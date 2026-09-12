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
var last_search_expanded := 0


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
	last_search_expanded=0


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
	var search=preload("res://playtest/fog_frontier_search.gd").new()
	var result:Dictionary=search.search(snapshot,cells,start,_exhausted_frontiers)
	last_search_expanded=search.expanded
	return result


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
