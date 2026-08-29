class_name AsciiVisualStyle
extends RefCounted

const VISIBILITY_STATES := ["VISIBLE", "MEMORY", "UNSEEN"]
const LIFE_STATES := ["ACTIVE", "DOWNED", "DEAD"]

const DIORAMA_PALETTE := {
	"void_hex":"#020406",
	"substrate_hex":"#091017",
	"wall_side_hex":"#070b0f",
	"shadow_hex":"#010304",
}

const TERRAIN_DEFINITIONS := {
	"floor": {"glyph":".", "base_hex":"#0b101b", "glyph_hex":"#8294ff", "edge_hex":"#060a12", "font_ratio":0.52, "raised":false},
	"stone_floor": {"glyph":"#", "base_hex":"#0c111a", "glyph_hex":"#c7b8ff", "edge_hex":"#080b13", "font_ratio":0.55, "raised":false},
	"wood_floor": {"glyph":",", "base_hex":"#11100f", "glyph_hex":"#ff9d52", "edge_hex":"#0b0908", "font_ratio":0.55, "raised":false},
	"metal": {"glyph":"=", "base_hex":"#09141a", "glyph_hex":"#58e5ff", "edge_hex":"#051015", "font_ratio":0.56, "raised":false},
	"rubble": {"glyph":":", "base_hex":"#11110f", "glyph_hex":"#dbb45d", "edge_hex":"#0b0a07", "font_ratio":0.54, "raised":false},
	"shallow_water": {"glyph":"~", "base_hex":"#081421", "glyph_hex":"#37a8ff", "edge_hex":"#050e18", "font_ratio":0.58, "raised":false},
	"wall": {"glyph":"#", "base_hex":"#10121b", "glyph_hex":"#ead5ff", "edge_hex":"#080a12", "font_ratio":0.61, "raised":true},
}


static func diorama_palette_spec() -> Dictionary:
	return DIORAMA_PALETTE.duplicate(true)


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
	var registered := TERRAIN_DEFINITIONS.has(terrain_id)
	var definition: Dictionary = TERRAIN_DEFINITIONS.get(terrain_id, {
		"glyph":"", "base_hex":"#091017", "glyph_hex":"#091017", "edge_hex":"#060a0e",
		"font_ratio":0.52, "raised":false,
	})
	var result := definition.duplicate(true)
	var visibility := visibility_spec(cell)
	result["terrain_id"] = terrain_id
	result["visibility_state"] = visibility.state
	result["visible"] = bool(visibility.draw_terrain)
	result["opacity"] = float(visibility.opacity)
	result["registered"] = registered
	result["glyph_primary"] = registered and bool(visibility.draw_terrain)
	result["draw_image"] = false
	result["draw_tile_border"] = false
	result["draw_cell_surface"] = registered and terrain_id != "floor" \
		and bool(visibility.draw_terrain)
	result["background_source"] = "GRID_FLAT" if terrain_id == "floor" else "TERRAIN_FLAT"
	result["outline_hex"] = "#020508"
	return result.duplicate(true)


static func hazard_spec(cell: Dictionary) -> Dictionary:
	var visibility := visibility_spec(cell)
	var fire := clampi(int(cell.get("fire_intensity", cell.get("fire", 0))), 0, 100)
	var wetness := clampi(int(cell.get("wetness", 0)), 0, 100)
	var cues: Array[Dictionary] = []
	if bool(visibility.draw_hazards) and fire > 0:
		cues.append({"kind":"FIRE", "glyph":"*", "color_hex":"#ff7a3d", "value":fire,
			"corner":"BOTTOM_LEFT", "fill_alpha":0.12 + 0.34 * float(fire) / 100.0})
	if bool(visibility.draw_hazards) and wetness > 0:
		cues.append({"kind":"WET", "glyph":"~", "color_hex":"#62c8ff", "value":wetness,
			"corner":"BOTTOM_RIGHT", "fill_alpha":0.08 + 0.20 * float(wetness) / 100.0})
	# Conductivity remains inspectable simulation data, but it has no persistent
	# floor glyph. Electricity should be communicated only when an actual event
	# happens, not as a misleading lightning mark on every conductive tile.
	return {"visibility_state":visibility.state, "fire":fire, "wetness":wetness,
		"cues":cues}.duplicate(true)


static func feature_spec(feature_id: String) -> Dictionary:
	var definitions := {
		"run_entry":{"glyph":"<", "color_hex":"#55C8FF"},
		"run_exit_locked":{"glyph":"X", "color_hex":"#A36A73"},
		"run_exit_open":{"glyph":">", "color_hex":"#6EFFA8"},
		"open_door":{"glyph":"/", "color_hex":"#FFD166"},
	}
	if not definitions.has(feature_id):
		return {"visible":false, "feature_id":"", "glyph":"",
			"color_hex":"#FFFFFF"}.duplicate(true)
	var definition: Dictionary = definitions[feature_id]
	return {"visible":true, "feature_id":feature_id,
		"glyph":str(definition.glyph),
		"color_hex":str(definition.color_hex)}.duplicate(true)


