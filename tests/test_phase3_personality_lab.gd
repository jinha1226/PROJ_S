extends "res://tests/test_case.gd"

const PersonalityRegistry = preload("res://sim/personality_definition_registry.gd")
const DecisionRegistry = preload("res://sim/decision_ruleset_registry.gd")
const FixedPoint = preload("res://sim/fixed_point.gd")
const Session = preload("res://playtest/playtest_session.gd")
const Simulator = preload("res://sim/simulator.gd")
const WorldState = preload("res://sim/world_state.gd")
const BodyStateScript = preload("res://sim/body_state.gd")

func test_sha256_u31_latin_hypercube_exact_vector_and_strata() -> bool:
	var expected := {"aggression": [652, 939, 11, 457], "altruism": [357, 238, 739, 846],
		"boldness": [482, 994, 151, 739], "composure": [775, 127, 393, 738]}
	for facet_id in PersonalityRegistry.FACET_IDS:
		var values: Array = []
		var strata: Array = []
		for slot in range(4):
			var value: int = PersonalityRegistry.generate(123, slot).value(facet_id)
			values.append(value); strata.append(value / 250)
		strata.sort()
		check_eq(values, expected[facet_id], "SHA vector %s" % facet_id)
		check_eq(strata, [0, 1, 2, 3], "one of each stratum")
	return finish()

func test_fixed_point_negative_trunc_curves_endpoints_and_monotonicity() -> bool:
	check_eq(FixedPoint.trunc_div(-5, 2), -2, "negative trunc toward zero")
	check_eq(FixedPoint.interpolate(1, 0, 0, 3, -5), -1, "negative interpolation trunc")
	for curve_id in ["linear_up", "linear_down", "threshold_up", "threshold_down"]:
		check(DecisionRegistry.evaluate_curve(curve_id, -1) in [0, 1000], "low clamp")
		check(DecisionRegistry.evaluate_curve(curve_id, 1001) in [0, 1000], "high clamp")
	var previous_up := -1
	var previous_down := 1001
	for x in range(1001):
		var up: int = DecisionRegistry.evaluate_curve("linear_up", x)
		var down: int = DecisionRegistry.evaluate_curve("linear_down", x)
		check(up >= previous_up, "linear up monotonic"); check(down <= previous_down, "linear down monotonic")
		previous_up = up; previous_down = down
	return finish()

func test_profile_wire_is_strict_before_canonical_construction() -> bool:
	var valid: Dictionary = PersonalityRegistry.generate(55, 0).to_dict()
	check_eq(PersonalityRegistry.profile_wire_error(valid), "", "valid profile")
	var reversed := valid.duplicate(true); reversed.facet_rows.reverse()
	check_eq(PersonalityRegistry.profile_wire_error(reversed), "duplicate_or_unsorted_personality_facet", "unsorted rejected")
	var numeric_string := valid.duplicate(true); numeric_string.facet_rows[0].base_value = "500"
	check_eq(PersonalityRegistry.profile_wire_error(numeric_string), "invalid_personality_facet_row", "numeric string rejected")
	var extra := valid.duplicate(true); extra.extra = 1
	check_eq(PersonalityRegistry.profile_wire_error(extra), "invalid_personality_profile_keys", "unknown key rejected")
	return finish()

func test_registry_accessors_are_detached_and_missing_inputs_rejected() -> bool:
	check_eq(PersonalityRegistry.validation_error(), "", "personality registry valid")
	check_eq(DecisionRegistry.validation_error(), "", "registry valid")
	var curve = DecisionRegistry.curve("linear_up"); curve.control_points[1] = Vector2i(1000, 0)
	check_eq(DecisionRegistry.evaluate_curve("linear_up", 1000), 1000, "curve mutation detached")
	var mode = DecisionRegistry.mode("PANIC"); mode.tie_break_rank = 0
	check_eq(DecisionRegistry.mode("PANIC").tie_break_rank, 1, "mode mutation detached")
	var missing: Dictionary = DecisionRegistry.evaluate(DecisionRegistry.action("ENGAGE"), {})
	check(str(missing.error).begins_with("missing_or_invalid_input:"), "missing input rejected")
	return finish()

