extends SceneTree
## Manual tool: the solo expedition bot driven by the rules policy (Tactics.choose) per build
## and GUARD-rule variant. Prints wins/8, actions, hp and skill uses. Not in CI.
const Session = preload("res://expedition/session.gd")
const Objective = preload("res://expedition/expedition_objective.gd")
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const SEEDS := 8
const SHOPPING := ["supply:0","supply:5","supply:5","supply:1","supply:1","food","food","food","food","food","food","food","food","torch","supply:0","supply:5","torch"]
func _initialize() -> void: call_deferred("run")
func route(s, target: Vector2i) -> Array:
	var goals: Array = [target]
	for d in s.DIRECTIONS:
		if s.is_free(target+d) and s.melee_reach(target+d,target): goals.append(target+d)
	var r: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,s.party[0].pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
	return r.path if r.found else []
func play(s, build: String, policy: String, variant: String = "") -> Dictionary:
	for id in SHOPPING:
		if s.bank >= s.price(id): s.buy(id)
	Runner.apply_build(s,build)
	# "default" keeps the build's own rules; "no_guard" strips the guard rules
	# to price what guarding is worth on top of them.
	if variant == "no_guard": s.party[0].rules = s.party[0].rules.filter(func(r): return r.skill != "GUARD")
	s.depart()
	var hero: Dictionary = s.party[0]
	var actions := 0; var heals := 0; var stuck := 0; var uses: Dictionary = {}
	var goal := "relic"
	while s.phase == "BATTLE" and actions < 1500:
		var target: Vector2i = s.objective.pos if goal == "relic" else s.entry_position()
		if not s.combat_enemies().is_empty():
			if hero.hp < 14 and s.supplies[0] > 0 and s.use_supply(0): heals += 1; actions += 1; continue
			if hero.hp < 10 and s.supplies[5] > 0 and s.use_supply(5): heals += 1; actions += 1; continue
			if policy == "rules":
				var choice: Dictionary = s.Tactics.choose(s,hero)
				if s.act(choice.kind,choice.cell):
					if s.Abilities.DEFINITIONS.has(choice.kind) or choice.kind in ["PUSH","GUARD"]: uses[choice.kind] = int(uses.get(choice.kind,0))+1
					actions += 1; continue
			if s.auto_attack(): actions += 1; continue
			s.act("WAIT",hero.pos); actions += 1; continue
		if hero.stress >= 125 and s.supplies[1] > 0 and s.use_supply(1): actions += 1; continue
		if s.light < 35 and s.torches > 0 and s.use_torch(): continue
		if hero.hp <= hero.max_hp-20 and s.supplies[0] > 0 and s.use_supply(0): heals += 1; actions += 1; continue
		if hero.hp <= hero.max_hp-10 and s.supplies[5] > 0 and s.use_supply(5): heals += 1; actions += 1; continue
		if goal == "relic" and Objective.error(s).is_empty():
			s.pickup_relic(); actions += 1; goal = "home"; continue
		if goal == "home" and s.return_error().is_empty():
			s.return_home(); break
		var path := route(s,target)
		if path.size() < 2:
			stuck += 1
			if stuck > 5: break
			s.act("WAIT",hero.pos); actions += 1; continue
		if not s.act("MOVE",path[1]): s.act("WAIT",hero.pos)
		actions += 1
	return {"reason":s.result.get("reason","STUCK"),"actions":actions,"heals":heals,"hp":hero.hp,"uses":uses}
func run() -> void:
	var matrix: Array = []
	for variant in ["default","no_guard"]:
		for build in ["melee_1","b_strike","b_knife","b_dressing","b_lunge","b_bomb","b_shockwave","b_iron"]: matrix.append([build,"rules",variant])
	for row in matrix:
		var wins := 0; var hp_sum := 0; var acts := 0; var uses: Dictionary = {}; var reasons: Array = []
		for seed_value in range(SEEDS):
			var r := play(Session.new(seed_value,true,false,true,1),row[0],row[1],row[2])
			if r.reason == "SUCCESS": wins += 1; hp_sum += r.hp
			acts += r.actions; reasons.append(r.reason.substr(0,1))
			for k in r.uses: uses[k] = int(uses.get(k,0))+int(r.uses[k])
		var use_text: Array = []
		for k in uses: use_text.append("%s %.1f" % [k,float(uses[k])/SEEDS])
		print("%-11s %-12s wins %d/8 [%s] avg actions %d  avg hp(win) %d  uses/run: %s" % [row[0],row[2],wins,"".join(reasons),acts/SEEDS,(hp_sum/wins if wins > 0 else 0),", ".join(use_text)])
	quit(0)
