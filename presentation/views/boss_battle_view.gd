class_name BossBattleView
extends Control

const WORLD_RECT := Rect2(0.0, 0.0, 820.0, 1500.0)
const PLAYER_RADIUS := 25.0
const BOSS_RADIUS := 118.0
const PART_RADIUS := 52.0
const PLAYER_SPEED := 275.0
const DODGE_SPEED := 720.0
const DODGE_DURATION := 0.34
const DODGE_COST := 34.0
const ATTACK_RANGE := 174.0
const ATTACK_DURATION := 0.43
const ATTACK_HIT_TIME := 0.17
const ATTACK_DAMAGE := 12.0

const COLOR_VOID := Color("101827")
const COLOR_ARENA := Color("263852")
const COLOR_ARENA_ALT := Color("2c4260")
const COLOR_LINE := Color("496681")
const COLOR_PLAYER := Color("dbe9f1")
const COLOR_CAPE := Color("d45f5f")
const COLOR_STEEL := Color("a8c7d8")
const COLOR_BOSS := Color("746b78")
const COLOR_BOSS_DARK := Color("403b49")
const COLOR_CORE := Color("f0a35e")
const COLOR_DANGER := Color("ef665f")
const COLOR_DODGE := Color("72e4c0")
const COLOR_GOLD := Color("ffd77b")

var _elapsed: float = 0.0
var _player_position := Vector2(410.0, 1260.0)
var _player_health: float = 100.0
var _player_stamina: float = 100.0
var _player_invulnerable: float = 0.0
var _stamina_regen_delay: float = 0.0
var _move_input := Vector2.ZERO
var _touch_move_input := Vector2.ZERO
var _move_touch_index: int = -1
var _mouse_move_active: bool = false
var _last_touch_msec: int = -10000

var _dodge_timer: float = 0.0
var _dodge_direction := Vector2.UP
var _perfect_dodge_used: bool = false
var _attack_elapsed: float = -1.0
var _attack_cooldown: float = 0.0
var _attack_hit_done: bool = false
var _attack_facing := Vector2.UP
var _counter_bonus: bool = false

var _boss_position := Vector2(410.0, 300.0)
var _boss_home := Vector2(410.0, 300.0)
var _boss_state: StringName = &"IDLE"
var _boss_pattern: StringName = &""
var _boss_state_timer: float = 1.15
var _boss_pattern_index: int = 0
var _boss_attack_resolved: bool = false
var _boss_locked_direction := Vector2.DOWN
var _boss_health: float = 220.0
var _part_health: Dictionary = {&"left_arm": 54.0, &"right_arm": 54.0}
var _selected_part: StringName = &"core"

var _camera_center := Vector2(410.0, 760.0)
var _camera_zoom: float = 0.72
var _camera_shake: float = 0.0
var _camera_punch: float = 0.0
var _slow_motion_timer: float = 0.0
var _hit_stop_timer: float = 0.0

var _player_dead: bool = false
var _victory: bool = false
var _battle_time: float = 0.0
var _feedback_text: String = ""
var _feedback_timer: float = 0.0
var _tutorial_timer: float = 7.0
var _effects: Array[Dictionary] = []

var _joystick_center := Vector2.ZERO
var _joystick_radius: float = 82.0
var _dodge_center := Vector2.ZERO
var _dodge_radius: float = 66.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_restart_battle()


func _process(delta: float) -> void:
	var frame_delta := minf(delta, 0.04)
	_elapsed += frame_delta
	_update_control_layout()
	_update_input_vector()
	_update_effects(frame_delta)
	_feedback_timer = maxf(0.0, _feedback_timer - frame_delta)
	_tutorial_timer = maxf(0.0, _tutorial_timer - frame_delta)
	_camera_shake = maxf(0.0, _camera_shake - frame_delta * 7.0)
	_camera_punch = maxf(0.0, _camera_punch - frame_delta * 3.8)

	if _hit_stop_timer > 0.0:
		_hit_stop_timer = maxf(0.0, _hit_stop_timer - frame_delta)
		_update_camera(frame_delta)
		queue_redraw()
		return

	var world_delta := frame_delta
	if _slow_motion_timer > 0.0:
		_slow_motion_timer = maxf(0.0, _slow_motion_timer - frame_delta)
		world_delta *= 0.42

	if not _player_dead and not _victory:
		_battle_time += frame_delta
		_update_player(world_delta)
		_update_auto_attack(world_delta)
		_update_boss(world_delta)
	else:
		_attack_elapsed = -1.0

	_update_camera(frame_delta)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_try_dodge()
		elif event.keycode == KEY_R and (_player_dead or _victory):
			_restart_battle()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_last_touch_msec = Time.get_ticks_msec()
		_handle_touch(event)
		accept_event()
		return
	if event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		_handle_touch_drag(event)
		accept_event()
		return
	if event is InputEventMouseButton:
		if Time.get_ticks_msec() - _last_touch_msec < 400:
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_handle_pointer_press(event.position)
			else:
				_mouse_move_active = false
				_touch_move_input = Vector2.ZERO
			accept_event()
			return
	if event is InputEventMouseMotion and _mouse_move_active:
		_update_pointer_move(event.position)
		accept_event()


