class_name InventoryState
extends RefCounted

const SCHEMA_VERSION:=1
const BACKPACK_CAPACITY:=12
const ItemScript=preload("res://sim/item_instance.gd")
const RegistryScript=preload("res://sim/item_registry.gd")
const DefinitionScript=preload("res://sim/item_definition.gd")

var schema_version:=SCHEMA_VERSION
var backpack:Array=[]
var equipped:Dictionary=_empty_equipment()


func _init(p_backpack:Array=[],p_equipped:Dictionary={})->void:
	backpack.clear()
	for value in p_backpack:
		if value is Dictionary:backpack.append(ItemScript.from_dict(value))
		elif value!=null:backpack.append(ItemScript.from_dict(value.to_dict()))
	equipped=_empty_equipment()
	for slot in DefinitionScript.EQUIPMENT_SLOTS:
		equipped[slot]=str(p_equipped.get(slot,""))
	_sort_backpack()


func item(instance_id:String):
	var value=_item_ref(instance_id)
	return ItemScript.from_dict(value.to_dict()) if value!=null else null


func _item_ref(instance_id:String):
	for value in backpack:
		if value.instance_id==instance_id:return value
	return null


func equipped_item(slot:String):
	return item(str(equipped.get(slot,"")))


func unequipped_items()->Array:
	var result:Array=[]
	var equipped_ids:Array=equipped.values()
	for value in backpack:
		if value.instance_id not in equipped_ids:result.append(ItemScript.from_dict(value.to_dict()))
	return result


func used_backpack_slots()->int:
	return unequipped_items().size()


func validation_error()->String:
	if schema_version!=SCHEMA_VERSION:return "unsupported_inventory_schema"
	# `backpack` is the canonical ownership table. Equipped instances remain in
	# that table for stable identity, but only unequipped rows occupy bag slots.
	if backpack.size()>BACKPACK_CAPACITY+DefinitionScript.EQUIPMENT_SLOTS.size() \
			or used_backpack_slots()>BACKPACK_CAPACITY:
		return "inventory_backpack_overflow"
	var previous_id:="";var ids:Dictionary={}
	for value in backpack:
		if value==null:return "invalid_inventory_item"
		var error:String=value.validation_error()
		if not error.is_empty():return error
		if ids.has(value.instance_id):return "duplicate_inventory_instance"
		if not previous_id.is_empty() and value.instance_id<previous_id:
			return "noncanonical_inventory_order"
		ids[value.instance_id]=true;previous_id=value.instance_id
	var equipped_ids:Dictionary={}
	for slot in DefinitionScript.EQUIPMENT_SLOTS:
		if not equipped.has(slot):return "invalid_inventory_equipment_slots"
		var instance_id:=str(equipped[slot])
		if instance_id.is_empty():continue
		if not ids.has(instance_id):return "equipped_item_missing"
		if equipped_ids.has(instance_id):return "item_equipped_twice"
		equipped_ids[instance_id]=true
		var definition=RegistryScript.definition(item(instance_id).definition_id)
		if definition==null or slot not in definition.equip_slots:
			return "item_equipped_in_wrong_slot"
	var main=item(str(equipped.MAIN_HAND))
	if main!=null:
		if RegistryScript.is_two_handed(main.definition_id) \
				and not str(equipped.OFF_HAND).is_empty():
			return "two_handed_offhand_conflict"
	return ""


func equipment_bonuses()->Dictionary:
	var result:={"armor_flat":0,"parry_milli":0,"dodge_milli":0,"stealth":0,
		"affix_hook_ids":[]}
	for slot in DefinitionScript.EQUIPMENT_SLOTS:
		var value=equipped_item(slot)
		if value==null:continue
		var source:=_resolved_equipment_source(slot,value)
		for key in DefinitionScript.BONUS_KEYS:
			result[key]=int(result[key])+int(source.bonuses[key])
		for hook_id in source.hook_ids:
			if str(hook_id) not in result.affix_hook_ids:result.affix_hook_ids.append(str(hook_id))
	result.affix_hook_ids.sort();return result.duplicate(true)


func combat_modifier_dto()->Dictionary:
	# This is the canonical item-to-combat handoff. It deliberately contains no
	# hit/damage formula: combat rules consume the frozen totals and may use the
	# ordered sources for explanation without reaching back into mutable inventory.
	var sources:Array=[]
	for slot in DefinitionScript.EQUIPMENT_SLOTS:
		var value=equipped_item(slot)
		if value==null:continue
		sources.append(_resolved_equipment_source(slot,value))
	return {"schema_version":1,"ruleset_id":RegistryScript.RULESET_ID,
		"sources":sources,"totals":equipment_bonuses()}.duplicate(true)


