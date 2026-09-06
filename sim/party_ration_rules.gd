class_name PartyRationRules
extends RefCounted

## Single authority for party ration numbers. Reads data/content/hunger_rules.json
## once; every consumer asks this script instead of holding its own constants.

const CONTENT_PATH := "res://data/content/hunger_rules.json"
const CONTENT_TYPE := "HUNGER_RULES"
const RULESET_ID := "party-ration-v1"
const ContentLoaderScript = preload("res://sim/json_content_loader.gd")
const EXPECTED_KEYS := ["content_schema_version", "content_version", "content_type",
	"ruleset_id", "ration_max", "hungry_below", "drain_interval",
	"drain_per_interval_milli", "drain_extra_member_milli", "starve_interval",
	"starve_damage", "starve_stress", "food_definition_id", "food_nutrition"]
const INTEGER_KEYS := ["ration_max", "hungry_below", "drain_interval",
	"drain_per_interval_milli", "drain_extra_member_milli", "starve_interval",
	"starve_damage", "starve_stress", "food_nutrition"]

static var _CONTENT: Dictionary = ContentLoaderScript.load_document(CONTENT_PATH)


static func rules() -> Dictionary:
	return _CONTENT.duplicate(true)


static func registry_error() -> String:
	var document_error := ContentLoaderScript.document_error(_CONTENT, CONTENT_TYPE, EXPECTED_KEYS)
	if not document_error.is_empty(): return document_error
	if str(_CONTENT.get("ruleset_id", "")) != RULESET_ID: return "hunger_ruleset_mismatch"
	for key in INTEGER_KEYS:
		if not _CONTENT.get(key) is int or int(_CONTENT[key]) < 1:
			return "hunger_rule_not_positive_integer:%s" % key
	if int(_CONTENT.hungry_below) >= int(_CONTENT.ration_max): return "hunger_threshold_above_max"
	if int(_CONTENT.food_nutrition) > int(_CONTENT.ration_max): return "hunger_nutrition_above_max"
	# The starve boundary is counted in whole drain intervals, so a starve_interval
	# that does not tile the drain interval would silently drop or double bites.
	if int(_CONTENT.starve_interval) % int(_CONTENT.drain_interval) != 0:
		return "hunger_starve_interval_not_divisible"
	if not _CONTENT.get("food_definition_id") is String \
			or str(_CONTENT.food_definition_id).is_empty():
		return "hunger_food_definition_invalid"
	return ""


static func ration_max_milli() -> int:
	return int(_CONTENT.get("ration_max", 0)) * 1000


static func hungry_below_milli() -> int:
	return int(_CONTENT.get("hungry_below", 0)) * 1000


static func food_nutrition_milli() -> int:
	return int(_CONTENT.get("food_nutrition", 0)) * 1000


static func band(ration_milli: int) -> String:
	if ration_milli <= 0: return "STARVING"
	if ration_milli < hungry_below_milli(): return "HUNGRY"
	return "FED"


static func drain_per_interval_milli(active_count: int) -> int:
	var extra := maxi(0, active_count - 1)
	return int(_CONTENT.get("drain_per_interval_milli", 0)) \
		+ int(_CONTENT.get("drain_extra_member_milli", 0)) * extra
