extends SceneTree
const World=preload("res://game/rebuilt/world.gd")
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func arena(w)->void:
	w.terrain.fill("floor");w.occupancy.fill(-1);w.memory.fill(1)
	w.actors.clear();w.actors.append(w.make_actor(0,w.index(Vector2i(10,10)),"hero"))
	w.occupancy[w.hero().cell]=0;w.scheduler.clear();w.lights.clear();w.rebuild_lights()
	w.navigation.fields.clear()
	w.time=0;w.sight_origin=-1;w.update_sight();w.effects.clear()
func _init()->void:
	var w=World.new()
	check(w.terrain.size()==4096 and w.actors.size()>1,"real map and roster initialize")
	arena(w)
	var start:int=w.hero().cell
	var target:int=w.index(Vector2i(11,11))
	w.terrain[w.index(Vector2i(11,10))]="wall"
	check(w.submit("MOVE",target),"one-wall diagonal allowed")
	w.move_actor(w.hero(),start)
	w.terrain[w.index(Vector2i(10,11))]="wall"
	var before:Dictionary=w.save_data()
	check(not w.submit("MOVE",target) and w.save_data()==before,"two-wall input rejected atomically")
	arena(w)
	var water:int=w.index(Vector2i(11,10));w.terrain[water]="shallow_water"
	check(w.submit("MOVE",water) and w.time==130,"water action cost")
	var builds:int=w.fov_builds
	w.submit("WAIT");w.submit("TORCH")
	check(w.fov_builds==builds,"waiting and torch do not rebuild sight")
	check(w.visible[w.index(Vector2i(17,10))]==1 and w.visible[w.index(Vector2i(17,11))]==0,"circular six-cell radius")
	arena(w)
	var enemy:Dictionary=w.make_actor(1,w.index(Vector2i(11,10)),"enemy")
	enemy.hp=1;w.actors.append(enemy);w.occupancy[enemy.cell]=1;w.scheduler.push([0,1,1])
	check(w.submit("MOVE",enemy.cell) and enemy.hp==0 and w.hero().hp==80,"immediate death no retaliation")
	check(w.occupancy[enemy.cell]==-1,"dead actor releases occupancy")
	var saved:Dictionary=w.save_data()
	var loaded=World.new(99)
	check(loaded.restore(JSON.parse_string(JSON.stringify(saved))),"JSON load")
	check(loaded.save_data()==saved,"save roundtrip exact")
	for i in range(5):
		w.submit("WAIT");loaded.submit("WAIT")
	check(w.save_data()==loaded.save_data(),"loaded continuation deterministic")
	before=loaded.save_data()
	check(not loaded.restore({"schema":1}) and loaded.save_data()==before,"invalid save does not mutate world")
	arena(w)
	for x in range(11,21):w.terrain[w.index(Vector2i(x,10))]="shallow_water"
	var times:Array[int]=[]
	for i in range(50):
		w.plan_route(w.index(Vector2i(20,10)));times.append(w.last_path_usec)
	check(not w.route_steps.is_empty() and w.route_steps[-1]==w.index(Vector2i(20,10)),"water route reaches destination")
	times.sort();print("WATER PATH us: median=",times[25]," p95=",times[47])
	arena(w)
	# Dense roster, same canonical state used by the running scene.
	for y in range(12,22):
		for x in range(12,22):
			var a:Dictionary=w.make_actor(w.actors.size(),w.index(Vector2i(x,y)),"enemy")
			w.actors.append(a);w.occupancy[a.cell]=a.id;w.scheduler.push([0,a.id,a.id])
	w.hero().hp=100000;w.hero().max_hp=100000
	times.clear()
	for i in range(30):w.submit("WAIT");times.append(w.last_action_usec)
	times.sort();print("100 ENEMY TURN us: median=",times[15]," p95=",times[28])
	arena(w);w.memory.fill(0);w.sight_origin=-1;w.update_sight();w.auto_explore=true
	var moved:=0
	for i in range(60):
		if w.auto_step():moved+=1
	check(moved>20,"auto exploration continues across frontiers")
	print("REBUILT RUNTIME: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
