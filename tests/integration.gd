extends SceneTree
## End-to-end floor contract and persistent run state across descent.
const Session = preload("res://expedition/session.gd")
const Floor = preload("res://expedition/continuous_floor.gd")
const Generator = preload("res://expedition/floor_generator.gd")
var checks := 0
var failures := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var signatures: Dictionary = {}
	var theme: Dictionary = Floor.theme_for(1)
	for seed in range(100):
		var s = Session.new_run(seed)
		var layout: Dictionary = s.floor_state.layout
		check(s.phase == "EXPLORE" and s.depth == 1 and s.party.size() == 1,"seed %d starts solo on floor one" % seed)
		check(layout.size == 80 and layout.terrain.size() == 6400,"seed %d full floor" % seed)
		check(Generator.validate(layout,theme).is_empty(),"seed %d layout validates" % seed)
		check(layout.entry != layout.stairs and layout.stairs.x >= 0,"seed %d has separate entry and stairs" % seed)
		check(s.tile(layout.entry).terrain != "wall" and s.tile(layout.stairs).terrain != "wall","seed %d endpoints walkable" % seed)
		check(layout.npc_rooms.size() >= 3 and layout.npc_rooms.size() <= 5,"seed %d reserved NPC rooms" % seed)
		var ids: Dictionary = {}
		for room in layout.rooms:
			check(not ids.has(room.id),"seed %d unique room id %d" % [seed,room.id])
			ids[room.id] = true
			check(room.rect.position.x >= 1 and room.rect.position.y >= 1 and room.rect.end.x < 80 and room.rect.end.y < 80,"seed %d room %d stays in bounds" % [seed,room.id])
			check(room.doors.size() >= 1 and room.doors.all(func(p): return s.tile(p).terrain != "wall"),"seed %d room %d has walkable doors" % [seed,room.id])
		check(ids.size() == layout.rooms.size(),"seed %d all rooms have ids" % seed)
		check(s.floor_state.features.has(layout.stairs) and s.floor_state.features[layout.stairs].kind == "stairs","seed %d stairs feature registered" % seed)
		check(s.enemies.all(func(e): return s.inside(e.pos) and s.tile(e.pos).terrain != "wall"),"seed %d enemies spawn on walkable tiles" % seed)
		signatures[str(layout.rooms.map(func(r): return r.rect))] = true
	check(signatures.size() > 20,"run seeds vary topology")
	var run_session = Session.new_run(731)
	var actor: Dictionary = run_session.party[0]
	actor.hp = 20; actor.stress = 60
	for enemy in run_session.enemies: enemy.hp = 0
	var food_before: int = run_session.food
	check(run_session.camp() and run_session.food == food_before-1,"safe camp consumes food")
	check(actor.hp > 20 and actor.stress == 30,"camp recovers condition")
	check(run_session.end_camp(),"camp returns to floor")
	var memory_before: Dictionary = actor.memory.to_dict()
	var hp_before: int = actor.hp
	run_session.party[0].pos = run_session.floor_state.layout.stairs
	run_session.floor_state.observe(run_session)
	check(run_session.descend() and run_session.depth == 2,"stairs advance to floor two")
	check(actor.hp == hp_before and actor.memory.to_dict() == memory_before,"descent keeps HP and memories")
	check(run_session.food == food_before-1 and run_session.floor_state.layout.theme_id == "F2_MINES","food persists and theme changes")
	run_session.damage(actor,1000,100,"IMPACT")
	run_session.check_battle_end()
	check(run_session.phase == "DEFEAT" and not run_session.descend(),"hero death ends run")
	print("Integration: %d checks, %d failures; 100 run seeds" % [checks,failures])
	quit(1 if failures else 0)
