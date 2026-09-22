extends RefCounted
## Fixed-arena encounter runs and their statistics. Public session API only.
const Session = preload("res://expedition/session.gd")
const Floor = preload("res://expedition/continuous_floor.gd")
const Generator = preload("res://expedition/floor_generator.gd")
const Arena = preload("res://expedition/sim/encounter_arena.gd")
const Policy = preload("res://expedition/sim/bot_policy.gd")
static var builds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/reference_builds.json"))

static func build(id: String) -> Dictionary:
	for row in builds.builds:
		if row.id == id: return row
	return {}

static func apply_build(s, id: String) -> void:
	var row := build(id)
	for actor in s.party:
		for axis in row.get("ranks",{}): actor.growth.ranks[axis] = int(row.ranks[axis])
		for stat in row.get("stats",{}): actor.growth.stats[stat] = int(row.stats[stat])
		for ability in row.get("learned",[]):
			if ability not in actor.learned_abilities: actor.learned_abilities.append(ability)
		actor.equipped_abilities = row.equipped.duplicate()

static func run_one(config: Dictionary, seed: int) -> Dictionary:
	var size: int = config.party_size
	var s = Session.new(seed,true,size > 1,true,size)
	s.rules_config = config.rules.duplicate()
	apply_build(s,config.build)
	var theme: Dictionary = Generator.theme("F1_RUINS")
	Floor.apply(s,theme,Arena.layout(config.arena,theme,seed))
	s.light = int(config.arena.get("light",90)); s.supplies = config.supplies.duplicate()
	var taken: Array = []
	for _a in s.party: taken.append(0)
	var dealt: Dictionary = {}
	var first_death := -1; var heals := 0; var guards := 0; var actions := 0; var before_first := 0; var acted := false
	var idle := 0
	var result := "TIMEOUT"
	while s.phase == "BATTLE" and s.round_number <= int(config.max_rounds):
		var supplies_before: int = s.supplies[0]+s.supplies[5]
		var guarded_before: bool = s.party[s.selected].get("guarded",false)
		var ok: bool = Policy.step(s,config.policy)
		if ok:
			actions += 1; acted = true; idle = 0
		else:
			idle += 1
			if idle >= 2: s.act("WAIT",s.party[s.selected].pos); idle = 0
		if s.supplies[0]+s.supplies[5] < supplies_before: heals += 1
		if not guarded_before and s.party[s.selected].get("guarded",false): guards += 1
		for effect in s.effects:
			if effect.get("kind","") == "ENEMY_ATTACK" or not effect.has("amount"): continue
			var victim := s.at(effect.cell)
			if victim.is_empty() or victim.enemy: continue
			taken[victim.id] += int(effect.amount)
			if not acted: before_first += int(effect.amount)
			dealt[effect.from] = int(dealt.get(effect.from,0))+int(effect.amount)
		s.effects.clear()
		if first_death < 0 and s.party.any(func(a): return a.hp <= 0): first_death = s.round_number
		if s.enemies.all(func(e): return e.hp <= 0):
			result = "WIN"; break
	if s.phase != "BATTLE" and result != "WIN": result = "DEFEAT"
	return {"result":result,"rounds":s.round_number,"damage_taken":taken,"hp_end":s.party.map(func(a): return a.hp),
		"deaths":s.party.filter(func(a): return a.hp <= 0).map(func(a): return a.id),"first_death_round":first_death,
		"heals_used":heals,"guards_used":guards,"player_actions":actions,"damage_before_first_action":before_first,
		"enemy_count":s.enemies.size(),"enemy_damage_dealt":dealt}

static func wilson(wins: int, n: int) -> Array:
	if n == 0: return [0.0,0.0]
	var z := 1.96; var p := float(wins)/n
	var denom := 1.0+z*z/n
	var centre := (p+z*z/(2*n))/denom
	var half := z*sqrt(p*(1-p)/n+z*z/(4.0*n*n))/denom
	return [maxf(0.0,centre-half),minf(1.0,centre+half)]

static func percentile(values: Array, p: float) -> float:
	if values.is_empty(): return 0.0
	var sorted: Array = values.duplicate(); sorted.sort()
	var index: int = clampi(int(ceil(p*sorted.size()))-1,0,sorted.size()-1)
	return float(sorted[index])

static func summary(values: Array) -> Dictionary:
	if values.is_empty(): return {"mean":0.0,"sd":0.0,"median":0.0,"p90":0.0,"p95":0.0}
	var mean := 0.0
	for v in values: mean += v
	mean /= values.size()
	var variance := 0.0
	for v in values: variance += (v-mean)*(v-mean)
	return {"mean":mean,"sd":sqrt(variance/values.size()),"median":percentile(values,0.5),"p90":percentile(values,0.9),"p95":percentile(values,0.95)}

static func run_many(config: Dictionary, seeds: Array) -> Dictionary:
	var runs: Array = []
	for seed in seeds: runs.append(run_one(config,seed))
	var results: Dictionary = {}
	for r in runs: results[r.result] = int(results.get(r.result,0))+1
	var wins: int = int(results.get("WIN",0))
	var per_member: Array = []
	var distinct: Dictionary = {}
	for r in runs:
		for value in r.damage_taken: per_member.append(value)
		distinct["%s|%d|%s" % [r.result,r.rounds,str(r.damage_taken)]] = true
	return {"distinct_outcomes":distinct.size(),"samples":runs.size(),"results":results,"win_rate":float(wins)/runs.size(),"win_ci":wilson(wins,runs.size()),
		"damage":summary(per_member),"damage_wins":summary(runs.filter(func(r): return r.result == "WIN").map(func(r): return r.damage_taken.reduce(func(a,b): return a+b,0))),
		"rounds":summary(runs.map(func(r): return r.rounds)),
		"first_death":summary(runs.filter(func(r): return r.first_death_round > 0).map(func(r): return r.first_death_round)),
		"before_first":summary(runs.map(func(r): return r.damage_before_first_action)),
		"heals":summary(runs.map(func(r): return r.heals_used)),"deaths":runs.reduce(func(acc,r): return acc+r.deaths.size(),0),"runs":runs}
