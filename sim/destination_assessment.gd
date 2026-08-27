class_name DestinationAssessment
extends RefCounted

var traversal
var sample
var affinity
var evaluation
var move_time_cost: int
var speed_tier: String


func _init(data: Dictionary = {}) -> void:
	traversal = data.get("traversal")
	sample = data.get("sample")
	affinity = data.get("affinity")
	evaluation = data.get("evaluation")
	move_time_cost = int(data.get("move_time_cost", 0))
	speed_tier = str(data.get("speed_tier", ""))


func to_dict() -> Dictionary:
	return {
		"traversal": traversal.to_dict() if traversal != null else null,
		"sample": sample.to_dict() if sample != null else null,
		"affinity": affinity.to_dict() if affinity != null else null,
		"evaluation": evaluation.to_dict() if evaluation != null else null,
		"move_time_cost": move_time_cost, "speed_tier": speed_tier,
	}
