extends SceneTree
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func _initialize() -> void:
	call_deferred("exercise")

func exercise() -> void:
	attack_effect_checks()
	pacing_checks()
	var s = Session.new(731,true)
	s.depart()
	check(s.party.size() == 1 and s.phase == "BATTLE","solo begins with boss")
	for id in range(9):
		s.room = id; s.enter_room()
		check(s.enemies.size() == 1 and s.rooms[id].kind == "boss","one boss in every room")
		var boss: Dictionary = s.enemies[0]
		if id % 3 in [0,1]:
			boss.cooldown = 0
			if id % 3 == 0:
				boss.cooldown = 0; s.party[0].pos = boss.pos+Vector2i.LEFT
			s.round_number = 3; s.plan_enemies()
			check(not s.intents.is_empty(),"special attack telegraphed")
			s.party[0].pos = s.intents[0].cell
			var hp: int = s.party[0].hp
			s.enemy_attack_turn(boss)
			check(s.party[0].hp == hp,"blast allows first escape action")
			s.enemy_attack_turn(boss)
			check(s.party[0].hp == hp-16,"marked cells resolve once")
			if id % 3 == 0:
				check(boss.recovery == 1,"goo has one-action recovery window")
				s.party[0].pos = boss.pos+Vector2i.LEFT
				hp = s.party[0].hp
				for step in range(1):
					s.enemy_attack_turn(boss); s.plan_enemies()
					check(s.intents.is_empty() and s.party[0].hp == hp,"recovery allows approach and attack without retaliation")
				for step in range(3):
					s.enemy_attack_turn(boss); s.plan_enemies()
					check(s.intents.is_empty(),"no immediate repeat charge")
			s.party[0].hp = s.party[0].max_hp
		else:
			boss.hp = 32; s.plan_enemies()
			check(s.rooms[id].shield,"half health activates shield")
			s.damage(boss,10,0,"SLASH")
			check(boss.hp == 32,"shield blocks damage")
			s.party[0].pos = s.rooms[id].pylon+Vector2i.LEFT
			check(s.act("PYLON",s.rooms[id].pylon),"adjacent hero disables pylon")
			check(not s.rooms[id].shield,"pylon releases shield")
		s.damage(boss,1000,0,"SLASH"); s.check_battle_end()
		check(s.phase == "EXPLORE" and s.party[0].hp == s.party[0].max_hp,"win clears and heals")
		s.enter_room()
		check(s.phase == "EXPLORE" and s.enemies.size() == 1,"cleared boss never respawns")
	var scene = load("res://expedition/main.tscn").instantiate()
	scene.session = Session.new(731,true)
	root.add_child(scene); scene.depart()
	await process_frame
	scene.session.enemy_attack_effect(scene.session.enemies[0],[Vector2i(2,2),Vector2i(3,2)],true)
	scene.action_effects = scene.session.effects.duplicate(true); scene.session.effects.clear(); scene.refresh()
	await process_frame
	check(scene.board.effects.any(func(e): return e.get("kind","") == "ENEMY_ATTACK"),"board receives blast effects without a damage event")
	scene.board.effect_time = 0.25; scene.refresh()
	check(not scene.board.effects.is_empty() and scene.board.effect_time == 0.25,"non-action UI refresh preserves effect and elapsed time")
	scene.board._process(1.1)
	check(scene.board.effects.is_empty(),"attack effects expire without consuming a turn")
	check(scene.portrait_buttons.size() == 1 and scene.skill_buttons.size() == 2,"solo UI")
	check(scene.end_turn_button == null,"action mode has no end-turn control")
	var game = scene.session
	var before: int = game.round_number
	var position: Vector2i = game.party[0].pos
	check(not game.act("MOVE",position+Vector2i(2,0)),"long move rejected")
	check(game.round_number == before,"invalid action costs no time")
	check(game.act("MOVE",position+Vector2i.LEFT),"one tile movement")
	check(game.round_number == before+1 and game.party[0].ap == 1,"one action advances exactly once")
	before = game.round_number
	game.attack_preview(game.enemies[0].pos)
	check(game.round_number == before,"preview costs no time")
	game.act("WAIT",game.party[0].pos)
	check(game.round_number == before+1,"wait advances world")
	before = game.round_number
	game.party[0].hp -= 5
	check(game.use_supply(0),"potion succeeds")
	check(game.round_number == before+1,"potion advances exactly once")
	game.tile(game.party[0].pos).terrain = "wood"
	before = game.round_number
	check(game.use_supply(3,game.party[0].pos),"scroll succeeds")
	check(game.round_number == before+1,"scroll does not double advance")
	game.intents.clear(); game.enemies[0].charging = false; game.enemies[0].fuse = 0
	game.enemies[0].recovery = 2; game.enemies[0].pos = Vector2i(3,4)
	game.party[0].pos = Vector2i(2,4); game.party[0].hp = game.party[0].max_hp
	game.tile(game.party[0].pos).fire = 0
	before = game.round_number
	var enemy_hp: int = game.enemies[0].hp
	scene.on_cell(game.enemies[0].pos)
	check(game.enemies[0].hp < enemy_hp and game.round_number == before+1,"touch immediately attacks and advances once")
	check(scene.pending_attack.is_empty() and scene.attack_button == null,"no attack confirmation")
	check(not scene.board.effects.any(func(e): return e.get("body_injury",false)),"ordinary tissue damage does not trigger injury feedback")
	scene.board.impact_time = 0; scene.board.effect_time = 0; scene.board._process(0.1)
	check(scene.board.impact_transform().zoom == 1 and is_equal_approx(scene.board.effect_time,0.1),"ordinary hits have no zoom or slow motion")
	var victim: Dictionary = game.enemies[0]
	for part in victim.body.parts:
		if part.part_id in victim.body.LIMB_PART_IDS:
			for layer in part.layers: layer.integrity = 1
	game.effects.clear()
	for attempt in range(100):
		victim.hp = victim.max_hp
		game.damage(victim,8,game.party[0].id,"IMPACT")
		if game.effects[-1].get("body_injury",false): break
	check(game.effects.any(func(e): return e.get("body_injury",false)),"new limb disability triggers injury feedback")
	scene.board.effects = game.effects.duplicate(true)
	scene.board.impact_time = 0; scene.board.effect_time = 0; scene.board._process(0.1)
	var camera: Dictionary = scene.board.impact_transform()
	check(camera.zoom > 1 and scene.board.effect_time < 0.1,"body injury zoom and slow animation")
	var hit_cell := Vector2i(3,3)
	check(scene.board.cell_at(scene.board.cell_center(hit_cell)*camera.zoom+camera.offset) == hit_cell,"zoomed tile input uses inverse camera")
	scene.board._process(2)
	check(scene.board.impact_transform().zoom == 1 and scene.board.effects.is_empty(),"cinematic restores camera and expires")
	for part in victim.body.parts:
		if part.part_id in victim.body.LIMB_PART_IDS:
			part.condition = "DISABLED"
			part.condition_source_event_id = game.serial
			for layer in part.layers: layer.integrity = 0
	game.effects.clear()
	for attempt in range(20):
		victim.hp = victim.max_hp
		game.damage(victim,8,game.party[0].id,"IMPACT")
	check(not game.effects.any(func(e): return e.get("body_injury",false)),"repeated hits on disabled limbs do not replay cinematic")
	for viewport_size in [Vector2i(390,844),Vector2i(430,844),Vector2i(412,915)]:
		root.size = viewport_size
		for frame in range(5): await process_frame
		scene.board.geometry()
		check(scene.board.half_width == scene.board.half_height,"square top-down tiles")
		check(absf(scene.board.size.x-scene.size.x) < 1,"board fills screen width")
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"portrait layout fits screen")
		for y in range(8):
			for x in range(8):
				var cell := Vector2i(x,y)
				check(scene.board.cell_at(scene.board.cell_center(cell)) == cell,"64 top-down touch targets")
		check(scene.board.cell_at(Vector2(5,5)) == Vector2i.ZERO,"board starts immediately below HUD without boss info band")
		check(scene.board.find_children("*","Label",true,false).is_empty(),"no monster name HP or countdown panel over board")
		check(not game.inside(scene.board.cell_at(Vector2(5,scene.board.size.y-5))),"footer is not a tile")
	scene.queue_free(); await process_frame
	print("Boss trial: %d failures" % failures)
	quit(1 if failures else 0)

