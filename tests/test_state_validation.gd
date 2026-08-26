class_name TestStateValidation
extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	failures.clear()
	_test_state_001_new_game()
	_test_state_002_id_increase()
	_test_state_003_serialization_round_trip()
	_test_sim_001_tick_determinism()
	_test_sim_002_render_group_independence()
	_test_invalid_state_rejected_without_replacement()
	return failures


func _test_state_001_new_game() -> void:
	var session := _new_session()
	_expect_equal(session.state.get_population(), 1, "STATE-001 population")
	_expect_equal(session.state.next_entity_number, 2, "STATE-001 next entity number")
	_expect_equal(session.state.simulation_tick, 0, "STATE-001 simulation tick")

	var slime: SlimeState = session.state.slimes[&"slime_000001"]
	_expect_equal(slime.memory_capacity, 1, "STATE-001 memory capacity")
	_expect_equal(slime.skill_memories.size(), 0, "STATE-001 empty skills")
	_expect_equal(slime.division_meter, 12, "STATE-001 initial division meter")

	var inventory: InventoryState = session.state.inventories[&"town_storage"]
	_expect_equal(inventory.amounts["wood"], 0, "STATE-001 wood")
	_expect_equal(inventory.amounts["crystal"], 0, "STATE-001 crystal")
	_expect_true(bool(session.state.facilities["forest"]["enabled"]), "STATE-001 forest enabled")
	_expect_true(bool(session.state.facilities["crystal_mine"]["locked"]), "STATE-001 mine locked")
	_expect_equal(session.validate_state().size(), 0, "STATE-001 invariants")


func _test_state_002_id_increase() -> void:
	var session := _new_session()
	var first := session.state.allocate_slime_id()
	var second := session.state.allocate_slime_id()
	var third := session.state.allocate_slime_id()
	_expect_equal(str(first), "slime_000002", "STATE-002 first allocated ID")
	_expect_equal(str(second), "slime_000003", "STATE-002 second allocated ID")
	_expect_equal(str(third), "slime_000004", "STATE-002 third allocated ID")
	_expect_true(first != second and second != third and first != third, "STATE-002 IDs are unique")
	_expect_equal(session.state.next_entity_number, 5, "STATE-002 IDs are never rewound")


func _test_state_003_serialization_round_trip() -> void:
	var session := _new_session()
	session.advance_ticks(7)
	var original_hash := session.state.canonical_hash()
	var json_text := JSON.stringify(session.create_snapshot())
	var parsed: Variant = JSON.parse_string(json_text)
	_expect_true(typeof(parsed) == TYPE_DICTIONARY, "STATE-003 JSON parses as Dictionary")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var restored := GameState.from_dict(parsed)
	_expect_equal(restored.validate().size(), 0, "STATE-003 restored state validates")
	_expect_equal(restored.canonical_hash(), original_hash, "STATE-003 canonical hash round trip")


func _test_sim_001_tick_determinism() -> void:
	var session_a := _new_session()
	var session_b := _new_session()
	session_a.advance_ticks(100)
	for _index: int in range(100):
		session_b.advance_ticks(1)
	_expect_equal(session_a.state.canonical_hash(), session_b.state.canonical_hash(), "SIM-001 split ticks")


func _test_sim_002_render_group_independence() -> void:
	var session_30fps := _new_session()
	var session_60fps := _new_session()
	for _index: int in range(20):
		session_30fps.advance_ticks(5)
	for _index: int in range(50):
		session_60fps.advance_ticks(2)
	_expect_equal(session_30fps.state.canonical_hash(), session_60fps.state.canonical_hash(), "SIM-002 render grouping")


func _test_invalid_state_rejected_without_replacement() -> void:
	var session := _new_session()
	var original_state := session.state
	var invalid_snapshot := session.create_snapshot()
	invalid_snapshot["slimes"]["slime_000001"]["memory_capacity"] = 0
	var result := session.load_game(invalid_snapshot)
	_expect_true(not result.ok, "STATE invalid snapshot fails")
	_expect_equal(str(result.code), "INVALID_STATE", "STATE invalid snapshot error code")
	_expect_true(session.state == original_state, "STATE invalid snapshot does not replace live state")


func _new_session() -> GameSession:
	var session := GameSession.new()
	session.new_game()
	return session


func _expect_true(condition: bool, label: String) -> void:
	if not condition:
		failures.append("%s: expected true" % label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
