class_name NpcExpeditionLab
extends Control

const SimulatorScript = preload("res://sim/npc_expedition/npc_expedition_simulator.gd")
const PartySimulatorScript = preload("res://sim/party_combat_observer_simulator.gd")
const GridScript = preload("res://playtest/npc_expedition_grid.gd")
const KoreanFont: FontFile = preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const PARTY_SCENE_PATH := "res://playtest/party_encounter_sandbox.tscn"
const DEFAULT_SEED := 22002
const TOUCH_TARGET := 44
const DEFAULT_PLAYBACK_SPEED := 1.0
const PLAYBACK_SPEEDS := [0.5, 1.0, 2.0, 4.0]
const BASE_PLAYBACK_INTERVAL := 0.4

var simulator
var grid: NpcExpeditionGrid
var root_layout: VBoxContainer
var title_label: Label
var phase_label: Label
var goal_label: Label
var turn_queue_label: Label
var npc_status_label: Label
var monster_status_label: Label
var detail_text: RichTextLabel
var seed_edit: LineEdit
var auto_button: Button
var step_button: Button
var reset_button: Button
var auto_timer: Timer
var speed_label: Label
var speed_buttons: Dictionary = {}
var mode_button: Button
var playback_speed := DEFAULT_PLAYBACK_SPEED
var observer_mode := "NPC"
var _initialized_for_headless_test := false


func _ready() -> void:
	_build_ui()
	if simulator == null and not _initialized_for_headless_test:
		simulator = SimulatorScript.new(DEFAULT_SEED)
	_refresh()


func initialize_for_headless_test(custom_simulator = null) -> void:
	if grid == null:
		_build_ui()
	_initialized_for_headless_test = true
	simulator = custom_simulator if custom_simulator != null else SimulatorScript.new(DEFAULT_SEED)
	var initial_observation:Dictionary=simulator.observation()
	observer_mode="PARTY" if str(initial_observation.get("mode",""))=="PARTY_COMBAT" else "NPC"
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
	background.name = "NpcExpeditionBackground"
	background.color = Color("#050b10")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	root_layout = VBoxContainer.new()
	root_layout.name = "NpcExpeditionLayout"
	root_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layout.offset_left = 6
	root_layout.offset_top = 4
	root_layout.offset_right = -6
	root_layout.offset_bottom = -4
	root_layout.add_theme_constant_override("separation", 4)
	add_child(root_layout)

	var header := HBoxContainer.new()
	header.name = "NpcExpeditionHeader"
	header.custom_minimum_size.y = TOUCH_TARGET
	header.add_theme_constant_override("separation", 4)
	root_layout.add_child(header)
	var back := _button("← 복귀", "BackToParty", _back_to_party)
	back.custom_minimum_size.x = 62
	header.add_child(back)
	title_label = Label.new()
	title_label.name = "NpcExpeditionTitle"
	title_label.text = "NPC 원정 관찰"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	mode_button=_button("파티 보기","ObserverModeToggle",_toggle_observer_mode)
	mode_button.custom_minimum_size.x=78
	header.add_child(mode_button)
	seed_edit = LineEdit.new()
	seed_edit.name = "NpcSeedInput"
	seed_edit.custom_minimum_size = Vector2(72, TOUCH_TARGET)
	seed_edit.placeholder_text = "seed"
	seed_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	seed_edit.text_submitted.connect(_apply_seed)
	header.add_child(seed_edit)

	var summary := PanelContainer.new()
	summary.name = "NpcExpeditionSummary"
	summary.custom_minimum_size.y = 72
	summary.add_theme_stylebox_override("panel", _panel_style("#0b1820", "#31515c"))
	root_layout.add_child(summary)
	var summary_stack := VBoxContainer.new()
	summary_stack.add_theme_constant_override("separation", 0)
	summary.add_child(summary_stack)
	phase_label = Label.new()
	phase_label.name = "NpcExpeditionPhase"
	phase_label.add_theme_font_size_override("font_size", 17)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary_stack.add_child(phase_label)
	goal_label = Label.new()
	goal_label.name = "NpcExpeditionGoal"
	goal_label.add_theme_font_size_override("font_size", 13)
	goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary_stack.add_child(goal_label)
	turn_queue_label=Label.new()
	turn_queue_label.name="PartyTurnQueue"
	turn_queue_label.add_theme_font_size_override("font_size",13)
	turn_queue_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	turn_queue_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	turn_queue_label.visible=false
	summary_stack.add_child(turn_queue_label)

	grid = GridScript.new()
	grid.name = "NpcExpeditionGrid"
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.custom_minimum_size = Vector2(360, 290)
	root_layout.add_child(grid)

	var status_row := HBoxContainer.new()
	status_row.name = "NpcExpeditionVitals"
	status_row.custom_minimum_size.y = 46
	status_row.add_theme_constant_override("separation", 4)
	root_layout.add_child(status_row)
	npc_status_label = _status_card(status_row, "NpcStatus", Color("#69e5dc"))
	monster_status_label = _status_card(status_row, "MonsterStatus", Color("#ef725f"))

	var detail_panel := PanelContainer.new()
	detail_panel.name = "NpcDecisionInspector"
	detail_panel.custom_minimum_size.y = 150
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _panel_style("#0a151c", "#263f4b"))
	root_layout.add_child(detail_panel)
	detail_text = RichTextLabel.new()
	detail_text.name = "NpcDecisionText"
	detail_text.bbcode_enabled = false
	detail_text.fit_content = false
	detail_text.scroll_active = true
	detail_text.add_theme_font_size_override("normal_font_size", 14)
	detail_panel.add_child(detail_text)

	var speed_row := HBoxContainer.new()
	speed_row.name = "NpcPlaybackSpeedControls"
	speed_row.custom_minimum_size.y = TOUCH_TARGET
	speed_row.add_theme_constant_override("separation", 4)
	root_layout.add_child(speed_row)
	speed_label = Label.new()
	speed_label.name = "NpcPlaybackSpeedLabel"
	speed_label.custom_minimum_size.x = 78
	speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speed_label.add_theme_font_size_override("font_size", 13)
	speed_row.add_child(speed_label)
	for speed_value in PLAYBACK_SPEEDS:
		var speed := float(speed_value)
		var button := _button(_speed_text(speed), _speed_button_name(speed),
			_set_playback_speed.bind(speed))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "자동 재생 속도를 %s로 변경" % _speed_text(speed)
		speed_row.add_child(button)
		speed_buttons[speed] = button

	var controls := HBoxContainer.new()
	controls.name = "NpcExpeditionControls"
	controls.custom_minimum_size.y = TOUCH_TARGET
	controls.add_theme_constant_override("separation", 4)
	root_layout.add_child(controls)
	auto_button = _button("자동 재생", "NpcAutoPlay", _toggle_auto)
	auto_button.toggle_mode = true
	auto_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(auto_button)
	step_button = _button("1턴 진행", "NpcStep", _step_once)
	step_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(step_button)
	reset_button = _button("같은 시드 재시작", "NpcReset", _reset_same_seed)
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(reset_button)

	auto_timer = Timer.new()
	auto_timer.name = "NpcAutoTimer"
	auto_timer.timeout.connect(_on_auto_tick)
	add_child(auto_timer)
	_set_playback_speed(DEFAULT_PLAYBACK_SPEED)


