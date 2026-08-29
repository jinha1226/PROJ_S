class_name AsciiDioramaProjection
extends RefCounted

## Pure, presentation-only projection helpers. Logical coordinates, visibility,
## simulation state and input mapping stay outside this class.

const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8
const ALL_CARDINALS := NORTH | EAST | SOUTH | WEST

const DRAW_LAYERS := [
	"VOID",
	"MEMORY_GROUND",
	"VISIBLE_GROUND",
	"MATERIAL_MARKS",
	"WALL_SHADOWS",
	"WALL_TOPS_AND_FACES",
	"GROUND_FEATURES",
	"VISIBLE_HAZARDS",
	"GROUND_ROUTES",
	"ACTOR_GROUNDING",
	"ACTORS",
	"INTENTS_AND_SELECTION",
	"EFFECTS",
	"FOV_EDGE_AND_VIGNETTE",
]

const _TERRAIN_SALTS := {
	"floor": 11,
	"stone_floor": 23,
	"wood_floor": 37,
	"metal": 43,
	"rubble": 59,
	"shallow_water": 71,
	"wall": 89,
}

const _MARK_DEFINITIONS := {
	"floor": {"kind":"DUST", "glyph":".", "density":14},
	"stone_floor": {"kind":"CRACK", "glyph":":", "density":22},
	"wood_floor": {"kind":"PLANK", "glyph":"=", "density":58},
	"metal": {"kind":"SHEEN", "glyph":"+", "density":52},
	"rubble": {"kind":"DEBRIS", "glyph":",", "density":72},
	"shallow_water": {"kind":"RIPPLE", "glyph":"~", "density":68},
	"wall": {"kind":"MASONRY", "glyph":"#", "density":34},
}

const ACTOR_MOTION_DEFAULT_MS := 150
const ACTOR_MOTION_MIN_MS := 120
const ACTOR_MOTION_MAX_MS := 180


static func layer_order() -> Array:
	return DRAW_LAYERS.duplicate()


static func actor_motion_sample(from_world: Vector2, to_world: Vector2,
		elapsed_ms: int, duration_ms: int = ACTOR_MOTION_DEFAULT_MS) -> Dictionary:
	var safe_duration := clampi(duration_ms, ACTOR_MOTION_MIN_MS, ACTOR_MOTION_MAX_MS)
	var progress := clampf(float(maxi(0, elapsed_ms)) / float(safe_duration), 0.0, 1.0)
	var remaining := 1.0 - progress
	var eased := 1.0 - remaining * remaining * remaining
	return {
		"active":progress < 1.0 and not from_world.is_equal_approx(to_world),
		"duration_ms":safe_duration,
		"progress":progress,
		"eased_progress":eased,
		"world_position":from_world.lerp(to_world, eased),
	}.duplicate(true)


static func sanitize_observed_cell(row: Dictionary) -> Dictionary:
	if row.is_empty():
		return {"visibility_state":"UNSEEN"}
	var state := str(row.get("visibility_state", row.get("visibility", "VISIBLE"))).to_upper()
	if state not in ["VISIBLE", "MEMORY", "UNSEEN"]:
		state = "VISIBLE"
	if state == "UNSEEN":
		# Deliberately discard every authoritative field. An unseen neighbor can
		# affect only the presentation boundary, never its shape or material.
		return {"visibility_state":"UNSEEN"}
	return {
		"visibility_state":state,
		"terrain_id":str(row.get("terrain_id", row.get("terrain", "floor"))),
	}.duplicate(true)


static func cell_spec(position: Vector2i, current_row: Dictionary,
		neighbors_by_side: Dictionary) -> Dictionary:
	var current := sanitize_observed_cell(current_row)
	var state := str(current.get("visibility_state", "UNSEEN"))
	if state == "UNSEEN":
		return {
			"visible":false,
			"position":[position.x, position.y],
			"visibility_state":"UNSEEN",
			"terrain_id":"",
			"observed_neighbor_mask":0,
			"connected_mask":0,
			"exposed_mask":0,
			"fov_edge_mask":ALL_CARDINALS,
			"material_mark":_empty_mark(),
		}.duplicate(true)

	var terrain_id := str(current.get("terrain_id", "floor"))
	var observed_mask := 0
	var connected := 0
	for side in ["N", "E", "S", "W"]:
		var bit := _side_bit(side)
		var raw_neighbor: Variant = neighbors_by_side.get(side, {})
		var neighbor := sanitize_observed_cell(
			raw_neighbor if raw_neighbor is Dictionary else {})
		if str(neighbor.get("visibility_state", "UNSEEN")) == "UNSEEN":
			continue
		observed_mask |= bit
		if str(neighbor.get("terrain_id", "")) == terrain_id:
			connected |= bit
	return {
		"visible":true,
		"position":[position.x, position.y],
		"visibility_state":state,
		"terrain_id":terrain_id,
		"observed_neighbor_mask":observed_mask,
		"connected_mask":connected,
		"exposed_mask":observed_mask & (ALL_CARDINALS ^ connected),
		"fov_edge_mask":ALL_CARDINALS & (ALL_CARDINALS ^ observed_mask),
		"material_mark":material_mark_spec(position, terrain_id, state),
	}.duplicate(true)


