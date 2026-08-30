class_name PartyAutoExplore
extends RefCounted

const MovementSystemScript = preload("res://sim/systems/movement_system.gd")

const SCHEMA_VERSION := 1
const AFFINITY_SAFE_RISK_THRESHOLD := 0

var _session_ref: WeakRef
var _running := false
var _stop_reason := "auto_explore_idle"
var _target := Vector2i(-1, -1)
var _target_visibility := ""
var _steps_committed := 0
var _started_step_index := -1
var _last_step_index := -1
var _health_baseline: Dictionary = {}
var _known_hazard_keys: Dictionary = {}
var _known_discovery_keys: Dictionary = {}
var _objective_signature := ""
var _last_step_result: Dictionary = {}


func _init(session) -> void:
	_session_ref = weakref(session)


func clear() -> void:
	_running = false
	_stop_reason = "auto_explore_idle"
	_target = Vector2i(-1, -1)
	_target_visibility = ""
	_steps_committed = 0
	_started_step_index = -1
	_last_step_index = -1
	_health_baseline.clear()
	_known_hazard_keys.clear()
	_known_discovery_keys.clear()
	_objective_signature = ""
	_last_step_result.clear()


func start() -> Dictionary:
	if _running:
		return _state("auto_explore_already_active")
	clear()
	var snapshot := _snapshot()
	var blocker := _precondition_reason(snapshot)
	if not blocker.is_empty():
		return _stop(blocker)
	_health_baseline = snapshot.get("health", {}).duplicate(true)
	_known_hazard_keys = snapshot.get("hazards", {}).duplicate(true)
	_known_discovery_keys = snapshot.get("discoveries", {}).duplicate(true)
	_objective_signature = str(snapshot.get("objective_signature", ""))
	_started_step_index = int(snapshot.get("step_index", -1))
	_last_step_index = _started_step_index
	_running = true
	_stop_reason = ""
	return _advance(snapshot)


func continue_auto() -> Dictionary:
	if not _running:
		return _state("auto_explore_not_active")
	var snapshot := _snapshot()
	var blocker := _change_reason(snapshot)
	if not blocker.is_empty():
		return _stop(blocker)
	return _advance(snapshot)


func cancel(reason: String = "auto_explore_cancelled") -> Dictionary:
	if not _running:
		return _state("auto_explore_not_active")
	var owner = _owner()
	if owner != null and bool(owner.exploration_route_state().get("active", false)):
		owner.cancel_exploration_route()
	return _stop(reason if not reason.is_empty() else "auto_explore_cancelled")


func state() -> Dictionary:
	return _state(_stop_reason if not _running else "ok")


func _advance(snapshot: Dictionary) -> Dictionary:
	var choice := _choose_frontier(snapshot)
	if not bool(choice.get("found", false)):
		return _stop(str(choice.get("reason", "auto_explore_no_frontier")))
	_target = choice.target
	_target_visibility = str(choice.visibility_state)
	var path: Array = choice.path
	if path.size() < 2:
		return _stop("auto_explore_no_frontier")
	var next_position: Vector2i = path[1]
	var visible: Dictionary = snapshot.get("visible", {})
	# The canonical route facade may inspect live occupancy on its goal. Restrict
	# that goal to a currently visible cell, so AUTO EXPLORE never probes an actor
	# hidden in fog even though MEMORY terrain is allowed in frontier planning.
	if not visible.has(_key(next_position)):
		return _stop("auto_explore_fog_boundary")
	var owner = _owner()
	if owner == null:
		return _stop("session_not_initialized")
	var journal_before: int = owner.command_journal.size()
	var step_before := int(owner.sim.world.step_index)
	var route_preview: Dictionary = owner.preview_exploration_route(next_position)
	if not bool(route_preview.get("accepted", false)):
		_last_step_result = route_preview.duplicate(true)
		return _stop("auto_explore_route_rejected")
	var result: Dictionary = owner.start_exploration_route(next_position,
		str(route_preview.get("plan_hash", "")))
	_last_step_result = result.duplicate(true)
	if not bool(result.get("accepted", false)) \
			or owner.command_journal.size() != journal_before + 1 \
			or int(owner.sim.world.step_index) != step_before + 1:
		return _stop("auto_explore_route_rejected")
	_steps_committed += 1
	_last_step_index = int(owner.sim.world.step_index)
	var after := _snapshot()
	var stop_after := _change_reason(after)
	if not stop_after.is_empty():
		return _stop(stop_after, true, next_position)
	# Safe newly visible cells become the next comparison baseline. Health stays
	# pinned to start because any change is a stop condition, not a new baseline.
	_known_hazard_keys = after.get("hazards", {}).duplicate(true)
	_known_discovery_keys = after.get("discoveries", {}).duplicate(true)
	_objective_signature = str(after.get("objective_signature", ""))
	return _state("ok", true, next_position)


