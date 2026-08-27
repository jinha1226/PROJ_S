extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")
const WorldState = preload("res://sim/world_state.gd")
const Int64Codec = preload("res://sim/int64_codec.gd")


func test_snapshot_v3_header_and_json_round_trip_preserve_all_state() -> bool:
	var sim = Simulator.new(2, 1, 4142397736433585562)
	var actor = sim.world.add_entity("human", "Actor", Vector2i.ZERO)
	sim.world.tile_at(Vector2i.ZERO).flammability = 100
	sim.step(Command.ignite(Vector2i.ZERO, 70, actor.id))
	sim.step(Command.wait_for(99, actor.id))
	var source: Dictionary = sim.snapshot()
	check_eq([source.snapshot_version, source.ruleset_version,
		source.terrain_ruleset_id, source.hazard_affinity_ruleset_id],
		[4, "phase3-dungeon-personality-lab-v1", "terrain-registry-v1", "hazard-affinity-v1"],
		"v4 semantic header")
	check_eq([source.personality_schema_id, source.decision_ruleset_id, source.score_combiner_id],
		["personality-facets-v1", "dungeon-hierarchical-utility-v1", "weighted-sum-v1"], "phase3 registries")
	var parsed = JSON.parse_string(JSON.stringify(source))
	var restored = Simulator.from_snapshot(parsed)
	check_eq(restored.snapshot(), sim.snapshot(), "canonical JSON round trip")
	check_eq(restored.world.scheduled_entries[0]["due_time"], 300, "schedule restored")
	check_eq(restored.world.scheduled_entries[1]["due_time"], 300, "actor schedule restored")
	return finish()


func test_snapshot_wire_format_uses_strings_for_ids_and_times() -> bool:
	var sim = Simulator.new(1, 1, 8)
	var actor = sim.world.add_entity("human", "Actor", Vector2i.ZERO)
	var result = sim.step(Command.pour_water(Vector2i.ZERO, 10, actor.id))
	var snapshot: Dictionary = sim.snapshot()
	for key in ["step_index", "world_time", "seed", "rng_state", "next_entity_id",
		"next_event_id", "next_schedule_id"]:
		check_eq(typeof(snapshot[key]), TYPE_STRING, "%s is a string" % key)
	check_eq(typeof(snapshot.entities[0].id), TYPE_STRING, "entity id string")
	for key in ["id", "step_index", "world_time", "actor_id", "target_id", "cause_id", "instigator_id"]:
		check_eq(typeof(snapshot.events[0][key]), TYPE_STRING, "event %s string" % key)
	for key in ["schedule_id", "due_time", "owner_id", "source_event_id", "repeat_interval"]:
		check_eq(typeof(snapshot.scheduled_entries[0][key]), TYPE_STRING, "schedule %s string" % key)
	check_eq(result.timeline[0]["event_ids"].front(), result.root_event_id, "runtime timeline keeps int IDs")
	check_eq(typeof(result.root_event_id), TYPE_INT, "runtime root ID is int")
	return finish()


func test_int64_codec_accepts_2pow53_plus_one_and_rejects_lossy_or_overflow_forms() -> bool:
	for valid in ["0", "-1", "9007199254740993", "9223372036854775807", "-9223372036854775808"]:
		check(Int64Codec.is_canonical(valid), "valid canonical %s" % valid)
	for invalid in [9007199254740993, 1.0, "", "+1", "01", "-0", " 1", "1 ",
		"1.0", "1e3", "9223372036854775808", "-9223372036854775809"]:
		check(not Int64Codec.is_canonical(invalid), "invalid canonical %s" % str(invalid))
	return finish()


