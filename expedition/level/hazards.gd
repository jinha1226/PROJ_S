extends RefCounted
## Zone hazards (spec §1). Three terrains keep themselves hot or soaked each
## environment tick; three tile flags (gas, collapse, fog) are placed by the
## generator and copied onto the tiles when a floor is applied.
const TERRAINS := ["lava","deep_water","bog"]
const WATERY := ["water","deep_water","bog"]
const COLLAPSE_RANGE := 2
const COLLAPSE_DAMAGE := 12
const GAS_RADIUS := 2
const GAS_DAMAGE := 16
const GAS_FIRE := 40
const BOG_POISON_TICKS := 300
const FOG_SIGHT_PENALTY := 3.0
const FOG_MIN_SIGHT := 1.5
const FOG_RADIUS := 2
## Separate from the layout generator so packs never shift with hazards.
const RNG_SALT := 0x48415A
const OVERLAY := {"lava":Color(1.0,0.35,0.05,0.55),"deep_water":Color(0.05,0.2,0.5,0.45),"bog":Color(0.3,0.45,0.1,0.5)}
const FOG_COLOR := Color(0.75,0.78,0.85,0.35)
const GAS_COLOR := Color(0.55,0.8,0.2,0.8)
const COLLAPSE_IDLE := Color(0.6,0.5,0.35,0.7)
const COLLAPSE_ARMED := Color("f37575")

static func initial(terrain: String) -> Dictionary:
	match terrain:
		"lava": return {"fire":100,"wet":0}
		"deep_water", "bog": return {"fire":0,"wet":100}
		"water": return {"fire":0,"wet":70}
	return {"fire":0,"wet":0}

## The floor's hazard flags: the templates' own glyphs first, then the theme's
## counts drawn on a generator of their own. Writes `layout.hazards`.
static func place(layout: Dictionary, theme: Dictionary) -> void:
	var hazards: Dictionary = {}
	for room in layout.rooms:
		if room.kind != "template": continue
		var marks: Dictionary = room.parsed.get("hazards",{})
		for p in marks: hazards[room.rect.position-Vector2i.ONE+p] = (marks[p] as Dictionary).duplicate()
	var counts: Dictionary = theme.get("hazards",{})
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout.seed)+RNG_SALT
	if counts.has("collapse"):
		var rooms: Array = layout.rooms.filter(func(r): return r.kind == "plain")
		scatter(layout,hazards,rooms,rng,counts.collapse,func(p): return fully_open(layout,p),func(p): hazards[p] = {"collapse":{"armed":false,"at":0}})
	if counts.has("gas"):
		var rooms: Array = layout.rooms.filter(func(r): return r.kind in ["plain","fight"])
		scatter(layout,hazards,rooms,rng,counts.gas,func(_p): return true,func(p): hazards[p] = {"gas":true})
	if counts.has("fog"):
		var rooms: Array = layout.rooms.filter(func(r): return r.kind in ["plain","fight"])
		scatter(layout,hazards,rooms,rng,counts.fog,func(_p): return true,func(p): blanket(layout,hazards,p))
	layout.hazards = hazards

## `range` hazards in randomly drawn rooms, each on a cell `allowed` accepts.
static func scatter(layout: Dictionary, hazards: Dictionary, rooms: Array, rng: RandomNumberGenerator, range: Array, allowed: Callable, put: Callable) -> void:
	if rooms.is_empty(): return
	var wanted: int = rng.randi_range(int(range[0]),int(range[1]))
	var guard := 0
	var placed := 0
	while placed < wanted and guard < 60:
		guard += 1
		var room: Dictionary = rooms[rng.randi_range(0,rooms.size()-1)]
		var cells: Array = open_cells(layout,room).filter(func(p): return not hazards.has(p) and allowed.call(p))
		if cells.is_empty(): continue
		put.call(cells[rng.randi_range(0,cells.size()-1)])
		placed += 1

