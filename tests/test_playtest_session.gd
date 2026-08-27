extends "res://tests/test_case.gd"

const PlaytestSession = preload("res://playtest/playtest_session.gd")
const SimEventScript = preload("res://sim/sim_event.gd")

func test_session_reset_and_visible_view_are_deterministic_and_detached() -> bool:
	var first = PlaytestSession.new(101, 501)
	var second = PlaytestSession.new(101, 501)
	check_eq(first.snapshot_json(), second.snapshot_json(), "same seeds lab snapshot")
	var observed: Dictionary = first.observe_lab()
	check_eq(observed.cells.size(), 225, "full 15x15 lab")
	check_eq(observed.slots.size(), 4, "four slot summaries")
	var before: String = first.snapshot_json()
	observed.cells.clear(); observed.slots[0].fear = 9999
	check_eq(first.snapshot_json(), before, "observation detached")
	return finish()

func test_session_inspect_preview_commit_and_status_are_authoritative() -> bool:
	var session = PlaytestSession.new(102, 502)
	var lead_id: int = session.lead_roster()[0].entity_id
	check(session.select_lead(lead_id), "lead selected")
	var before: Dictionary = session.inspect_reaction(lead_id)
	check_eq(before.emotion.mental_mode, "NORMAL", "bootstrap mode")
	var result: Dictionary = session.advance_ticks(1)
	check(result.ok, "one WAIT tick")
	check_eq(session.lab_status().world_time, 100, "world advanced one cadence")
	check_eq(session.lab_status().command_count, 1, "external WAIT journaled once")
	var after: Dictionary = session.inspect_reaction(lead_id)
	check(after.last_decision_event_id > 0 and after.candidates.size() == 6, "trace and all mode gates exposed")
	return finish()

func test_progress_status_separates_turns_commands_and_salient_events() -> bool:
	var session = PlaytestSession.new(1021, 5021)
	var initial: Dictionary = session.progress_status()
	check_eq(initial.tick_index, 0, "initial turn")
	check_eq(initial.step_index, 0, "initial command count")
	check_eq(initial.phase_label, "조우 대기", "readable initial phase")
	check_eq(initial.active_trials, 4, "four unresolved trials")
	check(not initial.last_advance.available, "no fabricated initial advance")
	var before := session.snapshot_json()
	initial.active_trials = 0; initial.last_advance.latest_salient_event["message"] = "tampered"
	check_eq(session.snapshot_json(), before, "progress DTO is detached")
	check(session.advance_ticks(1).ok, "first visible turn")
	var first: Dictionary = session.progress_status()
	check_eq(first.tick_index, 1, "one simulation turn")
	check_eq(first.step_index, 1, "one external command")
	check_eq(first.phase_label, "전투 진행", "activation is visible")
	check_eq(first.last_advance.processed_ticks, 1, "one processed tick")
	check(first.last_advance.emitted_event_count > 0, "event count reported")
	check(not first.last_advance.latest_salient_event.is_empty() \
		and str(first.last_advance.latest_salient_event.message).ends_with("."),
		"salient event is presented as a Korean sentence")
	var narrative_session = PlaytestSession.new()
	check(narrative_session.advance_ticks(1).ok, "default first turn for narrative status")
	var narrative: Dictionary = narrative_session.progress_status().last_advance.latest_salient_event
	check_eq(narrative.get("type", ""), "ai.decision_selected",
		"meaningful decision outranks routine first-turn movement")
	check(str(narrative.get("message", "")).contains("동료") \
		and str(narrative.get("message", "")).contains("지키러 나섰다"),
		"first-turn banner tells a concrete protective decision")
	check(session.advance_ticks(10).ok, "ten visible turns")
	var tenth: Dictionary = session.progress_status()
	check_eq(tenth.tick_index, 11, "world turn count accumulates")
	check_eq(tenth.step_index, 2, "ten-turn batch remains one command")
	check_eq(tenth.last_advance.processed_ticks, 10, "batch size is explicit")
	var resolved_session = PlaytestSession.new()
	for _attempt in range(10):
		if resolved_session.progress_status().active_trials == 0: break
		check(resolved_session.advance_ticks(10).ok, "default comparison continues to outcome")
	var resolved: Dictionary = resolved_session.progress_status()
	check_eq(resolved.active_trials, 0, "all chamber outcomes become decided")
	check_eq(resolved.display_phase_id, "RESOLVED", "presentation phase cannot contradict zero rooms")
	check_eq(resolved.phase_label, "결과 확정", "resolved phase is readable")
	return finish()

