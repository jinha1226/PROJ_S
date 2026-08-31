class_name WeaponRegistry
extends RefCounted

const DefinitionScript = preload("res://sim/weapon_definition.gd")
const ContentLoaderScript=preload("res://sim/json_content_loader.gd")
const ProgressionRegistryScript=preload("res://sim/progression_registry.gd")
const CONTENT_PATH:="res://data/content/weapons.json"
static var _CONTENT:Dictionary=ContentLoaderScript.load_document(CONTENT_PATH)
static var RULESET_ID:String=str(_CONTENT.get("ruleset_id",""))
# attack_time remains intrinsic JSON weapon data. Proficiency never changes it.
static var DEFINITIONS:Dictionary=ContentLoaderScript.index_rows(
	_CONTENT.get("definitions",[]),"weapon_id")


static func has(weapon_id: String) -> bool:
	return DEFINITIONS.has(weapon_id) and definition_error(DEFINITIONS[weapon_id]).is_empty()


static func definition(weapon_id: String):
	return DefinitionScript.new(DEFINITIONS[weapon_id]) if has(weapon_id) else null


static func definition_dict(weapon_id: String) -> Dictionary:
	var value = definition(weapon_id)
	return value.to_dict() if value != null else {}


static func ids() -> Array[String]:
	var result: Array[String] = []
	for weapon_id in DEFINITIONS: result.append(str(weapon_id))
	result.sort()
	return result


static func definition_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_weapon_definition_shape"
	if not row.get("two_handed") is bool: return "invalid_weapon_hands"
	var value = DefinitionScript.new(row)
	return value.validation_error()


static func registry_error() -> String:
	var document_error:=ContentLoaderScript.document_error(_CONTENT,"WEAPONS",[
		"content_schema_version","content_version","content_type","ruleset_id","definitions"])
	if not document_error.is_empty():return document_error
	if RULESET_ID!="weapon-registry-v1":return "weapon_ruleset_mismatch"
	var rows_error:=ContentLoaderScript.rows_error(_CONTENT.definitions,"weapon_id")
	if not rows_error.is_empty():return rows_error
	for weapon_id in DEFINITIONS:
		if str(DEFINITIONS[weapon_id].get("weapon_id", "")) != weapon_id:
			return "weapon_registry_key_mismatch"
		var error := definition_error(DEFINITIONS[weapon_id])
		if not error.is_empty(): return error
		if str(DEFINITIONS[weapon_id].get("proficiency_id","")) \
				not in ProgressionRegistryScript.PROFICIENCY_IDS:
			return "unknown_weapon_proficiency"
	return ""


static func content_version()->String:
	return str(_CONTENT.get("content_version",""))
