class_name ProgressionRegistry
extends RefCounted

const RULESET_ID := "weapon-proficiency-v1"
const SCHEMA_VERSION := 2
const VICTORY_XP := 100
const FOCUS_TOTAL := 100
const SKILL_IDS := ["SWORD", "AXE", "BLUNT", "SPEAR", "RANGED", "UNARMED"]
const PROFICIENCY_IDS := SKILL_IDS
const DEFAULT_FOCUS := {"SWORD":30, "AXE":15, "BLUNT":15, "SPEAR":15,
	"RANGED":15, "UNARMED":10}
const MAX_XP := 1000000
const MAX_RANK := 20

const DEFINITIONS := {
	"SWORD":{"label":"도검", "description":"베기검과 찌르기검의 명중과 피해를 높입니다."},
	"AXE":{"label":"도끼", "description":"주변 적까지 스치는 도끼의 명중과 피해를 높입니다."},
	"BLUNT":{"label":"둔기", "description":"충격과 기절을 노리는 둔기의 명중과 피해를 높입니다."},
	"SPEAR":{"label":"창", "description":"두 칸 거리까지 닿는 창의 명중과 피해를 높입니다."},
	"RANGED":{"label":"원거리", "description":"활과 쇠뇌의 명중과 피해를 함께 높입니다."},
	"UNARMED":{"label":"격투", "description":"빠른 맨손 공격의 명중과 피해를 높입니다."},
}


static func definition(proficiency_id: String) -> Dictionary:
	if proficiency_id not in PROFICIENCY_IDS: return {}
	var value: Dictionary = DEFINITIONS[proficiency_id].duplicate(true)
	value["proficiency_id"] = proficiency_id
	value["effect_id"] = "WEAPON_ACCURACY_AND_DAMAGE"
	# Transitional presentation fields for the current dossier. These are not
	# unlockable skills; the UI can replace them with rank progress directly.
	value["milestone_rank"] = MAX_RANK
	value["milestone_label"] = "명중·피해 숙련"
	return value


static func focus_preset(proficiency_id: String) -> Dictionary:
	if proficiency_id not in PROFICIENCY_IDS: return {}
	var result := {}
	for id in PROFICIENCY_IDS: result[id] = 50 if id == proficiency_id else 10
	return result


static func focus_error(focus: Variant) -> String:
	if not focus is Dictionary: return "invalid_progression_focus_shape"
	var keys: Array = focus.keys(); keys.sort()
	var expected: Array = PROFICIENCY_IDS.duplicate(); expected.sort()
	if keys != expected: return "invalid_progression_focus_keys"
	var total := 0
	for proficiency_id in PROFICIENCY_IDS:
		if not focus[proficiency_id] is int or int(focus[proficiency_id]) < 0 \
				or int(focus[proficiency_id]) > FOCUS_TOTAL:
			return "invalid_progression_focus_value"
		total += int(focus[proficiency_id])
	return "" if total == FOCUS_TOTAL else "invalid_progression_focus_total"


static func level_for_xp(xp_total: int) -> int:
	var level := 1
	while level < 100 and xp_total >= xp_floor_for_level(level + 1): level += 1
	return level


static func xp_floor_for_level(level: int) -> int:
	if level <= 1: return 0
	return 25 * (level - 1) * (level + 2)


static func skill_rank(training_total: int) -> int:
	var rank := 0
	while rank < MAX_RANK and training_total >= training_floor_for_rank(rank + 1): rank += 1
	return rank


static func training_floor_for_rank(rank: int) -> int:
	if rank <= 0: return 0
	return 25 * rank * (rank + 1)


static func proficiency_accuracy_bonus_milli(rank: int) -> int:
	return 15 * clampi(rank, 0, MAX_RANK)


static func proficiency_damage_bonus(rank: int) -> int:
	var bounded := clampi(rank, 0, MAX_RANK)
	return int((bounded + 1) / 2) if bounded > 0 else 0


# Compatibility helpers keep the currently shipped event validator readable
# until the weapon-aware event schema is connected. They do not define a
# MELEE/GUARD proficiency and never influence weapon attack time.
static func melee_power_bonus(_rank: int) -> int:
	return 0


static func guard_reduction_milli(_rank: int) -> int:
	return 250
