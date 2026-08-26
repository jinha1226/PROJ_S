class_name BackviewDuelView
extends Control

const ARENA_TEXTURE := preload("res://assets/duel/arena_courtyard.png")
const PLAYER_TEXTURE := preload("res://assets/duel/player_back.png")
const BOSS_TEXTURE := preload("res://assets/duel/warden_front.png")

const MIN_DEPTH := 0.27
const MAX_DEPTH := 0.92
const ATTACK_DEPTH := 0.53
const MOVE_SPEED_X := 1.14
const MOVE_SPEED_DEPTH := 0.52
const DODGE_DURATION := 0.32
const DODGE_COOLDOWN := 0.62
const ATTACK_DURATION := 0.46
const ATTACK_HIT_TIME := 0.20
const DEFLECT_DURATION := 0.42
const PERFECT_DEFLECT_WINDOW := 0.17

const INK := Color("101722")
const PAPER := Color("e8edf0")
const AMBER := Color("e9aa55")
const POSTURE := Color("e7bb68")
const PLAYER_TEAL := Color("62d7c0")
const HEALTH_RED := Color("cf5f59")
const DANGER := Color("ed665c")
const MUTED := Color("6d7d87")

var _elapsed: float = 0.0
var _battle_time: float = 0.0
var _player_x: float = 0.0
var _player_depth: float = 0.78
var _player_health: float = 100.0
var _player_posture: float = 0.0
var _player_posture_delay: float = 0.0
var _move_input := Vector2.ZERO
var _touch_move_input := Vector2.ZERO
var _player_motion := Vector2.ZERO
var _player_stagger: float = 0.0

var _attack_timer: float = 0.0
var _attack_elapsed: float = 0.0
var _attack_hit_done: bool = false
var _deflect_timer: float = 0.0
var _deflect_elapsed: float = 0.0
var _action_cooldown: float = 0.0
var _dodge_timer: float = 0.0
var _dodge_cooldown: float = 0.0
var _dodge_direction := Vector2(0.0, 1.0)
var _dodge_invulnerable: float = 0.0
var _dodge_perfect_used: bool = false

var _boss_health: float = 100.0
var _boss_posture: float = 0.0
var _boss_posture_delay: float = 0.0
var _boss_state: StringName = &"IDLE"
var _boss_pattern: StringName = &""
var _boss_timer: float = 0.85
var _boss_pattern_index: int = 0
var _boss_attack_resolved: bool = false
var _boss_locked_x: float = 0.0
var _telegraph_total: float = 1.0
var _active_total: float = 0.3
var _combo_remaining: int = 0
var _boss_recoil: float = 0.0

var _focus_alpha: float = 0.0
var _hit_stop: float = 0.0
var _camera_shake: float = 0.0
var _camera_punch: float = 0.0
var _feedback_text: String = "CLOSE THE DISTANCE"
var _feedback_timer: float = 1.8
var _tutorial_timer: float = 7.0
var _player_dead: bool = false
var _victory: bool = false
var _effects: Array[Dictionary] = []

var _joystick_center := Vector2.ZERO
var _attack_center := Vector2.ZERO
var _deflect_center := Vector2.ZERO
var _dodge_center := Vector2.ZERO
var _joystick_radius: float = 78.0
var _move_touch_index: int = -1
var _mouse_move_active: bool = false
var _last_touch_msec: int = -10000


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_restart_battle()


func _process(delta: float) -> void:
	var frame_delta := minf(delta, 0.04)
	_elapsed += frame_delta
	_battle_time += frame_delta if not _player_dead and not _victory else 0.0
	_feedback_timer = maxf(0.0, _feedback_timer - frame_delta)
	_tutorial_timer = maxf(0.0, _tutorial_timer - frame_delta)
	_camera_shake = maxf(0.0, _camera_shake - frame_delta * 13.0)
	_camera_punch = maxf(0.0, _camera_punch - frame_delta * 4.8)
	_boss_recoil = maxf(0.0, _boss_recoil - frame_delta * 4.0)
	_update_layout()
	_update_input_vector()
	_update_effects(frame_delta)

	var focus_target := 1.0 if _boss_state == &"TELEGRAPH" else 0.0
	_focus_alpha = move_toward(_focus_alpha, focus_target, frame_delta * 4.8)
	if _hit_stop > 0.0:
		_hit_stop = maxf(0.0, _hit_stop - frame_delta)
		queue_redraw()
		return

	var world_delta := frame_delta * lerpf(1.0, 0.43, _focus_alpha)
	if not _player_dead and not _victory:
		_update_player(world_delta)
		_update_player_actions(world_delta)
		_update_boss(world_delta)
		_update_posture(world_delta)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_J: _try_attack()
			KEY_K, KEY_F: _try_deflect()
			KEY_SPACE: _try_dodge()
			KEY_R:
				if _player_dead or _victory:
					_restart_battle()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_last_touch_msec = Time.get_ticks_msec()
		_handle_touch(event)
		accept_event()
		return
	if event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if event.index == _move_touch_index:
			_update_pointer_move(event.position)
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
			_touch_move_input = Vector2.ZERO
		accept_event()
		return
	if event is InputEventMouseMotion and _mouse_move_active:
		_update_pointer_move(event.position)
		accept_event()