func _refresh() -> void:
	if simulator == null or grid == null:
		return
	var observation: Dictionary = simulator.observation()
	grid.set_observation(observation)
	if not seed_edit.has_focus():
		seed_edit.text = str(observation.seed)
	var party_mode:=str(observation.get("mode",""))=="PARTY_COMBAT"
	observer_mode="PARTY" if party_mode else "NPC"
	title_label.text="파티 전투 관찰" if party_mode else "NPC 원정 관찰"
	mode_button.text="1:1 보기" if party_mode else "파티 보기"
	phase_label.text = "%s · 제%d차 원정 · 완료 %d회" % [observation.phase_label,
		int(observation.expedition_number), int(observation.completed_cycles)]
	if party_mode:
		phase_label.text="%s · T%s"%[str(observation.phase_label),str(observation.turn_index)]
	goal_label.text = "목표 · %s" % str(observation.goal)
	turn_queue_label.visible=party_mode
	if party_mode:
		var tokens:Array[String]=[]
		for row_value in observation.get("next_queue",[]):
			if row_value is Dictionary:
				tokens.append("%s%s"%[str(row_value.get("glyph","?")),
					str(row_value.get("action_symbol","?"))])
		turn_queue_label.text="NEXT  %s"%"  ".join(tokens) if not tokens.is_empty() \
			else "NEXT  —"
		var party:Dictionary=observation.get("party",{})
		var enemies:Dictionary=observation.get("enemy_force",{})
		npc_status_label.text="@ 파티 %d명 · 활동 %d\nHP %d/%d"%[
			int(party.get("count",0)),int(party.get("active",0)),
			int(party.get("hp",0)),int(party.get("max_hp",0))]
		monster_status_label.text="g 적군 %d체 · 활동 %d\nHP %d/%d"%[
			int(enemies.get("count",0)),int(enemies.get("active",0)),
			int(enemies.get("hp",0)),int(enemies.get("max_hp",0))]
	else:
		var npc: Dictionary = observation.npc
		npc_status_label.text = "@ 아린  HP %d/%d\n물약 %d · 전리품 %d" % [
			int(npc.hp), int(npc.max_hp), int(npc.potions), int(npc.carried_loot)]
		var monster: Dictionary = observation.monster
		monster_status_label.text = "g 감염체 %d체 · 활동 %d\n목표 %d/%d · 위협 %d" % [
			int(observation.get("monster_count", 1)), int(observation.get("active_monster_count", 0)),
			int(monster.hp), int(monster.max_hp), int(observation.get("threat_milli", 0))]
	detail_text.text = inspector_text(observation)
	step_button.disabled = bool(observation.get("terminal",false)) \
		or str(observation.phase) == "DEAD"
	if step_button.disabled:
		_stop_auto()


