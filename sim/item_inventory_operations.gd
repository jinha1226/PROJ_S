class_name ItemInventoryOperations
extends RefCounted

const InventoryScript=preload("res://sim/inventory_state.gd")
const GroundScript=preload("res://sim/ground_item_state.gd")
const ItemScript=preload("res://sim/item_instance.gd")
const RegistryScript=preload("res://sim/item_registry.gd")
const DefinitionScript=preload("res://sim/item_definition.gd")


static func preview_add(inventory,item)->Dictionary:
	return _preview_result(commit_add(inventory,item))


static func commit_add(inventory,item)->Dictionary:
	var error:=_inventory_error(inventory)
	if not error.is_empty():return _rejected(error)
	if item==null:return _rejected("invalid_inventory_item")
	error=item.validation_error()
	if not error.is_empty():return _rejected(error)
	if inventory.item(item.instance_id)!=null:return _rejected("duplicate_inventory_instance")
	var next=_clone_inventory(inventory)
	var definition=RegistryScript.definition(item.definition_id)
	var remaining:int=item.quantity
	if definition.stack_limit>1:
		for target in next.backpack:
			if target.stack_key()!=item.stack_key() or target.quantity>=definition.stack_limit:continue
			var moved:=mini(remaining,definition.stack_limit-target.quantity)
			target.quantity+=moved;remaining-=moved
			if remaining==0:break
	if remaining>0:
		if next.used_backpack_slots()>=InventoryScript.BACKPACK_CAPACITY:
			return _rejected("inventory_backpack_full")
		next.backpack.append(ItemScript.new(item.instance_id,item.definition_id,remaining,
			item.rarity,item.affix_ids))
		next._sort_backpack()
	error=next.validation_error()
	if not error.is_empty():return _rejected(error)
	return _accepted({"inventory":next,"stacked_quantity":item.quantity-remaining,
		"new_row_quantity":remaining})


static func commit_insert_instance(inventory,item)->Dictionary:
	# Cross-container movement preserves permanent item identity. Matching stacks
	# remain separate rows; merging is an explicit creation/reward concern owned
	# by commit_add(), not an implicit side effect of pickup, transfer or loot.
	var error:=_inventory_error(inventory)
	if not error.is_empty():return _rejected(error)
	if item==null:return _rejected("invalid_inventory_item")
	error=item.validation_error()
	if not error.is_empty():return _rejected(error)
	if inventory.item(item.instance_id)!=null:return _rejected("duplicate_inventory_instance")
	if inventory.used_backpack_slots()>=InventoryScript.BACKPACK_CAPACITY:
		return _rejected("inventory_backpack_full")
	var next=_clone_inventory(inventory)
	next.backpack.append(ItemScript.from_dict(item.to_dict()))
	next._sort_backpack()
	error=next.validation_error()
	if not error.is_empty():return _rejected(error)
	return _accepted({"inventory":next,"instance_id":str(item.instance_id)})


static func preview_pickup(inventory,ground,instance_id:String,actor_position:Vector2i,
		world_bounds:Rect2i)->Dictionary:
	return _preview_result(commit_pickup(inventory,ground,instance_id,actor_position,world_bounds))


static func commit_pickup(inventory,ground,instance_id:String,actor_position:Vector2i,
		world_bounds:Rect2i)->Dictionary:
	var error:=combined_state_error(inventory,ground,world_bounds)
	if not error.is_empty():return _rejected(error)
	if not world_bounds.has_point(actor_position):return _rejected("invalid_item_world_context")
	var source=ground.item(instance_id)
	if source==null:return _rejected("ground_item_missing")
	if ground.position_of(instance_id)!=actor_position:return _rejected("ground_item_not_at_actor")
	var added:=commit_insert_instance(inventory,source)
	if not bool(added.get("accepted",false)):return added
	var next_ground=_clone_ground(ground)
	for index in range(next_ground.rows.size()-1,-1,-1):
		if next_ground.rows[index].item.instance_id==instance_id:
			next_ground.rows.remove_at(index);break
	return _accepted({"inventory":added.inventory,"ground":next_ground,
		"instance_id":instance_id})


