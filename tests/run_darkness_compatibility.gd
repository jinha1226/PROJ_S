extends SceneTree

func _init()->void:
	var total:=0;var failed:=0
	for path in ["test_vision_rules.gd","test_torch_stage3.gd","test_darkness_stage5.gd"]:
		var script=load("res://tests/"+path)
		for method in script.new().get_method_list():
			if not method.name.begins_with("test_"):continue
			var test_case=script.new();var result=test_case.call(method.name)
			total+=1
			if result!=true or not test_case.errors.is_empty():
				failed+=1;printerr("FAIL ",path," :: ",method.name," ",test_case.errors)
			else:print("PASS ",path," :: ",method.name)
	print("DARKNESS COMPATIBILITY: ",total," tests, ",failed," failed")
	quit(0 if failed==0 and total>0 else 1)
