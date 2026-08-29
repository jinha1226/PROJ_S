class_name DuelDecisionLab
extends Control

const GridScript = preload("res://playtest/duel_decision_grid.gd")
const KoreanFont: FontFile = preload("res://assets/fonts/NanumSquareR.ttf")
const SIMULATOR_PATH := "res://sim/dungeon_population/dungeon_population_simulator.gd"
const PARTY_SCENE_PATH := "res://playtest/party_encounter_sandbox.tscn"
const DEFAULT_SEED := 22002
const TOUCH_TARGET := 44

var simulator
var grid: DuelDecisionGrid
var root_layout: VBoxContainer
var phase_label: Label
var seed_edit: LineEdit
var step_button: Button
var restart_button: Button
var actor_buttons: Array[Button] = []
var event_button: Button
var detail_text: RichTextLabel

var selected_actor_id := ""
var detail_mode := "ACTOR"
var ui_notice := ""
var _observation: Dictionary = {}
var _breakdowns: Array = []
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
	detail_mode = "ACTOR"
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
	root_layout.add_theme_constant_override("separation", 4)
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
	var random_button := _add_button(header, "새 상황", "NewRandomSituation", _new_random_situation, 15)
	random_button.custom_minimum_size.x = 68

	var phase_panel := PanelContainer.new()
	phase_panel.name = "DecisionOutcomePanel"
	phase_panel.custom_minimum_size.y = 50
	phase_panel.add_theme_stylebox_override("panel", _panel_style("#10212d", "#426173"))
	root_layout.add_child(phase_panel)
	phase_label = Label.new()
	phase_label.name = "DecisionOutcome"
	phase_label.add_theme_font_size_override("font_size", 16)
	phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_panel.add_child(phase_label)

	grid = GridScript.new()
	grid.name = "DuelDecisionGrid"
	grid.custom_minimum_size = Vector2(225, 225)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.actor_pressed.connect(_on_actor_pressed)
	root_layout.add_child(grid)

	var controls := HBoxContainer.new()
	controls.name = "DecisionControls"
	controls.custom_minimum_size.y = TOUCH_TARGET
	controls.add_theme_constant_override("separation", 4)
	root_layout.add_child(controls)
	step_button = _add_button(controls, "판단하기", "ResolveTurn", _step, 18)
	step_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_button.size_flags_stretch_ratio = 1.6
	restart_button = _add_button(controls, "같은 상황 다시", "RestartSameSituation", _restart_same_situation, 16)
	restart_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var tabs := HBoxContainer.new()
	tabs.name = "DecisionDetailTabs"
	tabs.custom_minimum_size.y = 48
	tabs.add_theme_constant_override("separation", 4)
	root_layout.add_child(tabs)
	for index in range(2):
		var actor_button := _add_button(tabs, "인물 %s" % ("A" if index == 0 else "B"),
			"ActorCardTab%d" % index, _select_actor_index.bind(index), 15)
		actor_button.toggle_mode = true
		actor_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actor_button.size_flags_stretch_ratio = 1.25
		actor_buttons.append(actor_button)
	event_button = _add_button(tabs, "사건", "EventLogTab", _show_events, 15)
	event_button.toggle_mode = true
	event_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_button.size_flags_stretch_ratio = 0.65

	var detail_panel := PanelContainer.new()
	detail_panel.name = "DecisionDetailPanel"
	detail_panel.custom_minimum_size.y = 136
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
	var resolution: Dictionary = _observation.get("last_resolution", {}) \
		if _observation.get("last_resolution", {}) is Dictionary else {}
	var message := _resolution_summary(resolution)
	if message.is_empty() and not _recent_logs.is_empty() and _recent_logs[-1] is Dictionary:
		message = _event_message_ko(_recent_logs[-1])
	if message.is_empty():
		message = "두 인물은 같은 상황을 서로 다르게 판단할 수 있습니다."
	var phase_text := "실험 완료" if str(_observation.get("phase", "ACTIVE")) == "COMPLETE" else "판단 대기"
	phase_label.text = (ui_notice + " · " if not ui_notice.is_empty() else "") \
		+ "T%s · %s\n%s" % [str(_observation.get("tick_index", "0")), phase_text, message]


func _refresh_tabs() -> void:
	var actors: Array = _observation.get("actors", [])
	for index in range(actor_buttons.size()):
		var button: Button = actor_buttons[index]
		if index >= actors.size() or not actors[index] is Dictionary:
			button.text = "인물 %s 없음" % ("A" if index == 0 else "B")
			button.disabled = true
			button.button_pressed = false
			continue
		var actor: Dictionary = actors[index]
		button.disabled = false
		button.text = "%s · %s\nHP %d/%d" % [str(actor.get("name", "인물 %s" % ("A" if index == 0 else "B"))),
			_species_label(str(actor.get("species_id", "?"))), int(actor.get("hp", 0)), int(actor.get("max_hp", 0))]
		button.button_pressed = detail_mode == "ACTOR" and _actor_id(actor) == selected_actor_id
	event_button.button_pressed = detail_mode == "EVENTS"


func _refresh_controls() -> void:
	var complete := str(_observation.get("phase", "ACTIVE")) == "COMPLETE"
	step_button.disabled = complete
	step_button.text = "실험 완료" if complete else ("판단하기" if int(str(_observation.get("tick_index", "0"))) == 0 else "다음 턴")


func _refresh_detail() -> void:
	detail_text.text = event_log_text(_recent_logs) if detail_mode == "EVENTS" else actor_card_text(selected_actor_id)


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
		"HEXACO  H %d  E %d  X %d  A %d  C %d  O %d" % [
			_hexaco(hexaco, "H"), _hexaco(hexaco, "E"), _hexaco(hexaco, "X"),
			_hexaco(hexaco, "A"), _hexaco(hexaco, "C"), _hexaco(hexaco, "O")],
	]
	var breakdown := _breakdown_for(actor_id)
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


func _step() -> void:
	if simulator == null:
		return
	ui_notice = ""
	var result_value: Variant = simulator.step()
	if result_value is Dictionary and not bool(result_value.get("accepted", result_value.get("ok", true))):
		ui_notice = "판단 실패 · %s" % _rejection_text(str(result_value.get("reason", "")))
	_refresh()


func _restart_same_situation() -> void:
	if simulator == null:
		return
	simulator.restart_same_scenario()
	ui_notice = "같은 상황을 처음부터 다시 봅니다"
	detail_mode = "ACTOR"
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
	detail_mode = "ACTOR"
	selected_actor_id = ""
	_refresh()


func _on_actor_pressed(actor_id: String) -> void:
	selected_actor_id = actor_id
	detail_mode = "ACTOR"
	_refresh_tabs()
	_refresh_detail()
	grid.set_observation(_observation, selected_actor_id)


func _select_actor_index(index: int) -> void:
	var actors: Array = _observation.get("actors", [])
	if index < 0 or index >= actors.size() or not actors[index] is Dictionary:
		return
	_on_actor_pressed(_actor_id(actors[index]))


func _show_events() -> void:
	detail_mode = "EVENTS"
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
			var status := str(row_value.get("label_ko", row_value.get("status_id", "상태이상")))
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
