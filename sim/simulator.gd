class_name LivingWorldSimulator
extends RefCounted

const EnvironmentSystemScript = preload("res://sim/systems/environment_system.gd")
const DamageSystemScript = preload("res://sim/systems/damage_system.gd")
const RelationshipSystemScript = preload("res://sim/systems/relationship_system.gd")
const MovementSystemScript = preload("res://sim/systems/movement_system.gd")
const ExposureSystemScript = preload("res://sim/systems/exposure_system.gd")
const StatusLifecycleSystemScript = preload("res://sim/systems/status_lifecycle_system.gd")
const ActorCoordinatorScript = preload("res://sim/systems/actor_coordinator.gd")
const PartyCoordinatorScript = preload("res://sim/systems/party_encounter_coordinator.gd")
const PartyActionScript = preload("res://sim/party_action_command.gd")
const PartyRequestScript = preload("res://sim/party_turn_request.gd")
const PartyPlanScript = preload("res://sim/party_turn_plan.gd")
const PartyMoraleSystemScript = preload("res://sim/systems/party_morale_system.gd")
const PartyEmotionSystemScript = preload("res://sim/systems/party_emotion_system.gd")
const PartyMemorySystemScript = preload("res://sim/systems/party_memory_system.gd")
const MeleeScript = preload("res://sim/systems/melee_combat_system.gd")
const WeightedPathfinderScript = preload("res://sim/weighted_pathfinder.gd")
const OpeningEventSystemScript = preload("res://sim/systems/opening_event_system.gd")
const WorldStateScript = preload("res://sim/world_state.gd")
const WorldItemOperationsScript = preload("res://sim/world_item_operations.gd")
const CommandScript = preload("res://sim/sim_command.gd")
const StepResultScript = preload("res://sim/sim_step_result.gd")
const PreviewScript = preload("res://sim/sim_action_preview.gd")
const TimingScript = preload("res://sim/action_timing_table.gd")
const ClockScript = preload("res://sim/world_clock.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")

const MAX_SCHEDULE_OCCURRENCES_PER_STEP := 1024
const MAX_INT64 := 9223372036854775807
const MAX_WORLD_TIME := 9223372036854775707

var world
var damage
var environment
var relationships
var movement
var exposure
var status_lifecycle
var actor_coordinator
var party_coordinator
var pathfinder
var melee
var opening_event


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


