class_name LivingWorldSimulator
extends RefCounted

const EnvironmentSystemScript = preload("res://sim/systems/environment_system.gd")
const DamageSystemScript = preload("res://sim/systems/damage_system.gd")
const RelationshipSystemScript = preload("res://sim/systems/relationship_system.gd")
const MovementSystemScript = preload("res://sim/systems/movement_system.gd")
const ExposureSystemScript = preload("res://sim/systems/exposure_system.gd")
const ActorCoordinatorScript = preload("res://sim/systems/actor_coordinator.gd")
const WeightedPathfinderScript = preload("res://sim/weighted_pathfinder.gd")
const WorldStateScript = preload("res://sim/world_state.gd")
const CommandScript = preload("res://sim/sim_command.gd")
const StepResultScript = preload("res://sim/sim_step_result.gd")
const PreviewScript = preload("res://sim/sim_action_preview.gd")
const TimingScript = preload("res://sim/action_timing_table.gd")
const ClockScript = preload("res://sim/world_clock.gd")

const MAX_SCHEDULE_OCCURRENCES_PER_STEP := 1024
const MAX_INT64 := 9223372036854775807
const MAX_WORLD_TIME := 9223372036854775707

var world
var damage
var environment
var relationships
var movement
var exposure
var actor_coordinator
var pathfinder


func _init(width: int, height: int, seed: int = 1) -> void:
	if not WorldStateScript.dimensions_error(width, height).is_empty():
		return
	world = WorldStateScript.new(width, height, seed)
	_rebuild_systems()


static func create(width: Variant, height: Variant, seed: int = 1):
	var width_is_integer: bool = width is int or (width is float and width == floor(width))
	var height_is_integer: bool = height is int or (height is float and height == floor(height))
	if not width_is_integer or not height_is_integer:
		return null
	var checked_width := int(width)
	var checked_height := int(height)
	if not WorldStateScript.dimensions_error(checked_width, checked_height).is_empty():
		return null
	return LivingWorldSimulator.new(checked_width, checked_height, seed)


func preview(command):
	return PreviewScript.new(_plan_action(command))


func step(command):
	var plan: Dictionary = _plan_action(command)
	if not plan["accepted"]:
		return StepResultScript.new(false, false, plan["reason"], [], {
			"processed_step_index": -1,
			"start_time": world.world_time, "end_time": world.world_time,
			"time_cost": 0, "speed_tier": "", "timeline": [], "root_event_id": -1,
		})
	# A scheduled handler is allowed to reject its complete frozen batch. Keep a
	# canonical pre-step image so such a rejection also rolls back the command,
	# earlier same-time cadence work, time, schedules, IDs and RNG.
	var rollback_snapshot: Dictionary = {}
	if world.encounter_lab != null:
		rollback_snapshot = world.snapshot()
		assert(not rollback_snapshot.is_empty(), "A settled Phase 3 lab must snapshot before stepping")
	var event_start: int = world.events.size()
	var timeline: Array = plan["timeline"].duplicate(true)
	var processed_step_index: int = world.step_index + 1
	var start_time: int = plan["start_time"]
	var end_time: int = plan["end_time"]
	world.begin_step(processed_step_index)
	var root_event = _resolve_command(command, plan)
	var immediate_ids: Array[int] = []
	for index in range(event_start, world.events.size()):
		immediate_ids.append(world.events[index].id)
	timeline[0]["event_ids"] = immediate_ids
	var marker_index := 1
	for planned_occurrence in plan["_occurrences"]:
		var entry: Dictionary = world.take_next_schedule()
		assert(entry["kind"] == planned_occurrence["kind"]
			and entry["due_time"] == planned_occurrence["due_time"]
			and entry["schedule_id"] == planned_occurrence["schedule_id"],
			"Live schedule diverged from the shared occurrence plan")
		world.world_time = int(entry["due_time"])
		assert(marker_index < timeline.size() - 1, "Actual schedule was absent from preview")
		var marker: Dictionary = timeline[marker_index]
		assert(marker["kind"] == entry["kind"] and marker["at_time"] == entry["due_time"]
			and marker["schedule_id"] == entry["schedule_id"], "Preview/actual schedule mismatch")
		var tick_event_start: int = world.events.size()
		var schedule_id_before: int = world.next_schedule_id
		if not _dispatch_schedule(entry):
			var restored = WorldStateScript.from_snapshot(rollback_snapshot)
			assert(restored != null, "Validated pre-step snapshot must restore")
			world = restored
			_rebuild_systems()
			return StepResultScript.new(false, false, "actor_tick_failed", [], {
				"processed_step_index": -1, "start_time": start_time,
				"end_time": start_time, "time_cost": 0, "speed_tier": "",
				"timeline": [], "root_event_id": -1})
		assert(world.next_schedule_id == schedule_id_before, "Phase 1 handlers cannot create logical schedules")
		var tick_ids: Array[int] = []
		for index in range(tick_event_start, world.events.size()):
			tick_ids.append(world.events[index].id)
		marker["event_ids"] = tick_ids
		timeline[marker_index] = marker
		if int(entry["repeat_interval"]) > 0:
			world.requeue_repeating(entry)
		marker_index += 1
	assert(marker_index == timeline.size() - 1, "Not all previewed schedules were processed")
	world.world_time = end_time
	world.finish_step()
	var result_events: Array = world.events_since(event_start)
	_assert_event_partition(result_events, timeline)
	return StepResultScript.new(true, true, "ok", result_events, {
		"processed_step_index": processed_step_index,
		"start_time": start_time, "end_time": end_time,
		"time_cost": plan["time_cost"], "speed_tier": plan["speed_tier"],
		"timeline": timeline, "root_event_id": root_event.id,
	})


