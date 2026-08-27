extends Control

const DEFAULT_SEED := 7
const DEFAULT_SPECIES := "human"
const POSITION_INVALID := Vector2i(-2147483648, -2147483648)
const UI_FONT := preload("res://assets/fonts/NanumSquareR.ttf")

const REASON_LABELS := {
	"move_requires_actor": "이동할 actor가 없음",
	"actor_not_found": "actor를 찾을 수 없음",
	"actor_dead": "사망한 actor는 행동할 수 없음",
	"move_out_of_bounds": "월드 경계 밖",
	"move_not_cardinal_adjacent": "인접한 네 방향만 이동 가능",
	"move_terrain_blocked": "통과할 수 없는 지형",
	"move_destination_occupied": "목적지가 점유됨",
	"schedule_budget_exceeded": "한 행동의 세계 처리량 한도 초과",
	"time_overflow": "세계시간 한도 도달",
}

@onready var grid_view: Control = $SafeMargin/MainColumn/GridPanel/GridView
@onready var hud_panel: PanelContainer = $SafeMargin/MainColumn/Hud
@onready var hp_label: Label = $SafeMargin/MainColumn/Hud/HudMargin/HudRows/Top/Hp
@onready var time_label: Label = $SafeMargin/MainColumn/Hud/HudMargin/HudRows/Top/Time
@onready var seed_label: Label = $SafeMargin/MainColumn/Hud/HudMargin/HudRows/Bottom/Seed
@onready var next_tick_label: Label = $SafeMargin/MainColumn/Hud/HudMargin/HudRows/Bottom/NextTick
@onready var game_over_label: Label = $SafeMargin/MainColumn/Hud/HudMargin/HudRows/GameOver
@onready var inspection_title: Label = $SafeMargin/MainColumn/Inspection/Margin/Rows/Title
@onready var traversal_label: Label = $SafeMargin/MainColumn/Inspection/Margin/Rows/Traversal
@onready var objective_label: Label = $SafeMargin/MainColumn/Inspection/Margin/Rows/Objective
@onready var evaluation_label: Label = $SafeMargin/MainColumn/Inspection/Margin/Rows/Evaluation
@onready var electric_label: Label = $SafeMargin/MainColumn/Inspection/Margin/Rows/Electric
@onready var timeline_label: Label = $SafeMargin/MainColumn/Timeline/TimelineLabel
@onready var move_button: Button = $SafeMargin/MainColumn/Actions/Move
@onready var wait_button: Button = $SafeMargin/MainColumn/Actions/Wait
@onready var ignite_button: Button = $SafeMargin/MainColumn/Actions/Ignite
@onready var water_button: Button = $SafeMargin/MainColumn/Actions/Water
@onready var discharge_button: Button = $SafeMargin/MainColumn/Actions/Discharge
@onready var recent_panel: PanelContainer = $SafeMargin/MainColumn/Recent
@onready var recent_summary: Label = $SafeMargin/MainColumn/Recent/Margin/Rows/Summary
@onready var recent_event: Label = $SafeMargin/MainColumn/Recent/Margin/Rows/Event
@onready var input_shield: Control = $InputShield
@onready var drawer: PanelContainer = $Drawer
@onready var drawer_log: TextEdit = $Drawer/Margin/Rows/LogText
@onready var menu_sheet: PanelContainer = $MenuSheet
@onready var menu_seed: SpinBox = $MenuSheet/Margin/Rows/SeedRow/SeedValue
@onready var menu_status: Label = $MenuSheet/Margin/Rows/Status

var _session: Variant = null
var _selected_position := POSITION_INVALID
var _player_position := POSITION_INVALID
var _current_species := DEFAULT_SPECIES
var _current_seed := DEFAULT_SEED
var _last_assessment: Dictionary = {}
var _last_actual_timeline: Array = []
var _last_action_label := "행동"
var _last_feedback_text := ""
var _drawer_open := false
var _menu_open := false
var _headless_test_initialized := false
var _pending_species := ""


func _ready() -> void:
	if _headless_test_initialized:
		return
	_apply_theme()
	_connect_controls()
	resized.connect(_on_viewport_resized)
	_create_default_session()
	_on_viewport_resized()
	refresh_from_session()


