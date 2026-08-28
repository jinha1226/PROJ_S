class_name AsciiVisualStyle
extends RefCounted

const VISIBILITY_STATES := ["VISIBLE", "MEMORY", "UNSEEN"]
const LIFE_STATES := ["ACTIVE", "DOWNED", "DEAD"]

const TERRAIN_DEFINITIONS := {
	"floor": {"glyph":".", "base_hex":"#1b2833", "glyph_hex":"#5d7180", "edge_hex":"#0b1218", "depth_ratio":0.035, "raised":false},
	"stone_floor": {"glyph":":", "base_hex":"#223342", "glyph_hex":"#7892a5", "edge_hex":"#0d171f", "depth_ratio":0.045, "raised":false},
	"wood_floor": {"glyph":"=", "base_hex":"#3b2a1b", "glyph_hex":"#c38b4f", "edge_hex":"#1b1009", "depth_ratio":0.055, "raised":false},
	"metal": {"glyph":"+", "base_hex":"#18343d", "glyph_hex":"#7fc6d4", "edge_hex":"#08191e", "depth_ratio":0.050, "raised":false},
	"rubble": {"glyph":",", "base_hex":"#392f20", "glyph_hex":"#c5a264", "edge_hex":"#181209", "depth_ratio":0.070, "raised":false},
	"shallow_water": {"glyph":"~", "base_hex":"#123e52", "glyph_hex":"#68d6f2", "edge_hex":"#071d27", "depth_ratio":0.030, "raised":false},
	"wall": {"glyph":"#", "base_hex":"#24313b", "glyph_hex":"#a5b2ba", "edge_hex":"#070c11", "depth_ratio":0.145, "raised":true},
}


static func visibility_state(cell: Dictionary) -> String:
	var state := str(cell.get("visibility_state", cell.get("visibility", "VISIBLE"))).to_upper()
	return state if state in VISIBILITY_STATES else "VISIBLE"


static func visibility_spec(cell_or_state: Variant) -> Dictionary:
	var state := str(cell_or_state).to_upper() if cell_or_state is String else visibility_state(
		cell_or_state if cell_or_state is Dictionary else {})
	if state not in VISIBILITY_STATES:
		state = "VISIBLE"
	return {
		"state": state,
		"draw_terrain": state != "UNSEEN",
		"draw_hazards": state == "VISIBLE",
		"draw_actors": state == "VISIBLE",
		"accepts_actor_input": state == "VISIBLE",
		"opacity": 1.0 if state == "VISIBLE" else (0.34 if state == "MEMORY" else 0.0),
	}.duplicate(true)


static func terrain_spec(cell: Dictionary) -> Dictionary:
	var terrain_id := str(cell.get("terrain_id", cell.get("terrain", "floor")))
	var definition: Dictionary = TERRAIN_DEFINITIONS.get(terrain_id, {
		"glyph":"?", "base_hex":"#242a31", "glyph_hex":"#aab3bc", "edge_hex":"#090d12",
		"depth_ratio":0.04, "raised":false,
	})
	var result := definition.duplicate(true)
	var visibility := visibility_spec(cell)
	result["terrain_id"] = terrain_id
	result["visibility_state"] = visibility.state
	result["visible"] = bool(visibility.draw_terrain)
	result["opacity"] = float(visibility.opacity)
	return result.duplicate(true)


static func hazard_spec(cell: Dictionary) -> Dictionary:
	var visibility := visibility_spec(cell)
	var fire := clampi(int(cell.get("fire_intensity", cell.get("fire", 0))), 0, 100)
	var wetness := clampi(int(cell.get("wetness", 0)), 0, 100)
	var conductivity := clampi(int(cell.get("effective_conductivity",
		cell.get("conductivity", cell.get("base_conductivity", 0)))), 0, 100)
	var cues: Array[Dictionary] = []
	if bool(visibility.draw_hazards) and fire > 0:
		cues.append({"kind":"FIRE", "glyph":"*", "color_hex":"#ff7a3d", "value":fire,
			"corner":"BOTTOM_LEFT", "fill_alpha":0.12 + 0.34 * float(fire) / 100.0})
	if bool(visibility.draw_hazards) and wetness > 0:
		cues.append({"kind":"WET", "glyph":"~", "color_hex":"#62c8ff", "value":wetness,
			"corner":"BOTTOM_RIGHT", "fill_alpha":0.08 + 0.20 * float(wetness) / 100.0})
	if bool(visibility.draw_hazards) and conductivity >= 25:
		cues.append({"kind":"CONDUCTIVE", "glyph":"+", "color_hex":"#8ddce8", "value":conductivity,
			"corner":"TOP_RIGHT", "fill_alpha":0.0})
	return {"visibility_state":visibility.state, "fire":fire, "wetness":wetness,
		"conductivity":conductivity, "cues":cues}.duplicate(true)


