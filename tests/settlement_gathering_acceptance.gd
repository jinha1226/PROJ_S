extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/settlement_work_rules.gd")
const Service=preload("res://playtest/settlement_work_service.gd")
const Local=preload("res://sim/settlement_gathering_rules.gd")
const Action=preload("res://sim/party_action_command.gd")
const Visitors=preload("res://playtest/dungeon_visitors_service.gd")
var failures:Array=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func tick(s,n:int)->void:
	for i in range(n):
		var result:Dictionary=Service.automatic_tick(s)
		if not result.get("accepted",false):check(false,"tick "+str(result));return
func replay(s,label:String)->void:
	var loaded=Session.new()
	var result:Dictionary=loaded.load_session_json(s.save_session_json())
	check(result.get("accepted",false),"replay "+label+" "+str(result))
func walk(s,target:Vector2i)->bool:
	for i in range(80):
		var id:int=s.sim.world.party_control_actor_id()
		if s.sim.world.entities[id].position==target:return true
		var path:Dictionary=s.sim.pathfinder.find_path(id,target)
		if not path.get("found",false) or path.path.size()<2:return false
		if not s.commit_field_action(Action.move_to(id,path.path[1])).get("accepted",false):return false
	return false
func run()->void:
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).get("accepted",false),"start")
	check(s.town_life_command({"action":"START","frontier":true}).get("accepted",false),"shelter")
	check(s.base_work({"action":"GATHER_POLICY","resource_id":"TIMBER","enabled":true}).get("accepted",false),"enable timber")
	for i in range(80):
		var jobs:=Rules.active(Rules.state(s.sim.world))
		if not jobs.is_empty() and int(jobs[0].get("cargo",0))==1:break
		tick(s,1)
	var jobs:=Rules.active(Rules.state(s.sim.world))
	check(not jobs.is_empty() and int(jobs[0].get("cargo",0))==1,"gathered bundle carried")
	if jobs.is_empty():quit(1);return
	check(Rules.stock(s.sim.world).total.TIMBER==4,"no stock before delivery")
	check(Local.remaining(s.sim.world,"TIMBER")==23,"site depleted exactly once")
	replay(s,"carried")
	s.base_work({"action":"GATHER_POLICY","resource_id":"TIMBER","enabled":false})
	check(s.base_work({"action":"CANCEL","job_id":jobs[0].job_id}).get("accepted",false),"cancel cargo job")
	tick(s,100)
	check(Rules.stock(s.sim.world).total.TIMBER==5,"cancelled cargo returned once")
	check(Rules.active(Rules.state(s.sim.world)).is_empty(),"disabled policy creates no replacement")
	check(Service.automatic_tick(s).get("idle",false),"idle resumes after deposit")
	replay(s,"returned")
	# Rescue a real resident using the public command paths.
	check(s.depart_town().get("accepted",false),"rescue departure")
	var survivor:=-1
	for id in s.sim.world.entities:
		if "frontier_survivor" in s.sim.world.entities[id].tags:survivor=int(id);break
	check(survivor>=0,"survivor")
	if survivor<0:quit(1);return
	var target:Vector2i=s.sim.world.entities[survivor].position
	check(walk(s,target+Vector2i.LEFT),"reach survivor")
	check(Visitors.interact(s,{"action":"AID","entity_id":str(survivor)}).get("accepted",false),"aid")
	check(Visitors.interact(s,{"action":"ACCEPT","entity_id":str(survivor)}).get("accepted",false),"accept")
	check(walk(s,s._map_layout.entry_position),"return to entrance")
	check(s.base_return().get("accepted",false),"resident returns")
	var hero:int=s.sim.world.party_encounter.protagonist_id
	s.base_work({"action":"PRIORITY","entity_id":hero,"kind":"GATHER","priority":0})
	s.base_work({"action":"GATHER_POLICY","resource_id":"HERBS","enabled":true})
	tick(s,1)
	check(s.depart_town().get("accepted",false),"leave worker at shelter")
	var initial:int=Rules.stock(s.sim.world).total.HERBS
	for i in range(50):
		var result:Dictionary=s.commit_field_action(Action.hold(hero))
		if not result.get("accepted",false):check(false,"expedition action "+str(result.get("reason","")));break
		if Rules.stock(s.sim.world).total.HERBS>initial:break
	check(Rules.stock(s.sim.world).total.HERBS>initial,"resident banks herbs during player expedition")
	check(int(Rules.state(s.sim.world).residents[str(hero)].job_id)==-1,"hero never works in two places")
	check(Local.audit(s.sim.world,Rules.state(s.sim.world)).is_empty(),"cargo conservation")
	replay(s,"resident expedition work")
	check(s.sim.world.world_state_error().is_empty(),"full audit")
	check(s.base_return().get("accepted",false),"return for finite supply test")
	s.base_work({"action":"PRIORITY","entity_id":hero,"kind":"GATHER","priority":2})
	for resource in Local.SITES:s.base_work({"action":"GATHER_POLICY","resource_id":resource,"enabled":true})
	check(s.load_session_json(s.save_session_json()).get("accepted",false),"install saved multi-resource policies")
	tick(s,5)
	replay(s,"continue after loading policies")
	for i in range(2000):
		if Local.remaining(s.sim.world,"TIMBER")+Local.remaining(s.sim.world,"STONE")+Local.remaining(s.sim.world,"HERBS")==0 and Rules.active(Rules.state(s.sim.world)).is_empty():break
		tick(s,1)
	for resource in Local.SITES:check(Local.remaining(s.sim.world,resource)==0,"finite supply exhausted "+resource)
	check(Rules.stock(s.sim.world).total=={"TIMBER":28,"STONE":20,"HERBS":14},"all harvest deposited exactly once")
	check(Local.audit(s.sim.world,Rules.state(s.sim.world)).is_empty(),"final conservation")
	check(Service.automatic_tick(s).get("idle",false),"exhausted policies stop clock")
	print("SETTLEMENT_GATHERING ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
