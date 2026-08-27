class_name PersonalityLabSandbox
extends Control

const SessionScript = preload("res://playtest/playtest_session.gd")
const GridScript = preload("res://playtest/playtest_grid_view.gd")
const KoreanUIFont: FontFile = preload("res://assets/fonts/NanumSquareR.ttf")
const LEAD_UI_COLORS := [Color("#ff766d"), Color("#f3c85b"), Color("#8fcf62"), Color("#75a7ff")]

var session
var grid
var progress_panel: PanelContainer
var progress_banner: Label
var progress_style: StyleBoxFlat
var summaries: GridContainer
var inspector: RichTextLabel
var event_log: RichTextLabel
var drawer: RichTextLabel
var auto_timer: Timer
var one_turn_button: Button
var auto_button: Button
var ten_turn_button: Button
var auto_running := false
var drawer_open := false
var log_open := false
var ui_notice := ""

func _ready() -> void:
	_build_ui()
	if session == null: session = SessionScript.new()
	_refresh()

func initialize_for_headless_test(custom_session = null) -> void:
	if not is_node_ready(): _build_ui()
	session = custom_session if custom_session != null else SessionScript.new()
	_refresh()

func _build_ui() -> void:
	if grid != null: return
	var ui_theme := Theme.new()
	ui_theme.default_font = KoreanUIFont
	ui_theme.default_font_size = 13
	theme = ui_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new(); background.color = Color("#0b1018")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var root := VBoxContainer.new(); root.name = "LabLayout"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_theme_constant_override("separation", 4)
	root.offset_left = 6; root.offset_top = 4; root.offset_right = -6; root.offset_bottom = -4; add_child(root)
	progress_panel = PanelContainer.new(); progress_panel.name = "ProgressPanel"
	progress_panel.custom_minimum_size.y = 42
	progress_style = StyleBoxFlat.new(); progress_style.bg_color = Color("#152131")
	progress_style.border_color = Color("#5d7691")
	progress_style.set_border_width_all(1); progress_style.set_corner_radius_all(4)
	progress_style.content_margin_left = 5; progress_style.content_margin_right = 5
	progress_style.content_margin_top = 2; progress_style.content_margin_bottom = 2
	progress_panel.add_theme_stylebox_override("panel", progress_style); root.add_child(progress_panel)
	progress_banner = Label.new(); progress_banner.name = "ProgressBanner"
	progress_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress_banner.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	progress_banner.add_theme_font_size_override("font_size", 13); progress_panel.add_child(progress_banner)
	summaries = GridContainer.new(); summaries.name = "LeadSummaries"; summaries.columns = 2; summaries.custom_minimum_size.y = 62; root.add_child(summaries)
	grid = GridScript.new(); grid.name = "LabGrid"; grid.custom_minimum_size = Vector2(320, 320)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL; grid.world_cell_pressed.connect(_on_grid_pressed); root.add_child(grid)
	inspector = RichTextLabel.new(); inspector.name = "ReactionInspector"; inspector.fit_content = false
	inspector.custom_minimum_size.y = 116; inspector.scroll_active = true; inspector.bbcode_enabled = true; root.add_child(inspector)
	var controls := GridContainer.new(); controls.name = "Controls"; controls.columns = 5; root.add_child(controls)
	one_turn_button = _add_button(controls, "1턴", func(): _advance(1))
	auto_button = _add_button(controls, "자동 시작", _toggle_auto)
	ten_turn_button = _add_button(controls, "10턴", func(): _advance(10))
	_add_button(controls, "새 성격", _new_personality)
	_add_button(controls, "저장", _save)
	var second := HBoxContainer.new(); root.add_child(second)
	_add_button(second, "리셋", _reset)
	_add_button(second, "불러오기", _load)
	_add_button(second, "사건 로그", _toggle_event_log)
	_add_button(second, "계산 근거", _toggle_drawer)
	event_log = RichTextLabel.new(); event_log.name = "EventLog"; event_log.visible = false
	event_log.custom_minimum_size.y = 116; event_log.bbcode_enabled = true; event_log.scroll_active = true; root.add_child(event_log)
	drawer = RichTextLabel.new(); drawer.name = "CalculationDrawer"; drawer.visible = false
	drawer.custom_minimum_size.y = 136; drawer.bbcode_enabled = true; drawer.scroll_active = true; root.add_child(drawer)
	auto_timer = Timer.new(); auto_timer.name = "AutoTimer"; auto_timer.wait_time = 0.75; auto_timer.timeout.connect(func():
		if auto_running and session != null: _advance(1)); add_child(auto_timer)
	var viewport := get_viewport()
	if viewport != null and not viewport.focus_exited.is_connected(_pause_auto):
		viewport.focus_exited.connect(_pause_auto)

