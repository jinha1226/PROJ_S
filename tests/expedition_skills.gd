extends SceneTree
## Manual build probe on the current fixed-sight combat core. Not in CI.
const Session = preload("res://expedition/run/session.gd")
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const Arena = preload("res://expedition/sim/encounter_arena.gd")
const BUILDS := ["melee_1","b_strike","b_knife","b_dressing","b_lunge","b_bomb","b_shockwave","b_iron"]
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var spec: Dictionary = Arena.DEFAULT_SPEC.duplicate(true)
	spec.members = [{"species_id":"dcss_hobgoblin","role":"MELEE"},{"species_id":"goblin","role":"RANGED"}]
	for build_id in BUILDS:
		for variant in ["default","no_guard"]:
			var config := {"arena":spec,"party_size":1,"build":build_id,"policy":"rules",
				"rules":Session.DEFAULT_RULES,"supplies":[0,0,0,0,0],"max_rounds":60}
			if variant == "no_guard":
				var row: Dictionary = Runner.build(build_id)
				config["rules_override"] = row.get("rules",[]).filter(func(r): return r[0] != "GUARD")
			var result: Dictionary = Runner.run_many(config,range(5000,5008))
			print("%-12s %-8s win %.2f damage %.1f rounds %.1f" % [build_id,variant,result.win_rate,result.damage.mean,result.rounds.mean])
	quit(0)
