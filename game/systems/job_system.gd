class_name JobSystem
extends RefCounted

var state: GameState
var content_registry: ContentRegistry
var inventory_system: InventorySystem
var proficiency_system: ProficiencySystem


func _init(
	p_state: GameState = null,
	p_registry: ContentRegistry = null,
	p_inventory: InventorySystem = null,
	p_proficiency: ProficiencySystem = null
) -> void:
	state = p_state
	content_registry = p_registry
	inventory_system = p_inventory
	proficiency_system = p_proficiency


func set_state(p_state: GameState) -> void:
	state = p_state


func advance_tick() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state == null:
		return events
	var slime_ids: Array = state.slimes.keys()
	slime_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for raw_slime_id: Variant in slime_ids:
		var slime := state.slimes[raw_slime_id] as SlimeState
		if slime == null:
			continue
		match slime.current_job.phase:
			JobRuntime.IDLE, JobRuntime.BLOCKED:
				events.append_array(_try_start_next_job(slime))
			JobRuntime.MOVING:
				_update_movement(slime)
			JobRuntime.WORKING:
				events.append_array(_update_work(slime))
			JobRuntime.BLOCKED_OUTPUT:
				events.append_array(_try_complete_job(slime))
	return events


func cancel_current_job(slime: SlimeState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if slime == null or slime.current_job == null:
		return events
	_release_worker(slime.current_job.target_id, slime.id)
	if slime.current_job.phase != JobRuntime.IDLE:
		events.append(_event(&"job_cancelled", [slime.id], {
			"job_id": str(slime.current_job.job_id),
			"cycle_id": slime.current_job.cycle_id,
		}))
	slime.current_job = JobRuntime.new(slime.id)
	return events


func _try_start_next_job(slime: SlimeState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if slime.routine.is_empty():
		slime.current_job = JobRuntime.new(slime.id)
		return events

	var step := slime.routine[slime.routine_cursor]
	var job := content_registry.get_job(step.job_id)
	var facility := state.facilities.get(step.target_id) as FacilityState
	if not step.enabled or job == null or facility == null or facility.locked or not facility.enabled:
		return _set_blocked(slime, step, &"TARGET_LOCKED")
	if not facility.active_worker_ids.has(slime.id) and not facility.has_open_worker_slot():
		return _set_blocked(slime, step, &"FACILITY_FULL")

	if not facility.active_worker_ids.has(slime.id):
		facility.active_worker_ids.append(slime.id)
	var runtime := JobRuntime.new(slime.id)
	runtime.job_id = job.id
	runtime.target_id = facility.id
	runtime.cycle_id = slime.next_cycle_number
	slime.next_cycle_number += 1
	runtime.duration_ticks = _calculate_duration_ticks(slime, job, facility)
	runtime.movement_ticks = job.movement_duration_ticks if slime.logical_location_id != facility.id else 0
	runtime.phase = JobRuntime.MOVING if runtime.movement_ticks > 0 else JobRuntime.WORKING
	runtime.reservation_id = StringName("reservation:%s:%d" % [str(slime.id), runtime.cycle_id])
	slime.current_job = runtime
	step.blocked_reason = &""
	events.append(_event(&"job_cycle_started", [slime.id, facility.id], {
		"job_id": str(job.id),
		"cycle_id": runtime.cycle_id,
		"duration_ticks": runtime.duration_ticks,
		"movement_ticks": runtime.movement_ticks,
	}))
	return events


func _update_movement(slime: SlimeState) -> void:
	var runtime := slime.current_job
	runtime.elapsed_ticks += 1
	if runtime.elapsed_ticks >= runtime.movement_ticks:
		slime.logical_location_id = runtime.target_id
		runtime.phase = JobRuntime.WORKING
		runtime.elapsed_ticks = 0


func _update_work(slime: SlimeState) -> Array[Dictionary]:
	if slime.current_job.completion_requested:
		return _try_complete_job(slime)
	slime.current_job.elapsed_ticks += 1
	if slime.current_job.elapsed_ticks >= slime.current_job.duration_ticks:
		return _try_complete_job(slime)
	return []


func _try_complete_job(slime: SlimeState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var runtime := slime.current_job
	var job := content_registry.get_job(runtime.job_id)
	if job == null:
		return cancel_current_job(slime)
	if not inventory_system.can_add(&"town_storage", job.outputs):
		runtime.phase = JobRuntime.BLOCKED_OUTPUT
		runtime.blocked_reason = &"STORAGE_FULL"
		runtime.elapsed_ticks = runtime.duration_ticks
		return events

	var add_result := inventory_system.try_add(&"town_storage", job.outputs)
	if not add_result.ok:
		return events
	for change: Dictionary in add_result.payload.get("changes", []):
		events.append(_event(&"inventory_changed", [&"town_storage"], change))

	var progress := slime.skill_memories.get(job.required_skill_id) as SkillProgress
	if progress != null:
		progress.total_cycles += 1
	events.append_array(proficiency_system.grant_xp(slime.id, job.required_skill_id, job.passive_xp))
	slime.division_meter += 1
	events.append(_event(&"job_cycle_completed", [slime.id, runtime.target_id], {
		"job_id": str(runtime.job_id),
		"cycle_id": runtime.cycle_id,
		"outputs": job.outputs.duplicate(true),
		"division_meter": slime.division_meter,
	}))

	_release_worker(runtime.target_id, slime.id)
	if not slime.routine.is_empty():
		slime.routine_cursor = (slime.routine_cursor + 1) % slime.routine.size()
	slime.current_job = JobRuntime.new(slime.id)
	return events


func _set_blocked(slime: SlimeState, step: RoutineStep, reason: StringName) -> Array[Dictionary]:
	var should_emit := slime.current_job.phase != JobRuntime.BLOCKED or slime.current_job.blocked_reason != reason
	var runtime := JobRuntime.new(slime.id)
	runtime.job_id = step.job_id
	runtime.target_id = step.target_id
	runtime.phase = JobRuntime.BLOCKED
	runtime.blocked_reason = reason
	slime.current_job = runtime
	step.blocked_reason = reason
	if not should_emit:
		return []
	return [_event(&"job_blocked", [slime.id, step.target_id], {"reason": str(reason)})]


func _calculate_duration_ticks(slime: SlimeState, job: JobDefinition, facility: FacilityState) -> int:
	var skill_multiplier := proficiency_system.get_speed_multiplier(slime.id, job.required_skill_id)
	var facility_definition := content_registry.get_facility(facility.definition_id)
	var facility_multiplier := 1.0
	if facility_definition != null:
		facility_multiplier = facility_definition.speed_multiplier_for_tier(facility.tier)
	var calculated := ceili(float(job.base_duration_ticks) / skill_multiplier / facility_multiplier)
	return maxi(calculated, job.min_duration_ticks)


func _release_worker(target_id: StringName, slime_id: StringName) -> void:
	var facility := state.facilities.get(target_id) as FacilityState
	if facility != null:
		facility.active_worker_ids.erase(slime_id)


func _event(type: StringName, entity_ids: Array[StringName], payload: Dictionary) -> Dictionary:
	return {
		"type": str(type),
		"simulation_tick": state.simulation_tick,
		"entity_ids": Array(entity_ids),
		"payload": payload,
	}
