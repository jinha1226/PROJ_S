class_name ItemRegistry
extends RefCounted

const DefinitionScript=preload("res://sim/item_definition.gd")
const WeaponRegistryScript=preload("res://sim/weapon_registry.gd")
const ContentLoaderScript=preload("res://sim/json_content_loader.gd")
const CONTENT_PATH:="res://data/content/items.json"
static var _CONTENT:Dictionary=ContentLoaderScript.load_document(CONTENT_PATH)
static var RULESET_ID:String=str(_CONTENT.get("ruleset_id",""))
static var HEALING_POTION_RESTORE:int=int(_CONTENT.get("healing_potion_restore",0))
static var DEFINITIONS:Dictionary=ContentLoaderScript.index_rows(
	_CONTENT.get("definitions",[]),"definition_id")
# Affixes remain small extension records and cannot replace weapon authority.
static var AFFIX_DEFINITIONS:Dictionary=ContentLoaderScript.index_rows(
	_CONTENT.get("affixes",[]),"affix_id")


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
			"requirements","stack_limit","use_kind","weapon_id"]:
		return "invalid_item_definition_keys"
	if not row.get("equip_slots") is Array or not row.get("bonuses") is Dictionary \
			or not row.get("requirements") is Dictionary \
			or not row.get("placeholder") is bool:
		return "invalid_item_definition_shape"
	for key in ["definition_id","label","category","weapon_id","use_kind"]:
		if not row.get(key) is String:return "invalid_item_definition_string"
	if not row.get("stack_limit") is int:return "invalid_item_definition_stack_limit"
	var bonus_keys:Array=row.bonuses.keys();bonus_keys.sort()
	var expected_bonus_keys:Array=DefinitionScript.BONUS_KEYS.duplicate();expected_bonus_keys.sort()
	if bonus_keys!=expected_bonus_keys:return "invalid_item_bonus_shape"
	var requirement_keys:Array=row.requirements.keys();requirement_keys.sort()
	if requirement_keys!=["DEX","INT","STR"]:return "invalid_item_requirements_shape"
	for stat_id in ["STR","DEX","INT"]:
		if not row.requirements[stat_id] is int or int(row.requirements[stat_id])<0:
			return "invalid_item_requirement"
	for value in row.equip_slots:
		if not value is String:return "invalid_item_equip_slot"
	var value=DefinitionScript.new(row)
	var error:String=value.validation_error()
	if not error.is_empty():return error
	if value.category=="WEAPON":
		if not WeaponRegistryScript.has(value.weapon_id) \
				or bool(WeaponRegistryScript.definition(value.weapon_id).natural_weapon):
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
	var document_error:=ContentLoaderScript.document_error(_CONTENT,"ITEMS",[
		"content_schema_version","content_version","content_type","ruleset_id",
		"healing_potion_restore","definitions","affixes"])
	if not document_error.is_empty():return document_error
	if RULESET_ID!="item-registry-v2":return "item_ruleset_mismatch"
	if HEALING_POTION_RESTORE<1 or HEALING_POTION_RESTORE>10000:
		return "invalid_item_healing_amount"
	var rows_error:=ContentLoaderScript.rows_error(_CONTENT.definitions,"definition_id")
	if not rows_error.is_empty():return rows_error
	rows_error=ContentLoaderScript.rows_error(_CONTENT.affixes,"affix_id")
	if not rows_error.is_empty():return rows_error
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
		if bool(WeaponRegistryScript.definition(weapon_id).natural_weapon):continue
		if not weapon_bridges.has(weapon_id):return "missing_item_weapon_bridge"
	for affix_id in AFFIX_DEFINITIONS:
		if str(AFFIX_DEFINITIONS[affix_id].get("affix_id",""))!=affix_id:
			return "item_affix_registry_key_mismatch"
		var error:=affix_error(AFFIX_DEFINITIONS[affix_id])
		if not error.is_empty():return error
	return ""


static func content_version()->String:
	return str(_CONTENT.get("content_version",""))


static func _integer(value:Variant)->bool:
	return value is int or (value is float and value==floor(value))
