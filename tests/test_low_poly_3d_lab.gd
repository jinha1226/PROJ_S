extends "res://tests/test_case.gd"

const Lab=preload("res://playtest/low_poly_3d_lab.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")

func _count_type(node:Node,type_name:String)->int:
	var count:=1 if node.get_class()==type_name else 0
	for child in node.get_children():count+=_count_type(child,type_name)
	return count

func test_topdown_pawn_is_a_2d_cutout_on_a_3d_bone_rig()->bool:
	var lab=Lab.new();lab.size=Vector2(450,800);lab._ready()
	var hero:Dictionary=lab.demo_contract().hero
	check(int(hero.visible_mesh_count)==0 and _count_type(lab.pawn,"MeshInstance3D")==0,
		"pawn has no visible 3D meshes or textured 3D body underneath the art")
	check(int(hero.sprite_part_count)>=18 and _count_type(lab.pawn,"Sprite3D")>=19,
		"the visible pawn is assembled from head, torso, limb, gear, and shadow 2D cutouts")
	check(int(hero.rig_bone_count)>=13 and not bool(hero.full_frame_sprite),
		"Node3D joints drive modular art instead of swapping a baked full-character frame")
	check(int(hero.equipment_part_count)>=7 and bool(hero.separate_equipment),
		"armor, sword, and shield remain detachable 2D rig parts")
	check(bool(hero.topdown_cutout_skin) and bool(hero.animated_limbs),
		"upper/lower arms and legs are independently articulated for the top-down view")
	check(lab.pawn.find_child("Head",true,false) is Sprite3D \
		and lab.pawn.find_child("BodyCore",true,false) is Sprite3D \
		and lab.pawn.find_child("ArmorTorso",true,false) is Sprite3D \
		and lab.pawn.find_child("SwordBlade",true,false) is Sprite3D \
		and lab.pawn.find_child("Shield",true,false) is Sprite3D,
		"all named visible body and equipment pieces are 2D sprites")
	var body:=lab.pawn.find_child("BodyCore",true,false) as Sprite3D
	check(body.texture is AtlasTexture and not body.shaded \
		and is_equal_approx(body.rotation_degrees.x,-90.0),
		"cutout art lies in the true top-down XZ screen plane and ignores 3D shading")
	lab.toggle_gear()
	check(not lab.pawn.equipment_visible \
		and not lab.pawn.find_child("ArmorTorso",true,false).visible \
		and not lab.pawn.find_child("SwordBlade",true,false).visible,
		"gear toggle hides only detachable cutout parts")
	check(lab.pawn._torso.visible \
		and lab.pawn.find_child("UpperArm*",true,false).visible,
		"base torso and articulated limbs remain when gear is removed")
	check(_count_type(lab.world_root,"MeshInstance3D")==0 \
		and _count_type(lab.world_root,"Sprite3D")>120,
		"floor, boundary, props, actors, and effects are visible 2D art with no 3D geometry")
	var right_arm:Node3D=lab.pawn.right_arm_pivot
	var right_forearm:Node3D=lab.pawn.right_forearm_pivot
	lab.pawn.play_attack();lab.pawn._process(0.24)
	check(absf(right_arm.rotation.y)>0.2 and absf(right_forearm.rotation.y)>0.05,
		"attack drives the upper-arm, forearm, and attached sword chain")
	lab.pawn.set_walking(true);lab.pawn._process(0.11)
	check(absf(lab.pawn.left_leg_pivot.rotation.y)>0.05 \
		and lab.pawn.left_leg_pivot.rotation.y*lab.pawn.right_leg_pivot.rotation.y<0.0,
		"walk pose moves the two leg cutouts in opposite directions")
	lab.free();return finish()

func test_true_topdown_camera_and_directional_cutout_variants()->bool:
	var lab=Lab.new();lab.size=Vector2(360,640);lab._ready()
	var pawn_id:int=lab.pawn.get_instance_id()
	lab.set_view_mode(lab.VIEW_TOPDOWN)
	check(lab.camera.projection==Camera3D.PROJECTION_ORTHOGONAL \
		and is_equal_approx(lab.camera.rotation_degrees.x,-90.0),
		"the prototype is fixed to a true vertical orthographic 2D top view")
	check(is_zero_approx(lab.camera.position.x) and is_zero_approx(lab.camera.position.z),
		"camera pitch and perspective no longer create the character presentation")
	var head:=lab.pawn.find_child("Head",true,false) as Sprite3D
	var south_region:Rect2=(head.texture as AtlasTexture).region
	lab.pawn.face_direction(Vector3(0,0,-1))
	var north_region:Rect2=(head.texture as AtlasTexture).region
	check(south_region!=north_region and lab.pawn.facing=="north",
		"north movement selects back/top cutout art without rotating a full-frame sprite")
	lab.pawn.face_direction(Vector3(-1,0,0))
	check(lab.pawn.facing=="west" and lab.pawn.visual_root.scale.x<0.0,
		"east/west movement mirrors the same modular rig consistently")
	check(lab.pawn.get_instance_id()==pawn_id,
		"direction changes reuse the exact same 3D bone hierarchy")
	check(not bool(lab.demo_contract().authoritative_state_accessed),
		"visual prototype is isolated from the authoritative game session")
	for button_name in ["TopdownCamera","GearToggle","MoveLeft","Attack","BackToGame"]:
		var button:=lab.find_child(button_name,true,false) as Button
		check(button!=null and button.custom_minimum_size.y>=44.0,
			"%s remains a mobile-safe touch target"%button_name)
	check(lab.find_child("PitchedCamera",true,false)==null \
		and lab.find_child("PaintedSkinToggle",true,false)==null,
		"obsolete 2.5D camera and 3D-material comparison controls are gone")
	lab.free();return finish()

func test_product_hud_exposes_the_isolated_2d_rig_probe()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var before:=session.save_session_json()
	var sandbox=Sandbox.new();sandbox.size=Vector2(450,800)
	sandbox.initialize_for_headless_test(session,false)
	check(sandbox.grid_3d_model_button!=null \
		and sandbox.grid_3d_model_button.text=="[2D]" \
		and sandbox.grid_3d_model_button.custom_minimum_size.y>=44.0,
		"product HUD exposes a mobile-safe 2D top-down rig test button")
	sandbox._activate_product_zoom_control("Open3DModelLab")
	check(sandbox.ascii_3d_lab_view is LowPoly3DLab and sandbox.grid.modal_open,
		"2D button opens the cutout-rig lab over the intact product map")
	sandbox._close_ascii_3d_lab()
	check(not sandbox.grid.modal_open and session.save_session_json()==before,
		"closing the visual probe restores input without mutating the saved session")
	sandbox.free();return finish()
