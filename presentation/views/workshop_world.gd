class_name WorkshopWorld
extends Control

signal slime_pressed(slime_id: StringName)
signal forest_pressed

const SKY := Color("9dd8d0")
const SKY_LOW := Color("bce6d4")
const GRASS := Color("75aa62")
const GRASS_DARK := Color("4d7e4e")
const FOREST_HIGHLIGHT := Color("ffd27c")
const SLIME_BODY := Color("72e0b3")
const SLIME_DARK := Color("244052")

var game_state: GameState
var selected_slime_id: StringName = &""
var compatible_target_highlight: bool = false
var _elapsed: float = 0.0
var _forest_rect := Rect2()
var _slime_position := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(400.0, 620.0)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()


func set_game_state(p_state: GameState) -> void:
	game_state = p_state
	queue_redraw()


func set_selection(slime_id: StringName) -> void:
	selected_slime_id = slime_id
	compatible_target_highlight = slime_id != &""
	queue_redraw()


func _draw() -> void:
	_forest_rect = Rect2(24.0, size.y * 0.28, size.x * 0.40, size.y * 0.56)
	draw_rect(Rect2(Vector2.ZERO, size), SKY)
	draw_rect(Rect2(0.0, size.y * 0.42, size.x, size.y * 0.58), SKY_LOW)
	_draw_cloud(Vector2(size.x * 0.18, size.y * 0.13), 1.0)
	_draw_cloud(Vector2(size.x * 0.74, size.y * 0.20), 0.72)
	draw_rect(Rect2(0.0, size.y * 0.72, size.x, size.y * 0.28), GRASS)
	for index: int in range(9):
		var x := float(index) * size.x / 8.0
		draw_line(Vector2(x, size.y * 0.80), Vector2(x + 18.0, size.y * 0.75), GRASS_DARK, 5.0)

	_draw_forest()
	_draw_habitat()
	_draw_path()
	_draw_slime()


func _draw_forest() -> void:
	var border := FOREST_HIGHLIGHT if compatible_target_highlight else Color("6ea178")
	draw_style_box(_panel_style(Color("315b4699"), border, 22), _forest_rect)
	var tree_positions := [
		Vector2(_forest_rect.position.x + 60.0, _forest_rect.position.y + 155.0),
		Vector2(_forest_rect.position.x + 150.0, _forest_rect.position.y + 115.0),
		Vector2(_forest_rect.position.x + 215.0, _forest_rect.position.y + 205.0),
		Vector2(_forest_rect.position.x + 105.0, _forest_rect.position.y + 285.0),
	]
	for index: int in range(tree_positions.size()):
		_draw_tree(tree_positions[index], 0.85 + float(index % 2) * 0.18)
	_draw_centered_text("FOREST", Vector2(_forest_rect.get_center().x, _forest_rect.position.y + 44.0), 22, Color("f6edcf"))
	var prompt := "TAP TO TEACH" if compatible_target_highlight else "Logging site"
	_draw_centered_text(prompt, Vector2(_forest_rect.get_center().x, _forest_rect.end.y - 32.0), 16, border)


func _draw_habitat() -> void:
	var center := Vector2(size.x * 0.76, size.y * 0.64)
	var shadow := Rect2(center + Vector2(-98.0, 66.0), Vector2(196.0, 30.0))
	draw_style_box(_panel_style(Color("31524455"), Color.TRANSPARENT, 18), shadow)
	var dome := PackedVector2Array()
	for index: int in range(25):
		var angle := PI - PI * float(index) / 24.0
		dome.append(center + Vector2(cos(angle) * 102.0, -sin(angle) * 82.0))
	dome.append(center + Vector2(102.0, 66.0))
	dome.append(center + Vector2(-102.0, 66.0))
	draw_colored_polygon(dome, Color("f1c46b"))
	draw_rect(Rect2(center + Vector2(-30.0, 5.0), Vector2(60.0, 61.0)), Color("805b55"))
	draw_circle(center + Vector2(0.0, 35.0), 7.0, Color("ffdb78"))
	_draw_centered_text("NEST", center + Vector2(0.0, 110.0), 17, Color("36505a"))


func _draw_path() -> void:
	var start := Vector2(_forest_rect.end.x - 8.0, size.y * 0.78)
	var finish := Vector2(size.x * 0.68, size.y * 0.76)
	draw_line(start, finish, Color("d8c48888"), 52.0, true)
	draw_line(start, finish, Color("f0d99a88"), 36.0, true)