func snapshot() -> Variant:
	return world.snapshot() if world != null else null


static func from_snapshot(data: Dictionary) -> LivingWorldSimulator:
	var restored_world = WorldStateScript.from_snapshot(data)
	if restored_world == null:
		return null
	# Construct an inert shell so a valid restore allocates/deserializes the world
	# exactly once inside WorldState.checked_decode_snapshot().
	var sim := LivingWorldSimulator.new(0, 0, 1)
	sim.world = restored_world
	sim._rebuild_systems()
	return sim


func _rebuild_systems() -> void:
	damage = DamageSystemScript.new(world)
	environment = EnvironmentSystemScript.new(world, damage)
	relationships = RelationshipSystemScript.new(world)
	movement = MovementSystemScript.new(world)
	exposure = ExposureSystemScript.new(world, movement)
	pathfinder = WeightedPathfinderScript.new(world, movement)
	actor_coordinator = ActorCoordinatorScript.new(world, movement, relationships, damage)


func assess_move(actor_id: int, destination: Vector2i):
	return movement.assess_move(actor_id, destination)


func sample_exposure(position: Vector2i):
	return exposure.sample(position)


func evaluate_exposure_for_entity(entity_id: int, position: Vector2i):
	return exposure.evaluate_for_entity(entity_id, position)


func assess_destination(entity_id: int, position: Vector2i):
	return exposure.assess_destination(entity_id, position)


func find_path(entity_id: int, goal: Vector2i) -> Dictionary:
	return pathfinder.find_path(entity_id, goal).duplicate(true)


