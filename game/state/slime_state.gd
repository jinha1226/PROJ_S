class_name SlimeState
extends RefCounted

var id: StringName = &""
var definition_id: StringName = &"basic_slime"
var display_name: String = ""
var skill_memories: Dictionary = {}
var memory_capacity: int = 1
var routine: Array = []
var routine_cursor: int = 0
var current_job: Dictionary = {}
var division_meter: int = 0
var generation: int = 0
var parent_ids: Array[StringName] = []
var fusion_tier: int = 0
var logical_location_id: StringName = &"habitat"
var next_cycle_number: int = 1


func _init(p_id: StringName = &"") -> void:
	id = p_id


func to_dict() -> Dictionary:
	var serialized_skills: Dictionary = {}
	for skill_key: Variant in skill_memories.keys():
		var progress: Variant = skill_memories[skill_key]
		if progress is SkillProgress:
			serialized_skills[str(skill_key)] = progress.to_dict()
		elif typeof(progress) == TYPE_DICTIONARY:
			serialized_skills[str(skill_key)] = progress.duplicate(true)

	var serialized_parents: Array[String] = []
	for parent_id: StringName in parent_ids:
		serialized_parents.append(str(parent_id))

	return {
		"id": str(id),
		"definition_id": str(definition_id),
		"display_name": display_name,
		"skill_memories": serialized_skills,
		"memory_capacity": memory_capacity,
		"routine": routine.duplicate(true),
		"routine_cursor": routine_cursor,
		"current_job": current_job.duplicate(true),
		"division_meter": division_meter,
		"generation": generation,
		"parent_ids": serialized_parents,
		"fusion_tier": fusion_tier,
		"logical_location_id": str(logical_location_id),
		"next_cycle_number": next_cycle_number,
	}


static func from_dict(data: Dictionary) -> SlimeState:
	var state := SlimeState.new(StringName(str(data.get("id", ""))))
	state.definition_id = StringName(str(data.get("definition_id", "basic_slime")))
	state.display_name = str(data.get("display_name", ""))
	state.memory_capacity = int(data.get("memory_capacity", 1))
	state.routine = _array_copy(data.get("routine", []))
	state.routine_cursor = int(data.get("routine_cursor", 0))
	state.current_job = _dictionary_copy(data.get("current_job", {}))
	state.division_meter = int(data.get("division_meter", 0))
	state.generation = int(data.get("generation", 0))
	state.fusion_tier = int(data.get("fusion_tier", 0))
	state.logical_location_id = StringName(str(data.get("logical_location_id", "habitat")))
	state.next_cycle_number = int(data.get("next_cycle_number", 1))

	var raw_skills: Variant = data.get("skill_memories", data.get("skills", {}))
	if typeof(raw_skills) == TYPE_DICTIONARY:
		for skill_key: Variant in raw_skills.keys():
			var skill_data: Variant = raw_skills[skill_key]
			if typeof(skill_data) != TYPE_DICTIONARY:
				continue
			var normalized: Dictionary = skill_data.duplicate(true)
			normalized["skill_id"] = str(normalized.get("skill_id", skill_key))
			state.skill_memories[StringName(str(skill_key))] = SkillProgress.from_dict(normalized)

	var raw_parents: Variant = data.get("parent_ids", [])
	if typeof(raw_parents) == TYPE_ARRAY:
		for parent_id: Variant in raw_parents:
			state.parent_ids.append(StringName(str(parent_id)))
	return state


func clone_state() -> SlimeState:
	return SlimeState.from_dict(to_dict())


func validate(content_registry: Variant = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("SlimeState.id is empty")
	if definition_id == &"":
		errors.append("SlimeState.definition_id is empty")
	if memory_capacity < 1 or memory_capacity > 3:
		errors.append("SlimeState.memory_capacity must be between 1 and 3")
	if skill_memories.size() > memory_capacity:
		errors.append("SlimeState skill count exceeds memory capacity")
	if routine.size() > memory_capacity:
		errors.append("SlimeState routine count exceeds memory capacity")
	if division_meter < 0:
		errors.append("SlimeState.division_meter must not be negative")
	if generation < 0:
		errors.append("SlimeState.generation must not be negative")
	if fusion_tier < 0:
		errors.append("SlimeState.fusion_tier must not be negative")
	if next_cycle_number < 1:
		errors.append("SlimeState.next_cycle_number must be at least 1")

	for skill_key: Variant in skill_memories.keys():
		var progress: Variant = skill_memories[skill_key]
		if not progress is SkillProgress:
			errors.append("SlimeState skill %s is not SkillProgress" % str(skill_key))
			continue
		if progress.skill_id != StringName(str(skill_key)):
			errors.append("SlimeState skill key does not match SkillProgress.skill_id")
		for error: String in progress.validate(content_registry):
			errors.append("%s: %s" % [str(id), error])

	for step: Variant in routine:
		if typeof(step) != TYPE_DICTIONARY:
			errors.append("SlimeState routine step must be a Dictionary during M0")
			continue
		var skill_id := StringName(str(step.get("skill_id", "")))
		if skill_id != &"" and not skill_memories.has(skill_id):
			errors.append("SlimeState routine references an unowned skill: %s" % str(skill_id))

	if routine.is_empty():
		if routine_cursor != 0:
			errors.append("SlimeState.routine_cursor must be 0 for an empty routine")
	elif routine_cursor < 0 or routine_cursor >= routine.size():
		errors.append("SlimeState.routine_cursor is outside the routine")

	if not current_job.is_empty():
		var current_slime_id := StringName(str(current_job.get("slime_id", "")))
		if current_slime_id != id:
			errors.append("SlimeState.current_job references another slime")
	return errors


static func _array_copy(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)


static func _dictionary_copy(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)
