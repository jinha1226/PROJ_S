class_name PartyVisualTestMap
extends RefCounted

const REGRESSION_SCENARIO_ID := "REGRESSION_V1"
const SHOWCASE_SCENARIO_ID := "SHOWCASE_V1"
const SOLO_COMBAT_SCENARIO_ID := "SOLO_COMBAT_V1"
const SOLO_FIXTURE_SCENARIO_ID := "SOLO_FIXTURE_V1"
const SHOWCASE_FOV_RADIUS := 6
const RUN_MANIFEST_SCHEMA_VERSION := 1
const DungeonMapScript = preload("res://playtest/deterministic_dungeon_map.gd")
const CampaignFloorMapScript = preload("res://playtest/campaign_floor_map.gd")
const SHOWCASE_ROWS := [
	"###############",
	"#......#......#",
	"#......#......#",
	"#......#......#",
	"#......#......#",
	"#......#......#",
	"#..rr..+......#",
	"#......#......#",
	"#.www..#..rr..#",
	"#.www..#..rr..#",
	"#.mmm..#......#",
	"#.....E#......#",
	"#.@.ff.#......#",
	"#......#......#",
	"###############",
]

const HERO_POSITION := Vector2i(2, 12)
const ENEMY_POSITION := Vector2i(6, 11)
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
	return scenario_id in [REGRESSION_SCENARIO_ID, SHOWCASE_SCENARIO_ID,
		SOLO_COMBAT_SCENARIO_ID, SOLO_FIXTURE_SCENARIO_ID]


static func uses_showcase_layout(scenario_id:String)->bool:
	return scenario_id in [SHOWCASE_SCENARIO_ID, SOLO_FIXTURE_SCENARIO_ID]


static func uses_product_dungeon(scenario_id: String) -> bool:
	return scenario_id == SOLO_COMBAT_SCENARIO_ID


static func uses_los_fov(scenario_id: String) -> bool:
	return uses_showcase_layout(scenario_id) or uses_product_dungeon(scenario_id)


static func product_dungeon(seed: int) -> Dictionary:
	return CampaignFloorMapScript.generate(1,seed)


static func campaign_floor(floor_index:int,seed:int)->Dictionary:
	return CampaignFloorMapScript.generate(floor_index,seed)


static func previous_product_dungeon(seed:int)->Dictionary:
	return DungeonMapScript.generate(DungeonMapScript.DEFAULT_WIDTH,
		DungeonMapScript.DEFAULT_HEIGHT,seed)


static func older_product_dungeon(seed:int)->Dictionary:
	return DungeonMapScript.generate_previous_product(DungeonMapScript.DEFAULT_WIDTH,
		DungeonMapScript.DEFAULT_HEIGHT,seed)


static func legacy_product_dungeon(seed:int)->Dictionary:
	return DungeonMapScript.generate_legacy(DungeonMapScript.LEGACY_WIDTH,
		DungeonMapScript.LEGACY_HEIGHT,seed)


static func run_manifest(scenario_id: String, layout: Dictionary = {}) -> Dictionary:
	if not uses_los_fov(scenario_id):
		return {}
	var entry_position := ENTRY_POSITION
	var exit_position := EXIT_POSITION
	if uses_product_dungeon(scenario_id):
		var generated := layout if not layout.is_empty() else product_dungeon(44)
		entry_position = generated.get("entry_position", ENTRY_POSITION)
		exit_position = generated.get("exit_position", EXIT_POSITION)
	var transition_exit:=uses_product_dungeon(scenario_id) \
		and layout.has("transition_portal_position")
	return {
		"schema_version":RUN_MANIFEST_SCHEMA_VERSION,
		"scenario_id":scenario_id,
		"objective_id":"CLEAR_SINGLE_ENCOUNTER_AND_EXIT",
		"entry":{"position":[entry_position.x,entry_position.y],
			"feature_id":"run_entry"},
		"exit":{"position":[exit_position.x,exit_position.y],
			"locked_feature_id":"floor_transition_portal_locked" \
				if transition_exit else "run_exit_locked",
			"open_feature_id":"floor_transition_portal" \
				if transition_exit else "run_exit_open"},
		"reward":{"reward_id":"SOLO_COMBAT_VICTORY_TOKEN" \
			if scenario_id in [SOLO_COMBAT_SCENARIO_ID, SOLO_FIXTURE_SCENARIO_ID] \
			else "SHOWCASE_VICTORY_TOKEN","amount":1},
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


static func apply_product_dungeon_terrain(world, layout: Dictionary) -> bool:
	return DungeonMapScript.apply_terrain(world, layout)


static func apply_product_dungeon_hazards(world, layout: Dictionary) -> bool:
	return DungeonMapScript.apply_hazards(world, layout)


static func feature_id_at(scenario_id: String, position: Vector2i,
		layout: Dictionary = {}) -> String:
	if uses_showcase_layout(scenario_id) and position == OPEN_DOOR_POSITION:
		return "open_door"
	if uses_product_dungeon(scenario_id):
		if position==layout.get("transition_portal_position",Vector2i(-1,-1)):
			return "floor_transition_portal"
		for door_position in layout.get("door_positions", []):
			if position == door_position:
				return "open_door"
	return ""


static func visible_cells(world, origin: Vector2i, scenario_id: String) -> Dictionary:
	var visible: Dictionary = {}
	if world == null:
		return visible
	if not uses_los_fov(scenario_id):
		for y in range(world.height):
			for x in range(world.width):
				visible[_key(Vector2i(x, y))] = true
		return visible
	var min_y := maxi(0, origin.y - SHOWCASE_FOV_RADIUS)
	var max_y := mini(world.height - 1, origin.y + SHOWCASE_FOV_RADIUS)
	var min_x := maxi(0, origin.x - SHOWCASE_FOV_RADIUS)
	var max_x := mini(world.width - 1, origin.x + SHOWCASE_FOV_RADIUS)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var target := Vector2i(x, y)
			if _has_line_of_sight(world, origin, target):
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