func _choose_frontier(snapshot: Dictionary) -> Dictionary:
	var cells: Dictionary = snapshot.get("cells", {})
	var current := _wire_position(snapshot.get("hero_position", [-1, -1]))
	var reachable := _known_safe_paths(current, cells)
	var candidates: Array[Dictionary] = []
	for key_value in cells:
		var cell: Dictionary = cells[key_value]
		if not bool(cell.get("passable", false)):
			continue
		var position := _wire_position(cell.get("position", [-1, -1]))
		if position == current or not _is_frontier(position, cells,
				int(snapshot.get("width", 0)), int(snapshot.get("height", 0))):
			continue
		var path_result: Dictionary = reachable.get(_key(position), {})
		if path_result.is_empty():
			continue
		candidates.append({"target":position,
			"visibility_state":str(cell.get("visibility_state", "MEMORY")),
			"path":path_result.path,
			"steps":int(path_result.steps), "cost":int(path_result.cost)})
	if candidates.is_empty():
		return {"found":false, "reason":"auto_explore_no_frontier"}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.steps) != int(b.steps): return int(a.steps) < int(b.steps)
		if int(a.cost) != int(b.cost): return int(a.cost) < int(b.cost)
		var a_position: Vector2i = a.target
		var b_position: Vector2i = b.target
		if a_position.y != b_position.y: return a_position.y < b_position.y
		return a_position.x < b_position.x)
	var chosen: Dictionary = candidates[0]
	chosen["found"] = true
	return chosen


func _known_safe_paths(start: Vector2i, cells: Dictionary) -> Dictionary:
	var start_key := _key(start)
	if not cells.has(start_key):
		return {}
	var open: Array[Dictionary] = [{"position":start, "steps":0, "cost":0,
		"sequence":0, "path":[start]}]
	var best: Dictionary = {start_key:[0, 0]}
	var reachable: Dictionary = {start_key:{"found":true, "path":[start],
		"steps":0, "cost":0}}
	var sequence := 1
	while not open.is_empty():
		open.sort_custom(func(a: Dictionary, b: Dictionary):
			if int(a.steps) != int(b.steps): return int(a.steps) < int(b.steps)
			if int(a.cost) != int(b.cost): return int(a.cost) < int(b.cost)
			var a_position: Vector2i = a.position
			var b_position: Vector2i = b.position
			if a_position.y != b_position.y: return a_position.y < b_position.y
			if a_position.x != b_position.x: return a_position.x < b_position.x
			return int(a.sequence) < int(b.sequence))
		var node: Dictionary = open.pop_front()
		var position: Vector2i = node.position
		if best.get(_key(position), []) != [int(node.steps), int(node.cost)]:
			continue
		reachable[_key(position)] = {"found":true, "path":node.path.duplicate(),
			"steps":int(node.steps), "cost":int(node.cost)}
		for direction in MovementSystemScript.MOVE_DIRECTIONS_8:
			var next := position + direction
			if not _known_step_is_safe(position, next, cells):
				continue
			var cell: Dictionary = cells[_key(next)]
			var candidate_steps := int(node.steps) + 1
			var candidate_cost := int(node.cost) + int(cell.get("move_time_cost", 0))
			var old: Array = best.get(_key(next), [])
			if not old.is_empty() and [candidate_steps, candidate_cost] >= old:
				continue
			var path: Array = node.path.duplicate()
			path.append(next)
			best[_key(next)] = [candidate_steps, candidate_cost]
			open.append({"position":next, "steps":candidate_steps,
				"cost":candidate_cost, "sequence":sequence, "path":path})
			sequence += 1
	return reachable