func inspector_text(observation: Dictionary) -> String:
	if str(observation.get("mode",""))=="PARTY_COMBAT":
		return _party_inspector_text(observation)
	var decision: Dictionary = observation.decision
	var npc: Dictionary = observation.npc
	var lines: Array[String] = []
	lines.append("구조 · 원정 상태기계 → 공용 Utility 규칙셋 → 공용 행동 커널")
	lines.append("규칙 · %s" % str(decision.get("ruleset_id", "-")))
	lines.append("현재 판단 · %s" % str(decision.get("selected_label", "대기")))
	lines.append("이유 · %s" % str(decision.get("selected_reason", "")))
	lines.append("")
	lines.append("후보 행동")
	for row_value in decision.get("candidates", []):
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value
		var marker := "▶" if bool(row.get("selected", false)) else "·"
		var score := str(row.get("score", -1)) if bool(row.get("legal", false)) else "불가"
		lines.append("%s %s  [%s]" % [marker, str(row.get("label", "행동")), score])
		if bool(row.get("selected", false)):
			var term_labels: Array[String] = []
			for term_value in row.get("terms", []):
				if term_value is Dictionary:
					var contribution := int(term_value.get("value", 0))
					term_labels.append("%s %s%d" % [str(term_value.get("factor", "요인")),
						"+" if contribution >= 0 else "", contribution])
			if not term_labels.is_empty():
				lines.append("  점수 구성 · %s" % " / ".join(term_labels))
	lines.append("")
	lines.append("성격 · %s" % str(npc.get("style", {}).get("label", "-")))
	var hexaco: Dictionary = npc.get("hexaco", {})
	lines.append("HEXACO · H %d / E %d / X %d / A %d / C %d / O %d" % [
		int(hexaco.get("H", 500)), int(hexaco.get("E", 500)),
		int(hexaco.get("X", 500)), int(hexaco.get("A", 500)),
		int(hexaco.get("C", 500)), int(hexaco.get("O", 500))])
	lines.append("소지품 · %s" % ", ".join(observation.get("inventory_labels", [])))
	lines.append("위협 · %d/1000 · 활동 %d · 쓰러짐 %d" % [
		int(observation.get("threat_milli", 0)),
		int(observation.get("active_monster_count", 0)),
		int(observation.get("downed_monster_count", 0))])
	for monster_value in observation.get("monsters", []):
		if monster_value is Dictionary and str(monster_value.get("life_state", "")) != "DEAD":
			lines.append("  %s · 이동 %s(%d) / 공격 %s(%d) / 인지 %s" % [
				str(monster_value.get("name", "감염체")),
				str(monster_value.get("move_speed", "보통")), int(monster_value.get("move_cost", 100)),
				str(monster_value.get("attack_speed", "보통")), int(monster_value.get("attack_cost", 100)),
				str(monster_value.get("awareness_state", "UNAWARE"))])
	lines.append("")
	lines.append("최근 사건")
	for event_value in observation.get("recent_events", []):
		if event_value is Dictionary:
			lines.append("T%s · %s" % [str(event_value.get("turn", "0")),
				str(event_value.get("message", ""))])
	return "\n".join(lines)


