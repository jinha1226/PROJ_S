class_name LowPolyPawn3D
extends Node3D

signal attack_finished

const HERO_CUTOUT_ATLAS:Texture2D=preload(
	"res://assets/generated/topdown_cutout_v1/character/runtime/hero_cutout_atlas_4x4_1024.png")
const GOBLIN_CUTOUT_ATLAS:Texture2D=preload(
	"res://assets/generated/topdown_cutout_v1/character/runtime/goblin_cutout_atlas_4x4_1024_v2.png")

@export_enum("human", "goblin") var species := "human"
@export var equipment_visible := true

# The rig lives in the XZ gameplay plane. Nothing in this pawn is a visible 3D
# volume: Node3D joints provide transforms while Sprite3D cutouts provide all art.
var visual_root:Node3D
var skeleton_root:Node3D
var equipment_root:Node3D
var torso_bone:Node3D
var head_pivot:Node3D
var left_arm_pivot:Node3D
var right_arm_pivot:Node3D
var left_forearm_pivot:Node3D
var right_forearm_pivot:Node3D
var left_leg_pivot:Node3D
var right_leg_pivot:Node3D
var left_shin_pivot:Node3D
var right_shin_pivot:Node3D
var sprite_parts:Array[Sprite3D]=[]
var equipment_parts:Array[Sprite3D]=[]
var rig_bones:Array[Node3D]=[]
var walking:=false
var animation_clock:=0.0
var attack_progress:=-1.0
var facing:="south"

var _head:Sprite3D
var _torso:Sprite3D
var _armor:Sprite3D
var _cape:Sprite3D
var _rest_visual_z:=0.0

func _ready()->void:
	if visual_root==null:_build_pawn()
	set_equipment_visible(equipment_visible)
	set_process(true)

func _build_pawn()->void:
	visual_root=Node3D.new();visual_root.name="TopdownCutoutVisual";add_child(visual_root)
	skeleton_root=_bone("Skeleton3DPlane",Vector3.ZERO,visual_root)
	equipment_root=Node3D.new();equipment_root.name="Equipment2DCutouts";visual_root.add_child(equipment_root)
	_build_shadow()
	_build_skeleton()
	_build_skin()
	_build_equipment()
	_apply_rest_pose()

func _build_shadow()->void:
	var gradient:=Gradient.new()
	gradient.set_color(0,Color(0.015,0.01,0.008,0.42))
	gradient.set_color(1,Color(0.015,0.01,0.008,0.0))
	var texture:=GradientTexture2D.new();texture.width=96;texture.height=64
	texture.gradient=gradient;texture.fill=GradientTexture2D.FILL_RADIAL
	texture.fill_from=Vector2(0.5,0.5);texture.fill_to=Vector2(0.5,0.02)
	var shadow:=Sprite3D.new();shadow.name="GroundShadow2D";shadow.texture=texture
	shadow.rotation_degrees.x=-90;shadow.pixel_size=0.0085;shadow.position=Vector3(0,0.012,0.20)
	shadow.shaded=false;shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)

func _build_skeleton()->void:
	torso_bone=_bone("TorsoBone",Vector3(0,0.050,-0.08),skeleton_root)
	head_pivot=_bone("HeadBone",Vector3(0,0.084,-0.43),skeleton_root)
	left_arm_pivot=_bone("UpperArmBone.L",Vector3(-0.25,0.058,-0.18),skeleton_root)
	right_arm_pivot=_bone("UpperArmBone.R",Vector3(0.25,0.059,-0.18),skeleton_root)
	left_forearm_pivot=_bone("ForearmBone.L",Vector3(0,0.002,0.31),left_arm_pivot)
	right_forearm_pivot=_bone("ForearmBone.R",Vector3(0,0.002,0.31),right_arm_pivot)
	left_leg_pivot=_bone("ThighBone.L",Vector3(-0.13,0.046,0.20),skeleton_root)
	right_leg_pivot=_bone("ThighBone.R",Vector3(0.13,0.047,0.20),skeleton_root)
	left_shin_pivot=_bone("ShinBone.L",Vector3(0,0.002,0.31),left_leg_pivot)
	right_shin_pivot=_bone("ShinBone.R",Vector3(0,0.002,0.31),right_leg_pivot)

