extends RefCounted
## Read-only item rules shared by statistics, effects, loot and UI.
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))
const SLOTS := ["weapon","offhand","armour","ring1","ring2"]
const SLOT_NAMES := {"weapon":"무기","offhand":"왼손","armour":"갑옷","ring1":"반지 1","ring2":"반지 2"}
const PROP_NAMES := {"accuracy":"명중","crit_chance":"치명타 확률","crit_damage":"치명타 피해","res_fire":"화염 저항","res_ice":"냉기 저항","res_air":"전격 저항","res_poison":"독 저항","res_will":"의지 저항","wound_resist.bleed":"출혈 저항","wound_resist.fracture":"골절 저항","wound_resist.exposed":"급소 노출 저항","atk":"공격력","ac":"방어","sh":"막기","ev":"회피","hp":"최대 HP","mp":"최대 MP","spell":"주문력","speed":"행동 속도","taken_percent":"받는 피해","heal_taken_percent":"받는 회복","max_hp_percent":"최대 HP","noise":"소음"}

static func worn(actor: Dictionary) -> Dictionary:
	var gear: Dictionary = actor.get_or_add("gear",{})
	for pair in [["shield","offhand"],["ring","ring1"]]:
		if gear.has(pair[0]):
			if gear.get(pair[1],{}).is_empty(): gear[pair[1]] = gear[pair[0]]
			gear.erase(pair[0])
	for slot in SLOTS:
		if not gear.has(slot): gear[slot] = {}
	return gear

static func slot(item: Dictionary) -> String:
	var id: String = str(item.get("type",""))
	if content.get("offhands",{}).has(id) or id == "shield": return "offhand"
	if content.weapons.has(id): return "weapon"
	if content.armours.has(id): return "armour"
	if content.rings.has(id): return "ring1"
	return ""

static func definition(item: Dictionary) -> Dictionary:
	match slot(item):
		"weapon": return content.weapons.get(str(item.type),{})
		"offhand": return content.get("offhands",{}).get(str(item.type),{})
		"armour": return content.armours.get(str(item.type),{})
		"ring1": return content.rings.get(str(item.type),{})
	return {}

static func hands(item: Dictionary) -> int:
	return int(definition(item).get("hands",1))

static func title(item: Dictionary) -> String:
	if item.is_empty(): return "없음"
	var name: String = str(item.get("name",definition(item).get("name",item.get("type","장비"))))
	var enchant: int = int(item.get("enchant",0))
	return name+(" +%d" % enchant if enchant > 0 else "")

static func colour(item: Dictionary) -> Color:
	return Color("e4ba54") if item.get("tier","") == "unrand" else Color("74b7e8") if item.get("tier","") == "randart" else Color("e0d4bc")

static func automatic(actor: Dictionary) -> bool:
	return str(actor.get("combat_profile","legacy")) == "attack_wait_v1" and not bool(actor.get("enemy",false))

static func property(prop: Dictionary, actor: Dictionary) -> Dictionary:
	if not automatic(actor): return prop
	if str(prop.get("key","")) == "mp": return {"key":"hp","value":int(prop.value)*2}
	if str(prop.get("key","")) == "spell": return {"key":"atk","value":int(prop.value)}
	return prop

static func numeric(item: Dictionary, key: String, actor: Dictionary = {}) -> int:
	var total := 0
	for raw in item.get("props",[]):
		var prop := property(raw,actor)
		if str(prop.get("key","")) == key: total += int(prop.value)
	var flaw: Dictionary = property(item.get("flaw",{}),actor)
	if str(flaw.get("key","")) == key: total += int(flaw.get("value",0))
	return total

static func bonus(actor: Dictionary, key: String) -> int:
	var total := 0
	for item in worn(actor).values(): total += numeric(item,key,actor)
	return total

static func effects(actor: Dictionary) -> Array:
	var result: Array = []
	for slot_id in SLOTS:
		var item: Dictionary = worn(actor)[slot_id]
		for id in [item.get("affix",""),item.get("cost_effect","")]:
			if not str(id).is_empty() and id not in result: result.append(id)
	return result

static var effect_text: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/stone_effects.json")).get("effects",{})

static func effect_row(row: Dictionary, actor: Dictionary) -> Dictionary:
	if not automatic(actor) or not row.has("mobile_rules"): return row
	var mapped := row.duplicate()
	mapped.rules = row.mobile_rules; mapped.text = row.get("mobile_text",row.get("text",""))
	return mapped

static func description(item: Dictionary, actor: Dictionary = {}) -> String:
	var lines: PackedStringArray = []
	if automatic(actor):
		var def := definition(item)
		var attack: int = 4 if def.get("trait","") == "focus" else int(def.get("spell",0))
		if def.get("stat","") == "power": attack += int(def.value)
		if attack != 0: lines.append("공격력 %+d" % attack)
	for raw in item.get("props",[]):
		var prop := property(raw,actor)
		lines.append("%s %+d" % [PROP_NAMES.get(str(prop.key),str(prop.key)),int(prop.value)])
	var effects: Dictionary = effect_text
	for id in [item.get("affix",""),item.get("cost_effect","")]:
		if effects.has(id): lines.append(str(effect_row(effects[id],actor).text))
	var flaw: Dictionary = property(item.get("flaw",{}),actor)
	if not flaw.is_empty(): lines.append("단점 · %s %+d" % [PROP_NAMES.get(str(flaw.key),str(flaw.key)),int(flaw.value)])
	return "\n".join(lines)

## A noisy attack wakes sleepers even when the blow misses.
static func attack_noise(s, actor: Dictionary) -> void:
	var radius: int = bonus(actor,"noise")
	if radius <= 0 or not actor.has("pos"): return
	for foe in s.enemies:
		if foe.hp > 0 and s.side_of(foe) != s.side_of(actor) and maxi(absi(foe.pos.x-actor.pos.x),absi(foe.pos.y-actor.pos.y)) <= radius:
			foe.sleep_until = 0; foe.alert = true
