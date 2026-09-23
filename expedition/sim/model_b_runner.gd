extends RefCounted
## Deterministic balance probes using the same submit path as manual play.
const Session = preload("res://expedition/session.gd")
const Tactics = preload("res://expedition/tactical_action_selector.gd")

static func run_one(arena_id: String, party_size: int, seed: int, limit: int = 80, hero_hp: int = 55) -> Dictionary:
	var preset: Dictionary = Session.ARENA_PRESETS.get(arena_id,{})
	if preset.is_empty(): return {"result":"INVALID"}
	var members: Array = []
	for _i in range(party_size): members.append({"stance":"CHARGER","parts":["PUSH","GUARD"]})
	var s = Session.arena_test(seed,party_size,preset,members)
	s.manual_mode = true
	if hero_hp != 55:
		s.party[0].max_hp = hero_hp; s.party[0].hp = hero_hp
	var initial: int = s.enemies.filter(func(e): return e.hp > 0).size()
	var result := "TIMEOUT"
	for _turn in range(limit):
		if s.party[0].hp <= 0 or s.phase == "DEFEAT": result = "DEFEAT"; break
		if s.enemies.all(func(e): return e.hp <= 0): result = "WIN"; break
		var hero: Dictionary = s.party[0]
		hero.ap = 1
		var choice: Dictionary = Tactics.choose(s,hero)
		var kind: String = str(choice.get("kind","WAIT"))
		var target: Vector2i = choice.get("cell",hero.pos)
		if kind == "WAIT" and s.party_enemies().is_empty():
			var goals: Array = []
			for enemy in s.enemies:
				if enemy.hp <= 0: continue
				for direction in s.DIRECTIONS:
					var cell: Vector2i = enemy.pos+direction
					if s.is_free(cell) and s.melee_reach(cell,enemy.pos): goals.append(cell)
			if not goals.is_empty():
				var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,hero.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
				if route.found and route.path.size() > 1: kind = "MOVE"; target = route.path[1]
		if not s.submit(kind,target): s.submit("WAIT",hero.pos)
	if result == "TIMEOUT" and s.enemies.all(func(e): return e.hp <= 0): result = "WIN"
	elif result == "TIMEOUT" and s.party[0].hp <= 0: result = "DEFEAT"
	return {"result":result,"time":s.time,"hero_actions":s.turn_serial,"initial_enemies":initial,
		"remaining_hp":s.party[0].hp,"remaining_enemies":s.enemies.filter(func(e): return e.hp > 0).size(),
		"skills":s.party[0].skill_xp.duplicate(true)}

static func run_many(arena_id: String, party_size: int, seeds: Array, hero_hp: int = 55) -> Dictionary:
	var results := {"WIN":0,"DEFEAT":0,"TIMEOUT":0,"INVALID":0}
	var rows: Array = []
	for seed in seeds:
		var row: Dictionary = run_one(arena_id,party_size,int(seed),80,hero_hp)
		results[row.result] = int(results.get(row.result,0))+1
		rows.append(row)
	return {"arena":arena_id,"party_size":party_size,"hero_hp":hero_hp,"samples":seeds.size(),"results":results,
		"win_rate":float(results.WIN)/maxi(1,seeds.size()),"runs":rows}
