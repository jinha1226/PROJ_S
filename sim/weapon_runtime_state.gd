class_name WeaponRuntimeState
extends RefCounted

const SCHEMA_VERSION:=1

var schema_version:=SCHEMA_VERSION
var instance_id:String
var loaded:bool


func _init(p_instance_id:String="",p_loaded:bool=false)->void:
	instance_id=p_instance_id;loaded=p_loaded


func validation_error()->String:
	if schema_version!=SCHEMA_VERSION:return "unsupported_weapon_runtime_schema"
	# Whether the referenced instance exists and may hold a load is a world-wide
	# item invariant, so `WorldItemState` owns it instead of this row.
	if instance_id.is_empty():return "invalid_weapon_runtime_instance_id"
	return ""


func to_dict()->Dictionary:
	return {"schema_version":schema_version,"instance_id":instance_id,
		"loaded":loaded}.duplicate(true)


static func from_dict(row:Dictionary):
	if not wire_error(row).is_empty():return null
	return _from_valid_dict(row)


static func _from_valid_dict(row:Dictionary):
	var value=load("res://sim/weapon_runtime_state.gd").new(str(row.instance_id),bool(row.loaded))
	value.schema_version=int(row.schema_version)
	return value


static func wire_error(row:Variant)->String:
	if not row is Dictionary:return "invalid_weapon_runtime_shape"
	var keys:Array=row.keys();keys.sort()
	if keys!=["instance_id","loaded","schema_version"]:return "invalid_weapon_runtime_keys"
	if not row.schema_version is int or int(row.schema_version)!=SCHEMA_VERSION:
		return "unsupported_weapon_runtime_schema"
	if not row.instance_id is String or not row.loaded is bool:
		return "invalid_weapon_runtime_shape"
	return _from_valid_dict(row).validation_error()
