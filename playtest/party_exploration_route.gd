class_name PartyExplorationRoute
extends RefCounted

const CommandScript = preload("res://sim/sim_command.gd")
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")

const SCHEMA_VERSION := 1

var _session_ref: WeakRef
var _draft: Dictionary = {}
var _active: Dictionary = {}
var _last_state: Dictionary = {}


func _init(session) -> void:
	_session_ref = weakref(session)


func _owner():
	return _session_ref.get_ref()


func clear() -> void:
	_draft.clear()
	_active.clear()
	_last_state.clear()


func cancel_for_direct_command() -> void:
	_draft.clear()
	_active.clear()
	_last_state.clear()


func preview(goal_value: Variant) -> Dictionary:
	if not _active.is_empty():
		return _route_feedback(_public_state(_active), "route_already_active")
	var parsed := _parse_position(goal_value)
	if not bool(parsed.get("ok", false)):
		_draft.clear()
		return _empty_feedback("invalid_route_goal")
	var plan := _build_plan(parsed.position)
	if not bool(plan.get("accepted", false)):
		_draft.clear()
		return _route_feedback(_public_state(plan), str(plan.get("reason", "route_unavailable")))
	_draft = plan.duplicate(true)
	_last_state.clear()
	return _route_feedback(_public_state(_draft), "ok")


func draft() -> Dictionary:
	if _draft.is_empty():
		return _empty_feedback("route_preview_required")
	return _route_feedback(_public_state(_draft), str(_draft.get("reason", "ok")))


func state() -> Dictionary:
	if not _active.is_empty():
		return _route_feedback(_public_state(_active), str(_active.get("reason", "ok")))
	if not _draft.is_empty():
		return _route_feedback(_public_state(_draft), str(_draft.get("reason", "ok")))
	if not _last_state.is_empty():
		return _route_feedback(_public_state(_last_state), str(_last_state.get("reason", "ok")))
	return _empty_feedback("route_preview_required")


func start(goal_value: Variant, supplied_plan_hash: String) -> Dictionary:
	if not _active.is_empty():
		return _route_feedback(_public_state(_active), "route_already_active")
	var parsed := _parse_position(goal_value)
	if not bool(parsed.get("ok", false)):
		return _empty_feedback("invalid_route_goal")
	if _draft.is_empty():
		return _empty_feedback("route_preview_required")
	if supplied_plan_hash.is_empty() or supplied_plan_hash != str(_draft.get("plan_hash", "")) \
			or parsed.position != _wire_position(_draft.get("goal", [-1, -1])):
		return _stop_draft("route_plan_mismatch")
	# The internal draft is the canonical value object; the caller only supplies
	# its goal and detached hash. `_advance_one()` performs the same ordered live
	# validation used by every continuation, which preserves exact blocker,
	# diagonal, hazard and generic-stale reasons on the first hop as well.
	_active = _draft.duplicate(true)
	_draft.clear()
	_active["active"] = true
	_active["completed"] = false
	_active["terminal"] = false
	_active["completed_steps"] = 0
	_active["remaining_steps"] = int(_active.total_steps)
	_active["current_index"] = 0
	_active["resume_fingerprint"] = str(_active.fingerprint)
	_active["stop_reason"] = ""
	_active["last_step_result"] = null
	_active["last_step_effects"] = []
	return _advance_one()


func continue_route() -> Dictionary:
	if _active.is_empty():
		return state() if not _last_state.is_empty() else _empty_feedback("route_not_active")
	return _advance_one()


func cancel() -> Dictionary:
	var source: Dictionary = _active if not _active.is_empty() else _draft
	if source.is_empty():
		return _empty_feedback("route_not_active")
	var stopped := source.duplicate(true)
	_draft.clear()
	_active.clear()
	stopped["active"] = false
	stopped["completed"] = false
	stopped["terminal"] = true
	stopped["reason"] = "route_cancelled"
	stopped["stop_reason"] = "route_cancelled"
	_last_state = stopped.duplicate(true)
	return _route_feedback(_public_state(stopped), "route_cancelled", true)


