extends SceneTree

const TEST_FILE := "test_party_enemy_awareness.gd"

func _init()->void:
	var script=load("res://tests/"+TEST_FILE)
	var total:=0;var failed:=0
	if script==null or not script.can_instantiate():
		printerr("FAIL %s :: script failed to load"%TEST_FILE);quit(1);return
	for method in script.new().get_method_list():
		if not method.name.begins_with("test_"):continue
		total+=1
		var test_case=script.new();var completed=test_case.call(method.name)
		if typeof(completed)!=TYPE_BOOL:test_case.errors.append("test did not return explicit completion")
		if test_case.errors.is_empty():print("PASS %s :: %s"%[TEST_FILE,method.name])
		else:
			failed+=1
			for error in test_case.errors:print("FAIL %s :: %s -- %s"%[TEST_FILE,method.name,error])
	print("---- Party enemy awareness: %d tests, %d failed ----"%[total,failed])
	quit(1 if failed>0 else 0)
