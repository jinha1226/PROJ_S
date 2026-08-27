extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")
const TerrainRegistry = preload("res://sim/terrain_registry.gd")
const WorldState = preload("res://sim/world_state.gd")


func test_terrain_registry_v1_values_are_exact_and_detached() -> bool:
	var expected := {
		"floor": [true, 1, 100, 0, 0, 0],
		"stone_floor": [true, 1, 100, 0, 0, 5],
		"wood_floor": [true, 1, 100, 0, 80, 5],
		"metal": [true, 1, 100, 0, 0, 25],
		"rubble": [true, 1, 140, 0, 10, 5],
		"shallow_water": [true, 1, 130, 80, 0, 60],
		"wall": [false, 0, 0, 0, 0, 0],
	}
	for terrain_id in expected:
		var row: Dictionary = TerrainRegistry.definition(terrain_id)
		check_eq([row.passable, row.occupancy_capacity, row.move_time_cost,
			row.terrain_water_exposure, row.default_flammability,
			row.default_base_conductivity], expected[terrain_id], terrain_id)
		check(not str(row.presentation_key).is_empty(), "presentation key")
	var detached_row: Dictionary = TerrainRegistry.definition("wood_floor")
	detached_row.default_flammability = 0
	check_eq(TerrainRegistry.definition("wood_floor").default_flammability, 80,
		"registry result detached")
	return finish()


func test_terrain_bootstrap_is_checked_and_applies_material_defaults() -> bool:
	var sim = Simulator.new(2, 2, 1)
	var position := Vector2i(1, 1)
	var tile = sim.world.tile_at(position)
	tile.fire = 30
	tile.wetness = 20
	tile.fire_source_event_id = 99
	tile.wetness_source_event_id = 98
	tile.fire_damage_eligible_time = 77
	check(sim.world.bootstrap_set_terrain(position, "wood_floor"), "valid bootstrap")
	check_eq(tile.terrain, "wood_floor", "terrain id")
	check_eq(tile.flammability, 80, "default flammability")
	check_eq(tile.base_conductivity, 5, "default conductivity")
	check_eq([tile.fire, tile.wetness, tile.fire_source_event_id,
		tile.wetness_source_event_id, tile.fire_damage_eligible_time], [0, 0, -1, -1, -1],
		"dynamic state reset")
	var before: Dictionary = sim.snapshot()
	check(not sim.world.bootstrap_set_terrain(Vector2i(2, 0), "wall"), "bounds rejected")
	check(not sim.world.bootstrap_set_terrain(Vector2i.ZERO, "missing"), "unknown rejected")
	check_eq(sim.snapshot(), before, "invalid bootstrap no-op")
	sim.step(Command.wait_for(1))
	var late_before: Dictionary = sim.snapshot()
	check(not sim.world.bootstrap_set_terrain(Vector2i.ZERO, "wall"), "late bootstrap rejected")
	check_eq(sim.snapshot(), late_before, "late bootstrap no-op")
	return finish()


func test_terrain_and_live_occupancy_producer_restore_domains_match() -> bool:
	var wall_sim = Simulator.new(2, 1, 2)
	check(wall_sim.world.bootstrap_set_terrain(Vector2i(1, 0), "wall"), "wall bootstrap")
	var id_before: int = wall_sim.world._next_entity_id
	check(wall_sim.world.add_entity("human", "Blocked", Vector2i(1, 0)) == null,
		"wall spawn rejected")
	check_eq(wall_sim.world._next_entity_id, id_before, "wall rejection no ID")

	var sim = Simulator.new(2, 1, 3)
	var corpse = sim.world.add_entity("human", "Corpse", Vector2i.ZERO)
	var occupied_id_before: int = sim.world._next_entity_id
	check(sim.world.add_entity("goblin", "Blocked", Vector2i.ZERO) == null,
		"second live entity rejected")
	check_eq(sim.world._next_entity_id, occupied_id_before, "occupied rejection no ID")
	corpse.health = 0
	var living = sim.world.add_entity("goblin", "Living", Vector2i.ZERO)
	check(living != null, "corpse does not block")
	var valid: Dictionary = sim.snapshot()
	var restored = Simulator.from_snapshot(valid)
	check(restored != null, "dead/live cohabitation restores")
	check_eq(restored.snapshot(), valid, "dead/live exact round trip")

	var duplicate: Dictionary = valid.duplicate(true)
	duplicate.entities[0].health = 100
	check_eq(WorldState.snapshot_restore_error(duplicate), "live_occupancy_capacity_exceeded",
		"duplicate live occupancy rejected")
	var on_wall: Dictionary = valid.duplicate(true)
	on_wall.tiles[0].terrain = "wall"
	check_eq(WorldState.snapshot_restore_error(on_wall), "live_entity_on_impassable_terrain",
		"live entity on wall rejected")
	var unknown: Dictionary = valid.duplicate(true)
	unknown.tiles[1].terrain = "void"
	check_eq(WorldState.snapshot_restore_error(unknown), "unknown_terrain_id",
		"unknown terrain raw error")
	check(Simulator.from_snapshot(unknown) == null, "unknown terrain null restore")
	sim.world.tile_at(Vector2i(1, 0)).terrain = "void"
	check(sim.snapshot() == null, "unknown terrain world cannot save")
	return finish()


