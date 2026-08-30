extends "res://tests/test_case.gd"

const DungeonMap = preload("res://playtest/deterministic_dungeon_map.gd")
const Session = preload("res://playtest/party_playtest_session.gd")
const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")
const Command = preload("res://sim/sim_command.gd")


func test_same_seed_is_exact_and_different_seed_changes_layout() -> bool:
	var first := DungeonMap.generate(48, 48, 44)
	var second := DungeonMap.generate(48, 48, 44)
	var other := DungeonMap.generate(48, 48, 45)
	check(not first.is_empty(), "generated layout exists")
	check_eq(first, second, "same seed reproduces the exact layout")
	check(first.terrain != other.terrain, "different seed changes terrain topology")
	check_eq([first.width, first.height], [48, 48], "product dungeon size")
	return finish()


func test_rooms_features_materials_and_objectives_are_connected() -> bool:
	var layout := DungeonMap.generate(48, 48, 8080)
	var entry: Vector2i = layout.entry_position
	var exit: Vector2i = layout.exit_position
	check(DungeonMap.reachable(layout, entry, exit), "entry reaches exit")
	for enemy_position in layout.enemy_positions:
		check(DungeonMap.reachable(layout, entry, enemy_position),
			"entry reaches every enemy spawn")
	check(layout.rooms.size() >= 9, "dungeon contains several rooms")
	check(not layout.door_positions.is_empty(), "dungeon exposes open-door features")
	check(not layout.hazards.is_empty(), "dungeon exposes hazard positions")
	for material_id in ["shallow_water", "metal", "wood_floor", "rubble"]:
		check(not layout.material_positions[material_id].is_empty(),
			"material terrain present: %s" % material_id)
	for x in range(48):
		check_eq(DungeonMap.terrain_at(layout, Vector2i(x, 0)), "wall", "north border")
		check_eq(DungeonMap.terrain_at(layout, Vector2i(x, 47)), "wall", "south border")
	for y in range(48):
		check_eq(DungeonMap.terrain_at(layout, Vector2i(0, y)), "wall", "west border")
		check_eq(DungeonMap.terrain_at(layout, Vector2i(47, y)), "wall", "east border")
	return finish()


func test_solo_session_uses_large_map_los_memory_and_seeded_spawns() -> bool:
	var first = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var second = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check(first.sim != null and second.sim != null, "solo sessions initialize")
	if first.sim == null or second.sim == null:
		return finish()
	check_eq([first.sim.world.width, first.sim.world.height], [48, 48],
		"solo world is larger than the viewport")
	check_eq(first.sim.snapshot(), second.sim.snapshot(),
		"same seed reproduces authoritative world and spawns")
	var state = first.sim.world.party_encounter
	var hero_position: Vector2i = first.sim.world.entities[state.protagonist_id].position
	var enemy_position: Vector2i = first.sim.world.entities[state.enemy_ids[0]].position
	var opening_distance:=maxi(absi(hero_position.x-enemy_position.x),
		absi(hero_position.y-enemy_position.y))
	check(opening_distance>=4 and opening_distance<=6,
		"monster begins visible with two-to-four approach steps before adjacency")
	check(DungeonMap.terrain_at(first._map_layout,enemy_position)!="wall" \
		and enemy_position!=first._map_layout.exit_position \
		and enemy_position not in first._map_layout.door_positions,
		"opening monster population never occupies a wall, exit, or door")
	var observation := first.observe_party_world()
	check_eq(observation.visibility.mode, "LOS_RADIUS", "large map keeps bounded LOS")
	check_eq(observation.visibility.radius, 6, "large map keeps the 15x15 camera-safe FOV")
	var visible_count := 0
	var unseen_count := 0
	for cell in observation.cells:
		if str(cell.visibility_state) == "VISIBLE": visible_count += 1
		elif str(cell.visibility_state) == "UNSEEN": unseen_count += 1
	check(visible_count > 0 and visible_count <= 169,
		"observation reveals a local window rather than the whole dungeon")
	check(unseen_count > 0, "large dungeon begins with unexplored cells")
	var enemy_visible:=false
	for cell in observation.cells:
		if cell.position==[enemy_position.x,enemy_position.y]:
			enemy_visible=str(cell.visibility_state)=="VISIBLE" \
				and not cell.actors.is_empty()
	check(enemy_visible,"opening monster is present inside the initial LOS observation")
	check_eq(first.run_progress().entry_position,
		[hero_position.x, hero_position.y], "run manifest follows generated entry")
	return finish()