static func preview_drop(inventory,ground,instance_id:String,actor_position:Vector2i,
		world_bounds:Rect2i)->Dictionary:
	return _preview_result(commit_drop(inventory,ground,instance_id,actor_position,world_bounds))


static func commit_drop(inventory,ground,instance_id:String,actor_position:Vector2i,
		world_bounds:Rect2i)->Dictionary:
	var error:=combined_state_error(inventory,ground,world_bounds)
	if not error.is_empty():return _rejected(error)
	if not world_bounds.has_point(actor_position):return _rejected("invalid_item_world_context")
	var source=inventory.item(instance_id)
	if source==null:return _rejected("inventory_item_missing")
	if instance_id in inventory.equipped.values():return _rejected("equipped_item_locked")
	if ground.item(instance_id)!=null:return _rejected("duplicate_ground_item_instance")
	var next_inventory=_clone_inventory(inventory)
	_remove_backpack_item(next_inventory,instance_id)
	var next_ground=_clone_ground(ground)
	next_ground.rows.append({"position":actor_position,"item":ItemScript.from_dict(source.to_dict())})
	next_ground._sort_rows()
	return _accepted({"inventory":next_inventory,"ground":next_ground,
		"instance_id":instance_id})


static func preview_equip(inventory,instance_id:String,slot:String)->Dictionary:
	return _preview_result(commit_equip(inventory,instance_id,slot))


static func commit_equip(inventory,instance_id:String,slot:String)->Dictionary:
	var error:=_inventory_error(inventory)
	if not error.is_empty():return _rejected(error)
	if slot not in DefinitionScript.EQUIPMENT_SLOTS:return _rejected("invalid_item_equip_slot")
	var source=inventory.item(instance_id)
	if source==null:return _rejected("inventory_item_missing")
	var definition=RegistryScript.definition(source.definition_id)
	if slot not in definition.equip_slots:return _rejected("item_equipped_in_wrong_slot")
	if instance_id in inventory.equipped.values():return _rejected("item_already_equipped")
	# Replacing the item in the chosen slot is one atomic inventory operation.
	# Equipped instances remain in the ownership table, so the displaced item
	# naturally returns to the backpack without losing its permanent identity.
	var replaced_instance_id:=str(inventory.equipped[slot])
	if slot=="MAIN_HAND" and RegistryScript.is_two_handed(source.definition_id) \
			and not str(inventory.equipped.OFF_HAND).is_empty():
		return _rejected("two_handed_offhand_conflict")
	if slot=="OFF_HAND":
		var main=inventory.equipped_item("MAIN_HAND")
		if main!=null and RegistryScript.is_two_handed(main.definition_id):
			return _rejected("two_handed_offhand_conflict")
	var next=_clone_inventory(inventory);next.equipped[slot]=instance_id
	error=next.validation_error()
	if not error.is_empty():return _rejected(error)
	return _accepted({"inventory":next,"instance_id":instance_id,"slot":slot,
		"replaced_instance_id":replaced_instance_id})


static func preview_unequip(inventory,slot:String)->Dictionary:
	return _preview_result(commit_unequip(inventory,slot))


static func commit_unequip(inventory,slot:String)->Dictionary:
	var error:=_inventory_error(inventory)
	if not error.is_empty():return _rejected(error)
	if slot not in DefinitionScript.EQUIPMENT_SLOTS:return _rejected("invalid_item_equip_slot")
	var instance_id:=str(inventory.equipped[slot])
	if instance_id.is_empty():return _rejected("equipment_slot_empty")
	if inventory.used_backpack_slots()>=InventoryScript.BACKPACK_CAPACITY:
		return _rejected("inventory_backpack_full")
	var next=_clone_inventory(inventory);next.equipped[slot]=""
	return _accepted({"inventory":next,"instance_id":instance_id,"slot":slot})


