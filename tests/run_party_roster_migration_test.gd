extends SceneTree

const TEST_FILE := "test_party_playtest_session.gd"
const TEST_METHOD := "test_companion_exile_and_distinct_recruitment_pool_are_authoritative_and_replay_exact"
const Session = preload("res://playtest/party_playtest_session.gd")
const PartyState = preload("res://sim/party_encounter_state.gd")
const WeaponLoadout = preload("res://sim/weapon_loadout_state.gd")


func _init() -> void:
	var script = load("res://tests/" + TEST_FILE)
	var test_case = script.new()
	var completed = test_case.call(TEST_METHOD)
	if typeof(completed) != TYPE_BOOL or not completed:
		if test_case.errors.is_empty(): test_case.errors.append("test did not complete")
	_check_legacy_loadout_defaults(test_case.errors)
	for error in test_case.errors:
		print("FAIL %s :: %s -- %s" % [TEST_FILE, TEST_METHOD, error])
	if test_case.errors.is_empty():
		print("PASS %s :: %s" % [TEST_FILE, TEST_METHOD])
	quit(1 if not test_case.errors.is_empty() else 0)


func _check_legacy_loadout_defaults(errors: Array) -> void:
	var session = Session.new()
	var current: Dictionary = session.sim.world.party_encounter.to_dict()
	for schema_version in [1, 2, 3, 4, 5]:
		var row: Dictionary = current.duplicate(true)
		row.schema_version = schema_version
		for member_row in row.member_rows:
			member_row.erase("mental_mode")
		row.erase("protagonist_growth")
		row.erase("opening_event")
		row.erase("safe_recovery_turns")
		row.erase("last_protagonist_damage_step")
		row.erase("protagonist_inventory")
		row.erase("ground_items")
		row.erase("enemy_awareness_rows")
		row.erase("diagonal_gateway_positions")
		# v5-v12 carried a protagonist_loadout; v13 removed that duplicate weapon
		# authority, so only the historical fixtures state the field.
		if schema_version >= 5:
			row["protagonist_loadout"] = WeaponLoadout.new("SHORT_SWORD", 12, 6).to_dict()
		if schema_version < 4: row.erase("protagonist_progression")
		if schema_version < 3: row.erase("patrol_reserved_positions")
		if schema_version < 2:
			row.erase("active_party_member_ids")
			row.erase("exile_records")
		var wire_error := PartyState.wire_error(row, session.sim.world.width,
			session.sim.world.height)
		if not wire_error.is_empty():
			errors.append("schema %d fixture rejected: %s" % [schema_version, wire_error])
			continue
		var restored = PartyState.from_dict(row)
		if restored.schema_version != PartyState.SCHEMA_VERSION \
				or restored.to_dict().has("protagonist_loadout"):
			errors.append("schema %d did not drop the legacy loadout field" % schema_version)
		if schema_version == 1 \
				and restored.active_party_member_ids != restored.party_member_ids:
			errors.append("schema 1 did not default the full roster active")
