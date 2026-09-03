class_name WeightedPathfinder
extends RefCounted

const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const MovementSystemScript = preload("res://sim/systems/movement_system.gd")

var world
var movement


func _init(p_world, p_movement = null) -> void:
	world = p_world
	movement = p_movement if p_movement != null else MovementSystemScript.new(world)


func find_path(actor_id: int, goal: Vector2i, occupancy_projection: Dictionary = {}) -> Dictionary:
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

	var open: Array[Dictionary] = [{"position": start, "cost": 0, "steps": 0, "sequence": 0}]
	var sequence := 1
	var best: Dictionary = {_key(start): [0, 0]}
	var previous: Dictionary = {}
	while not open.is_empty():
		open.sort_custom(_open_less)
		var node: Dictionary = open.pop_front()
		var position: Vector2i = node["position"]
		var known: Array = best.get(_key(position), [])
		if known.is_empty() or int(node["cost"]) != int(known[0]) or int(node["steps"]) != int(known[1]):
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
			var next_key := _key(next)
			var old: Array = best.get(next_key, [])
			if not old.is_empty() and (next_cost > int(old[0]) or (next_cost == int(old[0]) and next_steps >= int(old[1]))):
				continue
			best[next_key] = [next_cost, next_steps]
			previous[next_key] = position
			open.append({"position": next, "cost": next_cost, "steps": next_steps, "sequence": sequence})
			sequence += 1
	return _failure("path_unreachable")


func find_path_to_any(actor_id: int, goals: Array, occupancy_projection: Dictionary = {}) -> Dictionary:
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
	var open: Array[Dictionary] = [{"position":start,"cost":0,"steps":0,"sequence":0}]
	var sequence := 1
	var best: Dictionary = {_key(start):[0,0]}
	var previous: Dictionary = {}
	while not open.is_empty():
		open.sort_custom(_open_less)
		var node: Dictionary = open.pop_front(); var position: Vector2i = node.position
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
			open.append({"position":next,"cost":next_cost,"steps":next_steps,"sequence":sequence}); sequence += 1
	return _failure("path_unreachable")


func _can_step(actor_id: int, from: Vector2i, to: Vector2i, projection: Dictionary) -> bool:
	if not world.in_bounds(to):
		return false
	var definition: Dictionary = TerrainRegistryScript.definition_view(world.tile_at(to).terrain)
	if definition.is_empty() or not bool(definition.get("passable", false)) or _occupant(to, actor_id, projection) != -1:
		return false
	var delta := to - from
	if delta.x != 0 and delta.y != 0:
		if not world.diagonal_step_terrain_allowed(from, to):
			return false
	return true


func _occupant(position: Vector2i, actor_id: int, projection: Dictionary) -> int:
	if not projection.is_empty():
		var value: Variant = projection.get(_key(position), -1)
		return int(value) if value is int and int(value) != actor_id else -1
	var blocker = world.blocking_entity_at(position, actor_id)
	return blocker.id if blocker != null else -1


func _open_less(a: Dictionary, b: Dictionary) -> bool:
	for key in ["cost", "steps"]:
		if int(a[key]) != int(b[key]):
			return int(a[key]) < int(b[key])
	var ap: Vector2i = a["position"]
	var bp: Vector2i = b["position"]
	if ap.y != bp.y:
		return ap.y < bp.y
	if ap.x != bp.x:
		return ap.x < bp.x
	return int(a["sequence"]) < int(b["sequence"])


func _failure(reason: String) -> Dictionary:
	return {"found": false, "reason": reason, "path": [], "total_cost": -1, "steps": 0}


func _key(position: Vector2i) -> String:
	return "%d:%d" % [position.x, position.y]
