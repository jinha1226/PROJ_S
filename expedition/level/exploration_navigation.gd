extends RefCounted
## Fog planner from ../playtest; retained suffix follows party_auto_explore.
const Search = preload("res://expedition/legacy/fog_frontier_search.gd")
var destination := Vector2i(-1,-1)
var automatic := false
var active := false
var exhausted: Dictionary = {}
var planned_path: Array = []
var plan_builds := 0
var last_search_expanded := 0

func stop() -> void:
	active = false; automatic = false; destination = Vector2i(-1,-1)
	exhausted.clear(); planned_path.clear()

func traversable(s, a: Vector2i, b: Vector2i) -> bool:
	if not s.floor_state.explored.has(b) or not s.inside(b) or s.tile(b).terrain == "wall": return false
	# Never inspect hidden actors or hazards while planning remembered ground.
	if s.floor_state.visible.has(b) and (not s.is_free(b) or s.tile(b).fire > 0 or s.Tactics.danger(s,b) > 0): return false
	if not s.walk_reach(a,b): return false
	return true

func route(s, target: Vector2i) -> Array:
	if not s.inside(target) or not s.floor_state.explored.has(target): return []
	plan_builds += 1
	var result: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,s.party[s.selected].pos,[target],func(a,b): return traversable(s,a,b),func(_p): return 100)
	return result.path if result.found else []

func start(s, target: Vector2i) -> bool:
	stop(); plan_builds = 0
	if s.phase != "EXPLORE" or not s.party_enemies().is_empty(): return false
	planned_path = route(s,target)
	if planned_path.size() < 2: return false
	destination = target; active = true; return true

func explore(s) -> bool:
	stop(); plan_builds = 0
	if s.phase != "EXPLORE" or not s.party_enemies().is_empty() or s.party.any(func(a): return s.Downed.is_downed(a)): return false
	automatic = true; active = true; return true

func frontier_path(s) -> Array:
	var cells: Dictionary = {}
	for p in s.floor_state.explored:
		var live: bool = s.floor_state.visible.has(p)
		cells["%d:%d" % [p.x,p.y]] = {"passable":s.tile(p).terrain != "wall","occupied":live and not s.at(p).is_empty(),"risk":s.tile(p).fire if live else 0,"move_time_cost":100,"visibility_state":"VISIBLE" if live else "MEMORY"}
	var search = Search.new(); plan_builds += 1
	var result: Dictionary = search.search({"width":s.BOARD_SIDE,"height":s.BOARD_SIDE},cells,s.party[s.selected].pos,exhausted)
	last_search_expanded = search.expanded
	if not result.get("found",false): return []
	destination = result.target; return result.path

func next_step(s) -> Vector2i:
	if not active: return Vector2i(-1,-1)
	if automatic and s.party.any(func(a): return s.Downed.is_downed(a)): stop(); return Vector2i(-1,-1)
	if s.phase != "EXPLORE" or not s.party_enemies().is_empty(): stop(); return Vector2i(-1,-1)
	var current: Vector2i = s.party[s.selected].pos
	exhausted["%d:%d" % [current.x,current.y]] = true
	if planned_path.size() > 1 and planned_path[1] == current: planned_path.pop_front()
	if planned_path.size() < 2:
		if automatic: planned_path = frontier_path(s)
		else: stop(); return Vector2i(-1,-1)
	if planned_path.size() < 2 or planned_path[0] != current: stop(); return Vector2i(-1,-1)
	var next: Vector2i = planned_path[1]
	# Validate only the immediate hop; don't rebuild A* and all fog cells per turn.
	if not s.floor_state.visible.has(next) or not traversable(s,current,next) or not s.can_step(current,next): stop(); return Vector2i(-1,-1)
	return next