func test_personality_relation_and_injury_monotonicity_contracts() -> bool:
	var session = Session.new(7, 130)
	check(session.advance_ticks(1).ok, "activation")
	var lead_id: int = session.lead_roster()[0].entity_id
	var state = session.sim.world.agent_states[lead_id]
	_set_facet(state, "boldness", 0)
	var engage_low_bold := _candidate_score(session, lead_id, "ENGAGE")
	var flee_low_bold := _candidate_score(session, lead_id, "FLEE")
	_set_facet(state, "boldness", 999)
	check(_candidate_score(session, lead_id, "ENGAGE") >= engage_low_bold, "boldness does not lower ENGAGE")
	check(_candidate_score(session, lead_id, "FLEE") <= flee_low_bold, "boldness does not raise FLEE")
	_set_facet(state, "aggression", 0)
	var engage_low_aggression := _candidate_score(session, lead_id, "ENGAGE")
	_set_facet(state, "aggression", 999)
	check(_candidate_score(session, lead_id, "ENGAGE") >= engage_low_aggression, "aggression does not lower ENGAGE")
	_set_facet(state, "altruism", 0)
	var protect_low := _candidate_score(session, lead_id, "PROTECT")
	_set_facet(state, "altruism", 999)
	check(_candidate_score(session, lead_id, "PROTECT") >= protect_low, "altruism does not lower legal PROTECT")
	var threat_state = session.sim.world.agent_states[state.active_threat_id]
	threat_state.intent_target_entity_id = lead_id
	check(not _candidate_row(session, lead_id, "PROTECT").legal, "altruism cannot create PROTECT without ally danger")
	threat_state.intent_target_entity_id = session.sim.world.agent_states.keys().filter(func(id):
		return session.sim.world.agent_states[id].trial_slot == state.trial_slot \
			and session.sim.world.agent_states[id].controller_kind == "PASSIVE_ALLY")[0]

	state.mental_mode = "PANIC"
	_set_facet(state, "composure", 0)
	var low_composure_appraisal: Dictionary = session.sim.actor_coordinator.threat_appraisal(lead_id)
	var freeze_low := _candidate_score(session, lead_id, "FREEZE")
	_set_facet(state, "composure", 999)
	var high_composure_appraisal: Dictionary = session.sim.actor_coordinator.threat_appraisal(lead_id)
	check(high_composure_appraisal.panic_pressure <= low_composure_appraisal.panic_pressure, "composure lowers panic pressure")
	check(_candidate_score(session, lead_id, "FREEZE") <= freeze_low, "composure does not raise FREEZE")
	state.mental_mode = "NORMAL"

	session.sim.world.species_relations.set_relation("human", "goblin", -25, 0, 0)
	var low_prior: Dictionary = session.sim.actor_coordinator.threat_appraisal(lead_id)
	var low_flee := _candidate_score(session, lead_id, "FLEE")
	var low_engage := _candidate_score(session, lead_id, "ENGAGE")
	session.sim.world.species_relations.set_relation("human", "goblin", -25, 100, 100)
	var high_prior: Dictionary = session.sim.actor_coordinator.threat_appraisal(lead_id)
	check(high_prior.perceived_threat >= low_prior.perceived_threat and _candidate_score(session, lead_id, "FLEE") >= low_flee,
		"species fear does not lower perceived threat/FLEE")
	check(high_prior.attack_drive >= low_prior.attack_drive and _candidate_score(session, lead_id, "ENGAGE") >= low_engage,
		"species hostility does not lower attack drive/ENGAGE")
	var healthy_flee := _candidate_score(session, lead_id, "FLEE")
	session.sim.world.entities[lead_id].health = 10
	check(_candidate_score(session, lead_id, "FLEE") >= healthy_flee, "injury does not lower FLEE")
	return finish()

func _set_facet(state, facet_id: String, value: int) -> void:
	for row in state.personality_profile.facet_rows:
		if row.facet_id == facet_id: row.base_value = value; return

func _candidate_row(session, actor_id: int, reaction_id: String) -> Dictionary:
	for row in session.sim.actor_coordinator.evaluate_candidates(actor_id):
		if row.reaction_id == reaction_id: return row
	return {}

func _candidate_score(session, actor_id: int, reaction_id: String) -> int:
	return int(_candidate_row(session, actor_id, reaction_id).get("score", -1000000))

func test_lab_bootstrap_activation_symmetry_and_detached_observation() -> bool:
	var session = Session.new()
	check_eq(session.observe_lab().cells.size(), 225, "15x15 cells")
	check_eq(session.lead_roster().size(), 4, "four leads")
	var before: Dictionary = session.sim.snapshot()
	var dto: Dictionary = session.observe_lab(); dto.cells.clear()
	check_eq(session.sim.snapshot(), before, "observer pure detached")
	var result: Dictionary = session.advance_ticks(1)
	check(result.ok, "activation tick accepted")
	check_eq(session.sim.world.events.filter(func(e): return e.type == "encounter.threat_appeared").size(), 4, "four appearance")
	check_eq(session.sim.world.events.filter(func(e): return e.type == "perception.threat_noticed").size(), 4, "four perceptions")
	var activation_types: Array = session.sim.world.events.filter(func(e):
		return e.type in ["encounter.threat_appeared", "perception.threat_noticed"]).map(func(e): return e.type)
	check_eq(activation_types, ["encounter.threat_appeared", "encounter.threat_appeared",
		"encounter.threat_appeared", "encounter.threat_appeared", "perception.threat_noticed",
		"perception.threat_noticed", "perception.threat_noticed", "perception.threat_noticed"],
		"all appearances precede all perceptions")
	var objectives: Array = []
	var first_reactions: Dictionary = {}
	for lead in session.lead_roster():
		objectives.append(session.inspect_reaction(lead.entity_id).last_trace.appraisal.objective_danger)
		first_reactions[lead.reaction] = true
	check_eq(objectives, [objectives[0], objectives[0], objectives[0], objectives[0]], "objective symmetry")
	check(first_reactions.size() >= 3, "default seed first tick exposes at least three reaction classes")
	return finish()

