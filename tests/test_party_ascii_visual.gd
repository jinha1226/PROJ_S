extends "res://tests/test_case.gd"

const Style = preload("res://playtest/ascii_visual_style.gd")
const Portrait = preload("res://playtest/ascii_actor_portrait.gd")
const Grid = preload("res://playtest/party_grid_view.gd")
const Diorama = preload("res://playtest/ascii_diorama_projection.gd")


func test_seven_terrain_glyphs_and_visibility_contract() -> bool:
	var expected := {
		"floor":".", "stone_floor":"#", "wood_floor":",", "metal":"=",
		"rubble":":", "shallow_water":"~", "wall":"#",
	}
	var darkest_base:=1.0
	var brightest_base:=0.0
	for terrain_id in expected:
		var spec: Dictionary = Style.terrain_spec({"terrain_id":terrain_id})
		check_eq(spec.glyph,expected[terrain_id],"%s ASCII glyph"%terrain_id)
		check(not str(spec.base_hex).is_empty(),"%s has a base color"%terrain_id)
		check(spec.glyph_primary and spec.registered and not spec.draw_image \
			and not spec.draw_tile_border,"%s glyph is primary over a borderless code-native floor"%terrain_id)
		check_eq(bool(spec.draw_cell_surface),terrain_id!="floor",
			"ordinary floor uses grid-wide flat background; special terrain may use flat surface")
		var luminance:=Color(str(spec.base_hex)).get_luminance()
		darkest_base=minf(darkest_base,luminance);brightest_base=maxf(brightest_base,luminance)
	check(brightest_base-darkest_base<0.025,"terrain backgrounds stay nearly uniform neutral navy")
	check(Style.terrain_spec({"terrain_id":"tree"}).glyph.is_empty() \
		and not Style.terrain_spec({"terrain_id":"tree"}).registered,
		"unregistered tree terrain is not invented for presentation")
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
		check_eq(bool(spec.draw_cell_surface),terrain_ids[index]!="floor",
			"only ordinary floor suppresses its per-cell surface rect")
	var memory:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(7,0))
	check(memory.visible and memory.visibility_state=="MEMORY" and memory.opacity<1.0,
		"memory keeps only a dim static terrain glyph")
	var unseen:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(8,0))
	check(not unseen.visible and unseen.glyph.is_empty() and unseen.terrain_id.is_empty(),
		"unseen terrain emits no glyph or terrain identity")
	check_eq(grid.mapping_signature(),mapping,"glyph projection leaves mapping and hits unchanged")
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
		check_eq([spec.glyph_weight,spec.glyph_outline_passes],["OUTLINE_REDRAW",8],
			"regular project font gains deterministic outline weight")
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


func test_neutral_terrain_palette_keeps_role_glyphs_high_contrast_and_distinct() -> bool:
	var terrain_ids:=["floor","stone_floor","wood_floor","metal","rubble","wall"]
	var brightest_ground:=0.0
	for terrain_id in terrain_ids:
		var color:=Color(str(Style.terrain_spec({"terrain_id":terrain_id}).base_hex))
		brightest_ground=maxf(brightest_ground,color.get_luminance())
		check(maxf(color.r,maxf(color.g,color.b))-minf(color.r,minf(color.g,color.b))<0.09,
			"%s remains low-chroma neutral"%terrain_id)
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
