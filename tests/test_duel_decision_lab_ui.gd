extends "res://tests/test_case.gd"

const LabScene = preload("res://playtest/duel_decision_lab.tscn")
const Grid = preload("res://playtest/duel_decision_grid.gd")
const FakeSimulator = preload("res://tests/duel_decision_ui_fake.gd")
const REAL_SIMULATOR_PATH := "res://sim/dungeon_population/dungeon_population_simulator.gd"
const PartyScene = preload("res://playtest/party_encounter_sandbox.tscn")
const PartySession = preload("res://playtest/party_playtest_session.gd")


func test_lab_presents_five_actor_map_and_compact_selectable_cards() -> bool:
	var simulator = FakeSimulator.new(301)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulator)
	lab.grid.size = Vector2(315, 315)
	check_eq(lab.grid.visible_cell_count(), 441, "21x21 observation map")
	check_eq(lab.grid.actor_count(), 5, "exactly five actors are presented")
	var floor_spec:=Grid.floor_presentation_spec()
	check_eq([floor_spec.terrain_id,floor_spec.glyph,floor_spec.fake_terrain_count],
		["floor",".",0],"LAB renders only core-declared open floor and invents no terrain")
	check(not floor_spec.draw_image and not floor_spec.draw_tile_border,
		"LAB floor is code glyph over a neutral continuous backdrop")
	check(lab.situation_label.text.contains("21×21 던전") \
		and lab.situation_label.text.contains("인물 5명"), "short summary preserves map priority")
	check(lab.actor_buttons[0].text.contains("라온") and lab.actor_buttons[0].text.contains("HP 82"),
		"actor A overview shows identity and body state")
	check(lab.actor_buttons[4].text.contains("키리") and lab.actor_buttons[4].text.contains("HP 73"),
		"all five compact cards expose identity and body state")
	check_eq(lab.actor_buttons.size(), 5, "five selectable overview chips replace two large cards")
	for button in lab.actor_buttons:
		check_eq(button.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART,
			"360px overview cards wrap whole words")
		check_eq(button.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING,
			"overview cards never replace reasons or traits with ellipsis")
		for line in button.text.split("\n"):
			check(line.length() <= 10, "compact chip line stays within the mobile copy budget")
	check(not lab.detail_panel.visible and not lab.actor_buttons[0].text.contains("HEXACO") \
		and not lab.actor_buttons[0].text.contains("ENGAGE"), "raw calculation is hidden by default")
	check(lab.body_scroll != null and lab.step_button.get_parent().get_parent() == lab.root_layout,
		"content scrolls while sticky controls stay outside the scroll body")
	check_eq(lab.step_button.text, "판단 보기", "pre-decision stage is explicit")
	check_eq(simulator.step_calls, 0, "rendering DTO does not resolve a turn")
	lab.free()
	return finish()


func test_candidate_breakdown_uses_korean_sentences_and_all_score_buckets() -> bool:
	var simulator = FakeSimulator.new(302)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulator)
	lab._on_primary_action()
	check_eq(simulator.step_calls, 0, "revealing five intents is presentation-only")
	check(lab.actor_buttons[0].text.contains("공격") and lab.actor_buttons[1].text.contains("도주") \
		and lab.actor_buttons[2].text.contains("접근") and lab.actor_buttons[3].text.contains("치료") \
		and lab.actor_buttons[4].text.contains("경계"), "five intents compare in compact Korean labels")
	check(not lab.actor_buttons[0].text.contains("합계") and not lab.actor_buttons[0].text.contains("작은 변동"),
		"overview does not expose score mechanics")
	lab._toggle_detail()
	check(lab.detail_panel.visible and not lab.grid.visible, "calculation disclosure replaces the map")
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


func test_approach_copy_distinguishes_hostile_from_neutral_intent() -> bool:
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(FakeSimulator.new(3021))
	var approach := {
		"selected_action_id": "APPROACH",
		"candidates": [{"action_id": "APPROACH", "selected": true,
			"relation_terms": [{"input_id": "species_prior", "input_value": -75, "contribution": -112}],
			"context_terms": []}],
	}
	check_eq(lab._intent_phrase("APPROACH", {"relation": {"effective": -35}}, approach),
		"공격 기회를 노리며 접근", "negative effective relation reads as hostile approach")
	check_eq(lab._intent_phrase("APPROACH", {"relation": {"effective": 20}}, approach),
		"조심스럽게 접근", "positive relation reads as cautious approach")
	check_eq(lab._intent_phrase("APPROACH", {}, approach), "공격 기회를 노리며 접근",
		"breakdown terms provide a hostile fallback when relation DTO is absent")
	check_eq(str(Grid.intent_visual_spec("APPROACH").shape_id), "INWARD_CHEVRON",
		"wording does not change the approach icon mapping")
	lab.free()
	return finish()


