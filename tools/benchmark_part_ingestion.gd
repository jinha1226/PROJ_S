extends SceneTree
## Diagnostic only: compare the binding path from 2caec2d to the current path.
## Both consume the same granted part in a fresh deterministic procedural run.
## Timings cover use_party_item, not UI refresh or browser/device performance.
const Session=preload("res://playtest/party_playtest_session.gd")
class OldSession extends Session:
	func bind_ability_item(actor_id:int,instance_id:String,ingestion:bool=true)->Dictionary:
		var assessment:=ability_binding_assessment(actor_id,instance_id)
		if not bool(assessment.get("accepted",false)):return assessment
		var rollback:Variant=sim.snapshot()
		if not rollback is Dictionary:return _rejection_dto("snapshot_unavailable")
		var next=sim.world.item_state.clone()
		var removed:=InventoryOperationsScript.commit_discard(next.inventory(actor_id),instance_id)
		if not bool(removed.get("accepted",false)):
			return _rejection_dto(str(removed.get("reason","ability_binding_item_failed")))
		next.inventory_rows[actor_id]=removed.inventory
		next.revision=int(sim.world.item_state.revision)+1
		var member=sim.world.party_encounter.member(actor_id)
		member.bound_ability_ids.append(str(assessment.ability_id))
		member.bound_ability_ids.sort()
		var position:Vector2i=sim.world.entities[actor_id].position
		var event=sim.world.emit_event("party.ability_bound",actor_id,actor_id,position,1,-1,{
			"schema_version":1,"ruleset_id":AbilityBindingRulesScript.RULESET_ID,
			"ability_id":str(assessment.ability_id),"instance_id":instance_id,
			"slot_index":int(assessment.slot_index)})
		if event==null:
			_restore_town_rollback(rollback)
			return _rejection_dto("ability_binding_event_failed")
		sim.world.item_state=next
		if ingestion and _part_ingestion_enabled:
			if not preload("res://sim/part_ingestion_rules.gd").apply(sim.world,event):
				_restore_town_rollback(rollback)
				return _rejection_dto("part_ingestion_failed")
		sim.world.party_encounter.revision+=1
		var state_error:String=sim.world.world_state_error()
		if not state_error.is_empty():
			_restore_town_rollback(rollback)
			return _rejection_dto(state_error)
		command_journal.append({"kind":"ability","operation":{"action":"BIND",
			"actor_id":str(actor_id),"instance_id":instance_id,
			"ability_id":str(assessment.ability_id),"part_ingestion":ingestion and _part_ingestion_enabled}})
		return _feedback_dto({"accepted":true,"reason":"ok","event_id":int(event.id),
			"actor_id":actor_id,"instance_id":instance_id,
			"ability_id":str(assessment.ability_id),"slot_index":int(assessment.slot_index),
			"bindings":ability_binding_rows(actor_id),
			"ability_preview":AbilityBindingRulesScript.effect_preview(str(assessment.ability_id)),
			"ingestion_status":preload("res://sim/consumable_effects.gd").summary(sim.world,actor_id)})
func _init():run.call_deferred()
func run():
	for script in [OldSession,Session]:
		var s=script.new(44,1,Session.DUO_SCENARIO_ID,"human",true)
		s.start_procedural_run_with_species("human",15,13)
		var hero:int=s.sim.world.party_control_actor_id()
		var inv=s.sim.world.inventory_of(hero);var items:Array=inv.backpack.duplicate()
		items.append(preload("res://sim/item_instance.gd").new("BENCH_PART","ESSENCE_FIRE_BOLT",1))
		s.sim.world.item_state.inventory_rows[hero]=preload("res://sim/inventory_state.gd").new(items,inv.equipped)
		var start:=Time.get_ticks_usec();var result:Dictionary=s.use_party_item("BENCH_PART",hero)
		print("INGEST ","OLD" if script==OldSession else "NEW"," ms=",(Time.get_ticks_usec()-start)/1000.0," accepted=",result.accepted)
	quit()