func _build_skin()->void:
	_cape=_cutout("BackCloth2D",Vector2i(3,3),skeleton_root,Vector3(0,0.001,-0.01),0.0030,0)
	_torso=_cutout("BodyCore",Vector2i(2,0),torso_bone,Vector3.ZERO,0.0030,4)
	_head=_cutout("Head",Vector2i(0,0),head_pivot,Vector3.ZERO,0.00265,8)
	_build_arm_skin(left_arm_pivot,left_forearm_pivot,true)
	_build_arm_skin(right_arm_pivot,right_forearm_pivot,false)
	_build_leg_skin(left_leg_pivot,left_shin_pivot,true)
	_build_leg_skin(right_leg_pivot,right_shin_pivot,false)

func _build_arm_skin(upper:Node3D,forearm:Node3D,is_left:bool)->void:
	var suffix:=".L" if is_left else ".R"
	var upper_sprite:=_cutout("UpperArm"+suffix,Vector2i(0,1),upper,
		Vector3(0,0,0.155),0.00212,3)
	var forearm_sprite:=_cutout("Forearm"+suffix,Vector2i(1,1),forearm,
		Vector3(0,0,0.155),0.00212,5)
	upper_sprite.flip_h=is_left;forearm_sprite.flip_h=is_left

func _build_leg_skin(thigh:Node3D,shin:Node3D,is_left:bool)->void:
	var suffix:=".L" if is_left else ".R"
	var thigh_sprite:=_cutout("Thigh"+suffix,Vector2i(2,1),thigh,
		Vector3(0,0,0.155),0.00215,2)
	var shin_sprite:=_cutout("ShinBoot"+suffix,Vector2i(3,1),shin,
		Vector3(0,0,0.175),0.00218,3)
	thigh_sprite.flip_h=is_left;shin_sprite.flip_h=is_left

func _build_equipment()->void:
	_armor=_equipment_cutout("ArmorTorso",Vector2i(0,2),torso_bone,Vector3(0,0.012,0),0.00305,9)
	_equipment_cutout("Pauldron.L",Vector2i(2,2),left_arm_pivot,
		Vector3(0,0.012,0.035),0.00155,10).flip_h=true
	_equipment_cutout("Pauldron.R",Vector2i(2,2),right_arm_pivot,
		Vector3(0,0.012,0.035),0.00155,10)
	_equipment_cutout("Helmet",Vector2i(3,2),head_pivot,
		Vector3(0,0.014,-0.005),0.00278,11)
	_equipment_cutout("BeltPelvis",Vector2i(2,3),skeleton_root,
		Vector3(0,0.064,0.18),0.00235,10)
	var sword_socket:=_bone("SwordSocket",Vector3(0,0.006,0.27),right_forearm_pivot)
	_equipment_cutout("SwordBlade",Vector2i(0,3),sword_socket,
		Vector3(0,0,0.22),0.00235,12)
	var shield_socket:=_bone("ShieldSocket",Vector3(-0.055,0.006,0.19),left_forearm_pivot)
	_equipment_cutout("Shield",Vector2i(1,3),shield_socket,
		Vector3.ZERO,0.00242,13)

func _bone(node_name:String,position:Vector3,parent:Node3D=null)->Node3D:
	var bone:=Node3D.new();bone.name=node_name;bone.position=position
	(parent if parent!=null else self).add_child(bone);rig_bones.append(bone)
	return bone

func _atlas_texture(cell:Vector2i)->AtlasTexture:
	var texture:=AtlasTexture.new();texture.atlas=_atlas()
	texture.region=Rect2(cell.x*256,cell.y*256,256,256)
	return texture

func _atlas()->Texture2D:
	return GOBLIN_CUTOUT_ATLAS if species=="goblin" else HERO_CUTOUT_ATLAS

func _cutout(node_name:String,cell:Vector2i,parent:Node3D,position:Vector3,
		pixel_size:float,priority:int)->Sprite3D:
	var sprite:=Sprite3D.new();sprite.name=node_name;sprite.texture=_atlas_texture(cell)
	sprite.position=position;sprite.rotation_degrees.x=-90;sprite.pixel_size=pixel_size
	sprite.shaded=false;sprite.double_sided=true;sprite.render_priority=priority
	sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(sprite);sprite_parts.append(sprite)
	return sprite

