extends SceneTree
## Scripted first-floor descent using only public actions and paid camps.
const Session = preload("res://expedition/session.gd")
const Curios = preload("res://expedition/curios.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const SEEDS := 8
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func route(s, target: Vector2i) -> Array:
	var goals: Array = [target]
	for d in s.DIRECTIONS:
		if s.distance(target+d,target) == 1 and s.inside(target+d) and s.tile(target+d).terrain != "wall": goals.append(target+d)
	var found: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,s.party[0].pos,goals,
		func(a,b): return s.can_step(a,b),func(_p): return 100)
	if found.found: return found.path
	# A living enemy can block the only passage even before the hero sees it.
	# In that case path to the near side of the blocker and fight it there.
	var blocked_goals: Array = []
	for enemy in s.enemies:
		if enemy.hp <= 0: continue
		for direction in s.DIRECTIONS:
			var cell: Vector2i = enemy.pos+direction
			if s.is_free(cell) and s.melee_reach(cell,enemy.pos): blocked_goals.append(cell)
	if blocked_goals.is_empty(): return []
	var approach: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,s.party[0].pos,blocked_goals,
		func(a,b): return s.can_step(a,b),func(_p): return 100)
	return approach.path if approach.found else []

func play(seed: int) -> Dictionary:
	var s = Session.new_run(seed)
	# A real player can use the first ration to prepare the two starting parts.
	if s.camp():
		s.equip_part(0,0,"PUSH"); s.equip_part(0,1,"GUARD"); s.end_camp()
	var row: Dictionary = clear_floor(s,1)
	row.session = s
	return row

## One floor, from where the hero stands to the stairs down: fight what is in
## the way, search what is in reach, camp when hurt, then descend.
func clear_floor(s, camps: int) -> Dictionary:
	var hero: Dictionary = s.party[0]
	var entered: int = s.depth
	var actions := 0; var stalls := 0
	while s.on_floor() and s.depth == entered and actions < 500:
		if not s.party_enemies().is_empty():
			if Fixture.hero_turn(s): actions += 1; continue
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
	return {"reason":"DESCENDED" if s.depth > entered else "DEAD" if s.phase == "DEFEAT" else "STUCK",
		"actions":actions,"camps":camps,"kills":int(s.run_stats.kills),"hp":hero.hp,"food":s.food,
		"depth":s.depth,"score":int(s.score),"stalled":stalls >= 3}

func run() -> void:
	var wins := 0
	var deaths := 0
	for seed in range(SEEDS):
		var row: Dictionary = play(seed)
		print("seed %d: %s · 행동 %d · 야영 %d · 처치 %d · HP %d · 식량 %d" % [seed,row.reason,row.actions,row.camps,row.kills,row.hp,row.food])
		if row.reason == "DESCENDED": wins += 1
		if row.reason == "DEAD": deaths += 1
		check(row.reason != "STUCK","pathing never stalls (seed %d)" % seed)
		check(row.actions <= 500,"first-floor run ends within action limit (seed %d)" % seed)
		check(row.camps >= 1 and row.food >= 0,"camp uses nonnegative food (seed %d)" % seed)
		check(row.depth == 2 if row.reason == "DESCENDED" else row.depth == 1,"depth matches outcome (seed %d)" % seed)
		check(row.reason != "DESCENDED" or row.hp > 0,"a hero that took the stairs is alive at the bottom (seed %d)" % seed)
		check(row.food >= 0 and row.score >= 0,"food and score never go negative (seed %d)" % seed)
	check(wins+deaths == SEEDS,"all solo runs end in descent or death (%d/%d)" % [wins,deaths])
	campaign()
	print("Solo balance: %d checks, %d failures; %d/8 descents" % [checks,failures,wins]); quit(1 if failures else 0)

## The run is one descent, not one floor: the same hero keeps going down until
## it dies or runs out of road. Guards the lifecycle the old town round trip
## used to guard — no return, no refit, just the next floor.
func campaign() -> void:
	var s = Session.new_run(6)
	if s.camp():
		s.equip_part(0,0,"PUSH"); s.equip_part(0,1,"GUARD"); s.end_camp()
	var reached := 1; var camps := 1; var last: Dictionary = {}
	for attempt in range(2):
		if not s.on_floor(): break
		last = clear_floor(s,camps)
		camps = int(last.camps)
		print("campaign floor %d: %s · 행동 %d · 점수 %d · 식량 %d · HP %d" % [reached,last.reason,last.actions,last.score,last.food,last.hp])
		check(not bool(last.stalled),"the campaign's pathing never stalls on floor %d" % reached)
		if last.reason != "DESCENDED": break
		check(s.depth == reached+1,"the stairs land the hero one floor deeper (floor %d)" % reached)
		reached = int(s.depth)
	check(reached >= 1 and s.turn_serial > 0,"the same hero takes manual actions in the campaign (%d)" % reached)
	check(s.score > 0 or s.phase == "DEFEAT","a descent that got anywhere scored something")
	check(s.food >= 0 and int(s.run_stats.kills) >= 0,"the campaign leaves the run counters intact")
