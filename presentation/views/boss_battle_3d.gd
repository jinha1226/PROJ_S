class_name BossBattle3D
extends Node3D

const ARENA_RADIUS := 12.6
const PLAYER_SPEED := 5.5
const DODGE_SPEED := 13.5
const DODGE_DURATION := 0.38
const DODGE_COST := 34.0
const ATTACK_RANGE := 2.35
const ATTACK_DURATION := 0.56
const ATTACK_HIT_TIME := 0.25
const BASE_DAMAGE := 18.0

const PLAYER_TEAL := Color("244f56")
const PLAYER_TEAL_LIGHT := Color("3f7a7d")
const IVORY := Color("e7dfcc")
const SCARF_RED := Color("9f3f38")
const BOSS_BRONZE := Color("3f3935")
const BOSS_BRONZE_LIGHT := Color("66584a")
const BOSS_DARK := Color("1b1b20")
const AMBER := Color("f29b3d")
const WATER := Color("18364b")
const STONE := Color("303842")
const MOON := Color("9fc3de")

var _camera: Camera3D
var _camera_focus := Vector3(0.0, 1.2, 1.0)
var _camera_shake: float = 0.0
var _camera_punch: float = 0.0
var _hud: BossHUD3D

var _player_root: Node3D
var _player_model: Node3D
var _player_torso: Node3D
var _player_head: Node3D
var _player_left_arm: Node3D
var _player_right_arm: Node3D
var _player_left_leg: Node3D
var _player_right_leg: Node3D
var _player_sword: Node3D
var _player_scarf: Node3D

var _boss_root: Node3D
var _boss_model: Node3D
var _boss_torso: Node3D
var _boss_weapon_arm: Node3D
var _boss_guard_arm: Node3D
var _boss_weapon: Node3D
var _boss_core: MeshInstance3D
var _boss_weapon_armor: Node3D
var _boss_guard_armor: Node3D

var _material_player: StandardMaterial3D
var _material_player_light: StandardMaterial3D
var _material_ivory: StandardMaterial3D
var _material_scarf: StandardMaterial3D
var _material_boss: StandardMaterial3D
var _material_boss_light: StandardMaterial3D
var _material_boss_dark: StandardMaterial3D
var _material_amber: StandardMaterial3D
var _material_steel: StandardMaterial3D
var _material_stone: StandardMaterial3D

var _elapsed: float = 0.0
var _move_touch := Vector2.ZERO
var _move_input := Vector2.ZERO
var _player_health: float = 100.0
var _player_stamina: float = 100.0
var _stamina_delay: float = 0.0
var _player_invulnerable: float = 0.0
var _dodge_timer: float = 0.0
var _dodge_direction := Vector3(0.0, 0.0, -1.0)
var _dodge_perfect_used: bool = false
var _parry_timer: float = 0.0
var _parry_active: float = 0.0
var _parry_cooldown: float = 0.0
var _attack_elapsed: float = -1.0
var _attack_hit_done: bool = false
var _attack_cooldown: float = 0.0
var _counter_bonus: bool = false

var _boss_health: float = 320.0
var _part_health: Dictionary = {&"weapon_arm": 75.0, &"guard_arm": 75.0}
var _selected_part: StringName = &"core"
var _boss_state: StringName = &"IDLE"
var _boss_pattern: StringName = &""
var _boss_timer: float = 1.2
var _boss_pattern_index: int = 0
var _boss_attack_resolved: bool = false
var _boss_locked_direction := Vector3(0.0, 0.0, 1.0)
var _boss_stagger: float = 0.0

var _battle_time: float = 0.0
var _player_dead: bool = false
var _victory: bool = false
var _feedback_text: String = "APPROACH THE WARDEN"
var _feedback_timer: float = 1.6
var _tutorial_timer: float = 7.0
var _hit_stop: float = 0.0
var _slow_motion: float = 0.0
var _effects: Array[Dictionary] = []


func _ready() -> void:
	_build_materials()
	_build_world()
	_build_player()
	_build_boss()
	_build_hud()
	_restart_battle()


