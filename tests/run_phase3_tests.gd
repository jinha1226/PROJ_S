extends SceneTree

func _init() -> void:
	var script = load("res://tests/test_phase3_personality_lab.gd")
	var total := 0; var failed := 0
	for method in script.new().get_method_list():
		if not method.name.begins_with("test_"): continue
		total += 1
		var test = script.new(); test.call(method.name)
		if test.errors.is_empty(): print("PASS ", method.name)
		else:
			failed += 1
			for error in test.errors: print("FAIL ", method.name, " -- ", error)
	print("---- %d tests, %d failed ----" % [total, failed])
	quit(1 if failed else 0)
