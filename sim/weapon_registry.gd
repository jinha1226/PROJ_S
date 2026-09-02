class_name WeaponRegistry
extends RefCounted

const DefinitionScript = preload("res://sim/weapon_definition.gd")
const ContentLoaderScript=preload("res://sim/json_content_loader.gd")
const ProgressionRegistryScript=preload("res://sim/progression_registry.gd")
const CONTENT_PATH:="res://data/content/weapons.json"
static var _CONTENT:Dictionary=ContentLoaderScript.load_document(CONTENT_PATH)
static var RULESET_ID:String=str(_CONTENT.get("ruleset_id",""))
static var STAT_SCALING_RULES:Dictionary=_CONTENT.get("stat_scaling_rules",{}).duplicate(true)
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
	var keys:Array=row.keys();keys.sort()
	if keys!=["accuracy_milli","ammo_cost","ammo_kind","armor_penetration_flat",
			"attack_form","attack_time","base_damage","label","natural_weapon",
			"proficiency_id","range_max","range_min","reload_required","reload_time",
			"scaling","secondary_damage_milli","stun_chance_milli","trait_id",
			"two_handed","weapon_id"]:return "invalid_weapon_definition_keys"
	if not row.get("two_handed") is bool or not row.get("natural_weapon") is bool \
			or not row.get("scaling") is Dictionary:return "invalid_weapon_definition_shape"
	var value = DefinitionScript.new(row)
	return value.validation_error()


static func registry_error() -> String:
	var document_error:=ContentLoaderScript.document_error(_CONTENT,"WEAPONS",[
		"content_schema_version","content_version","content_type","ruleset_id",
		"stat_scaling_rules","definitions"])
	if not document_error.is_empty():return document_error
	if RULESET_ID!="weapon-registry-v1":return "weapon_ruleset_mismatch"
	var scaling_error:=_stat_scaling_rules_error(STAT_SCALING_RULES)
	if not scaling_error.is_empty():return scaling_error
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


static func stat_scaling_rules()->Dictionary:
	return STAT_SCALING_RULES.duplicate(true)


static func _stat_scaling_rules_error(row:Variant)->String:
	if not row is Dictionary:return "invalid_stat_scaling_rules"
	var keys:Array=row.keys();keys.sort()
	if keys!=["grade_coefficients_milli","stat_baseline","total_bonus_cap_milli"] \
			or not row.grade_coefficients_milli is Dictionary \
			or not row.stat_baseline is int or not row.total_bonus_cap_milli is int:
		return "invalid_stat_scaling_rules"
	var grade_keys:Array=row.grade_coefficients_milli.keys();grade_keys.sort()
	if grade_keys!=["A","B","C","D","E","NONE"]:return "invalid_stat_scaling_rules"
	if int(row.stat_baseline)<0 or int(row.stat_baseline)>1000 \
			or int(row.total_bonus_cap_milli)<0 or int(row.total_bonus_cap_milli)>1000:
		return "invalid_stat_scaling_rules"
	for grade in grade_keys:
		if not row.grade_coefficients_milli[grade] is int \
				or int(row.grade_coefficients_milli[grade])<0 \
				or int(row.grade_coefficients_milli[grade])>1000:
			return "invalid_stat_scaling_rules"
	if int(row.grade_coefficients_milli.NONE)!=0:return "invalid_stat_scaling_rules"
	var previous:=0
	for grade in ["E","D","C","B","A"]:
		var coefficient:=int(row.grade_coefficients_milli[grade])
		if coefficient<=previous:return "invalid_stat_scaling_rules"
		previous=coefficient
	return ""


static func content_version()->String:
	return str(_CONTENT.get("content_version",""))
