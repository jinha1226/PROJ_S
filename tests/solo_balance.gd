extends SceneTree
## Scripted first-floor descent using only public actions and paid camps.
const Session = preload("res://expedition/session.gd")
const Curios = preload("res://expedition/curios.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const SEEDS := 8
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func route(s, target: Vector2i) -> Array:
	var goals: Array = [target]
	for d in s.DIRECTIONS:
		if s.distance(target+d,target) == 1 and s.inside(target+d) and s.tile(target+d).terrain != "wall": goals.append(target+d)
	var found: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,s.party[0].pos,goals,
		func(a,b): return s.can_step(a,b),func(_p): return 100)
	return found.path if found.found else []

func play(seed: int) -> Dictionary:
	var s = Session.new_run(seed)
	var hero: Dictionary = s.party[0]
	# A real player can use the first ration to prepare the two starting parts.
	if s.camp():
		s.equip_part(0,0,"PUSH"); s.equip_part(0,1,"GUARD"); s.end_camp()
	var actions := 0; var camps := 1; var stalls := 0
	while s.on_floor() and s.depth == 1 and actions < 500:
		if not s.combat_enemies().is_empty():
			if Fixture.fight_round(s): actions += 1; continue
			if s.act("WAIT",hero.pos): actions += 1; continue
			break
		if hero.hp <= 35 and s.can_camp().is_empty():
			if s.camp(): camps += 1; s.end_camp(); continue
		var searched := false
		for p in s.floor_state.features:
			var feature: Dictionary = s.floor_state.features[p]
			if feature.get("kind","") != "curio" or feature.get("used",false): continue
			if s.distance(hero.pos,p) > 1 or not s.floor_state.visible.has(p): continue
			if Curios.resolve(s,p,"SEARCH"):
				actions += 1; searched = true; break
		if searched: continue
		var stairs: Vector2i = s.floor_state.layout.stairs
		if s.distance(hero.pos,stairs) <= 1:
			if s.descend(): break
		var path: Array = route(s,stairs)
		if path.size() < 2:
			stalls += 1
			if stalls >= 3: break
			if s.act("WAIT",hero.pos): actions += 1
			continue
		stalls = 0
		if s.act("MOVE",path[1]): actions += 1
		else:
			stalls += 1
			if stalls >= 3: break
	return {"reason":"DESCENDED" if s.depth >= 2 else "DEAD" if s.phase == "DEFEAT" else "STUCK",
		"actions":actions,"camps":camps,"kills":int(s.run_stats.kills),"hp":hero.hp,"food":s.food,"depth":s.depth}

func run() -> void:
	var wins := 0
	for seed in range(SEEDS):
		var row: Dictionary = play(seed)
		print("seed %d: %s · 행동 %d · 야영 %d · 처치 %d · HP %d · 식량 %d" % [seed,row.reason,row.actions,row.camps,row.kills,row.hp,row.food])
		if row.reason == "DESCENDED": wins += 1
		check(row.reason != "STUCK","pathing never stalls (seed %d)" % seed)
		check(row.actions <= 500,"first-floor run ends within action limit (seed %d)" % seed)
		check(row.camps >= 1 and row.food >= 0,"camp uses nonnegative food (seed %d)" % seed)
		check(row.depth == 2 if row.reason == "DESCENDED" else row.depth == 1,"depth matches outcome (seed %d)" % seed)
	check(wins >= 3,"solo bot descends at least 3 of 8 (%d/8)" % wins)
	print("Solo balance: %d failures; %d/8 descents" % [failures,wins]); quit(1 if failures else 0)