func _known_step_is_safe(from: Vector2i, to: Vector2i,
		cells: Dictionary) -> bool:
	var key := _key(to)
	if not cells.has(key):
		return false
	var cell: Dictionary = cells[key]
	if not bool(cell.get("passable", false)) \
			or bool(cell.get("occupied", false)) \
			or int(cell.get("risk", 0)) > AFFINITY_SAFE_RISK_THRESHOLD:
		return false
	var delta := to - from
	if delta.x != 0 and delta.y != 0:
		for flank in [from + Vector2i(delta.x, 0), from + Vector2i(0, delta.y)]:
			var flank_key := _key(flank)
			if not cells.has(flank_key):
				return false
			var flank_cell: Dictionary = cells[flank_key]
			if not bool(flank_cell.get("passable", false)) \
					or bool(flank_cell.get("occupied", false)):
				return false
	return true


func _is_frontier(position: Vector2i, cells: Dictionary,
		width: int, height: int) -> bool:
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var neighbor: Vector2i = position + direction
		if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < width \
				and neighbor.y < height and not cells.has(_key(neighbor)):
			return true
	return false


func _precondition_reason(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return "session_not_initialized"
	if bool(snapshot.get("terminal", false)):
		return "auto_explore_terminal"
	if str(snapshot.get("view_mode", "")) != "EXPLORATION" \
			or str(snapshot.get("safe_phase", "")) not in ["GROUPED", "GROUPED_COMPLETE"]:
		return "auto_explore_combat_contact"
	if not snapshot.get("visible_enemy_keys", {}).is_empty():
		return "auto_explore_enemy_visible"
	return ""


func _change_reason(snapshot: Dictionary) -> String:
	var blocker := _precondition_reason(snapshot)
	if not blocker.is_empty():
		return blocker
	if snapshot.get("health", {}) != _health_baseline:
		return "auto_explore_health_changed"
	if str(snapshot.get("objective_signature", "")) != _objective_signature:
		return "auto_explore_objective_discovered"
	var hazards: Dictionary = snapshot.get("hazards", {})
	for key_value in hazards:
		if not _known_hazard_keys.has(key_value) \
				and int(hazards[key_value]) > AFFINITY_SAFE_RISK_THRESHOLD:
			return "auto_explore_hazard_discovered"
	var discoveries: Dictionary = snapshot.get("discoveries", {})
	for key_value in discoveries:
		if not _known_discovery_keys.has(key_value):
			return "auto_explore_interaction_discovered"
	return ""


func _stop(reason: String, advanced: bool = false,
		next_position: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	_running = false
	_stop_reason = reason
	return _state(reason, advanced, next_position)


func _state(reason: String, advanced: bool = false,
		next_position: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var route_state: Dictionary = {}
	var owner = _owner()
	if owner != null:
		route_state = owner.exploration_route_state()
	return {"schema_version":SCHEMA_VERSION, "running":_running,
		"reason":reason, "stop_reason":"" if _running else _stop_reason,
		"advanced":advanced,
		"target":[_target.x, _target.y] if _target.x >= 0 else [],
		"target_visibility":_target_visibility,
		"next_position":[next_position.x, next_position.y] \
			if next_position.x >= 0 else [],
		"steps_committed":_steps_committed,
		"started_step_index":_started_step_index,
		"last_step_index":_last_step_index,
		"affinity_safe_risk_threshold":AFFINITY_SAFE_RISK_THRESHOLD,
		"route_state":route_state.duplicate(true),
		"last_step_result":_last_step_result.duplicate(true)}.duplicate(true)


func _snapshot() -> Dictionary:
	var owner = _owner()
	return owner._auto_explore_fog_snapshot() if owner != null else {}


func _owner():
	return _session_ref.get_ref()


func _wire_position(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)


func _key(position: Vector2i) -> String:
	return "%d:%d" % [position.x, position.y]