func _plan_action(command) -> Dictionary:
	var rejection_reason := _validate_command(command)
	var start_time: int = world.world_time
	if not rejection_reason.is_empty():
		return _rejected_plan(rejection_reason, start_time)
	var move_terrain_id := ""
	if command.type == CommandScript.Type.MOVE:
		var move_assessment = movement.assess_move(command.actor_id, command.position)
		assert(move_assessment.accepted, "Validated MOVE must have an accepted traversal assessment")
		move_terrain_id = move_assessment.terrain_id
	var timing: Dictionary = TimingScript.timing_for(command, move_terrain_id)
	if timing.is_empty() or int(timing["time_cost"]) <= 0:
		return _rejected_plan("invalid_time_cost", start_time)
	var cost: int = timing["time_cost"]
	if world.step_index == MAX_INT64:
		return _rejected_plan("step_index_overflow", start_time)
	if start_time > MAX_WORLD_TIME - cost:
		return _rejected_plan("time_overflow", start_time)
	var end_time := start_time + cost
	var occurrence_plan: Dictionary = _enumerate_occurrences(end_time)
	if not occurrence_plan["reason"].is_empty():
		return _rejected_plan(occurrence_plan["reason"], start_time)
	var occurrences: Array = occurrence_plan["occurrences"]
	for occurrence in occurrences:
		if str(occurrence["kind"]) == "system.actor_tick" \
				and int(occurrence["due_time"]) > MAX_WORLD_TIME - 10000:
			return _rejected_plan("time_overflow", start_time)
	var per_tick_bound := _saturating_add(_saturating_multiply(world.tiles.size(), 4),
		_saturating_add(_saturating_multiply(world.entities.size(), 10), 1))
	var conservative_event_count := _saturating_add(4,
		_saturating_add(_saturating_multiply(world.tiles.size(), 2),
			_saturating_multiply(world.entities.size(), 2)))
	conservative_event_count = _saturating_add(conservative_event_count,
		_saturating_multiply(occurrences.size(), per_tick_bound))
	if command.type == CommandScript.Type.DISCHARGE:
		conservative_event_count = _saturating_add(conservative_event_count,
			_saturating_add(world.tiles.size(), _saturating_multiply(world.entities.size(), 2)))
	if not world.has_event_id_headroom(conservative_event_count):
		return _rejected_plan("event_id_overflow", start_time)
	var timeline := [_timeline_entry(
		"action.start", start_time, 0, command.actor_id, -1, -1,
		"timeline.action_start")]
	for occurrence in occurrences:
		var presentation := "timeline.actor_tick" if occurrence["kind"] == "system.actor_tick" else "timeline.environment_tick"
		timeline.append(_timeline_entry(
			str(occurrence["kind"]), int(occurrence["due_time"]),
			int(occurrence["due_time"]) - start_time, -1, int(occurrence["owner_id"]),
			int(occurrence["schedule_id"]), presentation))
	timeline.append(_timeline_entry(
		"actor.ready", end_time, cost, command.actor_id, -1, -1,
		"timeline.actor_ready"))
	return {
		"accepted": true, "reason": "ok", "processed_step_index": world.step_index + 1,
		"start_time": start_time, "end_time": end_time, "time_cost": cost,
		"speed_tier": timing["speed_tier"],
		"calendar_start": ClockScript.project(start_time),
		"calendar_end": ClockScript.project(end_time),
		"timeline": timeline, "_occurrences": occurrences.duplicate(true),
	}


func _rejected_plan(reason: String, current_time: int) -> Dictionary:
	return {
		"accepted": false, "reason": reason, "processed_step_index": -1,
		"start_time": current_time, "end_time": current_time, "time_cost": 0,
		"speed_tier": "", "calendar_start": ClockScript.project(current_time),
		"calendar_end": ClockScript.project(current_time), "timeline": [],
	}


func _enumerate_occurrences(end_time: int) -> Dictionary:
	var occurrences: Array = []
	for original in world.scheduled_entries:
		var entry: Dictionary = original.duplicate(true)
		while int(entry["due_time"]) <= end_time:
			occurrences.append(entry.duplicate(true))
			if occurrences.size() > MAX_SCHEDULE_OCCURRENCES_PER_STEP:
				return {"reason": "schedule_budget_exceeded", "occurrences": []}
			if int(entry["repeat_interval"]) <= 0:
				break
			if int(entry["due_time"]) > MAX_WORLD_TIME - int(entry["repeat_interval"]):
				return {"reason": "time_overflow", "occurrences": []}
			entry["due_time"] = int(entry["due_time"]) + int(entry["repeat_interval"])
	occurrences.sort_custom(func(a: Dictionary, b: Dictionary):
		if a["due_time"] != b["due_time"]:
			return a["due_time"] < b["due_time"]
		if a["priority"] != b["priority"]:
			return a["priority"] < b["priority"]
		return a["schedule_id"] < b["schedule_id"])
	return {"reason": "", "occurrences": occurrences}


func _timeline_entry(kind: String, at_time: int, offset: int, actor_id: int,
		owner_id: int, schedule_id: int, presentation_key: String) -> Dictionary:
	return {
		"kind": kind, "at_time": at_time, "offset": offset,
		"actor_id": actor_id, "owner_id": owner_id, "schedule_id": schedule_id,
		"presentation_key": presentation_key, "certainty": "CERTAIN", "event_ids": [],
	}