func pacing_checks() -> void:
	for pattern in [0,1,2]:
		var s = Session.new(731,true); s.depart(); s.room = pattern; s.enter_room()
		var boss: Dictionary = s.enemies[0]
		for tile in s.tiles: tile.terrain = "stone"; tile.fire = 0
		boss.pos = Vector2i(4,4); s.party[0].pos = Vector2i(2,4)
		var hp: int = s.party[0].hp
		s.enemy_attack_turn(boss)
		check(s.party[0].hp == hp-8 and s.melee_reach(boss.pos,s.party[0].pos),"boss approaches and attacks on same turn")
		if pattern == 2: continue
		boss.charging = true; boss.fuse = 1
		s.intents = [{"id":boss.id,"cell":Vector2i.ZERO,"damage":16}]
		s.enemy_attack_turn(boss); s.plan_enemies()
		check(boss.cooldown == 6 and boss.recovery == 1 and s.intents.is_empty(),"blast starts recovery and six ordinary actions")
		s.enemy_attack_turn(boss); s.plan_enemies()
		for tick in range(5):
			s.party[0].hp = s.party[0].max_hp
			s.enemy_attack_turn(boss); s.plan_enemies()
			check(not boss.charging and s.intents.is_empty(),"no repeated pattern during cooldown")

func attack_effect_checks() -> void:
	for pattern in [0,1]:
		var s = Session.new(731,true); s.depart(); s.room = pattern; s.enter_room()
		var boss: Dictionary = s.enemies[0]
		boss.cooldown = 0; s.party[0].pos = boss.pos+Vector2i.LEFT
		s.round_number = 3; s.plan_enemies(); s.effects.clear()
		var marked: Array = s.intents.map(func(i): return i.cell)
		s.party[0].pos = Vector2i.ZERO
		var hp: int = s.party[0].hp
		s.enemy_attack_turn(boss)
		check(s.effects.is_empty(),"charging is not rendered as an executed attack")
		s.enemy_attack_turn(boss)
		var blasts: Array = s.effects.filter(func(e): return e.get("kind","") == "ENEMY_ATTACK")
		check(blasts.size() == 1 and blasts[0].cells == marked and blasts[0].area,"empty blast still renders every marked tile once")
		check(s.party[0].hp == hp and s.effects.size() == 1,"missed blast has no fake damage number")
	var s = Session.new(731,true); s.depart()
	var boss: Dictionary = s.enemies[0]
	s.party[0].pos = boss.pos+Vector2i.LEFT; boss.cooldown = 9
	s.effects.clear(); s.enemy_attack_turn(boss)
	check(s.effects.size() == 2 and s.effects[0].get("kind","") == "ENEMY_ATTACK" and not s.effects[0].area and s.effects[1].amount > 0,"melee has attack motion plus real damage feedback")
	boss.charging = true; boss.fuse = 1; s.intents.clear(); s.effects.clear()
	s.enemy_attack_turn(boss)
	check(s.effects.is_empty(),"interrupted warning does not show a blast")
