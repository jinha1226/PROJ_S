extends RefCounted
const Ops=preload("res://sim/world_item_operations.gd")
const Catalog=preload("res://sim/item_catalog_registry.gd")
const Mystery=preload("res://sim/mystery_consumables.gd")
const Host=preload("res://sim/round_item_slot_host.gd")

static func wire_error(operation:Variant)->String:
	if not operation is Dictionary:return "round_item_shape"
	if operation.is_empty():return ""
	var keys:Array=operation.keys();keys.sort()
	if keys!=["action","instance_id","selection","slot"] or operation.action not in ["USE","PICKUP","EQUIP","UNEQUIP","DROP","DISCARD"] or not operation.instance_id is String or not operation.slot is String or not preload("res://playtest/consumable_utility_service.gd").selection_valid(operation.selection):return "round_item_wire"
	return ""

static func assess(w,id:int,operation:Dictionary)->Dictionary:
	if not wire_error(operation).is_empty():return {"accepted":false,"reason":"round_item_wire"}
	if id not in w.party_encounter.active_party_member_ids:return {"accepted":false,"reason":"round_item_actor"}
	var pos:Vector2i=w.entities[id].position
	match operation.action:
		"USE":
			var owner:int=preload("res://sim/party_bag_rules.gd").owner(w,operation.instance_id)
			return Ops.preview_use(w,owner,operation.instance_id)
		"PICKUP":return Ops.preview_pickup(w,id,operation.instance_id,pos)
		"EQUIP":return Ops._preview(Ops._plan_equip(w,id,operation.instance_id,operation.slot,preload("res://sim/party_bag_rules.gd").owner(w,operation.instance_id)))
		"UNEQUIP":return Ops.preview_unequip(w,id,operation.slot)
		"DROP":return Ops.preview_drop(w,preload("res://sim/party_bag_rules.gd").owner(w,operation.instance_id),operation.instance_id,pos)
		"DISCARD":return Ops.preview_discard(w,preload("res://sim/party_bag_rules.gd").owner(w,operation.instance_id),operation.instance_id)
	return {"accepted":false,"reason":"round_item_unknown"}

static func commit(sim,id:int,operation:Dictionary)->Dictionary:
	var w=sim.world;var preview:=assess(w,id,operation)
	if not preview.get("accepted",false):return preview
	var pos:Vector2i=w.entities[id].position
	if operation.action in ["EQUIP","DROP","DISCARD"]:
		var routed:Dictionary=preload("res://sim/party_bag_rules.gd").route(w,operation.instance_id,id)
		if not routed.get("accepted",false):return routed
	match operation.action:
		"PICKUP":return Ops.commit_pickup(w,id,operation.instance_id,pos,100)
		"EQUIP":return Ops.commit_equip(w,id,operation.instance_id,operation.slot,pos,100)
		"UNEQUIP":return Ops.commit_unequip(w,id,operation.slot,pos,100)
		"DROP":return Ops.commit_drop(w,id,operation.instance_id,pos,100)
		"DISCARD":return Ops.commit_discard(w,id,operation.instance_id,pos,100)
		"USE":
			var definition_id:String=preview.definition_id
			var routed:Dictionary=preload("res://sim/party_bag_rules.gd").route(w,operation.instance_id,id)
			if not routed.get("accepted",false):return routed
			if Mystery.has(definition_id):return preload("res://playtest/mystery_item_service.gd").use(Host.new(sim,id),operation.instance_id,operation.selection)
			var power:=Catalog.healing_amount(definition_id)
			if power<=0:return {"accepted":false,"reason":"item_use_unimplemented"}
			var actor=w.entities[id];var amount:=mini(power,actor.max_health-actor.health)
			if amount<=0:return {"accepted":false,"reason":"resource_full"}
			var consumed:=Ops.commit_use(w,id,operation.instance_id,pos,100)
			if not consumed.get("accepted",false):return consumed
			actor.health+=amount
			var event=w.emit_event("health.restored",id,id,pos,amount,int(consumed.event_id),
				{"schema_version":1,"ruleset_id":"healing-potion-v1","kind":"POTION","health_after":actor.health})
			w.party_encounter.revision+=1
			return {"accepted":event!=null,"reason":"ok"}
	return {"accepted":false,"reason":"round_item_unknown"}
