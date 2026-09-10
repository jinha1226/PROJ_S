extends SceneTree

const TEST_FILES := [
	"test_environment_simulation.gd", "test_elements.gd", "test_exposure_affinity.gd",
	"test_core.gd", "test_world_body_lifecycle.gd",
	"test_vision_rules.gd",
	"test_enemy_stealth_stage2.gd",
	"test_torch_stage3.gd",
	"test_darkness_stage5.gd",
	"test_guild_tutorial.gd",
]


func _init() -> void:
	var total := 0
	var failed := 0
	for file in TEST_FILES:
		var script = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			printerr("FAIL %s failed to load" % file)
			failed += 1
			continue
		for method in script.new().get_method_list():
			if not method.name.begins_with("test_"): continue
			total += 1
			var test_case = script.new()
			var completed = test_case.call(method.name)
			if typeof(completed) != TYPE_BOOL or not completed or not test_case.errors.is_empty():
				failed += 1
				print("FAIL %s :: %s -- %s" % [file, method.name, test_case.errors])
			else:
				print("PASS %s :: %s" % [file, method.name])
	print("---- Environment regression: %d tests, %d failed ----" % [total, failed])
	quit(1 if failed > 0 or total == 0 else 0)