func step(command, supplied_rollback_memento: Variant = null):
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
	var rollback_value: Variant = supplied_rollback_memento \
		if supplied_rollback_memento != null else world.rollback_memento()
	if not rollback_value is Dictionary or rollback_value.is_empty():
		return StepResultScript.new(false, false, "snapshot_unavailable")
	if supplied_rollback_memento != null \
			and not world.rollback_memento_is_current(rollback_value):
		return StepResultScript.new(false, false, "snapshot_unavailable")
	var rollback_memento: Dictionary = rollback_value
	var event_start: int = world.events.size()
	var timeline: Array = plan["timeline"].duplicate(true)
	var processed_step_index: int = int(plan["processed_step_index"])
	var start_time: int = plan["start_time"]
	var end_time: int = plan["end_time"]
	world.begin_step(processed_step_index)
	var root_event = _resolve_command(command, plan, processed_step_index)
	if root_event == null or (world.party_encounter != null and not party_coordinator.reconcile_liveness()):
		var failed_restore = WorldStateScript.from_rollback_memento(rollback_memento)
		if failed_restore != null:
			world = failed_restore
			_rebuild_systems()
		return StepResultScript.new(false, false, "command_resolution_failed")
	if world.party_encounter != null and world.party_encounter.safe_phase in ["GROUPED", "GROUPED_COMPLETE"]:
		var party_state = world.party_encounter
		party_state.group_anchor = world.entities[party_state.protagonist_id].position
		for member_id in party_state.party_member_ids:
			if party_state.member(member_id).presence == "GROUPED": world.entities[member_id].position = party_state.group_anchor
	if world.party_encounter != null \
			and not PartyEmotionSystemScript.commit_batch(world,
				world.events_since(event_start)):
		var emotion_restore = WorldStateScript.from_rollback_memento(rollback_memento)
		if emotion_restore != null:
			world = emotion_restore
			_rebuild_systems()
		return StepResultScript.new(false, false, "party_emotion_failed")
	if world.party_encounter != null \
			and not PartyMemorySystemScript.commit_batch(world,
				world.events_since(event_start)):
		var memory_restore = WorldStateScript.from_rollback_memento(rollback_memento)
		if memory_restore != null:
			world = memory_restore
			_rebuild_systems()
		return StepResultScript.new(false, false, "party_memory_failed")
	if world.party_encounter != null \
			and not PartyMoraleSystemScript.commit_batch(world, world.events_since(event_start)):
		var morale_restore = WorldStateScript.from_rollback_memento(rollback_memento)
		if morale_restore != null:
			world = morale_restore
			_rebuild_systems()
		return StepResultScript.new(false, false, "party_morale_failed")
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
		if not _dispatch_schedule(entry, processed_step_index):
			var restored = WorldStateScript.from_rollback_memento(rollback_memento)
			assert(restored != null, "Validated pre-step snapshot must restore")
			world = restored
			_rebuild_systems()
			return StepResultScript.new(false, false, "actor_tick_failed", [], {
				"processed_step_index": -1, "start_time": start_time,
				"end_time": start_time, "time_cost": 0, "speed_tier": "",
				"timeline": [], "root_event_id": -1})
		if world.party_encounter != null and not PartyEmotionSystemScript.commit_batch(
				world, world.events_since(tick_event_start), false):
			var emotion_restore = WorldStateScript.from_rollback_memento(rollback_memento)
			if emotion_restore != null:
				world = emotion_restore
				_rebuild_systems()
			return StepResultScript.new(false, false, "party_emotion_failed")
		if world.party_encounter != null and not PartyMemorySystemScript.commit_batch(
				world, world.events_since(tick_event_start)):
			var memory_restore = WorldStateScript.from_rollback_memento(rollback_memento)
			if memory_restore != null:
				world = memory_restore
				_rebuild_systems()
			return StepResultScript.new(false, false, "party_memory_failed")
		if world.party_encounter != null and not PartyMoraleSystemScript.commit_batch(
				world, world.events_since(tick_event_start), false):
			var morale_restore = WorldStateScript.from_rollback_memento(rollback_memento)
			if morale_restore != null:
				world = morale_restore
				_rebuild_systems()
			return StepResultScript.new(false, false, "party_morale_failed")
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
	_reconcile_expedition_cycle()
	world.finish_step()
	# Live turns use a bounded tail/surface postcondition. Full ledger validation
	# remains mandatory at save/load/restore boundaries; re-running it here made
	# append-only exploration slower as the journal grew.
	if not world.runtime_step_postcondition_error(event_start).is_empty():
		var semantic_restore = WorldStateScript.from_rollback_memento(rollback_memento)
		assert(semantic_restore != null, "Validated pre-step memento must restore")
		world = semantic_restore
		_rebuild_systems()
		return StepResultScript.new(false, false, "step_semantic_failure", [], {
			"processed_step_index": -1, "start_time": start_time,
			"end_time": start_time, "time_cost": 0, "speed_tier": "",
			"timeline": [], "root_event_id": -1})
	var result_events: Array = world.events_since(event_start)
	_assert_event_partition(result_events, timeline)
	var step_result=StepResultScript.new(true, true, "ok", result_events, {
		"processed_step_index": processed_step_index,
		"start_time": start_time, "end_time": end_time,
		"time_cost": plan["time_cost"], "speed_tier": plan["speed_tier"],
		"timeline": timeline, "root_event_id": root_event.id,
	})
	return step_result


func snapshot() -> Variant:
	return world.snapshot() if world != null else null


func capture_rollback_memento(validate_state: bool = true) -> Variant:
	return world.rollback_memento(validate_state) if world != null else null


func restore_rollback_memento(value: Variant) -> bool:
	var restored = WorldStateScript.from_rollback_memento(value)
	if restored == null:
		return false
	world = restored
	_rebuild_systems()
	return true


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
	status_lifecycle = StatusLifecycleSystemScript.new(world, damage)
	pathfinder = WeightedPathfinderScript.new(world, movement)
	opening_event = OpeningEventSystemScript.new(world, movement, pathfinder, relationships)
	actor_coordinator = ActorCoordinatorScript.new(world, movement, relationships, damage)
	party_coordinator = PartyCoordinatorScript.new(world, movement, damage, pathfinder,
		environment, exposure, opening_event)
	melee = MeleeScript.new(world, damage)


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


