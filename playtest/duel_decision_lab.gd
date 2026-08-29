class_name DuelDecisionLab
extends Control

const GridScript = preload("res://playtest/duel_decision_grid.gd")
const KoreanFont: FontFile = preload("res://assets/fonts/NanumSquareR.ttf")
const SIMULATOR_PATH := "res://sim/dungeon_population/dungeon_population_simulator.gd"
const PARTY_SCENE_PATH := "res://playtest/party_encounter_sandbox.tscn"
const DEFAULT_SEED := 22002
const TOUCH_TARGET := 44


class IntentCardBadge:
	extends Control

	var action_id := ""
	var status := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_presentation(next_action_id: String, next_status: String = "") -> void:
		action_id = next_action_id
		status = next_status
		visible = not action_id.is_empty() or not status.is_empty()
		queue_redraw()

	func display_spec() -> Dictionary:
		var spec := GridScript.intent_visual_spec(action_id, status)
		return spec.merged({"action_id": action_id, "status": status})

	func _draw() -> void:
		var spec := GridScript.intent_visual_spec(action_id, status)
		if spec.is_empty():
			return
		GridScript.draw_intent_badge(self, size * 0.5, minf(size.x, size.y) * 0.42, spec)


var simulator
var grid: DuelDecisionGrid
var root_layout: VBoxContainer
var situation_label: Label
var intent_turn_label: Label
var phase_label: Label
var result_panel: PanelContainer
var detail_panel: PanelContainer
var detail_toggle_button: Button
var seed_edit: LineEdit
var random_button: Button
var step_button: Button
var restart_button: Button
var actor_buttons: Array[Button] = []
var actor_badges: Array[Control] = []
var event_button: Button
var detail_text: RichTextLabel

var selected_actor_id := ""
var detail_mode := "OVERVIEW"
var presentation_stage := "HIDDEN"
var ui_notice := ""
var _observation: Dictionary = {}
var _breakdowns: Array = []
var _shown_breakdowns: Array = []
var _recent_logs: Array = []
var _initialized_for_headless_test := false


func _ready() -> void:
	_build_ui()
	if simulator == null and not _initialized_for_headless_test:
		simulator = _create_default_simulator(DEFAULT_SEED)
	_refresh()


func initialize_for_headless_test(custom_simulator) -> void:
	if grid == null:
		_build_ui()
	_initialized_for_headless_test = true
	simulator = custom_simulator
	ui_notice = ""
	selected_actor_id = ""
	detail_mode = "OVERVIEW"
	presentation_stage = "HIDDEN"
	_shown_breakdowns.clear()
	_refresh()


func _build_ui() -> void:
	if grid != null:
		return
	var ui_theme := Theme.new()
	ui_theme.default_font = KoreanFont
	ui_theme.default_font_size = 16
	theme = ui_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.name = "DecisionLabBackground"
	background.color = Color("#071019")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	root_layout = VBoxContainer.new()
	root_layout.name = "DuelDecisionLabLayout"
	root_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layout.offset_left = 6
	root_layout.offset_top = 4
	root_layout.offset_right = -6
	root_layout.offset_bottom = -4
	root_layout.add_theme_constant_override("separation", 3)
	add_child(root_layout)

	var header := HBoxContainer.new()
	header.name = "DecisionLabHeader"
	header.custom_minimum_size.y = TOUCH_TARGET
	header.add_theme_constant_override("separation", 4)
	root_layout.add_child(header)
	var back := _add_button(header, "← 복귀", "BackToParty", _back_to_party, 15)
	back.custom_minimum_size.x = 60
	var title := Label.new()
	title.name = "DecisionLabTitle"
	title.text = "2인 판단 LAB"
	title.add_theme_font_size_override("font_size", 18)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	seed_edit = LineEdit.new()
	seed_edit.name = "SeedInput"
	seed_edit.custom_minimum_size = Vector2(68, TOUCH_TARGET)
	seed_edit.placeholder_text = "seed"
	seed_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	seed_edit.text_submitted.connect(_apply_typed_seed)
	header.add_child(seed_edit)

	var situation_panel := PanelContainer.new()
	situation_panel.name = "SituationSummaryPanel"
	situation_panel.custom_minimum_size.y = 44
	situation_panel.add_theme_stylebox_override("panel", _panel_style("#0d1b25", "#29404d"))
	root_layout.add_child(situation_panel)
	situation_label = Label.new()
	situation_label.name = "SituationSummary"
	situation_label.add_theme_font_size_override("font_size", 14)
	situation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	situation_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	situation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	situation_panel.add_child(situation_label)

	grid = GridScript.new()
	grid.name = "DuelDecisionGrid"
	grid.custom_minimum_size = Vector2(225, 225)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.actor_pressed.connect(_on_actor_pressed)
	root_layout.add_child(grid)

	intent_turn_label = Label.new()
	intent_turn_label.name = "IntentTurnLabel"
	intent_turn_label.custom_minimum_size.y = 24
	intent_turn_label.add_theme_font_size_override("font_size", 15)
	intent_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intent_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root_layout.add_child(intent_turn_label)

	var tabs := HBoxContainer.new()
	tabs.name = "DecisionIntentCards"
	tabs.custom_minimum_size.y = 94
	tabs.add_theme_constant_override("separation", 5)
	root_layout.add_child(tabs)
	for index in range(2):
		var actor_button := _add_button(tabs, "인물 %s" % ("A" if index == 0 else "B"),
			"ActorIntentCard%d" % index, _select_actor_index.bind(index), 15)
		actor_button.toggle_mode = true
		actor_button.custom_minimum_size.y = 94
		actor_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actor_button.size_flags_stretch_ratio = 1.0
		actor_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		actor_button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		var badge := IntentCardBadge.new()
		badge.name = "ActorIntentBadge%d" % index
		badge.position = Vector2(5, 27)
		badge.size = Vector2(18, 18)
		actor_button.add_child(badge)
		actor_badges.append(badge)
		actor_buttons.append(actor_button)

	result_panel = PanelContainer.new()
	result_panel.name = "DecisionResultPanel"
	result_panel.custom_minimum_size.y = 44
	result_panel.add_theme_stylebox_override("panel", _panel_style("#10212d", "#426173"))
	root_layout.add_child(result_panel)
	phase_label = Label.new()
	phase_label.name = "DecisionResult"
	phase_label.add_theme_font_size_override("font_size", 15)
	phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(phase_label)

	var disclosure_row := HBoxContainer.new()
	disclosure_row.name = "DecisionDisclosureRow"
	disclosure_row.custom_minimum_size.y = TOUCH_TARGET
	disclosure_row.add_theme_constant_override("separation", 4)
	root_layout.add_child(disclosure_row)
	detail_toggle_button = _add_button(disclosure_row, "왜 이렇게 판단했지?", "DetailToggle",
		_toggle_detail, 15)
	detail_toggle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_button = _add_button(disclosure_row, "사건 보기", "EventLogTab", _show_events, 15)
	event_button.toggle_mode = true
	event_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	detail_panel = PanelContainer.new()
	detail_panel.name = "DecisionDetailPanel"
	detail_panel.custom_minimum_size.y = 180
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _panel_style("#0c1822", "#2c4859"))
	root_layout.add_child(detail_panel)
	detail_text = RichTextLabel.new()
	detail_text.name = "DecisionDetailText"
	detail_text.bbcode_enabled = false
	detail_text.fit_content = false
	detail_text.scroll_active = true
	detail_text.add_theme_font_size_override("normal_font_size", 15)
	detail_panel.add_child(detail_text)
	detail_panel.visible = false

	var controls := HBoxContainer.new()
	controls.name = "DecisionControls"
	controls.custom_minimum_size.y = TOUCH_TARGET
	controls.add_theme_constant_override("separation", 4)
	root_layout.add_child(controls)
	random_button = _add_button(controls, "새 랜덤 상황", "NewRandomSituation", _new_random_situation, 14)
	random_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_button = _add_button(controls, "판단 보기", "ResolveTurn", _on_primary_action, 16)
	step_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_button.size_flags_stretch_ratio = 1.25
	restart_button = _add_button(controls, "같은 상황 다시", "RestartSameSituation", _restart_same_situation, 14)
	restart_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _create_default_simulator(seed_value: int):
	if not ResourceLoader.exists(SIMULATOR_PATH):
		ui_notice = "판단 시뮬레이터를 불러오지 못했습니다"
		return null
	var simulator_script = load(SIMULATOR_PATH)
	if simulator_script == null or not simulator_script.can_instantiate():
		ui_notice = "판단 시뮬레이터를 시작할 수 없습니다"
		return null
	return simulator_script.new(seed_value)


