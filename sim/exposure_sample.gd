class_name ExposureSample
extends RefCounted

var position: Vector2i
var sampled_step_index: int
var sampled_world_time: int
var after_event_id: int
var next_environment_time: int
var terrain_id: String
var passable: bool
var move_time_cost: int
var fire_intensity: int
var fire_damage_eligible_time: int
var known_fire_damage_at_next_tick: int
var terrain_water_exposure: int
var wetness: int
var water_exposure: int
var conductivity: int
var electric_risk: int
var electric_certainty: String
var poison_intensity: int
var fire_source_event_id: int
var wetness_source_event_id: int
var source_event_ids: Array[int]


func _init(data: Dictionary = {}) -> void:
	position = data.get("position", Vector2i(-1, -1))
	sampled_step_index = int(data.get("sampled_step_index", 0))
	sampled_world_time = int(data.get("sampled_world_time", 0))
	after_event_id = int(data.get("after_event_id", -1))
	next_environment_time = int(data.get("next_environment_time", 0))
	terrain_id = str(data.get("terrain_id", ""))
	passable = bool(data.get("passable", false))
	move_time_cost = int(data.get("move_time_cost", 0))
	fire_intensity = int(data.get("fire_intensity", 0))
	fire_damage_eligible_time = int(data.get("fire_damage_eligible_time", -1))
	known_fire_damage_at_next_tick = int(data.get("known_fire_damage_at_next_tick", 0))
	terrain_water_exposure = int(data.get("terrain_water_exposure", 0))
	wetness = int(data.get("wetness", 0))
	water_exposure = int(data.get("water_exposure", 0))
	conductivity = int(data.get("conductivity", 0))
	electric_risk = int(data.get("electric_risk", 0))
	electric_certainty = str(data.get("electric_certainty", "NONE"))
	poison_intensity = int(data.get("poison_intensity", 0))
	fire_source_event_id = int(data.get("fire_source_event_id", -1))
	wetness_source_event_id = int(data.get("wetness_source_event_id", -1))
	source_event_ids = []
	for value in data.get("source_event_ids", []):
		source_event_ids.append(int(value))
	source_event_ids.sort()


func to_dict() -> Dictionary:
	var source_rows: Array[String] = []
	for source_id in source_event_ids:
		source_rows.append(str(source_id))
	return {
		"position": [position.x, position.y],
		"sampled_step_index": str(sampled_step_index),
		"sampled_world_time": str(sampled_world_time),
		"after_event_id": str(after_event_id),
		"next_environment_time": str(next_environment_time),
		"terrain_id": terrain_id, "passable": passable,
		"move_time_cost": move_time_cost, "fire_intensity": fire_intensity,
		"fire_damage_eligible_time": str(fire_damage_eligible_time),
		"known_fire_damage_at_next_tick": known_fire_damage_at_next_tick,
		"terrain_water_exposure": terrain_water_exposure, "wetness": wetness,
		"water_exposure": water_exposure, "conductivity": conductivity,
		"electric_risk": electric_risk, "electric_certainty": electric_certainty,
		"poison_intensity": poison_intensity,
		"fire_source_event_id": str(fire_source_event_id),
		"wetness_source_event_id": str(wetness_source_event_id),
		"source_event_ids": source_rows,
	}
