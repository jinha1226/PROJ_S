extends RefCounted
## Procedural floor: DCSS layout_rooms variant (scatter rooms, MST + loops,
## noisy-Dijkstra corridors, ASCII vault templates) with DD-style room-bound
## encounters. Pure static functions; output contract in the spec §7.
const Templates = preload("res://expedition/floor_templates.gd")
const Encounters = preload("res://expedition/encounter_builder.gd")
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/floor_themes.json"))
const PLACE_TRIES := 200
const MAX_REGENERATIONS := 5
const ROOM_GAP := 2
const DIRECTIONS4 := [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]
const DIRECTIONS8 := [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN,Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]

static func theme(id: String) -> Dictionary:
	return content.get("themes",{}).get(id,{})

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
	elif template_id == "relic_vault": min_x = maxi(min_x,size*2/3)
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
	for edge in edges:
		var a: Dictionary = rooms[edge[0]]
		var b: Dictionary = rooms[edge[1]]
		var best_pair: Array = []
		var best_d := 1 << 30
		for ca in door_candidates(a):
			for cb in door_candidates(b):
				var d: int = absi(ca.x-cb.x)+absi(ca.y-cb.y)
				if d < best_d:
					best_d = d; best_pair = [ca,cb]
		if best_pair.is_empty(): continue
		var da: Vector2i = best_pair[0]
		var db: Vector2i = best_pair[1]
		var from: Vector2i = da+outward(a,da)
		var to: Vector2i = db+outward(b,db)
		var path := dig_path(terrain,size,from,to,protected,theme.corridor.wiggle,rng)
		if path.is_empty(): continue
		for p in [da,db]+path:
			if terrain[index_of(size,p)] == "wall": terrain[index_of(size,p)] = theme.palette.floor
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

## Same rule as Session.melee_reach: diagonal steps need both orthogonal
## neighbours open.
static func reachable_from(terrain: Array, size: int, origin: Vector2i) -> Dictionary:
	var dist: Dictionary = {origin:0}
	var queue: Array = [origin]
	var cursor := 0
	while cursor < queue.size():
		var p: Vector2i = queue[cursor]; cursor += 1
		for d in DIRECTIONS8:
			var next: Vector2i = p+d
			if dist.has(next) or not inside(size,next) or terrain[index_of(size,next)] == "wall": continue
			if d.x != 0 and d.y != 0 and (terrain[index_of(size,Vector2i(p.x,next.y))] == "wall" or terrain[index_of(size,Vector2i(next.x,p.y))] == "wall"): continue
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
