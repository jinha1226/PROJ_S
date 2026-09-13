extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
var samples:Array=[]
func _init()->void:run.call_deferred()
func run()->void:
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	s.start_new_run_with_species("human",true,true)
	s.town_life_command({"action":"START","frontier":true})
	if not s.depart_town().get("accepted",false):printerr("FAIL departure");quit(1);return
	var hero:int=s.sim.world.party_control_actor_id();var start:Vector2i=s.sim.world.entities[hero].position
	var next:=Vector2i(-1,-1)
	for direction in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
		var path:Dictionary=s.sim.pathfinder.find_path(hero,start+direction)
		if path.get("found",false) and path.path.size()==2:next=start+direction;break
	if next.x<0:printerr("FAIL adjacent route");quit(1);return
	for n in range(40):
		var target:Vector2i=next if n%2==0 else start
		var begun:=Time.get_ticks_usec()
		var r:Dictionary=s.commit_field_action(Action.move_to(hero,target))
		s._auto_explore_fog_snapshot();s._party_observation_context()
		var elapsed:float=(Time.get_ticks_usec()-begun)/1000.0
		if not r.get("accepted",false):printerr("FAIL move ",r);quit(1);return
		samples.append(elapsed)
	var sorted:=samples.duplicate();sorted.sort()
	print("SETTLEMENT_TRAVEL ",JSON.stringify({"moves":samples.size(),"p50_ms":sorted[20],"p95_ms":sorted[38],"max_ms":sorted[-1],"samples_ms":samples,"full_audit":s.sim.world.world_state_error()}))
	quit()