func test_move_cardinal_success_and_geometry_rejections() -> bool:
	for destination in [Vector2i(1, 0), Vector2i(2, 1), Vector2i(1, 2), Vector2i(0, 1)]:
		var sim = Simulator.new(3, 3, 4)
		var actor = sim.world.add_entity("human", "Mover", Vector2i.ONE)
		var result = sim.step(Command.move_to(actor.id, destination))
		check(result.accepted, "cardinal MOVE accepted")
		check_eq(actor.position, destination, "cardinal position")
	for destination in [Vector2i.ONE, Vector2i(2, 2), Vector2i(1, 3)]:
		var sim = Simulator.new(3, 3, 5)
		var actor = sim.world.add_entity("human", "Mover", Vector2i.ONE)
		var before: Dictionary = sim.snapshot()
		var result = sim.step(Command.move_to(actor.id, destination))
		check(not result.accepted, "non-cardinal MOVE rejected")
		check_eq(result.reason, "move_not_cardinal_adjacent", "geometry reason")
		check_eq(sim.snapshot(), before, "geometry rejection no-op")
	return finish()


func test_move_actor_bounds_wall_occupancy_and_death_rejections_are_noops() -> bool:
	var sim = Simulator.new(3, 1, 6)
	var actor = sim.world.add_entity("human", "Mover", Vector2i.ZERO)
	var blocker = sim.world.add_entity("goblin", "Blocker", Vector2i(1, 0))
	var occupied_before: Dictionary = sim.snapshot()
	var occupied = sim.step(Command.move_to(actor.id, Vector2i(1, 0)))
	check_eq(occupied.reason, "move_destination_occupied", "occupied reason")
	check_eq(sim.snapshot(), occupied_before, "occupied no-op")
	blocker.health = 0
	check(sim.step(Command.move_to(actor.id, Vector2i(1, 0))).accepted, "corpse destination allowed")

	var wall = Simulator.new(2, 1, 7)
	wall.world.bootstrap_set_terrain(Vector2i(1, 0), "wall")
	var wall_actor = wall.world.add_entity("human", "Mover", Vector2i.ZERO)
	var wall_before: Dictionary = wall.snapshot()
	check_eq(wall.step(Command.move_to(wall_actor.id, Vector2i(1, 0))).reason,
		"move_terrain_blocked", "wall reason")
	check_eq(wall.snapshot(), wall_before, "wall no-op")

	var edge = Simulator.new(2, 1, 8)
	var edge_actor = edge.world.add_entity("human", "Mover", Vector2i.ZERO)
	var edge_before: Dictionary = edge.snapshot()
	check_eq(edge.step(Command.move_to(edge_actor.id, Vector2i(-1, 0))).reason,
		"move_out_of_bounds", "bounds reason")
	check_eq(edge.snapshot(), edge_before, "bounds no-op")
	for command in [Command.move_to(-1, Vector2i(1, 0)),
		Command.move_to(999, Vector2i(1, 0))]:
		check(not edge.step(command).accepted, "invalid actor rejected")
		check_eq(edge.snapshot(), edge_before, "invalid actor no-op")
	edge_actor.health = 0
	var dead_before: Dictionary = edge.snapshot()
	check_eq(edge.step(Command.move_to(edge_actor.id, Vector2i(1, 0))).reason,
		"actor_dead", "dead reason")
	check_eq(edge.snapshot(), dead_before, "dead no-op")
	return finish()