func _add_button(parent: Control, text_value: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text_value; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback); parent.add_child(button); return button

func _refresh() -> void:
	if session == null or grid == null: return
	_refresh_progress()
	var observation: Dictionary = session.observe_lab()
	grid.set_view(observation.get("cells", []), Vector2i(7, 7), null)
	for child in summaries.get_children(): child.queue_free()
	for row in session.lead_roster():
		var button := Button.new(); button.name = "Lead%d" % (int(row.trial_slot) + 1)
		button.clip_text = true
		var selected_mark := "▶" if int(row.entity_id) == session.selected_lead_id else "#"
		button.text = "%s%d HP%d · 공포%d · %s" % [selected_mark, int(row.trial_slot) + 1,
			int(row.health), int(row.fear), _reaction_label(str(row.reaction))]
		var lead_color: Color = LEAD_UI_COLORS[int(row.trial_slot)]
		button.add_theme_color_override("font_color", lead_color)
		button.add_theme_color_override("font_hover_color", lead_color.lightened(0.15))
		button.pressed.connect(func(): session.select_lead(int(row.entity_id)); _refresh())
		summaries.add_child(button)
	var detail: Dictionary = session.inspect_reaction(session.selected_lead_id)
	inspector.text = _inspector_text(detail)
	event_log.text = _event_log_text(session.recent_event_log(24))
	drawer.text = _drawer_text(detail)
	grid.selected_trial_slot = int(detail.get("identity", {}).get("trial_slot", -1))
	grid.queue_redraw()

func _refresh_progress() -> void:
	if session == null or progress_banner == null: return
	var status: Dictionary = session.progress_status()
	progress_banner.text = _progress_text(status)
	var phase_id := str(status.get("display_phase_id", status.get("phase_id", "ARMED")))
	var result_finished: bool = phase_id in ["RESOLVED", "COMPLETE"] or int(status.get("active_trials", 1)) <= 0
	if one_turn_button != null: one_turn_button.disabled = result_finished
	if ten_turn_button != null: ten_turn_button.disabled = result_finished
	if auto_button != null:
		auto_button.disabled = result_finished
		auto_button.text = "진행 완료" if result_finished else ("자동 정지" if auto_running else "자동 시작")
	progress_style.bg_color = Color({"ARMED": "#172333", "ACTIVE": "#172b25",
		"RESOLVED": "#30241a", "COMPLETE": "#30241a"}.get(phase_id, "#172333"))
	progress_style.border_color = Color({"ARMED": "#6683a1", "ACTIVE": "#64bf87",
		"RESOLVED": "#d2a158", "COMPLETE": "#d2a158"}.get(phase_id, "#6683a1"))
	progress_panel.queue_redraw()

