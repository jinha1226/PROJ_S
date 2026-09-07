extends SceneTree
const Model=preload("res://playtest/active_combat_lab_model.gd")
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	if not value:failures.append(message)
func _init()->void:
	var model=Model.new(44)
	var source:Dictionary=model.actor(1);var target:Dictionary=model.actor(5)
	source.position=Vector2i(5,5);target.position=Vector2i(6,5)
	var old_body:Dictionary=model.body_bridge.bodies[5].to_dict()
	var plan:Dictionary=model.body_bridge.plan(source,target,"ATTACK",20,44,0)
	check(plan.accepted and model.body_bridge.bodies[5].to_dict()==old_body,"body preflight is pure")
	check(model._execute(source,"ATTACK",5,Vector2i(-1,-1)).accepted,"physical hit accepted")
	check(model.body_bridge.summary().physical_hits==1 and model.body_bridge.summary().wounds>0,"production body wound committed")
	check(model.body_bridge.bodies[5].validation_error().is_empty(),"body remains valid")
	var replay=Model.new(44);replay.actor(1).position=source.position;replay.actor(5).position=target.position
	replay._execute(replay.actor(1),"ATTACK",5,Vector2i(-1,-1))
	check(replay.body_bridge.bodies[5].to_dict()==model.body_bridge.bodies[5].to_dict(),"injury replay is deterministic")
	model.body_bridge.bodies.erase(5);source.skills=["STRIKE"]
	var hp_before:int=target.hp;var energy_before:int=source.energy
	check(not model._execute(source,"STRIKE",5,Vector2i(-1,-1)).accepted and target.hp==hp_before and source.energy==energy_before,"invalid body does not half-commit HP or energy")
	model=Model.new();source=model.actor(1);target=model.actor(5)
	source.position=Vector2i(5,5);target.position=Vector2i(6,5);target.barrier=28
	check(model._execute(source,"ATTACK",5,Vector2i(-1,-1)).accepted,"shielded hit accepted")
	check(model.body_bridge.summary().physical_hits==0 and model.body_bridge.summary().wounds==0,"full barrier prevents body injury")
	target.barrier=0
	check(model._execute(source,"FIREBOLT",5,Vector2i(-1,-1)).accepted,"fire remains playable")
	check(model.body_bridge.summary().elemental_hits==1 and model.body_bridge.bodies[5].wounds[-1].form=="FIRE","fire uses shared elemental injury")
	var body=model.body_bridge.bodies[1]
	for part in body.parts:
		if part.part_id in ["LEFT_ARM","RIGHT_ARM"]:
			part.condition="DISABLED";part.condition_source_event_id=1
			part.layers[1].integrity=0
	body.revision+=1
	check(body.validation_error().is_empty(),"disabled arm fixture valid")
	source.skills=["STRIKE","SHOVE"]
	check(not model.preview(1,"STRIKE",5).accepted,"weapon skill blocked without arms")
	check(model.basic_power(source)==16,"existing unarmed fallback power")
	check(model.body_bridge.use_error(source,"SHOVE").is_empty(),"body check remains legal")
	model.body_bridge.enabled=false
	check(model.basic_power(source)==20 and model.preview(1,"STRIKE",5).accepted,"body-off comparison restores baseline")
	for failure in failures:printerr(failure)
	print("Active body bridge: %d failures"%failures.size());quit(0 if failures.is_empty() else 1)