func test_large_exact_world_time_and_entity_id_survive_json() -> bool:
	var seed_snapshot: Dictionary = Simulator.new(1, 1, 4).snapshot()
	seed_snapshot["world_time"] = "9007199254740993"
	seed_snapshot["step_index"] = "9007199254740993"
	seed_snapshot["next_entity_id"] = "9007199254740993"
	seed_snapshot.scheduled_entries[0].due_time = "9007199254741000"
	seed_snapshot.scheduled_entries[1].due_time = "9007199254741000"
	var restored = Simulator.from_snapshot(JSON.parse_string(JSON.stringify(seed_snapshot)))
	var entity = restored.world.add_entity("test", "Large ID", Vector2i.ZERO)
	check_eq(entity.id, 9007199254740993, "large entity ID exact")
	check_eq(restored.world.world_time, 9007199254740993, "large time exact")
	var round_trip = Simulator.from_snapshot(JSON.parse_string(JSON.stringify(restored.snapshot())))
	check_eq(round_trip.snapshot(), restored.snapshot(), "large state JSON exact")
	return finish()


func test_v1_v2_and_registry_mismatch_headers_are_explicitly_unsupported() -> bool:
	var v1 := {"snapshot_version": 1, "ruleset_version": "phase0-relations-v1"}
	check_eq(WorldState.snapshot_header_error(v1), "unsupported_snapshot_version", "v1 rejection")
	check(Simulator.from_snapshot(v1) == null, "v1 checked restore returns null")
	var v2: Dictionary = Simulator.new(1, 1, 1).snapshot()
	v2.snapshot_version = 2
	v2.ruleset_version = "phase1-time-timeline-v1"
	check_eq(WorldState.snapshot_header_error(v2), "unsupported_snapshot_version", "v2 rejection")
	check(Simulator.from_snapshot(v2) == null, "v2 checked restore returns null")
	var mismatches := [
		["terrain_ruleset_id", "terrain-registry-v0", "unsupported_terrain_ruleset"],
		["hazard_affinity_ruleset_id", "hazard-affinity-v0", "unsupported_hazard_affinity_ruleset"],
	]
	for mismatch in mismatches:
		var invalid: Dictionary = Simulator.new(1, 1, 1).snapshot()
		invalid[mismatch[0]] = mismatch[1]
		check_eq(WorldState.snapshot_header_error(invalid), mismatch[2], mismatch[0])
		check(Simulator.from_snapshot(invalid) == null, "%s null restore" % mismatch[0])
	return finish()


func test_snapshot_wire_validator_rejects_numeric_overflow_and_bad_cadence() -> bool:
	var base: Dictionary = Simulator.new(1, 1, 1).snapshot()
	var numeric := base.duplicate(true)
	numeric["world_time"] = 0
	check_eq(WorldState.snapshot_wire_error(numeric), "noncanonical_world_time", "numeric time rejected")
	var overflow := base.duplicate(true)
	overflow["next_schedule_id"] = "9223372036854775808"
	check_eq(WorldState.snapshot_wire_error(overflow), "noncanonical_next_schedule_id", "overflow rejected")
	var fractional_source = Simulator.new(1, 1, 2)
	fractional_source.step(Command.wait())
	var fractional: Dictionary = fractional_source.snapshot()
	fractional.events[0].id = 1.5
	check_eq(WorldState.snapshot_wire_error(fractional), "noncanonical_event_id", "fractional ID rejected")
	var cadence := base.duplicate(true)
	cadence.scheduled_entries[0].due_time = "101"
	check_eq(WorldState.snapshot_wire_error(cadence), "invalid_canonical_schedule_cadence", "bad cadence rejected")
	var unknown := base.duplicate(true)
	unknown.scheduled_entries[0].kind = "system.unknown"
	check_eq(WorldState.snapshot_wire_error(unknown), "invalid_canonical_schedule_kind_or_priority", "unknown kind rejected")
	check(Simulator.from_snapshot(unknown) == null, "unknown kind returns null")
	var missing := base.duplicate(true)
	missing.scheduled_entries = []
	check(Simulator.from_snapshot(missing) == null, "missing environment row returns null")
	var duplicate := base.duplicate(true)
	duplicate.scheduled_entries.append(duplicate.scheduled_entries[0].duplicate(true))
	check(Simulator.from_snapshot(duplicate) == null, "duplicate environment row returns null")
	return finish()


