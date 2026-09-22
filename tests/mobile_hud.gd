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
	s.depart()
	var c := Fixture.arena(s,15)
	s.floor_state.features.clear(); s.floor_state.observe(s)
	var enemy: Dictionary = s.enemies[0]
	enemy.hp = 20; enemy.pos = c+Vector2i(10,0); s.floor_state.observe(s)
	check(s.combat_enemies().is_empty() and scene.navigation.explore(s),"enemy ten tiles away does not stop exploration")
	enemy.pos = c+Vector2i(9,0); s.floor_state.observe(s)
	check(scene.navigation.next_step(s).x < 0 and not scene.navigation.active,"enemy inside nine-tile sight stops exploration")
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
		check(header.get_children().slice(1).map(func(c): return str(c.name)) == ["Location","FoodButton","TorchButton","ObjectiveChip","Funds","ExpeditionMenu"],"header order")
		check(scene.skill_buttons[0].get_global_rect().end.y <= scene.portrait_buttons[0].get_global_rect().position.y,"skills above member card")
		check(scene.portrait_buttons[0].find_children("*","TextureRect",true,false).is_empty(),"member card has no portrait image")
		var nav: Node = scene.root_layout.get_child(-1)
		check(nav.get_children().map(func(c): return c.text) == ["공격","휴식","자동탐험","전술","가방"],"safe footer order")
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
	scene.wait_button.pressed.emit()
	check(s.food == food-1 and s.party[0].stress == 20,"safe rest consumes food and reduces stress")
	enemy.hp = 20; enemy.pos = s.party[0].pos+Vector2i.RIGHT; s.floor_state.observe(s); scene.refresh()
	check(scene.wait_button.text == "대기" and not s.rest_field(),"rest unavailable with visible enemy")
	scene.notice = "이동 불가"; check(scene.toast.visible,"toast shown immediately")
	scene._process(3); check(not scene.toast.visible,"toast expires")
	scene.show_party_tactics()
	check(scene.modal_content.get_child(0).disabled,"solo disables companion commands")
	scene.details_popup.hide()
	var duo = Session.new(731,true,true,true); duo.depart()
	for foe in duo.enemies: foe.hp = 0
	duo.party_command = "HOLD_POSITION"
	check(duo.companion_choice(duo.party[1]).kind == "WAIT","hold command prevents companion movement")
	duo.party_command = "FOLLOW"; duo.formation = "COLUMN"
	Fixture.arena(duo,8)
	check(duo.floor_state.follow(duo,duo.party[1]).kind == "WAIT","column formation holds assigned position")
	scene.queue_free(); await process_frame
	print("Mobile HUD: %d failures" % failures); quit(1 if failures else 0)
