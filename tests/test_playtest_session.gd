extends "res://tests/test_case.gd"

const PlaytestSession = preload("res://playtest/playtest_session.gd")
const Simulator = preload("res://sim/simulator.gd")


func test_session_reset_and_visible_view_are_deterministic_and_detached() -> bool:
	var first = PlaytestSession.new(101, "human")
	var second = PlaytestSession.new(101, "human")
	check_eq(first.snapshot_json(), second.snapshot_json(), "same seed arena snapshot")
	check_eq(first.player_state(), second.player_state(), "same seed player state")
	var rows: Array[Dictionary] = first.view_visible_cells()
	check_eq(rows.size(), 81, "default visible cell count")
	check_eq(first.view_visible_cells(100).size(), 81, "visible view is capped at 9x9")
	check_eq(rows[0].position, [0, 0], "clamped view top-left")
	check_eq(rows[-1].position, [8, 8], "clamped view bottom-right")
	var player_rows := 0
	var corpse_rows := 0
	for row in rows:
		check(row.has("terrain_id") and row.has("fire") and row.has("wetness"),
			"visible row hazard fields")
		for entity in row.entities:
			if entity.is_player:
				player_rows += 1
			if not entity.alive:
				corpse_rows += 1
	check_eq(player_rows, 1, "one player marker")
	check_eq(corpse_rows, 0, "initial view has no corpse")
	var before := first.snapshot_json()
	rows[0].terrain_id = "wall"
	rows[0].entities.append({"id": 999})
	var player: Dictionary = first.player_state()
	player.position[0] = 999
	var status: Dictionary = first.world_status()
	status.calendar.day = 999
	check_eq(first.snapshot_json(), before, "UI DTO mutation cannot reach session")
	return finish()


func test_session_inspect_preview_commit_and_status_are_authoritative() -> bool:
	var session = PlaytestSession.new(102, "human")
	var destination := Vector2i(5, 4)
	var inspection = session.inspect_destination(destination)
	check(inspection != null, "inspection available")
	check(inspection.traversal.accepted, "floor destination accepted")
	check_eq([inspection.move_time_cost, inspection.speed_tier], [100, "NORMAL"],
		"inspection uses core timing")
	var preview = session.preview_move(destination)
	check(preview.accepted, "MOVE preview accepted")
	check_eq([preview.start_time, preview.end_time, preview.time_cost], [0, 100, 100],
		"preview time")
	var result = session.commit_move(destination)
	check(result.accepted, "MOVE committed")
	check_eq(session.player_state().position, [5, 4], "player position from world")
	var status: Dictionary = session.world_status()
	check_eq([status.world_time, status.step_index, status.command_count], [100, 1, 1],
		"world status after MOVE")
	check(status.calendar is Dictionary, "calendar detached dictionary")
	check_eq(session.recent_events(1)[0].type, "action.move", "recent MOVE event")
	var summary: Dictionary = session.last_result_summary()
	check(summary.available and summary.accepted, "last result summary")
	check_eq([summary.start_time, summary.end_time, summary.time_cost], [0, 100, 100],
		"last result timing")
	check_eq(JSON.parse_string(session.command_journal_json()).size(), 1,
		"accepted command journaled")
	check_eq(session.journal_json(), session.command_journal_json(), "journal alias")
	var rejected = session.commit_move(Vector2i(7, 4))
	check(not rejected.accepted, "non-adjacent session MOVE rejected")
	check_eq(session.world_status().command_count, 1, "rejected command not journaled")
	return finish()


func test_session_element_commands_and_returned_results_are_detached() -> bool:
	var session = PlaytestSession.new(103, "dwarf")
	var position := Vector2i(5, 4)
	check(session.commit_ignite(position).accepted, "ignite committed")
	check(session.commit_water(position).accepted, "water committed")
	check(session.commit_discharge(position).accepted, "discharge committed")
	check(session.commit_wait().accepted, "wait committed")
	check_eq(session.world_status().command_count, 4, "mixed accepted journal count")
	var before := session.snapshot_json()
	var events: Array[Dictionary] = session.recent_events(20)
	if not events.is_empty():
		events[0].type = "tampered"
		if events[0].data is Dictionary:
			events[0].data.tampered = true
	var summary: Dictionary = session.last_result_summary()
	summary.timeline.clear()
	summary.events.clear()
	check_eq(session.snapshot_json(), before, "event/result DTOs detached")
	return finish()


