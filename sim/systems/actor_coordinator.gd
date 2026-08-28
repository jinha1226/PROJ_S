class_name ActorCoordinator
extends RefCounted

const PersonalityRegistry = preload("res://sim/personality_definition_registry.gd")
const DecisionRegistry = preload("res://sim/decision_ruleset_registry.gd")
const WeightedPathfinderScript = preload("res://sim/weighted_pathfinder.gd")
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const FixedPointScript = preload("res://sim/fixed_point.gd")
const MeleeCombatSystemScript = preload("res://sim/systems/melee_combat_system.gd")
const AgentStateScript = preload("res://sim/agent_state.gd")
const EncounterLabStateScript = preload("res://sim/encounter_lab_state.gd")

const PANIC_ENTER_THRESHOLD := 850
const PANIC_EXIT_THRESHOLD := 500
const THREAT_POWER_NORM := 760
const MAX_WORLD_TIME := 9223372036854775707

var world
var movement
var relationships
var damage
var pathfinder
var combat
# Deterministic fault injection used only by the transaction regression. It is
# intentionally coordinator-local and is cleared when Simulator restores the
# pre-step snapshot and rebuilds its systems.
var _test_force_tick_failure := false

func _init(p_world, p_movement, p_relationships, p_damage) -> void:
	world = p_world; movement = p_movement; relationships = p_relationships; damage = p_damage
	pathfinder = WeightedPathfinderScript.new(world, movement)
	combat = MeleeCombatSystemScript.new(world, damage)

func process_tick(processed_step_index: int, actor_schedule_id: int, due_time: int,
		tick_start_can_act_ids: Dictionary) -> bool:
	if processed_step_index <= 0 or world._active_step_index != processed_step_index \
			or actor_schedule_id <= 0 or due_time != world.world_time:
		return false
	if _test_force_tick_failure: return false
	if world.encounter_lab == null: return true
	var now: int = world.world_time
	var activation_rollback: Dictionary = {}
	if world.encounter_lab.phase == "ARMED" and now >= world.encounter_lab.activation_time:
		var pre_activation_rows: Array[Dictionary] = []
		for actor_id in _all_actor_ids(): pre_activation_rows.append(world.agent_states[actor_id].to_dict())
		activation_rollback = {"agent_rows": pre_activation_rows,
			"encounter": world.encounter_lab.to_dict(), "event_count": world.events.size(),
			"next_event_id": world._next_event_id}
		if not _activate(): return false
	var projection := _occupancy_projection()
	var leads := _actor_ids("LEAD")
	# Affect/mode projection uses temporary authoritative-shaped copies. Nothing is
	# emitted until every intent, trace and leaf mutation has passed preflight.
	var original_agent_rows: Array[Dictionary] = []
	for actor_id in _all_actor_ids(): original_agent_rows.append(world.agent_states[actor_id].to_dict())
	_project_threat_targets()
	# Perception is already chamber-filtered; affect and mode update even while busy.
	for actor_id in leads:
		var state = world.agent_states[actor_id]
		if state.encounter_status == "ACTIVE" and world.is_autonomous_target(actor_id):
			_update_affect(state, threat_appraisal(actor_id), now)
	var mode_transitions: Array[Dictionary] = []
	for actor_id in leads:
		var state = world.agent_states[actor_id]
		if state.encounter_status == "ACTIVE" and world.is_autonomous_target(actor_id):
			var transition: Dictionary = _project_mode(state, now)
			if not transition.is_empty(): mode_transitions.append(transition)
	var intents: Array[Dictionary] = []
	for actor_id in leads:
		var state = world.agent_states[actor_id]
		if tick_start_can_act_ids.has(actor_id) and state.encounter_status == "ACTIVE" \
				and world.can_act(actor_id, now) and state.busy_until <= now:
			var lead_intent: Dictionary = _decide_lead(actor_id, projection)
			var actor_transition: Dictionary = {}
			for transition in mode_transitions:
				if int(transition.actor_id) == actor_id: actor_transition = transition; break
			lead_intent["mode_transition_evidence"] = _mode_transition_evidence(state, actor_transition)
			if not actor_transition.is_empty() and str(actor_transition.old_reaction) != "NONE":
				lead_intent.switch_evidence.previous_reaction = str(actor_transition.old_reaction)
				lead_intent.switch_evidence.switch_margin = DecisionRegistry.action(str(actor_transition.old_reaction)).switch_margin
				lead_intent.switch_evidence.reason_code = "mode_transition_reset"
			intents.append(lead_intent)
	for actor_id in _actor_ids("MELEE_THREAT"):
		if tick_start_can_act_ids.has(actor_id) and world.is_autonomous_target(actor_id) \
				and world.agent_states[actor_id].encounter_status == "ACTIVE" \
				and world.agent_states[actor_id].busy_until <= now:
			if now == world.encounter_lab.activation_time:
				intents.append(_simple_intent(actor_id, "HOLD", "HOLD", -1, world.entities[actor_id].position, 0, 999))
			else: intents.append(_decide_threat(actor_id, projection))
	for actor_id in _actor_ids("PASSIVE_ALLY"):
		if tick_start_can_act_ids.has(actor_id) and world.is_autonomous_target(actor_id) \
				and world.agent_states[actor_id].encounter_status == "ACTIVE" \
				and world.agent_states[actor_id].busy_until <= now:
			intents.append(_simple_intent(actor_id, "HOLD", "HOLD", -1, world.entities[actor_id].position, 0, 999))
	_resolve_conflicts(intents)
	intents.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_slot: int = world.agent_states[int(a.actor_id)].trial_slot
		var b_slot: int = world.agent_states[int(b.actor_id)].trial_slot
		return a_slot < b_slot if a_slot != b_slot else int(a.actor_id) < int(b.actor_id))
	var preflight_error := _batch_preflight(intents, mode_transitions, projection)
	if not preflight_error.is_empty():
		_restore_agent_rows(original_agent_rows)
		if not activation_rollback.is_empty(): _rollback_activation(activation_rollback)
		return false
	var frozen_batch: Dictionary = _freeze_melee_batch(intents, processed_step_index,
		actor_schedule_id, due_time)
	if not bool(frozen_batch.get("ok", false)):
		return false
	if not _commit_batch(intents, mode_transitions, projection, now, processed_step_index,
			actor_schedule_id, due_time, frozen_batch):
		return false
	_update_complete()
	return true

