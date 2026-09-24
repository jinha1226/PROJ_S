extends RefCounted
## Standing orders: knobs, stances, cover, tactics, the rule editor and the
## marching order.
const Knobs = preload("res://expedition/ai/knobs.gd")
const Rules = preload("res://expedition/ai/tactic_rules.gd")
const Stances = preload("res://expedition/ai/stances.gd")

## Town and safe ground only: a standing order is not rewritten mid-fight.
## Whether it conflicts with the personality is judged when it matters, not stored.
static func set_knob(s, index: int, key: String, value: int) -> bool:
	if not s.safe_management() or s.in_combat(): return false
	if index < 0 or index >= s.party.size() or s.party[index].hp <= 0: return false
	if not Knobs.RANGE.has(key): return false
	var bounds: Array = Knobs.RANGE[key]
	if value < int(bounds[0]) or value > int(bounds[1]): return false
	s.party[index].knobs[key] = value
	return true

## The stance is a standing order like a knob: set on safe ground only. A lone
## member has nobody to cover, so it cannot be a guardian.
static func set_stance(s, index: int, stance: String) -> bool:
	if not s.safe_management() or s.in_combat(): return false
	if index < 0 or index >= s.party.size() or s.party[index].hp <= 0 or stance not in Stances.IDS: return false
	if stance == "GUARDIAN" and s.party.size() == 1: return false
	s.party[index].stance = stance
	return true

## Who a guardian covers: another living member, or -1 to let it pick.
static func set_protect(s, index: int, target_index: int) -> bool:
	if not s.safe_management() or s.in_combat(): return false
	if index < 0 or index >= s.party.size() or s.party[index].hp <= 0: return false
	if target_index != -1 and (target_index == index or target_index < 0 or target_index >= s.party.size() or s.party[target_index].hp <= 0): return false
	s.party[index].protect_id = target_index
	return true

static func set_tactic(s, index: int, skill: String, policy: String) -> bool:
	if index < 0 or index >= s.party.size(): return false
	var allowed: Array = ["PROTECT","OFFENSE","MANUAL"] if skill == "PUSH" else ["DANGER","LOW_HP","MANUAL"] if skill == "GUARD" else []
	if policy not in allowed: return false
	s.party[index].tactics[skill] = policy
	# Compatibility for previous callers; the live editor uses common rules.
	for rule in s.party[index].rules:
		if rule.skill == skill:
			rule.enabled = policy != "MANUAL"
			# 엄호 has one condition, so every legacy GUARD policy maps onto it;
			# only the enabled flag still separates MANUAL from the rest.
			if skill == "GUARD": rule.when = "ALLY_LETHAL"; rule.target = "ALLY"
			else: rule.when = "CHARGING" if policy == "PROTECT" else "HP" if policy == "LOW_HP" else "DANGER" if policy == "DANGER" else "ALWAYS"
			rule.subject = "SELF"
	return true

static func set_basic_target(s, index: int, target: String) -> bool:
	if index < 0 or index >= s.party.size() or target not in Rules.BASIC_TARGETS: return false
	s.party[index].basic_target = target
	return true

static func update_rule(s, index: int, position: int, field: String, value: Variant) -> bool:
	if index < 0 or index >= s.party.size() or position < 0 or position >= s.party[index].rules.size(): return false
	if field not in ["enabled","target","when","subject","threshold","comparison","status"]: return false
	var updated: Dictionary = s.party[index].rules[position].duplicate(true)
	updated[field] = value
	if not Rules.valid(updated): return false
	s.party[index].rules[position] = updated
	return true

static func reorder_rule(s, index: int, position: int, direction: int) -> bool:
	if index < 0 or index >= s.party.size() or direction not in [-1,1]: return false
	var rows: Array = s.party[index].rules
	var destination := position+direction
	if position < 0 or position >= rows.size() or destination < 0 or destination >= rows.size(): return false
	var rule = rows[position]; rows[position] = rows[destination]; rows[destination] = rule
	return true

## Two members trade cells and places in the marching order. Only while the
## run is stopped for a battle start, once per battle.
static func can_swap_formation(s) -> bool:
	return s.in_combat() and s.auto.last_stop.reason == "BATTLE_START" and int(s.auto.last_stop.round) == s.round_number \
		and int(s.auto.get("swapped_round",-1)) != s.round_number and s.alive().size() >= 2

static func swap_formation(s, a: int, b: int) -> bool:
	if not s.can_swap_formation(): return false
	if a == b or a < 0 or b < 0 or a >= s.party.size() or b >= s.party.size() or s.party[a].hp <= 0 or s.party[b].hp <= 0: return false
	var pa: Vector2i = s.party[a].pos; s.party[a].pos = s.party[b].pos; s.party[b].pos = pa
	var ia: int = s.formation.find(a); var ib: int = s.formation.find(b)
	s.formation[ia] = b; s.formation[ib] = a
	s.auto.swapped_round = s.round_number
	s.floor_state.observe(s)
	s.message("%s ↔ %s 자리 교환" % [s.party[a].name,s.party[b].name])
	return true
