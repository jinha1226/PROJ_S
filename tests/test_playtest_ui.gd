extends SimTestCase

const SceneResource = preload("res://playtest/playtest_sandbox.tscn")
const GridScript = preload("res://playtest/playtest_grid_view.gd")


func test_main_scene_instantiates_as_control_with_session_dto() -> bool:
	var sandbox := _make_sandbox()
	check(sandbox is Control, "main scene root is Control")
	check_eq(ProjectSettings.get_setting("application/run/main_scene"),
		"res://playtest/playtest_sandbox.tscn", "project main scene")
	check_eq(sandbox.get_node("SafeMargin/MainColumn/GridPanel/GridView").call("visible_cell_count"),
		81, "session supplies 9x9 detached visible cells")
	check(str(sandbox.get_node("SafeMargin/MainColumn/Hud/HudMargin/HudRows/Top/Hp").text).contains("100/100"),
		"HUD reads authoritative health")
	check(str(sandbox.get_node("SafeMargin/MainColumn/Hud/HudMargin/HudRows/Bottom/Seed").text).contains("0007"),
		"HUD reads authoritative seed")
	var bundled_font: Font = sandbox.theme.default_font
	check(bundled_font != null and bundled_font.has_char("한".unicode_at(0)),
		"bundled UI font contains Korean glyphs for Web export")
	_free_sandbox(sandbox)
	return finish()


func test_grid_has_exact_world_coordinate_mapping() -> bool:
	var grid: Control = GridScript.new()
	grid.size = Vector2(414, 414)
	var cells: Array[Dictionary] = []
	for local_y in range(9):
		for local_x in range(9):
			cells.append({
				"position": [8 + local_x, 14 + local_y],
				"local_position": [local_x, local_y],
				"terrain_id": "floor",
			})
	grid.call("set_view", cells, Vector2i(12, 18), Vector2i(12, 18))
	check_eq(grid.call("visible_cell_count"), 81, "exactly 81 cells")
	check_eq(grid.call("local_cell_to_world", Vector2i(0, 0)), Vector2i(8, 14), "top-left world coordinate")
	check_eq(grid.call("world_to_local_cell", Vector2i(16, 22)), Vector2i(8, 8), "bottom-right local coordinate")
	var rect: Rect2 = grid.call("grid_rect")
	check_eq(grid.call("position_to_world", rect.position + Vector2(4.5, 4.5) * 44.0),
		Vector2i(12, 18), "pointer center converts to camera world cell")
	grid.free()
	return finish()


func test_same_adjacent_selection_commits_exactly_one_move() -> bool:
	var sandbox := _make_sandbox()
	var session: Variant = sandbox.get("_session")
	var before: Dictionary = session.world_status()
	sandbox.call("select_world_position", Vector2i(5, 4))
	var selected_only: Dictionary = session.world_status()
	check_eq(selected_only.step_index, before.step_index, "first tap only selects")
	sandbox.call("select_world_position", Vector2i(5, 4))
	var after: Dictionary = session.world_status()
	check_eq(after.step_index, before.step_index + 1, "second same tap commits one step")
	check_eq(session.player_state().position, [5, 4], "authoritative player moved")
	check(str(sandbox.get_node("SafeMargin/MainColumn/Timeline/TimelineLabel").text).begins_with("실제:"),
		"actual timeline remains visible after refresh")
	_free_sandbox(sandbox)
	return finish()


func test_affinity_and_electric_certainty_are_distinct_in_card() -> bool:
	var sandbox := _make_sandbox()
	sandbox.call("select_world_position", Vector2i(8, 8))
	var evaluation: String = sandbox.get_node("SafeMargin/MainColumn/Inspection/Margin/Rows/Evaluation").text
	check(evaluation.contains("물 60"), "human shallow-water risk is 60")
	sandbox.call("_reset_session", 7, "amphibian")
	sandbox.call("select_world_position", Vector2i(8, 8))
	evaluation = sandbox.get_node("SafeMargin/MainColumn/Inspection/Margin/Rows/Evaluation").text
	check(evaluation.contains("물 0"), "amphibian shallow-water risk is 0")
	sandbox.call("_reset_session", 7, "dwarf")
	sandbox.call("select_world_position", Vector2i(8, 8))
	evaluation = sandbox.get_node("SafeMargin/MainColumn/Inspection/Margin/Rows/Evaluation").text
	check(evaluation.contains("물 100"), "dwarf shallow-water risk is 100")
	sandbox.call("select_world_position", Vector2i(22, 24))
	var electric: String = sandbox.get_node("SafeMargin/MainColumn/Inspection/Margin/Rows/Electric").text
	check(electric.contains("전기위험 없음"), "conductivity does not imply persistent electric risk")
	_free_sandbox(sandbox)
	return finish()


func test_modal_layers_block_world_input_and_echo_is_ignored() -> bool:
	var sandbox := _make_sandbox()
	var session: Variant = sandbox.get("_session")
	sandbox.call("set_drawer_open", true)
	sandbox.call("select_world_position", Vector2i(5, 4))
	sandbox.call("select_world_position", Vector2i(5, 4))
	check_eq(session.world_status().step_index, 0, "drawer blocks map commits")
	sandbox.call("set_drawer_open", false)
	var echo_event := InputEventKey.new()
	echo_event.keycode = KEY_RIGHT
	echo_event.pressed = true
	echo_event.echo = true
	sandbox.call("_unhandled_input", echo_event)
	check_eq(session.world_status().step_index, 0, "keyboard echo does not submit")
	var press_event := InputEventKey.new()
	press_event.keycode = KEY_RIGHT
	press_event.pressed = true
	sandbox.call("_unhandled_input", press_event)
	check_eq(session.world_status().step_index, 1, "one keyboard press submits one move")
	_free_sandbox(sandbox)
	return finish()


func test_portrait_resize_smoke_preserves_selection_and_session() -> bool:
	var sandbox := _make_sandbox()
	var session: Variant = sandbox.get("_session")
	var snapshot_before := str(session.snapshot_json())
	sandbox.call("select_world_position", Vector2i(8, 8))
	for viewport_size in [Vector2(360, 640), Vector2(450, 800), Vector2(540, 960)]:
		sandbox.size = viewport_size
		sandbox.call("_on_viewport_resized")
		check_eq(sandbox.call("selected_position"), Vector2i(8, 8), "resize keeps detached selection")
		check(sandbox.get_node("SafeMargin/MainColumn/Actions/Move").custom_minimum_size.y >= 44.0,
			"touch action remains at least 44px")
	check_eq(str(session.snapshot_json()), snapshot_before, "resize does not mutate authoritative world")
	_free_sandbox(sandbox)
	return finish()


func _make_sandbox() -> Control:
	var sandbox: Control = SceneResource.instantiate()
	sandbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sandbox.size = Vector2(450, 800)
	sandbox.call("initialize_for_headless_test")
	return sandbox


func _free_sandbox(sandbox: Control) -> void:
	sandbox.free()
