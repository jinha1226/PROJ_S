extends RefCounted
## A single party-facing bag, with existing per-actor equipment/ownership rows
## retained for save compatibility. Routing is atomic with the enclosing use.
const CAPACITY=preload("res://sim/inventory_state.gd").BACKPACK_CAPACITY
static func used_slots(w)->int:
	var count:int=0
	for id in w.party_encounter.active_party_member_ids:
		var inv=w._inventory_ref(id)
		if inv!=null:count+=inv.used_backpack_slots()
	return count

static func pickup_error(w,actor_id:int)->String:
	if w.party_encounter==null or actor_id not in w.party_encounter.active_party_member_ids:return ""
	return "inventory_backpack_full" if used_slots(w)>=CAPACITY else ""

static func owner(w,instance:String)->int:
	for id in w.party_encounter.active_party_member_ids:
		var inv=w._inventory_ref(id)
		if inv!=null and inv.item(instance)!=null and instance not in inv.equipped.values():return id
	return -1
static func route(w,instance:String,recipient:int)->Dictionary:
	if recipient not in w.party_encounter.active_party_member_ids or not w.occupies_tile(recipient):return {"accepted":false,"reason":"item_user_unavailable"}
	var source:=owner(w,instance)
	if source==-1:return {"accepted":false,"reason":"inventory_item_missing"}
	if source==recipient:return {"accepted":true}
	return load("res://sim/world_item_operations.gd").commit_transfer(w,source,recipient,instance,w.entities[source].position,0)
