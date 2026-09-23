extends SceneTree
const Runner = preload("res://expedition/sim/model_b_runner.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var seeds: Array = range(100,108)
	for arena in ["early_hob","early_pair","deep_mixed","deep_caster"]:
		for size in [1,3]:
			for hp in [55,72]:
				var result: Dictionary = Runner.run_many(arena,size,seeds,hp)
				print(JSON.stringify({"arena":arena,"party":size,"hero_hp":hp,"seeds":seeds,"results":result.results,"win_rate":result.win_rate,
					"mean_actions":result.runs.reduce(func(total,row): return total+int(row.hero_actions),0)/seeds.size()}))
	quit()
