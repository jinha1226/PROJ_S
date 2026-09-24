extends RefCounted
## Fixed-arena encounter runs and their statistics. Public session API only.
const Session = preload("res://expedition/run/session.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const Generator = preload("res://expedition/level/floor_generator.gd")
const Arena = preload("res://expedition/sim/encounter_arena.gd")
const Policy = preload("res://expedition/sim/bot_policy.gd")
const Rules = preload("res://expedition/ai/tactic_rules.gd")
const Knobs = preload("res://expedition/ai/knobs.gd")
static var builds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/reference_builds.json"))

static func build(id: String) -> Dictionary:
	for row in builds.builds:
		if row.id == id: return row
	return {}

static func apply_build(s, id: String) -> void:
	var row := build(id)
	for i in range(s.party.size()):
		var actor: Dictionary = s.party[i]
		for axis in row.get("ranks",{}): actor.growth.ranks[axis] = int(row.ranks[axis])
		for stat in row.get("stats",{}): actor.growth.stats[stat] = int(row.stats[stat])
		# `equipped_by_member` lets one build hand each seat its own parts — a
		# mixed party needs the skirmisher's sling without splitting the build.
		var per_member: Array = row.get("equipped_by_member",[])
		if not per_member.is_empty(): actor.equipped_abilities = (per_member[mini(i,per_member.size()-1)] as Array).duplicate()
		else: actor.equipped_abilities = row.equipped.duplicate()
		if row.has("rules"): actor.rules = row.rules.map(func(r): return Rules.make_rule(r[0],r[1],r[2]))
		# A build measures the build: without knobs of its own it fights on the
		# neutral defaults, not on whatever personality the seed rolled.
		actor.knobs = row.knobs.duplicate() if row.has("knobs") else Knobs.DEFAULT.duplicate()
		# Same for the stance: a build fights on the neutral charger unless it
		# names one for everybody, or one per member.
		if row.has("stances"): actor.stance = str(row.stances[mini(i,row.stances.size()-1)])
		elif row.has("stance"): actor.stance = str(row.stance)
		else: actor.stance = "CHARGER"
		actor.protect_id = -1

## Drains `s.effects` into the running tallies. Called before every player
## action and once more after the loop, so ambush hits and the strikes of the
## final round are counted too.
static func harvest(s, taken: Array, dealt: Dictionary, counters: Dictionary) -> void:
	for effect in s.effects:
		if effect.get("kind","") == "ENEMY_ATTACK" or not effect.has("amount"): continue
		var victim: Dictionary = s.at(effect.cell)
		if victim.is_empty() or victim.enemy: continue
		taken[victim.id] += int(effect.amount)
		if not counters.acted: counters.before_first += int(effect.amount)
		# The attacker has not moved between its strike and this harvest.
		var attacker: Dictionary = s.at(effect.from)
		var key: String = str(attacker.id) if not attacker.is_empty() else str(effect.from)
		dealt[key] = int(dealt.get(key,0))+int(effect.amount)
	s.effects.clear()

static func run_one(config: Dictionary, seed: int) -> Dictionary:
	var size: int = config.party_size
	var s = Session.new(seed,true,size > 1,true,size)
	s.simulation_arena = true
	s.rules_config = config.rules.duplicate()
	apply_build(s,config.build)
	# Manual probes only: replace the build's rule list with [[skill,target,when],...]
	# so one run can be compared against another rule set without editing data.
	if config.has("rules_override"):
		for actor in s.party: actor.rules = config.rules_override.map(func(r): return Rules.make_rule(r[0],r[1],r[2]))
	var theme: Dictionary = Generator.theme("F1_RUINS")
	# Keep only the five run supplies; the arena shares the fixed sight rules.
	s.supplies = config.supplies.slice(0,5).duplicate()
	var cap: int = int(config.rules.get("solo_max_members",0)) if size == 1 else 0
	Floor.apply(s,theme,Arena.layout(config.arena,theme,seed,cap))
	# No stop events run here, so the arena opens the battle report itself.
	s.reset_battle_stats()
	var taken: Array = []
	for _a in s.party: taken.append(0)
	var dealt: Dictionary = {}
	var counters := {"acted":false,"before_first":0}
	var first_death := -1; var heals := 0; var actions := 0
	var idle := 0
	var steps := 0
	# Diagnosis only: absent by default, so the measured path is untouched.
	var probe: Callable = config.get("probe",Callable())
	var probing: bool = probe.is_valid()
	var result := "TIMEOUT"
	# Harvest any setup effects before the first hero action.
	harvest(s,taken,dealt,counters)
	while s.on_floor() and s.round_number <= int(config.max_rounds):
		steps += 1
		if steps > int(config.max_rounds)*4: break
		harvest(s,taken,dealt,counters)
		var round_before: int = s.round_number
		if probing: probe.call(s,round_before)
		var kind: String = Policy.step(s,config.policy)
		if kind != "":
			actions += 1; counters.acted = true; idle = 0
			# A potion is the one action no part records; everything the party
			# pressed is tallied in battle_stats and summed after the loop.
			if kind == "HEAL": heals += 1
		else:
			idle += 1
			if idle >= 2: s.act("WAIT",s.party[s.selected].pos); idle = 0
		# "the round in which the death happened": end_round() increments
		# round_number when the party survives but returns before the increment
		# on a wipe, so the round the action started in is the answer either way.
		if first_death < 0 and s.party.any(func(a): return a.hp <= 0): first_death = round_before
		if s.enemies.all(func(e): return e.hp <= 0):
			result = "WIN"; break
	harvest(s,taken,dealt,counters)
	if s.phase == "DEFEAT" and result != "WIN": result = "DEFEAT"
	# Every member's presses, whichever policy pressed them.
	var skill_uses: Dictionary = {}
	var guards := 0; var redirects := 0
	# `role_rounds` per stance, not per member: the mixed party's three seats
	# each answer for their own stance in the gate table.
	var role_rounds: Dictionary = {}
	# 설계 §6: which consideration led each utility-chosen action, tallied per
	# stance. `battle_stats.members[].explains` is a window of the last 20
	# rounds per member, so this is a sample of the battle, not a transcript.
	var explain_top: Dictionary = {}
	for i in range(s.party.size()):
		var actor: Dictionary = s.party[i]
		var stance: String = str(actor.get("stance","CHARGER"))
		var rr: Dictionary = s.battle_stats.members.get(actor.id,{}).get("role_rounds",{"in_role":0,"total":0})
		var acc: Dictionary = role_rounds.get(stance,{"in_role":0,"total":0})
		acc.in_role += int(rr.in_role); acc.total += int(rr.total)
		role_rounds[stance] = acc
		var top: Dictionary = explain_top.get(stance,{})
		for entry in s.battle_stats.members.get(actor.id,{}).get("explains",[]):
			var terms: Array = entry.get("explain",[])
			# An early return (fire, hesitation, the retreat line) has no terms:
			# it was not the utility pool that answered, so it is not counted.
			if terms.is_empty(): continue
			# The terms come sorted by contribution, so the head is the reason —
			# unless nothing paid at all (a 0-contribution head only means the
			# candidate won on being the least bad), which is its own bucket.
			var cid: String = str(terms[0].id) if int(terms[0].contrib) > 0 else "(무득점)"
			top[cid] = int(top.get(cid,0))+1
		explain_top[stance] = top
	for id in s.battle_stats.members:
		var row: Dictionary = s.battle_stats.members[id]
		guards += int(row.guards); redirects += int(row.covers)
		for part in row.parts:
			skill_uses[part] = int(skill_uses.get(part,0))+int(row.parts[part])
			if s.Abilities.DEFINITIONS[part].effect == "HEAL": heals += int(row.parts[part])
	return {"result":result,"rounds":s.round_number,"damage_taken":taken,"hp_end":s.party.map(func(a): return a.hp),
		"deaths":s.party.filter(func(a): return a.hp <= 0).map(func(a): return a.id),"first_death_round":first_death,
		"heals_used":heals,"guards_used":guards,"protect_redirects":redirects,"skill_uses":skill_uses,"player_actions":actions,"damage_before_first_action":int(counters.before_first),
		"role_rounds":role_rounds,"explain_top":explain_top,"enemy_count":s.enemies.size(),"enemy_damage_dealt":dealt,"enemy_skill_uses":s.battle_stats.enemy_parts.duplicate(),"interrupts":int(s.battle_stats.interrupts)}

## One `--explain` cell: the most frequent top considerations of one stance,
## as "`id` %", biggest first, ties by id. "—" when that stance made no
## utility-chosen action in this row.
static func explain_cell(explain_top: Dictionary, stance: String, top_n: int = 3) -> String:
	var row: Dictionary = explain_top.get(stance,{})
	var total := 0
	for cid in row: total += int(row[cid])
	if total == 0: return "—"
	var ids: Array = row.keys()
	ids.sort_custom(func(a,b): return int(row[a]) > int(row[b]) if int(row[a]) != int(row[b]) else str(a) < str(b))
	var parts: Array = []
	for cid in ids.slice(0,top_n): parts.append("`%s` %d%%" % [cid,int(round(100.0*float(row[cid])/float(total)))])
	return "%s (n=%d)" % [" · ".join(parts),total]

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
	var size: float = maxf(1.0,float(config.party_size))
	# Every key any run saw, averaged over all runs — a run that never used a
	# skill counts as a zero, not as a missing sample.
	var skill_keys: Dictionary = {}
	for r in runs:
		for key in r.skill_uses: skill_keys[key] = true
	var skill_uses_mean: Dictionary = {}
	for key in skill_keys:
		var total := 0
		for r in runs: total += int(r.skill_uses.get(key,0))
		skill_uses_mean[key] = float(total)/runs.size()
	var enemy_skill_keys: Dictionary = {}
	for r in runs:
		for key in r.enemy_skill_uses: enemy_skill_keys[key] = true
	var enemy_skill_uses_mean: Dictionary = {}
	for key in enemy_skill_keys:
		var total := 0
		for r in runs: total += int(r.enemy_skill_uses.get(key,0))
		enemy_skill_uses_mean[key] = float(total)/runs.size()
	# Summed over the seed set, then read as one ratio per stance.
	var role_rounds: Dictionary = {}
	for r in runs:
		for stance in r.role_rounds:
			var acc: Dictionary = role_rounds.get(stance,{"in_role":0,"total":0})
			acc.in_role += int(r.role_rounds[stance].in_role); acc.total += int(r.role_rounds[stance].total)
			role_rounds[stance] = acc
	var explain_top: Dictionary = {}
	for r in runs:
		for stance in r.explain_top:
			var acc: Dictionary = explain_top.get(stance,{})
			for cid in r.explain_top[stance]: acc[cid] = int(acc.get(cid,0))+int(r.explain_top[stance][cid])
			explain_top[stance] = acc
	var interrupts_total := 0
	for r in runs: interrupts_total += int(r.interrupts)
	var interrupts_mean := float(interrupts_total)/runs.size()
	return {"distinct_outcomes":distinct.size(),"samples":runs.size(),"results":results,"win_rate":float(wins)/runs.size(),"win_ci":wilson(wins,runs.size()),
		"damage":summary(per_member),"damage_wins_per_member":summary(runs.filter(func(r): return r.result == "WIN").map(func(r): return r.damage_taken.reduce(func(a,b): return a+b,0)/size)),
		"guards":summary(runs.map(func(r): return r.guards_used)),"redirects":summary(runs.map(func(r): return r.protect_redirects)),"skill_uses_mean":skill_uses_mean,"enemy_skill_uses_mean":enemy_skill_uses_mean,"interrupts_mean":interrupts_mean,"role_rounds":role_rounds,"explain_top":explain_top,
		"rounds":summary(runs.map(func(r): return r.rounds)),
		"first_death":summary(runs.filter(func(r): return r.first_death_round > 0).map(func(r): return r.first_death_round)),
		"before_first":summary(runs.map(func(r): return r.damage_before_first_action)),
		"heals":summary(runs.map(func(r): return r.heals_used)),"deaths":runs.reduce(func(acc,r): return acc+r.deaths.size(),0),"runs":runs}
