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

	return _search(actor_id,start,[goal],occupancy_projection)


func find_path_to_any(actor_id: int, goals: Array, occupancy_projection: Dictionary = {}, maximum_steps:int=-1) -> Dictionary:
	var started:=preload("res://sim/perf_probe.gd").begin()
	_cell_cache.clear();_occupant_cache.clear()
	_search_active=true
	var result:=_find_path_to_any(actor_id,goals,occupancy_projection,maximum_steps)
	_search_active=false
	preload("res://sim/perf_probe.gd").end("path.multigoal",started)
	return result

func _find_path_to_any(actor_id: int, goals: Array, occupancy_projection: Dictionary = {}, maximum_steps:int=-1) -> Dictionary:
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
	return _search(actor_id,start,goal_set.values(),occupancy_projection,maximum_steps)

func _search(actor_id:int,start:Vector2i,goals:Array,projection:Dictionary,maximum_steps:int=-1)->Dictionary:
	return preload("res://sim/turn_engine.gd").path(world.width,world.height,start,goals,
		func(from:Vector2i,to:Vector2i)->bool:return _can_step(actor_id,from,to,projection),
		func(point:Vector2i)->int:return int(_cell_definition(point).move_time_cost),MIN_PASSABLE_MOVE_COST,maximum_steps)


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


func _failure(reason: String) -> Dictionary:
	return {"found": false, "reason": reason, "path": [], "total_cost": -1, "steps": 0}


func _key(position: Vector2i) -> String:
	return "%d:%d" % [position.x, position.y]
