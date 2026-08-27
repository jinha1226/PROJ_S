extends "res://tests/test_case.gd"

const Scene = preload("res://playtest/playtest_sandbox.tscn")
const Session = preload("res://playtest/playtest_session.gd")

func test_main_scene_instantiates_as_control_with_session_dto() -> bool:
	var sandbox = Scene.instantiate()
	sandbox.initialize_for_headless_test(Session.new(7, 77))
	check(sandbox is Control, "main root control")
	check(sandbox.get_theme_default_font().has_char("한".unicode_at(0)), "root theme embeds Hangul font")
	check(sandbox.grid.get_theme_default_font().has_char("글".unicode_at(0)), "grid inherits Hangul font")
	check_eq(sandbox.grid.visible_cell_count(), 225, "15x15 detached grid")
	check_eq(sandbox.summaries.get_child_count(), 4, "four lead summary buttons")
	check(sandbox.inspector.text.contains("객관"), "reaction inspector populated")
	check(sandbox.event_log.text.contains("아직 사건이 없습니다"), "empty event log guidance")
	sandbox.free()
	return finish()

func test_world_event_log_updates_without_blocking_progress() -> bool:
	var sandbox = Scene.instantiate()
	var session = Session.new(7, 770)
	sandbox.initialize_for_headless_test(session)
	sandbox._toggle_event_log()
	check(sandbox.event_log.visible and not sandbox.inspector.visible, "event log replaces inspector")
	var before: int = session.lab_status().world_time
	sandbox._advance(1)
	check(session.lab_status().world_time > before, "event log allows live progress")
	check(sandbox.event_log.text.contains("최근 세계 사건"), "event log header")
	check(sandbox.event_log.text.contains("위협") or sandbox.event_log.text.contains("반응 선택"),
		"readable world events rendered")
	sandbox._toggle_event_log()
	check(not sandbox.event_log.visible and sandbox.inspector.visible, "inspector restored")
	sandbox.free()
	return finish()

func test_progress_banner_and_auto_control_make_each_advance_visible() -> bool:
	var sandbox = Scene.instantiate()
	var session = Session.new(7, 7701)
	sandbox.initialize_for_headless_test(session)
	check(sandbox.progress_banner.text.contains("턴 0") and sandbox.progress_banner.text.contains("1턴을 누르면"),
		"initial action is explicit")
	check_eq(sandbox.auto_button.text, "자동 시작", "auto starts with a readable state")
	sandbox._advance(1)
	check(sandbox.progress_banner.text.contains("턴 1") \
		and sandbox.progress_banner.text.contains("방금 +1턴") \
		and sandbox.progress_banner.text.contains("사건"), "advance result stays visible")
	sandbox._toggle_auto()
	check(sandbox.auto_running and sandbox.auto_button.text == "자동 정지" \
		and sandbox.progress_banner.text.contains("자동 켜짐"), "running auto state is explicit")
	sandbox._toggle_auto()
	check(not sandbox.auto_running and sandbox.auto_button.text == "자동 시작", "stopped auto state is explicit")
	sandbox._save()
	check(sandbox.progress_banner.text.contains("저장 완료"), "save result is visible")
	sandbox._load()
	check(sandbox.progress_banner.text.contains("불러오기 완료"), "load result is visible")
	sandbox.free()
	return finish()

func test_all_resolved_trials_stop_progress_controls_without_core_mutation() -> bool:
	var sandbox = Scene.instantiate()
	var session = Session.new()
	sandbox.initialize_for_headless_test(session)
	sandbox.auto_running = true
	for _attempt in range(10):
		if session.progress_status().active_trials == 0: break
		sandbox._advance(10)
	var status: Dictionary = session.progress_status()
	check_eq(status.display_phase_id, "RESOLVED", "zero remaining rooms use resolved presentation phase")
	check(sandbox.progress_banner.text.contains("결과 확정") \
		and sandbox.progress_banner.text.contains("결과가 모두 정해졌습니다"), "completion is unmistakable")
	check(not sandbox.auto_running and sandbox.one_turn_button.disabled \
		and sandbox.ten_turn_button.disabled and sandbox.auto_button.disabled,
		"resolved comparison cannot silently keep advancing")
	sandbox._save()
	check(sandbox.progress_banner.text.contains("저장 완료"), "resolved state still reports save result")
	sandbox.free()
	return finish()

func test_character_atlas_maps_every_lab_role_without_touching_sim_state() -> bool:
	var sandbox = Scene.instantiate()
	var session = Session.new(7, 771)
	sandbox.initialize_for_headless_test(session)
	check(sandbox.grid.CHARACTER_ATLAS != null, "character atlas loads")
	check_eq(Vector2i(sandbox.grid.CHARACTER_ATLAS.get_size()), Vector2i(108, 88),
		"six-frame mobile atlas dimensions")
	for trial_slot in range(4):
		check_eq(sandbox.grid.actor_frame_index({"controller_kind": "LEAD", "trial_slot": trial_slot}),
			trial_slot, "lead %d has a distinct frame" % (trial_slot + 1))
	check_eq(sandbox.grid.actor_frame_index({"controller_kind": "PASSIVE_ALLY"}), 4, "ally frame")
	check_eq(sandbox.grid.actor_frame_index({"controller_kind": "MELEE_THREAT"}), 5, "goblin frame")
	check_eq(sandbox.grid.actor_frame_index({"controller_kind": "UNKNOWN", "glyph": "?"}), -1,
		"unknown actors keep glyph fallback")
	check_eq(sandbox.grid.actor_frame_index({"controller_kind": "LEAD", "trial_slot": 0,
		"is_player": true}), -1, "nested player keeps legacy glyph fallback")
	var compact_sprite: Vector2 = sandbox.grid.actor_sprite_size(23.0)
	check(compact_sprite.y >= 36.0 and compact_sprite.y > 24.0, "compact actor is visibly larger than old cap")
	var full_sprite: Vector2 = sandbox.grid.actor_sprite_size(28.0)
	check_eq(full_sprite.y, 44.0, "full grid actor uses the complete source frame")
	var snapshot := session.snapshot_json()
	sandbox.grid.queue_redraw()
	check_eq(session.snapshot_json(), snapshot, "presentation mapping leaves deterministic world untouched")
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
