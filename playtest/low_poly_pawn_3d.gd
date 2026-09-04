class_name LowPolyPawn3D
extends Node3D

signal attack_finished

@export_enum("human", "goblin") var species := "human"
@export var equipment_visible := true

var visual_root:Node3D
var left_arm_pivot:Node3D
var right_arm_pivot:Node3D
var left_leg_pivot:Node3D
var right_leg_pivot:Node3D
var head_pivot:Node3D
var equipment_root:Node3D
var mesh_parts:Array[MeshInstance3D]=[]
var equipment_parts:Array[MeshInstance3D]=[]
var walking:=false
var animation_clock:=0.0
var attack_progress:=-1.0

var _skin:StandardMaterial3D
var _hair:StandardMaterial3D
var _cloth:StandardMaterial3D
var _accent:StandardMaterial3D
var _leather:StandardMaterial3D
var _iron:StandardMaterial3D
var _dark_iron:StandardMaterial3D
var _eye:StandardMaterial3D

func _ready()->void:
	if visual_root==null:
		_build_materials()
		_build_pawn()
	set_equipment_visible(equipment_visible)
	set_process(true)

func _build_materials()->void:
	if species=="goblin":
		_skin=_material(Color("#70864f"),0.0,0.94)
		_hair=_material(Color("#302b24"),0.0,1.0)
		_cloth=_material(Color("#392f2c"),0.0,1.0)
		_accent=_material(Color("#6e3828"),0.0,0.96)
	else:
		_skin=_material(Color("#c58e67"),0.0,0.92)
		_hair=_material(Color("#332720"),0.0,1.0)
		_cloth=_material(Color("#262a2e"),0.0,1.0)
		_accent=_material(Color("#75412b"),0.0,0.96)
	_leather=_material(Color("#3c2b22"),0.0,0.92)
	_iron=_material(Color("#71777a"),0.62,0.48)
	_dark_iron=_material(Color("#3f4649"),0.72,0.42)
	_eye=_material(Color("#12100e"),0.0,1.0)

func _material(color:Color,metallic:float,roughness:float)->StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.metallic=metallic
	material.roughness=roughness
	material.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode=BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return material

func _build_pawn()->void:
	visual_root=Node3D.new();visual_root.name="AnimatedVisual";add_child(visual_root)
	_build_shadow()
	_build_body()
	_build_equipment()

func _build_shadow()->void:
	var shadow_material:=StandardMaterial3D.new()
	shadow_material.albedo_color=Color(0.015,0.012,0.01,0.44)
	shadow_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var shadow_mesh:=CylinderMesh.new()
	shadow_mesh.top_radius=0.34;shadow_mesh.bottom_radius=0.34
	shadow_mesh.height=0.012;shadow_mesh.radial_segments=12
	_part("GroundShadow",shadow_mesh,shadow_material,self,Vector3(0,0.012,0.03),Vector3.ZERO,false)

func _build_body()->void:
	var torso_mesh:=CylinderMesh.new()
	torso_mesh.top_radius=0.27;torso_mesh.bottom_radius=0.22
	torso_mesh.height=0.48;torso_mesh.radial_segments=8
	_part("BodyCore",torso_mesh,_cloth,visual_root,Vector3(0,0.91,0),Vector3.ZERO)

	var belt_mesh:=CylinderMesh.new()
	belt_mesh.top_radius=0.235;belt_mesh.bottom_radius=0.235
	belt_mesh.height=0.09;belt_mesh.radial_segments=8
	_part("Belt",belt_mesh,_leather,visual_root,Vector3(0,0.69,0),Vector3.ZERO)

	head_pivot=Node3D.new();head_pivot.name="HeadPivot";head_pivot.position=Vector3(0,1.27,0);visual_root.add_child(head_pivot)
	var head_mesh:=SphereMesh.new()
	head_mesh.radius=0.34;head_mesh.height=0.66;head_mesh.radial_segments=10;head_mesh.rings=5
	_part("Head",head_mesh,_skin,head_pivot,Vector3(0,0.19,0),Vector3.ZERO)
	var hair_mesh:=CylinderMesh.new()
	hair_mesh.top_radius=0.30;hair_mesh.bottom_radius=0.35
	hair_mesh.height=0.18;hair_mesh.radial_segments=9
	_part("Hair",hair_mesh,_hair,head_pivot,Vector3(0,0.45,0.015),Vector3.ZERO)
	var fringe_mesh:=BoxMesh.new();fringe_mesh.size=Vector3(0.38,0.13,0.10)
	_part("HairFringe",fringe_mesh,_hair,head_pivot,Vector3(-0.05,0.35,-0.29),Vector3(0,0,0.12))
	_build_face()

	left_arm_pivot=_limb_pivot("ArmPivot.L",Vector3(-0.31,1.08,0),visual_root)
	right_arm_pivot=_limb_pivot("ArmPivot.R",Vector3(0.31,1.08,0),visual_root)
	_build_arm("Arm.L",left_arm_pivot,-1.0)
	_build_arm("Arm.R",right_arm_pivot,1.0)
	left_leg_pivot=_limb_pivot("LegPivot.L",Vector3(-0.14,0.64,0),visual_root)
	right_leg_pivot=_limb_pivot("LegPivot.R",Vector3(0.14,0.64,0),visual_root)
	_build_leg("Leg.L",left_leg_pivot)
	_build_leg("Leg.R",right_leg_pivot)
	if species=="goblin":_build_goblin_ears()