func threat_appraisal(actor_id: int) -> Dictionary:
	if not world.agent_states.has(actor_id): return {}
	var state = world.agent_states[actor_id]
	if state.controller_kind != "LEAD" or state.personality_profile == null: return {}
	var actor = world.entities[actor_id]
	var threat = world.entities.get(state.active_threat_id)
	var has_threat: bool = threat != null and world.is_autonomous_target(threat.id) and _same_slot(actor_id, threat.id)
	var distance: int = 99 if not has_threat else maxi(absi(actor.position.x - threat.position.x), absi(actor.position.y - threat.position.y))
	var distance_pressure: int = clampi(1000 - maxi(0, distance - 1) * 160, 0, 1000) if has_threat else 0
	var objective: int = FixedPointScript.trunc_div(2 * THREAT_POWER_NORM + distance_pressure, 3) if has_threat else 0
	var hp_loss: int = FixedPointScript.trunc_div((actor.max_health - actor.health) * 1000, actor.max_health)
	var relation: Dictionary = relationships.effective_relation(actor_id, state.active_threat_id) if has_threat else {}
	var ally_id: int = _slot_actor(state.trial_slot, "PASSIVE_ALLY")
	var ally_relation: Dictionary = relationships.effective_relation(actor_id, ally_id) if ally_id > 0 else {}
	var ally_active: bool = ally_id > 0 and world.is_autonomous_target(ally_id) \
		and world.agent_states[ally_id].encounter_status == "ACTIVE"
	var ally_targeted: bool = has_threat and ally_active \
		and world.agent_states[state.active_threat_id].intent_target_entity_id == ally_id
	var boldness: int = state.personality_profile.value("boldness")
	var aggression: int = state.personality_profile.value("aggression")
	var composure: int = state.personality_profile.value("composure")
	var relation_fear: int = int(relation.get("fear", 0)) * 10
	var hostility: int = int(relation.get("hostility", 0)) * 10
	var perceived_target: int = clampi(objective + FixedPointScript.trunc_div(relation_fear, 2) \
		+ FixedPointScript.trunc_div(hp_loss, 2) - FixedPointScript.trunc_div(boldness, 3), 0, 2000) if has_threat else 0
	var anger_target: int = clampi(hostility + FixedPointScript.trunc_div(aggression, 2) \
		+ (200 if ally_targeted else 0), 0, 2000) if has_threat else 0
	var panic: int = clampi(state.fear + FixedPointScript.trunc_div(hp_loss, 2) \
		- FixedPointScript.trunc_div(composure, 2), 0, 2000)
	var attack_drive: int = clampi(hostility + FixedPointScript.trunc_div(aggression, 2) \
		+ FixedPointScript.trunc_div(state.anger, 2), 0, 2000)
	var concern: int = clampi(int(ally_relation.get("trust", 0)) * 10 + (500 if ally_targeted else 0), 0, 2000)
	return {"objective_danger": objective, "distance_pressure": distance_pressure,
		"species_fear_term": relation_fear, "species_hostility_term": hostility,
		"ally_support": int(ally_relation.get("trust", 0)) * 10,
		"boldness_relief": FixedPointScript.trunc_div(boldness, 3),
		"composure_relief": FixedPointScript.trunc_div(composure, 2), "perceived_threat_target": perceived_target,
		"anger_target": anger_target,
		"perceived_threat": clampi(perceived_target + FixedPointScript.trunc_div(state.fear, 2), 0, 2000),
		"attack_drive": attack_drive, "ally_concern": concern, "panic_pressure": panic,
		"hp_loss_norm": hp_loss, "ally_targeted": ally_targeted, "distance": distance}

func evaluate_candidates(actor_id: int, projection: Dictionary = {}) -> Array[Dictionary]:
	if projection.is_empty(): projection = _occupancy_projection()
	var state = world.agent_states.get(actor_id)
	if state == null or state.controller_kind != "LEAD": return []
	var appraisal := threat_appraisal(actor_id)
	var mode_def = DecisionRegistry.mode(state.mental_mode)
	var rows: Array[Dictionary] = []
	for action_id in mode_def.candidate_action_ids:
		rows.append(_evaluate_candidate(actor_id, action_id, appraisal, projection))
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if bool(a.legal) != bool(b.legal): return bool(a.legal)
		if int(a.score) != int(b.score): return int(a.score) > int(b.score)
		return int(a.tie_break_rank) < int(b.tie_break_rank))
	return rows

func _activate() -> bool:
	if world._next_event_id != world.events.size() + 1 or not world.has_event_id_headroom(8): return false
	for slot in range(4):
		var threat_id := _slot_actor(slot, "MELEE_THREAT")
		var lead_id := _slot_actor(slot, "LEAD")
		if threat_id <= 0 or lead_id <= 0 or not _same_slot(threat_id, lead_id): return false
	world.encounter_lab.phase = "ACTIVE"
	for slot in range(4):
		var threat_id := _slot_actor(slot, "MELEE_THREAT")
		var lead_id := _slot_actor(slot, "LEAD")
		var appeared = world.emit_event("encounter.threat_appeared", threat_id, lead_id,
			world.entities[threat_id].position, 1, -1, {"trial_slot": slot})
		world.encounter_lab.appearance_event_ids[slot] = appeared.id
	for slot in range(4):
		var threat_id := _slot_actor(slot, "MELEE_THREAT")
		var lead_id := _slot_actor(slot, "LEAD")
		var appeared = world.event_by_id(world.encounter_lab.appearance_event_ids[slot])
		var noticed = world.emit_event("perception.threat_noticed", lead_id, threat_id,
			world.entities[threat_id].position, 1, appeared.id, {"trial_slot": slot})
		var state = world.agent_states[lead_id]
		state.active_threat_id = threat_id; state.threat_notice_event_id = noticed.id
		state.last_seen_position = world.entities[threat_id].position; state.last_seen_time = world.world_time
	return true