func test_actor_batch_preflight_failure_is_atomic_and_decisions_precede_leaves() -> bool:
	var armed = Session.new(7, 1234)
	var armed_roster: Array[Dictionary] = armed.lead_roster()
	var last_lead_id: int = armed_roster[-1].entity_id
	armed.sim.world.agent_states[last_lead_id].personality_profile.facet_rows[-1].base_value = 1000
	var armed_rows_before: Array = []
	for actor_id in armed.sim.world.agent_states: armed_rows_before.append(armed.sim.world.agent_states[actor_id].to_dict())
	armed_rows_before.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.entity_id) < int(b.entity_id))
	check(not armed.advance_ticks(1).ok, "post-perception preflight failure injected")
	check_eq(armed.sim.world.encounter_lab.phase, "ARMED", "activation phase rollback")
	check_eq(armed.sim.world.events.size(), 0, "appearance/perception event rollback")
	check_eq(armed.sim.world._next_event_id, 1, "activation event ID rollback")
	var armed_rows_after: Array = []
	for actor_id in armed.sim.world.agent_states: armed_rows_after.append(armed.sim.world.agent_states[actor_id].to_dict())
	armed_rows_after.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.entity_id) < int(b.entity_id))
	check_eq(armed_rows_after, armed_rows_before, "late slot fault restores every actor field")
	for lead in armed.lead_roster():
		check_eq(armed.sim.world.agent_states[lead.entity_id].active_threat_id, -1, "perception state rollback")
	var session = Session.new(7, 124)
	check(session.advance_ticks(1).ok, "activation")
	var tick_events: Array = session.sim.world.events.filter(func(e): return e.world_time == 100)
	var first_leaf := tick_events.size()
	var last_decision := -1
	for index in range(tick_events.size()):
		if tick_events[index].type == "ai.decision_selected": last_decision = index
		if str(tick_events[index].type).begins_with("action.") and tick_events[index].type != "action.wait":
			first_leaf = mini(first_leaf, index)
	check(last_decision >= 0 and last_decision < first_leaf, "all lead decisions precede every leaf")

	var world = session.sim.world
	var state_rows: Array = []
	for actor_id in world.agent_states.keys(): state_rows.append(world.agent_states[actor_id].to_dict())
	state_rows.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.entity_id) < int(b.entity_id))
	var positions: Array = []
	for entity_id in world.entities.keys(): positions.append([entity_id, world.entities[entity_id].position, world.entities[entity_id].health])
	positions.sort_custom(func(a: Array, b: Array): return int(a[0]) < int(b[0]))
	var event_count: int = world.events.size()
	world._next_event_id = 9223372036854775806
	check(not session.advance_ticks(1).ok, "last-actor event headroom preflight rejects batch")
	world = session.sim.world
	var after_rows: Array = []
	for actor_id in world.agent_states.keys(): after_rows.append(world.agent_states[actor_id].to_dict())
	after_rows.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.entity_id) < int(b.entity_id))
	var after_positions: Array = []
	for entity_id in world.entities.keys(): after_positions.append([entity_id, world.entities[entity_id].position, world.entities[entity_id].health])
	after_positions.sort_custom(func(a: Array, b: Array): return int(a[0]) < int(b[0]))
	check_eq(after_rows, state_rows, "affect/mode/reaction/history rollback")
	check_eq(after_positions, positions, "action/damage rollback")
	check_eq(world.events.size(), event_count, "event batch rollback")
	return finish()

