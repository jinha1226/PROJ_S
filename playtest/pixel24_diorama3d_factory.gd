class_name Pixel24Diorama3DFactory
extends RefCounted

## Reusable low-poly, volumetric assets for the isolated Pixel24 diorama lab.
## Source PNGs are visual references only; no Sprite3D or flat character plane
## participates in the rendered scene.

const PALETTE := {
	"soil": Color("#211b17"),
	"soil_light": Color("#302820"),
	"moss": Color("#536044"),
	"moss_light": Color("#78805a"),
	"path": Color("#6c6253"),
	"water": Color("#304f55"),
	"timber": Color("#73583a"),
	"timber_dark": Color("#3e3024"),
	"canvas": Color("#b59b6a"),
	"stone": Color("#66645e"),
	"stone_dark": Color("#393a36"),
	"skin": Color("#e8a873"),
	"hair": Color("#634734"),
	"cloth": Color("#77736b"),
	"leather": Color("#604331"),
	"dwarf_hair": Color("#a64f27"),
	"dwarf_cloth": Color("#8a7137"),
	"goblin_skin": Color("#949756"),
	"goblin_cloth": Color("#51543b"),
	"steel": Color("#aeb8b6"),
	"steel_dark": Color("#4e5553"),
	"ember": Color("#ff8a2b"),
}

const SOURCE_MAPPING := {
	"human": {
		"source": "assets/pixel24_v3/runtime/actors/base/human.png",
		"carried": "round brown hair cap, warm face, grey tunic, brown boots",
		"inferred": "solid back hair, short block torso and limbs",
		"model": "playtest/pixel24_diorama3d_factory.gd::build_actor(human)",
	},
	"dwarf": {
		"source": "assets/pixel24_v3/runtime/actors/base/dwarf.png",
		"carried": "wide copper beard, bald crown, ochre apron, short body",
		"inferred": "beard wraps the jaw; compact back and boots",
		"model": "playtest/pixel24_diorama3d_factory.gd::build_actor(dwarf)",
	},
	"goblin": {
		"source": "assets/pixel24_v3/runtime/monsters/goblin.png",
		"carried": "olive skin, long side ears, dark olive tunic",
		"inferred": "ears taper as solid wedges; plain back tunic",
		"model": "playtest/pixel24_diorama3d_factory.gd::build_actor(goblin)",
	},
	"human_sword": {
		"source": "assets/pixel24_v3/fit_v2/equipment/weapons/short_sword.png",
		"carried": "short pale blade, dark guard and grip",
		"inferred": "rectangular blade thickness and solid pommel",
		"model": "playtest/pixel24_diorama3d_factory.gd::build_actor(human)/SwordEquipment",
	},
	"storage": {
		"source": "assets/pixel24_v3/runtime/buildings/storage_timber.png",
		"carried": "open timber deck, four posts, crates, sack and barrel",
		"inferred": "post depth, raised deck and solid container backs",
		"model": "playtest/pixel24_diorama3d_factory.gd::build_storage",
	},
	"armory": {
		"source": "assets/pixel24_v3/runtime/buildings/armory_timber.png",
		"carried": "open timber deck, anvil, forge, rear weapon rack",
		"inferred": "solid forge, chimney, rear posts and rack depth",
		"model": "playtest/pixel24_diorama3d_factory.gd::build_armory",
	},
	"tree": {
		"source": "none — new derivative design",
		"carried": "Pixel24 moss/timber earth palette only",
		"inferred": "six-sided trunk and clustered low-poly crown",
		"model": "playtest/pixel24_diorama3d_factory.gd::build_tree",
	},
}


static func material(color: Color, no_depth := false, emission := Color.TRANSPARENT) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.86
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.no_depth_test = no_depth
	if color.a < 0.999:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if emission.a > 0.0:
		result.emission_enabled = true
		result.emission = emission
		result.emission_energy_multiplier = 1.55
	return result


