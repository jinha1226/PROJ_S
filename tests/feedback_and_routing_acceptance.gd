extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func routing_parity(world):
	var expected:Dictionary={}
	for y in range(world.height):
		for x in range(world.width):
			var p:=Vector2i(x,y);var tile=world.tile_at(p)
			if tile.fire>0 or tile.wetness>0 or str(tile.terrain)=="shallow_water":expected[p]=true
	check(expected==world.explorer_hazard_positions(),"sparse hazards equal full map scan")
func run():
	root.size=Vector2i(390,800);root.content_scale_size=root.size
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	s.start_new_run_with_species("human",true,true);s.town_life_command({"action":"START"})
	var world=s.sim.world;var hero:int=world.party_control_actor_id()
	var observer:=-1
	for id in world.entities:
		if id!=hero and world.entities.has(id):observer=id;break
	check(observer>0,"relationship fixture observer")
	if observer<0:quit(1);return
	for magnitude in [10,100,100]:
		var before:int=s._affinity_toward_protagonist(observer).score
		var cause=world.emit_event("action.wait",hero)
		check(s.sim.relationships.record_aid(observer,hero,cause.id,magnitude),"record actual aid")
		var after:int=s._affinity_toward_protagonist(observer).score
		var history:Dictionary=s.combat_log()
		var latest:Dictionary=history.groups[-1].rows[-1]
		check(latest.message.contains("호감도 %+d"%(after-before)),"actual clamped score delta in log")
	var before_harm:int=s._affinity_toward_protagonist(observer).score
	var source=world.emit_event("action.wait",hero)
	s.sim.relationships.record_harm(observer,hero,source.id,20)
	var after_harm:int=s._affinity_toward_protagonist(observer).score
	check(s.combat_log().groups[-1].rows[-1].message.contains("호감도 %+d"%(after_harm-before_harm)),"negative affinity delta")
	var ui=Sandbox.new();ui.size=Vector2(390,800);ui._initialized_for_headless_test=true;root.add_child(ui);ui.initialize_for_headless_test(s,true)
	for i in range(4):await process_frame
	check(ui.event_label.text.contains("호감도"),"town displays relation log")
	check(ui.event_label.size.y>=54 and ui.event_label.max_lines_visible==3,"three visible log baselines")
	ui.queue_free();await process_frame
	# Take real damage, defeat the attacker, return to a safe place, then rest.
	s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	s.start_new_run_with_species("human",true,true)
	s.town_life_command({"action":"START"});s.depart_town()
	world=s.sim.world;hero=world.party_control_actor_id()
	var origin:Vector2i=world.entities[hero].position
	var fought:=-1
	for i in range(120):
		var goals:Array[Vector2i]=[]
		for id in world.party_encounter.enemy_ids:
			if not world.is_autonomous_target(id):continue
			if world.entities[hero].position.distance_to(world.entities[id].position)<1.5:fought=id;break
			for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:goals.append(world.entities[id].position+d)
		if fought>0:break
		var route:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
		if not route.get("found",false) or route.path.size()<2:break
		if not s.commit_field_action(Action.move_to(hero,route.path[1])).accepted:break
	for i in range(40):
		if fought<0 or not world.is_autonomous_target(fought):break
		var hit:Dictionary=s.commit_field_action(Action.melee(hero,fought))
		if not hit.accepted:print("HP FIGHT STOP ",hit);break
	for i in range(80):
		var route:Dictionary=s.sim.pathfinder.find_path(hero,origin)
		if not route.get("found",false) or route.path.size()<2:break
		var moved:Dictionary=s.commit_field_action(Action.move_to(hero,route.path[1]))
		if not moved.accepted:print("HP RETURN STOP ",moved);break
	world=s.sim.world
	check(world.entities[hero].health<world.entities[hero].max_health,"combat leaves HP to recover")
	check(world.world_state_error().is_empty(),"HP fixture canonical: "+world.world_state_error())
	var loaded=Session.new()
	var restored:Dictionary=loaded.load_session_json(s.save_session_json())
	check(restored.accepted,"independent NPC combat history loads: "+str(restored.get("reason","")))
	if restored.accepted:
		check(loaded.sim.snapshot()==s.sim.snapshot(),"independent combat replay exact")
		var potion:Dictionary=loaded.use_inventory_item("START_POTION_001")
		check(potion.accepted,"potion after independent combat: "+str(potion.get("reason","")))
	ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(s,true);root.add_child(ui)
	for i in range(4):await process_frame
	var start:int=world.world_time
	ui._on_product_rest()
	var deadline:=Time.get_ticks_msec()+30000
	while ui._product_rest_active and Time.get_ticks_msec()<deadline:await process_frame
	check(world.world_time-start>300,"HP rest continues beyond 300 time units")
	check(world.entities[hero].health==world.entities[hero].max_health,"HP rest reaches full: "+ui.notice_text)
	check(not ui._product_rest_active,"HP rest terminates")
	check(not ui.product_interact_button.text.contains("채집"),"no gather context button")
	if world.entities[hero].health==world.entities[hero].max_health:
		ui._open_member_detail(hero,"ITEM")
		for i in range(4):await process_frame
		ui._on_item_row_selected("START_POTION_001","")
		for i in range(4):await process_frame
		var quantity:int=world.item_state.inventory(hero).item("START_POTION_001").quantity
		ui._on_item_use_selected()
		check(ui.member_item_popover_compare.visible and ui.member_item_popover_compare.text.contains("가득"),"potion refusal visible inside modal")
		check(world.item_state.inventory(hero).item("START_POTION_001").quantity==quantity,"full HP potion not consumed")
	ui.queue_free();await process_frame
	routing_parity(world)
	var p:Vector2i=world.entities[hero].position+Vector2i.RIGHT
	s.sim.environment.apply_water(p,40,-1,world.step_index)
	routing_parity(world)
	for i in range(5):s.commit_exploration_direction(Vector2i.ZERO)
	routing_parity(s.sim.world)
	# Cache must not outlive one synchronous search, including direct assessments.
	var path=s.sim.pathfinder
	path.find_path(hero,p)
	check(path._occupant(p,hero,{"%d:%d"%[p.x,p.y]:999})==999,"fresh occupancy outside search")
	print("FEEDBACK ROUTING: ",failures)
	quit(0 if failures.is_empty() else 1)