func test_batch_start_alive_attackers_finish_and_damage_order_is_stable() -> bool:
	var session = Session.new(7, 125)
	check(session.advance_ticks(1).ok, "activation")
	var world = session.sim.world
	var lead_id: int = session.lead_roster()[0].entity_id
	var lead_state = world.agent_states[lead_id]
	var threat_id: int = lead_state.active_threat_id
	var ally_id: int = -1
	for actor_id in world.agent_states:
		var state = world.agent_states[actor_id]
		if state.trial_slot == 0 and state.controller_kind == "PASSIVE_ALLY": ally_id = actor_id
		if state.trial_slot != 0: state.busy_until = 10000
	world.entities[ally_id].health = 0
	world.combatant_states[ally_id].life_state = "DEAD"
	world.combatant_states[ally_id].guarded_until = 0
	world.combatant_states[ally_id].guard_source_event_id = -1
	world.combatant_states[ally_id].recovery_lock_until = 0
	world.combatant_states[ally_id].recovery_source_event_id = -1
	world.combatant_states[ally_id].status_rows.clear()
	world.entities[lead_id].position = world.entities[threat_id].position + Vector2i(0, 1)
	world.entities[lead_id].health = 100
	world.entities[threat_id].health = 10
	lead_state.busy_until = 0; lead_state.current_reaction = "ENGAGE"; lead_state.commitment_until = 1000
	world.agent_states[threat_id].busy_until = 0
	var event_start: int = world.events.size()
	var processed_step_index: int = world.step_index + 1
	world.begin_step(processed_step_index)
	var batch_ok := true
	while not world.scheduled_entries.is_empty() \
			and int(world.scheduled_entries[0].due_time) <= 200:
		var entry: Dictionary = world.take_next_schedule()
		world.world_time = int(entry.due_time)
		batch_ok = session.sim._dispatch_schedule(entry, processed_step_index) and batch_ok
		if int(entry.repeat_interval) > 0: world.requeue_repeating(entry)
	world.world_time = 200
	world.finish_step()
	check(batch_ok, "two-attack batch commits through explicit outer dispatch")
	var attack_events: Array = world.events.slice(event_start).filter(func(e): return e.type == "action.melee_attack")
	check_eq(attack_events.size(), 2, "both batch-start-alive attacks emit")
	check_eq(world.entities[threat_id].health, 0, "lead attack kills threat")
	check_eq(world.entities[lead_id].health, 82, "threat attack still completes")
	var damage_events: Array = world.events.slice(event_start).filter(func(e): return e.type == "combat.physical_damage")
	check_eq(damage_events.map(func(e): return e.target_id), [lead_id, threat_id], "damage target/attacker order")
	return finish()

func test_diagonal_flanks_block_terrain_and_live_occupancy() -> bool:
	var wall_sim = Simulator.new(3, 3, 1)
	wall_sim.world.bootstrap_set_terrain(Vector2i(2, 1), "wall")
	var wall_actor = wall_sim.world.add_entity("human", "Mover", Vector2i.ONE)
	check_eq(wall_sim.assess_move(wall_actor.id, Vector2i(2, 2)).reason,
		"move_diagonal_flank_blocked", "wall flank blocks diagonal")
	var occupied_sim = Simulator.new(3, 3, 2)
	var occupied_actor = occupied_sim.world.add_entity("human", "Mover", Vector2i.ONE)
	var flank = occupied_sim.world.add_entity("human", "Flank", Vector2i(2, 1))
	check_eq(occupied_sim.assess_move(occupied_actor.id, Vector2i(2, 2)).reason,
		"move_diagonal_flank_occupied", "living flank blocks diagonal outside safe party exploration")
	check(occupied_sim.world.bootstrap_set_combatant_life_state(flank.id, "DEAD"), "dead flank life fixture")
	check(occupied_sim.assess_move(occupied_actor.id, Vector2i(2, 2)).accepted, "corpse flank does not block")
	var session = Session.new(7, 127)
	check(session.advance_ticks(1).ok, "lab activation")
	var lead_id: int = session.lead_roster()[0].entity_id
	var threat_id: int = session.sim.world.agent_states[lead_id].active_threat_id
	session.sim.world.entities[lead_id].position = Vector2i(2, 4)
	session.sim.world.entities[threat_id].position = Vector2i(4, 4)
	var diagonal := {"actor_id": lead_id, "reaction_id": "ENGAGE", "leaf_action_id": "MOVE",
		"target_entity_id": threat_id, "leaf_target_entity_id": threat_id,
		"target_position": Vector2i(4, 4), "leaf_position": Vector2i(3, 5),
		"score": 900, "tie_break_rank": 0, "decision_tier": 100}
	var into_flank := {"actor_id": threat_id, "reaction_id": "ENGAGE", "leaf_action_id": "MOVE",
		"target_entity_id": lead_id, "leaf_target_entity_id": lead_id,
		"target_position": Vector2i(2, 4), "leaf_position": Vector2i(3, 4),
		"score": 700, "tie_break_rank": 0, "decision_tier": 100}
	var intents: Array[Dictionary] = [diagonal, into_flank]
	session.sim.actor_coordinator._resolve_conflicts(intents)
	check(not diagonal.conflict_lost and into_flank.conflict_lost, "destination into diagonal flank loses deterministically")
	return finish()

