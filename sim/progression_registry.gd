class_name ProgressionRegistry
extends RefCounted

const ContentLoaderScript=preload("res://sim/json_content_loader.gd")
const CONTENT_PATH:="res://data/content/proficiencies.json"
static var _CONTENT:Dictionary=ContentLoaderScript.load_document(CONTENT_PATH)
static var RULESET_ID:String=str(_CONTENT.get("ruleset_id",""))
const SCHEMA_VERSION := 5
# A defeated enemy pays two *parallel* ledgers. Character XP is never spent or
# converted into training; the same kill independently creates this mastery pool.
const ENEMY_KILL_CHARACTER_XP := 100
const ENEMY_KILL_MASTERY_POOL := 100
# Read-only compatibility alias for old callers/tests. New gameplay must name
# the source explicitly as an enemy-kill reward.
const VICTORY_XP := ENEMY_KILL_CHARACTER_XP
const FOCUS_TOTAL := 100
static var SKILL_IDS:Array[String]=ContentLoaderScript.ordered_ids(
	_CONTENT.get("definitions",[]),"proficiency_id")
static var PROFICIENCY_IDS:Array[String]=SKILL_IDS.duplicate()
const TRAINING_MODES := ["FOCUS", "NORMAL", "OFF"]
const MODE_WEIGHTS := {"FOCUS":3, "NORMAL":1, "OFF":0}
const DEFAULT_MODES := {"SWORD":"OFF", "AXE":"OFF", "BLUNT":"OFF",
	"SPEAR":"OFF", "RANGED":"OFF", "UNARMED":"OFF"}
# Schema 1/2 compatibility only. New progression authority uses DEFAULT_MODES.
const DEFAULT_FOCUS := {"SWORD":30, "AXE":15, "BLUNT":15, "SPEAR":15,
	"RANGED":15, "UNARMED":10}
const MAX_XP := 1000000
const MAX_RANK := 20

static var DEFINITIONS:Dictionary=ContentLoaderScript.index_rows(
	_CONTENT.get("definitions",[]),"proficiency_id")


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


static func content_version()->String:
	return str(_CONTENT.get("content_version",""))


static func registry_error()->String:
	var document_error:=ContentLoaderScript.document_error(_CONTENT,"PROFICIENCIES",[
		"content_schema_version","content_version","content_type","ruleset_id","definitions"])
	if not document_error.is_empty():return document_error
	if RULESET_ID!="weapon-proficiency-v3":return "progression_ruleset_mismatch"
	var rows_error:=ContentLoaderScript.rows_error(_CONTENT.definitions,"proficiency_id")
	if not rows_error.is_empty():return rows_error
	if SKILL_IDS!=["SWORD","AXE","BLUNT","SPEAR","RANGED","UNARMED"]:
		return "progression_definition_order_invalid"
	for proficiency_id in SKILL_IDS:
		var row:Variant=DEFINITIONS.get(proficiency_id)
		if not row is Dictionary:return "invalid_progression_definition"
		var keys:Array=row.keys();keys.sort()
		if keys!=["description","label","proficiency_id"] \
				or str(row.proficiency_id)!=proficiency_id \
				or str(row.label).is_empty() or str(row.description).is_empty():
			return "invalid_progression_definition"
	return ""


static func focus_preset(proficiency_id: String) -> Dictionary:
	if proficiency_id not in PROFICIENCY_IDS: return {}
	var result := {}
	for id in PROFICIENCY_IDS: result[id] = 50 if id == proficiency_id else 10
	return result


static func initial_training_modes(equipped_proficiency_id: String) -> Dictionary:
	# New expeditions begin legibly: only the weapon currently held is training.
	# Later loadout changes deliberately do not call this function, preserving the
	# player's explicitly selected focus modes.
	var result := DEFAULT_MODES.duplicate(true)
	if equipped_proficiency_id in PROFICIENCY_IDS:
		result[equipped_proficiency_id] = "FOCUS"
	return result


static func training_modes_error(modes: Variant) -> String:
	if not modes is Dictionary: return "invalid_progression_modes_shape"
	var keys: Array = modes.keys(); keys.sort()
	var expected: Array = PROFICIENCY_IDS.duplicate(); expected.sort()
	if keys != expected: return "invalid_progression_modes_keys"
	for proficiency_id in PROFICIENCY_IDS:
		if modes[proficiency_id] not in TRAINING_MODES:
			return "invalid_progression_mode_value"
	return ""


static func next_training_mode(mode: String) -> String:
	match mode:
		"FOCUS": return "NORMAL"
		"NORMAL": return "OFF"
		_: return "FOCUS"


static func mode_label(mode: String) -> String:
	return {"FOCUS":"집중", "NORMAL":"보통", "OFF":"끄기"}.get(mode, "보통")


static func modes_from_legacy_focus(focus: Dictionary) -> Dictionary:
	var result := {}
	var dominant_id := PROFICIENCY_IDS[0]
	var dominant_weight := -1
	for proficiency_id in PROFICIENCY_IDS:
		var weight := int(focus.get(proficiency_id, 0))
		if weight > dominant_weight:
			dominant_id = proficiency_id
			dominant_weight = weight
	for proficiency_id in PROFICIENCY_IDS:
		var weight := int(focus.get(proficiency_id, 0))
		result[proficiency_id] = "FOCUS" if proficiency_id == dominant_id and weight > 0 \
			else ("NORMAL" if weight > 0 else "OFF")
	return result


static func enemy_kill_mastery_allocation(modes: Dictionary) -> Dictionary:
	var result := {}
	var total_weight := 0
	for proficiency_id in PROFICIENCY_IDS:
		result[proficiency_id] = 0
		total_weight += int(MODE_WEIGHTS.get(str(modes.get(proficiency_id, "OFF")), 0))
	if total_weight <= 0: return result
	var allocated := 0
	for proficiency_id in PROFICIENCY_IDS:
		var amount := int(ENEMY_KILL_MASTERY_POOL * int(MODE_WEIGHTS[str(modes[proficiency_id])]) / total_weight)
		result[proficiency_id] = amount
		allocated += amount
	var remainder := ENEMY_KILL_MASTERY_POOL - allocated
	var index := 0
	while remainder > 0:
		var proficiency_id: String = PROFICIENCY_IDS[index % PROFICIENCY_IDS.size()]
		if int(MODE_WEIGHTS[str(modes[proficiency_id])]) > 0:
			result[proficiency_id] = int(result[proficiency_id]) + 1
			remainder -= 1
		index += 1
	return result


static func victory_training_allocation(modes: Dictionary) -> Dictionary:
	# Compatibility spelling. Rewards are allocated per canonical enemy death.
	return enemy_kill_mastery_allocation(modes)


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