func test_strict_small_snapshot_scalars_reject_fractional_string_and_negative_values() -> bool:
	var base: Dictionary = Simulator.new(1, 1, 1).snapshot()
	var mutations := [
		["width_fraction", func(row): row.width = 1.5],
		["priority_fraction", func(row): row.scheduled_entries[0].priority = 100.5],
		["priority_string", func(row): row.scheduled_entries[0].priority = "100"],
		["flammability_fraction", func(row): row.tiles[0].flammability = 10.5],
		["negative_fire", func(row): row.tiles[0].fire = -1],
	]
	for mutation in mutations:
		var corrupted: Dictionary = base.duplicate(true)
		mutation[1].call(corrupted)
		check(not WorldState.snapshot_restore_error(corrupted).is_empty(), "%s error" % mutation[0])
		check(Simulator.from_snapshot(corrupted) == null, "%s returns null" % mutation[0])
	return finish()


func test_fire_sentinel_semantic_corruption_returns_error_and_null_without_partial_world() -> bool:
	var burning = Simulator.new(1, 1, 3)
	burning.world.tile_at(Vector2i.ZERO).flammability = 100
	burning.step(Command.ignite(Vector2i.ZERO, 70))
	var burning_snapshot: Dictionary = burning.snapshot()
	var corruptions: Array = []
	var missing_source := burning_snapshot.duplicate(true)
	missing_source.tiles[0].fire_source_event_id = "-1"
	corruptions.append(missing_source)
	var missing_eligibility := burning_snapshot.duplicate(true)
	missing_eligibility.tiles[0].fire_damage_eligible_time = "-1"
	corruptions.append(missing_eligibility)
	var ghost_eligibility: Dictionary = Simulator.new(1, 1, 4).snapshot()
	ghost_eligibility.tiles[0].fire_damage_eligible_time = "0"
	corruptions.append(ghost_eligibility)
	for corrupted in corruptions:
		var reason := WorldState.snapshot_restore_error(corrupted)
		check(not reason.is_empty(), "semantic corruption has reason")
		check(Simulator.from_snapshot(corrupted) == null, "semantic corruption returns null")
	return finish()


func test_event_step_and_world_time_are_independently_monotonic() -> bool:
	var sim = Simulator.new(1, 1, 5)
	sim.step(Command.wait())
	sim.step(Command.wait())
	var corrupted: Dictionary = sim.snapshot()
	corrupted.events[0].world_time = "100"
	corrupted.events[1].world_time = "0"
	check_eq(WorldState.snapshot_restore_error(corrupted), "event_time_not_monotonic",
		"step increase cannot hide time reversal")
	check(Simulator.from_snapshot(corrupted) == null, "time reversal returns null")
	return finish()


func test_event_metadata_large_numeric_values_are_rejected_without_id_consumption() -> bool:
	var sim = Simulator.new(1, 1, 6)
	var before_event_count: int = sim.world.events.size()
	var before_schedule_count: int = sim.world.scheduled_entries.size()
	var before_schedule_id: int = sim.world.next_schedule_id
	check(sim.world.emit_event("test.large", -1, -1, Vector2i(-1, -1), 0, -1,
		{"unsafe": 9007199254740992}) == null, "unsafe runtime metadata rejected")
	check_eq(sim.world.events.size(), before_event_count, "event ID not consumed")
	check_eq(sim.world.schedule_entry("system.environment_tick", 50, 100, -1, -1, 0,
		{"unsafe": 9007199254740992}), -1, "unsafe payload rejected")
	check_eq(sim.world.scheduled_entries.size(), before_schedule_count, "schedule not added")
	check_eq(sim.world.next_schedule_id, before_schedule_id, "schedule ID not consumed")
	var safe = sim.world.emit_event("test.large_string", -1, -1, Vector2i(-1, -1), 0, -1,
		{"exact_id": "9007199254740993"})
	check(safe != null, "canonical metadata string accepted")
	var corrupted: Dictionary = sim.snapshot()
	corrupted.events[0].data = {"unsafe": 9007199254740992}
	check_eq(WorldState.snapshot_restore_error(corrupted), "invalid_event_data",
		"unsafe snapshot metadata rejected before JSON loss")
	check(Simulator.from_snapshot(corrupted) == null, "unsafe metadata restore returns null")
	return finish()


