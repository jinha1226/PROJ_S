extends RefCounted
## Read-only projection of supplies actually carried by the departing party.
static func rows(session)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var world=session.sim.world
	for definition_id in ["FOOD_RATION","POTION_HEALING"]:
		var total:=0;var owners:Array[String]=[]
		for id in world.party_encounter.active_party_member_ids:
			if world.combatant_states[id].life_state=="DEAD":continue
			var inventory=world.item_state.inventory(id)
			if inventory==null:continue
			var count:=0
			for item in inventory.backpack:
				if item.definition_id==definition_id:count+=int(item.quantity)
			if count>0:owners.append("%s %d"%[world.entities[id].display_name,count])
			total+=count
		for stock in session.town_market_stock():
			if stock.definition_id!=definition_id:continue
			var row:Dictionary=stock.duplicate(true)
			row["carried"]=total;row["owners"]=" · ".join(owners)
			result.append(row);break
	return result