func initialize_for_headless_test() -> void:
	if is_node_ready() or _headless_test_initialized:
		return
	grid_view = get_node("SafeMargin/MainColumn/GridPanel/GridView")
	hud_panel = get_node("SafeMargin/MainColumn/Hud")
	hp_label = get_node("SafeMargin/MainColumn/Hud/HudMargin/HudRows/Top/Hp")
	time_label = get_node("SafeMargin/MainColumn/Hud/HudMargin/HudRows/Top/Time")
	seed_label = get_node("SafeMargin/MainColumn/Hud/HudMargin/HudRows/Bottom/Seed")
	next_tick_label = get_node("SafeMargin/MainColumn/Hud/HudMargin/HudRows/Bottom/NextTick")
	game_over_label = get_node("SafeMargin/MainColumn/Hud/HudMargin/HudRows/GameOver")
	inspection_title = get_node("SafeMargin/MainColumn/Inspection/Margin/Rows/Title")
	traversal_label = get_node("SafeMargin/MainColumn/Inspection/Margin/Rows/Traversal")
	objective_label = get_node("SafeMargin/MainColumn/Inspection/Margin/Rows/Objective")
	evaluation_label = get_node("SafeMargin/MainColumn/Inspection/Margin/Rows/Evaluation")
	electric_label = get_node("SafeMargin/MainColumn/Inspection/Margin/Rows/Electric")
	timeline_label = get_node("SafeMargin/MainColumn/Timeline/TimelineLabel")
	move_button = get_node("SafeMargin/MainColumn/Actions/Move")
	wait_button = get_node("SafeMargin/MainColumn/Actions/Wait")
	ignite_button = get_node("SafeMargin/MainColumn/Actions/Ignite")
	water_button = get_node("SafeMargin/MainColumn/Actions/Water")
	discharge_button = get_node("SafeMargin/MainColumn/Actions/Discharge")
	recent_panel = get_node("SafeMargin/MainColumn/Recent")
	recent_summary = get_node("SafeMargin/MainColumn/Recent/Margin/Rows/Summary")
	recent_event = get_node("SafeMargin/MainColumn/Recent/Margin/Rows/Event")
	input_shield = get_node("InputShield")
	drawer = get_node("Drawer")
	drawer_log = get_node("Drawer/Margin/Rows/LogText")
	menu_sheet = get_node("MenuSheet")
	menu_seed = get_node("MenuSheet/Margin/Rows/SeedRow/SeedValue")
	menu_status = get_node("MenuSheet/Margin/Rows/Status")
	_headless_test_initialized = true
	_apply_theme()
	_connect_controls()
	_create_default_session()
	_on_viewport_resized()
	refresh_from_session()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if _menu_open:
			set_menu_open(false)
		elif _drawer_open:
			set_drawer_open(false)
		return
	if event.keycode == KEY_L:
		set_drawer_open(not _drawer_open)
		_mark_input_handled()
		return
	if _menu_open or _drawer_open or _session == null:
		return
	var direction := Vector2i.ZERO
	match event.keycode:
		KEY_LEFT, KEY_A:
			direction = Vector2i.LEFT
		KEY_RIGHT, KEY_D:
			direction = Vector2i.RIGHT
		KEY_UP, KEY_W:
			direction = Vector2i.UP
		KEY_DOWN, KEY_S:
			direction = Vector2i.DOWN
	if direction != Vector2i.ZERO:
		_submit_move(_player_position + direction)
		_mark_input_handled()
		return
	match event.keycode:
		KEY_SPACE, KEY_PERIOD:
			_submit_command("commit_wait")
		KEY_1:
			_submit_at_selection("commit_ignite")
		KEY_2:
			_submit_at_selection("commit_water")
		KEY_3:
			_submit_at_selection("commit_discharge")
		_:
			return
	_mark_input_handled()


func set_session_for_test(session: Variant) -> void:
	_session = session
	_selected_position = POSITION_INVALID
	refresh_from_session()


func selected_position() -> Vector2i:
	return _selected_position


func select_world_position(position: Vector2i) -> void:
	_on_grid_world_cell_pressed(position)


