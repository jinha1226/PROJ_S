extends RefCounted
## What the party carries: weapons and armour, parts, supplies and the bag.
const Abilities = preload("res://expedition/items/abilities.gd")
const Body = preload("res://game/rebuilt/body_bridge.gd")
const CombatStats = preload("res://expedition/combat/combat_stats.gd")
const Growth = preload("res://expedition/progression/growth.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Mastery = preload("res://expedition/progression/mastery.gd")
const Rules = preload("res://expedition/ai/tactic_rules.gd")

static func gear_slot(s, item: Dictionary) -> String:
	var id: String = str(item.get("type",""))
	if id == "shield": return "shield"
	if CombatStats.content.weapons.has(id): return "weapon"
	if CombatStats.content.armours.has(id): return "armour"
	if CombatStats.content.rings.has(id): return "ring"
	return ""

static func equip_gear(s, index: int, item: Dictionary) -> bool:
	if s.phase != "CAMP" or index < 0 or index >= s.party.size() or item not in s.gear_bag: return false
	var slot: String = s.gear_slot(item)
	if slot.is_empty(): return false
	var actor: Dictionary = s.party[index]
	if slot == "shield" and str(actor.gear.weapon.get("type","")) in ["bow","staff"]: return false
	if slot == "weapon" and str(item.type) in ["bow","staff"] and not actor.gear.shield.is_empty(): return false
	if slot == "armour" and actor.species_id == "elf" and str(item.type) == "plate": return false
	var previous: Dictionary = actor.gear[slot]
	if slot == "weapon" and not previous.is_empty():
		var old_axis := Mastery.weapon_axis(str(previous.type))
		var new_axis := Mastery.weapon_axis(str(item.type))
		if old_axis != new_axis and Mastery.rank(actor,old_axis) > 0: Mastery.catchup(actor,new_axis)
	s.gear_bag.erase(item)
	if not previous.is_empty(): s.gear_bag.append(previous)
	actor.gear[slot] = item.duplicate(true)
	return true

static func unequip_gear(s, index: int, slot: String) -> bool:
	if s.phase != "CAMP" or index < 0 or index >= s.party.size() or slot not in ["weapon","armour","shield","ring"]: return false
	var actor: Dictionary = s.party[index]
	if actor.gear[slot].is_empty(): return false
	s.gear_bag.append(actor.gear[slot])
	actor.gear[slot] = {}
	return true

static func grant_gear(s, item: Dictionary) -> void:
	if item.is_empty(): return
	s.gear_bag.append(item.duplicate(true))
	s.message(str(item.get("type","장비"))+" 획득")

## Town only: a part leaves the bag for a slot; the slot's old part returns to the bag.
static func equip_part(s, index: int, slot: int, id: String) -> bool:
	if s.phase != "CAMP" or index < 0 or index >= s.party.size() or slot < 0 or slot >= 2: return false
	var actor: Dictionary = s.party[index]
	if actor.hp <= 0 or not Abilities.DEFINITIONS.has(id) or int(s.parts_bag.get(id,0)) <= 0: return false
	if id in actor.equipped_abilities: return false
	var old: String = str(actor.equipped_abilities[slot])
	if not old.is_empty(): s.unequip_part(index,slot)
	s.parts_bag[id] -= 1
	actor.equipped_abilities[slot] = id
	actor.reservation = {}
	if not actor.rules.any(func(r): return r.skill == id): actor.rules.append(Abilities.default_rule(id))
	return true

static func unequip_part(s, index: int, slot: int) -> bool:
	if s.phase != "CAMP" or index < 0 or index >= s.party.size() or slot < 0 or slot >= 2: return false
	var actor: Dictionary = s.party[index]
	var old: String = str(actor.equipped_abilities[slot])
	if actor.hp <= 0 or old.is_empty(): return false
	actor.equipped_abilities[slot] = ""
	s.parts_bag[old] = int(s.parts_bag.get(old,0))+1
	actor.rules = actor.rules.filter(func(r): return r.skill != old)
	actor.reservation = {}
	return true

static func grant_part(s, id: String) -> void:
	if not Abilities.DEFINITIONS.has(id): return
	s.parts_bag[id] = int(s.parts_bag.get(id,0))+1
	s.message(Abilities.DEFINITIONS[id].item+" 획득")

static func roll_part(s, enemy: Dictionary) -> void:
	if not enemy.enemy or enemy.hp > 0 or enemy.get("part_rolled",false): return
	enemy.part_rolled = true
	for actor in s.alive():
		if s.manual_mode:
			if s.gain_level_xp(actor,18+s.depth*8) > 0: s.message(actor.name+" · 레벨 %d" % actor.level)
		elif Growth.gain(actor,25) > 0: s.message(actor.name+" · 레벨 %d" % actor.growth.level)
	var id: String = str(enemy.get("part_id",""))
	if not Abilities.DEFINITIONS.has(id): return
	var chance: int = Abilities.DROP_PERCENT
	if Hexaco.sample(s.seed_value,s.depth*10000+enemy.id,"essence",100) >= chance: return
	s.parts_bag[id] = int(s.parts_bag.get(id,0))+1
	s.battle_stats.drops[id] = int(s.battle_stats.drops.get(id,0))+1
	s.message(Abilities.DEFINITIONS[id].item+" 획득")

## Playtest helper: one of every catalog part in the bag, so loadouts can be tried without farming.
static func grant_test_loadout(s) -> bool:
	if s.party.is_empty(): return false
	var added := 0
	for id in Abilities.DEFINITIONS:
		if int(s.parts_bag.get(id,0)) > 0: continue
		s.parts_bag[id] = 1; added += 1
	s.message("시험 로드아웃 · 이미 전부 보유" if added == 0 else "시험 로드아웃 · 파츠 %d종 지급 — 파츠 탭에서 장착하세요." % added)
	return true

static func spend_growth(s, index: int, id: String, stat: bool = false) -> bool:
	if not s.safe_management() or index < 0 or index >= s.party.size() or s.party[index].hp <= 0: return false
	return Growth.spend(s.party[index],id,stat)

static func reset_rules(s, index: int) -> void:
	var actor: Dictionary = s.party[index]
	actor.rules = Rules.defaults(); actor.basic_target = Rules.BASIC_TARGET_DEFAULT
	for id in actor.equipped_abilities:
		if Abilities.DEFINITIONS.has(id): actor.rules.append(Abilities.default_rule(id))
