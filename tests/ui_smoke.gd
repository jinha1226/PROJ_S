extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(390,915)
	var scene = load("res://expedition/ui/main.tscn").instantiate(); root.add_child(scene)
	await process_frame
	check(scene.find_child("StartScreen",true,false) != null,"start screen")
	check(scene.find_child("ArenaButton",true,false) != null,"arena entry")
	scene.new_run(); await process_frame
	check(scene.session.depth == 1 and scene.session.party.size() == 1,"solo floor")
	check(scene.find_child("FoodLabel",true,false) != null and scene.find_child("BottomActions",true,false) != null,"floor controls")
	check(scene.find_child("TorchButton",true,false) == null and scene.find_child("Funds",true,false) == null,"retired resources absent")
	check(scene.minimap.size.x <= 100 and scene.board.size.x == scene.get_viewport_rect().size.x,"compact map and full-width board")
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
	var item_step: Vector2i = scene.session.movement_cells(0)[0]
	scene.session.floor_state.features[item_step] = {"kind":"item","item_id":"healing"}
	scene.refresh(); await process_frame
	scene.on_cell(item_step); await process_frame
	check(scene.session.party[0].pos == item_step and int(scene.session.bag.get("healing",0)) == 1,"tapping a floor item walks onto it and picks it up")
	var duel: Vector2i = preload("res://tests/floor_fixture.gd").arena(scene.session,8)
	var foe: Dictionary = scene.session.enemies[0]
	foe.hp = 100; foe.max_hp = 100; foe.pos = duel+Vector2i(1,0); foe.alert = true; foe.ready_at = 1000
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
	check(scene.board.effects.any(func(effect): return effect.get("kind","") == "ATTACK_SWING"),"melee attack shows a swing even if it misses")
	before_time = scene.session.time
	var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_RIGHT
	scene._unhandled_key_input(key); await process_frame
	check(scene.session.time > before_time,"direction key attacks the adjacent enemy")
	before_time = scene.session.time
	key.keycode = KEY_TAB
	scene._unhandled_key_input(key); await process_frame
	check(scene.session.time > before_time and scene.mode.is_empty(),"Tab takes one attack action")
	before_time = scene.session.time
	scene.find_child("Attack",true,false).pressed.emit(); await process_frame
	check(scene.session.time > before_time and scene.mode.is_empty(),"attack button strikes an in-range enemy immediately")
	foe.pos = duel+Vector2i(3,0); scene.session.floor_state.observe(scene.session); scene.refresh(); await process_frame
	before_time = scene.session.time
	var before_pos: Vector2i = scene.session.party[0].pos
	scene.find_child("Attack",true,false).pressed.emit(); await process_frame
	check(scene.session.time > before_time and scene.session.party[0].pos != before_pos and scene.mode.is_empty() and not scene.board.show_attack_range,"attack button approaches a visible enemy one step")
	foe.pos = duel+Vector2i(1,0); scene.session.floor_state.observe(scene.session)
	scene.on_cell(foe.pos); await process_frame
	check(scene.session.time > before_time and scene.mode.is_empty(),"armed attack fires and clears selection")
	var hero: Dictionary = scene.session.party[0]
	hero.spells = ["fire_1"]; hero.prepared = ["fire_1"]
	scene.refresh(); await process_frame
	scene.find_child("Tactics",true,false).pressed.emit(); await process_frame
	check(scene.find_child("Spell_fire_1",true,false) != null,"prepared spell appears in tactics")
	var before_mp: int = hero.mp
	before_time = scene.session.time
	scene.find_child("Spell_fire_1",true,false).pressed.emit(); scene.on_cell(foe.pos); await process_frame
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
