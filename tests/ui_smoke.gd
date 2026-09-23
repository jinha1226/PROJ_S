extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(390,915)
	var scene = load("res://expedition/main.tscn").instantiate(); root.add_child(scene)
	await process_frame
	check(scene.find_child("StartScreen",true,false) != null,"start screen")
	check(scene.find_child("ArenaButton",true,false) != null,"arena entry")
	scene.new_run(); await process_frame
	check(scene.session.depth == 1 and scene.session.party.size() == 1,"solo floor")
	check(scene.find_child("FoodLabel",true,false) != null and scene.find_child("CampButton",true,false) != null,"floor controls")
	check(scene.find_child("TorchButton",true,false) == null and scene.find_child("Funds",true,false) == null,"retired resources absent")
	check(scene.minimap.size.x <= 100 and scene.board.size.x >= 340,"compact map and wide board")
	var event := InputEventMouseButton.new(); event.pressed = true; event.button_index = MOUSE_BUTTON_LEFT
	event.position = scene.minimap.size/2; scene.minimap._gui_input(event); await process_frame
	check(scene.map_popup.visible,"minimap expands")
	scene.map_popup.hide()
	var center: Vector2i = scene.session.party[0].pos
	for dy in range(-3,4):
		for dx in range(-3,4):
			var p: Vector2i = center+Vector2i(dx,dy)
			if not scene.session.inside(p): continue
			check(scene.board.cell_at(scene.board.cell_center(p)) == p,"board hit test %s" % p)
	check(scene.item_buttons.is_empty() and scene.find_child("PartyRow",true,false) == null,"manual floor uses a hero status instead of party controls")
	check(scene.find_child("HeroStatus",true,false) != null and scene.find_child("AutoToggle",true,false) == null,"manual hero HUD")
	check(scene.find_child("SpellBar",true,false) == null,"empty prepared spells do not occupy the HUD")
	var duel: Vector2i = preload("res://tests/floor_fixture.gd").arena(scene.session,8)
	var foe: Dictionary = scene.session.enemies[0]
	foe.hp = 40; foe.max_hp = 40; foe.pos = duel+Vector2i(1,0); foe.alert = true; foe.ready_at = 1000
	scene.session.phase = "BATTLE"; scene.session.floor_state.observe(scene.session); scene.refresh(); await process_frame
	var inspect := InputEventMouseButton.new(); inspect.pressed = true; inspect.button_index = MOUSE_BUTTON_RIGHT
	inspect.position = scene.board.cell_center(foe.pos); scene.board._gui_input(inspect); await process_frame
	check(scene.details_popup.visible and scene.find_child("EnemyInfo",true,false) != null,"right click inspects the enemy without attacking")
	scene.details_popup.hide(); await process_frame
	var hold := InputEventScreenTouch.new(); hold.index = 0; hold.pressed = true; hold.position = inspect.position
	scene.board._gui_input(hold); scene.board.touch_pressed_at -= 500
	hold.pressed = false; scene.board._gui_input(hold); await process_frame
	check(scene.details_popup.visible and scene.find_child("EnemyInfo",true,false) != null,"long touch inspects the enemy without attacking")
	scene.details_popup.hide()
	var before_time: int = scene.session.time
	scene.on_cell(foe.pos); await process_frame
	check(scene.session.time > before_time and not scene.details_popup.visible,"one enemy tap attacks and advances one hero action")
	before_time = scene.session.time
	var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_RIGHT
	scene._unhandled_key_input(key); await process_frame
	check(scene.session.time > before_time,"direction key attacks the adjacent enemy")
	var hero: Dictionary = scene.session.party[0]
	hero.spells = ["bolt"]; hero.prepared = ["bolt"]
	scene.refresh(); await process_frame
	var spell_bar: Node = scene.find_child("SpellBar",true,false)
	check(spell_bar != null and spell_bar.get_child_count() == 1,"only prepared spells appear in the action bar")
	var before_mp: int = hero.mp
	before_time = scene.session.time
	scene.find_child("Spell0",true,false).pressed.emit(); scene.on_cell(foe.pos); await process_frame
	check(hero.mp < before_mp and scene.session.time > before_time,"prepared spell casts with one target tap")
	var old_depth: int = scene.session.depth
	var stairs: Vector2i = scene.session.floor_state.layout.stairs
	for enemy in scene.session.enemies: enemy.hp = 0
	scene.session.party[0].pos = stairs; scene.session.floor_state.observe(scene.session); scene.refresh(); await process_frame
	scene.on_cell(stairs); await process_frame
	check(scene.find_child("StairsPopup",true,false) != null,"stairs prompt")
	scene.find_child("Descend",true,false).pressed.emit(); await process_frame
	check(scene.session.depth == old_depth+1,"stairs descend")
	scene.queue_free(); await process_frame
	print("UI smoke: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
