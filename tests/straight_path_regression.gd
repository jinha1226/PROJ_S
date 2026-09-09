extends SceneTree

## Regression: on open ground an 8-direction shortest path must hug the
## straight start->goal line instead of walking all diagonals first (a V).

const Simulator=preload("res://sim/simulator.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("run")
func _check(value:bool,message:String)->void:
	if not value:failures.append(message);printerr("FAIL ",message)

func _drift(start:Vector2i,goal:Vector2i,cell:Vector2i)->float:
	var line:=Vector2(goal-start);var offset:=Vector2(cell-start)
	return absf(line.x*offset.y-line.y*offset.x)/maxf(1.0,line.length())

func run()->void:
	var sim=Simulator.create(24,12,7)
	var hero=sim.world.add_entity("hero","Walker",Vector2i(1,1))
	for goal in [Vector2i(21,5),Vector2i(21,9),Vector2i(12,10),Vector2i(1,10)]:
		var path:Dictionary=sim.pathfinder.find_path(hero.id,goal)
		_check(bool(path.get("found",false)),"path to %s is found"%goal)
		if not bool(path.get("found",false)):continue
		var expected_steps:int=maxi(absi(goal.x-1),absi(goal.y-1))
		_check(int(path.steps)==expected_steps,"path to %s stays shortest (%d steps, expected %d)"%[goal,int(path.steps),expected_steps])
		var worst:=0.0
		for cell in path.path:worst=maxf(worst,_drift(Vector2i(1,1),goal,cell))
		_check(worst<=1.01,"path to %s never strays more than one cell from the straight line (worst %.2f)"%[goal,worst])
	# The player's tap-to-move route goes through the session's own search, which
	# must agree with the raw pathfinder on open ground.
	var session=Session.new();var state=session.sim.world.party_encounter
	session.sim.world.entities[state.enemy_ids[0]].position=Vector2i(14,14)
	var hero_id:int=state.protagonist_id
	var start:Vector2i=session.sim.world.entities[hero_id].position
	for goal in [start+Vector2i(2,0),start+Vector2i(4,0),start+Vector2i(0,3),start+Vector2i(4,2)]:
		var raw:Dictionary=session.sim.find_path(hero_id,goal)
		var preview:Dictionary=session.preview_exploration_route(goal)
		if not bool(raw.get("found",false)) or not bool(preview.get("accepted",false)):continue
		var raw_wire:Array=[]
		for cell in raw.path:raw_wire.append([cell.x,cell.y])
		_check(preview.path==raw_wire,"session route to %s matches the straight raw path (%s vs %s)"%[goal,str(preview.path),str(raw_wire)])
		var worst:=0.0
		for cell in preview.path:worst=maxf(worst,_drift(start,goal,Vector2i(int(cell[0]),int(cell[1]))))
		_check(worst<=1.01,"session route to %s hugs the straight line (worst %.2f)"%[goal,worst])
	if failures.is_empty():print("PASS straight path");quit(0)
	else:printerr("FAIL straight path: %d failures"%failures.size());quit(1)