func _update_affect(state, stimulus: Dictionary, now: int) -> void:
	var quanta: int = FixedPointScript.trunc_div(now - state.emotion_updated_time, 100)
	if quanta <= 0: return
	var composure: int = state.personality_profile.value("composure")
	state.fear = _approach(state.fear, int(stimulus.get("perceived_threat_target", 0)), 240 * quanta,
		(80 + FixedPointScript.trunc_div(composure, 10)) * quanta)
	state.anger = _approach(state.anger, int(stimulus.get("anger_target", 0)), 180 * quanta, 100 * quanta)
	state.fear = clampi(state.fear, 0, 2000); state.anger = clampi(state.anger, 0, 2000)
	state.emotion_updated_time += quanta * 100

func _approach(value: int, target: int, rise: int, fall: int) -> int:
	return mini(target, value + rise) if value < target else maxi(target, value - fall)

func _project_mode(state, now: int) -> Dictionary:
	var pressure := int(threat_appraisal(state.entity_id).get("panic_pressure", 0))
	var next_mode: String = state.mental_mode
	var mode_definition = DecisionRegistry.mode(state.mental_mode)
	if mode_definition == null or mode_definition.transition_policy_id != "panic-hysteresis-v1": return {}
	if state.mental_mode == "NORMAL" and pressure >= PANIC_ENTER_THRESHOLD: next_mode = "PANIC"
	elif state.mental_mode == "PANIC" and pressure <= PANIC_EXIT_THRESHOLD: next_mode = "NORMAL"
	if next_mode == state.mental_mode: return {}
	var old: String = state.mental_mode
	var old_reaction: String = state.current_reaction
	if old_reaction != "NONE": _start_cooldown(state, old_reaction, now)
	state.mental_mode = next_mode; state.mental_mode_since = now; state.commitment_until = now; state.current_reaction = "NONE"
	return {"actor_id": state.entity_id, "target_id": state.active_threat_id,
		"trial_slot": state.trial_slot, "from_mode": old, "to_mode": next_mode,
		"panic_pressure": pressure, "cause_id": state.threat_notice_event_id,
		"old_reaction": old_reaction}

