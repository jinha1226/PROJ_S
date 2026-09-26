extends RefCounted
## The battle-test arena: the rosters the simulator measures and the walk to
## first contact that opens the fight.
const Abilities = preload("res://expedition/items/abilities.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const Stances = preload("res://expedition/ai/stances.gd")

## The battle-test arenas: the six rosters the simulator measures, plus the
## seat the player fills in by hand.
static var ARENA_PRESETS: Dictionary = load_arena_presets()

static func load_arena_presets() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/balance_experiments.json"))
	var result: Dictionary = {}
	for id in data.experiments.action_economy.arenas:
		var row: Dictionary = data.experiments.action_economy.arenas[id]
		result[id] = {"members":row.members.duplicate(true),"label":id}
	result["custom"] = {"members":[],"label":"직접 구성"}
	return result

## A throwaway floor battle: full health, every part available, the members'
## stances and slots set as asked, dropped into an arena the simulator also
## uses. The town session is never involved.
static func arena_test(s, p_seed: int, party_size: int, arena: Dictionary, members: Array):
	s.grant_test_loadout()
	for i in range(s.party.size()):
		var actor: Dictionary = s.party[i]
		var setup: Dictionary = members[i] if i < members.size() else {}
		var stance: String = str(setup.get("stance",actor.stance))
		if stance == "GUARDIAN" and party_size == 1: stance = "CHARGER"
		if stance in Stances.IDS: actor.stance = stance
		actor.equipped_abilities = ["",""]; actor.rules = []
		var parts: Array = setup.get("parts",["",""])
		for slot in range(2):
			var id: String = str(parts[slot]) if slot < parts.size() else ""
			if Abilities.has(id) and id not in actor.equipped_abilities:
				actor.equipped_abilities[slot] = id; actor.rules.append(Abilities.default_rule(id))
		Essences.normalize_actor(actor)
	var spec: Dictionary = preload("res://expedition/sim/encounter_arena.gd").DEFAULT_SPEC.duplicate(true)
	spec.members = arena.members.map(func(m): return {"species_id":m[0],"role":m[1]})
	var theme: Dictionary = preload("res://expedition/level/floor_generator.gd").theme("F1_RUINS")
	s.simulation_arena = true
	Floor.apply(s,theme,preload("res://expedition/sim/encounter_arena.gd").layout(spec,theme,p_seed))
	arena_contact(s)
	s.reset_battle_stats()
	s.auto.prev_threats = 0
	return s

## The sim's arena drops the party at the door, out of sight of a roster placed
## as far from it as the room allows. A battle test is the fight, not the walk
## to it: the party closes in before round one so the first stop is 전투 시작.
static func arena_contact(s) -> void:
	var state = s.floor_state
	for _step in range(40):
		state.observe(s)
		if not state.safe(s): break
		var moved := false
		for actor in s.party:
			var foes: Array = s.enemies.filter(func(e): return e.hp > 0)
			if foes.is_empty(): return
			foes.sort_custom(func(a,b): return s.distance(actor.pos,a.pos) < s.distance(actor.pos,b.pos))
			var goal: Vector2i = foes[0].pos
			var delta := Vector2i(signi(goal.x-actor.pos.x),signi(goal.y-actor.pos.y))
			for cell in [actor.pos+delta,actor.pos+Vector2i(delta.x,0),actor.pos+Vector2i(0,delta.y)]:
				if cell == actor.pos or not s.can_step(actor.pos,cell): continue
				actor.pos = cell; moved = true; break
		if not moved: break
	state.observe(s)
