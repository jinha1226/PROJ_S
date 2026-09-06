extends "res://tests/test_case.gd"

const Rules = preload("res://sim/party_ration_rules.gd")
const Session = preload("res://playtest/party_playtest_session.gd")
const PartyState = preload("res://sim/party_encounter_state.gd")
const WorldState = preload("res://sim/world_state.gd")
const Command = preload("res://sim/sim_command.gd")


func test_rules_load_and_bands_are_derived_from_content() -> bool:
	check_eq(Rules.registry_error(), "", "hunger_rules.json validates")
	var rules: Dictionary = Rules.rules()
	check_eq(int(rules.ration_max), 300, "ration_max read from content")
	check_eq(Rules.ration_max_milli(), 300000, "max is stored in milli")
	check_eq(Rules.band(300000), "FED", "full gauge is FED")
	check_eq(Rules.band(100000), "FED", "exactly hungry_below is still FED")
	check_eq(Rules.band(99999), "HUNGRY", "below hungry_below is HUNGRY")
	check_eq(Rules.band(0), "STARVING", "zero is STARVING")
	check_eq(Rules.drain_per_interval_milli(1), 1000, "solo drains base rate")
	check_eq(Rules.drain_per_interval_milli(3), 2000, "each extra member adds 500 milli")
	check_eq(Rules.drain_per_interval_milli(0), 1000, "zero members clamps to one")
	return finish()


func test_state_persists_ration_and_legacy_saves_load_full() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	check_eq(int(state.schema_version), 22, "fresh state uses ration schema")
	check_eq(int(state.ration_milli), Rules.ration_max_milli(), "fresh run starts full")
	check_eq(int(state.ration_processed_at), int(session.sim.world.world_time),
		"fresh run anchors the drain clock at creation time")
	state.ration_milli = 123456
	var wire: Dictionary = state.to_dict()
	check(wire.has("ration_milli") and wire.has("ration_processed_at"),
		"v22 wire carries both ration keys")
	check_eq(PartyState.wire_error(wire, session.sim.world.width, session.sim.world.height), "",
		"v22 wire validates")
	var restored = PartyState.from_dict(wire)
	check_eq(int(restored.ration_milli), 123456, "round trip keeps the gauge")
	check_eq(int(restored.ration_processed_at), int(state.ration_processed_at),
		"round trip keeps the drain clock")
	var legacy: Dictionary = wire.duplicate(true)
	legacy.erase("ration_milli"); legacy.erase("ration_processed_at")
	legacy["schema_version"] = 21
	check_eq(PartyState.wire_error(legacy, session.sim.world.width, session.sim.world.height), "",
		"v21 wire without ration keys still validates")
	var migrated = PartyState.from_dict(legacy)
	check_eq(int(migrated.ration_milli), Rules.ration_max_milli(), "legacy save loads full")
	check_eq(int(migrated.schema_version), 22, "legacy save upgrades to v22")
	var broken: Dictionary = wire.duplicate(true)
	broken["ration_milli"] = Rules.ration_max_milli() + 1
	check(not PartyState.wire_error(broken, session.sim.world.width, session.sim.world.height).is_empty(),
		"gauge above max is rejected")
	var negative: Dictionary = wire.duplicate(true)
	negative["ration_milli"] = -1
	check(not PartyState.wire_error(negative, session.sim.world.width, session.sim.world.height).is_empty(),
		"negative gauge is rejected")
	var missing: Dictionary = wire.duplicate(true)
	missing.erase("ration_milli")
	check(not PartyState.wire_error(missing, session.sim.world.width, session.sim.world.height).is_empty(),
		"v22 wire without ration keys is rejected")
	check_eq(session.sim.world.world_state_error(), "", "world with ration state stays canonical")
	return finish()


func test_legacy_snapshot_reanchors_ration_clock() -> bool:
	var session = Session.new()
	var hero_id: int = int(session.sim.world.party_encounter.protagonist_id)
	check(bool(session.commit_exploration(Command.wait(hero_id)).get("accepted", false)),
		"waiting advances the run before the save")
	check(int(session.sim.world.world_time) > 0, "waiting advanced world time before the save")
	var snapshot: Dictionary = session.sim.snapshot()
	var legacy_party: Dictionary = snapshot.party_encounter.duplicate(true)
	legacy_party.erase("ration_milli"); legacy_party.erase("ration_processed_at")
	legacy_party["schema_version"] = 21
	snapshot["party_encounter"] = legacy_party
	var restored = WorldState.from_snapshot(snapshot)
	check(restored != null, "legacy v21 snapshot still restores")
	if restored == null: return finish()
	check_eq(int(restored.party_encounter.ration_milli), Rules.ration_max_milli(),
		"legacy restore loads a full gauge")
	check_eq(int(restored.party_encounter.ration_processed_at), int(restored.world_time),
		"legacy restore anchors the drain clock at the restored world time")
	check_eq(restored.world_state_error(), "", "re-anchored legacy world stays canonical")
	return finish()


func test_legacy_session_save_migrates_with_a_full_anchored_gauge() -> bool:
	var source = Session.new()
	var hero_id: int = int(source.sim.world.party_encounter.protagonist_id)
	check(bool(source.commit_exploration(Command.wait(hero_id)).get("accepted", false)),
		"waiting advances the run before the save")
	var encoded: Dictionary = JSON.parse_string(source.save_session_json())
	encoded.snapshot.party_encounter.schema_version = PartyState.EMOTION_STATE_SCHEMA_VERSION
	encoded.snapshot.party_encounter.erase("ration_milli")
	encoded.snapshot.party_encounter.erase("ration_processed_at")
	var saved_world_time := int(str(encoded.snapshot.world_time))
	check(saved_world_time > 0, "the save carries a nonzero world time")
	var restored = Session.new(1, 2)
	var loaded: Dictionary = restored.load_session_json(JSON.stringify(encoded))
	check(bool(loaded.get("accepted", false)),
		"v20 save without ration keys migrates: %s" % str(loaded.get("reason", "")))
	if not bool(loaded.get("accepted", false)): return finish()
	var state = restored.sim.world.party_encounter
	check_eq(int(state.ration_milli), Rules.ration_max_milli(),
		"a migrated save starts on a full gauge")
	check_eq(int(state.ration_processed_at), saved_world_time,
		"a migrated save anchors the drain clock at its own world time")
	check_eq(restored.sim.world.world_state_error(), "", "the migrated world stays canonical")
	return finish()