func _advance_one() -> Dictionary:
	var validation := _validate_next_step()
	if not bool(validation.get("accepted", false)):
		return _stop_active(str(validation.get("reason", "route_stale")), false,
			validation.get("details", {}))
	var next_index := int(_active.completed_steps) + 1
	var destination := _wire_position(_active.path[next_index])
	var command = CommandScript.move_to(int(_active.actor_id), destination)
	# This is the only mutating seam in the route macro. It delegates to the same
	# one-cell facade used by manual exploration and therefore appends the existing
	# exploration journal row on success.
	var result: Dictionary = _owner()._commit_exploration_one(command, true)
	if not bool(result.get("accepted", false)):
		return _stop_active(str(result.get("reason", "route_step_rejected")), false,
			{"last_step_result": result.duplicate(true)})
	_active["completed_steps"] = next_index
	_active["remaining_steps"] = int(_active.total_steps) - next_index
	_active["current_index"] = next_index
	_active["last_step_result"] = result.duplicate(true)
	_active["last_step_effects"] = result.get("visual_effects", []).duplicate(true)
	_active["resume_fingerprint"] = _snapshot_fingerprint()

	var status: Dictionary = _owner().party_status()
	if str(status.get("safe_phase", "")) == "PARTY_DEFEATED" \
			or bool(status.get("terminal", false)):
		return _stop_active("route_party_defeated", true)
	if str(status.get("view_mode", "")) != "EXPLORATION" \
			or str(status.get("safe_phase", "")) == "CONTACT":
		return _stop_active("route_contact", true)
	if int(_active.completed_steps) >= int(_active.total_steps):
		return _stop_active("route_completed", true, {}, true)
	_active["reason"] = "ok"
	_active["stop_reason"] = ""
	return _route_feedback(_public_state(_active), "ok", true)