func _process(delta: float) -> void:
	var frame_delta := minf(delta, 0.04)
	_elapsed += frame_delta
	_feedback_timer = maxf(0.0, _feedback_timer - frame_delta)
	_tutorial_timer = maxf(0.0, _tutorial_timer - frame_delta)
	_camera_shake = maxf(0.0, _camera_shake - frame_delta * 8.0)
	_camera_punch = maxf(0.0, _camera_punch - frame_delta * 3.5)
	_update_effects(frame_delta)
	_update_move_input()

	if _hit_stop > 0.0:
		_hit_stop = maxf(0.0, _hit_stop - frame_delta)
		_update_camera(frame_delta)
		_update_hud()
		return

	var world_delta := frame_delta
	if _slow_motion > 0.0:
		_slow_motion = maxf(0.0, _slow_motion - frame_delta)
		world_delta *= 0.38

	if not _player_dead and not _victory:
		_battle_time += frame_delta
		_update_player(world_delta)
		_update_auto_attack(world_delta)
		_update_boss(world_delta)
	_update_models(world_delta)
	_update_camera(frame_delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_try_dodge()
		elif event.keycode == KEY_F:
			_try_parry()
		elif event.keycode == KEY_R and (_player_dead or _victory):
			_restart_battle()


func _build_materials() -> void:
	_material_player = _make_material(PLAYER_TEAL, 0.05, 0.78)
	_material_player_light = _make_material(PLAYER_TEAL_LIGHT, 0.12, 0.68)
	_material_ivory = _make_material(IVORY, 0.0, 0.72)
	_material_scarf = _make_material(SCARF_RED, 0.0, 0.92)
	_material_boss = _make_material(BOSS_BRONZE, 0.62, 0.58)
	_material_boss_light = _make_material(BOSS_BRONZE_LIGHT, 0.72, 0.46)
	_material_boss_dark = _make_material(BOSS_DARK, 0.25, 0.82)
	_material_amber = _make_material(AMBER, 0.15, 0.34, AMBER, 3.2)
	_material_steel = _make_material(Color("9baeb4"), 0.84, 0.28)
	_material_stone = _make_material(STONE, 0.08, 0.94)


func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("07101b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("64829c")
	environment.ambient_light_energy = 0.48
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)

	var moon_light := DirectionalLight3D.new()
	moon_light.light_color = MOON
	moon_light.light_energy = 1.25
	moon_light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	moon_light.shadow_enabled = true
	moon_light.directional_shadow_max_distance = 45.0
	add_child(moon_light)

	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 13.7
	floor_mesh.bottom_radius = 13.7
	floor_mesh.height = 0.46
	floor_mesh.radial_segments = 48
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.material_override = _material_stone
	floor.position.y = -0.34
	add_child(floor)

	var water_material := _make_material(WATER, 0.72, 0.18, Color("163b52"), 0.35)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.albedo_color.a = 0.82
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 12.8
	water_mesh.bottom_radius = 12.8
	water_mesh.height = 0.08
	water_mesh.radial_segments = 48
	var water := MeshInstance3D.new()
	water.mesh = water_mesh
	water.material_override = water_material
	water.position.y = -0.04
	add_child(water)

	for tile_index: int in range(28):
		var angle := TAU * float(tile_index) / 28.0
		var tile_position := Vector3(cos(angle) * 12.2, 0.07, sin(angle) * 12.2)
		var tile := _box(self, "RingTile", Vector3(2.15, 0.24, 1.35), tile_position, _material_stone)
		tile.rotation.y = -angle
		tile.rotation.z = sin(float(tile_index) * 2.1) * 0.025

	for path_index: int in range(9):
		var z := 8.0 - float(path_index) * 2.0
		var path_tile := _box(self, "PathStone", Vector3(2.7, 0.16, 1.55), Vector3(sin(float(path_index) * 1.7) * 0.42, 0.08, z), _material_stone)
		path_tile.rotation.y = sin(float(path_index) * 0.8) * 0.12

	for column_index: int in range(8):
		var column_angle := TAU * float(column_index) / 8.0 + 0.22
		var column_root := Node3D.new()
		column_root.position = Vector3(cos(column_angle) * 11.2, 0.0, sin(column_angle) * 11.2)
		column_root.rotation.y = -column_angle
		add_child(column_root)
		var column_height := 2.4 + float(column_index % 3) * 0.72
		_box(column_root, "ColumnBase", Vector3(1.25, 0.5, 1.25), Vector3(0.0, 0.25, 0.0), _material_stone)
		_box(column_root, "Column", Vector3(0.78, column_height, 0.78), Vector3(0.0, 0.5 + column_height * 0.5, 0.0), _material_stone)
		_box(column_root, "ColumnCap", Vector3(1.05, 0.3, 1.05), Vector3(0.0, 0.65 + column_height, 0.0), _material_stone)

	for brazier_index: int in range(4):
		var brazier_angle := TAU * float(brazier_index) / 4.0 + PI * 0.25
		var brazier_position := Vector3(cos(brazier_angle) * 9.8, 0.0, sin(brazier_angle) * 9.8)
		_cylinder(self, "Brazier", 0.42, 0.58, brazier_position + Vector3(0.0, 0.3, 0.0), _material_boss_dark, 8)
		_sphere(self, "Flame", 0.27, brazier_position + Vector3(0.0, 0.88, 0.0), _material_amber, Vector3(0.7, 1.5, 0.7), 8, 4)
		var fire_light := OmniLight3D.new()
		fire_light.position = brazier_position + Vector3(0.0, 1.2, 0.0)
		fire_light.light_color = Color("ff9a42")
		fire_light.light_energy = 2.0
		fire_light.omni_range = 5.2
		fire_light.shadow_enabled = false
		add_child(fire_light)

	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.near = 0.12
	_camera.far = 80.0
	_camera.current = true
	_camera.position = Vector3(0.0, 14.0, 18.0)
	add_child(_camera)


func _build_player() -> void:
	_player_root = Node3D.new()
	_player_root.name = "MaskedWanderer"
	add_child(_player_root)
	_player_model = Node3D.new()
	_player_model.name = "Visual"
	_player_root.add_child(_player_model)

	_player_torso = Node3D.new()
	_player_torso.position = Vector3(0.0, 1.28, 0.0)
	_player_model.add_child(_player_torso)
	_capsule(_player_torso, "Torso", 0.38, 1.02, Vector3.ZERO, _material_player, Vector3(0.95, 1.0, 0.72), 8, 3)
	_box(_player_torso, "ChestPlate", Vector3(0.82, 0.48, 0.25), Vector3(0.0, 0.15, -0.30), _material_player_light)
	_box(_player_torso, "Belt", Vector3(0.82, 0.15, 0.50), Vector3(0.0, -0.40, 0.0), _material_boss_dark)

	_player_head = Node3D.new()
	_player_head.position = Vector3(0.0, 2.07, 0.0)
	_player_model.add_child(_player_head)
	_sphere(_player_head, "Head", 0.30, Vector3.ZERO, _material_boss_dark, Vector3(0.82, 1.08, 0.82), 8, 4)
	var mask := _sphere(_player_head, "IvoryMask", 0.29, Vector3(0.0, 0.0, -0.13), _material_ivory, Vector3(0.72, 1.08, 0.30), 8, 4)
	mask.rotation.x = -0.08
	_box(_player_head, "MaskBrow", Vector3(0.46, 0.07, 0.11), Vector3(0.0, 0.08, -0.33), _material_boss_dark)

	_player_left_arm = _build_limb(_player_model, "LeftArm", Vector3(-0.50, 1.62, 0.0), 0.25, 0.92, _material_player_light)
	_player_right_arm = _build_limb(_player_model, "RightArm", Vector3(0.50, 1.62, 0.0), 0.25, 0.92, _material_player_light)
	_player_left_leg = _build_limb(_player_model, "LeftLeg", Vector3(-0.23, 0.90, 0.0), 0.27, 1.00, _material_player)
	_player_right_leg = _build_limb(_player_model, "RightLeg", Vector3(0.23, 0.90, 0.0), 0.27, 1.00, _material_player)

	_player_sword = Node3D.new()
	_player_sword.name = "Sword"
	_player_sword.position = Vector3(0.0, -0.78, -0.05)
	_player_right_arm.add_child(_player_sword)
	_box(_player_sword, "Blade", Vector3(0.10, 1.35, 0.16), Vector3(0.0, -0.58, 0.0), _material_steel)
	_box(_player_sword, "Guard", Vector3(0.55, 0.10, 0.16), Vector3(0.0, 0.07, 0.0), _material_boss_light)
	_box(_player_sword, "Grip", Vector3(0.12, 0.38, 0.14), Vector3(0.0, 0.27, 0.0), _material_boss_dark)

	_player_scarf = Node3D.new()
	_player_scarf.position = Vector3(0.0, 1.86, 0.28)
	_player_model.add_child(_player_scarf)
	var scarf_one := _box(_player_scarf, "ScarfTailA", Vector3(0.24, 0.05, 1.05), Vector3(-0.10, 0.0, 0.46), _material_scarf)
	scarf_one.rotation.x = -0.14
	scarf_one.rotation.y = 0.18
	var scarf_two := _box(_player_scarf, "ScarfTailB", Vector3(0.20, 0.05, 0.82), Vector3(0.14, -0.08, 0.36), _material_scarf)
	scarf_two.rotation.x = -0.20
	scarf_two.rotation.y = -0.28


func _build_boss() -> void:
	_boss_root = Node3D.new()
	_boss_root.name = "HollowWarden"
	add_child(_boss_root)
	_boss_model = Node3D.new()
	_boss_model.name = "Visual"
	_boss_root.add_child(_boss_model)

	_boss_torso = Node3D.new()
	_boss_torso.position = Vector3(0.0, 2.65, 0.0)
	_boss_model.add_child(_boss_torso)
	_capsule(_boss_torso, "Torso", 1.12, 2.6, Vector3.ZERO, _material_boss, Vector3(1.22, 1.0, 0.82), 10, 4)
	_box(_boss_torso, "ChestArmor", Vector3(2.35, 1.05, 0.48), Vector3(0.0, 0.34, -0.78), _material_boss_light)
	_box(_boss_torso, "WaistArmor", Vector3(1.80, 0.48, 0.75), Vector3(0.0, -1.05, 0.0), _material_boss_dark)

	var boss_head := Node3D.new()
	boss_head.position = Vector3(0.0, 4.65, 0.0)
	_boss_model.add_child(boss_head)
	_sphere(boss_head, "Head", 0.72, Vector3.ZERO, _material_boss_dark, Vector3(0.86, 1.12, 0.82), 9, 4)
	_box(boss_head, "FacePlate", Vector3(0.96, 0.95, 0.32), Vector3(0.0, 0.0, -0.58), _material_boss_light)
	var horn_left := _cone(boss_head, "HornL", 0.20, 0.95, Vector3(-0.42, 0.72, -0.05), _material_boss_light, 6)
	horn_left.rotation.z = -0.42
	var horn_right := _cone(boss_head, "HornR", 0.20, 0.95, Vector3(0.42, 0.72, -0.05), _material_boss_light, 6)
	horn_right.rotation.z = 0.42

	_boss_weapon_arm = _build_limb(_boss_model, "WeaponArm", Vector3(-1.48, 3.72, 0.0), 0.62, 2.45, _material_boss)
	_boss_guard_arm = _build_limb(_boss_model, "GuardArm", Vector3(1.48, 3.72, 0.0), 0.72, 2.35, _material_boss)
	_boss_weapon_armor = _sphere(_boss_weapon_arm, "WeaponShoulder", 0.88, Vector3(0.0, -0.10, 0.0), _material_boss_light, Vector3(1.12, 0.78, 1.0), 8, 4)
	_boss_guard_armor = _sphere(_boss_guard_arm, "GuardShoulder", 0.96, Vector3(0.0, -0.05, 0.0), _material_boss_light, Vector3(1.20, 0.86, 1.05), 8, 4)

	_boss_weapon = Node3D.new()
	_boss_weapon.name = "HookBlade"
	_boss_weapon.position = Vector3(0.0, -2.15, 0.0)
	_boss_weapon_arm.add_child(_boss_weapon)
	_box(_boss_weapon, "Handle", Vector3(0.22, 1.25, 0.24), Vector3(0.0, 0.35, 0.0), _material_boss_dark)
	var blade := _box(_boss_weapon, "Blade", Vector3(0.48, 2.30, 0.30), Vector3(0.0, -1.15, 0.0), _material_boss_light)
	blade.rotation.z = -0.18
	var hook := _box(_boss_weapon, "Hook", Vector3(1.15, 0.38, 0.32), Vector3(-0.40, -2.10, 0.0), _material_boss_light)
	hook.rotation.z = -0.42

	var left_leg := _build_limb(_boss_model, "LeftLeg", Vector3(-0.68, 1.55, 0.0), 0.60, 2.25, _material_boss)
	var right_leg := _build_limb(_boss_model, "RightLeg", Vector3(0.68, 1.55, 0.0), 0.60, 2.25, _material_boss)
	_box(left_leg, "LeftGreave", Vector3(0.92, 1.32, 0.78), Vector3(0.0, -1.22, -0.06), _material_boss_light)
	_box(right_leg, "RightGreave", Vector3(0.92, 1.32, 0.78), Vector3(0.0, -1.22, -0.06), _material_boss_light)

	_boss_core = _sphere(_boss_torso, "AmberCore", 0.43, Vector3(0.0, 0.22, -1.08), _material_amber, Vector3.ONE, 10, 5)
	for seam_index: int in range(5):
		var seam_angle := TAU * float(seam_index) / 5.0
		var seam := _box(_boss_torso, "EnergySeam", Vector3(0.10, 0.82, 0.08), Vector3(cos(seam_angle) * 0.56, -0.35 + float(seam_index % 2) * 0.22, -1.04), _material_amber)
		seam.rotation.z = seam_angle * 0.35


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_hud = BossHUD3D.new()
	canvas.add_child(_hud)
	_hud.move_changed.connect(_on_move_changed)
	_hud.dodge_pressed.connect(_try_dodge)
	_hud.parry_pressed.connect(_try_parry)
	_hud.target_pressed.connect(_select_target_from_screen)
	_hud.restart_pressed.connect(_restart_battle)


func _restart_battle() -> void:
	_player_root.position = Vector3(0.0, 0.0, 8.4)
	_player_root.rotation = Vector3.ZERO
	_player_model.rotation = Vector3.ZERO
	_player_health = 100.0
	_player_stamina = 100.0
	_stamina_delay = 0.0
	_player_invulnerable = 0.0
	_dodge_timer = 0.0
	_dodge_perfect_used = false
	_parry_timer = 0.0
	_parry_active = 0.0
	_parry_cooldown = 0.0
	_attack_elapsed = -1.0
	_attack_hit_done = false
	_attack_cooldown = 0.0
	_counter_bonus = false
	_boss_root.position = Vector3(0.0, 0.0, -4.0)
	_boss_root.rotation = Vector3(0.0, PI, 0.0)
	_boss_model.rotation = Vector3.ZERO
	_boss_health = 320.0
	_part_health = {&"weapon_arm": 75.0, &"guard_arm": 75.0}
	_boss_weapon_armor.visible = true
	_boss_guard_armor.visible = true
	_boss_weapon.visible = true
	_selected_part = &"core"
	_boss_state = &"IDLE"
	_boss_pattern = &""
	_boss_timer = 1.2
	_boss_pattern_index = 0
	_boss_attack_resolved = false
	_boss_locked_direction = Vector3(0.0, 0.0, 1.0)
	_boss_stagger = 0.0
	_move_touch = Vector2.ZERO
	_move_input = Vector2.ZERO
	_battle_time = 0.0
	_player_dead = false
	_victory = false
	_feedback_text = "APPROACH THE WARDEN"
	_feedback_timer = 1.6
	_tutorial_timer = 7.0
	_hit_stop = 0.0
	_slow_motion = 0.0
	_camera_shake = 0.0
	_camera_punch = 0.0
	for effect: Dictionary in _effects:
		var node := effect.get("node") as Node
		if is_instance_valid(node):
			node.queue_free()
	_effects.clear()


func _update_move_input() -> void:
	var keyboard := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)
	_move_input = keyboard.normalized() if keyboard.length_squared() > 0.01 else _move_touch