func _restart_battle() -> void:
	_player_x = 0.0
	_player_depth = 0.78
	_player_health = 100.0
	_player_posture = 0.0
	_player_posture_delay = 0.0
	_move_input = Vector2.ZERO
	_touch_move_input = Vector2.ZERO
	_player_motion = Vector2.ZERO
	_player_stagger = 0.0
	_attack_timer = 0.0
	_attack_elapsed = 0.0
	_attack_hit_done = false
	_deflect_timer = 0.0
	_deflect_elapsed = 0.0
	_action_cooldown = 0.0
	_dodge_timer = 0.0
	_dodge_cooldown = 0.0
	_dodge_invulnerable = 0.0
	_dodge_perfect_used = false
	_boss_health = 100.0
	_boss_posture = 0.0
	_boss_posture_delay = 0.0
	_boss_state = &"IDLE"
	_boss_pattern = &""
	_boss_timer = 0.85
	_boss_pattern_index = 0
	_boss_attack_resolved = false
	_boss_locked_x = 0.0
	_combo_remaining = 0
	_boss_recoil = 0.0
	_focus_alpha = 0.0
	_hit_stop = 0.0
	_camera_shake = 0.0
	_camera_punch = 0.0
	_feedback_text = "CLOSE THE DISTANCE"
	_feedback_timer = 1.8
	_tutorial_timer = 7.0
	_battle_time = 0.0
	_player_dead = false
	_victory = false
	_effects.clear()
	queue_redraw()


func _update_layout() -> void:
	_joystick_center = Vector2(122.0, size.y - 132.0)
	_attack_center = Vector2(size.x - 102.0, size.y - 122.0)
	_deflect_center = Vector2(size.x - 202.0, size.y - 232.0)
	_dodge_center = Vector2(size.x - 302.0, size.y - 120.0)


func _update_input_vector() -> void:
	var keyboard := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)
	_move_input = keyboard.normalized() if keyboard.length_squared() > 0.01 else _touch_move_input


func _update_player(delta: float) -> void:
	_action_cooldown = maxf(0.0, _action_cooldown - delta)
	_dodge_cooldown = maxf(0.0, _dodge_cooldown - delta)
	_dodge_invulnerable = maxf(0.0, _dodge_invulnerable - delta)
	_player_stagger = maxf(0.0, _player_stagger - delta)
	_player_motion = _move_input
	if _player_stagger > 0.0:
		_player_motion = Vector2.ZERO
		return

	if _dodge_timer > 0.0:
		_dodge_timer = maxf(0.0, _dodge_timer - delta)
		_player_x += _dodge_direction.x * 2.15 * delta
		_player_depth += _dodge_direction.y * 0.94 * delta
	else:
		var action_scale := 0.38 if _attack_timer > 0.0 or _deflect_timer > 0.0 else 1.0
		_player_x += _move_input.x * MOVE_SPEED_X * action_scale * delta
		_player_depth += _move_input.y * MOVE_SPEED_DEPTH * action_scale * delta
	_player_x = clampf(_player_x, -1.0, 1.0)
	_player_depth = clampf(_player_depth, MIN_DEPTH, MAX_DEPTH)


