extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Visitors=preload("res://playtest/dungeon_visitors_service.gd")
const Action=preload("res://sim/party_action_command.gd")
var errors:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func walk(s,target:Vector2i)->bool:
	for i in range(30):
		var hero:int=s.sim.world.party_control_actor_id()
		if s.sim.world.entities[hero].position==target:return true
		var route:Dictionary=s.sim.pathfinder.find_path(hero,target)
		if not route.get("found",false) or route.path.size()<2:return false
		if not s.commit_field_action(Action.move_to(hero,route.path[1])).get("accepted",false):return false
	return false
func run()->void:
	root.size=Vector2i(390,844)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var ui=Shell.new();ui.initialize_for_headless_test(s,false);root.add_child(ui);ui.set_process(false)
	ui.show_species_picker_for_new_run();ui._commit_species_picker("human");ui._refresh()
	for i in range(6):await process_frame
	check(s.town_life_overview().get("frontier",false),"frontier initialized")
	check(s.sim.world.party_encounter.expedition_cycle.phase=="TOWN","starts at shelter")
	check(s.town_life_overview().residents.size()==1,"only founder lives here")
	check(s.private_home_available(),"shelter management available")
	check(ui.find_child("FrontierExplore",true,false)!=null,"region navigation shown")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("/tmp/frontier-shelter.png")
	var departed:Dictionary=s.depart_town();check(departed.get("accepted",false),"forest departure "+str(departed.get("reason","")))
	var survivor:=-1
	for id in s.sim.world.entities:
		if "frontier_survivor" in s.sim.world.entities[id].tags:survivor=id;break
	check(survivor>0,"survivor placed")
	if survivor>0:
		var target:Vector2i=s.sim.world.entities[survivor].position
		var reached:=false
		for offset in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
			if walk(s,target+offset):reached=true;break
		check(reached,"reach survivor")
		var aid:Dictionary=Visitors.interact(s,{"action":"AID","entity_id":str(survivor)})
		check(aid.get("accepted",false),"share food "+str(aid.get("reason","")))
		var joined:Dictionary=Visitors.interact(s,{"action":"ACCEPT","entity_id":str(survivor)})
		check(joined.get("accepted",false),"accept rescued survivor "+str(joined.get("reason","")))
		check(survivor not in s.company_member_ids(),"not a resident before returning")
		check(walk(s,s._map_layout.entry_position),"return to entrance")
		var returned:Dictionary=s.base_return();check(returned.get("accepted",false),"return "+str(returned.get("reason","")))
		check(survivor in s.company_member_ids(),"rescued survivor becomes resident")
		check(s.town_life_overview().residents.size()==2,"two shelter residents")
		check(s.base_overview().residents.size()==2,"resident connected to existing settlement")
		check(s.depart_town().get("accepted",false),"second departure")
		check(not s.sim.world.is_independent_visitor(survivor),"reserved resident stays home on next expedition")
		check(s.base_return().get("accepted",false),"second return")
		check(s.company_member_ids().count(survivor)==1,"resident not duplicated on return")
		check(s.town_life_command({"action":"ASSIGN","entity_id":str(survivor)}).get("accepted",false),"resident can join next expedition")
		check(s.town_life_command({"action":"RESERVE","entity_id":str(survivor)}).get("accepted",false),"resident can stay at shelter")
		ui.town_facility_id="BASE";ui._refresh()
		for i in range(6):await process_frame
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("/tmp/frontier-rescued.png")
	check(s.sim.world.world_state_error().is_empty(),"full world audit")
	var restored=Session.new();var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.get("accepted",false),"reload "+str(loaded.get("reason","")))
	if loaded.get("accepted",false):check(restored.sim.snapshot()==s.sim.snapshot(),"exact campaign replay")
	ui.queue_free();await process_frame
	print("FRONTIER CAMPAIGN: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
