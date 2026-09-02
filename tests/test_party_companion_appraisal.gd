extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Blackboard = preload("res://sim/party_squad_blackboard.gd")
const Appraisal = preload("res://sim/party_companion_appraisal.gd")
const Registry = preload("res://sim/decision_ruleset_registry.gd")


func _engaged():
	var session = Session.new()
	var state = session.sim.world.party_encounter
	session.commit_exploration(Command.wait(state.protagonist_id))
	session.preview_deployment("WEDGE", state.party_member_ids.slice(1))
	check(session.commit_deployment().accepted, "fixture deploys the party")
	return session


func test_appraisal_fills_every_party_input_with_integers() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var companion: int = state.active_party_member_ids[1]
	var board: Dictionary = Blackboard.build(world, Action.hold(state.protagonist_id))
	var appraisal: Dictionary = Appraisal.appraise(world, companion, board)
	check_eq(appraisal.mode, "NORMAL", "calm start is NORMAL")
	var inputs: Dictionary = Appraisal.inputs_for(appraisal,
		state.member(companion).personality_profile, board.focus_target_id, board, companion)
	for input_id in Registry.party_inputs():
		check(inputs.has(input_id) and inputs[input_id] is int,
			"input %s present and int" % input_id)
		check(int(inputs[input_id]) >= 0 and int(inputs[input_id]) <= 1000,
			"input %s normalized" % input_id)
	check_eq(inputs["context.focus_alignment"], 1000,
		"focus alignment set for the focus target")
	return finish()


func test_wounded_stressed_companion_enters_panic_and_sees_ally_pressure() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var hero: int = state.protagonist_id
	var companion: int = state.active_party_member_ids[1]
	var enemy: int = state.enemy_ids[0]
	world.entities[enemy].position = world.entities[hero].position + Vector2i.RIGHT
	world.entities[hero].health = maxi(1, int(world.entities[hero].max_health / 4))
	var board: Dictionary = Blackboard.build(world, null)
	var calm: Dictionary = Appraisal.appraise(world, companion, board)
	check_eq(calm.ally_targeted, 1000,
		"adjacent enemy on the wounded protagonist reads as ally targeted")
	check_eq(calm.ally_id, hero, "the threatened ally is the protagonist")
	check(calm.ally_hp_loss >= 700, "ally hp loss is disclosed")
	world.entities[companion].health = maxi(1,
		int(world.entities[companion].max_health / 5))
	state.member(companion).stress = 900
	state.member(companion).mental_mode = "PANIC"
	var panicked: Dictionary = Appraisal.appraise(world, companion, board)
	check_eq(panicked.mode, "PANIC", "stored hysteresis mode drives the action set")
	check(panicked.panic_pressure > calm.panic_pressure, "panic pressure rises with stress")
	return finish()
