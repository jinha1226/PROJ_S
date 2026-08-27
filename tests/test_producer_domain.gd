extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const WorldState = preload("res://sim/world_state.gd")


func test_checked_factory_and_producer_boundaries_match_restore_domain() -> bool:
	check(Simulator.create(1.5, 1, 1) == null, "fractional dynamic dimension is rejected")
	check(Simulator.create(4097, 1, 1) == null, "per-axis dimension cap is checked")
	check(Simulator.create(2000, 501, 1) == null, "total tile cap is checked before allocation")
	var invalid_raw = Simulator.new(4097, 1, 1)
	check(invalid_raw.snapshot() == null, "raw invalid dimensions cannot create an unreadable save")

	var sim = Simulator.create(4096, 1, 9)
	check(sim != null, "maximum axis is accepted when total tiles are safe")
	var entity = sim.world.add_entity(
		"human", "Boundary", Vector2i(4095, 0), 2147483647, ["player"], "human", "party")
	check(entity != null, "maximum health producer boundary accepted")
	var event = sim.world.emit_event(
		"test.boundary", entity.id, entity.id, Vector2i(4095, 0), 2147483647,
		-1, {"safe": 9007199254740991})
	check(event != null, "maximum event magnitude and safe metadata accepted")
	var tile = sim.world.tile_at(Vector2i(4095, 0))
	tile.flammability = 100
	tile.base_conductivity = 100
	tile.wetness = 100
	var water_source = sim.world.emit_event(
		"environment.water_applied", -1, -1, Vector2i(4095, 0), 100, -1,
		{"requested_amount": 100})
	tile.wetness_source_event_id = water_source.id
	sim.world.bootstrap_set_fire(Vector2i(4095, 0), 100)
	var saved: Dictionary = sim.snapshot()
	check(saved != null, "accepted producer state is saveable")
	check_eq(WorldState.snapshot_restore_error(saved), "", "producer state passes checked restore")
	var restored = Simulator.from_snapshot(saved)
	check(restored != null, "producer state restores")
	check_eq(restored.snapshot(), saved, "producer state exact round trip")
	return finish()


func test_invalid_producer_mutations_consume_no_ids_and_invalid_state_cannot_save() -> bool:
	var sim = Simulator.new(2, 2, 3)
	var next_entity_before: int = sim.world._next_entity_id
	check(sim.world.add_entity("bad", "Health", Vector2i.ZERO, 2147483648) == null,
		"oversized max health rejected")
	check(sim.world.add_entity("bad", "Position", Vector2i(2, 0)) == null,
		"out-of-bounds position rejected")
	check(sim.world.add_entity("bad", "Tag", Vector2i.ZERO, 10, ["ok", 7]) == null,
		"non-string tag rejected")
	check_eq(sim.world._next_entity_id, next_entity_before, "invalid entities consume no ID")

	var entity = sim.world.add_entity("human", "Valid", Vector2i.ZERO)
	var next_event_before: int = sim.world._next_event_id
	for rejected_event in [
		sim.world.emit_event("test.bad", -1, -1, Vector2i(-1, -1), 2147483648),
		sim.world.emit_event("test.bad", -1, -1, Vector2i(2, 0), 1),
		sim.world.emit_event("test.bad", 999, -1, Vector2i.ZERO, 1),
		sim.world.emit_event("test.bad", entity.id, -1, Vector2i.ZERO, 1, -1,
			{"unsafe": 9007199254740992}),
	]:
		check(rejected_event == null, "invalid event rejected")
	check_eq(sim.world._next_event_id, next_event_before, "invalid events consume no ID")

	var next_schedule_before: int = sim.world.next_schedule_id
	for rejected_schedule_id in [
		sim.world.schedule_entry("system.environment_tick", 50, 50),
		sim.world.schedule_entry("unknown.kind", 1),
		sim.world.schedule_entry("system.environment_tick", 0),
		sim.world.schedule_entry("system.environment_tick", 1, 2147483648),
		sim.world.schedule_entry("system.environment_tick", 1, 100, 999),
		sim.world.schedule_entry("system.environment_tick", 1, 100, -1, -1, -1),
		sim.world.schedule_entry("system.environment_tick", 1, 100, -1, -1, 0,
			{"unsafe": 9007199254740992}),
	]:
		check_eq(rejected_schedule_id, -1, "invalid schedule rejected")
	check_eq(sim.world.next_schedule_id, next_schedule_before, "invalid schedules consume no ID")
	check(sim.snapshot() != null, "rejected public schedules preserve the canonical save boundary")

	var tile = sim.world.tile_at(Vector2i.ZERO)
	tile.flammability = 101
	check(not sim.world.world_state_error().is_empty(), "direct invalid tile mutation is diagnosed")
	check(sim.snapshot() == null, "invalid bootstrap state cannot emit a snapshot")
	tile.flammability = 100
	var valid_saved: Dictionary = sim.snapshot()
	check(valid_saved != null, "repairing the bootstrap state restores saveability")
	check_eq(WorldState.snapshot_restore_error(valid_saved), "", "repaired save is readable")
	return finish()


func test_duplicate_directional_species_relation_rows_are_rejected() -> bool:
	var sim = Simulator.new(1, 1, 7)
	sim.world.species_relations.set_relation("human", "goblin", -70, 35, 75)
	var saved: Dictionary = sim.snapshot()
	var duplicate: Dictionary = saved.duplicate(true)
	duplicate["species_relations"]["rows"].append(
		duplicate["species_relations"]["rows"][0].duplicate(true))
	check_eq(WorldState.snapshot_restore_error(duplicate), "duplicate_species_relation",
		"duplicate direction pair has an explicit raw error")
	check(Simulator.from_snapshot(duplicate) == null, "duplicate direction pair is not restored")

	var delimiter_pairs: Dictionary = saved.duplicate(true)
	delimiter_pairs["species_relations"]["rows"] = [
		{"observer_species_id": "a", "subject_species_id": "b\u001fc",
			"base_trust": 4, "base_fear": 5, "base_hostility": 6},
		{"observer_species_id": "a\u001fb", "subject_species_id": "c",
			"base_trust": 1, "base_fear": 2, "base_hostility": 3},
	]
	check_eq(WorldState.snapshot_restore_error(delimiter_pairs), "",
		"distinct pairs containing delimiter characters do not collide")
	var delimiter_restored = Simulator.from_snapshot(delimiter_pairs)
	check(delimiter_restored != null, "distinct delimiter-containing pairs restore")
	check_eq(delimiter_restored.snapshot(), delimiter_pairs,
		"distinct delimiter-containing pairs exact round trip")
	return finish()