func _update_player(delta: float) -> void:
	_player_invulnerable = maxf(0.0, _player_invulnerable - delta)
	_stamina_delay = maxf(0.0, _stamina_delay - delta)
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_parry_cooldown = maxf(0.0, _parry_cooldown - delta)
	_parry_timer = maxf(0.0, _parry_timer - delta)
	_parry_active = maxf(0.0, _parry_active - delta)
	if _stamina_delay <= 0.0 and _dodge_timer <= 0.0:
		_player_stamina = minf(100.0, _player_stamina + 30.0 * delta)

	var movement := Vector3(_move_input.x, 0.0, _move_input.y)
	if _dodge_timer > 0.0:
		_dodge_timer = maxf(0.0, _dodge_timer - delta)
		_player_root.position += _dodge_direction * DODGE_SPEED * delta
	else:
		var move_scale := 0.42 if _attack_elapsed >= 0.0 or _parry_timer > 0.0 else 1.0
		_player_root.position += movement * PLAYER_SPEED * move_scale * delta
	_clamp_to_arena(_player_root, 0.75)

	var boss_delta := _player_root.position - _boss_root.position
	boss_delta.y = 0.0
	if boss_delta.length() < 2.25:
		_player_root.position = _boss_root.position + boss_delta.normalized() * 2.25

	var target_direction := _target_position() - _player_root.position
	target_direction.y = 0.0
	if target_direction.length_squared() > 0.01:
		var desired_yaw := atan2(-target_direction.x, -target_direction.z)
		_player_root.rotation.y = lerp_angle(_player_root.rotation.y, desired_yaw, 1.0 - exp(-11.0 * delta))