static func actor_spec(actor: Dictionary, ghost: bool = false) -> Dictionary:
	var species_id := str(actor.get("species_id", "")).to_lower()
	var faction_id := str(actor.get("faction_id", "")).to_lower()
	var is_protagonist := bool(actor.get("is_protagonist", false))
	var is_enemy := bool(actor.get("is_enemy", false)) or faction_id == "enemy"
	var is_party := is_protagonist or faction_id == "party" or int(actor.get("roster_slot", -1)) >= 0
	var glyph := "?"
	var color_hex := "#c2ccd5"
	var highlight_hex := "#eef4f8"
	if is_protagonist:
		glyph = "@"; color_hex = "#ffd447"; highlight_hex = "#fff1a6"
	elif is_enemy:
		glyph = "G" if species_id in ["", "goblin"] else "?"
		color_hex = "#ff675c"; highlight_hex = "#ffc0a8"
	elif is_party and species_id == "goblin":
		glyph = "g"; color_hex = "#91d657"; highlight_hex = "#d7ff9b"
	elif is_party:
		glyph = "&"; color_hex = "#65bfff"; highlight_hex = "#ccecff"

	var life_state := str(actor.get("life_state", "ACTIVE")).to_upper()
	if life_state not in LIFE_STATES:
		life_state = "DEAD" if actor.has("alive") and not bool(actor.get("alive", true)) else "ACTIVE"
	if life_state == "DEAD":
		glyph = "x"; color_hex = "#8d6870"; highlight_hex = "#c7959d"
	var statuses: Array[String] = []
	var raw_statuses: Variant = actor.get("status_ids", [])
	if raw_statuses is Array:
		for raw_status in raw_statuses:
			var status_id := str(raw_status.get("status_id", "")) if raw_status is Dictionary else str(raw_status)
			if not status_id.is_empty() and status_id not in statuses:
				statuses.append(status_id)
	statuses.sort()
	var facing := normalized_facing(actor.get("facing", [0, 1]))
	var geometry := _pose_geometry(life_state, facing)
	var guarded := bool(actor.get("guarded", false))
	return {
		"glyph":glyph, "color_hex":color_hex, "highlight_hex":highlight_hex,
		"shadow_hex":"#03070b", "outline_hex":"#0a1016",
		"opacity":0.46 if ghost else (0.58 if life_state == "DOWNED" else 1.0),
		"ghost":ghost, "life_state":life_state, "statuses":statuses,
		"bleeding":"BLEEDING" in statuses, "guarded":guarded,
		"facing":[facing.x, facing.y], "pose":geometry.pose,
		"body_center":geometry.body_center, "head_center":geometry.head_center,
		"facing_point":geometry.facing_point, "limb_segments":geometry.limb_segments,
		"guard_segments":_guard_geometry(facing) if guarded and life_state == "ACTIVE" else [],
		"draw_head":life_state != "DEAD", "draw_limbs":life_state != "DEAD",
	}.duplicate(true)


static func follower_spec(actor: Dictionary) -> Dictionary:
	var display_role := str(actor.get("display_role", "")).to_upper()
	var logical := _array_position(actor.get("logical_position", actor.get("position", [])))
	var display := _array_position(actor.get("display_position", actor.get("position", [])))
	var has_separation := logical != Vector2i(-1,-1) and display != Vector2i(-1,-1) \
		and logical != display
	return {
		"display_role":display_role,
		"visible":display_role == "FOLLOWER" and has_separation,
		"logical_position":[logical.x,logical.y],
		"display_position":[display.x,display.y],
		"tether_hex":"#67bfe2", "footprint_hex":"#9cdbef",
		"opacity":0.62, "dash_count":4, "footprint_radius_ratio":0.12,
	}.duplicate(true)


