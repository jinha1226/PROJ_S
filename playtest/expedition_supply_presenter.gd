extends RefCounted
## Read-only projection of supplies actually carried by the departing party.
const TorchRules=preload("res://sim/torch_rules.gd")

static func rows(session)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var world=session.sim.world
	for definition_id in ["FOOD_RATION","POTION_HEALING",TorchRules.DEFINITION_ID]:
		var total:=0;var owners:Array[String]=[]
		for id in world.party_encounter.active_party_member_ids:
			if world.combatant_states[id].life_state=="DEAD":continue
			var inventory=world.item_state.inventory(id)
			if inventory==null:continue
			var count:=0
			for item in inventory.backpack:
				if item.definition_id==definition_id:count+=int(item.quantity)
			for slot in inventory.equipped:
				var equipped_id:=str(inventory.equipped[slot])
				if equipped_id.is_empty():continue
				var equipped=inventory._item_ref(equipped_id)
				if equipped!=null and str(equipped.definition_id)==definition_id:
					count+=int(equipped.quantity)
			if count>0:owners.append("%s %d"%[world.entities[id].display_name,count])
			total+=count
		for stock in session.town_market_stock():
			if stock.definition_id!=definition_id:continue
			var row:Dictionary=stock.duplicate(true)
			row["carried"]=total;row["owners"]=" · ".join(owners)
			row["is_torch"]=definition_id==TorchRules.DEFINITION_ID
			row["equipped"]=_equipped_torch_count(world)>0 if definition_id==TorchRules.DEFINITION_ID else false
			result.append(row);break
	return result


static func _equipped_torch_count(world)->int:
	var count:=0
	for id in world.party_encounter.active_party_member_ids:
		var inventory=world.item_state.inventory(id)
		if inventory==null:continue
		var instance_id:=str(inventory.equipped.get(TorchRules.EQUIP_SLOT,""))
		if instance_id.is_empty():continue
		var item=inventory._item_ref(instance_id)
		if item!=null and TorchRules.is_torch_item(item):count+=1
	return count
