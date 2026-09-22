extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	var s = Session.new(731,true,false,true)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	check(scene.portrait_buttons.is_empty() and scene.skill_buttons.is_empty() and scene.item_buttons.is_empty(),"town omits all combat cards and item slots")
	check(scene.auto_explore_button == null and not scene.board.visible,"town omits combat footer and dungeon")
	check(scene.find_child("Funds",true,false).text == "자금\n%d" % s.bank,"town HUD shows available funds")
	for viewport in [Vector2i(320,640),Vector2i(390,844),Vector2i(430,932)]:
		root.size = viewport; scene.refresh()
		for frame in range(4): await process_frame
		var hub = scene.find_child("SettlementHub",true,false)
		check(hub != null and scene.get_global_rect().encloses(hub.get_global_rect()),"settlement fits viewport")
		for control in hub.find_children("*","Button",true,false):
			check(hub.get_global_rect().encloses(control.get_global_rect()),"facility touch region fits viewport")
			check(control.size.x >= 44 and control.size.y >= 44,"facility touch region is at least 44px")
		scene.find_child("TownShop",true,false).pressed.emit(); await process_frame
		check(scene.details_popup.visible and scene.modal_content.get_child(0).text.begins_with("상점"),"shop opens from building")
		scene.details_popup.hide()
	scene.find_child("TownLodging",true,false).pressed.emit()
	check(scene.modal_content.get_child(0).text == "숙소","lodging opens roster")
	scene.modal_content.get_child(1).pressed.emit()
	check(scene.character_tab == "상태","lodging opens selected member status")
	scene.find_child("TownTraining",true,false).pressed.emit()
	scene.modal_content.get_child(1).pressed.emit()
	check(scene.character_tab == "숙련","training opens mastery")
	scene.details_popup.hide()
	check(scene.find_child("TownEdit",true,false).disabled,"unimplemented tile edit stays disabled")
	check(s.log_lines.is_empty(),"new session has no tutorial log")
	s.depart()
	scene.refresh(); await process_frame
	check(scene.board.visible_side() == 13 and scene.board.camera_cell() == s.party[0].pos-Vector2i(6,6),"default camera centers hero in thirteen tiles even near map edge")
	check(scene.find_child("ObjectiveChip",true,false) == null,"objective button removed from HUD")
	var drop: Dictionary = s.make_actor(999,"시험 대상",true)
	drop.hp = 0; drop.part_id = "BOMB"
	while s.Hexaco.sample(s.seed_value,s.expedition_number*10000+s.room*100+drop.id,"essence",100) >= s.Floor.drop_percent(s.light): drop.id += 1
	scene.run_action(func(): s.roll_part(drop); return true)
	check(scene.notice.is_empty() and not scene.toast.visible,"item pickup produces no toast")
	check(s.log_lines[-1] == Session.Abilities.DEFINITIONS.BOMB.item+" 획득","item pickup uses concise log")
	var c := Fixture.arena(s,15)
	s.floor_state.features.clear(); s.floor_state.observe(s)
	var enemy: Dictionary = s.enemies[0]
	enemy.hp = 20; enemy.pos = c+Vector2i(7,0); s.floor_state.observe(s)
	check(s.combat_enemies().is_empty() and scene.navigation.explore(s),"enemy seven tiles away does not stop exploration")
	enemy.pos = c+Vector2i(6,0); s.floor_state.observe(s)
	check(scene.navigation.next_step(s).x < 0 and not scene.navigation.active,"enemy inside six-tile sight stops exploration")
	s.tile(c+Vector2i(1,0)).terrain = "wall"; enemy.pos = c+Vector2i(2,0); s.floor_state.observe(s)
	check(s.combat_enemies().is_empty() and scene.navigation.explore(s),"wall-hidden enemy does not block exploration")
	scene.stop_navigation(); enemy.hp = 0; s.tile(c+Vector2i(1,0)).terrain = "stone"; s.floor_state.observe(s)
	for viewport in [Vector2i(320,640),Vector2i(360,780),Vector2i(390,844),Vector2i(430,932)]:
		root.size = viewport; scene.refresh()
		for frame in range(5): await process_frame
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"HUD fits %s" % viewport)
		check(scene.minimap.is_visible_in_tree(),"minimap returns after leaving town")
		for id in ["FoodGauge","TorchGauge"]:
			var bar: ProgressBar = scene.find_child(id,true,false)
			check(bar != null and bar.get_parent().get_global_rect().encloses(bar.get_global_rect()),"resource gauge stays inside HUD button")
			check(bar.mouse_filter == Control.MOUSE_FILTER_IGNORE,"gauge does not block item touches")
		var header: Node = scene.find_child("TopHUD",true,false)
		check(header.get_children().slice(1).map(func(c): return str(c.name)) == ["Location","FoodButton","TorchButton","Funds","ExpeditionMenu"],"header order")
		# The floor battle is automatic: no per-member skill buttons, one auto
		# toggle and the five party commands instead.
		check(scene.skill_buttons.is_empty(),"floor battle has no skill buttons")
		var bar: Node = scene.find_child("CommandBar",true,false)
		var toggle: Button = scene.find_child("AutoToggle",true,false)
		check(bar != null and bar.get_child_count() == 5 and toggle != null,"auto toggle and five party commands")
		for control in bar.get_children()+[toggle]:
			check(control.size.y >= 44 and scene.get_global_rect().encloses(control.get_global_rect()),"auto control is touchable and on screen")
		check(scene.portrait_buttons[0].find_children("*","TextureRect",true,false).is_empty(),"member card has no portrait image")
		var nav: Node = scene.root_layout.get_child(-1)
		check(nav.get_children().map(func(c): return c.text) == ["▶ 재개","1×","진형 교환","자동탐험","가방","⚙"],"floor footer order")
		scene.show_objective(); await process_frame
		check(scene.modal_content.get_children().map(func(c): return c.text) == ["원정 목표","입구까지 이동","원정포기"],"menu contains exactly three actions")
		check(scene.details_popup.size.x <= viewport.x,"menu width fits")
		scene.details_popup.hide()
	var food: int = s.food; s.party[0].hp -= 10; s.hunger = 30
	scene.find_child("FoodButton",true,false).pressed.emit()
	check(s.food == food-1 and s.hunger == 10,"HUD food consumes one and reduces hunger")
	check(scene.find_child("FoodGauge",true,false).value == 90,"food gauge shows remaining satiety after eating")
	var torches: int = s.torches; s.light = 20
	scene.find_child("TorchButton",true,false).pressed.emit()
	check(s.torches == torches-1 and s.light == 70,"HUD torch consumes one and raises light")
	check(scene.find_child("TorchGauge",true,false).value == 70,"torch gauge shows current light after use")
	s.party[0].stress = 30; food = s.food
	var before_wait: int = s.round_number
	var before_hp: int = s.party[0].hp
	# Floor mode has no wait button and the board only commands while fighting,
	# so the waiting itself is checked on the session.
	for step in range(3): scene.run_action(func(): return s.act("WAIT",s.party[0].pos))
	check(s.round_number == before_wait+3 and s.food == food,"waiting without visible enemies advances turns without spending food")
	check(s.party[0].hp == before_hp and s.party[0].stress == 30,"waiting does not perform recovery")
	var saved_food: int = s.food; s.food = 0; scene.refresh()
	scene.run_action(func(): return s.act("WAIT",s.party[0].pos))
	check(s.round_number == before_wait+4 and s.food == 0,"waiting remains available without food")
	s.food = saved_food
	enemy.hp = 20; enemy.pos = s.party[0].pos+Vector2i.RIGHT; s.floor_state.observe(s); scene.refresh()
	check(scene.find_child("AutoToggle",true,false).text == "▶ 재개","a visible enemy leaves the run stopped")
	before_wait = s.round_number; food = s.food
	Fixture.fight_round(s); scene.refresh()
	check(s.round_number == before_wait+1 and s.food == food,"an auto round also advances without food cost")
	scene.notice = "이동 불가"; check(scene.toast.visible,"toast shown immediately")
	scene._process(3); check(not scene.toast.visible,"toast expires")
	scene.show_party_tactics()
	check(scene.modal_content.get_child(0).disabled,"solo disables companion commands")
	scene.details_popup.hide()
	var duo = Session.new(731,true,true,true); duo.depart()
	for foe in duo.enemies: foe.hp = 0
	duo.party_command = "HOLD_POSITION"
	check(duo.companion_choice(duo.party[1]).kind == "WAIT","hold command prevents companion movement")
	duo.party_command = "FOLLOW"; duo.formation = [0,1,2]
	Fixture.arena(duo,8)
	check(duo.floor_state.follow(duo,duo.party[1]).kind == "WAIT","column formation holds assigned position")
	var corner = Session.new(818,true,false,true); corner.depart()
	var origin := Fixture.arena(corner,15); corner.floor_state.features.clear()
	for foe in corner.enemies: foe.hp = 0
	scene.session = corner
	for direction in [Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]:
		for blocked in [1,2]:
			corner.party[0].pos = origin; corner.party[0].ap = 1
			for offset in corner.DIRECTIONS: corner.tile(origin+offset).terrain = "stone"
			corner.tile(origin+Vector2i(direction.x,0)).terrain = "wall"
			if blocked == 2: corner.tile(origin+Vector2i(0,direction.y)).terrain = "wall"
			var destination: Vector2i = origin+direction
			corner.floor_state.observe(corner); scene.refresh()
			check(corner.can_step(origin,destination) and corner.floor_state.visible.has(destination),"diagonal corner destination is walkable and tappable")
			check(scene.navigation.route(corner,destination) == [origin,destination],"automatic route uses the same direct diagonal")
			check(Session.Objective.reachability(corner,origin)[destination] == 1,"objective reachability uses corner-cutting movement")
			var before: int = corner.round_number
			scene.on_cell(destination)
			check(corner.party[0].pos == destination and corner.round_number == before+1,"tap moves diagonally past one or two corner walls in one turn")
	corner.party[0].pos = origin; corner.party[0].ap = 1
	corner.tile(origin+Vector2i.ONE).terrain = "wall"
	check(not corner.can_step(origin,origin+Vector2i.ONE),"wall destination remains blocked")
	corner.tile(origin+Vector2i.ONE).terrain = "stone"
	corner.enemies[0].hp = 20; corner.enemies[0].pos = origin+Vector2i.ONE
	check(not corner.can_step(origin,origin+Vector2i.ONE),"occupied destination remains blocked")
	scene.queue_free(); await process_frame
	print("Mobile HUD: %d failures" % failures); quit(1 if failures else 0)
