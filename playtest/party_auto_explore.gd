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
var _target_kind := ""
var _steps_committed := 0
var _started_step_index := -1
var _last_step_index := -1
var _last_step_result: Dictionary = {}
var _planned_path: Array = []
var _exhausted_frontiers: Dictionary = {}
var plan_builds := 0


func _init(session) -> void:
	_session_ref = weakref(session)


func clear() -> void:
	_running = false
	_stop_reason = "auto_explore_idle"
	_target = Vector2i(-1, -1)
	_target_visibility = ""
	_target_kind = ""
	_steps_committed = 0
	_started_step_index = -1
	_last_step_index = -1
	_last_step_result.clear()
	_planned_path.clear()
	_exhausted_frontiers.clear()
	plan_builds=0


func start() -> Dictionary:
	if _running:
		return _state("auto_explore_already_active")
	clear()
	var snapshot := _snapshot()
	var blocker := _precondition_reason(snapshot)
	if not blocker.is_empty():
		return _stop(blocker)
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
	_target_kind = str(choice.get("target_kind", "FRONTIER"))
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
	var canonical_result: Dictionary = owner._commit_auto_explore_one(next_position)
	# Preserve the established nested result DTO consumed by sandbox motion/VFX;
	# only the redundant one-step route plan allocation is gone.
	var result := {"accepted":bool(canonical_result.get("accepted", false)),
		"reason":str(canonical_result.get("reason", "auto_explore_route_rejected")),
		"active":false, "completed":bool(canonical_result.get("accepted", false)),
		"terminal":true, "stop_reason":"route_completed" \
			if bool(canonical_result.get("accepted", false)) else "route_rejected",
		"last_step_result":canonical_result.duplicate(true),
		"last_step_effects":canonical_result.get("visual_effects", []).duplicate(true)}
	_last_step_result = result.duplicate(true)
	if not bool(canonical_result.get("accepted", false)) \
			or owner.command_journal.size() != journal_before + 1 \
			or int(owner.sim.world.step_index) != step_before + 1:
		return _stop("auto_explore_route_rejected")
	_steps_committed += 1
	_last_step_index = int(owner.sim.world.step_index)
	# After committing, only structural phase/terminal state and newly confirmed
	# enemies can stop AUTO. Do not rebuild every discovered cell a second time in
	# the same hop merely to answer those questions; the next hop still takes a
	# fresh full fog-safe planning snapshot before choosing any destination.
	var after := _stop_snapshot()
	var stop_after := _change_reason(after)
	if not stop_after.is_empty():
		return _stop(stop_after, true, next_position)
	return _state("ok", true, next_position)


func _choose_frontier(snapshot: Dictionary) -> Dictionary:
	var cells: Dictionary = snapshot.get("cells", {})
	var current := _wire_position(snapshot.get("hero_position", [-1, -1]))
	# Reaching a reveal boundary is the probe. A boundary still present after
	# standing there is occluded, not an invitation to bounce back to it.
	_exhausted_frontiers[_key(current)] = true
	if _planned_path.size() > 1 and _planned_path[1] == current:
		_planned_path.pop_front()
	if _planned_path.size() > 1 and _planned_path[0] == current:
		var valid := true
		for i in range(1, _planned_path.size()):
			if not _known_step_is_safe(_planned_path[i-1], _planned_path[i], cells):
				valid = false; break
		if valid and (snapshot.get("visible", {}) as Dictionary).has(_key(_planned_path[1])):
			return {"found":true,"target":_target,"visibility_state":_target_visibility,
				"target_kind":_target_kind,"path":_planned_path}
	_planned_path.clear()
	if bool(snapshot.get("path_only",false)):
		snapshot=_owner()._auto_explore_fog_snapshot()
		cells=snapshot.get("cells",{})
	var choice := _nearest_safe_frontier(snapshot, cells, current)
	if bool(choice.get("found", false)):
		_planned_path = choice.path.duplicate()
	return choice