func _refresh() -> void:
	if simulator == null or grid == null:
		_show_unavailable()
		return
	var observation_value: Variant = simulator.observation()
	if not observation_value is Dictionary:
		ui_notice = "관찰 정보를 읽지 못했습니다"
		_show_unavailable()
		return
	_observation = observation_value
	var breakdown_value: Variant = simulator.decision_breakdowns()
	_breakdowns = breakdown_value.duplicate(true) if breakdown_value is Array else []
	var logs_value: Variant = simulator.recent_logs(24)
	_recent_logs = logs_value.duplicate(true) if logs_value is Array else []
	if not seed_edit.has_focus():
		seed_edit.text = str(_observation.get("seed", DEFAULT_SEED))
	var actors: Array = _observation.get("actors", [])
	if selected_actor_id.is_empty() or not _contains_actor(selected_actor_id):
		selected_actor_id = _actor_id(actors[0]) if not actors.is_empty() and actors[0] is Dictionary else ""
	grid.set_observation(_observation, selected_actor_id)
	_refresh_phase()
	_refresh_tabs()
	_refresh_detail()
	_refresh_controls()


func _refresh_phase() -> void:
	situation_label.text = _situation_summary()
	var tick := int(str(_observation.get("tick_index", "0")))
	if presentation_stage == "RESULT":
		var resolution: Dictionary = _observation.get("last_resolution", {}) \
			if _observation.get("last_resolution", {}) is Dictionary else {}
		intent_turn_label.text = "방금 해결한 판단 · T%s" % str(resolution.get("turn_index", tick))
		phase_label.text = _actual_result_summary(resolution)
	elif presentation_stage == "INTENT":
		intent_turn_label.text = "다음 판단 · T%d · 실행 전" % (tick + 1)
		phase_label.text = "두 행동을 함께 실행하기 전입니다."
	else:
		intent_turn_label.text = "다음 판단 · T%d · 아직 공개 전" % (tick + 1)
		phase_label.text = "‘판단 보기’를 누르면 두 인물의 생각을 함께 비교합니다."
	if not ui_notice.is_empty():
		phase_label.text = ui_notice + "\n" + phase_label.text


func _refresh_tabs() -> void:
	var actors: Array = _observation.get("actors", [])
	grid.set_intent_presentation(_shown_breakdowns, presentation_stage != "HIDDEN")
	for index in range(actor_buttons.size()):
		var button: Button = actor_buttons[index]
		if index >= actors.size() or not actors[index] is Dictionary:
			button.text = "인물 %s 없음" % ("A" if index == 0 else "B")
			button.disabled = true
			button.button_pressed = false
			actor_badges[index].set_presentation("")
			continue
		var actor: Dictionary = actors[index]
		button.disabled = false
		var actor_id := _actor_id(actor)
		var breakdown := _shown_breakdown_for(actor_id)
		var action_id := str(breakdown.get("selected_action_id", ""))
		var status := _actor_terminal_status(actor_id, actor)
		var shown_action := action_id if presentation_stage != "HIDDEN" and status.is_empty() else ""
		actor_badges[index].set_presentation(shown_action, status)
		var intent_line := "아직 판단을 보지 않았다"
		var reason_line := "판단을 공개하면 핵심 이유가 보인다"
		if not status.is_empty():
			intent_line = "쓰러짐" if status == "DEAD" else "조우에서 벗어남"
			reason_line = "현재 행동 의도는 종료되었다"
		elif not shown_action.is_empty() and not breakdown.is_empty():
			var visual := GridScript.intent_visual_spec(action_id)
			intent_line = "%s · %s" % [str(visual.get("label_ko", "행동")),
				_intent_phrase(action_id, actor, breakdown)]
			var reasons := _key_reasons(actor, breakdown)
			reason_line = reasons[0] if not reasons.is_empty() else "지금 상황을 종합해서"
			var continuity := _commitment_line(breakdown)
			if not continuity.is_empty():
				intent_line += " · " + continuity
		button.text = "%s %s · %s · HP %d\n%s\n%s\n성향 · %s" % ["A" if index == 0 else "B",
			str(actor.get("name", "인물")), _species_label(str(actor.get("species_id", "?"))),
			int(actor.get("hp", 0)), intent_line, reason_line, _personality_summary(actor, true)]
		button.button_pressed = actor_id == selected_actor_id
		_apply_action_card_style(button, shown_action)
	event_button.button_pressed = detail_mode == "EVENTS"
	detail_toggle_button.button_pressed = detail_mode == "DETAIL"