static func box(parent: Node3D, node_name: String, size: Vector3, position: Vector3,
		color: Color, rotation_y := 0.0, material_override: Material = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(parent, node_name, mesh, position, color, rotation_y, material_override)


static func cylinder(parent: Node3D, node_name: String, radius: float, height: float,
		position: Vector3, color: Color, sides := 8, material_override: Material = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return _instance(parent, node_name, mesh, position, color, 0.0, material_override)


static func sphere(parent: Node3D, node_name: String, radius: float, position: Vector3,
		color: Color, material_override: Material = null, scale := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var instance := _instance(parent, node_name, mesh, position, color, 0.0, material_override)
	instance.scale = scale
	return instance


static func _instance(parent: Node3D, node_name: String, mesh: Mesh, position: Vector3,
		color: Color, rotation_y: float, material_override: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.rotation.y = rotation_y
	instance.material_override = material_override if material_override != null else material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance


static func build_actor(species: String, sword_enabled := false) -> Node3D:
	var root := Node3D.new()
	root.name = species.capitalize() + "VolumeActor"
	root.set_meta("asset_kind", species)
	var cloth: Color = PALETTE.cloth
	var skin: Color = PALETTE.skin
	var height_scale := 1.0
	if species == "dwarf":
		cloth = PALETTE.dwarf_cloth
		height_scale = 0.83
	elif species == "goblin":
		cloth = PALETTE.goblin_cloth
		skin = PALETTE.goblin_skin
		height_scale = 0.90

	box(root, "LeftBoot", Vector3(0.20, 0.18, 0.28), Vector3(-0.14, 0.12, 0.13), PALETTE.leather)
	box(root, "RightBoot", Vector3(0.20, 0.18, 0.28), Vector3(0.14, 0.12, 0.13), PALETTE.leather)
	box(root, "Torso", Vector3(0.52, 0.58 * height_scale, 0.42),
		Vector3(0.0, 0.43 * height_scale, 0.0), cloth)
	box(root, "LeftArm", Vector3(0.15, 0.48 * height_scale, 0.16),
		Vector3(-0.34, 0.46 * height_scale, 0.0), skin)
	box(root, "RightArm", Vector3(0.15, 0.48 * height_scale, 0.16),
		Vector3(0.34, 0.46 * height_scale, 0.0), skin)
	var head_y := 0.91 * height_scale
	sphere(root, "Head", 0.27, Vector3(0.0, head_y, -0.02), skin, null,
		Vector3(1.0, 0.90, 0.92))

	if species == "human":
		sphere(root, "HairCap", 0.285, Vector3(0.0, head_y + 0.09, -0.07), PALETTE.hair,
			null, Vector3(1.04, 0.55, 1.02))
		box(root, "FacePatch", Vector3(0.30, 0.06, 0.20),
			Vector3(0.0, head_y + 0.205, 0.13), skin)
	elif species == "dwarf":
		# The broad copper beard extends toward screen-bottom (+Z) so it remains
		# the primary silhouette cue in the strict vertical view.
		box(root, "WideBeard", Vector3(0.52, 0.30, 0.42),
			Vector3(0.0, head_y - 0.02, 0.23), PALETTE.dwarf_hair)
		box(root, "BeardTip", Vector3(0.34, 0.18, 0.25),
			Vector3(0.0, head_y - 0.15, 0.43), PALETTE.dwarf_hair)
	elif species == "goblin":
		box(root, "LeftLongEar", Vector3(0.38, 0.11, 0.18),
			Vector3(-0.39, head_y + 0.02, 0.0), skin, deg_to_rad(-18.0))
		box(root, "RightLongEar", Vector3(0.38, 0.11, 0.18),
			Vector3(0.39, head_y + 0.02, 0.0), skin, deg_to_rad(18.0))
		box(root, "LeftEye", Vector3(0.07, 0.04, 0.06),
			Vector3(-0.10, head_y + 0.23, 0.13), PALETTE.stone_dark)
		box(root, "RightEye", Vector3(0.07, 0.04, 0.06),
			Vector3(0.10, head_y + 0.23, 0.13), PALETTE.stone_dark)

	if species == "human":
		var sword := Node3D.new()
		sword.name = "SwordEquipment"
		root.add_child(sword)
		box(sword, "SwordBlade", Vector3(0.11, 0.09, 0.60),
			Vector3(0.43, 0.47, 0.13), PALETTE.steel, deg_to_rad(-18.0))
		box(sword, "SwordGuard", Vector3(0.30, 0.10, 0.09),
			Vector3(0.34, 0.45, 0.42), PALETTE.steel_dark, deg_to_rad(-18.0))
		box(sword, "SwordGrip", Vector3(0.10, 0.11, 0.22),
			Vector3(0.29, 0.43, 0.53), PALETTE.leather, deg_to_rad(-18.0))
		sword.visible = sword_enabled
	return root


static func build_storage() -> Node3D:
	var root := _building_shell("StorageVolume", Vector2i(3, 3))
	root.set_meta("asset_kind", "storage")
	build_crate(root, Vector3(-0.72, 0.28, -0.55), 0.58)
	build_crate(root, Vector3(-0.68, 0.22, 0.55), 0.46)
	build_barrel(root, Vector3(0.72, 0.34, 0.52))
	var sack := sphere(root, "GrainSack", 0.32, Vector3(0.65, 0.31, -0.52), PALETTE.canvas,
		null, Vector3(0.78, 1.08, 0.92))
	sack.rotation.y = deg_to_rad(12.0)
	return root


static func build_armory() -> Node3D:
	var root := _building_shell("ArmoryVolume", Vector2i(3, 2))
	root.set_meta("asset_kind", "armory")
	# Anvil: dark base, narrow waist and broad steel top.
	box(root, "AnvilBase", Vector3(0.42, 0.34, 0.40),
		Vector3(-0.68, 0.25, 0.10), PALETTE.steel_dark)
	box(root, "AnvilTop", Vector3(0.78, 0.18, 0.32),
		Vector3(-0.68, 0.50, 0.10), PALETTE.steel)
	# Forge and orange coal bed remain distinct in the vertical view.
	box(root, "ForgeStone", Vector3(0.92, 0.42, 0.72),
		Vector3(0.66, 0.26, 0.12), PALETTE.stone_dark)
	box(root, "ForgeEmber", Vector3(0.58, 0.08, 0.42),
		Vector3(0.66, 0.51, 0.12), PALETTE.ember, 0.0,
		material(PALETTE.ember, false, PALETTE.ember))
	cylinder(root, "ForgeChimney", 0.19, 0.85,
		Vector3(1.12, 0.62, -0.46), PALETTE.stone_dark, 6)
	# Rear weapon rack: three pale blades on a timber beam.
	box(root, "WeaponRack", Vector3(1.25, 0.15, 0.16),
		Vector3(0.0, 0.55, -0.75), PALETTE.timber)
	for x in [-0.42, 0.0, 0.42]:
		box(root, "RackBlade", Vector3(0.09, 0.13, 0.62),
			Vector3(x, 0.64, -0.64), PALETTE.steel)
	return root


static func _building_shell(node_name: String, footprint: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.set_meta("footprint", footprint)
	var width := float(footprint.x) - 0.12
	var depth := float(footprint.y) - 0.12
	box(root, "RaisedTimberDeck", Vector3(width, 0.18, depth),
		Vector3(0.0, 0.02, 0.0), PALETTE.timber_dark)
	for x in [-width * 0.46, width * 0.46]:
		for z in [-depth * 0.46, depth * 0.46]:
			box(root, "TimberPost", Vector3(0.20, 0.95, 0.20),
				Vector3(x, 0.50, z), PALETTE.timber)
	box(root, "RearBeam", Vector3(width, 0.20, 0.18),
		Vector3(0.0, 0.95, -depth * 0.46), PALETTE.timber)
	box(root, "LeftBeam", Vector3(0.18, 0.20, depth),
		Vector3(-width * 0.46, 0.95, 0.0), PALETTE.timber)
	box(root, "RightBeam", Vector3(0.18, 0.20, depth),
		Vector3(width * 0.46, 0.95, 0.0), PALETTE.timber)
	return root


static func build_tree() -> Node3D:
	var root := Node3D.new()
	root.name = "MossTreeVolume"
	root.set_meta("asset_kind", "tree")
	cylinder(root, "TreeTrunk", 0.24, 1.35, Vector3(0.0, 0.68, 0.0), PALETTE.timber_dark, 6)
	var canopy_material := material(Color(PALETTE.moss_light, 0.94))
	root.set_meta("canopy_material", canopy_material)
	for spec in [
		["CrownCenter", Vector3(0.0, 1.63, 0.0), Vector3(1.10, 0.72, 1.02), 0.82],
		["CrownLeft", Vector3(-0.58, 1.52, 0.10), Vector3(1.0, 0.66, 0.92), 0.62],
		["CrownRight", Vector3(0.55, 1.55, -0.08), Vector3(1.0, 0.68, 0.90), 0.64],
		["CrownFront", Vector3(0.04, 1.48, 0.63), Vector3(0.96, 0.62, 1.0), 0.58],
	]:
		sphere(root, str(spec[0]), float(spec[3]), spec[1], PALETTE.moss_light,
			canopy_material, spec[2])
	return root


static func set_tree_faded(tree: Node3D, faded: bool) -> void:
	var canopy_material: StandardMaterial3D = tree.get_meta("canopy_material")
	var tint := PALETTE.moss_light
	tint.a = 0.30 if faded else 0.94
	canopy_material.albedo_color = tint


static func build_crate(parent: Node3D, position: Vector3, width := 0.56) -> Node3D:
	var root := Node3D.new()
	root.name = "WoodCrate"
	root.position = position
	parent.add_child(root)
	box(root, "CrateBody", Vector3(width, width, width), Vector3.ZERO, PALETTE.timber)
	box(root, "CrateBandX", Vector3(width + 0.04, 0.09, 0.10),
		Vector3(0.0, width * 0.51, 0.0), PALETTE.timber_dark)
	box(root, "CrateBandZ", Vector3(0.10, 0.09, width + 0.04),
		Vector3(0.0, width * 0.51, 0.0), PALETTE.timber_dark)
	return root


static func build_barrel(parent: Node3D, position: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "TimberBarrel"
	root.position = position
	parent.add_child(root)
	cylinder(root, "BarrelBody", 0.30, 0.62, Vector3.ZERO, PALETTE.timber, 8)
	for y in [-0.22, 0.22]:
		cylinder(root, "IronBand", 0.315, 0.075, Vector3(0.0, y, 0.0), PALETTE.steel_dark, 8)
	return root


static func build_low_wall() -> Node3D:
	var root := Node3D.new()
	root.name = "LowRuinWall"
	box(root, "WallCore", Vector3(0.92, 0.48, 0.78),
		Vector3(0.0, 0.24, 0.0), PALETTE.stone)
	box(root, "WallMoss", Vector3(0.94, 0.06, 0.42),
		Vector3(-0.08, 0.51, 0.08), PALETTE.moss)
	return root


static func add_selection_ring(parent: Node3D) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.34
	mesh.outer_radius = 0.44
	mesh.rings = 12
	mesh.ring_segments = 6
	var glow := Color("#f2d45c")
	return _instance(parent, "SelectionRing", mesh, Vector3(0.0, 0.055, 0.0),
		glow, 0.0, material(Color(glow, 0.92), true, glow))


static func model_stats(root: Node) -> Dictionary:
	var result := {"mesh_instances": 0, "triangles": 0, "sprite3d": 0, "quad_meshes": 0}
	_accumulate_stats(root, result)
	return result


static func _accumulate_stats(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D:
		result.mesh_instances += 1
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			result.triangles += mesh.get_faces().size() / 3
			if mesh is QuadMesh:
				result.quad_meshes += 1
	elif node is Sprite3D:
		result.sprite3d += 1
	for child in node.get_children():
		_accumulate_stats(child, result)
