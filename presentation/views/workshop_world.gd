class_name WorkshopWorld
extends Control

signal slime_pressed(slime_id: StringName)
signal forest_pressed
signal background_pressed

const MAP_GRASS := Color("78aa68")
const MAP_GRASS_ALT := Color("72a363")
const PATH := Color("d6c58c")
const PATH_EDGE := Color("ab986d")
const FOREST_DARK := Color("315c45")
const FOREST_LIGHT := Color("4f9660")
const LOCKED_FILL := Color("61706e")
const LOCKED_BORDER := Color("82908d")
const HIGHLIGHT := Color("ffd16f")
const SLIME_BODY := Color("72e0b3")
const SLIME_DARK := Color("243f4d")
const WORK_RING := Color("d8fff0")
const PERFECT_RING := Color("ff9f43")

var game_state: GameState
var selected_slime_id: StringName = &""
var interpolation_alpha: float = 0.0
var _elapsed: float = 0.0
var _forest_rect := Rect2()
var _slime_position := Vector2.ZERO
var _forest_center := Vector2.ZERO
var _mine_center := Vector2.ZERO
var _ark_center := Vector2.ZERO
var _fusion_center := Vector2.ZERO
var _habitat_center := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(400.0, 650.0)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()


func set_game_state(p_state: GameState) -> void:
	game_state = p_state


func set_selection(slime_id: StringName) -> void:
	selected_slime_id = slime_id


func set_interpolation_alpha(alpha: float) -> void:
	interpolation_alpha = clampf(alpha, 0.0, 0.999)


func _draw() -> void:
	_update_layout_points()
	_draw_ground()
	_draw_paths()
	_draw_facilities()
	_draw_slime()
	_draw_mode_badge()


func _update_layout_points() -> void:
	_forest_center = Vector2(size.x * 0.20, size.y * 0.24)
	_mine_center = Vector2(size.x * 0.79, size.y * 0.22)
	_ark_center = Vector2(size.x * 0.51, size.y * 0.47)
	_fusion_center = Vector2(size.x * 0.20, size.y * 0.73)
	_habitat_center = Vector2(size.x * 0.78, size.y * 0.74)
	_forest_rect = Rect2(_forest_center - Vector2(112.0, 112.0), Vector2(224.0, 224.0))


func _draw_ground() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), MAP_GRASS)
	var tile_size := 56.0
	var columns := ceili(size.x / tile_size)
	var rows := ceili(size.y / tile_size)
	for row: int in range(rows):
		for column: int in range(columns):
			if (row + column) % 2 == 0:
				draw_rect(Rect2(column * tile_size, row * tile_size, tile_size, tile_size), MAP_GRASS_ALT)
	for index: int in range(26):
		var x := fmod(float(index * 83 + 31), maxf(size.x, 1.0))
		var y := fmod(float(index * 137 + 77), maxf(size.y, 1.0))
		draw_circle(Vector2(x, y), 3.0, Color("9dc17c88"))


func _draw_paths() -> void:
	_draw_path(_habitat_center, _ark_center)
	_draw_path(_ark_center, _forest_center + Vector2(72.0, 76.0))
	_draw_path(_ark_center, _mine_center)
	_draw_path(_ark_center, _fusion_center)


func _draw_path(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, PATH_EDGE, 38.0, true)
	draw_line(from, to, PATH, 29.0, true)
	var distance := from.distance_to(to)
	var steps := maxi(1, int(distance / 48.0))
	for index: int in range(1, steps):
		var point := from.lerp(to, float(index) / float(steps))
		draw_circle(point, 3.5, Color("a9966877"))


func _draw_facilities() -> void:
	var teach_highlight := selected_slime_id != &"" and _selected_slime_is_untrained()
	_draw_forest(teach_highlight)
	_draw_mine()
	_draw_ark()
	_draw_fusion_pool()
	_draw_habitat()


func _draw_forest(highlighted: bool) -> void:
	var border := HIGHLIGHT if highlighted else FOREST_DARK
	draw_circle(_forest_center, 108.0, Color("426f4d"))
	draw_arc(_forest_center, 111.0 + (sin(_elapsed * 5.0) * 3.0 if highlighted else 0.0), 0.0, TAU, 48, border, 7.0, true)
	var offsets := [
		Vector2(-58.0, -44.0), Vector2(0.0, -66.0), Vector2(58.0, -38.0),
		Vector2(-72.0, 26.0), Vector2(-12.0, 8.0), Vector2(56.0, 28.0), Vector2(2.0, 68.0),
	]
	for index: int in range(offsets.size()):
		_draw_top_tree(_forest_center + offsets[index], 0.82 + float(index % 3) * 0.08)
	_draw_centered_text("FOREST", _forest_center + Vector2(0.0, 136.0), 19, Color("244637"))
	if highlighted:
		_draw_centered_text("TAP TO TEACH", _forest_center + Vector2(0.0, -137.0), 16, HIGHLIGHT)