func _refresh_controls() -> void:
	var phase := str(_observation.get("phase", "ACTIVE"))
	var complete := phase == "COMPLETE" or phase == "ESCAPED"
	step_button.disabled = complete and presentation_stage == "RESULT"
	if complete and presentation_stage == "RESULT":
		step_button.text = "상황 종료"
	elif presentation_stage == "HIDDEN":
		step_button.text = "판단 보기"
	elif presentation_stage == "INTENT":
		step_button.text = "결과 보기"
	else:
		step_button.text = "다음 턴"


func _refresh_detail() -> void:
	var detail_open := detail_mode != "OVERVIEW"
	detail_panel.visible = detail_open
	grid.visible = not detail_open
	result_panel.visible = not detail_open
	detail_toggle_button.text = "핵심 화면으로" if detail_mode == "DETAIL" else "왜 이렇게 판단했지?"
	if detail_mode == "EVENTS":
		detail_text.text = event_log_text(_recent_logs)
	elif detail_mode == "DETAIL":
		detail_text.text = actor_card_text(selected_actor_id)
	else:
		detail_text.text = ""


func _situation_summary() -> String:
	var actors: Array = _observation.get("actors", [])
	if actors.size() < 2 or not actors[0] is Dictionary or not actors[1] is Dictionary:
		return "두 인물의 상황을 불러오는 중입니다."
	var first: Dictionary = actors[0]
	var second: Dictionary = actors[1]
	var summary := "%s %s(%s)과 %s %s(%s)가 %d칸 거리에서 마주쳤다." % [
		_species_label(str(first.get("species_id", "?"))), str(first.get("name", "인물 A")),
		_actor_condition_short(first), _species_label(str(second.get("species_id", "?"))),
		str(second.get("name", "인물 B")), _actor_condition_short(second),
		int(_observation.get("distance", 0))]
	var memories: Array[String] = []
	for actor_value in actors:
		if not actor_value is Dictionary:
			continue
		var actor: Dictionary = actor_value
		var memory_kind := _memory_kind(actor)
		var memory_text := str({"EXILED": "버려진 원한", "HARMED": "공격받은 기억",
			"HELPED": "도움을 받은 기억"}.get(memory_kind, ""))
		if not memory_text.is_empty():
			memories.append("%s에게는 %s이 있다" % [str(actor.get("name", "인물")), memory_text])
	if not memories.is_empty():
		summary += " " + " · ".join(memories) + "."
	return summary


func _actor_condition_short(actor: Dictionary) -> String:
	var parts: Array[String] = ["HP %d" % int(actor.get("hp", 0))]
	var status := _dot_summary(actor.get("dot", []))
	if status != "없음":
		parts.append(status)
	parts.append("%s 무장" % _weapon_label(str(actor.get("weapon", "무기"))) \
		if bool(actor.get("armed", false)) else "비무장")
	return ", ".join(parts)


func _personality_summary(actor: Dictionary, compact: bool = false) -> String:
	var hexaco: Dictionary = actor.get("hexaco", {})
	var rows: Array[Dictionary] = []
	var order := ["H", "E", "X", "A", "C", "O"]
	for index in range(order.size()):
		var axis: String = order[index]
		rows.append({"axis": axis, "value": _hexaco(hexaco, axis),
			"distance": absi(_hexaco(hexaco, axis) - 500), "order": index})
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.distance) != int(b.distance):
			return int(a.distance) > int(b.distance)
		return int(a.order) < int(b.order))
	if rows.is_empty() or int(rows[0].distance) < 80:
		return "균형 잡힌 성향 · 상황의 영향을 많이 받음" if compact \
			else "성향이 한쪽으로 치우치지 않았다. 상황의 영향을 더 크게 받는 편이다."
	var phrases: Array[String] = []
	for index in range(mini(2, rows.size())):
		var row: Dictionary = rows[index]
		phrases.append(_trait_phrase(str(row.axis), int(row.value) >= 500, compact))
	return " · ".join(phrases) if compact else "\n".join(phrases)


func _trait_phrase(axis: String, high: bool, compact: bool) -> String:
	var full := {
		"H": ["실리를 위해 편법도 감수한다.", "정직하고 욕심이 적다."],
		"E": ["위험 앞에서도 쉽게 흔들리지 않는다.", "위험과 관계의 상실에 민감하다."],
		"X": ["앞에 나서기보다 거리를 둔다.", "먼저 나서고 주도하려 한다."],
		"A": ["모욕과 충돌에 강경하게 맞선다.", "충돌을 피하고 쉽게 용서한다."],
		"C": ["계획보다 순간 판단을 따른다.", "계획대로 신중하게 행동한다."],
		"O": ["검증된 방식과 익숙함을 선호한다.", "낯선 선택과 변화를 즐긴다."],
	}
	var short := {
		"H": ["편법도 감수", "정직·절제"],
		"E": ["쉽게 흔들리지 않음", "위험에 민감"],
		"X": ["거리를 둠", "주도적"],
		"A": ["충돌에 강경", "온화·관대"],
		"C": ["즉흥적", "신중·계획적"],
		"O": ["익숙함 선호", "변화 선호"],
	}
	var table: Dictionary = short if compact else full
	var choices: Array = table.get(axis, ["상황을 살핌", "상황을 살핌"])
	return str(choices[1 if high else 0])