static func preview_discard(inventory,instance_id:String)->Dictionary:
	return _preview_result(commit_discard(inventory,instance_id))


static func commit_discard(inventory,instance_id:String)->Dictionary:
	var error:=_inventory_error(inventory)
	if not error.is_empty():return _rejected(error)
	if inventory.item(instance_id)==null:return _rejected("inventory_item_missing")
	if instance_id in inventory.equipped.values():return _rejected("equipped_item_locked")
	var next=_clone_inventory(inventory);_remove_backpack_item(next,instance_id)
	return _accepted({"inventory":next,"instance_id":instance_id})


static func preview_use(inventory,instance_id:String)->Dictionary:
	return _preview_result(commit_use(inventory,instance_id))


static func commit_use(inventory,instance_id:String)->Dictionary:
	var error:=_inventory_error(inventory)
	if not error.is_empty():return _rejected(error)
	var source=inventory.item(instance_id)
	if source==null:return _rejected("inventory_item_missing")
	var definition=RegistryScript.definition(source.definition_id)
	if definition.category!="CONSUMABLE":return _rejected("item_not_consumable")
	if definition.use_kind=="NONE":return _rejected("item_use_unimplemented")
	# Pure inventory authority only consumes one stack unit. Gameplay owns the
	# health effect, keeping this kernel reusable and rollback-safe.
	var next=_clone_inventory(inventory)
	var target=next._item_ref(instance_id)
	if target==null:return _rejected("inventory_item_missing")
	if target.quantity>1:target.quantity-=1
	else:_remove_backpack_item(next,instance_id)
	var next_error:String=next.validation_error()
	if not next_error.is_empty():return _rejected(next_error)
	return _accepted({"inventory":next,"instance_id":instance_id,
		"definition_id":str(source.definition_id),"use_kind":str(definition.use_kind)})


static func combined_state_error(inventory,ground,world_bounds:Rect2i)->String:
	if world_bounds.position!=Vector2i.ZERO or world_bounds.size.x<=0 or world_bounds.size.y<=0:
		return "invalid_item_world_context"
	var error:=_inventory_error(inventory)
	if not error.is_empty():return error
	error=_ground_error(ground,world_bounds)
	if not error.is_empty():return error
	var ids:Dictionary={}
	for row in inventory.to_dict().backpack:ids[str(row.instance_id)]=true
	for row in ground.to_dict().rows:
		var instance_id:=str(row.item.instance_id)
		if ids.has(instance_id):return "duplicate_world_item_instance"
		ids[instance_id]=true
	return ""


static func _preview_result(commit_result:Dictionary)->Dictionary:
	var result:=commit_result.duplicate()
	if result.get("inventory")!=null:result["inventory"]=result.inventory.to_dict()
	if result.get("ground")!=null:result["ground"]=result.ground.to_dict()
	result["preview"]=true
	return result.duplicate(true)


static func _accepted(extra:Dictionary={})->Dictionary:
	var result:={"accepted":true,"reason":"ok","preview":false}
	result.merge(extra,true);return result


static func _rejected(reason:String)->Dictionary:
	return {"accepted":false,"reason":reason,"preview":false}


static func _inventory_error(inventory)->String:
	return "invalid_inventory_state" if inventory==null else inventory.validation_error()


static func _ground_error(ground,world_bounds:Rect2i=Rect2i())->String:
	if ground==null:return "invalid_ground_item_state"
	return ground.validation_error(world_bounds.size.x,world_bounds.size.y) \
		if world_bounds.size.x>0 and world_bounds.size.y>0 else ground.validation_error()


static func _clone_inventory(inventory):
	return InventoryScript.from_dict(inventory.to_dict())


static func _clone_ground(ground):
	return GroundScript.from_dict(ground.to_dict())


static func _remove_backpack_item(inventory,instance_id:String)->void:
	for index in range(inventory.backpack.size()-1,-1,-1):
		if inventory.backpack[index].instance_id==instance_id:
			inventory.backpack.remove_at(index);return
