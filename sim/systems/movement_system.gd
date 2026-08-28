class_name MovementSystem
extends RefCounted

const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const TraversalAssessmentScript = preload("res://sim/traversal_assessment.gd")

const MOVE_DIRECTIONS_8: Array[Vector2i] = [
	Vector2i.UP, Vector2i(1, -1), Vector2i.RIGHT, Vector2i(1, 1),
	Vector2i.DOWN, Vector2i(-1, 1), Vector2i.LEFT, Vector2i(-1, -1),
]

var world


func _init(p_world) -> void:
	world = p_world


func assess_move(actor_id: int, destination: Vector2i):
	return assess_move_in_projection(actor_id, destination, {})


func assess_move_in_projection(actor_id: int, destination: Vector2i,
		occupancy_projection: Dictionary):
	var base := {
		"accepted": false, "reason": "", "actor_id": actor_id,
		"from_position": Vector2i(-1, -1), "to_position": destination,
		"terrain_id": "", "blocking_entity_ids": [],
		"sampled_world_time": world.world_time,
	}
	if actor_id < 1:
		base["reason"] = "move_requires_actor"
		return TraversalAssessmentScript.new(base)
	if not world.entities.has(actor_id):
		base["reason"] = "actor_not_found"
		return TraversalAssessmentScript.new(base)
	var actor = world.entities[actor_id]
	base["from_position"] = actor.position
	if not world.can_act(actor_id, world.world_time):
		base["reason"] = "actor_dead"
		return TraversalAssessmentScript.new(base)
	var delta: Vector2i = destination - actor.position
	if delta == Vector2i.ZERO or maxi(absi(delta.x), absi(delta.y)) != 1:
		base["reason"] = "move_not_adjacent"
		return TraversalAssessmentScript.new(base)
	if not world.in_bounds(destination):
		base["reason"] = "move_out_of_bounds"
		return TraversalAssessmentScript.new(base)
	var terrain_id: String = world.tile_at(destination).terrain
	base["terrain_id"] = terrain_id
	var definition: Dictionary = TerrainRegistryScript.definition(terrain_id)
	if definition.is_empty() or not bool(definition["passable"]) \
			or int(definition["occupancy_capacity"]) < 1 \
			or int(definition["move_time_cost"]) < 1 \
			or int(definition["move_time_cost"]) > 10000:
		base["reason"] = "move_terrain_blocked"
		return TraversalAssessmentScript.new(base)
	var blockers: Array[int] = _blockers_at(destination, actor_id, occupancy_projection)
	blockers.sort()
	base["blocking_entity_ids"] = blockers
	if not blockers.is_empty():
		base["reason"] = "move_destination_occupied"
		return TraversalAssessmentScript.new(base)
	if delta.x != 0 and delta.y != 0:
		for flank in [actor.position + Vector2i(delta.x, 0), actor.position + Vector2i(0, delta.y)]:
			if not _terrain_passable(flank):
				base["reason"] = "move_diagonal_flank_blocked"
				return TraversalAssessmentScript.new(base)
			var flank_blockers := _blockers_at(flank, actor_id, occupancy_projection)
			if not flank_blockers.is_empty():
				base["blocking_entity_ids"] = flank_blockers
				base["reason"] = "move_diagonal_flank_occupied"
				return TraversalAssessmentScript.new(base)
	base["accepted"] = true
	base["reason"] = "ok"
	return TraversalAssessmentScript.new(base)


func _terrain_passable(position: Vector2i) -> bool:
	if not world.in_bounds(position):
		return false
	var definition: Dictionary = TerrainRegistryScript.definition(world.tile_at(position).terrain)
	return not definition.is_empty() and bool(definition.get("passable", false)) \
		and int(definition.get("occupancy_capacity", 0)) > 0


func _blockers_at(position: Vector2i, actor_id: int, projection: Dictionary) -> Array[int]:
	var blockers: Array[int] = []
	if not projection.is_empty():
		var key := "%d:%d" % [position.x, position.y]
		var value: Variant = projection.get(key, -1)
		if value is int and int(value) > 0 and int(value) != actor_id:
			blockers.append(int(value))
	else:
		for entity in world.occupying_entities_at(position):
			if entity.id != actor_id:
				blockers.append(entity.id)
	blockers.sort()
	return blockers


func commit_move(actor_id: int, destination: Vector2i, move_time_cost: int, cause_id: int = -1):
	var assessment = assess_move(actor_id, destination)
	assert(assessment.accepted, "Only a freshly validated MOVE can be committed")
	return commit_preflighted_move(actor_id, destination, assessment.terrain_id, move_time_cost, cause_id)


func commit_preflighted_move(actor_id: int, destination: Vector2i, terrain_id: String,
		move_time_cost: int, cause_id: int = -1):
	var actor = world.entities[actor_id]
	var from_position: Vector2i = actor.position
	var event = world.emit_event(
		"action.move", actor_id, -1, destination, move_time_cost, cause_id,
		{
			"from_position": [from_position.x, from_position.y],
			"to_position": [destination.x, destination.y],
			"terrain_id": terrain_id,
			"move_time_cost": move_time_cost,
		})
	if event == null:
		return null
	actor.position = destination
	return event