static func normalized_facing(value: Variant) -> Vector2i:
	var facing := Vector2i.DOWN
	if value is Vector2i:
		facing = value
	elif value is Vector2:
		facing = Vector2i(signi(int(value.x)), signi(int(value.y)))
	elif value is Array and value.size() == 2:
		facing = Vector2i(signi(int(value[0])), signi(int(value[1])))
	if facing == Vector2i.ZERO:
		return Vector2i.DOWN
	return Vector2i(signi(facing.x), signi(facing.y))


static func bracket_segments(rect: Rect2, inset_ratio: float = 0.08,
		arm_ratio: float = 0.24) -> Array:
	var inset := maxf(1.0, minf(rect.size.x, rect.size.y) * inset_ratio)
	var inner := rect.grow(-inset)
	var arm := maxf(3.0, minf(inner.size.x, inner.size.y) * arm_ratio)
	var tl := inner.position; var tr := Vector2(inner.end.x, inner.position.y)
	var br := inner.end; var bl := Vector2(inner.position.x, inner.end.y)
	return [
		[tl, tl + Vector2(arm, 0)], [tl, tl + Vector2(0, arm)],
		[tr, tr + Vector2(-arm, 0)], [tr, tr + Vector2(0, arm)],
		[br, br + Vector2(-arm, 0)], [br, br + Vector2(0, -arm)],
		[bl, bl + Vector2(arm, 0)], [bl, bl + Vector2(0, -arm)],
	].duplicate(true)


static func _pose_geometry(life_state: String, facing: Vector2i) -> Dictionary:
	if life_state == "DOWNED":
		return {"pose":"DOWNED", "body_center":Vector2(0.0, 0.24),
			"head_center":Vector2(-0.31, 0.25), "facing_point":Vector2(-0.36, 0.22),
			"limb_segments":[
				[Vector2(-0.16,0.23),Vector2(-0.40,0.12)],
				[Vector2(0.16,0.23),Vector2(0.40,0.32)],
				[Vector2(-0.08,0.36),Vector2(-0.30,0.44)],
				[Vector2(0.08,0.36),Vector2(0.32,0.42)],
			]}
	if life_state == "DEAD":
		return {"pose":"DEAD", "body_center":Vector2(0.0,0.32),
			"head_center":Vector2.ZERO, "facing_point":Vector2.ZERO, "limb_segments":[]}
	var direction := Vector2(facing).normalized()
	var side := Vector2(-direction.y, direction.x)
	var shoulder := Vector2(0.0,-0.09)
	var hip := Vector2(0.0,0.18)
	var left_shoulder := shoulder - side * 0.10
	var right_shoulder := shoulder + side * 0.10
	return {"pose":"STANDING", "body_center":Vector2(0.0,0.02),
		"head_center":Vector2(0.0,-0.31), "facing_point":Vector2(0.0,-0.31)+direction*0.075,
		"limb_segments":[
			[left_shoulder,left_shoulder-side*0.18+direction*0.10],
			[right_shoulder,right_shoulder+side*0.18+direction*0.14],
			[hip-Vector2(0.04,0.0),Vector2(-0.15,0.43)],
			[hip+Vector2(0.04,0.0),Vector2(0.15,0.43)],
		]}


static func _guard_geometry(facing: Vector2i) -> Array:
	var direction := Vector2(facing).normalized()
	var side := Vector2(-direction.y, direction.x)
	var center := direction * 0.29 + Vector2(0.0,0.01)
	return [[center-side*0.15-direction*0.04, center-side*0.15+direction*0.06],
		[center-side*0.15-direction*0.04, center+side*0.15-direction*0.04],
		[center+side*0.15-direction*0.04, center+side*0.15+direction*0.06]]


static func _array_position(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size()==2:
		return Vector2i(int(value[0]),int(value[1]))
	return Vector2i(-1,-1)