func _try_dodge() -> void:
	if _player_dead or _victory or _dodge_timer > 0.0 or _player_stamina < DODGE_COST:
		return
	_player_stamina -= DODGE_COST
	_stamina_delay = 0.72
	_dodge_timer = DODGE_DURATION
	_player_invulnerable = maxf(_player_invulnerable, DODGE_DURATION + 0.08)
	_dodge_perfect_used = false
	_attack_elapsed = -1.0
	_parry_timer = 0.0
	_parry_active = 0.0
	var movement := Vector3(_move_input.x, 0.0, _move_input.y)
	_dodge_direction = movement.normalized()
	if _dodge_direction.length_squared() < 0.01:
		_dodge_direction = (_player_root.position - _boss_root.position).normalized()
	_spawn_burst(_player_root.position + Vector3.UP * 0.2, Color("63dbc2"), 8, 4.2)


func _try_parry() -> void:
	if _player_dead or _victory or _dodge_timer > 0.0 or _parry_cooldown > 0.0:
		return
	_parry_timer = 0.36
	_parry_active = 0.20
	_parry_cooldown = 0.78
	_attack_elapsed = -1.0


func _update_auto_attack(delta: float) -> void:
	if _dodge_timer > 0.0 or _parry_timer > 0.0 or _boss_state == &"DEAD":
		_attack_elapsed = -1.0
		return
	var target := _target_position()
	var to_target := target - _player_root.position
	to_target.y = 0.0
	if _attack_elapsed >= 0.0:
		_attack_elapsed += delta
		if not _attack_hit_done and _attack_elapsed >= ATTACK_HIT_TIME:
			_attack_hit_done = true
			_resolve_player_attack()
		if _attack_elapsed >= ATTACK_DURATION:
			_attack_elapsed = -1.0
			_attack_cooldown = 0.15
		return
	if _attack_cooldown > 0.0 or to_target.length() > ATTACK_RANGE:
		return
	var move_world := Vector3(_move_input.x, 0.0, _move_input.y)
	var moving_away := move_world.length_squared() > 0.1 and move_world.dot(to_target.normalized()) < -0.32
	if moving_away:
		return
	_attack_elapsed = 0.0
	_attack_hit_done = false


