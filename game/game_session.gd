class_name GameSession
extends RefCounted

signal state_replaced(state: GameState)
signal interaction_pause_changed(paused: bool)
signal domain_event(event: Dictionary)

const CURRENT_SCHEMA_VERSION := 1
const CURRENT_CONTENT_VERSION := 1

var state: GameState
var simulation: Simulation
var content_registry: ContentRegistry
var inventory_system: InventorySystem
var proficiency_system: ProficiencySystem
var job_system: JobSystem
var assignment_system: AssignmentSystem
var coaching_system: CoachingSystem


func new_game() -> void:
	content_registry = ContentRegistry.new()
	state = _create_initial_state()
	_build_runtime_systems()
	state_replaced.emit(state)


func load_game(snapshot: Dictionary) -> CommandResult:
	var shape_errors := _validate_snapshot_shape(snapshot)
	if not shape_errors.is_empty():
		return CommandResult.failure(&"INVALID_SNAPSHOT", {"errors": Array(shape_errors)})

	var snapshot_schema := int(snapshot.get("schema_version", 0))
	if snapshot_schema > CURRENT_SCHEMA_VERSION:
		return CommandResult.failure(
			&"FUTURE_SCHEMA",
			{"snapshot_schema": snapshot_schema, "current_schema": CURRENT_SCHEMA_VERSION}
		)
	if snapshot_schema < CURRENT_SCHEMA_VERSION:
		return CommandResult.failure(
			&"MIGRATION_REQUIRED",
			{"snapshot_schema": snapshot_schema, "current_schema": CURRENT_SCHEMA_VERSION}
		)

	if content_registry == null:
		content_registry = ContentRegistry.new()
	var candidate := GameState.from_dict(snapshot)
	var errors := candidate.validate(content_registry)
	if not errors.is_empty():
		return CommandResult.failure(&"INVALID_STATE", {"errors": Array(errors)})

	state = candidate
	_build_runtime_systems()
	state_replaced.emit(state)
	return CommandResult.success()


func advance_ticks(tick_count: int) -> CommandResult:
	if simulation == null:
		return CommandResult.failure(&"SESSION_NOT_READY")
	var result := simulation.advance_ticks(tick_count)
	if result.ok:
		_publish_events(result.payload.get("events", []))
	return result


func teach(slime_id: StringName, target_id: StringName, job_id: StringName) -> CommandResult:
	if assignment_system == null:
		return CommandResult.failure(&"SESSION_NOT_READY")
	var result := assignment_system.teach(slime_id, target_id, job_id)
	if result.ok:
		_publish_events(result.payload.get("events", []))
	return result


func coach(slime_id: StringName, cycle_id: int) -> CommandResult:
	if coaching_system == null:
		return CommandResult.failure(&"SESSION_NOT_READY")
	var result := coaching_system.coach(slime_id, cycle_id, simulation.interaction_paused)
	if result.ok:
		_publish_events(result.payload.get("events", []))
	return result


func set_interaction_pause(paused: bool) -> void:
	if simulation == null:
		return
	simulation.set_interaction_pause(paused)
	interaction_pause_changed.emit(paused)


func create_snapshot() -> Dictionary:
	if state == null:
		return {}
	return state.to_dict()


func validate_state() -> PackedStringArray:
	if state == null:
		return PackedStringArray(["GameSession.state is null"])
	return state.validate(content_registry)


func _build_runtime_systems() -> void:
	inventory_system = InventorySystem.new(state)
	proficiency_system = ProficiencySystem.new(state, content_registry)
	job_system = JobSystem.new(state, content_registry, inventory_system, proficiency_system)
	assignment_system = AssignmentSystem.new(state, content_registry, job_system)
	coaching_system = CoachingSystem.new(state, content_registry, proficiency_system)
	simulation = Simulation.new(state, job_system)


func _publish_events(events: Variant) -> void:
	if typeof(events) != TYPE_ARRAY:
		return
	for event: Variant in events:
		if typeof(event) == TYPE_DICTIONARY:
			domain_event.emit(event)


func _create_initial_state() -> GameState:
	var initial := GameState.new()
	initial.schema_version = CURRENT_SCHEMA_VERSION
	initial.content_version = CURRENT_CONTENT_VERSION
	initial.region_id = &"first_clearing"
	initial.simulation_tick = 0
	initial.next_entity_number = 1
	initial.last_saved_unix = 0

	var slime_id := initial.allocate_slime_id()
	var slime := SlimeState.new(slime_id)
	slime.definition_id = &"basic_slime"
	slime.display_name = "Momo"
	slime.memory_capacity = 1
	slime.division_meter = 12
	slime.logical_location_id = &"habitat"
	slime.next_cycle_number = 1
	initial.slimes[slime_id] = slime

	var town_storage := InventoryState.new(&"town_storage")
	town_storage.amounts = {"wood": 0, "crystal": 0}
	town_storage.capacities = {"wood": 999, "crystal": 999}
	initial.inventories[&"town_storage"] = town_storage

	initial.facilities = {
		&"habitat": _facility_state(&"habitat", true, false, 0, 0, 4),
		&"forest": _facility_state(&"forest", true, false, 0, 1),
		&"crystal_mine": _facility_state(&"crystal_mine", false, true, 0, 1),
		&"fusion_pool": _facility_state(&"fusion_pool", false, true, 0, 0),
		&"ark": _facility_state(&"ark", true, false, 0, 1, 0, false),
		&"town_storage": _facility_state(&"town_storage", true, false, 0, 0),
	}

	initial.unlocked_content_ids = {
		"logging": true,
		"job_logging": true,
		"forest": true,
	}
	initial.goal_states = {
		"ark_stage_1": _goal_state("ark_stage_1", true),
		"ark_stage_2": _goal_state("ark_stage_2", false),
		"ark_stage_3": _goal_state("ark_stage_3", false),
	}
	return initial


static func _facility_state(
	facility_id: StringName,
	enabled: bool,
	locked: bool,
	tier: int,
	worker_slots: int,
	population_capacity: int = 0,
	repair_enabled: bool = false
) -> FacilityState:
	var result := FacilityState.new(facility_id)
	result.enabled = enabled
	result.locked = locked
	result.tier = tier
	result.worker_slots = worker_slots
	result.population_capacity = population_capacity
	result.repair_enabled = repair_enabled
	return result


static func _goal_state(goal_id: String, active: bool) -> Dictionary:
	return {
		"goal_id": goal_id,
		"current_progress": 0,
		"completed": false,
		"reward_claimed": false,
		"active": active,
	}


static func _validate_snapshot_shape(snapshot: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for field_name: String in ["slimes", "facilities", "inventories"]:
		if not snapshot.has(field_name) or typeof(snapshot[field_name]) != TYPE_DICTIONARY:
			errors.append("Snapshot.%s must be a Dictionary" % field_name)
	if not snapshot.has("schema_version"):
		errors.append("Snapshot.schema_version is missing")
	return errors