func test_move_cost_preview_commit_event_and_stale_replan() -> bool:
	for terrain_case in [["floor", 100, "NORMAL"], ["shallow_water", 130, "SLOW"],
		["rubble", 140, "SLOW"]]:
		var sim = Simulator.new(2, 1, int(terrain_case[1]))
		sim.world.bootstrap_set_terrain(Vector2i(1, 0), terrain_case[0])
		var actor = sim.world.add_entity("human", "Mover", Vector2i.ZERO)
		var command = Command.move_to(actor.id, Vector2i(1, 0))
		var preview = sim.preview(command)
		check_eq(preview.time_cost, terrain_case[1], "preview terrain cost")
		check_eq(preview.speed_tier, terrain_case[2], "preview speed")
		var result = sim.step(command)
		check_eq(result.time_cost, terrain_case[1], "actual terrain cost")
		var root = result.events[0]
		check_eq([root.type, root.actor_id, root.position, root.magnitude],
			["action.move", actor.id, Vector2i(1, 0), terrain_case[1]], "MOVE root")
		check_eq(root.data, {"from_position": [0, 0], "to_position": [1, 0],
			"terrain_id": terrain_case[0], "move_time_cost": terrain_case[1]}, "MOVE data")
		check_eq(result.timeline[0].event_ids, [root.id], "root belongs to action marker")

	var stale = Simulator.new(2, 1, 11)
	stale.world.bootstrap_set_terrain(Vector2i(1, 0), "shallow_water")
	var stale_actor = stale.world.add_entity("human", "Mover", Vector2i.ZERO)
	var stale_command = Command.move_to(stale_actor.id, Vector2i(1, 0))
	check_eq(stale.preview(stale_command).time_cost, 130, "old preview cost")
	stale.world.bootstrap_set_terrain(Vector2i(1, 0), "rubble")
	check_eq(stale.step(stale_command).time_cost, 140, "actual replans current terrain")
	return finish()


func test_move_start_commit_controls_due_tick_damage_and_ready_order() -> bool:
	var enter = Simulator.new(2, 1, 12)
	enter.world.tile_at(Vector2i(1, 0)).flammability = 100
	enter.world.bootstrap_set_fire(Vector2i(1, 0), 50)
	var entering_actor = enter.world.add_entity("human", "Enter", Vector2i.ZERO)
	enter.step(Command.pour_water(Vector2i.ZERO, 1))
	var entered = enter.step(Command.move_to(entering_actor.id, Vector2i(1, 0)))
	check_eq(entered.start_time, 80, "MOVE starts at t80")
	check_eq(entering_actor.position, Vector2i(1, 0), "position committed at start")
	check_eq(entering_actor.health, 80, "t100 tick damages new position")
	check_eq(entered.timeline[1].at_time, 100, "tick occurs in move window")

	var leave = Simulator.new(2, 1, 13)
	leave.world.bootstrap_set_fire(Vector2i.ZERO, 50)
	var leaving_actor = leave.world.add_entity("human", "Leave", Vector2i.ZERO)
	var left = leave.step(Command.move_to(leaving_actor.id, Vector2i(1, 0)))
	check_eq(leaving_actor.health, 100, "start commit escapes old burning tile")
	check_eq(left.timeline[-2].kind, "system.environment_tick", "due=end before ready")
	check_eq(left.timeline[-2].at_time, 100, "due at MOVE end")
	check_eq(left.timeline.back().kind, "actor.ready", "ready last")
	return finish()