func _resolve_player_attack() -> void:
	var target := _target_position()
	var flat_delta := target - _player_root.position
	flat_delta.y = 0.0
	if flat_delta.length() > ATTACK_RANGE + 0.35:
		return
	var damage := BASE_DAMAGE
	if _boss_state == &"RECOVERY":
		damage *= 1.28
	if _counter_bonus:
		damage *= 1.70
		_counter_bonus = false
		_set_feedback("COUNTER STRIKE", 0.75)
	_damage_part(_selected_part, damage)
	_hit_stop = 0.055
	_camera_shake = 0.22
	_camera_punch = 0.07
	_spawn_burst(target, Color("ffc46b"), 10, 5.2)


func _damage_part(part_id: StringName, damage: float) -> void:
	if part_id == &"core":
		_boss_health = maxf(0.0, _boss_health - damage)
	else:
		if not _part_alive(part_id):
			return
		_part_health[part_id] = maxf(0.0, float(_part_health.get(part_id, 0.0)) - damage)
		_boss_health = maxf(0.0, _boss_health - damage * 0.60)
		if float(_part_health[part_id]) <= 0.0:
			_break_part(part_id)
	if _boss_health <= 0.0:
		_defeat_boss()


func _break_part(part_id: StringName) -> void:
	_boss_health = maxf(0.0, _boss_health - 18.0)
	_slow_motion = 0.55
	_hit_stop = 0.11
	_camera_shake = 0.48
	_camera_punch = 0.15
	if part_id == &"weapon_arm":
		_boss_weapon_armor.visible = false
		_boss_weapon.visible = false
	else:
		_boss_guard_armor.visible = false
	if is_inside_tree():
		_spawn_burst(_part_position(part_id), Color("f1a24f"), 24, 8.0)
	_set_feedback("%s BROKEN" % _part_name(part_id), 1.15)
	_selected_part = &"core"
	if _boss_health <= 0.0:
		_defeat_boss()


func _update_boss(delta: float) -> void:
	if _boss_state == &"DEAD":
		return
	var face_direction := _player_root.position - _boss_root.position
	face_direction.y = 0.0
	if face_direction.length_squared() > 0.01 and _boss_state != &"ACTIVE":
		var desired_yaw := atan2(-face_direction.x, -face_direction.z)
		_boss_root.rotation.y = lerp_angle(_boss_root.rotation.y, desired_yaw, 1.0 - exp(-5.0 * delta))

	match _boss_state:
		&"IDLE":
			_boss_timer -= delta
			if _boss_timer <= 0.0:
				_begin_pattern()
		&"TELEGRAPH":
			_boss_timer -= delta
			if _boss_timer <= 0.0:
				_begin_active()
		&"ACTIVE":
			_update_active_boss(delta)
		&"RECOVERY":
			_boss_timer -= delta
			if _boss_timer <= 0.0:
				_boss_state = &"IDLE"
				_boss_timer = 0.38 if _has_broken_part() else 0.56


func _begin_pattern() -> void:
	var patterns: Array[StringName] = []
	if _part_alive(&"weapon_arm"):
		patterns.append(&"SWEEP")
	if _part_alive(&"guard_arm"):
		patterns.append(&"SLAM")
	patterns.append(&"CHARGE")
	_boss_pattern = patterns[_boss_pattern_index % patterns.size()]
	_boss_pattern_index += 1
	_boss_state = &"TELEGRAPH"
	_boss_attack_resolved = false
	_boss_locked_direction = (_player_root.position - _boss_root.position).normalized()
	_boss_locked_direction.y = 0.0
	match _boss_pattern:
		&"SWEEP": _boss_timer = 0.82
		&"SLAM": _boss_timer = 1.02
		&"CHARGE": _boss_timer = 0.76


