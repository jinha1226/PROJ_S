extends SceneTree
## Solo first-floor relic loop: placement, pickup, return, settlement, rollback.
const Session = preload("res://expedition/session.gd")
const Objective = preload("res://expedition/expedition_objective.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func solo(seed_value: int = 731) -> Variant:
	var s = Session.new(seed_value,true,false,true); s.depart(); return s

func relic_pos(s) -> Vector2i:
	return s.objective.pos

func entry_pos(s) -> Vector2i:
	return s.entry_position()

func stand_beside(s, p: Vector2i) -> void:
	for d in s.DIRECTIONS:
		var cell: Vector2i = p+d
		if s.inside(cell) and s.tile(cell).terrain != "wall" and s.melee_reach(cell,p):
			s.party[0].pos = cell; s.floor_state.observe(s); return
	check(false,"no adjacent cell for %s" % p)

func run() -> void:
	# --- placement over many seeds -------------------------------------------
	for seed_value in range(100):
		var s = solo(seed_value)
		var relics: Array = s.floor_state.features.keys().filter(func(p): return s.floor_state.features[p].kind == "relic")
		check(relics.size() == 1,"exactly one mission relic (seed %d)" % seed_value)
		check(s.floor_state.features.values().filter(func(f): return f.kind == "exit").is_empty(),"deep exit no longer grants instant success")
		check(s.floor_state.features.get(entry_pos(s),{}).get("kind","") == "entry","entry feature survives registration order")
		if relics.is_empty(): continue
		var p: Vector2i = relics[0]
		check(p == relic_pos(s) and s.objective.state == "UNDISCOVERED","objective tracks the placed relic")
		check(p != entry_pos(s) and s.tile(p).terrain != "wall","relic not on entry or wall")
		check(s.enemies.all(func(e): return e.pos != p),"relic not on an enemy start")
		var reach: Dictionary = Objective.reachability(s,entry_pos(s))
		check(reach.has(p),"relic reachable from entry (seed %d)" % seed_value)
		var adjacent := false
		for d in s.DIRECTIONS:
			if reach.has(p+d) and s.melee_reach(p+d,p): adjacent = true
		check(adjacent,"relic has a reachable interaction cell")
		check(reach[p] >= 40,"relic is far from the entry (seed %d: %d)" % [seed_value,reach[p]])
		var altars: Array = s.floor_state.features.values().filter(func(f): return f.kind == "altar")
		check(altars.size() == 1,"legacy relic landmark separated as altar")
		var same = solo(seed_value)
		check(relic_pos(same) == p,"placement reproducible by seed")

	# --- fallback placement when the preferred cell is unusable -------------------
	var blocked = solo()
	var preferred: Vector2i = relic_pos(blocked)
	blocked.floor_state.features.erase(preferred)
	blocked.floor_state.features[preferred] = {"kind":"curio","curio_id":"LOCKED_CHEST","used":false,"label":"x"}
	var entry: Vector2i = entry_pos(blocked)
	var reach: Dictionary = Objective.reachability(blocked,entry)
	var farthest := 0
	for value in reach.values(): farthest = maxi(farthest,int(value))
	var alternative: Vector2i = Objective.choose(blocked,blocked.floor_state,entry,preferred)
	check(alternative != preferred and reach.has(alternative) and reach[alternative] >= farthest*Objective.FAR_BAND_RATIO,"blocked preferred cell falls back to the far band")
	check(alternative == Objective.choose(blocked,blocked.floor_state,entry,preferred),"fallback choice is deterministic")
	check(not blocked.floor_state.features.has(alternative) and blocked.enemies.all(func(e): return e.pos != alternative),"fallback avoids features and enemy starts")

	# --- solo party --------------------------------------------------------------
	var s = solo()
	check(s.party.size() == 1 and not s.companions,"solo party")
	check(s.companion_previews().is_empty() and not s.reserve_action(0,"WAIT",s.party[0].pos),"no companion reservation in solo")
	check(s.objective_text() == "유물 찾기","objective starts with finding the relic")

	# --- hidden until seen -----------------------------------------------------
	var p: Vector2i = relic_pos(s)
	check(not s.floor_state.explored.has(p),"relic starts hidden")
	check(s.floor_state.discoveries.all(func(row): return row.marker != "PORTAL"),"no relic marker before discovery")
	var scene = load("res://expedition/main.tscn").instantiate(); scene.session = s
	root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	check(not scene.navigation.start(s,p),"hidden relic is not a navigation target")

	# --- discovery stops navigation ------------------------------------------
	for enemy in s.enemies: enemy.hp = 0
	var far: Vector2i = p
	for d in [Vector2i(-6,0),Vector2i(6,0),Vector2i(0,-6),Vector2i(0,6)]:
		var cell: Vector2i = p+d
		if s.inside(cell) and s.tile(cell).terrain != "wall": far = cell; break
	s.party[0].pos = far; s.light = 100; s.floor_state.explored.erase(p); s.floor_state.observe(s)
	check(s.objective.state == "DISCOVERED","seeing the relic discovers it")
	check(s.floor_state.discoveries.any(func(row): return row.position == [p.x,p.y] and row.marker == "PORTAL"),"discovery marks the map")
	check(s.log_lines.back().contains("유물"),"discovery is logged")
	var again = solo(); for enemy in again.enemies: enemy.hp = 0
	again.party[0].pos = far; again.light = 100
	scene.session = again; scene.refresh(); await process_frame
	scene.navigation.explore(again)
	var stopped := false
	for i in range(30):
		if not scene.navigation.active: stopped = true; break
		scene.navigation_tick()
		if again.objective.state == "DISCOVERED":
			check(not scene.navigation.active,"auto explore halts on relic discovery"); stopped = true; break
	check(stopped,"navigation loop ends")
	scene.session = s; scene.refresh(); await process_frame

	# --- pickup rules --------------------------------------------------------
	var turn: int = s.round_number
	s.party[0].pos = far; s.floor_state.observe(s)
	check(not s.pickup_relic() and s.objective.state == "DISCOVERED","remote pickup refused")
	stand_beside(s,p)
	scene.on_cell(p); await process_frame
	check(scene.details_popup.visible and s.round_number == turn and s.objective.state == "DISCOVERED","relic popup is free")
	var close: Button = scene.modal_content.find_children("*","Button",true,false).filter(func(b): return b.text == "닫기")[0]
	close.pressed.emit()
	check(not scene.details_popup.visible and s.round_number == turn,"closing costs nothing")
	await process_frame
	s.enemies[0].hp = 20; s.enemies[0].pos = s.party[0].pos+Vector2i(0,-1) if s.is_free(s.party[0].pos+Vector2i(0,-1)) else s.party[0].pos+Vector2i(0,1); s.floor_state.observe(s)
	check(not s.pickup_relic() and s.objective.state == "DISCOVERED","visible enemy blocks pickup")
	s.enemies[0].hp = 0; s.floor_state.observe(s)
	var two_away = solo(); for enemy in two_away.enemies: enemy.hp = 0
	var wp: Vector2i = relic_pos(two_away)
	stand_beside(two_away,wp)
	var far2: Vector2i = wp+(two_away.party[0].pos-wp)*2
	if two_away.inside(far2) and two_away.tile(far2).terrain != "wall":
		two_away.party[0].pos = far2; two_away.floor_state.observe(two_away)
		check(not two_away.pickup_relic(),"two tiles away is not adjacent")
	check(s.pickup_relic(),"adjacent safe pickup accepted")
	check(s.objective.state == "CARRIED" and s.round_number == turn+1,"pickup costs exactly one action")
	check(not s.floor_state.features.has(p),"world relic removed after pickup")
	check(s.floor_state.discoveries.all(func(row): return row.position != [p.x,p.y] or row.marker == ""),"map marker cleared after pickup")
	check(not s.pickup_relic() and s.objective.state == "CARRIED","no double pickup")
	check(s.objective_text() == "입구로 귀환","objective switches to returning")
	check(s.phase == "BATTLE" and s.result.is_empty(),"pickup alone is not success")
	check(scene.inventory_rows().any(func(r): return r.category == "임무"),"relic shows as a mission item")

	# --- return rules --------------------------------------------------------
	check(not s.retreat(),"generic retreat disabled on the continuous floor")
	check(not s.return_home(),"return needs adjacency to the entry")
	var bank: int = s.bank
	stand_beside(s,entry_pos(s))
	s.enemies[1].hp = 20; s.enemies[1].pos = s.party[0].pos+Vector2i(0,1) if s.is_free(s.party[0].pos+Vector2i(0,1)) else s.party[0].pos+Vector2i(0,-1); s.floor_state.observe(s)
	check(not s.return_home(),"visible enemy blocks return")
	s.enemies[1].hp = 0; s.floor_state.observe(s)
	s.loot = 40
	scene.on_cell(entry_pos(s)); await process_frame
	check(scene.details_popup.visible and s.phase == "BATTLE","return asks for confirmation first")
	var confirm: Button = scene.modal_content.find_children("*","Button",true,false).filter(func(b): return b.text.begins_with("귀환"))[0]
	confirm.pressed.emit(); await process_frame
	check(s.phase == "TOWN" and s.result.reason == "SUCCESS","relic delivered at the entry is a success")
	check(s.bank == bank+40+100 and s.result.settled,"loot plus one recovery bonus")
	check(s.objective.state == "DELIVERED","relic returned")
	check(not s.return_home() and s.bank == bank+140,"repeat return pays nothing")
	scene.refresh(); await process_frame
	check(scene.find_child("ResultCard",true,false) != null,"result card shown")
	var refit: Button = scene.root_layout.find_children("*","Button",true,false).filter(func(b): return b.text == "정비하기")[0]
	refit.pressed.emit(); await process_frame
	check(s.bank == bank+140 and s.result.is_empty(),"refit acknowledges without paying again")
	check(scene.find_child("ResultCard",true,false) == null,"result card dismissed")

	# --- re-departure clears mission state --------------------------------------
	check(s.depart(),"same hero departs again")
	check(s.objective.state == "UNDISCOVERED" and s.objective.expedition == 2 and s.result.is_empty(),"new expedition resets objective")
	check(s.loot == 0 and scene.inventory_rows().all(func(r): return r.category != "임무"),"carried relic never persists")
	check(s.floor_state.features.values().filter(func(f): return f.kind == "relic").size() == 1,"new relic placed")

	# --- partial return without relic -----------------------------------------
	for enemy in s.enemies: enemy.hp = 0
	bank = s.bank; s.loot = 25
	stand_beside(s,entry_pos(s))
	check(s.return_home() and s.result.reason == "PARTIAL" and s.bank == bank+25,"return without relic is partial success")
	check(s.objective.state == "LOST","undelivered relic is lost")
	s.refit(); check(s.depart(),"third expedition")

	# --- defeat rollback -----------------------------------------------------
	var hero: Dictionary = s.party[0]
	bank = s.bank
	var level: int = hero.growth.level; var memories: int = hero.memory.records.size(); var hp_before: int = hero.hp
	s.essences["BOMB"] = 3; s.loot = 90; s.objective.state = "CARRIED"
	Session.Growth.gain(hero,10000)
	check(hero.growth.level > level,"expedition growth happened")
	s.enemies[0].pos = hero.pos+Vector2i.RIGHT; s.floor_state.observe(s)
	hero.hp = 1
	s.damage(hero,50,s.enemies[0].id,"IMPACT")
	s.check_battle_end()
	check(s.phase == "TOWN" and s.result.reason == "DEFEAT","defeat ends the expedition")
	check(s.bank == bank and s.essences.get("BOMB",0) == 0 and s.party[0].growth.level == level and s.party[0].hp == hp_before,"defeat restores the departure snapshot")
	check(s.party[0].memory.records.size() == memories and s.objective.state == "LOST","expedition memories and relic are lost")
	check(s.party[0].hp > 0 and s.alive().size() == 1,"hero survives to redeploy")
	s.refit(); check(s.depart(),"same hero departs after defeat")

	# --- pickup then death in the same action ----------------------------------
	for enemy in s.enemies: enemy.hp = 0
	p = relic_pos(s); stand_beside(s,p)
	s.enemies[0].hp = 20; s.enemies[0].pos = Vector2i(99,99)
	s.party[0].hp = 1; s.tile(s.party[0].pos).terrain = "wood"; s.tile(s.party[0].pos).fire = 100
	s.floor_state.observe(s)
	check(s.pickup_relic(),"pickup accepted before fire resolves")
	check(s.phase == "TOWN" and s.result.reason == "DEFEAT","dying during the pickup action is a defeat, not success")

	# --- abandon -----------------------------------------------------------------
	s.refit(); s.depart(); bank = s.bank; s.loot = 50; s.essences["BOMB"] = 2
	check(s.abandon() and s.result.reason == "ABANDON" and s.bank == bank+50+s.result.provisions and s.essences.get("BOMB",0) == 2,"abandon keeps expedition loot and essences")
	check(not s.abandon(),"abandon once")
	s.refit()
	check(s.depart() and s.phase == "BATTLE","redeploy after abandon")

	# --- free refit ------------------------------------------------------------
	s.abandon(); s.bank = 0; s.party[0].hp = 3; s.party[0].stress = 190
	check(not s.rest_town(),"paid rest needs funds")
	check(s.refit() and s.party[0].hp >= s.party[0].max_hp*6/10 and s.party[0].stress < 100,"free refit restores a survivable state")
	check(s.depart(),"no money never blocks the next expedition")

	# --- mobile layout ------------------------------------------------------------
	for viewport in [Vector2i(390,844),Vector2i(412,915)]:
		root.size = viewport
		s.refit(); s.depart(); scene.refresh()
		for frame in range(4): await process_frame
		check(scene.root_layout.get_child(0).size.y < 70,"objective chip keeps the HUD compact")
		var chip: Button = scene.find_child("ObjectiveChip",true,false)
		check(chip != null and chip.text == "유물찾기" and scene.get_global_rect().encloses(chip.get_global_rect()),"objective chip visible and on screen")
		check(scene.portrait_buttons.size() == 1 and scene.skill_buttons.size() == 2 and scene.item_buttons.size() == 6,"one portrait, two abilities, shared supplies")
		for node in scene.item_buttons+scene.skill_buttons+scene.portrait_buttons:
			check(node.size.y >= 44 and scene.get_global_rect().encloses(node.get_global_rect()),"solo touch targets on screen")
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"solo layout fits portrait screen")
		var nav_texts: Array = scene.root_layout.get_child(scene.root_layout.get_child_count()-1).get_children().map(func(b): return b.text)
		check("전술" in nav_texts and "원정" not in nav_texts,"footer contains tactics; expedition menu lives in header")
		chip.pressed.emit(); await process_frame
		check(scene.details_popup.visible and scene.details_popup.size.x <= viewport.x,"objective popup fits")
		scene.details_popup.hide(); await process_frame
		s.abandon(); scene.refresh()
		for frame in range(4): await process_frame
		var card: Control = scene.find_child("ResultCard",true,false)
		check(card != null and scene.get_global_rect().encloses(card.get_global_rect()),"result card fits portrait screen")
		var footer: Control = scene.root_layout.get_child(scene.root_layout.get_child_count()-1)
		check(scene.get_global_rect().encloses(footer.get_global_rect()) and footer.get_global_rect().position.y > card.get_global_rect().end.y,"result card leaves the footer on screen")
	root.size = Vector2i(390,844)

	# --- companion mode still works --------------------------------------------
	var duo = Session.new(731,true,true,true); duo.depart()
	check(duo.party.size() == 2 and duo.objective.state == "UNDISCOVERED","companion floor keeps the same objective")

	scene.queue_free(); await process_frame
	print("Solo floor: %d failures" % failures); quit(1 if failures else 0)