func test_session_element_commands_and_returned_results_are_detached() -> bool:
	var session = PlaytestSession.new(103, 503)
	check(session.advance_ticks(1).ok, "activation")
	var before: String = session.snapshot_json()
	var inspect: Dictionary = session.inspect_reaction(session.selected_lead_id)
	inspect.candidates.clear(); inspect.personality.facet_rows[0].base_value = 999
	var events: Array[Dictionary] = session.recent_events(20)
	if not events.is_empty(): events[0].type = "tampered"
	var event_log: Array[Dictionary] = session.recent_event_log(20)
	check(not event_log.is_empty(), "presentation event log available")
	check(event_log.any(func(row: Dictionary): return str(row.message).contains("발견했다") \
			or str(row.message).contains("기로 했다")), "event log has natural Korean incident sentences")
	check(not event_log.any(func(row: Dictionary): return str(row.message).contains("반응 선택") \
			or str(row.message).contains("NORMAL") or str(row.message).contains("PANIC")),
		"presentation messages hide internal state names")
	if not event_log.is_empty(): event_log[0].message = "tampered"
	check_eq(session.snapshot_json(), before, "inspector and events detached")
	return finish()

func test_event_presentation_maps_mode_and_decision_payloads_without_mutating_core() -> bool:
	var session = PlaytestSession.new(7, 9001)
	var lead_id: int = session._actor_id_for_slot("LEAD", 0)
	var ally_id: int = session._actor_id_for_slot("PASSIVE_ALLY", 0)
	var threat_id: int = session._actor_id_for_slot("MELEE_THREAT", 0)
	var position: Vector2i = session.sim.world.entities[lead_id].position
	var snapshot_before := session.snapshot_json()
	var journal_before := session.command_journal_json()
	var panic_event = SimEventScript.new(9001, 0, 100, "ai.mental_mode_changed",
		lead_id, threat_id, position, 900, -1, -1,
		{"from_mode": "NORMAL", "to_mode": "PANIC", "panic_pressure": 900})
	var recovery_event = SimEventScript.new(9002, 0, 200, "ai.mental_mode_changed",
		lead_id, threat_id, position, 400, -1, -1,
		{"from_mode": "PANIC", "to_mode": "NORMAL", "panic_pressure": 400})
	var engage_event = SimEventScript.new(9003, 0, 200, "ai.decision_selected",
		lead_id, threat_id, position, 800, -1, -1,
		{"reaction_id": "ENGAGE", "retained": false,
			"switch_evidence": {"previous_reaction": "TAKE_COVER"}})
	var protect_event = SimEventScript.new(9004, 0, 200, "ai.decision_selected",
		lead_id, ally_id, position, 700, -1, -1,
		{"reaction_id": "PROTECT", "retained": false,
			"switch_evidence": {"previous_reaction": "NONE"}})
	check_eq(session._event_log_message(panic_event),
		"주인공 1이 위협에 겁을 먹고 평정심을 잃었다.", "panic becomes an incident sentence")
	check_eq(session._event_log_message(recovery_event),
		"주인공 1이 마음을 추스르고 평정을 되찾았다.", "panic recovery becomes an incident sentence")
	check_eq(session._event_log_message(engage_event),
		"주인공 1이 용기를 내어 다시 고블린 1에게 맞서기로 했다.", "return to combat is explicit")
	check_eq(session._event_log_message(protect_event),
		"주인공 1이 동료 1을 지키러 나섰다.", "protect decision states its human meaning")
	check_eq(session.snapshot_json(), snapshot_before, "event presentation leaves deterministic snapshot untouched")
	check_eq(session.command_journal_json(), journal_before, "event presentation leaves journal untouched")
	return finish()

func test_session_save_load_and_invalid_load_are_transactional() -> bool:
	var session = PlaytestSession.new(104, 504)
	check(session.advance_ticks(10).ok, "pre-save ten ticks")
	var saved_snapshot: String = session.snapshot_json()
	var saved_journal: String = session.command_journal_json()
	check(session.save_slot().ok, "save slot")
	check(session.advance_ticks(1).ok, "post-save tick")
	check(session.load_slot().ok, "load slot")
	check_eq(session.snapshot_json(), saved_snapshot, "snapshot restored")
	check_eq(session.command_journal_json(), saved_journal, "WAIT journal restored")
	var before: String = session.snapshot_json()
	check(not session.load_session_json("{broken").ok, "malformed rejected")
	check_eq(session.snapshot_json(), before, "transactional malformed load")
	var malformed: Dictionary = JSON.parse_string(session.save_session_json())
	malformed.personality_seed = "999"
	check_eq(session.load_session_json(JSON.stringify(malformed)).reason, "session_metadata_mismatch", "metadata mismatch")
	check_eq(session.snapshot_json(), before, "metadata rejection no-op")
	return finish()

func test_session_species_reset_changes_affinity_without_changing_arena() -> bool:
	var first = PlaytestSession.new(105, 1)
	var second = PlaytestSession.new(105, 2)
	var first_observation: Dictionary = first.observe_lab()
	var second_observation: Dictionary = second.observe_lab()
	check_eq(first_observation.cells, second_observation.cells, "personality seed does not alter base chamber")
	check(first.lead_roster()[0].personality != second.lead_roster()[0].personality, "personality seed changes facets")
	check_eq(first.sim.world.rng.state, second.sim.world.rng.state, "personality generation does not consume world RNG")
	return finish()