func _progress_text(status: Dictionary) -> String:
	if not bool(status.get("ok", false)): return "진행 상태를 불러올 수 없습니다"
	var auto_text := "켜짐" if auto_running else "꺼짐"
	var display_phase_id := str(status.get("display_phase_id", status.phase_id))
	var first_line: String
	if display_phase_id == "ARMED":
		first_line = "턴 %d · %s · 자동 %s" % [int(status.tick_index), str(status.phase_label), auto_text]
	else:
		first_line = "턴 %d · %s · 남은 방 %d/%d · 주인공 %d · 적 %d · 자동 %s" % [
			int(status.tick_index), str(status.phase_label), int(status.active_trials), int(status.total_trials),
			int(status.active_leads), int(status.alive_threats), auto_text]
	var last: Dictionary = status.last_advance
	if not ui_notice.is_empty(): return first_line + "\n" + ui_notice
	if display_phase_id in ["RESOLVED", "COMPLETE"]:
		return first_line + "\n네 방의 결과가 모두 정해졌습니다 · 새 성격으로 다시 비교하세요"
	if not bool(last.available):
		return first_line + "\n" + ("1턴을 누르면 네 방에서 고블린이 동시에 나타납니다" \
			if str(status.phase_id) == "ARMED" else "1턴 또는 자동 시작으로 관찰을 계속하세요")
	if not bool(last.accepted): return first_line + "\n진행 실패 · %s" % str(last.reason)
	var second_line := "방금 +%d턴 · 사건 %d건" % [int(last.processed_ticks), int(last.emitted_event_count)]
	var salient: Dictionary = last.latest_salient_event
	if not salient.is_empty(): second_line += " · " + str(salient.message)
	return first_line + "\n" + second_line

func _event_log_text(rows: Array[Dictionary]) -> String:
	var status: Dictionary = session.progress_status() if session != null else {}
	var lines: Array[String] = ["[b]최근 세계 사건[/b] · 턴 %s · %s" % [
		str(status.get("tick_index", 0)), str(status.get("phase_label", "?"))]]
	if rows.is_empty():
		lines.append("아직 사건이 없습니다. ‘1턴’을 눌러 조우를 시작하세요.")
		return "\n".join(lines)
	for index in range(rows.size() - 1, -1, -1):
		var row: Dictionary = rows[index]
		lines.append("[color=#8fa3b8]T%04d · #%s[/color] %s" % [
			int(row.world_time), str(row.event_id), str(row.message)])
	return "\n".join(lines)

func _inspector_text(detail: Dictionary) -> String:
	if detail.is_empty(): return "lead를 선택하세요"
	var i: Dictionary = detail.identity; var p: Array = detail.personality.facet_rows
	var actual_trace: Dictionary = detail.last_trace
	var a: Dictionary = actual_trace.get("appraisal", detail.appraisal)
	var scores: Array[String] = []
	for c in actual_trace.get("candidates", detail.candidates):
		scores.append("%s=%s" % [c.reaction_id, str(c.score) if c.legal else c.rejection_reason])
	var live_gates: Array[String] = []
	for c in detail.candidates:
		if not c.legal: live_gates.append("%s:%s" % [c.reaction_id, c.rejection_reason])
	return "[b]#%d %s[/b] · HP %d/%d · (%d,%d)\n대담 %d / 공격 %d / 이타 %d / 침착 %d\n공포 %d / 분노 %d · %s · 객관 %d / 체감 %d\n결정시 %s\n근거 %s\nlive %s\n선택 %s → (%d,%d)" % [
		int(i.trial_slot)+1, i.name, i.health, i.max_health, i.position[0], i.position[1],
		_facet(p,"boldness"), _facet(p,"aggression"), _facet(p,"altruism"), _facet(p,"composure"),
		detail.emotion.fear, detail.emotion.anger, _mode_label(str(detail.emotion.mental_mode)),
		int(a.get("objective_danger",0)), int(a.get("perceived_threat",0)), " · ".join(scores),
		_committed_basis(actual_trace), " · ".join(live_gates),
		_reaction_label(str(detail.selected_reaction)), detail.target_position[0], detail.target_position[1]]