func _begin_active() -> void:
	_boss_state = &"ACTIVE"
	_boss_attack_resolved = false
	match _boss_pattern:
		&"SWEEP": _boss_timer = 0.28
		&"SLAM": _boss_timer = 0.25
		&"CHARGE": _boss_timer = 0.62


func _update_active_boss(delta: float) -> void:
	_boss_timer -= delta
	if _boss_pattern == &"CHARGE":
		_boss_root.position += _boss_locked_direction * 8.7 * delta
		_clamp_to_arena(_boss_root, 2.0)
		if _flat_distance(_boss_root.position, _player_root.position) <= 2.55:
			_try_boss_damage(30.0, false)
	elif not _boss_attack_resolved:
		_boss_attack_resolved = true
		if _boss_pattern == &"SWEEP" and _flat_distance(_boss_root.position, _player_root.position) <= 5.2:
			_try_boss_damage(24.0, true)
		elif _boss_pattern == &"SLAM" and _flat_distance(_boss_root.position, _player_root.position) <= 4.6:
			_try_boss_damage(33.0, false)
		_spawn_impact_ring(_boss_root.position + Vector3.UP * 0.08, Color("e66a52") if _boss_pattern == &"SLAM" else Color("e6a45c"))
	if _boss_timer <= 0.0 and _boss_state == &"ACTIVE":
		_boss_state = &"RECOVERY"
		_boss_timer = 1.0 if _boss_pattern == &"CHARGE" else 0.78


func _try_boss_damage(damage: float, parryable: bool) -> void:
	if parryable and _parry_active > 0.0:
		_successful_parry()
		return
	if _dodge_timer > 0.0:
		var dodge_elapsed := DODGE_DURATION - _dodge_timer
		if dodge_elapsed <= 0.21 and not _dodge_perfect_used:
			_dodge_perfect_used = true
			_successful_dodge()
		return
	if _player_invulnerable > 0.0:
		return
	_player_health = maxf(0.0, _player_health - damage)
	_player_invulnerable = 0.76
	_hit_stop = 0.085
	_camera_shake = 0.52
	_spawn_burst(_player_root.position + Vector3.UP, Color("e9665e"), 16, 6.2)
	_set_feedback("HIT", 0.55)
	if _player_health <= 0.0:
		_player_dead = true
		_slow_motion = 0.62
		_feedback_text = "YOU FELL"
		_feedback_timer = 99.0


func _successful_parry() -> void:
	_parry_active = 0.0
	_boss_state = &"RECOVERY"
	_boss_timer = 1.28
	_counter_bonus = true
	_slow_motion = 0.42
	_hit_stop = 0.10
	_camera_shake = 0.40
	_camera_punch = 0.12
	if is_inside_tree():
		_spawn_burst(_part_position(&"weapon_arm"), Color("fff0af"), 22, 7.5)
	_set_feedback("PERFECT PARRY", 0.95)


func _successful_dodge() -> void:
	_counter_bonus = true
	_slow_motion = 0.30
	_camera_punch = 0.08
	_spawn_burst(_player_root.position + Vector3.UP * 0.7, Color("5de2c3"), 14, 5.8)
	_set_feedback("PERFECT DODGE", 0.80)


func _defeat_boss() -> void:
	_boss_state = &"DEAD"
	_victory = true
	_slow_motion = 0.72
	_hit_stop = 0.14
	_camera_shake = 0.68
	_camera_punch = 0.18
	if is_inside_tree():
		_spawn_burst(_boss_core.global_position, AMBER, 34, 10.0)
	_feedback_text = "WARDEN DEFEATED"
	_feedback_timer = 99.0