func test_snapshot_rejects_cross_room_perception_trace_evidence_and_village_fields() -> bool:
	var session = Session.new(7, 126)
	check(session.advance_ticks(1).ok, "activation")
	var valid: Dictionary = session.sim.snapshot()
	var leads: Array = valid.agent_states.filter(func(row): return row.controller_kind == "LEAD")
	var threats: Array = valid.agent_states.filter(func(row): return row.controller_kind == "MELEE_THREAT")
	var cross := valid.duplicate(true)
	cross.agent_states[valid.agent_states.find(leads[0])].active_threat_id = threats[1].entity_id
	check_eq(WorldState.snapshot_restore_error(cross), "active_threat_slot_invalid", "cross-room active threat rejected")
	var bad_evidence := valid.duplicate(true)
	for event in bad_evidence.events:
		if event.type == "ai.decision_selected":
			event.data.candidates[0].gates[0].evidence_ids = ["999999"]
			break
	check_eq(WorldState.snapshot_restore_error(bad_evidence), "decision_trace_evidence_missing", "missing trace evidence rejected")
	var cross_evidence := valid.duplicate(true)
	var slot_one_notice_id := "-1"
	for event in cross_evidence.events:
		if event.type == "perception.threat_noticed" and event.data.trial_slot == 1: slot_one_notice_id = event.id
	for event in cross_evidence.events:
		if event.type == "ai.decision_selected" and event.data.trial_slot == 0:
			event.data.candidates[0].gates[0].evidence_ids = [slot_one_notice_id]; break
	check_eq(WorldState.snapshot_restore_error(cross_evidence), "decision_trace_evidence_actor_mismatch", "cross-room valid evidence rejected")
	var cross_consideration_evidence := valid.duplicate(true)
	for event in cross_consideration_evidence.events:
		if event.type == "ai.decision_selected" and event.data.trial_slot == 0:
			event.data.candidates[0].considerations[0].evidence_ids = [slot_one_notice_id]; break
	check_eq(WorldState.snapshot_restore_error(cross_consideration_evidence), "decision_trace_evidence_actor_mismatch",
		"cross-room consideration evidence rejected")
	var swapped_profile := valid.duplicate(true)
	var slot_one_profile: Array = leads[1].personality_profile.facet_rows
	for event in swapped_profile.events:
		if event.type == "ai.decision_selected" and event.data.trial_slot == 0:
			event.data.personality_facet_rows = slot_one_profile.duplicate(true); break
	check_eq(WorldState.snapshot_restore_error(swapped_profile), "decision_trace_personality_invalid", "trace profile must match actor")
	var duplicate_gate := valid.duplicate(true)
	for event in duplicate_gate.events:
		if event.type == "ai.decision_selected":
			event.data.candidates[0].gates[1] = event.data.candidates[0].gates[0].duplicate(true); break
	check_eq(WorldState.snapshot_restore_error(duplicate_gate), "decision_trace_gate_definition_mismatch", "duplicate gate rejected")
	var raw_tamper := valid.duplicate(true)
	for event in raw_tamper.events:
		if event.type == "ai.decision_selected":
			event.data.candidates[0].considerations[0].raw_input = \
				(event.data.candidates[0].considerations[0].normalized_input + 1) % 1001; break
	check_eq(WorldState.snapshot_restore_error(raw_tamper), "decision_trace_consideration_definition_mismatch", "raw/normalized mismatch rejected")
	var target_tamper := valid.duplicate(true)
	for event in target_tamper.events:
		if event.type == "ai.decision_selected" and event.data.trial_slot == 0:
			event.target_id = leads[0].entity_id; break
	check_eq(WorldState.snapshot_restore_error(target_tamper), "decision_trace_selected_target_mismatch", "decision event target mismatch rejected")
	var village := valid.duplicate(true)
	village.personal_relations.append({"observer_id": leads[0].entity_id, "subject_id": leads[1].entity_id,
		"personal_trust_delta": 0, "personal_fear_delta": 0, "gratitude": 0, "grievance": 0,
		"familiarity": 1, "last_social_time": "0", "processed_source_event_ids": []})
	check_eq(WorldState.snapshot_restore_error(village), "invalid_personal_relation_keys", "conversation fields absent from v4")
	return finish()

