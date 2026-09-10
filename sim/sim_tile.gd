class_name SimTile
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")
const EnvironmentConfigScript = preload("res://sim/environment_config.gd")

var terrain: String = "floor"
var flammability: int = 0
var base_conductivity: int = 0
var material_id: String = "STONE"
var wetness: int = 0
var fire: int = 0
var temperature: int = EnvironmentConfigScript.AMBIENT_TEMPERATURE
var fuel_amount: int = 0
var surface_id: String = "NONE"
var surface_amount: int = 0
var gas_amount: int = EnvironmentConfigScript.DEFAULT_GAS_AMOUNT
var smoke_amount: int = 0
var steam_amount: int = 0
var flammable_gas_amount: int = 0
var sealed: bool = false
var fire_source_event_id: int = -1
var wetness_source_event_id: int = -1
var fire_damage_eligible_time: int = -1


func effective_conductivity() -> int:
	if material_id == "RUBBER" and wetness == 0:
		return 0
	return clampi(base_conductivity + wetness, 0, 100)


func pressure() -> int:
	return EnvironmentConfigScript.pressure_for(self)


func to_dict() -> Dictionary:
	return {
		"terrain": terrain,
		"flammability": flammability,
		"base_conductivity": base_conductivity,
		"material_id": material_id,
		"wetness": wetness,
		"fire": fire,
		"temperature": temperature,
		"fuel_amount": fuel_amount,
		"surface_id": surface_id,
		"surface_amount": surface_amount,
		"gas_amount": gas_amount,
		"smoke_amount": smoke_amount,
		"steam_amount": steam_amount,
		"flammable_gas_amount": flammable_gas_amount,
		"sealed": sealed,
		"fire_source_event_id": str(fire_source_event_id),
		"wetness_source_event_id": str(wetness_source_event_id),
		"fire_damage_eligible_time": str(fire_damage_eligible_time),
	}


static func from_dict(row: Dictionary) -> SimTile:
	var tile := SimTile.new()
	tile.terrain = str(row.get("terrain", "floor"))
	tile.flammability = int(row.get("flammability", 0))
	tile.base_conductivity = int(row.get("base_conductivity", 0))
	tile.material_id = str(row.get("material_id", "STONE"))
	tile.wetness = int(row.get("wetness", 0))
	tile.fire = int(row.get("fire", 0))
	tile.temperature = int(row.get("temperature", EnvironmentConfigScript.AMBIENT_TEMPERATURE))
	tile.fuel_amount = int(row.get("fuel_amount", 0))
	tile.surface_id = str(row.get("surface_id", "NONE"))
	tile.surface_amount = int(row.get("surface_amount", 0))
	tile.gas_amount = int(row.get("gas_amount", EnvironmentConfigScript.DEFAULT_GAS_AMOUNT))
	tile.smoke_amount = int(row.get("smoke_amount", 0))
	tile.steam_amount = int(row.get("steam_amount", 0))
	tile.flammable_gas_amount = int(row.get("flammable_gas_amount", 0))
	tile.sealed = bool(row.get("sealed", false))
	tile.fire_source_event_id = _parse_canonical_int(row.get("fire_source_event_id", "-1"), "fire source")
	tile.wetness_source_event_id = _parse_canonical_int(row.get("wetness_source_event_id", "-1"), "wetness source")
	tile.fire_damage_eligible_time = _parse_canonical_int(row.get("fire_damage_eligible_time", "-1"), "fire eligibility")
	return tile


static func _parse_canonical_int(value: Variant, label: String) -> int:
	return Int64CodecScript.parse(value, label)
