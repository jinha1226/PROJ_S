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
const WORLD_SIZE := Vector2(1120.0, 1040.0)
const ZOOM_STEP := 1.20

var game_state: GameState
var content_registry: ContentRegistry
var selected_slime_id: StringName = &""
var interpolation_alpha: float = 0.0
var _elapsed: float = 0.0
var _tap_feedback_elapsed: float = 99.0
var _coach_feedback_elapsed: float = 99.0
var _coach_feedback_kind: StringName = &""
var _forest_rect := Rect2()
var _slime_position := Vector2.ZERO
var _forest_center := Vector2.ZERO
var _mine_center := Vector2.ZERO
var _ark_center := Vector2.ZERO
var _fusion_center := Vector2.ZERO
var _habitat_center := Vector2.ZERO
var _zoom: float = 1.0
var _min_zoom: float = 0.5
var _max_zoom: float = 1.5
var _camera_center := WORLD_SIZE * 0.5
var _camera_initialized: bool = false
var _last_control_size := Vector2.ZERO
var _zoom_out_rect := Rect2()
var _zoom_reset_rect := Rect2()
var _zoom_in_rect := Rect2()
var _active_touches: Dictionary = {}
var _single_touch_start := Vector2.ZERO
var _touch_dragged: bool = false
var _gesture_is_pinch: bool = false
var _pinch_last_distance: float = 0.0
var _mouse_pressed: bool = false
var _mouse_dragged: bool = false
var _mouse_press_position := Vector2.ZERO
var _mouse_last_position := Vector2.ZERO
var _last_touch_event_msec: int = -10000


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(400.0, 650.0)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	_tap_feedback_elapsed += delta
	_coach_feedback_elapsed += delta
	queue_redraw()


func set_game_state(p_state: GameState) -> void:
	game_state = p_state


func set_content_registry(p_registry: ContentRegistry) -> void:
	content_registry = p_registry


func set_selection(slime_id: StringName) -> void:
	selected_slime_id = slime_id


func set_interpolation_alpha(alpha: float) -> void:
	interpolation_alpha = clampf(alpha, 0.0, 0.999)


func play_tap_feedback() -> void:
	_tap_feedback_elapsed = 0.0
	queue_redraw()


func play_coaching_feedback(result_type: StringName) -> void:
	_coach_feedback_kind = result_type
	_coach_feedback_elapsed = 0.0
	Input.vibrate_handheld(90 if result_type == &"PERFECT" else 45, 0.75 if result_type == &"PERFECT" else 0.45)
	queue_redraw()


func _draw() -> void:
	_configure_camera()
	_update_layout_points()
	draw_rect(Rect2(Vector2.ZERO, size), FOREST_DARK)
	_apply_camera_transform()
	_draw_ground()
	_draw_paths()
	_draw_facilities()
	_draw_slime()
	_draw_tap_feedback()
	_draw_coaching_feedback()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_mode_badge()
	_draw_zoom_controls()


func _update_layout_points() -> void:
	_forest_center = Vector2(WORLD_SIZE.x * 0.17, WORLD_SIZE.y * 0.19)
	_mine_center = Vector2(WORLD_SIZE.x * 0.83, WORLD_SIZE.y * 0.18)
	_ark_center = Vector2(WORLD_SIZE.x * 0.50, WORLD_SIZE.y * 0.48)
	_fusion_center = Vector2(WORLD_SIZE.x * 0.18, WORLD_SIZE.y * 0.80)
	_habitat_center = Vector2(WORLD_SIZE.x * 0.82, WORLD_SIZE.y * 0.80)
	_forest_rect = Rect2(_forest_center - Vector2(112.0, 112.0), Vector2(224.0, 224.0))