func preview_deployment(preset_id: String, companion_ids: Array) -> Dictionary:
	return party_coordinator.preview_deployment(preset_id, companion_ids).duplicate(true)


func deploy_party(plan: Variant):
	if not plan is Dictionary:
		return StepResultScript.new(false, false, "invalid_deployment_plan")
	var processed_step_index: int = _next_processed_step_index()
	if processed_step_index < 0:
		return StepResultScript.new(false, false, "step_index_overflow")
	var plan_copy: Dictionary = plan.duplicate(true)
	var plan_error: String = party_coordinator.deployment_commit_error(plan_copy)
	if not plan_error.is_empty():
		return StepResultScript.new(false, false, plan_error)
	var rollback_value: Variant = world.snapshot()
	if not rollback_value is Dictionary or rollback_value.is_empty():
		return StepResultScript.new(false, false, "party_snapshot_unavailable")
	var rollback: Dictionary = rollback_value
	world.begin_step(processed_step_index)
	var result = party_coordinator.commit_prevalidated_deployment(plan_copy, processed_step_index)
	if result is Dictionary or not result.accepted:
		world = WorldStateScript.from_snapshot(rollback)
		_rebuild_systems()
		return StepResultScript.new(false, false, str(result.get("reason", "deployment_failed")))
	world.finish_step()
	if not world.world_state_error().is_empty():
		world = WorldStateScript.from_snapshot(rollback)
		_rebuild_systems()
		return StepResultScript.new(false, false, "deployment_semantic_failure")
	return result


func deploy_solo_party():
	# Trusted one-member product facade: build the authoritative empty-companion
	# deployment and commit it in one call. External deployment plans still use
	# `deploy_party` and its fingerprint/recompute/tamper checks above.
	var state=world.party_encounter if world!=null else null
	if state==null or state.party_member_ids!=[state.protagonist_id] \
			or state.active_party_member_ids!=[state.protagonist_id]:
		return StepResultScript.new(false,false,"invalid_companion_ids")
	var processed_step_index:int=_next_processed_step_index()
	if processed_step_index<0:return StepResultScript.new(false,false,"step_index_overflow")
	var authoritative:Dictionary=party_coordinator.preview_deployment("LINE",[],false)
	if not bool(authoritative.get("accepted",false)):
		return StepResultScript.new(false,false,str(authoritative.get("reason","deployment_failed")))
	if not world.runtime_party_health_error().is_empty():
		return StepResultScript.new(false,false,"party_snapshot_unavailable")
	var rollback_value:Variant=world.rollback_memento(false)
	if not rollback_value is Dictionary or rollback_value.is_empty():
		return StepResultScript.new(false,false,"party_snapshot_unavailable")
	var rollback:Dictionary=rollback_value
	var event_start:int=world.events.size()
	world.begin_step(processed_step_index)
	var result=party_coordinator.commit_prevalidated_deployment(authoritative,
		processed_step_index)
	if result is Dictionary or not result.accepted:
		world=WorldStateScript.from_rollback_memento(rollback);_rebuild_systems()
		return StepResultScript.new(false,false,str(result.get("reason","deployment_failed")))
	world.finish_step()
	if not world.runtime_step_postcondition_error(event_start).is_empty():
		world=WorldStateScript.from_rollback_memento(rollback);_rebuild_systems()
		return StepResultScript.new(false,false,"deployment_semantic_failure")
	return result


func preview_party_turn(request):
	var processed_step_index: int = _next_processed_step_index()
	if processed_step_index < 0:
		return PartyPlanScript.new({"accepted": false, "reason": "step_index_overflow",
			"actor_rows": [], "base_fingerprint": JSON.stringify(world.snapshot()).sha256_text()})
	return party_coordinator.preview_party_turn(request, processed_step_index, world.world_time)


func direct_solo_party_action_error(request) -> String:
	# Product Tab only needs to know whether this one protagonist action is legal.
	# Building the damage batch, cadence timeline and integrity fingerprint here
	# duplicated the authoritative preview immediately performed by the commit.
	if request == null or not request is PartyTurnRequest:
		return "invalid_party_request"
	var request_error := PartyRequestScript.wire_error(request.to_dict())
	if not request_error.is_empty():
		return request_error
	return party_coordinator.direct_solo_action_error(request)


