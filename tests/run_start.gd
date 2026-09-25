extends SceneTree
const Session = preload("res://expedition/run/session.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var s = Session.new(731,false,false,true,1)
	check(s.party.size() == 1 and s.phase == "IDLE","idle solo party")
	check(s.depart(),"start")
	check(s.phase == "EXPLORE" and s.depth == 1 and s.food == 2,"floor 1 state")
	check(s.party[0].equipped_abilities == [""],"one empty slot at level one")
	check(s.bag.is_empty() and s.known.is_empty() and s.appearances.size() == 16,"empty bag and shuffled appearances")
	check(s.floor_state.sight_radius() == 6.0,"six-tile sight")
	var body_before: Dictionary = s.party[0].body.to_dict()
	s.damage(s.party[0],10,999,"IMPACT")
	check(s.party[0].body.to_dict() == body_before,"run damage changes HP without a lasting injury")
	check(s.floor_state.layout.get("stairs",Vector2i(-1,-1)).x >= 0,"stairs")
	check(s.floor_state.layout.get("npc_rooms",[]).size() >= 3,"NPC room reservations")
	check(not s.has_method("return_home") and not s.has_method("use_torch"),"old lifecycle removed")
	var main = load("res://expedition/ui/main.tscn").instantiate()
	root.add_child(main); await process_frame
	check(main.find_child("StartScreen",true,false) != null,"start screen")
	main.new_run(); await process_frame
	check(main.find_child("FoodLabel",true,false) != null and main.find_child("BottomActions",true,false) != null,"floor HUD")
	main.session.food = 2
	for enemy in main.session.enemies: enemy.hp = 0
	main.session.floor_state.observe(main.session); main.refresh(); await process_frame
	main.show_menu(); await process_frame
	var camp: Button = main.modal_content.get_child(0)
	check(camp != null and not camp.disabled,"camp available")
	camp.pressed.emit(); await process_frame
	check(main.find_child("CampScreen",true,false) != null,"camp screen")
	main.find_child("CampEnd",true,false).pressed.emit(); await process_frame
	check(main.session.phase == "EXPLORE","camp ends")
	main.session.party[0].hp = 0; main.session.check_battle_end(); main.refresh(); await process_frame
	check(main.find_child("ResultCard",true,false) != null,"result card")
	main.queue_free(); await process_frame
	print("Run start: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
