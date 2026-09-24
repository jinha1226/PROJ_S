extends SceneTree
## Solo descent: stair placement, visibility, camp, persistence, and death.
const Session = preload("res://expedition/run/session.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const Generator = preload("res://expedition/level/floor_generator.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	for seed in range(100):
		var s = Session.new_run(seed)
		var layout: Dictionary = s.floor_state.layout
		var stairs: Vector2i = layout.stairs
		check(s.party.size() == 1 and not s.companions,"seed %d starts solo" % seed)
		check(s.food == 2 and s.bag.is_empty(),"seed %d uses run resources" % seed)
		check(stairs.x >= 0 and s.floor_state.features.get(stairs,{}).get("kind","") == "stairs","seed %d has stairs" % seed)
		check(stairs != layout.entry and s.tile(stairs).terrain != "wall","seed %d stairs separate from entry" % seed)
		check(s.floor_state.features.values().filter(func(f): return f.get("kind","") == "stairs").size() == 1,"seed %d exactly one stair" % seed)
		check(s.floor_state.features.values().all(func(f): return f.get("kind","") != "relic"),"seed %d has no mission relic" % seed)
		check(s.enemies.all(func(e): return e.pos != stairs and e.pos != layout.entry),"seed %d endpoints have no enemy" % seed)
		check(Generator.validate(layout,Floor.theme_for(1)).is_empty(),"seed %d floor validates" % seed)
		check(s.floor_state.sight_radius() == 6.0 and s.floor_state.visible.has(layout.entry),"seed %d six-tile sight sees entry" % seed)
		check(not s.descend(),"seed %d cannot descend remotely" % seed)
	var s = Session.new_run(731)
	check(s.companion_previews().is_empty() and not s.reserve_action(0,"WAIT",s.party[0].pos),"solo has no companion reservation")
	var stairs: Vector2i = s.floor_state.layout.stairs
	check(not s.floor_state.explored.has(stairs),"distant stairs start unseen")
	for enemy in s.enemies: enemy.hp = 0
	s.party[0].pos = stairs+Vector2i.LEFT; s.floor_state.observe(s)
	check(s.floor_state.visible.has(stairs) and s.floor_state.explored.has(stairs),"walking up reveals stairs")
	var old_food: int = s.food
	check(s.camp() and s.food == old_food-1,"solo camp costs one food")
	check(s.end_camp() and s.phase == "EXPLORE","camp returns to exploration")
	var hp: int = s.party[0].hp
	check(s.descend() and s.depth == 2,"adjacent stairs descend")
	check(s.party[0].hp == hp and s.food == old_food-1,"condition and food persist")
	check(s.floor_state.layout.theme_id == "F2_MINES","second floor changes theme")
	s.party[0].hp = 1; s.damage(s.party[0],50,100,"IMPACT")
	check(s.phase == "DEFEAT" and not s.descend(),"solo death ends the run")
	var scene = load("res://expedition/ui/main.tscn").instantiate(); scene.session = s
	root.size = Vector2i(390,844); root.add_child(scene); await process_frame
	check(scene.find_child("ResultCard",true,false) != null,"death opens result card")
	check(scene.portrait_buttons.is_empty() and scene.item_buttons.is_empty(),"result omits combat controls")
	scene.queue_free(); await process_frame
	await stairs_discovery()
	await descent_rules()
	await camp_rules()
	await persistence()
	await hud_fit()
	await duo_floor()
	print("Solo floor: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func hero(s) -> Dictionary:
	return s.party[0]

## A cell next to `p` the hero can stand on.
func beside(s, p: Vector2i) -> Vector2i:
	return Fixture.beside(s,p)

## The stairs are the run's objective: hidden until seen, marked on the map
## when they are, and logged once.
func stairs_discovery() -> void:
	var s = Session.new_run(731)
	for enemy in s.enemies: enemy.hp = 0
	var stairs: Vector2i = s.floor_state.layout.stairs
	check(not s.floor_state.explored.has(stairs),"the stairs start unseen")
	check(s.floor_state.discoveries.all(func(row): return row.position != [stairs.x,stairs.y]),"and unmarked")
	var scene = load("res://expedition/ui/main.tscn").instantiate(); scene.session = s
	root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	check(not scene.navigation.start(s,stairs),"unseen stairs are not a navigation target")
	var stand: Vector2i = beside(s,stairs)
	check(stand.x >= 0,"the stairs have a cell to stand on")
	hero(s).pos = stand; s.floor_state.observe(s)
	check(s.floor_state.visible.has(stairs) and s.floor_state.explored.has(stairs),"walking up reveals them")
	check(s.floor_state.discoveries.any(func(row): return row.position == [stairs.x,stairs.y] and row.marker == "STAIRS"),"and marks the map")
	var marked: int = s.floor_state.discoveries.filter(func(row): return row.marker == "STAIRS").size()
	s.floor_state.observe(s)
	check(s.floor_state.discoveries.filter(func(row): return row.marker == "STAIRS").size() == marked,"a known stair is not rediscovered every turn")
	var turn: int = s.round_number
	scene.show_stairs(); await process_frame
	check(scene.details_popup.visible and s.round_number == turn,"opening the stair sheet costs nothing")
	check(scene.find_child("StairsPopup",true,false) != null and scene.details_popup.size.x <= 390,"the stair sheet fits the screen")
	scene.details_popup.hide(); await process_frame
	check(s.round_number == turn and s.depth == 1,"closing it costs nothing either")
	scene.queue_free(); await process_frame

## Who may take the stairs, and when.
func descent_rules() -> void:
	var s = Session.new_run(731)
	for enemy in s.enemies: enemy.hp = 0
	var stairs: Vector2i = s.floor_state.layout.stairs
	var stand: Vector2i = beside(s,stairs)
	hero(s).pos = stand+Vector2i(3,0); s.floor_state.observe(s)
	check(not s.descend() and s.depth == 1,"the stairs are not a remote control")
	hero(s).pos = stand; s.floor_state.observe(s)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 20; foe.max_hp = 20; foe.pos = stand+Vector2i(0,2); s.floor_state.observe(s)
	check(not s.party_enemies().is_empty(),"a foe is in sight")
	check(not s.descend() and s.depth == 1,"a foe in sight keeps the party on this floor")
	foe.hp = 0; s.floor_state.observe(s)
	var score: int = s.score
	check(s.descend() and s.depth == 2,"a quiet stair descends")
	check(s.score == score+20,"the descent is worth twenty points")
	check(s.floor_state.layout.stairs != stairs,"the new floor has its own stairs")
	check(s.round_number == 1 and s.on_floor(),"the new floor starts its own round count")
	var boss = Session.new_run(9)
	var guard: Dictionary = boss.enemies[0]
	guard.boss = true; guard.hp = 50; guard.max_hp = 50
	check(boss.stairs_sealed(),"a living boss seals the stairs")
	check(not boss.descend(),"and no one gets past it")
	guard.hp = 0
	check(not boss.stairs_sealed(),"a dead boss unseals them")

## Camping is paid in food, needs a quiet floor and heals once.
func camp_rules() -> void:
	var s = Session.new_run(41)
	for enemy in s.enemies: enemy.hp = 0
	Fixture.arena(s,10)
	var actor: Dictionary = hero(s)
	actor.hp = 20; actor.stress = 60
	check(s.can_camp().is_empty(),"a quiet floor with food allows a camp")
	var food: int = s.food
	check(s.camp() and s.food == food-1,"a solo camp costs one ration")
	check(s.phase == "CAMP" and actor.hp > 20 and actor.stress == 30,"it heals and calms")
	check(not s.camp(),"and it cannot be taken twice in a row")
	check(s.end_camp() and s.phase == "EXPLORE","ending the camp returns to the floor")
	check(actor.ap == s.action_budget(actor),"with a fresh action budget")
	s.food = 0
	check(s.can_camp() == "식량 1 필요","an empty larder names its price")
	check(not s.camp(),"and refuses the camp")
	s.food = 3
	var foe: Dictionary = s.enemies[0]
	foe.hp = 20; foe.max_hp = 20; foe.pos = actor.pos+Vector2i(2,0); s.floor_state.observe(s)
	# A seen foe turns the floor into a battle, and the phase answers first.
	check(s.can_camp() == "지금은 불가","mid-battle there is no camping at all")
	check(not s.camp() and s.food == 3,"and the ration is not spent")
	s.phase = "EXPLORE"
	check(s.can_camp() == "적이 보임","behind that, the foe in sight names itself")
	check(not s.camp() and s.food == 3,"and it refuses just the same")

## The run is one hero: what it carries follows it down the stairs.
func persistence() -> void:
	var s = Session.new_run(55)
	for enemy in s.enemies: enemy.hp = 0
	var actor: Dictionary = hero(s)
	s.grant_part("BOMB"); s.grant_item("healing"); s.grant_item("identify",1,true)
	actor.stress = 44
	var parts: Dictionary = s.parts_bag.duplicate(true)
	var bag: Dictionary = s.bag.duplicate(); var known: Dictionary = s.known.duplicate(); var looks: Dictionary = s.appearances.duplicate()
	var memory: Dictionary = actor.memory.to_dict()
	var kills: int = int(s.run_stats.kills)
	var stairs: Vector2i = s.floor_state.layout.stairs
	actor.pos = beside(s,stairs); s.floor_state.observe(s)
	check(s.descend(),"the hero takes the stairs")
	check(s.parts_bag == parts,"the parts bag follows")
	check(s.bag == bag and s.known == known and s.appearances == looks,"the bag follows")
	check(actor.stress == 44,"the stress follows")
	check(actor.memory.to_dict() == memory,"the memories follow")
	check(int(s.run_stats.kills) == kills,"the run tally keeps counting")
	check(s.party.size() == 1 and s.party[0] == actor,"and it is the same hero, not a copy")
	check(s.floor_state.layout.theme_id == "F2_MINES","the second floor is the mines")

## Portrait screens: the HUD is compact, everything is a touch target and
## nothing hangs off the edge.
func hud_fit() -> void:
	var s = Session.new_run(731)
	for enemy in s.enemies: enemy.hp = 0
	Fixture.arena(s,12)
	var scene = load("res://expedition/ui/main.tscn").instantiate(); scene.session = s
	root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for viewport in [Vector2i(320,640),Vector2i(390,844),Vector2i(430,932)]:
		root.size = viewport; scene.refresh()
		for frame in range(3): await process_frame
		check(scene.root_layout.get_child(0).size.y < 70,"the header stays compact at %s" % viewport)
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"the HUD fits %s" % viewport)
		check(scene.portrait_buttons.is_empty() and scene.item_buttons.is_empty(),"manual HUD has no party card or supply strip at %s" % viewport)
		check(scene.find_child("HeroStatus",true,false) != null,"hero status appears at %s" % viewport)
		check(scene.skill_buttons.is_empty(),"no manual skill row at %s" % viewport)
		check(scene.minimap != null and scene.minimap.is_visible_in_tree(),"the minimap is on screen at %s" % viewport)
		var footer: Node = scene.find_child("BottomActions",true,false)
		var texts: Array = footer.get_children().map(func(c): return str(c.text))
		check(footer.find_child("RetreatToggle",true,false) == null and footer.find_child("AutoToggle",true,false) == null,"the manual footer has no autobattle controls at %s" % viewport)
		check(texts == ["공격","대기","탐색","전술","가방"],"five direct actions stay in one row at %s" % viewport)
		check("원정" not in texts and "귀환" not in texts,"and nothing that returns home at %s" % viewport)
		for node in footer.get_children():
			check(node.size.y >= 44,"every solo control is a 44px target at %s" % viewport)
			check(scene.get_global_rect().encloses(node.get_global_rect()),"and stays on screen at %s" % viewport)
		scene.show_menu()
		await process_frame
		check(scene.details_popup.visible and scene.details_popup.size.x <= viewport.x,"the menu fits %s" % viewport)
		scene.details_popup.hide(); await process_frame
	check(scene.inventory_rows().all(func(r): return r.category != "임무"),"no mission item survives the relic's removal")
	scene.queue_free(); await process_frame

## The same floor with a companion on it: the card row grows, the objective
## does not change.
func duo_floor() -> void:
	var duo = Session.new(731,false,true,true,2); duo.depart()
	check(duo.party.size() == 2 and duo.companions,"a two-member run departs")
	check(duo.floor_state.layout.stairs.x >= 0,"onto a floor with stairs")
	check(duo.can_camp() == "" or duo.can_camp() == "적이 보임","camping asks the same two questions")
	duo.food = 1
	check(duo.can_camp() in ["식량 2 필요","적이 보임"],"a duo camp costs two rations")
	var scene = load("res://expedition/ui/main.tscn").instantiate(); scene.session = duo
	root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	check(scene.portrait_buttons.size() == 2,"two member cards")
	check(scene.find_child("MemberCard1",true,false) != null and scene.find_child("MemberCaption1",true,false) != null,"the second card is captioned too")
	check(scene.get_global_rect().encloses(scene.find_child("PartyRow",true,false).get_global_rect()),"two cards still fit 390px")
	scene.queue_free(); await process_frame
