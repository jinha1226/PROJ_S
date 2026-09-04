extends "res://tests/test_case.gd"

const Lab=preload("res://playtest/low_poly_3d_lab.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")

func _count_mesh_instances(node:Node)->int:
	var count:=1 if node is MeshInstance3D else 0
	for child in node.get_children():count+=_count_mesh_instances(child)
	return count

func test_real_mesh_pawn_has_modular_equipment_and_animated_limbs()->bool:
	var lab=Lab.new();lab.size=Vector2(450,800);lab._ready()
	var contract:Dictionary=lab.demo_contract()
	var hero:Dictionary=contract.hero
	check(int(hero.actual_mesh_count)>=20,"prototype hero is composed from actual 3D mesh parts")
	check(int(hero.equipment_part_count)>=8 and bool(hero.separate_equipment),
		"armor, sword, and shield are detachable equipment meshes")
	check(bool(hero.painted_surface) and bool(hero.face_decal),
		"the 3D pawn carries painted surface texture and a bone-attached 2D face decal")
	check(bool(hero.animated_limbs),"arms and legs use independent animation pivots")
	check(lab.pawn.find_child("Head",true,false) is MeshInstance3D \
		and lab.pawn.find_child("ArmorTorso",true,false) is MeshInstance3D \
		and lab.pawn.find_child("SwordBlade",true,false) is MeshInstance3D \
		and lab.pawn.find_child("Shield",true,false) is MeshInstance3D,
		"head, armor, sword, and shield remain named reusable parts")
	var body:=lab.pawn.find_child("BodyCore",true,false) as MeshInstance3D
	check(body.material_override is StandardMaterial3D \
		and (body.material_override as StandardMaterial3D).albedo_texture!=null \
		and (body.material_override as StandardMaterial3D).next_pass is ShaderMaterial,
		"body material combines the hand-painted albedo with a 2D-style outline pass")
	check(lab.pawn.find_child("FaceDecal2D",true,false) is MeshInstance3D \
		and lab.pawn.find_child("ArmorPaintedDecal",true,false) is MeshInstance3D \
		and lab.pawn.find_child("ShieldPaintedDecal",true,false) is MeshInstance3D,
		"face and heraldry stay separate transparent 2D overlays")
	lab.toggle_painted_skin()
	check(not lab.pawn.painted_skin_enabled \
		and (body.material_override as StandardMaterial3D).albedo_texture==null \
		and not lab.pawn.find_child("FaceDecal2D",true,false).visible,
		"comparison toggle removes painted textures, outlines, and 2D decals together")
	lab.toggle_painted_skin()
	check(lab.pawn.painted_skin_enabled \
		and (body.material_override as StandardMaterial3D).albedo_texture!=null,
		"painted skin can be restored without rebuilding or replacing the 3D pawn")
	check(_count_mesh_instances(lab.world_root)>130,
		"the room, props, actors, equipment, and blood pool are true 3D geometry")
	var right_arm:Node3D=lab.pawn.right_arm_pivot
	lab.pawn.play_attack();lab.pawn._process(0.24)
	check(absf(right_arm.rotation.x)>0.2,"attack visibly drives the sword-arm pivot")
	lab.pawn.set_walking(true);lab.pawn._process(0.11)
	check(absf(lab.pawn.left_leg_pivot.rotation.x)>0.05 \
		and lab.pawn.left_leg_pivot.rotation.x*lab.pawn.right_leg_pivot.rotation.x<0.0,
		"walk pose moves both legs in opposite directions")
	lab.free();return finish()

func test_same_3d_model_switches_between_cardinal_top_views()->bool:
	var lab=Lab.new();lab.size=Vector2(360,640);lab._ready()
	var pawn_id:int=lab.pawn.get_instance_id()
	lab.set_view_mode(lab.VIEW_TOPDOWN)
	var top_position:Vector3=lab.camera.position
	var top_elevation:float=rad_to_deg(asin(absf((Vector3(0,0.45,-0.25)-top_position).normalized().y)))
	lab.set_view_mode(lab.VIEW_PITCHED)
	var pitched_position:Vector3=lab.camera.position
	var pitched_elevation:float=rad_to_deg(asin(absf((Vector3(0,0.45,-0.25)-pitched_position).normalized().y)))
	check(lab.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,
		"both modes use an orthographic camera so the 3D render keeps a 2D-like scale")
	check(top_elevation>68.0 and pitched_elevation>40.0 and pitched_elevation<55.0,
		"camera presets provide near-vertical 2D and pitched 2.5D top views")
	check(is_equal_approx(lab.camera.basis.x.dot(Vector3.RIGHT),1.0),
		"camera keeps screen horizontal aligned to the world grid without isometric yaw")
	check(lab.pawn.get_instance_id()==pawn_id,
		"camera switching reuses the exact same model instead of directional sprites")
	lab.toggle_gear()
	check(not lab.pawn.equipment_visible and not lab.pawn.find_child("ArmorTorso",true,false).visible,
		"gear toggle removes only detachable equipment")
	check(lab.pawn.find_child("BodyCore",true,false).visible,
		"the base paper-doll body remains when equipment is removed")
	check(lab.torch_light.omni_range>=5.5 and lab.torch_light.omni_attenuation>1.0,
		"torch light reaches several cells and fades with distance")
	check(not bool(lab.demo_contract().authoritative_state_accessed),
		"visual prototype is isolated from the authoritative game session")
	for button_name in ["TopdownCamera","PitchedCamera","PaintedSkinToggle","GearToggle",
			"MoveLeft","Attack","BackToGame"]:
		var button:=lab.find_child(button_name,true,false) as Button
		check(button!=null and button.custom_minimum_size.y>=44.0,
			"%s remains a mobile-safe touch target"%button_name)
	lab.free();return finish()

func test_product_hud_exposes_the_isolated_3d_model_probe()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var before:=session.save_session_json()
	var sandbox=Sandbox.new();sandbox.size=Vector2(450,800)
	sandbox.initialize_for_headless_test(session,false)
	check(sandbox.grid_3d_model_button!=null \
		and sandbox.grid_3d_model_button.custom_minimum_size.y>=44.0,
		"product HUD exposes a mobile-safe 3D model test button")
	sandbox._activate_product_zoom_control("Open3DModelLab")
	check(sandbox.ascii_3d_lab_view is LowPoly3DLab and sandbox.grid.modal_open,
		"3D button opens the new low-poly lab over the intact product map")
	sandbox._close_ascii_3d_lab()
	check(not sandbox.grid.modal_open and session.save_session_json()==before,
		"closing the visual probe restores input without mutating the saved session")
	sandbox.free();return finish()
