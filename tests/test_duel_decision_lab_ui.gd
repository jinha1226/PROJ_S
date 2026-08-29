extends "res://tests/test_case.gd"

const LabScene = preload("res://playtest/duel_decision_lab.tscn")
const Grid = preload("res://playtest/duel_decision_grid.gd")
const FakeSimulator = preload("res://tests/duel_decision_ui_fake.gd")
const RealSimulator = preload("res://sim/dungeon_population/dungeon_population_simulator.gd")
const PartyScene = preload("res://playtest/party_encounter_sandbox.tscn")
const PartySession = preload("res://playtest/party_playtest_session.gd")


func test_lab_presents_two_actor_map_and_large_readable_cards() -> bool:
	var simulator = FakeSimulator.new(301)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulator)
	lab.grid.size = Vector2(300, 300)
	check_eq(lab.grid.visible_cell_count(), 225, "15x15 decision map")
	check_eq(lab.grid.actor_count(), 2, "exactly two actors are presented")
	check(lab.actor_buttons[0].text.contains("라온") and lab.actor_buttons[0].text.contains("HP 82/100"),
		"actor A card tab shows identity and body state")
	check(lab.actor_buttons[1].text.contains("모그") and lab.actor_buttons[1].text.contains("HP 46/90"),
		"actor B card tab shows identity and body state")
	check(lab.detail_text.text.contains("장검 · 전투력 67") and lab.detail_text.text.contains("출혈 3턴"),
		"active card shows weapon and DOT")
	check(lab.detail_text.text.contains("HEXACO  H 620") and lab.detail_text.text.contains("O 540"),
		"all six HEXACO axes are visible")
	check_eq(simulator.step_calls, 0, "rendering DTO does not resolve a turn")
	lab.free()
	return finish()


func test_candidate_breakdown_uses_korean_sentences_and_all_score_buckets() -> bool:
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(FakeSimulator.new(302))
	var card: String = lab.actor_card_text("actor_a")
	check(card.contains("최종 판단 · 맞서 싸운다") and card.contains("몸 상태가 버틸 만해"),
		"selected action has a natural-language reason")
	check(card.contains("기본") and card.contains("성격") and card.contains("상태") \
		and card.contains("종족 관계") and card.contains("개인 기억") and card.contains("상황") \
		and card.contains("작은 변동") and card.contains("합계"), "candidate exposes every required bucket")
	check(card.contains("정직-겸손") or card.contains("외향성"), "HEXACO contribution is named for players")
	check(card.contains("거부 · 숨을 고르며 쉰다") and card.contains("안전하게 쉴 수 없습니다"),
		"illegal candidate explains rejection in Korean")
	check(not card.contains("ENGAGE") and not card.contains("FLEE") and not card.contains("REST"),
		"internal action ids stay out of the player-facing card")
	lab.free()
	return finish()


func test_grid_hit_selects_each_actor_without_advancing_core() -> bool:
	var simulator = FakeSimulator.new(303)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulator)
	lab.grid.size = Vector2(300, 300)
	var center: Variant = lab.grid.actor_screen_center("actor_b")
	check(center != null, "actor B has a visible map center")
	check_eq(lab.grid.actor_id_at_point(center), "actor_b", "map hit maps to actor B")
	lab._on_actor_pressed("actor_b")
	check_eq(lab.selected_actor_id, "actor_b", "map tap selects actor B")
	check(lab.detail_text.text.contains("모그 · 고블린") and lab.detail_text.text.contains("굽은 단검"),
		"actor B card replaces actor A card")
	check_eq(simulator.step_calls, 0, "actor selection is read-only")
	lab.free()
	return finish()


func test_step_resolves_both_decisions_once_and_surfaces_relation_event() -> bool:
	var simulator = FakeSimulator.new(304)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulator)
	lab._step()
	check_eq(simulator.step_calls, 1, "decision button calls one simultaneous core step")
	check(lab.phase_label.text.contains("인간은 맞섰고") and lab.phase_label.text.contains("고블린은"),
		"resolution stays visible in outcome banner")
	check_eq(lab.step_button.text, "다음 턴", "subsequent action is explicit")
	lab._show_events()
	check(lab.detail_text.text.contains("동시 해결") and lab.detail_text.text.contains("관계 ·") \
		and lab.detail_text.text.contains("경계 +12"), "event log includes simultaneous result and relation change")
	lab.free()
	return finish()


