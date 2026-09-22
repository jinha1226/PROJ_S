extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func prepare(seed_value: int = 731, id: String = "LOCKED_CHEST") -> Dictionary:
	var s = Session.new(seed_value,true,true,true)
	# The town kit stocks one of each tool; these cases assume two.
	s.exploration_tools = {"KEY":2,"SHOVEL":2}; s.depart()
	for enemy in s.enemies: enemy.hp = 0
	var p: Vector2i = s.floor_state.features.keys().filter(func(cell): return s.floor_state.features[cell].get("curio_id","") == id)[0]
	s.party[0].pos = Fixture.beside(s,p); s.party[1].pos = Fixture.beside(s,s.party[0].pos)
	s.floor_state.observe(s)
	return {"s":s,"p":p}
func run() -> void:
	var fixture := prepare(); var s = fixture.s; var p: Vector2i = fixture.p
	check(not s.floor_state.interact(s,p) and not s.floor_state.features[p].used,"generic interaction cannot bypass choice")
	var turn: int = s.round_number
	s.exploration_tools.KEY = 0
	check(not Session.Curios.resolve(s,p,"TOOL") and s.loot == 0 and s.round_number == turn,"missing tool costs no turn or reward")
	s.exploration_tools.KEY = 2
	check(not Session.Curios.resolve(s,p,"INVALID"),"invalid choice rejected")
	check(Session.Curios.resolve(s,p,"TOOL"),"key opens chest")
	check(s.loot == 30 and s.exploration_tools.KEY == 1 and s.round_number == turn+1,"one tool, one reward, one action")
	check(not Session.Curios.resolve(s,p,"BARE") and s.loot == 30 and s.exploration_tools.KEY == 1,"used chest cannot pay twice")
	fixture = prepare(731,"DIRT_PILE"); s = fixture.s; p = fixture.p
	var food: int = s.food
	check(Session.Curios.resolve(s,p,"TOOL") and s.food == food+2 and s.loot == 20 and s.exploration_tools.SHOVEL == 1,"shovel resolves dirt reward")
	fixture = prepare(731,"DIRT_PILE"); s = fixture.s; p = fixture.p
	check(Session.Curios.resolve(s,p,"BARE") and s.party[0].stress > 0 and s.exploration_tools.SHOVEL == 2 and s.loot == 10,"bare digging costs stress, not tool")
	fixture = prepare(); s = fixture.s; p = fixture.p
	s.enemies[0].hp = 20; s.enemies[0].pos = p+Vector2i.RIGHT; s.floor_state.observe(s)
	check(not Session.Curios.resolve(s,p,"TOOL") and not s.floor_state.features[p].used,"visible combat blocks investigation")
	s.enemies[0].hp = 0; Fixture.arena(s,3); s.floor_state.observe(s)
	check(not Session.Curios.resolve(s,p,"TOOL"),"remote interaction rejected")
	var saw_failure := false
	for seed_value in range(12):
		fixture = prepare(seed_value); s = fixture.s; p = fixture.p
		var hp: int = s.party[0].hp
		check(Session.Curios.resolve(s,p,"BARE") and s.floor_state.features[p].used,"risky option consumes object on either result")
		if s.party[0].hp < hp: saw_failure = true; check(s.loot == 0,"failed chest grants no reward")
	check(saw_failure,"deterministic seeds exercise trap branch")
	fixture = prepare(); s = fixture.s; p = fixture.p
	var scene = load("res://expedition/main.tscn").instantiate(); scene.session = s
	root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	turn = s.round_number; scene.on_cell(p); await process_frame
	check(scene.details_popup.visible and not s.floor_state.features[p].used and s.round_number == turn,"opening choices spends nothing")
	var skip: Button = scene.modal_content.find_children("*","Button",true,false).filter(func(b): return b.text == "지나가기")[0]
	skip.pressed.emit()
	check(not scene.details_popup.visible and s.round_number == turn and not s.floor_state.features[p].used,"skip keeps object and time unchanged")
	check(scene.inventory_rows().filter(func(r): return r.category == "도구").size() == 2,"both tools in common bag")
	var fresh = Session.new(731,true,true,true); fresh.depart(); scene.session = fresh; scene.refresh()
	var origin: Vector2i = fresh.party[0].pos
	var discovery := origin+Vector2i(floori(Session.Floor.sight_radius(fresh.light))+1,0)
	for x in range(origin.x,discovery.x+1): fresh.tile(Vector2i(x,origin.y)).terrain = "stone"
	fresh.floor_state.observe(fresh)
	fresh.floor_state.features[discovery] = {"kind":"curio","curio_id":"DIRT_PILE","used":false,"label":"흙더미"}
	scene.navigation.explore(fresh); scene.navigation.planned_path = [origin,origin+Vector2i.RIGHT]; scene.navigation.destination = origin+Vector2i.RIGHT
	turn = fresh.round_number; scene.navigation_tick()
	check(not scene.navigation.active and fresh.round_number == turn+1 and scene.notice.contains("조사물 발견"),"new discovery stops auto exploration after one step")
	var count: int = fresh.floor_state.discovered_curios; fresh.floor_state.observe(fresh)
	check(fresh.floor_state.discovered_curios == count,"known objects are not rediscovered every turn")
	scene.queue_free(); await process_frame
	print("Curios: %d failures" % failures); quit(1 if failures else 0)