func test_flee_copy_surfaces_survival_pressure_without_exposing_score_ids() -> bool:
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(FakeSimulator.new(3022))
	var survival := {
		"selected_action_id": "FLEE",
		"candidates": [{"action_id": "FLEE", "selected": true,
			"state_terms": [{"input_id": "survival_crisis", "contribution": 700}]}],
	}
	var losing_ground := {
		"selected_action_id": "FLEE",
		"candidates": [{"action_id": "FLEE", "selected": true,
			"state_terms": [{"input_id": "injury", "contribution": 220}]}],
	}
	check_eq(lab._intent_phrase("FLEE", {}, survival), "생존이 위험해 도주",
		"survival crisis is presented as an immediate reason to flee")
	check_eq(lab._intent_phrase("FLEE", {}, losing_ground), "불리해져 전투에서 이탈하려 함",
		"injury presents retreat as a changing battlefield decision")
	check_eq(lab._intent_phrase("FLEE", {}, {"selected_action_id": "FLEE"}), "도망치려 한다",
		"ordinary flee keeps the concise neutral wording")
	lab.free()
	return finish()


func test_grid_hit_selects_each_actor_without_advancing_core() -> bool:
	var simulator = FakeSimulator.new(303)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulator)
	lab.grid.size = Vector2(315, 315)
	var center: Variant = lab.grid.actor_screen_center("actor_c")
	check(center != null, "actor C has a visible map center")
	check_eq(lab.grid.actor_id_at_point(center), "actor_c", "map hit maps to actor C")
	lab._on_actor_pressed("actor_c")
	check_eq(lab.selected_actor_id, "actor_c", "map tap selects actor C")
	lab._toggle_detail()
	check(lab.detail_text.text.contains("세라 · 인간") and lab.detail_text.text.contains("창"),
		"only selected actor detail replaces the map")
	check_eq(simulator.step_calls, 0, "actor selection is read-only")
	lab.free()
	return finish()