func _key_reasons(actor: Dictionary, breakdown: Dictionary) -> Array[String]:
	var selected := _selected_candidate(breakdown)
	if selected.is_empty():
		return []
	var strongest_by_group: Dictionary = {}
	var stable_order := 0
	for bucket_name in ["hexaco_terms", "state_terms", "relation_terms", "context_terms"]:
		var terms: Variant = selected.get(bucket_name, [])
		if not terms is Array:
			continue
		for term_value in terms:
			if not term_value is Dictionary:
				continue
			var term: Dictionary = term_value
			var contribution := float(term.get("contribution", term.get("amount", term.get("value", 0))))
			if contribution <= 0.0:
				stable_order += 1
				continue
			var input_id := str(term.get("input_id", term.get("facet", "")))
			var group := _reason_group(input_id, bucket_name)
			var candidate := {"group": group, "input_id": input_id, "contribution": contribution,
				"order": stable_order, "term": term}
			if not strongest_by_group.has(group) \
					or contribution > float(strongest_by_group[group].contribution):
				strongest_by_group[group] = candidate
			stable_order += 1
	var rows: Array = strongest_by_group.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if not is_equal_approx(float(a.contribution), float(b.contribution)):
			return float(a.contribution) > float(b.contribution)
		return int(a.order) < int(b.order))
	var result: Array[String] = []
	for index in range(mini(2, rows.size())):
		result.append(_reason_phrase(actor, str(rows[index].input_id), rows[index].term))
	return result


func _reason_group(input_id: String, bucket_name: String) -> String:
	if input_id in ["memory_modifier", "personal_memory", "fear_pressure"]:
		return "memory"
	if input_id in ["injury", "health", "hp_crisis", "hp_ratio"]:
		return "body"
	if input_id in ["survival_crisis", "recent_interrupt"]:
		return "survival"
	if input_id in ["dot", "treatment_need"]:
		return "treatment"
	if input_id in ["power", "power_gap", "power_disadvantage", "armed"]:
		return "power"
	if input_id == "species_prior":
		return "species"
	return bucket_name + "/" + input_id


func _reason_phrase(actor: Dictionary, input_id: String, term: Dictionary) -> String:
	match input_id:
		"species_prior":
			var prior := int(actor.get("relation", {}).get("species_prior", term.get("input_value", 0))) \
				if actor.get("relation", {}) is Dictionary else int(term.get("input_value", 0))
			return "종족 사이 %s가 깊어서" % ("적대" if prior < 0 else "호의")
		"memory_modifier", "personal_memory":
			return str({"EXILED": "버려진 원한 때문에", "HARMED": "공격받은 기억 때문에",
				"HELPED": "도움을 받은 기억 때문에"}.get(_memory_kind(actor), "개인적인 기억 때문에"))
		"fear_pressure":
			return "그 기억 때문에 두려워서"
		"health":
			return "몸 상태가 괜찮아서"
		"injury":
			return "부상이 심해서"
		"hp_crisis":
			return "체력이 위험할 만큼 낮아서"
		"hp_ratio":
			return "몸 상태가 버틸 만해서"
		"survival_crisis":
			return "생존이 위험해서"
		"recent_interrupt":
			return "방금 피해를 받아서"
		"dot", "treatment_need":
			return "%s을 치료해야 해서" % _dot_name(actor)
		"power_gap", "power_disadvantage":
			return "상대보다 전력이 약해서"
		"power", "armed":
			return "싸울 힘과 무장이 있어서"
		"threat", "danger":
			return "상대가 가까워 위협적이라서"
		"distance", "approach_pressure":
			return "서로 거리가 멀어서"
		"supplies":
			return "치료 도구가 있어서"
		"escape_space":
			return "물러날 공간이 있어서"
		"other_alive":
			return "상대가 아직 위협이어서"
		"uncertainty":
			return "상황이 불확실해서"
	if input_id in ["H", "E", "X", "A", "C", "O"]:
		return _trait_reason(input_id, _hexaco(actor.get("hexaco", {}), input_id) >= 500)
	var explicit := str(term.get("label_ko", ""))
	return explicit + " 때문에" if not explicit.is_empty() else "상황을 종합해서"


func _trait_reason(axis: String, high: bool) -> String:
	return str({
		"H": ["실리를 우선하는 성향이라서", "정직하고 절제하는 성향이라서"],
		"E": ["위험에도 잘 흔들리지 않는 성향이라서", "위협에 민감한 성향이라서"],
		"X": ["거리를 두는 성향이라서", "먼저 나서는 성향이라서"],
		"A": ["충돌에 강경한 성향이라서", "충돌을 피하는 성향이라서"],
		"C": ["순간 판단을 따르는 성향이라서", "계획을 지키는 성향이라서"],
		"O": ["익숙한 방식을 선호해서", "낯선 선택을 즐겨서"],
	}.get(axis, ["성향의 영향으로", "성향의 영향으로"])[1 if high else 0])


func _selected_candidate(breakdown: Dictionary) -> Dictionary:
	var selected_id := str(breakdown.get("selected_action_id", ""))
	for value in breakdown.get("candidates", []):
		if value is Dictionary and (bool(value.get("selected", false)) \
				or str(value.get("action_id", "")) == selected_id):
			return value
	return {}


func _commitment_line(breakdown: Dictionary) -> String:
	var action_id := str(breakdown.get("selected_action_id", ""))
	if bool(breakdown.get("continued", false)):
		return "%d턴째 유지" % maxi(1, int(breakdown.get("intent_turn_count", 1)))
	var mode := str(breakdown.get("selection_mode", "NEW"))
	var reason_code := str(breakdown.get("switch_reason_code", "NEW"))
	if mode in ["SWITCHED", "RESTARTED"]:
		return str({
			"INTERRUPT": "피해로 계획 변경",
			"ILLEGAL": "행동 불가로 변경",
			"GOAL_COMPLETE": "목표를 마쳐 재판단",
			"CHALLENGER": "더 나은 선택으로 변경",
		}.get(reason_code, str(breakdown.get("switch_reason_ko", "상황 변화로 다시 판단함"))))
	return "새 판단"


func _intent_object(action_id: String) -> String:
	return str({"ENGAGE": "공격을", "FLEE": "도주를", "APPROACH": "접근을",
		"SELF_TREAT": "치료를", "HOLD": "경계를"}.get(action_id, "행동을"))


