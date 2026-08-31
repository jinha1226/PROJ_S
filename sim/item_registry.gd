class_name ItemRegistry
extends RefCounted

const RULESET_ID:="item-registry-v1"
const DefinitionScript=preload("res://sim/item_definition.gd")
const WeaponRegistryScript=preload("res://sim/weapon_registry.gd")

const DEFINITIONS:={
	"WEAPON_SHORT_SWORD":{"definition_id":"WEAPON_SHORT_SWORD","label":"단검",
		"category":"WEAPON","stack_limit":1,"equip_slots":["MAIN_HAND"],
		"weapon_id":"SHORT_SWORD","bonuses":{"armor_flat":0,
		"parry_milli":0,"dodge_milli":0,"stealth":0},"use_kind":"NONE","placeholder":false},
	"WEAPON_THRUSTING_SWORD":{"definition_id":"WEAPON_THRUSTING_SWORD","label":"찌르기검",
		"category":"WEAPON","stack_limit":1,"equip_slots":["MAIN_HAND"],
		"weapon_id":"THRUSTING_SWORD","bonuses":{"armor_flat":0,
		"parry_milli":0,"dodge_milli":0,"stealth":0},"use_kind":"NONE","placeholder":false},
	"WEAPON_HAND_AXE":{"definition_id":"WEAPON_HAND_AXE","label":"손도끼",
		"category":"WEAPON","stack_limit":1,"equip_slots":["MAIN_HAND"],
		"weapon_id":"HAND_AXE","bonuses":{"armor_flat":0,
		"parry_milli":0,"dodge_milli":0,"stealth":0},"use_kind":"NONE","placeholder":false},
	"WEAPON_MACE":{"definition_id":"WEAPON_MACE","label":"철퇴","category":"WEAPON",
		"stack_limit":1,"equip_slots":["MAIN_HAND"],"weapon_id":"MACE",
		"bonuses":{"armor_flat":0,"parry_milli":0,"dodge_milli":0,"stealth":0},
		"use_kind":"NONE","placeholder":false},
	"WEAPON_SPEAR":{"definition_id":"WEAPON_SPEAR","label":"창","category":"WEAPON",
		"stack_limit":1,"equip_slots":["MAIN_HAND"],"weapon_id":"SPEAR",
		"bonuses":{"armor_flat":0,"parry_milli":0,"dodge_milli":0,"stealth":0},
		"use_kind":"NONE","placeholder":false},
	"WEAPON_BOW":{"definition_id":"WEAPON_BOW","label":"활","category":"WEAPON",
		"stack_limit":1,"equip_slots":["MAIN_HAND"],"weapon_id":"BOW",
		"bonuses":{"armor_flat":0,"parry_milli":0,"dodge_milli":0,"stealth":0},
		"use_kind":"NONE","placeholder":false},
	"WEAPON_CROSSBOW":{"definition_id":"WEAPON_CROSSBOW","label":"쇠뇌","category":"WEAPON",
		"stack_limit":1,"equip_slots":["MAIN_HAND"],"weapon_id":"CROSSBOW",
		"bonuses":{"armor_flat":0,"parry_milli":0,"dodge_milli":0,"stealth":0},
		"use_kind":"NONE","placeholder":false},
	"ARMOR_LEATHER":{"definition_id":"ARMOR_LEATHER","label":"가죽 갑옷","category":"ARMOR",
		"stack_limit":1,"equip_slots":["ARMOR"],"weapon_id":"",
		"bonuses":{"armor_flat":1,"parry_milli":0,"dodge_milli":0,"stealth":0},
		"use_kind":"NONE","placeholder":false},
	"ARMOR_PADDED":{"definition_id":"ARMOR_PADDED","label":"누비 갑옷","category":"ARMOR",
		"stack_limit":1,"equip_slots":["ARMOR"],"weapon_id":"",
		"bonuses":{"armor_flat":1,"parry_milli":0,"dodge_milli":0,"stealth":0},
		"use_kind":"NONE","placeholder":false},
	"SHIELD_WOOD":{"definition_id":"SHIELD_WOOD","label":"나무 방패","category":"ARMOR",
		"stack_limit":1,"equip_slots":["OFF_HAND"],"weapon_id":"",
		"bonuses":{"armor_flat":0,"parry_milli":100,"dodge_milli":0,"stealth":0},
		"use_kind":"NONE","placeholder":false},
	# Their gameplay effects are intentionally unspecified. These definitions let
	# saves and UI carry the base families without inventing use authority.
	"POTION_UNSPECIFIED":{"definition_id":"POTION_UNSPECIFIED","label":"미정 물약",
		"category":"CONSUMABLE","stack_limit":10,"equip_slots":[],"weapon_id":"",
		"bonuses":{"armor_flat":0,"parry_milli":0,"dodge_milli":0,
		"stealth":0},"use_kind":"NONE","placeholder":true},
	"SCROLL_UNSPECIFIED":{"definition_id":"SCROLL_UNSPECIFIED","label":"미정 두루마리",
		"category":"CONSUMABLE","stack_limit":10,"equip_slots":[],"weapon_id":"",
		"bonuses":{"armor_flat":0,"parry_milli":0,"dodge_milli":0,
		"stealth":0},"use_kind":"NONE","placeholder":true},
	"ACCESSORY_UNSPECIFIED":{"definition_id":"ACCESSORY_UNSPECIFIED","label":"미정 장신구",
		"category":"ACCESSORY","stack_limit":1,"equip_slots":["ACCESSORY_1","ACCESSORY_2"],
		"weapon_id":"","bonuses":{"armor_flat":0,"parry_milli":0,
		"dodge_milli":0,"stealth":0},"use_kind":"NONE","placeholder":true},
	"MATERIAL_UNSPECIFIED":{"definition_id":"MATERIAL_UNSPECIFIED","label":"미정 재료",
		"category":"MATERIAL","stack_limit":99,"equip_slots":[],"weapon_id":"",
		"bonuses":{"armor_flat":0,"parry_milli":0,"dodge_milli":0,
		"stealth":0},"use_kind":"NONE","placeholder":true},
}