func _validate_next_step() -> Dictionary:
	if _owner().sim == null or _owner().sim.world == null \
			or _owner().sim.world.party_encounter == null:
		return {"accepted": false, "reason": "session_not_initialized"}
	var status: Dictionary = _owner().party_status()
	if not bool(status.get("ok", false)):
		return {"accepted": false, "reason": str(status.get("reason", "session_not_initialized"))}
	if bool(status.get("terminal", false)) or str(status.get("safe_phase", "")) == "PARTY_DEFEATED":
		return {"accepted": false, "reason": "route_party_defeated"}
	if str(status.get("view_mode", "")) != "EXPLORATION" \
			or str(status.get("safe_phase", "")) not in ["GROUPED", "GROUPED_COMPLETE"]:
		return {"accepted": false, "reason": "route_exploration_phase_required"}
	var actor_id := int(_active.get("actor_id", -1))
	if not _owner().sim.world.entities.has(actor_id) \
			or not _owner().sim.world.entities[actor_id].is_alive():
		return {"accepted": false, "reason": "route_actor_dead"}
	var next_index := int(_active.get("completed_steps", 0)) + 1
	if next_index <= 0 or next_index >= _active.get("path", []).size():
		return {"accepted": false, "reason": "route_path_changed"}
	var current: Vector2i = _owner().sim.world.entities[actor_id].position
	var expected_current: Vector2i = _wire_position(_active.path[next_index - 1])
	var next_position: Vector2i = _wire_position(_active.path[next_index])
	if current != expected_current:
		return {"accepted": false, "reason": "route_position_changed",
			"details": {"expected_position": _position_wire(expected_current),
				"actual_position": _position_wire(current)}}

	# Check the frozen next edge first so a newly occupied destination or diagonal
	# flank retains the core's exact movement reason instead of becoming a generic
	# re-path message.
	var next_preview = _owner().sim.preview(CommandScript.move_to(actor_id, next_position))
	if not bool(next_preview.accepted):
		return {"accepted": false, "reason": str(next_preview.reason),
			"details": {"destination": _position_wire(next_position)}}

	var fresh_path: Dictionary = _owner().sim.find_path(actor_id, _wire_position(_active.goal))
	if not bool(fresh_path.get("found", false)):
		return {"accepted": false, "reason": "route_path_changed"}
	var frozen_suffix: Array = _active.path.slice(next_index - 1)
	if not _same_path(fresh_path.get("path", []), frozen_suffix):
		return {"accepted": false, "reason": "route_path_changed"}

	# A route freezes every remaining terrain cost and every travelling member's
	# four-component exposure ceiling. No silent re-path or newly riskier suffix is
	# accepted, even when the immediate next cell itself remains legal.
	for frozen_step_index in range(next_index - 1, _active.steps.size()):
		var frozen_step: Dictionary = _active.steps[frozen_step_index]
		var fresh_step := _build_step(int(frozen_step.index),
			_wire_position(frozen_step.from), _wire_position(frozen_step.to), actor_id)
		if not bool(fresh_step.get("accepted", false)):
			return {"accepted": false, "reason": str(fresh_step.get("reason", "route_path_changed"))}
		if str(fresh_step.terrain_id) != str(frozen_step.terrain_id) \
				or int(fresh_step.cost) != int(frozen_step.cost) \
				or str(fresh_step.tier) != str(frozen_step.tier):
			return {"accepted": false, "reason": "route_path_changed"}
		var ceilings: Dictionary = {}
		for row in frozen_step.member_risk_ceilings:
			ceilings[int(row.entity_id)] = row
		for risk in fresh_step.member_risk_ceilings:
			var member_id := int(risk.entity_id)
			if not ceilings.has(member_id):
				return {"accepted": false, "reason": "route_party_changed"}
			var ceiling: Dictionary = ceilings[member_id]
			for component in ["fire", "water", "electric", "poison", "total"]:
				if int(risk[component]) > int(ceiling[component]):
					return {"accepted": false, "reason": "route_hazard_increased",
						"details": {"destination": fresh_step.to.duplicate(true),
							"member_id": member_id, "member_name": str(risk.display_name),
							"component": component, "preview_ceiling": int(ceiling[component]),
							"current_risk": int(risk[component])}}
		if fresh_step.member_risk_ceilings.size() != frozen_step.member_risk_ceilings.size():
			return {"accepted": false, "reason": "route_party_changed"}
	if _snapshot_fingerprint() != str(_active.get("resume_fingerprint", "")):
		return {"accepted": false, "reason": "route_stale"}
	return {"accepted": true, "reason": "ok"}


func _build_plan(goal: Vector2i) -> Dictionary:
	var base := _base_plan(goal)
	if _owner().sim == null or _owner().sim.world == null \
			or _owner().sim.world.party_encounter == null:
		base["reason"] = "session_not_initialized"
		return base
	var status: Dictionary = _owner().party_status()
	if not bool(status.get("ok", false)):
		base["reason"] = str(status.get("reason", "session_not_initialized"))
		return base
	if str(status.get("view_mode", "")) != "EXPLORATION" \
			or str(status.get("safe_phase", "")) not in ["GROUPED", "GROUPED_COMPLETE"]:
		base["reason"] = "route_exploration_phase_required"
		return base
	if not _owner().sim.world.in_bounds(goal):
		base["reason"] = "route_goal_out_of_bounds"
		return base
	var actor_id := int(status.protagonist_id)
	var actor = _owner().sim.world.entities.get(actor_id)
	if actor == null or not actor.is_alive():
		base["reason"] = "route_actor_dead"
		return base
	base["actor_id"] = actor_id
	base["from"] = _position_wire(actor.position)
	if actor.position == goal:
		base["reason"] = "route_already_at_goal"
		return base
	var found: Dictionary = _owner().sim.find_path(actor_id, goal)
	if not bool(found.get("found", false)):
		base["reason"] = _path_reason(str(found.get("reason", "route_unavailable")))
		return base
	var path_wire: Array = []
	for position in found.get("path", []):
		path_wire.append(_position_wire(position))
	if path_wire.size() < 2:
		base["reason"] = "route_unavailable"
		return base
	var step_rows: Array = []
	for index in range(1, path_wire.size()):
		var step := _build_step(index, _wire_position(path_wire[index - 1]),
			_wire_position(path_wire[index]), actor_id)
		if not bool(step.get("accepted", false)):
			base["reason"] = str(step.get("reason", "route_unavailable"))
			return base
		step.erase("accepted")
		step.erase("reason")
		step_rows.append(step)
	base["accepted"] = true
	base["reason"] = "ok"
	base["path"] = path_wire
	base["steps"] = step_rows
	base["total_steps"] = step_rows.size()
	base["total_cost"] = int(found.get("total_cost", 0))
	base["remaining_steps"] = step_rows.size()
	base["fingerprint"] = _snapshot_fingerprint()
	var hash_source := base.duplicate(true)
	hash_source.erase("plan_hash")
	base["plan_hash"] = JSON.stringify(hash_source).sha256_text()
	return base


