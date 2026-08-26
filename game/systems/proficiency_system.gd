class_name ProficiencySystem
extends RefCounted

var state: GameState
var content_registry: ContentRegistry


func _init(p_state: GameState = null, p_registry: ContentRegistry = null) -> void:
	state = p_state
	content_registry = p_registry


func set_state(p_state: GameState) -> void:
	state = p_state


func grant_xp(slime_id: StringName, skill_id: StringName, amount: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if amount <= 0 or state == null:
		return events
	var slime := state.slimes.get(slime_id) as SlimeState
	if slime == null:
		return events
	var progress := slime.skill_memories.get(skill_id) as SkillProgress
	var definition := content_registry.get_skill(skill_id)
	if progress == null or definition == null or progress.level >= 5:
		return events

	var old_level := progress.level
	progress.xp += amount
	while progress.level < 5:
		var requirement_index := progress.level - 1
		if requirement_index >= definition.level_xp_requirements.size():
			break
		var requirement := definition.level_xp_requirements[requirement_index]
		if progress.xp < requirement:
			break
		progress.xp -= requirement
		progress.level += 1
	if progress.level >= 5:
		progress.level = 5
		progress.xp = 0

	if progress.level != old_level:
		events.append(_event(&"proficiency_changed", [slime_id], {
			"skill_id": str(skill_id),
			"old_level": old_level,
			"new_level": progress.level,
			"xp": progress.xp,
		}))
	return events


func get_speed_multiplier(slime_id: StringName, skill_id: StringName) -> float:
	if state == null:
		return 1.0
	var slime := state.slimes.get(slime_id) as SlimeState
	var definition := content_registry.get_skill(skill_id)
	if slime == null or definition == null:
		return 1.0
	var progress := slime.skill_memories.get(skill_id) as SkillProgress
	if progress == null or definition.level_speed_multipliers.is_empty():
		return 1.0
	var index := clampi(progress.level - 1, 0, definition.level_speed_multipliers.size() - 1)
	return definition.level_speed_multipliers[index]


func _event(type: StringName, entity_ids: Array[StringName], payload: Dictionary) -> Dictionary:
	return {
		"type": str(type),
		"simulation_tick": state.simulation_tick,
		"entity_ids": Array(entity_ids),
		"payload": payload,
	}
