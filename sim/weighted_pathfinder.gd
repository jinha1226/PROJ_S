class_name WeightedPathfinder
extends RefCounted

const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const MovementSystemScript = preload("res://sim/systems/movement_system.gd")
const MIN_PASSABLE_MOVE_COST := 100

var world
var movement
var _cell_cache:Dictionary={}
var _occupant_cache:Dictionary={}
var _search_active:=false


func _init(p_world, p_movement = null) -> void:
	world = p_world
	movement = p_movement if p_movement != null else MovementSystemScript.new(world)


func find_path(actor_id: int, goal: Vector2i, occupancy_projection: Dictionary = {}) -> Dictionary:
	var started:=preload("res://sim/perf_probe.gd").begin()
	_cell_cache.clear();_occupant_cache.clear()
	_search_active=true
	var result:=_find_path(actor_id,goal,occupancy_projection)
	_search_active=false
	preload("res://sim/perf_probe.gd").end("path.single",started)
	return result

func _find_path(actor_id: int, goal: Vector2i, occupancy_projection: Dictionary = {}) -> Dictionary:
	if not world.entities.has(actor_id) or not world.can_act(actor_id, world.world_time):
		return _failure("actor_not_found")
	if not world.in_bounds(goal):
		return _failure("out_of_bounds")
	var start: Vector2i = world.entities[actor_id].position
	if start == goal:
		return {"found": true, "reason": "already_there", "path": [start], "total_cost": 0, "steps": 0}
	var goal_blocker := _occupant(goal, actor_id, occupancy_projection)
	if goal_blocker != -1:
		return _failure("occupied")
	var goal_def: Dictionary = TerrainRegistryScript.definition_view(world.tile_at(goal).terrain)
	if goal_def.is_empty() or not bool(goal_def.get("passable", false)):
		return _failure("path_unreachable")

	var open: Array[Dictionary] = [{"position": start, "cost": 0, "steps": 0,
		"priority":_path_priority(0,start,goal),"sequence": 0,"drift":0}]
	var sequence := 1
	# Eight-direction movement leaves many equal-cost paths (a V of diagonals
	# then a straight run is as cheap as a straight-looking line). Tie-break on
	# distance from the start->goal line so equal-cost routes hug that line.
	var best: Dictionary = {_key(start): [0, 0, 0]}
	var previous: Dictionary = {}
	while not open.is_empty():
		var node: Dictionary = _heap_pop(open)
		var position: Vector2i = node["position"]
		var known: Array = best.get(_key(position), [])
		if known.is_empty() or int(node["cost"]) != int(known[0]) or int(node["steps"]) != int(known[1]) \
				or (known.size() > 2 and int(node.get("drift", 0)) != int(known[2])):
			continue
		if position == goal:
			var path: Array[Vector2i] = [goal]
			var cursor := goal
			while cursor != start:
				cursor = previous[_key(cursor)]
				path.push_front(cursor)
			return {"found": true, "reason": "ok", "path": path,
				"total_cost": int(node["cost"]), "steps": int(node["steps"])}
		for direction in MovementSystemScript.MOVE_DIRECTIONS_8:
			var next: Vector2i = position + direction
			if not _can_step(actor_id, position, next, occupancy_projection):
				continue
			var definition: Dictionary = TerrainRegistryScript.definition_view(world.tile_at(next).terrain)
			var next_cost: int = int(node["cost"]) + int(definition["move_time_cost"])
			var next_steps: int = int(node["steps"]) + 1
			var next_drift: int = int(node["drift"]) + _line_drift(start, goal, next)
			var next_key := _key(next)
			var old: Array = best.get(next_key, [])
			if not old.is_empty() and (next_cost > int(old[0]) \
					or (next_cost == int(old[0]) and next_steps > int(old[1])) \
					or (next_cost == int(old[0]) and next_steps == int(old[1]) and next_drift >= int(old[2]))):
				continue
			best[next_key] = [next_cost, next_steps, next_drift]
			previous[next_key] = position
			_heap_push(open,{"position": next, "cost": next_cost,
				"priority":_path_priority(next_cost,next,goal),
				"steps": next_steps, "sequence": sequence, "drift": next_drift})
			sequence += 1
	return _failure("path_unreachable")


