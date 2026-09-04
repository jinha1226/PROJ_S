extends "res://tests/test_case.gd"

const LabScene = preload("res://playtest/npc_expedition_lab.tscn")
const Simulator = preload("res://sim/npc_expedition/npc_expedition_simulator.gd")
const PartySimulator = preload("res://sim/party_combat_observer_simulator.gd")
const PartyScene = preload("res://playtest/party_encounter_sandbox.tscn")


func test_observer_opens_on_mobile_layout_with_map_status_and_decision_trace() -> bool:
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(Simulator.new(22002))
	lab.grid.size = Vector2(360, 290)
	check_eq(lab.root_layout.offset_left, 6.0, "observer keeps compact mobile gutter")
	check_eq(lab.step_button.custom_minimum_size.y, 44.0, "step action keeps touch target")
	check_eq(lab.speed_buttons.size(), 4, "four quick playback presets are visible")
	for speed_button in lab.speed_buttons.values():
		check_eq(speed_button.custom_minimum_size.y, 44.0,
			"each playback preset keeps its touch target")
	check_eq(lab.grid.custom_minimum_size, Vector2(360, 290), "15x13 map remains primary")
	check(lab.phase_label.text.contains("마을 · 원정 준비"), "macro phase is visible")
	check(lab.goal_label.text.contains("목표 ·"), "current macro goal is visible")
	check(lab.npc_status_label.text.contains("HP 100/100") \
		and lab.npc_status_label.text.contains("물약 2"), "NPC body and supply state are visible")
	check(lab.detail_text.text.contains("현재 판단 · 보급을 점검한다") \
		and lab.detail_text.text.contains("후보 행동") \
		and lab.detail_text.text.contains("HEXACO") \
		and lab.detail_text.text.contains("원정 상태기계"),
		"decision inspector exposes reason, candidates, and personality")
	check_eq(lab.grid.cell_center(Vector2i(1, 11)).is_finite(), true,
		"grid provides a stable map position for the entrance")
	lab.free()
	return finish()


func test_step_and_auto_controls_advance_the_same_simulator_without_hidden_resolution() -> bool:
	var simulation = Simulator.new(22002)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulation)
	check_eq(simulation.turn_index, 0, "opening the observer is read-only")
	lab._step_once()
	check_eq(simulation.turn_index, 1, "one-turn button resolves one autonomous turn")
	check(lab.detail_text.text.contains("T1 ·"), "resolved event appears immediately")
	lab.auto_button.set_pressed_no_signal(true)
	lab._toggle_auto()
	check(lab.auto_button.button_pressed and lab.auto_button.text == "일시 정지",
		"auto play visibly enters running state")
	lab._on_auto_tick()
	check_eq(simulation.turn_index, 2, "auto tick uses the same one-turn action")
	lab._stop_auto()
	check(not lab.auto_button.button_pressed and lab.auto_button.text == "자동 재생",
		"pause leaves the observer at a decision boundary")
	lab._reset_same_seed()
	check_eq(simulation.turn_index, 0, "same-seed reset returns to the first decision")
	lab.free()
	return finish()


func test_playback_speed_changes_timer_only_and_preserves_live_observation() -> bool:
	var simulation = Simulator.new(22002)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulation)
	var before: Dictionary = simulation.observation()
	lab.auto_button.set_pressed_no_signal(true)
	lab._toggle_auto()
	lab._set_playback_speed(4.0)
	check(is_equal_approx(lab.playback_speed, 4.0) \
		and is_equal_approx(lab.auto_timer.wait_time, 0.1),
		"4x preset changes the next automatic cadence immediately")
	check(lab.auto_button.button_pressed and lab.auto_button.text == "일시 정지",
		"speed changes do not pause an active observation")
	check_eq(simulation.observation(), before,
		"speed selection never advances or mutates the simulation")
	lab._set_playback_speed(0.5)
	check(is_equal_approx(lab.auto_timer.wait_time, 0.8) \
		and lab.speed_label.text.contains("0.5×"),
		"slow preset is visible and gives time to inspect a specific action")
	check(lab.speed_buttons[0.5].button_pressed and not lab.speed_buttons[4.0].button_pressed,
		"exactly the selected speed remains highlighted")
	lab._on_auto_tick()
	check_eq(simulation.turn_index, 1,
		"cadence still resolves the same single authoritative turn")
	lab.free()
	return finish()


func test_main_record_panel_has_no_npc_expedition_observer_entry() -> bool:
	var sandbox = PartyScene.instantiate()
	sandbox._build_ui()
	check(sandbox.find_child("NpcExpeditionLabButton",true,false)==null,
		"main product scene does not construct the observer entry")
	sandbox.free()
	return finish()


func test_same_observer_surface_runs_four_by_four_party_combat_automatically() -> bool:
	var simulation=PartySimulator.new(17)
	var opening:Dictionary=simulation.observation()
	check_eq(opening.mode,"PARTY_COMBAT","observer enters party mode")
	check_eq([opening.party.count,opening.enemy_force.count],[4,4],
		"party observer starts with four actors per force")
	check(opening.next_queue.size()>=4,"top queue exposes automatic upcoming actions")
	check(not opening.intent_lines.is_empty(),"thin target-line data is available")
	var lab=LabScene.instantiate()
	lab.initialize_for_headless_test(simulation)
	check(lab.turn_queue_label.visible and lab.turn_queue_label.text.begins_with("NEXT"),
		"shared top HUD renders NEXT tokens")
	check(lab.npc_status_label.text.contains("파티 4명") \
		and lab.monster_status_label.text.contains("적군 4체"),
		"two compact force summaries replace one-to-one cards")
	check(lab.detail_text.text.contains("개별 시야 → 파티 공유 → 자동 경고 → 암묵적 지시"),
		"party inspector states the zero-input control flow")
	lab._step_once()
	check_eq(simulation.turn_index,1,"one-turn control advances one complete party round")
	check(simulation.session.sim.world.world_state_error().is_empty(),
		"observed party round remains canonical")
	lab._toggle_observer_mode()
	check_eq(lab.observer_mode,"NPC","same surface can return to one-to-one expedition")
	check(not lab.turn_queue_label.visible,"one-to-one mode hides party queue")
	lab.free()
	return finish()


func test_party_observer_autoplay_reaches_a_canonical_terminal_boundary() -> bool:
	var simulation=PartySimulator.new(29)
	var resolved_turns:=0
	while not bool(simulation.observation().get("terminal",false)) \
			and resolved_turns<simulation.MAX_TURNS:
		var result:Dictionary=simulation.step()
		check(bool(result.get("accepted",false)),
			"every observed automatic party round is accepted")
		if not bool(result.get("accepted",false)):break
		check(simulation.session.sim.world.world_state_error().is_empty(),
			"every observed automatic party round stays canonical")
		resolved_turns+=1
	check(resolved_turns>1,"autoplay observes more than an opening snapshot")
	check(bool(simulation.observation().get("terminal",false)),
		"autoplay stops at combat outcome or the explicit observer turn cap")
	return finish()
