extends SceneTree
## Solo descent: stair placement, visibility, camp, persistence, and death.
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
	for seed in range(100):
		var s = Session.new_run(seed)
		var layout: Dictionary = s.floor_state.layout
		var stairs: Vector2i = layout.stairs
		check(s.party.size() == 1 and not s.companions,"seed %d starts solo" % seed)
		check(s.food == 2 and s.supplies.size() == 5,"seed %d uses run resources" % seed)
		check(stairs.x >= 0 and s.floor_state.features.get(stairs,{}).get("kind","") == "stairs","seed %d has stairs" % seed)
		check(stairs != layout.entry and s.tile(stairs).terrain != "wall","seed %d stairs separate from entry" % seed)
		check(s.floor_state.features.values().filter(func(f): return f.get("kind","") == "stairs").size() == 1,"seed %d exactly one stair" % seed)
		check(s.floor_state.features.values().all(func(f): return f.get("kind","") != "relic"),"seed %d has no mission relic" % seed)
		check(s.enemies.all(func(e): return e.pos != stairs and e.pos != layout.entry),"seed %d endpoints have no enemy" % seed)
		check(Generator.validate(layout,Floor.theme_for(1)).is_empty(),"seed %d floor validates" % seed)
		check(s.floor_state.sight_radius() == 5.0 and s.floor_state.visible.has(layout.entry),"seed %d fixed sight sees entry" % seed)
		check(not s.descend(),"seed %d cannot descend remotely" % seed)
	var s = Session.new_run(731)
	check(s.companion_previews().is_empty() and not s.reserve_action(0,"WAIT",s.party[0].pos),"solo has no companion reservation")
	var stairs: Vector2i = s.floor_state.layout.stairs
	check(not s.floor_state.explored.has(stairs),"distant stairs start unseen")
	for enemy in s.enemies: enemy.hp = 0
	s.party[0].pos = stairs+Vector2i.LEFT; s.floor_state.observe(s)
	check(s.floor_state.visible.has(stairs) and s.floor_state.explored.has(stairs),"walking up reveals stairs")
	var old_food: int = s.food
	check(s.camp() and s.food == old_food-1,"solo camp costs one food")
	check(s.end_camp() and s.phase == "EXPLORE","camp returns to exploration")
	var hp: int = s.party[0].hp
	check(s.descend() and s.depth == 2,"adjacent stairs descend")
	check(s.party[0].hp == hp and s.food == old_food-1,"condition and food persist")
	check(s.floor_state.layout.theme_id == "F2_MINES","second floor changes theme")
	s.party[0].hp = 1; s.damage(s.party[0],50,100,"IMPACT")
	check(s.phase == "DEFEAT" and not s.descend(),"solo death ends the run")
	var scene = load("res://expedition/main.tscn").instantiate(); scene.session = s
	root.size = Vector2i(390,844); root.add_child(scene); await process_frame
	check(scene.find_child("ResultCard",true,false) != null,"death opens result card")
	check(scene.portrait_buttons.is_empty() and scene.item_buttons.is_empty(),"result omits combat controls")
	scene.queue_free(); await process_frame
	print("Solo floor: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
