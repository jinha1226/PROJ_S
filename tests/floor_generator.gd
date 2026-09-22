extends SceneTree
const Generator = preload("res://expedition/floor_generator.gd")
const Templates = preload("res://expedition/floor_templates.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = seed_value; return r
func run() -> void:
	var theme: Dictionary = Generator.theme("F1_RUINS")
	check(theme.size == 64 and theme.depth == 1,"theme loads")
	check(Generator.theme("nope").is_empty(),"unknown theme is empty")
	await rooms_and_graph(theme)
	print("Floor generator: %d failures" % failures); quit(1 if failures else 0)

func rooms_and_graph(theme: Dictionary) -> void:
	var scatter_failures: int = 0
	for seed_value in range(100):
		var rooms: Array = Generator.scatter_rooms(theme,rng(seed_value))
		if rooms.is_empty():
			scatter_failures += 1
			continue # scatter may fail; generate() retries with seed+1 (Task 5)
		check(rooms.size() >= theme.rooms.count[0] and rooms.size() <= theme.rooms.count[1],"room count in range (seed %d: %d)" % [seed_value,rooms.size()])
		var fights: int = rooms.filter(func(r): return r.kind == "fight" or (r.kind == "template" and r.template_id in theme.templates.fight_pool)).size()
		check(fights >= theme.rooms.fight[0] and fights <= theme.rooms.fight[1],"fight room count in range (seed %d: %d)" % [seed_value,fights])
		for id in theme.templates.required: check(Generator.room_index(rooms,id) >= 0,"required template %s present" % id)
		check(rooms.filter(func(r): return r.kind == "template" and r.template_id in theme.templates.fight_pool).size() == theme.templates.fight_picks,"two fight templates picked")
		for i in range(rooms.size()):
			var a: Rect2i = Generator.outer(rooms[i].rect)
			check(a.position.x >= 1 and a.position.y >= 1 and a.end.x <= theme.size-1 and a.end.y <= theme.size-1,"room inside the border wall")
			for j in range(i+1,rooms.size()):
				check(not a.grow(1).intersects(Generator.outer(rooms[j].rect)),"rooms keep two wall cells apart (seed %d)" % seed_value)
			if rooms[i].kind == "fight":
				check(rooms[i].rect.size.x >= 9 and rooms[i].rect.size.y >= 9 and rooms[i].rect.size.x <= 12 and rooms[i].rect.size.y <= 10,"fight room size")
			elif rooms[i].kind == "plain":
				check(rooms[i].rect.size.x >= 5 and rooms[i].rect.size.y >= 5 and rooms[i].rect.size.x <= 8 and rooms[i].rect.size.y <= 7,"plain room size")
			else:
				check(rooms[i].rows.size() == rooms[i].rect.size.y+2,"template rect matches rotated rows")
		var entry: Rect2i = rooms[Generator.room_index(rooms,"entry_camp")].rect
		var relic: Rect2i = rooms[Generator.room_index(rooms,"relic_vault")].rect
		check(entry.position.x < theme.size/3 and relic.position.x > theme.size*2/3-relic.size.x,"entry west, relic east")
		var edges: Array = Generator.build_graph(rooms,theme,rng(seed_value))
		check(edges.size() >= rooms.size()-1+theme.corridor.extra_links[0] and edges.size() <= rooms.size()-1+theme.corridor.extra_links[1],"spanning tree plus extra links (seed %d: %d edges for %d rooms)" % [seed_value,edges.size(),rooms.size()])
		var degree: Dictionary = {}
		for e in edges:
			check(e[0] < e[1],"edges stored ascending")
			degree[e[0]] = int(degree.get(e[0],0))+1; degree[e[1]] = int(degree.get(e[1],0))+1
		check(degree.get(Generator.room_index(rooms,"sealed_treasury"),0) == 1,"treasury is a leaf")
		check(degree.size() == rooms.size(),"every room connected")
		var leaves: int = 0
		for id in degree:
			if degree[id] == 1: leaves += 1
		check(leaves >= 2,"at least two dead ends (seed %d)" % seed_value)
		check(edges == Generator.build_graph(rooms,theme,rng(seed_value)),"graph deterministic")
	print("Floor generator: scatter returned [] on %d of 100 seeds" % scatter_failures)