func test_snapshot_rejects_status_time_fixture_relation_and_combat_semantic_tampering() -> bool:
	var session = Session.new(7, 127)
	check(session.advance_ticks(10).ok, "produce active combat snapshot")
	var valid: Dictionary = session.sim.snapshot()
	var leads: Array = valid.agent_states.filter(func(row): return row.controller_kind == "LEAD")
	var allies: Array = valid.agent_states.filter(func(row): return row.controller_kind == "PASSIVE_ALLY")
	var threats: Array = valid.agent_states.filter(func(row): return row.controller_kind == "MELEE_THREAT")

	var escaped_ally := valid.duplicate(true)
	for row in escaped_ally.agent_states:
		if row.entity_id == allies[0].entity_id: row.encounter_status = "ESCAPED"; break
	check_eq(WorldState.snapshot_restore_error(escaped_ally), "non_lead_escape_invalid", "ally cannot escape")
	var escaped_threat := valid.duplicate(true)
	for row in escaped_threat.agent_states:
		if row.entity_id == threats[0].entity_id: row.encounter_status = "ESCAPED"; break
	check_eq(WorldState.snapshot_restore_error(escaped_threat), "non_lead_escape_invalid", "threat cannot escape")

	var future_busy := valid.duplicate(true)
	for row in future_busy.agent_states:
		if row.entity_id == leads[0].entity_id: row.busy_until = "9223372036854775807"; break
	check_eq(WorldState.snapshot_restore_error(future_busy), "agent_state_invalid", "unbounded busy rejected")
	var future_history := valid.duplicate(true)
	for row in future_history.agent_states:
		if row.entity_id == leads[0].entity_id and not row.action_history_rows.is_empty():
			row.action_history_rows[0].last_committed_time = str(int(valid.world_time) + 1); break
	check_eq(WorldState.snapshot_restore_error(future_history), "action_history_invalid", "future history rejected")
	var cross_position := valid.duplicate(true)
	for row in cross_position.agent_states:
		if row.entity_id == leads[0].entity_id: row.intent_target_position = [10, 5]; break
	check_eq(WorldState.snapshot_restore_error(cross_position), "agent_intent_position_cross_chamber", "cross-room intent tile rejected")
	var false_last_seen := valid.duplicate(true)
	for row in false_last_seen.agent_states:
		if row.entity_id == leads[0].entity_id: row.last_seen_position = [5, 5]; break
	check_eq(WorldState.snapshot_restore_error(false_last_seen), "last_seen_perception_mismatch", "last seen tied to notice")
	var false_notice_position := valid.duplicate(true)
	var false_notice_id := "-1"
	for event in false_notice_position.events:
		if event.type == "perception.threat_noticed" and event.data.trial_slot == 0:
			event.position = [10, 2]; false_notice_id = event.id; break
	for row in false_notice_position.agent_states:
		if row.entity_id == leads[0].entity_id:
			row.last_seen_position = [10, 2]; row.threat_notice_event_id = false_notice_id; break
	check_eq(WorldState.snapshot_restore_error(false_notice_position), "threat_notice_event_invalid", "notice remains tied to appearance slot")

	var terrain_tamper := valid.duplicate(true)
	terrain_tamper.tiles[16].terrain = "stone_floor"
	check_eq(WorldState.snapshot_restore_error(terrain_tamper), "lab_fixture_terrain_invalid", "mirrored terrain immutable")
	var species_tamper := valid.duplicate(true)
	for row in species_tamper.entities:
		if row.id == leads[0].entity_id: row.species_id = "goblin"; break
	for index in range(species_tamper.body_states.size()):
		var row:Dictionary=species_tamper.body_states[index]
		if row.entity_id!=leads[0].entity_id:continue
		var seed_value:=int(species_tamper.seed)
		var body=BodyStateScript.create(int(row.entity_id),"goblin",
			BodyStateScript.world_body_seed(seed_value,int(row.entity_id),"goblin"))
		if body!=null:species_tamper.body_states[index]=body.to_dict()
		break
	check_eq(WorldState.snapshot_restore_error(species_tamper), "lab_fixture_actor_identity_invalid", "fixture species immutable")
	var health_tamper := valid.duplicate(true)
	for row in health_tamper.entities:
		if row.id == leads[0].entity_id: row.max_health = 101; break
	check_eq(WorldState.snapshot_restore_error(health_tamper), "lab_fixture_actor_identity_invalid", "fixture max health immutable")

	var relation_tamper := valid.duplicate(true)
	relation_tamper.personal_relations.append({"observer_id": leads[0].entity_id, "subject_id": leads[1].entity_id,
		"personal_trust_delta": 0, "personal_fear_delta": 0, "gratitude": 0, "grievance": 0,
		"processed_source_event_ids": []})
	check_eq(WorldState.snapshot_restore_error(relation_tamper), "cross_chamber_relation_invalid", "cross-room relation rejected")

	var cross_attack := valid.duplicate(true)
	for event in cross_attack.events:
		if event.type == "action.melee_attack": event.target_id = threats[1].entity_id; break
	check_eq(WorldState.snapshot_restore_error(cross_attack),
		"canonical_melee_guard_source_invalid", "cross-room melee rejected")
	var leaf_type_tamper := valid.duplicate(true)
	for event in leaf_type_tamper.events:
		if event.type == "action.move" and event.cause_id != "-1": event.type = "action.freeze"; break
	check_eq(WorldState.snapshot_restore_error(leaf_type_tamper), "reaction_leaf_mapping_invalid", "reaction-to-leaf mapping immutable")
	var damage_rewire := valid.duplicate(true)
	var threat_ids: Array = threats.map(func(row): return row.entity_id)
	for event in damage_rewire.events:
		if event.type != "combat.physical_damage": continue
		var attack = damage_rewire.events[int(event.cause_id) - 1]
		if attack.actor_id not in threat_ids: continue
		for notice in damage_rewire.events:
			if notice.type == "perception.threat_noticed" and notice.instigator_id == event.instigator_id:
				event.cause_id = notice.id; break
		break
	check_eq(WorldState.snapshot_restore_error(damage_rewire), "physical_damage_chain_invalid", "damage must cite melee")
	var death_rewire := valid.duplicate(true)
	for event in death_rewire.events:
		if event.type != "entity.died" or event.data.get("damage_type") != "physical": continue
		var damage = death_rewire.events[int(event.cause_id) - 1]
		event.cause_id = damage.cause_id
		break
	check_eq(WorldState.snapshot_restore_error(death_rewire),
		"canonical_bleedout_death_invalid", "death must cite damage")
	return finish()

