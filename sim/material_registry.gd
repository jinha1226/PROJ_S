class_name MaterialRegistry
extends RefCounted

# These are bounded gameplay coefficients, not real-world property values.
const _DEFINITIONS := {
	"STONE": {"thermal_conductivity": 18, "heat_capacity": 80,
		"electric_conductivity": 5, "flammability": 0,
		"ignition_temperature": 4000, "combustion_heat": 0,
		"initial_fuel": 0, "mechanical_resistance": 90},
	"WOOD": {"thermal_conductivity": 7, "heat_capacity": 65,
		"electric_conductivity": 5, "flammability": 80,
		"ignition_temperature": 650, "combustion_heat": 90,
		"initial_fuel": 1000, "mechanical_resistance": 35},
	"IRON": {"thermal_conductivity": 70, "heat_capacity": 45,
		"electric_conductivity": 80, "flammability": 0,
		"ignition_temperature": 4000, "combustion_heat": 0,
		"initial_fuel": 0, "mechanical_resistance": 100},
	"RUBBER": {"thermal_conductivity": 3, "heat_capacity": 70,
		"electric_conductivity": 0, "flammability": 45,
		"ignition_temperature": 800, "combustion_heat": 65,
		"initial_fuel": 700, "mechanical_resistance": 25},
	"LEATHER": {"thermal_conductivity": 5, "heat_capacity": 60,
		"electric_conductivity": 3, "flammability": 55,
		"ignition_temperature": 750, "combustion_heat": 55,
		"initial_fuel": 500, "mechanical_resistance": 30},
	"TEXTILE": {"thermal_conductivity": 4, "heat_capacity": 75,
		"electric_conductivity": 2, "flammability": 70,
		"ignition_temperature": 600, "combustion_heat": 50,
		"initial_fuel": 450, "mechanical_resistance": 18},
}

const _TERRAIN_MATERIAL := {
	"floor": "STONE", "stone_floor": "STONE", "wall": "STONE",
	"rubble": "STONE", "shallow_water": "STONE", "wood_floor": "WOOD",
	"metal": "IRON", "rubber_floor": "RUBBER", "door_closed": "WOOD",
	"door_open": "WOOD",
}


static func has(material_id: String) -> bool:
	return _DEFINITIONS.has(material_id)


static func definition(material_id: String) -> Dictionary:
	return _DEFINITIONS.get(material_id, {}).duplicate(true)


static func material_for_terrain(terrain_id: String) -> String:
	return str(_TERRAIN_MATERIAL.get(terrain_id, "STONE"))


static func initial_fuel(material_id: String) -> int:
	return int(_DEFINITIONS.get(material_id, {}).get("initial_fuel", 0))