func _nearest_safe_frontier(snapshot: Dictionary, cells: Dictionary,
		start: Vector2i) -> Dictionary:
	plan_builds+=1
	var start_key := _key(start)
	if not cells.has(start_key):
		return {"found":false, "reason":"auto_explore_no_frontier"}
	# Exit seeking: when the run publishes an exit, every candidate is scored by
	# steps + Chebyshev distance from the candidate to the exit, so AUTO explores
	# toward the exit instead of hugging its own reveal boundary around the map
	# edge. Without an exit the score is the step count, which is the old
	# nearest-frontier rule. An open, known, reachable exit is walked to directly.
	var exit := _wire_position(snapshot.get("exit_position", [-1, -1]))
	var seek_exit := exit.x >= 0 and exit.y >= 0
	var exit_open := seek_exit and bool(snapshot.get("exit_open", false))
	# Step count is the primary BFS key, so process one layer at a time and sort
	# that layer once. Storing only a parent avoids copying a growing path array
	# for every candidate.
	var open: Array[Dictionary] = [{"position":start, "steps":0, "cost":0,
		"sequence":0}]
	var best: Dictionary = {start_key:[0, 0]}
	var parents: Dictionary = {}
	var visited: Dictionary = snapshot.get("visited", {})
	var use_visited_fallback := snapshot.has("visited")
	var best_frontier: Dictionary = {}
	var best_unvisited: Dictionary = {}
	var sequence := 1
	while not open.is_empty():
		open.sort_custom(_frontier_open_less)
		# Every node of a layer shares its step count and the exit distance is
		# never negative, so once the layer's steps exceed the best frontier score
		# no later candidate can win. Keep searching while an open exit may still
		# be reached, since reaching it beats every frontier.
		if not exit_open and not best_frontier.is_empty() \
				and int(open[0].steps) > int(best_frontier.score):
			break
		var next_open: Array[Dictionary] = []
		for node in open:
			var position: Vector2i = node.position
			if best.get(_key(position), []) != [int(node.steps), int(node.cost)]:
				continue
			if exit_open and position == exit and position != start:
				return {"found":true, "target":position,
					"visibility_state":str(cells[_key(position)].get(
						"visibility_state", "MEMORY")),
					"path":_frontier_path(start, position, parents),
					"steps":int(node.steps), "cost":int(node.cost),
					"target_kind":"EXIT", "exit_distance":0}
			var exit_distance := _exit_distance(position, exit) if seek_exit else 0
			var candidate := {"position":position, "steps":int(node.steps),
				"cost":int(node.cost), "score":int(node.steps) + exit_distance,
				"exit_distance":exit_distance if seek_exit else -1}
			if position != start and not _exhausted_frontiers.has(_key(position)) \
					and not visited.has(_key(position)) and _is_frontier(position, cells,
					int(snapshot.get("width", 0)), int(snapshot.get("height", 0))):
				if best_frontier.is_empty() \
						or _frontier_candidate_less(candidate, best_frontier):
					best_frontier = candidate
			# Visibility frontiers remain the first priority. Remember the best
			# reachable safe cell the hero has never actually occupied, then use it
			# only when this whole known component has no unseen frontier left.
			elif use_visited_fallback and position != start \
					and not visited.has(_key(position)) \
					and (best_unvisited.is_empty() \
						or _frontier_candidate_less(candidate, best_unvisited)):
				best_unvisited = candidate
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
				var next_key := _key(next)
				best[next_key] = [candidate_steps, candidate_cost]
				parents[next_key] = position
				next_open.append({"position":next, "steps":candidate_steps,
					"cost":candidate_cost, "sequence":sequence})
				sequence += 1
		open = next_open
	var chosen := best_frontier
	var target_kind := "FRONTIER"
	if chosen.is_empty():
		chosen = best_unvisited
		target_kind = "UNVISITED"
	if chosen.is_empty():
		return {"found":false, "reason":"auto_explore_no_frontier"}
	var target: Vector2i = chosen.position
	var cell: Dictionary = cells[_key(target)]
	return {"found":true, "target":target,
		"visibility_state":str(cell.get("visibility_state", "MEMORY")),
		"path":_frontier_path(start, target, parents),
		"steps":int(chosen.steps), "cost":int(chosen.cost),
		"target_kind":target_kind, "exit_distance":int(chosen.exit_distance)}


