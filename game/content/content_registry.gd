class_name ContentRegistry
extends RefCounted

var resources: Dictionary = {}
var skills: Dictionary = {}
var jobs: Dictionary = {}
var facilities: Dictionary = {}
var balance: BalanceDefinition


func _init() -> void:
	_build_m1_content()


func get_skill(skill_id: StringName) -> SkillDefinition:
	return skills.get(skill_id) as SkillDefinition


func get_job(job_id: StringName) -> JobDefinition:
	return jobs.get(job_id) as JobDefinition


func get_facility(facility_id: StringName) -> FacilityDefinition:
	return facilities.get(facility_id) as FacilityDefinition


func is_unlocked(state: GameState, content_id: StringName) -> bool:
	return bool(state.unlocked_content_ids.get(str(content_id), false))


func validate_state_content(state: GameState) -> PackedStringArray:
	var errors := PackedStringArray()
	for slime: SlimeState in state.slimes.values():
		for skill_id: Variant in slime.skill_memories.keys():
			if not skills.has(StringName(str(skill_id))):
				errors.append("Unknown skill content ID: %s" % str(skill_id))
		for step: RoutineStep in slime.routine:
			if not jobs.has(step.job_id):
				errors.append("Unknown job content ID: %s" % str(step.job_id))
	for facility_id: Variant in state.facilities.keys():
		if not facilities.has(StringName(str(facility_id))):
			errors.append("Unknown facility content ID: %s" % str(facility_id))
	return errors


func _build_m1_content() -> void:
	var wood := ResourceDefinition.new()
	wood.id = &"wood"
	wood.display_name_key = &"resource.wood"
	wood.stack_limit = 999
	resources[wood.id] = wood

	var crystal := ResourceDefinition.new()
	crystal.id = &"crystal"
	crystal.display_name_key = &"resource.crystal"
	crystal.stack_limit = 999
	resources[crystal.id] = crystal

	var logging := SkillDefinition.new()
	logging.id = &"logging"
	logging.display_name_key = &"skill.logging"
	logging.animation_key = &"logging"
	skills[logging.id] = logging

	var job_logging := JobDefinition.new()
	job_logging.id = &"job_logging"
	job_logging.display_name_key = &"job.logging"
	job_logging.required_skill_id = &"logging"
	job_logging.job_kind = &"PRODUCTION"
	job_logging.allowed_target_tags = [&"forest"]
	job_logging.base_duration_ticks = 30
	job_logging.movement_duration_ticks = 3
	job_logging.normal_coaching_progress_ratio = 0.25
	job_logging.perfect_window_ticks = 7
	job_logging.min_duration_ticks = 10
	job_logging.outputs = {"wood": 1}
	jobs[job_logging.id] = job_logging

	_register_facility(&"habitat", [&"habitat"], [0], 0)
	_register_facility(&"forest", [&"forest"], [1, 2])
	_register_facility(&"crystal_mine", [&"mine"], [1, 2])
	_register_facility(&"fusion_pool", [&"fusion"], [0])
	_register_facility(&"ark", [&"ark"], [1])
	_register_facility(&"town_storage", [&"storage"], [0])

	balance = BalanceDefinition.new()


func _register_facility(
	facility_id: StringName,
	tags: Array[StringName],
	worker_slots: Array[int],
	population_capacity: int = 0
) -> void:
	var definition := FacilityDefinition.new()
	definition.id = facility_id
	definition.display_name_key = StringName("facility.%s" % str(facility_id))
	definition.tags = tags
	definition.worker_slots_by_tier = worker_slots
	facilities[facility_id] = definition
