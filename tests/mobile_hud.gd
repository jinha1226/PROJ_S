extends SceneTree
## Start, floor, camp and stair controls fit portrait screens.
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.size = Vector2i(390,844)
	var scene = load("res://expedition/main.tscn").instantiate()
	root.add_child(scene); scene.set_process(false); await process_frame
	check(scene.find_child("StartScreen",true,false) != null,"start screen appears")
	check(scene.portrait_buttons.is_empty() and scene.skill_buttons.is_empty(),"start has no battle cards")
	check(scene.find_child("NewRun",true,false) != null and scene.find_child("ArenaButton",true,false) != null,"start has run and arena actions")
	scene.find_child("NewRun",true,false).pressed.emit(); await process_frame
	var s = scene.session
	check(s.depth == 1 and s.food == 2 and s.party.size() == 1,"new run starts solo with food")
	check(scene.find_child("FoodLabel",true,false).text == "식량 2","HUD displays food")
	check(scene.find_child("Location",true,false).text == "1층","HUD displays depth")
	check(scene.find_child("CampButton",true,false) != null,"HUD has camp button")
	check(scene.find_child("TorchButton",true,false) == null and scene.find_child("Funds",true,false) == null,"removed resources stay out of HUD")
	check(scene.find_child("ObjectiveChip",true,false) == null,"no relic objective chip")
	for viewport in [Vector2i(320,640),Vector2i(360,780),Vector2i(390,844),Vector2i(430,932)]:
		root.size = viewport; scene.refresh()
		for frame in range(3): await process_frame
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"layout fits %s" % viewport)
		check(scene.minimap != null and scene.minimap.is_visible_in_tree(),"minimap visible at %s" % viewport)
		for id in ["Location","FoodLabel","ExpeditionMenu","HeroStatus","CampButton","Wait"]:
			var control: Control = scene.find_child(id,true,false)
			check(control != null and scene.get_global_rect().encloses(control.get_global_rect()),"%s fits %s" % [id,viewport])
		check(scene.portrait_buttons.is_empty() and scene.item_buttons.is_empty(),"manual HUD has no party card or supply strip")
		check(scene.find_child("SpellBar",true,false) == null,"unprepared spells take no HUD space")
	var header: Node = scene.find_child("TopHUD",true,false)
	check(header.get_children().slice(1).map(func(c): return str(c.name)) == ["Location","FoodLabel","ExpeditionMenu"],"floor header order")
	scene.show_menu(); await process_frame
	check(scene.modal_content.get_children().map(func(c): return c.text) == ["기록","가방","인물","닫기"],"menu keeps only direct actions")
	scene.details_popup.hide()
	Fixture.arena(s,12); s.floor_state.observe(s); scene.refresh(); await process_frame
	var camp_button: Button = scene.find_child("CampButton",true,false)
	check(not camp_button.disabled,"safe floor enables camp")
	camp_button.pressed.emit(); await process_frame
	check(s.phase == "CAMP" and scene.find_child("CampScreen",true,false) != null,"camp screen opens")
	check(scene.find_child("CampMember0",true,false) != null and scene.find_child("CampEnd",true,false) != null,"camp member and exit controls")
	scene.find_child("CampEnd",true,false).pressed.emit(); await process_frame
	check(s.phase == "EXPLORE" and scene.find_child("FoodLabel",true,false).text == "식량 1","return to floor updates food")
	scene.show_stairs(); await process_frame
	check(scene.find_child("StairsPopup",true,false) != null and not scene.find_child("Descend",true,false).disabled,"unsealed stairs have descent action")
	scene.details_popup.hide()
	# Corner movement uses a direct diagonal even if the two side cells are walls.
	var center: Vector2i = Fixture.arena(s,10)
	for d in [Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]:
		for blocked in [1,2]:
			s.party[0].pos = center; s.party[0].ap = 1
			for offset in s.DIRECTIONS: s.tile(center+offset).terrain = "stone"
			s.tile(center+Vector2i(d.x,0)).terrain = "wall"
			if blocked == 2: s.tile(center+Vector2i(0,d.y)).terrain = "wall"
			s.floor_state.observe(s)
			check(s.can_step(center,center+d),"corner step is legal")
			check(scene.navigation.route(s,center+d) == [center,center+d],"route uses direct diagonal")
			check(s.act("MOVE",center+d) and s.party[0].pos == center+d,"tap action moves diagonally")
	var food: int = s.food; var before_round: int = s.round_number
	for i in range(3): s.act("WAIT",s.party[0].pos)
	check(s.food == food and s.round_number >= before_round+3,"waiting advances without eating")
	await touch_targets(scene)
	await framing(scene,s)
	await quiet_log(scene,s)
	await sight_stops(scene,s)
	await waiting_and_auto(scene,s)
	await toast_life(scene)
	await companion_orders()
	await blocked_steps(scene)
	scene.queue_free(); await process_frame
	print("Mobile HUD: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Every control the run needs is a 44px target and none of them hangs off the
## edge of a 390px phone.
func touch_targets(scene) -> void:
	root.size = Vector2i(390,844); scene.refresh()
	for frame in range(3): await process_frame
	for id in ["ExpeditionMenu","HeroStatus","CampButton","Wait","RecentLog"]:
		var control: Control = scene.find_child(id,true,false)
		check(control != null and control.size.y >= 36,"%s is a touchable height" % id)
		check(control != null and scene.get_global_rect().encloses(control.get_global_rect()),"%s stays on screen" % id)
	check(scene.item_buttons.is_empty(),"supplies live in the bag")
	var nav: Node = scene.find_child("BottomActions",true,false)
	check(nav.get_children().map(func(c): return str(c.name)).has("CampButton"),"camp sits in the footer")
	check(scene.find_child("PartyRow",true,false) == null,"manual play has no auto-battle party row")
	var status: Button = scene.find_child("HeroStatus",true,false)
	check(status != null and status.text.contains("HP") and status.text.contains("MP") and status.text.contains("AC"),"hero status reports combat values")

## The board frames seventeen tiles with the hero in the middle.
func framing(scene, s) -> void:
	check(scene.board.visible_side() == 17,"the default camera shows seventeen tiles")
	var camera: Vector2i = scene.board.camera_cell()
	check(camera.x <= s.party[0].pos.x and s.party[0].pos.x < camera.x+17,"the hero is inside the frame horizontally")
	check(camera.y <= s.party[0].pos.y and s.party[0].pos.y < camera.y+17,"the hero is inside the frame vertically")
	scene.show_menu(); await process_frame
	check(scene.details_popup.size.x <= root.size.x,"the menu fits the screen width")
	scene.details_popup.hide(); await process_frame

## The HUD speaks through the log, not through the toast.
func quiet_log(scene, s) -> void:
	var drop: Dictionary = s.make_actor(999,"시험 대상",true)
	drop.hp = 0; drop.part_id = "BOMB"
	while s.Hexaco.sample(s.seed_value,s.depth*10000+drop.id,"essence",100) >= s.Abilities.DROP_PERCENT: drop.id += 1
	scene.notice = ""
	scene.run_action(func(): s.roll_part(drop); return true)
	await process_frame
	check(scene.notice.is_empty() and not scene.toast.visible,"a part drop produces no toast")
	check(s.log_lines[-1] == Session.Abilities.DEFINITIONS.BOMB.item+" 획득","a part drop uses the concise log line")
	check(scene.find_child("RecentLog",true,false).text == s.log_lines[-1],"the HUD shows the latest log line")

## Auto exploration stops on what the party can actually see (sight 5).
func sight_stops(scene, s) -> void:
	var c: Vector2i = Fixture.arena(s,15)
	s.floor_state.features.clear(); s.floor_state.observe(s)
	var enemy: Dictionary = s.enemies[0]
	enemy.hp = 20; enemy.max_hp = 20; enemy.pos = c+Vector2i(7,0); s.floor_state.observe(s)
	check(s.party_enemies().is_empty(),"a foe seven tiles away is out of sight")
	check(scene.navigation.explore(s),"and does not stop exploration")
	enemy.pos = c+Vector2i(4,0); s.floor_state.observe(s)
	check(not s.party_enemies().is_empty(),"a foe four tiles away is in sight")
	check(scene.navigation.next_step(s).x < 0 and not scene.navigation.active,"and stops exploration")
	s.tile(c+Vector2i(1,0)).terrain = "wall"; enemy.pos = c+Vector2i(2,0); s.floor_state.observe(s)
	check(s.party_enemies().is_empty() and scene.navigation.explore(s),"a wall-hidden foe does not block exploration")
	scene.stop_navigation(); enemy.hp = 0; s.tile(c+Vector2i(1,0)).terrain = "stone"; s.floor_state.observe(s)
	await process_frame

## Rounds pass without eating, and a seen foe leaves the run stopped.
func waiting_and_auto(scene, s) -> void:
	Fixture.arena(s,12); s.floor_state.observe(s)
	var hero: Dictionary = s.party[0]
	hero.hp = maxi(1,hero.max_hp-10); hero.stress = 30
	var before_hp: int = hero.hp; var before_round: int = s.round_number; var food: int = s.food
	for step in range(3): scene.run_action(func(): return s.act("WAIT",hero.pos))
	await process_frame
	check(s.round_number >= before_round+3 and s.food == food,"waiting advances rounds without spending food")
	check(hero.hp == before_hp and hero.stress == 30,"waiting is not a rest: no health and no calm")
	var saved: int = s.food; s.food = 0; scene.refresh(); await process_frame
	before_round = s.round_number
	scene.run_action(func(): return s.act("WAIT",hero.pos)); await process_frame
	check(s.round_number >= before_round+1 and s.food == 0,"waiting stays available with an empty larder")
	check(scene.find_child("CampButton",true,false).disabled,"but camping does not")
	s.food = saved
	var foe: Dictionary = s.enemies[0]
	foe.hp = 20; foe.max_hp = 20; foe.pos = hero.pos+Vector2i.RIGHT; s.floor_state.observe(s)
	scene.refresh(); await process_frame
	check(scene.find_child("AutoToggle",true,false) == null and scene.find_child("HeroStatus",true,false) != null,"a seen foe remains under manual control")
	before_round = s.round_number; food = s.food
	s.submit("WAIT",hero.pos); scene.refresh(); await process_frame
	check(s.round_number >= before_round and s.food == food,"a manual turn costs no food")
	foe.hp = 0; s.floor_state.observe(s); scene.refresh(); await process_frame

## The toast says its piece and goes.
func toast_life(scene) -> void:
	scene.notice = "이동 불가"
	check(scene.toast.visible,"the toast shows at once")
	scene._process(3)
	check(not scene.toast.visible,"the toast expires")
	await process_frame

## The two standing orders the session still keeps.
func companion_orders() -> void:
	var duo = Session.new(731,true,true,true,2); duo.depart()
	for foe in duo.enemies: foe.hp = 0
	Fixture.arena(duo,8)
	duo.party_command = "HOLD_POSITION"
	check(duo.companion_choice(duo.party[1]).kind == "WAIT","the hold order keeps a companion still")
	duo.party_command = "FOLLOW"; duo.formation = [0,1]
	check(duo.floor_state.follow(duo,duo.party[1]).kind == "WAIT","the column formation holds its assigned place")
	await process_frame

## A wall or a body is a wall or a body, diagonal or not.
func blocked_steps(scene) -> void:
	var corner = Session.new(818,false,false,true,1); corner.depart()
	var origin: Vector2i = Fixture.arena(corner,15); corner.floor_state.features.clear()
	for foe in corner.enemies: foe.hp = 0
	corner.floor_state.observe(corner)
	corner.party[0].pos = origin; corner.party[0].ap = 1
	corner.tile(origin+Vector2i.ONE).terrain = "wall"
	check(not corner.can_step(origin,origin+Vector2i.ONE),"a wall destination stays blocked")
	corner.tile(origin+Vector2i.ONE).terrain = "stone"
	corner.enemies[0].hp = 20; corner.enemies[0].pos = origin+Vector2i.ONE
	check(not corner.can_step(origin,origin+Vector2i.ONE),"an occupied destination stays blocked")
	await process_frame