func _exit_distance(position: Vector2i, exit: Vector2i) -> int:
	return maxi(absi(exit.x - position.x), absi(exit.y - position.y))


func _frontier_candidate_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.score) != int(b.score): return int(a.score) < int(b.score)
	if int(a.steps) != int(b.steps): return int(a.steps) < int(b.steps)
	if int(a.cost) != int(b.cost): return int(a.cost) < int(b.cost)
	var a_position: Vector2i = a.position
	var b_position: Vector2i = b.position
	if a_position.y != b_position.y: return a_position.y < b_position.y
	return a_position.x < b_position.x


func _frontier_open_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.steps) != int(b.steps): return int(a.steps) < int(b.steps)
	if int(a.cost) != int(b.cost): return int(a.cost) < int(b.cost)
	var a_position: Vector2i = a.position
	var b_position: Vector2i = b.position
	if a_position.y != b_position.y: return a_position.y < b_position.y
	if a_position.x != b_position.x: return a_position.x < b_position.x
	return int(a.sequence) < int(b.sequence)


func _frontier_path(start: Vector2i, goal: Vector2i,
		parents: Dictionary) -> Array:
	var reversed: Array = [goal]
	var cursor := goal
	while cursor != start:
		var parent: Variant = parents.get(_key(cursor), null)
		if not parent is Vector2i: return []
		cursor = parent
		reversed.append(cursor)
	reversed.reverse()
	return reversed


func _known_step_is_safe(from: Vector2i, to: Vector2i,
		cells: Dictionary) -> bool:
	var key := _key(to)
	if not cells.has(key):
		return false
	var cell: Dictionary = cells[key]
	if not bool(cell.get("passable", false)) \
			or bool(cell.get("occupied", false)) \
			or bool(cell.get("objective_blocked", false)) \
			or int(cell.get("risk", 0)) > AFFINITY_SAFE_RISK_THRESHOLD:
		return false
	var delta := to - from
	if delta.x != 0 and delta.y != 0:
		var passable_flanks: Array[Dictionary] = []
		for flank in [from + Vector2i(delta.x, 0), from + Vector2i(0, delta.y)]:
			var flank_key := _key(flank)
			if not cells.has(flank_key):continue
			var flank_cell: Dictionary = cells[flank_key]
			if bool(flank_cell.get("passable", false)):
				passable_flanks.append(flank_cell)
		if passable_flanks.size() == 2:
			for flank_cell in passable_flanks:
				if bool(flank_cell.get("occupied", false)):return false
		elif passable_flanks.size() == 1:
			var from_cell:Dictionary=cells.get(_key(from),{})
			if not bool(from_cell.get("diagonal_gateway", false)) \
					and not bool(cell.get("diagonal_gateway", false)) \
					and not bool(passable_flanks[0].get("diagonal_gateway", false)):
				return false
			if bool(passable_flanks[0].get("occupied", false)):return false
		else:return false
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
	if bool(snapshot.get("opening_interaction", false)):
		return "auto_explore_interaction_discovered"
	if not snapshot.get("visible_enemy_keys", {}).is_empty():
		return "auto_explore_enemy_visible"
	return ""


func _change_reason(snapshot: Dictionary) -> String:
	var blocker := _precondition_reason(snapshot)
	if not blocker.is_empty():
		return blocker
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
		"target_kind":_target_kind,
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
	return owner._auto_explore_fog_snapshot(_planned_path if _planned_path.size()>2 else []) if owner != null else {}


func _stop_snapshot() -> Dictionary:
	var owner = _owner()
	return owner._auto_explore_stop_snapshot() if owner != null else {}


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
