extends "res://tests/test_case.gd"

const Lab=preload("res://playtest/ascii_3d_lab.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")

var pointer_target:=Vector2i.ZERO

func _resolve_pointer_for_test(_point:Vector2)->Vector2i:
	return pointer_target

func _count_mesh_instances(node:Node)->int:
	var count:=1 if node is MeshInstance3D else 0
	for child in node.get_children():count+=_count_mesh_instances(child)
	return count

func test_real_3d_scene_has_portrait_safe_controls_shared_resources_and_fov()->bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var lab=Lab.new();lab.size=viewport_size;lab._ready()
		check(lab.lab_viewport is SubViewport and lab.camera is Camera3D \
			and lab.world_root is Node3D,"%s uses a real SubViewport/Node3D/Camera3D"%viewport_size)
		check(lab.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"camera is fixed orthographic")
		var focus:=lab._cell_world(lab.hero_cell)
		var view_direction:Vector3=(focus-lab.camera.position).normalized()
		var elevation_degrees:=rad_to_deg(asin(absf(view_direction.y)))
		check(absf(view_direction.x)<0.0001 and view_direction.z<-0.7 \
			and is_equal_approx(elevation_degrees,45.0) \
			and is_equal_approx(lab.camera.size,lab.CAMERA_ORTHO_SIZE),
			"camera has cardinal-axis yaw and a 45-degree orthographic pitch")
		check(lab.camera.basis.x.dot(Vector3.RIGHT)>0.999,
			"screen horizontal remains grid/world +X without isometric yaw")
		var title_text:=str((lab.find_child("LabTitle",true,false) as Label).text)
		check("문자 전용 3D" in title_text and "45° 경사 탑뷰 · 축 정렬" in title_text,
			"lab labels its text-only cardinal-axis 45-degree projection")
		check_eq(lab.tile_nodes.size(),225,"15x15 deterministic test room")
		check(lab.find_child("BackTo2D",true,false).custom_minimum_size.y>=44 \
			and lab.find_child("LabReset",true,false).custom_minimum_size.y>=44,
			"%s close/reset remain 44px touch targets"%viewport_size)
		check_eq(_count_mesh_instances(lab.terrain_root),0,
			"terrain subtree contains no MeshInstance3D, BoxMesh tile, or substrate")
		check_eq(_count_mesh_instances(lab.world_root),0,
			"actor grounding and limbs are also glyph-only rather than tile-like meshes")
		check_eq(lab.tile_glyph_layers[Vector2i(7,7)].size(),1,
			"floor is exactly one horizontal dot glyph layer")
		check_eq(lab.tile_glyph_layers[Vector2i(5,4)].size(),2,
			"an exposed wall uses exactly one slanted top and one upright front face")
		check_eq(lab.tile_glyph_layers[Vector2i(4,4)].size(),1,
			"a wall front hidden by another wall avoids redundant text layers")
		check_eq(lab.tile_glyph_layers[Vector2i(2,10)].size(),2,
			"water uses a recessed top and darker overlapping ripple glyph")
		check_eq(lab.tile_glyph_layers[Vector2i(10,4)].size(),2,
			"metal uses a raised top plus darker vertical edge glyph")
		check_eq(lab.tile_glyph_layers[Vector2i(3,7)].size(),2,
			"rubble uses a small offset ASCII depth mark")
		var floor_glyph:Label3D=lab.tile_glyphs[Vector2i(7,7)]
		var metal_glyph:Label3D=lab.tile_glyphs[Vector2i(10,4)]
		var water_glyph:Label3D=lab.tile_glyphs[Vector2i(2,10)]
		check(metal_glyph.position.y>floor_glyph.position.y and water_glyph.position.y<floor_glyph.position.y,
			"text positions alone raise metal and recess water relative to floor")
		var floor_width:=lab.glyph_world_width(floor_glyph)
		var legacy_width:float=(lab.FONT.get_string_size(".",HORIZONTAL_ALIGNMENT_LEFT,-1,44).x+8.0)*0.005
		check(floor_glyph.font==lab.FONT and not floor_glyph.font is FontVariation \
			and floor_glyph.font_size==lab.TERRAIN_TOP_FONT_SIZE and floor_glyph.pixel_size>0.005 \
			and floor_width>=0.65 and floor_width<=0.80 and floor_width>=legacy_width*2.0,
			"upright floor metrics produce a 65-80% cell footprint at least twice the legacy size")
		for sample_cell in [Vector2i(10,4),Vector2i(2,10),Vector2i(3,7)]:
			var sample:Label3D=lab.tile_glyphs[sample_cell]
			check(sample.font_size==lab.TERRAIN_TOP_FONT_SIZE \
				and is_equal_approx(lab.glyph_world_width(sample),lab.TERRAIN_WORLD_WIDTH),
				"%s top glyph fills its explicit terrain world width"%sample_cell)
		var wall_layers:Array=lab.tile_glyph_layers[Vector2i(5,4)]
		var wall_top_glyph:=wall_layers[0] as Label3D
		var wall_top_variation:=wall_top_glyph.font as FontVariation
		check(wall_top_variation!=null and wall_top_variation.base_font==lab.FONT \
			and is_equal_approx(wall_top_variation.variation_transform.x.y,lab.WALL_TOP_SLANT) \
			and is_equal_approx(lab.glyph_world_width(wall_top_glyph),lab.WALL_WORLD_WIDTH),
			"wall top alone uses the 0.30 faux-italic FontVariation without changing its world width")
		var wall_face:=wall_layers[1] as Label3D
		var wall_face_height:=lab.glyph_world_height(wall_face)
		check(wall_face.font_size==lab.WALL_FONT_SIZE and wall_face.font==lab.FONT \
			and not wall_face.font is FontVariation and wall_face.scale.y>=0.90 \
			and lab.glyph_world_width(wall_face)>=0.85,
			"the single exposed wall face stays upright, nearly one cell wide, and minimally squeezed")
		check(wall_face_height>=1.3 and wall_face_height<=1.6 \
			and wall_top_glyph.position.y>=1.5,
			"one upright glyph forms a 1.3-1.6 world-unit face below the raised top")
		var hero_glyph:=lab.find_child("HeroGlyph",true,false) as Label3D
		var enemy_glyph:=lab.find_child("EnemyGlyph",true,false) as Label3D
		check(lab.glyph_world_width(hero_glyph)/lab.TERRAIN_WORLD_WIDTH>=1.15 \
			and lab.glyph_world_width(hero_glyph)/lab.TERRAIN_WORLD_WIDTH<=1.25 \
			and lab.glyph_world_width(enemy_glyph)/lab.TERRAIN_WORLD_WIDTH>=1.15,
			"high-contrast actors are 15-25% wider than ordinary terrain glyphs")
		var terrain_glyph_count:=0
		for layers in lab.tile_glyph_layers.values():terrain_glyph_count+=layers.size()
		check_eq(terrain_glyph_count,285,
			"single-face exposed walls reduce text-only terrain to exactly 285 glyph nodes")
		var visible:=0;var memory:=0;var unseen:=0
		for cell in lab.tile_nodes:
			var glyph:Label3D=lab.tile_glyphs[cell]
			if not glyph.visible:unseen+=1
			elif lab.seen_cells.has(cell) and lab._distance(lab.hero_cell,cell)>lab.VISIBLE_RADIUS:memory+=1
			else:visible+=1
		check(visible>0 and unseen>0,"%s exposes distinct visible and unseen regions"%viewport_size)
		var memory_cell:=Vector2i(12,8)
		var memory_base:Color=lab.tile_glyphs[memory_cell].get_meta("base_color")
		lab.hero_cell+=Vector2i.LEFT*5;lab._reveal_visible();lab._update_visuals()
		for cell in lab.seen_cells:
			if lab._distance(lab.hero_cell,cell)>lab.VISIBLE_RADIUS:memory+=1
		var memory_color:Color=lab.tile_glyphs[memory_cell].modulate
		check(memory>0 and lab.tile_glyphs[memory_cell].visible \
			and memory_color.v<memory_base.v and memory_color.s<memory_base.s,
			"movement leaves the same glyph visible with dim, desaturated memory color")
		check(not lab.tile_glyphs[Vector2i(14,0)].visible,"unseen text terrain is fully hidden")
		lab.free()
	return finish()

