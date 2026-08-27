extends "res://tests/test_case.gd"

const PlaytestSession = preload("res://playtest/playtest_session.gd")

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
	check(event_log.any(func(row: Dictionary): return str(row.message).contains("발견") \
			or str(row.message).contains("반응 선택")), "event log has readable Korean messages")
	if not event_log.is_empty(): event_log[0].message = "tampered"
	check_eq(session.snapshot_json(), before, "inspector and events detached")
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
