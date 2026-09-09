extends RefCounted

const Factory = preload("res://playtest/pixel24_diorama3d_factory.gd")

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	printerr("FAIL ", message)


func check_approx(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s (actual %.4f, expected %.4f ± %.4f)" % [message, actual, expected, tolerance])


func run(lab: Pixel24Diorama3DLab) -> bool:
	_check_real_geometry(lab)
	_check_projection_and_mapping(lab)
	_check_fixture_occupancy_and_movement(lab)
	_check_equipment_and_canopy(lab)
	_check_sources_and_isolation(lab)
	return failures.is_empty()


func _check_real_geometry(lab: Pixel24Diorama3DLab) -> void:
	var contract: Dictionary = lab.demo_contract()
	check(int(contract.grid_size) == 18 and contract.render_size == Vector2i(432, 432),
		"fixture is exactly 18x18 in a 432x432 render viewport")
	check(int(contract.mesh_instances) >= 80, "diorama contains many visible MeshInstance3D volumes")
	check(int(contract.triangles) >= 900, "low-poly assets expose actual triangle geometry")
	check(int(contract.sprite3d) == 0, "visible diorama contains no Sprite3D stand-ins")
	check(int(contract.quad_meshes) == 0, "visible diorama contains no QuadMesh character/building planes")
	for node_name in ["Torso", "Head", "WideBeard", "LeftLongEar", "SwordBlade",
			"RaisedTimberDeck", "AnvilTop", "TreeTrunk", "CrownCenter"]:
		check(lab.fixture_root.find_child(node_name, true, false) is MeshInstance3D,
			"%s is volumetric mesh geometry" % node_name)
	check(lab.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and lab.is_vertical_camera(),
		"default camera is strict vertical orthographic")


func _check_projection_and_mapping(lab: Pixel24Diorama3DLab) -> void:
	var measurement: Dictionary = lab.projection_measurement()
	check_approx(float(measurement.x_spacing_px), 24.0, 0.05,
		"adjacent world X cells project to 24 pixels")
	check_approx(float(measurement.z_spacing_px), 24.0, 0.05,
		"adjacent world Z cells project to 24 pixels")
	check(measurement.roundtrip_cell == Vector2i(8, 8),
		"projected center returns to the same logical cell")
	for cell in [Vector2i(0, 0), Vector2i(1, 16), Vector2i(8, 13), Vector2i(17, 17)]:
		check(lab.screen_to_cell(lab.cell_to_screen(cell)) == cell,
			"screen/cell roundtrip preserves %s" % cell)
	check(lab.screen_to_cell(Vector2(-1, -1)) == Vector2i(-1, -1),
		"outside pointer input is rejected")


func _check_fixture_occupancy_and_movement(lab: Pixel24Diorama3DLab) -> void:
	for y in range(2, 5):
		for x in range(2, 5):
			check(lab.occupancy_kind(Vector2i(x, y)) == "storage",
				"storage occupies its complete 3x3 footprint")
	for y in range(3, 5):
		for x in range(11, 14):
			check(lab.occupancy_kind(Vector2i(x, y)) == "armory",
				"armory occupies its complete 3x2 footprint")
	check(lab.occupancy_kind(lab.TREE_TRUNK_CELL) == "tree_trunk",
		"tree trunk occupies one logical cell")
	for canopy_cell in lab.CANOPY_WALKABLE_CELLS:
		check(lab.is_walkable(canopy_cell), "visual canopy cell %s remains walkable" % canopy_cell)

	lab.reset_demo()
	check(lab.try_move(Vector2i.UP) and lab.human_cell == Vector2i(8, 13),
		"keyboard-style move reaches the walkable canopy cell")
	check(lab.is_vertical_camera(), "movement preserves the vertical camera")
	check(not lab.try_move(Vector2i.UP) and lab.human_cell == Vector2i(8, 13),
		"tree trunk blocks movement without occupying the whole crown")
	lab.human_cell = Vector2i(5, 3); lab._sync_human_visual()
	check(not lab.try_move(Vector2i.LEFT) and lab.human_cell == Vector2i(5, 3),
		"storage footprint blocks movement")
	lab.human_cell = Vector2i(5, 8); lab._sync_human_visual()
	check(not lab.try_move(Vector2i.UP), "low wall occupancy blocks movement")
	lab.human_cell = Vector2i(13, 14); lab._sync_human_visual()
	check(not lab.try_move(Vector2i.RIGHT), "water fixture occupancy blocks movement")
	lab.human_cell = Vector2i(0, 10); lab._sync_human_visual()
	check(not lab.try_move(Vector2i.LEFT), "grid boundary blocks movement")
	lab.human_cell = Vector2i(7, 14); lab._sync_human_visual()
	check(lab.step_toward(Vector2i(11, 14)) and lab.human_cell == Vector2i(8, 14),
		"far click advances one cardinal cell toward its target")


func _check_equipment_and_canopy(lab: Pixel24Diorama3DLab) -> void:
	lab.reset_demo()
	var sword := lab.human.find_child("SwordEquipment", true, false) as Node3D
	check(sword != null and sword.visible, "human starts with separate sword geometry visible")
	lab.toggle_sword()
	check(not lab.sword_equipped and not sword.visible,
		"gear toggle removes the sword without removing the actor body")
	check(lab.human.find_child("Torso", true, false).visible,
		"human body remains visible with the sword unequipped")
	lab.toggle_sword()
	check(lab.sword_equipped and sword.visible, "second toggle restores sword geometry")

	lab.try_move(Vector2i.UP)
	check(bool(lab.demo_contract().canopy_faded), "entering the crown overlap activates occlusion treatment")
	check_approx(lab.canopy_alpha(), 0.30, 0.001, "tree crown fades under the actor")
	check(lab.selection_ring.visible, "selection marker remains visible under the crown")
	var selection_material := lab.selection_ring.material_override as StandardMaterial3D
	check(selection_material != null and selection_material.no_depth_test,
		"selection marker uses an explicit depth-safe material")
	lab.reset_demo()
	check_approx(lab.canopy_alpha(), 0.94, 0.001, "reset restores the normal crown")
	check(lab.is_vertical_camera(), "reset restores the vertical camera after every evidence mode")


func _check_sources_and_isolation(lab: Pixel24Diorama3DLab) -> void:
	var audit_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://docs/plans/pixel24-diorama3d-source-audit.json"))
	check(audit_value is Array and audit_value.size() == 7, "source audit contains seven frozen inputs")
	if audit_value is Array:
		for row_value in audit_value:
			var row: Dictionary = row_value
			check(FileAccess.get_sha256("res://" + str(row.path)) == str(row.sha256),
				"frozen source hash matches %s" % row.path)
	var mapping := lab.source_mapping()
	for key in ["human", "dwarf", "goblin", "human_sword", "storage", "armory", "tree"]:
		check(mapping.has(key) and not str(mapping[key].model).is_empty(),
			"source-to-model mapping documents %s" % key)
	check(str(mapping.tree.source).begins_with("none"),
		"new tree is explicitly identified as a derivative without a source sprite")
	check(not bool(lab.demo_contract().authoritative_state_accessed),
		"isolated lab never accesses authoritative save/session state")
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	check('run/main_scene="res://playtest/pixel24_diorama3d_lab.tscn"' in project_text,
		"Pages entry scene exposes the diorama after the explicit deployment request")
	for button_name in ["MoveLeft", "MoveUp", "MoveDown", "MoveRight", "SwordToggle", "ResetDiorama"]:
		var button := lab.find_child(button_name, true, false) as Button
		check(button != null and button.custom_minimum_size.y >= 44.0,
			"%s remains a 44px touch target" % button_name)
