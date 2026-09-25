extends RefCounted
## Procedural floor: DCSS layout_rooms variant (scatter rooms, MST + loops,
## noisy-Dijkstra corridors, ASCII vault templates) with DD-style room-bound
## encounters. Pure static functions; output contract in the spec §7.
const Templates = preload("res://expedition/level/floor_templates.gd")
const Encounters = preload("res://expedition/level/encounter_builder.gd")
const Consumables = preload("res://expedition/items/consumables.gd")
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/floor_themes.json"))
const PLACE_TRIES := 200
const MAX_REGENERATIONS := 5
const ROOM_GAP := 2
const DIRECTIONS4 := [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]
const DIRECTIONS8 := [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN,Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]

static func theme(id: String) -> Dictionary:
	var row: Dictionary = content.get("themes",{}).get(id,{})
	if row.is_empty(): return {}
	row = row.duplicate(true)
	row.id = id
	row.size = int(row.size)
	row.depth = int(row.depth)
	row.rooms.count = [int(row.rooms.count[0]),int(row.rooms.count[1])]
	row.corridor.width = int(row.corridor.get("width",1))
	return row

static func outer(rect: Rect2i) -> Rect2i:
	return Rect2i(rect.position-Vector2i.ONE,rect.size+Vector2i(2,2))

static func room_index(rooms: Array, template_id: String) -> int:
	for i in range(rooms.size()):
		if rooms[i].template_id == template_id: return i
	return -1

static func make_room(id: int, rect: Rect2i, kind: String, template_id: String = "", rows: Array = [], parsed: Dictionary = {}) -> Dictionary:
	return {"id":id,"rect":rect,"kind":kind,"template_id":template_id,"rows":rows,"parsed":parsed,"doors":[],"tier":"","spine":false}

static func fits(rect: Rect2i, rooms: Array, size: int) -> bool:
	var shell := outer(rect)
	if shell.position.x < 1 or shell.position.y < 1 or shell.end.x > size-1 or shell.end.y > size-1: return false
	for room in rooms:
		if shell.grow(ROOM_GAP-1).intersects(outer(room.rect)): return false
	return true

## Room plan in placement order: required templates, picked fight templates,
## procedural fight rooms, plain rooms. Returns [] when placement fails.
static func scatter_rooms(theme: Dictionary, rng: RandomNumberGenerator) -> Array:
	var size: int = theme.size
	var count: int = rng.randi_range(theme.rooms.count[0],theme.rooms.count[1])
	var fight_total: int = rng.randi_range(theme.rooms.fight[0],theme.rooms.fight[1])
	var pool: Array = theme.templates.fight_pool.duplicate()
	var picks: Array = []
	for _i in range(theme.templates.fight_picks):
		picks.append(pool.pop_at(rng.randi_range(0,pool.size()-1)))
	var plan: Array = []
	for id in theme.templates.required: plan.append({"kind":"template","template_id":id})
	for id in picks: plan.append({"kind":"template","template_id":id})
	for _i in range(fight_total-picks.size()): plan.append({"kind":"fight"})
	while plan.size() < count: plan.append({"kind":"plain"})
	var rooms: Array = []
	for spec in plan:
		var placed := false
		for _try in range(PLACE_TRIES):
			var rect: Rect2i
			var rows: Array = []
			var parsed: Dictionary = {}
			if spec.kind == "template":
				var def: Dictionary = Templates.definition(spec.template_id)
				rows = Templates.rotate(def.rows,rng.randi_range(0,3) if def.orient else 0)
				parsed = Templates.parse(rows)
				var interior := Vector2i(parsed.width-2,parsed.height-2)
				rect = Rect2i(random_origin(theme,rng,interior,spec.template_id),interior)
			else:
				var range_rows: Array = theme.rooms.fight_size if spec.kind == "fight" else theme.rooms.plain_size
				var interior := Vector2i(rng.randi_range(range_rows[0][0],range_rows[1][0]),rng.randi_range(range_rows[0][1],range_rows[1][1]))
				rect = Rect2i(random_origin(theme,rng,interior,""),interior)
			if not fits(rect,rooms,size): continue
			rooms.append(make_room(rooms.size(),rect,spec.kind,spec.get("template_id",""),rows,parsed))
			placed = true; break
		if not placed: return []
	return rooms

