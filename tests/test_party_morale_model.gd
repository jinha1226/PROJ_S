extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Request = preload("res://sim/party_turn_request.gd")
const Model = preload("res://sim/party_morale_model.gd")
const PartyState = preload("res://sim/party_encounter_state.gd")


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


func test_authoritative_override_commits_one_morale_chain_and_restores_exactly() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var companion_id := int(state.active_party_member_ids[1])
	check(session.begin_turn(Action.hold(state.protagonist_id)).accepted,
		"journaled party turn begins")
	check(session.override_companion(companion_id, Action.hold(companion_id)).accepted,
		"journaled companion override is accepted")
	var event_start: int = world.events.size()
	var result: Dictionary = session.commit_turn()
	check(result.accepted, "override turn with morale commits: %s" % str(result.reason))
	var result_events: Array = world.events_since(event_start)
	var overrides: Array = result_events.filter(func(event):
		return event.type == "party.override_committed" and event.actor_id == companion_id)
	check_eq(overrides.size(), 1, "override source is canonical")
	var override_id: int = overrides[0].id if overrides.size() == 1 else -1
	var matching: Array = result_events.filter(func(event):
		return event.type == "party.morale_changed" and event.actor_id == companion_id \
			and str(override_id) in event.data.get("source_event_ids", []))
	check_eq(matching.size(), 1, "one companion morale row is emitted for the batch")
	if matching.size() == 1:
		var event = matching[0]
		var keys: Array = event.data.keys(); keys.sort()
		check_eq(keys, ["contagion_delta", "direct_delta", "mode_after", "mode_before",
			"recovery_delta", "ruleset_id", "schema_version", "source_event_ids",
			"stress_after", "stress_before", "trigger_codes"],
			"morale event metadata is exact")
		check_eq([event.data.stress_before, event.data.mode_before], [0, "NORMAL"],
			"override consumes the authoritative starting state once")
	var actor_morale: Array = result_events.filter(func(event):
		return event.type == "party.morale_changed" and event.actor_id == companion_id)
	if not actor_morale.is_empty():
		var latest = actor_morale.back()
		check_eq([state.member(companion_id).stress,
			state.member(companion_id).mental_mode],
			[latest.data.stress_after, latest.data.mode_after],
			"latest event and authority agree")
	check_eq(world.world_state_error(), "", "morale ledger validates before save")
	var restored = Session.new(9, 9)
	var loaded: Dictionary = restored.load_session_json(session.save_session_json())
	check(loaded.accepted, "morale save/load is accepted: %s" % str(loaded.get("reason")))
	if loaded.accepted:
		check_eq(restored.sim.snapshot(), session.sim.snapshot(),
			"stress and panic mode restore snapshot-exactly")
	return finish()


func test_authoritative_morale_crosses_and_persists_panic_threshold() -> bool:
	var session = _engaged()
	var state = session.sim.world.party_encounter
	var companion_id := int(state.active_party_member_ids[1])
	state.member(companion_id).stress = 840
	state.member(companion_id).mental_mode = "NORMAL"
	var request = Request.new(Action.hold(state.protagonist_id), [
		{"actor_id":companion_id, "action":Action.hold(companion_id)}])
	var result = session.sim.step_party_turn(session.sim.preview_party_turn(request))
	check(result.accepted, "threshold fixture commits: %s" % str(result.reason))
	var transitions: Array = result.events.filter(func(event):
		return event.type == "party.morale_changed" and event.actor_id == companion_id \
			and event.data.mode_before == "NORMAL" and event.data.mode_after == "PANIC")
	check_eq(transitions.size(), 1, "panic transition is emitted exactly once")
	check_eq(state.member(companion_id).mental_mode, "PANIC",
		"panic mode persists after the batch")
	return finish()


func test_morale_failure_rolls_back_events_state_and_mode() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var companion_id := int(state.active_party_member_ids[1])
	var request = Request.new(Action.hold(state.protagonist_id), [
		{"actor_id":companion_id, "action":Action.hold(companion_id)}])
	var plan = session.sim.preview_party_turn(request)
	var before: Dictionary = session.sim.snapshot()
	session.sim.party_coordinator.fail_point = "party_morale_event"
	var result = session.sim.step_party_turn(plan)
	check(not result.accepted and result.reason == "party_morale_failed",
		"morale fault rejects the complete party turn")
	check_eq(session.sim.snapshot(), before,
		"morale fault retracts stress, mode, events, time and RNG")
	return finish()


func test_schema_thirteen_migrates_to_normal_or_panicked_hysteresis_state() -> bool:
	var session = Session.new()
	var current: Dictionary = session.sim.world.party_encounter.to_dict()
	var legacy: Dictionary = current.duplicate(true)
	legacy.schema_version = PartyState.WEAPON_AUTHORITY_SCHEMA_VERSION
	for row in legacy.member_rows:
		row.erase("mental_mode")
	legacy.member_rows[0].stress = 849
	legacy.member_rows[1].stress = 850
	check_eq(PartyState.wire_error(legacy, session.sim.world.width,
		session.sim.world.height), "", "v13 member rows remain readable")
	var migrated = PartyState.from_dict(legacy)
	check_eq([migrated.member_rows[migrated.party_member_ids[0]].mental_mode,
		migrated.member_rows[migrated.party_member_ids[1]].mental_mode],
		["NORMAL", "PANIC"], "legacy stress deterministically seeds the new mode")
	check_eq(migrated.schema_version, PartyState.SCHEMA_VERSION,
		"legacy party state upgrades to v14")
	var malformed: Dictionary = current.duplicate(true)
	malformed.member_rows[0].erase("mental_mode")
	check_eq(PartyState.wire_error(malformed, session.sim.world.width,
		session.sim.world.height), "invalid_party_member_keys",
		"v14 requires persisted mental mode")
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
