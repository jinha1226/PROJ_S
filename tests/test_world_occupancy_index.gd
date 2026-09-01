extends "res://tests/test_case.gd"

const WorldScript = preload("res://sim/world_state.gd")

const LOOKUPS_PER_SAMPLE := 2000
const SAMPLE_COUNT := 7
const SMALL_ROSTER := 8
const LARGE_ROSTER := 160
# The probe cell is deliberately left empty so every lookup takes the miss path,
# which is the one autonomous NPC pathfinding hammers per neighbour.
const PROBE := Vector2i(1, 1)


func _world_with_entities(count: int):
	var world = WorldScript.new(64, 64, 1)
	var placed := 0
	var index := 0
	while placed < count and index < 4096:
		var position := Vector2i(index % 60 + 3, index / 60 + 3)
		index += 1
		if world.add_entity("enemy", "filler_%d" % placed, position) != null:
			placed += 1
	return world


func _median_lookup_usec(world, position: Vector2i) -> int:
	for _warm in range(LOOKUPS_PER_SAMPLE):
		world.blocking_entity_at(position)
	var samples: Array[int] = []
	for _sample in range(SAMPLE_COUNT):
		var started := Time.get_ticks_usec()
		for _lookup in range(LOOKUPS_PER_SAMPLE):
			world.blocking_entity_at(position)
		samples.append(Time.get_ticks_usec() - started)
	samples.sort()
	return samples[SAMPLE_COUNT / 2]


func test_occupancy_lookup_cost_does_not_scale_with_the_entity_roster() -> bool:
	var small = _world_with_entities(SMALL_ROSTER)
	var large = _world_with_entities(LARGE_ROSTER)
	check_eq(small.entities.size(), SMALL_ROSTER, "small roster fixture size")
	check_eq(large.entities.size(), LARGE_ROSTER, "large roster fixture size")
	check(small.blocking_entity_at(PROBE) == null \
			and large.blocking_entity_at(PROBE) == null,
		"probe cell is empty in both fixtures")
	if not errors.is_empty(): return finish()
	var small_median := _median_lookup_usec(small, PROBE)
	var large_median := _median_lookup_usec(large, PROBE)
	print("PERF occupancy lookup roster%d_us=%d roster%d_us=%d ratio_milli=%d" % [
		SMALL_ROSTER, small_median, LARGE_ROSTER, large_median,
		int(large_median * 1000 / maxi(1, small_median))])
	check(large_median < small_median * 3,
		"a 20x entity roster must not cost 3x per occupancy lookup; "
		+ "occupancy is a positional question, not a roster scan")
	return finish()


func test_occupancy_lookup_tracks_moves_death_and_restore_in_entity_id_order() -> bool:
	var world = WorldScript.new(16, 16, 1)
	var first = world.add_entity("enemy", "first", Vector2i(4, 4))
	var second = world.add_entity("enemy", "second", Vector2i(6, 6))
	check(first != null and second != null, "fixture entities are spawned")
	if first == null or second == null: return finish()

	check_eq(world.blocking_entity_at(Vector2i(4, 4)).id, first.id,
		"spawned entity occupies its own cell")
	check(world.blocking_entity_at(Vector2i(5, 5)) == null,
		"an empty cell reports no occupant")

	# Movement writes entity.position directly; occupancy must follow it.
	first.position = Vector2i(5, 5)
	check(world.blocking_entity_at(Vector2i(4, 4)) == null,
		"the vacated cell is free after a move")
	check_eq(world.blocking_entity_at(Vector2i(5, 5)).id, first.id,
		"the entered cell reports the moved entity")

	# A dead body stays on its tile but stops occupying it.
	# Mirror the canonical death seam: HP and life state move together.
	world.entities[second.id].health = 0
	world.combatant_states[second.id].life_state = "DEAD"
	check(world.blocking_entity_at(Vector2i(6, 6)) == null,
		"a dead entity no longer occupies its cell")
	check_eq(world.entities[second.id].position, Vector2i(6, 6),
		"the dead entity keeps its position")

	# Two entities may share a cell once one of them is dead; the roster order
	# is the canonical ascending entity id, not insertion or scan order.
	var third = world.add_entity("enemy", "third", Vector2i(6, 6))
	check(third != null, "a live entity spawns onto a dead body's cell")
	if third == null: return finish()
	var shared: Array = world.entities_at(Vector2i(6, 6))
	var shared_ids: Array[int] = []
	for entity in shared: shared_ids.append(int(entity.id))
	check_eq(shared_ids, [third.id],
		"only the live entity of a shared cell is reported as occupying")
	check_eq(world.blocking_entity_at(Vector2i(6, 6), third.id), null,
		"excluding the sole occupant reports the cell as free")

	check_eq(world.world_state_error(), "", "fixture world stays valid")
	var snapshot_data = world.snapshot()
	var restored = WorldScript.from_snapshot(snapshot_data) if snapshot_data is Dictionary else null
	check(restored != null, "world restores from its own snapshot")
	if restored == null: return finish()
	check_eq(restored.blocking_entity_at(Vector2i(5, 5)).id, first.id,
		"restored world reports the moved entity")
	check(restored.blocking_entity_at(Vector2i(4, 4)) == null,
		"restored world keeps the vacated cell free")
	check_eq(restored.blocking_entity_at(Vector2i(6, 6)).id, third.id,
		"restored world resolves the shared cell to the live entity")
	return finish()