static func random_origin(theme: Dictionary, rng: RandomNumberGenerator, interior: Vector2i, template_id: String) -> Vector2i:
	# Origins start at 3 so a door on the outer wall still has a corridor cell
	# (x or y == 1) outside it; dig_path never uses the border row/column.
	var size: int = theme.size
	var min_x := 3; var max_x: int = size-3-interior.x-1
	if template_id == "entry_camp": max_x = mini(max_x,size/3-interior.x)
	elif template_id in ["descent","boss_lair"]: min_x = maxi(min_x,size*2/3)
	return Vector2i(rng.randi_range(min_x,maxi(min_x,max_x)),rng.randi_range(3,size-3-interior.y-1))

static func center(room: Dictionary) -> Vector2:
	return Vector2(room.rect.position)+Vector2(room.rect.size)/2.0

static func segment_crosses_room(a: Vector2, b: Vector2, rooms: Array, skip: Array) -> bool:
	var steps: int = int(a.distance_to(b)*2)+1
	for i in range(steps+1):
		var p: Vector2 = a.lerp(b,float(i)/steps)
		for room in rooms:
			if room.id in skip: continue
			if Rect2(outer(room.rect)).has_point(p): return true
	return false

static func find_root(parent: Array, i: int) -> int:
	while parent[i] != i: parent[i] = parent[parent[i]]; i = parent[i]
	return i

## Kruskal MST over room centres (treasury excluded), extra links that do not
## cut through other rooms, then the treasury hung as a leaf on its nearest
## non-template room.
static func build_graph(rooms: Array, theme: Dictionary, rng: RandomNumberGenerator) -> Array:
	var treasury := room_index(rooms,"sealed_treasury")
	var pairs: Array = []
	for i in range(rooms.size()):
		for j in range(i+1,rooms.size()):
			if i == treasury or j == treasury: continue
			pairs.append({"a":i,"b":j,"d":center(rooms[i]).distance_to(center(rooms[j]))})
	pairs.sort_custom(func(x,y): return x.d < y.d if x.d != y.d else (x.a < y.a if x.a != y.a else x.b < y.b))
	var parent: Array = range(rooms.size())
	var edges: Array = []
	var used: Dictionary = {}
	for pair in pairs:
		var ra := find_root(parent,pair.a); var rb := find_root(parent,pair.b)
		if ra == rb: continue
		parent[ra] = rb; edges.append([pair.a,pair.b]); used["%d/%d" % [pair.a,pair.b]] = true
	# The treasury hangs off its nearest non-template room, so that anchor is
	# known before the loops close off the last dead end.
	var anchor := -1
	if treasury >= 0:
		var best_d := INF
		for i in range(rooms.size()):
			if i == treasury or rooms[i].kind == "template": continue
			var d := center(rooms[i]).distance_to(center(rooms[treasury]))
			if d < best_d: best_d = d; anchor = i
	var degree: Array = []
	degree.resize(rooms.size()); degree.fill(0)
	for edge in edges:
		degree[edge[0]] += 1; degree[edge[1]] += 1
	if anchor >= 0: degree[anchor] += 1
	var leaves := 0
	for i in range(rooms.size()):
		if i != treasury and degree[i] == 1: leaves += 1
	var extra: int = rng.randi_range(theme.corridor.extra_links[0],theme.corridor.extra_links[1])
	for pair in pairs:
		if extra <= 0: break
		if used.has("%d/%d" % [pair.a,pair.b]): continue
		if segment_crosses_room(center(rooms[pair.a]),center(rooms[pair.b]),rooms,[pair.a,pair.b]): continue
		# Keep at least one dead end besides the treasury: a floor whose loops
		# swallow every leaf reads as a ring, not a branching ruin.
		var spent: int = (1 if degree[pair.a] == 1 else 0)+(1 if degree[pair.b] == 1 else 0)
		if leaves-spent < 1: continue
		leaves -= spent
		degree[pair.a] += 1; degree[pair.b] += 1
		edges.append([pair.a,pair.b]); used["%d/%d" % [pair.a,pair.b]] = true; extra -= 1
	if anchor >= 0: edges.append([mini(anchor,treasury),maxi(anchor,treasury)])
	return edges

static func index_of(size: int, p: Vector2i) -> int:
	return p.y*size+p.x

