extends SceneTree

func _init() -> void:
	var script = load("res://tests/test_darkness_stage5.gd")
	var failed := 0
	for method in script.new().get_method_list():
		if not method.name.begins_with("test_"): continue
		var test_case = script.new()
		var completed = test_case.call(method.name)
		if typeof(completed) != TYPE_BOOL or not completed or not test_case.errors.is_empty():
			failed += 1
			print("FAIL %s -- %s" % [method.name, test_case.errors])
		else:
			print("PASS %s" % method.name)
	print("---- Darkness stage 5: %d failed ----" % failed)
	quit(1 if failed > 0 else 0)