func _party_inspector_text(observation:Dictionary)->String:
	var lines:Array[String]=[]
	lines.append("구조 · 개별 시야 → 파티 공유 → 자동 경고 → 암묵적 지시")
	lines.append("규칙 · %s"%str(observation.get("ruleset_id","-")))
	var warning:Dictionary=observation.get("warning",{})
	if bool(warning.get("available",false)):
		lines.append("경고 · %s"%str(warning.get("message","")))
	lines.append("")
	lines.append("다음 행동")
	for row_value in observation.get("next_queue",[]):
		if not row_value is Dictionary:continue
		var row:Dictionary=row_value
		var target_text:=" → %s"%str(row.get("target_name","")) \
			if not str(row.get("target_name","")).is_empty() else ""
		lines.append("%s%s  %s%s"%[str(row.get("glyph","?")),
			str(row.get("action_symbol","?")),str(row.get("name","행동자")),target_text])
	lines.append("")
	lines.append("동료 판단")
	for row_value in observation.get("decision",{}).get("companions",[]):
		if not row_value is Dictionary:continue
		var row:Dictionary=row_value
		lines.append("· %s · %s%s"%[str(row.get("name","동료")),
			str(row.get("action_id","HOLD"))," · 공황" \
			if str(row.get("mode","NORMAL"))=="PANIC" else ""])
	lines.append("")
	lines.append("최근 사건")
	for event_value in observation.get("recent_events",[]):
		if event_value is Dictionary:
			lines.append("T%s · %s"%[str(event_value.get("turn","0")),
				str(event_value.get("message",""))])
	return "\n".join(lines)


func _step_once() -> void:
	if simulator != null:
		simulator.step()
		_refresh()


func _toggle_auto() -> void:
	if auto_button.button_pressed:
		auto_button.text = "일시 정지"
		if auto_timer.is_inside_tree():
			auto_timer.start()
	else:
		_stop_auto()


func _on_auto_tick() -> void:
	_step_once()


func _set_playback_speed(speed: float) -> void:
	if speed not in PLAYBACK_SPEEDS:
		return
	playback_speed = speed
	var was_running := auto_timer != null and auto_timer.is_inside_tree() \
		and not auto_timer.is_stopped()
	if auto_timer != null:
		auto_timer.wait_time = BASE_PLAYBACK_INTERVAL / playback_speed
		if was_running:
			auto_timer.start()
	if speed_label != null:
		speed_label.text = "재생 속도 · %s" % _speed_text(playback_speed)
	for speed_value in speed_buttons:
		var button := speed_buttons[speed_value] as Button
		button.set_pressed_no_signal(is_equal_approx(float(speed_value), playback_speed))


func _stop_auto() -> void:
	if auto_timer != null:
		if auto_timer.is_inside_tree():
			auto_timer.stop()
	if auto_button != null:
		auto_button.set_pressed_no_signal(false)
		auto_button.text = "자동 재생"


func _toggle_observer_mode() -> void:
	_stop_auto()
	var active_seed:=int(str(simulator.seed)) if simulator!=null else DEFAULT_SEED
	if observer_mode=="PARTY":
		observer_mode="NPC"
		simulator=SimulatorScript.new(active_seed)
	else:
		observer_mode="PARTY"
		simulator=PartySimulatorScript.new(active_seed)
	_refresh()


func _reset_same_seed() -> void:
	_stop_auto()
	if simulator != null:
		simulator.reset(int(str(simulator.seed)))
	_refresh()


func _apply_seed(value: String) -> void:
	_stop_auto()
	var parsed := int(value) if value.is_valid_int() else DEFAULT_SEED
	if simulator == null:
		simulator = SimulatorScript.new(parsed)
	else:
		simulator.reset(parsed)
	_refresh()


func _back_to_party() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file(PARTY_SCENE_PATH)


func _button(label: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.custom_minimum_size.y = TOUCH_TARGET
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(callback)
	return button


func _status_card(parent: Control, node_name: String, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	var style := _panel_style("#09131a", color.to_html(false))
	label.add_theme_stylebox_override("normal", style)
	parent.add_child(label)
	return label


func _panel_style(background: String, border: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_content_margin_all(5)
	return style


func _life_label(value: String) -> String:
	return {"ACTIVE": "활동", "DOWNED": "쓰러짐", "DEAD": "사망"}.get(value, value)


func _speed_text(speed: float) -> String:
	var numeric := str(int(speed)) if is_equal_approx(speed, floorf(speed)) else str(speed)
	return "%s×" % numeric


func _speed_button_name(speed: float) -> String:
	return "NpcPlaybackSpeed%s" % _speed_text(speed).replace(".", "_").replace("×", "x")
