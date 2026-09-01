class_name WorldItemState
extends RefCounted

const SCHEMA_VERSION:=1
const INSTANCE_ID_FORMAT:="ITEM_%020d"
const INSTANCE_ID_DIGITS:=20
const Int64CodecScript=preload("res://sim/int64_codec.gd")
const InventoryScript=preload("res://sim/inventory_state.gd")
const AmmoPoolScript=preload("res://sim/ammo_pool_state.gd")
const WeaponRuntimeScript=preload("res://sim/weapon_runtime_state.gd")
const GroundItemScript=preload("res://sim/ground_item_state.gd")
const RegistryScript=preload("res://sim/item_registry.gd")
const WeaponRegistryScript=preload("res://sim/weapon_registry.gd")

var schema_version:=SCHEMA_VERSION
var revision:int=0
var next_item_instance_id:int=1
var inventory_rows:Dictionary={}
var ammo_pool_rows:Dictionary={}
var weapon_runtime_rows:Dictionary={}
var ground_items=GroundItemScript.new()
var processed_drop_death_event_ids:Array[int]=[]


func inventory(entity_id:int):
	return inventory_rows.get(entity_id)


func ammo_pool(entity_id:int):
	return ammo_pool_rows.get(entity_id)


func weapon_runtime(instance_id:String):
	return weapon_runtime_rows.get(instance_id)


func clone():
	return from_dict(to_dict())


static func instance_id_for(sequence:int)->String:
	return INSTANCE_ID_FORMAT%sequence


func validation_error(width:int=-1,height:int=-1)->String:
	# Invariants 1, 2 and 11 need the world entity set and death event ledger, so
	# they live in `world_membership_error()` and are never guessed here.
	# Invariants 13 and 14 belong to the operation layer, not to a resting state.
	if schema_version!=SCHEMA_VERSION:return "unsupported_world_item_schema"
	if revision<0 or next_item_instance_id<1:return "invalid_world_item_scalar"
	var definitions:Dictionary={}
	var entity_ids:Array=inventory_rows.keys();entity_ids.sort()
	for entity_id in entity_ids:
		var row=inventory_rows[entity_id]
		if not entity_id is int or entity_id<1 or row==null:return "invalid_world_item_inventory_row"
		var error:String=row.validation_error()
		if not error.is_empty():return error
		for value in row.backpack:
			if definitions.has(value.instance_id):return "duplicate_world_item_instance"
			definitions[value.instance_id]=str(value.definition_id)
	var ammo_ids:Array=ammo_pool_rows.keys();ammo_ids.sort()
	for entity_id in ammo_ids:
		var row=ammo_pool_rows[entity_id]
		if not entity_id is int or entity_id<1 or row==null:return "invalid_world_item_ammo_row"
		var error:String=row.validation_error()
		if not error.is_empty():return error
	var ground_error:String=ground_items.validation_error(width,height)
	if not ground_error.is_empty():return ground_error
	for row in ground_items.rows:
		if definitions.has(row.item.instance_id):return "duplicate_world_item_instance"
		definitions[row.item.instance_id]=str(row.item.definition_id)
	var runtime_ids:Array=weapon_runtime_rows.keys();runtime_ids.sort()
	for instance_id in runtime_ids:
		var row=weapon_runtime_rows[instance_id]
		if row==null or str(row.instance_id)!=str(instance_id):
			return "invalid_weapon_runtime_row"
		var error:String=row.validation_error()
		if not error.is_empty():return error
		if not definitions.has(instance_id):return "unknown_weapon_runtime_instance"
		var definition=RegistryScript.definition(str(definitions[instance_id]))
		if definition==null or definition.category!="WEAPON":return "weapon_runtime_not_a_weapon"
		var weapon=WeaponRegistryScript.definition(definition.weapon_id)
		if weapon==null:return "weapon_runtime_not_a_weapon"
		if not weapon.reload_required:return "weapon_runtime_reload_mismatch"
	for instance_id in definitions:
		var definition=RegistryScript.definition(str(definitions[instance_id]))
		if definition==null or definition.category!="WEAPON":continue
		var weapon=WeaponRegistryScript.definition(definition.weapon_id)
		if weapon!=null and weapon.reload_required and not weapon_runtime_rows.has(instance_id):
			return "missing_weapon_runtime_row"
	for instance_id in definitions:
		if _allocated_sequence(str(instance_id))>=next_item_instance_id:
			return "invalid_world_item_allocator"
	var previous_death_id:int=-1
	for death_event_id in processed_drop_death_event_ids:
		if death_event_id<1:return "invalid_processed_death_event"
		if death_event_id==previous_death_id:return "duplicate_processed_death_event"
		if death_event_id<previous_death_id:return "noncanonical_processed_death_event_order"
		previous_death_id=death_event_id
	return ""


