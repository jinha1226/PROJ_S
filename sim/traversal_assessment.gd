class_name TraversalAssessment
extends RefCounted

var accepted: bool
var reason: String
var actor_id: int
var from_position: Vector2i
var to_position: Vector2i
var terrain_id: String
var blocking_entity_ids: Array[int]
var sampled_world_time: int


func _init(data: Dictionary = {}) -> void:
	accepted = bool(data.get("accepted", false))
	reason = str(data.get("reason", ""))
	actor_id = int(data.get("actor_id", -1))
	from_position = data.get("from_position", Vector2i(-1, -1))
	to_position = data.get("to_position", Vector2i(-1, -1))
	terrain_id = str(data.get("terrain_id", ""))
	blocking_entity_ids = []
	for value in data.get("blocking_entity_ids", []):
		blocking_entity_ids.append(int(value))
	blocking_entity_ids.sort()
	sampled_world_time = int(data.get("sampled_world_time", 0))


func to_dict() -> Dictionary:
	return {
		"accepted": accepted, "reason": reason, "actor_id": actor_id,
		"from_position": [from_position.x, from_position.y],
		"to_position": [to_position.x, to_position.y], "terrain_id": terrain_id,
		"blocking_entity_ids": blocking_entity_ids.duplicate(),
		"sampled_world_time": sampled_world_time,
	}
