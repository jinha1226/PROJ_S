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
	for node in scene.item_buttons:
		check(node.size.x > 0 and node.size.y >= 44,"item touch target")
	check(scene.item_buttons.size() == 5,"five supplies")
	check(scene.find_child("AutoToggle",true,false) == null and scene.find_child("SpellBar",true,false) != null,"manual combat and prepared spells")
	var old_depth: int = scene.session.depth
	var stairs: Vector2i = scene.session.floor_state.layout.stairs
	for foe in scene.session.enemies: foe.hp = 0
	scene.session.party[0].pos = stairs; scene.session.floor_state.observe(scene.session); scene.refresh(); await process_frame
	scene.on_cell(stairs); await process_frame
	check(scene.find_child("StairsPopup",true,false) != null,"stairs prompt")
	scene.find_child("Descend",true,false).pressed.emit(); await process_frame
	check(scene.session.depth == old_depth+1,"stairs descend")
	scene.queue_free(); await process_frame
	print("UI smoke: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
