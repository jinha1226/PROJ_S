class_name CoachingSystem
extends RefCounted

var state: GameState
var content_registry: ContentRegistry
var proficiency_system: ProficiencySystem


func _init(
	p_state: GameState = null,
	p_registry: ContentRegistry = null,
	p_proficiency: ProficiencySystem = null
) -> void:
	state = p_state
	content_registry = p_registry
	proficiency_system = p_proficiency


func set_state(p_state: GameState) -> void:
	state = p_state


func coach(slime_id: StringName, cycle_id: int, interaction_paused: bool) -> CommandResult:
	var slime := state.slimes.get(slime_id) as SlimeState
	if slime == null:
		return CommandResult.failure(&"SLIME_NOT_FOUND")
	var runtime := slime.current_job
	if runtime.phase != JobRuntime.WORKING:
		return CommandResult.failure(&"NOT_WORKING")
	if cycle_id != runtime.cycle_id:
		return CommandResult.failure(&"STALE_CYCLE")
	if runtime.coaching_used:
		return CommandResult.failure(&"COACHING_ALREADY_USED")
	if interaction_paused:
		return CommandResult.failure(&"INTERACTION_PAUSED")
	var job := content_registry.get_job(runtime.job_id)
	if job == null:
		return CommandResult.failure(&"JOB_NOT_FOUND")

	var remaining_ticks := runtime.duration_ticks - runtime.elapsed_ticks
	var result_type := &"NORMAL"
	var gained_xp := job.normal_coaching_xp
	if remaining_ticks <= job.perfect_window_ticks:
		result_type = &"PERFECT"
		gained_xp = job.perfect_coaching_xp
		runtime.completion_requested = true
	else:
		var progress_ticks := ceili(float(runtime.duration_ticks) * job.normal_coaching_progress_ratio)
		runtime.elapsed_ticks = mini(runtime.duration_ticks, runtime.elapsed_ticks + progress_ticks)
	runtime.coaching_used = true

	var events := proficiency_system.grant_xp(slime.id, job.required_skill_id, gained_xp)
	events.push_front({
		"type": "coaching_resolved",
		"simulation_tick": state.simulation_tick,
		"entity_ids": [str(slime.id)],
		"payload": {
			"result_type": str(result_type),
			"gained_xp": gained_xp,
			"cycle_id": runtime.cycle_id,
		},
	})
	return CommandResult.success({
		"result_type": str(result_type),
		"gained_xp": gained_xp,
		"events": events,
	})
