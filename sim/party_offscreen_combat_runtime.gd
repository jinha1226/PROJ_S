class_name PartyOffscreenCombatRuntime
extends RefCounted

const ModelScript = preload("res://sim/party_offscreen_combat_model.gd")
const StateScript = preload("res://sim/party_offscreen_combat_state.gd")
const MAX_WORLD_TIME := 9223372036854775707
const MAX_ROUNDS_PER_ADVANCE := 8


static func advance(state_value: Variant, target_world_time: int,
		round_budget: int = MAX_ROUNDS_PER_ADVANCE) -> Dictionary:
	return advance_batch([state_value], target_world_time, round_budget)


static func advance_batch(state_values: Variant, target_world_time: int,
		round_budget: int = MAX_ROUNDS_PER_ADVANCE) -> Dictionary:
	if not state_values is Array or target_world_time < 0 \
			or target_world_time > MAX_WORLD_TIME or round_budget < 0 \
			or round_budget > MAX_ROUNDS_PER_ADVANCE:
		return _rejected("invalid_offscreen_advance_request")
	var states: Array = []
	var seen_encounters: Dictionary = {}
	for value in state_values:
		var state = _decode_state(value)
		if state == null:
			return _rejected("invalid_offscreen_authority_state")
		if seen_encounters.has(state.encounter_id):
			return _rejected("duplicate_offscreen_encounter")
		if target_world_time < state.current_world_time:
			return _rejected("offscreen_time_reversal")
		seen_encounters[state.encounter_id] = true
		states.append(state)
	states.sort_custom(func(a, b): return a.encounter_id < b.encounter_id)
	var starting_event_counts: Dictionary = {}
	for state in states:
		starting_event_counts[state.encounter_id] = state.event_rows.size()
	var processed_rows: Array = []
	while processed_rows.size() < round_budget:
		var candidate = _next_due_eligible(states, target_world_time)
		if candidate == null:
			break
		var committed: Dictionary = _commit_one_round(candidate)
		if not bool(committed.accepted):
			return _rejected(str(committed.reason_code))
		processed_rows.append({"encounter_id":str(candidate.encounter_id),
			"round_index":str(candidate.round_index - 1),
			"world_time":str(candidate.current_world_time)})
	var paused_rows := _paused_rows(states, target_world_time)
	var budget_exhausted := _next_due_eligible(states, target_world_time) != null
	var state_rows: Array = []
	var emitted_event_rows: Array = []
	for state in states:
		var wire: Dictionary = state.to_dict()
		state_rows.append(wire)
		var event_start := int(starting_event_counts[state.encounter_id])
		for index in range(event_start, wire.event_rows.size()):
			var event: Dictionary = wire.event_rows[index].duplicate(true)
			event["encounter_id"] = str(state.encounter_id)
			emitted_event_rows.append(event)
	return {"accepted":true, "reason_code":"ok", "state_rows":state_rows,
		"rounds_processed":processed_rows.size(),
		"budget_exhausted":budget_exhausted, "paused_rows":paused_rows,
		"processed_rows":processed_rows, "event_rows":emitted_event_rows}


static func _decode_state(value: Variant):
	if typeof(value) == TYPE_OBJECT and is_instance_valid(value) \
			and value.get_script() == StateScript:
		return value.clone()
	if value is Dictionary:
		return StateScript.from_dict(value)
	return null


static func _next_due_eligible(states: Array, target_world_time: int):
	var selected = null
	for state in states:
		if state.encounter_phase != "ENGAGED" or state.next_round_at < 0 \
				or state.next_round_at > target_world_time:
			continue
		var assessment: Dictionary = ModelScript.assess(
			state.model_input(state.next_round_at))
		if not bool(assessment.eligible):
			continue
		if selected == null or state.next_round_at < selected.next_round_at \
				or (state.next_round_at == selected.next_round_at \
				and state.encounter_id < selected.encounter_id):
			selected = state
	return selected


static func _paused_rows(states: Array, target_world_time: int) -> Array:
	var result: Array = []
	for state in states:
		if state.encounter_phase != "ENGAGED" or state.next_round_at < 0 \
				or state.next_round_at > target_world_time:
			continue
		var assessment: Dictionary = ModelScript.assess(
			state.model_input(state.next_round_at))
		if bool(assessment.eligible):
			continue
		result.append({"encounter_id":str(state.encounter_id),
			"reason_code":str(assessment.reason_code)})
	return result