func step_direct_solo_party_turn(request, supplied_rollback_memento: Variant = null):
	# The request was constructed by the session from one local tap, not supplied
	# as an external frozen plan. Validate and freeze it once authoritatively, then
	# share the exact canonical commit/rollback/semantic-validation tail.
	if request==null or not request is PartyTurnRequest:
		return StepResultScript.new(false,false,"invalid_party_request")
	var request_error:=PartyRequestScript.wire_error(request.to_dict())
	if not request_error.is_empty():return StepResultScript.new(false,false,request_error)
	var processed_step_index:int=_next_processed_step_index()
	if processed_step_index<0:return StepResultScript.new(false,false,"step_index_overflow")
	var authoritative_plan=party_coordinator.preview_party_turn(request,
		processed_step_index,world.world_time,false)
	var authoritative:Dictionary=authoritative_plan.to_dict()
	if not bool(authoritative.get("accepted",false)):
		return StepResultScript.new(false,false,
			str(authoritative.get("reason","invalid_party_action")))
	return _commit_prevalidated_party_turn(authoritative,processed_step_index,
		supplied_rollback_memento)


func step_party_turn(plan):
	if not plan is PartyTurnPlan:
		return StepResultScript.new(false, false, "invalid_party_plan")
	var supplied: Dictionary = plan.to_dict()
	var supplied_error := _accepted_party_plan_shape_error(supplied)
	if not supplied_error.is_empty():
		return StepResultScript.new(false, false, "stale_or_tampered_combat_plan" \
			if bool(supplied.get("accepted", false)) else supplied_error)
	if not bool(supplied.accepted):
		return StepResultScript.new(false, false, str(supplied.reason))
	var request_error := PartyRequestScript.wire_error(supplied.get("canonical_request"))
	if not request_error.is_empty():
		return StepResultScript.new(false, false, request_error)
	var request = PartyRequestScript.from_dict(supplied.canonical_request)
	if request == null:
		return StepResultScript.new(false, false, "invalid_party_request")
	if world.party_encounter == null or str(supplied.base_fingerprint) != JSON.stringify(world.snapshot()).sha256_text() \
			or str(supplied.base_step) != str(world.step_index) or str(supplied.base_time) != str(world.world_time) \
			or str(supplied.base_revision) != str(world.party_encounter.revision):
		return StepResultScript.new(false, false, "stale_party_plan")
	var processed_step_index: int = _next_processed_step_index()
	if processed_step_index < 0:
		return StepResultScript.new(false, false, "step_index_overflow")
	var authoritative_plan = party_coordinator.preview_party_turn(
		request, processed_step_index, world.world_time)
	var authoritative: Dictionary = authoritative_plan.to_dict()
	if not bool(authoritative.get("accepted", false)):
		return StepResultScript.new(false, false, str(authoritative.get("reason", "stale_party_plan")))
	if supplied != authoritative:
		return StepResultScript.new(false, false, "stale_or_tampered_combat_plan")
	return _commit_prevalidated_party_turn(authoritative,processed_step_index)