func _validate_command(command) -> String:
	if command == null:
		return "null_command"
	if not (command is SimCommand):
		return "invalid_command_object"
	if not (command.type is int):
		return "command_type_not_integer"
	if int(command.type) < int(CommandScript.Type.WAIT) or int(command.type) > int(CommandScript.Type.MOVE):
		return "unknown_command"
	if not (command.actor_id is int):
		return "actor_id_not_integer"
	if command.type == CommandScript.Type.MOVE:
		if not (command.power is int):
			return "power_not_integer"
		if command.power != 0:
			return "move_power_must_be_zero"
		var move_assessment = movement.assess_move(command.actor_id, command.position)
		return "" if move_assessment.accepted else move_assessment.reason
	if command.actor_id < -1:
		return "invalid_actor_id"
	if command.actor_id >= 0:
		if not world.entities.has(command.actor_id):
			return "actor_not_found"
		if not world.entities[command.actor_id].is_alive():
			return "actor_dead"
	if command.type == CommandScript.Type.WAIT:
		if not (command.wait_duration_time_units is int):
			return "wait_duration_not_integer"
		if command.wait_duration_time_units < 1 or command.wait_duration_time_units > TimingScript.MAX_WAIT_COST:
			return "wait_duration_out_of_range"
	else:
		if not (command.power is int):
			return "power_not_integer"
		if not world.in_bounds(command.position):
			return "out_of_bounds"
		if command.power < 1 or command.power > 100:
			return "power_out_of_range"
	return ""


func _resolve_command(command, plan: Dictionary):
	match command.type:
		CommandScript.Type.WAIT:
			return world.emit_event("action.wait", command.actor_id)
		CommandScript.Type.IGNITE:
			var action = world.emit_event("action.ignite", command.actor_id, -1, command.position, command.power)
			environment.ignite(command.position, command.power, action.id)
			return action
		CommandScript.Type.POUR_WATER:
			var action = world.emit_event("action.pour_water", command.actor_id, -1, command.position, command.power)
			environment.apply_water(command.position, command.power, action.id)
			return action
		CommandScript.Type.DISCHARGE:
			var action = world.emit_event("action.discharge", command.actor_id, -1, command.position, command.power)
			environment.discharge(command.position, command.power, action.id)
			return action
		CommandScript.Type.MOVE:
			return movement.commit_move(command.actor_id, command.position, int(plan["time_cost"]))
	assert(false, "Validated command type was not dispatched")
	return null


func _dispatch_schedule(entry: Dictionary) -> bool:
	match str(entry["kind"]):
		"system.environment_tick":
			environment.process_tick()
			return true
		"system.actor_tick":
			return actor_coordinator.process_tick()
		_:
			return false


func _assert_event_partition(result_events: Array, timeline: Array) -> void:
	var assigned: Dictionary = {}
	var assigned_in_order: Array[int] = []
	assert(not timeline.is_empty() and timeline.back()["kind"] == "actor.ready",
		"Timeline must end with actor.ready")
	assert(timeline.back()["event_ids"].is_empty(), "actor.ready cannot own events")
	for marker in timeline:
		for event_id in marker["event_ids"]:
			assert(not assigned.has(event_id), "Event assigned to multiple timeline markers")
			assigned[event_id] = true
			assigned_in_order.append(event_id)
	var expected_in_order: Array[int] = []
	for event in result_events:
		expected_in_order.append(event.id)
	assert(assigned.size() == result_events.size(), "Timeline contains non-step event IDs")
	assert(assigned_in_order == expected_in_order,
		"Timeline event partition must equal the step event sequence in order")


func _saturating_add(a: int, b: int) -> int:
	if a < 0 or b < 0 or a > MAX_INT64 - b:
		return MAX_INT64
	return a + b


func _saturating_multiply(a: int, b: int) -> int:
	if a < 0 or b < 0:
		return MAX_INT64
	if a == 0 or b == 0:
		return 0
	if a > MAX_INT64 / b:
		return MAX_INT64
	return a * b
