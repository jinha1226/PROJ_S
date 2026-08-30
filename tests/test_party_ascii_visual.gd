extends "res://tests/test_case.gd"

const Style = preload("res://playtest/ascii_visual_style.gd")
const Portrait = preload("res://playtest/ascii_actor_portrait.gd")
const Grid = preload("res://playtest/party_grid_view.gd")
const Diorama = preload("res://playtest/ascii_diorama_projection.gd")


func test_seven_terrain_glyphs_and_visibility_contract() -> bool:
	var expected := {
		"floor":".", "stone_floor":".", "wood_floor":",", "metal":"=",
		"rubble":":", "shallow_water":"~", "wall":"#",
	}
	var glyph_colors:Array[Color]=[]
	var glyph_hexes:Array[String]=[]
	for terrain_id in expected:
		var spec: Dictionary = Style.terrain_spec({"terrain_id":terrain_id})
		check_eq(spec.glyph,expected[terrain_id],"%s ASCII glyph"%terrain_id)
		check(not str(spec.base_hex).is_empty(),"%s has a base color"%terrain_id)
		check(spec.glyph_primary and spec.registered and not spec.draw_image \
			and not spec.draw_tile_border,"%s glyph is primary over a borderless code-native floor"%terrain_id)
		check_eq(bool(spec.draw_cell_surface),terrain_id=="wall",
			"only structural walls own a local slab; walkable terrain stays on the black field")
		var base:=Color(str(spec.base_hex));var glyph:=Color(str(spec.glyph_hex))
		glyph_colors.append(glyph);glyph_hexes.append(str(spec.glyph_hex))
		check(glyph.get_luminance()>base.get_luminance()+0.025,
			"%s glyph remains readable against its restrained substrate"%terrain_id)
	check_eq(glyph_hexes.duplicate().reduce(func(accum,value):
		if value not in accum:accum.append(value)
		return accum,[]).size(),expected.size(),"seven terrain roles have distinct glyph colors")
	for walkable_id in ["floor","stone_floor","wood_floor","metal","rubble","shallow_water"]:
		check_eq(Style.terrain_spec({"terrain_id":walkable_id}).slab_ratio,Vector2.ZERO,
			"%s emits no coloured checkerboard slab"%walkable_id)
	check(Style.terrain_spec({"terrain_id":"wall"}).slab_ratio!=Vector2.ZERO,
		"walls alone retain a structural local underlay")
	check(Style.terrain_spec({"terrain_id":"tree"}).glyph.is_empty() \
		and not Style.terrain_spec({"terrain_id":"tree"}).registered,
		"unregistered tree terrain is not invented for presentation")
	for walkable_id in ["floor","stone_floor","wood_floor","metal","rubble","shallow_water"]:
		check(str(Style.terrain_spec({"terrain_id":walkable_id}).glyph)!="#",
			"walkable %s never borrows the wall glyph"%walkable_id)
	check_eq([Style.feature_spec("run_entry").glyph,
		Style.feature_spec("run_exit_locked").glyph,
		Style.feature_spec("run_exit_open").glyph],["<",">",">"],
		"stairs use standard roguelike grammar independent of lock state")
	check(Style.feature_spec("run_entry").glyph!=Style.terrain_spec({"terrain_id":"floor"}).glyph \
		and Style.feature_spec("run_exit_locked").glyph!=Style.terrain_spec({"terrain_id":"floor"}).glyph,
		"entry and exit glyphs cannot merge with ordinary floor")
	check_eq(Style.feature_spec("open_door").glyph,"/","canonical open door uses slash")
	var memory: Dictionary = Style.visibility_spec("MEMORY")
	check(memory.draw_terrain and not memory.draw_hazards and not memory.draw_actors,
		"memory draws terrain only")
	check(not memory.accepts_actor_input and memory.opacity<1.0,"memory is dim and non-interactive")
	var unseen: Dictionary = Style.visibility_spec("UNSEEN")
	check(not unseen.draw_terrain and not unseen.draw_actors and unseen.opacity==0.0,
		"unseen draws and accepts nothing")
	return finish()


func test_primary_terrain_glyph_projection_is_fov_safe_and_mapping_neutral() -> bool:
	var cells:=_visible_cells()
	var terrain_ids:=["floor","stone_floor","wood_floor","metal","rubble","shallow_water","wall"]
	for index in range(terrain_ids.size()):
		cells[index].terrain_id=terrain_ids[index]
	cells[7].terrain_id="wall";cells[7].visibility_state="MEMORY"
	cells[8].terrain_id="shallow_water";cells[8].visibility_state="UNSEEN"
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var mapping:=grid.mapping_signature()
	for index in range(terrain_ids.size()):
		var spec:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(index,0))
		check(spec.visible and spec.glyph==Style.terrain_spec({"terrain_id":terrain_ids[index]}).glyph,
			"registered %s projects its primary glyph"%terrain_ids[index])
		check(not spec.draw_image and not spec.draw_tile_border,
			"terrain glyph adds no image, tile card, or input surface")
		check_eq(bool(spec.draw_cell_surface),terrain_ids[index]=="wall",
			"only the wall silhouette emits a per-cell surface rect")
	var memory:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(7,0))
	check(memory.visible and memory.visibility_state=="MEMORY" and memory.opacity<1.0,
		"memory keeps only a dim static terrain glyph")
	var unseen:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(8,0))
	check(not unseen.visible and unseen.glyph.is_empty() and unseen.terrain_id.is_empty(),
		"unseen terrain emits no glyph or terrain identity")
	check_eq(grid.mapping_signature(),mapping,"glyph projection leaves mapping and hits unchanged")
	grid.free();return finish()


func test_visibility_light_pool_memory_unseen_and_void_are_immediately_distinct() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[1,0]:cell.visibility_state="MEMORY"
		elif cell.position==[2,0]:cell.visibility_state="UNSEEN"
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid.set_hero_centered_view(Vector2i.ZERO,15,77)
	var visible_ground:Dictionary=grid.visibility_ground_draw_spec(Vector2i(0,0))
	var memory_ground:Dictionary=grid.visibility_ground_draw_spec(Vector2i(1,0))
	var unseen_ground:Dictionary=grid.visibility_ground_draw_spec(Vector2i(2,0))
	var void_ground:Dictionary=grid.visibility_ground_draw_spec(Vector2i(-1,0))
	check_eq([visible_ground.visibility_state,memory_ground.visibility_state,
		unseen_ground.visibility_state,void_ground.visibility_state],
		["VISIBLE","MEMORY","UNSEEN","VOID"],"four spatial knowledge states remain explicit")
	var visible_luma:=Color(str(visible_ground.color_hex)).get_luminance()
	var memory_luma:=Color(str(memory_ground.color_hex)).get_luminance()
	var unseen_luma:=Color(str(unseen_ground.color_hex)).get_luminance()
	var void_luma:=Color(str(void_ground.color_hex)).get_luminance()
	check(visible_luma>memory_luma and memory_luma>unseen_luma and unseen_luma>void_luma,
		"flat light pool steps clearly from visible to memory, unseen, and void")
	check(visible_ground.draw_terrain and memory_ground.draw_terrain \
		and not unseen_ground.draw_terrain and not void_ground.draw_terrain,
		"only visible and remembered cells expose static terrain")
	check(not memory_ground.draw_actors and not memory_ground.draw_hazards \
		and not unseen_ground.draw_actors and not unseen_ground.draw_hazards,
		"memory and unseen states leak no actors or live hazards")
	var visible_glyph:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(0,0))
	var memory_glyph:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(1,0))
	var unseen_glyph:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(2,0))
	var visible_color:Color=visible_glyph.rendered_glyph_color
	var memory_color:Color=memory_glyph.rendered_glyph_color
	var visible_chroma:=maxf(visible_color.r,maxf(visible_color.g,visible_color.b)) \
		-minf(visible_color.r,minf(visible_color.g,visible_color.b))
	var memory_chroma:=maxf(memory_color.r,maxf(memory_color.g,memory_color.b)) \
		-minf(memory_color.r,minf(memory_color.g,memory_color.b))
	check(visible_color.a>memory_color.a+0.5 and visible_chroma>memory_chroma,
		"remembered glyph is visibly darker and less saturated than current FOV")
	check(not unseen_glyph.visible and str(unseen_glyph.glyph).is_empty(),
		"unseen terrain emits no glyph")
	var layers:Array=grid.diorama_layer_order()
	check(layers.find("GROUND_FEATURES")>layers.find("WALL_TOPS_AND_FACES") \
		and layers.find("GROUND_FEATURES")>layers.find("MATERIAL_MARKS"),
		"stairs and doors remain above every terrain glyph layer")
	grid.free();return finish()


