class_name AssignmentSystem
extends RefCounted

var state: GameState
var content_registry: ContentRegistry
var job_system: JobSystem


func _init(
	p_state: GameState = null,
	p_registry: ContentRegistry = null,
	p_job_system: JobSystem = null
) -> void:
	state = p_state
	content_registry = p_registry
	job_system = p_job_system


func set_state(p_state: GameState) -> void:
	state = p_state


func teach(slime_id: StringName, target_id: StringName, job_id: StringName) -> CommandResult:
	var slime := state.slimes.get(slime_id) as SlimeState
	if slime == null:
		return CommandResult.failure(&"SLIME_NOT_FOUND")
	var facility := state.facilities.get(target_id) as FacilityState
	if facility == null:
		return CommandResult.failure(&"TARGET_NOT_FOUND")
	if facility.locked or not facility.enabled or not content_registry.is_unlocked(state, target_id):
		return CommandResult.failure(&"TARGET_LOCKED")
	var job := content_registry.get_job(job_id)
	if job == null or not content_registry.is_unlocked(state, job_id):
		return CommandResult.failure(&"JOB_LOCKED")
	var facility_definition := content_registry.get_facility(facility.definition_id)
	if facility_definition == null or not _has_compatible_tag(job, facility_definition):
		return CommandResult.failure(&"INVALID_TARGET")
	if not content_registry.is_unlocked(state, job.required_skill_id):
		return CommandResult.failure(&"SKILL_LOCKED")

	var has_skill := slime.skill_memories.has(job.required_skill_id)
	if not has_skill and slime.skill_memories.size() >= slime.memory_capacity:
		return CommandResult.failure(&"MEMORY_FULL", {
			"new_skill_id": str(job.required_skill_id),
			"existing_skill_ids": slime.skill_memories.keys(),
		})

	var events := job_system.cancel_current_job(slime)
	if not has_skill:
		slime.skill_memories[job.required_skill_id] = SkillProgress.new(job.required_skill_id)
	slime.routine = [RoutineStep.new(job.required_skill_id, job.id, facility.id, 0)]
	slime.routine_cursor = 0
	events.append({
		"type": "assignment_changed",
		"simulation_tick": state.simulation_tick,
		"entity_ids": [str(slime.id), str(facility.id)],
		"payload": {"job_id": str(job.id), "skill_id": str(job.required_skill_id)},
	})
	return CommandResult.success({"events": events})


static func _has_compatible_tag(job: JobDefinition, facility: FacilityDefinition) -> bool:
	for allowed_tag: StringName in job.allowed_target_tags:
		if facility.tags.has(allowed_tag):
			return true
	return false