func refresh_from_session() -> void:
	if not is_node_ready() and not _headless_test_initialized:
		return
	if _session == null:
		_show_session_unavailable()
		return
	var player := _dictionary_from(_session_call("player_state"))
	var status := _dictionary_from(_session_call("world_status"))
	_player_position = _position_from(player.get("position", player.get("world_position", null)))
	if _player_position == POSITION_INVALID:
		_player_position = Vector2i.ZERO
	if _selected_position == POSITION_INVALID:
		_selected_position = _player_position
	_current_seed = int(status.get("seed", player.get("seed", _current_seed)))
	_current_species = str(player.get("species_id", status.get("species_id", _current_species))).to_lower()
	menu_seed.value = _current_seed
	_update_hud(player, status)
	var cells_value: Variant = _session_call("view_visible_cells", [4])
	var cells: Array = cells_value if cells_value is Array else []
	cells = _decorate_visible_cells(cells)
	grid_view.call("set_view", cells, _player_position, _selected_position)
	grid_view.call("set_player_position", _player_position)
	_update_inspection(player)
	_update_recent()
	_update_action_state(player)
	if _drawer_open:
		_refresh_drawer()


func set_drawer_open(open: bool) -> void:
	_drawer_open = open
	drawer.visible = open
	if open:
		_menu_open = false
		menu_sheet.visible = false
		_refresh_drawer()
	$SafeMargin/MainColumn/Recent/Margin/Rows/DrawerButton.text = "로그 접기" if open else "로그 펼치기"
	_update_input_shield()


func set_menu_open(open: bool) -> void:
	_menu_open = open
	menu_sheet.visible = open
	if open:
		_drawer_open = false
		drawer.visible = false
		menu_status.text = ""
	_update_input_shield()


func _create_default_session() -> void:
	if not ResourceLoader.exists("res://playtest/playtest_session.gd"):
		return
	var session_script = load("res://playtest/playtest_session.gd")
	if session_script == null or not session_script.can_instantiate():
		return
	_session = session_script.new()
	if _session_has_method("reset"):
		_session.call("reset", DEFAULT_SEED, DEFAULT_SPECIES)


func _connect_controls() -> void:
	grid_view.connect("world_cell_pressed", _on_grid_world_cell_pressed)
	$SafeMargin/MainColumn/Hud/HudMargin/HudRows/Bottom/MenuButton.pressed.connect(func(): set_menu_open(true))
	move_button.pressed.connect(func(): _submit_move(_selected_position))
	wait_button.pressed.connect(func(): _submit_command("commit_wait"))
	ignite_button.pressed.connect(func(): _submit_at_selection("commit_ignite"))
	water_button.pressed.connect(func(): _submit_at_selection("commit_water"))
	discharge_button.pressed.connect(func(): _submit_at_selection("commit_discharge"))
	$SafeMargin/MainColumn/Recent/Margin/Rows/DrawerButton.pressed.connect(func(): set_drawer_open(not _drawer_open))
	$Drawer/Margin/Rows/Header/Close.pressed.connect(func(): set_drawer_open(false))
	$Drawer/Margin/Rows/CopyReplay.pressed.connect(_copy_replay)
	$MenuSheet/Margin/Rows/Species/Human.pressed.connect(func(): _request_species_reset("human"))
	$MenuSheet/Margin/Rows/Species/Amphibian.pressed.connect(func(): _request_species_reset("amphibian"))
	$MenuSheet/Margin/Rows/Species/Dwarf.pressed.connect(func(): _request_species_reset("dwarf"))
	$MenuSheet/Margin/Rows/ResetRow/Reset.pressed.connect(func(): _reset_session(int(menu_seed.value), _current_species))
	$MenuSheet/Margin/Rows/ResetRow/NewSeed.pressed.connect(_new_seed)
	$MenuSheet/Margin/Rows/SlotRow/Save.pressed.connect(_save_slot)
	$MenuSheet/Margin/Rows/SlotRow/Load.pressed.connect(_load_slot)
	$MenuSheet/Margin/Rows/CopySnapshot.pressed.connect(_copy_snapshot)
	$MenuSheet/Margin/Rows/Close.pressed.connect(func(): set_menu_open(false))
	$ResetConfirmation.confirmed.connect(_confirm_species_reset)