func _update_models(_delta: float) -> void:
	var move_amount := _move_input.length()
	var walk_wave := sin(_elapsed * 10.0) * move_amount
	var breathe := sin(_elapsed * 2.2)

	_player_model.position.y = 0.04 + absf(sin(_elapsed * 10.0)) * 0.08 * move_amount
	_player_left_leg.rotation.x = walk_wave * 0.62
	_player_right_leg.rotation.x = -walk_wave * 0.62
	_player_left_arm.rotation.x = -walk_wave * 0.38
	_player_right_arm.rotation = Vector3(-walk_wave * 0.25, 0.0, -0.10)
	_player_torso.rotation = Vector3(0.0, 0.0, -walk_wave * 0.035)
	_player_head.rotation.y = sin(_elapsed * 1.4) * 0.035
	_player_scarf.rotation.x = -0.14 - move_amount * 0.16 + sin(_elapsed * 6.5) * 0.04
	_player_scarf.rotation.y = sin(_elapsed * 4.2) * 0.10

	if _attack_elapsed >= 0.0:
		var attack_ratio := clampf(_attack_elapsed / ATTACK_DURATION, 0.0, 1.0)
		var slash := sin(attack_ratio * PI)
		_player_right_arm.rotation.x = -1.65 + attack_ratio * 2.55
		_player_right_arm.rotation.z = -0.55 + slash * 0.35
		_player_torso.rotation.y = -0.46 + attack_ratio * 0.92
	elif _parry_timer > 0.0:
		var parry_ratio := 1.0 - _parry_timer / 0.36
		_player_right_arm.rotation = Vector3(-1.25, -0.65, -0.72)
		_player_left_arm.rotation = Vector3(-0.78, 0.28, 0.62)
		_player_torso.rotation.y = sin(parry_ratio * PI) * 0.18
	if _dodge_timer > 0.0:
		var dodge_ratio := 1.0 - _dodge_timer / DODGE_DURATION
		_player_model.rotation.x = sin(dodge_ratio * PI) * -0.72
		_player_model.rotation.z = sin(dodge_ratio * TAU) * 0.12
	else:
		_player_model.rotation.x = lerpf(_player_model.rotation.x, 0.0, 0.28)
		_player_model.rotation.z = lerpf(_player_model.rotation.z, 0.0, 0.28)

	_boss_model.position.y = breathe * 0.055
	_boss_torso.scale = Vector3(1.0 + breathe * 0.018, 1.0 - breathe * 0.012, 1.0 + breathe * 0.018)
	_boss_weapon_arm.rotation = Vector3(0.06, 0.0, -0.10)
	_boss_guard_arm.rotation = Vector3(0.04, 0.0, 0.10)
	_boss_torso.rotation = Vector3.ZERO
	if _boss_state == &"TELEGRAPH":
		var telegraph_duration := _pattern_telegraph_duration()
		var telegraph_ratio := 1.0 - clampf(_boss_timer / telegraph_duration, 0.0, 1.0)
		if _boss_pattern == &"SWEEP":
			_boss_weapon_arm.rotation = Vector3(-1.10 * telegraph_ratio, -0.48 * telegraph_ratio, -0.55 * telegraph_ratio)
			_boss_torso.rotation.y = -0.52 * telegraph_ratio
		elif _boss_pattern == &"SLAM":
			_boss_guard_arm.rotation = Vector3(-2.15 * telegraph_ratio, 0.0, 0.38)
			_boss_torso.rotation.x = -0.25 * telegraph_ratio
		elif _boss_pattern == &"CHARGE":
			_boss_torso.rotation.x = -0.46 * telegraph_ratio
			_boss_weapon_arm.rotation.x = 0.45 * telegraph_ratio
	elif _boss_state == &"ACTIVE":
		if _boss_pattern == &"SWEEP":
			var active_ratio := 1.0 - clampf(_boss_timer / 0.28, 0.0, 1.0)
			_boss_weapon_arm.rotation = Vector3(-0.95 + active_ratio * 1.65, -1.25 + active_ratio * 2.5, -0.48)
			_boss_torso.rotation.y = -0.55 + active_ratio * 1.1
		elif _boss_pattern == &"SLAM":
			var slam_ratio := 1.0 - clampf(_boss_timer / 0.25, 0.0, 1.0)
			_boss_guard_arm.rotation.x = lerpf(-2.15, 0.82, slam_ratio)
			_boss_torso.rotation.x = lerpf(-0.25, 0.30, slam_ratio)
		elif _boss_pattern == &"CHARGE":
			_boss_torso.rotation.x = -0.52
	elif _boss_state == &"RECOVERY":
		_boss_torso.rotation.x = 0.18
		_boss_weapon_arm.rotation.x = 0.48
		_boss_guard_arm.rotation.x = 0.42
	elif _boss_state == &"DEAD":
		_boss_model.rotation.z = lerpf(_boss_model.rotation.z, 1.22, 0.035)

	_boss_core.scale = Vector3.ONE * (1.0 + sin(_elapsed * 5.2) * 0.10)


func _update_camera(delta: float) -> void:
	var flat_distance := _flat_distance(_player_root.position, _boss_root.position)
	var far_ratio := clampf((flat_distance - 3.2) / 9.5, 0.0, 1.0)
	var axis := _player_root.position - _boss_root.position
	axis.y = 0.0
	axis = axis.normalized() if axis.length_squared() > 0.01 else Vector3(0.0, 0.0, 1.0)
	var focus_target := _player_root.position.lerp(_target_position(), 0.46)
	focus_target.y = 1.35 + far_ratio * 0.75
	var camera_height := lerpf(7.4, 14.8, far_ratio)
	var camera_back := lerpf(7.8, 15.8, far_ratio)
	if _boss_state == &"TELEGRAPH" and (_boss_pattern == &"SLAM" or _boss_pattern == &"CHARGE"):
		camera_height = maxf(camera_height, 12.8)
		camera_back = maxf(camera_back, 13.8)
	var desired_position := focus_target + axis * camera_back + Vector3.UP * camera_height
	desired_position -= axis * _camera_punch * 4.0
	var response := 1.0 - exp(-4.4 * delta)
	_camera_focus = _camera_focus.lerp(focus_target, response)
	_camera.position = _camera.position.lerp(desired_position, response)
	var shake := Vector3(sin(_elapsed * 73.0), cos(_elapsed * 89.0), sin(_elapsed * 61.0)) * _camera_shake
	_camera.position += shake
	_camera.look_at(_camera_focus, Vector3.UP)


func _update_hud() -> void:
	if _hud == null:
		return
	var flash := 0.0
	if _boss_state == &"TELEGRAPH" and _boss_pattern == &"SWEEP":
		flash = clampf(1.0 - _boss_timer / 0.24, 0.0, 1.0)
	_hud.set_battle_data({
		"player_health": _player_health,
		"player_stamina": _player_stamina,
		"boss_health": 100.0 * _boss_health / 320.0,
		"target_name": _part_name(_selected_part),
		"feedback_text": _feedback_text,
		"feedback_alpha": clampf(_feedback_timer * 2.2, 0.0, 1.0),
		"tutorial_alpha": clampf(_tutorial_timer, 0.0, 1.0),
		"battle_over": _player_dead or _victory,
		"victory": _victory,
		"battle_time": _battle_time,
		"dodge_ready": _player_stamina >= DODGE_COST and _dodge_timer <= 0.0,
		"parry_ready": _parry_cooldown <= 0.0,
		"parry_flash": flash,
	})


func _on_move_changed(direction: Vector2) -> void:
	_move_touch = direction


