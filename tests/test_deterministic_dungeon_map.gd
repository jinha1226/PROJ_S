extends "res://tests/test_case.gd"

const DungeonMap = preload("res://playtest/deterministic_dungeon_map.gd")
const Session = preload("res://playtest/party_playtest_session.gd")


func test_same_seed_is_exact_and_different_seed_changes_layout() -> bool:
	var first := DungeonMap.generate(48, 48, 44)
	var second := DungeonMap.generate(48, 48, 44)
	var other := DungeonMap.generate(48, 48, 45)
	check(not first.is_empty(), "generated layout exists")
	check_eq(first, second, "same seed reproduces the exact layout")
	check(first.terrain != other.terrain, "different seed changes terrain topology")
	check_eq([first.width, first.height], [48, 48], "product dungeon size")
	return finish()


func test_rooms_features_materials_and_objectives_are_connected() -> bool:
	var layout := DungeonMap.generate(48, 48, 8080)
	var entry: Vector2i = layout.entry_position
	var exit: Vector2i = layout.exit_position
	check(DungeonMap.reachable(layout, entry, exit), "entry reaches exit")
	for enemy_position in layout.enemy_positions:
		check(DungeonMap.reachable(layout, entry, enemy_position),
			"entry reaches every enemy spawn")
	check(layout.rooms.size() >= 9, "dungeon contains several rooms")
	check(not layout.door_positions.is_empty(), "dungeon exposes open-door features")
	check(not layout.hazards.is_empty(), "dungeon exposes hazard positions")
	for material_id in ["shallow_water", "metal", "wood_floor", "rubble"]:
		check(not layout.material_positions[material_id].is_empty(),
			"material terrain present: %s" % material_id)
	for x in range(48):
		check_eq(DungeonMap.terrain_at(layout, Vector2i(x, 0)), "wall", "north border")
		check_eq(DungeonMap.terrain_at(layout, Vector2i(x, 47)), "wall", "south border")
	for y in range(48):
		check_eq(DungeonMap.terrain_at(layout, Vector2i(0, y)), "wall", "west border")
		check_eq(DungeonMap.terrain_at(layout, Vector2i(47, y)), "wall", "east border")
	return finish()


func test_solo_session_uses_large_map_los_memory_and_seeded_spawns() -> bool:
	var first = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var second = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check(first.sim != null and second.sim != null, "solo sessions initialize")
	if first.sim == null or second.sim == null:
		return finish()
	check_eq([first.sim.world.width, first.sim.world.height], [48, 48],
		"solo world is larger than the viewport")
	check_eq(first.sim.snapshot(), second.sim.snapshot(),
		"same seed reproduces authoritative world and spawns")
	var state = first.sim.world.party_encounter
	var hero_position: Vector2i = first.sim.world.entities[state.protagonist_id].position
	var enemy_position: Vector2i = first.sim.world.entities[state.enemy_ids[0]].position
	check(hero_position.distance_to(enemy_position) > 6.0,
		"monster has scouting space outside the initial FOV")
	var observation := first.observe_party_world()
	check_eq(observation.visibility.mode, "LOS_RADIUS", "large map keeps bounded LOS")
	check_eq(observation.visibility.radius, 6, "large map keeps the 15x15 camera-safe FOV")
	var visible_count := 0
	var unseen_count := 0
	for cell in observation.cells:
		if str(cell.visibility_state) == "VISIBLE": visible_count += 1
		elif str(cell.visibility_state) == "UNSEEN": unseen_count += 1
	check(visible_count > 0 and visible_count <= 169,
		"observation reveals a local window rather than the whole dungeon")
	check(unseen_count > 0, "large dungeon begins with unexplored cells")
	check_eq(first.run_progress().entry_position,
		[hero_position.x, hero_position.y], "run manifest follows generated entry")
	return finish()


func test_large_map_save_load_regenerates_seeded_layout_exactly() -> bool:
	var source = Session.new(8080, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check(source.sim != null, "source large-map session initializes")
	if source.sim == null:
		return finish()
	var encoded := source.save_session_json()
	var restored = Session.new(1, 2, Session.SOLO_COMBAT_SCENARIO_ID)
	var result: Dictionary = restored.load_session_json(encoded)
	check(bool(result.get("accepted", false)),
		"large-map session load accepted: %s" % str(result))
	if bool(result.get("accepted", false)):
		check_eq(restored.sim.snapshot(), source.sim.snapshot(),
			"large-map save restore remains exact")
		check_eq(restored.run_progress(), source.run_progress(),
			"regenerated entry and exit stay exact")
	return finish()
