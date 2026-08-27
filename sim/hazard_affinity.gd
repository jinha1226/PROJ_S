class_name HazardAffinity
extends RefCounted

var species_id: String
var fire_tolerance: int
var water_tolerance: int
var electric_tolerance: int
var poison_tolerance: int


func _init(data: Dictionary = {}) -> void:
	species_id = str(data.get("species_id", "default"))
	fire_tolerance = int(data.get("fire_tolerance", 0))
	water_tolerance = int(data.get("water_tolerance", 0))
	electric_tolerance = int(data.get("electric_tolerance", 0))
	poison_tolerance = int(data.get("poison_tolerance", 0))


func to_dict() -> Dictionary:
	return {
		"species_id": species_id, "fire_tolerance": fire_tolerance,
		"water_tolerance": water_tolerance, "electric_tolerance": electric_tolerance,
		"poison_tolerance": poison_tolerance,
	}
