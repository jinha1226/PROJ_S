class_name ProtagonistProgression
extends RefCounted

const RegistryScript = preload("res://sim/progression_registry.gd")
const SCHEMA_VERSION := 3
const LEGACY_SCHEMA_VERSION := 1
const PRESET_SCHEMA_VERSION := 2

var schema_version := SCHEMA_VERSION
var xp_total := 0
var training_modes: Dictionary = RegistryScript.DEFAULT_MODES.duplicate(true)
var skill_training: Dictionary = _empty_training()
var processed_victory_event_ids: Array[int] = []


func award_victory(event_id: int) -> bool:
	if event_id <= 0 or event_id in processed_victory_event_ids: return false
	if xp_total > RegistryScript.MAX_XP - RegistryScript.VICTORY_XP: return false
	if not RegistryScript.training_modes_error(training_modes).is_empty(): return false
	xp_total += RegistryScript.VICTORY_XP
	var allocation := RegistryScript.victory_training_allocation(training_modes)
	for proficiency_id in RegistryScript.PROFICIENCY_IDS:
		skill_training[proficiency_id] = int(skill_training[proficiency_id]) \
			+ int(allocation[proficiency_id])
	processed_victory_event_ids.append(event_id)
	return true


func set_training_mode(proficiency_id: String, mode: String) -> bool:
	if proficiency_id not in RegistryScript.PROFICIENCY_IDS \
			or mode not in RegistryScript.TRAINING_MODES \
			or str(training_modes.get(proficiency_id, "")) == mode:
		return false
	training_modes[proficiency_id] = mode
	return true


func rank(proficiency_id: String) -> int:
	if proficiency_id not in RegistryScript.PROFICIENCY_IDS: return 0
	return RegistryScript.skill_rank(int(skill_training.get(proficiency_id, 0)))


func bonuses(proficiency_id: String) -> Dictionary:
	var current_rank := rank(proficiency_id)
	return {"proficiency_id": proficiency_id, "rank": current_rank,
		"accuracy_milli": RegistryScript.proficiency_accuracy_bonus_milli(current_rank),
		"damage": RegistryScript.proficiency_damage_bonus(current_rank)}.duplicate(true)


func to_dict() -> Dictionary:
	var mode_rows: Array = []
	var training_rows: Array = []
	for proficiency_id in RegistryScript.PROFICIENCY_IDS:
		mode_rows.append({"skill_id":proficiency_id, "mode":str(training_modes[proficiency_id])})
		training_rows.append({"skill_id":proficiency_id,
			"training_total":int(skill_training[proficiency_id])})
	return {"schema_version":schema_version, "xp_total":xp_total,
		"training_modes":mode_rows, "skill_training":training_rows,
		"processed_victory_event_ids":processed_victory_event_ids.map(func(id): return str(id))}


static func from_dict(row: Dictionary):
	var value = load("res://sim/protagonist_progression.gd").new()
	value.schema_version = SCHEMA_VERSION
	value.xp_total = int(row.get("xp_total", 0))
	value.processed_victory_event_ids.clear()
	for event_id in row.get("processed_victory_event_ids", []):
		value.processed_victory_event_ids.append(int(str(event_id)))
	if int(row.get("schema_version", 0)) in [LEGACY_SCHEMA_VERSION, PRESET_SCHEMA_VERSION]:
		_migrate_legacy_rows(value, row)
		return value
	value.training_modes.clear()
	for mode_row in row.training_modes:
		value.training_modes[str(mode_row.skill_id)] = str(mode_row.mode)
	value.skill_training.clear()
	for training_row in row.skill_training:
		value.skill_training[str(training_row.skill_id)] = int(training_row.training_total)
	return value