func _restart_battle() -> void:
	_player_position = Vector2(410.0, 1260.0)
	_player_health = 100.0
	_player_stamina = 100.0
	_player_invulnerable = 0.0
	_stamina_regen_delay = 0.0
	_move_input = Vector2.ZERO
	_touch_move_input = Vector2.ZERO
	_move_touch_index = -1
	_mouse_move_active = false
	_dodge_timer = 0.0
	_perfect_dodge_used = false
	_attack_elapsed = -1.0
	_attack_cooldown = 0.0
	_counter_bonus = false
	_boss_position = _boss_home
	_boss_state = &"IDLE"
	_boss_pattern = &""
	_boss_state_timer = 1.15
	_boss_pattern_index = 0
	_boss_attack_resolved = false
	_boss_locked_direction = Vector2.DOWN
	_boss_health = 220.0
	_part_health = {&"left_arm": 54.0, &"right_arm": 54.0}
	_selected_part = &"core"
	_camera_center = Vector2(410.0, 760.0)
	_camera_zoom = 0.72
	_camera_shake = 0.0
	_camera_punch = 0.0
	_slow_motion_timer = 0.0
	_hit_stop_timer = 0.0
	_player_dead = false
	_victory = false
	_battle_time = 0.0
	_feedback_text = "APPROACH THE COLOSSUS"
	_feedback_timer = 1.8
	_tutorial_timer = 7.0
	_effects.clear()
	queue_redraw()


func _update_control_layout() -> void:
	_joystick_center = Vector2(142.0, size.y - 138.0)
	_dodge_center = Vector2(size.x - 124.0, size.y - 138.0)


func _update_input_vector() -> void:
	var keyboard := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)
	_move_input = keyboard.normalized() if keyboard.length_squared() > 0.01 else _touch_move_input


func _update_player(delta: float) -> void:
	_player_invulnerable = maxf(0.0, _player_invulnerable - delta)
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_stamina_regen_delay = maxf(0.0, _stamina_regen_delay - delta)
	if _stamina_regen_delay <= 0.0 and _dodge_timer <= 0.0:
		_player_stamina = minf(100.0, _player_stamina + 31.0 * delta)

	var velocity := Vector2.ZERO
	if _dodge_timer > 0.0:
		_dodge_timer = maxf(0.0, _dodge_timer - delta)
		velocity = _dodge_direction * DODGE_SPEED
	else:
		var movement_scale := 0.46 if _attack_elapsed >= 0.0 else 1.0
		velocity = _move_input * PLAYER_SPEED * movement_scale
	_player_position += velocity * delta
	_player_position.x = clampf(_player_position.x, WORLD_RECT.position.x + 44.0, WORLD_RECT.end.x - 44.0)
	_player_position.y = clampf(_player_position.y, WORLD_RECT.position.y + 90.0, WORLD_RECT.end.y - 45.0)

	var from_boss := _player_position - _boss_position
	var minimum_distance := BOSS_RADIUS + PLAYER_RADIUS + 5.0
	if from_boss.length() < minimum_distance:
		_player_position = _boss_position + from_boss.normalized() * minimum_distance


func _try_dodge() -> void:
	if _player_dead or _victory or _dodge_timer > 0.0 or _player_stamina < DODGE_COST:
		return
	_player_stamina -= DODGE_COST
	_stamina_regen_delay = 0.68
	_dodge_timer = DODGE_DURATION
	_player_invulnerable = maxf(_player_invulnerable, DODGE_DURATION + 0.08)
	_perfect_dodge_used = false
	_attack_elapsed = -1.0
	_attack_cooldown = 0.10
	_dodge_direction = _move_input.normalized()
	if _dodge_direction.length_squared() < 0.01:
		_dodge_direction = (_player_position - _boss_position).normalized()
	_add_effect(_player_position, COLOR_DODGE, &"dodge", 0.42)


