class_name SimTile
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")

var terrain: String = "floor"
var flammability: int = 0
var base_conductivity: int = 0
var wetness: int = 0
var fire: int = 0
var fire_source_event_id: int = -1
var wetness_source_event_id: int = -1
var fire_damage_eligible_time: int = -1


func effective_conductivity() -> int:
	return clampi(base_conductivity + wetness, 0, 100)


func to_dict() -> Dictionary:
	return {
		"terrain": terrain,
		"flammability": flammability,
		"base_conductivity": base_conductivity,
		"wetness": wetness,
		"fire": fire,
		"fire_source_event_id": str(fire_source_event_id),
		"wetness_source_event_id": str(wetness_source_event_id),
		"fire_damage_eligible_time": str(fire_damage_eligible_time),
	}


static func from_dict(row: Dictionary) -> SimTile:
	var tile := SimTile.new()
	tile.terrain = str(row.get("terrain", "floor"))
	tile.flammability = int(row.get("flammability", 0))
	tile.base_conductivity = int(row.get("base_conductivity", 0))
	tile.wetness = int(row.get("wetness", 0))
	tile.fire = int(row.get("fire", 0))
	tile.fire_source_event_id = _parse_canonical_int(row.get("fire_source_event_id", "-1"), "fire source")
	tile.wetness_source_event_id = _parse_canonical_int(row.get("wetness_source_event_id", "-1"), "wetness source")
	tile.fire_damage_eligible_time = _parse_canonical_int(row.get("fire_damage_eligible_time", "-1"), "fire eligibility")
	return tile


static func _parse_canonical_int(value: Variant, label: String) -> int:
	return Int64CodecScript.parse(value, label)
