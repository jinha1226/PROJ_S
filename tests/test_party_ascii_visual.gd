extends "res://tests/test_case.gd"

const Style = preload("res://playtest/ascii_visual_style.gd")
const Portrait = preload("res://playtest/ascii_actor_portrait.gd")
const Grid = preload("res://playtest/party_grid_view.gd")


func test_seven_terrain_glyphs_and_visibility_contract() -> bool:
	var expected := {
		"floor":".", "stone_floor":":", "wood_floor":"=", "metal":"+",
		"rubble":",", "shallow_water":"~", "wall":"#",
	}
	var base_colors: Dictionary = {}
	for terrain_id in expected:
		var spec: Dictionary = Style.terrain_spec({"terrain_id":terrain_id})
		check_eq(spec.glyph,expected[terrain_id],"%s ASCII glyph"%terrain_id)
		check(not str(spec.base_hex).is_empty(),"%s has a base color"%terrain_id)
		base_colors[str(spec.base_hex)]=true
	check_eq(base_colors.size(),7,"seven terrains remain color-distinct")
	var memory: Dictionary = Style.visibility_spec("MEMORY")
	check(memory.draw_terrain and not memory.draw_hazards and not memory.draw_actors,
		"memory draws terrain only")
	check(not memory.accepts_actor_input and memory.opacity<1.0,"memory is dim and non-interactive")
	var unseen: Dictionary = Style.visibility_spec("UNSEEN")
	check(not unseen.draw_terrain and not unseen.draw_actors and unseen.opacity==0.0,
		"unseen draws and accepts nothing")
	return finish()


func test_hazard_cues_are_layered_and_visibility_safe() -> bool:
	var visible: Dictionary = Style.hazard_spec({
		"visibility_state":"VISIBLE", "fire_intensity":60, "wetness":40,
		"effective_conductivity":70,
	})
	var kinds: Array = []
	for cue in visible.cues:kinds.append(cue.kind)
	check_eq(kinds,["FIRE","WET","CONDUCTIVE"],"hazard cue order")
	check_eq(visible.fire,60,"fire value")
	check_eq(visible.wetness,40,"wet value")
	check_eq(visible.conductivity,70,"conductivity value")
	check(Style.hazard_spec({"conductivity":24}).cues.is_empty(),
		"sub-threshold conductivity has no visual cue")
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
	check_eq(hero.facing,[1,-1],"diagonal facing remains explicit")
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


