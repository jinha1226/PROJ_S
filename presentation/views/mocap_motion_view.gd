class_name MocapMotionView
extends Node3D

const CLIP_PATH := "res://assets/mocap/cmu/02_07_swordplay_game.json"
const BODY_COLOR := Color("58d8e8")
const JOINT_COLOR := Color("d7fbff")
const WEAPON_COLOR := Color("ff7448")

var _fps: float = 30.0
var _joint_names: Array = []
var _joint_index: Dictionary = {}
var _frames: Array = []
var _bone_specs: Array = []
var _joint_nodes: Array[MeshInstance3D] = []
var _bone_nodes: Array[MeshInstance3D] = []
var _rig_root: Node3D
var _elapsed := 0.0
var _speed := 1.0
var _paused := false
var _status_label: Label
var _pause_button: Button
var _speed_button: Button


func _ready() -> void:
	_load_clip()
	_build_stage()
	_build_mannequin()
	_build_ui()
	_apply_time(0.0)
	set_process(true)


func _process(delta: float) -> void:
	if _paused or _frames.is_empty():
		return
	var motion_duration := float(_frames.size() - 1) / _fps
	_elapsed += delta * _speed
	if _elapsed > motion_duration + 0.42:
		_elapsed = 0.0
	_apply_time(minf(_elapsed, motion_duration))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_rig_root.rotation.y += event.relative.x * 0.006
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_rig_root.rotation.y += event.relative.x * 0.006


func _load_clip() -> void:
	var file := FileAccess.open(CLIP_PATH, FileAccess.READ)
	assert(file != null, "Mocap clip is missing")
	var payload: Variant = JSON.parse_string(file.get_as_text())
	assert(payload is Dictionary, "Mocap clip JSON is invalid")
	_fps = float(payload.get("fps", 30.0))
	_joint_names = payload.get("joints", [])
	_frames = payload.get("frames", [])
	_bone_specs = payload.get("bones", [])
	for index in range(_joint_names.size()):
		_joint_index[String(_joint_names[index])] = index


func _build_stage() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("07111f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("7db6d1")
	environment.ambient_light_energy = 0.68
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment_node.environment = environment
	add_child(environment_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	light.light_color = Color("a8dfff")
	light.light_energy = 1.25
	light.shadow_enabled = true
	add_child(light)

	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.2, 2.2, 1.0)
	rim.light_color = WEAPON_COLOR
	rim.light_energy = 3.0
	rim.omni_range = 5.0
	add_child(rim)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("101b2a")
	floor_material.metallic = 0.18
	floor_material.roughness = 0.72
	floor.material_override = floor_material
	add_child(floor)

	for radius in [1.4, 2.3, 3.2]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.012
		torus.outer_radius = radius + 0.012
		torus.rings = 32
		torus.ring_segments = 6
		ring.mesh = torus
		ring.position.y = 0.008
		var ring_material := StandardMaterial3D.new()
		ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_material.albedo_color = Color(0.19, 0.39, 0.50, 0.36)
		ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = ring_material
		add_child(ring)

	var camera := Camera3D.new()
	camera.position = Vector3(3.45, 2.55, 5.85)
	camera.fov = 37.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.25, 0.0), Vector3.UP)