func test_time_and_event_id_overflow_are_rejected_before_commit() -> bool:
	var near_limit: Dictionary = Simulator.new(1, 1, 1).snapshot()
	near_limit.world_time = "9223372036854775657"
	near_limit.scheduled_entries[0].due_time = "9223372036854775700"
	near_limit.scheduled_entries[1].due_time = "9223372036854775700"
	var sim = Simulator.from_snapshot(near_limit)
	var before: Dictionary = sim.snapshot()
	var time_result = sim.step(Command.wait_for(100))
	check(not time_result.accepted, "time overflow rejected")
	check_eq(time_result.reason, "time_overflow", "time overflow reason")
	check_eq(sim.snapshot(), before, "time overflow no-op")

	var id_sim = Simulator.new(1, 1, 2)
	id_sim.world._next_event_id = 9223372036854775807
	var rng_before: int = id_sim.world.rng.state
	var schedule_before: Array = id_sim.world.scheduled_entries.duplicate(true)
	var id_result = id_sim.step(Command.wait())
	check(not id_result.accepted, "event ID overflow rejected")
	check_eq(id_result.reason, "event_id_overflow", "event overflow reason")
	check_eq(id_sim.world.world_time, 0, "event overflow time no-op")
	check_eq(id_sim.world.step_index, 0, "event overflow step no-op")
	check_eq(id_sim.world.events.size(), 0, "event overflow events no-op")
	check_eq(id_sim.world.rng.state, rng_before, "event overflow RNG no-op")
	check_eq(id_sim.world.scheduled_entries, schedule_before, "event overflow schedule no-op")
	return finish()


func test_resume_immediately_before_cadence_processes_due_once() -> bool:
	var continuous = Simulator.new(1, 1, 12)
	continuous.step(Command.wait_for(99))
	var resumed = Simulator.from_snapshot(JSON.parse_string(JSON.stringify(continuous.snapshot())))
	var a = continuous.step(Command.wait_for(1))
	var b = resumed.step(Command.wait_for(1))
	check_eq(_count_timeline_kind(a.timeline, "system.environment_tick"), 1, "continuous due once")
	check_eq(_count_timeline_kind(b.timeline, "system.environment_tick"), 1, "resumed due once")
	check_eq(resumed.snapshot(), continuous.snapshot(), "cadence resume exact")
	return finish()


func test_memory_and_json_midpoint_resume_match_mixed_cost_future() -> bool:
	var continuous = _prepared_sim(31)
	var commands := _mixed_commands(16)
	for index in range(8):
		continuous.step(commands[index])
	var memory = Simulator.from_snapshot(continuous.snapshot())
	var json = Simulator.from_snapshot(JSON.parse_string(JSON.stringify(continuous.snapshot())))
	for index in range(8, commands.size()):
		continuous.step(commands[index])
		memory.step(Command.from_dict(commands[index].to_dict()))
		json.step(Command.from_dict(commands[index].to_dict()))
	check_eq(memory.snapshot(), continuous.snapshot(), "memory resume")
	check_eq(json.snapshot(), continuous.snapshot(), "JSON resume")
	return finish()


func test_mixed_cost_long_run_over_10000_units_is_deterministic() -> bool:
	var a = _prepared_sim(20260827)
	var b = _prepared_sim(20260827)
	var commands := _mixed_commands(100)
	for index in range(commands.size()):
		a.step(commands[index])
		b.step(Command.from_dict(commands[index].to_dict()))
		if index == 49:
			b = Simulator.from_snapshot(JSON.parse_string(JSON.stringify(b.snapshot())))
	check(a.world.world_time > 10000, "long run crosses 10,000 time units")
	check_eq(a.snapshot(), b.snapshot(), "long deterministic snapshot")
	check_eq(hash(JSON.stringify(a.snapshot().events)), hash(JSON.stringify(b.snapshot().events)), "event hash")
	return finish()