func test_vector_intent_badges_share_mapping_without_changing_hits() -> bool:
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(FakeSimulator.new(3031))
	lab.grid.size = Vector2(315, 315)
	check(lab.grid.intent_badge_specs().is_empty(), "intent badges stay hidden before decision reveal")
	check(lab.actor_badges.all(func(badge): return not badge.visible),
		"all compact card badges stay hidden before reveal")
	check(lab.grid.target_link_specs().is_empty(), "target arrows stay hidden before decision reveal")
	var centers := {}
	for actor_id in ["actor_a", "actor_b", "actor_c", "actor_d", "actor_e"]:
		centers[actor_id] = lab.grid.actor_screen_center(actor_id)
	lab._on_primary_action()
	var rows: Array = lab.grid.intent_badge_specs()
	check_eq(rows.size(), 5, "five revealed intents have one map badge each")
	var by_actor: Dictionary = {}
	for row in rows:
		by_actor[str(row.actor_id)] = row
	check_eq(str(by_actor.actor_a.shape_id), "CROSSED_BLADES", "attack uses crossed vector blades")
	check_eq(str(by_actor.actor_b.shape_id), "OUTWARD_ARROW", "flee uses a directional vector arrow")
	check_eq(str(by_actor.actor_c.shape_id), "INWARD_CHEVRON", "approach uses inward chevron")
	check_eq(str(by_actor.actor_d.shape_id), "MEDICAL_CROSS", "self treatment uses medical cross")
	check_eq(str(by_actor.actor_e.shape_id), "GUARD_SHIELD", "hold is presented as Korean guard")
	check(by_actor.actor_a.color != by_actor.actor_b.color, "attack and flee retain distinct colors")
	check_eq(str(lab.actor_badges[0].display_spec().shape_id), "CROSSED_BLADES",
		"actor A card consumes the same attack badge mapping")
	check_eq(str(lab.actor_badges[1].display_spec().shape_id), "OUTWARD_ARROW",
		"actor B card consumes the same flee badge mapping")
	check(lab.actor_buttons[0].text.contains("공격") and lab.actor_buttons[1].text.contains("도주") \
		and not lab.actor_buttons[0].text.contains("⚔"), "cards use stable Korean labels instead of emoji")
	var links: Array = lab.grid.target_link_specs()
	check_eq(links.size(), 3, "only approach, attack, and flee expose target direction")
	var links_by_actor := {}
	for link in links:
		links_by_actor[str(link.actor_id)] = link
	check_eq([links_by_actor.actor_a.target_id, links_by_actor.actor_a.kind], ["actor_b", "TARGET"],
		"attack line names its exact target")
	check_eq([links_by_actor.actor_b.target_id, links_by_actor.actor_b.kind], ["actor_a", "FLEE_AWAY"],
		"flee cue points away from its threat")
	check(not bool(links_by_actor.actor_a.hit_surface), "target lines never add an input surface")
	for actor_id in centers:
		check_eq(lab.grid.actor_id_at_point(centers[actor_id]), actor_id,
			"badge drawing leaves authoritative actor hit center unchanged")
	var shape_ids: Dictionary = {}
	for action_id in ["APPROACH", "ENGAGE", "FLEE", "SELF_TREAT", "HOLD"]:
		shape_ids[str(Grid.intent_visual_spec(action_id).shape_id)] = true
	check_eq(shape_ids.size(), 5, "every intent remains distinguishable without color")
	lab.free()

	var terminal_grid = Grid.new()
	terminal_grid.size = Vector2(300, 300)
	terminal_grid.set_observation({"actors": [
		{"id": "dead", "position": [4, 7], "hp": 0, "max_hp": 10, "alive": false, "presence": "DEAD"},
		{"id": "gone", "position": [10, 7], "hp": 10, "max_hp": 10, "alive": true, "presence": "ESCAPED"},
	], "recent_events": [{"type": "ESCAPED", "actor_id": "gone"}]})
	terminal_grid.set_intent_presentation([
		{"actor_id": "dead", "selected_action_id": "ENGAGE"},
		{"actor_id": "gone", "selected_action_id": "FLEE"},
	], true)
	var terminal_rows := terminal_grid.intent_badge_specs()
	check_eq([terminal_rows[0].status, terminal_rows[1].status], ["DEAD", "ESCAPED"],
		"terminal actors replace intents with state marks")
	check_eq([terminal_rows[0].action_id, terminal_rows[1].action_id], ["", ""],
		"dead and escaped actors never retain action icons")
	check_eq(terminal_grid.actor_id_at_point(terminal_grid.actor_screen_center("dead")), "",
		"terminal actor remains visible but cannot become a decision input")
	terminal_grid.free()
	var scrubbed_grid = Grid.new()
	scrubbed_grid.size = Vector2(315, 315)
	scrubbed_grid.set_observation({"actors": [
		{"id": "visible", "position": [5, 5], "hp": 10, "max_hp": 10,
			"alive": true, "presence": "ACTIVE"},
	]})
	scrubbed_grid.set_intent_presentation([{"actor_id": "visible",
		"selected_action_id": "ENGAGE", "selected_target_id": "outside_fov"}], true)
	check(scrubbed_grid.target_link_specs().is_empty(),
		"missing observation target produces no line or hidden-position leak")
	scrubbed_grid.free()
	return finish()


