class_name MovementSystem
extends RefCounted

const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const TraversalAssessmentScript = preload("res://sim/traversal_assessment.gd")

var world


func _init(p_world) -> void:
	world = p_world


func assess_move(actor_id: int, destination: Vector2i):
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
	if not actor.is_alive():
		base["reason"] = "actor_dead"
		return TraversalAssessmentScript.new(base)
	var delta: Vector2i = destination - actor.position
	if absi(delta.x) + absi(delta.y) != 1:
		base["reason"] = "move_not_cardinal_adjacent"
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
	var blockers: Array[int] = []
	for entity in world.entities_at(destination):
		if entity.id != actor_id:
			blockers.append(entity.id)
	blockers.sort()
	base["blocking_entity_ids"] = blockers
	if not blockers.is_empty():
		base["reason"] = "move_destination_occupied"
		return TraversalAssessmentScript.new(base)
	base["accepted"] = true
	base["reason"] = "ok"
	return TraversalAssessmentScript.new(base)


func commit_move(actor_id: int, destination: Vector2i, move_time_cost: int):
	var assessment = assess_move(actor_id, destination)
	assert(assessment.accepted, "Only a freshly validated MOVE can be committed")
	var actor = world.entities[actor_id]
	var from_position: Vector2i = actor.position
	var event = world.emit_event(
		"action.move", actor_id, -1, destination, move_time_cost, -1,
		{
			"from_position": [from_position.x, from_position.y],
			"to_position": [destination.x, destination.y],
			"terrain_id": assessment.terrain_id,
			"move_time_cost": move_time_cost,
		})
	assert(event != null, "Validated MOVE event emission must succeed")
	actor.position = destination
	return event
