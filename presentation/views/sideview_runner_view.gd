class_name SideviewRunnerView
extends Control

const CombatModel = preload("res://game/runner/runner_combat_model.gd")
const RUN_CLIP_PATH := "res://assets/mocap/cmu/02_03_run_2d.json"
const BASE_HEIGHT := 720.0
const GROUND_Y := 545.0
const PLAYER_X_RATIO := 0.285
const MIN_PLAYER_X := 300.0
const BASE_SPEED := 405.0
const MAX_SPEED := 540.0
const RUN_STRIDE := 126.0
const RUN_POSE_SCALE := 70.0

var combat: RunnerCombatModel = CombatModel.new()
var world_speed := 0.0
var world_offset := 0.0
var distance_m := 0.0
var run_phase := 0.0
var spawn_timer := 1.25
var hit_stop := 0.0
var shake_strength := 0.0
var impact_flash := 0.0
var danger_pulse := 0.0
var restart_timer := 0.0
var _last_footstep := -1
var _rng := RandomNumberGenerator.new()
var _enemies: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _speed_lines: Array[Dictionary] = []
var _status_label: Label
var _distance_label: Label
var _combo_label: Label
var _health_label: Label
var _attack_button: Button
var _dodge_button: Button
var _restart_button: Button
var _run_fps := 30.0
var _run_time := 0.0
var _run_frames: Array = []
var _run_root_forward: Array = []
var _run_root_height: Array = []
var _run_joint_names: Array = []
var _run_pose: Dictionary = {}


func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_rng.seed = 73021
	_load_run_motion()
	_build_ui()
	_reset_run()
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	var visual_delta := minf(delta, 0.04)
	if combat.state == RunnerCombatModel.State.DEAD:
		restart_timer += visual_delta
		_update_particles(visual_delta)
		_update_ui()
		queue_redraw()
		return

	if hit_stop > 0.0:
		hit_stop = maxf(0.0, hit_stop - visual_delta)
		shake_strength = maxf(0.0, shake_strength - visual_delta * 48.0)
		impact_flash = maxf(0.0, impact_flash - visual_delta * 8.0)
		_update_particles(visual_delta * 0.25)
		queue_redraw()
		return

	combat.advance(visual_delta)
	var speed_target := BASE_SPEED
	if combat.state == RunnerCombatModel.State.DODGE:
		speed_target = MAX_SPEED
	elif combat.state == RunnerCombatModel.State.HURT:
		speed_target = BASE_SPEED * 0.48
	elif combat.combo >= 4:
		speed_target = BASE_SPEED + minf(95.0, float(combat.combo - 3) * 16.0)
	world_speed = move_toward(world_speed, speed_target, visual_delta * 245.0)
	world_offset += world_speed * visual_delta
	distance_m += world_speed * visual_delta / 52.0
	_advance_run_motion(visual_delta)
	_update_footsteps()
	_update_enemies(visual_delta)
	_update_particles(visual_delta)
	_update_speed_lines(visual_delta)
	shake_strength = maxf(0.0, shake_strength - visual_delta * 30.0)
	impact_flash = maxf(0.0, impact_flash - visual_delta * 6.0)
	danger_pulse = maxf(0.0, danger_pulse - visual_delta * 2.8)
	_update_ui()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_Z:
			_request_attack()
		elif event.keycode == KEY_SHIFT or event.keycode == KEY_X:
			_request_dodge()


func _load_run_motion() -> void:
	var file := FileAccess.open(RUN_CLIP_PATH, FileAccess.READ)
	assert(file != null, "Runner mocap clip is missing")
	var payload: Variant = JSON.parse_string(file.get_as_text())
	assert(payload is Dictionary, "Runner mocap clip is invalid")
	_run_fps = float(payload.get("fps", 30.0))
	_run_frames = payload.get("frames", [])
	_run_root_forward = payload.get("root_forward", [])
	_run_root_height = payload.get("root_height", [])
	_run_joint_names = payload.get("joints", [])
	assert(_run_frames.size() >= 20, "Runner mocap needs a complete stride")
	_sample_run_pose()


func _advance_run_motion(delta: float) -> void:
	if _run_frames.is_empty():
		return
	var clip_duration := float(_run_frames.size()) / _run_fps
	var captured_speed := _captured_run_distance() / clip_duration
	_run_time = fmod(_run_time + delta * world_speed / maxf(captured_speed, 1.0), clip_duration)
	run_phase = _run_time / clip_duration * TAU
	_sample_run_pose()


