extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/settlement_work_rules.gd")
const Action=preload("res://sim/party_action_command.gd")
const Visitors=preload("res://playtest/dungeon_visitors_service.gd")
var errors:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func walk(s,target:Vector2i)->bool:
	for i in range(80):
		var id:int=s.sim.world.party_control_actor_id()
		if s.sim.world.entities[id].position==target:return true
		var path:Dictionary=s.sim.pathfinder.find_path(id,target)
		if not path.get("found",false) or path.path.size()<2:return false
		if not s.commit_field_action(Action.move_to(id,path.path[1])).get("accepted",false):return false
	return false
func ticks(s,count:int)->void:
	for i in range(count):
		var r:Dictionary=s.base_work({"action":"TICK"})
		if not r.get("accepted",false):check(false,"tick "+str(r));return
func replay(s,label:String)->void:
	print("REPLAY ",label)
	var loaded=Session.new()
	var json:String=s.save_session_json()
	check(not json.is_empty(),label+" save")
	var r:Dictionary=loaded.load_session_json(json)
	check(r.get("accepted",false),label+" reload "+str(r))
	if r.get("accepted",false):check(Rules.state(loaded.sim.world)==Rules.state(s.sim.world),label+" exact settlement state")
func run()->void:
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).get("accepted",false),"living run start")
	var start:Dictionary=s.town_life_command({"action":"START","frontier":true})
	check(start.get("accepted",false),"frontier start "+str(start))
	check(s.depart_town().get("accepted",false),"depart for rescue")
	var survivor:=-1
	for id in s.sim.world.entities:
		if "frontier_survivor" in s.sim.world.entities[id].tags:survivor=int(id);break
	check(survivor>=0,"survivor exists")
	if survivor<0:quit(1);return
	var target:Vector2i=s.sim.world.entities[survivor].position
	var reached:=false
	for offset in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
		if walk(s,target+offset):reached=true;break
	check(reached,"reach survivor")
	check(Visitors.interact(s,{"action":"AID","entity_id":str(survivor)}).get("accepted",false),"aid")
	check(Visitors.interact(s,{"action":"ACCEPT","entity_id":str(survivor)}).get("accepted",false),"accept")
	check(walk(s,s._map_layout.entry_position),"walk home")
	check(s.base_return().get("accepted",false),"return with resident")
	var hero:int=s.sim.world.party_encounter.protagonist_id
	check(s.company_member_ids().size()==2,"two real residents")
	var tile:=Vector2i(-1,-1)
	for y in range(16):
		for x in range(16):
			if s.base_build_assessment("CLINIC",[x,y]).get("accepted",false):tile=Vector2i(x,y);break
		if tile.x>=0:break
	check(tile.x>=0,"valid clinic footprint")
	if tile.x<0:quit(1);return
	var op:Dictionary={"action":"BUILD","type_id":"CLINIC","tile_origin":[tile.x,tile.y]}
	var initial:Dictionary=Rules.stock(s.sim.world).total
	var ordered:Dictionary=s.base_work(op);check(ordered.get("accepted",false),"clinic ordered "+str(ordered))
	check(not s.base_work(op).get("accepted",false),"duplicate blueprint rejected")
	check(not s.base_build("CLINIC",tile).get("accepted",false),"instant build cannot bypass blueprint")
	ticks(s,1)
	check(Rules.stock(s.sim.world).total==initial,"reservation does not consume material")
	replay(s,"reserved")
	var first_id:=int(ordered.get("job_id",-1))
	check(s.base_work({"action":"CANCEL","job_id":first_id}).get("accepted",false),"cancel reserved")
	check(Rules.stock(s.sim.world).available==initial,"storage reservation immediately released")
	check(not s.base_work({"action":"CANCEL","job_id":first_id}).get("accepted",false),"cancel idempotent")
	ordered=s.base_work(op);first_id=int(ordered.get("job_id",-1))
	for i in range(60):
		var job:Dictionary=Rules.state(s.sim.world).jobs[str(first_id)]
		if job.material_location=="CARRIED":break
		ticks(s,1)
	check(Rules.state(s.sim.world).jobs[str(first_id)].material_location=="CARRIED","physical pickup occurs")
	replay(s,"carried")
	check(s.base_work({"action":"CANCEL","job_id":first_id}).get("accepted",false),"cancel in flight")
	check(Rules.stock(s.sim.world).available!=initial,"no instant material refund in flight")
	ticks(s,90)
	check(Rules.stock(s.sim.world).available==initial,"return haul restores stock")
	replay(s,"returned")
	ordered=s.base_work(op);first_id=int(ordered.get("job_id",-1))
	check(s.base_work({"action":"UPGRADE","type_id":"STORAGE"}).get("accepted",false),"resource-poor upgrade queued")
	ticks(s,100)
	check(s._base_building_built("CLINIC"),"clinic completed through haul and construction")
	check(Rules.state(s.sim.world).jobs[str(first_id)].state=="COMPLETED","job completed")
	check(Rules.stock(s.sim.world).total=={"TIMBER":1,"STONE":0,"HERBS":0},"construction consumes once")
	var upgrade:Dictionary=Rules.active(Rules.state(s.sim.world))[0]
	check(upgrade.state=="BLOCKED" and upgrade.blocked_reason=="materials_missing","shortage keeps waiting job")
	var produce:Dictionary=s.base_work({"action":"PRODUCE","recipe_id":"HEALING_POTION"})
	check(produce.get("accepted",false),"finite production shortage queued")
	check(s.base_work({"action":"PRIORITY","entity_id":hero,"kind":"BUILD","priority":0}).get("accepted",false),"priority off")
	var count:int=s.command_journal.size();var tick_before:int=Rules.state(s.sim.world).tick
	check(s.depart_town().get("accepted",false),"depart with queued jobs")
	var id:int=s.sim.world.party_control_actor_id()
	check(s.commit_field_action(Action.hold(id)).get("accepted",false),"successful expedition time action")
	check(int(Rules.state(s.sim.world).tick)==tick_before+1,"one expedition action one settlement tick")
	var before_failed:=Rules.state(s.sim.world)
	s.commit_field_action(Action.move_to(-999,Vector2i(-10,-10)))
	check(Rules.state(s.sim.world)==before_failed,"failed input no tick")
	var helper=preload("res://tests/base_progression_acceptance.gd").new()
	var herbs:Dictionary={}
	var cache_rows:Array[Dictionary]=[]
	for row in s._base_cache_rows():cache_rows.append(row)
	for row in helper._safe_cache_rows(s,cache_rows):
		if row.resource_id=="HERBS":herbs=row;break
	check(not herbs.is_empty(),"accessible expedition herbs")
	if not herbs.is_empty():
		check(walk(s,Vector2i(int(herbs.position[0]),int(herbs.position[1]))),"walk to herbs")
		check(s.base_gather().get("accepted",false),"gather production materials")
		check(walk(s,s._map_layout.entry_position),"walk home with herbs")
	var final_tick:int=Rules.state(s.sim.world).tick
	check(s.base_return().get("accepted",false),"return no catch-up")
	check(int(Rules.state(s.sim.world).tick)==final_tick,"return no duplicate ticks")
	replay(s,"expedition")
	ticks(s,100)
	check(Rules.index(s.sim.world).ready.HEALING_POTION==1,"supplied production resumes and completes")
	check(s.base_work({"action":"CLAIM","recipe_id":"HEALING_POTION"}).get("accepted",false),"claim expedition-supported output")
	check(not s.base_work({"action":"CLAIM","recipe_id":"HEALING_POTION"}).get("accepted",false),"claim exactly once")
	replay(s,"claimed")
	check(s.command_journal.size()>count,"time boundary journalled")
	check(Rules.audit(Rules.state(s.sim.world),Rules.stock(s.sim.world)).is_empty(),"material and worker audit")
	check(s.sim.world.world_state_error().is_empty(),"full world audit")
	legacy_compatibility()
	print("SETTLEMENT_WORK_ACCEPTANCE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)

func legacy_compatibility()->void:
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START","frontier":true}).get("accepted",false),"legacy fixture shelter")
	var tile:=Vector2i(-1,-1)
	for y in range(16):
		for x in range(16):
			if s.base_build_assessment("CLINIC",[x,y]).get("accepted",false):tile=Vector2i(x,y);break
		if tile.x>=0:break
	check(tile.x>=0,"legacy fixture site")
	if tile.x<0:return
	var result:Dictionary=preload("res://playtest/base_work_service.gd").commit(s,{"action":"BUILD","type_id":"CLINIC","tile_origin":[tile.x,tile.y]})
	check(result.get("accepted",false),"legacy raw order retained")
	check(not preload("res://sim/base_work_rules.gd").legacy_current(s.sim.world.events).is_empty(),"old schema job exists")
	replay(s,"legacy pending")
	for i in range(50):
		if preload("res://sim/base_work_rules.gd").legacy_current(s.sim.world.events).is_empty():break
		check(s.base_work({"action":"TICK"}).get("accepted",false),"legacy job can finish")
	check(s._base_building_built("CLINIC"),"legacy completion kept")
	check(not bool(Rules.state(s.sim.world).enabled),"legacy ticks do not enable new schema")
	check(s.base_work({"action":"PRODUCE","recipe_id":"HEALING_POTION"}).get("accepted",false),"new orders enable after legacy completion")
	replay(s,"legacy to new schema")
