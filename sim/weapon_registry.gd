class_name WeaponRegistry
extends RefCounted

const RULESET_ID := "weapon-registry-v1"
const DefinitionScript = preload("res://sim/weapon_definition.gd")

# attack_time is intrinsic to the weapon. Proficiency never reads or changes it.
const DEFINITIONS := {
	"UNARMED": {"weapon_id":"UNARMED", "label":"맨손", "proficiency_id":"UNARMED",
		"attack_form":"IMPACT", "range_min":1, "range_max":1, "base_damage":0,
		"accuracy_milli":20, "armor_penetration_flat":0, "attack_time":70,
		"ammo_kind":"NONE", "ammo_cost":0, "reload_required":false, "reload_time":0,
		"trait_id":"FAST_UNARMED", "secondary_damage_milli":0, "stun_chance_milli":0},
	"SHORT_SWORD": {"weapon_id":"SHORT_SWORD", "label":"단검", "proficiency_id":"SWORD",
		"attack_form":"SLASH", "range_min":1, "range_max":1, "base_damage":4,
		"accuracy_milli":40, "armor_penetration_flat":0, "attack_time":100,
		"ammo_kind":"NONE", "ammo_cost":0, "reload_required":false, "reload_time":0,
		"trait_id":"NONE", "secondary_damage_milli":0, "stun_chance_milli":0},
	"THRUSTING_SWORD": {"weapon_id":"THRUSTING_SWORD", "label":"찌르기검", "proficiency_id":"SWORD",
		"attack_form":"PIERCE", "range_min":1, "range_max":1, "base_damage":4,
		"accuracy_milli":30, "armor_penetration_flat":1, "attack_time":100,
		"ammo_kind":"NONE", "ammo_cost":0, "reload_required":false, "reload_time":0,
		"trait_id":"NONE", "secondary_damage_milli":0, "stun_chance_milli":0},
	"HAND_AXE": {"weapon_id":"HAND_AXE", "label":"손도끼", "proficiency_id":"AXE",
		"attack_form":"SLASH", "range_min":1, "range_max":1, "base_damage":6,
		"accuracy_milli":-20, "armor_penetration_flat":0, "attack_time":120,
		"ammo_kind":"NONE", "ammo_cost":0, "reload_required":false, "reload_time":0,
		"trait_id":"AXE_CLEAVE", "secondary_damage_milli":400, "stun_chance_milli":0},
	"MACE": {"weapon_id":"MACE", "label":"철퇴", "proficiency_id":"BLUNT",
		"attack_form":"IMPACT", "range_min":1, "range_max":1, "base_damage":5,
		"accuracy_milli":-10, "armor_penetration_flat":1, "attack_time":125,
		"ammo_kind":"NONE", "ammo_cost":0, "reload_required":false, "reload_time":0,
		"trait_id":"BLUNT_STUN", "secondary_damage_milli":0, "stun_chance_milli":250},
	"SPEAR": {"weapon_id":"SPEAR", "label":"창", "proficiency_id":"SPEAR",
		"attack_form":"PIERCE", "range_min":1, "range_max":2, "base_damage":5,
		"accuracy_milli":10, "armor_penetration_flat":1, "attack_time":110,
		"ammo_kind":"NONE", "ammo_cost":0, "reload_required":false, "reload_time":0,
		"trait_id":"SPEAR_REACH", "secondary_damage_milli":0, "stun_chance_milli":0},
	"BOW": {"weapon_id":"BOW", "label":"활", "proficiency_id":"RANGED",
		"attack_form":"PIERCE", "range_min":2, "range_max":8, "base_damage":4,
		"accuracy_milli":0, "armor_penetration_flat":0, "attack_time":90,
		"ammo_kind":"ARROW", "ammo_cost":1, "reload_required":false, "reload_time":0,
		"trait_id":"BOW_REPEAT", "secondary_damage_milli":0, "stun_chance_milli":0},
	"CROSSBOW": {"weapon_id":"CROSSBOW", "label":"쇠뇌", "proficiency_id":"RANGED",
		"attack_form":"PIERCE", "range_min":2, "range_max":10, "base_damage":9,
		"accuracy_milli":30, "armor_penetration_flat":3, "attack_time":115,
		"ammo_kind":"BOLT", "ammo_cost":1, "reload_required":true, "reload_time":140,
		"trait_id":"CROSSBOW_RELOAD", "secondary_damage_milli":0, "stun_chance_milli":0},
}


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
	var value = DefinitionScript.new(row)
	return value.validation_error()


static func registry_error() -> String:
	for weapon_id in DEFINITIONS:
		if str(DEFINITIONS[weapon_id].get("weapon_id", "")) != weapon_id:
			return "weapon_registry_key_mismatch"
		var error := definition_error(DEFINITIONS[weapon_id])
		if not error.is_empty(): return error
	return ""
