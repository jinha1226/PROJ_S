extends SceneTree
const Timeline=preload("res://sim/abilities/action_timeline.gd")
const Model=preload("res://playtest/active_combat_lab_model.gd")
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	if not value:failures.append(message)
func _init()->void:
	var model=Model.new()
	var clock=Timeline.new();clock.reset(model.actors)
	var hero:Dictionary=model.actor(1)
	hero.move_speed=200
	check(clock.duration(hero,"MOVE")==50 and clock.duration(hero,"FIREBOLT")==120,"movement speed does not accelerate magic")
	hero.attack_speed=200
	check(clock.duration(hero,"STRIKE")==70 and clock.duration(hero,"WAIT")==100,"attack speed and wait separated")
	var before:Dictionary=clock.ready.duplicate()
	var forecast:Array=clock.forecast(model.actors,"FIREBOLT",12)
	check(clock.now==0 and clock.ready==before,"forecast is pure")
	check(forecast[0].id==2 and forecast[0].time==100,"preview moves player behind earlier actors")
	check(forecast[8].id==1 and forecast[8].time==120,"preview includes delayed player")
	check(forecast[9].estimated,"repeat actions marked as estimates")
	model.actor(2).hp=0
	check(clock.forecast(model.actors,"FIREBOLT")[0].id==3,"dead actors removed from queue")
	model=Model.new()
	var snapshot:Dictionary=model.timeline.ready.duplicate()
	check(not model.act("ATTACK",5).accepted and model.timeline.now==0 and model.timeline.ready==snapshot,"invalid command spends no time")
	model.actor(1).attack_time=250
	check(model.act("WAIT").accepted,"first wait legal")
	# A deliberately slow attack duration can give another actor multiple slots.
	model=Model.new();model.actor(1).cast_speed=40
	check(model.act("FIREBOLT",5).accepted,"slow magic accepted")
	var count:int=0
	for entry in model.decisions:
		if int(entry.actor_id)==2:count+=1
	check(count>=2,"slow action allows multiple companion actions")
	check(not model.terminal.is_empty() or model.timeline.next_actor(model.actors)==1,"stop only at player or terminal")
	for failure in failures:printerr(failure)
	print("Action timeline: %d failures"%failures.size());quit(0 if failures.is_empty() else 1)