func _decide_lead(actor_id: int, projection: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = evaluate_candidates(actor_id, projection)
	var selected: Dictionary = {}
	for row in candidates:
		if row.legal: selected = row; break
	if selected.is_empty(): selected = _evaluate_candidate(actor_id, "FREEZE", threat_appraisal(actor_id), projection)
	var state = world.agent_states[actor_id]
	var challenger: Dictionary = selected.duplicate(true)
	var previous_reaction: String = state.current_reaction
	var retained: bool = false
	var reason_code := "entered"
	var current_score := -1000000
	var switch_margin := 0
	if state.current_reaction != "NONE":
		var current := _evaluate_candidate(actor_id, state.current_reaction, threat_appraisal(actor_id), projection)
		current_score = int(current.score)
		var current_def = DecisionRegistry.action(current.reaction_id)
		switch_margin = current_def.switch_margin
		if current.legal and state.commitment_until > world.world_time:
			selected = current; retained = true; reason_code = "retained_commitment"
		elif current.legal and selected.reaction_id != current.reaction_id:
			if int(selected.score) < int(current.score) + current_def.switch_margin:
				selected = current; retained = true; reason_code = "retained_margin"
			else: reason_code = "switched"
		elif current.legal and selected.reaction_id == current.reaction_id:
			retained = true; reason_code = "continued_best"
		else: reason_code = "switched_illegal"
	selected["retained"] = retained
	selected["switch_evidence"] = {"previous_reaction": previous_reaction,
		"challenger_reaction": str(challenger.reaction_id), "selected_reaction": str(selected.reaction_id),
		"current_score": current_score, "challenger_score": int(challenger.score),
		"switch_margin": switch_margin, "commitment_until": str(state.commitment_until),
		"challenger_cooldown_until": str(state.history(str(challenger.reaction_id)).cooldown_until),
		"retained": retained, "reason_code": reason_code}
	selected["all_candidates"] = candidates.duplicate(true)
	return selected

func _mode_transition_evidence(state, transition: Dictionary) -> Dictionary:
	if transition.is_empty():
		var pressure: int = int(threat_appraisal(state.entity_id).get("panic_pressure", 0))
		return {"transitioned": false, "policy_id": "panic-hysteresis-v1",
			"from_mode": state.mental_mode, "to_mode": state.mental_mode,
			"panic_pressure": pressure, "enter_threshold": PANIC_ENTER_THRESHOLD,
			"exit_threshold": PANIC_EXIT_THRESHOLD, "source_event_id": str(state.threat_notice_event_id)}
	return {"transitioned": true, "policy_id": "panic-hysteresis-v1",
		"from_mode": str(transition.from_mode), "to_mode": str(transition.to_mode),
		"panic_pressure": int(transition.panic_pressure), "enter_threshold": PANIC_ENTER_THRESHOLD,
		"exit_threshold": PANIC_EXIT_THRESHOLD, "source_event_id": str(transition.cause_id)}

func _evaluate_candidate(actor_id: int, action_id: String, appraisal: Dictionary, projection: Dictionary) -> Dictionary:
	var state = world.agent_states[actor_id]; var definition = DecisionRegistry.action(action_id)
	var provider: Dictionary = _provide_candidate(actor_id, definition.candidate_provider_id, appraisal, projection)
	var target_id: int = int(provider.target_entity_id)
	var target_pos: Vector2i = provider.target_position
	var route: Dictionary = provider.route
	var gates: Array[Dictionary] = []
	var evidence: Array = [str(state.threat_notice_event_id)] if state.threat_notice_event_id > 0 else []
	var history: Dictionary = state.history(action_id)
	for gate_definition in definition.gates:
		var veto := false; var gate_reason := ""
		match gate_definition.evaluator_id:
			"alive-ready-v1":
				veto = not world.can_act(actor_id, world.world_time) or state.encounter_status != "ACTIVE" or state.busy_until > world.world_time
				if veto: gate_reason = "actor_not_alive_or_ready"
			"mode-v1":
				veto = not definition.allowed_mode_ids.has(state.mental_mode)
				if veto: gate_reason = "mode_gate"
			"target-valid-v1":
				veto = not bool(provider.legal)
				if veto: gate_reason = str(provider.reason)
			"cooldown-v1":
				veto = state.current_reaction != action_id and int(history.cooldown_until) > world.world_time
				if veto: gate_reason = "cooldown"
			_:
				veto = true; gate_reason = "unknown_gate_evaluator"
		gates.append({"gate_id": gate_definition.gate_id, "veto": veto,
			"reason": gate_reason, "evidence_ids": evidence.duplicate()})
	var legal := true; var reason := ""
	for gate in gates:
		if gate.veto:
			legal = false
			if reason.is_empty(): reason = gate.reason
	var inputs: Dictionary = {}
	for consideration in definition.considerations:
		inputs[consideration.input_id] = _normalized_input(consideration.input_id, state, appraisal)
	var utility: Dictionary = DecisionRegistry.evaluate(definition, inputs)
	return {"actor_id": actor_id, "reaction_id": action_id, "leaf_action_id": "", "decision_tier": definition.decision_tier,
		"tie_break_rank": definition.tie_break_rank, "legal": legal, "rejection_reason": reason,
		"target_entity_id": target_id, "target_position": target_pos, "score": utility.score,
		"base_score": utility.base_score, "gates": gates, "considerations": utility.considerations,
		"path": route.path, "appraisal": appraisal.duplicate(true), "mode": state.mental_mode}


func _provide_candidate(actor_id: int, provider_id: String, appraisal: Dictionary, projection: Dictionary) -> Dictionary:
	var state = world.agent_states[actor_id]
	var result := {"legal": true, "reason": "", "target_entity_id": -1,
		"target_position": world.entities[actor_id].position,
		"route": {"found": true, "reason": "already_there", "path": [world.entities[actor_id].position], "total_cost": 0, "steps": 0}}
	match provider_id:
		"threat-v1":
			result.target_entity_id = state.active_threat_id
			if state.active_threat_id <= 0 or not world.entities.has(state.active_threat_id) \
					or not world.is_autonomous_target(state.active_threat_id) or not _same_slot(actor_id, state.active_threat_id):
				result.legal = false; result.reason = "threat_not_perceived"
			else:
				result.target_position = world.entities[state.active_threat_id].position
				result.route = _route_adjacent(actor_id, state.active_threat_id, projection)
		"ally-threatened-v1":
			result.target_entity_id = _slot_actor(state.trial_slot, "PASSIVE_ALLY")
			result.target_position = _semantic(state.trial_slot, "intercept")
			if not bool(appraisal.ally_targeted): result.legal = false; result.reason = "ally_not_targeted"
			elif state.active_threat_id > 0 and combat.can_attack(actor_id, state.active_threat_id): pass
			else: result.route = pathfinder.find_path(actor_id, result.target_position, projection)
		"retreat-v1":
			result.target_position = _semantic(state.trial_slot, "retreat")
			result.route = pathfinder.find_path(actor_id, result.target_position, projection)
		"cover-v1":
			result.target_position = _semantic(state.trial_slot, "cover")
			result.route = pathfinder.find_path(actor_id, result.target_position, projection)
		"self-v1": pass
		_:
			result.legal = false; result.reason = "unknown_candidate_provider"
	if bool(result.legal) and not bool(result.route.found):
		result.legal = false; result.reason = str(result.route.reason)
	return result


func _normalized_input(input_id: String, state, appraisal: Dictionary) -> int:
	if input_id.begins_with("facet."): return state.personality_profile.value(input_id.trim_prefix("facet."))
	if input_id.begins_with("appraisal."):
		return clampi(FixedPointScript.trunc_div(int(appraisal.get(input_id.trim_prefix("appraisal."), 0)), 2), 0, 1000)
	if input_id == "context.hp_loss": return int(appraisal.hp_loss_norm)
	if input_id == "context.ally_targeted": return 1000 if appraisal.ally_targeted else 0
	if input_id == "relation.ally_trust":
		return clampi(FixedPointScript.trunc_div(int(appraisal.ally_support) + 1000, 2), 0, 1000)
	if input_id == "affect.fear": return clampi(FixedPointScript.trunc_div(state.fear, 2), 0, 1000)
	return -1

func _route_adjacent(actor_id: int, target_id: int, projection: Dictionary) -> Dictionary:
	if not world.entities.has(target_id): return {"found": false, "reason": "target_missing", "path": []}
	var actor_pos: Vector2i = world.entities[actor_id].position; var target_pos: Vector2i = world.entities[target_id].position
	if maxi(absi(actor_pos.x-target_pos.x), absi(actor_pos.y-target_pos.y)) == 1:
		return {"found": true, "reason": "in_range", "path": [actor_pos], "total_cost": 0, "steps": 0}
	var options: Array[Dictionary] = []
	for p in world.movement_neighbors(target_pos):
		var route: Dictionary = pathfinder.find_path(actor_id, p, projection)
		if route.found: options.append(route)
	if options.is_empty(): return {"found": false, "reason": "path_unreachable", "path": []}
	options.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.total_cost) != int(b.total_cost): return int(a.total_cost) < int(b.total_cost)
		var ap: Vector2i = a.path[-1]; var bp: Vector2i = b.path[-1]
		return ap.y < bp.y if ap.y != bp.y else ap.x < bp.x)
	return options[0]

