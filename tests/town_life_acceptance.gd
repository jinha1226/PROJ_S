extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/town_life_rules.gd")
const TownPanel=preload("res://playtest/town_life_panel.gd")
const Visitors=preload("res://playtest/dungeon_visitors_service.gd")
const Population=preload("res://sim/town_population_rules.gd")
const Command=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)

func replay(session,label:String)->void:
	var saved:String=session.save_session_json()
	check(not saved.is_empty(),label+" saves")
	var loaded=Session.new()
	var result:Dictionary=loaded.load_session_json(saved)
	check(result.get("accepted",false),label+" replays: "+str(result.get("reason")))
	if result.get("accepted",false):
		check(loaded.sim.snapshot()==session.sim.snapshot(),label+" exact world")
		check(loaded.town_life_overview()==session.town_life_overview(),label+" exact town observer")

func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(not session.town_life_enabled(),"old DUO fixtures keep their campaign")
	var start:Dictionary=session.town_life_command({"action":"START"})
	print("START ",start)
	check(start.get("accepted",false),"start town life")
	if not start.get("accepted",false):quit(1);return
	var world=session.sim.world;var party=world.party_encounter
	check(party.active_party_member_ids.size()==1,"solo start")
	check(party.expedition_cycle.phase=="TOWN","start in inn")
	check(session.town_gold()==120,"no bootstrap return stipend")
	check(not session.private_home_available(),"no private home yet")
	check(not session.base_work({"action":"UPGRADE","type_id":"STORAGE"}).get("accepted",false),"cannot upgrade public warehouse")
	check(not session.base_build("CLINIC",Vector2i(1,8)).get("accepted",false),"cannot build before acquisition")
	check(not session.town_market_stock().is_empty(),"public market open before building")
	check(session.town_service_available("CLINIC"),"public clinic open")
	check(session.town_life_overview().residents.size()==16,"sixteen persistent humans inhabit town")
	var occupied:Array=[]
	for resident in session.town_life_overview().residents:
		check(resident.tile not in occupied,"town residents have distinct visible locations")
		occupied.append(resident.tile)
	var ids:Array=party.party_member_ids.duplicate()
	var companion:=-1
	for id in ids:
		check(world.entities[id].species_id=="human","human-only townspeople")
		if world.entities[id].display_name=="나래":companion=int(id)
	var talk:={"action":"TALK","entity_id":str(companion)}
	check(session.town_life_command(talk).get("accepted",false),"meet first companion")
	check(not session.town_life_command(talk).get("accepted",false),"no same-visit chat farming")
	check(not session.town_life_command({"action":"JOIN","entity_id":str(companion)}).get("accepted",false),"first expedition remains solo")
	check(not session.recruit_companion(companion).get("accepted",false),"legacy recruit cannot bypass meeting")
	replay(session,"inn conversation")
	check(session.depart_town().get("accepted",false),"depart solo")
	check(Population.locations(world).size()==8,"eight neutral explorers distributed through the dungeon")
	var citizen:=-1
	for resident in session.town_life_overview().residents:
		if not resident.adventurer:citizen=int(resident.entity_id);break
	check(citizen>0,"public service residents have stable identities")
	check(not Visitors.interact(session,{"action":"GREET","entity_id":str(citizen)}).get("accepted",false),"cannot remotely greet townspeople from dungeon")
	replay(session,"first floor visitors")
	check(session.base_return().get("accepted",false),"empty return")
	session.town_overview()
	check(session.town_gold()==120,"empty trips yield no free gold")
	check(session.town_life_overview().completed_returns==0,"empty trips do not unlock home")
	check(party.party_member_ids==ids,"residents persist, no new random candidate batch")
	for run_index in range(2):
		check(session.depart_town().get("accepted",false),"depart salvage expedition")
		if not _gather_and_return(session):break
		session.town_overview()
		check(session.town_life_command({"action":"CLAIM"}).get("accepted",false),"claim actual expedition reward")
		check(not session.town_life_command({"action":"CLAIM"}).get("accepted",false),"no reward duplication")
		if run_index==0:
			var joined:Dictionary=session.town_life_command({"action":"JOIN","entity_id":str(companion)})
			check(joined.get("accepted",false),"first companion joins: "+str(joined))
			check(session.sim.world.party_encounter.active_party_member_ids.size()==2,"two-person field party")
			replay(session,"first companion")
	var gold:int=session.town_gold()
	var acquire:Dictionary=session.town_life_command({"action":"ACQUIRE"})
	check(acquire.get("accepted",false),"acquire home: "+str(acquire))
	check(session.town_gold()==gold-Rules.HOUSE_COST,"one purchase fee")
	check(not session.town_life_command({"action":"ACQUIRE"}).get("accepted",false),"no repeat purchase")
	check(session.private_home_available(),"private base unlocks")
	var inventory:Dictionary=session.sim.world.item_state.inventory(companion).to_dict()
	check(session.town_life_command({"action":"RESERVE","entity_id":str(companion)}).get("accepted",false),"reserve is not exile")
	check(session.sim.world.party_encounter.member(companion).presence=="RECRUITABLE","canonical detached reserve")
	check(session.town_life_command({"action":"ASSIGN","entity_id":str(companion)}).get("accepted",false),"reassign companion")
	check(session.sim.world.item_state.inventory(companion).to_dict()==inventory,"no gear loss or duplicated starter gear")
	replay(session,"house and roster")
	check(session.depart_town().get("accepted",false),"depart to meet other explorers")
	_meet_visitors(session)
	replay(session,"visitor conversations and patrols")
	var helper=preload("res://tests/base_progression_acceptance.gd").new()
	check(helper._walk_to_position(session,helper._entry_position(session)),"return path from other explorers")
	check(session.base_return().get("accepted",false),"return after meeting explorers")
	var extra:=-1
	for row in session.town_life_overview().residents:
		if not row.joined and row.can_join:extra=int(row.entity_id);break
	check(extra>0,"dungeon acquaintances become town recruitment candidates")
	if extra>0:
		check(session.town_life_command({"action":"JOIN","entity_id":str(extra)}).get("accepted",false),"third company member joins without third field fighter")
		check(session.sim.world.party_encounter.active_party_member_ids.size()==2,"company is separate from field party")
		check(session.sim.world.item_state.inventory(extra).equipped_item("MAIN_HAND")!=null,"standby recruit receives starting equipment once")
		check(not session.town_life_command({"action":"ASSIGN","entity_id":str(extra)}).get("accepted",false),"field party remains limited to two")
	replay(session,"expanded company")
	if extra>0:
		var build_tile:=Vector2i(-1,-1)
		for y in range(16):
			for x in range(16):
				if session.base_build_assessment("CLINIC",Vector2i(x,y)).get("accepted",false):build_tile=Vector2i(x,y);break
			if build_tile.x>=0:break
		check(build_tile.x>=0,"private construction becomes available after buying a home")
		if build_tile.x>=0:
			check(session.base_work({"action":"BUILD","type_id":"CLINIC","tile_origin":[build_tile.x,build_tile.y]}).get("accepted",false),"queue private clinic construction")
			check(int(preload("res://sim/base_work_rules.gd").current(session.sim.world.events).worker_id)==extra,"standby resident takes construction work first")
			check(session.base_work({"action":"TICK"}).get("accepted",false),"standby worker progresses")
			replay(session,"standby building work")
			check(session.base_work({"action":"CANCEL"}).get("accepted",false),"construction cancellation refunds resources")
	if extra>0:_controlled_reserve_rest(session,extra)
	root.size=Vector2i(360,800)
	var panel=TownPanel.new();root.add_child(panel);panel.size=Vector2(360,800)
	panel.present(session.town_life_overview());await process_frame;await process_frame
	for id in ["TownNavINN","TownNavMARKET","TownNavCLINIC","TownNavHOUSE","TownNavGATE"]:
		var button:=panel.find_child(id,true,false) as Button
		check(button!=null and button.size.y>=48,"mobile target "+id)
		if button!=null:check(button.get_global_rect().end.x<=361,"fits 360px "+id)
	panel.free()
	check(session.sim.world.world_state_error().is_empty(),"canonical final audit")
	print("TOWN_LIFE_ACCEPTANCE ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)

func _controlled_reserve_rest(source,id:int)->void:
	# Isolated unit fixture, not part of the end-to-end journal above. A newly
	# recruited standby member has no prior stress events, so start with a
	# documented strained state to exercise recovery outside the field roster.
	var session=Session.new()
	check(session.load_session_json(source.save_session_json()).get("accepted",false),"clone before controlled rest fixture")
	var member=session.sim.world.party_encounter.member(id)
	member.stress=300
	member.emotion_state.set_channel("FEAR",400,-1,-1,"SAFE_DECAY")
	member.emotion_state.updated_at=session.sim.world.world_time
	var audit:String=session.sim.world.world_state_error()
	check(audit.is_empty(),"controlled strained reserve is a valid snapshot: "+audit)
	if not audit.is_empty():return
	var gold:int=session.town_gold()
	var result:Dictionary=session.town_life_command({"action":"REST","entity_id":str(id)})
	check(result.get("accepted",false),"standby resident public rest: "+str(result))
	if result.get("accepted",false):
		check(session.town_gold()==gold-15,"public rest charged exactly once")
		check(member.stress==0,"standby stress recovers")
		check(member.emotion_state.intensity("FEAR")==100,"standby emotion recovers")
		check(session.sim.world.world_state_error().is_empty(),"standby rest emotion and morale audited")

func _meet_visitors(session)->void:
	var initial:Array=Population.locations(session.sim.world)
	var desired:Array=[]
	for row in initial:
		if bool(row.needs_supplies):desired.append(int(row.entity_id));break
	if initial.size()>1:desired.append(int(initial[1].entity_id))
	for id in desired:
		var met:=false
		for step_index in range(80):
			var assessment:Dictionary=Visitors.assess(session,id)
			if assessment.get("nearby",false):
				var action:="AID" if assessment.needs_supplies else "GREET"
				var result:Dictionary=Visitors.interact(session,{"action":action,"entity_id":str(id)})
				check(result.get("accepted",false),"meet nearby explorer: "+str(result))
				check(not Visitors.interact(session,{"action":action,"entity_id":str(id)}).get("accepted",false),"no duplicate encounter reward")
				met=bool(result.get("accepted",false));break
			var target:=Vector2i(-1,-1)
			for row in Population.locations(session.sim.world):
				if int(row.entity_id)==id:target=Vector2i(int(row.position[0]),int(row.position[1]));break
			var leader:int=session.sim.world.party_control_actor_id()
			var path:Dictionary=session.find_exploration_path(leader,target)
			if not path.get("found",false) or path.path.size()<2:break
			var moved:Dictionary=session.commit_exploration(Command.move_to(leader,path.path[1]))
			if not moved.get("accepted",false) or session.sim.world.party_encounter.safe_phase=="CONTACT":break
		check(met,"reachable neutral explorer %d"%id)
	var patrols:=0
	for event in session.sim.world.events:
		if event.type=="population.patrol":patrols+=1
	check(patrols>0,"explorers patrol on exploration time, not render frames")

func _gather_and_return(session)->bool:
	var helper=preload("res://tests/base_progression_acceptance.gd").new()
	var index:int=session.sim.world.party_encounter.expedition_cycle.expedition_index
	var rows:Array=helper._safe_cache_rows(session,helper._expected_cache_rows(session,index))
	if rows.is_empty():check(false,"reachable safe salvage");return false
	if not helper._walk_to_position(session,helper._row_position(rows[0])):
		check(false,"walk to salvage");return false
	var result:Dictionary=session.base_gather()
	check(result.get("accepted",false),"collect actual dungeon materials")
	if not helper._walk_to_position(session,helper._entry_position(session)):
		check(false,"walk home");return false
	check(session.base_return().get("accepted",false),"extract resources")
	return true
