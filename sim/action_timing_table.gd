class_name ActionTimingTable
extends RefCounted

const STANDARD_ACTION_COST := 100
const MAX_WAIT_COST := 10000
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")


static func timing_for(command, move_terrain_id: String = "") -> Dictionary:
	if command == null:
		return {}
	var cost := 0
	match int(command.type):
		SimCommand.Type.WAIT:
			if not (command.wait_duration_time_units is int):
				return {}
			cost = command.wait_duration_time_units
		SimCommand.Type.IGNITE:
			cost = 120
		SimCommand.Type.POUR_WATER:
			cost = 80
		SimCommand.Type.DISCHARGE:
			cost = 160
		SimCommand.Type.MOVE:
			var definition: Dictionary = TerrainRegistryScript.definition(move_terrain_id)
			if definition.is_empty() or not bool(definition["passable"]):
				return {}
			cost = int(definition["move_time_cost"])
		_:
			return {}
	return {"time_cost": cost, "speed_tier": speed_tier_for(cost)}


static func speed_tier_for(cost: int) -> String:
	if cost < STANDARD_ACTION_COST:
		return "FAST"
	if cost == STANDARD_ACTION_COST:
		return "NORMAL"
	return "SLOW"