func _on_grid_world_cell_pressed(position: Vector2i) -> void:
	if _menu_open or _drawer_open or _session == null:
		return
	var was_selected := _selected_position == position
	_selected_position = position
	if was_selected and _is_cardinal_neighbor(position) and _assessment_accepts(position):
		_submit_move(position)
		return
	refresh_from_session()


func _submit_move(position: Vector2i) -> void:
	if _session == null or position == POSITION_INVALID:
		return
	_selected_position = position
	_submit_command("commit_move", [position])


func _submit_at_selection(method: String) -> void:
	if _selected_position == POSITION_INVALID:
		return
	_submit_command(method, [_selected_position])


func _submit_command(method: String, arguments: Array = []) -> void:
	if _menu_open or _drawer_open or not _session_has_method(method):
		return
	var before_player := _dictionary_from(_session_call("player_state"))
	_last_action_label = _action_label(method)
	var result = _session.callv(method, arguments)
	_last_actual_timeline = _array_field(result, "timeline")
	refresh_from_session()
	_show_result_feedback(result, method, before_player)


func _update_hud(player: Dictionary, status: Dictionary) -> void:
	var hp := int(player.get("hp", player.get("current_hp", 0)))
	var max_hp := int(player.get("max_hp", player.get("hp_max", max(hp, 1))))
	var species_display := str(player.get("species_display_name", _current_species)).to_upper()
	hp_label.text = "HP %d/%d  %s" % [hp, max_hp, species_display]
	var world_time := int(status.get("world_time", player.get("world_time", 0)))
	var step_index := int(status.get("step_index", player.get("step_index", 0)))
	var calendar: Dictionary = status.get("calendar", status.get("calendar_projection", {}))
	var day := int(calendar.get("day", calendar.get("day_index", 0))) + (0 if calendar.has("day") else 1)
	var hour := int(calendar.get("hour", calendar.get("hour_of_day", 0)))
	var minute := int(calendar.get("minute", calendar.get("minute_of_hour", 0)))
	time_label.text = "D%d %02d:%02d  T%d S%d" % [day, hour, minute, world_time, step_index]
	seed_label.text = "Seed %04d  DEBUG OMNI" % _current_seed
	var next_tick := int(status.get("next_environment_time", status.get("next_environment_tick", 0)))
	next_tick_label.text = "다음 환경 T%d" % next_tick
	var alive := bool(player.get("alive", hp > 0))
	game_over_label.visible = not alive
	if not alive:
		hud_panel.modulate = Color("#d37474")
	elif max_hp > 0 and hp * 100 <= max_hp * 15:
		hud_panel.modulate = Color("#ef6972")
	elif max_hp > 0 and hp * 100 <= max_hp * 30:
		hud_panel.modulate = Color("#e5ad62")
	else:
		hud_panel.modulate = Color.WHITE


func _update_inspection(player: Dictionary) -> void:
	_last_assessment = _dictionary_from(_session_call("inspect_destination", [_selected_position]))
	if _last_assessment.is_empty():
		inspection_title.text = "(%d,%d) 검사 정보 없음" % [_selected_position.x, _selected_position.y]
		traversal_label.text = "이동 평가 없음"
		objective_label.text = "객관 DTO 없음"
		evaluation_label.text = "평가 DTO 없음"
		electric_label.text = "전도/전기위험 DTO 없음"
		timeline_label.text = "예상 불가: destination DTO 없음"
		return
	var traversal := _dictionary_from(_last_assessment.get("traversal", {}))
	var sample := _dictionary_from(_last_assessment.get("sample", {}))
	var evaluation := _dictionary_from(_last_assessment.get("evaluation", {}))
	var terrain := str(sample.get("terrain_id", traversal.get("terrain_id", "unknown"))).to_upper()
	inspection_title.text = "(%d,%d) %s" % [_selected_position.x, _selected_position.y, terrain]
	var accepted := bool(traversal.get("accepted", false))
	var reason := str(traversal.get("reason", ""))
	var move_cost := int(_last_assessment.get("move_time_cost", sample.get("move_time_cost", 0)))
	var speed := str(_last_assessment.get("speed_tier", ""))
	if _selected_position == _player_position:
		traversal_label.text = "현재 위치 · 이동 명령 없음"
	elif accepted:
		traversal_label.text = "이동 가능 · %d · %s" % [move_cost, speed]
	else:
		traversal_label.text = "이동 불가 · %s" % _reason_label(reason)
	objective_label.text = "객관  불 %d  다음틱피해 %d  물 %d  젖음 %d" % [
		int(sample.get("fire_intensity", 0)),
		int(sample.get("known_fire_damage_at_next_tick", 0)),
		int(sample.get("terrain_water_exposure", 0)),
		int(sample.get("wetness", 0)),
	]
	evaluation_label.text = "평가  불 %d  물 %d  총 위험 %d" % [
		int(evaluation.get("fire_score", 0)),
		int(evaluation.get("water_score", 0)),
		int(evaluation.get("total_risk", 0)),
	]
	var electric_risk := int(sample.get("electric_risk", 0))
	var electric_text := "없음" if electric_risk == 0 else "%d/%s" % [electric_risk, str(sample.get("electric_certainty", ""))]
	electric_label.text = "객관  전도 %d  전기위험 %s  독 %d · 평가 전기 %d 독 %d" % [
		int(sample.get("conductivity", 0)), electric_text,
		int(sample.get("poison_intensity", 0)),
		int(evaluation.get("electric_score", 0)),
		int(evaluation.get("poison_score", 0)),
	]
	_update_preview(accepted, reason)


