extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func touch(board, index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new(); event.index = index; event.position = position; event.pressed = pressed
	board._gui_input(event)
func run() -> void:
	root.size = Vector2i(390,844)
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = Session.new(731,true,true,true); root.add_child(scene); scene.depart()
	scene.set_process(false)
	for frame in range(4): await process_frame
	check(scene.root_layout.get_child(0).size.y < 70,"compact HUD height")
	check(scene.find_child("Location",true,false).get_theme_font_size("font_size") >= 18,"location text enlarged")
	check(scene.find_child("FoodLabel",true,false).text == "식량 %d" % scene.session.food,"compact food label shows actual supply")
	var s = scene.session
	var start: Vector2i = s.party[0].pos
	var target := start+Vector2i(4,0)
	var center_before: Vector2 = scene.board.cell_center(start)
	var floor_before: Vector2 = scene.board.cell_center(start+Vector2i(2,0))
	var turns: int = s.round_number
	scene.on_cell(target)
	check(s.party[0].pos != start and s.party[0].pos != target and s.round_number == turns+1,"distant tap advances one step, not teleport")
	check(scene.board.walk_actor_id == int(s.party[0].id) and scene.board.walk_from == start and scene.board.walk_to == s.party[0].pos,
		"travel step animates from the previous tile")
	var first_step: Vector2i = s.party[0].pos
	scene.navigation_tick()
	check(s.party[0].pos == first_step,"the next travel turn waits for the camera to finish its step")
	var board = scene.board
	check(board.display_center(s.party[0]).distance_to(center_before) < 0.01,"the hero does not jump when a travel step begins")
	board.walk_elapsed = board.walk_duration*0.5
	check(board.display_center(s.party[0]).distance_to(center_before) < 0.01,"the camera and hero move together")
	check(board.cell_center(start+Vector2i(2,0)).distance_to(floor_before-Vector2(board.half_width,0)) < 0.01,
		"the floor scrolls linearly through half a tile")
	check(board.cell_at(board.cell_center(start)) == start,"touch coordinates follow the scrolling camera")
	board.animate_walk(int(s.party[0].id),s.party[0].pos,s.party[0].pos+Vector2i.RIGHT,board.walk_duration)
	check(board.walk_visual_from.distance_to(Vector2(start)+Vector2(0.5,0)) < 0.01,
		"a queued step continues from the current visual position")
	board.animate_walk(int(s.party[0].id),start,s.party[0].pos,board.walk_duration)
	for i in range(10):
		if scene.navigation.active:
			board._process(board.walk_duration)
			scene.navigation_tick()
			var visual_focus: Vector2 = board.camera_origin()+Vector2.ONE*float((board.visible_side()-1)/2)
			check(visual_focus.distance_to(Vector2(s.party[0].pos)) <= 1.01,"camera remains within one tile of the moving hero")
	check(s.party[0].pos == target and s.round_number == turns+4 and not scene.navigation.active,"queued movement arrives using four turns")
	check(scene.navigation.plan_builds == 1,"long route reuses one A* plan")
	check(not scene.navigation.start(s,Vector2i(s.BOARD_SIDE-1,s.BOARD_SIDE-1)),"unknown destination rejected")
	board._process(board.walk_duration)
	scene.toggle_explore(); check(scene.navigation.active and scene.navigation.automatic,"auto exploration starts")
	turns = s.round_number; scene.navigation_tick()
	check(s.round_number == turns+1,"auto exploration performs a normal action")
	s.enemies[0].pos = s.party[0].pos+Vector2i.RIGHT; s.floor_state.observe(s)
	turns = s.round_number; scene.navigation_tick()
	check(not scene.navigation.active and s.round_number == turns,"enemy contact stops before another action")
	var battle_center: Vector2i = Fixture.arena(s,9)
	s.party[0].pos = battle_center
	s.enemies[0].hp = s.enemies[0].max_hp
	s.enemies[0].pos = battle_center+Vector2i(0,3)
	s.floor_state.observe(s)
	turns = s.round_number
	scene.on_cell(battle_center+Vector2i(3,0))
	if scene.navigation.active and scene.navigation_camera_busy():
		board._process(board.walk_duration)
		scene.navigation_tick()
	check(s.phase == "BATTLE" and s.party[0].pos != battle_center and s.round_number == turns+1,
		"a distant tap still moves one step after auto exploration stops on an enemy")
	s.enemies[0].pos = Vector2i(s.BOARD_SIDE-2,s.BOARD_SIDE-2); s.floor_state.observe(s)
	scene.refresh(); await process_frame
	board = scene.board
	var position: Vector2i = s.party[0].pos
	turns = s.round_number
	var initial_side: int = board.view_side
	touch(board,0,Vector2(100,120),true); touch(board,1,Vector2(200,120),true)
	var drag := InputEventScreenDrag.new(); drag.index = 1; drag.position = Vector2(280,120)
	board._gui_input(drag)
	check(board.view_side == clampi(roundi(initial_side/1.8),6,24),"pinch scales current camera size")
	drag.position = Vector2(500,120); board._gui_input(drag)
	check(board.view_side == 6,"pinch outward clamps at six tiles")
	touch(board,1,drag.position,false); touch(board,0,Vector2(100,120),false)
	check(s.round_number == turns and s.party[0].pos == position,"pinch release never moves or consumes a turn")
	for side in [6,10,16,24]:
		board.set_view_side(side)
		var camera: Vector2i = board.camera_cell()
		for y in range(side):
			for x in range(side):
				var p := camera+Vector2i(x,y)
				check(board.cell_at(board.cell_center(p)) == p,"zoom-aware cell hit test")
	scene.refresh(); await process_frame
	check(scene.board.view_side == 24,"zoom survives HUD refresh")
	var hero_status: Button = scene.find_child("HeroStatus",true,false)
	check(hero_status != null,"manual HUD exposes hero status")
	if hero_status != null:
		hero_status.pressed.emit(); await process_frame
		check(scene.details_popup.visible and scene.tactics_actor == 0 and scene.reservation_actor == -1,"hero status opens character without reservation")
		scene.details_popup.hide()
	check(scene.reservation_actor == -1 and s.selected == 0,"manual hero remains selected")
	for i in range(60): s.message("기록 %d" % i)
	scene.refresh(); await process_frame
	var recent: Button = scene.find_child("RecentLog",true,false)
	check(recent != null and recent.text == "기록 56\n기록 57\n기록 58\n기록 59","HUD shows the latest four log lines")
	var log_rect: Rect2 = scene.find_child("RecentLog",true,false).get_global_rect()
	var field_rect: Rect2 = scene.board.get_global_rect()
	check(log_rect.position.y >= field_rect.end.y and log_rect.size.y >= 36,"log button sits below the field")
	scene.show_logs(); await process_frame
	var history: RichTextLabel = scene.log_popup.find_child("FullHistory",true,false)
	check(history.text.contains("기록 0") and history.text.contains("기록 59"),"full log retains more than forty entries")
	check(scene.log_popup.size == Vector2i(scene.get_viewport_rect().size),"full-screen log fits viewport")
	scene.log_popup.hide()
	for viewport in [Vector2i(390,844),Vector2i(430,844),Vector2i(412,915)]:
		root.size = viewport
		for frame in range(4): await process_frame
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"HUD logs and footer fit portrait screen")
	var target_actor: Dictionary = s.enemies[0]
	target_actor.hp = 100; target_actor.max_hp = 100
	var before_hp: int = target_actor.hp
	s.damage(target_actor,7,s.party[0].id,"IMPACT")
	check(s.log_lines[-1] == "%s %s에게 %d의 피해를 주었습니다." % [Session.subject_name(s.party[0].name),target_actor.name,before_hp-target_actor.hp],"damage sentence names attacker, target, actual damage")
	s.damage(target_actor,2,999,"FIRE")
	check(s.log_lines[-1].begins_with("불길이 "),"environmental damage has a named cause")
	check(Session.subject_name("아린") == "아린이" and Session.subject_name("세라") == "세라가","Korean subject particles")
	var center: Vector2i = Fixture.arena(s,8)
	target_actor.hp = 100; target_actor.pos = center+Vector2i.RIGHT; s.floor_state.observe(s)
	scene.refresh(); await process_frame
	turns = s.round_number
	scene.find_child("Tactics",true,false).pressed.emit(); await process_frame
	check(scene.find_child("TacticFocus",true,false) != null and scene.find_child("TacticHold",true,false) != null,
		"solo tactics offer a target order and a real wait action")
	scene.find_child("TacticFocus",true,false).pressed.emit()
	check(scene.mode == "COMMAND_TARGET","focus command waits for an enemy tile")
	scene.on_cell(target_actor.pos)
	check(s.party_command == "ATTACK_TARGET" and s.command_target == target_actor.id and s.round_number == turns,
		"marking a target issues an order without spending a turn")
	target_actor.hp = 0; s.floor_state.observe(s); scene.refresh(); await process_frame
	scene.find_child("Tactics",true,false).pressed.emit(); await process_frame
	turns = s.round_number
	scene.find_child("TacticHold",true,false).pressed.emit()
	check(s.round_number == turns+1,"solo hold spends one turn in place")
	s.companions = true; s.party.append(s.make_actor(1,"브란",false)); s.party[1].pos = center+Vector2i.DOWN
	s.formation = [0,1]; target_actor.hp = 100; target_actor.pos = center+Vector2i(3,0)
	s.floor_state.observe(s); scene.refresh(); await process_frame
	scene.find_child("Tactics",true,false).pressed.emit(); await process_frame
	check(scene.find_child("Tactic_HOLD_POSITION",true,false) != null and scene.find_child("Tactic_RETREAT",true,false) != null
		and scene.find_child("Tactic_STOP_ATTACK",true,false) != null and scene.find_child("Tactic_FOLLOW",true,false) != null,
		"party tactics expose the four standing orders")
	scene.find_child("Tactic_HOLD_POSITION",true,false).pressed.emit()
	check(s.party_command == "HOLD_POSITION" and s.command_choice(s.party[1]).kind == "WAIT",
		"hold order makes a distant companion stay put")
	scene.queue_free(); await process_frame
	print("Mobile exploration: %d failures" % failures); quit(1 if failures else 0)
