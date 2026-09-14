extends RefCounted
# Adapter for existing consumable effects: their canonical effects are reused,
# while time/journal belong to the enclosing round transaction.
const ITEM_ACTION_TIME_COST:=100
const Items=preload("res://sim/world_item_operations.gd")
const Mystery=preload("res://sim/mystery_consumables.gd")
var sim
var actor_id:int=-1
var command_journal:Array=[]
var _deployment_plan:Dictionary={}
func _init(p_sim,p_actor_id:int=-1):sim=p_sim;actor_id=p_actor_id
func consumable_actor_id()->int:return actor_id if actor_id!=-1 else sim.world.party_control_actor_id()
func _advance_item_action_time()->Dictionary:return {"accepted":true,"time_cost":0,"visual_effects":[]}
func _clear_draft()->void:pass
func _invalidate_explored_presentation_cache()->void:pass
func _rejection_dto(reason:String)->Dictionary:return {"accepted":false,"reason":reason}
func _feedback_dto(row:Dictionary)->Dictionary:return row
func _visual_effect_row(_event,_kind,_symbol,_delay,_channel,_amount,_text)->Dictionary:return {}
func _rollback_session_transaction(memento:Dictionary,_journal_size:int)->bool:return sim.restore_rollback_memento(memento)
func protagonist_inventory()->Dictionary:
	var rows:Array=[]
	for id in sim.world.party_encounter.active_party_member_ids:
		var inventory=sim.world.inventory_of(id)
		if inventory==null:continue
		for item in inventory.backpack:
			rows.append({"instance_id":item.instance_id,"definition_id":item.definition_id,
				"identified":Mystery.known(sim.world,item.definition_id),"label":Mystery.label(sim.world,item.definition_id)})
	return {"backpack_rows":rows}
