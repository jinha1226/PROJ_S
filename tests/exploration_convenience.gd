extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.size = Vector2i(390,844)
	var s = Session.new_run(827)
	var center: Vector2i = Fixture.arena(s,9)
	s.enemies.clear(); s.npcs.clear()
	for x in range(center.x-2,center.x+9):
		s.tile(Vector2i(x,center.y-1)).terrain = "wall"
		s.tile(Vector2i(x,center.y+1)).terrain = "wall"
	var npc: Dictionary = s.make_actor(888,"길목 NPC",false)
	npc.npc = true; npc.hostile = false; npc.awake = false; npc.ready_at = 999999
	npc.pos = center+Vector2i.RIGHT
	s.npcs.append(npc)
	var item: Vector2i = center+Vector2i(3,0)
	var item_id: String = str(s.Consumables.kinds()[0])
	s.floor_state.features[item] = {"kind":"item","item_id":item_id,"label":"바닥 물품"}
	var curio: Vector2i = center+Vector2i(5,0)
	s.floor_state.features[curio] = {"kind":"curio","curio_id":"MUSHROOMS","label":"버섯 군락","used":false}
	s.floor_state.observe(s)
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = s; root.add_child(scene); scene.set_process(false)
	for _frame in range(4): await process_frame
	check(s.can_swap_step(s.party[0],npc.pos),"a neutral NPC can exchange places with the hero")
	var route: Array = scene.navigation.route(s,item)
	check(route.size() > 1 and route[1] == npc.pos,"a long route passes through a friendly NPC in a narrow corridor")
	scene.on_cell(center+Vector2i(2,0))
	for _step in range(4):
		if not scene.navigation.active: break
		scene.board._process(1.0)
		scene.navigation_tick()
	check(s.party[0].pos == center+Vector2i(2,0) and npc.pos == center,"a distant tap swaps past the NPC")
	npc.pos = center+Vector2i.RIGHT
	s.party[0].pos = center
	s.floor_state.observe(s)
	scene.board.walk_actor_id = -1
	var before: int = int(s.bag.get(item_id,0))
	scene.toggle_explore()
	check(scene.navigation.active and scene.navigation.automatic,"auto exploration starts")
	for _step in range(8):
		if int(s.bag.get(item_id,0)) > before: break
		scene.board._process(1.0)
		scene.navigation_tick()
	check(int(s.bag.get(item_id,0)) == before+1 and not s.floor_state.features.has(item),"auto exploration walks to and picks up a known floor item")
	check(scene.board.walk_duration <= 0.08,"automatic movement uses the faster step interval")
	scene.stop_navigation()
	npc.pos = center+Vector2i(4,0)
	s.floor_state.observe(s)
	check(Session.Curios.error(s,curio,"SEARCH") == "거리 초과","the mushroom is still out of reach")
	scene.on_cell(curio)
	await process_frame
	var collect: Array = scene.modal_content.find_children("*","Button",true,false).filter(func(button): return button.text == "채집한다")
	check(collect.size() == 1 and not collect[0].disabled,"distant mushroom action stays enabled")
	if collect.size() == 1: collect[0].pressed.emit()
	check(scene.navigation.active and not scene.queued_curio.is_empty(),"distant action starts a route to the mushroom")
	for _step in range(8):
		if bool(s.floor_state.features[curio].used): break
		scene.board._process(1.0)
		scene.navigation_tick()
	check(bool(s.floor_state.features[curio].used) and scene.queued_curio.is_empty(),"the hero swaps past the NPC and harvests the mushroom")
	s.message("첫 문장입니다. 둘째 문장입니다.")
	check(s.log_lines[-2] == "첫 문장입니다." and s.log_lines[-1] == "둘째 문장입니다.","each sentence occupies one log entry")
	scene.queue_free(); await process_frame
	print("Exploration convenience: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
