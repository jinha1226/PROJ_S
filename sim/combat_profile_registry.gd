class_name CombatProfileRegistry
extends RefCounted

const RULESET_ID := "combat-profile-registry-v1"
const DEFAULT_PROFILE_ID := "combatant-default-v1"
const PROFILE_KEYS := ["accuracy_milli", "armor_flat", "bleed_proc_milli",
	"bleed_resist_milli", "evasion_milli", "power", "profile_id"]

const KIND_TO_PROFILE := {
	"hero": "party-hero-v1",
	"companion": "party-companion-v1",
	"melee_enemy": "party-goblin-v1",
	"lead": "phase3-lead-v1",
	"melee_threat": "phase3-threat-v1",
	"passive_ally": "phase3-passive-v1",
}

const PROFILES := {
	"party-hero-v1": {"profile_id":"party-hero-v1", "accuracy_milli":600, "evasion_milli":150,
		"power":24, "armor_flat":2, "bleed_proc_milli":650, "bleed_resist_milli":100},
	"party-companion-v1": {"profile_id":"party-companion-v1", "accuracy_milli":575, "evasion_milli":130,
		"power":24, "armor_flat":2, "bleed_proc_milli":550, "bleed_resist_milli":100},
	"party-goblin-v1": {"profile_id":"party-goblin-v1", "accuracy_milli":550, "evasion_milli":100,
		"power":16, "armor_flat":2, "bleed_proc_milli":400, "bleed_resist_milli":50},
	"phase3-lead-v1": {"profile_id":"phase3-lead-v1", "accuracy_milli":600, "evasion_milli":150,
		"power":24, "armor_flat":2, "bleed_proc_milli":650, "bleed_resist_milli":100},
	"phase3-threat-v1": {"profile_id":"phase3-threat-v1", "accuracy_milli":550, "evasion_milli":100,
		"power":20, "armor_flat":2, "bleed_proc_milli":400, "bleed_resist_milli":50},
	"phase3-passive-v1": {"profile_id":"phase3-passive-v1", "accuracy_milli":500, "evasion_milli":130,
		"power":12, "armor_flat":2, "bleed_proc_milli":250, "bleed_resist_milli":100},
	"combatant-default-v1": {"profile_id":"combatant-default-v1", "accuracy_milli":500, "evasion_milli":100,
		"power":12, "armor_flat":2, "bleed_proc_milli":300, "bleed_resist_milli":100},
}

static func profile_id_for_kind(kind: String) -> String:
	return str(KIND_TO_PROFILE.get(kind, DEFAULT_PROFILE_ID))

static func has(profile_id: String) -> bool:
	return PROFILES.has(profile_id) and profile_error(PROFILES[profile_id]).is_empty()

static func profile(profile_id: String) -> Dictionary:
	return PROFILES[profile_id].duplicate(true) if has(profile_id) else {}

static func registry_error() -> String:
	for profile_id in PROFILES:
		var row: Dictionary = PROFILES[profile_id]
		if str(row.get("profile_id", "")) != profile_id:
			return "combat_profile_key_mismatch"
		var error := profile_error(row)
		if not error.is_empty(): return error
	for kind in KIND_TO_PROFILE:
		if not PROFILES.has(KIND_TO_PROFILE[kind]): return "unknown_kind_profile_mapping"
	return ""

static func profile_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_combat_profile_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != PROFILE_KEYS: return "invalid_combat_profile_keys"
	if not row.profile_id is String or str(row.profile_id).is_empty(): return "invalid_combat_profile_id"
	for key in ["accuracy_milli", "evasion_milli", "bleed_proc_milli", "bleed_resist_milli"]:
		if not row[key] is int or int(row[key]) < 0 or int(row[key]) > 1000:
			return "invalid_combat_profile_%s" % key
	if not row.power is int or int(row.power) < 1 or int(row.power) > 1000000:
		return "invalid_combat_profile_power"
	if not row.armor_flat is int or int(row.armor_flat) < 0 or int(row.armor_flat) > 1000000:
		return "invalid_combat_profile_armor"
	return ""