func _update_auto_attack(delta: float) -> void:
	if _dodge_timer > 0.0 or _boss_state == &"DEAD":
		_attack_elapsed = -1.0
		return
	var target_position := _part_position(_selected_part)
	var to_target := target_position - _player_position
	if _attack_elapsed >= 0.0:
		_attack_elapsed += delta
		_attack_facing = to_target.normalized()
		if not _attack_hit_done and _attack_elapsed >= ATTACK_HIT_TIME:
			_attack_hit_done = true
			_resolve_player_attack()
		if _attack_elapsed >= ATTACK_DURATION:
			_attack_elapsed = -1.0
			_attack_cooldown = 0.13
		return

	if _attack_cooldown > 0.0 or to_target.length() > ATTACK_RANGE:
		return
	var moving_away := _move_input.length_squared() > 0.1 and _move_input.dot(to_target.normalized()) < -0.32
	if moving_away:
		return
	_attack_elapsed = 0.0
	_attack_hit_done = false
	_attack_facing = to_target.normalized()


func _resolve_player_attack() -> void:
	var target_position := _part_position(_selected_part)
	if _player_position.distance_to(target_position) > ATTACK_RANGE + 28.0:
		return
	var damage := ATTACK_DAMAGE
	if _boss_state == &"RECOVERY":
		damage *= 1.25
	if _counter_bonus:
		damage *= 1.65
		_counter_bonus = false
		_set_feedback("COUNTER STRIKE", 0.75)
	_damage_boss_part(_selected_part, damage)
	_hit_stop_timer = 0.045
	_camera_shake = maxf(_camera_shake, 5.5)
	_camera_punch = maxf(_camera_punch, 0.07)
	_add_effect(target_position, COLOR_GOLD, &"hit", 0.45)


func _damage_boss_part(part_id: StringName, damage: float) -> void:
	if part_id == &"core":
		_boss_health = maxf(0.0, _boss_health - damage)
		if _boss_health <= 0.0:
			_defeat_boss()
		return
	if not _part_is_alive(part_id):
		return
	var previous_health := float(_part_health.get(part_id, 0.0))
	_part_health[part_id] = maxf(0.0, previous_health - damage)
	if float(_part_health[part_id]) <= 0.0:
		_break_boss_part(part_id)


func _break_boss_part(part_id: StringName) -> void:
	_slow_motion_timer = 0.48
	_hit_stop_timer = 0.09
	_camera_shake = 12.0
	_camera_punch = 0.14
	_add_effect(_part_position(part_id), COLOR_CORE, &"break", 1.0)
	_set_feedback("%s SHATTERED" % _part_display_name(part_id), 1.2)
	_selected_part = &"core"


func _update_boss(delta: float) -> void:
	if _boss_state == &"DEAD":
		return
	if _boss_state == &"IDLE" or _boss_state == &"RECOVERY":
		_boss_position = _boss_position.move_toward(_boss_home, 80.0 * delta)
	_boss_state_timer -= delta
	match _boss_state:
		&"IDLE":
			if _boss_state_timer <= 0.0:
				_begin_next_pattern()
		&"TELEGRAPH":
			if _boss_state_timer <= 0.0:
				_begin_active_pattern()
		&"ACTIVE":
			_update_active_pattern(delta)
		&"RECOVERY":
			if _boss_state_timer <= 0.0:
				_boss_state = &"IDLE"
				_boss_state_timer = 0.34 if _has_broken_part() else 0.52


func _begin_next_pattern() -> void:
	var patterns: Array[StringName] = []
	if _part_is_alive(&"left_arm"):
		patterns.append(&"SWEEP")
	if _part_is_alive(&"right_arm"):
		patterns.append(&"SLAM")
	patterns.append(&"CHARGE")
	_boss_pattern = patterns[_boss_pattern_index % patterns.size()]
	_boss_pattern_index += 1
	_boss_state = &"TELEGRAPH"
	_boss_attack_resolved = false
	_boss_locked_direction = (_player_position - _boss_position).normalized()
	match _boss_pattern:
		&"SWEEP":
			_boss_state_timer = 0.78
		&"SLAM":
			_boss_state_timer = 0.96
		&"CHARGE":
			_boss_state_timer = 0.70


