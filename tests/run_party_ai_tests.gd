extends SceneTree

const TEST_FILES := [
	"test_party_companion_ruleset.gd",
	"test_party_squad_blackboard.gd",
	"test_party_shared_perception.gd",
	"test_party_exception_commands.gd",
	"test_party_companion_appraisal.gd",
	"test_party_companion_suggest.gd",
	"test_party_companion_explanation_ui.gd",
	"test_party_combat_matrix.gd",
]


func _init() -> void:
	var total := 0
	var failed := 0
	for file in TEST_FILES:
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
	print("---- Party companion AI: %d tests, %d failed ----" % [total, failed])
	quit(1 if failed > 0 else 0)
