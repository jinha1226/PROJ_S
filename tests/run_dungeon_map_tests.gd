extends SceneTree


func _init() -> void:
	var script = load("res://tests/test_deterministic_dungeon_map.gd")
	if script == null or not script.can_instantiate():
		printerr("FAIL dungeon map test script failed to load")
		quit(1)
		return
	var total := 0
	var failed := 0
	for method in script.new().get_method_list():
		if not method.name.begins_with("test_"):
			continue
		total += 1
		var test_case = script.new()
		var completed = test_case.call(method.name)
		if typeof(completed) != TYPE_BOOL or not completed:
			if test_case.errors.is_empty():
				test_case.errors.append("test did not complete")
		if test_case.errors.is_empty():
			print("PASS dungeon map :: %s" % method.name)
		else:
			failed += 1
			for error in test_case.errors:
				print("FAIL dungeon map :: %s -- %s" % [method.name, error])
	print("---- Dungeon map: %d tests, %d failed ----" % [total, failed])
	quit(1 if failed > 0 else 0)