func _begin_active_pattern() -> void:
	_boss_state = &"ACTIVE"
	_boss_attack_resolved = false
	match _boss_pattern:
		&"SWEEP":
			_boss_state_timer = 0.24
		&"SLAM":
			_boss_state_timer = 0.22
		&"CHARGE":
			_boss_state_timer = 0.58


func _update_active_pattern(delta: float) -> void:
	_boss_state_timer -= delta
	if _boss_pattern == &"CHARGE":
		_boss_position += _boss_locked_direction * 650.0 * delta
		_boss_position.x = clampf(_boss_position.x, 145.0, WORLD_RECT.end.x - 145.0)
		_boss_position.y = clampf(_boss_position.y, 145.0, 800.0)
		if _boss_position.distance_to(_player_position) <= BOSS_RADIUS + PLAYER_RADIUS + 10.0:
			_try_boss_hit(29.0)
	elif not _boss_attack_resolved:
		_boss_attack_resolved = true
		_resolve_boss_strike()
	if _boss_state_timer <= 0.0:
		_boss_state = &"RECOVERY"
		_boss_state_timer = 0.86 if _boss_pattern == &"CHARGE" else 0.72


func _resolve_boss_strike() -> void:
	var relative := _player_position - _boss_position
	if _boss_pattern == &"SWEEP":
		var angle_difference := absf(wrapf(relative.angle() - _boss_locked_direction.angle(), -PI, PI))
		if relative.length() <= 345.0 and angle_difference <= deg_to_rad(112.0):
			_try_boss_hit(24.0)
		_add_effect(_boss_position, COLOR_DANGER, &"sweep", 0.48)
	elif _boss_pattern == &"SLAM":
		if relative.length() <= 310.0:
			_try_boss_hit(32.0)
		_add_effect(_boss_position, COLOR_DANGER, &"slam", 0.62)


func _try_boss_hit(damage: float) -> void:
	if _dodge_timer > 0.0:
		var dodge_elapsed := DODGE_DURATION - _dodge_timer
		if dodge_elapsed <= 0.21 and not _perfect_dodge_used:
			_perfect_dodge_used = true
			_perfect_dodge()
		return
	if _player_invulnerable > 0.0:
		return
	_player_health = maxf(0.0, _player_health - damage)
	_player_invulnerable = 0.72
	_camera_shake = 14.0
	_hit_stop_timer = 0.075
	_add_effect(_player_position, COLOR_DANGER, &"hurt", 0.65)
	_player_position += (_player_position - _boss_position).normalized() * 46.0
	_set_feedback("HIT", 0.55)
	if _player_health <= 0.0:
		_player_dead = true
		_slow_motion_timer = 0.55
		_feedback_text = "FALLEN"
		_feedback_timer = 99.0


func _perfect_dodge() -> void:
	_player_invulnerable = maxf(_player_invulnerable, 0.34)
	_counter_bonus = true
	_slow_motion_timer = 0.34
	_camera_punch = 0.10
	_camera_shake = 4.0
	_add_effect(_player_position, COLOR_DODGE, &"perfect", 0.78)
	_set_feedback("PERFECT DODGE", 0.85)


func _defeat_boss() -> void:
	_boss_state = &"DEAD"
	_victory = true
	_slow_motion_timer = 0.65
	_hit_stop_timer = 0.12
	_camera_shake = 18.0
	_camera_punch = 0.18
	_add_effect(_boss_position, COLOR_CORE, &"break", 1.45)
	_feedback_text = "COLOSSUS FELLED"
	_feedback_timer = 99.0


func _update_camera(delta: float) -> void:
	var target_part_position := _part_position(_selected_part)
	var distance_to_boss := _player_position.distance_to(_boss_position)
	var distance_ratio := clampf((distance_to_boss - 270.0) / 720.0, 0.0, 1.0)
	var target_zoom := lerpf(1.11, 0.67, distance_ratio)
	if _boss_state == &"TELEGRAPH" and (_boss_pattern == &"SLAM" or _boss_pattern == &"CHARGE"):
		target_zoom = minf(target_zoom, 0.73)
	if _victory:
		target_zoom = 0.82
	else:
		target_zoom += _camera_punch
	var target_center := _player_position.lerp(target_part_position, 0.44)
	if distance_ratio > 0.72:
		target_center = _player_position.lerp(_boss_position, 0.50)
	var camera_response := 1.0 - exp(-4.8 * delta)
	_camera_zoom = lerpf(_camera_zoom, target_zoom, camera_response)
	_camera_center = _camera_center.lerp(target_center, 1.0 - exp(-4.2 * delta))
	_clamp_camera()


