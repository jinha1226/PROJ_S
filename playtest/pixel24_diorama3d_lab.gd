class_name Pixel24Diorama3DLab
extends Control

const Factory = preload("res://playtest/pixel24_diorama3d_factory.gd")
const FONT: FontFile = preload("res://assets/fonts/LivingWorldMonoKRBold.ttf")

const GRID_SIZE := 18
const RENDER_SIZE := Vector2i(432, 432)
const CAMERA_ORTHO_SIZE := 18.0
const WORLD_UNITS_PER_CELL := 1.0
const PIXELS_PER_CELL := 24.0
const HUMAN_START := Vector2i(8, 14)
const DWARF_CELL := Vector2i(6, 11)
const GOBLIN_CELL := Vector2i(11, 12)
const TREE_TRUNK_CELL := Vector2i(8, 12)
const STORAGE_ORIGIN := Vector2i(2, 2)
const STORAGE_FOOTPRINT := Vector2i(3, 3)
const ARMORY_ORIGIN := Vector2i(11, 3)
const ARMORY_FOOTPRINT := Vector2i(3, 2)
const LOW_WALL_CELLS := [
	Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6),
	Vector2i(9, 6), Vector2i(5, 7),
]
const WATER_CELLS := [
	Vector2i(14, 13), Vector2i(15, 13), Vector2i(16, 13),
	Vector2i(14, 14), Vector2i(15, 14), Vector2i(16, 14),
	Vector2i(14, 15), Vector2i(15, 15), Vector2i(16, 15),
]
const PATH_CELLS := [
	Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9), Vector2i(8, 9),
	Vector2i(9, 9), Vector2i(10, 9), Vector2i(11, 9), Vector2i(12, 9),
	Vector2i(8, 10), Vector2i(8, 11), Vector2i(8, 13), Vector2i(8, 14),
	Vector2i(8, 15), Vector2i(8, 16),
]
const CANOPY_WALKABLE_CELLS := [
	Vector2i(8, 13), Vector2i(7, 12), Vector2i(9, 12),
]

var viewport_container: SubViewportContainer
var lab_viewport: SubViewport
var world_root: Node3D
var fixture_root: Node3D
var camera: Camera3D
var human: Node3D
var dwarf: Node3D
var goblin: Node3D
var tree: Node3D
var selection_ring: MeshInstance3D
var status_label: Label
var gear_button: Button
var input_catcher: Control
var human_cell := HUMAN_START
var sword_equipped := true
var interaction_count := 0
var authoritative_state_accessed := false
var _occupancy: Dictionary = {}
var _canopy_faded := false


func _ready() -> void:
	if lab_viewport != null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(432, 560)
	_build_viewport()
	_build_hud()
	_build_fixture()
	reset_demo()
	set_process_unhandled_key_input(true)


func _build_viewport() -> void:
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "DioramaViewportContainer"
	viewport_container.stretch = false
	viewport_container.custom_minimum_size = Vector2(RENDER_SIZE)
	viewport_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	viewport_container.position = Vector2(-RENDER_SIZE.x * 0.5, 0.0)
	viewport_container.size = Vector2(RENDER_SIZE)
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport_container)

	lab_viewport = SubViewport.new()
	lab_viewport.name = "Pixel24DioramaViewport"
	lab_viewport.size = RENDER_SIZE
	lab_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	lab_viewport.msaa_3d = Viewport.MSAA_DISABLED
	lab_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	lab_viewport.use_debanding = false
	viewport_container.add_child(lab_viewport)

	world_root = Node3D.new()
	world_root.name = "Pixel24DioramaWorld"
	lab_viewport.add_child(world_root)

	var environment_node := WorldEnvironment.new()
	environment_node.name = "DioramaEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#0c1010")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#a8b19b")
	environment.ambient_light_energy = 0.66
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world_root.add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "DioramaSun"
	sun.light_color = Color("#e8d7b3")
	sun.light_energy = 1.12
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	world_root.add_child(sun)

	camera = Camera3D.new()
	camera.name = "FixedVerticalOrthographicCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_ORTHO_SIZE
	camera.near = 0.1
	camera.far = 60.0
	camera.current = true
	world_root.add_child(camera)
	_restore_vertical_camera()

	input_catcher = Control.new()
	input_catcher.name = "DioramaInputCatcher"
	input_catcher.set_anchors_preset(Control.PRESET_CENTER_TOP)
	input_catcher.position = Vector2(-RENDER_SIZE.x * 0.5, 0.0)
	input_catcher.size = Vector2(RENDER_SIZE)
	input_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	input_catcher.gui_input.connect(_on_world_input)
	add_child(input_catcher)