func test_actor_tick_failure_and_cross_chamber_relation_are_transactional_no_ops() -> bool:
	var session = Session.new(7, 128)
	var before: Dictionary = session.sim.snapshot()
	var journal_before: Array = session.command_journal.duplicate(true)
	session.sim.actor_coordinator._test_force_tick_failure = true
	var failed: Dictionary = session.advance_ticks(1)
	check(not failed.ok, "forced actor cadence failure rejected")
	check_eq(failed.reason, "actor_tick_failed", "failure propagated")
	check_eq(session.sim.snapshot(), before, "command/time/schedules/events exact rollback")
	check_eq(session.command_journal, journal_before, "failed command not journaled")

	check(session.advance_ticks(1).ok, "restored coordinator continues")
	var lead_ids: Array = session.lead_roster().map(func(row): return row.entity_id)
	var notice = session.sim.world.events.filter(func(event):
		return event.type == "perception.threat_noticed" and event.actor_id == lead_ids[0])[0]
	var relation_count: int = session.sim.world.personal_relations.size()
	var event_count: int = session.sim.world.events.size()
	check(not session.sim.relationships.record_aid(lead_ids[0], lead_ids[1], notice.id, 10),
		"runtime cross-room aid rejected")
	check_eq(session.sim.world.personal_relations.size(), relation_count, "no cross-room relation row")
	check_eq(session.sim.world.events.size(), event_count, "no cross-room relationship event")
	return finish()