func _update_preview(accepted: bool, reason: String) -> void:
	if not _is_cardinal_neighbor(_selected_position):
		timeline_label.text = "예상: 인접한 네 방향 칸을 선택하세요"
		return
	var preview = _session_call("preview_move", [_selected_position])
	if preview == null:
		timeline_label.text = "예상 불가: preview DTO 없음"
		return
	var preview_accepted := bool(_field(preview, "accepted", accepted))
	var preview_reason := str(_field(preview, "reason", reason))
	if not preview_accepted:
		timeline_label.text = "예상 불가: %s" % _reason_label(preview_reason)
		return
	var timeline := _array_field(preview, "timeline")
	timeline_label.text = "예상: %s" % _format_timeline(timeline, "이동")


func _update_action_state(player: Dictionary) -> void:
	var alive := bool(player.get("alive", int(player.get("hp", 0)) > 0))
	var selected_valid := _selected_position != POSITION_INVALID and not _last_assessment.is_empty()
	move_button.disabled = not alive or not selected_valid or not _is_cardinal_neighbor(_selected_position) or not _assessment_accepts(_selected_position)
	wait_button.disabled = not alive
	ignite_button.disabled = not alive or not selected_valid
	water_button.disabled = not alive or not selected_valid
	discharge_button.disabled = not alive or not selected_valid


func _update_recent() -> void:
	if not _last_feedback_text.is_empty():
		recent_summary.text = _last_feedback_text
		_update_recent_event_only()
		return
	var summary := _dictionary_from(_session_call("last_result_summary"))
	if bool(summary.get("available", false)):
		recent_summary.text = str(summary.get("text", summary.get("summary", _summary_from_fields(summary))))
	elif not summary.is_empty():
		recent_summary.text = "최근: %s" % str(summary.get("reason", "명령 없음"))
	_update_recent_event_only()


func _update_recent_event_only() -> void:
	var events_value: Variant = _session_call("recent_events", [2])
	if events_value is Array and not events_value.is_empty():
		recent_event.text = _format_event(events_value[-1])
	else:
		recent_event.text = "사건 없음"


