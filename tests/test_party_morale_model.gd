extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Model = preload("res://sim/party_morale_model.gd")


func test_morale_model_is_exact_pure_and_order_independent() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var companion_id := int(state.active_party_member_ids[1])
	var enemy_id := int(state.enemy_ids[0])
	var events := [
		{"id":12, "type":"entity.downed", "target_id":companion_id, "magnitude":0},
		{"id":11, "type":"combat.physical_damage", "target_id":companion_id,
			"magnitude":20},
		{"id":13, "type":"entity.died", "target_id":enemy_id, "magnitude":0},
	]
	var before := JSON.stringify(world.snapshot())
	var first: Dictionary = Model.evaluate(world, events)
	var reversed := events.duplicate(); reversed.reverse()
	check_eq(first, Model.evaluate(world, reversed), "event input order cannot change morale")
	var keys: Array = first.keys(); keys.sort()
	check_eq(keys, ["member_rows", "ruleset_id", "schema_version"],
		"morale projection has exact keys")
	check_eq(first.ruleset_id, "party-morale-contagion-v1", "ruleset id is stable")
	check_eq(JSON.stringify(world.snapshot()), before,
		"morale evaluation mutates no world event or RNG")
	return finish()


func test_direct_shock_spreads_and_composure_reduces_contagion() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var source_id := int(state.active_party_member_ids[1])
	var calm_id := int(state.active_party_member_ids[2])
	_set_facet(state.member(calm_id).personality_profile, "composure", 1000)
	var events := [{"id":1, "type":"combat.physical_damage",
		"target_id":source_id, "magnitude":30}]
	var calm: Dictionary = _row(Model.evaluate(world, events), calm_id)
	_set_facet(state.member(calm_id).personality_profile, "composure", 0)
	var reactive: Dictionary = _row(Model.evaluate(world, events), calm_id)
	check(int(calm.contagion_delta) > 0, "nearby ally receives fear contagion")
	check(int(reactive.contagion_delta) > int(calm.contagion_delta),
		"lower composure receives more contagion")
	check(int(reactive.contagion_delta) <= Model.MAX_CONTAGION,
		"contagion is batch capped")
	var source: Dictionary = _row(Model.evaluate(world, events), source_id)
	check_eq(source.direct_delta, 120, "self damage uses the fixed direct shock formula")
	return finish()


func test_panic_hysteresis_and_safe_recovery_are_explicit() -> bool:
	check_eq(Model.next_mode("NORMAL", 849), "NORMAL", "normal stays below enter threshold")
	check_eq(Model.next_mode("NORMAL", 850), "PANIC", "normal enters panic at 850")
	check_eq(Model.next_mode("PANIC", 651), "PANIC", "panic persists above exit threshold")
	check_eq(Model.next_mode("PANIC", 650), "NORMAL", "panic exits at 650")
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	for enemy_id in state.enemy_ids:
		world.combatant_states[enemy_id].life_state = "DEAD"
		world.entities[enemy_id].health = 0
	var companion_id := int(state.active_party_member_ids[1])
	state.member(companion_id).stress = 500
	var row: Dictionary = _row(Model.evaluate(world, [], {companion_id:"NORMAL"}),
		companion_id)
	check_eq([row.recovery_delta, row.stress_after, row.mode_after],
		[-40, 460, "NORMAL"], "safe batch recovers stress without changing mode")
	return finish()


func _engaged():
	var session = Session.new()
	var state = session.sim.world.party_encounter
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
		"morale fixture reaches contact")
	session.preview_deployment("WEDGE", session.available_companion_ids())
	check(session.commit_deployment().accepted, "morale fixture deploys")
	return session


func _row(projection: Dictionary, entity_id: int) -> Dictionary:
	for row in projection.member_rows:
		if int(row.entity_id) == entity_id:
			return row
	return {}


func _set_facet(profile, facet_id: String, value: int) -> void:
	for row in profile.facet_rows:
		if str(row.facet_id) == facet_id:
			row.base_value = value
			return
	profile.facet_rows.append({"facet_id":facet_id, "base_value":value})
	profile.facet_rows.sort_custom(func(a: Dictionary, b: Dictionary):
		return str(a.facet_id) < str(b.facet_id))