func _sample_run_pose() -> void:
	if _run_frames.is_empty():
		return
	var frame_value := _run_time * _run_fps
	var frame_a := floori(frame_value) % _run_frames.size()
	var frame_b := (frame_a + 1) % _run_frames.size()
	var blend := frame_value - floorf(frame_value)
	var pose_a: Array = _run_frames[frame_a]
	var pose_b: Array = _run_frames[frame_b]
	_run_pose.clear()
	for index in range(_run_joint_names.size()):
		var point_a := Vector2(float(pose_a[index][0]), float(pose_a[index][1]))
		var point_b := Vector2(float(pose_b[index][0]), float(pose_b[index][1]))
		_run_pose[String(_run_joint_names[index])] = point_a.lerp(point_b, blend)
	var height_a := float(_run_root_height[frame_a])
	var height_b := float(_run_root_height[frame_b])
	_run_pose["root_height"] = lerpf(height_a, height_b, blend)


func _draw() -> void:
	var scale_factor := size.y / BASE_HEIGHT
	var virtual_width := size.x / maxf(scale_factor, 0.001)
	var shake := Vector2.ZERO
	if shake_strength > 0.0:
		var ticks := float(Time.get_ticks_msec())
		shake = Vector2(sin(ticks * 0.091), cos(ticks * 0.073)) * shake_strength
	draw_set_transform(shake * scale_factor, 0.0, Vector2(scale_factor, scale_factor))
	_draw_sky(virtual_width)
	_draw_parallax(virtual_width)
	_draw_ground(virtual_width)
	_draw_speed_streaks(virtual_width)
	for enemy in _enemies:
		_draw_enemy(enemy)
	_draw_player(virtual_width)
	_draw_particles()
	if impact_flash > 0.0:
		draw_rect(Rect2(0.0, 0.0, virtual_width, BASE_HEIGHT), Color(0.92, 0.98, 1.0, impact_flash * 0.24))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _build_ui() -> void:
	var title := Label.new()
	title.text = "RIFT RUNNER"
	title.position = Vector2(24, 18)
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color("eaf8ff"))
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "MOMENTUM COMBAT TEST"
	subtitle.position = Vector2(27, 51)
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color("66dce8"))
	add_child(subtitle)

	_distance_label = Label.new()
	_distance_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_distance_label.position = Vector2(-210, 20)
	_distance_label.size = Vector2(184, 30)
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_distance_label.add_theme_font_size_override("font_size", 21)
	_distance_label.add_theme_color_override("font_color", Color("eaf8ff"))
	add_child(_distance_label)

	_combo_label = Label.new()
	_combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_combo_label.position = Vector2(-210, 50)
	_combo_label.size = Vector2(184, 26)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.add_theme_font_size_override("font_size", 15)
	_combo_label.add_theme_color_override("font_color", Color("ffbc66"))
	add_child(_combo_label)

	_health_label = Label.new()
	_health_label.position = Vector2(26, 82)
	_health_label.add_theme_font_size_override("font_size", 19)
	_health_label.add_theme_color_override("font_color", Color("ff786f"))
	add_child(_health_label)

	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status_label.position = Vector2(-230, 25)
	_status_label.size = Vector2(460, 42)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color("d9edf2"))
	add_child(_status_label)

	_dodge_button = _make_action_button("DODGE", Color("1b8798"))
	_dodge_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_dodge_button.position = Vector2(24, -92)
	_dodge_button.size = Vector2(148, 64)
	_dodge_button.button_down.connect(_request_dodge)
	add_child(_dodge_button)

	_attack_button = _make_action_button("ATTACK", Color("ca4f35"))
	_attack_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_attack_button.position = Vector2(-172, -92)
	_attack_button.size = Vector2(148, 64)
	_attack_button.button_down.connect(_request_attack)
	add_child(_attack_button)

	_restart_button = _make_action_button("RUN AGAIN", Color("ca4f35"))
	_restart_button.set_anchors_preset(Control.PRESET_CENTER)
	_restart_button.position = Vector2(-96, 50)
	_restart_button.size = Vector2(192, 62)
	_restart_button.pressed.connect(_reset_run)
	_restart_button.visible = false
	add_child(_restart_button)