func _build_hud() -> void:
	var panel := PanelContainer.new()
	panel.name = "DioramaHUD"
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-216, 438)
	panel.size = Vector2(432, 114)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var title := Label.new()
	title.name = "LabTitle"
	title.text = "PIXEL24 실제 3D · 수직 직교 · 18×18"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 15)
	column.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	for spec in [
		["MoveLeft", "←", Vector2i.LEFT], ["MoveUp", "↑", Vector2i.UP],
		["MoveDown", "↓", Vector2i.DOWN], ["MoveRight", "→", Vector2i.RIGHT],
	]:
		var button := _button(str(spec[0]), str(spec[1]), Vector2(46, 44))
		var direction: Vector2i = spec[2]
		button.pressed.connect(func(): try_move(direction))
		row.add_child(button)
	gear_button = _button("SwordToggle", "검 ON", Vector2(68, 44))
	gear_button.pressed.connect(toggle_sword)
	row.add_child(gear_button)
	var reset_button := _button("ResetDiorama", "초기화", Vector2(70, 44))
	reset_button.pressed.connect(reset_demo)
	row.add_child(reset_button)
	status_label = Label.new()
	status_label.name = "DioramaStatus"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_override("font", FONT)
	status_label.add_theme_font_size_override("font_size", 12)
	column.add_child(status_label)


func _button(node_name: String, label: String, minimum: Vector2) -> Button:
	var result := Button.new()
	result.name = node_name
	result.text = label
	result.custom_minimum_size = minimum
	result.add_theme_font_override("font", FONT)
	result.add_theme_font_size_override("font_size", 13)
	return result


func _build_fixture() -> void:
	fixture_root = Node3D.new()
	fixture_root.name = "Fixed18x18Fixture"
	world_root.add_child(fixture_root)
	Factory.box(fixture_root, "GroundVolume", Vector3(18.0, 0.18, 18.0),
		Vector3(9.0, -0.12, 9.0), Factory.PALETTE.soil)
	# Sparse moss tiles break up the soil without covering the legible path.
	for cell in [Vector2i(1, 1), Vector2i(6, 2), Vector2i(8, 4), Vector2i(15, 7),
			Vector2i(2, 11), Vector2i(5, 15), Vector2i(12, 16), Vector2i(16, 10)]:
		Factory.box(fixture_root, "MossPatch", Vector3(0.86, 0.035, 0.72),
			cell_world(cell) + Vector3(0.0, 0.005, 0.0), Factory.PALETTE.moss,
			deg_to_rad(float((cell.x * 17 + cell.y * 11) % 4) * 11.0))
	for cell in PATH_CELLS:
		Factory.box(fixture_root, "StonePath", Vector3(0.82, 0.055, 0.82),
			cell_world(cell) + Vector3(0.0, 0.025, 0.0), Factory.PALETTE.path,
			deg_to_rad(float((cell.x + cell.y) % 3 - 1) * 5.0))
	for cell in WATER_CELLS:
		Factory.box(fixture_root, "ShallowWater", Vector3(0.98, 0.05, 0.98),
			cell_world(cell) + Vector3(0.0, -0.015, 0.0), Color(Factory.PALETTE.water, 0.88),
			0.0, Factory.material(Color(Factory.PALETTE.water, 0.88)))
		_occupancy[cell] = "water"

	_mark_footprint(STORAGE_ORIGIN, STORAGE_FOOTPRINT, "storage")
	var storage := Factory.build_storage()
	storage.position = footprint_center(STORAGE_ORIGIN, STORAGE_FOOTPRINT)
	fixture_root.add_child(storage)
	_mark_footprint(ARMORY_ORIGIN, ARMORY_FOOTPRINT, "armory")
	var armory := Factory.build_armory()
	armory.position = footprint_center(ARMORY_ORIGIN, ARMORY_FOOTPRINT)
	fixture_root.add_child(armory)

	for cell in LOW_WALL_CELLS:
		var wall := Factory.build_low_wall()
		wall.position = cell_world(cell)
		fixture_root.add_child(wall)
		_occupancy[cell] = "low_wall"

	tree = Factory.build_tree()
	tree.position = cell_world(TREE_TRUNK_CELL)
	fixture_root.add_child(tree)
	_occupancy[TREE_TRUNK_CELL] = "tree_trunk"
	Factory.build_crate(fixture_root, cell_world(Vector2i(12, 9)) + Vector3(0.0, 0.28, 0.0), 0.52)
	_occupancy[Vector2i(12, 9)] = "crate"

	human = Factory.build_actor("human", true)
	human.name = "MovableHuman"
	fixture_root.add_child(human)
	selection_ring = Factory.add_selection_ring(human)
	dwarf = Factory.build_actor("dwarf")
	dwarf.name = "ReferenceDwarf"
	dwarf.position = cell_world(DWARF_CELL)
	fixture_root.add_child(dwarf)
	goblin = Factory.build_actor("goblin")
	goblin.name = "ReferenceGoblin"
	goblin.position = cell_world(GOBLIN_CELL)
	fixture_root.add_child(goblin)
	_occupancy[DWARF_CELL] = "dwarf"
	_occupancy[GOBLIN_CELL] = "goblin"