func world_membership_error(combatant_entity_ids:Array,death_event_ids:Array)->String:
	# A2 seam for invariants 1, 2 and 11. The caller supplies the real world sets;
	# this state never derives or approximates them.
	var expected:Array=[]
	for entity_id in combatant_entity_ids:expected.append(int(entity_id))
	expected.sort()
	var inventory_ids:Array=inventory_rows.keys();inventory_ids.sort()
	if inventory_ids!=expected:return "inventory_row_entity_mismatch"
	var ammo_ids:Array=ammo_pool_rows.keys();ammo_ids.sort()
	if ammo_ids!=expected:return "ammo_pool_row_entity_mismatch"
	var known_deaths:Dictionary={}
	for death_event_id in death_event_ids:known_deaths[int(death_event_id)]=true
	for death_event_id in processed_drop_death_event_ids:
		if not known_deaths.has(death_event_id):return "unknown_processed_death_event"
	return ""


func to_dict()->Dictionary:
	var inventory_wire:Array=[]
	var entity_ids:Array=inventory_rows.keys();entity_ids.sort()
	for entity_id in entity_ids:
		inventory_wire.append({"entity_id":str(entity_id),
			"inventory":inventory_rows[entity_id].to_dict()})
	var ammo_wire:Array=[]
	var ammo_ids:Array=ammo_pool_rows.keys();ammo_ids.sort()
	for entity_id in ammo_ids:
		ammo_wire.append({"entity_id":str(entity_id),
			"ammo_pool":ammo_pool_rows[entity_id].to_dict()})
	var runtime_wire:Array=[]
	var runtime_ids:Array=weapon_runtime_rows.keys();runtime_ids.sort()
	for instance_id in runtime_ids:
		runtime_wire.append(weapon_runtime_rows[instance_id].to_dict())
	var death_wire:Array=[]
	for death_event_id in processed_drop_death_event_ids:death_wire.append(str(death_event_id))
	return {"schema_version":schema_version,"revision":str(revision),
		"next_item_instance_id":str(next_item_instance_id),"inventory_rows":inventory_wire,
		"ammo_pool_rows":ammo_wire,"weapon_runtime_rows":runtime_wire,
		"ground_items":ground_items.to_dict(),
		"processed_drop_death_event_ids":death_wire}.duplicate(true)


static func from_dict(row:Dictionary,width:int=-1,height:int=-1):
	if not wire_error(row,width,height).is_empty():return null
	return _from_valid_dict(row)


static func _from_valid_dict(row:Dictionary):
	var state=load("res://sim/world_item_state.gd").new()
	state.schema_version=int(row.schema_version)
	state.revision=Int64CodecScript.parse(row.revision,"world item revision")
	state.next_item_instance_id=Int64CodecScript.parse(row.next_item_instance_id,
		"next item instance ID")
	state.inventory_rows.clear()
	for inventory_row in row.inventory_rows:
		state.inventory_rows[Int64CodecScript.parse(inventory_row.entity_id,"entity ID")] \
			=InventoryScript.from_dict(inventory_row.inventory)
	state.ammo_pool_rows.clear()
	for ammo_row in row.ammo_pool_rows:
		state.ammo_pool_rows[Int64CodecScript.parse(ammo_row.entity_id,"entity ID")] \
			=AmmoPoolScript.from_dict(ammo_row.ammo_pool)
	state.weapon_runtime_rows.clear()
	for runtime_row in row.weapon_runtime_rows:
		var runtime=WeaponRuntimeScript.from_dict(runtime_row)
		state.weapon_runtime_rows[runtime.instance_id]=runtime
	state.ground_items=GroundItemScript.from_dict(row.ground_items)
	state.processed_drop_death_event_ids.clear()
	for death_event_id in row.processed_drop_death_event_ids:
		state.processed_drop_death_event_ids.append(
			Int64CodecScript.parse(death_event_id,"death event ID"))
	return state


