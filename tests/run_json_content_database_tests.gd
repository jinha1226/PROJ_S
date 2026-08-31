extends SceneTree

const TEST_FILE := "test_json_content_database.gd"


func _init()->void:
	var script=load("res://tests/"+TEST_FILE)
	var total:=0;var failed:=0
	if script==null or not script.can_instantiate():
		printerr("FAIL JSON content database test script failed to load")
		quit(1);return
	for method in script.new().get_method_list():
		if not method.name.begins_with("test_"):continue
		total+=1
		var test_case=script.new()
		var completed=test_case.call(method.name)
		if typeof(completed)!=TYPE_BOOL or not completed:
			failed+=1
			if test_case.errors.is_empty():test_case.errors.append("test did not complete")
			for error in test_case.errors:
				print("FAIL %s :: %s -- %s"%[TEST_FILE,method.name,error])
		else:print("PASS %s :: %s"%[TEST_FILE,method.name])
	print("---- JSON content database: %d tests, %d failed ----"%[total,failed])
	quit(1 if failed>0 else 0)