func _clamp_camera() -> void:
	var half_view := size / maxf(_camera_zoom * 2.0, 0.001)
	_camera_center.x = clampf(_camera_center.x, half_view.x, WORLD_RECT.end.x - half_view.x) if half_view.x < WORLD_RECT.size.x * 0.5 else WORLD_RECT.get_center().x
	_camera_center.y = clampf(_camera_center.y, half_view.y, WORLD_RECT.end.y - half_view.y) if half_view.y < WORLD_RECT.size.y * 0.5 else WORLD_RECT.get_center().y


func _part_position(part_id: StringName) -> Vector2:
	match part_id:
		&"left_arm": return _boss_position + Vector2(-132.0, 24.0)
		&"right_arm": return _boss_position + Vector2(132.0, 24.0)
		_: return _boss_position + Vector2(0.0, -12.0)


func _part_is_alive(part_id: StringName) -> bool:
	return float(_part_health.get(part_id, 0.0)) > 0.0


func _has_broken_part() -> bool:
	return not _part_is_alive(&"left_arm") or not _part_is_alive(&"right_arm")


func _part_display_name(part_id: StringName) -> String:
	match part_id:
		&"left_arm": return "SWEEP ARM"
		&"right_arm": return "SLAM ARM"
		_: return "CORE"


func _set_feedback(text: String, duration: float) -> void:
	_feedback_text = text
	_feedback_timer = duration


func _add_effect(position: Vector2, color: Color, kind: StringName, duration: float) -> void:
	_effects.append({"position": position, "color": color, "kind": kind, "time": 0.0, "duration": duration})


func _update_effects(delta: float) -> void:
	for index: int in range(_effects.size() - 1, -1, -1):
		var effect := _effects[index]
		effect["time"] = float(effect["time"]) + delta
		if float(effect["time"]) >= float(effect["duration"]):
			_effects.remove_at(index)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _player_dead or _victory:
			_restart_battle()
			return
		if event.position.distance_to(_dodge_center) <= _dodge_radius * 1.25:
			_try_dodge()
			return
		if _try_select_part(event.position):
			return
		if event.position.x <= size.x * 0.66 and event.position.y >= size.y * 0.50 and _move_touch_index < 0:
			_move_touch_index = event.index
			_update_pointer_move(event.position)
	else:
		if event.index == _move_touch_index:
			_move_touch_index = -1
			_touch_move_input = Vector2.ZERO


func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	if event.index == _move_touch_index:
		_update_pointer_move(event.position)


func _handle_pointer_press(position: Vector2) -> void:
	if _player_dead or _victory:
		_restart_battle()
		return
	if position.distance_to(_dodge_center) <= _dodge_radius * 1.25:
		_try_dodge()
		return
	if _try_select_part(position):
		return
	if position.x <= size.x * 0.66 and position.y >= size.y * 0.50:
		_mouse_move_active = true
		_update_pointer_move(position)


func _update_pointer_move(position: Vector2) -> void:
	var delta := position - _joystick_center
	_touch_move_input = delta.limit_length(_joystick_radius) / _joystick_radius


func _try_select_part(screen_position: Vector2) -> bool:
	var candidates: Array[StringName] = [&"core"]
	if _part_is_alive(&"left_arm"):
		candidates.append(&"left_arm")
	if _part_is_alive(&"right_arm"):
		candidates.append(&"right_arm")
	var best_part: StringName = &""
	var best_distance := 78.0
	for part_id: StringName in candidates:
		var part_screen := _world_to_screen(_part_position(part_id))
		var distance := part_screen.distance_to(screen_position)
		if distance < best_distance:
			best_distance = distance
			best_part = part_id
	if best_part == &"":
		return false
	_selected_part = best_part
	_set_feedback("TARGET: %s" % _part_display_name(best_part), 0.65)
	_camera_punch = 0.04
	return true


func _camera_screen_center() -> Vector2:
	return size * 0.5 + Vector2(0.0, 34.0)


func _world_to_screen(world_position: Vector2) -> Vector2:
	return (world_position - _camera_center) * _camera_zoom + _camera_screen_center()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_VOID)
	var shake_offset := Vector2(sin(_elapsed * 71.0), cos(_elapsed * 83.0)) * _camera_shake
	var origin := _camera_screen_center() - _camera_center * _camera_zoom + shake_offset
	draw_set_transform(origin, 0.0, Vector2.ONE * _camera_zoom)
	_draw_arena()
	_draw_boss()
	_draw_player()
	_draw_world_effects()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hud()
	_draw_controls()
	_draw_screen_feedback()


