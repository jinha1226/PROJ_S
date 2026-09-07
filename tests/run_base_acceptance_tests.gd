extends SceneTree


const TEST_FILE := "base_progression_acceptance.gd"


func _init() -> void:
	var total := 0
	var failed := 0
	var script = load("res://tests/" + TEST_FILE)
	if script == null or not script.can_instantiate():
		printerr("FAIL %s :: script failed to load" % TEST_FILE)
		quit(1)
		return
	var probe = script.new()
	var only := OS.get_environment("BASE_ACCEPTANCE_TEST")
	for method in probe.get_method_list():
		if not method.name.begins_with("test_"):
			continue
		if not only.is_empty() and method.name != only:
			continue
		total += 1
		var test_case = script.new()
		var completed = test_case.call(method.name)
		if completed != true and test_case.errors.is_empty():
			test_case.errors.append("test did not return explicit true completion")
		if test_case.errors.is_empty():
			print("PASS %s :: %s" % [TEST_FILE, method.name])
		else:
			failed += 1
			for error in test_case.errors:
				print("FAIL %s :: %s -- %s" % [TEST_FILE, method.name, error])
	if total == 0:
		printerr("FAIL: zero base acceptance tests discovered")
		failed += 1
	print("---- Base acceptance: %d tests, %d failed ----" % [total, failed])
	quit(1 if failed > 0 else 0)
