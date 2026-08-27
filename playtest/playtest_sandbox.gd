class_name PersonalityLabSandbox
extends Control

const SessionScript = preload("res://playtest/playtest_session.gd")
const GridScript = preload("res://playtest/playtest_grid_view.gd")
const KoreanUIFont: FontFile = preload("res://assets/fonts/NanumSquareR.ttf")

var session
var grid
var summaries: GridContainer
var inspector: RichTextLabel
var event_log: RichTextLabel
var drawer: RichTextLabel
var auto_timer: Timer
var auto_running := false
var drawer_open := false
var log_open := false

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
	var title := Label.new(); title.name = "Title"; title.text = "DEBUG LAB · CONTROLLED STIMULUS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 16); root.add_child(title)
	summaries = GridContainer.new(); summaries.name = "LeadSummaries"; summaries.columns = 2; summaries.custom_minimum_size.y = 62; root.add_child(summaries)
	grid = GridScript.new(); grid.name = "LabGrid"; grid.custom_minimum_size = Vector2(320, 320)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL; grid.world_cell_pressed.connect(_on_grid_pressed); root.add_child(grid)
	inspector = RichTextLabel.new(); inspector.name = "ReactionInspector"; inspector.fit_content = false
	inspector.custom_minimum_size.y = 116; inspector.scroll_active = true; inspector.bbcode_enabled = true; root.add_child(inspector)
	var controls := GridContainer.new(); controls.name = "Controls"; controls.columns = 5; root.add_child(controls)
	_add_button(controls, "다음 tick", func(): _advance(1))
	_add_button(controls, "▶/⏸", _toggle_auto)
	_add_button(controls, "+10 tick", func(): _advance(10))
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
	auto_timer = Timer.new(); auto_timer.name = "AutoTimer"; auto_timer.wait_time = 0.4; auto_timer.timeout.connect(func():
		if auto_running and session != null: _advance(1)); add_child(auto_timer)
	var viewport := get_viewport()
	if viewport != null and not viewport.focus_exited.is_connected(_pause_auto):
		viewport.focus_exited.connect(_pause_auto)

func _add_button(parent: Control, text_value: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text_value; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback); parent.add_child(button); return button

func _refresh() -> void:
	if session == null or grid == null: return
	var observation: Dictionary = session.observe_lab()
	grid.set_view(observation.get("cells", []), Vector2i(7, 7), null)
	for child in summaries.get_children(): child.queue_free()
	for row in session.lead_roster():
		var button := Button.new(); button.name = "Lead%d" % (int(row.trial_slot) + 1)
		button.clip_text = true
		button.text = "#%d %s · F%d · %s · %s" % [int(row.trial_slot) + 1, str(row.mental_mode),
			int(row.fear), str(row.reaction), "/".join(_dominant_labels(row.personality))]
		button.pressed.connect(func(): session.select_lead(int(row.entity_id)); _refresh())
		summaries.add_child(button)
	var detail: Dictionary = session.inspect_reaction(session.selected_lead_id)
	inspector.text = _inspector_text(detail)
	event_log.text = _event_log_text(session.recent_event_log(24))
	drawer.text = _drawer_text(detail)
	grid.selected_trial_slot = int(detail.get("identity", {}).get("trial_slot", -1))
	grid.queue_redraw()

func _event_log_text(rows: Array[Dictionary]) -> String:
	var status: Dictionary = session.lab_status() if session != null else {}
	var lines: Array[String] = ["[b]최근 세계 사건[/b] · T%s · %s" % [
		str(status.get("world_time", 0)), str(status.get("phase", "?"))]]
	if rows.is_empty():
		lines.append("아직 사건이 없습니다. ‘다음 tick’을 눌러 조우를 시작하세요.")
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
		detail.emotion.fear, detail.emotion.anger, detail.emotion.mental_mode,
		int(a.get("objective_danger",0)), int(a.get("perceived_threat",0)), " · ".join(scores),
		_committed_basis(actual_trace), " · ".join(live_gates),
		detail.selected_reaction, detail.target_position[0], detail.target_position[1]]

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

func _facet(rows: Array, id: String) -> int:
	for row in rows:
		if row.facet_id == id: return int(row.base_value)
	return -1

func _advance(count: int) -> void:
	if drawer_open: return
	session.advance_ticks(count); _refresh()
func _toggle_auto() -> void:
	if drawer_open: return
	auto_running = not auto_running
	if auto_running: auto_timer.start()
	else: auto_timer.stop()
func _pause_auto() -> void:
	auto_running = false
	if auto_timer != null: auto_timer.stop()
func _new_personality() -> void:
	_pause_auto(); session.reset_lab(session.world_seed, session.personality_seed + 1); _refresh()
func _reset() -> void:
	_pause_auto(); session.reset_lab(session.world_seed, session.personality_seed); _refresh()
func _save() -> void:
	_pause_auto(); session.save_slot(); _refresh()
func _load() -> void:
	_pause_auto(); session.load_slot(); _refresh()
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
