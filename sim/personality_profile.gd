class_name PersonalityProfile
extends RefCounted

const PROFILE_SCHEMA_VERSION := 1
const Int64CodecScript = preload("res://sim/int64_codec.gd")

var profile_schema_version: int = PROFILE_SCHEMA_VERSION
var generation_ruleset_id: String
var facet_rows: Array[Dictionary] = []


func _init(p_generation_ruleset_id: String = "", p_rows: Array = []) -> void:
	generation_ruleset_id = p_generation_ruleset_id
	for row in p_rows:
		facet_rows.append({"facet_id": str(row["facet_id"]), "base_value": int(row["base_value"])})
	facet_rows.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.facet_id) < str(b.facet_id))


func value(facet_id: String) -> int:
	for row in facet_rows:
		if row.facet_id == facet_id:
			return int(row.base_value)
	return -1


func to_dict() -> Dictionary:
	return {"profile_schema_version": profile_schema_version,
		"generation_ruleset_id": generation_ruleset_id,
		"facet_rows": facet_rows.duplicate(true)}


static func from_dict(row: Dictionary):
	var profile = load("res://sim/personality_profile.gd").new(
		str(row.get("generation_ruleset_id", "")), row.get("facet_rows", []))
	profile.profile_schema_version = int(row.get("profile_schema_version", -1))
	return profile
