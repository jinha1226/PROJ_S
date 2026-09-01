class_name ItemInstance
extends RefCounted

const SCHEMA_VERSION:=1
const RARITIES:=["COMMON","UNCOMMON","RARE"]
const RegistryScript=preload("res://sim/item_registry.gd")

var schema_version:=SCHEMA_VERSION
var instance_id:String
var definition_id:String
var quantity:int
var rarity:String
var affix_ids:Array[String]


func _init(p_instance_id:String="",p_definition_id:String="",p_quantity:int=1,
		p_rarity:String="COMMON",p_affix_ids:Array=[])->void:
	instance_id=p_instance_id;definition_id=p_definition_id;quantity=p_quantity
	rarity=p_rarity;affix_ids.clear()
	for affix_id in p_affix_ids:affix_ids.append(str(affix_id))


func validation_error()->String:
	if schema_version!=SCHEMA_VERSION:return "unsupported_item_instance_schema"
	if not _canonical_id(instance_id):return "invalid_item_instance_id"
	var definition=RegistryScript.definition(definition_id)
	if definition==null:return "unknown_item_definition"
	if quantity<1 or quantity>definition.stack_limit:return "invalid_item_quantity"
	if rarity not in RARITIES:return "unknown_item_rarity"
	var maximum_affixes:int=int({"COMMON":0,"UNCOMMON":1,"RARE":2}[rarity])
	if affix_ids.size()>maximum_affixes:return "too_many_item_affixes"
	var sorted:=affix_ids.duplicate();sorted.sort()
	if affix_ids!=sorted:return "noncanonical_item_affixes"
	var seen:Dictionary={}
	for affix_id in affix_ids:
		if seen.has(affix_id):return "duplicate_item_affix"
		seen[affix_id]=true
		if not RegistryScript.has_affix(affix_id):return "unknown_item_affix"
	return ""


func stack_key()->String:
	return "%s|%s|%s"%[definition_id,rarity,",".join(affix_ids)]


func to_dict()->Dictionary:
	return {"schema_version":schema_version,"instance_id":instance_id,
		"definition_id":definition_id,"quantity":quantity,"rarity":rarity,
		"affix_ids":affix_ids.duplicate()}.duplicate(true)


static func from_dict(row:Dictionary):
	if not wire_error(row).is_empty():return null
	var value=load("res://sim/item_instance.gd").new(row.instance_id,
		row.definition_id,int(row.quantity),row.rarity,row.affix_ids)
	value.schema_version=int(row.schema_version)
	return value


static func wire_error(row:Variant)->String:
	if not row is Dictionary:return "invalid_item_instance_shape"
	var keys:Array=row.keys();keys.sort()
	if keys!=["affix_ids","definition_id","instance_id","quantity","rarity","schema_version"]:
		return "invalid_item_instance_keys"
	if not _integer(row.schema_version) or int(row.schema_version)!=SCHEMA_VERSION:
		return "unsupported_item_instance_schema"
	if not row.instance_id is String or not row.definition_id is String \
			or not row.rarity is String:return "invalid_item_instance_string"
	if not _integer(row.quantity) or not row.affix_ids is Array:return "invalid_item_instance_shape"
	for affix_id in row.affix_ids:
		if not affix_id is String:return "invalid_item_affix_shape"
	var value=load("res://sim/item_instance.gd").new(row.instance_id,row.definition_id,
		int(row.quantity),row.rarity,row.affix_ids)
	value.schema_version=int(row.schema_version)
	return value.validation_error()


static func _canonical_id(value:String)->bool:
	if value.is_empty() or value.length()>64:return false
	for index in range(value.length()):
		var code:=value.unicode_at(index)
		if not (code>=48 and code<=57) and not (code>=65 and code<=90) \
				and code!=45 and code!=95:return false
	return true


static func _integer(value:Variant)->bool:
	return value is int or (value is float and value==floor(value))