func test_pointer_signal_moves_one_cell_and_eases_before_camera_follow()->bool:
	var lab=Lab.new();lab.size=Vector2(360,640);lab._ready()
	lab.pointer_cell_resolver_for_test=Callable(self,"_resolve_pointer_for_test")
	var start:Vector2i=lab.hero_cell
	pointer_target=start+Vector2i(-1,-1)
	var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT
	mouse.pressed=true;mouse.position=Vector2(140,220)
	lab.input_catcher.gui_input.emit(mouse)
	var first_delta:Vector2i=lab.hero_cell-start
	check(first_delta==Vector2i(-1,-1),"actual input-catcher gui_input route preserves an adjacent diagonal tap")
	check(absi(first_delta.x)<=1 and absi(first_delta.y)<=1,"adjacent pointer movement never exceeds one cell per axis")
	check(lab.movement_settling and lab.hero_root.position==lab._cell_world(start),
		"logical movement starts a visible 160ms actor transition instead of snapping")
	var camera_before:Vector3=lab.camera.position
	lab._process(0.06)
	check(lab.hero_root.position!=lab._cell_world(start) and lab.camera.position.is_equal_approx(camera_before),
		"actor visibly leads while the follow camera briefly holds")
	# A second event during settling must be consumed without queueing another move.
	pointer_target=Vector2i(12,12);lab.input_catcher.gui_input.emit(mouse)
	check(lab.hero_cell==start+first_delta,"repeat pointer input is safely ignored during movement settling")
	lab._process(0.11)
	check(not lab.movement_settling and lab.hero_root.position.is_equal_approx(lab._cell_world(lab.hero_cell)),
		"movement settles exactly on its destination")
	lab._process(0.02)
	var before_far:Vector2i=lab.hero_cell
	var touch:=InputEventScreenTouch.new();touch.pressed=true;touch.position=Vector2(210,310)
	lab.input_catcher.gui_input.emit(touch)
	var far_delta:Vector2i=lab.hero_cell-before_far
	check(absi(far_delta.x)<=1 and absi(far_delta.y)<=1 and far_delta!=Vector2i.ZERO,
		"far touch through the same route advances only one sensible adjacent cell")
	lab.free();return finish()

func test_touch_model_attack_effects_and_demo_state_are_isolated()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var before:=session.save_session_json()
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640);sandbox.initialize_for_headless_test(session,true)
	check(sandbox.find_child("Ascii3DLabButton",true,false)==null \
			and sandbox.find_child("Ascii3DLabOverlay",true,false)==null,
		"2D product HUD does not construct the isolated visual experiment")
	check(session.save_session_json()==before,
		"removing the product lab entry does not alter the authoritative session")
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
