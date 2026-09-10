class_name AbilityBindingRules
extends RefCounted

const RULESET_ID := "ability-binding-v1"
const MAX_SLOTS := 6
const REMOVAL_POLICY := "LOCKED_UNTIL_POLICY_DEFINED"
const ALIASES := {
	# Keep aliases explicit so an old/content-facing name cannot create a second
	# effect or bypass duplicate detection.
	"FIRE_BOLT": "FIREBOLT",
}
const ActiveSkillRegistryScript = preload("res://sim/abilities/active_skill_registry.gd")


static func canonical_id(ability_id: String) -> String:
	var value := str(ability_id)
	return str(ALIASES.get(value, value))


static func has(ability_id: String) -> bool:
	return ActiveSkillRegistryScript.SKILLS.has(canonical_id(ability_id))


static func definition(ability_id: String) -> Dictionary:
	return ActiveSkillRegistryScript.definition(canonical_id(ability_id))


static func slot_limit(level: int) -> int:
	return clampi(int(level), 0, MAX_SLOTS)


static func binding_ids_error(ids: Variant) -> String:
	if not ids is Array:
		return "invalid_ability_binding_ids"
	if ids.size() > MAX_SLOTS:
		return "ability_binding_slots_overflow"
	var previous := ""
	var seen: Dictionary = {}
	for raw_id in ids:
		if not raw_id is String or str(raw_id).is_empty():
			return "invalid_ability_binding_id"
		var canonical := canonical_id(str(raw_id))
		if canonical != str(raw_id) or not has(canonical):
			return "invalid_ability_binding_id"
		if seen.has(canonical):
			return "duplicate_ability_binding"
		if not previous.is_empty() and canonical <= previous:
			return "noncanonical_ability_binding_order"
		seen[canonical] = true
		previous = canonical
	return ""


static func effect_preview(ability_id: String) -> Dictionary:
	var canonical := canonical_id(ability_id)
	var row := definition(canonical)
	if row.is_empty():
		return {}
	return {"ability_id": canonical, "label": str(row.get("name", canonical)),
		"kind": "ACTIVE", "cost": int(row.get("cost", 0)),
		"range": int(row.get("range", 0)), "effect": str(row.get("effect", "")),
		"power": int(row.get("power", 0))}.duplicate(true)