func _intent_phrase(action_id: String, actor: Dictionary = {}, breakdown: Dictionary = {}) -> String:
	if action_id == "APPROACH":
		return "공격 기회를 노리며 접근" if _approach_is_hostile(actor, breakdown) else "조심스럽게 접근"
	if action_id == "FLEE":
		if _selected_has_positive_term(breakdown, ["survival_crisis"]):
			return "생존이 위험해 도주"
		if _selected_has_positive_term(breakdown,
				["injury", "hp_crisis", "power_disadvantage", "recent_interrupt"]):
			return "불리해져 전투에서 이탈하려 함"
	return str({"ENGAGE": "공격하려 한다",
		"FLEE": "도망치려 한다", "HOLD": "지켜보려 한다",
		"SELF_TREAT": "치료하려 한다"}.get(action_id, "상황을 지켜보려 한다"))


func _selected_has_positive_term(breakdown: Dictionary, input_ids: Array) -> bool:
	var selected := _selected_candidate(breakdown)
	for bucket_name in ["state_terms", "relation_terms", "context_terms"]:
		var terms: Variant = selected.get(bucket_name, [])
		if not terms is Array:
			continue
		for term_value in terms:
			if not term_value is Dictionary:
				continue
			var input_id := str(term_value.get("input_id", ""))
			var contribution := float(term_value.get("contribution",
				term_value.get("amount", term_value.get("value", 0))))
			if input_id in input_ids and contribution > 0.0:
				return true
	return false


func _approach_is_hostile(actor: Dictionary, breakdown: Dictionary) -> bool:
	var relation: Variant = actor.get("relation", {})
	if relation is Dictionary:
		if relation.has("effective"):
			return int(relation.get("effective", 0)) < 0
		if relation.has("species_prior") or relation.has("memory_modifier"):
			return int(relation.get("species_prior", 0)) + int(relation.get("memory_modifier", 0)) < 0
	var selected := _selected_candidate(breakdown)
	for bucket_name in ["relation_terms", "context_terms"]:
		for term_value in selected.get(bucket_name, []):
			if not term_value is Dictionary:
				continue
			var input_id := str(term_value.get("input_id", "")).to_lower()
			var input_value := int(term_value.get("input_value", 0))
			var contribution := int(term_value.get("contribution", 0))
			if input_id in ["species_prior", "memory_modifier"] and input_value < 0:
				return true
			if input_id == "hostility" and input_value > 0:
				return true
			if ("hostile" in input_id or "attack" in input_id or "aggression" in input_id) \
					and maxi(input_value, contribution) > 0:
				return true
	return false


func _apply_action_card_style(button: Button, action_id: String) -> void:
	var colors := {
		"ENGAGE": [Color("#35151c"), Color("#ff6671")],
		"FLEE": [Color("#102744"), Color("#6eafff")],
		"APPROACH": [Color("#0d3030"), Color("#58dbc4")],
		"SELF_TREAT": [Color("#12341f"), Color("#65df8b")],
		"HOLD": [Color("#20272d"), Color("#aab5bd")],
		"": [Color("#111d27"), Color("#8295a2")],
	}
	var pair: Array = colors.get(action_id, colors[""])
	var normal := _panel_style(pair[0].to_html(), pair[1].darkened(0.25).to_html())
	var pressed := _panel_style(pair[0].lightened(0.08).to_html(), pair[1].to_html())
	pressed.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", pressed)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", pair[1])
	button.add_theme_color_override("font_pressed_color", pair[1].lightened(0.12))


func _actual_result_summary(resolution: Dictionary) -> String:
	var ids: Array = resolution.get("event_ids", []) if resolution.get("event_ids", []) is Array else []
	var id_set: Dictionary = {}
	for value in ids:
		id_set[str(value)] = true
	var matching: Array[Dictionary] = []
	for value in _recent_logs:
		if value is Dictionary and (ids.is_empty() or id_set.has(str(value.get("event_id", "")))):
			matching.append(value)
	matching.sort_custom(func(a: Dictionary, b: Dictionary):
		var priority := {"DEATH": 0, "ESCAPED": 1, "DAMAGE": 2, "HEAL": 2,
			"STATUS_TICK": 2, "MOVE": 3, "ACTION": 4, "MEMORY": 5}
		var pa := int(priority.get(str(a.get("type", "")), 9))
		var pb := int(priority.get(str(b.get("type", "")), 9))
		if pa != pb:
			return pa < pb
		return int(str(a.get("event_id", "0"))) < int(str(b.get("event_id", "0"))))
	var clauses: Array[String] = []
	for event in matching:
		if str(event.get("type", "")) == "MEMORY":
			continue
		var clause := _result_clause(event)
		if not clause.is_empty() and clause not in clauses:
			clauses.append(clause)
		if clauses.size() >= 2:
			break
	if not clauses.is_empty():
		return " · ".join(clauses)
	var fallback := _resolution_summary(resolution)
	return fallback if not fallback.is_empty() else "두 행동을 동시에 해결했지만 눈에 띄는 변화는 없었다."


func _result_clause(event: Dictionary) -> String:
	var actor := _actor_name(str(event.get("actor_id", "")))
	var target := _actor_name(str(event.get("target_id", "")))
	match str(event.get("type", "")):
		"DEATH":
			return "%s 쓰러졌다" % _subject(actor)
		"ESCAPED":
			return "%s 거리를 벌려 조우에서 벗어났다" % _subject(actor)
		"DAMAGE":
			return "%s %s에게 %d 피해를 줬다" % [_subject(actor), target, int(event.get("magnitude", 0))]
		"HEAL":
			return "%s HP를 %d 회복했다" % [_subject(actor), int(event.get("magnitude", 0))]
		"STATUS_TICK":
			return "%s 상태이상으로 %d 피해를 입었다" % [_subject(actor), int(event.get("magnitude", 0))]
		"MOVE":
			return "%s %s" % [_subject(actor), "물러났다" if str(event.get("action_id", "")) == "FLEE" else "다가갔다"]
		"ACTION":
			if str(event.get("action_id", "")) == "HOLD":
				return "%s 자리를 지켜봤다" % _subject(actor)
	return ""


func _subject(value: String) -> String:
	if value.is_empty():
		return "인물이"
	var code := value.unicode_at(value.length() - 1)
	if code >= 0xAC00 and code <= 0xD7A3:
		return value + ("이" if (code - 0xAC00) % 28 != 0 else "가")
	return value + "가"