func _build_step(index: int, from_position: Vector2i, to_position: Vector2i,
		actor_id: int) -> Dictionary:
	var assessment = _owner().sim.assess_destination(actor_id, to_position)
	if assessment == null or assessment.sample == null:
		return {"accepted": false, "reason": "route_destination_unavailable"}
	var sample = assessment.sample
	var definition: Dictionary = TerrainRegistryScript.definition(str(sample.terrain_id))
	if definition.is_empty() or not bool(sample.passable) or int(sample.move_time_cost) <= 0:
		return {"accepted": false, "reason": "move_terrain_blocked"}
	var risks: Array = []
	var state = _owner().sim.world.party_encounter
	var member_ids: Array = state.party_member_ids.duplicate()
	member_ids.sort_custom(func(a, b):
		var member_a = state.member(int(a)); var member_b = state.member(int(b))
		return int(member_a.roster_slot) < int(member_b.roster_slot) \
			if int(member_a.roster_slot) != int(member_b.roster_slot) else int(a) < int(b))
	for member_id_value in member_ids:
		var member_id := int(member_id_value)
		var member = state.member(member_id)
		var entity = _owner().sim.world.entities.get(member_id)
		if entity == null or not entity.is_alive() \
				or (member.presence != "GROUPED" and member_id != state.protagonist_id):
			continue
		var evaluated = _owner().sim.evaluate_exposure_for_entity(member_id, to_position)
		if evaluated == null:
			return {"accepted": false, "reason": "route_destination_unavailable"}
		var wire: Dictionary = evaluated.evaluation.to_dict()
		risks.append({"entity_id": member_id, "display_name": str(entity.display_name),
			"role": str(member.role), "species_id": str(entity.species_id),
			"fire": int(wire.fire_score), "water": int(wire.water_score),
			"electric": int(wire.electric_score), "poison": int(wire.poison_score),
			"total": int(wire.total_risk)})
	var max_total := 0
	for risk in risks:
		max_total = maxi(max_total, int(risk.total))
	return {"accepted": true, "reason": "ok", "index": index,
		"from": _position_wire(from_position), "to": _position_wire(to_position),
		"terrain_id": str(sample.terrain_id),
		"terrain_label": _terrain_label(str(sample.terrain_id)),
		"cost": int(sample.move_time_cost), "tier": str(assessment.speed_tier),
		"member_risk_ceilings": risks, "max_total_risk": max_total}


func _base_plan(goal: Vector2i) -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "has_preview": false,
		"accepted": false, "reason": "route_unavailable", "actor_id": -1,
		"from": [-1, -1], "goal": _position_wire(goal), "path": [],
		"plan_hash": "", "fingerprint": "", "total_steps": 0,
		"total_cost": 0, "completed_steps": 0, "remaining_steps": 0,
		"current_index": 0, "steps": [], "active": false, "completed": false,
		"terminal": false, "stop_reason": "", "last_step_result": null,
		"last_step_effects": []}


