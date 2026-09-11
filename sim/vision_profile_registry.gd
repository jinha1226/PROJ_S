class_name VisionProfileRegistry
extends RefCounted

const RULESET_ID := "shared-vision-profiles-v1"
const PROFILE_KEYS := ["base_sight_range", "dark_front_angle", "dark_vision_milli",
	"detection_sensitivity_milli", "darkness_stress_resistance_milli", "peripheral_range"]
const BASE_PROFILE := {
	"base_sight_range": 6, "dark_vision_milli": 350, "dark_front_angle": 120,
	"peripheral_range": 2, "detection_sensitivity_milli": 500,
	"darkness_stress_resistance_milli": 500,
}
const SPECIES_PROFILES := {
	"human": {"base_sight_range": 6, "dark_vision_milli": 300,
		"dark_front_angle": 120, "peripheral_range": 2,
		"detection_sensitivity_milli": 500, "darkness_stress_resistance_milli": 500},
	"elf": {"base_sight_range": 8, "dark_vision_milli": 650,
		"dark_front_angle": 150, "peripheral_range": 2,
		"detection_sensitivity_milli": 700, "darkness_stress_resistance_milli": 450},
	"dwarf": {"base_sight_range": 5, "dark_vision_milli": 850,
		"dark_front_angle": 180, "peripheral_range": 2,
		"detection_sensitivity_milli": 560, "darkness_stress_resistance_milli": 650},
	"orc": {"base_sight_range": 5, "dark_vision_milli": 400,
		"dark_front_angle": 110, "peripheral_range": 2,
		"detection_sensitivity_milli": 520, "darkness_stress_resistance_milli": 550},
	"beastkin": {"base_sight_range": 7, "dark_vision_milli": 550,
		"dark_front_angle": 135, "peripheral_range": 2,
		"detection_sensitivity_milli": 650, "darkness_stress_resistance_milli": 500},
	"goblin": {"base_sight_range": 6, "dark_vision_milli": 750,
		"dark_front_angle": 165, "peripheral_range": 2,
		"detection_sensitivity_milli": 520, "darkness_stress_resistance_milli": 600},
	"kobold": {"base_sight_range": 7, "dark_vision_milli": 900,
		"dark_front_angle": 180, "peripheral_range": 2,
		"detection_sensitivity_milli": 680, "darkness_stress_resistance_milli": 700},
	"generic_humanoid": {"base_sight_range": 6, "dark_vision_milli": 350,
		"dark_front_angle": 120, "peripheral_range": 2,
		"detection_sensitivity_milli": 500, "darkness_stress_resistance_milli": 500},
}
const TYPE_OVERRIDES := {
	"scout": {"base_sight_range": 8, "detection_sensitivity_milli": 760},
	"sentinel": {"base_sight_range": 7, "dark_front_angle": 180,
		"detection_sensitivity_milli": 820},
	"predator": {"base_sight_range": 7, "dark_front_angle": 100,
		"peripheral_range": 1, "detection_sensitivity_milli": 720},
	"cave_beast": {"base_sight_range": 4, "dark_vision_milli": 850,
		"dark_front_angle": 160, "detection_sensitivity_milli": 460},
}
static var _warned_unknown: Dictionary = {}


static func profile_for(species_id: String, monster_type: String = "") -> Dictionary:
	var species := str(species_id).to_lower()
	var result: Dictionary = BASE_PROFILE.duplicate(true)
	if SPECIES_PROFILES.has(species):
		result.merge(SPECIES_PROFILES[species], true)
	else:
		_warn_unknown("species", species)
	var override_key := str(monster_type).to_lower()
	if not override_key.is_empty():
		if TYPE_OVERRIDES.has(override_key):
			result.merge(TYPE_OVERRIDES[override_key], true)
		else:
			_warn_unknown("monster_type", override_key)
	return _clamp_profile(result)


static func profile_for_entity(entity) -> Dictionary:
	if entity == null:
		return _clamp_profile(BASE_PROFILE.duplicate(true))
	var monster_type := ""
	for tag in entity.tags:
		var value := str(tag)
		if value.begins_with("vision_type:"):
			monster_type = value.trim_prefix("vision_type:")
			break
	return profile_for(str(entity.species_id), monster_type)


static func registry_error() -> String:
	if BASE_PROFILE.keys().size() != PROFILE_KEYS.size():
		return "vision_base_profile_keys_invalid"
	for row in [BASE_PROFILE] + SPECIES_PROFILES.values() + TYPE_OVERRIDES.values():
		for key in row:
			if key not in PROFILE_KEYS or not row[key] is int:
				return "vision_profile_field_invalid"
		var merged := BASE_PROFILE.duplicate(true)
		merged.merge(row, true)
		if not _profile_error(merged).is_empty():
			return "vision_profile_scalar_invalid"
	return ""


static func _clamp_profile(row: Dictionary) -> Dictionary:
	var result := BASE_PROFILE.duplicate(true)
	result.merge(row, true)
	result.base_sight_range = clampi(int(result.base_sight_range), 1, 15)
	result.dark_vision_milli = clampi(int(result.dark_vision_milli), 0, 1000)
	result.dark_front_angle = clampi(int(result.dark_front_angle), 0, 180)
	result.peripheral_range = clampi(int(result.peripheral_range), 0, result.base_sight_range)
	result.detection_sensitivity_milli = clampi(int(result.detection_sensitivity_milli), 0, 1000)
	result.darkness_stress_resistance_milli = clampi(
		int(result.darkness_stress_resistance_milli), 0, 1000)
	return result


static func _profile_error(row: Dictionary) -> String:
	for key in PROFILE_KEYS:
		if not row.has(key) or not row[key] is int:
			return "missing_profile_field"
	if int(row.base_sight_range) < 1 or int(row.base_sight_range) > 15 \
			or int(row.dark_vision_milli) < 0 or int(row.dark_vision_milli) > 1000 \
			or int(row.dark_front_angle) < 0 or int(row.dark_front_angle) > 180 \
			or int(row.peripheral_range) < 0 or int(row.peripheral_range) > int(row.base_sight_range) \
			or int(row.detection_sensitivity_milli) < 0 \
			or int(row.detection_sensitivity_milli) > 1000 \
			or int(row.darkness_stress_resistance_milli) < 0 \
			or int(row.darkness_stress_resistance_milli) > 1000:
		return "profile_scalar_out_of_range"
	return ""


static func _warn_unknown(kind: String, value: String) -> void:
	if value.is_empty() or _warned_unknown.has(kind + ":" + value):
		return
	_warned_unknown[kind + ":" + value] = true
	push_warning("Vision profile fallback: unknown %s '%s'" % [kind, value])
