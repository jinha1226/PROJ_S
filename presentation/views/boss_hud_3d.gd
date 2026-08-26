class_name BossHUD3D
extends Control

signal move_changed(direction: Vector2)
signal dodge_pressed
signal parry_pressed
signal target_pressed(screen_position: Vector2)
signal restart_pressed

const INK := Color("111823")
const PAPER := Color("e7edf0")
const TEAL := Color("53d9be")
const AMBER := Color("f4a955")
const RED := Color("d95f5b")

var player_health: float = 100.0
var player_stamina: float = 100.0
var boss_health: float = 100.0
var target_name: String = "CORE"
var feedback_text: String = ""
var feedback_alpha: float = 0.0
var tutorial_alpha: float = 1.0
var battle_over: bool = false
var victory: bool = false
var battle_time: float = 0.0
var dodge_ready: bool = true
var parry_ready: bool = true
var parry_flash: float = 0.0

var _joystick_center := Vector2.ZERO
var _dodge_center := Vector2.ZERO
var _parry_center := Vector2.ZERO
var _joystick_radius: float = 82.0
var _dodge_radius: float = 65.0
var _parry_radius: float = 48.0
var _move_touch_index: int = -1
var _move_vector := Vector2.ZERO
var _mouse_move_active: bool = false
var _last_touch_msec: int = -10000


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func _process(_delta: float) -> void:
	_update_layout()
	queue_redraw()


func set_battle_data(data: Dictionary) -> void:
	player_health = float(data.get("player_health", player_health))
	player_stamina = float(data.get("player_stamina", player_stamina))
	boss_health = float(data.get("boss_health", boss_health))
	target_name = str(data.get("target_name", target_name))
	feedback_text = str(data.get("feedback_text", feedback_text))
	feedback_alpha = float(data.get("feedback_alpha", feedback_alpha))
	tutorial_alpha = float(data.get("tutorial_alpha", tutorial_alpha))
	battle_over = bool(data.get("battle_over", battle_over))
	victory = bool(data.get("victory", victory))
	battle_time = float(data.get("battle_time", battle_time))
	dodge_ready = bool(data.get("dodge_ready", dodge_ready))
	parry_ready = bool(data.get("parry_ready", parry_ready))
	parry_flash = float(data.get("parry_flash", parry_flash))