func _decide_threat(actor_id: int, projection: Dictionary) -> Dictionary:
	var state = world.agent_states[actor_id]; var target_id: int = state.intent_target_entity_id
	if target_id <= 0:
		return _simple_intent(actor_id, "HOLD", "HOLD", -1, world.entities[actor_id].position, 0, 999)
	if combat.can_attack(actor_id, target_id): return _simple_intent(actor_id, "ENGAGE", "MELEE_ATTACK", target_id, world.entities[target_id].position, 800, 0)
	var route: Dictionary = _route_adjacent(actor_id, target_id, projection)
	if route.found and route.path.size() > 1: return _simple_intent(actor_id, "ENGAGE", "MOVE", target_id, route.path[1], 700, 0)
	return _simple_intent(actor_id, "HOLD", "HOLD", -1, world.entities[actor_id].position, 0, 999)


func _project_threat_targets() -> void:
	for actor_id in _actor_ids("MELEE_THREAT"):
		var state = world.agent_states[actor_id]
		var target_id := _slot_actor(state.trial_slot, "PASSIVE_ALLY")
		if target_id <= 0 or not world.is_autonomous_target(target_id) \
				or world.agent_states[target_id].encounter_status != "ACTIVE":
			target_id = _slot_actor(state.trial_slot, "LEAD")
			if target_id <= 0 or not world.is_autonomous_target(target_id) \
					or world.agent_states[target_id].encounter_status != "ACTIVE": target_id = -1
		state.intent_target_entity_id = target_id

func _simple_intent(actor_id: int, reaction: String, leaf: String, target_id: int, position: Vector2i, score: int, rank: int) -> Dictionary:
	return {"actor_id": actor_id, "reaction_id": reaction, "leaf_action_id": leaf,
		"target_entity_id": target_id, "leaf_target_entity_id": target_id,
		"target_position": position, "leaf_position": position, "score": score, "tie_break_rank": rank, "decision_tier": 100,
		"legal": true, "gates": [], "considerations": [], "base_score": score, "appraisal": {}, "mode": "", "conflict_lost": false}

func _resolve_conflicts(intents: Array[Dictionary]) -> void:
	var movers: Array[Dictionary] = []
	for intent in intents:
		_materialize_leaf(intent)
		intent["conflict_lost"] = false
		if intent.leaf_action_id == "MOVE": movers.append(intent)
	movers.sort_custom(_intent_precedes)
	var accepted: Array[Dictionary] = []
	for mover in movers:
		for winner in accepted:
			if _move_intents_conflict(mover, winner):
				mover.conflict_lost = true
				break
		if not mover.conflict_lost: accepted.append(mover)


func _intent_precedes(a: Dictionary, b: Dictionary) -> bool:
	if int(a.decision_tier) != int(b.decision_tier): return int(a.decision_tier) > int(b.decision_tier)
	if int(a.score) != int(b.score): return int(a.score) > int(b.score)
	if int(a.tie_break_rank) != int(b.tie_break_rank): return int(a.tie_break_rank) < int(b.tie_break_rank)
	return int(a.actor_id) < int(b.actor_id)


func _move_intents_conflict(a: Dictionary, b: Dictionary) -> bool:
	if a.leaf_position == b.leaf_position: return true
	var a_flanks := _move_flanks(int(a.actor_id), a.leaf_position)
	var b_flanks := _move_flanks(int(b.actor_id), b.leaf_position)
	return a_flanks.has(b.leaf_position) or b_flanks.has(a.leaf_position)


func _move_flanks(actor_id: int, destination: Vector2i) -> Array[Vector2i]:
	var origin: Vector2i = world.entities[actor_id].position
	var delta := destination - origin
	if delta.x == 0 or delta.y == 0: return []
	return [origin + Vector2i(delta.x, 0), origin + Vector2i(0, delta.y)]

func _materialize_leaf(intent: Dictionary) -> void:
	if not str(intent.get("leaf_action_id", "")).is_empty(): return
	var actor_id: int = intent.actor_id; var reaction: String = intent.reaction_id
	var definition = DecisionRegistry.action(reaction)
	var builder_id: String = "" if definition == null else definition.intent_builder_id
	var actor_pos: Vector2i = world.entities[actor_id].position
	var attack_target_id: int = world.agent_states[actor_id].active_threat_id if builder_id == "protect-v1" else int(intent.target_entity_id)
	if builder_id in ["engage-v1", "protect-v1"] and attack_target_id > 0 and combat.can_attack(actor_id, attack_target_id):
		intent.leaf_action_id = "MELEE_ATTACK"; intent.leaf_target_entity_id = attack_target_id
		intent.leaf_position = world.entities[attack_target_id].position
	elif builder_id == "flee-v1" and actor_pos == intent.target_position: intent.leaf_action_id = "ESCAPE"
	elif builder_id == "cover-v1" and actor_pos == intent.target_position: intent.leaf_action_id = "HOLD"
	elif builder_id == "hold-v1": intent.leaf_action_id = "HOLD"
	elif builder_id == "freeze-v1": intent.leaf_action_id = "FREEZE"
	elif intent.path.size() > 1: intent.leaf_action_id = "MOVE"; intent.leaf_position = intent.path[1]
	else: intent.leaf_action_id = "HOLD"
	if not intent.has("leaf_position"): intent["leaf_position"] = actor_pos
	if not intent.has("leaf_target_entity_id"): intent["leaf_target_entity_id"] = int(intent.target_entity_id)