func _draw_mine() -> void:
	draw_circle(_mine_center, 78.0, LOCKED_FILL)
	draw_arc(_mine_center, 81.0, 0.0, TAU, 40, LOCKED_BORDER, 5.0, true)
	for offset: Vector2 in [Vector2(-34.0, 18.0), Vector2(5.0, -25.0), Vector2(38.0, 22.0)]:
		var rock := PackedVector2Array([
			_mine_center + offset + Vector2(-20.0, 14.0),
			_mine_center + offset + Vector2(-9.0, -19.0),
			_mine_center + offset + Vector2(17.0, -13.0),
			_mine_center + offset + Vector2(23.0, 16.0),
		])
		draw_colored_polygon(rock, Color("87928f"))
	_draw_lock(_mine_center)
	_draw_centered_text("MINE", _mine_center + Vector2(0.0, 108.0), 17, Color("3d514c"))


func _draw_ark() -> void:
	draw_circle(_ark_center, 83.0, Color("b88a5d"))
	draw_arc(_ark_center, 86.0, 0.0, TAU, 40, Color("6f543f"), 5.0, true)
	var hull := PackedVector2Array([
		_ark_center + Vector2(-55.0, 18.0),
		_ark_center + Vector2(-32.0, -34.0),
		_ark_center + Vector2(38.0, -28.0),
		_ark_center + Vector2(57.0, 16.0),
		_ark_center + Vector2(0.0, 48.0),
	])
	draw_colored_polygon(hull, Color("e5b96f"))
	draw_line(_ark_center + Vector2(0.0, -25.0), _ark_center + Vector2(0.0, 35.0), Color("80573e"), 7.0)
	_draw_centered_text("ARK", _ark_center + Vector2(0.0, 112.0), 18, Color("4f4035"))


func _draw_fusion_pool() -> void:
	draw_circle(_fusion_center, 71.0, Color("5f7476"))
	draw_arc(_fusion_center, 74.0, 0.0, TAU, 40, LOCKED_BORDER, 5.0, true)
	draw_circle(_fusion_center, 48.0, Color("5d8c93"))
	draw_circle(_fusion_center + Vector2(-18.0, 4.0), 16.0, Color("78aab0"))
	draw_circle(_fusion_center + Vector2(22.0, -13.0), 11.0, Color("8cbac0"))
	_draw_lock(_fusion_center)
	_draw_centered_text("FUSION", _fusion_center + Vector2(0.0, 103.0), 16, Color("405357"))


func _draw_habitat() -> void:
	draw_circle(_habitat_center, 87.0, Color("e3bc65"))
	draw_arc(_habitat_center, 90.0, 0.0, TAU, 40, Color("9c773c"), 6.0, true)
	draw_circle(_habitat_center, 55.0, Color("f2d584"))
	draw_circle(_habitat_center, 29.0, Color("805a51"))
	draw_circle(_habitat_center, 13.0, Color("3b4650"))
	_draw_centered_text("NEST", _habitat_center + Vector2(0.0, 116.0), 17, Color("554b36"))


func _draw_slime() -> void:
	if game_state == null or game_state.slimes.is_empty():
		return
	var slime := game_state.slimes.values()[0] as SlimeState
	if slime == null:
		return
	_slime_position = _calculate_slime_position(slime)
	var selected := selected_slime_id == slime.id
	var pulse := sin(_elapsed * 5.5)

	if selected:
		draw_circle(_slime_position, 58.0 + pulse * 2.0, Color("ffe29a55"))
		draw_arc(_slime_position, 61.0 + pulse * 2.0, 0.0, TAU, 40, HIGHLIGHT, 5.0, true)

	# Overhead slime silhouette.
	draw_circle(_slime_position, 39.0, SLIME_BODY)
	draw_circle(_slime_position + Vector2(-26.0, 14.0), 19.0, SLIME_BODY)
	draw_circle(_slime_position + Vector2(26.0, 14.0), 19.0, SLIME_BODY)
	draw_circle(_slime_position + Vector2(-12.0, -10.0), 6.0, SLIME_DARK)
	draw_circle(_slime_position + Vector2(12.0, -10.0), 6.0, SLIME_DARK)
	draw_circle(_slime_position + Vector2(-14.0, -12.0), 2.0, Color.WHITE)
	draw_circle(_slime_position + Vector2(10.0, -12.0), 2.0, Color.WHITE)

	var runtime := slime.current_job
	if runtime.phase == JobRuntime.WORKING:
		_draw_work_animation(slime)
		if selected:
			_draw_coaching_ring(slime)
	elif selected:
		_draw_centered_text("FOCUS", _slime_position + Vector2(0.0, -78.0), 15, HIGHLIGHT)

	_draw_centered_text(slime.display_name, _slime_position + Vector2(0.0, 70.0), 16, Color("203b3f"))


func _draw_work_animation(slime: SlimeState) -> void:
	var swing := sin(_elapsed * 9.0)
	var axe_origin := _slime_position + Vector2(-31.0, -15.0)
	var axe_end := axe_origin + Vector2(-20.0 + swing * 10.0, -31.0 - swing * 8.0)
	draw_line(axe_origin, axe_end, Color("744b35"), 6.0, true)
	draw_line(axe_end + Vector2(-8.0, -4.0), axe_end + Vector2(10.0, 8.0), Color("d9e2dc"), 8.0, true)
	if int(_elapsed * 6.0) % 2 == 0:
		draw_circle(_slime_position + Vector2(-50.0, -5.0), 4.0, Color("ffe28a"))