func _update_layout() -> void:
	_joystick_center = Vector2(138.0, size.y - 142.0)
	_dodge_center = Vector2(size.x - 118.0, size.y - 137.0)
	_parry_center = Vector2(size.x - 226.0, size.y - 218.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_last_touch_msec = Time.get_ticks_msec()
		_handle_touch(event)
		accept_event()
		return
	if event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if event.index == _move_touch_index:
			_update_move(event.position)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 400:
			accept_event()
			return
		if event.pressed:
			_handle_pointer_press(event.position)
		else:
			_mouse_move_active = false
			_set_move(Vector2.ZERO)
		accept_event()
		return
	if event is InputEventMouseMotion and _mouse_move_active:
		_update_move(event.position)
		accept_event()


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if battle_over:
			restart_pressed.emit()
			return
		if event.position.distance_to(_dodge_center) <= _dodge_radius * 1.28:
			dodge_pressed.emit()
			return
		if event.position.distance_to(_parry_center) <= _parry_radius * 1.35:
			parry_pressed.emit()
			return
		if event.position.x < size.x * 0.58 and event.position.y > size.y * 0.52 and _move_touch_index < 0:
			_move_touch_index = event.index
			_update_move(event.position)
			return
		target_pressed.emit(event.position)
	elif event.index == _move_touch_index:
		_move_touch_index = -1
		_set_move(Vector2.ZERO)


func _handle_pointer_press(position: Vector2) -> void:
	if battle_over:
		restart_pressed.emit()
		return
	if position.distance_to(_dodge_center) <= _dodge_radius * 1.28:
		dodge_pressed.emit()
		return
	if position.distance_to(_parry_center) <= _parry_radius * 1.35:
		parry_pressed.emit()
		return
	if position.x < size.x * 0.58 and position.y > size.y * 0.52:
		_mouse_move_active = true
		_update_move(position)
		return
	target_pressed.emit(position)


func _update_move(position: Vector2) -> void:
	var raw := (position - _joystick_center) / _joystick_radius
	_set_move(raw.limit_length(1.0))


func _set_move(direction: Vector2) -> void:
	_move_vector = direction
	move_changed.emit(direction)


func _draw() -> void:
	_update_layout()
	_draw_top_hud()
	_draw_controls()
	_draw_messages()


func _draw_top_hud() -> void:
	_draw_text("THE HOLLOW WARDEN", Vector2(size.x * 0.5, 35.0), 22, PAPER)
	var boss_rect := Rect2(54.0, 56.0, size.x - 108.0, 27.0)
	draw_rect(boss_rect, Color("090d15dd"))
	draw_rect(Rect2(boss_rect.position + Vector2(4.0, 4.0), Vector2((boss_rect.size.x - 8.0) * clampf(boss_health / 100.0, 0.0, 1.0), boss_rect.size.y - 8.0)), AMBER)
	_draw_text("TARGET · %s" % target_name, Vector2(size.x * 0.5, 107.0), 15, Color("ffd493"))

	var player_width := minf(270.0, size.x * 0.43)
	draw_rect(Rect2(26.0, 130.0, player_width, 18.0), Color("080d15cc"))
	draw_rect(Rect2(29.0, 133.0, (player_width - 6.0) * clampf(player_health / 100.0, 0.0, 1.0), 12.0), RED)
	draw_rect(Rect2(26.0, 155.0, player_width, 13.0), Color("080d15cc"))
	draw_rect(Rect2(29.0, 158.0, (player_width - 6.0) * clampf(player_stamina / 100.0, 0.0, 1.0), 7.0), TEAL)


func _draw_controls() -> void:
	draw_circle(_joystick_center, _joystick_radius, Color("09111e66"))
	draw_arc(_joystick_center, _joystick_radius, 0.0, TAU, 44, Color("dce8ed4d"), 4.0)
	draw_circle(_joystick_center + _move_vector * _joystick_radius, 34.0, Color("dce8ed88"))

	var dodge_color := TEAL if dodge_ready else Color("526b70")
	draw_circle(_dodge_center, _dodge_radius, Color(dodge_color, 0.82))
	draw_arc(_dodge_center, _dodge_radius, 0.0, TAU, 44, Color("e9fff7aa"), 5.0)
	_draw_text("DODGE", _dodge_center, 17, INK)

	var parry_color := AMBER if parry_ready else Color("695d4c")
	if parry_flash > 0.0:
		draw_circle(_parry_center, _parry_radius + 12.0 * parry_flash, Color("fff2b366"))
	draw_circle(_parry_center, _parry_radius, Color(parry_color, 0.88))
	draw_arc(_parry_center, _parry_radius, 0.0, TAU, 40, Color("fff0c0bb"), 5.0)
	_draw_text("PARRY", _parry_center, 14, INK)
	_draw_text("AUTO STRIKE", Vector2(size.x * 0.5, size.y - 45.0), 12, Color("dce8ed77"))


func _draw_messages() -> void:
	if tutorial_alpha > 0.01 and not battle_over:
		var panel := Rect2(36.0, size.y * 0.62, size.x - 72.0, 92.0)
		draw_rect(panel, Color("09111edd", tutorial_alpha))
		draw_rect(panel, Color("dce8ed55", tutorial_alpha), false, 2.0)
		_draw_text("DRAG TO MOVE · ATTACKS ARE AUTOMATIC", Vector2(size.x * 0.5, panel.position.y + 31.0), 15, Color(PAPER, tutorial_alpha))
		_draw_text("TAP THE BOSS TO TARGET · PARRY THE BLADE", Vector2(size.x * 0.5, panel.position.y + 63.0), 13, Color(AMBER, tutorial_alpha))
	if feedback_alpha > 0.01:
		_draw_text(feedback_text, Vector2(size.x * 0.5, size.y * 0.31), 29, Color(AMBER, feedback_alpha))
	if battle_over:
		draw_rect(Rect2(Vector2.ZERO, size), Color("050910c7"))
		_draw_text("WARDEN DEFEATED" if victory else "YOU FELL", Vector2(size.x * 0.5, size.y * 0.42), 39, AMBER if victory else Color("ef8179"))
		_draw_text("TIME %.1fs" % battle_time, Vector2(size.x * 0.5, size.y * 0.49), 20, PAPER)
		_draw_text("TAP TO RETRY", Vector2(size.x * 0.5, size.y * 0.57), 21, TEAL)


func _draw_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center - Vector2(width * 0.5, -font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
