extends SceneTree


func _init() -> void:
	var total := 0
	var failed := 0
	var directory := DirAccess.open("res://tests")
	if directory == null:
		printerr("FAIL: could not open res://tests")
		quit(1)
		return
	var files := directory.get_files()
	files.sort()
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
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
			if typeof(completed) != TYPE_BOOL:
				test_case.errors.append("test did not return explicit true completion")
			elif completed == false and test_case.errors.is_empty():
				test_case.errors.append("test returned false without a recorded assertion")
			if test_case.errors.is_empty():
				print("PASS %s :: %s" % [file, method.name])
			else:
				failed += 1
				for error in test_case.errors:
					print("FAIL %s :: %s -- %s" % [file, method.name, error])
	if total == 0:
		printerr("FAIL: zero tests discovered")
		failed += 1
	print("---- %d tests, %d failed ----" % [total, failed])
	quit(1 if failed > 0 else 0)
