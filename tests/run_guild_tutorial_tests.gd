extends SceneTree

func _init()->void:
	var script=load("res://tests/test_guild_tutorial.gd")
	var failed:=0;var total:=0
	for method in script.new().get_method_list():
		if not method.name.begins_with("test_"):continue
		total+=1;var test=script.new();var ok=test.call(method.name)
		if not ok or not test.errors.is_empty():failed+=1;print("FAIL %s :: %s"%[method.name,test.errors])
		else:print("PASS %s"%method.name)
	print("guild tutorial: %d tests, %d failed"%[total,failed]);quit(1 if failed>0 else 0)