func _resolved_equipment_source(slot:String,value)->Dictionary:
	var definition=RegistryScript.definition(value.definition_id)
	if definition==null:return {}
	var bonuses:Dictionary=definition.bonuses.duplicate(true)
	var hook_ids:Array[String]=[]
	for affix_id_value in value.affix_ids:
		var affix_id:=str(affix_id_value)
		var affix:Dictionary=RegistryScript.affix(affix_id)
		for key in DefinitionScript.BONUS_KEYS:
			bonuses[key]=int(bonuses[key])+int(affix.get("bonuses",{}).get(key,0))
		for hook_id_value in affix.get("hook_ids",[]):
			var hook_id:=str(hook_id_value)
			if hook_id not in hook_ids:hook_ids.append(hook_id)
	hook_ids.sort()
	return {"slot":slot,"instance_id":str(value.instance_id),
		"definition_id":str(value.definition_id),"bonuses":bonuses.duplicate(true),
		"affix_ids":value.affix_ids.duplicate(),"hook_ids":hook_ids.duplicate()}.duplicate(true)


func to_dict()->Dictionary:
	var backpack_rows:Array=[]
	for value in backpack:backpack_rows.append(value.to_dict())
	var slot_rows:Array=[]
	for slot in DefinitionScript.EQUIPMENT_SLOTS:
		slot_rows.append({"slot":slot,"instance_id":str(equipped[slot])})
	return {"schema_version":schema_version,"backpack_capacity":BACKPACK_CAPACITY,
		"backpack":backpack_rows,"equipped_slots":slot_rows}.duplicate(true)


static func from_dict(row:Dictionary):
	if not wire_error(row).is_empty():return null
	return _from_valid_dict(row)


static func _from_valid_dict(row:Dictionary):
	var mapping:Dictionary={}
	for slot_row in row.equipped_slots:mapping[str(slot_row.slot)]=str(slot_row.instance_id)
	var value=load("res://sim/inventory_state.gd").new(row.backpack,mapping)
	value.schema_version=int(row.schema_version)
	return value


static func wire_error(row:Variant)->String:
	if not row is Dictionary:return "invalid_inventory_shape"
	var keys:Array=row.keys();keys.sort()
	if keys!=["backpack","backpack_capacity","equipped_slots","schema_version"]:
		return "invalid_inventory_keys"
	if not row.schema_version is int or int(row.schema_version)!=SCHEMA_VERSION:
		return "unsupported_inventory_schema"
	if not _integer(row.backpack_capacity) or int(row.backpack_capacity)!=BACKPACK_CAPACITY:
		return "invalid_inventory_capacity"
	if not row.backpack is Array or not row.equipped_slots is Array \
			or row.equipped_slots.size()!=DefinitionScript.EQUIPMENT_SLOTS.size():
		return "invalid_inventory_shape"
	var raw_ids:Dictionary={};var previous_id:=""
	for item_row in row.backpack:
		var error:=ItemScript.wire_error(item_row)
		if not error.is_empty():return error
		var instance_id:=str(item_row.instance_id)
		if raw_ids.has(instance_id):return "duplicate_inventory_instance"
		if not previous_id.is_empty() and instance_id<previous_id:
			return "noncanonical_inventory_order"
		raw_ids[instance_id]=true;previous_id=instance_id
	for index in range(DefinitionScript.EQUIPMENT_SLOTS.size()):
		var slot_row:Variant=row.equipped_slots[index]
		if not slot_row is Dictionary:return "invalid_inventory_slot_row"
		var slot_keys:Array=slot_row.keys();slot_keys.sort()
		if slot_keys!=["instance_id","slot"] \
				or str(slot_row.get("slot",""))!=DefinitionScript.EQUIPMENT_SLOTS[index] \
				or not slot_row.get("instance_id") is String:
			return "invalid_inventory_slot_row"
	return _from_valid_dict(row).validation_error()


func _sort_backpack()->void:
	backpack.sort_custom(func(a,b):return a.instance_id<b.instance_id)


static func _empty_equipment()->Dictionary:
	var result:Dictionary={}
	for slot in DefinitionScript.EQUIPMENT_SLOTS:result[slot]=""
	return result


static func _integer(value:Variant)->bool:
	return value is int or (value is float and value==floor(value))
