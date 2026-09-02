class_name ItemDefinition
extends RefCounted

const CATEGORIES:= ["WEAPON","ARMOR","CONSUMABLE","ACCESSORY","MATERIAL"]
const EQUIPMENT_SLOTS:= ["MAIN_HAND","OFF_HAND","ARMOR","ACCESSORY_1","ACCESSORY_2"]
const BONUS_KEYS:= ["armor_flat","parry_milli","dodge_milli","stealth"]

var definition_id:String
var label:String
var category:String
var stack_limit:int
var equip_slots:Array[String]
var weapon_id:String
var bonuses:Dictionary
var use_kind:String
var placeholder:bool
var requirements:Dictionary


func _init(row:Dictionary={})->void:
	definition_id=str(row.get("definition_id",""))
	label=str(row.get("label",""))
	category=str(row.get("category",""))
	stack_limit=int(row.get("stack_limit",1))
	equip_slots.clear()
	for value in row.get("equip_slots",[]):equip_slots.append(str(value))
	weapon_id=str(row.get("weapon_id",""))
	bonuses=_empty_bonuses()
	var source:Variant=row.get("bonuses",{})
	if source is Dictionary:
		for key in BONUS_KEYS:bonuses[key]=int(source.get(key,0))
	use_kind=str(row.get("use_kind","NONE"))
	placeholder=bool(row.get("placeholder",false))
	requirements={}
	var requirement_source:Variant=row.get("requirements",{})
	if requirement_source is Dictionary:
		for stat_id in ["STR","DEX","INT"]:requirements[stat_id]=int(requirement_source.get(stat_id,0))


func validation_error()->String:
	if definition_id.is_empty() or label.is_empty():return "invalid_item_definition_identity"
	if category not in CATEGORIES:return "invalid_item_category"
	if stack_limit<1 or stack_limit>999:return "invalid_item_stack_limit"
	if equip_slots.size()!=_unique_sorted(equip_slots).size():return "duplicate_item_equip_slot"
	for slot in equip_slots:
		if slot not in EQUIPMENT_SLOTS:return "invalid_item_equip_slot"
	if equip_slots!=_slots_in_canonical_order(equip_slots):return "noncanonical_item_equip_slots"
	if bonuses.keys().size()!=BONUS_KEYS.size():return "invalid_item_bonus_shape"
	for key in BONUS_KEYS:
		if not bonuses.has(key) or not _integer(bonuses[key]):return "invalid_item_bonus_shape"
		if int(bonuses[key])<-10000 or int(bonuses[key])>10000:return "invalid_item_bonus_value"
	if use_kind not in ["NONE","HEALING"]:return "unknown_item_use_kind"
	if requirements.keys().size()!=3:return "invalid_item_requirements_shape"
	for stat_id in ["STR","DEX","INT"]:
		if not requirements.has(stat_id) or not _integer(requirements[stat_id]) \
				or int(requirements[stat_id])<0 or int(requirements[stat_id])>1000:
			return "invalid_item_requirement"
	match category:
		"WEAPON":
			if stack_limit!=1 or equip_slots!=["MAIN_HAND"] or weapon_id.is_empty():
				return "invalid_weapon_item_contract"
		"ARMOR":
			if stack_limit!=1 or equip_slots.size()!=1 \
					or equip_slots[0] not in ["OFF_HAND","ARMOR"] or not weapon_id.is_empty():
				return "invalid_armor_item_contract"
		"ACCESSORY":
			if stack_limit!=1 or equip_slots!=["ACCESSORY_1","ACCESSORY_2"] \
					or not weapon_id.is_empty():return "invalid_accessory_item_contract"
		"CONSUMABLE","MATERIAL":
			if not equip_slots.is_empty() or not weapon_id.is_empty():
				return "invalid_carried_item_contract"
	if use_kind=="HEALING" and category!="CONSUMABLE":return "invalid_item_use_kind"
	return ""


func to_dict()->Dictionary:
	return {"definition_id":definition_id,"label":label,"category":category,
		"stack_limit":stack_limit,"equip_slots":equip_slots.duplicate(),
		"weapon_id":weapon_id,"bonuses":bonuses.duplicate(true),
		"use_kind":use_kind,"placeholder":placeholder,
		"requirements":requirements.duplicate(true)}.duplicate(true)


static func _empty_bonuses()->Dictionary:
	return {"armor_flat":0,"parry_milli":0,"dodge_milli":0,"stealth":0}


static func _slots_in_canonical_order(values:Array[String])->Array[String]:
	var result:Array[String]=[]
	for slot in EQUIPMENT_SLOTS:
		if slot in values:result.append(slot)
	return result


static func _unique_sorted(values:Array[String])->Array[String]:
	var seen:Dictionary={};var result:Array[String]=[]
	for value in values:
		if not seen.has(value):seen[value]=true;result.append(value)
	result.sort();return result


static func _integer(value:Variant)->bool:
	return value is int or (value is float and value==floor(value))