func _drawer_text(detail: Dictionary) -> String:
	if detail.is_empty(): return ""
	var actual_trace: Dictionary = detail.last_trace
	var lines: Array[String] = ["[b]committed decision trace · raw input → curve → contribution[/b]"]
	for candidate in actual_trace.get("candidates", detail.candidates):
		lines.append("\n[b]%s[/b] score=%d %s" % [candidate.reaction_id, candidate.score, candidate.rejection_reason])
		for gate in candidate.gates:
			lines.append("gate %s: %s %s" % [gate.gate_id, "VETO" if gate.veto else "PASS", gate.reason])
		for consideration in candidate.considerations:
			lines.append("%s: %d → %s:%d → %+d" % [consideration.input_id, consideration.raw_input,
				consideration.curve_id, consideration.curve_output, consideration.contribution])
	lines.append("\ncommit=%s busy=%s event=%s" % [detail.commitment_until, detail.busy_until,
		detail.last_decision_event_id])
	lines.append("mode evidence=%s" % str(actual_trace.get("mode_transition_evidence", {})))
	lines.append("switch evidence=%s" % str(actual_trace.get("switch_evidence", {})))
	for history in detail.action_history_rows:
		lines.append("history %s cooldown=%s last=%s repeat=%s" % [history.action_id,
			history.cooldown_until, history.last_committed_time, history.consecutive_commit_count])
	for relation_row in [["threat", detail.threat_relation], ["ally", detail.ally_relation]]:
		var relation: Dictionary = relation_row[1]
		if not relation.is_empty():
			lines.append("%s species=%s personal=%s effective=[T%d F%d H%d]" % [relation_row[0],
				str(relation.get("species_base", {})), str(relation.get("personal", {})),
				int(relation.get("trust", 0)), int(relation.get("fear", 0)), int(relation.get("hostility", 0))])
	lines.append("\n[b]causal events[/b]")
	for event in detail.recent_events:
		lines.append("#%s %s ← #%s" % [event.id, event.type, event.cause_id])
	lines.append("\n[b]live preview (not committed)[/b]")
	for candidate in detail.candidates:
		lines.append("%s=%s" % [candidate.reaction_id, str(candidate.score) if candidate.legal else candidate.rejection_reason])
	var status: Dictionary = session.lab_status() if session != null else {}
	lines.append("snapshot v%s · ruleset %s · journal %s" % [status.get("snapshot_version", "?"),
		status.get("ruleset_version", "?"), session.command_journal_json() if session != null else "[]"])
	return "\n".join(lines)

func _committed_basis(trace: Dictionary) -> String:
	if trace.is_empty(): return "아직 committed trace 없음"
	for candidate in trace.get("candidates", []):
		if candidate.reaction_id != trace.get("reaction_id", ""): continue
		var strongest_positive: Dictionary = {}
		var strongest_negative: Dictionary = {}
		for row in candidate.considerations:
			if int(row.contribution) > 0 and (strongest_positive.is_empty() \
					or int(row.contribution) > int(strongest_positive.contribution)):
				strongest_positive = row
			if int(row.contribution) < 0 and (strongest_negative.is_empty() \
					or int(row.contribution) < int(strongest_negative.contribution)):
				strongest_negative = row
		var parts: Array[String] = []
		if not strongest_positive.is_empty():
			parts.append("%s %+d" % [strongest_positive.input_id, strongest_positive.contribution])
		if not strongest_negative.is_empty():
			parts.append("%s %+d" % [strongest_negative.input_id, strongest_negative.contribution])
		if parts.is_empty():
			for gate in candidate.gates:
				if gate.veto: parts.append("%s %s" % [gate.gate_id, gate.reason]); break
		return " / ".join(parts) if not parts.is_empty() else "base score %s" % candidate.base_score
	return "selected candidate 누락"