static func _commit_one_round(state) -> Dictionary:
	var due_time := int(state.next_round_at)
	if due_time < state.current_world_time or due_time > MAX_WORLD_TIME:
		return {"accepted":false, "reason_code":"invalid_offscreen_next_round"}
	var forecast: Dictionary = ModelScript.forecast_round(
		state.model_input(due_time))
	if not bool(forecast.accepted):
		return {"accepted":false, "reason_code":str(forecast.reason_code)}
	var impacts_by_target: Dictionary = {}
	for impact in forecast.impact_rows:
		var target_id := int(impact.target_id)
		if not impacts_by_target.has(target_id):
			impacts_by_target[target_id] = {"projected_damage_milli":0,
				"source_actor_ids":[], "source_side_id":str(impact.source_side_id)}
		var aggregate: Dictionary = impacts_by_target[target_id]
		aggregate.projected_damage_milli += int(impact.projected_damage_milli)
		aggregate.source_actor_ids.append(int(impact.actor_id))
	var target_ids: Array = impacts_by_target.keys(); target_ids.sort()
	var damage_event_count := 0
	for target_id_value in target_ids:
		var target_id := int(target_id_value)
		var member: Dictionary = state.member_ref(target_id)
		var aggregate: Dictionary = impacts_by_target[target_id]
		aggregate.source_actor_ids.sort()
		if member.is_empty() or str(member.life_state) != "ACTIVE" \
				or not state.damage_remainders.has(target_id):
			return {"accepted":false,
				"reason_code":"offscreen_target_projection_mismatch"}
		var remainder_before := int(state.damage_remainders[target_id])
		var projected := int(aggregate.projected_damage_milli)
		var accumulated := remainder_before + projected
		var requested_damage := int(accumulated / 1000)
		var remainder_after := int(accumulated % 1000)
		var health_before := int(member.health)
		var applied_damage := mini(health_before, requested_damage)
		var health_after := health_before - applied_damage
		member.health = health_after
		state.damage_remainders[target_id] = remainder_after
		var damage_event_id := _emit(state, due_time,
			"offscreen.damage_resolved", target_id, applied_damage, -1,
			{"health_before":health_before, "health_after":health_after,
				"projected_damage_milli":projected,
				"remainder_before":remainder_before,
				"remainder_after":remainder_after,
				"source_actor_ids":aggregate.source_actor_ids.duplicate(),
				"source_side_id":str(aggregate.source_side_id)})
		if damage_event_id < 0:
			return {"accepted":false, "reason_code":"offscreen_event_overflow"}
		damage_event_count += 1
		if health_after > 0:
			continue
		var downed_id := _emit(state, due_time, "offscreen.entity_downed",
			target_id, 0, damage_event_id, {"previous_life_state":"ACTIVE"})
		if downed_id < 0:
			return {"accepted":false, "reason_code":"offscreen_event_overflow"}
		member.life_state = "DOWNED"
		var death_id := _emit(state, due_time, "offscreen.entity_died",
			target_id, 0, downed_id, {"previous_life_state":"DOWNED",
				"reason":"EXPECTED_DAMAGE"})
		if death_id < 0:
			return {"accepted":false, "reason_code":"offscreen_event_overflow"}
		member.life_state = "DEAD"
		state.damage_remainders[target_id] = 0
	_normalize_dead_focus_targets(state)
	var active_side_ids := _active_side_ids(state)
	var last_event_id: int = state.next_event_id - 1 \
		if not state.event_rows.is_empty() else -1
	var round_event_id := _emit(state, due_time, "offscreen.round_resolved", -1,
		forecast.impact_rows.size(), last_event_id,
		{"active_side_ids":active_side_ids.duplicate(),
			"damage_event_count":damage_event_count,
			"impact_count":forecast.impact_rows.size(),
			"ruleset_id":ModelScript.RULESET_ID})
	if round_event_id < 0:
		return {"accepted":false, "reason_code":"offscreen_event_overflow"}
	state.current_world_time = due_time
	if active_side_ids.size() < 2:
		state.encounter_phase = "TERMINAL"
		state.next_round_at = -1
		var outcome := "MUTUAL_DEFEAT" if active_side_ids.is_empty() else "SIDE_VICTORY"
		if _emit(state, due_time, "offscreen.encounter_resolved", -1, 0,
				round_event_id, {"active_side_ids":active_side_ids.duplicate(),
					"outcome":outcome}) < 0:
			return {"accepted":false, "reason_code":"offscreen_event_overflow"}
	else:
		if due_time > MAX_WORLD_TIME - ModelScript.ROUND_TIME:
			return {"accepted":false, "reason_code":"offscreen_time_overflow"}
		state.next_round_at = due_time + ModelScript.ROUND_TIME
	state.round_index += 1
	var validation_error: String = state.validation_error()
	return {"accepted":validation_error.is_empty(),
		"reason_code":"ok" if validation_error.is_empty() else validation_error}


static func _emit(state, world_time: int, type: String, target_id: int,
		magnitude: int, cause_id: int, data: Dictionary) -> int:
	if state.next_event_id <= 0 or state.next_event_id >= 9223372036854775807:
		return -1
	var event_id := int(state.next_event_id)
	state.next_event_id += 1
	state.event_rows.append({"event_id":event_id, "world_time":world_time,
		"round_index":int(state.round_index), "type":type,
		"target_id":target_id, "magnitude":magnitude, "cause_id":cause_id,
		"data":data.duplicate(true)})
	return event_id


static func _normalize_dead_focus_targets(state) -> void:
	for side in state.side_rows:
		if str(side.command_id) != "ATTACK_TARGET":
			continue
		var target: Dictionary = state.member_ref(int(side.target_id))
		if target.is_empty() or str(target.life_state) != "ACTIVE":
			side.command_id = "FOLLOW"
			side.target_id = -1


static func _active_side_ids(state) -> Array:
	var result: Array = []
	for side in state.side_rows:
		var active := false
		for member in side.member_rows:
			if str(member.life_state) == "ACTIVE":
				active = true
				break
		if active:
			result.append(str(side.side_id))
	result.sort()
	return result


static func _rejected(reason_code: String) -> Dictionary:
	return {"accepted":false, "reason_code":reason_code, "state_rows":[],
		"rounds_processed":0, "budget_exhausted":false, "paused_rows":[],
		"processed_rows":[], "event_rows":[]}