func _build_face()->void:
	for side in [-1.0,1.0]:
		var eye_mesh:=SphereMesh.new();eye_mesh.radius=0.036;eye_mesh.height=0.07
		eye_mesh.radial_segments=6;eye_mesh.rings=3
		_part("Eye.L" if side<0 else "Eye.R",eye_mesh,_eye,head_pivot,
			Vector3(0.11*side,0.22,-0.305),Vector3.ZERO)
	var nose_mesh:=CylinderMesh.new();nose_mesh.top_radius=0.035;nose_mesh.bottom_radius=0.055
	nose_mesh.height=0.12;nose_mesh.radial_segments=5
	_part("Nose",nose_mesh,_skin,head_pivot,Vector3(0,0.13,-0.34),Vector3(deg_to_rad(90),0,0))

func _build_goblin_ears()->void:
	for side in [-1.0,1.0]:
		var ear_mesh:=PrismMesh.new();ear_mesh.size=Vector3(0.27,0.13,0.08)
		_part("Ear.L" if side<0 else "Ear.R",ear_mesh,_skin,head_pivot,
			Vector3(0.40*side,0.22,0),Vector3(0,0,deg_to_rad(-18.0*side)))

func _limb_pivot(node_name:String,position:Vector3,parent:Node3D)->Node3D:
	var pivot:=Node3D.new();pivot.name=node_name;pivot.position=position;parent.add_child(pivot)
	return pivot

func _build_arm(node_name:String,parent:Node3D,side:float)->void:
	var sleeve_mesh:=CapsuleMesh.new();sleeve_mesh.radius=0.105;sleeve_mesh.height=0.42
	sleeve_mesh.radial_segments=8;sleeve_mesh.rings=3
	_part(node_name,sleeve_mesh,_cloth,parent,Vector3(0,-0.18,0),Vector3.ZERO)
	var hand_mesh:=SphereMesh.new();hand_mesh.radius=0.105;hand_mesh.height=0.20
	hand_mesh.radial_segments=8;hand_mesh.rings=4
	_part("Hand.L" if side<0 else "Hand.R",hand_mesh,_skin,parent,Vector3(0,-0.43,0),Vector3.ZERO)

func _build_leg(node_name:String,parent:Node3D)->void:
	var leg_mesh:=CapsuleMesh.new();leg_mesh.radius=0.115;leg_mesh.height=0.43
	leg_mesh.radial_segments=8;leg_mesh.rings=3
	_part(node_name,leg_mesh,_cloth,parent,Vector3(0,-0.18,0),Vector3.ZERO)
	var boot_mesh:=BoxMesh.new();boot_mesh.size=Vector3(0.20,0.18,0.31)
	_part(node_name.replace("Leg","Boot"),boot_mesh,_leather,parent,Vector3(0,-0.42,-0.07),Vector3.ZERO)

func _build_equipment()->void:
	equipment_root=Node3D.new();equipment_root.name="Equipment";visual_root.add_child(equipment_root)
	var chest_mesh:=CylinderMesh.new();chest_mesh.top_radius=0.295;chest_mesh.bottom_radius=0.245
	chest_mesh.height=0.38;chest_mesh.radial_segments=8
	_equipment_part("ArmorTorso",chest_mesh,_dark_iron,equipment_root,Vector3(0,0.98,0),Vector3.ZERO)
	var chest_mark:=BoxMesh.new();chest_mark.size=Vector3(0.18,0.20,0.035)
	_equipment_part("ArmorMark",chest_mark,_accent,equipment_root,Vector3(0,1.00,-0.267),Vector3.ZERO)
	for side in [-1.0,1.0]:
		var shoulder_mesh:=SphereMesh.new();shoulder_mesh.radius=0.15;shoulder_mesh.height=0.22
		shoulder_mesh.radial_segments=8;shoulder_mesh.rings=3
		_equipment_part("Pauldron.L" if side<0 else "Pauldron.R",shoulder_mesh,_iron,
			equipment_root,Vector3(0.34*side,1.10,0),Vector3(0,0,deg_to_rad(12.0*side)))
	var helmet_mesh:=CylinderMesh.new();helmet_mesh.top_radius=0.31;helmet_mesh.bottom_radius=0.36
	helmet_mesh.height=0.22;helmet_mesh.radial_segments=9
	_equipment_part("Helmet",helmet_mesh,_dark_iron,head_pivot,Vector3(0,0.46,0),Vector3.ZERO)
	var helmet_brow:=BoxMesh.new();helmet_brow.size=Vector3(0.54,0.10,0.09)
	_equipment_part("HelmetBrow",helmet_brow,_iron,head_pivot,Vector3(0,0.34,-0.29),Vector3.ZERO)
	_build_sword()
	_build_shield()