func _show_result_feedback(result: Variant, method: String, before_player: Dictionary) -> void:
	if result == null:
		_last_feedback_text = "거부 · session 결과 없음"
		recent_summary.text = _last_feedback_text
		return
	var accepted := bool(_field(result, "accepted", false))
	var reason := str(_field(result, "reason", ""))
	if accepted:
		var start_time := int(_field(result, "start_time", 0))
		var end_time := int(_field(result, "end_time", start_time))
		var time_cost := int(_field(result, "time_cost", end_time - start_time))
		var environment_count := 0
		for marker in _last_actual_timeline:
			if str(_dictionary_from(marker).get("kind", "")).contains("environment"):
				environment_count += 1
		if method == "commit_move":
			var from_position := _position_from(before_player.get("position", null))
			_last_feedback_text = "이동 (%d,%d)→(%d,%d) · +%d · T%d→%d · 환경틱 %d회" % [
				from_position.x, from_position.y, _player_position.x, _player_position.y,
				time_cost, start_time, end_time, environment_count,
			]
		else:
			_last_feedback_text = "%s 정착 · +%d · T%d→%d · 환경틱 %d회" % [
				_action_label(method), time_cost, start_time, end_time, environment_count,
			]
		var after_player := _dictionary_from(_session_call("player_state"))
		if not bool(after_player.get("alive", true)):
			_last_feedback_text += " · PLAYER 사망"
		recent_summary.text = _last_feedback_text
		if not _last_actual_timeline.is_empty():
			timeline_label.text = "실제: %s" % _format_timeline(_last_actual_timeline, _last_action_label)
	else:
		_last_feedback_text = "거부 · %s · 시간/step 변화 없음" % _reason_label(reason)
		recent_summary.text = _last_feedback_text


func _refresh_drawer() -> void:
	if _session == null:
		drawer_log.text = "PlaytestSession을 불러올 수 없습니다."
		return
	var lines: Array[String] = ["EVENTS"]
	var events_value: Variant = _session_call("recent_events", [40])
	if events_value is Array:
		for event in events_value:
			lines.append(_format_event(event))
	lines.append("")
	lines.append("TIMELINE")
	lines.append(_format_timeline(_last_actual_timeline, _last_action_label) if not _last_actual_timeline.is_empty() else "실제 timeline 없음")
	lines.append("")
	lines.append("REPLAY")
	lines.append("seed=%d species=%s" % [_current_seed, _current_species])
	lines.append(str(_session_call("command_journal_json")))
	drawer_log.text = "\n".join(lines)


func _reset_session(seed: int, species_id: String) -> void:
	if not _session_has_method("reset"):
		menu_status.text = "RESET 실패 · session API 없음"
		return
	var ok := bool(_session.call("reset", seed, species_id))
	if ok:
		_current_seed = seed
		_current_species = species_id
		_selected_position = POSITION_INVALID
		_last_actual_timeline.clear()
		_last_feedback_text = ""
		menu_status.text = "RESET 완료 · Seed %d · %s" % [seed, species_id.to_upper()]
	else:
		menu_status.text = "RESET 실패"
	refresh_from_session()


func _request_species_reset(species_id: String) -> void:
	var status := _dictionary_from(_session_call("world_status"))
	if int(status.get("command_count", 0)) <= 0:
		_reset_session(_current_seed, species_id)
		return
	_pending_species = species_id
	$ResetConfirmation.popup_centered(Vector2i(390, 190))


func _confirm_species_reset() -> void:
	if _pending_species.is_empty():
		return
	var species_id := _pending_species
	_pending_species = ""
	_reset_session(_current_seed, species_id)


func _new_seed() -> void:
	var new_seed := int(Time.get_unix_time_from_system()) & 0x7fffffff
	menu_seed.value = new_seed
	_reset_session(new_seed, _current_species)


func _save_slot() -> void:
	var response := _dictionary_from(_session_call("save_slot"))
	var ok := bool(response.get("ok", false))
	menu_status.text = "SAVE 완료" if ok else "SAVE 실패 · %s" % str(response.get("reason", "unknown"))
	recent_summary.text = menu_status.text


func _load_slot() -> void:
	var response := _dictionary_from(_session_call("load_slot"))
	var ok := bool(response.get("ok", false))
	menu_status.text = "LOAD 완료" if ok else "LOAD 실패 · %s" % str(response.get("reason", "유효한 v3 snapshot 없음"))
	recent_summary.text = menu_status.text
	if ok:
		_selected_position = POSITION_INVALID
		_last_actual_timeline.clear()
		_last_feedback_text = menu_status.text
		refresh_from_session()


func _copy_snapshot() -> void:
	var text := str(_session_call("snapshot_json"))
	if text.is_empty():
		menu_status.text = "SNAPSHOT 복사 실패"
		return
	DisplayServer.clipboard_set(text)
	menu_status.text = "SNAPSHOT JSON 복사 완료"