func _draw_ground() -> void:
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), MAP_GRASS)
	var tile_size := 56.0
	var columns := ceili(WORLD_SIZE.x / tile_size)
	var rows := ceili(WORLD_SIZE.y / tile_size)
	for row: int in range(rows):
		for column: int in range(columns):
			if (row + column) % 2 == 0:
				draw_rect(Rect2(column * tile_size, row * tile_size, tile_size, tile_size), MAP_GRASS_ALT)
	for index: int in range(48):
		var x := fmod(float(index * 83 + 31), WORLD_SIZE.x)
		var y := fmod(float(index * 137 + 77), WORLD_SIZE.y)
		draw_circle(Vector2(x, y), 3.0, Color("9dc17c88"))
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("d9efc777"), false, 8.0)


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
	if _coach_feedback_elapsed < _coach_feedback_duration():
		var bounce_progress := _coach_feedback_elapsed / _coach_feedback_duration()
		var bounce_height := 29.0 if _coach_feedback_kind == &"PERFECT" else 15.0
		_slime_position.y -= sin(bounce_progress * PI) * bounce_height
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


func _draw_tap_feedback() -> void:
	const TAP_DURATION := 0.28
	if _tap_feedback_elapsed >= TAP_DURATION:
		return
	var progress := _tap_feedback_elapsed / TAP_DURATION
	var color := Color("fff2ae")
	color.a = (1.0 - progress) * 0.9
	draw_arc(_slime_position, 44.0 + progress * 42.0, 0.0, TAU, 40, color, 8.0 * (1.0 - progress) + 1.0, true)


func _draw_coaching_feedback() -> void:
	var duration := _coach_feedback_duration()
	if _coach_feedback_elapsed >= duration:
		return
	var progress := clampf(_coach_feedback_elapsed / duration, 0.0, 1.0)
	var fade := 1.0 - progress
	var perfect := _coach_feedback_kind == &"PERFECT"
	var effect_color := PERFECT_RING if perfect else Color("7cf2cb")

	var flash_color := effect_color
	flash_color.a = fade * (0.25 if perfect else 0.12)
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), flash_color)

	for ring_index: int in range(3 if perfect else 2):
		var delayed_progress := clampf(progress * 1.45 - float(ring_index) * 0.18, 0.0, 1.0)
		if delayed_progress <= 0.0:
			continue
		var ring_color := effect_color
		ring_color.a = (1.0 - delayed_progress) * (0.95 - float(ring_index) * 0.18)
		var radius := 48.0 + delayed_progress * (165.0 if perfect else 110.0)
		draw_arc(_slime_position, radius, 0.0, TAU, 56, ring_color, maxf(1.0, 11.0 * (1.0 - delayed_progress)), true)

	var ray_count := 14 if perfect else 9
	for ray_index: int in range(ray_count):
		var angle := TAU * float(ray_index) / float(ray_count) + 0.13
		var inner_radius := 54.0 + progress * 46.0
		var outer_radius := inner_radius + (34.0 if perfect else 22.0) * fade
		var ray_color := effect_color
		ray_color.a = fade
		draw_line(
			_slime_position + Vector2.from_angle(angle) * inner_radius,
			_slime_position + Vector2.from_angle(angle) * outer_radius,
			ray_color,
			6.0 if perfect else 4.0,
			true
		)

	# Deterministic chips make the hit read clearly without allocating particle nodes.
	for chip_index: int in range(10 if perfect else 6):
		var chip_angle := -PI * 0.9 + float(chip_index) * PI * 1.8 / float(9 if perfect else 5)
		var chip_distance := progress * (130.0 + float(chip_index % 3) * 18.0)
		var chip_position := _slime_position + Vector2.from_angle(chip_angle) * chip_distance
		chip_position.y += progress * progress * 54.0
		var chip_color := Color("ffe28a") if chip_index % 2 == 0 else Color("9e653f")
		chip_color.a = fade
		draw_circle(chip_position, (7.0 if perfect else 5.0) * fade + 1.0, chip_color)

	var message := "PERFECT!" if perfect else "NICE!"
	var message_color := Color("fff1a8") if perfect else Color("d9fff0")
	message_color.a = minf(1.0, fade * 1.8)
	_draw_centered_text(message, _slime_position + Vector2(0.0, -112.0 - progress * 58.0), 32 if perfect else 25, message_color)


func _coach_feedback_duration() -> float:
	return 0.95 if _coach_feedback_kind == &"PERFECT" else 0.62


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


