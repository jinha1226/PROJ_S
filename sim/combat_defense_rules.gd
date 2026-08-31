class_name CombatDefenseRules
extends RefCounted

# Pure defense seam for the canonical combat resolver. This module owns no
# entity, event, RNG, or turn state: callers freeze a snapshot, then include it
# in their own authoritative assessment when that schema is ready to migrate.
const RULESET_ID := "deterministic-combat-defense-v1"
const SCHEMA_VERSION := 1
const MIN_HIT_CHANCE_MILLI := 50
const MAX_HIT_CHANCE_MILLI := 950
const MAX_MILLI := 1000
const MAX_FLAT_VALUE := 1000000

const SNAPSHOT_KEYS := [
	"base_armor_flat",
	"base_evasion_milli",
	"dodge_milli",
	"effective_armor_flat",
	"effective_evasion_milli",
	"equipment_armor_flat",
	"parry_milli",
	"ruleset_id",
	"schema_version",
]


static func build_snapshot(base_evasion_milli: int, base_armor_flat: int,
		equipment_bonuses: Dictionary = {}) -> Dictionary:
	if base_evasion_milli < 0 or base_evasion_milli > MAX_MILLI \
			or base_armor_flat < 0 or base_armor_flat > MAX_FLAT_VALUE \
			or not bonus_error(equipment_bonuses).is_empty():
		return {}
	var equipment_armor_flat := int(equipment_bonuses.get("armor_flat", 0))
	var dodge_milli := int(equipment_bonuses.get("dodge_milli", 0))
	var parry_milli := int(equipment_bonuses.get("parry_milli", 0))
	return {
		"schema_version": SCHEMA_VERSION,
		"ruleset_id": RULESET_ID,
		"base_armor_flat": base_armor_flat,
		"equipment_armor_flat": equipment_armor_flat,
		"effective_armor_flat": base_armor_flat + equipment_armor_flat,
		"base_evasion_milli": base_evasion_milli,
		"dodge_milli": dodge_milli,
		"effective_evasion_milli": mini(MAX_MILLI, base_evasion_milli + dodge_milli),
		"parry_milli": mini(MAX_MILLI, parry_milli),
	}.duplicate(true)


static func bonus_error(equipment_bonuses: Variant) -> String:
	if not equipment_bonuses is Dictionary:
		return "invalid_defense_bonus_shape"
	for key in ["armor_flat", "dodge_milli", "parry_milli"]:
		var value: Variant = equipment_bonuses.get(key, 0)
		if not value is int:
			return "invalid_defense_bonus_%s" % key
		var upper_bound := MAX_FLAT_VALUE if key == "armor_flat" else MAX_MILLI
		if int(value) < 0 or int(value) > upper_bound:
			return "invalid_defense_bonus_%s" % key
	return ""


static func snapshot_error(snapshot: Variant) -> String:
	if not snapshot is Dictionary:
		return "invalid_defense_snapshot_shape"
	var keys: Array = snapshot.keys()
	keys.sort()
	if keys != SNAPSHOT_KEYS:
		return "invalid_defense_snapshot_keys"
	if snapshot.get("schema_version") != SCHEMA_VERSION \
			or snapshot.get("ruleset_id") != RULESET_ID:
		return "invalid_defense_snapshot_identity"
	for key in ["base_armor_flat", "equipment_armor_flat", "effective_armor_flat",
			"base_evasion_milli", "dodge_milli", "effective_evasion_milli", "parry_milli"]:
		if not snapshot.get(key) is int:
			return "invalid_defense_snapshot_scalar"
	var rebuilt := build_snapshot(int(snapshot.base_evasion_milli),
		int(snapshot.base_armor_flat), {
			"armor_flat": int(snapshot.equipment_armor_flat),
			"dodge_milli": int(snapshot.dodge_milli),
			"parry_milli": int(snapshot.parry_milli),
		})
	if rebuilt != snapshot:
		return "invalid_defense_snapshot_projection"
	return ""


# Accuracy is split into the same three existing sources so an eventual
# canonical integration can replace the inline formula without changing its
# meaning. Dodge raises effective evasion; parry is deliberately not folded
# into this roll because it has its own readable post-hit outcome.
static func hit_chance_milli(attacker_accuracy_milli: int,
		weapon_accuracy_milli: int, proficiency_accuracy_milli: int,
		snapshot: Dictionary) -> int:
	if not snapshot_error(snapshot).is_empty():
		return -1
	return clampi(500 + attacker_accuracy_milli + weapon_accuracy_milli \
		+ proficiency_accuracy_milli - int(snapshot.effective_evasion_milli),
		MIN_HIT_CHANCE_MILLI, MAX_HIT_CHANCE_MILLI)


# Flat armor acts only after a hit. Penetration removes armor one-for-one, and
# a non-parried landed attack always keeps the existing minimum one damage.
static func armor_reduction(raw_damage: int, armor_penetration_flat: int,
		snapshot: Dictionary) -> int:
	if raw_damage < 0 or armor_penetration_flat < 0 \
			or not snapshot_error(snapshot).is_empty():
		return -1
	var effective_armor := maxi(0,
		int(snapshot.effective_armor_flat) - armor_penetration_flat)
	return mini(effective_armor, maxi(0, raw_damage - 1))


static func parry_succeeds(parry_roll_milli: int, snapshot: Dictionary) -> bool:
	if parry_roll_milli < 0 or parry_roll_milli >= MAX_MILLI \
			or not snapshot_error(snapshot).is_empty():
		return false
	return parry_roll_milli < int(snapshot.parry_milli)


static func parry_roll_milli(commitment_key: String) -> int:
	if commitment_key.is_empty(): return -1
	var digest: PackedByteArray = (commitment_key + "|lane=PARRY").sha256_buffer()
	var u31 := ((int(digest[0]) & 0x7f) << 24) | (int(digest[1]) << 16) \
		| (int(digest[2]) << 8) | int(digest[3])
	return u31 % MAX_MILLI


static func commitment_fragment(snapshot: Dictionary) -> String:
	if not snapshot_error(snapshot).is_empty(): return ""
	return "defense=%s|base_evasion=%d|base_armor=%d|dodge=%d|equipment_armor=%d|parry=%d" % [
		RULESET_ID, int(snapshot.base_evasion_milli), int(snapshot.base_armor_flat),
		int(snapshot.dodge_milli), int(snapshot.equipment_armor_flat),
		int(snapshot.parry_milli)]


static func resolve_landed_hit(raw_damage: int, armor_penetration_flat: int,
		parry_roll_milli: int, snapshot: Dictionary) -> Dictionary:
	var reduction := armor_reduction(raw_damage, armor_penetration_flat, snapshot)
	if reduction < 0 or parry_roll_milli < 0 or parry_roll_milli >= MAX_MILLI:
		return {}
	var parried := parry_succeeds(parry_roll_milli, snapshot)
	return {
		"outcome": "PARRIED" if parried else "DAMAGED",
		"parry_chance_milli": int(snapshot.parry_milli),
		"parry_roll_milli": parry_roll_milli,
		"armor_reduction": 0 if parried else reduction,
		"final_damage": 0 if parried else maxi(1, raw_damage - reduction),
	}.duplicate(true)
