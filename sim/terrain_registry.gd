class_name TerrainRegistry
extends RefCounted

const RULESET_ID := "terrain-registry-v1"

const _DEFINITIONS := {
	"floor": {
		"terrain_id": "floor", "passable": true, "occupancy_capacity": 1,
		"move_time_cost": 100, "terrain_water_exposure": 0,
		"default_flammability": 0, "default_base_conductivity": 0,
		"presentation_key": "terrain.floor",
	},
	"stone_floor": {
		"terrain_id": "stone_floor", "passable": true, "occupancy_capacity": 1,
		"move_time_cost": 100, "terrain_water_exposure": 0,
		"default_flammability": 0, "default_base_conductivity": 5,
		"presentation_key": "terrain.stone_floor",
	},
	"wood_floor": {
		"terrain_id": "wood_floor", "passable": true, "occupancy_capacity": 1,
		"move_time_cost": 100, "terrain_water_exposure": 0,
		"default_flammability": 80, "default_base_conductivity": 5,
		"presentation_key": "terrain.wood_floor",
	},
	"metal": {
		"terrain_id": "metal", "passable": true, "occupancy_capacity": 1,
		"move_time_cost": 100, "terrain_water_exposure": 0,
		"default_flammability": 0, "default_base_conductivity": 25,
		"presentation_key": "terrain.metal",
	},
	"rubble": {
		"terrain_id": "rubble", "passable": true, "occupancy_capacity": 1,
		"move_time_cost": 140, "terrain_water_exposure": 0,
		"default_flammability": 10, "default_base_conductivity": 5,
		"presentation_key": "terrain.rubble",
	},
	"shallow_water": {
		"terrain_id": "shallow_water", "passable": true, "occupancy_capacity": 1,
		"move_time_cost": 130, "terrain_water_exposure": 80,
		"default_flammability": 0, "default_base_conductivity": 60,
		"presentation_key": "terrain.shallow_water",
	},
	"wall": {
		"terrain_id": "wall", "passable": false, "occupancy_capacity": 0,
		"move_time_cost": 0, "terrain_water_exposure": 0,
		"default_flammability": 0, "default_base_conductivity": 0,
		"presentation_key": "terrain.wall",
	},
}


static func has(terrain_id: String) -> bool:
	return _DEFINITIONS.has(terrain_id)


static func definition(terrain_id: String) -> Dictionary:
	if not _DEFINITIONS.has(terrain_id):
		return {}
	return _DEFINITIONS[terrain_id].duplicate(true)


static func all_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _DEFINITIONS.keys()
	ids.sort()
	for terrain_id in ids:
		result.append(_DEFINITIONS[terrain_id].duplicate(true))
	return result
