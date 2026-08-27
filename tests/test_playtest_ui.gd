extends "res://tests/test_case.gd"

const Scene = preload("res://playtest/playtest_sandbox.tscn")
const Session = preload("res://playtest/playtest_session.gd")

func test_main_scene_instantiates_as_control_with_session_dto() -> bool:
	var sandbox = Scene.instantiate()
	sandbox.initialize_for_headless_test(Session.new(7, 77))
	check(sandbox is Control, "main root control")
	check_eq(sandbox.grid.visible_cell_count(), 225, "15x15 detached grid")
	check_eq(sandbox.summaries.get_child_count(), 4, "four lead summary buttons")
	check(sandbox.inspector.text.contains("객관"), "reaction inspector populated")
	sandbox.free()
	return finish()

func test_grid_has_exact_world_coordinate_mapping() -> bool:
	var sandbox = Scene.instantiate()
	sandbox.initialize_for_headless_test(Session.new(7, 78))
	sandbox.grid.size = Vector2(330, 330)
	check_eq(sandbox.grid.local_cell_to_world(Vector2i.ZERO), Vector2i.ZERO, "top-left world mapping")
	check_eq(sandbox.grid.local_cell_to_world(Vector2i(14, 14)), Vector2i(14, 14), "bottom-right world mapping")
	var center: Vector2 = sandbox.grid.grid_rect().get_center()
	check_eq(sandbox.grid.position_to_world(center), Vector2i(7, 7), "pointer center mapping")
	sandbox.free()
	return finish()

func test_same_adjacent_selection_commits_exactly_one_move() -> bool:
	var sandbox = Scene.instantiate()
	var session = Session.new(7, 79)
	sandbox.initialize_for_headless_test(session)
	var lead_id: int = session.lead_roster()[2].entity_id
	check(session.select_lead(lead_id), "summary/grid share lead id")
	sandbox._refresh()
	check(sandbox.inspector.text.contains("#3"), "selected lead inspector")
	check_eq(session.lab_status().step_index, 0, "selection does not advance")
	sandbox.free()
	return finish()

func test_affinity_and_electric_certainty_are_distinct_in_card() -> bool:
	var sandbox = Scene.instantiate()
	var session = Session.new(7, 80)
	sandbox.initialize_for_headless_test(session)
	check(session.advance_ticks(1).ok, "decision available")
	sandbox._refresh()
	var detail: Dictionary = session.inspect_reaction(session.selected_lead_id)
	var candidate_count := 0
	for candidate in detail.candidates:
		candidate_count += 1
		for row in candidate.considerations:
			check(row.has("raw_input") and row.has("curve_output") and row.has("contribution"), "calculation row complete")
	check_eq(candidate_count, 6, "current plus MODE_GATE actions")
	sandbox._toggle_drawer()
	check(sandbox.drawer.visible and sandbox.drawer.text.contains("contribution"), "calculation drawer")
	check(sandbox.drawer.text.contains("committed decision trace") and sandbox.drawer.text.contains("live preview"),
		"committed trace is SSOT and live preview is separate")
	var frozen_time: int = session.lab_status().world_time
	sandbox._toggle_auto(); sandbox._advance(1)
	check(not sandbox.auto_running and session.lab_status().world_time == frozen_time, "open drawer blocks progress controls")
	sandbox.free()
	return finish()

func test_modal_layers_block_world_input_and_echo_is_ignored() -> bool:
	var sandbox = Scene.instantiate()
	var session = Session.new(7, 81)
	sandbox.initialize_for_headless_test(session)
	var before: int = session.lab_status().world_time
	sandbox.auto_running = false
	sandbox.auto_timer.timeout.emit()
	check_eq(session.lab_status().world_time, before, "paused timeout no-op")
	sandbox.auto_running = true
	sandbox._pause_auto()
	check(not sandbox.auto_running and sandbox.auto_timer.is_stopped(), "focus/modal pause")
	sandbox.free()
	return finish()

func test_portrait_resize_smoke_preserves_selection_and_session() -> bool:
	var sandbox = Scene.instantiate()
	var session = Session.new(7, 82)
	sandbox.initialize_for_headless_test(session)
	var selected: int = session.lead_roster()[1].entity_id
	session.select_lead(selected)
	var snapshot: String = session.snapshot_json()
	sandbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	for viewport_size in [Vector2(450, 800), Vector2(360, 640)]:
		sandbox.size = viewport_size; sandbox.grid.size = Vector2(minf(330, viewport_size.x - 12), 320)
		check(sandbox.grid.cell_size_px() >= 20.0, "15x15 readable at %s" % viewport_size)
		check(sandbox.grid.grid_rect().size.x <= viewport_size.x, "no horizontal grid overflow")
		var layout: Control = sandbox.get_node("LabLayout")
		check(layout.get_combined_minimum_size().x <= viewport_size.x - 12, "layout minimum width fits %s" % viewport_size)
		check(layout.get_combined_minimum_size().y <= viewport_size.y - 8, "layout minimum height fits %s" % viewport_size)
	sandbox._toggle_drawer()
	check(sandbox.drawer.visible and not sandbox.inspector.visible, "drawer replaces inspector in portrait layout")
	check(sandbox.get_node("LabLayout").get_combined_minimum_size().y <= 632, "open drawer fits 360x640")
	check_eq(session.selected_lead_id, selected, "selection preserved")
	check_eq(session.snapshot_json(), snapshot, "resize leaves world unchanged")
	sandbox.free()
	return finish()
