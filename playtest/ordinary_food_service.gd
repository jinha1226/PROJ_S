extends RefCounted
const Items=preload("res://sim/world_item_operations.gd")
const Catalog=preload("res://sim/item_catalog_registry.gd")
const Rations=preload("res://sim/party_ration_rules.gd")

static func eat(session,instance_id:String)->Dictionary:
	var w=session.sim.world;var actor:int=w.party_control_actor_id()
	var food=w.inventory_of(actor).item(instance_id)
	if food==null or Catalog.family(str(food.definition_id))!="FOOD":return session._rejection_dto("item_use_unimplemented")
	if w.party_encounter.ration_milli>=Rations.ration_max_milli():return session._rejection_dto("monster_meat_full")
	for enemy_id in w.party_encounter.enemy_ids:
		if session.FieldTurns.Rules.visible(w,enemy_id):return session._rejection_dto("monster_meat_enemy_near")
	var rollback:Dictionary=session.sim.snapshot()
	var used:=Items.commit_use(w,actor,instance_id,w.entities[actor].position,0)
	if not used.get("accepted",false):return session._rejection_dto(str(used.reason))
	var before:int=w.party_encounter.ration_milli
	var nutrition:=Catalog.nutrition_milli(str(food.definition_id))
	w.party_encounter.ration_milli=mini(Rations.ration_max_milli(),before+nutrition)
	var event=w.emit_event("party.ration_eaten",actor,-1,w.entities[actor].position,0,-1,{
		"schema_version":1,"ruleset_id":Rations.RULESET_ID,"definition_id":str(food.definition_id),
		"instance_id":instance_id,"nutrition_milli":nutrition,"ration_milli":w.party_encounter.ration_milli})
	w.party_encounter.revision+=1
	if event==null or not w.world_state_error().is_empty():
		session._restore_town_rollback(rollback);return session._rejection_dto("item_operation_failed")
	session.command_journal.append({"kind":"item","operation":{"action":"USE","instance_id":instance_id,"heal_before_time":true}})
	return session._feedback_dto({"accepted":true,"reason":"ok","event_id":int(event.id),"nutrition_milli":w.party_encounter.ration_milli-before,"ordinary_food":true})
