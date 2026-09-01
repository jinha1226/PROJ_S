class_name AmmoPoolState
extends RefCounted

const SCHEMA_VERSION:=1
const AMMO_KINDS:=["ARROW","BOLT"]
const MAX_AMOUNT:=2147483647

var schema_version:=SCHEMA_VERSION
var amounts:Dictionary={"ARROW":0,"BOLT":0}


func _init(p_arrows:int=0,p_bolts:int=0)->void:
	amounts={"ARROW":p_arrows,"BOLT":p_bolts}


func amount(ammo_kind:String)->int:
	return int(amounts.get(ammo_kind,0))


func validation_error()->String:
	if schema_version!=SCHEMA_VERSION:return "unsupported_ammo_pool_schema"
	var keys:Array=amounts.keys();keys.sort()
	if keys!=AMMO_KINDS:return "invalid_ammo_pool_keys"
	for ammo_kind in AMMO_KINDS:
		if amount(ammo_kind)<0 or amount(ammo_kind)>MAX_AMOUNT:return "invalid_ammo_pool_amount"
	return ""


func to_dict()->Dictionary:
	var ammo_wire:Array=[]
	for ammo_kind in AMMO_KINDS:
		ammo_wire.append({"ammo_kind":ammo_kind,"amount":amount(ammo_kind)})
	return {"schema_version":schema_version,"ammo_pools":ammo_wire}.duplicate(true)


static func from_dict(row:Dictionary):
	if not wire_error(row).is_empty():return null
	return _from_valid_dict(row)


static func _from_valid_dict(row:Dictionary):
	var value=load("res://sim/ammo_pool_state.gd").new(
		int(row.ammo_pools[0].amount),int(row.ammo_pools[1].amount))
	value.schema_version=int(row.schema_version)
	return value


static func wire_error(row:Variant)->String:
	if not row is Dictionary:return "invalid_ammo_pool_shape"
	var keys:Array=row.keys();keys.sort()
	if keys!=["ammo_pools","schema_version"]:return "invalid_ammo_pool_keys"
	if not _integer(row.schema_version) or int(row.schema_version)!=SCHEMA_VERSION:
		return "unsupported_ammo_pool_schema"
	if not row.ammo_pools is Array or row.ammo_pools.size()!=AMMO_KINDS.size():
		return "invalid_ammo_pool_shape"
	for index in range(AMMO_KINDS.size()):
		var ammo_row:Variant=row.ammo_pools[index]
		if not ammo_row is Dictionary:return "invalid_ammo_pool_row"
		var row_keys:Array=ammo_row.keys();row_keys.sort()
		if row_keys!=["ammo_kind","amount"]:return "invalid_ammo_pool_row"
		if not ammo_row.ammo_kind is String \
				or str(ammo_row.ammo_kind)!=AMMO_KINDS[index]:
			return "noncanonical_ammo_pool_order"
		if not _integer(ammo_row.amount) or int(ammo_row.amount)<0 \
				or int(ammo_row.amount)>MAX_AMOUNT:
			return "invalid_ammo_pool_amount"
	return _from_valid_dict(row).validation_error()


static func _integer(value:Variant)->bool:
	return value is int or (value is float and value==floor(value))
