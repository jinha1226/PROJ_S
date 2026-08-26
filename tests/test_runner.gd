extends SceneTree

const StateValidationSuite = preload("res://tests/test_state_validation.gd")


func _init() -> void:
	var failures: Array[String] = []
	var state_suite = StateValidationSuite.new()
	failures.append_array(state_suite.run())

	if failures.is_empty():
		print("M0 TESTS PASSED (STATE-001..003, SIM-001..002)")
		quit(0)
		return

	printerr("M0 TESTS FAILED: %d failure(s)" % failures.size())
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)