func _equipment_cutout(node_name:String,cell:Vector2i,parent:Node3D,position:Vector3,
		pixel_size:float,priority:int)->Sprite3D:
	var sprite:=_cutout(node_name,cell,parent,position,pixel_size,priority)
	equipment_parts.append(sprite);return sprite

func set_equipment_visible(enabled:bool)->void:
	equipment_visible=enabled
	for part in equipment_parts:
		if is_instance_valid(part):part.visible=enabled
	if is_instance_valid(_cape):_cape.visible=enabled

func set_walking(enabled:bool)->void:
	walking=enabled
	if not enabled and attack_progress<0.0:_apply_rest_pose()

func face_direction(direction:Vector3)->void:
	var flat:=Vector2(direction.x,direction.z)
	if flat.length_squared()<=0.0001:return
	if absf(flat.y)>=absf(flat.x):facing="south" if flat.y>=0.0 else "north"
	else:facing="east" if flat.x>=0.0 else "west"
	_apply_facing_skin()

func _apply_facing_skin()->void:
	var north_facing:=facing=="north"
	_head.texture=_atlas_texture(Vector2i(1,0) if north_facing else Vector2i(0,0))
	_torso.texture=_atlas_texture(Vector2i(3,0) if north_facing else Vector2i(2,0))
	_armor.texture=_atlas_texture(Vector2i(1,2) if north_facing else Vector2i(0,2))
	visual_root.scale.x=-1.0 if facing=="west" else 1.0

func play_attack()->void:
	attack_progress=0.0

func _process(delta:float)->void:
	if visual_root==null:return
	animation_clock+=delta
	var stride:=sin(animation_clock*10.0)*0.38 if walking else 0.0
	left_leg_pivot.rotation.y=stride
	right_leg_pivot.rotation.y=-stride
	left_shin_pivot.rotation.y=-stride*0.34
	right_shin_pivot.rotation.y=stride*0.34
	left_arm_pivot.rotation.y=-stride*0.72+0.10
	visual_root.position.z=_rest_visual_z-(absf(sin(animation_clock*10.0))*0.026 if walking else 0.0)
	head_pivot.rotation.y=sin(animation_clock*2.0)*0.025
	if attack_progress>=0.0:
		attack_progress+=delta/0.48
		var normalized:=minf(attack_progress,1.0)
		var swing:=lerpf(-0.95,1.18,smoothstep(0.14,0.74,normalized))
		right_arm_pivot.rotation.y=swing
		right_forearm_pivot.rotation.y=-0.35+sin(normalized*PI)*0.62
		if attack_progress>=1.0:
			attack_progress=-1.0;_apply_rest_pose();attack_finished.emit()
	else:
		right_arm_pivot.rotation.y=stride*0.72-0.10
		right_forearm_pivot.rotation.y=0.08

func _apply_rest_pose()->void:
	if left_arm_pivot==null:return
	left_arm_pivot.rotation=Vector3(0,0.10,0)
	right_arm_pivot.rotation=Vector3(0,-0.10,0)
	left_forearm_pivot.rotation=Vector3(0,-0.06,0)
	right_forearm_pivot.rotation=Vector3(0,0.08,0)
	left_leg_pivot.rotation=Vector3(0,-0.055,0)
	right_leg_pivot.rotation=Vector3(0,0.055,0)
	left_shin_pivot.rotation=Vector3.ZERO;right_shin_pivot.rotation=Vector3.ZERO
	visual_root.position.z=_rest_visual_z

func visual_contract()->Dictionary:
	return {
		"visible_mesh_count":0,
		"sprite_part_count":sprite_parts.size(),
		"equipment_part_count":equipment_parts.size(),
		"rig_bone_count":rig_bones.size(),
		"separate_equipment":equipment_root!=null,
		"full_frame_sprite":false,
		"topdown_cutout_skin":true,
		"animated_limbs":left_forearm_pivot!=null and right_forearm_pivot!=null \
			and left_shin_pivot!=null and right_shin_pivot!=null,
		"species":species,
		"facing":facing,
	}
