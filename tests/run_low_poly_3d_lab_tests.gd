extends SceneTree

const TEST_FILE="test_low_poly_3d_lab.gd"

func _init()->void:
	var script=load("res://tests/"+TEST_FILE);var total:=0;var failed:=0
	for method in script.new().get_method_list():
		if not method.name.begins_with("test_"):continue
		total+=1;var test_case=script.new();var completed=test_case.call(method.name)
		if typeof(completed)!=TYPE_BOOL or not completed:
			if test_case.errors.is_empty():test_case.errors.append("test did not complete")
		if test_case.errors.is_empty():print("PASS %s :: %s"%[TEST_FILE,method.name])
		else:
			failed+=1
			for error in test_case.errors:print("FAIL %s :: %s -- %s"%[TEST_FILE,method.name,error])
	print("---- Low-poly 3D lab: %d tests, %d failed ----"%[total,failed]);quit(1 if failed>0 else 0)