func _batch_preflight(intents: Array[Dictionary], mode_transitions: Array[Dictionary], projection: Dictionary) -> String:
	# Registry definitions are bounded to 10,000 time units. Reserving that
	# complete horizon makes every busy/guarded/commitment/cooldown addition
	# below a checked integer operation rather than a possible wraparound.
	if (not intents.is_empty() or not mode_transitions.is_empty()) \
			and world.world_time > MAX_WORLD_TIME - 10000:
		return "actor_time_overflow"
	var maximum_events: int = mode_transitions.size()
	for intent in intents:
		var actor_id := int(intent.get("actor_id", -1))
		if not world.entities.has(actor_id) or not world.agent_states.has(actor_id): return "actor_missing"
		var state = world.agent_states[actor_id]
		if not world.can_act(actor_id, world.world_time) or state.encounter_status != "ACTIVE": return "actor_not_active"
		if state.controller_kind == "LEAD" and not PersonalityRegistry.profile_error(state.personality_profile).is_empty():
			return "invalid_personality_profile"
		var target_id := int(intent.get("target_entity_id", -1))
		if target_id > 0 and (not world.entities.has(target_id) or not _same_slot(actor_id, target_id)):
			return "cross_chamber_target"
		if state.controller_kind == "LEAD":
			maximum_events += 1
			var trace := _decision_trace(intent)
			if trace.is_empty() or JSON.stringify(trace).to_utf8_buffer().size() > 32768: return "invalid_decision_trace"
		if bool(intent.get("conflict_lost", false)): continue
		match str(intent.get("leaf_action_id", "")):
			"MOVE":
				var move_assessment = movement.assess_move_in_projection(actor_id, intent.leaf_position, projection)
				if not move_assessment.accepted:
					return "move_preflight_failed"
				intent["move_terrain_id"] = move_assessment.terrain_id
				intent["move_time_cost"] = int(TerrainRegistryScript.definition(move_assessment.terrain_id).move_time_cost)
			"MELEE_ATTACK":
				var attack_target_id := int(intent.get("leaf_target_entity_id", -1))
				if attack_target_id <= 0 or not combat.can_attack(actor_id, attack_target_id): return "attack_preflight_failed"
				maximum_events += 2 # action + damage + possible death, in addition to the common leaf event.
			"HOLD": pass
			"FREEZE":
				if state.controller_kind != "LEAD" or state.personality_profile == null: return "freeze_preflight_failed"
			"ESCAPE":
				if str(intent.reaction_id) != "FLEE" or world.entities[actor_id].position != intent.target_position:
					return "escape_preflight_failed"
			_: return "unknown_leaf_action"
		maximum_events += 1
	return "" if world.has_event_id_headroom(maximum_events) else "event_id_overflow"


func _freeze_melee_batch(intents: Array[Dictionary], processed_step_index: int,
		actor_schedule_id: int, due_time: int) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for original_action_order in range(intents.size()):
		var intent: Dictionary = intents[original_action_order]
		if bool(intent.get("conflict_lost", false)) \
				or str(intent.get("leaf_action_id", "")) != "MELEE_ATTACK":
			continue
		candidates.append({"actor_id": int(intent.actor_id),
			"target_id": int(intent.leaf_target_entity_id),
			"original_action_order": original_action_order})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.target_id) != int(b.target_id): return int(a.target_id) < int(b.target_id)
		if int(a.actor_id) != int(b.actor_id): return int(a.actor_id) < int(b.actor_id)
		return int(a.original_action_order) < int(b.original_action_order))
	var context := "PHASE3_ACTOR/%d/%d" % [actor_schedule_id, due_time]
	var rows: Dictionary = {}
	var frozen_intents: Array = []
	for ordinal in range(candidates.size()):
		var candidate: Dictionary = candidates[ordinal]
		var actor_id := int(candidate.actor_id)
		var target_id := int(candidate.target_id)
		var target = world.entities.get(target_id)
		if target == null:
			return {"ok": false, "canonical": false, "rows": {}}
		var assessment: Dictionary = combat.assess_attack(actor_id, target_id, "SUGGESTED",
			processed_step_index, due_time, context, ordinal)
		var frozen = combat.freeze_assessment(assessment, target.health,
			int(candidate.original_action_order))
		if assessment.is_empty() or frozen == null:
			return {"ok": false, "canonical": false, "rows": {}}
		frozen_intents.append(frozen)
		rows[actor_id] = {"intent": frozen, "resolution": null}
	var projected: Array = combat.project_batch(frozen_intents)
	var supported: bool = projected.size() == frozen_intents.size()
	if supported:
		for resolution in projected:
			var ordinal := int(resolution.action_data.get("intent_ordinal", -1))
			if ordinal < 0 or ordinal >= frozen_intents.size() \
					or resolution.outcome not in ["MISS", "HIT", "OVERKILL_SKIP"]:
				supported = false
				break
			var frozen = frozen_intents[ordinal]
			var actor_id := int(str(frozen.assessment.attacker_id))
			if not rows.has(actor_id):
				supported = false
				break
			rows[actor_id].resolution = resolution
	return {"ok": true, "canonical": supported, "rows": rows}


