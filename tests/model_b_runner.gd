extends SceneTree
const Runner = preload("res://expedition/sim/model_b_runner.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func run() -> void:
	var first: Dictionary = Runner.run_one("early_hob",1,100,50)
	check(first.result in ["WIN","DEFEAT","TIMEOUT"] and first.hero_actions > 0,"manual simulator takes hero actions")
	check(first == Runner.run_one("early_hob",1,100,50),"same seed reproduces the whole result")
	var many: Dictionary = Runner.run_many("early_hob",1,[100,101,102])
	check(many.samples == 3 and int(many.results.WIN)+int(many.results.DEFEAT)+int(many.results.TIMEOUT) == 3,"three runs accounted for")
	print("Model B runner: %d failures" % failures)
	quit(1 if failures else 0)
