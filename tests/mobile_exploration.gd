extends SceneTree
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func touch(board, index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new(); event.index = index; event.position = position; event.pressed = pressed
	board._gui_input(event)
func run() -> void:
	root.size = Vector2i(390,844)
	var scene = load("res://expedition/main.tscn").instantiate()
	scene.session = Session.new(731,true,true,true); root.add_child(scene); scene.depart()
	scene.set_process(false)
	for frame in range(4): await process_frame
	check(scene.root_layout.get_child(0).size.y < 70,"compact HUD height")
	check(scene.find_child("Location",true,false).get_theme_font_size("font_size") >= 18,"location text enlarged")
	check(scene.find_child("FoodLabel",true,false).text == "식량 %d" % scene.session.food,"compact food label shows actual supply")
	var s = scene.session
	var start: Vector2i = s.party[0].pos
	var target := start+Vector2i(4,0)
	var turns: int = s.round_number
	scene.on_cell(target)
	check(s.party[0].pos != start and s.party[0].pos != target and s.round_number == turns+1,"distant tap advances one step, not teleport")
	for i in range(10):
		if scene.navigation.active: scene.navigation_tick()
	check(s.party[0].pos == target and s.round_number == turns+4 and not scene.navigation.active,"queued movement arrives using four turns")
	check(scene.navigation.plan_builds == 1,"long route reuses one A* plan")
	check(not scene.navigation.start(s,Vector2i(s.BOARD_SIDE-1,s.BOARD_SIDE-1)),"unknown destination rejected")
	scene.toggle_explore(); check(scene.navigation.active and scene.navigation.automatic,"auto exploration starts")
	turns = s.round_number; scene.navigation_tick()
	check(s.round_number == turns+1,"auto exploration performs a normal action")
	s.enemies[0].pos = s.party[0].pos+Vector2i.RIGHT; s.floor_state.observe(s)
	turns = s.round_number; scene.navigation_tick()
	check(not scene.navigation.active and s.round_number == turns,"enemy contact stops before another action")
	s.enemies[0].pos = Vector2i(s.BOARD_SIDE-2,s.BOARD_SIDE-2); s.floor_state.observe(s)
	scene.refresh(); await process_frame
	var board = scene.board
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
	var portrait = scene.portrait_buttons[0]
	var press := InputEventScreenTouch.new(); press.index = 0; press.pressed = true; press.position = portrait.get_global_rect().get_center()
	scene._input(press); scene.portrait_gesture.started -= 601; scene.portrait_gesture.tick(scene)
	press.pressed = false; scene._input(press)
	check(scene.details_popup.visible and scene.tactics_actor == 0 and scene.reservation_actor == -1,"long hold opens correct status without reservation")
	scene.details_popup.hide(); press.pressed = true; scene._input(press); press.pressed = false; scene._input(press)
	# Floor mode has no action reservations: a short tap only takes the camera there.
	check(scene.reservation_actor == -1 and s.selected == 0,"short portrait tap selects the member instead of reserving")
	for i in range(60): s.message("기록 %d" % i)
	scene.refresh(); await process_frame
	var recent: Button = scene.find_child("RecentLog",true,false)
	check(recent != null and recent.text == "기록 59","latest event remains a concise log button")
	var log_rect: Rect2 = scene.find_child("RecentLog",true,false).get_global_rect()
	var field_rect: Rect2 = scene.board.get_global_rect()
	check(log_rect.position.y >= field_rect.end.y and log_rect.size.y >= 36,"log button sits below the field")
	scene.show_logs(); await process_frame
	var history: RichTextLabel = scene.log_popup.find_child("FullHistory",true,false)
	check(history.text.contains("기록 0") and history.text.contains("기록 59"),"full log retains more than forty entries")
	check(scene.log_popup.size == root.size,"full-screen log fits viewport")
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
	scene.queue_free(); await process_frame
	print("Mobile exploration: %d failures" % failures); quit(1 if failures else 0)