func _update_player_actions(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer = maxf(0.0, _attack_timer - delta)
		_attack_elapsed += delta
		if not _attack_hit_done and _attack_elapsed >= ATTACK_HIT_TIME:
			_attack_hit_done = true
			_resolve_player_attack()
	if _deflect_timer > 0.0:
		_deflect_timer = maxf(0.0, _deflect_timer - delta)
		_deflect_elapsed += delta


func _try_attack() -> void:
	if not _can_start_action():
		return
	_attack_timer = ATTACK_DURATION
	_attack_elapsed = 0.0
	_attack_hit_done = false
	_action_cooldown = 0.10


func _try_deflect() -> void:
	if not _can_start_action():
		return
	_deflect_timer = DEFLECT_DURATION
	_deflect_elapsed = 0.0
	_action_cooldown = 0.08


func _try_dodge() -> void:
	if _player_dead or _victory or _player_stagger > 0.0 or _dodge_timer > 0.0 or _dodge_cooldown > 0.0:
		return
	_dodge_direction = _move_input.normalized()
	if _dodge_direction.length_squared() < 0.01:
		_dodge_direction = Vector2(0.0, 1.0)
	_dodge_timer = DODGE_DURATION
	_dodge_cooldown = DODGE_COOLDOWN
	_dodge_invulnerable = 0.25
	_dodge_perfect_used = false
	_attack_timer = 0.0
	_deflect_timer = 0.0
	_add_effect(&"dodge", _player_screen_position(), PLAYER_TEAL, 0.42)


func _can_start_action() -> bool:
	return not _player_dead and not _victory and _player_stagger <= 0.0 and _dodge_timer <= 0.0 and _attack_timer <= 0.0 and _deflect_timer <= 0.0 and _action_cooldown <= 0.0


func _resolve_player_attack() -> void:
	if _boss_state == &"DEAD":
		return
	if _player_depth > ATTACK_DEPTH or absf(_player_x) > 0.58:
		_set_feedback("OUT OF RANGE", 0.55)
		return
	var contact := _contact_position()
	if _boss_state == &"BROKEN":
		_resolve_deathblow()
		return
	var health_damage := 5.0
	var posture_damage := 13.0
	if _boss_state == &"RECOVERY":
		health_damage = 7.0
		posture_damage = 19.0
	_boss_health = maxf(0.0, _boss_health - health_damage)
	_add_boss_posture(posture_damage)
	_boss_posture_delay = 1.25
	_boss_recoil = 0.34
	_hit_stop = 0.045
	_camera_shake = 0.34
	_camera_punch = 0.045
	_add_effect(&"hit", contact, AMBER, 0.38)
	_set_feedback("PRESSURE", 0.45)
	if _boss_health <= 0.0:
		_defeat_boss()


func _resolve_deathblow() -> void:
	_boss_health = maxf(0.0, _boss_health - 34.0)
	_boss_posture = 0.0
	_boss_posture_delay = 1.5
	_hit_stop = 0.13
	_camera_shake = 0.82
	_camera_punch = 0.13
	_add_effect(&"deathblow", _contact_position(), DANGER, 0.90)
	_set_feedback("DEATHBLOW", 1.0)
	if _boss_health <= 0.0:
		_defeat_boss()
	else:
		_boss_state = &"RECOVERY"
		_boss_timer = 1.0


func _update_boss(delta: float) -> void:
	if _boss_state == &"DEAD":
		return
	match _boss_state:
		&"IDLE":
			_boss_timer -= delta
			if _boss_timer <= 0.0:
				_begin_pattern()
		&"TELEGRAPH":
			_boss_timer -= delta
			if _boss_timer <= 0.0:
				_begin_active_pattern()
		&"ACTIVE":
			_boss_timer -= delta
			if not _boss_attack_resolved and _boss_timer <= _active_total * 0.52:
				_boss_attack_resolved = true
				_resolve_boss_strike()
			if _boss_timer <= 0.0:
				_finish_active_pattern()
		&"RECOVERY":
			_boss_timer -= delta
			if _boss_timer <= 0.0:
				_boss_state = &"IDLE"
				_boss_timer = 0.48
		&"BROKEN":
			_boss_timer -= delta
			if _boss_timer <= 0.0:
				_boss_posture = 48.0
				_boss_state = &"RECOVERY"
				_boss_timer = 0.72


func _begin_pattern() -> void:
	var patterns: Array[StringName] = [&"SLASH", &"THRUST", &"DOUBLE", &"SWEEP"]
	_boss_pattern = patterns[_boss_pattern_index % patterns.size()]
	_boss_pattern_index += 1
	_combo_remaining = 2 if _boss_pattern == &"DOUBLE" else 0
	_boss_locked_x = _player_x
	var duration := 0.82
	match _boss_pattern:
		&"THRUST": duration = 0.98
		&"DOUBLE": duration = 0.66
		&"SWEEP": duration = 1.04
	_begin_telegraph(duration)


func _begin_telegraph(duration: float) -> void:
	_boss_state = &"TELEGRAPH"
	_boss_timer = duration
	_telegraph_total = duration
	_boss_attack_resolved = false


func _begin_active_pattern() -> void:
	_boss_state = &"ACTIVE"
	_active_total = 0.30
	if _boss_pattern == &"THRUST":
		_active_total = 0.34
	elif _boss_pattern == &"SWEEP":
		_active_total = 0.36
	elif _boss_pattern == &"DOUBLE":
		_active_total = 0.26
	_boss_timer = _active_total
	_boss_attack_resolved = false


func _finish_active_pattern() -> void:
	if _boss_pattern == &"DOUBLE" and _combo_remaining > 1:
		_combo_remaining -= 1
		_boss_locked_x = _player_x
		_begin_telegraph(0.40)
		return
	_boss_state = &"RECOVERY"
	_boss_timer = 0.72 if _boss_pattern == &"SWEEP" else 0.58


func _resolve_boss_strike() -> void:
	var in_danger := false
	var parryable := true
	var damage := 22.0
	match _boss_pattern:
		&"SLASH":
			in_danger = _player_depth <= 0.64 and absf(_player_x) <= 0.76
		&"THRUST":
			in_danger = _player_depth <= 0.78 and absf(_player_x - _boss_locked_x) <= 0.25
			damage = 28.0
		&"DOUBLE":
			in_danger = _player_depth <= 0.67 and absf(_player_x) <= 0.82
			damage = 18.0
		&"SWEEP":
			in_danger = _player_depth <= 0.57
			parryable = false
			damage = 31.0
	_add_effect(&"boss_strike", _contact_position(), DANGER, 0.44)
	if not in_danger:
		_set_feedback("POSITION EVADE", 0.58)
		return
	_receive_boss_strike(damage, parryable)


func _receive_boss_strike(damage: float, parryable: bool) -> void:
	if _dodge_invulnerable > 0.0:
		if not _dodge_perfect_used:
			_dodge_perfect_used = true
			_add_boss_posture(7.0)
			_boss_posture_delay = 0.8
			_set_feedback("PERFECT EVADE", 0.68)
			_add_effect(&"perfect", _player_screen_position(), PLAYER_TEAL, 0.56)
		return
	if _deflect_timer > 0.0 and parryable:
		if _deflect_elapsed <= PERFECT_DEFLECT_WINDOW:
			_add_boss_posture(22.0 if _boss_pattern != &"DOUBLE" else 17.0)
			_boss_posture_delay = 1.25
			_player_posture = maxf(0.0, _player_posture - 8.0)
			_hit_stop = 0.075
			_camera_shake = 0.55
			_camera_punch = 0.075
			_set_feedback("PERFECT DEFLECT", 0.72)
			_add_effect(&"deflect", _contact_position(), Color("fff0b5"), 0.52)
		else:
			_add_player_posture(21.0)
			_set_feedback("GUARD", 0.44)
			_add_effect(&"guard", _contact_position(), MUTED, 0.34)
		return
	if _deflect_timer > 0.0 and not parryable:
		_set_feedback("UNBLOCKABLE", 0.55)
	_player_health = maxf(0.0, _player_health - damage)
	_add_player_posture(18.0)
	_player_posture_delay = 1.0
	_player_stagger = maxf(_player_stagger, 0.32)
	_attack_timer = 0.0
	_deflect_timer = 0.0
	_hit_stop = 0.085
	_camera_shake = 0.78
	_camera_punch = 0.09
	_add_effect(&"hurt", _player_screen_position(), DANGER, 0.58)
	_set_feedback("HIT", 0.52)
	if _player_health <= 0.0:
		_player_dead = true
		_feedback_text = "YOU FELL"
		_feedback_timer = 99.0


func _add_boss_posture(amount: float) -> void:
	if _boss_state == &"BROKEN" or _boss_state == &"DEAD":
		return
	_boss_posture = minf(100.0, _boss_posture + amount)
	if _boss_posture >= 100.0:
		_boss_state = &"BROKEN"
		_boss_timer = 2.25
		_boss_attack_resolved = true
		_focus_alpha = 1.0
		_camera_shake = 0.62
		_camera_punch = 0.10
		_set_feedback("POSTURE BROKEN · ATTACK", 1.25)


func _add_player_posture(amount: float) -> void:
	_player_posture = minf(100.0, _player_posture + amount)
	_player_posture_delay = 1.0
	if _player_posture >= 100.0:
		_player_posture = 52.0
		_player_stagger = 0.92
		_set_feedback("YOUR POSTURE BROKE", 0.92)
		_add_effect(&"break", _player_screen_position(), DANGER, 0.72)


func _update_posture(delta: float) -> void:
	_player_posture_delay = maxf(0.0, _player_posture_delay - delta)
	_boss_posture_delay = maxf(0.0, _boss_posture_delay - delta)
	if _player_posture_delay <= 0.0 and _player_stagger <= 0.0:
		_player_posture = maxf(0.0, _player_posture - 14.0 * delta)
	if _boss_posture_delay <= 0.0 and (_boss_state == &"IDLE" or _boss_state == &"RECOVERY"):
		var recovery_rate := 2.0 + 8.0 * (_boss_health / 100.0)
		_boss_posture = maxf(0.0, _boss_posture - recovery_rate * delta)


func _defeat_boss() -> void:
	_boss_state = &"DEAD"
	_victory = true
	_hit_stop = 0.14
	_camera_shake = 0.90
	_camera_punch = 0.16
	_add_effect(&"deathblow", _boss_screen_position(), AMBER, 1.2)
	_feedback_text = "WARDEN DEFEATED"
	_feedback_timer = 99.0


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _player_dead or _victory:
			_restart_battle()
			return
		if event.position.distance_to(_attack_center) <= 75.0:
			_try_attack()
			return
		if event.position.distance_to(_deflect_center) <= 72.0:
			_try_deflect()
			return
		if event.position.distance_to(_dodge_center) <= 62.0:
			_try_dodge()
			return
		if event.position.x < size.x * 0.53 and event.position.y > size.y * 0.57 and _move_touch_index < 0:
			_move_touch_index = event.index
			_update_pointer_move(event.position)
			return
		_try_deflect()
	elif event.index == _move_touch_index:
		_move_touch_index = -1
		_touch_move_input = Vector2.ZERO


func _handle_pointer_press(position: Vector2) -> void:
	if _player_dead or _victory:
		_restart_battle()
		return
	if position.distance_to(_attack_center) <= 75.0:
		_try_attack()
		return
	if position.distance_to(_deflect_center) <= 72.0:
		_try_deflect()
		return
	if position.distance_to(_dodge_center) <= 62.0:
		_try_dodge()
		return
	if position.x < size.x * 0.53 and position.y > size.y * 0.57:
		_mouse_move_active = true
		_update_pointer_move(position)
		return
	_try_deflect()


func _update_pointer_move(position: Vector2) -> void:
	var raw := (position - _joystick_center) / _joystick_radius
	_touch_move_input = raw.limit_length(1.0)


func _player_screen_position() -> Vector2:
	var horizon_y := size.y * 0.405
	var near_y := size.y * 0.755
	var half_width := lerpf(size.x * 0.18, size.x * 0.43, _player_depth)
	var shake := _shake_offset()
	return Vector2(size.x * 0.5 + _player_x * half_width, lerpf(horizon_y, near_y, _player_depth)) + shake


func _boss_screen_position() -> Vector2:
	var attack_lunge := 0.0
	if _boss_state == &"ACTIVE":
		var ratio := 1.0 - clampf(_boss_timer / maxf(_active_total, 0.01), 0.0, 1.0)
		attack_lunge = sin(ratio * PI) * size.y * 0.045
	return Vector2(size.x * 0.5 - _player_x * size.x * 0.025, size.y * 0.405 + attack_lunge) + _shake_offset()


func _contact_position() -> Vector2:
	return _boss_screen_position().lerp(_player_screen_position(), 0.52)


func _player_sprite_height() -> float:
	return lerpf(size.y * 0.19, size.y * 0.305, _player_depth)


func _boss_sprite_height() -> float:
	var closeness := 1.0 - inverse_lerp(MIN_DEPTH, MAX_DEPTH, _player_depth)
	var height := lerpf(size.y * 0.32, size.y * 0.38, closeness)
	if _boss_state == &"ACTIVE":
		height *= 1.0 + sin((1.0 - _boss_timer / maxf(_active_total, 0.01)) * PI) * 0.10
	return height


func _shake_offset() -> Vector2:
	return Vector2(sin(_elapsed * 91.0), cos(_elapsed * 77.0)) * _camera_shake * 8.0


func _add_effect(kind: StringName, position: Vector2, color: Color, duration: float) -> void:
	_effects.append({"kind": kind, "position": position, "color": color, "time": 0.0, "duration": duration})


func _update_effects(delta: float) -> void:
	for index: int in range(_effects.size() - 1, -1, -1):
		var effect := _effects[index]
		effect["time"] = float(effect["time"]) + delta
		if float(effect["time"]) >= float(effect["duration"]):
			_effects.remove_at(index)


func _set_feedback(text: String, duration: float) -> void:
	_feedback_text = text
	_feedback_timer = duration


func _draw() -> void:
	_update_layout()
	_draw_background()
	_draw_perspective_guides()
	_draw_attack_telegraph()
	_draw_boss()
	_draw_player()
	_draw_effects()
	_draw_hud()
	_draw_controls()
	_draw_messages()


func _draw_background() -> void:
	var zoom_extra := _camera_punch * 0.45
	var expanded := size * zoom_extra
	var parallax := Vector2(-_player_x * 7.0, -zoom_extra * size.y * 0.15)
	draw_texture_rect(ARENA_TEXTURE, Rect2(-expanded * 0.5 + parallax, size + expanded), false)
	draw_rect(Rect2(Vector2.ZERO, size), Color("06101b1c"))
	draw_rect(Rect2(0.0, 0.0, size.x, size.y * 0.22), Color("07101b66"))


func _draw_perspective_guides() -> void:
	var vanishing := Vector2(size.x * 0.5, size.y * 0.385)
	for guide: float in [-1.0, -0.5, 0.5, 1.0]:
		var end := Vector2(size.x * 0.5 + guide * size.x * 0.46, size.y * 0.79)
		draw_line(vanishing, end, Color("8eb8c518"), 2.0)
	var player_position := _player_screen_position()
	draw_arc(player_position + Vector2(0.0, 7.0), _player_sprite_height() * 0.22, PI, TAU, 34, Color("84d9d534"), 3.0)


func _draw_attack_telegraph() -> void:
	if _boss_state != &"TELEGRAPH" and _boss_state != &"ACTIVE":
		return
	var ratio := 1.0 - clampf(_boss_timer / maxf(_telegraph_total if _boss_state == &"TELEGRAPH" else _active_total, 0.01), 0.0, 1.0)
	var alpha := 0.12 + ratio * 0.20 if _boss_state == &"TELEGRAPH" else 0.34
	var boss_position := _boss_screen_position()
	var player_position := _player_screen_position()
	if _boss_pattern == &"THRUST":
		var lane_x := size.x * 0.5 + _boss_locked_x * size.x * 0.28
		var points := PackedVector2Array([
			boss_position + Vector2(-18.0, 0.0),
			Vector2(lane_x - 64.0, player_position.y + 60.0),
			Vector2(lane_x + 64.0, player_position.y + 60.0),
			boss_position + Vector2(18.0, 0.0),
		])
		draw_colored_polygon(points, Color(DANGER, alpha * 0.42))
		draw_line(boss_position, Vector2(lane_x, player_position.y + 40.0), Color(DANGER, alpha), 5.0)
	elif _boss_pattern == &"SWEEP":
		draw_arc(boss_position + Vector2(0.0, 20.0), size.x * (0.23 + ratio * 0.12), 0.05, PI - 0.05, 54, Color(DANGER, alpha), 8.0)
	else:
		draw_arc(_contact_position(), 70.0 + ratio * 42.0, -2.8, -0.2, 42, Color(DANGER, alpha), 7.0)


func _draw_boss() -> void:
	var feet := _boss_screen_position()
	var height := _boss_sprite_height()
	var width := height * float(BOSS_TEXTURE.get_width()) / float(BOSS_TEXTURE.get_height())
	var rotation := 0.0
	var tint := Color.WHITE
	if _boss_state == &"TELEGRAPH":
		var ratio := 1.0 - clampf(_boss_timer / maxf(_telegraph_total, 0.01), 0.0, 1.0)
		match _boss_pattern:
			&"SLASH", &"DOUBLE": rotation = lerpf(0.0, -0.055, ratio)
			&"THRUST": rotation = lerpf(0.0, 0.035, ratio)
			&"SWEEP": rotation = lerpf(0.0, 0.065, ratio)
		tint = Color.WHITE.lerp(Color("ffd0a4"), 0.10 + sin(_elapsed * 12.0) * 0.04)
	elif _boss_state == &"BROKEN":
		rotation = 0.10
		tint = Color("d7c0ae")
	elif _boss_state == &"DEAD":
		rotation = 0.34
		tint = Color("766f72")
	rotation += _boss_recoil * 0.08
	draw_set_transform(feet, rotation, Vector2.ONE)
	draw_ellipse_shadow(Vector2.ZERO, Vector2(width * 0.34, 16.0), Color("02050988"))
	draw_texture_rect(BOSS_TEXTURE, Rect2(-width * 0.5, -height, width, height), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _boss_state != &"DEAD":
		draw_arc(feet + Vector2(0.0, 8.0), width * 0.28, PI, TAU, 32, Color("d6a85c66"), 3.0)


func _draw_player() -> void:
	var feet := _player_screen_position()
	var height := _player_sprite_height()
	var width := height * float(PLAYER_TEXTURE.get_width()) / float(PLAYER_TEXTURE.get_height())
	var rotation := _move_input.x * 0.045
	var vertical_offset := absf(sin(_elapsed * 9.0)) * 5.0 * _player_motion.length()
	if _attack_timer > 0.0:
		var ratio := clampf(_attack_elapsed / ATTACK_DURATION, 0.0, 1.0)
		rotation += lerpf(-0.08, 0.11, ratio)
		vertical_offset -= sin(ratio * PI) * 24.0
	elif _deflect_timer > 0.0:
		rotation -= 0.045
	elif _player_stagger > 0.0:
		rotation = -0.10
	if _dodge_timer > 0.0:
		rotation += _dodge_direction.x * 0.15
		for ghost_index: int in range(2, 0, -1):
			var ghost_offset := Vector2(-_dodge_direction.x * 22.0 * ghost_index, _dodge_direction.y * 12.0 * ghost_index)
			draw_texture_rect(PLAYER_TEXTURE, Rect2(feet + ghost_offset - Vector2(width * 0.5, height), Vector2(width, height)), false, Color("73dcca22"))
	draw_set_transform(feet + Vector2(0.0, vertical_offset), rotation, Vector2.ONE)
	draw_ellipse_shadow(Vector2.ZERO, Vector2(width * 0.31, 13.0), Color("02050999"))
	draw_texture_rect(PLAYER_TEXTURE, Rect2(-width * 0.5, -height, width, height), false, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _deflect_timer > 0.0:
		var ring_alpha := 1.0 - clampf(_deflect_elapsed / DEFLECT_DURATION, 0.0, 1.0)
		draw_arc(feet - Vector2(0.0, height * 0.56), width * 0.42, -2.8, -0.2, 32, Color(PLAYER_TEAL, ring_alpha), 6.0)


func draw_ellipse_shadow(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in range(28):
		var angle := TAU * float(index) / 28.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)


func _draw_effects() -> void:
	for effect: Dictionary in _effects:
		var progress := clampf(float(effect["time"]) / float(effect["duration"]), 0.0, 1.0)
		var fade := 1.0 - progress
		var position := effect["position"] as Vector2
		var color := effect["color"] as Color
		var kind := effect["kind"] as StringName
		color.a = fade
		match kind:
			&"hit", &"hurt", &"boss_strike":
				for ray: int in range(10):
					var direction := Vector2.from_angle(TAU * float(ray) / 10.0 + 0.17)
					draw_line(position + direction * 8.0, position + direction * (28.0 + progress * 80.0), color, 7.0 * fade + 1.0)
			&"deflect":
				draw_arc(position, 28.0 + progress * 105.0, 0.0, TAU, 48, color, 11.0 * fade + 1.0)
				for ray: int in range(12):
					var direction := Vector2.from_angle(TAU * float(ray) / 12.0)
					draw_line(position + direction * 16.0, position + direction * (50.0 + progress * 66.0), color, 5.0)
			&"guard":
				draw_arc(position, 30.0 + progress * 42.0, -2.7, -0.3, 30, color, 8.0 * fade + 1.0)
			&"dodge", &"perfect":
				draw_arc(position, 34.0 + progress * 120.0, 0.0, TAU, 42, color, 8.0 * fade + 1.0)
			&"break", &"deathblow":
				draw_arc(position, 42.0 + progress * 210.0, 0.0, TAU, 56, color, 15.0 * fade + 1.0)
				for shard: int in range(14):
					var direction := Vector2.from_angle(TAU * float(shard) / 14.0)
					draw_circle(position + direction * progress * (80.0 + float(shard % 3) * 30.0), 7.0 * fade + 1.0, color)


func _draw_hud() -> void:
	_draw_text("ASHEN WARDEN", Vector2(size.x * 0.5, 31.0), 20, PAPER)
	var boss_posture_rect := Rect2(54.0, 50.0, size.x - 108.0, 22.0)
	draw_rect(boss_posture_rect, Color("080d15dd"))
	draw_rect(Rect2(boss_posture_rect.position + Vector2(3.0, 3.0), Vector2((boss_posture_rect.size.x - 6.0) * _boss_posture / 100.0, boss_posture_rect.size.y - 6.0)), POSTURE)
	var boss_health_rect := Rect2(78.0, 77.0, size.x - 156.0, 10.0)
	draw_rect(boss_health_rect, Color("080d15cc"))
	draw_rect(Rect2(boss_health_rect.position + Vector2(2.0, 2.0), Vector2((boss_health_rect.size.x - 4.0) * _boss_health / 100.0, 6.0)), HEALTH_RED)

	var player_width := minf(255.0, size.x * 0.39)
	_draw_text("VITALITY", Vector2(27.0, 112.0), 12, Color("e7c5c5"), HORIZONTAL_ALIGNMENT_LEFT)
	draw_rect(Rect2(27.0, 125.0, player_width, 15.0), Color("080d15bb"))
	draw_rect(Rect2(30.0, 128.0, (player_width - 6.0) * _player_health / 100.0, 9.0), HEALTH_RED)
	_draw_text("POSTURE", Vector2(27.0, 155.0), 12, Color("ecd9ac"), HORIZONTAL_ALIGNMENT_LEFT)
	draw_rect(Rect2(27.0, 168.0, player_width, 12.0), Color("080d15bb"))
	draw_rect(Rect2(30.0, 171.0, (player_width - 6.0) * _player_posture / 100.0, 6.0), POSTURE)

	if _boss_state == &"TELEGRAPH":
		var remaining_ratio := clampf(_boss_timer / maxf(_telegraph_total, 0.01), 0.0, 1.0)
		var cue_color := DANGER if remaining_ratio < 0.30 else AMBER
		_draw_text("READ THE MOTION", Vector2(size.x * 0.5, 111.0), 15, Color(cue_color, 0.72 + sin(_elapsed * 8.0) * 0.18))
	if _boss_state == &"BROKEN":
		_draw_text("ATTACK NOW", Vector2(size.x * 0.5, 142.0), 20, AMBER)


func _draw_controls() -> void:
	draw_circle(_joystick_center, _joystick_radius, Color("07101c88"))
	draw_arc(_joystick_center, _joystick_radius, 0.0, TAU, 44, Color("dce7ed44"), 4.0)
	draw_circle(_joystick_center + _touch_move_input * _joystick_radius, 31.0, Color("dce7ed88"))

	_draw_action_button(_attack_center, 63.0, "ATTACK", AMBER, _attack_timer <= 0.0 and _action_cooldown <= 0.0)
	_draw_action_button(_deflect_center, 58.0, "DEFLECT", PLAYER_TEAL, _deflect_timer <= 0.0 and _action_cooldown <= 0.0)
	_draw_action_button(_dodge_center, 48.0, "DODGE", Color("93bfe4"), _dodge_cooldown <= 0.0)


func _draw_action_button(center: Vector2, radius: float, label: String, color: Color, ready: bool) -> void:
	var display_color := color if ready else Color("53616a")
	draw_circle(center, radius, Color(display_color, 0.86))
	draw_arc(center, radius, 0.0, TAU, 40, Color("f3f7f4aa"), 4.0)
	_draw_text(label, center, 14 if label != "DEFLECT" else 13, INK)


func _draw_messages() -> void:
	if _tutorial_timer > 0.0 and not _player_dead and not _victory:
		var panel := Rect2(42.0, size.y * 0.215, size.x - 84.0, 58.0)
		draw_rect(panel, Color("07101cbb"))
		_draw_text("MOVE TO CONTROL RANGE · READ · DEFLECT", Vector2(size.x * 0.5, panel.position.y + 22.0), 13, PAPER)
		_draw_text("SWEEP ATTACKS MUST BE EVADED", Vector2(size.x * 0.5, panel.position.y + 43.0), 12, Color("efb17a"))
	if _feedback_timer > 0.0:
		_draw_text(_feedback_text, Vector2(size.x * 0.5, size.y * 0.34), 26, AMBER if _feedback_text != "HIT" else DANGER)
	if _player_dead or _victory:
		draw_rect(Rect2(Vector2.ZERO, size), Color("04080dc9"))
		_draw_text("WARDEN DEFEATED" if _victory else "YOU FELL", Vector2(size.x * 0.5, size.y * 0.42), 37, AMBER if _victory else DANGER)
		_draw_text("TIME %.1fs" % _battle_time, Vector2(size.x * 0.5, size.y * 0.49), 19, PAPER)
		_draw_text("TAP TO RETRY", Vector2(size.x * 0.5, size.y * 0.56), 20, PLAYER_TEAL)


func _draw_text(text: String, center: Vector2, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var font := ThemeDB.fallback_font
	if alignment == HORIZONTAL_ALIGNMENT_LEFT:
		draw_string(font, center + Vector2(0.0, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
		return
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(font, center - Vector2(width * 0.5, -font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