static func material_mark_spec(position: Vector2i, terrain_id: String,
		visibility_state: String = "VISIBLE") -> Dictionary:
	if visibility_state == "UNSEEN" or not _MARK_DEFINITIONS.has(terrain_id):
		return _empty_mark()
	var definition: Dictionary = _MARK_DEFINITIONS[terrain_id]
	var value := visual_hash(position, int(_TERRAIN_SALTS.get(terrain_id, 101)))
	var density := int(definition.density)
	if visibility_state == "MEMORY":
		density = density / 2
	var offset_x := (float((value / 101) % 9) - 4.0) * 0.035
	var offset_y := (float((value / 911) % 9) - 4.0) * 0.028
	return {
		"visible":value % 100 < density,
		"kind":str(definition.kind),
		"glyph":str(definition.glyph),
		"variant":value % 4,
		"offset":Vector2(offset_x, offset_y),
		"opacity":0.22 if visibility_state == "VISIBLE" else 0.09,
	}.duplicate(true)


static func hazard_floor_spec(position: Vector2i, row: Dictionary) -> Dictionary:
	var observed := sanitize_observed_cell(row)
	if str(observed.get("visibility_state", "UNSEEN")) != "VISIBLE":
		return {
			"visible":false, "fire":0, "wetness":0, "conductivity":0,
			"phase":0, "fire_glow_alpha":0.0, "wet_reflection_alpha":0.0,
			"arc_alpha":0.0,
		}.duplicate(true)
	var fire := clampi(int(row.get("fire_intensity", row.get("fire", 0))), 0, 100)
	var wetness := clampi(int(row.get("wetness", 0)), 0, 100)
	var conductivity := clampi(int(row.get("effective_conductivity",
		row.get("conductivity", row.get("base_conductivity", 0)))), 0, 100)
	return {
		"visible":fire > 0 or wetness > 0 or conductivity >= 25,
		"fire":fire,
		"wetness":wetness,
		"conductivity":conductivity,
		"phase":visual_hash(position, 131) % 4,
		"fire_glow_alpha":0.08 + 0.24 * float(fire) / 100.0 if fire > 0 else 0.0,
		"wet_reflection_alpha":0.06 + 0.18 * float(wetness) / 100.0 if wetness > 0 else 0.0,
		"arc_alpha":0.28 + 0.36 * float(conductivity) / 100.0 if conductivity >= 25 else 0.0,
	}.duplicate(true)


static func equipment_spec(_actor: Dictionary) -> Dictionary:
	return {
		"equipment_id":"NONE",
		"back_segments":[],
		"front_segments":[],
		"front_polyline":[],
		"shield_points":[],
		"lantern":{"visible":false, "center":Vector2.ZERO,
			"radius_ratio":0.0, "color_hex":"#ffc45c"},
		"shadow":{"width_ratio":0.58, "height_ratio":0.075,
			"length_ratio":0.26, "color_hex":"#020609"},
		"draw_equipment":false,"equipment_primitive_count":0,
	}.duplicate(true)


static func visual_hash(position: Vector2i, salt: int) -> int:
	# Fixed integer mixing: deterministic across redraws and consumes no simulation RNG.
	return ((int(position.x)*73856093) ^ (int(position.y)*19349663) \
		^ (salt*83492791)) & 0x7fffffff


static func _side_bit(side: String) -> int:
	return {"N":NORTH, "E":EAST, "S":SOUTH, "W":WEST}.get(side, 0)


static func _empty_mark() -> Dictionary:
	return {"visible":false, "kind":"NONE", "glyph":"", "variant":0,
		"offset":Vector2.ZERO, "opacity":0.0}.duplicate(true)
