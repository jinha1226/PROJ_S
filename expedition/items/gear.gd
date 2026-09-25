extends RefCounted
## What the party carries: weapons and armour, parts, supplies and the bag.
const Abilities = preload("res://expedition/items/abilities.gd")
const Body = preload("res://game/rebuilt/body_bridge.gd")
const CombatStats = preload("res://expedition/combat/combat_stats.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
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

static func equip_part(s, index: int, slot: int, id: String) -> bool:
	if index < 0 or index >= s.party.size() or not Essences.has(id): return false
	var actor: Dictionary = s.party[index]
	if not Essences.can_manage(s) or int(actor.hp) <= 0: return false
	Essences.sync_slots(actor)
	if slot < 0 or slot >= Essences.slot_count(actor) or id in actor.equipped_abilities: return false
	if int(actor.get("essences",{}).get(id,0)) <= 0 and not absorb_essence(s,index,id).is_empty(): return false
	if not Essences.equip(s,actor,slot,id): return false
	StatSheet.refresh_pools(s,actor)
	return true

## The slot empties; the essence stays absorbed and can be slotted again.
static func unequip_part(s, index: int, slot: int) -> bool:
	if index < 0 or index >= s.party.size(): return false
	var actor: Dictionary = s.party[index]
	if not Essences.unequip(s,actor,slot): return false
	StatSheet.refresh_pools(s,actor)
	return true

static func absorb_essence(s, index: int, id: String) -> String:
	if index < 0 or index >= s.party.size(): return "없는 인물"
	var actor: Dictionary = s.party[index]
	var reason: String = Essences.absorb(s,actor,id)
	if not reason.is_empty(): return reason
	StatSheet.refresh_pools(s,actor)
	s.message("%s · %s 흡수" % [actor.name,Essences.title(id)])
	return ""

static func choose_essence_spell(s, index: int, essence_id: String, spell_id: String) -> bool:
	if index < 0 or index >= s.party.size(): return false
	return Essences.choose_spell(s,s.party[index],essence_id,spell_id)

static func grant_part(s, id: String) -> void:
	if not Essences.has(id): return
	s.parts_bag[id] = int(s.parts_bag.get(id,0))+1
	s.message(Essences.title(id)+" 획득")

## Level XP to every hunter; the essence only to a hunt the party joined. The
## first of a species this run always leaves it, the rest one time in four.
static func roll_part(s, enemy: Dictionary, reward_actors: Variant = null) -> void:
	if not enemy.enemy or enemy.hp > 0 or enemy.get("part_rolled",false): return
	enemy.part_rolled = true
	var recipients: Array = s.alive() if reward_actors == null else reward_actors
	for actor in recipients:
		if s.gain_level_xp(actor,18+s.depth*8) > 0 and (actor in s.party or s.floor_state.visible.has(actor.pos)): s.message(actor.name+" · 레벨 %d" % actor.level)
	if not recipients.any(func(a): return a in s.party): return
	var id: String = str(enemy.get("part_id",""))
	if not Essences.has(id): return
	var species: String = Abilities.kind_key(enemy)
	var chance: int = Essences.drop_chance(s,species)
	s.essence_seen[species] = true
	if Hexaco.sample(s.seed_value,s.depth*10000+enemy.id,"essence",100) >= chance: return
	s.parts_bag[id] = int(s.parts_bag.get(id,0))+1
	s.battle_stats.drops[id] = int(s.battle_stats.drops.get(id,0))+1
	s.message(Essences.title(id)+" 획득")

## Playtest helper: one of every catalog part in the bag, so loadouts can be tried without farming.
static func grant_test_loadout(s) -> bool:
	if s.party.is_empty(): return false
	var added := 0
	for id in Essences.content.rows:
		if int(s.parts_bag.get(id,0)) > 0: continue
		s.parts_bag[id] = 1; added += 1
	s.message("시험 로드아웃 · 이미 전부 보유" if added == 0 else "시험 로드아웃 · 영혼석 %d종" % added)
	return true

static func reset_rules(s, index: int) -> void:
	var actor: Dictionary = s.party[index]
	actor.rules = Rules.defaults(); actor.basic_target = Rules.BASIC_TARGET_DEFAULT
	for id in actor.equipped_abilities:
		if Abilities.has(id): actor.rules.append(Abilities.default_rule(id))
