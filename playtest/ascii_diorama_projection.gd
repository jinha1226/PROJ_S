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


static func layer_order() -> Array:
	return DRAW_LAYERS.duplicate()


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


static func equipment_spec(actor: Dictionary) -> Dictionary:
	var protagonist := bool(actor.get("is_protagonist", false))
	var faction_id := str(actor.get("faction_id", "")).to_lower()
	var species_id := str(actor.get("species_id", "")).to_lower()
	var roster_slot := int(actor.get("roster_slot", -1))
	var facing_value: Variant = actor.get("facing", [0, 1])
	var facing_x := 0
	if facing_value is Array and facing_value.size() == 2:
		facing_x = int(facing_value[0])
	elif facing_value is Vector2i:
		facing_x = facing_value.x
	var mirror := -1.0 if facing_x < 0 else 1.0
	var result := {
		"equipment_id":"NONE",
		"back_segments":[],
		"front_segments":[],
		"front_polyline":[],
		"shield_points":[],
		"lantern":{"visible":false, "center":Vector2.ZERO,
			"radius_ratio":0.0, "color_hex":"#ffc45c"},
		"shadow":{"width_ratio":0.58, "height_ratio":0.075,
			"length_ratio":0.26, "color_hex":"#020609"},
	}
	if protagonist:
		result.equipment_id = "HERO_SWORD_LANTERN"
		result.back_segments = [
			_segment(_mirror(Vector2(-0.26, -0.03), mirror),
				_mirror(Vector2(-0.34, 0.20), mirror), "#d19a42", 0.034),
		]
		result.front_segments = [
			_segment(_mirror(Vector2(0.10, 0.07), mirror),
				_mirror(Vector2(0.39, -0.35), mirror), "#dbe9ef", 0.035),
			_segment(_mirror(Vector2(0.20, -0.06), mirror),
				_mirror(Vector2(0.37, 0.02), mirror), "#d6a64e", 0.030),
		]
		result.lantern = {"visible":true,
			"center":_mirror(Vector2(-0.34, 0.24), mirror),
			"radius_ratio":0.075, "color_hex":"#ffc45c"}
		result.shadow.length_ratio = 0.38
	elif faction_id == "party" and roster_slot == 1:
		result.equipment_id = "COMPANION_SPEAR_SHIELD"
		result.back_segments = [
			_segment(_mirror(Vector2(-0.31, 0.42), mirror),
				_mirror(Vector2(0.28, -0.47), mirror), "#c9d7d8", 0.030),
			_segment(_mirror(Vector2(0.28, -0.47), mirror),
				_mirror(Vector2(0.20, -0.38), mirror), "#e8b95c", 0.026),
		]
		result.shield_points = _mirrored_points([
			Vector2(0.12, -0.08), Vector2(0.40, -0.01),
			Vector2(0.34, 0.31), Vector2(0.15, 0.38),
		], mirror)
		result.shadow.length_ratio = 0.32
	elif faction_id == "party" and roster_slot == 2:
		result.equipment_id = "COMPANION_TOOL_DAGGER"
		result.back_segments = [
			_segment(_mirror(Vector2(-0.18, 0.16), mirror),
				_mirror(Vector2(-0.36, -0.31), mirror), "#b6c3c7", 0.036),
			_segment(_mirror(Vector2(-0.45, -0.31), mirror),
				_mirror(Vector2(-0.25, -0.31), mirror), "#c88a48", 0.050),
		]
		result.front_segments = [
			_segment(_mirror(Vector2(0.10, 0.12), mirror),
				_mirror(Vector2(0.38, -0.11), mirror), "#e2e9e9", 0.032),
		]
	elif species_id == "goblin":
		result.equipment_id = "GOBLIN_SAW"
		result.front_polyline = _mirrored_points([
			Vector2(0.08, 0.10), Vector2(0.20, -0.02), Vector2(0.29, 0.03),
			Vector2(0.35, -0.09), Vector2(0.43, -0.04),
		], mirror)
		result.front_segments = [
			_segment(_mirror(Vector2(0.03, 0.15), mirror),
				_mirror(Vector2(0.16, 0.03), mirror), "#8d553d", 0.052),
		]
		result.shadow.length_ratio = 0.30
	return result.duplicate(true)


static func visual_hash(position: Vector2i, salt: int) -> int:
	# Fixed integer mixing: deterministic across redraws and consumes no simulation RNG.
	return ((int(position.x)*73856093) ^ (int(position.y)*19349663) \
		^ (salt*83492791)) & 0x7fffffff


static func _side_bit(side: String) -> int:
	return {"N":NORTH, "E":EAST, "S":SOUTH, "W":WEST}.get(side, 0)


static func _segment(from: Vector2, to: Vector2, color_hex: String,
		width_ratio: float) -> Dictionary:
	return {"from":from, "to":to, "color_hex":color_hex,
		"width_ratio":width_ratio}


static func _mirror(point: Vector2, mirror: float) -> Vector2:
	return Vector2(point.x * mirror, point.y)


static func _mirrored_points(points: Array, mirror: float) -> Array:
	var result: Array = []
	for point in points:
		result.append(_mirror(point, mirror))
	return result


static func _empty_mark() -> Dictionary:
	return {"visible":false, "kind":"NONE", "glyph":"", "variant":0,
		"offset":Vector2.ZERO, "opacity":0.0}.duplicate(true)
