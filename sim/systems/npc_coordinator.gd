class_name NpcCoordinator
extends RefCounted

const AgentProfileRegistryScript = preload("res://sim/agent_profile_registry.gd")
const ActivityTimingScript = preload("res://sim/activity_timing_table.gd")
const WeightedPathfinderScript = preload("res://sim/weighted_pathfinder.gd")
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const WorldClockScript = preload("res://sim/world_clock.gd")

const PRIORITIES := {"DANGER": 500, "FATIGUE": 400, "HUNGER": 390,
	"ROUTINE": 300, "SOCIAL": 200, "IDLE": 100}

var world
var movement
var relationships
var pathfinder


func _init(p_world, p_movement, p_relationships) -> void:
	world = p_world
	movement = p_movement
	relationships = p_relationships
	pathfinder = WeightedPathfinderScript.new(world, movement)


func process_tick() -> void:
	var now: int = world.world_time
	var ids: Array = world.agent_states.keys()
	ids.sort()
	for entity_id in ids:
		_update_needs(world.agent_states[entity_id], now)
	var projection := _occupancy_projection()
	var intents: Array[Dictionary] = []
	for entity_id in ids:
		var entity = world.entities.get(entity_id)
		var state = world.agent_states[entity_id]
		if entity == null or not world.can_act(entity_id, now) or state.busy_until > now:
			continue
		intents.append(_decide(entity_id, projection, now))
	_resolve_destination_conflicts(intents)
	intents.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["actor_id"]) < int(b["actor_id"]))
	for intent in intents:
		_commit(intent, projection, now)


func _update_needs(state, now: int) -> void:
	if now <= state.last_need_update_time:
		return
	var minutes: int = (now - state.last_need_update_time) / 100
	if minutes <= 0:
		return
	var profile := AgentProfileRegistryScript.definition(state.profile_id)
	var rates: Dictionary = profile["need_rates_per_minute"]
	state.hunger = mini(1000, state.hunger + minutes * int(rates["hunger"]))
	state.fatigue = mini(1000, state.fatigue + minutes * int(rates["fatigue"]))
	state.social_need = mini(1000, state.social_need + minutes * int(rates["social_need"]))
	state.last_need_update_time += minutes * 100


func _decide(actor_id: int, projection: Dictionary, now: int) -> Dictionary:
	var state = world.agent_states[actor_id]
	var entity = world.entities[actor_id]
	var profile := AgentProfileRegistryScript.definition(state.profile_id)
	var candidates: Array[Dictionary] = []
	if world.tile_at(entity.position).fire >= 80:
		var safe_positions: Array[Vector2i] = []
		for position in world.movement_neighbors(entity.position):
			if world.tile_at(position).fire < world.tile_at(entity.position).fire:
				safe_positions.append(position)
		if not safe_positions.is_empty():
			safe_positions.sort_custom(_position_less)
			candidates.append(_candidate("MOVE", safe_positions[0], -1, PRIORITIES.DANGER, 1000, "immediate_danger"))
	var thresholds: Dictionary = profile["need_thresholds"]
	if state.fatigue >= int(thresholds["fatigue"]):
		candidates.append(_candidate("REST", profile["home_position"], -1,
			PRIORITIES.FATIGUE, state.fatigue, "critical_fatigue"))
	if state.hunger >= int(thresholds["hunger"]):
		for position in profile["meal_positions"]:
			candidates.append(_candidate("EAT", position, -1,
				PRIORITIES.HUNGER, state.hunger, "critical_hunger"))
	var clock: Dictionary = WorldClockScript.project(now)
	var minute_of_day: int = int(clock["hour_of_day"]) * 60 + int(clock["minute_of_hour"])
	var block := AgentProfileRegistryScript.current_block(state.profile_id, minute_of_day)
	var routine_positions := AgentProfileRegistryScript.zone_positions(str(block["target_zone_id"]))
	for position in routine_positions:
		candidates.append(_candidate(str(block["activity"]), position, -1,
			PRIORITIES.ROUTINE, 500, "routine:%s" % str(block["target_zone_id"])))
	if state.social_need >= int(thresholds["social_need"]) or str(block["activity"]) == "SOCIALIZE":
		_append_social_candidates(candidates, actor_id, projection, now)
	if candidates.is_empty():
		candidates.append(_candidate("IDLE", entity.position, -1, PRIORITIES.IDLE, 0, "idle"))
	var evaluated: Array[Dictionary] = []
	for candidate in candidates:
		evaluated.append(_evaluate_candidate(actor_id, candidate, projection))
	evaluated.sort_custom(_candidate_less)
	var diagnostics: Array[Dictionary] = []
	for candidate in evaluated.slice(0, mini(8, evaluated.size())):
		diagnostics.append(_diagnostic(candidate))
	state.candidate_diagnostics = diagnostics
	var selected: Dictionary = {}
	for candidate in evaluated:
		if bool(candidate["accepted"]):
			selected = candidate
			break
	if selected.is_empty():
		selected = _candidate("IDLE", entity.position, -1, PRIORITIES.IDLE, 0, "no_reachable_candidate")
		selected["accepted"] = true
		selected["path"] = [entity.position]
		selected["path_cost"] = 0
		selected["steps"] = 0
	return _materialize_intent(actor_id, selected, now)


