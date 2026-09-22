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