static func wire_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_progression_shape"
	var keys: Array = row.keys(); keys.sort()
	var current_keys := ["processed_victory_event_ids", "schema_version", "skill_training",
		"training_modes", "xp_total"]
	var legacy_keys := ["processed_victory_event_ids", "schema_version", "skill_training",
		"training_focus", "xp_total"]
	if keys != current_keys and keys != legacy_keys:
		return "invalid_progression_keys"
	if not _integer(row.schema_version) or int(row.schema_version) not in [LEGACY_SCHEMA_VERSION,
			PRESET_SCHEMA_VERSION, SCHEMA_VERSION]:
		return "unsupported_progression_schema"
	if int(row.schema_version) == SCHEMA_VERSION and keys != current_keys:
		return "invalid_progression_keys"
	if int(row.schema_version) != SCHEMA_VERSION and keys != legacy_keys:
		return "invalid_progression_keys"
	if not _integer(row.xp_total) or int(row.xp_total) < 0 or int(row.xp_total) > RegistryScript.MAX_XP:
		return "invalid_progression_xp"
	var expected_ids: Array = ["MELEE", "GUARD", "EXPLORATION"] \
		if int(row.schema_version) == LEGACY_SCHEMA_VERSION else RegistryScript.PROFICIENCY_IDS
	var authority_rows: Variant = row.get("training_modes") if int(row.schema_version) == SCHEMA_VERSION \
		else row.get("training_focus")
	if not authority_rows is Array or authority_rows.size() != expected_ids.size():
		return "invalid_progression_modes_shape" if int(row.schema_version) == SCHEMA_VERSION \
			else "invalid_progression_focus_shape"
	if not row.skill_training is Array or row.skill_training.size() != expected_ids.size():
		return "invalid_progression_training_shape"
	var focus := {}
	var modes := {}
	for index in range(expected_ids.size()):
		var expected_id: String = expected_ids[index]
		var focus_row: Variant = authority_rows[index]
		var training_row: Variant = row.skill_training[index]
		if not focus_row is Dictionary or focus_row.keys().size() != 2 \
				or str(focus_row.get("skill_id", "")) != expected_id:
			return "invalid_progression_mode_row" if int(row.schema_version) == SCHEMA_VERSION \
				else "invalid_progression_focus_row"
		if not training_row is Dictionary or training_row.keys().size() != 2 \
				or not training_row.has_all(["skill_id", "training_total"]) \
				or str(training_row.skill_id) != expected_id:
			return "invalid_progression_training_row"
		if int(row.schema_version) == SCHEMA_VERSION:
			if not focus_row.has("mode") or focus_row.mode not in RegistryScript.TRAINING_MODES:
				return "invalid_progression_mode_value"
			modes[expected_id] = str(focus_row.mode)
		else:
			if not focus_row.has("weight") or not _integer(focus_row.weight):
				return "invalid_progression_focus_value"
			focus[expected_id] = int(focus_row.weight)
		if not _integer(training_row.training_total) or int(training_row.training_total) < 0 \
				or int(training_row.training_total) > RegistryScript.MAX_XP:
			return "invalid_progression_training_value"
	if int(row.schema_version) == SCHEMA_VERSION:
		var modes_error := RegistryScript.training_modes_error(modes)
		if not modes_error.is_empty(): return modes_error
	elif int(row.schema_version) == PRESET_SCHEMA_VERSION:
		var focus_error := RegistryScript.focus_error(focus)
		if not focus_error.is_empty(): return focus_error
	else:
		var legacy_total := 0
		for weight in focus.values():
			if int(weight) < 0 or int(weight) > RegistryScript.FOCUS_TOTAL:
				return "invalid_progression_focus_value"
			legacy_total += int(weight)
		if legacy_total != RegistryScript.FOCUS_TOTAL: return "invalid_progression_focus_total"
	if not row.processed_victory_event_ids is Array: return "invalid_progression_victory_ids"
	var previous := 0
	for raw_id in row.processed_victory_event_ids:
		if not raw_id is String or not raw_id.is_valid_int(): return "noncanonical_progression_victory_id"
		var event_id := int(raw_id)
		if str(event_id) != raw_id or event_id <= previous: return "invalid_progression_victory_ids"
		previous = event_id
	return ""


static func _empty_training() -> Dictionary:
	var result := {}
	for proficiency_id in RegistryScript.PROFICIENCY_IDS: result[proficiency_id] = 0
	return result


static func _migrate_legacy_rows(value, row: Dictionary) -> void:
	var legacy_focus := RegistryScript.DEFAULT_FOCUS.duplicate(true)
	if int(row.get("schema_version", 0)) == PRESET_SCHEMA_VERSION:
		legacy_focus.clear()
		for focus_row in row.get("training_focus", []):
			legacy_focus[str(focus_row.get("skill_id", ""))] = int(focus_row.get("weight", 0))
	value.training_modes = RegistryScript.modes_from_legacy_focus(legacy_focus)
	value.skill_training = _empty_training()
	for training_row in row.get("skill_training", []):
		var skill_id := str(training_row.get("skill_id", ""))
		if skill_id in RegistryScript.PROFICIENCY_IDS:
			value.skill_training[skill_id] = int(training_row.get("training_total", 0))
		elif skill_id == "MELEE":
			value.skill_training.SWORD = int(training_row.get("training_total", 0))


static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))