func find_path_to_any(actor_id: int, goals: Array, occupancy_projection: Dictionary = {}) -> Dictionary:
	var started:=preload("res://sim/perf_probe.gd").begin()
	_cell_cache.clear();_occupant_cache.clear()
	_search_active=true
	var result:=_find_path_to_any(actor_id,goals,occupancy_projection)
	_search_active=false
	preload("res://sim/perf_probe.gd").end("path.multigoal",started)
	return result

func _find_path_to_any(actor_id: int, goals: Array, occupancy_projection: Dictionary = {}) -> Dictionary:
	if not world.entities.has(actor_id) or not world.can_act(actor_id, world.world_time):
		return _failure("actor_not_found")
	var start: Vector2i = world.entities[actor_id].position
	var goal_set: Dictionary = {}
	for value in goals:
		if not value is Vector2i: continue
		var goal: Vector2i = value
		if not world.in_bounds(goal): continue
		var definition: Dictionary = TerrainRegistryScript.definition_view(world.tile_at(goal).terrain)
		if definition.is_empty() or not bool(definition.get("passable", false)) \
				or _occupant(goal, actor_id, occupancy_projection) != -1: continue
		goal_set[_key(goal)] = goal
	if goal_set.is_empty(): return _failure("path_unreachable")
	if goal_set.has(_key(start)):
		return {"found":true,"reason":"already_there","path":[start],"total_cost":0,"steps":0,"goal":start}
	var goals_for_heuristic:Array=goal_set.values()
	var open: Array[Dictionary] = [{"position":start,"cost":0,"steps":0,
		"priority":_path_to_any_priority(0,start,goals_for_heuristic),"sequence":0}]
	var sequence := 1
	var best: Dictionary = {_key(start):[0,0]}
	var previous: Dictionary = {}
	while not open.is_empty():
		var node: Dictionary = _heap_pop(open); var position: Vector2i = node.position
		var known: Array = best.get(_key(position), [])
		if known.is_empty() or int(node.cost) != int(known[0]) or int(node.steps) != int(known[1]): continue
		if goal_set.has(_key(position)):
			var path: Array[Vector2i] = [position]; var cursor := position
			while cursor != start:
				cursor = previous[_key(cursor)]; path.push_front(cursor)
			return {"found":true,"reason":"ok","path":path,"total_cost":int(node.cost),
				"steps":int(node.steps),"goal":position}
		for direction in MovementSystemScript.MOVE_DIRECTIONS_8:
			var next: Vector2i = position + direction
			if not _can_step(actor_id, position, next, occupancy_projection): continue
			var definition: Dictionary = TerrainRegistryScript.definition_view(world.tile_at(next).terrain)
			var next_cost: int = int(node.cost) + int(definition.move_time_cost)
			var next_steps: int = int(node.steps) + 1; var next_key := _key(next)
			var old: Array = best.get(next_key, [])
			if not old.is_empty() and (next_cost > int(old[0]) or (next_cost == int(old[0]) and next_steps >= int(old[1]))): continue
			best[next_key] = [next_cost,next_steps]; previous[next_key] = position
			_heap_push(open,{"position":next,"cost":next_cost,"steps":next_steps,
				"priority":_path_to_any_priority(next_cost,next,goals_for_heuristic),
				"sequence":sequence}); sequence += 1
	return _failure("path_unreachable")


func _can_step(actor_id: int, from: Vector2i, to: Vector2i, projection: Dictionary) -> bool:
	if not world.in_bounds(to):
		return false
	var definition: Dictionary = _cell_definition(to)
	if definition.is_empty() or not bool(definition.get("passable", false)) or _occupant(to, actor_id, projection) != -1:
		return false
	var delta := to - from
	if delta.x != 0 and delta.y != 0:
		if not world.diagonal_step_terrain_allowed(from, to):
			return false
		if not movement.allows_occupied_diagonal_flanks(actor_id):
			for flank in [from + Vector2i(delta.x, 0), from + Vector2i(0, delta.y)]:
				if not world.in_bounds(flank):
					continue
				var flank_def: Dictionary = _cell_definition(flank)
				if flank_def.is_empty() or not bool(flank_def.get("passable", false)):
					continue
				if _occupant(flank, actor_id, projection) != -1:return false
	return true