func test_session_save_load_and_invalid_load_are_transactional() -> bool:
	var session = PlaytestSession.new(104, "amphibian")
	check(session.commit_move(Vector2i(5, 4)).accepted, "pre-save MOVE")
	var saved_snapshot := session.snapshot_json()
	var saved_journal := session.command_journal_json()
	var saved_evaluation: Dictionary = session.inspect_destination(Vector2i(6, 4)).to_dict()
	check(session.save_slot().ok, "save slot")
	check(session.commit_move(Vector2i(5, 5)).accepted, "post-save MOVE")
	check(session.load_slot().ok, "load slot")
	check_eq(session.snapshot_json(), saved_snapshot, "snapshot restored")
	check_eq(session.command_journal_json(), saved_journal, "journal restored")
	check_eq(session.player_state().position, [5, 4], "player reference rebound")
	check_eq(session.world_status().selection_position, [5, 4], "selection rebound")
	check_eq(session.inspect_destination(Vector2i(6, 4)).to_dict(), saved_evaluation,
		"destination sample and evaluation restored")
	var before := session.snapshot_json()
	var journal_before := session.command_journal_json()
	check(not session.load_session_json("{broken").ok, "malformed JSON rejected")
	check_eq(session.snapshot_json(), before, "malformed load snapshot no-op")
	check_eq(session.command_journal_json(), journal_before, "malformed load journal no-op")
	var invalid: Dictionary = {
		"session_format_version": 1, "seed": "104", "species_id": "amphibian",
		"snapshot": JSON.parse_string(before),
		"command_journal": [{"type": 4.5, "actor_id": "1", "position": [1, 1],
			"power": 0, "duration": 100}],
	}
	check(not session.load_session_json(JSON.stringify(invalid)).ok,
		"invalid command journal rejected")
	check_eq(session.snapshot_json(), before, "invalid journal load snapshot no-op")
	var metadata_mismatch: Dictionary = {
		"session_format_version": 1, "seed": "999", "species_id": "human",
		"snapshot": JSON.parse_string(before), "command_journal": [],
	}
	check_eq(session.load_session_json(JSON.stringify(metadata_mismatch)).reason,
		"session_metadata_mismatch", "metadata mismatch rejected")
	check_eq(session.snapshot_json(), before, "metadata mismatch no-op")
	var journal_mismatch: Dictionary = {
		"session_format_version": 1, "seed": "104", "species_id": "amphibian",
		"snapshot": JSON.parse_string(before),
		"command_journal": JSON.parse_string(journal_before),
	}
	journal_mismatch.command_journal.append({
		"type": 0, "actor_id": str(session.player_state().id),
		"position": [0, 0], "power": 0, "wait_duration_time_units": 100,
	})
	check_eq(session.load_session_json(JSON.stringify(journal_mismatch)).reason,
		"journal_snapshot_mismatch", "wire-valid but unrelated journal rejected")
	check_eq(session.snapshot_json(), before, "journal mismatch no-op")
	var rejected_journal: Dictionary = journal_mismatch.duplicate(true)
	rejected_journal.command_journal = [{
		"type": 4, "actor_id": str(session.player_state().id),
		"position": [20, 20], "power": 0, "wait_duration_time_units": 100,
	}]
	check_eq(session.load_session_json(JSON.stringify(rejected_journal)).reason,
		"journal_replay_rejected", "journal must contain accepted commands")
	var duplicate_player: Dictionary = journal_mismatch.duplicate(true)
	duplicate_player.command_journal = JSON.parse_string(journal_before)
	duplicate_player.snapshot.entities[1].tags.append("player")
	check_eq(session.load_session_json(JSON.stringify(duplicate_player)).reason,
		"player_count_invalid", "exactly one player tag required")
	check_eq(session.snapshot_json(), before, "duplicate player load no-op")
	var small = Simulator.new(1, 1, 104)
	small.world.add_entity(
		"player", "Small", Vector2i.ZERO, 100, ["player"], "amphibian", "party")
	var wrong_arena := {
		"session_format_version": 1, "seed": "104", "species_id": "amphibian",
		"snapshot": small.snapshot(), "command_journal": [],
	}
	check_eq(session.load_session_json(JSON.stringify(wrong_arena)).reason,
		"arena_shape_mismatch", "non-arena v3 world rejected")
	check_eq(session.snapshot_json(), before, "wrong arena load no-op")
	return finish()


func test_session_species_reset_changes_affinity_without_changing_arena() -> bool:
	var human = PlaytestSession.new(105, "human")
	var amphibian = PlaytestSession.new(105, "amphibian")
	var dwarf = PlaytestSession.new(105, "dwarf")
	for session in [human, amphibian, dwarf]:
		check(session.commit_move(Vector2i(5, 4)).accepted, "walk east")
		check(session.commit_move(Vector2i(6, 4)).accepted, "walk onto fire")
	check_eq([human.player_state().species_id, amphibian.player_state().species_id,
		dwarf.player_state().species_id], ["human", "amphibian", "dwarf"],
		"session species")
	check_eq(human.inspect_destination(Vector2i(6, 5)).sample.to_dict(),
		amphibian.inspect_destination(Vector2i(6, 5)).sample.to_dict(),
		"species does not alter environmental sample")
	return finish()