func test_companion_speech_specs_are_fov_safe_clamped_nonoverlapping_and_detached() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:
			cell.actors.append({"entity_id":10,"faction_id":"party","is_protagonist":true,
				"roster_slot":0,"display_role":"PROTAGONIST"})
		elif cell.position==[6,7]:
			cell.actors.append({"entity_id":11,"faction_id":"party","is_protagonist":false,
				"roster_slot":1,"display_role":"COMPANION"})
		elif cell.position==[8,7]:
			cell.actors.append({"entity_id":12,"faction_id":"party","is_protagonist":false,
				"roster_slot":2,"display_role":"COMPANION"})
		elif cell.position==[9,7]:
			cell.visibility_state="MEMORY"
			cell.actors.append({"entity_id":13,"faction_id":"party","is_protagonist":false,
				"roster_slot":3,"display_role":"COMPANION"})
	var grid=Grid.new();grid.size=Vector2(360,360)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var mapping_before:=grid.mapping_signature()
	var hit_before:=grid.actor_at_pointer(grid.world_to_pixel_center(Vector2i(7,7)))
	grid.set_intent_overlays([
		{"actor_id":10,"actor_name":"주인공","role":"PROTAGONIST","roster_slot":0,
			"from_position":[7,7],"source":"DIRECT","type":"MELEE",
			"reason":"직접 공격합니다."},
		{"actor_id":11,"actor_name":"동료 하나","role":"COMPANION","roster_slot":1,
			"from_position":[6,7],"source":"SUGGESTED","type":"HOLD",
			"reason":"위험과 거리를 보고 자리를 지킵니다.","source_color":"#75c8ff"},
		{"actor_id":12,"actor_name":"동료 둘","role":"COMPANION","roster_slot":2,
			"from_position":[8,7],"source":"SUGGESTED","type":"MOVE",
			"reason":"목표에 접근할 길을 골랐습니다.","source_color":"#75c8ff"},
		{"actor_id":13,"actor_name":"기억 속 동료","role":"COMPANION","roster_slot":3,
			"from_position":[9,7],"source":"SUGGESTED","type":"MELEE",
			"reason":"인접한 적을 공격할 수 있습니다."},
	])
	var specs:Array=grid.speech_bubble_draw_specs()
	check_eq(specs.size(),3,"hero is excluded and each primary companion intent has one spec")
	var visible:Array=[];var hidden:Dictionary={}
	for spec in specs:
		if bool(spec.visible):visible.append(spec)
		else:hidden=spec
	check_eq(visible.size(),2,"only FOV-visible companions draw speech")
	check_eq([visible[0].source,visible[0].action_type,visible[0].headline],
		["SUGGESTED","HOLD","엄호할게."],"suggested hold speech is explicit")
	check_eq([visible[1].source,visible[1].action_type,visible[1].headline],
		["SUGGESTED","MOVE","이동할게."],"move speech is explicit")
	check_eq(visible[1].reason,"목표에 접근할 길을 골랐습니다.",
		"draw spec preserves the action reason")
	check_eq([hidden.actor_id,hidden.visible,hidden.bounds],[13,false,Rect2()],
		"memory companion speech is non-drawable and has no bounds")
	check(not visible[0].bounds.grow(3.0).intersects(visible[1].bounds.grow(3.0)),
		"two deterministic bubbles do not overlap")
	for spec in visible:
		check(grid.grid_rect().encloses(spec.bounds),"bubble is clamped inside grid bounds")
		check(int(spec.font_size)>=12,"360-wide grid keeps speech at least 12px")
		check_eq(spec.tail_points.size(),3,"code-native bubble includes a tail")
	check_eq(grid.mapping_signature(),mapping_before,"speech changes no grid coordinate mapping")
	check_eq(grid.actor_at_pointer(grid.world_to_pixel_center(Vector2i(7,7))),hit_before,
		"speech changes no actor hit testing")
	specs[0].bounds=Rect2(Vector2(999,999),Vector2.ONE)
	check(grid.speech_bubble_draw_specs()[0].bounds.position.x<999,
		"returned speech draw specs are detached")
	grid.set_intent_overlays([
		{"actor_id":11,"actor_name":"동료 하나","role":"COMPANION","roster_slot":1,
			"from_position":[6,7],"source":"OVERRIDE","type":"HOLD",
			"reason":"자동 제안 대신 개별 지시를 따릅니다.","source_color":"#ff9f68",
			"automatic_suggestion":{"source":"SUGGESTED","type":"MOVE",
				"from_position":[6,7],"destination":[6,6]}},
		{"actor_id":12,"actor_name":"동료 둘","role":"COMPANION","roster_slot":2,
			"from_position":[8,7],"source":"SUGGESTED","type":"HOLD",
			"resolution_note":"destination_conflict_suggested_hold",
			"reason":"이동 경로가 충돌해 이번 턴에는 자리를 지킵니다."},
	])
	var updated:Array=grid.speech_bubble_draw_specs()
	check_eq(updated.size(),2,"secondary original suggestion creates no extra speech")
	check_eq([updated[0].source,updated[0].headline,updated[1].headline],
		["OVERRIDE","대기할게.","대기할게."],
		"override and conflict HOLD update speech immediately")
	grid.free();return finish()


func _visible_cells()->Array:
	var cells:Array=[]
	for y in range(15):
		for x in range(15):
			cells.append({"position":[x,y],"terrain_id":"floor","visibility_state":"VISIBLE",
				"actors":[]})
	return cells
