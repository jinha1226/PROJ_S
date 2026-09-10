extends SceneTree

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")
const DungeonMap = preload("res://playtest/deterministic_dungeon_map.gd")
const Perf = preload("res://sim/perf_probe.gd")


func _init() -> void:
	var rows: Array[Dictionary] = []
	rows.append(_measure("existing_96x96_idle", _existing_map(201), 3))
	rows.append(_measure("existing_96x96_local_fire", _local_fire_map(202), 3))
	rows.append(_measure("stress_100x100_wide_fire_gas", _wide_fire_map(203), 3))
	rows.append(_measure("stress_100x100_dense_exposure", _dense_exposure_map(204), 3))
	rows.append(_measure("stress_100x100_chain_explosion", _chain_explosion_map(205), 1))
	print("ENV_PERF_JSON " + JSON.stringify({"godot":Engine.get_version_info().string,
		"platform":OS.get_name(),"rows":rows}))
	quit(0)


func _existing_map(seed: int):
	var layout: Dictionary = DungeonMap.generate(96, 96, seed)
	var sim = Simulator.new(96, 96, seed)
	sim.world.bootstrap_set_terrain_layout(layout.terrain)
	return sim


func _local_fire_map(seed: int):
	var sim = _existing_map(seed)
	for position in _positions_with_terrain(sim, "wood_floor"):
		sim.world.bootstrap_set_fire(position, 80)
		break
	return sim


func _wide_fire_map(seed: int):
	var sim = Simulator.new(100, 100, seed)
	var terrain: Array = []
	terrain.resize(10000); terrain.fill("wood_floor")
	sim.world.bootstrap_set_terrain_layout(terrain)
	for y in range(35, 65, 3):
		for x in range(35, 65, 3):
			sim.world.bootstrap_set_fire(Vector2i(x, y), 70)
			sim.world.bootstrap_set_atmosphere(Vector2i(x, y), 500, 200, 100, 100)
	return sim


func _dense_exposure_map(seed: int):
	var sim = Simulator.new(100, 100, seed)
	for y in range(42, 58):
		for x in range(42, 58):
			var position := Vector2i(x, y)
			sim.world.bootstrap_set_atmosphere(position, 500, 120, 0, 0)
			sim.world.add_entity("goblin", "Dense %d:%d" % [x, y], position)
	return sim


func _chain_explosion_map(seed: int):
	var sim = Simulator.new(100, 100, seed)
	for x in range(45, 55):
		var position := Vector2i(x, 50)
		sim.world.bootstrap_set_atmosphere(position, 500, 0, 0, 400, true)
		sim.world.bootstrap_set_fire(position, 80)
	return sim


func _positions_with_terrain(sim, terrain_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for index in range(sim.world.tiles.size()):
		if sim.world.tiles[index].terrain == terrain_id:
			result.append(Vector2i(index % sim.world.width, index / sim.world.width))
	return result


func _measure(label: String, sim, ticks: int) -> Dictionary:
	Perf.reset(); Perf.enabled = true
	var active_before: int = sim.world.dynamic_tile_positions().size()
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var started := Time.get_ticks_usec()
	var accepted := true
	var reasons: Array[String] = []
	for index in range(ticks):
		var result = sim.step(Command.wait())
		accepted = accepted and bool(result.accepted)
		if not result.accepted: reasons.append(str(result.reason))
	var turn_us := Time.get_ticks_usec() - started
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	Perf.enabled = false
	return {"scenario":label,"ticks":ticks,"accepted":accepted,
		"active_before":active_before,
		"active_after":sim.world.dynamic_tile_positions().size(),
		"environment_tick_total_us":int(Perf.totals.get("environment.tick", 0)),
		"environment_tick_average_us":int(Perf.totals.get("environment.tick", 0)) / maxi(1, ticks),
		"turn_total_us":turn_us,"turn_average_us":turn_us / maxi(1, ticks),
		"memory_before_bytes":memory_before,"memory_after_bytes":memory_after,
		"event_count":sim.world.events.size(),"reasons":reasons,
		"world_error":sim.world.world_state_error()}