func _commit_prevalidated_party_turn(authoritative:Dictionary,
		processed_step_index:int, supplied_rollback_memento: Variant = null):
	var rollback_value: Variant = supplied_rollback_memento \
		if supplied_rollback_memento != null else world.snapshot()
	if not rollback_value is Dictionary:
		return StepResultScript.new(false, false, "party_snapshot_unavailable")
	var rollback: Dictionary = rollback_value
	if rollback.is_empty():
		return StepResultScript.new(false, false, "party_snapshot_unavailable")
	if supplied_rollback_memento != null \
			and not world.rollback_memento_is_current(rollback):
		return StepResultScript.new(false, false, "party_snapshot_unavailable")
	var event_start: int = world.events.size()
	var start_time: int = world.world_time
	var cost: int = int(authoritative.total_time_cost)
	if cost <= 0 or world.step_index == MAX_INT64 or start_time > MAX_WORLD_TIME - cost:
		return StepResultScript.new(false, false, "time_overflow")
	var frozen_party_intents: Array = []
	for row_index in range(authoritative.actor_rows.size()):
		var freeze_row: Dictionary = authoritative.actor_rows[row_index]
		if str(freeze_row.action.type) != "MELEE": continue
		var freeze_target_id := int(str(freeze_row.action.target_id))
		var freeze_target = world.entities.get(freeze_target_id)
		var frozen = melee.freeze_assessment(freeze_row.combat_assessment,
			freeze_target.health if freeze_target != null else -1, row_index)
		if frozen == null:
			return StepResultScript.new(false, false, "party_attack_freeze_failed")
		frozen_party_intents.append(frozen)
	var projected_party_results: Array = melee.project_batch(frozen_party_intents)
	var canonical_party_batch: bool = not frozen_party_intents.is_empty() \
		and projected_party_results.size() == frozen_party_intents.size()
	if not frozen_party_intents.is_empty() and not canonical_party_batch:
		return StepResultScript.new(false, false, "party_attack_projection_failed")
	var frozen_by_ordinal: Dictionary = {}
	var resolution_by_ordinal: Dictionary = {}
	if canonical_party_batch:
		for frozen in frozen_party_intents:
			frozen_by_ordinal[int(frozen.assessment.intent_ordinal)] = frozen
		for resolution in projected_party_results:
			resolution_by_ordinal[int(resolution.action_data.intent_ordinal)] = resolution
	world.begin_step(processed_step_index)
	var leaf_index := 0
	var pending_attack_results: Array = []
	for row in authoritative.actor_rows:
		var action: Dictionary = row.action
		var actor_id := int(str(action.actor_id))
		var leaf = null
		match str(action.type):
			"HOLD":
				leaf = world.emit_event("action.hold", actor_id, -1, world.entities[actor_id].position, int(row.time_cost))
				if leaf != null:
					var combatant = world.combatant_states[actor_id]
					var candidate_until := start_time + 200
					if candidate_until > combatant.guarded_until:
						combatant.guarded_until = candidate_until
						combatant.guard_source_event_id = leaf.id
			"MOVE":
				var destination := Vector2i(int(action.destination[0]), int(action.destination[1]))
				var terrain_id := str(world.tile_at(destination).terrain)
				leaf = movement.commit_preflighted_move(actor_id, destination, terrain_id, int(row.time_cost))
			"MELEE":
				var target_id := int(str(action.target_id))
				var target = world.entities.get(target_id)
				var assessment: Dictionary = row.combat_assessment
				if int(assessment.get("schema_version", 1)) == 2:
					var ammo_result: Dictionary = WorldItemOperationsScript.commit_attack_consumption(
						world, actor_id)
					if not bool(ammo_result.get("accepted", false)):
						return _rollback_party_step(rollback, str(ammo_result.get("reason", "ammo_commit_failed")))
				var ordinal := int(assessment.intent_ordinal)
				var frozen = frozen_by_ordinal.get(ordinal)
				var resolution = resolution_by_ordinal.get(ordinal)
				if target != null and frozen != null \
						and resolution != null:
					var frozen_position := Vector2i(int(assessment.target_position[0]),
						int(assessment.target_position[1]))
					leaf = world.emit_event("action.melee_attack", actor_id, target_id,
						frozen_position, int(assessment.base_damage), -1, resolution.action_data)
					if leaf != null:
						pending_attack_results.append({"action": leaf, "intent": frozen,
							"resolution": resolution})
		if leaf == null or party_coordinator.fail_after_leaf_index == leaf_index \
				or party_coordinator.fail_point == "party_leaf":
			return _rollback_party_step(rollback, "party_turn_failed")
		if bool(row.get("overridden", false)):
			var member = world.party_encounter.member(actor_id)
			var resilience: int = PartyMoraleSystemScript.ModelScript.morale_resilience(
				member.personality_profile)
			var protagonist_id:int=world.party_encounter.protagonist_id
			var personal=world.personal_relations.get("%d:%d"%[actor_id,protagonist_id])
			var stress_delta: int = 20 + int((1000 - resilience) / 20) \
				+ (int(personal.grievance / 5) if personal != null else 0) \
				- (int(personal.gratitude / 10) if personal != null else 0)
			stress_delta = maxi(1, stress_delta)
			if world.emit_event("party.override_committed", actor_id, -1, world.entities[actor_id].position,
					stress_delta, leaf.id) == null or party_coordinator.fail_point == "turn_override_event":
				return _rollback_party_step(rollback, "party_turn_failed")
		world.party_encounter.member(actor_id).busy_until = start_time + int(row.time_cost)
		leaf_index += 1
	pending_attack_results.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.resolution.action_data.intent_ordinal) \
			< int(b.resolution.action_data.intent_ordinal))
	for pending in pending_attack_results:
		var attack_action = pending.action
		var resolution = pending.resolution
		var target = world.entities.get(attack_action.target_id)
		var target_state = world.combatant_states.get(attack_action.target_id)
		if target == null or target_state == null \
				or target.health != resolution.target_health_before \
				or target_state.life_state != resolution.target_life_before:
			return _rollback_party_step(rollback, "party_attack_projection_mismatch")
		if resolution.outcome == "OVERKILL_SKIP":
			if target.health != resolution.target_health_after \
					or target_state.life_state != resolution.target_life_after:
				return _rollback_party_step(rollback, "party_attack_projection_mismatch")
			continue
		if resolution.outcome == "MISS":
			var miss = world.emit_event("combat.attack_missed", -1, attack_action.target_id,
				attack_action.position, 0, attack_action.id,
				{"schema_version": 1, "combat_ruleset_id": MeleeScript.COMBAT_RULESET_ID,
					"outcome": "MISS"})
			if miss == null:
				return _rollback_party_step(rollback, "party_turn_failed")
		elif resolution.outcome == "FINISHER":
			var pressure: int = int(pending.intent.assessment.normal_final_damage)
			var finished: Dictionary = damage.apply_canonical_downed_finisher(target,
				pressure, attack_action.id, attack_action.position, processed_step_index)
			if not bool(finished.accepted):
				return _rollback_party_step(rollback, "party_turn_failed")
		else:
			var applied: Dictionary = damage.apply_canonical_active_damage(target,
				resolution.final_damage, "physical", attack_action.id,
				attack_action.position, processed_step_index,
				resolution.target_health_before, false,
				resolution.bleed_proc_succeeded)
			var expected_applied: int = resolution.target_health_before \
				- resolution.target_health_after
			if not bool(applied.accepted) \
					or int(applied.applied_health_damage) != expected_applied:
				return _rollback_party_step(rollback, "party_turn_failed")
		if target.health != resolution.target_health_after \
				or target_state.life_state != resolution.target_life_after:
			return _rollback_party_step(rollback, "party_attack_projection_mismatch")
	if not PartyEmotionSystemScript.commit_batch(world, world.events_since(event_start)):
		return _rollback_party_step(rollback, "party_emotion_failed")
	if not PartyMemorySystemScript.commit_batch(world, world.events_since(event_start)):
		return _rollback_party_step(rollback, "party_memory_failed")
	if not PartyMoraleSystemScript.commit_batch(world, world.events_since(event_start)) \
			or party_coordinator.fail_point == "party_morale_event":
		return _rollback_party_step(rollback, "party_morale_failed")
	# A party victory is terminal only after every authoritative occurrence due
	# during this turn has run at the deployed combat positions. Liveness still
	# has to be reconciled here so a protagonist death/defeat takes effect before
	# cadence dispatch, but victory and its regroup tail are deliberately deferred.
	if not party_coordinator.reconcile_liveness(false):
		return _rollback_party_step(rollback, "party_turn_failed")
	var end_time: int = start_time + cost
	var occurrence_index := 0
	while not world.scheduled_entries.is_empty() and int(world.scheduled_entries[0].due_time) <= end_time:
		var entry: Dictionary = world.take_next_schedule()
		if occurrence_index >= authoritative.timeline.size():
			return _rollback_party_step(rollback, "party_schedule_mismatch")
		var expected: Dictionary = authoritative.timeline[occurrence_index]
		if str(expected.kind) != str(entry.kind) or str(expected.at_time) != str(entry.due_time) \
				or str(expected.schedule_id) != str(entry.schedule_id):
			return _rollback_party_step(rollback, "party_schedule_mismatch")
		world.world_time = int(entry.due_time)
		var schedule_event_start: int = world.events.size()
		if not _dispatch_schedule(entry, processed_step_index, false) or party_coordinator.fail_point == "party_schedule":
			return _rollback_party_step(rollback, "actor_tick_failed")
		if not PartyEmotionSystemScript.commit_batch(world,
				world.events_since(schedule_event_start), false):
			return _rollback_party_step(rollback, "party_emotion_failed")
		if not PartyMemorySystemScript.commit_batch(world,
				world.events_since(schedule_event_start)):
			return _rollback_party_step(rollback, "party_memory_failed")
		if not PartyMoraleSystemScript.commit_batch(world,
				world.events_since(schedule_event_start), false) \
				or party_coordinator.fail_point == "party_morale_event":
			return _rollback_party_step(rollback, "party_morale_failed")
		if int(entry.repeat_interval) > 0:
			world.requeue_repeating(entry)
		occurrence_index += 1
	if occurrence_index != authoritative.timeline.size():
		return _rollback_party_step(rollback, "party_schedule_mismatch")
	world.world_time = end_time
	if not party_coordinator.reconcile_liveness():
		return _rollback_party_step(rollback, "party_turn_failed")
	if not party_coordinator.finalize_automatic_regroup():
		return _rollback_party_step(rollback, "party_turn_failed")
	_reconcile_expedition_cycle()
	world.finish_step()
	# Match ordinary live simulation steps: validate the newly appended causal
	# tail and every mutable surface touched by this turn. Full ledger scans remain
	# mandatory at save/load/restore boundaries.
	var party_turn_semantic_error: String = world.runtime_step_postcondition_error(
		event_start)
	if not party_turn_semantic_error.is_empty():
		return _rollback_party_step(rollback, "party_turn_semantic_failure")
	var result_events: Array = world.events_since(event_start)
	return StepResultScript.new(true, true, "ok", result_events, {"processed_step_index": processed_step_index,
		"start_time": start_time, "end_time": end_time, "time_cost": cost, "timeline": authoritative.timeline.duplicate(true),
		"root_event_id": result_events[0].id if not result_events.is_empty() else -1})


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
	var processed_step_index: int = _next_processed_step_index()
	if processed_step_index < 0:
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
		"accepted": true, "reason": "ok", "processed_step_index": processed_step_index,
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
	if world.party_encounter != null:
		if world.party_encounter.expedition_cycle != null \
				and world.party_encounter.expedition_cycle.phase == "TOWN":
			return "expedition_in_town"
		if world.party_encounter.safe_phase not in ["GROUPED", "GROUPED_COMPLETE"]:
			return "party_specialized_flow_required"
		if not command.actor_id is int or command.actor_id != world.party_encounter.protagonist_id:
			return "party_protagonist_command_required"
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
		if not world.can_act(command.actor_id, world.world_time):
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


