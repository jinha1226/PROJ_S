extends SceneTree
## Start, floor, camp and stair controls fit portrait screens.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const Popups = preload("res://expedition/ui/screens/popups.gd")
var checks := 0
var failures := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	check(Art.ACTOR_SHEET.resource_path.ends_with("flat-v1/actors.png") and Art.actor_texture(0).get_width() > 300,"flat actor atlas is active")
	check(Art.actor_portrait({"id":1000,"npc":true}).atlas == Art.actor_texture(1).atlas and Art.actor_portrait({"id":1000,"npc":true}).region.position.x > Art.actor_texture(1).region.position.x,"NPC portrait is a larger crop of the map sprite")
	check(Art.MONSTER_SHEET.resource_path.ends_with("flat-v1/monsters.png") and Art.enemy_sprite("kobold").get_width() > 300,"flat monster atlas is active")
	check(Art.FirstFloor.tile("floor_a").get_width() > 250 and Art.FirstFloor.tile("front").get_width() > 250,"flat floor and wall tiles are active")
	check(Art.FirstFloor.tile("floor_a","F2_MINES").atlas != Art.FirstFloor.tile("floor_a","F1_RUINS").atlas,"mines have their own floor slabs")
	check(Art.FirstFloor.tile("front","F2_MINES").atlas != Art.FirstFloor.tile("front","F1_RUINS").atlas,"mines have their own wall blocks")
	check(Art.BOSS.resource_path.ends_with("flat-v1/fire-lizard-boss.png"),"the boss matches the flat actors")
	root.size = Vector2i(390,844)
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	root.add_child(scene); scene.set_process(false); await process_frame
	check(scene.find_child("StartScreen",true,false) != null,"start screen appears")
	check(scene.portrait_buttons.is_empty() and scene.skill_buttons.is_empty(),"start has no battle cards")
	check(scene.find_child("NewRun",true,false) != null and scene.find_child("ArenaButton",true,false) != null,"start has run and arena actions")
	root.size = Vector2i(320,640)
	for frame in range(3): await process_frame
	check(Rect2(Vector2.ZERO,root.size).encloses(scene.get_global_rect()),"start screen fits a 320px phone")
	root.size = Vector2i(320,568)
	for frame in range(3): await process_frame
	check(Rect2(Vector2.ZERO,scene.get_viewport_rect().size).encloses(scene.get_global_rect()),"start screen fits a short phone")
	root.size = Vector2i(390,844)
	seed(731)
	scene.find_child("NewRun",true,false).pressed.emit(); await process_frame
	var s = scene.session
	check(s.depth == 1 and s.food == 2 and s.party.size() == 1,"new run starts solo with food")
	check(scene.find_child("FoodLabel",true,false).text == "식량 2","HUD displays food")
	check(scene.find_child("Location",true,false).text == "1층","HUD displays depth")
	check(scene.find_child("TurnCount",true,false).text == "0턴","HUD displays the current turn under the floor")
	check(scene.find_child("TurnCount",true,false).position.y >= 24,"turn count sits below the floor label")
	check(scene.find_child("BottomActions",true,false) != null,"HUD has direct action bar")
	check(scene.find_child("TorchButton",true,false) == null and scene.find_child("Funds",true,false) == null,"removed resources stay out of HUD")
	check(scene.find_child("ObjectiveChip",true,false) == null,"no relic objective chip")
	for viewport in [Vector2i(320,640),Vector2i(360,780),Vector2i(390,844),Vector2i(430,932)]:
		root.size = viewport; scene.refresh()
		for frame in range(3): await process_frame
		check(Rect2(Vector2.ZERO,viewport).encloses(scene.get_global_rect()),"whole HUD fits the viewport at %s" % viewport)
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"layout fits %s" % viewport)
		check(scene.minimap != null and scene.minimap.is_visible_in_tree(),"minimap visible at %s" % viewport)
		for id in ["Location","FoodLabel","ExpeditionMenu","HeroStatus","Attack","Wait","Tactics","RecentLog"]:
			var control: Control = scene.find_child(id,true,false)
			check(control != null and scene.get_global_rect().encloses(control.get_global_rect()),"%s fits %s" % [id,viewport])
		var log_rect: Rect2 = scene.find_child("RecentLog",true,false).get_global_rect()
		var portrait_rect: Rect2 = scene.find_child("PortraitRow",true,false).get_global_rect()
		var actions_rect: Rect2 = scene.find_child("BottomActions",true,false).get_global_rect()
		check(log_rect.end.y <= portrait_rect.position.y and portrait_rect.end.y <= actions_rect.position.y,"log, portrait, actions stay stacked at %s" % viewport)
		check(scene.portrait_buttons.is_empty() and scene.item_buttons.is_empty(),"manual HUD has no party card or supply strip")
		check(scene.find_child("SpellBar",true,false) == null,"unprepared spells take no HUD space")
	var header: Node = scene.find_child("TopHUD",true,false)
	check(header.get_children().slice(1).map(func(c): return str(c.name)) == ["Location","FoodLabel","ExpeditionMenu"],"floor header order")
	scene.show_menu(); await process_frame
	check(scene.modal_content.get_children().map(func(c): return c.text) == ["야영","기록","가방","인물","닫기"],"menu keeps only direct actions")
	scene.details_popup.hide()
	Fixture.arena(s,12); s.floor_state.observe(s); scene.refresh(); await process_frame
	scene.show_menu(); await process_frame
	var camp_button: Button = scene.modal_content.get_child(0)
	check(not camp_button.disabled,"safe floor enables camp")
	camp_button.pressed.emit(); await process_frame
	check(s.phase == "CAMP" and scene.find_child("CampScreen",true,false) != null,"camp screen opens")
	check(scene.find_child("CampMember0",true,false) != null and scene.find_child("CampEnd",true,false) != null,"camp member and exit controls")
	root.size = Vector2i(320,568); scene.refresh()
	for frame in range(3): await process_frame
	check(Rect2(Vector2.ZERO,scene.get_viewport_rect().size).encloses(scene.root_layout.get_global_rect()),"camp fits a short phone")
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
	await recruited_ui()
	print("Mobile HUD: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Every control the run needs is a 44px target and none of them hangs off the
## edge of a 390px phone.
func touch_targets(scene) -> void:
	root.size = Vector2i(390,844); scene.refresh()
	for frame in range(3): await process_frame
	for id in ["ExpeditionMenu","HeroStatus","Attack","Wait","Tactics","RecentLog"]:
		var control: Control = scene.find_child(id,true,false)
		check(control != null and control.size.y >= 36,"%s is a touchable height" % id)
		check(control != null and scene.get_global_rect().encloses(control.get_global_rect()),"%s stays on screen" % id)
	var frame: StyleBox = scene.find_child("Attack",true,false).get_theme_stylebox("normal")
	check(frame is StyleBoxTexture and frame.texture is AtlasTexture and frame.texture.atlas.resource_path == "res://assets/ui/button-frames-flat-v1.png" and frame.texture.get_size() == Vector2(48,48) and frame.texture_margin_top == 10,"flat nine-slice frame fits the action button")
	check(scene.find_child("Attack",true,false).find_children("*","TextureRect",true,false).size() == 1,"action icon sits above its label")
	check(scene.item_buttons.is_empty(),"supplies live in the bag")
	var nav: Node = scene.find_child("BottomActions",true,false)
	check(nav.get_children().map(func(c): return str(c.text)) == ["공격","대기","탐색","전술","가방"],"five direct actions share one row")
	check(scene.find_child("PartyRow",true,false) == null,"manual play has no auto-battle party row")
	var status: Button = scene.find_child("HeroStatus",true,false)
	check(status != null and status.find_children("*","TextureRect",true,false).size() == 1,"hero portrait appears above actions")
	check(scene.find_child("RecentLog",true,false).get_global_rect().end.y <= status.get_global_rect().position.y,"four-line log sits above portrait")

## The default board scale keeps the flat character art readable on a phone.
func framing(scene, s) -> void:
	check(scene.board.visible_side() == 11,"the default camera shows eleven tiles")
	var camera: Vector2i = scene.board.camera_cell()
	check(camera.x <= s.party[0].pos.x and s.party[0].pos.x < camera.x+11,"the hero is inside the frame horizontally")
	check(camera.y <= s.party[0].pos.y and s.party[0].pos.y < camera.y+11,"the hero is inside the frame vertically")
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
	check(scene.find_child("RecentLog",true,false).text.ends_with(s.log_lines[-1]),"the HUD shows the latest log line")
	check(scene.find_child("RecentLog",true,false).get_theme_stylebox("normal") is StyleBoxEmpty,"recent log has no button border")

## Auto exploration stops on what the party can actually see (sight 5).
func sight_stops(scene, s) -> void:
	var c: Vector2i = Fixture.arena(s,15)
	s.floor_state.features.clear(); s.floor_state.observe(s)
	var enemy: Dictionary = s.enemies[0]
	enemy.hp = 20; enemy.max_hp = 20; enemy.pos = c+Vector2i(7,0); s.floor_state.observe(s)
	check(s.party_enemies().is_empty(),"a foe seven tiles away is out of sight")
	check(scene.navigation.explore(s),"and does not stop exploration")
	scene.refresh(); await process_frame
	var stop_button: Button = scene.auto_explore_button
	check(stop_button.text == "중지" and stop_button.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS,"exploration can stop on touch-down")
	stop_button.pressed.emit()
	check(not scene.navigation.active,"stop button cancels exploration")
	check(scene.navigation.explore(s),"exploration can start again")
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
	check(scene.find_child("TurnCount",true,false).text == "%d턴" % s.turn_serial,"turn counter follows player actions")
	check(hero.hp == before_hp and hero.stress == 30,"waiting is not a rest: no health and no calm")
	var saved: int = s.food; s.food = 0; scene.refresh(); await process_frame
	before_round = s.round_number
	scene.run_action(func(): return s.act("WAIT",hero.pos)); await process_frame
	check(s.round_number >= before_round+1 and s.food == 0,"waiting stays available with an empty larder")
	scene.show_menu(); await process_frame
	check((scene.modal_content.get_child(0) as Button).disabled,"but camping does not")
	scene.details_popup.hide(); await process_frame
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

func recruited_ui() -> void:
	root.size = Vector2i(390,844)
	var s = Session.new_run(921)
	var center: Vector2i = Fixture.arena(s,8)
	s.npcs = s.npcs.slice(0,2)
	for foe in s.enemies: foe.hp = 0
	var npc: Dictionary = s.npcs[0]
	npc.partner = -1; npc.bond = ""; npc.state = "MET"; npc.pos = center+Vector2i.LEFT
	s.floor_state.observe(s)
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = s; root.add_child(scene); scene.set_process(false)
	for frame in range(3): await process_frame
	Popups.show_npc(scene,npc); await process_frame
	var popup_icon: TextureRect = scene.find_child("NpcPopup",true,false).find_children("*","TextureRect",true,false)[0]
	var sprite_texture: Texture2D = popup_icon.texture
	check(sprite_texture == Art.actor_portrait(npc),"NPC dialogue and map use one sprite")
	scene.details_popup.hide()
	check(s.recruit(npc) and s.companions,"recruitment enables companion orders")
	scene.refresh(); await process_frame
	var card: Button = scene.find_child("MemberStatus1",true,false)
	var card_icon: TextureRect = card.find_children("*","TextureRect",true,false)[0]
	check(card_icon.texture == sprite_texture and scene.board.actor_sprite(npc) == Art.actor_index(npc),"recruited portrait keeps the NPC's map sprite")
	check(s.submit("MOVE",center+Vector2i.RIGHT),"hero can move after recruiting")
	check(npc.pos != center+Vector2i.LEFT and s.distance(npc.pos,s.party[0].pos) <= 2,"recruited NPC follows on the hero's next turn")
	var second: Dictionary = s.npcs[0]
	second.partner = -1; second.bond = ""; second.state = "MET"; second.pos = center+Vector2i(-1,1)
	check(s.recruit(second) and s.party.size() == 3,"party can fill all three slots")
	check(Popups.inventory_rows(scene).all(func(row): return row.icon.atlas == Art.ITEM_SHEET),"all item categories share one flat atlas")
	for viewport in [Vector2i(390,844),Vector2i(320,640),Vector2i(320,568)]:
		root.size = viewport; scene.refresh(); await process_frame
		check(Rect2(Vector2.ZERO,scene.get_viewport_rect().size).encloses(scene.get_global_rect()),"game scene fits logical screen at %s" % viewport)
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"recruited floor HUD fits %s" % viewport)
		check(scene.get_global_rect().encloses(scene.board.get_global_rect()),"floor board fits %s" % viewport)
		for id in ["TopHUD","RecentLog","PortraitRow","BottomActions"]:
			var control: Control = scene.find_child(id,true,false)
			check(scene.get_global_rect().encloses(control.get_global_rect()),"%s fits %s" % [id,viewport])
		for index in range(3):
			var member: Button = scene.find_child("HeroStatus" if index == 0 else "MemberStatus%d" % index,true,false)
			check(scene.get_global_rect().encloses(member.get_global_rect()),"member card stays on %s" % viewport)
			for bar in member.find_children("*","ProgressBar",true,false):
				check(member.get_global_rect().encloses(bar.get_global_rect()),"HP/MP bar stays inside its card at %s" % viewport)
		scene.inventory_filter = "파츠"; scene.show_supplies()
		for frame in range(3): await process_frame
		var popup_rect := Rect2(Vector2(scene.details_popup.position),Vector2(scene.details_popup.size))
		check(scene.get_global_rect().encloses(popup_rect),"parts bag fits %s" % viewport)
		check(scene.inventory_slots.all(func(slot): return slot.row.is_empty() or slot.row.icon.atlas == Art.ITEM_SHEET),"all bag categories use the flat item sheet")
		scene.details_popup.hide()
	scene.queue_free(); await process_frame

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
