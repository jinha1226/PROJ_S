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
		for id in ["Location","FoodLabel","ExpeditionMenu","CampButton","AutoToggle","SpeedToggle"]:
			var control: Control = scene.find_child(id,true,false)
			check(control != null and scene.get_global_rect().encloses(control.get_global_rect()),"%s fits %s" % [id,viewport])
		check(scene.portrait_buttons.size() == 1 and scene.portrait_buttons[0].find_children("*","TextureRect",true,false).is_empty(),"solo card has no portrait")
		check(scene.skill_buttons.is_empty(),"auto battle has no manual skill row")
	var header: Node = scene.find_child("TopHUD",true,false)
	check(header.get_children().slice(1).map(func(c): return str(c.name)) == ["Location","FoodLabel","ExpeditionMenu"],"floor header order")
	scene.show_menu(); await process_frame
	check(scene.modal_content.get_children().map(func(c): return c.text) == ["기록","가방","닫기"],"menu keeps only direct actions")
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
	scene.queue_free(); await process_frame
	print("Mobile HUD: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