# Affixes are deliberately small extension records. They cannot alter weapon
# attack or accuracy authority; consumers may extend the hook list later.
const AFFIX_DEFINITIONS:={
	"GUARDED":{"affix_id":"GUARDED","bonuses":{"armor_flat":1,"parry_milli":0,
		"dodge_milli":0,"stealth":0},"hook_ids":[]},
	"NIMBLE":{"affix_id":"NIMBLE","bonuses":{"armor_flat":0,"parry_milli":0,
		"dodge_milli":50,"stealth":0},"hook_ids":[]},
}


static func has(definition_id:String)->bool:
	return DEFINITIONS.has(definition_id) and definition_error(DEFINITIONS[definition_id]).is_empty()


static func definition(definition_id:String):
	return DefinitionScript.new(DEFINITIONS[definition_id].duplicate(true)) if has(definition_id) else null


static func definition_dict(definition_id:String)->Dictionary:
	var value=definition(definition_id)
	return value.to_dict() if value!=null else {}


static func ids()->Array[String]:
	var result:Array[String]=[]
	for definition_id in DEFINITIONS:result.append(str(definition_id))
	result.sort();return result


static func weapon_definition_id(weapon_id:String)->String:
	for definition_id in ids():
		if str(DEFINITIONS[definition_id].get("weapon_id",""))==weapon_id:return definition_id
	return ""


static func is_two_handed(definition_id:String)->bool:
	var item_definition=definition(definition_id)
	if item_definition==null or item_definition.category!="WEAPON":return false
	var weapon=WeaponRegistryScript.definition(item_definition.weapon_id)
	return weapon!=null and bool(weapon.two_handed)