func _occupant(position: Vector2i, actor_id: int, projection: Dictionary) -> int:
	# Search is synchronous: occupancy is immutable until this call returns.
	# Many parents inspect the same cell and diagonal flanks repeatedly.
	if _search_active and _occupant_cache.has(position):return int(_occupant_cache[position])
	var occupant:=-1
	if not projection.is_empty():
		var value: Variant = projection.get(_key(position), -1)
		occupant=int(value) if value is int and int(value) != actor_id else -1
	else:
		var blocker = world.blocking_entity_at(position, actor_id)
		occupant=blocker.id if blocker != null else -1
	if _search_active:_occupant_cache[position]=occupant
	return occupant

func _cell_definition(position:Vector2i)->Dictionary:
	if not _search_active:return TerrainRegistryScript.definition_view(world.tile_at(position).terrain)
	if not _cell_cache.has(position):
		_cell_cache[position]=TerrainRegistryScript.definition_view(world.tile_at(position).terrain)
	return _cell_cache[position]


func _line_drift(start: Vector2i, goal: Vector2i, position: Vector2i) -> int:
	# Twice the area of the (start, goal, position) triangle: zero on the exact
	# start->goal line, growing with perpendicular distance. Integer and exact.
	var line := goal - start
	var offset := position - start
	return absi(line.x * offset.y - line.y * offset.x)

func _open_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("priority",a["cost"]))!=int(b.get("priority",b["cost"])):
		return int(a.get("priority",a["cost"]))<int(b.get("priority",b["cost"]))
	for key in ["cost", "steps"]:
		if int(a[key]) != int(b[key]):
			return int(a[key]) < int(b[key])
	if int(a.get("drift",0)) != int(b.get("drift",0)):
		return int(a.get("drift",0)) < int(b.get("drift",0))
	var ap: Vector2i = a["position"]
	var bp: Vector2i = b["position"]
	if ap.y != bp.y:
		return ap.y < bp.y
	if ap.x != bp.x:
		return ap.x < bp.x
	return int(a["sequence"]) < int(b["sequence"])


func _path_priority(cost:int,position:Vector2i,goal:Vector2i)->int:
	return cost+maxi(absi(goal.x-position.x),absi(goal.y-position.y)) \
		*MIN_PASSABLE_MOVE_COST


func _path_to_any_priority(cost:int,position:Vector2i,goals:Array)->int:
	var distance:=2147483647
	for goal_value in goals:
		var goal:Vector2i=goal_value
		distance=mini(distance,maxi(absi(goal.x-position.x),absi(goal.y-position.y)))
	return cost+distance*MIN_PASSABLE_MOVE_COST


func _heap_push(heap:Array,node:Dictionary)->void:
	# Maintain the A* open set with logarithmic insertion instead of sorting every
	# discovered node after each expansion.
	heap.append(node)
	var index:=heap.size()-1
	while index>0:
		var parent:=int((index-1)/2)
		if not _open_less(heap[index],heap[parent]):break
		var swap:Variant=heap[parent]
		heap[parent]=heap[index]
		heap[index]=swap
		index=parent


func _heap_pop(heap:Array)->Dictionary:
	var first:Dictionary=heap[0]
	var tail:Variant=heap.pop_back()
	if heap.is_empty():return first
	heap[0]=tail
	var index:=0
	while true:
		var left:=index*2+1
		if left>=heap.size():break
		var right:=left+1
		var smallest:=right if right<heap.size() \
			and _open_less(heap[right],heap[left]) else left
		if not _open_less(heap[smallest],heap[index]):break
		var swap:Variant=heap[index]
		heap[index]=heap[smallest]
		heap[smallest]=swap
		index=smallest
	return first


func _failure(reason: String) -> Dictionary:
	return {"found": false, "reason": reason, "path": [], "total_cost": -1, "steps": 0}


func _key(position: Vector2i) -> String:
	return "%d:%d" % [position.x, position.y]
