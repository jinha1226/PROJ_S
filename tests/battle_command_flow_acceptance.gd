extends "res://tests/battle_mobile_loot_acceptance.gd"

func _run()->void:
	var session=_new_engaged_duo()
	if session==null:quit(1);return
	root.size=Vector2i(360,640);root.content_scale_size=Vector2i(360,640)
	var ui:=Sandbox.new()
	var exploration_zoom:int=ui._product_zoom_cell_count
	ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
	await process_frame;await process_frame
	_check(ui.autonomous_battle_clock.paused,"encounter starts paused")
	_check(ui._product_zoom_cell_count<=11,"encounter zooms in")
	var world=session.sim.world;var party=world.party_encounter
	var actor_id:int=party.protagonist_id
	var origin:Vector2i=world.entities[actor_id].position
	var before:int=world.world_time
	ui._tick_autonomous_battle(1)
	_check_eq(world.world_time,before,"preparation never advances time")
	var goal:=Vector2i(-1,-1)
	for y in range(origin.y-4,origin.y+5):
		for x in range(origin.x-4,origin.x+5):
			var candidate:=Vector2i(x,y)
			if not world.in_bounds(candidate) or not ui.grid.is_world_cell_visible(candidate):continue
			var path:Dictionary=session.sim.pathfinder.find_path(actor_id,candidate)
			if not path.get("found",false) or path.path.size()<3 or path.path.size()>5:continue
			var clear:=true
			for enemy_id in session.party_status().visible_enemy_ids:
				if world.entities[enemy_id].position.distance_to(candidate)<2:clear=false
			if clear:goal=candidate;break
		if goal!=Vector2i(-1,-1):break
	_check(goal!=Vector2i(-1,-1),"visible movement destination exists")
	if goal==Vector2i(-1,-1):quit(1);return
	var start:Vector2=ui.grid.get_global_transform_with_canvas()*ui.grid.actor_visual_center(actor_id)
	var end:Vector2=ui.grid.get_global_transform_with_canvas()*ui.grid.world_to_pixel_center(goal)
	_touch(ui,0,start,true)
	var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=end
	Input.parse_input_event(drag);Input.flush_buffered_events()
	_check_eq(ui.grid.move_preview_position,goal,"map drag previews destination tile")
	_touch(ui,0,end,false)
	await process_frame;await process_frame
	_check_eq(session.individual_battle.movements.get(actor_id),goal,"drag reserves actor-specific destination")
	_check_eq(world.entities[actor_id].position,origin,"formation order never teleports")
	_check_eq(world.world_time,before,"reservation costs no world time")
	var other_id:int=party.active_party_member_ids[1]
	_check(not session.individual_battle.reserve_move(other_id,goal).get("accepted",false),
		"two party members cannot reserve the same formation tile")
	_check(not session.individual_battle.operation_error("reserve_move",{
		"actor_id":str(actor_id),"destination":[1.5,2]}).is_empty(),"fractional destinations rejected")
	var save:String=session.save_session_json()
	var loaded=Session.new()
	var restored:Dictionary=loaded.load_session_json(save)
	_check(restored.get("accepted",false),"movement journal loads: "+str(restored.get("reason","")))
	_check_eq(loaded.individual_battle.movements.get(actor_id),goal,"pending movement survives load")
	ui._on_product_execute()
	_check(not ui.autonomous_battle_clock.paused,"start releases preparation pause")
	for attempt in range(36):
		if world.entities[actor_id].position==goal:break
		var result:Dictionary=session.individual_battle.commit()
		if not result.get("accepted",false):
			_check(false,"individual move commits: "+str(result));break
	_check_eq(world.entities[actor_id].position,goal,"actor reaches assigned tile through timed steps")
	_check_eq(world.world_state_error(),"","movement uses valid canonical rules")
	save=session.save_session_json();loaded=Session.new();restored=loaded.load_session_json(save)
	_check(restored.get("accepted",false),"executed movement replays: "+str(restored.get("reason","")))
	# Boundary-only alarm probes: restore health before canonical actions/save.
	var ally_id:int=party.active_party_member_ids[1]
	var ally=world.entities[ally_id];var saved_health:int=ally.health
	ally.health=maxi(1,int(ally.max_health/4))
	_check(ui.battle_command_flow.check_danger(ui),"crossing 25 percent pauses immediately")
	ui.battle_command_flow.paint(ui)
	_check(ui.autonomous_battle_clock.paused and ally_id in ui.grid.danger_actor_ids,"endangered actor highlighted while paused")
	ui.autonomous_battle_clock.paused=false
	_check(not ui.battle_command_flow.check_danger(ui),"remaining low does not retrigger endlessly")
	_check(not ui.autonomous_battle_clock.paused,"player can resume while low")
	ally.health=ally.max_health;ui.battle_command_flow.check_danger(ui)
	ally.health=maxi(1,int(ally.max_health/4))
	_check(ui.battle_command_flow.check_danger(ui),"recovery rearms a later danger crossing")
	ally.health=saved_health
	ui._refresh_individual_battle_surface()
	await process_frame;await process_frame
	var target:int=session.party_status().visible_enemy_ids[0]
	var enemy_card:=ui.battle_enemy_strip.row.get_node("EnemyPortrait%d"%target) as Control
	await _tap_control(enemy_card,0)
	for id in party.active_party_member_ids:
		_check_eq(session.actor_command_status(id).target_id,target,"enemy tap focuses every party member")
	_check(session.individual_battle.movements.is_empty(),"focus replaces formation orders")
	await process_frame;await process_frame
	for enemy_id in session.party_status().visible_enemy_ids:
		if enemy_id==target:continue
		var center:Vector2=ui.grid.actor_visual_center(enemy_id)
		if center.x<0 or center.y<0:continue
		var pixel:Vector2=ui.grid.get_global_transform_with_canvas()*center
		_touch(ui,0,pixel,true);_touch(ui,0,pixel,false)
		await process_frame;await process_frame
		for id in party.active_party_member_ids:
			_check_eq(session.actor_command_status(id).target_id,enemy_id,"map monster tap focuses the party")
		break
	# Leaving combat restores the user's exploration zoom; no snapshot is saved
	# while this presentation-only phase probe is active.
	var phase:String=party.safe_phase;party.safe_phase="GROUPED"
	ui.battle_command_flow.sync(ui)
	_check_eq(ui._product_zoom_cell_count,exploration_zoom,"combat exit restores exploration zoom")
	party.safe_phase=phase
	ui.queue_free();await process_frame
	for failure in failures:printerr("FAIL ",failure)
	print("PASS battle command flow" if failures.is_empty() else "FAIL battle command flow")
	quit(0 if failures.is_empty() else 1)