static func definition_error(row:Variant)->String:
	if not row is Dictionary:return "invalid_item_definition_shape"
	var keys:Array=row.keys();keys.sort()
	if keys!=["bonuses","category","definition_id","equip_slots","label","placeholder",
			"stack_limit","use_kind","weapon_id"]:
		return "invalid_item_definition_keys"
	if not row.get("equip_slots") is Array or not row.get("bonuses") is Dictionary \
			or not row.get("placeholder") is bool:
		return "invalid_item_definition_shape"
	for key in ["definition_id","label","category","weapon_id","use_kind"]:
		if not row.get(key) is String:return "invalid_item_definition_string"
	if not row.get("stack_limit") is int:return "invalid_item_definition_stack_limit"
	var bonus_keys:Array=row.bonuses.keys();bonus_keys.sort()
	var expected_bonus_keys:Array=DefinitionScript.BONUS_KEYS.duplicate();expected_bonus_keys.sort()
	if bonus_keys!=expected_bonus_keys:return "invalid_item_bonus_shape"
	for value in row.equip_slots:
		if not value is String:return "invalid_item_equip_slot"
	var value=DefinitionScript.new(row)
	var error:String=value.validation_error()
	if not error.is_empty():return error
	if value.category=="WEAPON":
		if not WeaponRegistryScript.has(value.weapon_id) or value.weapon_id=="UNARMED":
			return "unknown_item_weapon"
	return ""


static func has_affix(affix_id:String)->bool:
	return AFFIX_DEFINITIONS.has(affix_id) and affix_error(AFFIX_DEFINITIONS[affix_id]).is_empty()


static func affix(affix_id:String)->Dictionary:
	return AFFIX_DEFINITIONS[affix_id].duplicate(true) if has_affix(affix_id) else {}


static func affix_ids()->Array[String]:
	var result:Array[String]=[]
	for affix_id in AFFIX_DEFINITIONS:result.append(str(affix_id))
	result.sort();return result


static func affix_error(row:Variant)->String:
	if not row is Dictionary:return "invalid_item_affix_shape"
	var keys:Array=row.keys();keys.sort()
	if keys!=["affix_id","bonuses","hook_ids"]:return "invalid_item_affix_keys"
	if str(row.affix_id).is_empty() or not row.bonuses is Dictionary \
			or not row.hook_ids is Array:return "invalid_item_affix_shape"
	var bonus_keys:Array=row.bonuses.keys();bonus_keys.sort()
	var expected_bonus_keys:Array=DefinitionScript.BONUS_KEYS.duplicate();expected_bonus_keys.sort()
	if bonus_keys!=expected_bonus_keys:return "invalid_item_affix_bonuses"
	for key in DefinitionScript.BONUS_KEYS:
		if not _integer(row.bonuses[key]) or int(row.bonuses[key])<-10000 \
				or int(row.bonuses[key])>10000:return "invalid_item_affix_bonus"
	var hooks:Array=[]
	for hook in row.hook_ids:
		if not hook is String or str(hook).is_empty() or str(hook) in hooks:
			return "invalid_item_affix_hook"
		hooks.append(str(hook))
	var sorted_hooks:Array=hooks.duplicate();sorted_hooks.sort()
	if hooks!=sorted_hooks:return "noncanonical_item_affix_hooks"
	return ""


static func registry_error()->String:
	var weapon_bridges:Dictionary={}
	for definition_id in DEFINITIONS:
		if str(DEFINITIONS[definition_id].get("definition_id",""))!=definition_id:
			return "item_registry_key_mismatch"
		var error:=definition_error(DEFINITIONS[definition_id])
		if not error.is_empty():return error
		var weapon_id:=str(DEFINITIONS[definition_id].get("weapon_id",""))
		if not weapon_id.is_empty():
			if weapon_bridges.has(weapon_id):return "duplicate_item_weapon_bridge"
			weapon_bridges[weapon_id]=definition_id
	for weapon_id in WeaponRegistryScript.ids():
		if weapon_id=="UNARMED":continue
		if not weapon_bridges.has(weapon_id):return "missing_item_weapon_bridge"
	for affix_id in AFFIX_DEFINITIONS:
		if str(AFFIX_DEFINITIONS[affix_id].get("affix_id",""))!=affix_id:
			return "item_affix_registry_key_mismatch"
		var error:=affix_error(AFFIX_DEFINITIONS[affix_id])
		if not error.is_empty():return error
	return ""


static func _integer(value:Variant)->bool:
	return value is int or (value is float and value==floor(value))