func _draw_arena() -> void:
	draw_rect(WORLD_RECT, COLOR_ARENA)
	var tile := 100.0
	for row: int in range(15):
		for column: int in range(9):
			if (row + column) % 2 == 0:
				draw_rect(Rect2(column * tile, row * tile, tile, tile), COLOR_ARENA_ALT)
	for rune_index: int in range(12):
		var rune_position := Vector2(95.0 + float((rune_index * 197) % 650), 120.0 + float((rune_index * 311) % 1240))
		draw_arc(rune_position, 26.0 + float(rune_index % 3) * 8.0, 0.0, TAU, 20, Color("68819a44"), 3.0)
	draw_rect(WORLD_RECT.grow(-18.0), COLOR_LINE, false, 10.0)


func _draw_boss() -> void:
	if _boss_state == &"DEAD":
		_draw_boss_body(Color("4a4146"), 0.82)
		return
	_draw_boss_telegraph()
	_draw_boss_body(COLOR_BOSS, 1.0)


func _draw_boss_body(body_color: Color, alpha_scale: float) -> void:
	var torso_color := body_color
	torso_color.a *= alpha_scale
	var left_position := _part_position(&"left_arm")
	var right_position := _part_position(&"right_arm")
	if _part_is_alive(&"left_arm"):
		draw_circle(left_position, PART_RADIUS, torso_color.darkened(0.06))
		draw_circle(left_position + Vector2(-22.0, 28.0), 31.0, torso_color.darkened(0.12))
	else:
		draw_circle(left_position, 30.0, COLOR_BOSS_DARK)
		draw_line(left_position + Vector2(-22.0, -18.0), left_position + Vector2(21.0, 24.0), COLOR_DANGER, 8.0)
	if _part_is_alive(&"right_arm"):
		draw_circle(right_position, PART_RADIUS, torso_color.darkened(0.06))
		draw_circle(right_position + Vector2(22.0, 28.0), 31.0, torso_color.darkened(0.12))
	else:
		draw_circle(right_position, 30.0, COLOR_BOSS_DARK)
		draw_line(right_position + Vector2(-21.0, 24.0), right_position + Vector2(22.0, -18.0), COLOR_DANGER, 8.0)

	draw_circle(_boss_position, BOSS_RADIUS, torso_color)
	draw_circle(_boss_position + Vector2(0.0, -48.0), 63.0, torso_color.lightened(0.06))
	draw_circle(_boss_position + Vector2(-24.0, -62.0), 8.0, Color("f4d6a0"))
	draw_circle(_boss_position + Vector2(24.0, -62.0), 8.0, Color("f4d6a0"))
	draw_circle(_part_position(&"core"), 35.0 + sin(_elapsed * 4.0) * 3.0, COLOR_CORE)
	draw_arc(_part_position(&"core"), 47.0, 0.0, TAU, 32, Color("ffd49c88"), 6.0)

	var target_position := _part_position(_selected_part)
	draw_arc(target_position, PART_RADIUS + 17.0 + sin(_elapsed * 6.0) * 3.0, 0.0, TAU, 40, COLOR_GOLD, 5.0)
	_draw_world_text("TARGET", target_position + Vector2(0.0, -82.0), 18, COLOR_GOLD)


func _draw_boss_telegraph() -> void:
	if _boss_state != &"TELEGRAPH" and _boss_state != &"ACTIVE":
		return
	var active := _boss_state == &"ACTIVE"
	var danger_color := COLOR_DANGER
	danger_color.a = 0.62 if active else 0.24 + sin(_elapsed * 12.0) * 0.08
	if _boss_pattern == &"SWEEP":
		var start_angle := _boss_locked_direction.angle() - deg_to_rad(112.0)
		var end_angle := _boss_locked_direction.angle() + deg_to_rad(112.0)
		draw_arc(_boss_position, 330.0, start_angle, end_angle, 48, danger_color, 18.0 if active else 7.0)
		draw_line(_part_position(&"left_arm"), _part_position(&"left_arm") + _boss_locked_direction.rotated(-1.25) * 96.0, danger_color, 18.0)
	elif _boss_pattern == &"SLAM":
		var telegraph_ratio := 1.0 - clampf(_boss_state_timer / 0.96, 0.0, 1.0) if not active else 1.0
		draw_circle(_boss_position, 310.0 * telegraph_ratio, Color(danger_color, danger_color.a * 0.28))
		draw_arc(_boss_position, 310.0, 0.0, TAU, 56, danger_color, 9.0 if active else 5.0)
	elif _boss_pattern == &"CHARGE":
		var perpendicular := _boss_locked_direction.orthogonal() * 92.0
		var line_end := _boss_position + _boss_locked_direction * 660.0
		draw_line(_boss_position + perpendicular, line_end + perpendicular, danger_color, 7.0)
		draw_line(_boss_position - perpendicular, line_end - perpendicular, danger_color, 7.0)


