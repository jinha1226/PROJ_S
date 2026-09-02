extends SceneTree

const TEST_FILES := ["test_party_morale_model.gd","test_party_morale_matrix.gd"]


func _init() -> void:
	var total := 0
	var failed := 0
	for file in TEST_FILES:
		var script = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			printerr("FAIL %s :: script failed to load" % file)
			failed += 1
			continue
		var probe = script.new()
		for method in probe.get_method_list():
			if not method.name.begins_with("test_"):
				continue
			total += 1
			var test_case = script.new()
			var completed = test_case.call(method.name)
			if completed != true and test_case.errors.is_empty():
				test_case.errors.append("test did not return explicit true completion")
			if test_case.errors.is_empty():
				print("PASS %s :: %s" % [file, method.name])
			else:
				failed += 1
				for error in test_case.errors:
					print("FAIL %s :: %s -- %s" % [file, method.name, error])
	print("---- Party morale: %d tests, %d failed ----" % [total, failed])
	quit(1 if failed > 0 else 0)