func _draw_zoom_controls() -> void:
	var total_width := 184.0
	var button_height := 46.0
	var start_x := size.x - total_width - 14.0
	var start_y := size.y - button_height - 12.0
	_zoom_out_rect = Rect2(start_x, start_y, 48.0, button_height)
	_zoom_reset_rect = Rect2(start_x + 54.0, start_y, 76.0, button_height)
	_zoom_in_rect = Rect2(start_x + 136.0, start_y, 48.0, button_height)

	for rect: Rect2 in [_zoom_out_rect, _zoom_reset_rect, _zoom_in_rect]:
		draw_rect(rect, Color("243b3cdd"))
		draw_rect(rect, Color("d9efc788"), false, 2.0)
	_draw_centered_text("−", _zoom_out_rect.get_center() + Vector2(0.0, -2.0), 25, Color("f5f0dc"))
	_draw_centered_text("%d%%" % int(round(_zoom / maxf(_min_zoom, 0.001) * 100.0)), _zoom_reset_rect.get_center() + Vector2(0.0, -2.0), 15, Color("e5f3db"))
	_draw_centered_text("+", _zoom_in_rect.get_center() + Vector2(0.0, -2.0), 24, Color("f5f0dc"))
	draw_string(ThemeDB.fallback_font, Vector2(18.0, size.y - 27.0), "PINCH · DRAG", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e5f3dbcc"))


func _configure_camera() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.is_equal_approx(_last_control_size):
		return
	var previous_min := _min_zoom
	var normalized_zoom := _zoom / maxf(previous_min, 0.001)
	_min_zoom = minf(size.x / WORLD_SIZE.x, size.y / WORLD_SIZE.y) * 0.94
	_max_zoom = _min_zoom * 2.8
	if not _camera_initialized:
		_zoom = _min_zoom
		_camera_center = WORLD_SIZE * 0.5
		_camera_initialized = true
	else:
		_zoom = clampf(_min_zoom * normalized_zoom, _min_zoom, _max_zoom)
	_last_control_size = size
	_clamp_camera()


func _apply_camera_transform() -> void:
	var origin := size * 0.5 - _camera_center * _zoom
	draw_set_transform(origin, 0.0, Vector2.ONE * _zoom)


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return (screen_position - size * 0.5) / maxf(_zoom, 0.001) + _camera_center


func _zoom_at(screen_position: Vector2, requested_zoom: float) -> void:
	_configure_camera()
	var next_zoom := clampf(requested_zoom, _min_zoom, _max_zoom)
	if is_equal_approx(next_zoom, _zoom):
		return
	var anchor_world := _screen_to_world(screen_position)
	_zoom = next_zoom
	_camera_center = anchor_world - (screen_position - size * 0.5) / _zoom
	_clamp_camera()
	queue_redraw()


func _reset_camera() -> void:
	_configure_camera()
	_zoom = _min_zoom
	_camera_center = WORLD_SIZE * 0.5
	queue_redraw()


func _pan_camera(screen_delta: Vector2) -> void:
	if _zoom <= _min_zoom + 0.001:
		return
	_camera_center -= screen_delta / _zoom
	_clamp_camera()
	queue_redraw()


func _clamp_camera() -> void:
	var half_view := size / maxf(_zoom * 2.0, 0.001)
	if half_view.x >= WORLD_SIZE.x * 0.5:
		_camera_center.x = WORLD_SIZE.x * 0.5
	else:
		_camera_center.x = clampf(_camera_center.x, half_view.x, WORLD_SIZE.x - half_view.x)
	if half_view.y >= WORLD_SIZE.y * 0.5:
		_camera_center.y = WORLD_SIZE.y * 0.5
	else:
		_camera_center.y = clampf(_camera_center.y, half_view.y, WORLD_SIZE.y - half_view.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_last_touch_event_msec = Time.get_ticks_msec()
		_handle_screen_touch(event)
		accept_event()
		return
	if event is InputEventScreenDrag:
		_last_touch_event_msec = Time.get_ticks_msec()
		_handle_screen_drag(event)
		accept_event()
		return
	if event is InputEventMagnifyGesture:
		_zoom_at(event.position, _zoom * event.factor)
		accept_event()
		return
	if event is InputEventMouseButton:
		# Mobile browsers may emit an emulated mouse event after the real touch event.
		if Time.get_ticks_msec() - _last_touch_event_msec < 400:
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, _zoom * ZOOM_STEP)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, _zoom / ZOOM_STEP)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_mouse_button(event)
			accept_event()
			return
	if event is InputEventMouseMotion and _mouse_pressed:
		var mouse_delta: Vector2 = event.position - _mouse_last_position
		_mouse_last_position = event.position
		if event.position.distance_to(_mouse_press_position) > 9.0:
			_mouse_dragged = true
		if _mouse_dragged:
			_pan_camera(mouse_delta)
		accept_event()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.pressed:
		_mouse_pressed = true
		_mouse_dragged = false
		_mouse_press_position = event.position
		_mouse_last_position = event.position
		return
	if not _mouse_pressed:
		return
	_mouse_pressed = false
	if not _mouse_dragged:
		_handle_screen_tap(event.position)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_active_touches[event.index] = event.position
		if _active_touches.size() == 1:
			_single_touch_start = event.position
			_touch_dragged = false
			_gesture_is_pinch = false
		elif _active_touches.size() >= 2:
			_gesture_is_pinch = true
			_touch_dragged = true
			_pinch_last_distance = _first_two_touch_distance()
		return

	var should_tap := _active_touches.has(event.index) and _active_touches.size() == 1 and not _touch_dragged and not _gesture_is_pinch
	_active_touches.erase(event.index)
	if should_tap:
		_handle_screen_tap(event.position)
	if _active_touches.is_empty():
		_pinch_last_distance = 0.0
		_touch_dragged = false
		_gesture_is_pinch = false


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _active_touches.has(event.index):
		return
	_active_touches[event.index] = event.position
	if _active_touches.size() >= 2:
		var current_distance := _first_two_touch_distance()
		if _pinch_last_distance > 0.0 and current_distance > 0.0:
			_zoom_at(_first_two_touch_center(), _zoom * current_distance / _pinch_last_distance)
		_pinch_last_distance = current_distance
		_gesture_is_pinch = true
		_touch_dragged = true
		return
	if event.position.distance_to(_single_touch_start) > 10.0:
		_touch_dragged = true
	if _touch_dragged:
		_pan_camera(event.relative)