func test_product_floor_draw_paths_have_no_image_texture_or_tile_atlas() -> bool:
	for path in ["res://playtest/party_grid_view.gd", "res://playtest/duel_decision_grid.gd"]:
		var source:=FileAccess.get_file_as_string(path)
		check(not source.is_empty(),"product grid source is readable: %s"%path)
		for forbidden in ["character_atlas.png","Texture2D","ImageTexture","AtlasTexture",
				"Sprite2D","draw_texture","_draw_connected_material_blob"]:
			check(not source.contains(forbidden),
				"%s contains no floor image/atlas path: %s"%[path,forbidden])
	var empty_grid=Grid.new()
	var empty_spec:Dictionary=empty_grid.terrain_glyph_draw_spec(Vector2i.ZERO)
	check_eq([empty_spec.draw_image,empty_spec.draw_tile_border],[false,false],
		"empty product grid defaults to no image and no tile card")
	empty_grid.free()
	return finish()


func test_hazard_cues_are_layered_and_visibility_safe() -> bool:
	var visible: Dictionary = Style.hazard_spec({
		"visibility_state":"VISIBLE", "fire_intensity":60, "wetness":40,
		"effective_conductivity":70,
	})
	var kinds: Array = []
	for cue in visible.cues:kinds.append(cue.kind)
	check_eq(kinds,["FIRE","WET"],"only live fire and wetness have floor cues")
	check_eq(visible.fire,60,"fire value")
	check_eq(visible.wetness,40,"wet value")
	check(not visible.has("conductivity"),"conductivity is inspection data, not a visual spec")
	check(Style.hazard_spec({"conductivity":100}).cues.is_empty(),
		"conductivity never creates a persistent lightning floor cue")
	check(Style.hazard_spec({"visibility_state":"MEMORY","fire":100,"wetness":100,
		"conductivity":100}).cues.is_empty(),"memory cannot leak live hazard state")
	return finish()


func test_actor_glyph_pose_facing_status_and_guard_contract() -> bool:
	var hero: Dictionary = Style.actor_spec({"is_protagonist":true,"facing":[1,-1]})
	var human: Dictionary = Style.actor_spec({"faction_id":"party","species_id":"human"})
	var goblin: Dictionary = Style.actor_spec({"faction_id":"party","species_id":"goblin"})
	var enemy: Dictionary = Style.actor_spec({"faction_id":"enemy","species_id":"goblin"})
	var unknown: Dictionary = Style.actor_spec({"faction_id":"enemy","species_id":"slime"})
	check_eq([hero.glyph,human.glyph,goblin.glyph,enemy.glyph,unknown.glyph],
		["@","&","g","G","?"],"actor role glyph grammar")
	for spec in [hero,human,goblin,enemy,unknown]:
		check(spec.glyph_is_body and not spec.detached_head and not spec.draw_head,
			"ASCII glyph is the body with no detached head primitive")
		check_eq([spec.glyph_weight,spec.glyph_outline_passes,spec.glyph_weight_passes],
			["INK_STAMP",4,2],"actor glyph uses a compact deterministic ink stamp")
		check(spec.underlay_ratio.x>0.0 and spec.underlay_opacity>0.0,
			"actor identity owns a glyph-local background slab")
		check_eq([spec.draw_equipment,spec.equipment_primitive_count,spec.equipment],
			[false,0,{}],"actor draw grammar contains no weapon or equipment primitive")
		check(absf(spec.limb_segments[0][0].x-(spec.glyph_center.x-spec.glyph_half_width))<0.0001,
			"left arm starts at glyph edge")
		check(absf(spec.limb_segments[1][0].x-(spec.glyph_center.x+spec.glyph_half_width))<0.0001,
			"right arm starts at glyph edge")
		check(absf(spec.limb_segments[2][0].y-(spec.glyph_center.y+spec.glyph_half_height))<0.0001,
			"leg starts at glyph lower edge")
	check_eq(hero.facing,[1,-1],"diagonal facing remains explicit")
	var moving:Dictionary=Style.actor_spec({"faction_id":"party","visual_stance":"MOVING",
		"facing":[1,0]})
	var idle:Dictionary=Style.actor_spec({"faction_id":"party","visual_stance":"IDLE",
		"facing":[1,0]})
	check(moving.limb_segments!=idle.limb_segments and moving.glyph_center==idle.glyph_center,
		"movement changes limb pose without moving the glyph identity anchor")
	var guarded: Dictionary = Style.actor_spec({"faction_id":"party","guarded":true,
		"status_ids":["BLEEDING"]})
	check(guarded.bleeding and guarded.guard_segments.size()==3,
		"bleeding and guard have independent visuals")
	var downed: Dictionary = Style.actor_spec({"faction_id":"party","life_state":"DOWNED"})
	check_eq(downed.pose,"DOWNED","downed pose")
	check(downed.opacity<1.0 and downed.draw_limbs,"downed body stays legible but subdued")
	var dead: Dictionary = Style.actor_spec({"faction_id":"party","life_state":"DEAD"})
	check_eq(dead.glyph,"x","dead glyph")
	check(not dead.draw_head and not dead.draw_limbs,"dead state does not look standing")
	var ghost: Dictionary = Style.actor_spec({"faction_id":"party"},true)
	check(ghost.ghost and ghost.opacity<1.0,"proposal ghost is translucent")
	return finish()


func test_world_glyph_fits_15px_cell_and_preserves_hit_fov_contract() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:
			cell.actors.append({"entity_id":77,"faction_id":"party","species_id":"human",
				"roster_slot":0,"is_protagonist":true,"facing":[1,0],
				"logical_position":[7,7]})
	var grid=Grid.new();grid.size=Vector2(225,225)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var mapping:=grid.mapping_signature();var hit:=grid.actor_hit_rect(77)
	var spec:Dictionary=grid.actor_glyph_draw_spec(77)
	check(spec.visible and spec.font_size>=9,"15px cell keeps a readable central glyph")
	check(spec.cell_rect.encloses(spec.glyph_rect.grow(1.0)),
		"glyph outline remains in cell: %s vs %s"%[spec.glyph_rect.grow(1.0),spec.cell_rect])
	check(not spec.detached_head and spec.outline_passes==8 and not spec.selected_outline,
		"world actor has no head or yellow selection outline")
	check_eq([spec.draw_equipment,spec.equipment_primitive_count],[false,0],
		"party map draw path is glyph and attached limbs only")
	check(absf(spec.limb_segments[0][0].x-spec.glyph_rect.position.x)<=1.5 \
		and absf(spec.limb_segments[1][0].x-spec.glyph_rect.end.x)<=1.5,
		"world arms visibly join the rendered glyph edges")
	check(absf(spec.limb_segments[2][0].y-spec.glyph_rect.end.y)<=1.5,
		"world legs visibly join the rendered glyph lower edge")
	check_eq(grid.mapping_signature(),mapping,"glyph presentation cannot alter mapping")
	check_eq(grid.actor_hit_rect(77),hit,"glyph presentation cannot alter actor hit authority")
	check_eq(grid.actor_at_pointer(grid.world_to_pixel_center(Vector2i(7,7))),77,
		"logical target center remains immediately hittable")
	grid.free()
	return finish()