func _dominant_labels(rows: Array) -> Array[String]:
	var sorted: Array = rows.duplicate(true)
	sorted.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_distance := absi(int(a.base_value) - 500); var b_distance := absi(int(b.base_value) - 500)
		return a_distance > b_distance if a_distance != b_distance else str(a.facet_id) < str(b.facet_id))
	var labels := {"boldness": "대담", "aggression": "공격", "altruism": "이타", "composure": "침착"}
	var result: Array[String] = []
	for row in sorted.slice(0, mini(2, sorted.size())): result.append(str(labels.get(row.facet_id, row.facet_id)))
	return result

func _reaction_label(reaction_id: String) -> String:
	return str({"NONE": "관찰", "ENGAGE": "교전", "PROTECT": "보호", "FLEE": "후퇴",
		"TAKE_COVER": "엄폐", "HOLD": "대기", "FREEZE": "얼어붙기"}.get(reaction_id, reaction_id))

func _mode_label(mode_id: String) -> String:
	return str({"NORMAL": "평정", "PANIC": "공황"}.get(mode_id, mode_id))

func _facet(rows: Array, id: String) -> int:
	for row in rows:
		if row.facet_id == id: return int(row.base_value)
	return -1

func _advance(count: int) -> void:
	if drawer_open: return
	var before: Dictionary = session.progress_status()
	if str(before.get("display_phase_id", before.get("phase_id", ""))) in ["RESOLVED", "COMPLETE"]: return
	ui_notice = ""
	var advance_result: Dictionary = session.advance_ticks(count)
	if not bool(advance_result.get("ok", false)):
		auto_running = false
		if auto_timer != null: auto_timer.stop()
		ui_notice = "진행 실패 · %s" % str(advance_result.get("reason", "알 수 없는 오류"))
	var after: Dictionary = session.progress_status()
	if str(after.get("display_phase_id", after.get("phase_id", ""))) in ["RESOLVED", "COMPLETE"]:
		auto_running = false
		if auto_timer != null: auto_timer.stop()
	_refresh()
func _toggle_auto() -> void:
	if drawer_open: return
	var status: Dictionary = session.progress_status()
	if str(status.get("display_phase_id", status.get("phase_id", ""))) in ["RESOLVED", "COMPLETE"]: return
	auto_running = not auto_running
	if auto_running and auto_timer.is_inside_tree(): auto_timer.start()
	else: auto_timer.stop()
	_refresh_progress()
func _pause_auto() -> void:
	auto_running = false
	if auto_timer != null: auto_timer.stop()
	_refresh_progress()
func _new_personality() -> void:
	_pause_auto()
	session.reset_lab(session.world_seed, session.personality_seed + 1)
	ui_notice = "새 성격 생성 완료 · seed %d" % session.personality_seed
	_refresh()
func _reset() -> void:
	_pause_auto()
	session.reset_lab(session.world_seed, session.personality_seed)
	ui_notice = "같은 조건으로 리셋했습니다"
	_refresh()
func _save() -> void:
	_pause_auto()
	var result: Dictionary = session.save_slot()
	ui_notice = "저장 완료" if bool(result.get("ok", false)) else "저장 실패 · %s" % str(result.get("reason", "오류"))
	_refresh()
func _load() -> void:
	_pause_auto()
	var result: Dictionary = session.load_slot()
	ui_notice = "불러오기 완료" if bool(result.get("ok", false)) else "불러오기 실패 · %s" % str(result.get("reason", "오류"))
	_refresh()
func _toggle_event_log() -> void:
	if drawer_open: return
	log_open = not log_open
	event_log.visible = log_open
	inspector.visible = not log_open
func _toggle_drawer() -> void:
	_pause_auto(); drawer_open = not drawer_open; drawer.visible = drawer_open
	event_log.visible = log_open and not drawer_open
	inspector.visible = not log_open and not drawer_open
func _on_grid_pressed(position: Vector2i) -> void:
	var observation: Dictionary = session.observe_lab()
	for cell in observation.cells:
		if cell.position == [position.x, position.y]:
			for entity in cell.entities:
				if entity.controller_kind == "LEAD": session.select_lead(int(entity.entity_id)); _refresh(); return

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _pause_auto()
