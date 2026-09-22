extends SceneTree
## Manual tool: what the 엄호 rule is worth to a 3-person party. Runs the arena
## encounters with the shipped defaults and, for comparison, with no GUARD rule
## at all. A third configuration — the retired `[GUARD SELF HP]` default — is
## deliberately absent: self-guard no longer exists in the engine, so that rule
## can no longer be expressed, let alone measured against these numbers.
## Not part of the CI suite. Usage:
##   godot --headless --path . --script res://tests/party_guard_probe.gd
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const Arena = preload("res://expedition/sim/encounter_arena.gd")
static var experiments: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/balance_experiments.json"))
const ARENAS := ["deep_mixed","deep_caster","opt_gnoll"]
const BUILDS := ["melee_1","b_iron"]

func _initialize() -> void: call_deferred("run")

func spec(arena_id: String) -> Dictionary:
	var arenas: Dictionary = experiments.experiments.action_economy.arenas
	var out: Dictionary = Arena.DEFAULT_SPEC.duplicate(true)
	out.tier = arenas[arena_id].tier
	out.members = arenas[arena_id].members.map(func(pair): return {"species_id":pair[0],"role":pair[1]})
	return out

func run() -> void:
	var ex: Dictionary = experiments.experiments.action_economy
	var seeds: Array = range(5000,5060)
	print("party 3 · policy rules · seeds 5000-5059 (%d) · arenas %s" % [seeds.size(),", ".join(ARENAS)])
	print("%-9s %-11s %-12s %8s %10s %8s %8s %10s  %s" % ["rules","build","arena","win","dmg/member","deaths","guards","redirects","hero skill uses/run"])
	for variant in ["guard","no_guard"]:
		for build_id in BUILDS:
			for arena_id in ARENAS:
				var config := {"arena":spec(arena_id),"party_size":3,"build":build_id,"policy":"rules","rules":ex.rules["current"],"supplies":ex.supplies,"max_rounds":60}
				# Same build, same order, only the 엄호 rule taken out — the build's
				# own skill rule must stay or the two columns compare two things.
				if variant == "no_guard": config["rules_override"] = Runner.build(build_id).rules.filter(func(r): return r[0] != "GUARD")
				var stats: Dictionary = Runner.run_many(config,seeds)
				var uses: Array = []
				for key in stats.skill_uses_mean: uses.append("%s %.2f" % [key,stats.skill_uses_mean[key]])
				print("%-9s %-11s %-12s %8.2f %10.1f %8d %8.2f %10.2f  %s" % [variant,build_id,arena_id,stats.win_rate,stats.damage.mean,stats.deaths,stats.guards.mean,stats.redirects.mean,", ".join(uses)])
	quit(0)