func test_large_map_save_load_regenerates_seeded_layout_exactly() -> bool:
	var source = Session.new(8080, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check(source.sim != null, "source large-map session initializes")
	if source.sim == null:
		return finish()
	var encoded := source.save_session_json()
	var restored = Session.new(1, 2, Session.SOLO_COMBAT_SCENARIO_ID)
	var result: Dictionary = restored.load_session_json(encoded)
	check(bool(result.get("accepted", false)),
		"large-map session load accepted: %s" % str(result))
	if bool(result.get("accepted", false)):
		check_eq(restored.sim.snapshot(), source.sim.snapshot(),
			"large-map save restore remains exact")
		check_eq(restored.run_progress(), source.run_progress(),
			"regenerated entry and exit stay exact")
	return finish()


func test_product_touch_melee_vfx_starts_after_refresh_and_survives_a_frame()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	# A live container supplies this extent. The synchronous product fixture uses
	# the same 15x15 cell geometry so real ScreenTouch routing remains exercised.
	sandbox.grid.size=Vector2(345,345);sandbox._refresh()
	var state=session.sim.world.party_encounter
	var hero_id:=int(state.protagonist_id);var enemy_id:=int(state.enemy_ids[0])
	var hero_position:Vector2i=session.sim.world.entities[hero_id].position
	var enemy_position:Vector2i=session.sim.world.entities[enemy_id].position
	check_eq(sandbox.grid.actor_in_world_cell(enemy_position),enemy_id,
		"product opening observation exposes the authoritative nearby enemy glyph")
	var movement_inputs:=0
	var explore_step:=_first_exploration_step_toward(session,hero_id,enemy_position)
	check(explore_step!=Vector2i(-1,-1),"opening map exposes a legal touch approach")
	if explore_step!=Vector2i(-1,-1):
		_screen_touch_world(sandbox,explore_step);movement_inputs+=1
	check_eq(session.party_status().safe_phase,"ENGAGED",
		"opening touch reaches product solo combat through automatic deployment")
	while session.party_status().safe_phase=="ENGAGED" \
			and _entity_distance(session,hero_id,enemy_id)>1 and movement_inputs<4:
		_finish_product_camera_settle(sandbox)
		enemy_position=session.sim.world.entities[enemy_id].position
		var combat_step:=_first_combat_step_toward(session,hero_id,enemy_position)
		check(combat_step!=Vector2i(-1,-1),"combat approach has a legal touched cell")
		if combat_step==Vector2i(-1,-1):break
		var before_move_step:=int(session.party_status().step_index)
		_screen_touch_world(sandbox,combat_step)
		check(int(session.party_status().step_index)==before_move_step+1 \
				and not bool(sandbox.auto_flow_state().get("combat_pending",false)),
			"one-member product cell touch commits its authoritative turn immediately")
		movement_inputs+=1
	check(movement_inputs>=2 and movement_inputs<=4 \
		and _entity_distance(session,hero_id,enemy_id)==1,
		"nearby spawn becomes melee-adjacent after two to four movement touches")
	_finish_product_camera_settle(sandbox)
	hero_position=session.sim.world.entities[hero_id].position
	enemy_position=session.sim.world.entities[enemy_id].position
	var committed_after_ms:=Time.get_ticks_msec()
	var before_melee_step:=int(session.party_status().step_index)
	_screen_touch_world(sandbox,enemy_position)
	check_eq(sandbox.selected_target_id,-1,
		"committed enemy tap clears transient target selection")
	check(int(session.party_status().step_index)==before_melee_step+1 \
			and not bool(sandbox.auto_flow_state().get("combat_pending",false)),
		"real enemy glyph touch commits MELEE in the same input callback")
	check(sandbox.grid._intent_overlays.is_empty() and sandbox.grid._route_path.is_empty() \
			and sandbox.grid.cursor_cell==Vector2i(-1,-1),
		"direct solo combat renders no stale plan, route, or cursor marks")
	check(sandbox._pending_visual_effect_rows.is_empty(),
		"result effects flush only after the committed refresh completes")
	var overlay=sandbox.grid.melee_vfx
	check(overlay!=null,"product grid creates its separate melee overlay")
	var matched:Dictionary={}
	if overlay!=null:
		for effect in overlay.active_effects():
			if effect.attacker_grid_pos==hero_position \
					and effect.target_grid_pos==enemy_position \
					and int(effect.started_at_ms)>=committed_after_ms:
				matched=effect;break
	check(not matched.is_empty(),
		"touch commit carries the canonical hero/target pair through result, record, grid, and overlay")
	if not matched.is_empty():
		var params:Dictionary=overlay.parameter_spec()
		var frame_a:=int(matched.started_at_ms)+int(params.contact_at_ms)
		var frame_b:=frame_a+16
		var spec_a:=_effect_sequence_spec(overlay,frame_a,int(matched.sequence))
		var spec_b:=_effect_sequence_spec(overlay,frame_b,int(matched.sequence))
		check(_complete_melee_frame(spec_a) and _complete_melee_frame(spec_b),
			"line, target-background flash, and particles remain drawable across a full frame")
		check(Time.get_ticks_msec()-int(matched.started_at_ms) \
				<int(params.effect_duration_ms) and not overlay.effect_draw_specs().is_empty(),
			"refresh work cannot expire the newly started product VFX before first draw")
	sandbox.free();return finish()


func test_coalesced_refresh_flushes_rapid_vfx_results_once_without_loss()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	sandbox.grid.size=Vector2(345,345);sandbox._refresh()
	var hero:Vector2i=session.sim.world.entities[
		session.sim.world.party_encounter.protagonist_id].position
	var target:=hero+Vector2i.RIGHT
	var first:=_synthetic_melee_result(9901,hero,target)
	var second:=_synthetic_melee_result(9902,target,hero)
	sandbox._record_result(first,true)
	sandbox._record_result(second,true)
	sandbox._request_refresh();sandbox._request_refresh()
	check_eq(sandbox._pending_visual_effect_rows.size(),2,
		"two rapid committed results remain queued while refresh requests coalesce")
	check(sandbox._refresh_pending,"coalesced refresh owns one pending callback")
	sandbox._flush_requested_refresh()
	check(not sandbox._refresh_pending and sandbox._pending_visual_effect_rows.is_empty(),
		"one completed refresh drains the full pending result queue")
	check(sandbox.grid.melee_vfx!=null \
		and sandbox.grid.melee_vfx.active_effect_count()==2,
		"rapid melee effects both begin after the same coalesced refresh")
	check(sandbox.grid.has_played_effect("9901:melee_vfx") \
		and sandbox.grid.has_played_effect("9902:melee_vfx"),
		"each queued effect id is consumed exactly once")
	sandbox._flush_requested_refresh()
	check_eq(sandbox.grid.melee_vfx.active_effect_count(),2,
		"an obsolete deferred callback cannot replay the drained queue")
	sandbox.free();return finish()


func _first_exploration_step_toward(session,hero_id:int,target:Vector2i)->Vector2i:
	var hero:Vector2i=session.sim.world.entities[hero_id].position
	for direction:Vector2i in _toward_directions(hero,target):
		var destination:=hero+direction
		if bool(session.preview_exploration(Command.move_to(hero_id,destination)).accepted):
			return destination
	return Vector2i(-1,-1)


func _first_combat_step_toward(session,hero_id:int,target:Vector2i)->Vector2i:
	var hero:Vector2i=session.sim.world.entities[hero_id].position
	for direction:Vector2i in _toward_directions(hero,target):
		var destination:=hero+direction
		if bool(session.preview_actor_action(hero_id,"MOVE",
				[destination.x,destination.y]).accepted):return destination
	return Vector2i(-1,-1)


func _toward_directions(from:Vector2i,to:Vector2i)->Array[Vector2i]:
	var diagonal:=Vector2i(signi(to.x-from.x),signi(to.y-from.y))
	var horizontal:=Vector2i(signi(to.x-from.x),0)
	var vertical:=Vector2i(0,signi(to.y-from.y))
	var result:Array[Vector2i]=[]
	for direction in [diagonal,horizontal,vertical]:
		if direction!=Vector2i.ZERO and direction not in result:result.append(direction)
	return result


func _screen_touch_world(sandbox,position:Vector2i)->void:
	var pixel:Vector2=sandbox.grid.world_to_pixel_center(position)
	var press:=InputEventScreenTouch.new();press.index=0;press.pressed=true;press.position=pixel
	sandbox.grid._gui_input(press)
	var release:=InputEventScreenTouch.new();release.index=0;release.pressed=false;release.position=pixel
	sandbox.grid._gui_input(release)


func _finish_product_camera_settle(sandbox)->void:
	if sandbox.grid._camera_settle.is_empty():return
	sandbox.grid._camera_settle.started_at_ms=Time.get_ticks_msec() \
		-int(sandbox.grid._camera_settle.duration_ms)-1
	sandbox.grid._process(0.0)


func _flush_product_auto_turn(sandbox)->void:
	sandbox.flush_auto_flow_for_headless_test()
	sandbox.flush_auto_flow_for_headless_test()


func _entity_distance(session,first_id:int,second_id:int)->int:
	var first:Vector2i=session.sim.world.entities[first_id].position
	var second:Vector2i=session.sim.world.entities[second_id].position
	return maxi(absi(first.x-second.x),absi(first.y-second.y))


func _effect_sequence_spec(overlay,sample_time_ms:int,sequence:int)->Dictionary:
	for spec in overlay.effect_draw_specs(sample_time_ms):
		if int(spec.sequence)==sequence:return spec
	return {}


func _complete_melee_frame(spec:Dictionary)->bool:
	return not spec.is_empty() and bool(spec.get("line_visible",false)) \
		and bool(spec.get("flash_visible",false)) and int(spec.get("particle_count",0))>=3


func _synthetic_melee_result(event_id:int,attacker:Vector2i,target:Vector2i)->Dictionary:
	return {"accepted":true,"event_ids":[],"visual_effects":[{
		"effect_id":"%d:melee_vfx"%event_id,"event_id":event_id,"order":0,
		"kind":"MELEE_VFX","attacker_grid_pos":[attacker.x,attacker.y],
		"target_grid_pos":[target.x,target.y]}]}.duplicate(true)