func _reconcile_expedition_cycle() -> void:
	if world == null or world.party_encounter == null \
			or world.party_encounter.expedition_cycle == null \
			or world.party_encounter.safe_phase == "PARTY_DEFEATED":
		return
	if world.party_encounter.expedition_cycle.auto_return_if_due(world.world_time):
		world.party_encounter.revision += 1


func _resolve_command(command, plan: Dictionary, processed_step_index: int):
	assert(processed_step_index > 0, "Outer operation must provide a processed step")
	match command.type:
		CommandScript.Type.WAIT:
			if world.party_encounter != null and world.entities.has(command.actor_id):
				return world.emit_event("action.wait", command.actor_id, -1,
					world.entities[command.actor_id].position)
			return world.emit_event("action.wait", command.actor_id)
		CommandScript.Type.IGNITE:
			var action = world.emit_event("action.ignite", command.actor_id, -1, command.position, command.power)
			environment.ignite(command.position, command.power, action.id, processed_step_index)
			return action
		CommandScript.Type.POUR_WATER:
			var action = world.emit_event("action.pour_water", command.actor_id, -1, command.position, command.power)
			environment.apply_water(command.position, command.power, action.id, processed_step_index)
			return action
		CommandScript.Type.DISCHARGE:
			var action = world.emit_event("action.discharge", command.actor_id, -1, command.position, command.power)
			environment.discharge(command.position, command.power, action.id, processed_step_index)
			return action
		CommandScript.Type.MOVE:
			return movement.commit_move(command.actor_id, command.position, int(plan["time_cost"]))
	assert(false, "Validated command type was not dispatched")
	return null