static func inside(size: int, p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < size and p.y < size

## Door candidates on the wall ring: template '+' cells, or the middle ±2 of
## each side for procedural rooms (corners excluded).
static func door_candidates(room: Dictionary) -> Array:
	var shell := outer(room.rect)
	if room.kind == "template":
		return room.parsed.doors.map(func(p): return shell.position+p)
	var result: Array = []
	var cx: int = room.rect.position.x+room.rect.size.x/2
	var cy: int = room.rect.position.y+room.rect.size.y/2
	for dx in range(-2,3):
		var x: int = cx+dx
		if x > room.rect.position.x and x < room.rect.end.x-1:
			result.append(Vector2i(x,shell.position.y))
			result.append(Vector2i(x,shell.end.y-1))
	for dy in range(-2,3):
		var y: int = cy+dy
		if y > room.rect.position.y and y < room.rect.end.y-1:
			result.append(Vector2i(shell.position.x,y))
			result.append(Vector2i(shell.end.x-1,y))
	return result

static func outward(room: Dictionary, door: Vector2i) -> Vector2i:
	var shell := outer(room.rect)
	if door.y == shell.position.y: return Vector2i.UP
	if door.y == shell.end.y-1: return Vector2i.DOWN
	if door.x == shell.position.x: return Vector2i.LEFT
	return Vector2i.RIGHT

## Noisy Dijkstra between two cells: walls cost 3, existing floor 1, plus
## rng noise up to `wiggle` so corridors bend like DCSS join_the_dots.
## Protected cells (template shells) are impassable.
static func dig_path(terrain: Array, size: int, start: Vector2i, goal: Vector2i, protected: Dictionary, wiggle: int, rng: RandomNumberGenerator) -> Array:
	var noise: Dictionary = {}
	var cost: Dictionary = {start:0.0}
	var previous: Dictionary = {}
	var open: Array = [start]
	while not open.is_empty():
		var best := 0
		for i in range(1,open.size()):
			if cost[open[i]] < cost[open[best]]: best = i
		var current: Vector2i = open.pop_at(best)
		if current == goal: break
		for d in DIRECTIONS4:
			var next: Vector2i = current+d
			if not inside(size,next) or next.x == 0 or next.y == 0 or next.x == size-1 or next.y == size-1: continue
			if protected.has(next) and next != goal: continue
			if not noise.has(next): noise[next] = rng.randf()*wiggle
			var step: float = (1.0 if terrain[index_of(size,next)] != "wall" else 3.0)+noise[next]
			var total: float = cost[current]+step
			if not cost.has(next) or total < cost[next]:
				cost[next] = total; previous[next] = current
				if next not in open: open.append(next)
	if not previous.has(goal) and start != goal: return []
	var path: Array = [goal]
	while path[path.size()-1] != start: path.append(previous[path[path.size()-1]])
	path.reverse()
	return path

static func carve(rooms: Array, edges: Array, theme: Dictionary, rng: RandomNumberGenerator) -> Array:
	var size: int = theme.size
	var terrain: Array = []
	terrain.resize(size*size); terrain.fill("wall")
	var protected: Dictionary = {}
	for room in rooms:
		room.doors = []
		if room.kind == "template":
			Templates.stamp(terrain,size,room.rect.position-Vector2i.ONE,room.parsed)
			var shell := outer(room.rect)
			for y in range(shell.position.y,shell.end.y):
				for x in range(shell.position.x,shell.end.x): protected[Vector2i(x,y)] = true
		else:
			for y in range(room.rect.position.y,room.rect.end.y):
				for x in range(room.rect.position.x,room.rect.end.x): terrain[index_of(size,Vector2i(x,y))] = theme.palette.floor
	# `edges` is mutated in place: an edge whose corridor cannot be dug is
	# dropped so layout.edges always matches the carved terrain.
	for edge in edges.duplicate():
		var a: Dictionary = rooms[edge[0]]
		var b: Dictionary = rooms[edge[1]]
		var best_pair: Array = []
		var best_d := 1 << 30
		for ca in door_candidates(a):
			for cb in door_candidates(b):
				var d: int = absi(ca.x-cb.x)+absi(ca.y-cb.y)
				if d < best_d:
					best_d = d; best_pair = [ca,cb]
		if best_pair.is_empty():
			edges.erase(edge)
			continue
		var da: Vector2i = best_pair[0]
		var db: Vector2i = best_pair[1]
		var from: Vector2i = da+outward(a,da)
		var to: Vector2i = db+outward(b,db)
		var path := dig_path(terrain,size,from,to,protected,theme.corridor.wiggle,rng)
		if path.is_empty():
			edges.erase(edge)
			continue
		for p in [da,db]+path:
			if terrain[index_of(size,p)] == "wall": terrain[index_of(size,p)] = theme.palette.floor
		if int(theme.corridor.get("width",1)) >= 2:
			for i in range(path.size()):
				var p: Vector2i = path[i]
				var direction: Vector2i = path[mini(i+1,path.size()-1)]-p if i+1 < path.size() else p-path[i-1] if i > 0 else Vector2i.RIGHT
				var side := Vector2i(-direction.y,direction.x)
				for neighbor in [p+side,p-side]:
					if neighbor.x > 0 and neighbor.y > 0 and neighbor.x < size-1 and neighbor.y < size-1 and not protected.has(neighbor):
						if terrain[index_of(size,neighbor)] == "wall": terrain[index_of(size,neighbor)] = theme.palette.floor
						break
		if da not in a.doors: a.doors.append(da)
		if db not in b.doors: b.doors.append(db)
	# Corridors that brushed a procedural room's wall ring opened extra doors.
	for room in rooms:
		if room.kind == "template": continue
		var shell := outer(room.rect)
		for y in range(shell.position.y,shell.end.y):
			for x in range(shell.position.x,shell.end.x):
				var p := Vector2i(x,y)
				if room.rect.has_point(p): continue
				if terrain[index_of(size,p)] != "wall" and p not in room.doors and (x == shell.position.x or x == shell.end.x-1) != (y == shell.position.y or y == shell.end.y-1): room.doors.append(p)
	return terrain

static func floor_cells(terrain: Array, size: int, rect: Rect2i) -> Array:
	var result: Array = []
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			if terrain[index_of(size,Vector2i(x,y))] != "wall": result.append(Vector2i(x,y))
	return result

## Same rule as Session.walk_reach: only the destination must be open.
static func reachable_from(terrain: Array, size: int, origin: Vector2i) -> Dictionary:
	var dist: Dictionary = {origin:0}
	var queue: Array = [origin]
	var cursor := 0
	while cursor < queue.size():
		var p: Vector2i = queue[cursor]; cursor += 1
		for d in DIRECTIONS8:
			var next: Vector2i = p+d
			if dist.has(next) or not inside(size,next) or terrain[index_of(size,next)] == "wall": continue
			dist[next] = int(dist[p])+1; queue.append(next)
	return dist

static func has_open_block(terrain: Array, size: int, rect: Rect2i, obstacles: Dictionary, side: int) -> bool:
	for y in range(rect.position.y,rect.end.y-side+1):
		for x in range(rect.position.x,rect.end.x-side+1):
			var open := true
			for yy in range(y,y+side):
				for xx in range(x,x+side):
					var p := Vector2i(xx,yy)
					if obstacles.has(p) or terrain[index_of(size,p)] == "wall": open = false
			if open: return true
	return false

static func paint(terrain: Array, rooms: Array, theme: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var size: int = theme.size
	var result: Dictionary = {}
	for room in rooms:
		var obstacles: Dictionary = {}
		if room.kind == "fight":
			var cells := floor_cells(terrain,size,room.rect)
			var wanted: int = cells.size()*10/100
			var candidates: Array = cells.filter(func(p): return room.doors.all(func(d): return maxi(absi(p.x-d.x),absi(p.y-d.y)) > 1))
			for _i in range(wanted):
				if candidates.is_empty(): break
				var p: Vector2i = candidates.pop_at(rng.randi_range(0,candidates.size()-1))
				obstacles[p] = true
				candidates = candidates.filter(func(q): return maxi(absi(q.x-p.x),absi(q.y-p.y)) > 1)
			var keys: Array = obstacles.keys()
			while not has_open_block(terrain,size,room.rect,obstacles,5) and not keys.is_empty():
				obstacles.erase(keys.pop_back())
			for p in obstacles: terrain[index_of(size,p)] = "wall"
			# A pillar must never cut a room in two.
			var cells_after := floor_cells(terrain,size,room.rect)
			if not cells_after.is_empty():
				var reach := reachable_from(terrain,size,cells_after[0])
				if not cells_after.all(func(p): return reach.has(p)):
					for p in obstacles: terrain[index_of(size,p)] = theme.palette.floor
					obstacles.clear()
		elif room.kind == "plain":
			var cells := floor_cells(terrain,size,room.rect)
			var accent: String = theme.palette.accents[rng.randi_range(0,theme.palette.accents.size()-1)]
			var wanted: int = int(cells.size()*theme.palette.accent_ratio)
			var seed_cell: Vector2i = cells[rng.randi_range(0,cells.size()-1)]
			var cluster: Array = [seed_cell]
			var seen: Dictionary = {seed_cell:true}
			var cursor := 0
			while cluster.size() < wanted and cursor < cluster.size():
				for d in DIRECTIONS4:
					var next: Vector2i = cluster[cursor]+d
					if room.rect.has_point(next) and not seen.has(next) and rng.randi_range(0,2) > 0:
						seen[next] = true; cluster.append(next)
						if cluster.size() >= wanted: break
				cursor += 1
			for p in cluster:
				if room.doors.all(func(d): return maxi(absi(p.x-d.x),absi(p.y-d.y)) > 1): terrain[index_of(size,p)] = accent
		result[room.id] = {"obstacles":obstacles}
	return result

static func adjacency(rooms: Array, edges: Array) -> Dictionary:
	var result: Dictionary = {}
	for room in rooms:
		result[room.id] = []
	for e in edges:
		result[e[0]].append(e[1])
		result[e[1]].append(e[0])
	return result

static func graph_distances(rooms: Array, edges: Array, origin: int) -> Dictionary:
	var adj := adjacency(rooms,edges)
	var dist: Dictionary = {origin:0}
	var queue: Array = [origin]
	var cursor := 0
	while cursor < queue.size():
		var id: int = queue[cursor]
		cursor += 1
		for next in adj[id]:
			if not dist.has(next):
				dist[next] = int(dist[id])+1
				queue.append(next)
	return dist

## Shortest room path by edge count; rooms in `blocked` are impassable (the
## destination itself still counts as reached). Empty when no route remains.
static func graph_path(rooms: Array, edges: Array, from: int, to: int, blocked: Dictionary) -> Array:
	var adj := adjacency(rooms,edges)
	var previous: Dictionary = {from:-1}
	var queue: Array = [from]
	var cursor := 0
	while cursor < queue.size():
		var id: int = queue[cursor]
		cursor += 1
		if id == to:
			var path: Array = [to]
			while previous[path[path.size()-1]] != -1:
				path.append(previous[path[path.size()-1]])
			path.reverse()
			return path
		for next in adj[id]:
			if previous.has(next) or (blocked.has(next) and next != to): continue
			previous[next] = id
			queue.append(next)
	return []

static func is_fight_room(room: Dictionary, theme: Dictionary) -> bool:
	return room.kind == "fight" or (room.kind == "template" and (room.template_id in theme.templates.fight_pool or room.template_id in ["descent","boss_lair"]))

## Tiers by graph distance, spine rooms, mandatory (articulation -> shortest
## path) and optional (treasury neighbour, dead ends) encounter rooms.
static func choose_encounter_rooms(rooms: Array, edges: Array, theme: Dictionary) -> Dictionary:
	var entry := room_index(rooms,"entry_camp")
	var relic := room_index(rooms,"boss_lair" if theme.get("boss",false) else "descent")
	var treasury := room_index(rooms,"sealed_treasury")
	var dist := graph_distances(rooms,edges,entry)
	var adj := adjacency(rooms,edges)
	var relic_neighbours: Array = adj[relic]
	for room in rooms:
		var d: int = int(dist.get(room.id,99))
		room.tier = "deep" if room.id == relic or room.id in relic_neighbours else "early" if d <= 2 else "mid"
	var spine := graph_path(rooms,edges,entry,relic,{})
	for room in rooms:
		room.spine = room.id in spine
	var mandatory: Array = [relic]
	for room in rooms:
		if room.id in [entry,relic,treasury] or not is_fight_room(room,theme): continue
		if graph_path(rooms,edges,entry,relic,{room.id:true}).is_empty(): mandatory.append(room.id)
	if mandatory.size() < 2:
		for id in spine:
			if id in mandatory or id in [entry,treasury] or not is_fight_room(rooms[id],theme): continue
			mandatory.append(id)
			if mandatory.size() >= 2: break
	var optional: Array = []
	if treasury >= 0:
		for id in adj[treasury]:
			if id not in mandatory and is_fight_room(rooms[id],theme) and id != entry: optional.append(id)
	for room in rooms:
		if optional.size() >= 2: break
		if room.id in mandatory or room.id in optional or room.id in [entry,treasury] or not is_fight_room(room,theme): continue
		if adj[room.id].size() == 1: optional.append(room.id)
	if optional.is_empty():
		for room in rooms:
			if room.id not in mandatory and room.id not in [entry,treasury] and is_fight_room(room,theme):
				optional.append(room.id)
				break
	return {"mandatory":mandatory,"optional":optional.slice(0,2)}

static func room_anchor(room: Dictionary) -> Vector2i:
	if room.kind == "template" and room.parsed.anchor != Vector2i(-1,-1): return room.rect.position-Vector2i.ONE+room.parsed.anchor
	return Vector2i(-1,-1)

static func room_backline(room: Dictionary) -> Array:
	if room.kind != "template": return []
	return room.parsed.backline.map(func(p): return room.rect.position-Vector2i.ONE+p)

## One encounter per chosen room; feature cells and earlier members stay
## reserved so nothing shares a cell. Empty when a pack will not fit.
static func build_encounters(layout: Dictionary, theme: Dictionary, painted: Dictionary, rng: RandomNumberGenerator, depth: int) -> Array:
	var rooms: Array = layout.rooms
	var chosen := choose_encounter_rooms(rooms,layout.edges,theme)
	var result: Array = []
	var reserved: Dictionary = {}
	for p in layout.features:
		reserved[p] = true
	for id in chosen.mandatory+chosen.optional:
		var room: Dictionary = rooms[id]
		if theme.get("boss",false) and room.template_id == "boss_lair": continue
		var mandatory: bool = id in chosen.mandatory
		var budget: int = theme.monsters.budget[room.tier] if mandatory else theme.monsters.budget.optional
		var members := Encounters.fill(rng,mini(depth,6),budget,room.tier == "deep" or not mandatory,int(theme.monsters.get("max_members",Encounters.MAX_MEMBERS)))
		var obstacles: Dictionary = painted.get(id,{}).get("obstacles",{}).duplicate()
		for p in reserved:
			obstacles[p] = true
		if not Encounters.place(members,floor_cells(layout.terrain,layout.size,room.rect),room.doors,room_anchor(room),room_backline(room),obstacles,rng): return []
		for m in members:
			reserved[m.pos] = true
		result.append({"room":id,"tier":room.tier,"mandatory":mandatory,"budget":budget,"members":members})
	return result

## Template features first (entry, relic, altar, the treasury chests, the
## store's dirt, the camp), then chests on dead-end branch rooms, dirt in
## branch corners and an optional mid-tier camp -- never on the spine.
static func place_features(layout: Dictionary, theme: Dictionary, rng: RandomNumberGenerator) -> void:
	var rooms: Array = layout.rooms
	var size: int = layout.size
	var features: Dictionary = {}
	for room in rooms:
		if room.kind != "template": continue
		for p in room.parsed.features:
			var cell: Vector2i = room.rect.position-Vector2i.ONE+p
			features[cell] = room.parsed.features[p].duplicate(true)
			if features[cell].kind == "entry": layout.entry = cell
			if features[cell].kind == "stairs": layout.stairs = cell
	var count := func(kind: String, curio_id: String) -> int:
		return features.values().filter(func(f): return f.kind == kind and f.get("curio_id","") == curio_id).size()
	var adj := adjacency(rooms,layout.edges)
	var branch_plain: Array = rooms.filter(func(r): return r.kind == "plain" and not r.spine)
	var dead_end_plain: Array = branch_plain.filter(func(r): return adj[r.id].size() == 1)
	var is_corner := func(room: Dictionary, p: Vector2i) -> bool:
		return (p.x == room.rect.position.x or p.x == room.rect.end.x-1) and (p.y == room.rect.position.y or p.y == room.rect.end.y-1)
	var free_cell := func(room: Dictionary, corner: bool, draw_rng: RandomNumberGenerator) -> Vector2i:
		var cells: Array = floor_cells(layout.terrain,size,room.rect).filter(func(p): return not features.has(p) and room.doors.all(func(d): return maxi(absi(p.x-d.x),absi(p.y-d.y)) > 1))
		if corner:
			var corners: Array = cells.filter(func(p): return is_corner.call(room,p))
			if not corners.is_empty(): cells = corners
		if cells.is_empty(): return Vector2i(-1,-1)
		return cells[draw_rng.randi_range(0,cells.size()-1)]
	for id in ["supply_cache","mushrooms","dead_adventurer","broken_chest"]:
		var target: int = rng.randi_range(theme.curios[id][0],theme.curios[id][1])
		var glyph: String = {"supply_cache":"&","mushrooms":"^","dead_adventurer":"!","broken_chest":"$"}[id]
		var rooms_for: Array = dead_end_plain if id == "broken_chest" and not dead_end_plain.is_empty() else branch_plain
		var guard := 0
		while count.call("curio",id.to_upper()) < target and not rooms_for.is_empty() and guard < 30:
			guard += 1
			var cell: Vector2i = free_cell.call(rooms_for[rng.randi_range(0,rooms_for.size()-1)],id == "mushrooms",rng)
			if cell.x >= 0: features[cell] = Templates.feature_for(glyph)
	# A separate generator keeps monster compositions stable when loot changes.
	var item_rng := RandomNumberGenerator.new()
	item_rng.seed = int(layout.seed)+0x4D595DF4
	var item_count: int = item_rng.randi_range(int(theme.items[0]),int(theme.items[1]))
	var item_rooms: Array = rooms.filter(func(r): return r.kind == "plain")
	for _i in range(item_count):
		var options: Array = item_rooms.duplicate()
		while not options.is_empty():
			var room: Dictionary = options.pop_at(item_rng.randi_range(0,options.size()-1))
			var cell: Vector2i = free_cell.call(room,false,item_rng)
			if cell.x < 0: continue
			var weight_total := 0
			for row in Consumables.content.kinds: weight_total += int(row.weight)
			var roll: int = item_rng.randi_range(0,weight_total-1)
			for row in Consumables.content.kinds:
				roll -= int(row.weight)
				if roll < 0:
					features[cell] = {"kind":"item","item_id":str(row.id),"label":str(row.name)}
					break
			break
	layout.features = features

static func attempt_layout(theme: Dictionary, seed: int, depth: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rooms := scatter_rooms(theme,rng)
	if rooms.is_empty(): return {}
	var edges := build_graph(rooms,theme,rng)
	var terrain := carve(rooms,edges,theme,rng)
	var painted := paint(terrain,rooms,theme,rng)
	var pillars: Dictionary = {}
	for room_id in painted:
		for point in painted[room_id].obstacles: pillars[point] = true
	# Template rooms also use lone interior wall cells as columns.
	for room in rooms:
		if room.kind != "template": continue
		for y in range(room.rect.position.y,room.rect.end.y):
			for x in range(room.rect.position.x,room.rect.end.x):
				var point := Vector2i(x,y)
				if terrain[index_of(theme.size,point)] != "wall": continue
				if DIRECTIONS4.all(func(d): return terrain[index_of(theme.size,point+d)] != "wall"):
					pillars[point] = true
	var layout := {"size":theme.size,"seed":seed,"theme_id":theme.get("id",""),"depth":depth,"terrain":terrain,"rooms":rooms,"edges":edges,
		"entry":Vector2i(-1,-1),"stairs":Vector2i(-1,-1),"features":{},"encounters":[],"npc_rooms":[],"pillars":pillars,"stats":{"regenerations":0,"stairs_distance":0,"max_distance":0}}
	choose_encounter_rooms(rooms,edges,theme) # sets tier/spine before features
	place_features(layout,theme,rng)
	layout.encounters = build_encounters(layout,theme,painted,rng,depth)
	var reach := reachable_from(terrain,theme.size,layout.entry)
	var farthest := 0
	for v in reach.values():
		farthest = maxi(farthest,int(v))
	layout.stats.max_distance = farthest
	layout.stats.stairs_distance = int(reach.get(layout.stairs,0))
	if not theme.get("boss",false):
		var candidates: Array = rooms.filter(func(r): return r.kind == "plain" and not layout.encounters.any(func(e): return e.room == r.id))
		candidates.sort_custom(func(a,b): return int(reach.get(Vector2i(center(a)),0)) > int(reach.get(Vector2i(center(b)),0)))
		for room in candidates.slice(0,mini(candidates.size(),rng.randi_range(3,5))): layout.npc_rooms.append(room.id)
	return layout

## Minimal well-formed layout with every §7 key: all wall, nothing placed. Only
## used as the last resort of generate() so callers never receive {}.
static func empty_layout(theme: Dictionary, seed: int, depth: int) -> Dictionary:
	var size: int = theme.size
	var terrain: Array = []
	terrain.resize(size*size); terrain.fill("wall")
	return {"size":size,"seed":seed,"theme_id":theme.get("id",""),"depth":depth,"terrain":terrain,"rooms":[],"edges":[],
		"entry":Vector2i(-1,-1),"stairs":Vector2i(-1,-1),"features":{},"encounters":[],"npc_rooms":[],
		"stats":{"regenerations":MAX_REGENERATIONS,"stairs_distance":0,"max_distance":0}}

## Up to MAX_REGENERATIONS retries on seed+attempt; a failed scatter costs an
## attempt like a failed validation. The last attempt that produced anything is
## returned (with a pushed error) when none validates, and empty_layout() when
## not even one attempt produced rooms -- generate() never returns {}.
static func generate(theme: Dictionary, seed: int, depth: int) -> Dictionary:
	var last: Dictionary = {}
	for attempt in range(MAX_REGENERATIONS+1):
		var layout := attempt_layout(theme,seed+attempt,depth)
		if not layout.is_empty():
			layout.stats.regenerations = attempt
			layout.seed = seed
			last = layout
			if validate(layout,theme).is_empty(): return layout
	push_error("floor generator: no valid layout after %d regenerations (seed %d): %s" % [MAX_REGENERATIONS,seed,validate(last,theme) if not last.is_empty() else "no rooms"])
	return last if not last.is_empty() else empty_layout(theme,seed,depth)

## Empty string when the layout satisfies the spec; otherwise the first failure.
static func validate(layout: Dictionary, theme: Dictionary) -> String:
	if layout.is_empty(): return "empty layout"
	var size: int = layout.size
	var rooms: Array = layout.rooms
	if rooms.size() < theme.rooms.count[0] or rooms.size() > theme.rooms.count[1]: return "room count"
	for id in theme.templates.required:
		if room_index(rooms,id) < 0: return "missing template "+id
	if layout.entry.x < 0 or layout.stairs.x < 0: return "entry or stairs missing"
	var reach := reachable_from(layout.terrain,size,layout.entry)
	for room in rooms:
		for p in floor_cells(layout.terrain,size,room.rect):
			if not reach.has(p): return "room %d unreachable" % room.id
	for p in layout.features:
		var ok := reach.has(p)
		for d in DIRECTIONS8:
			if reach.has(p+d): ok = true
		if not ok: return "feature unreachable at %s" % p
		if not rooms.any(func(r): return r.rect.has_point(p)): return "feature in corridor at %s" % p
	if int(theme.corridor.get("width",1)) >= 2:
		for y in range(1,size-1):
			for x in range(1,size-1):
				var p := Vector2i(x,y)
				if layout.terrain[index_of(size,p)] == "wall" or rooms.any(func(r): return outer(r.rect).has_point(p)): continue
				var neighbor := false
				for d in DIRECTIONS4:
					var q: Vector2i = p+d
					if layout.terrain[index_of(size,q)] != "wall" and not rooms.any(func(r): return outer(r.rect).has_point(q)): neighbor = true
				if not neighbor:
					# A one-cell seam between two stamped room doors is a doorway,
					# not a traversable stretch of corridor that can be widened.
					var shell_neighbors := 0
					for d in DIRECTIONS4:
						if rooms.any(func(r): return outer(r.rect).has_point(p+d)): shell_neighbors += 1
					if shell_neighbors < 2: return "corridor width at %s" % p
	if layout.stats.stairs_distance < layout.stats.max_distance*60/100: return "stairs too close"
	# Reward counts: a floor whose plain rooms all sit on the spine cannot hold
	# the themed curios, so it is regenerated rather than shipped short.
	var tally: Dictionary = {}
	for p in layout.features:
		var f: Dictionary = layout.features[p]
		var key: String = f.kind+("/"+f.curio_id if f.kind == "curio" else "")
		tally[key] = int(tally.get(key,0))+1
	if int(tally.get("entry",0)) != 1 or int(tally.get("stairs",0)) != 1 or int(tally.get("altar",0)) != 1: return "entry, stairs and altar must be unique"
	if int(tally.get("camp",0)) != 1: return "camp marker count %d" % int(tally.get("camp",0))
	for id in theme.curios:
		var n: int = int(tally.get("curio/"+id.to_upper(),0))
		if n < theme.curios[id][0] or n > theme.curios[id][1]: return "%s count %d" % [id,n]
	var mandatory: Array = layout.encounters.filter(func(e): return e.mandatory)
	var optional: Array = layout.encounters.filter(func(e): return not e.mandatory)
	if mandatory.size() < (0 if theme.get("boss",false) else 2) or mandatory.size() > (3 if theme.get("boss",false) else 3): return "mandatory encounters %d" % mandatory.size()
	if optional.size() < 1 or optional.size() > 2: return "optional encounters %d" % optional.size()
	var blocked: Dictionary = {}
	for e in mandatory:
		blocked[e.room] = true
	if (mandatory.size() > 0 if theme.get("boss",false) else mandatory.size() > 1) and not graph_path(rooms,layout.edges,room_index(rooms,"entry_camp"),room_index(rooms,"boss_lair" if theme.get("boss",false) else "descent"),blocked).is_empty(): return "route skips mandatory encounters"
	var taken: Dictionary = {}
	for p in layout.features:
		taken[p] = true
	for e in layout.encounters:
		if not Encounters.valid(e.members,e.budget,int(theme.monsters.get("max_members",Encounters.MAX_MEMBERS))).is_empty(): return "encounter invalid: "+Encounters.valid(e.members,e.budget,int(theme.monsters.get("max_members",Encounters.MAX_MEMBERS)))
		for m in e.members:
			if taken.has(m.pos): return "overlap at %s" % m.pos
			taken[m.pos] = true
			for d in rooms[e.room].doors:
				if maxi(absi(m.pos.x-d.x),absi(m.pos.y-d.y)) < 3: return "member too close to door"
	var adj := adjacency(rooms,layout.edges)
	var leaves := 0
	for id in adj:
		if adj[id].size() == 1: leaves += 1
	if leaves < 2: return "fewer than two dead ends"
	if layout.edges.size() < rooms.size(): return "no loop"
	return ""
