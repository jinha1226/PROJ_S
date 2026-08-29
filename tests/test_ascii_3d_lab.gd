extends "res://tests/test_case.gd"

const Lab=preload("res://playtest/ascii_3d_lab.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")

func test_real_3d_scene_has_portrait_safe_controls_shared_resources_and_fov()->bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var lab=Lab.new();lab.size=viewport_size;lab._ready()
		check(lab.lab_viewport is SubViewport and lab.camera is Camera3D \
			and lab.world_root is Node3D,"%s uses a real SubViewport/Node3D/Camera3D"%viewport_size)
		check(lab.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"camera is fixed orthographic")
		var focus:=lab._cell_world(lab.hero_cell)
		var view_direction:Vector3=(focus-lab.camera.position).normalized()
		check(view_direction.is_equal_approx(Vector3.DOWN) and is_equal_approx(lab.camera.size,lab.TOP_VIEW_SIZE),
			"camera is exact vertical orthographic top-view")
		check(lab.camera.basis.x.dot(Vector3.RIGHT)>0.999 \
			and lab.camera.basis.y.dot(Vector3.FORWARD)>0.999,
			"screen horizontal/vertical align with grid X/Z axes")
		check("정사영 탑뷰" in str((lab.find_child("LabTitle",true,false) as Label).text),
			"lab labels the projection as orthographic top-view")
		check_eq(lab.tile_nodes.size(),225,"15x15 deterministic test room")
		check(lab.find_child("BackTo2D",true,false).custom_minimum_size.y>=44 \
			and lab.find_child("LabReset",true,false).custom_minimum_size.y>=44,
			"%s close/reset remain 44px touch targets"%viewport_size)
		check(lab.materials.size()<24,"terrain visibility uses a small shared material cache")
		var visible:=0;var memory:=0;var unseen:=0
		for cell in lab.tile_nodes:
			var glyph:Label3D=lab.tile_glyphs[cell]
			if not glyph.visible:unseen+=1
			elif lab.seen_cells.has(cell) and lab._distance(lab.hero_cell,cell)>lab.VISIBLE_RADIUS:memory+=1
			else:visible+=1
		check(visible>0 and unseen>0,"%s exposes distinct visible and unseen regions"%viewport_size)
		lab.hero_cell+=Vector2i.LEFT*5;lab._reveal_visible();lab._update_visuals()
		for cell in lab.seen_cells:
			if lab._distance(lab.hero_cell,cell)>lab.VISIBLE_RADIUS:memory+=1
		check(memory>0,"movement leaves a dim memory region")
		lab.free()
	return finish()

func test_touch_model_attack_effects_and_demo_state_are_isolated()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var before:=session.save_session_json()
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640);sandbox.initialize_for_headless_test(session,true)
	check(sandbox.ascii_3d_lab_button!=null and sandbox.ascii_3d_lab_button.custom_minimum_size.y>=44,
		"2D product HUD exposes the 3D experiment")
	sandbox._open_ascii_3d_lab();check(sandbox.ascii_3d_lab_view!=null and sandbox.grid.modal_open,
		"experiment opens as an in-project overlay over the intact 2D renderer")
	sandbox._close_ascii_3d_lab();check(not sandbox.grid.modal_open and session.save_session_json()==before,
		"2D close restores input without replacing the authoritative session")
	var lab=Lab.new();lab.size=Vector2(360,640);lab._ready()
	var initial:Dictionary=lab.demo_state();lab._interact(lab.hero_cell+Vector2i.RIGHT)
	check(lab.hero_cell==Vector2i(int(initial.hero[0])+1,int(initial.hero[1])) \
		and lab.interaction_count==1,"one tap moves one sensible walkable step")
	lab.hero_cell=lab.enemy_cell+Vector2i.LEFT;lab._update_visuals();lab._interact(lab.enemy_cell)
	check_eq(lab.enemy_health,14,"adjacent enemy tap deals deterministic seven damage")
	check(lab.active_effects.size()>=6 and lab.find_child("DamageNumber",true,false)!=null,
		"attack creates flash, shards, and large damage number")
	lab._process(1.0);check_eq(lab.active_effects.size(),0,"transient effects have a bounded lifecycle")
	check(not bool(lab.demo_state().authoritative_state_accessed) and session.save_session_json()==before,
		"3D demo state never touches session/save authority")
	lab.free();sandbox.free();return finish()