func _draw_player() -> void:
	var blink := _player_invulnerable > 0.0 and int(_elapsed * 18.0) % 2 == 0
	if blink:
		return
	var forward := _attack_facing if _attack_facing.length_squared() > 0.01 else Vector2.UP
	var right := forward.orthogonal()
	var cloak_points := PackedVector2Array([
		_player_position - forward * 23.0,
		_player_position - forward * 10.0 + right * 25.0,
		_player_position - forward * 10.0 - right * 25.0,
	])
	draw_colored_polygon(cloak_points, COLOR_CAPE)
	draw_circle(_player_position, PLAYER_RADIUS, COLOR_PLAYER)
	draw_circle(_player_position + forward * 8.0, 12.0, Color("496074"))
	draw_line(_player_position + right * 17.0, _player_position + right * 17.0 + forward * 42.0, COLOR_STEEL, 8.0, true)
	if _dodge_timer > 0.0:
		draw_arc(_player_position, 38.0, 0.0, TAU, 32, Color("72e4c0aa"), 5.0)
	if _attack_elapsed >= 0.0:
		var attack_ratio := clampf(_attack_elapsed / ATTACK_DURATION, 0.0, 1.0)
		var start_angle := forward.angle() - 1.3 + attack_ratio * 0.45
		draw_arc(_player_position, 63.0, start_angle, start_angle + 1.7, 24, COLOR_GOLD, 10.0 * sin(attack_ratio * PI), true)


func _draw_world_effects() -> void:
	for effect: Dictionary in _effects:
		var progress := clampf(float(effect["time"]) / float(effect["duration"]), 0.0, 1.0)
		var fade := 1.0 - progress
		var position := effect["position"] as Vector2
		var color := effect["color"] as Color
		var kind := effect["kind"] as StringName
		color.a = fade
		match kind:
			&"dodge":
				draw_arc(position, 28.0 + progress * 72.0, 0.0, TAU, 32, color, 7.0 * fade + 1.0)
			&"perfect":
				draw_arc(position, 35.0 + progress * 150.0, 0.0, TAU, 48, color, 12.0 * fade + 1.0)
				for ray_index: int in range(10):
					var direction := Vector2.from_angle(TAU * float(ray_index) / 10.0)
					draw_line(position + direction * 48.0, position + direction * (80.0 + 55.0 * progress), color, 5.0)
			&"hit", &"hurt":
				for spark_index: int in range(8):
					var direction := Vector2.from_angle(TAU * float(spark_index) / 8.0 + 0.2)
					draw_line(position + direction * 8.0, position + direction * (26.0 + progress * 58.0), color, 6.0 * fade + 1.0)
			&"break":
				draw_arc(position, 45.0 + progress * 220.0, 0.0, TAU, 56, color, 16.0 * fade + 1.0)
				for shard_index: int in range(14):
					var direction := Vector2.from_angle(TAU * float(shard_index) / 14.0)
					draw_circle(position + direction * progress * (90.0 + float(shard_index % 3) * 35.0), 8.0 * fade + 2.0, color)
			&"slam":
				draw_arc(position, 40.0 + progress * 350.0, 0.0, TAU, 64, color, 18.0 * fade + 2.0)
			&"sweep":
				draw_arc(position, 180.0 + progress * 200.0, _boss_locked_direction.angle() - 1.8, _boss_locked_direction.angle() + 1.8, 48, color, 20.0 * fade + 2.0)