func _draw_slime() -> void:
	if game_state == null or game_state.slimes.is_empty():
		return
	var slime := game_state.slimes.values()[0] as SlimeState
	if slime == null:
		return
	_slime_position = _calculate_slime_position(slime)
	_slime_position.y += sin(_elapsed * 4.0) * 5.0

	if selected_slime_id == slime.id:
		draw_circle(_slime_position, 68.0 + sin(_elapsed * 5.0) * 3.0, Color("ffd27c55"))
		draw_arc(_slime_position, 69.0, 0.0, TAU, 40, FOREST_HIGHLIGHT, 5.0, true)

	var body_center := _slime_position + Vector2(0.0, 8.0)
	draw_circle(body_center, 50.0, SLIME_BODY)
	draw_rect(Rect2(body_center + Vector2(-50.0, 0.0), Vector2(100.0, 42.0)), SLIME_BODY)
	draw_circle(body_center + Vector2(-24.0, 18.0), 27.0, SLIME_BODY)
	draw_circle(body_center + Vector2(25.0, 18.0), 27.0, SLIME_BODY)
	draw_circle(body_center + Vector2(-18.0, -8.0), 8.0, SLIME_DARK)
	draw_circle(body_center + Vector2(18.0, -8.0), 8.0, SLIME_DARK)
	draw_circle(body_center + Vector2(-21.0, -11.0), 2.5, Color.WHITE)
	draw_circle(body_center + Vector2(15.0, -11.0), 2.5, Color.WHITE)
	draw_arc(body_center + Vector2(0.0, 8.0), 15.0, 0.2, PI - 0.2, 18, SLIME_DARK, 3.5, true)

	var runtime := slime.current_job
	if runtime.phase == JobRuntime.WORKING and runtime.duration_ticks > 0:
		var ratio := clampf(float(runtime.elapsed_ticks) / float(runtime.duration_ticks), 0.0, 1.0)
		draw_arc(_slime_position, 62.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 36, Color("fff0a3"), 8.0, true)
		if not runtime.coaching_used:
			draw_circle(_slime_position + Vector2(50.0, -50.0), 15.0 + sin(_elapsed * 6.0) * 2.0, Color("ffb260"))
			draw_circle(_slime_position + Vector2(50.0, -50.0), 6.0, Color.WHITE)

	_draw_centered_text(slime.display_name, _slime_position + Vector2(0.0, 94.0), 17, Color("263f50"))


func _calculate_slime_position(slime: SlimeState) -> Vector2:
	var nest := Vector2(size.x * 0.76, size.y * 0.73)
	var work := Vector2(_forest_rect.end.x + 38.0, size.y * 0.72)
	var runtime := slime.current_job
	if runtime.phase == JobRuntime.MOVING and runtime.movement_ticks > 0:
		var ratio := clampf(float(runtime.elapsed_ticks) / float(runtime.movement_ticks), 0.0, 1.0)
		return nest.lerp(work, ratio)
	if slime.logical_location_id == &"forest" or runtime.target_id == &"forest":
		return work
	return nest


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.position.distance_to(_slime_position) <= 88.0 and game_state != null and not game_state.slimes.is_empty():
			var slime := game_state.slimes.values()[0] as SlimeState
			slime_pressed.emit(slime.id)
			accept_event()
			return
		if _forest_rect.has_point(event.position):
			forest_pressed.emit()
			accept_event()


func _draw_tree(base: Vector2, scale_factor: float) -> void:
	draw_rect(Rect2(base + Vector2(-14.0, -10.0) * scale_factor, Vector2(28.0, 95.0) * scale_factor), Color("76543e"))
	draw_circle(base + Vector2(0.0, -42.0) * scale_factor, 54.0 * scale_factor, Color("3d8758"))
	draw_circle(base + Vector2(-34.0, -20.0) * scale_factor, 37.0 * scale_factor, Color("4b9b61"))
	draw_circle(base + Vector2(34.0, -18.0) * scale_factor, 39.0 * scale_factor, Color("32764f"))
	draw_circle(base + Vector2(-15.0, -62.0) * scale_factor, 22.0 * scale_factor, Color("79bd6d"))


func _draw_cloud(center: Vector2, scale_factor: float) -> void:
	var color := Color("f6f5dcaa")
	draw_circle(center, 30.0 * scale_factor, color)
	draw_circle(center + Vector2(33.0, 5.0) * scale_factor, 23.0 * scale_factor, color)
	draw_circle(center + Vector2(-34.0, 8.0) * scale_factor, 20.0 * scale_factor, color)


func _draw_centered_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center - Vector2(width * 0.5, -font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


static func _panel_style(color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(3 if border_color.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	return style
