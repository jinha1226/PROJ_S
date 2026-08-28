class_name PartyVisualTestMap
extends RefCounted

const REGRESSION_SCENARIO_ID := "REGRESSION_V1"
const SHOWCASE_SCENARIO_ID := "SHOWCASE_V1"
const SHOWCASE_FOV_RADIUS := 6
const RUN_MANIFEST_SCHEMA_VERSION := 1
const SHOWCASE_ROWS := [
	"###############",
	"#......#......#",
	"#......#......#",
	"#......#....E.#",
	"#......#......#",
	"#......#......#",
	"#..rr..+......#",
	"#......#......#",
	"#.www..#..rr..#",
	"#.www..#..rr..#",
	"#.mmm..#......#",
	"#......#......#",
	"#.@.ff.#......#",
	"#......#......#",
	"###############",
]

const HERO_POSITION := Vector2i(2, 12)
const ENEMY_POSITION := Vector2i(12, 3)
const ENTRY_POSITION := Vector2i(2, 12)
const EXIT_POSITION := Vector2i(13, 1)
const OPEN_DOOR_POSITION := Vector2i(7, 6)
const WET_METAL_POSITION := Vector2i(3, 10)
const WET_WOOD_POSITION := Vector2i(4, 12)
const FIRE_POSITION := Vector2i(5, 12)

const _TERRAIN_BY_GLYPH := {
	"#": "wall",
	".": "stone_floor",
	"+": "stone_floor",
	"@": "stone_floor",
	"E": "stone_floor",
	"r": "rubble",
	"w": "shallow_water",
	"m": "metal",
	"f": "wood_floor",
}


static func has_scenario(scenario_id: String) -> bool:
	return scenario_id in [REGRESSION_SCENARIO_ID, SHOWCASE_SCENARIO_ID]


static func run_manifest(scenario_id: String) -> Dictionary:
	if scenario_id != SHOWCASE_SCENARIO_ID:
		return {}
	return {
		"schema_version":RUN_MANIFEST_SCHEMA_VERSION,
		"scenario_id":SHOWCASE_SCENARIO_ID,
		"objective_id":"CLEAR_SINGLE_ENCOUNTER_AND_EXIT",
		"entry":{"position":[ENTRY_POSITION.x,ENTRY_POSITION.y],
			"feature_id":"run_entry"},
		"exit":{"position":[EXIT_POSITION.x,EXIT_POSITION.y],
			"locked_feature_id":"run_exit_locked",
			"open_feature_id":"run_exit_open"},
		"reward":{"reward_id":"SHOWCASE_VICTORY_TOKEN","amount":1},
	}.duplicate(true)


static func apply_showcase_terrain(world) -> bool:
	if world == null or world.width != 15 or world.height != 15:
		return false
	for y in range(SHOWCASE_ROWS.size()):
		var row: String = SHOWCASE_ROWS[y]
		if row.length() != 15:
			return false
		for x in range(row.length()):
			var glyph := row.substr(x, 1)
			if not _TERRAIN_BY_GLYPH.has(glyph) \
					or not world.bootstrap_set_terrain(Vector2i(x, y),
						str(_TERRAIN_BY_GLYPH[glyph])):
				return false
	return true


static func apply_showcase_hazards(world) -> bool:
	# These checked bootstraps create the canonical step-zero provenance chain.
	# Terrain must already be complete because its bootstrap rejects after events.
	return world != null \
		and world.bootstrap_set_wetness(WET_METAL_POSITION, 80) != null \
		and world.bootstrap_set_wetness(WET_WOOD_POSITION, 60) != null \
		and world.bootstrap_set_fire(FIRE_POSITION, 80) != null


static func feature_id_at(scenario_id: String, position: Vector2i) -> String:
	if scenario_id == SHOWCASE_SCENARIO_ID and position == OPEN_DOOR_POSITION:
		return "open_door"
	return ""


static func visible_cells(world, origin: Vector2i, scenario_id: String) -> Dictionary:
	var visible: Dictionary = {}
	if world == null:
		return visible
	if scenario_id != SHOWCASE_SCENARIO_ID:
		for y in range(world.height):
			for x in range(world.width):
				visible[_key(Vector2i(x, y))] = true
		return visible
	for y in range(world.height):
		for x in range(world.width):
			var target := Vector2i(x, y)
			if maxi(absi(target.x - origin.x), absi(target.y - origin.y)) \
					<= SHOWCASE_FOV_RADIUS and _has_line_of_sight(world, origin, target):
				visible[_key(target)] = true
	return visible


static func _has_line_of_sight(world, origin: Vector2i, target: Vector2i) -> bool:
	if origin == target:
		return true
	var x0 := origin.x
	var y0 := origin.y
	var x1 := target.x
	var y1 := target.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var error := dx + dy
	while x0 != x1 or y0 != y1:
		var doubled := 2 * error
		if doubled >= dy:
			error += dy
			x0 += sx
		if doubled <= dx:
			error += dx
			y0 += sy
		var position := Vector2i(x0, y0)
		if position == target:
			return true
		if world.tile_at(position).terrain == "wall":
			return false
	return true


static func _key(position: Vector2i) -> String:
	return "%d:%d" % [position.x, position.y]