func _build_sword()->void:
	var sword_root:=Node3D.new();sword_root.name="SwordSocket"
	sword_root.position=Vector3(0,-0.42,0);sword_root.rotation.z=deg_to_rad(-52)
	right_arm_pivot.add_child(sword_root)
	var grip_mesh:=CylinderMesh.new();grip_mesh.top_radius=0.035;grip_mesh.bottom_radius=0.035
	grip_mesh.height=0.25;grip_mesh.radial_segments=6
	_equipment_part("SwordGrip",grip_mesh,_leather,sword_root,Vector3(0,-0.10,0),Vector3.ZERO)
	var guard_mesh:=BoxMesh.new();guard_mesh.size=Vector3(0.30,0.055,0.06)
	_equipment_part("SwordGuard",guard_mesh,_accent,sword_root,Vector3(0,-0.24,0),Vector3.ZERO)
	var blade_mesh:=PrismMesh.new();blade_mesh.size=Vector3(0.11,0.68,0.045)
	_equipment_part("SwordBlade",blade_mesh,_iron,sword_root,Vector3(0,-0.58,0),Vector3.ZERO)

func _build_shield()->void:
	var shield_mesh:=CylinderMesh.new();shield_mesh.top_radius=0.30;shield_mesh.bottom_radius=0.27
	shield_mesh.height=0.075;shield_mesh.radial_segments=10
	_equipment_part("Shield",shield_mesh,_dark_iron,left_arm_pivot,
		Vector3(-0.03,-0.46,-0.14),Vector3(deg_to_rad(90),0,0))
	var boss_mesh:=SphereMesh.new();boss_mesh.radius=0.095;boss_mesh.height=0.11
	boss_mesh.radial_segments=7;boss_mesh.rings=3
	_equipment_part("ShieldBoss",boss_mesh,_accent,left_arm_pivot,
		Vector3(-0.03,-0.46,-0.205),Vector3(deg_to_rad(90),0,0))

func _part(node_name:String,mesh:PrimitiveMesh,material:Material,parent:Node3D,
		position:Vector3,rotation:Vector3,track:bool=true)->MeshInstance3D:
	var part:=MeshInstance3D.new();part.name=node_name;part.mesh=mesh;part.material_override=material
	part.position=position;part.rotation=rotation
	part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(part)
	if track:mesh_parts.append(part)
	return part

func _equipment_part(node_name:String,mesh:PrimitiveMesh,material:Material,parent:Node3D,
		position:Vector3,rotation:Vector3)->MeshInstance3D:
	var part:=_part(node_name,mesh,material,parent,position,rotation)
	equipment_parts.append(part)
	return part

func set_equipment_visible(enabled:bool)->void:
	equipment_visible=enabled
	for part in equipment_parts:
		if is_instance_valid(part):part.visible=enabled

func set_walking(enabled:bool)->void:
	walking=enabled
	if not enabled and attack_progress<0.0:_apply_rest_pose()

func face_direction(direction:Vector3)->void:
	var flat:=Vector3(direction.x,0,direction.z)
	if flat.length_squared()>0.0001:
		look_at_from_position(position,position+flat.normalized(),Vector3.UP)

func play_attack()->void:
	attack_progress=0.0

func _process(delta:float)->void:
	if visual_root==null:return
	animation_clock+=delta
	var stride:=sin(animation_clock*10.0)*0.62 if walking else 0.0
	left_leg_pivot.rotation.x=stride
	right_leg_pivot.rotation.x=-stride
	left_arm_pivot.rotation.x=-stride*0.68
	visual_root.position.y=(absf(sin(animation_clock*10.0))*0.055 if walking \
		else sin(animation_clock*2.4)*0.014)
	head_pivot.rotation.z=sin(animation_clock*2.0)*0.025
	if attack_progress>=0.0:
		attack_progress+=delta/0.48
		var normalized:=minf(attack_progress,1.0)
		var swing:=lerpf(-1.25,1.15,smoothstep(0.18,0.72,normalized))
		right_arm_pivot.rotation.x=swing
		right_arm_pivot.rotation.z=-0.30+sin(normalized*PI)*0.22
		if attack_progress>=1.0:
			attack_progress=-1.0
			_apply_rest_pose()
			attack_finished.emit()
	else:
		right_arm_pivot.rotation.x=stride*0.68
		right_arm_pivot.rotation.z=-0.16

func _apply_rest_pose()->void:
	if left_arm_pivot==null:return
	left_arm_pivot.rotation=Vector3(0,0,0.16)
	right_arm_pivot.rotation=Vector3(0,0,-0.16)
	left_leg_pivot.rotation=Vector3.ZERO
	right_leg_pivot.rotation=Vector3.ZERO

func visual_contract()->Dictionary:
	return {
		"actual_mesh_count":mesh_parts.size(),
		"equipment_part_count":equipment_parts.size(),
		"separate_equipment":equipment_root!=null,
		"animated_limbs":left_arm_pivot!=null and right_arm_pivot!=null \
			and left_leg_pivot!=null and right_leg_pivot!=null,
		"species":species,
	}