func test_same_situation_restart_and_seeded_new_situation_are_distinct_commands() -> bool:
	var simulator = FakeSimulator.new(305)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulator)
	lab._step()
	lab._restart_same_situation()
	check_eq(simulator.restart_calls, 1, "same-situation restart calls dedicated facade command")
	check_eq(simulator.tick_index, 0, "same situation rewinds turn")
	check_eq(simulator.seed_value, 305, "same situation keeps seed")
	lab.seed_edit.text = "9901"
	lab._new_random_situation()
	check_eq(simulator.random_calls, 1, "new situation calls dedicated facade command")
	check_eq(simulator.seed_value, 9901, "typed seed selects reproducible new situation")
	check(lab.phase_label.text.contains("seed 9901의 새 상황"), "new situation result stays visible")
	lab._new_random_situation()
	check_eq(simulator.seed_value, 9902, "unchanged seed field advances to a genuinely new deterministic situation")
	lab.free()
	return finish()


func test_grid_mapping_remains_exact_and_actor_visuals_keep_logical_cells() -> bool:
	var grid = Grid.new()
	grid.size = Vector2(300, 300)
	grid.set_observation({"actors": [
		{"id": "a", "position": [2, 3], "hp": 10, "max_hp": 10, "alive": true, "weapon": "창"},
		{"id": "b", "position": [12, 11], "hp": 10, "max_hp": 10, "alive": true, "weapon": "활"},
	]}, "a")
	check_eq(grid.pixel_to_world_cell(grid.world_to_pixel_center(Vector2i(2, 3))), Vector2i(2, 3),
		"actor A presentation keeps exact logical cell")
	check_eq(grid.pixel_to_world_cell(grid.world_to_pixel_center(Vector2i(12, 11))), Vector2i(12, 11),
		"actor B presentation keeps exact logical cell")
	check_eq(grid.display_spec().grid_size, 15, "grid dimension is immutable")
	grid.free()
	return finish()


func test_real_duel_facade_integrates_without_leaking_action_ids_to_ui() -> bool:
	var simulator = RealSimulator.new(7711)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulator)
	lab.grid.size = Vector2(300, 300)
	var observation: Dictionary = simulator.observation()
	check_eq(observation.map_size, [15, 15], "real facade map contract")
	check_eq(observation.actors.size(), 2, "real facade exposes two actors")
	check_eq(lab.grid.actor_count(), 2, "real actors reach map presentation")
	check(not simulator.decision_breakdowns().is_empty(), "real facade exposes decision candidates")
	var first_id := str(observation.actors[0].id)
	var card: String = lab.actor_card_text(first_id)
	check(card.contains("행동 후보 점수") and card.contains("종족 관계") and card.contains("개인 기억"),
		"real candidate DTO reaches breakdown card")
	for action_id in ["APPROACH", "ENGAGE", "FLEE", "HOLD", "SELF_TREAT"]:
		check(not card.contains(action_id), "card hides internal id %s" % action_id)
	var before := int(str(observation.tick_index))
	lab._step()
	check_eq(int(str(simulator.observation().tick_index)), before + 1, "real simultaneous step advances once")
	lab._show_events()
	for action_id in ["APPROACH", "ENGAGE", "FLEE", "HOLD", "SELF_TREAT"]:
		check(not lab.detail_text.text.contains(action_id), "event log translates internal id %s" % action_id)
	lab.free()
	return finish()


func test_main_party_scene_has_clear_two_actor_lab_entry() -> bool:
	var sandbox = PartyScene.instantiate()
	sandbox.initialize_for_headless_test(PartySession.new(), false)
	check(sandbox.duel_lab_button != null and sandbox.duel_lab_button.text == "2인 판단 실험",
		"main playtest exposes decision LAB")
	check_eq(sandbox.duel_lab_button.get_parent(), sandbox.phase_row,
		"entry shares existing banner row instead of growing portrait layout")
	check_eq(sandbox.duel_lab_button.custom_minimum_size.y, 44.0, "entry keeps mobile touch target")
	sandbox.free()
	return finish()