func _append_social_candidates(candidates: Array[Dictionary], actor_id: int,
		projection: Dictionary, now: int) -> void:
	var actor = world.entities[actor_id]
	var ids: Array = world.agent_states.keys()
	ids.sort()
	for target_id in ids:
		if target_id == actor_id or not world.is_autonomous_target(target_id):
			continue
		var effective: Dictionary = relationships.effective_relation(actor_id, target_id)
		var relation = world.personal_relations.get("%d:%d" % [actor_id, target_id], null)
		var last_social: int = -1 if relation == null else relation.last_social_time
		var candidate := _candidate("SOCIALIZE", world.entities[target_id].position, target_id,
			PRIORITIES.SOCIAL, 300 + int(effective.get("trust", 0)) + int(effective.get("familiarity", 0)) * 2,
			"social_target")
		if int(effective.get("hostility", 0)) >= 60:
			candidate["rejection_reason"] = "hostility_forbidden"
		elif last_social >= 0 and now - last_social < 6000:
			candidate["rejection_reason"] = "social_cooldown"
		candidates.append(candidate)


func _evaluate_candidate(actor_id: int, candidate: Dictionary,
		projection: Dictionary) -> Dictionary:
	var result := candidate.duplicate(true)
	if not str(result.get("rejection_reason", "")).is_empty():
		result["accepted"] = false
		result["path"] = []
		result["path_cost"] = 2147483647
		result["steps"] = 0
		return result
	var actor_position: Vector2i = world.entities[actor_id].position
	var activity: String = result["activity"]
	var target_position: Vector2i = result["target_position"]
	if activity == "SOCIALIZE" and int(result["target_entity_id"]) > 0:
		var target_id: int = result["target_entity_id"]
		if maxi(absi(target_position.x - actor_position.x), absi(target_position.y - actor_position.y)) <= 1:
			result["accepted"] = true
			result["path"] = [actor_position]
			result["path_cost"] = 0
			result["steps"] = 0
			return result
		var approaches: Array[Dictionary] = []
		for adjacent in world.movement_neighbors(target_position):
			if _occupant(adjacent, actor_id, projection) != -1:
				continue
			var route: Dictionary = pathfinder.find_path(actor_id, adjacent, projection)
			if route.found:
				approaches.append({"position": adjacent, "route": route})
		if approaches.is_empty():
			result["accepted"] = false
			result["rejection_reason"] = "path_unreachable"
			result["path"] = []
			result["path_cost"] = 2147483647
			result["steps"] = 0
			return result
		approaches.sort_custom(func(a: Dictionary, b: Dictionary):
			if a.route.total_cost != b.route.total_cost: return a.route.total_cost < b.route.total_cost
			if a.route.steps != b.route.steps: return a.route.steps < b.route.steps
			return _position_less(a.position, b.position))
		result["approach_position"] = approaches[0].position
		result["path"] = approaches[0].route.path
		result["path_cost"] = approaches[0].route.total_cost
		result["steps"] = approaches[0].route.steps
		result["accepted"] = true
		return result
	var route: Dictionary = pathfinder.find_path(actor_id, target_position, projection)
	result["accepted"] = bool(route.found)
	result["rejection_reason"] = "" if route.found else str(route.reason)
	result["path"] = route.path
	result["path_cost"] = route.total_cost if route.found else 2147483647
	result["steps"] = route.steps
	return result