func _memory_kind(actor: Dictionary) -> String:
	var memory: Variant = actor.get("memory", {})
	if memory is Dictionary:
		return str(memory.get("kind", memory.get("memory_kind", "NONE"))).to_upper()
	return "NONE"


func _actor_terminal_status(actor_id: String, actor: Dictionary) -> String:
	if not bool(actor.get("alive", true)):
		return "DEAD"
	if str(_observation.get("phase", "ACTIVE")) != "ESCAPED":
		return ""
	for value in _recent_logs:
		if value is Dictionary and str(value.get("type", "")) == "ESCAPED" \
				and str(value.get("actor_id", "")) == actor_id:
			return "ESCAPED"
	return ""


func _dot_name(actor: Dictionary) -> String:
	var value: Variant = actor.get("dot", [])
	if value is Dictionary and not value.is_empty():
		var status := str(value.get("status_id", value.get("label_ko", "상태이상"))).to_upper()
		return str({"BLEEDING": "출혈", "POISONED": "독"}.get(status, status))
	if value is Array and not value.is_empty() and value[0] is Dictionary:
		var row: Dictionary = value[0]
		return str(row.get("label_ko", row.get("status_id", "상태이상")))
	return "상태이상"


func actor_card_text(actor_id: String) -> String:
	var actor := _actor_by_id(actor_id)
	if actor.is_empty():
		return "지도나 위의 인물 카드를 눌러 판단 근거를 확인하세요."
	var hexaco: Dictionary = actor.get("hexaco", {})
	var lines: Array[String] = [
		"%s · %s · %s" % [str(actor.get("name", actor_id)), _species_label(str(actor.get("species_id", "?"))),
			"생존" if bool(actor.get("alive", true)) else "쓰러짐"],
		"HP %d/%d · 상태이상 %s · %s" % [int(actor.get("hp", 0)), int(actor.get("max_hp", 0)),
			_dot_summary(actor.get("dot", [])), _weapon_summary(actor)],
		"성향 요약\n%s" % _personality_summary(actor),
		"HEXACO  H %d  E %d  X %d  A %d  C %d  O %d" % [
			_hexaco(hexaco, "H"), _hexaco(hexaco, "E"), _hexaco(hexaco, "X"),
			_hexaco(hexaco, "A"), _hexaco(hexaco, "C"), _hexaco(hexaco, "O")],
	]
	var breakdown := _shown_breakdown_for(actor_id)
	if breakdown.is_empty():
		breakdown = _breakdown_for(actor_id)
	if breakdown.is_empty():
		lines.append("\n아직 판단 근거가 없습니다. ‘판단하기’를 눌러 비교하세요.")
		return "\n".join(lines)
	var selected_reason := str(breakdown.get("selected_reason_ko", ""))
	if not selected_reason.is_empty():
		lines.append("\n최종 판단 · %s\n%s" % [_action_label(str(breakdown.get("selected_action_id", ""))), selected_reason])
	lines.append("\n행동 후보 점수")
	for candidate_value in breakdown.get("candidates", []):
		if candidate_value is Dictionary:
			lines.append(_candidate_text(candidate_value))
	return "\n".join(lines)


func _candidate_text(candidate: Dictionary) -> String:
	var action_label := _action_label(str(candidate.get("action_id", "")))
	var legal := bool(candidate.get("legal", false))
	var selected_mark := ("선택" if bool(candidate.get("selected", false)) else "후보") if legal else "거부"
	var relation_split := _relation_terms(candidate.get("relation_terms", []))
	var lines: Array[String] = ["\n%s · %s · 합계 %s" % [selected_mark, action_label,
		_number_text(candidate.get("total", 0))]]
	if not legal:
		lines.append("  %s" % _rejection_text(str(candidate.get("rejection_reason", ""))))
	lines.append("  기본 %s · 성격 %s · 상태 %s" % [_number_text(candidate.get("base", 0)),
		_terms_total(candidate.get("hexaco_terms", [])), _terms_total(candidate.get("state_terms", []))])
	lines.append("  종족 관계 %s · 개인 기억 %s" % [
		_terms_total(relation_split.species), _terms_total(relation_split.memory)])
	lines.append("  관계 효과 %s · 상황 %s · 작은 변동 %s" % [_terms_total(relation_split.other),
		_terms_total(candidate.get("context_terms", [])), _number_text(candidate.get("jitter", 0))])
	var details: Array[String] = []
	_append_term_detail(details, "성격", candidate.get("hexaco_terms", []))
	_append_term_detail(details, "상태", candidate.get("state_terms", []))
	_append_term_detail(details, "종족", relation_split.species)
	_append_term_detail(details, "기억", relation_split.memory)
	_append_term_detail(details, "관계", relation_split.other)
	_append_term_detail(details, "상황", candidate.get("context_terms", []))
	if not details.is_empty():
		lines.append("  " + " / ".join(details))
	return "\n".join(lines)


func event_log_text(rows: Array) -> String:
	var lines: Array[String] = ["동시 해결 및 관계 변화"]
	var resolution: Dictionary = _observation.get("last_resolution", {}) \
		if _observation.get("last_resolution", {}) is Dictionary else {}
	for change_value in resolution.get("relationship_changes", []):
		if change_value is Dictionary:
			lines.append("관계 · %s" % str(change_value.get("message_ko", change_value.get("message", "변화가 생겼습니다."))))
	if rows.is_empty():
		lines.append("아직 사건이 없습니다. ‘판단하기’를 눌러 두 선택을 동시에 해결하세요.")
		return "\n".join(lines)
	var start := maxi(0, rows.size() - 16)
	for index in range(rows.size() - 1, start - 1, -1):
		var value: Variant = rows[index]
		if value is Dictionary:
			lines.append("T%s · %s" % [str(value.get("turn_index", value.get("tick_index",
				value.get("world_time", "?")))), _event_message_ko(value)])
	return "\n".join(lines)


func _resolution_summary(resolution: Dictionary) -> String:
	var explicit := str(resolution.get("summary_ko", resolution.get("message", "")))
	if not explicit.is_empty():
		return explicit
	var action_parts: Array[String] = []
	for value in resolution.get("action_rows", []):
		if value is Dictionary:
			action_parts.append("%s: %s" % [_actor_name(str(value.get("actor_id", ""))),
				_action_label(str(value.get("action_id", "")))])
	return "동시 판단 · " + " / ".join(action_parts) if not action_parts.is_empty() else ""