func _commit_batch(intents: Array[Dictionary], mode_transitions: Array[Dictionary], _projection: Dictionary,
			now: int, processed_step_index: int, actor_schedule_id: int, due_time: int,
			frozen_batch: Dictionary) -> bool:
	var mode_event_ids: Dictionary = {}
	mode_transitions.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.trial_slot) < int(b.trial_slot) if int(a.trial_slot) != int(b.trial_slot) else int(a.actor_id) < int(b.actor_id))
	for transition in mode_transitions:
		var event = world.emit_event("ai.mental_mode_changed", int(transition.actor_id), int(transition.target_id),
			world.entities[int(transition.actor_id)].position, int(transition.panic_pressure), int(transition.cause_id),
			{"trial_slot": int(transition.trial_slot), "from_mode": str(transition.from_mode),
				"to_mode": str(transition.to_mode), "panic_pressure": int(transition.panic_pressure),
				"enter_threshold": PANIC_ENTER_THRESHOLD, "exit_threshold": PANIC_EXIT_THRESHOLD})
		assert(event != null, "Preflighted mode event must commit")
		mode_event_ids[int(transition.actor_id)] = event.id

	# Event IDs for every lead decision are assigned before any leaf mutates the world.
	var decision_events: Dictionary = {}
	for intent in intents:
		var actor_id := int(intent.actor_id); var state = world.agent_states[actor_id]
		if state.controller_kind != "LEAD": continue
		var cause_id: int = int(mode_event_ids.get(actor_id, state.threat_notice_event_id))
		var decision = world.emit_event("ai.decision_selected", actor_id, int(intent.target_entity_id),
			world.entities[actor_id].position, maxi(0, int(intent.score)), cause_id, _decision_trace(intent))
		assert(decision != null, "Preflighted decision event must commit")
		decision_events[actor_id] = decision

	var damage_requests: Array[Dictionary] = []
	var canonical_batch: bool = bool(frozen_batch.get("canonical", false))
	var frozen_rows: Dictionary = frozen_batch.get("rows", {})
	for intent in intents:
		if bool(intent.get("conflict_lost", false)): continue
		var actor_id := int(intent.actor_id); var state = world.agent_states[actor_id]
		var decision = decision_events.get(actor_id)
		var cause_id: int = decision.id if decision != null else -1
		match str(intent.leaf_action_id):
			"MOVE":
				var move_cost := int(intent.move_time_cost)
				movement.commit_preflighted_move(actor_id, intent.leaf_position, str(intent.move_terrain_id), move_cost, cause_id)
				state.busy_until = now + move_cost
			"MELEE_ATTACK":
				var target_id := int(intent.leaf_target_entity_id)
				var frozen_row: Dictionary = frozen_rows.get(actor_id, {})
				var frozen = frozen_row.get("intent")
				var resolution = frozen_row.get("resolution")
				var action = null
				if not canonical_batch or frozen == null or resolution == null:
					return false
				var assessment: Dictionary = frozen.assessment
				var frozen_position := Vector2i(int(assessment.target_position[0]),
					int(assessment.target_position[1]))
				action = world.emit_event("action.melee_attack", actor_id, target_id,
					frozen_position, int(assessment.base_damage), cause_id,
					resolution.action_data)
				assert(action != null, "Preflighted attack event must commit")
				damage_requests.append({"target_id": target_id, "attacker_id": actor_id,
					"action_event_id": action.id, "amount": action.magnitude,
					"event_position": action.position, "intent": frozen,
					"resolution": resolution})
				state.busy_until = now + 100
			"HOLD":
				var hold = world.emit_event("action.hold", actor_id, -1, world.entities[actor_id].position, 1, cause_id)
				assert(hold != null, "Preflighted HOLD event must commit")
				state.busy_until = now + 100
				var combatant = world.combatant_states[actor_id]
				var candidate_until := now + 200
				if candidate_until > combatant.guarded_until:
					combatant.guarded_until = candidate_until; combatant.guard_source_event_id = hold.id
			"FREEZE":
				var quanta: int = 1 + FixedPointScript.trunc_div(999 - state.personality_profile.value("composure"), 250)
				var freeze = world.emit_event("action.freeze", actor_id, -1, world.entities[actor_id].position, quanta, cause_id)
				assert(freeze != null, "Preflighted FREEZE event must commit")
				state.busy_until = now + quanta * 100
			"ESCAPE":
				var escaped = world.emit_event("encounter.actor_escaped", actor_id, -1, world.entities[actor_id].position, 1, cause_id)
				assert(escaped != null, "Preflighted ESCAPE event must commit")
				state.encounter_status = "ESCAPED"; state.busy_until = now
		_commit_intent_state(intent, decision, now)

	damage_requests.sort_custom(func(a: Dictionary, b: Dictionary):
		if canonical_batch:
			return int(a.intent.assessment.intent_ordinal) < int(b.intent.assessment.intent_ordinal)
		if int(a.target_id) != int(b.target_id): return int(a.target_id) < int(b.target_id)
		if int(a.attacker_id) != int(b.attacker_id): return int(a.attacker_id) < int(b.attacker_id)
		return int(a.action_event_id) < int(b.action_event_id))
	for request in damage_requests:
		if not canonical_batch:
			return false
		var resolution = request.resolution
		var canonical_target = world.entities.get(int(request.target_id))
		var canonical_state = world.combatant_states.get(int(request.target_id))
		if canonical_target == null or canonical_state == null \
				or canonical_target.health != resolution.target_health_before \
				or canonical_state.life_state != resolution.target_life_before:
			return false
		if resolution.outcome == "MISS":
			var miss = world.emit_event("combat.attack_missed", -1, int(request.target_id),
				request.event_position, 0, int(request.action_event_id),
				{"schema_version": 1,
					"combat_ruleset_id": MeleeCombatSystemScript.COMBAT_RULESET_ID,
					"outcome": "MISS"})
			if miss == null: return false
		elif resolution.outcome == "OVERKILL_SKIP":
			pass
		elif resolution.outcome == "HIT":
			var applied: Dictionary = damage.apply_canonical_active_damage(canonical_target,
				resolution.final_damage, "physical", int(request.action_event_id),
				request.event_position, processed_step_index,
				resolution.target_health_before, resolution.terminal_immediate,
				resolution.bleed_proc_succeeded)
			var expected_applied: int = resolution.target_health_before \
				- resolution.target_health_after
			if not bool(applied.accepted) \
					or int(applied.applied_health_damage) != expected_applied:
				return false
		else:
			return false
		if canonical_target.health != resolution.target_health_after \
				or canonical_state.life_state != resolution.target_life_after:
			return false
	return true


