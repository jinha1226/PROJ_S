extends SceneTree
## Manual probe: ranged-heavy arenas by party size, rules policy, no supplies.
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const Session = preload("res://expedition/session.gd")
const ARENAS := {"early_pair":[["kobold","MELEE"],["dcss_rat","MELEE"]],"deep_mixed":[["dcss_hobgoblin","MELEE"],["goblin","RANGED"],["kobold","MELEE"]],
	"opt_archers":[["kobold","RANGED"],["goblin","RANGED"],["dcss_rat","MELEE"]],"two_archers":[["kobold","RANGED"],["goblin","RANGED"]]}
func _initialize() -> void:
	var seeds: Array = range(5000,5030)
	for name in ARENAS:
		for size in [1,2,3]:
			var spec: Dictionary = Runner.Arena.DEFAULT_SPEC.duplicate(true)
			spec.members = ARENAS[name].map(func(m): return {"species_id":m[0],"role":m[1]})
			var config := {"arena":spec,"party_size":size,"build":"melee_1","policy":"rules","rules":Session.DEFAULT_RULES,"supplies":[0,0,0,0,0],"max_rounds":60}
			var r: Dictionary = Runner.run_many(config,seeds)
			var taken: float = 0.0
			taken = float(r.get("damage_taken_total",{}).get("mean",0.0)) if r.has("damage_taken_total") else 0.0
			print("%-12s p%d win=%.2f rounds=%.1f taken=%.1f" % [name,size,r.win_rate,float(r.rounds.mean),taken])
	quit(0)