func _event_message_ko(event: Dictionary) -> String:
	var explicit := str(event.get("message_ko", ""))
	if not explicit.is_empty():
		return explicit
	var actor_name := _actor_name(str(event.get("actor_id", "")))
	var event_type := str(event.get("type", ""))
	match event_type:
		"ACTION":
			return "%s는 %s고 판단했습니다." % [actor_name,
				_action_label(str(event.get("action_id", "")))]
		"DAMAGE":
			return "%s의 공격이 상대에게 %d 피해를 주었습니다." % [actor_name,
				int(event.get("magnitude", 0))]
		"MOVE":
			return "%s가 판단한 방향으로 움직였습니다." % actor_name
		"HEAL":
			return "%s가 자신을 치료해 HP를 %d 회복했습니다." % [actor_name,
				int(event.get("magnitude", 0))]
		"STATUS_TICK":
			return "%s의 상태이상이 %d 피해를 냈습니다." % [actor_name,
				int(event.get("magnitude", 0))]
		"MEMORY":
			return "관계 · %s는 공격받은 일을 원한으로 기억했습니다." % actor_name
		"DEATH":
			return "%s가 쓰러졌습니다." % actor_name
	var fallback := str(event.get("message", ""))
	for action_id in ["APPROACH", "ENGAGE", "FLEE", "HOLD", "SELF_TREAT"]:
		fallback = fallback.replace(action_id, _action_label(action_id))
	return fallback if not fallback.is_empty() else "두 인물 사이에 사건이 일어났습니다."


func _actor_name(actor_id: String) -> String:
	var actor := _actor_by_id(actor_id)
	return str(actor.get("name", "인물")) if not actor.is_empty() else "인물"


func _on_primary_action() -> void:
	match presentation_stage:
		"HIDDEN":
			_shown_breakdowns = _breakdowns.duplicate(true)
			presentation_stage = "INTENT"
			ui_notice = ""
			_refresh_phase()
			_refresh_tabs()
			_refresh_detail()
			_refresh_controls()
		"INTENT":
			_step()
		"RESULT":
			_shown_breakdowns = _breakdowns.duplicate(true)
			presentation_stage = "INTENT"
			ui_notice = ""
			_refresh_phase()
			_refresh_tabs()
			_refresh_detail()
			_refresh_controls()


func _step() -> void:
	if simulator == null:
		return
	ui_notice = ""
	if _shown_breakdowns.is_empty():
		_shown_breakdowns = _breakdowns.duplicate(true)
	var result_value: Variant = simulator.step()
	if result_value is Dictionary and not bool(result_value.get("accepted", result_value.get("ok", true))):
		ui_notice = "판단 실패 · %s" % _rejection_text(str(result_value.get("reason", "")))
	else:
		presentation_stage = "RESULT"
	_refresh()


func _restart_same_situation() -> void:
	if simulator == null:
		return
	simulator.restart_same_scenario()
	ui_notice = "같은 상황을 처음부터 다시 봅니다"
	detail_mode = "OVERVIEW"
	presentation_stage = "HIDDEN"
	_shown_breakdowns.clear()
	selected_actor_id = ""
	_refresh()


func _new_random_situation() -> void:
	if simulator == null:
		return
	var seed_text := seed_edit.text.strip_edges()
	if not seed_text.is_valid_int():
		ui_notice = "seed는 정수로 입력하세요"
		_refresh_phase()
		return
	var seed_value := int(seed_text)
	if seed_text == str(_observation.get("seed", "")):
		seed_value += 1
	_start_seeded_situation(seed_value)


func _apply_typed_seed(value: String) -> void:
	if simulator == null:
		return
	var seed_text := value.strip_edges()
	if not seed_text.is_valid_int():
		ui_notice = "seed는 정수로 입력하세요"
		_refresh_phase()
		return
	_start_seeded_situation(int(seed_text))


func _start_seeded_situation(seed_value: int) -> void:
	simulator.new_random_scenario(seed_value)
	ui_notice = "seed %d의 새 상황" % seed_value
	detail_mode = "OVERVIEW"
	presentation_stage = "HIDDEN"
	_shown_breakdowns.clear()
	selected_actor_id = ""
	_refresh()


func _on_actor_pressed(actor_id: String) -> void:
	selected_actor_id = actor_id
	_refresh_tabs()
	_refresh_detail()
	grid.set_observation(_observation, selected_actor_id)


func _select_actor_index(index: int) -> void:
	var actors: Array = _observation.get("actors", [])
	if index < 0 or index >= actors.size() or not actors[index] is Dictionary:
		return
	_on_actor_pressed(_actor_id(actors[index]))


func _show_events() -> void:
	detail_mode = "OVERVIEW" if detail_mode == "EVENTS" else "EVENTS"
	_refresh_tabs()
	_refresh_detail()


func _toggle_detail() -> void:
	detail_mode = "OVERVIEW" if detail_mode == "DETAIL" else "DETAIL"
	_refresh_tabs()
	_refresh_detail()


func _back_to_party() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file(PARTY_SCENE_PATH)


func _show_unavailable() -> void:
	if phase_label == null:
		return
	phase_label.text = ui_notice if not ui_notice.is_empty() else "판단 시뮬레이터 연결 대기 중"
	detail_text.text = "코어 판단 DTO가 준비되면 두 인물의 선택 근거가 여기에 표시됩니다."
	step_button.disabled = true
	restart_button.disabled = true


func _breakdown_for(actor_id: String) -> Dictionary:
	for value in _breakdowns:
		if value is Dictionary and str(value.get("actor_id", "")) == actor_id:
			return value
	return {}


func _shown_breakdown_for(actor_id: String) -> Dictionary:
	for value in _shown_breakdowns:
		if value is Dictionary and str(value.get("actor_id", "")) == actor_id:
			return value
	return {}


func _actor_by_id(actor_id: String) -> Dictionary:
	for value in _observation.get("actors", []):
		if value is Dictionary and _actor_id(value) == actor_id:
			return value
	return {}


func _contains_actor(actor_id: String) -> bool:
	return not _actor_by_id(actor_id).is_empty()


func _actor_id(actor: Dictionary) -> String:
	return str(actor.get("id", actor.get("entity_id", "")))