func _dispatch_schedule(entry: Dictionary, processed_step_index: int,
		allow_party_victory: bool = true) -> bool:
	match str(entry["kind"]):
		"system.environment_tick":
			if not environment.process_tick(processed_step_index): return false
			if world.party_encounter != null:
				return party_coordinator.reconcile_liveness(allow_party_victory) \
					and party_coordinator.fail_point != "after_environment_tick"
			return true
		"system.actor_tick":
			var tick_start_can_act_ids = status_lifecycle.freeze_tick_start_can_act_ids(
				int(entry.due_time))
			if not tick_start_can_act_ids is Dictionary \
					or not status_lifecycle.process_actor_occurrence(processed_step_index,
						tick_start_can_act_ids):
				return false
			if world.encounter_lab != null: return actor_coordinator.process_tick(processed_step_index,
				int(entry.schedule_id), int(entry.due_time), tick_start_can_act_ids)
			if world.party_encounter != null: return party_coordinator.process_tick(processed_step_index,
				int(entry.schedule_id), int(entry.due_time), tick_start_can_act_ids,
				allow_party_victory)
			return true
		_:
			return false


func _next_processed_step_index() -> int:
	if world == null or not world.is_settled() or world.step_index < 0 \
			or world.step_index == MAX_INT64:
		return -1
	return world.step_index + 1


