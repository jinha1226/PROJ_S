class_name PartyTurnPlan
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")
const ProfileRegistryScript = preload("res://sim/combat_profile_registry.gd")
const ASSESSMENT_KEYS := ["schema_version", "attacker_id", "target_id", "attacker_position",
	"target_position", "attacker_life_state", "target_life_state", "attacker_profile_id",
	"target_profile_id", "target_evasion_milli", "target_armor_flat", "frozen_guarded_until",
	"guard_source_event_id", "source", "processed_step_index", "attack_start_world_time",
	"batch_context", "intent_ordinal", "intent_mode", "hit_chance_milli", "bleed_chance_milli",
	"base_damage", "armor_reduction", "guarded", "guard_reduction", "normal_final_damage",
	"commitment_hash"]

var _data: Dictionary
func _init(p_data: Dictionary = {}) -> void: _data = p_data.duplicate(true)
func to_dict() -> Dictionary: return _data.duplicate(true)
func get_value(key: String, fallback: Variant = null) -> Variant:
	var value: Variant = _data.get(key, fallback)
	return value.duplicate(true) if value is Dictionary or value is Array else value

static func combat_assessment_wire_error(value: Variant) -> String:
	if not value is Dictionary: return "invalid_combat_assessment_shape"
	var keys: Array = value.keys(); keys.sort()
	var expected_keys: Array = ASSESSMENT_KEYS.duplicate(); expected_keys.sort()
	if keys != expected_keys: return "invalid_combat_assessment_keys"
	if value.schema_version != 1: return "unsupported_combat_assessment_schema"
	for key in ["attacker_id", "target_id", "frozen_guarded_until", "guard_source_event_id",
			"processed_step_index", "attack_start_world_time"]:
		if not Int64CodecScript.is_canonical(value.get(key)): return "noncanonical_combat_assessment_%s" % key
	if Int64CodecScript.parse(value.attacker_id, "attacker") <= 0 \
			or Int64CodecScript.parse(value.target_id, "target") <= 0 \
			or Int64CodecScript.parse(value.frozen_guarded_until, "guard") < 0 \
			or Int64CodecScript.parse(value.guard_source_event_id, "guard source") < -1 \
			or Int64CodecScript.parse(value.processed_step_index, "processed step") < 1 \
			or Int64CodecScript.parse(value.attack_start_world_time, "attack time") < 0:
		return "invalid_combat_assessment_int64_range"
	for key in ["attacker_position", "target_position"]:
		if not value.get(key) is Array or value[key].size() != 2 \
				or not value[key][0] is int or not value[key][1] is int:
			return "invalid_combat_assessment_position"
	if value.attacker_life_state != "ACTIVE" or value.target_life_state not in ["ACTIVE", "DOWNED"] \
			or value.source not in ["DIRECT", "SUGGESTED", "OVERRIDE"] \
			or value.intent_mode not in ["STRIKE", "FINISHER"]:
		return "invalid_combat_assessment_enum"
	for key in ["attacker_profile_id", "target_profile_id", "batch_context"]:
		if not value.get(key) is String or str(value[key]).is_empty(): return "invalid_combat_assessment_string"
	if not ProfileRegistryScript.has(str(value.attacker_profile_id)) \
			or not ProfileRegistryScript.has(str(value.target_profile_id)):
		return "unknown_combat_assessment_profile"
	for key in ["target_evasion_milli", "target_armor_flat", "intent_ordinal", "hit_chance_milli",
			"bleed_chance_milli", "base_damage", "armor_reduction", "guard_reduction", "normal_final_damage"]:
		if not value.get(key) is int or int(value[key]) < 0: return "invalid_combat_assessment_number"
	if int(value.target_evasion_milli) > 1000 or int(value.hit_chance_milli) > 1000 \
			or int(value.bleed_chance_milli) > 1000 or int(value.target_armor_flat) > 1000000 \
			or int(value.base_damage) < 1 or int(value.base_damage) > 1000000:
		return "invalid_combat_assessment_number"
	if not value.guarded is bool or not _lower_hex_64(value.commitment_hash):
		return "invalid_combat_assessment_commitment"
	return ""

static func canonical_hash(data: Dictionary, omitted_key: String = "plan_hash") -> String:
	var copy := data.duplicate(true); copy.erase(omitted_key)
	return _stable_encode(copy).sha256_text()

static func _stable_encode(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		var sorted_keys: Array = keys.duplicate(); sorted_keys.sort()
		var assessment_sorted: Array = ASSESSMENT_KEYS.duplicate(); assessment_sorted.sort()
		keys = ASSESSMENT_KEYS.duplicate() if sorted_keys == assessment_sorted else sorted_keys
		var parts: Array[String] = []
		for key in keys: parts.append(JSON.stringify(str(key)) + ":" + _stable_encode(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: Array[String] = []
		for item in value: parts.append(_stable_encode(item))
		return "[" + ",".join(parts) + "]"
	return JSON.stringify(value)

static func _lower_hex_64(value: Variant) -> bool:
	if not value is String or str(value).length() != 64: return false
	for character in str(value):
		if character not in "0123456789abcdef": return false
	return true