func _first_two_touch_distance() -> float:
	var positions := _first_two_touch_positions()
	return positions[0].distance_to(positions[1]) if positions.size() == 2 else 0.0


func _first_two_touch_center() -> Vector2:
	var positions := _first_two_touch_positions()
	return (positions[0] + positions[1]) * 0.5 if positions.size() == 2 else size * 0.5


func _first_two_touch_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for raw_position: Variant in _active_touches.values():
		positions.append(raw_position as Vector2)
		if positions.size() == 2:
			break
	return positions


func _handle_screen_tap(screen_position: Vector2) -> void:
	if _zoom_out_rect.has_point(screen_position):
		_zoom_at(size * 0.5, _zoom / ZOOM_STEP)
		return
	if _zoom_reset_rect.has_point(screen_position):
		_reset_camera()
		return
	if _zoom_in_rect.has_point(screen_position):
		_zoom_at(size * 0.5, _zoom * ZOOM_STEP)
		return

	var world_position := _screen_to_world(screen_position)
	var slime_hit_radius := maxf(86.0, 54.0 / maxf(_zoom, 0.001))
	if game_state != null and not game_state.slimes.is_empty() and world_position.distance_to(_slime_position) <= slime_hit_radius:
		var slime := game_state.slimes.values()[0] as SlimeState
		slime_pressed.emit(slime.id)
		return
	if _forest_rect.has_point(world_position):
		forest_pressed.emit()
		return
	background_pressed.emit()


func _selected_slime_is_untrained() -> bool:
	if game_state == null or selected_slime_id == &"":
		return false
	var slime := game_state.slimes.get(selected_slime_id) as SlimeState
	return slime != null and not slime.skill_memories.has(&"logging")


func _get_current_job(slime: SlimeState) -> JobDefinition:
	if slime.current_job.job_id == &"" or content_registry == null:
		return null
	return content_registry.get_job(slime.current_job.job_id)


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