func _mark_footprint(origin: Vector2i, footprint: Vector2i, kind: String) -> void:
	for y in range(origin.y, origin.y + footprint.y):
		for x in range(origin.x, origin.x + footprint.x):
			_occupancy[Vector2i(x, y)] = kind


func footprint_center(origin: Vector2i, footprint: Vector2i) -> Vector3:
	return Vector3(float(origin.x) + float(footprint.x) * 0.5,
		0.0, float(origin.y) + float(footprint.y) * 0.5)


func cell_world(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)


func _restore_vertical_camera() -> void:
	if camera == null:
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_ORTHO_SIZE
	camera.position = Vector3(9.0, 22.0, 9.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)


func set_evidence_pitch(enabled: bool) -> void:
	if not enabled:
		_restore_vertical_camera()
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.5
	camera.look_at_from_position(Vector3(9.0, 15.5, 20.0), Vector3(9.0, 0.0, 9.0), Vector3.UP)


func is_vertical_camera() -> bool:
	if camera == null or camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return false
	var forward := -camera.global_transform.basis.z.normalized()
	return forward.is_equal_approx(Vector3.DOWN) and is_equal_approx(camera.size, CAMERA_ORTHO_SIZE)


func reset_demo() -> void:
	human_cell = HUMAN_START
	interaction_count = 0
	set_sword_equipped(true)
	_restore_vertical_camera()
	_sync_human_visual()
	_set_status("시작 (%d,%d) · 클릭 또는 방향키/WASD" % [human_cell.x, human_cell.y])


func set_sword_equipped(enabled: bool) -> void:
	sword_equipped = enabled
	if human != null:
		var sword := human.find_child("SwordEquipment", true, false)
		if sword != null:
			sword.visible = enabled
	if gear_button != null:
		gear_button.text = "검 ON" if enabled else "검 OFF"


func toggle_sword() -> void:
	set_sword_equipped(not sword_equipped)
	interaction_count += 1
	_set_status("인간 단검 %s" % ("장착" if sword_equipped else "해제"))


