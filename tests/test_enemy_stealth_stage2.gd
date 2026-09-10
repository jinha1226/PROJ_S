extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const VisualMap = preload("res://playtest/party_visual_test_map.gd")
const VisionRules = preload("res://sim/vision_rules.gd")


func test_enemy_vision_overlay_is_visible_only_and_uses_common_query() -> bool:
	var session = Session.new(607, 20260828, VisualMap.SHOWCASE_SCENARIO_ID)
	var world = session.sim.world
	var overlay: Dictionary = session.enemy_vision_overlay()
	check(bool(overlay.get("available", false)), "enemy overlay is available")
	var rows: Array = overlay.get("rows", [])
	check(not rows.is_empty(), "visible enemy produces an overlay row")
	var hero = world.entities[world.party_control_actor_id()]
	var player_visible: Dictionary = session._presentation_visible_cells(hero.position)
	for row_value in rows:
		var row: Dictionary = row_value
		var enemy_id := int(row.get("enemy_id", -1))
		check(player_visible.has(str(row.enemy_position[0]) + ":" + str(row.enemy_position[1])),
			"overlay never exposes an unseen enemy position")
		var enemy = world.entities[enemy_id]
		var profile: Dictionary = VisionRules.profile_for_entity(enemy)
		var facing: Vector2i = VisionRules.facing_for_entity(world, enemy_id)
		var lighting: Dictionary = VisionRules.lighting_for_scenario(session.scenario_id)
		for cell_value in row.cells:
			var cell: Dictionary = cell_value
			var position := Vector2i(int(cell.position[0]), int(cell.position[1]))
			check(player_visible.has("%d:%d" % [position.x, position.y]),
				"overlay clips hidden terrain")
			var observation: Dictionary = VisionRules.observe(world, enemy.position, position,
				facing, profile, lighting)
			check(bool(observation.get("visible", false)),
				"overlay cell comes from common vision query")
		check_eq(row.get("awareness_state", ""),
			str(world.party_encounter.enemy_awareness(enemy_id).awareness_state),
			"overlay state is canonical awareness")
	var hidden_enemy = world.entities[int(world.party_encounter.enemy_ids[0])]
	hidden_enemy.position = Vector2i(13, 1)
	var hidden_overlay: Dictionary = session.enemy_vision_overlay()
	check_eq((hidden_overlay.get("rows", []) as Array).size(), 0,
		"unseen enemy has no overlay row")
	return finish()


func test_lost_sight_keeps_last_known_position_and_return_is_evented() -> bool:
	var session = Session.new(608, 20260828, VisualMap.SOLO_FIXTURE_SCENARIO_ID)
	var world = session.sim.world
	var state = world.party_encounter
	state.legacy_contact_rule = false
	var hero = world.entities[state.protagonist_id]
	var enemy = world.entities[state.enemy_ids[0]]
	enemy.position = hero.position + Vector2i(4, 0)
	check(session.sim.party_coordinator._update_enemy_awareness(enemy.id, 1),
		"visible awareness update succeeds")
	var awareness = state.enemy_awareness(enemy.id)
	var last_known: Vector2i = awareness.last_known_target_position
	check(last_known == hero.position, "visible update records last known position")
	awareness.awareness_state = "HUNTING"
	awareness.suspicion = 1000
	world.tile_at(enemy.position + Vector2i(-2, 0)).terrain = "wall"
	hero.position = Vector2i(2, 2)
	check(session.sim.party_coordinator._update_enemy_awareness(enemy.id, 2),
		"lost-sight awareness update succeeds")
	check_eq(awareness.awareness_state, "SEARCHING", "lost sight starts searching")
	check_eq(awareness.last_known_target_position, last_known,
		"lost sight never replaces last known position with current player position")
	var before_events: int = world.events.size()
	awareness.awareness_state = "RETURNING"
	awareness.suspicion = 100
	enemy.position = awareness.home_position
	check(session.sim.party_coordinator._update_enemy_awareness(enemy.id, 3),
		"home return update succeeds")
	check_eq(awareness.awareness_state, "UNAWARE", "home arrival resets awareness")
	check_eq(world.events.size(), before_events + 1, "return reset emits one transition")
	var event = world.events[-1]
	check_eq(event.type, "enemy.awareness_changed", "return transition event type")
	return finish()


func test_enemy_overlay_query_is_pure() -> bool:
	var session = Session.new(609, 20260828, VisualMap.SOLO_FIXTURE_SCENARIO_ID)
	var before: Dictionary = session.sim.snapshot()
	var first: Dictionary = session.enemy_vision_overlay()
	var second: Dictionary = session.enemy_vision_overlay()
	check_eq(first, second, "repeated overlay query is deterministic")
	check_eq(session.sim.snapshot(), before, "overlay query does not mutate simulation")
	return finish()
