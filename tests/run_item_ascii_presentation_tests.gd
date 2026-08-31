extends SceneTree

func _init()->void:
	var script=load("res://tests/test_item_ascii_presentation.gd")
	var total:=0;var failed:=0
	if script==null or not script.can_instantiate():
		printerr("FAIL item ASCII presentation -- script failed to load");quit(1);return
	for method in script.new().get_method_list():
		if not method.name.begins_with("test_"):continue
		total+=1;var test_case=script.new();test_case.call(method.name)
		if not test_case.errors.is_empty():
			failed+=1
			for error in test_case.errors:print("FAIL item ASCII presentation -- "+error)
		else:print("PASS item ASCII presentation :: "+method.name)
	print("---- Item ASCII presentation: %d tests, %d failed ----"%[total,failed])
	quit(1 if failed>0 else 0)