func _relation_terms(value: Variant) -> Dictionary:
	var species: Array = []
	var memory: Array = []
	var other: Array = []
	if value is Array:
		for term_value in value:
			if not term_value is Dictionary:
				continue
			var term: Dictionary = term_value
			var marker := (str(term.get("bucket", "")) + "/" + str(term.get("source", "")) \
				+ "/" + str(term.get("input_id", ""))).to_lower()
			if "species" in marker or "prior" in marker or "종족" in marker:
				species.append(term)
			elif "memory" in marker or "기억" in marker:
				memory.append(term)
			else:
				other.append(term)
	return {"species": species, "memory": memory, "other": other}


func _terms_total(value: Variant) -> String:
	if not value is Array or value.is_empty():
		return "0"
	var total := 0.0
	for term_value in value:
		if term_value is Dictionary:
			total += float(term_value.get("contribution", term_value.get("amount", term_value.get("value", 0))))
	return _number_text(total)


func _append_term_detail(target: Array[String], category: String, value: Variant) -> void:
	if not value is Array or value.is_empty():
		return
	var parts: Array[String] = []
	for term_value in value:
		if not term_value is Dictionary:
			continue
		parts.append("%s %s" % [_term_label(term_value), _number_text(term_value.get("contribution",
			term_value.get("amount", term_value.get("value", 0))))])
	if not parts.is_empty():
		target.append("%s: %s" % [category, ", ".join(parts)])


func _term_label(term: Dictionary) -> String:
	var explicit := str(term.get("label_ko", ""))
	if not explicit.is_empty():
		return explicit
	var input_id := str(term.get("input_id", term.get("facet", "")))
	return str({
		"H": "정직-겸손", "E": "정서성", "X": "외향성", "A": "원만성", "C": "성실성", "O": "개방성",
		"health": "체력", "injury": "부상", "fatigue": "피로", "supplies": "치료 물자",
		"dot": "상태이상", "danger": "위험", "threat": "위협", "safety": "안전",
		"armed": "무장 상태", "power": "전투력", "power_gap": "전력 열세",
		"treatment_need": "치료 필요", "species_prior": "종족 기본 관계",
		"memory_modifier": "개인 기억", "personal_memory": "개인 기억",
		"affinity": "친밀감", "hostility": "적대감", "fear_pressure": "과거 위협 기억",
		"neutrality": "중립성", "distance": "서로의 거리", "other_alive": "상대 생존",
		"escape_space": "후퇴 공간", "approach_pressure": "접근 필요",
		"uncertainty": "상황의 불확실성",
	}.get(input_id, "판단 요소"))


func _number_text(value: Variant) -> String:
	var number := float(value)
	if is_equal_approx(number, roundf(number)):
		return "%+d" % int(roundf(number))
	return "%+.1f" % number


func _action_label(action_id: String) -> String:
	return str({"APPROACH": "상대에게 조심스럽게 다가간다", "ROAM": "주변을 살핀다",
		"ENGAGE": "맞서 싸운다", "FLEE": "안전한 곳으로 물러난다",
		"HOLD": "자리를 지키며 지켜본다", "REST": "숨을 고르며 쉰다",
		"SELF_TREAT": "자신을 치료한다"}.get(action_id, "상황을 지켜본다"))


func _rejection_text(reason: String) -> String:
	if reason.is_empty():
		return "현재 조건을 만족하지 못했습니다."
	for index in reason.length():
		var code := reason.unicode_at(index)
		if code >= 0xAC00 and code <= 0xD7A3:
			return reason
	return str({
		"hostile_too_far": "상대가 행동 범위 밖에 있습니다.",
		"health_too_low": "몸 상태가 싸움을 감당하지 못합니다.",
		"not_in_danger": "지금은 달아날 만큼 위급하지 않습니다.",
		"not_injured": "치료할 부상이나 상태이상이 없습니다.",
		"no_supplies": "치료 물자가 없습니다.",
		"scenario_complete": "이 상황의 결말이 이미 정해졌습니다.",
	}.get(reason, "현재 조건을 만족하지 못했습니다."))


func _species_label(species_id: String) -> String:
	return str({"human": "인간", "dwarf": "드워프", "goblin": "고블린", "amphibian": "양서인",
		"beastkin": "수인"}.get(species_id.to_lower(), species_id))


func _weapon_summary(actor: Dictionary) -> String:
	if not bool(actor.get("armed", false)):
		return "비무장"
	return "%s · 전투력 %d" % [_weapon_label(str(actor.get("weapon", "무기"))), int(actor.get("power", 0))]


func _dot_summary(value: Variant) -> String:
	if value is Dictionary:
		if value.is_empty():
			return "없음"
		value = [value]
	if not value is Array or value.is_empty():
		return "없음"
	var parts: Array[String] = []
	for row_value in value:
		if row_value is Dictionary:
			var raw_status := str(row_value.get("label_ko", row_value.get("status_id", "상태이상")))
			var status := str({"BLEEDING": "출혈", "POISONED": "독"}.get(raw_status.to_upper(), raw_status))
			var remaining := str(row_value.get("remaining", row_value.get("remaining_quanta", "")))
			parts.append(status + (" %s턴" % remaining if not remaining.is_empty() else ""))
		else:
			parts.append(str(row_value))
	return ", ".join(parts)


func _weapon_label(weapon_id: String) -> String:
	return str({"SPEAR": "창", "SWORD": "검", "DAGGER": "단검", "BOW": "활", "NONE": "맨손"}.get(
		weapon_id.to_upper(), weapon_id))


func _hexaco(hexaco: Dictionary, key: String) -> int:
	return int(hexaco.get(key, hexaco.get(key.to_lower(), 0)))


func _add_button(parent: Control, value: String, node_name: String, callback: Callable,
		font_size: int = 16) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = value
	button.custom_minimum_size.y = TOUCH_TARGET
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _panel_style(background: String, border: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func layout_spec() -> Dictionary:
	return {
		"grid_size": grid.GRID_SIZE if grid != null else 0,
		"grid_rect": grid.grid_rect() if grid != null else Rect2(),
		"layout_minimum": root_layout.get_combined_minimum_size() if root_layout != null else Vector2.ZERO,
		"selected_actor_id": selected_actor_id,
		"detail_mode": detail_mode,
	}
