extends SceneTree
const Generator = preload("res://expedition/level/floor_generator.gd")
const Templates = preload("res://expedition/level/floor_templates.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = seed_value; return r
func run() -> void:
	var theme: Dictionary = Generator.theme("F1_RUINS")
	check(theme.monsters.max_members == 2,"first floor explicitly caps encounter actions at two enemies")
	check(theme.size == 80 and theme.depth == 1,"theme loads")
	check(Generator.theme("nope").is_empty(),"unknown theme is empty")
	await rooms_and_graph(theme)
	await corridors_and_paint(theme)
	await full_layouts(theme)
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
				check(rooms[i].rect.size.x >= 10 and rooms[i].rect.size.y >= 10 and rooms[i].rect.size.x <= 13 and rooms[i].rect.size.y <= 11,"fight room size")
			elif rooms[i].kind == "plain":
				check(rooms[i].rect.size.x >= 6 and rooms[i].rect.size.y >= 6 and rooms[i].rect.size.x <= 9 and rooms[i].rect.size.y <= 8,"plain room size")
			else:
				check(rooms[i].rows.size() == rooms[i].rect.size.y+2,"template rect matches rotated rows")
		var entry: Rect2i = rooms[Generator.room_index(rooms,"entry_camp")].rect
		var relic: Rect2i = rooms[Generator.room_index(rooms,"descent")].rect
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

func corridors_and_paint(theme: Dictionary) -> void:
	var size: int = theme.size
	var dropped_edge_seeds: int = 0
	var dropped_edges: int = 0
	for seed_value in range(100):
		var rooms: Array = Generator.scatter_rooms(theme,rng(seed_value))
		if rooms.is_empty(): continue
		var edges: Array = Generator.build_graph(rooms,theme,rng(seed_value))
		var planned: int = edges.size()
		var terrain: Array = Generator.carve(rooms,edges,theme,rng(seed_value))
		if edges.size() < planned:
			dropped_edge_seeds += 1
			dropped_edges += planned-edges.size()
		# Every edge that survived carve is a corridor you can actually walk.
		var room_reach: Dictionary = {}
		for edge in edges:
			var cells_a: Array = Generator.floor_cells(terrain,size,rooms[edge[0]].rect)
			var cells_b: Array = Generator.floor_cells(terrain,size,rooms[edge[1]].rect)
			check(not cells_a.is_empty() and not cells_b.is_empty(),"linked rooms have floor (seed %d)" % seed_value)
			if cells_a.is_empty() or cells_b.is_empty(): continue
			if not room_reach.has(edge[0]): room_reach[edge[0]] = Generator.reachable_from(terrain,size,cells_a[0])
			var reach_edge: Dictionary = room_reach[edge[0]]
			check(cells_b.any(func(p): return reach_edge.has(p)),"edge %s is walkable terrain (seed %d)" % [edge,seed_value])
		check(terrain.size() == size*size,"terrain covers the board")
		for i in range(size):
			check(terrain[i] == "wall" and terrain[(size-1)*size+i] == "wall" and terrain[i*size] == "wall" and terrain[i*size+size-1] == "wall","border stays wall")
		for room in rooms:
			check(room.doors.size() >= 1,"room %d has a door (seed %d)" % [room.id,seed_value])
			for d in room.doors:
				check(terrain[d.y*size+d.x] != "wall","door cell is floor")
				check(not room.rect.has_point(d) and Generator.outer(room.rect).has_point(d),"door sits on the wall ring")
			if room.kind == "template":
				var parsed: Dictionary = room.parsed
				for p in parsed.terrain:
					var cell: Vector2i = room.rect.position-Vector2i.ONE+p
					if p in parsed.doors: continue
					check(terrain[cell.y*size+cell.x] == parsed.terrain[p],"template interior untouched by corridors (seed %d)" % seed_value)
		check(rooms[Generator.room_index(rooms,"sealed_treasury")].doors.size() == 1,"treasury keeps a single door")
		var entry_room: Dictionary = rooms[Generator.room_index(rooms,"entry_camp")]
		var origin: Vector2i = entry_room.rect.position+Vector2i(1,2) # '@' sits at template (2,3); rect excludes the wall
		var reach: Dictionary = Generator.reachable_from(terrain,size,origin)
		for room in rooms:
			for p in Generator.floor_cells(terrain,size,room.rect):
				check(reach.has(p),"every room floor reachable from the entry (seed %d room %d)" % [seed_value,room.id])
		var painted: Dictionary = Generator.paint(terrain,rooms,theme,rng(seed_value))
		for room in rooms:
			if room.kind != "fight": continue
			var area: int = room.rect.size.x*room.rect.size.y
			var obstacles: Dictionary = painted[room.id].obstacles
			check(obstacles.size() <= area*15/100,"fight room obstacles at most 15 percent")
			check(Generator.has_open_block(terrain,size,room.rect,obstacles,5),"fight room keeps an open 5x5 block (seed %d room %d)" % [seed_value,room.id])
			for p in obstacles:
				for d in room.doors:
					check(maxi(absi(p.x-d.x),absi(p.y-d.y)) > 1,"pillars keep clear of doors")
		var reach_after: Dictionary = Generator.reachable_from(terrain,size,origin)
		for room in rooms:
			for p in Generator.floor_cells(terrain,size,room.rect):
				check(reach_after.has(p),"painting never disconnects a room (seed %d)" % seed_value)
		var accents: int = 0
		for cell in terrain:
			if cell in ["rubble","wood","water"]: accents += 1
		check(accents > 0,"palette accents painted")
	print("Floor generator: carve dropped an edge on %d of 100 seeds (%d edges total)" % [dropped_edge_seeds,dropped_edges])

func full_layouts(theme: Dictionary) -> void:
	var size: int = theme.size
	var total_regenerations := 0
	var min_usec := 1 << 62
	var max_usec := 0
	var sum_usec := 0
	for seed_value in range(100):
		var started: int = Time.get_ticks_usec()
		var layout: Dictionary = Generator.generate(theme,seed_value,1)
		var spent: int = Time.get_ticks_usec()-started
		min_usec = mini(min_usec,spent); max_usec = maxi(max_usec,spent); sum_usec += spent
		check(Generator.validate(layout,theme) == "","layout valid: %s (seed %d)" % [Generator.validate(layout,theme),seed_value])
		check(layout.size == size and layout.terrain.size() == size*size and layout.theme_id == "F1_RUINS" and layout.depth == 1,"contract scalars")
		check(layout.get("pillars",{}).keys().all(func(p): return layout.terrain[p.y*size+p.x] == "wall"),"pillar markers identify blocking wall cells")
		for room in layout.rooms:
			if room.kind != "template": continue
			for y in range(room.rect.position.y,room.rect.end.y):
				for x in range(room.rect.position.x,room.rect.end.x):
					var point := Vector2i(x,y)
					if layout.terrain[y*size+x] != "wall": continue
					if Generator.DIRECTIONS4.all(func(d): return layout.terrain[(y+d.y)*size+x+d.x] != "wall"):
						check(layout.pillars.has(point),"isolated template columns are marked")
		total_regenerations += layout.stats.regenerations
		check(layout.stats.regenerations <= 5,"regenerations bounded")
		var mandatory: Array = layout.encounters.filter(func(e): return e.mandatory)
		var optional: Array = layout.encounters.filter(func(e): return not e.mandatory)
		check(mandatory.size() >= 2 and mandatory.size() <= 3,"two or three mandatory encounters (seed %d: %d)" % [seed_value,mandatory.size()])
		check(optional.size() >= 1 and optional.size() <= 2,"one or two optional encounters (seed %d: %d)" % [seed_value,optional.size()])
		var relic_room: int = Generator.room_index(layout.rooms,"descent")
		check(mandatory.any(func(e): return e.room == relic_room and e.tier == "deep"),"relic vault holds a deep mandatory encounter")
		# Blocking every mandatory room cuts entry from relic: no route skips them all.
		var blocked: Dictionary = {}
		for e in mandatory:
			blocked[e.room] = true
		check(Generator.graph_path(layout.rooms,layout.edges,Generator.room_index(layout.rooms,"entry_camp"),relic_room,blocked).is_empty(),"mandatory rooms cover every entry->relic route (seed %d)" % seed_value)
		var budgets: Dictionary = theme.monsters.budget
		for e in layout.encounters:
			var expected: int = budgets.optional if not e.mandatory else budgets[e.tier]
			check(e.budget == expected,"encounter budget matches tier")
			var members: Array = e.members
			check(Generator.Encounters.valid(members,e.budget) == "","encounter members valid (seed %d room %d)" % [seed_value,e.room])
			var room: Dictionary = layout.rooms[e.room]
			for m in members:
				check(room.rect.has_point(m.pos) and layout.terrain[m.pos.y*size+m.pos.x] != "wall","member stands on room floor")
				for d in room.doors:
					check(maxi(absi(m.pos.x-d.x),absi(m.pos.y-d.y)) >= 3,"member three cells from doors (seed %d)" % seed_value)
				check(m.role in ["MELEE","RANGED","CASTER"] and m.has("species_id") and m.has("display_name") and m.has("max_health"),"member fields")
		var all_positions: Array = []
		for e in layout.encounters:
			for m in e.members:
				all_positions.append(m.pos)
		for p in layout.features:
			all_positions.append(p)
		check(all_positions.size() == all_positions.reduce(func(acc,p): return acc if p in acc else acc+[p],[]).size(),"no two objects share a cell (seed %d)" % seed_value)
		var kinds: Dictionary = {}
		for p in layout.features:
			var f: Dictionary = layout.features[p]
			var key: String = f.kind+("/"+f.curio_id if f.kind == "curio" else "")
			kinds[key] = int(kinds.get(key,0))+1
			var in_room: bool = layout.rooms.any(func(r): return r.rect.has_point(p))
			check(in_room,"feature %s inside a room, never a corridor (seed %d)" % [key,seed_value])
		check(kinds.get("entry",0) == 1 and kinds.get("stairs",0) == 1 and kinds.get("altar",0) == 1,"one entry, stairs and altar")
		check(kinds.get("curio/BROKEN_CHEST",0) >= theme.curios.broken_chest[0] and kinds.get("curio/BROKEN_CHEST",0) <= theme.curios.broken_chest[1],"chest count in theme range (%d)" % kinds.get("curio/BROKEN_CHEST",0))
		check(kinds.get("curio/MUSHROOMS",0) >= theme.curios.mushrooms[0] and kinds.get("curio/MUSHROOMS",0) <= theme.curios.mushrooms[1],"dirt count in theme range (%d)" % kinds.get("curio/MUSHROOMS",0))
		check(kinds.get("camp",0) == 1,"entry camp marker only")
		for id in ["supply_cache","dead_adventurer"]:
			var n: int = int(kinds.get("curio/"+id.to_upper(),0))
			check(n >= theme.curios[id][0] and n <= theme.curios[id][1],"%s count in theme range" % id)
		check(layout.npc_rooms.size() >= 3 and layout.npc_rooms.size() <= 5,"NPC rooms reserved")
		for p in layout.features:
			var f: Dictionary = layout.features[p]
			if f.kind in ["curio","altar"]:
				var owner: Dictionary = layout.rooms.filter(func(r): return r.rect.has_point(p))[0]
				check(not owner.spine or owner.kind == "template","procedurally placed rewards stay off the spine (seed %d)" % seed_value)
				check(layout.encounters.all(func(e): return e.room != owner.id) or owner.template_id == "collapsed_store","chests and dirt avoid fight rooms unless the template carries them")
		check(layout.stats.stairs_distance >= layout.stats.max_distance*60/100,"stairs far from entry (seed %d: %d of %d)" % [seed_value,layout.stats.stairs_distance,layout.stats.max_distance])
		var reach: Dictionary = Generator.reachable_from(layout.terrain,size,layout.entry)
		for p in layout.features:
			var adjacent := reach.has(p)
			for d in Generator.DIRECTIONS8:
				if reach.has(p+d): adjacent = true
			check(adjacent,"feature reachable or adjacent-reachable from entry (seed %d)" % seed_value)
		var again: Dictionary = Generator.generate(theme,seed_value,1)
		check(again.terrain == layout.terrain,"same seed regenerates the same terrain (seed %d)" % seed_value)
		check(again.features == layout.features,"same seed regenerates the same features (seed %d)" % seed_value)
		check(again.encounters == layout.encounters,"same seed regenerates the same encounters (seed %d)" % seed_value)
		check(again.entry == layout.entry and again.stairs == layout.stairs,"same seed regenerates the same entry and stairs (seed %d)" % seed_value)
		check(again.edges == layout.edges,"same seed regenerates the same edges (seed %d)" % seed_value)
	print("regenerations over 100 seeds: %d" % total_regenerations)
	check(total_regenerations <= 150,"regeneration is rare enough")
	print("generate() over 100 seeds: min %.1f ms, avg %.1f ms, max %.1f ms" % [min_usec/1000.0,sum_usec/100000.0,max_usec/1000.0])
	var blank: Dictionary = Generator.empty_layout(theme,0,1)
	for key in ["size","seed","theme_id","depth","terrain","rooms","edges","entry","stairs","features","encounters","stats"]:
		check(blank.has(key),"empty_layout carries the %s key" % key)
	check(blank.terrain.size() == size*size and blank.terrain.all(func(c): return c == "wall"),"empty_layout is all wall")
	check(blank.rooms.is_empty() and blank.edges.is_empty() and blank.encounters.is_empty() and blank.features.is_empty(),"empty_layout places nothing")
	check(blank.entry == Vector2i(-1,-1) and blank.stairs == Vector2i(-1,-1),"empty_layout has no entry or stairs")
	check(int(blank.stats.regenerations) == Generator.MAX_REGENERATIONS,"empty_layout reports a spent regeneration budget")
	check(not Generator.validate(blank,theme).is_empty(),"empty_layout never validates")