func _accepted_party_plan_shape_error(data: Variant) -> String:
	if not data is Dictionary:
		return "invalid_party_plan_shape"
	if not data.get("accepted") is bool:
		return "invalid_party_plan_accepted"
	if not bool(data.accepted):
		var rejected_keys: Array = data.keys(); rejected_keys.sort()
		if rejected_keys != ["accepted", "actor_rows", "base_fingerprint", "reason"] \
				or not data.get("reason") is String or not data.get("actor_rows") is Array \
				or not data.get("base_fingerprint") is String:
			return "invalid_party_plan_shape"
		return ""
	var keys: Array = data.keys(); keys.sort()
	if keys != ["accepted", "actor_rows", "base_fingerprint", "base_revision", "base_step",
			"base_time", "canonical_request", "plan_hash", "reason", "timeline", "total_time_cost"]:
		return "invalid_party_plan_keys"
	for key in ["base_revision", "base_step", "base_time"]:
		if not Int64CodecScript.is_canonical(data.get(key)) or Int64CodecScript.parse(data.get(key), key) < 0:
			return "noncanonical_party_plan_%s" % key
	if not data.get("reason") is String or str(data.reason) != "ok" \
			or not data.get("base_fingerprint") is String or str(data.base_fingerprint).length() != 64 \
			or not data.get("plan_hash") is String or str(data.plan_hash).length() != 64 \
			or not data.get("actor_rows") is Array or data.actor_rows.is_empty() \
			or not data.get("timeline") is Array or not data.get("total_time_cost") is int \
			or int(data.total_time_cost) <= 0 or int(data.total_time_cost) > 10000:
		return "invalid_party_plan_shape"
	if str(data.plan_hash) != PartyPlanScript.canonical_hash(data): return "invalid_party_plan_hash"
	var melee_assessments: Array = []
	for row in data.actor_rows:
		if not row is Dictionary: return "invalid_party_actor_row"
		var row_keys: Array = row.keys(); row_keys.sort()
		if row_keys != ["action", "actor_id", "combat_assessment", "overridden", "resolution_note",
				"roster_slot", "source", "suggestion", "time_cost"]:
			return "invalid_party_actor_row_keys"
		if not row.get("action") is Dictionary or not row.get("actor_id") is int \
				or not row.get("roster_slot") is int or not row.get("time_cost") is int \
				or not row.get("source") is String or not row.get("resolution_note") is String \
				or not row.get("overridden") is bool:
			return "invalid_party_actor_row"
		if str(row.action.get("type", "")) == "MELEE":
			var assessment_error := PartyPlanScript.combat_assessment_wire_error(row.combat_assessment)
			if not assessment_error.is_empty(): return assessment_error
			melee_assessments.append(row.combat_assessment)
		elif row.combat_assessment != null:
			return "unexpected_combat_assessment"
	var canonical_assessment_order: Array = melee_assessments.duplicate()
	canonical_assessment_order.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_target := Int64CodecScript.parse(a.target_id, "assessment target")
		var b_target := Int64CodecScript.parse(b.target_id, "assessment target")
		if a_target != b_target: return a_target < b_target
		return Int64CodecScript.parse(a.attacker_id, "assessment actor") \
			< Int64CodecScript.parse(b.attacker_id, "assessment actor"))
	for expected_ordinal in range(canonical_assessment_order.size()):
		if int(canonical_assessment_order[expected_ordinal].intent_ordinal) != expected_ordinal:
			return "invalid_combat_assessment_ordinal"
	return ""


func _rollback_party_step(snapshot_before: Dictionary, reason: String):
	var restored = WorldStateScript.from_rollback_memento(snapshot_before) \
		if snapshot_before.has("tile_scalars") else WorldStateScript.from_snapshot(snapshot_before)
	if restored != null:
		world = restored
		_rebuild_systems()
	return StepResultScript.new(false, false, reason)


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