func _draw_coaching_ring(slime: SlimeState) -> void:
	var runtime := slime.current_job
	if runtime.duration_ticks <= 0:
		return
	var job := _get_current_job(slime)
	if job == null:
		return
	var render_elapsed := minf(float(runtime.duration_ticks), float(runtime.elapsed_ticks) + interpolation_alpha)
	var ratio := clampf(render_elapsed / float(runtime.duration_ticks), 0.0, 1.0)
	var perfect_ratio := clampf(float(job.perfect_window_ticks) / float(runtime.duration_ticks), 0.0, 1.0)
	var radius := 70.0
	draw_arc(_slime_position, radius, -PI * 0.5, PI * 1.5, 48, Color("274c4f88"), 9.0, true)
	draw_arc(_slime_position, radius, -PI * 0.5 + TAU * (1.0 - perfect_ratio), PI * 1.5, 16, PERFECT_RING, 10.0, true)
	draw_arc(_slime_position, radius, -PI * 0.5, -PI * 0.5 + TAU * ratio, 48, WORK_RING, 7.0, true)

	if runtime.coaching_used:
		_draw_centered_text("AUTO", _slime_position + Vector2(0.0, -90.0), 15, Color("d8eee5"))
		return
	var remaining := runtime.duration_ticks - render_elapsed
	if remaining <= float(job.perfect_window_ticks):
		var pulse_radius := 80.0 + sin(_elapsed * 12.0) * 7.0
		draw_arc(_slime_position, pulse_radius, 0.0, TAU, 48, PERFECT_RING, 7.0, true)
		_draw_centered_text("TAP!", _slime_position + Vector2(0.0, -94.0), 22, PERFECT_RING)
	else:
		_draw_centered_text("COACH", _slime_position + Vector2(0.0, -91.0), 15, Color("fff1bb"))


func _calculate_slime_position(slime: SlimeState) -> Vector2:
	var work_point := _forest_center + Vector2(108.0, 92.0)
	var runtime := slime.current_job
	if runtime.phase == JobRuntime.MOVING and runtime.movement_ticks > 0:
		var render_elapsed := minf(float(runtime.movement_ticks), float(runtime.elapsed_ticks) + interpolation_alpha)
		return _habitat_center.lerp(work_point, render_elapsed / float(runtime.movement_ticks))
	if slime.logical_location_id == &"forest" or runtime.target_id == &"forest":
		return work_point
	return _habitat_center


func _draw_mode_badge() -> void:
	var focused := selected_slime_id != &""
	var label := "FOCUS MODE · TAP SLIME" if focused else "OVERVIEW · AUTO RUNNING"
	var color := Color("ffe199") if focused else Color("e5f3db")
	draw_rect(Rect2(14.0, 14.0, 246.0 if focused else 270.0, 36.0), Color("243b3cbb"))
	draw_string(ThemeDB.fallback_font, Vector2(28.0, 39.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if game_state != null and not game_state.slimes.is_empty() and event.position.distance_to(_slime_position) <= 86.0:
		var slime := game_state.slimes.values()[0] as SlimeState
		slime_pressed.emit(slime.id)
		accept_event()
		return
	if _forest_rect.has_point(event.position):
		forest_pressed.emit()
		accept_event()
		return
	background_pressed.emit()
	accept_event()


func _selected_slime_is_untrained() -> bool:
	if game_state == null or selected_slime_id == &"":
		return false
	var slime := game_state.slimes.get(selected_slime_id) as SlimeState
	return slime != null and not slime.skill_memories.has(&"logging")


func _get_current_job(slime: SlimeState) -> JobDefinition:
	if slime.current_job.job_id == &"":
		return null
	# The first slice has one job. Keeping lookup local avoids presentation state owning definitions.
	return App.game_session.content_registry.get_job(slime.current_job.job_id)


func _draw_top_tree(center: Vector2, scale_factor: float) -> void:
	draw_circle(center, 24.0 * scale_factor, FOREST_DARK)
	draw_circle(center + Vector2(-13.0, -9.0) * scale_factor, 18.0 * scale_factor, FOREST_LIGHT)
	draw_circle(center + Vector2(12.0, -7.0) * scale_factor, 17.0 * scale_factor, Color("3f8254"))
	draw_circle(center, 5.0 * scale_factor, Color("76523d"))


func _draw_lock(center: Vector2) -> void:
	draw_rect(Rect2(center + Vector2(-13.0, -2.0), Vector2(26.0, 24.0)), Color("34484a"))
	draw_arc(center + Vector2(0.0, -2.0), 12.0, PI, TAU, 16, Color("34484a"), 6.0, true)
	draw_circle(center + Vector2(0.0, 9.0), 3.0, Color("aab7ad"))


func _draw_centered_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center - Vector2(width * 0.5, -font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
