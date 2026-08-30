extends SceneTree


func _init() -> void:
	var script = load("res://tests/test_party_auto_explore.gd")
	if script == null or not script.can_instantiate():
		print("FAIL test_party_auto_explore.gd did not compile")
		quit(1)
		return
	var methods: Array[String] = []
	for method in script.get_script_method_list():
		var name := str(method.name)
		if name.begins_with("test_"):
			methods.append(name)
	methods.sort()
	var failed := 0
	for method in methods:
		var test = script.new()
		var completed = test.call(method)
		if typeof(completed) != TYPE_BOOL:
			test.errors.append("test did not return explicit true completion")
		elif completed == false and test.errors.is_empty():
			test.errors.append("test returned false without assertion")
		if test.errors.is_empty():
			print("PASS test_party_auto_explore.gd :: %s" % method)
		else:
			failed += 1
			for failure in test.errors:
				print("FAIL test_party_auto_explore.gd :: %s :: %s" % [method, failure])
	print("---- AUTO EXPLORE: %d tests, %d failed ----" % [methods.size(), failed])
	quit(1 if failed > 0 else 0)
