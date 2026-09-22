extends SceneTree
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	var s = Session.new(731,true,false,true)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	s.depart()
	for enemy in s.enemies: enemy.hp = 0
	s.party[0].pos = Vector2i(50,50)
	for y in range(35,66):
		for x in range(35,66): s.tile(Vector2i(x,y)).terrain = "stone"
	s.floor_state.features.clear(); s.floor_state.observe(s)
	var enemy: Dictionary = s.enemies[0]
	enemy.hp = 20; enemy.pos = Vector2i(60,50); s.floor_state.observe(s)
	check(s.combat_enemies().is_empty() and scene.navigation.explore(s),"enemy ten tiles away does not stop exploration")
	enemy.pos = Vector2i(59,50); s.floor_state.observe(s)
	check(scene.navigation.next_step(s).x < 0 and not scene.navigation.active,"enemy inside nine-tile sight stops exploration")
	s.tile(Vector2i(51,50)).terrain = "wall"; enemy.pos = Vector2i(52,50); s.floor_state.observe(s)
	check(s.combat_enemies().is_empty() and scene.navigation.explore(s),"wall-hidden enemy does not block exploration")
	scene.stop_navigation(); enemy.hp = 0; s.tile(Vector2i(51,50)).terrain = "stone"; s.floor_state.observe(s)
	for viewport in [Vector2i(320,640),Vector2i(360,780),Vector2i(390,844),Vector2i(430,932)]:
		root.size = viewport; scene.refresh()
		for frame in range(5): await process_frame
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"HUD fits %s" % viewport)
		var header: Node = scene.find_child("TopHUD",true,false)
		check(header.get_children().slice(1).map(func(c): return str(c.name)) == ["Location","FoodButton","TorchButton","ObjectiveChip","ExpeditionMenu"],"header order")
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
	var torches: int = s.torches; s.light = 20
	scene.find_child("TorchButton",true,false).pressed.emit()
	check(s.torches == torches-1 and s.light == 70,"HUD torch consumes one and raises light")
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
	duo.party[0].pos = Vector2i(50,50); duo.party[1].pos = Vector2i(50,51)
	check(duo.floor_state.follow(duo,duo.party[1]).kind == "WAIT","column formation holds assigned position")
	scene.queue_free(); await process_frame
	print("Mobile HUD: %d failures" % failures); quit(1 if failures else 0)
