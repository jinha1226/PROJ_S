extends SceneTree

const METHODS := [
	"test_exploration_route_is_exact_shortest_until_visible_hazard_requires_bounded_risk",
	"test_exploration_route_never_reads_unseen_live_hazards",
	"test_select_movement_destination_is_one_mutating_facade_in_both_modes",
	"test_long_route_preview_is_pure_detached_and_each_call_commits_one_existing_move",
	"test_long_route_stops_on_contact_blocker_risk_stale_death_and_combat",
]


func _init() -> void:
	var script = load("res://tests/test_party_playtest_session.gd")
	var failures: Array[String] = []
	for method in METHODS:
		var test_case = script.new()
		var completed = test_case.call(method)
		if typeof(completed) != TYPE_BOOL or not completed:
			failures.append("%s did not complete" % method)
		for error in test_case.errors:
			failures.append("%s -- %s" % [method, error])
		if test_case.errors.is_empty() and completed:
			print("PASS test_party_playtest_session.gd :: %s" % method)
	for failure in failures:
		print("FAIL test_party_playtest_session.gd :: %s" % failure)
	quit(1 if not failures.is_empty() else 0)
