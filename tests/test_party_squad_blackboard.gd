extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Blackboard = preload("res://sim/party_squad_blackboard.gd")


func _engaged():
	var session = Session.new()
	var state = session.sim.world.party_encounter
	session.commit_exploration(Command.wait(state.protagonist_id))
	session.preview_deployment("WEDGE", state.party_member_ids.slice(1))
	check(session.commit_deployment().accepted, "fixture deploys the party")
	return session


func test_blackboard_shape_focus_and_purity() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var before := JSON.stringify(world.snapshot())
	var board: Dictionary = Blackboard.build(world, Action.hold(state.protagonist_id))
	var keys: Array = board.keys()
	keys.sort()
	check_eq(keys, ["active_enemy_ids", "ally_pressure", "claims", "deployed_ids",
		"focus_target_id", "most_threatened_ally_id", "party_command",
		"schema_version", "threat_table"],
		"exact keys")
	check_eq(board.deployed_ids, state.active_party_member_ids,
		"deployed ids are the active roster in order")
	check(board.focus_target_id in state.enemy_ids, "focus is a real enemy")
	check_eq(board, Blackboard.build(world, Action.hold(state.protagonist_id)), "deterministic")
	check_eq(JSON.stringify(world.snapshot()), before, "build mutates nothing")
	return finish()


func test_protagonist_melee_target_becomes_focus_and_claims_cap_at_two() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var enemy: int = state.enemy_ids[0]
	var board: Dictionary = Blackboard.build(world,
		Action.melee(state.protagonist_id, enemy))
	check_eq(board.focus_target_id, enemy, "protagonist melee target is the squad focus")
	var claimed_on_focus := 0
	for companion_id in board.claims:
		if int(board.claims[companion_id]) == enemy:
			claimed_on_focus += 1
	check(claimed_on_focus <= 2 or state.enemy_ids.size() == 1,
		"at most two companions are claimed onto one enemy unless it is the only one")
	return finish()


func test_committed_protagonist_target_stays_focus_during_later_hold() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var hero: int = state.protagonist_id
	var enemy: int = state.enemy_ids[0]
	var attack_event = world.emit_event("action.melee_attack", hero, enemy,
		world.entities[enemy].position, 1)
	check(attack_event != null, "canonical protagonist attack event is recorded")
	var board: Dictionary = Blackboard.build(world, Action.hold(hero))
	check_eq(board.focus_target_id, enemy,
		"later HOLD retains the last living protagonist attack target")
	return finish()


func test_most_threatened_ally_uses_pressure_then_lowest_hp() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var hero: int = state.protagonist_id
	var enemy: int = state.enemy_ids[0]
	world.entities[enemy].position = world.entities[hero].position + Vector2i.RIGHT
	world.entities[hero].health = maxi(1, int(world.entities[hero].max_health / 3))
	var board: Dictionary = Blackboard.build(world, null)
	check_eq(board.most_threatened_ally_id, hero,
		"adjacent, wounded protagonist is most threatened")
	check_eq(board.ally_pressure[hero].adjacent_enemy_ids, [enemy],
		"pressure lists the adjacent enemy")
	check_eq(board.threat_table[enemy].adjacent_party_ids, [hero],
		"threat table lists the adjacent ally")
	return finish()