static func actor_spec(actor: Dictionary, ghost: bool = false) -> Dictionary:
	var species_id := str(actor.get("species_id", "")).to_lower()
	var faction_id := str(actor.get("faction_id", "")).to_lower()
	var is_protagonist := bool(actor.get("is_protagonist", false))
	var is_enemy := bool(actor.get("is_enemy", false)) or faction_id == "enemy"
	var is_party := is_protagonist or faction_id == "party" or int(actor.get("roster_slot", -1)) >= 0
	var glyph := "?"
	var color_hex := "#d5e2ea"
	var highlight_hex := "#ffffff"
	if is_protagonist:
		glyph = "@"; color_hex = "#ffdc55"; highlight_hex = "#fff3a8"
	elif is_enemy:
		glyph = "G" if species_id in ["", "goblin"] else "?"
		color_hex = "#ff615c"; highlight_hex = "#ffc2a8"
	elif is_party and species_id == "goblin":
		glyph = "g"; color_hex = "#91e45f"; highlight_hex = "#dcffa4"
	elif is_party:
		glyph = "&"
		if int(actor.get("roster_slot", -1)) == 2:
			color_hex = "#759cff"; highlight_hex = "#d7e0ff"
		else:
			color_hex = "#5ed6ff"; highlight_hex = "#d0f4ff"

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
	var stance := str(actor.get("visual_stance", actor.get("stance", "IDLE"))).to_upper()
	if stance not in ["IDLE", "MOVING", "ENGAGE", "FLEE", "APPROACH", "GUARD"]:
		stance = "IDLE"
	var geometry := _pose_geometry(life_state, facing, stance)
	var guarded := bool(actor.get("guarded", false))
	return {
		"glyph":glyph, "color_hex":color_hex, "highlight_hex":highlight_hex,
		"shadow_hex":"#03070b", "outline_hex":"#0a1016",
		"opacity":0.46 if ghost else (0.58 if life_state == "DOWNED" else 1.0),
		"ghost":ghost, "life_state":life_state, "statuses":statuses,
		"bleeding":"BLEEDING" in statuses, "guarded":guarded,
		"facing":[facing.x, facing.y], "pose":geometry.pose, "stance":stance,
		"body_center":geometry.glyph_center, "glyph_center":geometry.glyph_center,
		"glyph_half_width":geometry.glyph_half_width,
		"glyph_half_height":geometry.glyph_half_height,
		"glyph_is_body":true, "detached_head":false,
		"glyph_weight":"OUTLINE_REDRAW", "glyph_outline_passes":8,
		"limb_segments":geometry.limb_segments,
		"guard_segments":_guard_geometry(facing) if guarded and life_state == "ACTIVE" else [],
		# Inventory and weapon legality remain canonical simulation data, but the
		# map/portrait grammar is deliberately glyph + attached limbs only.
		"equipment":{}, "draw_equipment":false, "equipment_primitive_count":0,
		"draw_head":false, "draw_limbs":life_state != "DEAD",
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


static func _pose_geometry(life_state: String, facing: Vector2i,
		stance: String = "IDLE") -> Dictionary:
	var half_width := 0.40
	var half_height := 0.18
	if life_state == "DOWNED":
		var center := Vector2(0.0, 0.25)
		return {"pose":"DOWNED", "glyph_center":center,
			"glyph_half_width":half_width, "glyph_half_height":half_height,
			"limb_segments":[
				[center+Vector2(-half_width,0.0),Vector2(-0.49,0.12)],
				[center+Vector2(half_width,0.0),Vector2(0.49,0.34)],
				[center+Vector2(-half_width*0.30,half_height),Vector2(-0.30,0.47)],
				[center+Vector2(half_width*0.30,half_height),Vector2(0.32,0.45)],
			]}
	if life_state == "DEAD":
		return {"pose":"DEAD", "glyph_center":Vector2(0.0,0.28),
			"glyph_half_width":half_width, "glyph_half_height":half_height,
			"limb_segments":[]}
	var direction := Vector2(facing).normalized()
	var center := Vector2(0.0,0.18)
	var left_edge := center+Vector2(-half_width,-0.01)
	var right_edge := center+Vector2(half_width,-0.01)
	var left_hip := center+Vector2(-half_width*0.28,half_height)
	var right_hip := center+Vector2(half_width*0.28,half_height)
	var stride := 0.10 if stance in ["MOVING", "APPROACH", "FLEE"] else 0.035
	var attack_lift := -0.13 if stance == "ENGAGE" else 0.0
	var facing_x := direction.x*0.065
	var facing_y := direction.y*0.040
	return {"pose":"STANDING", "glyph_center":center,
		"glyph_half_width":half_width, "glyph_half_height":half_height,
		"limb_segments":[
			[left_edge,Vector2(-0.49+facing_x,center.y+0.08-facing_y)],
			[right_edge,Vector2(0.49+facing_x,center.y+0.07+facing_y+attack_lift)],
			[left_hip,Vector2(-0.19-direction.x*stride,0.47-direction.y*0.025)],
			[right_hip,Vector2(0.19+direction.x*stride,0.47+direction.y*0.025)],
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