func test_committed_mode_switch_and_history_evidence_is_bounded_and_authoritative() -> bool:
	var session = Session.new(7, 129)
	check(session.advance_ticks(1).ok, "initial decisions")
	for lead in session.lead_roster():
		var trace: Dictionary = session.inspect_reaction(lead.entity_id).last_trace
		check(trace.has("mode_transition_evidence") and trace.has("switch_evidence"), "explicit evidence rows")
		check(not trace.mode_transition_evidence.transitioned, "initial mode retained")
		check_eq(trace.switch_evidence.reason_code, "entered", "initial reaction entry explained")
	check(session.advance_ticks(1).ok, "continuation decisions")
	var retained_seen := false
	for lead in session.lead_roster():
		var switch_evidence: Dictionary = session.inspect_reaction(lead.entity_id).last_trace.switch_evidence
		if switch_evidence.retained:
			retained_seen = true
			check(switch_evidence.reason_code in ["continued_best", "retained_commitment", "retained_margin"],
				"retain reason explicit")
	check(retained_seen, "at least one actual retained reaction")

	var panic_session = Session.new(7, 130)
	check(panic_session.advance_ticks(1).ok, "panic fixture activation")
	var panic_lead_id: int = panic_session.lead_roster()[0].entity_id
	var panic_state = panic_session.sim.world.agent_states[panic_lead_id]
	panic_state.fear = 2000; panic_state.emotion_updated_time = panic_session.sim.world.world_time
	panic_state.busy_until = 0
	check(panic_session.advance_ticks(1).ok, "panic transition decision")
	var panic_trace: Dictionary = panic_session.inspect_reaction(panic_lead_id).last_trace
	check(panic_trace.mode_transition_evidence.transitioned, "mode transition recorded")
	check_eq(panic_trace.mode_transition_evidence.from_mode, "NORMAL", "mode source")
	check_eq(panic_trace.mode_transition_evidence.to_mode, "PANIC", "mode destination")
	check_eq(panic_trace.switch_evidence.reason_code, "mode_transition_reset", "old reaction reset explained")

	var valid: Dictionary = panic_session.sim.snapshot()
	var switch_tamper := valid.duplicate(true)
	for event in switch_tamper.events:
		if event.type == "ai.decision_selected" and event.actor_id == str(panic_lead_id):
			event.data.switch_evidence.selected_reaction = "HOLD"; break
	check_eq(WorldState.snapshot_restore_error(switch_tamper), "switch_evidence_selected_mismatch", "switch evidence immutable")
	var history_tamper := valid.duplicate(true)
	for row in history_tamper.agent_states:
		if row.entity_id != str(panic_lead_id): continue
		row.current_reaction = "HOLD"; row.current_activity = "HOLD"
		var found := false
		for history in row.action_history_rows:
			if history.action_id == "HOLD":
				history.last_committed_time = row.last_decision_time; history.consecutive_commit_count = 1; found = true
		if not found:
			row.action_history_rows.append({"action_id": "HOLD", "cooldown_until": "0",
				"last_committed_time": row.last_decision_time, "consecutive_commit_count": 1})
		row.action_history_rows.sort_custom(func(a: Dictionary, b: Dictionary): return a.action_id < b.action_id)
		break
	check_eq(WorldState.snapshot_restore_error(history_tamper), "last_decision_reaction_mismatch", "state/history cannot contradict trace")
	return finish()

func test_snapshot_round_trip_and_journal_continuation() -> bool:
	var session = Session.new(9, 123)
	check(session.advance_ticks(10).ok, "first ten ticks")
	var encoded: String = session.save_session_json()
	var clone = Session.new(1, 1)
	check(clone.load_session_json(encoded).ok, "load session")
	check_eq(clone.sim.snapshot(), session.sim.snapshot(), "loaded snapshot exact")
	check(clone.advance_ticks(1).ok and session.advance_ticks(1).ok, "continue both")
	check_eq(clone.sim.snapshot(), session.sim.snapshot(), "continuation exact")
	return finish()

func test_hundred_seed_soak_twenty_ticks() -> bool:
	var reactions_seen: Dictionary = {}
	var leaves_seen: Dictionary = {}
	for seed in range(100):
		var session = Session.new(7, seed)
		check(session.advance_ticks(10).ok, "seed %d ticks 1" % seed)
		check(session.advance_ticks(10).ok, "seed %d ticks 2" % seed)
		check_eq(session.observe_lab().cells.size(), 225, "seed %d cells" % seed)
		var settled_error: String = session.sim.world.world_state_error()
		check(settled_error.is_empty(), "seed %d settled valid (%s)" % [seed, settled_error])
		var occupancy: Dictionary = {}
		for actor_id in session.sim.world.agent_states:
			var state = session.sim.world.agent_states[actor_id]
			var entity = session.sim.world.entities[actor_id]
			check(state.current_reaction in state.REACTIONS and state.current_activity in state.ACTIVITIES,
				"seed %d registered reaction/leaf" % seed)
			reactions_seen[state.current_reaction] = true; leaves_seen[state.current_activity] = true
			if state.intent_target_entity_id > 0:
				check_eq(session.sim.world.agent_states[state.intent_target_entity_id].trial_slot, state.trial_slot,
					"seed %d no cross-room intent" % seed)
			if entity.is_alive() and state.encounter_status == "ACTIVE":
				var key := "%d:%d" % [entity.position.x, entity.position.y]
				check(not occupancy.has(key), "seed %d no duplicate occupancy" % seed); occupancy[key] = true
		for event in session.sim.world.events:
			if event.type == "action.move": leaves_seen.MOVE = true
			elif event.type == "action.melee_attack": leaves_seen.MELEE_ATTACK = true
			elif event.type == "action.hold": leaves_seen.HOLD = true
			elif event.type == "action.freeze": leaves_seen.FREEZE = true
			elif event.type == "encounter.actor_escaped": leaves_seen.ESCAPE = true
	check(reactions_seen.size() >= 3, "soak covers at least three reaction states")
	check(leaves_seen.has("MOVE") and (leaves_seen.has("MELEE_ATTACK") or leaves_seen.has("HOLD")), "soak covers shared leaves")
	return finish()
