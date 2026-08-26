extends SceneTree

const StateValidationSuite = preload("res://tests/test_state_validation.gd")
const GameplaySuite = preload("res://tests/test_gameplay.gd")


func _init() -> void:
	var failures: Array[String] = []
	var state_suite = StateValidationSuite.new()
	failures.append_array(state_suite.run())
	var gameplay_suite = GameplaySuite.new()
	failures.append_array(gameplay_suite.run())

	if failures.is_empty():
		print("M0-M2 TESTS PASSED (state, assignment, jobs, coaching, proficiency, determinism)")
		quit(0)
		return

	printerr("M0 TESTS FAILED: %d failure(s)" % failures.size())
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)
