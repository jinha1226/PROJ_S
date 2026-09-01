extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")


func test_companion_explanations_are_detached_korean_and_match_preview() -> bool:
	var session = Session.new()
	var state = session.sim.world.party_encounter
	session.commit_exploration(Command.wait(state.protagonist_id))
	session.preview_deployment("WEDGE", state.party_member_ids.slice(1))
	check(session.commit_deployment().accepted, "deploy")
	session.begin_turn(Action.hold(state.protagonist_id))
	var before := session.save_session_json()
	var explanations: Dictionary = session.companion_decision_explanations()
	check(bool(explanations.accepted), "explanations available during a drafted turn")
	check_eq(explanations.companions.size(), state.active_party_member_ids.size() - 1,
		"one row per deployed companion")
	for row in explanations.companions:
		check(str(row.reason_text).length() > 0, "reason text present")
		check(str(row.selected_action_id) in ["ENGAGE", "PROTECT", "RETREAT", "HOLD"],
			"action id disclosed")
		check(row.candidates.size() >= 2, "candidates disclosed")
	check_eq(session.save_session_json(), before, "explanation is a detached projection")
	var overlays: Array = session.turn_intent_overlays()
	var companion_rows := 0
	for row in overlays:
		if str(row.get("role", "")) == "COMPANION":
			companion_rows += 1
			check(str(row.get("reason_text", "")).length() > 0,
				"overlay carries reason text")
	check(companion_rows > 0, "overlay lists companions")
	return finish()
