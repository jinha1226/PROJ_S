extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Action=preload("res://sim/party_action_command.gd")
const Population=preload("res://sim/town_population_rules.gd")
const Minimap=preload("res://playtest/party_minimap.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func tap(button:Control,jitter:float=0):
	var p:=button.get_global_rect().get_center()
	var event=InputEventScreenTouch.new();event.index=0;event.pressed=true;event.position=p;root.push_input(event,true)
	if jitter>0:
		var drag=InputEventScreenDrag.new();drag.index=0;drag.position=p+Vector2(jitter,0);root.push_input(drag,true)
	event.pressed=false;event.position=p+Vector2(jitter,0);root.push_input(event,true)
func click(button:Control):
	var p:=button.get_global_rect().get_center()
	var motion=InputEventMouseMotion.new();motion.position=p;root.push_input(motion,true)
	var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=p
	event.pressed=true;root.push_input(event,true)
	event.pressed=false;root.push_input(event,true)
func replay(s,label:String):
	var loaded=Session.new();var result:Dictionary=loaded.load_session_json(s.save_session_json())
	check(result.accepted,label+" loads: "+str(result.get("reason","")))
	if result.accepted:check(loaded.sim.snapshot()==s.sim.snapshot(),label+" replays exactly")
func run():
	root.size=Vector2i(390,800);root.content_scale_size=root.size
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).accepted,"living bootstrap")
	var legacy_input:= "--legacy-input" in OS.get_cmdline_user_args()
	if legacy_input:check(s.reset_party(44,20260828,Session.DUO_SCENARIO_ID,{},false,"human",true,true,true,true,true,true,false),"old save input fixture")
	check(s.town_life_command({"action":"START"}).accepted,"start in town")
	check(s.depart_town().accepted,"depart alone")
	var hero:int=s.sim.world.party_control_actor_id()
	var visitors:Array=Population.locations(s.sim.world)
	var far_goals:=0
	for visitor in visitors:
		var anchor:=Vector2i(visitor.anchor[0],visitor.anchor[1])
		for goal in visitor.get("goals",[]):
			if anchor.distance_to(Vector2i(goal[0],goal[1]))>=8:far_goals+=1
	if not legacy_input:check(far_goals>0,"NPC destinations extend beyond entry patrol")
	var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(s,true);root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	ui._open_member_detail(hero,"ITEM")
	for i in range(4):await process_frame
	ui._on_item_row_selected("START_BOW_001","")
	for i in range(4):await process_frame
	tap(ui.member_item_equip_button,16)
	check(s.sim.world.item_state.inventory(hero).equipped_item("MAIN_HAND").definition_id=="WEAPON_BOW","bow touch tolerates finger jitter: "+ui.notice_text)
	ui._close_member_detail()
	check(s.commit_field_action(Action.skill_at(hero,"FIREBALL",s.sim.world.entities[hero].position+Vector2i.RIGHT)).accepted,"spend MP")
	ui._refresh()
	for i in range(4):await process_frame
	tap(ui.product_rest_button,12)
	check(ui._product_rest_active,"real rest tap starts continuous macro with jitter")
	ui.set_process(true)
	var rest_deadline:=Time.get_ticks_msec()+15000
	while ui._product_rest_active and Time.get_ticks_msec()<rest_deadline:await process_frame
	ui.set_process(false)
	check(s.sim.world.party_encounter.member(hero).energy==12,"rest restores full MP: "+ui.notice_text)
	check(not ui._product_rest_active,"rest ends at full resources")
	var card=ui.cards.find_child("MemberCard%d"%hero,true,false)
	check(card!=null and card.resource_meter_specs().size()==3,"solo portrait has three meters")
	if card!=null:
		for meter in card.resource_meter_specs():check(Rect2(Vector2.ZERO,card.size).encloses(meter.rect),"meter fits portrait")
	var rebuilds:int=ui.minimap.full_rebuild_count
	var time_before:int=s.sim.world.world_time
	for i in range(4):
		ui._toggle_map_overlay();ui._toggle_map_overlay();ui._refresh()
	check(not ui.map_overlay.visible and not ui.grid.modal_open,"map close releases modal input")
	check(not ui.map_overlay.is_processing(),"closed map has no frame loop")
	check(ui.minimap.full_rebuild_count==rebuilds,"map toggles do not rebuild compact map")
	check(s.sim.world.world_time==time_before,"map toggles never simulate turns")
	var small=Minimap.new()
	var stream:Array=[{"position":[1,1],"visibility_state":"VISIBLE","terrain_id":"floor","marker":"HERO"}]
	small.set_observation({"width":80,"height":80,"epoch":"test","static_count":1,"cells":stream,"added":stream,"visible":[[1,1]],"markers":[]})
	stream.append({"position":[2,1],"visibility_state":"MEMORY","terrain_id":"floor"})
	stream.append({"position":[3,1],"visibility_state":"VISIBLE","terrain_id":"floor"})
	# Another consumer already took the preceding producer delta.
	small.set_observation({"width":80,"height":80,"epoch":"test","static_count":3,"cells":stream,"discovery_rows":stream,"added":[stream[-1]],"visible":[[3,1]],"markers":[]})
	check(small.full_rebuild_count==1 and small.stream_state().cell_count==3,"skipped producer delta remains incremental")
	small.free()
	check(s.sim.world.world_state_error().is_empty(),"post UI world valid")
	if "--capture" in OS.get_cmdline_user_args():
		for i in range(4):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/solo-ui-v4.png")
	replay(s,"new exploration rules")
	# Approach a monster through actual moves and wait for canonical damage.
	for i in range(120):
		if s.sim.world.entities[hero].health<s.sim.world.entities[hero].max_health:break
		var world=s.sim.world;var goals:Array[Vector2i]=[]
		for id in world.party_encounter.enemy_ids:
			if not world.is_autonomous_target(id):continue
			for dir in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:goals.append(world.entities[id].position+dir)
		var path:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
		var result:Dictionary=s.commit_field_action(Action.move_to(hero,path.path[1])) \
			if path.get("found",false) and path.path.size()>1 else s.commit_exploration_direction(Vector2i.ZERO)
		if not result.accepted:print("combat fixture ",result.reason);break
	print("POTION fixture HP ",s.sim.world.entities[hero].health)
	check(s.sim.world.entities[hero].health<s.sim.world.entities[hero].max_health,"fixture takes damage")
	ui._open_member_detail(hero,"ITEM")
	for i in range(4):await process_frame
	var potion_slot=ui._find_item_row_button("START_POTION_001","")
	check(potion_slot!=null and potion_slot.is_visible_in_tree(),"potion bag slot visible")
	if potion_slot!=null:
		ui.member_detail_scroll.ensure_control_visible(potion_slot)
		for i in range(3):await process_frame
		click(potion_slot)
	for i in range(4):await process_frame
	check(ui.member_item_popover.visible and ui.member_item_use_button.is_visible_in_tree(),"real bag click opens potion use")
	var quantity:int=s.sim.world.item_state.inventory(hero).item("START_POTION_001").quantity
	click(ui.member_item_use_button)
	check(s.sim.world.item_state.inventory(hero).item("START_POTION_001").quantity==quantity-1,"potion touch consumes once: "+ui.notice_text)
	check(s.sim.world.world_state_error().is_empty(),"potion world valid: "+s.sim.world.world_state_error())
	replay(s,"potion before enemy response")
	ui.queue_free();await process_frame
	# No neutral visitors in this fixture: they could kill the test monster
	# between the potion click and the defensive wait.
	s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	s.start_new_run_with_species("human",true,true)
	hero=s.sim.world.party_control_actor_id()
	for i in range(120):
		var goals:Array[Vector2i]=[];var near:=false
		for id in s.sim.world.party_encounter.enemy_ids:
			if not s.sim.world.is_autonomous_target(id):continue
			var p:Vector2i=s.sim.world.entities[id].position
			if s.sim.world.entities[hero].position.distance_to(p)<1.5:near=true
			for dir in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:goals.append(p+dir)
		if near:break
		var path:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
		if not path.get("found",false) or path.path.size()<2:break
		if not s.commit_field_action(Action.move_to(hero,path.path[1])).accepted:break
	ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(s,true);root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	var guarded_hits:=0
	for i in range(4):
		var start:int=s.sim.world.events.size()
		tap(ui.product_wait_guard_button)
		for e in s.sim.world.events.slice(start):
			if e.type!="action.melee_attack" or e.target_id!=hero or e.data.get("outcome","")!="HIT":continue
			check(e.data.guarded and int(e.data.guard_reduction)>0,"wait guards incoming melee")
			check(e.data.final_damage==e.data.base_damage-e.data.armor_reduction-e.data.guard_reduction,"HP uses guard reduction")
			guarded_hits+=1
		if guarded_hits>0:break
	check(guarded_hits>0,"at least one guarded incoming hit")
	replay(s,"guarded combat")
	ui.queue_free();await process_frame
	var legacy=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(legacy.reset_party(44,20260828,Session.DUO_SCENARIO_ID,{},false,"human",true,true,true,true,true,true,false),"version 3 fixture")
	check(legacy.town_life_command({"action":"START"}).accepted and legacy.depart_town().accepted,"legacy living departure")
	replay(legacy,"legacy version 3")
	print("SOLO GAMEPLAY: ",failures)
	quit(0 if failures.is_empty() else 1)
