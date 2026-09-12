extends SceneTree
const Core=preload("res://sim/turn_engine.gd")
var failures:Array[String]=[]
var walls:Dictionary={}
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func solid(p:Vector2i)->bool:return walls.has(p)
func step(from:Vector2i,to:Vector2i)->bool:
	return not solid(to) and Core.Geometry.open_edge(from,to,solid)
func cost(p:Vector2i)->int:return 300 if p==Vector2i(2,2) else 100
func _init()->void:
	var result:=Core.path(5,5,Vector2i(0,2),[Vector2i(4,2)],step,cost)
	check(result.found and result.total_cost==400 and Vector2i(2,2) not in result.path,"weighted route avoids expensive water")
	var repeat:=Core.path(5,5,Vector2i(0,2),[Vector2i(4,2)],step,cost)
	check(repeat==result,"deterministic equal cost tie")
	result=Core.path(5,5,Vector2i(0,2),[Vector2i(4,2),Vector2i(0,0)],step,cost)
	check(result.found and result.goal==Vector2i(0,0) and result.total_cost==200,"multi goal uses closest weighted goal")
	var risk:=func(p:Vector2i)->int:return 10 if p==Vector2i(2,2) else 1
	result=Core.risk_path(5,5,Vector2i(0,2),[Vector2i(4,2)],step,cost,risk,4)
	check(result.found and result.steps<=4 and result.max_total_risk==1,"bounded risk route avoids high exposure")
	result=Core.risk_path(5,5,Vector2i(0,2),[Vector2i(4,2)],step,cost,risk,3)
	check(not result.found,"risk route respects action budget")
	walls[Vector2i(1,0)]=true
	check(step(Vector2i.ZERO,Vector2i(1,1)),"one corner diagonal allowed")
	walls[Vector2i(0,1)]=true
	check(not step(Vector2i.ZERO,Vector2i(1,1)),"two blocked flanks forbidden")
	result=Core.path(5,5,Vector2i.ZERO,[Vector2i(4,4)],step,cost)
	check(not result.found,"enclosed start no path")
	var physical:=Core.physical(10,900,50,4,1)
	check(physical.hit_chance==850 and physical.damage==7 and physical.armor_reduction==3,"physical defense and penetration")
	check(Core.physical(1,0,9999,100).damage==1,"minimum hit damage")
	check(Core.damage_outcome(850,850)=="MISS","exact miss boundary")
	check(Core.damage_outcome(849,850,99,100)=="PARRIED","shield only after hit")
	check(Core.damage_outcome(849,850,100,100)=="HIT","exact block boundary")
	print("TURN ENGINE: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