func _select_target_from_screen(screen_position: Vector2) -> void:
	if _player_dead or _victory:
		return
	var candidates: Array[StringName] = [&"core"]
	if _part_alive(&"weapon_arm"):
		candidates.append(&"weapon_arm")
	if _part_alive(&"guard_arm"):
		candidates.append(&"guard_arm")
	var closest: StringName = &""
	var closest_distance := 96.0
	for part_id: StringName in candidates:
		var projected := _camera.unproject_position(_part_position(part_id))
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = part_id
	if closest == &"":
		return
	_selected_part = closest
	_set_feedback("TARGET · %s" % _part_name(closest), 0.62)
	_camera_punch = 0.035


func _target_position() -> Vector3:
	return _part_position(_selected_part)


func _part_position(part_id: StringName) -> Vector3:
	match part_id:
		&"weapon_arm": return _boss_weapon_arm.global_position + Vector3.UP * -0.8
		&"guard_arm": return _boss_guard_arm.global_position + Vector3.UP * -0.8
		_: return _boss_core.global_position


func _part_alive(part_id: StringName) -> bool:
	return float(_part_health.get(part_id, 0.0)) > 0.0


func _part_name(part_id: StringName) -> String:
	match part_id:
		&"weapon_arm": return "HOOK ARM"
		&"guard_arm": return "GUARD ARM"
		_: return "CORE"


func _has_broken_part() -> bool:
	return not _part_alive(&"weapon_arm") or not _part_alive(&"guard_arm")


func _pattern_telegraph_duration() -> float:
	match _boss_pattern:
		&"SWEEP": return 0.82
		&"SLAM": return 1.02
		_: return 0.76


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _clamp_to_arena(node: Node3D, margin: float) -> void:
	var flat := Vector2(node.position.x, node.position.z)
	var maximum := ARENA_RADIUS - margin
	if flat.length() > maximum:
		flat = flat.normalized() * maximum
		node.position.x = flat.x
		node.position.z = flat.y


func _set_feedback(text: String, duration: float) -> void:
	_feedback_text = text
	_feedback_timer = duration


func _spawn_burst(position: Vector3, color: Color, count: int, speed: float) -> void:
	var effect_material := _make_material(color, 0.25, 0.45, color, 1.8)
	for index: int in range(count):
		var angle := TAU * float(index) / float(count) + float(index % 3) * 0.17
		var node := _box(self, "ImpactShard", Vector3(0.09, 0.09, 0.32), position, effect_material)
		node.rotation = Vector3(angle * 0.4, angle, angle * 0.2)
		var velocity := Vector3(cos(angle), 0.35 + float(index % 4) * 0.16, sin(angle)) * speed
		_effects.append({"node": node, "velocity": velocity, "time": 0.0, "duration": 0.48 + float(index % 3) * 0.08, "gravity": 8.0})


func _spawn_impact_ring(position: Vector3, color: Color) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.90
	torus.outer_radius = 1.04
	torus.rings = 24
	torus.ring_segments = 6
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = _make_material(color, 0.1, 0.45, color, 1.2)
	ring.position = position
	add_child(ring)
	_effects.append({"node": ring, "velocity": Vector3.ZERO, "time": 0.0, "duration": 0.55, "gravity": 0.0, "ring": true})


func _update_effects(delta: float) -> void:
	for index: int in range(_effects.size() - 1, -1, -1):
		var effect := _effects[index]
		var node := effect.get("node") as Node3D
		if not is_instance_valid(node):
			_effects.remove_at(index)
			continue
		var time := float(effect.get("time", 0.0)) + delta
		effect["time"] = time
		var duration := float(effect.get("duration", 0.5))
		if bool(effect.get("ring", false)):
			var ratio := clampf(time / duration, 0.0, 1.0)
			node.scale = Vector3.ONE * (1.0 + ratio * 4.8)
		else:
			var velocity := effect.get("velocity", Vector3.ZERO) as Vector3
			velocity.y -= float(effect.get("gravity", 0.0)) * delta
			effect["velocity"] = velocity
			node.position += velocity * delta
			node.rotation += Vector3(2.3, 3.7, 2.9) * delta
		if time >= duration:
			node.queue_free()
			_effects.remove_at(index)


func _make_material(
	color: Color,
	metallic: float,
	roughness: float,
	emission: Color = Color.BLACK,
	emission_energy: float = 0.0
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material


func _box(parent: Node, node_name: String, box_size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	return instance


func _sphere(
	parent: Node,
	node_name: String,
	radius: float,
	position: Vector3,
	material: Material,
	scale_value: Vector3 = Vector3.ONE,
	radial_segments: int = 8,
	rings: int = 4
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.scale = scale_value
	parent.add_child(instance)
	return instance


func _capsule(
	parent: Node,
	node_name: String,
	radius: float,
	height: float,
	position: Vector3,
	material: Material,
	scale_value: Vector3 = Vector3.ONE,
	radial_segments: int = 8,
	rings: int = 3
) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.scale = scale_value
	parent.add_child(instance)
	return instance


func _cylinder(parent: Node, node_name: String, radius: float, height: float, position: Vector3, material: Material, segments: int = 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	return instance


func _cone(parent: Node, node_name: String, radius: float, height: float, position: Vector3, material: Material, segments: int = 6) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	return instance


func _build_limb(parent: Node3D, node_name: String, position: Vector3, radius: float, length: float, material: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = position
	parent.add_child(pivot)
	_capsule(pivot, "%sMesh" % node_name, radius, length, Vector3(0.0, -length * 0.48, 0.0), material, Vector3(0.92, 1.0, 0.92), 8, 3)
	return pivot
