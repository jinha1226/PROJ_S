extends RefCounted
## Interactive loot is queued after awarding it. Decisions happen between
## committed actions, never inside the scheduler or the death animation.
const Essences = preload("res://expedition/progression/essences.gd")
const Mobile = preload("res://expedition/progression/attack_wait.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const STATUS_NAMES := {"burn":"화상", "poison":"중독", "slow":"둔화", "freeze":"빙결", "charge":"전하", "bleed":"출혈", "confuse":"혼란", "weak":"약화", "wet":"젖음", "death_mark":"사령 낙인", "exposed":"약점", "blessing":"축복"}

static func enqueue(s, stone: String) -> void:
	stone = Essences.canonical(stone)
	if not s.interactive_stone_drops or stone.is_empty(): return
	s.stone_drop_serial += 1
	s.pending_stone_drops.append({"token":s.stone_drop_serial,"stone":stone})

static func unavailable(actor: Dictionary, stone: String) -> String:
	if int(actor.get("hp",0)) <= 0: return "쓰러짐"
	if Essences.absorbed(actor,stone): return "이미 흡수함"
	if Essences.free_slot(actor) < 0: return "빈 슬롯 없음"
	return ""

## index -1 keeps the awarded stone in the bag, -2 leaves this one behind.
## Only the exact pending drop may bypass the ordinary safe-area restriction.
static func resolve(s, token: int, index: int) -> String:
	if s.pending_stone_drops.is_empty() or int(s.pending_stone_drops[0].token) != token: return "지난 선택"
	var stone: String = str(s.pending_stone_drops[0].stone)
	if index < -2 or index >= s.party.size(): return "없는 인물"
	if index != -1 and int(s.parts_bag.get(stone,0)) <= 0: return "가방에 없음"
	if index >= 0:
		var actor: Dictionary = s.party[index]
		if s.phase in ["DEFEAT","VICTORY"]: return "원정 종료"
		var reason := unavailable(actor,stone)
		if not reason.is_empty(): return reason
		reason = Essences.bind(actor,stone)
		if not reason.is_empty(): return reason
		s.parts_bag[stone] = int(s.parts_bag[stone])-1
		s.Codex.note_absorb(s,stone)
		StatSheet.refresh_pools(s,actor)
		s.message("%s · %s 흡수" % [actor.name,Essences.title(stone)])
	elif index == -2:
		s.parts_bag[stone] = int(s.parts_bag[stone])-1
		s.message(Essences.title(stone)+" 두고 감")
	s.pending_stone_drops.pop_front()
	return ""

## Static build potential, not a proc probability: all prerequisite producers
## must themselves be reachable. Two mutually dependent chains cannot seed
## each other. This also respects sealed stones and distinct combat profiles.
static func fit(actor: Dictionary, stone: String) -> Dictionary:
	if not Mobile.active(actor):
		var preview: Dictionary = actor.duplicate(true)
		preview.equipped_abilities = actor.get("equipped_abilities",[]).duplicate()
		preview.equipped_abilities.append(stone)
		for tag in [Essences.role(stone),Essences.element(stone)]:
			if str(tag).is_empty(): continue
			if TagSets.level(preview,str(tag)) > TagSets.level(actor,str(tag)):
				var names: Dictionary = Essences.ROLES if Essences.ROLES.has(tag) else Essences.ELEMENTS
				return {"kind":"linked","text":"조합 강화 · "+str(names.get(tag,tag))}
		return {"kind":"neutral","text":"같은 계열" if Essences.equipped(actor).any(func(id): return Essences.role(str(id)) == Essences.role(stone)) else "새 계열"}
	var id := Mobile.effect_id(stone)
	var owned := Mobile.effects(actor)
	if id in owned: return {"kind":"duplicate","text":"효과 중복"}
	var before := capabilities(actor,owned)
	var after_ids: Array = owned.duplicate(); after_ids.append(id)
	var after := capabilities(actor,after_ids)
	var row: Dictionary = Mobile.row(stone)
	var missing := unmet(actor,row,after)
	if not missing.is_empty(): return {"kind":"missing","text":"준비 필요 · "+" · ".join(missing)}
	var conditions := unmet(actor,row,{"statuses":[],"self":[],"pet":false})
	if not conditions.is_empty(): return {"kind":"linked","text":"연계 가능 · "+str(row.get("name",""))}
	for existing in owned:
		var other: Dictionary = Mobile.data.effects[existing]
		if not unmet(actor,other,before).is_empty() and unmet(actor,other,after).is_empty():
			return {"kind":"linked","text":"연계 가능 · "+str(other.get("name",""))}
	for existing in owned:
		var other: Dictionary = Mobile.data.effects[existing]
		var remaining := unmet(actor,other,after)
		if remaining.size() < unmet(actor,other,before).size():
			return {"kind":"missing","text":"연계 보완 · "+" · ".join(remaining)+" 필요"}
	return {"kind":"neutral","text":"독립 효과"}

static func unmet(actor: Dictionary, row: Dictionary, caps: Dictionary) -> Array:
	var result: Array = []
	for status in row.get("requires",[]):
		if status not in caps.statuses: result.append(str(STATUS_NAMES.get(status,status)))
	for status in row.get("self_requires",[]):
		if status not in caps.self: result.append(str(STATUS_NAMES.get(status,status)))
	if row.get("needs_pet",false) and not caps.pet: result.append("소환수")
	return result

static func capabilities(actor: Dictionary, ids: Array) -> Dictionary:
	var caps := {"statuses":[],"self":[],"pet":false}
	# A chain can produce another chain's input, but only after a valid seed.
	for _pass in range(ids.size()+1):
		for id in ids:
			var row: Dictionary = Mobile.data.effects.get(id,{})
			if row.is_empty() or not unmet(actor,row,caps).is_empty(): continue
			var op: String = str(row.op)
			if row.has("status") and op in ["status","status_area","spread","attack_prep","pet_burst","prepare"] and str(row.status) not in caps.statuses: caps.statuses.append(str(row.status))
			if op == "bless" and "blessing" not in caps.self: caps.self.append("blessing")
			if op == "summon": caps.pet = true
	return caps