func test_brackets_portrait_and_specs_are_detached() -> bool:
	var segments: Array = Style.bracket_segments(Rect2(Vector2.ZERO,Vector2(40,40)))
	check_eq(segments.size(),8,"four-corner bracket uses eight strokes")
	var actor := {"entity_id":7,"faction_id":"party","species_id":"goblin"}
	var portrait = Portrait.new()
	portrait.set_actor(actor)
	actor["species_id"]="human"
	check_eq(portrait.actor_dto().species_id,"goblin","portrait owns a detached actor DTO")
	var returned: Dictionary = portrait.actor_dto()
	returned["species_id"]="orc"
	check_eq(portrait.actor_dto().species_id,"goblin","portrait getter is detached")
	check_eq(portrait.actor_draw_spec().glyph,"g","portrait consumes shared actor grammar")
	portrait.free()
	return finish()


func test_grid_filters_non_visible_actors_and_sorts_y_x_id() -> bool:
	var grid = Grid.new()
	grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":[
		{"position":[3,4],"terrain_id":"floor","visibility_state":"VISIBLE","actors":[
			{"entity_id":4,"faction_id":"enemy","roster_slot":9}]},
		{"position":[1,2],"terrain_id":"floor","visibility_state":"VISIBLE","actors":[
			{"entity_id":5,"faction_id":"party","roster_slot":1},
			{"entity_id":3,"faction_id":"enemy","roster_slot":9}]},
		{"position":[4,4],"terrain_id":"floor","visibility_state":"MEMORY","actors":[
			{"entity_id":90,"faction_id":"enemy","roster_slot":9}]},
		{"position":[5,4],"terrain_id":"floor","visibility_state":"UNSEEN","actors":[
			{"entity_id":91,"faction_id":"enemy","roster_slot":9}]},
	]})
	check_eq(grid.actor_render_order(),[3,5,4],"actors draw by y then x then stable id")
	check_eq(grid.actor_in_world_cell(Vector2i(4,4)),-1,"memory actor is not selectable")
	check_eq(grid.actor_in_world_cell(Vector2i(5,4)),-1,"unseen actor is not selectable")
	check_eq(grid.actor_at_pointer(grid.world_to_pixel_center(Vector2i(4,4))),-1,
		"memory cell pointer cannot hit a stale actor")
	grid.free()
	return finish()


func test_follower_display_position_controls_visual_hit_without_moving_logical_cell() -> bool:
	var cells: Array = []
	for y in range(15):
		for x in range(15):
			cells.append({"position":[x,y],"terrain_id":"floor","visibility_state":"VISIBLE",
				"actors":[]})
	for cell in cells:
		if cell.position==[6,8]:
			cell.actors.append({"entity_id":12,"faction_id":"party","species_id":"goblin",
				"roster_slot":1,"display_role":"FOLLOWER","logical_position":[7,7],
				"display_position":[6,8]})
	var grid = Grid.new()
	grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	check_eq(grid.actor_in_world_cell(Vector2i(7,7)),-1,
		"logical occupancy cell is not reused as presentation hit area")
	check_eq(grid.actor_in_world_cell(Vector2i(6,8)),12,
		"follower display position owns visual input")
	check_eq(grid.actor_at_pointer(grid.world_to_pixel_center(Vector2i(6,8))),12,
		"display-position figure has the actor hit target")
	var stored: Dictionary = grid._actors[0]
	check_eq(stored.logical_position,[7,7],"renderer retains logical position for tether only")
	check_eq(stored.position,[6,8],"renderer projects follower at display position")
	var follower: Dictionary = Style.follower_spec(stored)
	check(follower.visible and follower.dash_count==4,
		"follower separation requests dotted tether and party footprint")
	check_eq(follower.logical_position,[7,7],"tether starts at supplied logical position")
	check_eq(follower.display_position,[6,8],"tether ends at presentation position")
	grid.free()
	return finish()


func test_contact_follower_never_suppresses_deployment_ghost_but_ghosts_dedupe() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[6,8]:
			cell.actors.append({"entity_id":12,"faction_id":"party","species_id":"goblin",
				"roster_slot":1,"display_role":"FOLLOWER","logical_position":[7,7],
				"display_position":[6,8]})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells},[
		{"entity_id":12,"faction_id":"party","roster_slot":1,"position":[5,8]},
		{"entity_id":12,"faction_id":"party","roster_slot":1,"position":[5,8]},
		{"entity_id":12,"faction_id":"party","roster_slot":1,"position":[6,8]},
	])
	check_eq(grid._ghosts.size(),2,"follower never suppresses a deployment ghost")
	var ghost_positions:Array=[]
	for ghost in grid._ghosts:ghost_positions.append(ghost.position)
	check_eq(ghost_positions,[[5,8],[6,8]],
		"prior ghost dedupes same id and position while follower does not")
	grid.free();return finish()


