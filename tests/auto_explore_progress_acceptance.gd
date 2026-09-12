extends SceneTree
const Auto=preload("res://playtest/party_auto_explore.gd")
const Fixtures=preload("res://tests/test_party_auto_explore.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
var failures:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func run()->void:
	var planner=Auto.new(self)
	# Both corridor cells border unknown space behind opaque corners. Standing
	# on each reveals nothing: old nearest-frontier selection oscillated forever.
	var cells:Dictionary={}
	for p in [Vector2i(2,2),Vector2i(2,3)]:
		cells["%d:%d"%[p.x,p.y]]={"passable":true,"move_time_cost":100}
	var snapshot:={"cells":cells,"visible":cells,"width":6,"height":6,
		"hero_position":[2,2],"visited":{"2:2":true}}
	var first:Dictionary=planner._choose_frontier(snapshot)
	check(first.found and first.target==Vector2i(2,3),"first occluded frontier is probed")
	snapshot.hero_position=[2,3];snapshot.visited["2:3"]=true
	check(not planner._choose_frontier(snapshot).found,"exhausted boundaries cannot bounce indefinitely")
	# Retargeting must not discard an already safe route because a nearer reveal
	# edge appears on the next step.
	planner.clear();cells.clear()
	for x in range(1,8):cells["%d:2"%x]={"passable":true,"move_time_cost":100}
	planner._target=Vector2i(7,2);planner._target_kind="FRONTIER"
	planner._planned_path=[Vector2i(1,2),Vector2i(2,2),Vector2i(3,2),Vector2i(4,2),Vector2i(5,2),Vector2i(6,2),Vector2i(7,2)]
	snapshot={"cells":cells,"visible":cells,"width":10,"height":6,"hero_position":[2,2]}
	var retained:Dictionary=planner._choose_frontier(snapshot)
	check(retained.target==Vector2i(7,2) and planner.plan_builds==0,"safe target retained without search")
	cells["3:2"]["risk"]=10
	var replanned:Dictionary=planner._choose_frontier(snapshot)
	check(planner.plan_builds==1 and (not replanned.found or Vector2i(3,2) not in replanned.path),"new hazard invalidates retained route")
	var fixture=Fixtures.new();var session=Session.new(77,20260828,Session.DUO_SCENARIO_ID,"human",true)
	for id in session.sim.world.party_encounter.enemy_ids:
		var hidden:Vector2i=fixture._hidden_passable_cell(session,id)
		if hidden.x>=0:session.sim.world.entities[id].position=hidden
		session.sim.world.party_encounter.enemy_busy_rows[id]=1000000000
	check(session.field_turns_active(),"test uses real campaign engine")
	var hops:=0;var times:Array=[];var result:Dictionary={}
	var positions:Array=[]
	for i in range(80):
		if i==3:
			var corridor:Dictionary=session._auto_explore._snapshot()
			var full:Dictionary=session._auto_explore_fog_snapshot()
			for key in corridor.cells:check(corridor.cells[key]==full.cells[key],"retained route uses fresh fog-safe cell "+str(key))
		var begun:=Time.get_ticks_usec()
		result=session.start_auto_explore() if i==0 else session.continue_auto_explore()
		times.append(Time.get_ticks_usec()-begun)
		if result.advanced:
			hops+=1;positions.append(result.next_position)
		if positions.size()>=6:
			var n:=positions.size()
			check(not (positions[n-1]==positions[n-3] and positions[n-3]==positions[n-5]
				and positions[n-2]==positions[n-4] and positions[n-4]==positions[n-6]),"no three-cycle two-cell oscillation")
		if not result.running:break
	times.sort()
	check(hops>10,"real dungeon exploration makes progress")
	check(session._auto_explore.plan_builds<hops,"search count lower than hop count")
	print("AUTO PROGRESS hops=",hops," plans=",session._auto_explore.plan_builds,
		" median_us=",times[times.size()/2]," p95_us=",times[mini(times.size()-1,int(times.size()*0.95))])
	print("AUTO PROGRESS: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