func _materialize_intent(actor_id: int, selected: Dictionary, now: int) -> Dictionary:
	var actor_position: Vector2i = world.entities[actor_id].position
	var path: Array = selected.get("path", [actor_position])
	var intent := selected.duplicate(true)
	intent["actor_id"] = actor_id
	intent["goal_activity"] = selected["activity"]
	intent["conflict_lost"] = false
	if path.size() > 1:
		intent["activity"] = "MOVE"
		intent["destination"] = path[1]
	else:
		intent["destination"] = actor_position
	intent["selected_time"] = now
	return intent


func _resolve_destination_conflicts(intents: Array[Dictionary]) -> void:
	var groups: Dictionary = {}
	for intent in intents:
		if intent["activity"] != "MOVE":
			continue
		var position: Vector2i = intent["destination"]
		var key := "%d:%d" % [position.x, position.y]
		if not groups.has(key): groups[key] = []
		groups[key].append(intent)
	var keys: Array = groups.keys()
	keys.sort()
	for key in keys:
		var rows: Array = groups[key]
		rows.sort_custom(func(a: Dictionary, b: Dictionary):
			if int(a["priority"]) != int(b["priority"]): return int(a["priority"]) > int(b["priority"])
			return int(a["actor_id"]) < int(b["actor_id"]))
		for index in range(1, rows.size()):
			rows[index]["conflict_lost"] = true


func _commit(intent: Dictionary, projection: Dictionary, now: int) -> void:
	var actor_id: int = intent["actor_id"]
	var state = world.agent_states[actor_id]
	var destination: Vector2i = intent["destination"]
	var target_id: int = intent["target_entity_id"]
	state.last_decision_time = now
	state.last_decision_reason = str(intent["reason"])
	state.last_decision_score = int(intent["score"])
	state.intent_started_time = now
	state.intent_target_entity_id = target_id
	state.intent_target_position = intent["target_position"]
	state.blocked_reason = ""
	world.emit_event("ai.intent_selected", actor_id, target_id,
		world.entities[actor_id].position, maxi(0, int(intent["score"])), -1,
		{"activity": intent["activity"], "goal_activity": intent["goal_activity"],
			"reason": intent["reason"], "priority": intent["priority"]})
	if bool(intent["conflict_lost"]):
		_block(state, actor_id, target_id, "destination_conflict", now)
		return
	match str(intent["activity"]):
		"MOVE":
			var assessment = movement.assess_move(actor_id, destination)
			if not assessment.accepted:
				_block(state, actor_id, target_id, "commit_revalidation_failed", now)
				return
			var definition: Dictionary = TerrainRegistryScript.definition(world.tile_at(destination).terrain)
			var cost: int = int(definition["move_time_cost"])
			movement.commit_move(actor_id, destination, cost)
			state.current_activity = "MOVE"
			state.intent_kind = "MOVE"
			state.busy_until = now + cost
			state.route_failures = 0
		"WORK", "EAT", "REST", "SOCIALIZE", "IDLE":
			_commit_activity(state, intent, now)