func _copy_replay() -> void:
	var text := str(_session_call("command_journal_json"))
	if text.is_empty():
		return
	DisplayServer.clipboard_set(text)
	recent_summary.text = "accepted command journal 복사 완료"


func _format_timeline(timeline: Array, action_label: String = "행동") -> String:
	if timeline.is_empty():
		return "marker 없음"
	var parts: Array[String] = []
	for raw_marker in timeline:
		var marker := _dictionary_from(raw_marker)
		var kind := str(marker.get("kind", marker.get("type", "marker")))
		var time := int(marker.get("world_time", marker.get("time", marker.get("at_time", 0))))
		var label := _marker_label(kind, action_label)
		var event_ids: Array = marker.get("event_ids", [])
		if not event_ids.is_empty():
			label += "[%s]" % ",".join(event_ids.map(func(value): return "#%s" % str(value)))
		parts.append("%s@%d" % [label, time])
	return " → ".join(parts)


func _marker_label(kind: String, action_label: String) -> String:
	if kind.contains("environment"):
		return "환경"
	if kind.contains("ready"):
		return "준비"
	if kind.contains("move") or kind.contains("action") or kind == "commit":
		return action_label
	return kind


func _action_label(method: String) -> String:
	match method:
		"commit_move":
			return "이동"
		"commit_wait":
			return "대기"
		"commit_ignite":
			return "불"
		"commit_water":
			return "물"
		"commit_discharge":
			return "방전"
	return "행동"


func _format_event(value: Variant) -> String:
	var event := _dictionary_from(value)
	if event.is_empty() and value is Object:
		event = {
			"event_id": _field(value, "event_id", -1),
			"world_time": _field(value, "world_time", 0),
			"type": _field(value, "type", "unknown"),
			"actor_id": _field(value, "actor_id", -1),
			"target_id": _field(value, "target_id", -1),
			"magnitude": _field(value, "magnitude", 0),
			"cause_event_id": _field(value, "cause_event_id", -1),
		}
	var extras: Array[String] = []
	for key in ["actor_id", "target_id", "magnitude", "cause_event_id"]:
		var field_value := int(event.get(key, -1 if key != "magnitude" else 0))
		if (key == "magnitude" and field_value != 0) or (key != "magnitude" and field_value >= 0):
			extras.append("%s=%d" % [key.trim_suffix("_id"), field_value])
	return "#%s T%s %s %s" % [
		str(event.get("event_id", "?")),
		str(event.get("world_time", "?")),
		str(event.get("type", "unknown")),
		" ".join(extras),
	]


func _summary_from_fields(summary: Dictionary) -> String:
	if bool(summary.get("accepted", false)):
		return "최근 명령 정착 · +%d" % int(summary.get("time_cost", 0))
	return "거부 · %s" % _reason_label(str(summary.get("reason", "unknown")))


func _assessment_accepts(position: Vector2i) -> bool:
	if position != _selected_position or _last_assessment.is_empty():
		return false
	var traversal := _dictionary_from(_last_assessment.get("traversal", {}))
	return bool(traversal.get("accepted", false))


func _decorate_visible_cells(cells: Array) -> Array:
	var decorated := cells.duplicate(true)
	var current_risk := 0
	var current_assessment := _dictionary_from(_session_call("inspect_destination", [_player_position]))
	if not current_assessment.is_empty():
		current_risk = int(_dictionary_from(current_assessment.get("evaluation", {})).get("total_risk", 0))
	for index in range(decorated.size()):
		if not decorated[index] is Dictionary:
			continue
		var row: Dictionary = decorated[index]
		var position := _position_from(row.get("position", null))
		if not _is_cardinal_neighbor(position):
			continue
		var assessment := _dictionary_from(_session_call("inspect_destination", [position]))
		var traversal := _dictionary_from(assessment.get("traversal", {}))
		if not bool(traversal.get("accepted", false)):
			row["traversal_hint"] = "blocked"
		else:
			var risk := int(_dictionary_from(assessment.get("evaluation", {})).get("total_risk", 0))
			row["traversal_hint"] = "risky" if risk > current_risk else "passable"
		decorated[index] = row
	return decorated


