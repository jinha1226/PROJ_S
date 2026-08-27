class_name ExposureEvaluation
extends RefCounted

var species_id: String
var sampled_step_index: int
var sampled_world_time: int
var position: Vector2i
var fire_score: int
var water_score: int
var electric_score: int
var poison_score: int
var total_risk: int


func _init(data: Dictionary = {}) -> void:
	species_id = str(data.get("species_id", "default"))
	sampled_step_index = int(data.get("sampled_step_index", 0))
	sampled_world_time = int(data.get("sampled_world_time", 0))
	position = data.get("position", Vector2i(-1, -1))
	fire_score = int(data.get("fire_score", 0))
	water_score = int(data.get("water_score", 0))
	electric_score = int(data.get("electric_score", 0))
	poison_score = int(data.get("poison_score", 0))
	total_risk = int(data.get("total_risk", 0))


func to_dict() -> Dictionary:
	return {
		"species_id": species_id, "sampled_step_index": str(sampled_step_index),
		"sampled_world_time": str(sampled_world_time),
		"position": [position.x, position.y], "fire_score": fire_score,
		"water_score": water_score, "electric_score": electric_score,
		"poison_score": poison_score, "total_risk": total_risk,
	}


static func component(intensity: int, tolerance: int) -> int:
	var numerator := intensity * (100 - tolerance) + 99
	return int(numerator / 100)


static func evaluate(sample, affinity):
	var fire := component(sample.fire_intensity, affinity.fire_tolerance)
	var water := component(sample.water_exposure, affinity.water_tolerance)
	var electric := component(sample.electric_risk, affinity.electric_tolerance)
	var poison := component(sample.poison_intensity, affinity.poison_tolerance)
	return load("res://sim/exposure_evaluation.gd").new({
		"species_id": affinity.species_id,
		"sampled_step_index": sample.sampled_step_index,
		"sampled_world_time": sample.sampled_world_time,
		"position": sample.position,
		"fire_score": fire, "water_score": water,
		"electric_score": electric, "poison_score": poison,
		"total_risk": fire + water + electric + poison,
	})