func try_move(direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO or absi(direction.x) + absi(direction.y) != 1:
		return false
	var target := human_cell + direction
	if not is_in_bounds(target):
		_set_status("경계 밖 (%d,%d) 차단" % [target.x, target.y])
		return false
	if _occupancy.has(target):
		_set_status("%s 점유 칸 (%d,%d) 차단" % [str(_occupancy[target]), target.x, target.y])
		return false
	human_cell = target
	interaction_count += 1
	_restore_vertical_camera()
	_sync_human_visual()
	_set_status("이동 (%d,%d)%s" % [human_cell.x, human_cell.y,
		" · 수관 반투명" if _canopy_faded else ""])
	return true


func step_toward(target: Vector2i) -> bool:
	if not is_in_bounds(target) or target == human_cell:
		return false
	var delta := target - human_cell
	var direction := Vector2i(signi(delta.x), 0) if absi(delta.x) > absi(delta.y) \
		else Vector2i(0, signi(delta.y))
	return try_move(direction)


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_SIZE and cell.y < GRID_SIZE


func is_walkable(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and not _occupancy.has(cell)


func occupancy_kind(cell: Vector2i) -> String:
	return str(_occupancy.get(cell, ""))


func _sync_human_visual() -> void:
	if human == null:
		return
	human.position = cell_world(human_cell)
	_canopy_faded = human_cell in CANOPY_WALKABLE_CELLS
	Factory.set_tree_faded(tree, _canopy_faded)


func canopy_alpha() -> float:
	var canopy_material: StandardMaterial3D = tree.get_meta("canopy_material")
	return canopy_material.albedo_color.a


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	var direction := Vector2i.ZERO
	match event.physical_keycode:
		KEY_A: direction = Vector2i.LEFT
		KEY_D: direction = Vector2i.RIGHT
		KEY_W: direction = Vector2i.UP
		KEY_S: direction = Vector2i.DOWN
	match event.keycode:
		KEY_LEFT: direction = Vector2i.LEFT
		KEY_RIGHT: direction = Vector2i.RIGHT
		KEY_UP: direction = Vector2i.UP
		KEY_DOWN: direction = Vector2i.DOWN
		KEY_G: toggle_sword(); get_viewport().set_input_as_handled(); return
	if direction != Vector2i.ZERO:
		try_move(direction)
		get_viewport().set_input_as_handled()


func _on_world_input(event: InputEvent) -> void:
	var point := Vector2(-1, -1)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		point = event.position
	elif event is InputEventScreenTouch and event.pressed:
		point = event.position
	if point.x < 0.0:
		return
	var cell := screen_to_cell(point)
	if cell.x >= 0:
		step_toward(cell)
	input_catcher.accept_event()


func cell_to_screen(cell: Vector2i) -> Vector2:
	return camera.unproject_position(cell_world(cell) + Vector3(0.0, 0.02, 0.0))


func screen_to_cell(point: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	if absf(direction.y) < 0.00001:
		return Vector2i(-1, -1)
	var world_point := origin + direction * (-origin.y / direction.y)
	var result := Vector2i(floori(world_point.x), floori(world_point.z))
	return result if is_in_bounds(result) else Vector2i(-1, -1)


func projection_measurement() -> Dictionary:
	var center := Vector2i(8, 8)
	var origin := cell_to_screen(center)
	var x_neighbor := cell_to_screen(center + Vector2i.RIGHT)
	var z_neighbor := cell_to_screen(center + Vector2i.DOWN)
	return {
		"viewport": [RENDER_SIZE.x, RENDER_SIZE.y],
		"camera_size": camera.size,
		"x_spacing_px": origin.distance_to(x_neighbor),
		"z_spacing_px": origin.distance_to(z_neighbor),
		"origin_screen": [origin.x, origin.y],
		"roundtrip_cell": screen_to_cell(origin),
	}


func demo_contract() -> Dictionary:
	var stats := Factory.model_stats(fixture_root)
	return {
		"grid_size": GRID_SIZE,
		"render_size": RENDER_SIZE,
		"pixels_per_cell": PIXELS_PER_CELL,
		"camera_projection": camera.projection,
		"camera_size": camera.size,
		"camera_forward": -camera.global_transform.basis.z.normalized(),
		"vertical_camera": is_vertical_camera(),
		"human_cell": human_cell,
		"sword_equipped": sword_equipped,
		"canopy_faded": _canopy_faded,
		"storage_footprint": STORAGE_FOOTPRINT,
		"armory_footprint": ARMORY_FOOTPRINT,
		"mesh_instances": stats.mesh_instances,
		"triangles": stats.triangles,
		"sprite3d": stats.sprite3d,
		"quad_meshes": stats.quad_meshes,
		"authoritative_state_accessed": authoritative_state_accessed,
	}


func source_mapping() -> Dictionary:
	return Factory.SOURCE_MAPPING.duplicate(true)
