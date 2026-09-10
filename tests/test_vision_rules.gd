extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const VisionRules = preload("res://sim/vision_rules.gd")
const VisionProfiles = preload("res://sim/vision_profile_registry.gd")
const VisualMap = preload("res://playtest/party_visual_test_map.gd")
const PartyState = preload("res://sim/party_encounter_state.gd")
const Session = preload("res://playtest/party_playtest_session.gd")


func test_profile_registry_inheritance_and_fallback() -> bool:
	check_eq(VisionProfiles.registry_error(), "", "vision profile registry")
	var human: Dictionary = VisionProfiles.profile_for("human")
	var scout: Dictionary = VisionProfiles.profile_for("human", "scout")
	var unknown: Dictionary = VisionProfiles.profile_for("unknown_species")
	check_eq(human.get("base_sight_range"), 6, "human base profile")
	check_eq(scout.get("base_sight_range"), 8, "monster type override inherits species")
	check_eq(scout.get("dark_vision_milli"), human.get("dark_vision_milli"),
		"override leaves unspecified species fields intact")
	check_eq(unknown.get("base_sight_range"), VisionProfiles.BASE_PROFILE.base_sight_range,
		"unknown species falls back to base")
	return finish()


func test_bright_is_omnidirectional_and_dark_is_forward_peripheral() -> bool:
	var sim = Simulator.new(9, 3, 601)
	var profile: Dictionary = VisionProfiles.profile_for("human")
	profile.dark_vision_milli = 500
	var dark: Dictionary = {"ambient_level": 120, "sources": []}
	var bright: Dictionary = {"ambient_level": 900, "sources": []}
	var origin := Vector2i(4, 1)
	var front := VisionRules.observe(sim.world, origin, Vector2i(6, 1), Vector2i.RIGHT,
		profile, dark)
	var rear := VisionRules.observe(sim.world, origin, Vector2i(2, 1), Vector2i.RIGHT,
		profile, dark)
	var bright_rear := VisionRules.observe(sim.world, origin, Vector2i(2, 1), Vector2i.RIGHT,
		profile, bright)
	var torch_rear := VisionRules.observe(sim.world, origin, Vector2i(2, 1), Vector2i.RIGHT,
		profile, {"ambient_level": 120, "sources": [
			{"position": [2, 1], "brightness": 1000, "radius": 1}]})
	check(bool(front.visible), "dark forward target remains visible")
	check(not bool(rear.visible), "dark rear target is outside peripheral range")
	check(bool(bright_rear.visible), "bright light restores omnidirectional sight")
	check(bool(torch_rear.visible), "lit target is visible from darkness")
	check_eq(str(bright_rear.observer_light_band), "BRIGHT", "bright band")
	return finish()


func test_wall_closed_door_and_smoke_block_line_of_sight() -> bool:
	for terrain_id in ["wall", "door_closed"]:
		var sim = Simulator.new(5, 1, 602)
		check(sim.world.bootstrap_set_terrain(Vector2i(2, 0), terrain_id), terrain_id + " setup")
		var through: Dictionary = VisionRules.observe(sim.world, Vector2i(0, 0), Vector2i(4, 0),
			Vector2i.RIGHT, VisionProfiles.profile_for("human"))
		var own_cell: Dictionary = VisionRules.observe(sim.world, Vector2i(0, 0), Vector2i(2, 0),
			Vector2i.RIGHT, VisionProfiles.profile_for("human"))
		check(not bool(through.visible), terrain_id + " blocks LOS")
		check(bool(own_cell.visible), terrain_id + " cell remains observable")
	var smoke_sim = Simulator.new(5, 1, 603)
	check(smoke_sim.world.bootstrap_set_atmosphere(Vector2i(2, 0), 500, 700, 0, 0),
		"smoke setup")
	var smoke_through: Dictionary = VisionRules.observe(smoke_sim.world, Vector2i(0, 0),
		Vector2i(4, 0), Vector2i.RIGHT, VisionProfiles.profile_for("human"))
	var smoke_cell: Dictionary = VisionRules.observe(smoke_sim.world, Vector2i(0, 0),
		Vector2i(2, 0), Vector2i.RIGHT, VisionProfiles.profile_for("human"))
	check(not bool(smoke_through.visible), "dense smoke blocks LOS")
	check(bool(smoke_cell.visible), "smoke cell remains observable")
	return finish()


func test_presentation_uses_common_query_and_repeated_query_is_deterministic() -> bool:
	var sim = Simulator.new(7, 3, 604)
	check(sim.world.bootstrap_set_atmosphere(Vector2i(3, 1), 500, 700, 0, 0),
		"presentation smoke setup")
	var profile: Dictionary = VisionProfiles.profile_for("human")
	var expected: Dictionary = VisionRules.visible_cells(sim.world, Vector2i(0, 1), Vector2i.RIGHT,
		profile, VisionRules.lighting_for_scenario(VisualMap.SHOWCASE_SCENARIO_ID))
	var presented: Dictionary = VisualMap.visible_cells(sim.world, Vector2i(0, 1),
		VisualMap.SHOWCASE_SCENARIO_ID)
	check_eq(presented, expected, "presentation delegates to common vision query")
	check_eq(VisionRules.visible_cells(sim.world, Vector2i(0, 1), Vector2i.RIGHT,
		profile), VisionRules.visible_cells(sim.world, Vector2i(0, 1), Vector2i.RIGHT,
		profile), "repeated query is deterministic")
	return finish()


func test_facing_save_roundtrip_and_snapshot_are_exact() -> bool:
	var state = PartyState.new()
	state.facing = Vector2i.LEFT
	var wire: Dictionary = state.to_dict()
	var restored = PartyState.from_dict(wire)
	check(restored != null and restored.facing == Vector2i.LEFT, "facing survives state wire")
	var sim = Simulator.new(3, 3, 605)
	var before: Dictionary = sim.snapshot()
	var after: Dictionary = Simulator.from_snapshot(before).snapshot()
	check_eq(after, before, "vision-independent snapshot replay remains exact")
	return finish()


func test_development_vision_projection_reuses_authoritative_query_after_save() -> bool:
	var session = Session.new(606, 20260828, VisualMap.VISION_TEST_SCENARIO_ID)
	var debug_before: Dictionary = session.vision_debug_observation()
	check(bool(debug_before.get("available", false)), "development vision projection available")
	check_eq(debug_before.get("ruleset_id"), VisionRules.RULESET_ID, "debug ruleset id")
	check_eq((debug_before.get("cells", []) as Array).size(),
		int(session.sim.world.width) * int(session.sim.world.height), "debug covers test map")
	var encoded: String = session.save_session_json()
	var restored = Session.new()
	var loaded: Dictionary = restored.load_session_json(encoded)
	check(bool(loaded.get("accepted", false)), "vision scenario save loads")
	var debug_after: Dictionary = restored.vision_debug_observation()
	check_eq(debug_after, debug_before, "debug projection survives save/load exactly")
	return finish()