func _make_action_button(text_value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(color, 0.88)
	normal.border_color = color.lightened(0.25)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(18)
	normal.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	normal.shadow_size = 6
	var pressed := normal.duplicate()
	pressed.bg_color = color.lightened(0.16)
	pressed.shadow_size = 2
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _reset_run() -> void:
	combat.reset()
	world_speed = 160.0
	world_offset = 0.0
	distance_m = 0.0
	run_phase = 0.0
	_run_time = 0.0
	_sample_run_pose()
	spawn_timer = 1.1
	hit_stop = 0.0
	shake_strength = 0.0
	impact_flash = 0.0
	restart_timer = 0.0
	_enemies.clear()
	_particles.clear()
	_speed_lines.clear()
	_restart_button.visible = false
	_attack_button.visible = true
	_dodge_button.visible = true
	_update_ui()
	queue_redraw()


func _request_attack() -> void:
	if combat.state == RunnerCombatModel.State.DEAD:
		return
	if combat.request_attack():
		_spawn_attack_sparks()


func _request_dodge() -> void:
	if combat.state == RunnerCombatModel.State.DEAD:
		return
	if combat.request_dodge():
		_spawn_dust(_player_x(_virtual_width()) - 25.0, 7, Color("74e2e9"))


func _update_enemies(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0.0 and _enemies.size() < 4:
		_spawn_enemy()
		spawn_timer = _rng.randf_range(1.25, 1.85)

	var player_x := _player_x(_virtual_width())
	for index in range(_enemies.size() - 1, -1, -1):
		var enemy := _enemies[index]
		var state: String = enemy["state"]
		enemy["phase"] = float(enemy["phase"]) + delta * 8.0
		enemy["timer"] = float(enemy["timer"]) + delta
		if state == "run":
			enemy["x"] = float(enemy["x"]) - world_speed * delta
			if float(enemy["x"]) - player_x < 245.0:
				enemy["state"] = "telegraph"
				enemy["timer"] = 0.0
				danger_pulse = 1.0
		elif state == "telegraph":
			enemy["x"] = float(enemy["x"]) - world_speed * delta * 0.32
			if float(enemy["timer"]) >= 0.58:
				enemy["state"] = "lunge"
				enemy["timer"] = 0.0
		elif state == "lunge":
			enemy["x"] = float(enemy["x"]) - (world_speed * 0.58 + 320.0) * delta
			if absf(float(enemy["x"]) - player_x) < 74.0 and not bool(enemy["resolved"]):
				enemy["resolved"] = true
				if combat.is_invulnerable():
					_on_perfect_dodge(enemy)
				elif combat.receive_hit():
					_on_player_hit()
		elif state == "stagger":
			enemy["x"] = float(enemy["x"]) + 115.0 * delta
			if float(enemy["timer"]) > 0.34:
				enemy["state"] = "telegraph"
				enemy["timer"] = 0.0
		elif state == "dead":
			enemy["x"] = float(enemy["x"]) + 420.0 * delta
			enemy["y"] = float(enemy["y"]) - 110.0 * delta + 330.0 * delta * float(enemy["timer"])
			enemy["rotation"] = float(enemy["rotation"]) + delta * 7.5

		if combat.is_attack_active() and state != "dead" and int(enemy["hit_attack_id"]) != combat.attack_id:
			var hit_distance := float(enemy["x"]) - player_x
			if hit_distance >= 8.0 and hit_distance <= combat.attack_reach():
				enemy["hit_attack_id"] = combat.attack_id
				enemy["hp"] = int(enemy["hp"]) - 1
				if int(enemy["hp"]) <= 0:
					_on_enemy_killed(enemy)
				else:
					_on_enemy_staggered(enemy)

		if float(enemy["x"]) < player_x - 180.0 or float(enemy["timer"]) > 1.15 and String(enemy["state"]) == "dead":
			_enemies.remove_at(index)


func _spawn_enemy() -> void:
	var brute := combat.kills >= 3 and _rng.randf() < 0.32
	_enemies.append({
		"x": _virtual_width() + 120.0,
		"y": GROUND_Y,
		"phase": _rng.randf_range(0.0, TAU),
		"timer": 0.0,
		"state": "run",
		"hp": 2 if brute else 1,
		"max_hp": 2 if brute else 1,
		"brute": brute,
		"rotation": 0.0,
		"resolved": false,
		"hit_attack_id": -1,
	})


func _on_enemy_killed(enemy: Dictionary) -> void:
	enemy["state"] = "dead"
	enemy["timer"] = 0.0
	combat.register_kill()
	hit_stop = 0.075 if combat.combo_step < 2 else 0.105
	shake_strength = 8.0 if combat.combo_step < 2 else 12.0
	impact_flash = 1.0
	_spawn_impact(float(enemy["x"]), GROUND_Y - 78.0, Color("ff874f"), 17)
	Input.vibrate_handheld(28 if combat.combo_step < 2 else 45)


func _on_enemy_staggered(enemy: Dictionary) -> void:
	enemy["state"] = "stagger"
	enemy["timer"] = 0.0
	hit_stop = 0.055
	shake_strength = 5.0
	impact_flash = 0.55
	_spawn_impact(float(enemy["x"]), GROUND_Y - 86.0, Color("ffd77a"), 10)


func _on_perfect_dodge(enemy: Dictionary) -> void:
	enemy["resolved"] = true
	combat.combo += 1
	combat.best_combo = maxi(combat.best_combo, combat.combo)
	shake_strength = 3.0
	_spawn_dust(_player_x(_virtual_width()), 10, Color("6de7ee"))


func _on_player_hit() -> void:
	world_speed *= 0.5
	hit_stop = 0.09
	shake_strength = 14.0
	impact_flash = 0.8
	_spawn_impact(_player_x(_virtual_width()), GROUND_Y - 84.0, Color("ff4f57"), 14)
	Input.vibrate_handheld(60)
	if combat.state == RunnerCombatModel.State.DEAD:
		_attack_button.visible = false
		_dodge_button.visible = false
		_restart_button.visible = true


func _update_footsteps() -> void:
	if combat.state == RunnerCombatModel.State.HURT or combat.state == RunnerCombatModel.State.DEAD:
		return
	var step_distance := maxf(80.0, _captured_run_distance() * 0.5)
	var step_index := int(floor(world_offset / step_distance))
	if step_index != _last_footstep:
		_last_footstep = step_index
		_spawn_dust(_player_x(_virtual_width()) - 20.0, 3, Color("8aa1a8"))


func _update_particles(delta: float) -> void:
	for index in range(_particles.size() - 1, -1, -1):
		var particle := _particles[index]
		particle["life"] = float(particle["life"]) - delta
		if float(particle["life"]) <= 0.0:
			_particles.remove_at(index)
			continue
		particle["position"] = Vector2(particle["position"]) + Vector2(particle["velocity"]) * delta
		particle["velocity"] = Vector2(particle["velocity"]) + Vector2(0.0, float(particle["gravity"])) * delta


func _update_speed_lines(delta: float) -> void:
	if world_speed > BASE_SPEED * 0.98 and _rng.randf() < delta * 7.0:
		_speed_lines.append({
			"x": _virtual_width() + 30.0,
			"y": _rng.randf_range(135.0, 500.0),
			"length": _rng.randf_range(55.0, 145.0),
			"life": _rng.randf_range(0.22, 0.38),
		})
	for index in range(_speed_lines.size() - 1, -1, -1):
		var line := _speed_lines[index]
		line["x"] = float(line["x"]) - world_speed * 1.7 * delta
		line["life"] = float(line["life"]) - delta
		if float(line["life"]) <= 0.0:
			_speed_lines.remove_at(index)


func _spawn_dust(x: float, count: int, color: Color) -> void:
	for index in range(count):
		var life := _rng.randf_range(0.28, 0.55)
		_particles.append({
			"position": Vector2(x + _rng.randf_range(-16.0, 12.0), GROUND_Y - _rng.randf_range(1.0, 8.0)),
			"velocity": Vector2(_rng.randf_range(-180.0, -55.0), _rng.randf_range(-95.0, -25.0)),
			"gravity": 145.0,
			"life": life,
			"max_life": life,
			"radius": _rng.randf_range(3.0, 8.0),
			"color": color,
		})


func _spawn_impact(x: float, y: float, color: Color, count: int) -> void:
	for index in range(count):
		var angle := _rng.randf_range(-PI, PI)
		var speed := _rng.randf_range(145.0, 430.0)
		var life := _rng.randf_range(0.18, 0.42)
		_particles.append({
			"position": Vector2(x, y),
			"velocity": Vector2(cos(angle), sin(angle)) * speed,
			"gravity": 380.0,
			"life": life,
			"max_life": life,
			"radius": _rng.randf_range(2.0, 6.5),
			"color": color,
		})


func _spawn_attack_sparks() -> void:
	var x := _player_x(_virtual_width()) + 28.0
	for index in range(3):
		var life := 0.15 + float(index) * 0.035
		_particles.append({
			"position": Vector2(x, GROUND_Y - 105.0),
			"velocity": Vector2(_rng.randf_range(35.0, 100.0), _rng.randf_range(-80.0, 20.0)),
			"gravity": 70.0,
			"life": life,
			"max_life": life,
			"radius": 2.5,
			"color": Color("63e6ef"),
		})


func _draw_sky(virtual_width: float) -> void:
	var sky_top := Color("07131f")
	var sky_bottom := Color("183348")
	for index in range(12):
		var t := float(index) / 11.0
		var band_height := GROUND_Y / 12.0
		draw_rect(Rect2(0.0, float(index) * band_height, virtual_width, band_height + 1.0), Color(sky_top).lerp(sky_bottom, t))
	var moon_x := virtual_width * 0.76 - fmod(world_offset * 0.018, virtual_width * 0.22)
	draw_circle(Vector2(moon_x, 145.0), 58.0, Color("d8f4ed"))
	draw_circle(Vector2(moon_x + 20.0, 133.0), 58.0, Color("10283a"))


func _draw_parallax(virtual_width: float) -> void:
	_draw_mountain_layer(virtual_width, 0.08, 355.0, Color("12283a"), 390.0, 150.0)
	_draw_mountain_layer(virtual_width, 0.18, 430.0, Color("17384a"), 310.0, 112.0)
	var ruin_spacing := 270.0
	var ruin_offset := -fmod(world_offset * 0.34, ruin_spacing)
	for index in range(-1, int(virtual_width / ruin_spacing) + 2):
		var x := ruin_offset + float(index) * ruin_spacing
		var height := 68.0 + float(posmod(index * 47, 78))
		draw_rect(Rect2(x, GROUND_Y - height - 28.0, 54.0, height), Color("122b34"))
		draw_rect(Rect2(x + 17.0, GROUND_Y - height - 44.0, 20.0, 22.0), Color("122b34"))
		draw_circle(Vector2(x + 27.0, GROUND_Y - height + 7.0), 7.0, Color("5ad2cf"))


func _draw_mountain_layer(virtual_width: float, factor: float, baseline: float, color: Color, spacing: float, height: float) -> void:
	var offset := -fmod(world_offset * factor, spacing)
	for index in range(-1, int(virtual_width / spacing) + 2):
		var x := offset + float(index) * spacing
		var points := PackedVector2Array([
			Vector2(x - 55.0, baseline),
			Vector2(x + spacing * 0.22, baseline - height * 0.5),
			Vector2(x + spacing * 0.48, baseline - height),
			Vector2(x + spacing * 0.68, baseline - height * 0.42),
			Vector2(x + spacing + 55.0, baseline),
		])
		draw_colored_polygon(points, color)


func _draw_ground(virtual_width: float) -> void:
	draw_rect(Rect2(0.0, GROUND_Y, virtual_width, BASE_HEIGHT - GROUND_Y), Color("0b171c"))
	draw_rect(Rect2(0.0, GROUND_Y, virtual_width, 7.0), Color("4e7780"))
	draw_rect(Rect2(0.0, GROUND_Y + 7.0, virtual_width, 8.0), Color("1d3f42"))
	var marker_spacing := 88.0
	var marker_offset := -fmod(world_offset, marker_spacing)
	for index in range(-1, int(virtual_width / marker_spacing) + 2):
		var x := marker_offset + float(index) * marker_spacing
		draw_line(Vector2(x, GROUND_Y + 19.0), Vector2(x - 58.0, BASE_HEIGHT), Color("183135"), 3.0)
		for blade in range(3):
			var grass_x := x + float(blade) * 8.0
			draw_line(Vector2(grass_x, GROUND_Y), Vector2(grass_x - 5.0, GROUND_Y - 13.0 - float(blade) * 3.0), Color("477d71"), 2.0)


func _draw_speed_streaks(_virtual_width_value: float) -> void:
	for line in _speed_lines:
		var alpha := clampf(float(line["life"]) * 2.4, 0.0, 0.3)
		draw_line(Vector2(float(line["x"]), float(line["y"])), Vector2(float(line["x"]) + float(line["length"]), float(line["y"])), Color(0.52, 0.91, 0.93, alpha), 2.0)


func _draw_player(virtual_width: float) -> void:
	var x := _player_x(virtual_width)
	var state := combat.state
	var captured_height := float(_run_pose.get("root_height", 1.62))
	var hip := Vector2(x, GROUND_Y - captured_height * RUN_POSE_SCALE)
	if state == RunnerCombatModel.State.DODGE:
		_draw_dodging_player(hip)
		return
	if state == RunnerCombatModel.State.DEAD:
		_draw_dead_player(hip)
		return
	if state == RunnerCombatModel.State.HURT:
		hip += Vector2(-18.0, 4.0)

	var left_hip := _mocap_point("left_hip", hip)
	var left_knee := _mocap_point("left_knee", hip)
	var left_ankle := _mocap_point("left_ankle", hip)
	var left_toe := _mocap_point("left_toe", hip)
	var right_hip := _mocap_point("right_hip", hip)
	var right_knee := _mocap_point("right_knee", hip)
	var right_ankle := _mocap_point("right_ankle", hip)
	var right_toe := _mocap_point("right_toe", hip)
	_draw_mocap_leg(left_hip, left_knee, left_ankle, left_toe, Color("172b38"), false)
	_draw_mocap_leg(right_hip, right_knee, right_ankle, right_toe, Color("31586a"), true)

	var chest := _mocap_point("chest", hip)
	var head_top := _mocap_point("head", hip)
	var shoulder := (_mocap_point("left_shoulder", hip) + _mocap_point("right_shoulder", hip)) * 0.5
	draw_line(hip, chest, Color("0d2430"), 62.0, true)
	draw_line(hip, chest, Color("1d5061"), 50.0, true)
	draw_line(hip.lerp(chest, 0.2), chest, Color("63cdd4"), 4.0, true)

	var scarf_anchor := shoulder + Vector2(-12.0, -5.0)
	var scarf_wave := sin(run_phase * 1.5) * 10.0
	var scarf := PackedVector2Array([
		scarf_anchor,
		scarf_anchor + Vector2(-55.0, -8.0 + scarf_wave * 0.25),
		scarf_anchor + Vector2(-120.0, 12.0 + scarf_wave),
		scarf_anchor + Vector2(-64.0, 13.0 + scarf_wave * 0.3),
	])
	draw_colored_polygon(scarf, Color("f06445"))

	var head := chest.lerp(head_top, 0.66) + Vector2(3.0, -2.0)
	draw_circle(head, 25.0, Color("14232f"))
	var mask := PackedVector2Array([
		head + Vector2(-16.0, -16.0),
		head + Vector2(20.0, -12.0),
		head + Vector2(15.0, 17.0),
		head + Vector2(-10.0, 20.0),
	])
	draw_colored_polygon(mask, Color("d9f1ee"))
	draw_line(head + Vector2(5.0, -4.0), head + Vector2(16.0, -2.0), Color("ff704d"), 4.0)

	if state == RunnerCombatModel.State.ATTACK:
		_draw_attack_arms(shoulder)
	else:
		_draw_mocap_running_arms(hip)


func _mocap_point(name: String, hip: Vector2) -> Vector2:
	var point: Vector2 = _run_pose.get(name, Vector2.ZERO)
	return hip + Vector2(point.x, -point.y) * RUN_POSE_SCALE


func _draw_mocap_leg(hip: Vector2, knee: Vector2, ankle: Vector2, toe: Vector2, color: Color, front: bool) -> void:
	draw_line(hip, knee, Color("0c202b"), 21.0, true)
	draw_line(knee, ankle, Color("0c202b"), 18.0, true)
	draw_line(hip, knee, color, 15.0, true)
	draw_line(knee, ankle, color.lightened(0.1) if front else color, 12.0, true)
	draw_circle(knee, 7.0, Color("70d3da") if front else Color("294958"))
	var foot_direction := (toe - ankle).normalized()
	if foot_direction.length_squared() < 0.5:
		foot_direction = Vector2.RIGHT
	var foot_tip := ankle + foot_direction * 27.0
	draw_line(ankle, foot_tip, Color("0c1922"), 13.0, true)


func _draw_mocap_running_arms(hip: Vector2) -> void:
	var left_shoulder := _mocap_point("left_shoulder", hip)
	var left_elbow := _mocap_point("left_elbow", hip)
	var left_hand := _mocap_point("left_hand", hip)
	var right_shoulder := _mocap_point("right_shoulder", hip)
	var right_elbow := _mocap_point("right_elbow", hip)
	var right_hand := _mocap_point("right_hand", hip)
	_draw_mocap_arm(left_shoulder, left_elbow, left_hand, Color("1e4858"), false)
	_draw_mocap_arm(right_shoulder, right_elbow, right_hand, Color("4b98a1"), true)
	var blade_direction := (right_hand - right_elbow).normalized()
	if blade_direction.x < 0.25:
		blade_direction = Vector2(0.94, 0.34)
	var blade_end := right_hand + blade_direction * 76.0
	draw_line(right_hand, blade_end, Color("efffff"), 7.0, true)
	draw_line(right_hand + blade_direction.orthogonal() * 10.0, right_hand - blade_direction.orthogonal() * 10.0, Color("ff704d"), 7.0, true)


func _draw_mocap_arm(shoulder: Vector2, elbow: Vector2, hand: Vector2, color: Color, front: bool) -> void:
	draw_line(shoulder, elbow, Color("0c202b"), 16.0, true)
	draw_line(elbow, hand, Color("0c202b"), 14.0, true)
	draw_line(shoulder, elbow, color, 11.0, true)
	draw_line(elbow, hand, color.lightened(0.12) if front else color, 9.0, true)
	draw_circle(hand, 6.0, Color("d9f1ee"))


func _draw_leg(hip: Vector2, phase: float, color: Color, front: bool) -> void:
	var swing := sin(phase) * 0.68
	var lift := maxf(0.0, -cos(phase))
	var knee := hip + Vector2(sin(swing) * 49.0, cos(swing) * 49.0)
	var shin_angle := swing * 0.38 - lift * 0.95
	var foot := knee + Vector2(sin(shin_angle) * 48.0, cos(shin_angle) * 48.0)
	foot.y = minf(foot.y, GROUND_Y - 8.0)
	draw_line(hip, knee, color, 18.0, true)
	draw_line(knee, foot, color.lightened(0.08) if front else color, 15.0, true)
	draw_circle(knee, 9.0, Color("6ccbd2") if front else Color("284756"))
	var foot_tip := foot + Vector2(30.0, 1.0)
	draw_line(foot, foot_tip, Color("0d1c26"), 13.0, true)


func _draw_running_arms(shoulder: Vector2, phase: float) -> void:
	var arm_swing := sin(phase + PI) * 0.62
	var elbow := shoulder + Vector2(sin(arm_swing) * 41.0, cos(arm_swing) * 41.0)
	var hand := elbow + Vector2(31.0, 15.0)
	draw_line(shoulder, elbow, Color("2f6877"), 13.0, true)
	draw_line(elbow, hand, Color("4d97a0"), 11.0, true)
	draw_circle(hand, 7.0, Color("d9f1ee"))
	var sword_end := hand + Vector2(70.0, 22.0)
	draw_line(hand, sword_end, Color("eefcff"), 7.0, true)
	draw_line(hand + Vector2(-5.0, -10.0), hand + Vector2(8.0, 10.0), Color("ff704d"), 7.0, true)


func _draw_attack_arms(shoulder: Vector2) -> void:
	var progress := combat.action_progress()
	var anticipation := clampf(progress / 0.25, 0.0, 1.0)
	var follow := clampf((progress - 0.25) / 0.75, 0.0, 1.0)
	var swing_curve := anticipation * anticipation if progress < 0.25 else 1.0 - pow(1.0 - follow, 3.0)
	var start_angle := -2.18 + float(combat.combo_step) * 0.28
	var end_angle := 0.22 + float(combat.combo_step) * 0.22
	if combat.combo_step == 1:
		start_angle = 1.0
		end_angle = -0.55
	var blade_angle := lerpf(start_angle, end_angle, swing_curve)
	var hand := shoulder + Vector2(30.0, 25.0)
	var support := shoulder + Vector2(12.0, 34.0)
	draw_line(shoulder, support, Color("2a5f70"), 12.0, true)
	draw_line(support, hand, Color("4a9da4"), 10.0, true)
	draw_circle(hand, 7.0, Color("e5f7f4"))
	var blade_end := hand + Vector2(cos(blade_angle), sin(blade_angle)) * (105.0 + float(combat.combo_step) * 10.0)
	var blade_back := hand - Vector2(cos(blade_angle), sin(blade_angle)) * 13.0
	draw_line(blade_back, blade_end, Color("efffff"), 8.0, true)
	draw_line(hand + Vector2(cos(blade_angle + PI * 0.5), sin(blade_angle + PI * 0.5)) * 12.0, hand - Vector2(cos(blade_angle + PI * 0.5), sin(blade_angle + PI * 0.5)) * 12.0, Color("ff704d"), 7.0, true)
	if combat.is_attack_active():
		var arc_points := PackedVector2Array()
		for index in range(10):
			var t := float(index) / 9.0
			var arc_angle := blade_angle - 0.8 + t * 0.92
			arc_points.append(hand + Vector2(cos(arc_angle), sin(arc_angle)) * (118.0 + t * 14.0))
		draw_polyline(arc_points, Color(0.45, 0.95, 1.0, 0.82), 11.0, true)


func _draw_dodging_player(hip: Vector2) -> void:
	var progress := combat.action_progress()
	var center := hip + Vector2(progress * 34.0, 25.0 + sin(progress * PI) * 12.0)
	for index in range(3):
		var alpha := 0.14 - float(index) * 0.035
		draw_circle(center - Vector2(28.0 + float(index) * 24.0, 20.0), 32.0, Color(0.32, 0.88, 0.91, alpha))
	draw_circle(center, 35.0, Color("173e4a"))
	draw_arc(center, 35.0, -PI * 0.2, PI * 1.4, 24, Color("73e1e6"), 5.0, true)
	var mask_center := center + Vector2(16.0, -10.0)
	draw_circle(mask_center, 18.0, Color("d9f1ee"))
	draw_line(mask_center + Vector2(5.0, -2.0), mask_center + Vector2(14.0, 0.0), Color("ff704d"), 4.0)


func _draw_dead_player(hip: Vector2) -> void:
	var center := hip + Vector2(0.0, 55.0)
	draw_line(center - Vector2(48.0, 0.0), center + Vector2(50.0, 0.0), Color("204b59"), 26.0, true)
	draw_circle(center + Vector2(57.0, -5.0), 24.0, Color("d9f1ee"))
	draw_line(center + Vector2(60.0, -7.0), center + Vector2(71.0, -7.0), Color("ff704d"), 4.0)


func _draw_enemy(enemy: Dictionary) -> void:
	var x := float(enemy["x"])
	var y := float(enemy["y"])
	var state := String(enemy["state"])
	var brute := bool(enemy["brute"])
	var size_scale := 1.28 if brute else 1.0
	var bob := sin(float(enemy["phase"]) * 2.0) * 4.0
	var center := Vector2(x, y - 67.0 * size_scale + bob)
	if state == "telegraph":
		var pulse := 1.0 + sin(float(enemy["timer"]) * 22.0) * 0.12
		draw_arc(center, 58.0 * size_scale * pulse, 0.0, TAU, 32, Color(1.0, 0.24, 0.22, 0.38), 4.0, true)
	var body_color := Color("5e2739") if not brute else Color("693b22")
	var back := center + Vector2(-34.0, 7.0) * size_scale
	var front := center + Vector2(34.0, 3.0) * size_scale
	draw_line(back, front, body_color, 48.0 * size_scale, true)
	draw_circle(front + Vector2(15.0, -13.0) * size_scale, 28.0 * size_scale, body_color.lightened(0.08))
	var jaw := PackedVector2Array([
		front + Vector2(9.0, 0.0) * size_scale,
		front + Vector2(42.0, 8.0) * size_scale,
		front + Vector2(13.0, 19.0) * size_scale,
	])
	draw_colored_polygon(jaw, Color("311928"))
	var horn := PackedVector2Array([
		front + Vector2(1.0, -28.0) * size_scale,
		front + Vector2(12.0, -53.0) * size_scale,
		front + Vector2(18.0, -23.0) * size_scale,
	])
	draw_colored_polygon(horn, Color("d8b978"))
	draw_circle(front + Vector2(24.0, -15.0) * size_scale, 5.0 * size_scale, Color("ff584c"))
	var leg_swing := sin(float(enemy["phase"])) * 18.0
	draw_line(back + Vector2(8.0, 16.0), Vector2(x - 25.0 + leg_swing, y - 4.0), Color("371b2a"), 13.0 * size_scale, true)
	draw_line(front + Vector2(-5.0, 17.0), Vector2(x + 28.0 - leg_swing, y - 4.0), Color("4a2031"), 13.0 * size_scale, true)
	if brute and state != "dead":
		var hp_ratio := float(enemy["hp"]) / float(enemy["max_hp"])
		draw_rect(Rect2(x - 42.0, center.y - 65.0, 84.0, 7.0), Color("251723"))
		draw_rect(Rect2(x - 42.0, center.y - 65.0, 84.0 * hp_ratio, 7.0), Color("ff8855"))


func _draw_particles() -> void:
	for particle in _particles:
		var ratio := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
		var color: Color = particle["color"]
		color.a *= ratio
		draw_circle(Vector2(particle["position"]), float(particle["radius"]) * (0.45 + ratio * 0.55), color)


func _update_ui() -> void:
	_distance_label.text = "%04d m" % int(distance_m)
	_combo_label.text = "%d KILLS  ·  x%d FLOW" % [combat.kills, maxi(1, combat.combo)]
	_health_label.text = "◆".repeat(combat.health) + "◇".repeat(4 - combat.health)
	if combat.state == RunnerCombatModel.State.DEAD:
		_status_label.text = "RUN ENDED  ·  %d m" % int(distance_m)
		_status_label.add_theme_color_override("font_color", Color("ff756d"))
	elif danger_pulse > 0.0:
		_status_label.text = "READ THE ATTACK"
		_status_label.add_theme_color_override("font_color", Color("ffbc66"))
	elif combat.combo >= 4:
		_status_label.text = "MOMENTUM x%d" % combat.combo
		_status_label.add_theme_color_override("font_color", Color("6de7ee"))
	else:
		_status_label.text = "KEEP MOVING"
		_status_label.add_theme_color_override("font_color", Color("d9edf2"))


func _virtual_width() -> float:
	return size.x / maxf(size.y / BASE_HEIGHT, 0.001)


func _captured_run_distance() -> float:
	if _run_root_forward.size() < 2:
		return RUN_STRIDE * 2.0
	return absf(float(_run_root_forward[-1]) - float(_run_root_forward[0])) * RUN_POSE_SCALE


func _player_x(virtual_width: float) -> float:
	return maxf(MIN_PLAYER_X, virtual_width * PLAYER_X_RATIO)
