extends RefCounted
const Mystery=preload("res://sim/mystery_consumables.gd")
const Catalog=preload("res://sim/item_catalog_registry.gd")
const Ops=preload("res://sim/world_item_operations.gd")
static func use(session,instance_id:String,selection:Dictionary={})->Dictionary:
	var w=session.sim.world;var id:int=w.party_control_actor_id();var hero=w.entities[id]
	var preview:Dictionary=Ops.preview_use(w,id,instance_id)
	if not preview.get("accepted",false):return session._rejection_dto(str(preview.get("reason")))
	var definition_id:String=str(preview.definition_id);var d:=Catalog.definition(definition_id)
	if d.effect_kind=="UTILITY":return preload("res://playtest/consumable_utility_service.gd").use(session,instance_id,selection)
	var member=w.party_encounter.member(id);var max_energy:int=preload("res://sim/abilities/active_skill_registry.gd").MAX_ENERGY
	var amount:int=mini(int(d.effect_power),hero.max_health-hero.health if d.effect_kind=="HEAL" else max_energy-member.energy)
	if amount<=0 and Mystery.known(w,definition_id):return {"accepted":false,"reason":"resource_full","message":"이미 가득 찼습니다."}
	var rollback:Dictionary=session.sim.capture_rollback_memento(false)
	var start:int=w.events.size();var journal_size:int=session.command_journal.size()
	var consumed:Dictionary=Ops.commit_use(w,id,instance_id,hero.position,session.ITEM_ACTION_TIME_COST)
	if not consumed.get("accepted",false):return consumed
	var event=null
	if amount>0:
		if d.effect_kind=="HEAL":
			hero.health+=amount
			event=w.emit_event("health.restored",id,id,hero.position,amount,int(consumed.event_id),{"schema_version":1,"ruleset_id":"healing-potion-v1","kind":"POTION","health_after":hero.health})
		else:
			member.energy+=amount
			event=w.emit_event("item.energy_restored",id,id,hero.position,amount,int(consumed.event_id),{"schema_version":1,"energy_after":member.energy})
	var identified=w.emit_event("item.identified",id,id,hero.position,0,int(consumed.event_id),{"schema_version":1,"definition_id":definition_id})
	member=w.party_encounter.member(id);w.party_encounter.revision+=1
	session._clear_draft()
	var error:String=w.runtime_step_postcondition_error(start) if identified!=null and (amount==0 or event!=null) else "item_event_failed"
	var advanced:Dictionary=session._advance_item_action_time() if error.is_empty() else {"accepted":false}
	if not advanced.get("accepted",false):
		session._rollback_session_transaction(rollback,journal_size);return session._rejection_dto("item_time_step_failed")
	while session.command_journal.size()>journal_size:session.command_journal.pop_back()
	session.command_journal.append({"kind":"item","operation":{"action":"USE","instance_id":instance_id,"slot":""}})
	session._deployment_plan.clear();session._invalidate_explored_presentation_cache()
	var message:String=Mystery.label(w,definition_id)+" · "+("HP" if d.effect_kind=="HEAL" else "MP")+" +%d"%amount
	var effects:Array=advanced.get("visual_effects",[]).duplicate()
	if event!=null:effects.append(session._visual_effect_row(event,"FLOATING_AMOUNT","heal",0,"healing",amount,"+%d"%amount))
	return session._feedback_dto({"accepted":true,"reason":"ok","message":message,"time_cost":session.ITEM_ACTION_TIME_COST,
		"healed_amount":amount if d.effect_kind=="HEAL" else 0,"energy_amount":amount if d.effect_kind=="ENERGY" else 0,
		"event_ids":w.events.slice(start).map(func(e):return e.id),"inventory":session.protagonist_inventory(),"visual_effects":effects})