func _draw_hud() -> void:
	var boss_bar_rect := Rect2(62.0, 56.0, size.x - 124.0, 28.0)
	draw_rect(boss_bar_rect, Color("151c28dd"))
	draw_rect(Rect2(boss_bar_rect.position + Vector2(4.0, 4.0), Vector2((boss_bar_rect.size.x - 8.0) * (_boss_health / 220.0), boss_bar_rect.size.y - 8.0)), COLOR_CORE)
	_draw_screen_text("THE HOLLOW COLOSSUS", Vector2(size.x * 0.5, 39.0), 22, Color("f3e8d5"))
	_draw_screen_text("TARGET  %s" % _part_display_name(_selected_part), Vector2(size.x * 0.5, 108.0), 16, COLOR_GOLD)

	var player_bar_width := minf(260.0, size.x * 0.40)
	draw_rect(Rect2(28.0, 126.0, player_bar_width, 18.0), Color("111824cc"))
	draw_rect(Rect2(31.0, 129.0, (player_bar_width - 6.0) * (_player_health / 100.0), 12.0), Color("d86666"))
	draw_rect(Rect2(28.0, 151.0, player_bar_width, 13.0), Color("111824cc"))
	draw_rect(Rect2(31.0, 154.0, (player_bar_width - 6.0) * (_player_stamina / 100.0), 7.0), COLOR_DODGE)
	_draw_screen_text("HP", Vector2(18.0, 136.0), 12, Color("f6d8d8"), HORIZONTAL_ALIGNMENT_LEFT)

	if _boss_state == &"RECOVERY" and not _victory:
		_draw_screen_text("OPENING", Vector2(size.x * 0.5, 178.0), 18, COLOR_DODGE)


func _draw_controls() -> void:
	var base_color := Color("10182777")
	var border_color := Color("dbe9f144")
	draw_circle(_joystick_center, _joystick_radius, base_color)
	draw_arc(_joystick_center, _joystick_radius, 0.0, TAU, 40, border_color, 4.0)
	var knob_position := _joystick_center + _touch_move_input * _joystick_radius
	draw_circle(knob_position, 34.0, Color("dbe9f188"))

	var dodge_ready := _player_stamina >= DODGE_COST and _dodge_timer <= 0.0
	var dodge_color := COLOR_DODGE if dodge_ready else Color("536a72")
	draw_circle(_dodge_center, _dodge_radius, Color(dodge_color, 0.76))
	draw_arc(_dodge_center, _dodge_radius, 0.0, TAU, 48, Color("e7fff5aa"), 5.0)
	_draw_screen_text("DODGE", _dodge_center, 18, Color("10252a"))
	_draw_screen_text("AUTO ATTACK", Vector2(size.x * 0.5, size.y - 50.0), 13, Color("dbe9f188"))


func _draw_screen_feedback() -> void:
	if _tutorial_timer > 0.0 and not _player_dead and not _victory:
		var panel_rect := Rect2(42.0, size.y * 0.64, size.x - 84.0, 88.0)
		draw_rect(panel_rect, Color("101827cc"))
		draw_rect(panel_rect, Color("dbe9f144"), false, 2.0)
		_draw_screen_text("DRAG TO MOVE  ·  ATTACKS ARE AUTOMATIC", Vector2(size.x * 0.5, panel_rect.position.y + 30.0), 16, Color("f3e8d5"))
		_draw_screen_text("TAP A BODY PART TO TARGET IT", Vector2(size.x * 0.5, panel_rect.position.y + 61.0), 14, COLOR_GOLD)
	if _feedback_timer > 0.0:
		_draw_screen_text(_feedback_text, Vector2(size.x * 0.5, size.y * 0.31), 29, COLOR_GOLD)
	if _player_dead or _victory:
		draw_rect(Rect2(Vector2.ZERO, size), Color("080c14bb"))
		_draw_screen_text("COLOSSUS FELLED" if _victory else "YOU FELL", Vector2(size.x * 0.5, size.y * 0.43), 42, COLOR_GOLD if _victory else Color("ef8b84"))
		_draw_screen_text("TIME  %.1fs" % _battle_time, Vector2(size.x * 0.5, size.y * 0.49), 20, Color("e5edf2"))
		_draw_screen_text("TAP TO RETRY", Vector2(size.x * 0.5, size.y * 0.57), 22, COLOR_DODGE)


func _draw_world_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center - Vector2(width * 0.5, -font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_screen_text(
	text: String,
	center: Vector2,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
) -> void:
	var font := ThemeDB.fallback_font
	if alignment == HORIZONTAL_ALIGNMENT_LEFT:
		draw_string(font, center + Vector2(0.0, font_size * 0.35), text, alignment, -1, font_size, color)
		return
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center - Vector2(width * 0.5, -font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