## Ordinary floor in the room: no wall, no hazard terrain, no water, no
## feature, and more than one cell from every door.
static func open_cells(layout: Dictionary, room: Dictionary) -> Array:
	var result: Array = []
	for y in range(room.rect.position.y,room.rect.end.y):
		for x in range(room.rect.position.x,room.rect.end.x):
			var p := Vector2i(x,y)
			var terrain: String = layout.terrain[y*layout.size+x]
			if terrain == "wall" or terrain in TERRAINS or terrain in WATERY or layout.features.has(p): continue
			if room.doors.any(func(d): return maxi(absi(p.x-d.x),absi(p.y-d.y)) <= 1): continue
			result.append(p)
	return result

## Eight open neighbours: a single fallen block here can never cut a room.
static func fully_open(layout: Dictionary, p: Vector2i) -> bool:
	for dy in [-1,0,1]:
		for dx in [-1,0,1]:
			var q: Vector2i = p+Vector2i(dx,dy)
			if q.x < 0 or q.y < 0 or q.x >= layout.size or q.y >= layout.size: return false
			if layout.terrain[q.y*layout.size+q.x] == "wall": return false
	return true

## A bank of fog: every open cell within FOG_RADIUS of the centre.
static func blanket(layout: Dictionary, hazards: Dictionary, centre: Vector2i) -> void:
	for dy in range(-FOG_RADIUS,FOG_RADIUS+1):
		for dx in range(-FOG_RADIUS,FOG_RADIUS+1):
			var p: Vector2i = centre+Vector2i(dx,dy)
			if p.x < 0 or p.y < 0 or p.x >= layout.size or p.y >= layout.size: continue
			if layout.terrain[p.y*layout.size+p.x] == "wall": continue
			var mark: Dictionary = hazards.get(p,{})
			mark["fog"] = true
			hazards[p] = mark

## One environment tick of one tile, before the fire and wetness pass.
static func tick_cell(s, point: Vector2i, cell: Dictionary) -> void:
	match str(cell.terrain):
		"lava": cell.fire = 100
		"deep_water": cell.wet = 100
		"bog":
			cell.wet = 100
			var standing: Dictionary = s.at(point)
			if not standing.is_empty(): s.Statuses.apply(s,standing,"poison",BOG_POISON_TICKS)
	if bool(cell.get("gas",false)) and int(cell.fire) > 0: explode(s,point)
	if cell.has("collapse"): collapse_tick(s,point,cell)

static func explode(s, origin: Vector2i) -> void:
	s.tile(origin).erase("gas")
	s.message("가스 폭발")
	for y in range(origin.y-GAS_RADIUS,origin.y+GAS_RADIUS+1):
		for x in range(origin.x-GAS_RADIUS,origin.x+GAS_RADIUS+1):
			var p := Vector2i(x,y)
			if not s.inside(p) or s.tile(p).terrain == "wall": continue
			var victim: Dictionary = s.at(p)
			if not victim.is_empty(): s.damage(victim,GAS_DAMAGE,999,"FIRE")
			if s.tile(p).terrain not in WATERY: s.tile(p).fire = mini(100,int(s.tile(p).fire)+GAS_FIRE)

static func collapse_tick(s, point: Vector2i, cell: Dictionary) -> void:
	var state: Dictionary = cell.collapse
	if not bool(state.get("armed",false)):
		if s.alive().any(func(a): return maxi(absi(a.pos.x-point.x),absi(a.pos.y-point.y)) <= COLLAPSE_RANGE):
			state.armed = true; state.at = int(s.time)+100
			s.message("천장이 흔들린다")
		return
	if int(s.time) < int(state.at): return
	var victim: Dictionary = s.at(point)
	if not victim.is_empty(): s.damage(victim,COLLAPSE_DAMAGE,999,"IMPACT")
	cell.erase("collapse")
	cell.terrain = "wall" if s.at(point).is_empty() else "rubble"

## The sight radius of `actor`: three less while standing in fog.
static func sight_radius(s, actor: Dictionary, base: float) -> float:
	if actor.is_empty() or not s.inside(actor.pos): return base
	if bool(s.tile(actor.pos).get("fog",false)): return maxf(FOG_MIN_SIGHT,base-FOG_SIGHT_PENALTY)
	return base

## The wash a hazard terrain lays over its floor texture.
static func overlay(cell: Dictionary) -> Color:
	return OVERLAY.get(str(cell.terrain),Color(0,0,0,0))