func _build_mannequin() -> void:
	_rig_root = Node3D.new()
	_rig_root.name = "MocapMannequin"
	add_child(_rig_root)

	var body_material := _make_material(BODY_COLOR, 0.14)
	var joint_material := _make_material(JOINT_COLOR, 0.42)
	var weapon_material := _make_material(WEAPON_COLOR, 0.78)

	for joint_name in _joint_names:
		var joint := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var is_tip := String(joint_name) == "sword_tip"
		sphere.radius = 0.035 if is_tip else 0.052
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		joint.mesh = sphere
		joint.material_override = weapon_material if is_tip else joint_material
		_rig_root.add_child(joint)
		_joint_nodes.append(joint)

	for spec_value in _bone_specs:
		var spec: Dictionary = spec_value
		var bone := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		var is_weapon := String(spec.get("kind", "body")) == "weapon"
		var radius := 0.027 if is_weapon else 0.041
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = 1.0
		cylinder.radial_segments = 8
		bone.mesh = cylinder
		bone.material_override = weapon_material if is_weapon else body_material
		_rig_root.add_child(bone)
		_bone_nodes.append(bone)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(ui)

	var eyebrow := Label.new()
	eyebrow.text = "REAL MOCAP / SKELETON TEST"
	eyebrow.add_theme_color_override("font_color", Color("78ddeb"))
	eyebrow.add_theme_font_size_override("font_size", 15)
	eyebrow.position = Vector2(22, 24)
	ui.add_child(eyebrow)

	var title := Label.new()
	title.text = "SWORDPLAY MOTION"
	title.add_theme_color_override("font_color", Color("eefaff"))
	title.add_theme_font_size_override("font_size", 29)
	title.position = Vector2(20, 48)
	ui.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "CMU 02_07  |  30 FPS  |  DRAG TO ROTATE"
	subtitle.add_theme_color_override("font_color", Color("91a7b4"))
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.position = Vector2(22, 86)
	ui.add_child(subtitle)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color("dcecf2"))
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status_label.position = Vector2(-118, -116)
	_status_label.size = Vector2(236, 28)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(_status_label)

	_pause_button = Button.new()
	_pause_button.text = "PAUSE"
	_pause_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pause_button.position = Vector2(-124, -76)
	_pause_button.size = Vector2(116, 48)
	_pause_button.add_theme_font_size_override("font_size", 15)
	_pause_button.pressed.connect(_toggle_pause)
	ui.add_child(_pause_button)

	_speed_button = Button.new()
	_speed_button.text = "SPEED 1.0x"
	_speed_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_speed_button.position = Vector2(8, -76)
	_speed_button.size = Vector2(116, 48)
	_speed_button.add_theme_font_size_override("font_size", 15)
	_speed_button.pressed.connect(_toggle_speed)
	ui.add_child(_speed_button)

	var credit := Label.new()
	credit.text = "Motion data: mocap.cs.cmu.edu / NSF EIA-0196217"
	credit.add_theme_color_override("font_color", Color("607683"))
	credit.add_theme_font_size_override("font_size", 10)
	credit.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	credit.position = Vector2(-190, -22)
	credit.size = Vector2(380, 18)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(credit)


func _make_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.24
	material.roughness = 0.34
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	return material


func _apply_time(time: float) -> void:
	if _frames.is_empty():
		return
	var frame_value := time * _fps
	var frame_a := mini(floori(frame_value), _frames.size() - 1)
	var frame_b := mini(frame_a + 1, _frames.size() - 1)
	var blend := frame_value - float(frame_a)
	var points_a: Array = _frames[frame_a]
	var points_b: Array = _frames[frame_b]
	var points: Array[Vector3] = []
	for index in range(_joint_names.size()):
		var a := _array_to_vec3(points_a[index])
		var b := _array_to_vec3(points_b[index])
		var point := a.lerp(b, blend)
		points.append(point)
		_joint_nodes[index].position = point

	for index in range(_bone_specs.size()):
		var spec: Dictionary = _bone_specs[index]
		var start: Vector3 = points[int(_joint_index[String(spec["a"])])]
		var end: Vector3 = points[int(_joint_index[String(spec["b"])])]
		_set_bone_transform(_bone_nodes[index], start, end)

	_status_label.text = "FRAME %02d / %02d    %.2f SEC" % [frame_a + 1, _frames.size(), time]


func _set_bone_transform(node: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var direction := end - start
	var length := direction.length()
	if length < 0.0001:
		node.visible = false
		return
	node.visible = true
	node.position = (start + end) * 0.5
	node.quaternion = Quaternion(Vector3.UP, direction / length)
	node.scale = Vector3(1.0, length, 1.0)


func _array_to_vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _toggle_pause() -> void:
	_paused = not _paused
	_pause_button.text = "PLAY" if _paused else "PAUSE"


func _toggle_speed() -> void:
	_speed = 0.5 if is_equal_approx(_speed, 1.0) else 1.0
	_speed_button.text = "SPEED %.1fx" % _speed