func _commit_activity(state, intent: Dictionary, now: int) -> void:
	var activity: String = intent["activity"]
	var actor_id: int = intent["actor_id"]
	var target_id: int = intent["target_entity_id"]
	state.current_activity = activity
	state.intent_kind = activity
	state.busy_until = now + ActivityTimingScript.cost(activity)
	match activity:
		"WORK":
			world.emit_event("activity.work", actor_id, -1, world.entities[actor_id].position, 1)
			state.fatigue = mini(1000, state.fatigue + 8)
		"EAT":
			world.emit_event("activity.eat", actor_id, -1, world.entities[actor_id].position, 1)
			state.hunger = maxi(0, state.hunger - 500)
		"REST":
			world.emit_event("activity.rest", actor_id, -1, world.entities[actor_id].position, 1)
			state.fatigue = maxi(0, state.fatigue - 450)
		"SOCIALIZE":
			if target_id > 0:
				var conversation = world.emit_event("social.conversation", actor_id, target_id,
					world.entities[actor_id].position, 1)
				if conversation != null:
					relationships.record_conversation(actor_id, target_id, conversation.id)
					for observer_id in [actor_id, target_id]:
						var memory = world.record_memory(observer_id, conversation.id, "conversation",
							actor_id, target_id, world.entities[observer_id].position, 60, 100, true)
						if memory != null:
							world.emit_event("memory.recorded", observer_id, target_id,
								world.entities[observer_id].position, memory.salience,
								conversation.id, {"memory_id": str(memory.memory_id), "kind": memory.kind})
					state.social_need = maxi(0, state.social_need - 450)
					world.agent_states[target_id].social_need = maxi(0, world.agent_states[target_id].social_need - 250)
		"IDLE":
			pass


func _block(state, actor_id: int, target_id: int, reason: String, now: int) -> void:
	state.current_activity = "IDLE"
	state.intent_kind = "IDLE"
	state.blocked_reason = reason
	state.route_failures += 1
	state.busy_until = now + ActivityTimingScript.cost("IDLE")
	world.emit_event("ai.action_blocked", actor_id, target_id,
		world.entities[actor_id].position, 0, -1, {"reason": reason})


func _candidate(activity: String, position: Vector2i, target_entity_id: int,
		priority: int, score: int, reason: String) -> Dictionary:
	return {"activity": activity, "target_position": position,
		"target_entity_id": target_entity_id, "priority": priority,
		"score": score, "reason": reason, "rejection_reason": ""}


func _diagnostic(candidate: Dictionary) -> Dictionary:
	var position: Vector2i = candidate["target_position"]
	return {"activity": candidate["activity"], "priority": candidate["priority"],
		"score": candidate["score"], "path_cost": candidate.get("path_cost", -1),
		"target_position": [position.x, position.y],
		"target_entity_id": str(candidate["target_entity_id"]),
		"accepted": candidate.get("accepted", false),
		"rejection_reason": candidate.get("rejection_reason", "")}


func _candidate_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["priority"]) != int(b["priority"]): return int(a["priority"]) > int(b["priority"])
	if int(a["score"]) != int(b["score"]): return int(a["score"]) > int(b["score"])
	if int(a["path_cost"]) != int(b["path_cost"]): return int(a["path_cost"]) < int(b["path_cost"])
	var ap: Vector2i = a["target_position"]
	var bp: Vector2i = b["target_position"]
	if ap.y != bp.y: return ap.y < bp.y
	if ap.x != bp.x: return ap.x < bp.x
	return int(a["target_entity_id"]) < int(b["target_entity_id"])


func _position_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y if a.y != b.y else a.x < b.x


func _occupancy_projection() -> Dictionary:
	var result: Dictionary = {}
	var ids: Array = world.entities.keys()
	ids.sort()
	for entity_id in ids:
		var entity = world.entities[entity_id]
		if world.occupies_tile(entity_id):
			result["%d:%d" % [entity.position.x, entity.position.y]] = entity_id
	return result


func _occupant(position: Vector2i, actor_id: int, projection: Dictionary) -> int:
	var value: Variant = projection.get("%d:%d" % [position.x, position.y], -1)
	return int(value) if value is int and int(value) != actor_id else -1