func test_step_resolves_five_decisions_once_and_surfaces_relation_event() -> bool:
	var simulator = FakeSimulator.new(304)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulator)
	lab._on_primary_action()
	check_eq(simulator.step_calls, 0, "first primary tap only reveals five simultaneous intentions")
	check_eq(lab.step_button.text, "결과 보기", "intent stage names the next operation")
	lab._on_primary_action()
	check_eq(simulator.step_calls, 1, "decision button calls one simultaneous core step")
	check(lab.phase_label.text.contains("라온이 모그에게 9 피해") \
		and lab.phase_label.text.contains("모그가 물러났다"), "actual structured result stays visible")
	check_eq(lab.step_button.text, "다음 턴", "subsequent action is explicit")
	lab._on_primary_action()
	check_eq(simulator.step_calls, 1, "next-turn preview does not resolve another turn")
	check_eq(lab._commitment_line(lab._shown_breakdown_for("actor_a")), "2턴째 유지",
		"selected actor detail can explain commitment continuation")
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
	grid.size = Vector2(315, 315)
	grid.set_observation({"actors": [
		{"id": "a", "position": [2, 3], "hp": 10, "max_hp": 10, "alive": true, "weapon": "창"},
		{"id": "b", "position": [12, 11], "hp": 10, "max_hp": 10, "alive": true, "weapon": "활"},
	]}, "a")
	check_eq(grid.pixel_to_world_cell(grid.world_to_pixel_center(Vector2i(2, 3))), Vector2i(2, 3),
		"actor A presentation keeps exact logical cell")
	check_eq(grid.pixel_to_world_cell(grid.world_to_pixel_center(Vector2i(12, 11))), Vector2i(12, 11),
		"actor B presentation keeps exact logical cell")
	check_eq(grid.display_spec().grid_size, 21, "grid dimension is immutable")
	var hit_before:Rect2=grid.actor_render_specs()[0].hit_rect
	var glyph_specs:=grid.actor_glyph_specs()
	check_eq(glyph_specs.size(),2,"duel renders both identities as central glyph bodies")
	for spec in glyph_specs:
		check(not spec.detached_head and spec.head_primitive_count==0 and spec.outline_passes==8,
			"duel glyph has weight but no detached head")
		check(spec.cell_rect.encloses(spec.glyph_rect.grow(1.0)),
			"duel glyph outline stays inside its 15px logical cell")
		check(not spec.selected_outline,"duel selection never reintroduces a yellow outline")
		check(spec.draw_equipment and spec.equipment_primitive_count==1 \
				and str(spec.weapon_glyph) in ["|",")"],
			"duel actor uses its weapon mark instead of artificial limbs")
		check(not spec.draw_limbs and spec.limb_segments.is_empty() \
				and spec.cell_rect.has_point(spec.weapon_center),
			"duel equipment remains tile-local with zero limb primitives")
	grid.set_intent_presentation([{"actor_id":"a","selected_action_id":"APPROACH","selected_target_id":"b"},
		{"actor_id":"b","selected_action_id":"FLEE","selected_target_id":"a"}],true)
	var moving_specs:=grid.actor_glyph_specs()
	check(moving_specs[0].limb_segments.is_empty() and glyph_specs[0].limb_segments.is_empty(),
		"intent direction never recreates limbs")
	check_eq(moving_specs[0].glyph_rect,glyph_specs[0].glyph_rect,
		"stance keeps the central glyph anchor fixed")
	check_eq(grid.actor_render_specs()[0].hit_rect,hit_before,
		"stance and glyph redraw preserve hit authority")
	var badge_rows:=grid.intent_badge_specs()
	check(not moving_specs[0].glyph_rect.grow(1.0).has_point(badge_rows[0].center),
		"intent badge remains outside the central glyph")
	grid.free()
	return finish()


func test_real_duel_facade_integrates_without_leaking_action_ids_to_ui() -> bool:
	var real_script = load(REAL_SIMULATOR_PATH)
	check(real_script != null and real_script.can_instantiate(), "real five-actor facade is loadable")
	if real_script == null or not real_script.can_instantiate():
		return finish()
	var simulator = real_script.new(7711)
	var lab = LabScene.instantiate()
	lab.initialize_for_headless_test(simulator)
	lab.grid.size = Vector2(300, 300)
	var observation: Dictionary = simulator.observation()
	check_eq(observation.map_size, [21, 21], "real facade map contract")
	check_eq(observation.actors.size(), 5, "real facade exposes five actors")
	check_eq(lab.grid.actor_count(), 5, "real actors reach map presentation")
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


func test_main_party_scene_has_clear_five_actor_lab_entry() -> bool:
	var sandbox = PartyScene.instantiate()
	sandbox.initialize_for_headless_test(PartySession.new(), false)
	check(sandbox.duel_lab_button != null and sandbox.duel_lab_button.text == "5인 관찰 실험",
		"main playtest exposes decision LAB")
	check_eq(sandbox.duel_lab_button.get_parent(), sandbox.phase_row,
		"entry shares existing banner row instead of growing portrait layout")
	check_eq(sandbox.duel_lab_button.custom_minimum_size.y, 44.0, "entry keeps mobile touch target")
	sandbox.free()
	return finish()