func _commit_intent_state(intent: Dictionary, decision, now: int) -> void:
	var actor_id := int(intent.actor_id); var state = world.agent_states[actor_id]
	var old_reaction: String = state.current_reaction; var entering: bool = old_reaction != intent.reaction_id
	if entering and old_reaction != "NONE": _start_cooldown(state, old_reaction, now)
	state.current_reaction = intent.reaction_id; state.current_activity = intent.leaf_action_id
	state.intent_target_entity_id = int(intent.target_entity_id); state.intent_target_position = intent.target_position
	state.intent_started_time = now; state.last_decision_time = now
	if decision != null: state.last_decision_event_id = decision.id
	if entering:
		var definition = DecisionRegistry.action(intent.reaction_id)
		state.commitment_until = now + (definition.commitment_duration if definition != null else 100)
	var history: Dictionary = state.history(intent.reaction_id)
	history.last_committed_time = now
	history.consecutive_commit_count = 1 if entering else mini(2147483647, int(history.consecutive_commit_count) + 1)
	state.set_history(history)
	if intent.leaf_action_id == "ESCAPE":
		_start_cooldown(state, intent.reaction_id, now)
		state.current_reaction = "NONE"
		state.commitment_until = now


func _decision_trace(intent: Dictionary) -> Dictionary:
	var actor_id := int(intent.actor_id); var state = world.agent_states[actor_id]
	return {"trace_schema_version": 1, "trial_slot": state.trial_slot, "reaction_id": intent.reaction_id,
		"personality_facet_rows": state.personality_profile.facet_rows.duplicate(true), "appraisal": intent.appraisal,
		"mental_mode": state.mental_mode, "mode_transition_evidence": intent.mode_transition_evidence.duplicate(true),
		"candidates": _trace_candidates(intent.get("all_candidates", [])),
		"selected_score": intent.score, "retained": bool(intent.get("retained", false)),
		"switch_evidence": intent.switch_evidence.duplicate(true),
		"conflict_lost": bool(intent.get("conflict_lost", false)),
		"semantic_target": _semantic_name(intent.target_position, state.trial_slot)}


func _restore_agent_rows(rows: Array[Dictionary]) -> void:
	world.agent_states.clear()
	for row in rows:
		var state = AgentStateScript.from_dict(row)
		world.agent_states[state.entity_id] = state


func _rollback_activation(rollback: Dictionary) -> void:
	_restore_agent_rows(rollback.agent_rows)
	world.events.resize(int(rollback.event_count))
	world._next_event_id = int(rollback.next_event_id)
	world.encounter_lab = EncounterLabStateScript.from_dict(rollback.encounter)

func _start_cooldown(state, action_id: String, now: int) -> void:
	var definition = DecisionRegistry.action(action_id)
	if definition == null: return
	var row: Dictionary = state.history(action_id); row.cooldown_until = now + definition.cooldown_duration; state.set_history(row)

func _trace_candidates(candidates: Array) -> Array:
	var rows: Array = []
	for c in candidates.slice(0, mini(6, candidates.size())):
		rows.append({"reaction_id": c.reaction_id, "legal": c.legal, "rejection_reason": c.rejection_reason,
			"base_score": c.base_score, "score": c.score, "gates": c.gates.duplicate(true),
			"considerations": c.considerations.duplicate(true), "target_entity_id": str(c.target_entity_id),
			"target_position": [c.target_position.x, c.target_position.y]})
	return rows

func _update_complete() -> void:
	if world.encounter_lab.phase != "ACTIVE": return
	for actor_id in _actor_ids("LEAD"):
		if world.is_autonomous_target(actor_id) and world.agent_states[actor_id].encounter_status == "ACTIVE": return
	world.encounter_lab.phase = "COMPLETE"

func _actor_ids(kind: String) -> Array:
	var ids: Array = []
	for id in world.agent_states:
		if world.agent_states[id].controller_kind == kind: ids.append(id)
	ids.sort_custom(func(a, b):
		if world.agent_states[a].trial_slot != world.agent_states[b].trial_slot: return world.agent_states[a].trial_slot < world.agent_states[b].trial_slot
		return a < b)
	return ids

func _all_actor_ids() -> Array:
	var ids: Array = world.agent_states.keys()
	ids.sort()
	return ids

func _slot_actor(slot: int, kind: String) -> int:
	for id in _actor_ids(kind):
		if world.agent_states[id].trial_slot == slot: return id
	return -1

func _same_slot(a: int, b: int) -> bool:
	return world.agent_states.has(a) and world.agent_states.has(b) and world.agent_states[a].trial_slot == world.agent_states[b].trial_slot

func _origin(slot: int) -> Vector2i: return Vector2i(1 if slot % 2 == 0 else 8, 1 if slot < 2 else 8)
func _semantic(slot: int, name: String) -> Vector2i:
	var local: Vector2i = {"threat": Vector2i(3,1), "cover": Vector2i(1,3), "intercept": Vector2i(3,3), "lead": Vector2i(2,4), "ally": Vector2i(3,4), "retreat": Vector2i(1,5)}.get(name, Vector2i.ZERO)
	return _origin(slot) + local
func _semantic_name(position: Vector2i, slot: int) -> String:
	for name in ["threat", "cover", "intercept", "lead", "ally", "retreat"]:
		if _semantic(slot, name) == position: return name
	return "tile.%d.%d" % [position.x - _origin(slot).x, position.y - _origin(slot).y]

func _occupancy_projection() -> Dictionary:
	var result: Dictionary = {}
	var ids: Array = world.entities.keys(); ids.sort()
	for id in ids:
		var entity = world.entities[id]; var state = world.agent_states.get(id)
		if world.occupies_tile(id) and (state == null or state.encounter_status == "ACTIVE"):
			result["%d:%d" % [entity.position.x, entity.position.y]] = id
	return result