func test_move_element_wait_100_command_json_midpoint_is_fully_deterministic() -> bool:
	var continuous = _prepared_move_sim(2026082701)
	var resumed = _prepared_move_sim(2026082701)
	var commands := _move_mixed_commands(continuous.world.entities.keys()[0], 100)
	var resumed_actor_id: int = resumed.world.entities.keys()[0]
	var resumed_commands := _move_mixed_commands(resumed_actor_id, 100)
	var continuous_timeline_rows: Array = []
	var resumed_timeline_rows: Array = []
	for index in range(100):
		var a_result = continuous.step(commands[index])
		var b_result = resumed.step(Command.from_dict(resumed_commands[index].to_dict()))
		check(a_result.accepted and b_result.accepted, "mixed command %d accepted" % index)
		continuous_timeline_rows.append(a_result.timeline.duplicate(true))
		resumed_timeline_rows.append(b_result.timeline.duplicate(true))
		if index == 49:
			resumed = Simulator.from_snapshot(
				JSON.parse_string(JSON.stringify(resumed.snapshot())))
			check(resumed != null, "midpoint v3 JSON restore")
	check_eq(continuous.world.world_time, 11470, "100-command final world time")
	check(continuous.world.world_time > 10000, "100-command run crosses 10,000")
	check_eq(resumed.snapshot(), continuous.snapshot(), "mixed MOVE exact final snapshot")
	check_eq(resumed.world.rng.state, continuous.world.rng.state, "mixed MOVE RNG")
	check_eq(hash(JSON.stringify(resumed.snapshot().events)),
		hash(JSON.stringify(continuous.snapshot().events)), "mixed MOVE event hash")
	check_eq(resumed_timeline_rows, continuous_timeline_rows, "mixed MOVE timelines")
	check_eq(resumed.sample_exposure(Vector2i(1, 0)).to_dict(),
		continuous.sample_exposure(Vector2i(1, 0)).to_dict(), "mixed MOVE exposure")
	return finish()


func _prepared_sim(seed: int):
	var sim = Simulator.new(2, 1, seed)
	for tile in sim.world.tiles:
		tile.flammability = 100
		tile.base_conductivity = 30
	sim.world.add_entity("goblin", "Target", Vector2i(1, 0), 1000)
	return sim


func _mixed_commands(count: int) -> Array:
	var pattern := [Command.pour_water(Vector2i(1, 0), 5),
		Command.ignite(Vector2i.ZERO, 70), Command.discharge(Vector2i.ZERO, 20),
		Command.wait_for(100)]
	var result: Array = []
	for index in range(count):
		result.append(pattern[index % pattern.size()])
	return result


func _prepared_move_sim(seed: int):
	var sim = Simulator.new(3, 1, seed)
	sim.world.bootstrap_set_terrain(Vector2i(1, 0), "shallow_water")
	sim.world.bootstrap_set_terrain(Vector2i(2, 0), "wood_floor")
	sim.world.add_entity("human", "Long Runner", Vector2i.ZERO, 1000, [], "human")
	return sim


func _move_mixed_commands(actor_id: int, count: int) -> Array:
	var pattern := [
		Command.move_to(actor_id, Vector2i(1, 0)),
		Command.pour_water(Vector2i(2, 0), 5, actor_id),
		Command.move_to(actor_id, Vector2i.ZERO),
		Command.ignite(Vector2i(2, 0), 70, actor_id),
		Command.wait_for(100, actor_id),
		Command.discharge(Vector2i(2, 0), 20, actor_id),
	]
	var result: Array = []
	for index in range(count):
		result.append(pattern[index % pattern.size()])
	return result


func _count_timeline_kind(timeline: Array, kind: String) -> int:
	var count := 0
	for marker in timeline:
		if marker["kind"] == kind:
			count += 1
	return count