func test_unseen_cell_emits_no_short_long_or_nearby_actor_signal() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.visibility_state="UNSEEN"
		if cell.position==[6,7]:cell.actors.append({"entity_id":42,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var pointer:=grid.world_cell_rect(Vector2i(7,7)).position+Vector2(1,grid.cell_size_px()*0.5)
	check_eq(grid.pixel_to_world_cell(pointer),Vector2i(7,7),"mapping still resolves unseen cell")
	check_eq(grid.actor_at_pointer(pointer),42,"fixture overlaps nearby visible actor hit slop")
	var emitted:Array=[]
	grid.world_cell_pressed.connect(func(_position):emitted.append("CELL"))
	grid.actor_pressed.connect(func(_entity_id):emitted.append("ACTOR"))
	grid.tile_long_pressed.connect(func(_position):emitted.append("LONG"))
	grid.pointer_gesture_started.connect(func():emitted.append("START"))
	grid.pointer_gesture_finished.connect(func(_outcome):emitted.append("FINISH"))
	var press:=InputEventScreenTouch.new();press.index=3;press.pressed=true;press.position=pointer
	var release:=InputEventScreenTouch.new();release.index=3;release.pressed=false;release.position=pointer
	grid._gui_input(press);grid._gui_input(release)
	grid._begin_pointer_gesture("TOUCH",4,pointer)
	grid._on_long_press_timeout(int(grid.pointer_gesture_state().generation))
	check(emitted.is_empty(),"unseen short, long, and nearby actor gestures emit no signal")
	check(not bool(grid.pointer_gesture_state().active),"unseen cell never owns a gesture")
	grid.free();return finish()


func test_hero_centered_world_padding_is_explicit_void_and_never_interactive() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[0,0]:cell.actors.append({"entity_id":77,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid.set_hero_centered_view(Vector2i.ZERO,15,77)
	check_eq(grid.view_origin,Vector2i(-7,-7),"edge hero keeps camera center without clamping")
	var padding_position:=Vector2i(-7,-7)
	var padding:Dictionary=grid.void_padding_draw_spec(padding_position)
	var pointer:Vector2=padding.rect.get_center()
	check(bool(padding.visible) and str(padding.color_hex)=="#010203" \
		and not bool(padding.accepts_input),"outside-world camera cell is an explicit void surface")
	check_eq(grid.pixel_to_world_cell(pointer),Vector2i(-1,-1),
		"void padding rejects pixel-to-world mapping")
	check_eq(grid.actor_at_pointer(pointer),-1,"void padding cannot hit the nearby centered hero")
	check(not grid.intent_draw_spec({"type":"MOVE","from_position":[0,0],
		"destination":[-1,0]}).visible,"intent endpoint cannot leak into world padding")
	check(not grid.visual_effect_draw_spec({"effect_id":"padding","event_id":1,
		"kind":"SLASH","world_position":[-1,0]}).visible,
		"effect cannot render in world padding")
	grid.set_route_overlay([[-1,0],[0,0]],0,true)
	var route:Dictionary=grid.route_draw_spec()
	check_eq(route.path,[[0,0]],"out-of-world route point is rejected before projection")
	check(not bool(route.valid),"route cannot become valid through void padding")
	var emitted:Array=[]
	grid.world_cell_pressed.connect(func(_position):emitted.append("CELL"))
	grid.actor_pressed.connect(func(_entity_id):emitted.append("ACTOR"))
	grid.tile_long_pressed.connect(func(_position):emitted.append("LONG"))
	grid._begin_pointer_gesture("TOUCH",5,pointer)
	grid._on_long_press_timeout(int(grid.pointer_gesture_state().generation))
	check(emitted.is_empty() and not bool(grid.pointer_gesture_state().active),
		"void padding owns neither short nor long-press gesture authority")
	grid.free();return finish()


func test_unseen_route_sections_are_present_but_not_drawable() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.visibility_state="UNSEEN"
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid.set_route_overlay([[6,7],[7,7],[8,7]],0,true)
	var spec:Dictionary=grid.route_draw_spec()
	check_eq(spec.path,[[6,7],[7,7],[8,7]],"route mapping keeps unseen coordinate")
	check_eq([spec.tiles[0].visible,spec.tiles[1].visible,spec.tiles[2].visible],
		[true,false,true],"unseen route tile is hidden")
	check_eq([spec.segments[0].visible,spec.segments[1].visible],[false,false],
		"segments touching unseen cells are hidden")
	check_eq([spec.direction_cues[0].visible,spec.direction_cues[1].visible],[false,false],
		"direction cues touching unseen cells are hidden")
	check(not spec.markers[1].visible,"unseen route marker is hidden")
	grid.free();return finish()


func test_unseen_intent_endpoints_are_not_drawable() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.visibility_state="UNSEEN"
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	check(not grid.intent_draw_spec({"type":"MOVE","from_position":[6,7],
		"destination":[7,7]}).visible,"move destination cannot leak into unseen")
	check(not grid.intent_draw_spec({"type":"MELEE","from_position":[6,7],
		"target_position":[7,7]}).visible,"melee target cannot leak into unseen")
	check(not grid.intent_draw_spec({"type":"HOLD","from_position":[7,7]}).visible,
		"unseen hold origin cannot leak")
	check(grid.intent_draw_spec({"type":"MOVE","from_position":[6,7],
		"destination":[6,8]}).visible,"fully visible intent remains drawable")
	grid.free();return finish()


func test_follow_plan_is_detached_offset_dashed_cued_risked_and_clearable() -> bool:
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":_visible_cells()})
	var path:=[[6,7],[7,7],[8,7]]
	var dto:={"schema_version":1,"accepted":true,"path":path,"completed_steps":0,
		"next_position":[7,7],"companion_rows":[
			{"entity_id":12,"roster_slot":1,"path":path.duplicate(true),
				"next_position":[7,7],"max_total_risk":12,"component_maxima":{"fire":12}},
			{"entity_id":13,"roster_slot":2,"path":path.duplicate(true),
				"next_position":[7,7],"max_total_risk":70,"component_maxima":{"fire":70}},
		]}
	grid.set_exploration_companion_follow_plan(dto)
	dto.path[0][0]=99;dto.companion_rows[0].path[0][0]=98
	var spec:Dictionary=grid.exploration_companion_follow_draw_spec()
	check(spec.active and spec.path[0]==[6,7],"setter owns a deep detached plan")
	check_eq(spec.rows.size(),2,"two companion lanes")
	check(spec.rows[0].offset_px!=spec.rows[1].offset_px,"roster slots use distinct path offsets")
	for row in spec.rows:
		check_eq(row.segments.size(),2,"each follower uses the shared path")
		check(row.segments[0].dash_count==4 and row.segments[0].visible,
			"follow lane is visible and dotted")
		check(row.next_cue.visible and row.next_cue.glyph==">","next-step cue is explicit")
		check(row.risk_badge.visible,"risk badge is projected")
	check_eq([spec.rows[0].risk_badge.value,spec.rows[1].risk_badge.value],[12,70],
		"risk badges retain per-companion totals")
	check_eq(grid.actor_at_pointer(spec.rows[0].next_cue.pixel_center),-1,
		"follow overlays never join actor hit testing")
	spec.rows[0].segments.clear()
	check_eq(grid.exploration_companion_follow_draw_spec().rows[0].segments.size(),2,
		"returned draw spec is detached")
	grid.set_exploration_companion_follow_plan({})
	var cleared:Dictionary=grid.exploration_companion_follow_draw_spec()
	check(not cleared.active and cleared.rows.is_empty(),"empty DTO clears follow rendering")
	grid.free();return finish()


func test_diorama_connected_masks_cover_all_cardinals_without_unseen_leak() -> bool:
	var wall := {"terrain_id":"wall","visibility_state":"VISIBLE"}
	var floor := {"terrain_id":"stone_floor","visibility_state":"VISIBLE"}
	var directions := ["N","E","S","W"]
	for expected_mask in range(16):
		var neighbors: Dictionary = {}
		for bit in range(4):
			neighbors[directions[bit]] = (wall if expected_mask & (1 << bit) else floor).duplicate(true)
		var spec: Dictionary = Diorama.cell_spec(Vector2i(7,7),wall,neighbors)
		check_eq(spec.connected_mask,expected_mask,"cardinal connected mask %d"%expected_mask)
	var memory_wall:=wall.duplicate(true);memory_wall.visibility_state="MEMORY"
	var unseen_wall:=wall.duplicate(true);unseen_wall.visibility_state="UNSEEN"
	var mixed:Dictionary=Diorama.cell_spec(Vector2i(7,7),wall,{
		"N":memory_wall,"E":unseen_wall,"S":floor,"W":floor,
		"NE":wall,
	})
	check_eq(mixed.connected_mask,Diorama.NORTH,
		"known memory connects while unseen and diagonal data do not")
	var hidden:Dictionary=Diorama.cell_spec(Vector2i(7,7),unseen_wall,{
		"N":wall,"E":wall,"S":wall,"W":wall,
	})
	check(not hidden.visible and hidden.connected_mask==0 and hidden.terrain_id.is_empty(),
		"unseen center exposes neither terrain nor silhouette")
	return finish()


func test_wall_roles_light_bands_and_tile_material_rules_are_quantized() -> bool:
	var role_vectors:=[
		[0,"END"],[Diorama.NORTH,"END"],
		[Diorama.NORTH|Diorama.SOUTH,"STRAIGHT"],
		[Diorama.NORTH|Diorama.EAST,"CORNER"],
		[Diorama.NORTH|Diorama.EAST|Diorama.SOUTH,"JUNCTION"],
		[Diorama.ALL_CARDINALS,"SOLID"],
	]
	for row in role_vectors:
		check_eq(Diorama.wall_role_spec(int(row[0]),0).role,row[1],
			"connected wall role %d"%int(row[0]))
	var south_face:Dictionary=Diorama.wall_role_spec(Diorama.NORTH,Diorama.SOUTH)
	check(south_face.face_visible and south_face.face_glyph==":",
		"exposed south wall becomes a darker ASCII face")
	check(not Diorama.wall_role_spec(Diorama.NORTH,Diorama.EAST).face_visible,
		"non-south exposure adds no false face")

	var near:Dictionary=Diorama.quantized_light_spec(Vector2i(7,7),Vector2i(7,7),"VISIBLE")
	var mid:Dictionary=Diorama.quantized_light_spec(Vector2i(11,7),Vector2i(7,7),"VISIBLE")
	var edge:Dictionary=Diorama.quantized_light_spec(Vector2i(13,7),Vector2i(7,7),"VISIBLE")
	var memory:Dictionary=Diorama.quantized_light_spec(Vector2i(7,7),Vector2i(7,7),"MEMORY")
	check_eq([near.band,mid.band,edge.band,memory.band],["NEAR","MID","EDGE","MEMORY"],
		"hero light uses four explicit knowledge-safe bands")
	check(near.foreground_multiplier>mid.foreground_multiplier \
		and mid.foreground_multiplier>edge.foreground_multiplier,
		"foreground ink falls in three discrete visible steps")
	check(memory.saturation<=0.14,"memory remains consistently near-monochrome")

	var material_families:Array=[]
	for terrain_id in ["floor","stone_floor","wood_floor","metal","rubble",
			"shallow_water","wall"]:
		var terrain:Dictionary=Style.terrain_spec({"terrain_id":terrain_id})
		material_families.append(terrain.ink_family)
		check(terrain.glyph_offset is Vector2 and terrain.slab_ratio is Vector2,
			"%s material owns placement and local background rules"%terrain_id)
		check(int(terrain.outline_passes)<=2 and int(terrain.weight_passes)<=2,
			"%s limits glyph overprint cost"%terrain_id)
	check_eq(material_families.duplicate().reduce(func(accum,value):
		if value not in accum:accum.append(value)
		return accum,[]).size(),7,"seven terrain roles use seven material families")
	return finish()


func test_fake_depth_specs_raise_walls_and_shadow_actors_without_fov_leaks() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:
			cell.terrain_id="wall"
		elif cell.position==[8,7]:
			cell.terrain_id="wall";cell.visibility_state="MEMORY"
		elif cell.position==[9,7]:
			cell.terrain_id="wall";cell.visibility_state="UNSEEN"
		elif cell.position==[6,7]:
			cell.actors.append({"entity_id":77,"faction_id":"party","species_id":"human",
				"roster_slot":0,"is_protagonist":true})
		elif cell.position==[6,8]:
			cell.visibility_state="MEMORY"
			cell.actors.append({"entity_id":88,"faction_id":"enemy","species_id":"goblin"})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var floor_depth:Dictionary=grid.terrain_depth_draw_spec(Vector2i(6,7))
	var wall_depth:Dictionary=grid.terrain_depth_draw_spec(Vector2i(7,7))
	var memory_depth:Dictionary=grid.terrain_depth_draw_spec(Vector2i(8,7))
	var unseen_depth:Dictionary=grid.terrain_depth_draw_spec(Vector2i(9,7))
	check(not floor_depth.raised and floor_depth.extrusion_px==0.0,
		"walkable floor stays low and flat")
	check(wall_depth.raised and wall_depth.extrusion_px>=2.0 \
		and wall_depth.extrusion_px<=4.0 and wall_depth.shadow_offset.length()>0.0,
		"wall has a small dark side and directional shadow")
	check(memory_depth.raised and memory_depth.opacity<wall_depth.opacity,
		"remembered wall keeps subdued depth")
	check(not unseen_depth.visible and not unseen_depth.raised,
		"unseen terrain emits no extrusion or shadow")
	check(not wall_depth.draw_cell_border and not wall_depth.draw_image,
		"fake depth adds neither cell borders nor images")
	var actor:Dictionary=grid.actor_glyph_draw_spec(77)
	check(actor.visible and actor.shadow.visible and actor.shadow.directional \
		and actor.shadow.radius.x>actor.shadow.radius.y,
		"world actor carries a compact offset ground shadow")
	check(not grid.actor_glyph_draw_spec(88).visible,
		"remembered actor and its shadow are both FOV-safe")
	grid.free();return finish()


func test_hero_camera_settle_is_move_only_centered_pure_and_input_safe() -> bool:
	var first:=_actor_observation(Vector2i.ZERO,"VISIBLE")
	var second:=_actor_observation(Vector2i(1,0),"VISIBLE")
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation(first);grid.set_hero_centered_view(Vector2i.ZERO,15,77)
	check(not grid.camera_settle_draw_spec().active,"initial camera observation snaps")
	grid.set_observation(second);grid.set_hero_centered_view(Vector2i(1,0),15,77)
	var started:=int(grid._camera_settle.started_at_ms)
	var sample0:Dictionary=grid.camera_settle_draw_spec(started)
	var sample90:Dictionary=grid.camera_settle_draw_spec(started+90)
	var sample180:Dictionary=grid.camera_settle_draw_spec(started+180)
	check_eq(grid.view_origin,Vector2i(-6,-7),"logical camera immediately follows hero-(7,7)")
	check(grid.world_to_pixel_center(Vector2i(1,0)).distance_to(grid.grid_rect().get_center())<0.01,
		"hero logical/pixel center is immediate and fixed")
	check(sample0.active and sample0.offset_px.x>0.0 \
		and sample90.offset_px.x<sample0.offset_px.x and sample90.offset_px.x>0.0 \
		and not sample180.active and sample180.offset_px==Vector2.ZERO,
		"world settle decays from the prior camera to zero in 180ms")
	check_eq(sample0.hero_counter_offset_px,-sample0.offset_px,
		"hero draw pass cancels world settle and stays at center")
	grid.set_hero_centered_view(Vector2i(1,0),15,77)
	check_eq(int(grid._camera_settle.started_at_ms),started,
		"refresh and phase-only camera calls never rearm settle")
	check_eq(grid.pixel_to_world_cell(grid.grid_rect().get_center()),Vector2i(1,0),
		"canonical pixel mapping remains exact during presentation settle")
	check_eq(grid.actor_at_pointer(grid.grid_rect().get_center()),-1,
		"actor/world gestures are safely blocked during the brief settle")
	var emitted:Array=[];grid.world_cell_pressed.connect(func(position):emitted.append(position))
	grid._begin_pointer_gesture("TOUCH",2,grid.grid_rect().get_center())
	check(emitted.is_empty() and not bool(grid.pointer_gesture_state().active),
		"settling camera owns no stale world gesture")
	check(grid.void_padding_draw_spec(Vector2i(-1,0)).visible,
		"edge void contract survives visual camera offset")
	grid._camera_settle.started_at_ms=Time.get_ticks_msec()-181
	check_eq(grid.actor_at_pointer(grid.grid_rect().get_center()),77,
		"canonical hero hit returns after settle")
	grid.set_hero_centered_view(Vector2i(10,10),15,77)
	check(not grid.camera_settle_draw_spec().active,"teleport/load-style camera changes snap")
	grid.free();return finish()


func test_product_hit_timeline_flashes_glyph_recoils_and_emits_local_ascii_feedback() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[6,7]:cell.actors.append({"entity_id":1,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
		elif cell.position==[7,7]:cell.actors.append({"entity_id":2,"faction_id":"enemy",
			"species_id":"goblin"})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid.set_hero_centered_view(Vector2i(6,7),15,1);grid.set_neutral_phase_map(true)
	var hit:={"effect_id":"42:hit","event_id":42,"order":0,"kind":"HIT_FLASH",
		"world_position":[7,7],"target_id":2,"instigator_id":1,"damage_type":"physical"}
	var amount:={"effect_id":"42:amount","event_id":42,"order":1,"kind":"FLOATING_AMOUNT",
		"world_position":[7,7],"target_id":2,"instigator_id":1,"damage_type":"physical","text":"-22"}
	check_eq(grid.play_effects([hit,amount]),2,"product effects consume each id once")
	check_eq(grid.play_effects([hit,amount]),0,"product effects remain exactly once")
	var started:=int(grid._active_visual_effects[0].started_at_ms)
	var hit0:Dictionary=grid.visual_effect_draw_spec(grid._active_visual_effects[0],started)
	var hit130:Dictionary=grid.visual_effect_draw_spec(grid._active_visual_effects[0],started+130)
	check_eq(hit0.primitive,"GLYPH_FLASH","product hit removes the circular ring")
	check(hit0.flash_active and hit0.particle_count>=2 and hit0.particle_count<=4,
		"early hit flashes target glyph and emits two to four local shards")
	check(hit0.particles.all(func(row):return str(row.get("glyph","")) in ["*","!","/","\\"]),
		"hit shards stay legible as the compact ASCII impact alphabet")
	check_eq(hit0.particles,grid.visual_effect_draw_spec(grid._active_visual_effects[0],started).particles,
		"hit shards are event-id deterministic")
	check(not hit130.flash_active,"glyph flash ends by 130ms")
	var recoil0:Dictionary=grid.actor_hit_feedback_draw_spec(2,started)
	var recoil170:Dictionary=grid.actor_hit_feedback_draw_spec(2,started+170)
	check(recoil0.flash_active and recoil0.recoil_offset.x>=3.0 \
		and recoil0.recoil_offset.x<=5.0,"target recoils away from attacker by three to five pixels")
	var flash:=Color(str(recoil0.flash_hex))
	check(flash.r>0.9 and flash.r>flash.g*2.0 and flash.r>flash.b*1.6,
		"impact gives the target glyph the highest-priority red registration flash")
	check(recoil0.impact_hold_active and recoil0.afterimage_active \
		and recoil0.afterimage_opacity>0.0,
		"initial impact adds a presentation-only registration hold and ink afterimage")
	check(recoil170.recoil_offset.length()<0.01,"target recoil returns by 170ms")
	var amount_row:Dictionary=grid._active_visual_effects[1]
	var amount0:Dictionary=grid.visual_effect_draw_spec(amount_row,started)
	var amount325:Dictionary=grid.visual_effect_draw_spec(amount_row,started+325)
	var amount650:Dictionary=grid.visual_effect_draw_spec(amount_row,started+650)
	check(amount0.font_size>=24 and amount0.text=="-22" and amount0.color_hex=="#ffd98a",
		"physical damage is a large concise warm number")
	check(amount325.pixel_center.y<amount0.pixel_center.y \
		and amount650.pixel_center.y<amount325.pixel_center.y,
		"damage number eases almost one cell upward")
	check(amount0.opacity==1.0 and amount650.opacity==0.0,
		"floating damage fades fully over 650ms")
	var miss:=grid.visual_effect_draw_spec({"effect_id":"43:miss","event_id":43,
		"kind":"MISS","world_position":[7,7],"text":"빗나감","started_at_ms":started},started)
	var slash:=grid.visual_effect_draw_spec({"effect_id":"44:slash","event_id":44,
		"kind":"SLASH","world_position":[7,7],"started_at_ms":started},started)
	var death_early:=grid.visual_effect_draw_spec({"effect_id":"45:death","event_id":45,
		"kind":"DEATH","world_position":[7,7],"started_at_ms":started},started+80)
	var death_late:=grid.visual_effect_draw_spec({"effect_id":"45:death","event_id":45,
		"kind":"DEATH","world_position":[7,7],"started_at_ms":started},started+300)
	check(miss.font_size<amount0.font_size and miss.text=="빗나감",
		"miss cue is smaller and quieter than damage")
	check_eq(slash.primitive,"LOCAL_STREAKS","slash is a short local streak, not a UI arrow")
	check(death_early.opacity==0.0 and death_late.opacity>0.0 and death_late.opacity<=0.48,
		"death cross arrives late and weak so it cannot cover the damage number")
	var offscreen:=hit.duplicate(true);offscreen.world_position=[14,14]
	check(not grid.visual_effect_draw_spec(offscreen,started).visible,
		"off-FOV hit feedback emits no field primitive")
	grid.free();return finish()


func test_physical_attack_forms_project_three_distinct_ink_trails() -> bool:
	var slash:Dictionary=Style.attack_form_spec("SLASH")
	var pierce:Dictionary=Style.attack_form_spec("찌르기")
	var impact:Dictionary=Style.attack_form_spec("BLUNT")
	check_eq([slash.attack_form,pierce.attack_form,impact.attack_form],
		["SLASH","PIERCE","IMPACT"],"physical forms normalize to the three combat silhouettes")
	check_eq([slash.trail_primitive,pierce.trail_primitive,impact.trail_primitive],
		["INK_ARC","INK_THRUST","INK_CRUSH"],"each physical form owns a distinct ink trail")
	check(slash.lead_glyph!=pierce.lead_glyph and pierce.lead_glyph!=impact.lead_glyph,
		"attack silhouettes remain readable as ASCII glyphs")
	slash.attack_form="CORRUPTED"
	check_eq(Style.attack_form_spec("SLASH").attack_form,"SLASH","attack form specs are detached")

	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[6,7]:cell.actors.append({"entity_id":1,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid.set_neutral_phase_map(true)
	var started:=Time.get_ticks_msec()
	for row in [["SLASH","INK_ARC"],["PIERCE","INK_THRUST"],["IMPACT","INK_CRUSH"]]:
		var effect:={"effect_id":"form:%s"%row[0],"event_id":41,"kind":"SLASH",
			"world_position":[7,7],"instigator_id":1,"attack_form":row[0],
			"started_at_ms":started}
		var spec:Dictionary=grid.visual_effect_draw_spec(effect,started)
		check_eq(spec.primitive,"LOCAL_STREAKS","attack remains a local presentation effect")
		check_eq(spec.trail_primitive,row[1],"%s selects its ink trail"%row[0])
		check_eq(spec.direction,Vector2.RIGHT,"trail points from instigator toward impact")
		check(spec.attack_glyph_count==4 and spec.attack_glyphs.all(func(glyph_row):
			return str(glyph_row.get("glyph","")) in ["-","/","\\","*","!",">"]),
			"%s adds a four-glyph, cell-crossing ASCII burst"%row[0])
	var ranged:=grid.visual_effect_draw_spec({"effect_id":"form:ranged","event_id":52,
		"kind":"SLASH","world_position":[10,7],"instigator_id":1,
		"attack_form":"PIERCE","started_at_ms":started},started)
	check(ranged.ranged_trajectory and ranged.attack_glyph_count>=3 \
		and ranged.attack_glyph_count<=6,
		"multi-cell attack exposes only a short bounded ASCII trajectory")
	check(ranged.attack_glyphs.all(func(glyph_row):return str(glyph_row.get("glyph","")) in ["-",">"]),
		"horizontal ranged travel reads as dashes ending in a thrust glyph")
	grid.free();return finish()


func test_diorama_hash_marks_and_layer_order_are_fixed_and_detached() -> bool:
	var vectors := [
		[Vector2i(0,0),0,0],
		[Vector2i(7,11),0,310339678],
		[Vector2i(7,11),1,377919465],
		[Vector2i(-3,5),9,1539742877],
		[Vector2i(14,14),97,1329410547],
	]
	for row in vectors:
		check_eq(Diorama.visual_hash(row[0],row[1]),row[2],
			"stable visual hash %s/%s"%[row[0],row[1]])
	var first:Dictionary=Diorama.material_mark_spec(Vector2i(5,12),"wood_floor")
	var second:Dictionary=Diorama.material_mark_spec(Vector2i(5,12),"wood_floor")
	check_eq(first,second,"material marks are coordinate-deterministic")
	first.kind="CORRUPTED"
	check(Diorama.material_mark_spec(Vector2i(5,12),"wood_floor").kind!="CORRUPTED",
		"material mark specs are detached")
	var expected_layers := ["VOID","MEMORY_GROUND","VISIBLE_GROUND","MATERIAL_MARKS",
		"WALL_SHADOWS","WALL_TOPS_AND_FACES","GROUND_FEATURES","VISIBLE_HAZARDS",
		"GROUND_ROUTES","ACTOR_GROUNDING","ACTORS","INTENTS_AND_SELECTION",
		"EFFECTS","FOV_EDGE_AND_VIGNETTE"]
	var layers:Array=Diorama.layer_order()
	check_eq(layers,expected_layers,"diorama draw layers are explicit")
	layers.clear()
	check_eq(Diorama.layer_order(),expected_layers,"layer order getter is detached")
	return finish()


func test_diorama_sanitizer_and_hazards_are_memory_unseen_safe() -> bool:
	var raw := {"position":[4,5],"terrain_id":"wall","feature_id":"run_exit_open",
		"visibility_state":"MEMORY","fire_intensity":90,"fire":91,"wetness":92,
		"effective_conductivity":93,"conductivity":94,"base_conductivity":95,
		"actors":[{"entity_id":9}],"secret":"must disappear"}
	var memory:Dictionary=Diorama.sanitize_observed_cell(raw)
	check_eq(memory,{"visibility_state":"MEMORY","terrain_id":"wall"},
		"memory sanitizer whitelists static terrain only")
	var memory_hazard:Dictionary=Diorama.hazard_floor_spec(Vector2i(4,5),raw)
	check_eq([memory_hazard.visible,memory_hazard.fire,memory_hazard.wetness],
		[false,0,0],"memory aliases cannot leak live hazards")
	check(not memory_hazard.has("conductivity") and not memory_hazard.has("arc_alpha"),
		"diorama has no conductive floor primitive")
	var unseen_raw:=raw.duplicate(true);unseen_raw.visibility_state="UNSEEN"
	check_eq(Diorama.sanitize_observed_cell(unseen_raw),{"visibility_state":"UNSEEN"},
		"unseen sanitizer exposes no authoritative fields")
	var visible_raw:=raw.duplicate(true);visible_raw.visibility_state="VISIBLE"
	var visible_hazard:Dictionary=Diorama.hazard_floor_spec(Vector2i(4,5),visible_raw)
	check(visible_hazard.visible and visible_hazard.fire==90 and visible_hazard.wetness==92,
		"visible fire and wetness produce a floor-layer spec")
	check(not visible_hazard.has("conductivity") and not visible_hazard.has("arc_alpha"),
		"visible conductive terrain still has no arc visual")
	memory.terrain_id="CORRUPTED"
	check_eq(str(raw.terrain_id),"wall","sanitizer output is detached from observation")
	return finish()


func test_diorama_equipment_projection_is_removed_from_every_actor_role() -> bool:
	var cases := [
		{"is_protagonist":true,"faction_id":"enemy","species_id":"goblin","roster_slot":1},
		{"faction_id":"party","species_id":"human","roster_slot":1},
		{"faction_id":"party","species_id":"goblin","roster_slot":2},
		{"faction_id":"enemy","species_id":"goblin","roster_slot":99},
		{"faction_id":"neutral","species_id":"human","inventory":["legendary_sword"]},
	]
	for actor_value in cases:
		var actor:Dictionary=actor_value;var before:=actor.duplicate(true)
		var spec:Dictionary=Diorama.equipment_spec(actor)
		check_eq(actor,before,"visual projection never mutates canonical weapon data")
		check_eq([spec.equipment_id,spec.back_segments,spec.front_segments,
			spec.front_polyline,spec.shield_points,spec.lantern.visible,
			spec.draw_equipment,spec.equipment_primitive_count],
			["NONE",[],[],[],[],false,false,0],
			"every role projects glyph and attached limbs with zero equipment primitives")
	return finish()


func test_diorama_route_style_preserves_mapping_and_actor_hit_authority() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.actors.append({"entity_id":77,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var mapping:=grid.mapping_signature();var hit:=grid.actor_hit_rect(77)
	check_eq(grid.diorama_layer_order(),Diorama.layer_order(),
		"grid forwards pure layer order")
	check_eq(grid.diorama_cell_draw_spec(Vector2i(7,7)).connected_mask,15,
		"visible same-terrain cross connects")
	grid.set_route_overlay([[6,7],[7,7],[8,7]],0,true)
	var route:Dictionary=grid.route_draw_spec()
	check_eq([route.render_style,route.draw_tile_cards],["CHALK_CENTERLINE",false],
		"route renders as chalk centerline without tile cards")
	check_eq(grid.mapping_signature(),mapping,"diorama and route never alter grid mapping")
	check_eq(grid.actor_hit_rect(77),hit,"equipment never enlarges actor hit authority")
	check_eq(grid.pixel_to_world_cell(grid.world_to_pixel_center(Vector2i(7,7))),Vector2i(7,7),
		"logical cell center roundtrip remains exact")
	check_eq(grid.actor_at_pointer(grid.world_to_pixel_center(Vector2i(7,7))),77,
		"visual equipment adds no competing hit surface")
	grid.free();return finish()


func test_selected_actor_has_no_yellow_overlay_but_target_and_ghost_remain() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.actors.append({"entity_id":1,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
		if cell.position==[8,7]:cell.actors.append({"entity_id":2,"faction_id":"enemy",
			"roster_slot":99})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells},[
		{"entity_id":3,"faction_id":"party","roster_slot":1,"position":[6,7]}])
	grid.set_selection(1,2)
	var overlays:Array=grid.selection_overlay_draw_specs()
	check_eq(overlays.map(func(row):return row.kind),["TARGET","DEPLOYMENT_GHOST"],
		"selected party actor emits no map bracket")
	check_eq([overlays[0].entity_id,overlays[0].color_hex],[2,"#ff6b70"],
		"enemy target retains red selection semantics")
	check_eq(overlays[1].entity_id,3,"deployment proposal retains cyan ghost bracket")
	overlays[0].kind="CORRUPTED"
	check_eq(grid.selection_overlay_draw_specs()[0].kind,"TARGET","overlay specs are detached")
	grid.free();return finish()


func test_actor_motion_eases_draw_only_and_snaps_without_canonical_arm() -> bool:
	var grid=Grid.new();grid.size=Vector2(345,345)
	var initial:=_actor_observation(Vector2i(7,7),"VISIBLE")
	grid.set_observation(initial)
	var mapping:=grid.mapping_signature()
	check(grid.actor_motion_state().is_empty(),"initial observation snaps")
	grid.arm_actor_motion([77],150);grid.set_observation(_actor_observation(Vector2i(8,7),"VISIBLE"))
	var motion:Dictionary=grid.actor_motion_state()[77]
	var started:=int(motion.started_at_ms)
	var sample0:Dictionary=grid.actor_motion_draw_spec(77,started)
	var sample75:Dictionary=grid.actor_motion_draw_spec(77,started+75)
	var sample150:Dictionary=grid.actor_motion_draw_spec(77,started+150)
	check_eq(sample0.world_position,Vector2(7,7),"motion starts at prior presentation cell")
	check(absf(float(sample75.eased_progress)-0.875)<0.0001,
		"75ms cubic ease-out reaches deterministic 87.5 percent")
	check_eq(sample150.world_position,Vector2(8,7),"150ms motion ends at target")
	check_eq(grid.actor_in_world_cell(Vector2i(8,7)),77,"authoritative hit cell changes immediately")
	check(grid.actor_hit_rect(77).has_point(grid.world_to_pixel_center(Vector2i(8,7))),
		"authoritative target center owns hit immediately")
	check_eq(grid.mapping_signature(),mapping,"animation never changes grid mapping")
	grid.set_observation(_actor_observation(Vector2i(10,7),"VISIBLE"))
	check(grid.actor_motion_state().is_empty(),"unarmed observation change snaps")
	grid.arm_actor_motion([77],150);grid.set_observation(_actor_observation(Vector2i(12,7),"VISIBLE"))
	check(grid.actor_motion_state().is_empty(),"two-cell teleport snaps even when armed")
	grid.free();return finish()


func test_static_projection_cache_is_viewport_bounded_and_motion_phase_is_free() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.actors.append({"entity_id":77,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
	var grid=Grid.new();grid.size=Vector2(360,360)
	grid.set_observation({"width":48,"height":48,"cells":cells})
	grid.set_hero_centered_view(Vector2i(7,7),15,77)
	var initial:Dictionary=grid.static_projection_cache_stats()
	check_eq([initial.cell_count,initial.viewport_capacity],[225,225],
		"static projection cache is bounded to the 15x15 camera")
	check(initial.world_cell_count<=225,"cache does not require a 48x48 presentation copy")
	var occupied:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(7,7))
	var clear:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(8,7))
	check(occupied.occupied and not clear.occupied \
		and (occupied.rendered_glyph_color as Color).a \
		< (clear.rendered_glyph_color as Color).a,
		"actor tile suppresses floor ink without adding a selection ring")
	var rebuilds:=int(initial.rebuild_count)
	grid.set_hero_centered_view(Vector2i(7,7),15,77)
	check_eq(grid.static_projection_cache_stats().rebuild_count,rebuilds,
		"same hero/view does not invalidate static ink")
	grid.play_effects([{"effect_id":"cache:hit","event_id":901,"order":0,
		"kind":"HIT_FLASH","world_position":[7,7],"target_id":77}])
	check_eq(grid.static_projection_cache_stats().rebuild_count,rebuilds,
		"transient hit animation does not rebuild static cells")
	grid.set_hero_centered_view(Vector2i(8,7),15,77)
	check_eq(grid.static_projection_cache_stats().rebuild_count,rebuilds+1,
		"hero/light/view change invalidates exactly once")

	var contact:Dictionary=grid.actor_motion_sample(Vector2.ZERO,Vector2.RIGHT,0,150)
	var passing:Dictionary=grid.actor_motion_sample(Vector2.ZERO,Vector2.RIGHT,75,150)
	var settle:Dictionary=grid.actor_motion_sample(Vector2.ZERO,Vector2.RIGHT,150,150)
	check_eq([contact.step_phase,passing.step_phase,settle.step_phase],
		["CONTACT","PASS","SETTLE"],"one movement owns three compact glyph phases")
	check(contact.stride_sign==1 and passing.stride_sign==-1 and settle.stride_sign==0,
		"step phase alternates limbs and returns to neutral")
	check(passing.glyph_bob_ratio<0.0 and not settle.active,
		"bob exists only during the already-active movement process")
	grid.free();return finish()


func test_colorful_terrain_palette_keeps_role_glyphs_high_contrast_and_distinct() -> bool:
	var terrain_ids:=["floor","stone_floor","wood_floor","metal","rubble","shallow_water","wall"]
	var brightest_ground:=0.0
	var terrain_glyph_hexes:Array[String]=[]
	for terrain_id in terrain_ids:
		var terrain:Dictionary=Style.terrain_spec({"terrain_id":terrain_id})
		var base:=Color(str(terrain.base_hex));var glyph:=Color(str(terrain.glyph_hex))
		brightest_ground=maxf(brightest_ground,base.get_luminance())
		terrain_glyph_hexes.append(str(terrain.glyph_hex))
		check(glyph.get_luminance()>base.get_luminance()+0.025,
			"%s restrained glyph clears its nearly-black ground"%terrain_id)
		var chroma:=maxf(glyph.r,maxf(glyph.g,glyph.b))-minf(glyph.r,minf(glyph.g,glyph.b))
		check(chroma<0.18,"%s terrain ink stays subordinate to saturated actors"%terrain_id)
	check_eq(terrain_glyph_hexes.duplicate().reduce(func(accum,value):
		if value not in accum:accum.append(value)
		return accum,[]).size(),terrain_ids.size(),"terrain glyph palette is role-distinct")
	var role_specs:=[
		Style.actor_spec({"is_protagonist":true,"roster_slot":0}),
		Style.actor_spec({"faction_id":"party","species_id":"human","roster_slot":1}),
		Style.actor_spec({"faction_id":"party","species_id":"human","roster_slot":2}),
		Style.actor_spec({"faction_id":"party","species_id":"goblin","roster_slot":2}),
		Style.actor_spec({"faction_id":"enemy","species_id":"goblin"}),
	]
	var colors:Array=[]
	for spec in role_specs:
		var color:=Color(str(spec.color_hex));colors.append(str(spec.color_hex))
		check(color.get_luminance()>brightest_ground+0.16,"actor glyph clears dark terrain")
	check_eq(colors.duplicate().reduce(func(accum,value):
		if value not in accum:accum.append(value)
		return accum,[]).size(),5,"gold/cyan/blue/green/red roles are color-distinct")
	var palette:Dictionary=Style.diorama_palette_spec()
	check(Color(str(palette.void_hex)).get_luminance()<Color(str(palette.substrate_hex)).get_luminance(),
		"void remains darker than neutral substrate")
	return finish()


func _actor_observation(position:Vector2i,visibility_state:String)->Dictionary:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[position.x,position.y]:
			cell.visibility_state=visibility_state
			cell.actors.append({"entity_id":77,"faction_id":"party","species_id":"human",
				"roster_slot":0,"is_protagonist":true,"logical_position":[position.x,position.y]})
	return {"width":15,"height":15,"cells":cells}


func _visible_cells()->Array:
	var cells:Array=[]
	for y in range(15):
		for x in range(15):
			cells.append({"position":[x,y],"terrain_id":"floor","visibility_state":"VISIBLE",
				"actors":[]})
	return cells