static func wire_error(row:Variant,width:int=-1,height:int=-1)->String:
	if not row is Dictionary:return "invalid_world_item_shape"
	var keys:Array=row.keys();keys.sort()
	if keys!=["ammo_pool_rows","ground_items","inventory_rows","next_item_instance_id",
			"processed_drop_death_event_ids","revision","schema_version","weapon_runtime_rows"]:
		return "invalid_world_item_keys"
	if not row.schema_version is int or int(row.schema_version)!=SCHEMA_VERSION:
		return "unsupported_world_item_schema"
	for key in ["revision","next_item_instance_id"]:
		if not Int64CodecScript.is_canonical(row[key]):return "noncanonical_world_item_%s"%key
	if Int64CodecScript.parse(row.revision,"revision")<0 \
			or Int64CodecScript.parse(row.next_item_instance_id,"allocator")<1:
		return "invalid_world_item_scalar"
	if not row.inventory_rows is Array or not row.ammo_pool_rows is Array \
			or not row.weapon_runtime_rows is Array \
			or not row.processed_drop_death_event_ids is Array:
		return "invalid_world_item_shape"
	var inventory_error:=_entity_rows_error(row.inventory_rows,"inventory")
	if not inventory_error.is_empty():return inventory_error
	var ammo_error:=_entity_rows_error(row.ammo_pool_rows,"ammo_pool")
	if not ammo_error.is_empty():return ammo_error
	var previous_instance_id:=""
	for runtime_row in row.weapon_runtime_rows:
		var error:=WeaponRuntimeScript.wire_error(runtime_row)
		if not error.is_empty():return error
		var instance_id:=str(runtime_row.instance_id)
		if instance_id==previous_instance_id:return "duplicate_weapon_runtime_row"
		if not previous_instance_id.is_empty() and instance_id<previous_instance_id:
			return "noncanonical_weapon_runtime_order"
		previous_instance_id=instance_id
	var ground_error:=GroundItemScript.wire_error(row.ground_items,width,height)
	if not ground_error.is_empty():return ground_error
	var previous_death_id:int=-1
	for death_event_id in row.processed_drop_death_event_ids:
		if not Int64CodecScript.is_canonical(death_event_id):
			return "noncanonical_processed_death_event"
		var parsed:=Int64CodecScript.parse(death_event_id,"death event ID")
		if parsed<1:return "invalid_processed_death_event"
		if parsed==previous_death_id:return "duplicate_processed_death_event"
		if parsed<previous_death_id:return "noncanonical_processed_death_event_order"
		previous_death_id=parsed
	return _from_valid_dict(row).validation_error(width,height)


static func _entity_rows_error(rows:Array,payload_key:String)->String:
	var row_label:="inventory" if payload_key=="inventory" else "ammo"
	var previous_id:int=-1
	for entity_row in rows:
		if not entity_row is Dictionary:return "invalid_world_item_%s_row"%row_label
		var keys:Array=entity_row.keys();keys.sort()
		var expected:Array=["entity_id",payload_key];expected.sort()
		if keys!=expected:return "invalid_world_item_%s_row"%row_label
		if not Int64CodecScript.is_canonical(entity_row.entity_id):
			return "noncanonical_world_item_entity_id"
		var entity_id:=Int64CodecScript.parse(entity_row.entity_id,"entity ID")
		if entity_id<1:return "invalid_world_item_entity_id"
		if entity_id==previous_id:return "duplicate_world_item_entity_row"
		if entity_id<previous_id:return "noncanonical_world_item_entity_order"
		previous_id=entity_id
		var error:=InventoryScript.wire_error(entity_row[payload_key]) if payload_key=="inventory" \
			else AmmoPoolScript.wire_error(entity_row[payload_key])
		if not error.is_empty():return error
	return ""


static func _allocated_sequence(instance_id:String)->int:
	if not instance_id.begins_with("ITEM_") \
			or instance_id.length()!=5+INSTANCE_ID_DIGITS:
		return -1
	var digits:=instance_id.substr(5)
	for index in range(digits.length()):
		var code:=digits.unicode_at(index)
		if code<48 or code>57:return -1
	return int(digits)