func test_move_window_can_end_with_dead_actor_and_next_move_rejects() -> bool:
	var sim = Simulator.new(2, 1, 14)
	sim.world.bootstrap_set_fire(Vector2i(1, 0), 100)
	var actor = sim.world.add_entity("human", "Fragile", Vector2i.ZERO, 10)
	var result = sim.step(Command.move_to(actor.id, Vector2i(1, 0)))
	check(result.accepted, "MOVE remains accepted through settled death")
	check_eq(actor.health, 0, "actor dies in cadence")
	check_eq(result.timeline.back().kind, "actor.ready", "time boundary still ready marker")
	var before: Dictionary = sim.snapshot()
	check_eq(sim.step(Command.move_to(actor.id, Vector2i.ZERO)).reason, "actor_dead",
		"next MOVE rejected as dead")
	check_eq(sim.snapshot(), before, "dead follow-up no-op")
	return finish()


func test_move_command_wire_and_json_resume_are_deterministic() -> bool:
	check_eq([int(Command.Type.WAIT), int(Command.Type.IGNITE), int(Command.Type.POUR_WATER),
		int(Command.Type.DISCHARGE), int(Command.Type.MOVE)], [0, 1, 2, 3, 4],
		"enum values append-only")
	var command = Command.move_to(9007199254740993, Vector2i(2, 3))
	var decoded = Command.from_dict(JSON.parse_string(JSON.stringify(command.to_dict())))
	check_eq(decoded.actor_id, 9007199254740993, "large MOVE actor exact")
	for mutation in [
		func(row): row.power = 1,
		func(row): row.position = [1.5, 0],
		func(row): row.type = 4.5,
		func(row): row.actor_id = 1,
	]:
		var row: Dictionary = Command.move_to(1, Vector2i.ONE).to_dict()
		mutation.call(row)
		check(Command.from_dict(row) == null, "malformed MOVE wire rejected")

	var a = Simulator.new(4, 1, 15)
	var b = Simulator.new(4, 1, 15)
	var actor_a = a.world.add_entity("human", "Mover", Vector2i.ZERO)
	var actor_b = b.world.add_entity("human", "Mover", Vector2i.ZERO)
	var commands := [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	for index in range(commands.size()):
		var ca = Command.move_to(actor_a.id, commands[index])
		var cb = Command.move_to(actor_b.id, commands[index])
		var ra = a.step(ca)
		var rb = b.step(Command.from_dict(cb.to_dict()))
		check_eq(ra.timeline, rb.timeline, "MOVE timeline deterministic")
		if index == 1:
			b = Simulator.from_snapshot(JSON.parse_string(JSON.stringify(b.snapshot())))
			actor_b = b.world.entities[actor_b.id]
	check_eq(b.snapshot(), a.snapshot(), "mid-MOVE JSON resume exact")
	return finish()


func test_move_preview_is_pure_revalidates_new_occupancy_and_actor_kinds_share_path() -> bool:
	var stale = Simulator.new(3, 1, 16)
	var actor = stale.world.add_entity("player", "Player", Vector2i.ZERO, 100, [], "human")
	var command = Command.move_to(actor.id, Vector2i(1, 0))
	var before_preview: Dictionary = stale.snapshot()
	var preview = stale.preview(command)
	check(preview.accepted, "initial preview accepted")
	check_eq(stale.snapshot(), before_preview, "MOVE preview pure")
	var blocker = stale.world.add_entity("goblin", "Late Blocker", Vector2i(1, 0))
	check(blocker != null, "blocker added after preview")
	var before_rejected_step: Dictionary = stale.snapshot()
	var rejected = stale.step(command)
	check_eq(rejected.reason, "move_destination_occupied", "stale occupancy revalidated")
	check_eq(stale.snapshot(), before_rejected_step, "stale preview rejection no-op")

	for actor_case in [["player", "human"], ["goblin", "goblin"]]:
		var sim = Simulator.new(2, 1, 17)
		var mover = sim.world.add_entity(
			actor_case[0], actor_case[0], Vector2i.ZERO, 100, [], actor_case[1])
		var assessment = sim.assess_move(mover.id, Vector2i(1, 0))
		var result = sim.step(Command.move_to(mover.id, Vector2i(1, 0)))
		check(assessment.accepted and result.accepted, "%s shared MOVE accepted" % actor_case[0])
		check_eq([result.time_cost, result.events[0].type, mover.position],
			[100, "action.move", Vector2i(1, 0)], "%s shared path" % actor_case[0])
	return finish()