func _is_cardinal_neighbor(position: Vector2i) -> bool:
	if _player_position == POSITION_INVALID:
		return false
	var delta := position - _player_position
	return absi(delta.x) + absi(delta.y) == 1


func _session_call(method: String, arguments: Array = []) -> Variant:
	if not _session_has_method(method):
		return null
	return _session.callv(method, arguments)


func _session_has_method(method: String) -> bool:
	return _session != null and _session is Object and _session.has_method(method)


func _dictionary_from(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	if value is Object and value.has_method("to_dict"):
		var result = value.call("to_dict")
		if result is Dictionary:
			return result.duplicate(true)
	return {}


func _field(value: Variant, key: String, default_value: Variant) -> Variant:
	if value is Dictionary:
		return value.get(key, default_value)
	if value is Object:
		for property in value.get_property_list():
			if str(property.name) == key:
				return value.get(key)
	return default_value


func _array_field(value: Variant, key: String) -> Array:
	var field_value = _field(value, key, [])
	return field_value.duplicate(true) if field_value is Array else []


func _position_from(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Dictionary and value.has("x") and value.has("y"):
		return Vector2i(int(value.x), int(value.y))
	return POSITION_INVALID


func _reason_label(reason: String) -> String:
	if reason.is_empty():
		return "알 수 없는 이유"
	return str(REASON_LABELS.get(reason, reason))


func _show_session_unavailable() -> void:
	hp_label.text = "HP --/--  SESSION OFFLINE"
	time_label.text = "T-- S--"
	inspection_title.text = "PlaytestSession 준비 중"
	traversal_label.text = "UI는 world를 직접 읽지 않습니다"
	objective_label.text = "session DTO 연결 후 표시됩니다"
	evaluation_label.text = ""
	electric_label.text = ""
	timeline_label.text = "예상 불가: session 없음"
	recent_summary.text = "최근: PlaytestSession을 불러올 수 없음"
	for button in [move_button, wait_button, ignite_button, water_button, discharge_button]:
		button.disabled = true


func _update_input_shield() -> void:
	input_shield.visible = _drawer_open or _menu_open
	input_shield.mouse_filter = Control.MOUSE_FILTER_STOP if input_shield.visible else Control.MOUSE_FILTER_IGNORE
	if _drawer_open:
		drawer.move_to_front()
	elif _menu_open:
		menu_sheet.move_to_front()


func _on_viewport_resized() -> void:
	if not is_node_ready() and not _headless_test_initialized:
		return
	var compact := size.y < 720.0
	recent_panel.custom_minimum_size.y = 48.0 if compact else 72.0
	$SafeMargin/MainColumn/Recent/Margin/Rows/Event.visible = not compact
	grid_view.queue_redraw()


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _apply_theme() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font = UI_FONT
	ui_theme.default_font_size = 13
	ui_theme.set_color("font_color", "Label", Color("#f2f5f8"))
	ui_theme.set_color("font_color", "Button", Color("#f7f9fb"))
	ui_theme.set_color("font_disabled_color", "Button", Color("#818995"))
	ui_theme.set_color("font_color", "TextEdit", Color("#e8edf2"))
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#121a25")
	panel_style.border_color = Color("#2d4155")
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	ui_theme.set_stylebox("panel", "PanelContainer", panel_style)
	var button_style := StyleBoxFlat.new()
	button_style.bg_color = Color("#27384a")
	button_style.border_color = Color("#49647c")
	button_style.set_border_width_all(1)
	button_style.corner_radius_top_left = 4
	button_style.corner_radius_top_right = 4
	button_style.corner_radius_bottom_left = 4
	button_style.corner_radius_bottom_right = 4
	ui_theme.set_stylebox("normal", "Button", button_style)
	var hover_style := button_style.duplicate()
	hover_style.bg_color = Color("#36516a")
	ui_theme.set_stylebox("hover", "Button", hover_style)
	var pressed_style := button_style.duplicate()
	pressed_style.bg_color = Color("#172330")
	ui_theme.set_stylebox("pressed", "Button", pressed_style)
	var disabled_style := button_style.duplicate()
	disabled_style.bg_color = Color("#1a2029")
	disabled_style.border_color = Color("#303945")
	ui_theme.set_stylebox("disabled", "Button", disabled_style)
	theme = ui_theme