func _public_state(source: Dictionary) -> Dictionary:
	var dto := _base_plan(_wire_position(source.get("goal", [-1, -1])))
	for key in dto.keys():
		if source.has(key):
			dto[key] = source[key]
	dto["has_preview"] = bool(source.get("accepted", false)) \
		or not str(source.get("plan_hash", "")).is_empty()
	dto["last_step_effects"] = source.get("last_step_effects", []).duplicate(true)
	return dto.duplicate(true)


func _stop_draft(reason: String) -> Dictionary:
	var stopped := _draft.duplicate(true)
	_draft.clear()
	stopped["accepted"] = false
	stopped["reason"] = reason
	stopped["active"] = false
	stopped["terminal"] = true
	stopped["stop_reason"] = reason
	_last_state = stopped.duplicate(true)
	return _route_feedback(_public_state(stopped), reason)


func _stop_active(reason: String, accepted_step: bool, details: Dictionary = {},
		completed: bool = false) -> Dictionary:
	var stopped := _active.duplicate(true)
	_active.clear()
	stopped["accepted"] = accepted_step
	stopped["reason"] = reason
	stopped["active"] = false
	stopped["completed"] = completed
	stopped["terminal"] = true
	stopped["stop_reason"] = reason
	if details.has("last_step_result"):
		stopped["last_step_result"] = details.last_step_result.duplicate(true)
		stopped["last_step_effects"] = details.last_step_result.get("visual_effects", []).duplicate(true)
	_last_state = stopped.duplicate(true)
	return _route_feedback(_public_state(stopped), reason, accepted_step, details)


func _empty_feedback(reason: String) -> Dictionary:
	return _route_feedback(_base_plan(Vector2i(-1, -1)), reason)


func _route_feedback(dto: Dictionary, reason: String, accepted_override: Variant = null,
		details: Dictionary = {}) -> Dictionary:
	dto["reason"] = reason
	if accepted_override != null:
		dto["accepted"] = bool(accepted_override)
	var context := details.duplicate(true)
	context["action_type"] = "ROUTE"
	context["goal"] = dto.get("goal", [-1, -1]).duplicate(true)
	context["plan_hash"] = str(dto.get("plan_hash", ""))
	return _owner()._feedback_dto(dto, null, null, context).duplicate(true)


func _snapshot_fingerprint() -> String:
	return JSON.stringify(_owner().sim.snapshot()).sha256_text()


func _same_path(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if _wire_position(first[index]) != _wire_position(second[index]):
			return false
	return true


func _parse_position(value: Variant) -> Dictionary:
	if value is Vector2i:
		return {"ok": true, "position": value}
	if value is Array and value.size() == 2 and value[0] is int and value[1] is int:
		return {"ok": true, "position": Vector2i(int(value[0]), int(value[1]))}
	return {"ok": false, "position": Vector2i(-1, -1)}


func _wire_position(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)


func _position_wire(position: Vector2i) -> Array:
	return [position.x, position.y]


func _path_reason(reason: String) -> String:
	return {"goal_out_of_bounds": "route_goal_out_of_bounds",
		"goal_terrain_blocked": "move_terrain_blocked",
		"goal_occupied": "move_destination_occupied",
		"path_unreachable": "route_unavailable",
		"actor_not_found": "actor_not_found", "actor_dead": "route_actor_dead"}.get(
		reason, "route_unavailable")


func _terrain_label(terrain_id: String) -> String:
	return {"floor": "바닥", "stone_floor": "돌바닥", "wood_floor": "나무바닥",
		"metal": "금속 바닥", "rubble": "잔해", "shallow_water": "얕은 물",
		"wall": "벽"}.get(terrain_id, terrain_id)
