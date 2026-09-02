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
	"grass": 73,
	"poison": 79,
	"ice": 83,
	"fog": 87,
	"wall": 89,
}

const _MARK_DEFINITIONS := {
	"floor": {"kind":"DUST", "glyph":".", "density":14},
	"stone_floor": {"kind":"CRACK", "glyph":":", "density":22},
	"wood_floor": {"kind":"PLANK", "glyph":"=", "density":58},
	"metal": {"kind":"SHEEN", "glyph":"+", "density":52},
	"rubble": {"kind":"DEBRIS", "glyph":",", "density":72},
	"shallow_water": {"kind":"RIPPLE", "glyph":"~", "density":68},
	"grass": {"kind":"TUFT", "glyph":"\"", "density":54},
	"poison": {"kind":"BUBBLE", "glyph":"%", "density":42},
	"ice": {"kind":"GLINT", "glyph":"*", "density":34},
	"fog": {"kind":"VEIL", "glyph":".", "density":30},
	"wall": {"kind":"MASONRY", "glyph":"#", "density":34},
}

const ACTOR_MOTION_DEFAULT_MS := 150
const ACTOR_MOTION_MIN_MS := 70
const ACTOR_MOTION_MAX_MS := 180

# The gameplay grid remains integer 2D authority. These values only project its
# presentation into the optional camera-following typographic diorama.
# target: a low pitch, strong perspective and a little extra screen-depth so a
# square mobile viewport does not collapse into a thin horizontal strip.
const CAMERA_PITCH_DEGREES := 30.0
const CAMERA_PERSPECTIVE := 0.78
const CAMERA_DISTANCE_CELLS := 22.0
const CAMERA_DEPTH_STRETCH := 1.65
const CAMERA_NEAR_WIDTH_RATIO := 0.90
const WALL_HEIGHT_CELL_RATIO := 0.72


static func perspective_projection_spec(viewport:Rect2,cell_count:int)->Dictionary:
	var count:=maxi(1,cell_count)
	var pitch:=deg_to_rad(CAMERA_PITCH_DEGREES)
	var half_count:=float(count)*0.5
	var near_depth:=half_count*cos(pitch)
	var near_pf:=CAMERA_DISTANCE_CELLS/maxf(5.0,CAMERA_DISTANCE_CELLS-near_depth)
	var near_factor:=(1.0-CAMERA_PERSPECTIVE)+CAMERA_PERSPECTIVE*near_pf
	var base_scale:=viewport.size.x*CAMERA_NEAR_WIDTH_RATIO \
		/(float(count)*maxf(0.01,near_factor))
	return {"pitch_degrees":CAMERA_PITCH_DEGREES,"pitch_radians":pitch,
		"perspective":CAMERA_PERSPECTIVE,"camera_distance":CAMERA_DISTANCE_CELLS,
		"depth_stretch":CAMERA_DEPTH_STRETCH,"base_scale":base_scale,
		"cell_count":count,"center":viewport.get_center(),
		"near_factor":near_factor,"near_width_ratio":CAMERA_NEAR_WIDTH_RATIO}.duplicate(true)


static func project_camera_point(local_point:Vector2,viewport:Rect2,
		cell_count:int)->Vector2:
	var spec:=perspective_projection_spec(viewport,cell_count)
	var center:Vector2=spec.center
	var pitch:=float(spec.pitch_radians)
	var half_count:=float(int(spec.cell_count))*0.5
	var x:=local_point.x-half_count
	var z:=local_point.y-half_count
	var depth:=z*cos(pitch)
	var denominator:=maxf(5.0,float(spec.camera_distance)-depth)
	var perspective_factor:=float(spec.camera_distance)/denominator
	var scale:=float(spec.base_scale)*((1.0-float(spec.perspective)) \
		+float(spec.perspective)*perspective_factor)
	return Vector2(center.x+x*scale,
		center.y+z*sin(pitch)*scale*float(spec.depth_stretch))


static func perspective_cell_polygon(local_cell:Vector2i,viewport:Rect2,
		cell_count:int)->PackedVector2Array:
	return PackedVector2Array([
		project_camera_point(Vector2(local_cell),viewport,cell_count),
		project_camera_point(Vector2(local_cell)+Vector2.RIGHT,viewport,cell_count),
		project_camera_point(Vector2(local_cell)+Vector2.ONE,viewport,cell_count),
		project_camera_point(Vector2(local_cell)+Vector2.DOWN,viewport,cell_count),
	])


static func polygon_bounds(points:PackedVector2Array)->Rect2:
	if points.is_empty():return Rect2()
	var minimum:=points[0];var maximum:=points[0]
	for point in points:
		minimum=Vector2(minf(minimum.x,point.x),minf(minimum.y,point.y))
		maximum=Vector2(maxf(maximum.x,point.x),maxf(maximum.y,point.y))
	return Rect2(minimum,maximum-minimum)


static func perspective_cell_center(local_cell:Vector2i,viewport:Rect2,
		cell_count:int)->Vector2:
	return project_camera_point(Vector2(local_cell)+Vector2(0.5,0.5),viewport,cell_count)


static func perspective_wall_block(cell_polygon:PackedVector2Array,
		opacity:float=1.0)->Dictionary:
	if cell_polygon.size()!=4:
		return {"visible":false,"top":PackedVector2Array(),
			"front":PackedVector2Array(),"right":PackedVector2Array(),
			"height":0.0}.duplicate(true)
	var bounds:=polygon_bounds(cell_polygon)
	var height:=clampf(bounds.size.x*WALL_HEIGHT_CELL_RATIO,8.0,34.0)
	var lift:=Vector2(0,-height)
	var top:=PackedVector2Array()
	for point in cell_polygon:top.append(point+lift)
	return {"visible":true,"height":height,"lift":lift,"top":top,
		"front":PackedVector2Array([top[3],top[2],cell_polygon[2],cell_polygon[3]]),
		"right":PackedVector2Array([top[1],top[2],cell_polygon[2],cell_polygon[1]]),
		"opacity":clampf(opacity,0.0,1.0),"draw_image":false,
		"changes_mapping":false}.duplicate(true)


static func terrain_depth_spec(cell:Dictionary,cell_size:float)->Dictionary:
	var observed:=sanitize_observed_cell(cell)
	var visibility_state:=str(observed.get("visibility_state","UNSEEN"))
	var terrain_id:=str(observed.get("terrain_id",""))
	var raised:=visibility_state!="UNSEEN" and terrain_id=="wall"
	var extrusion_px:=clampf(cell_size*0.12,2.0,4.0) if raised else 0.0
	var opacity:=1.0 if visibility_state=="VISIBLE" else (0.28 \
		if visibility_state=="MEMORY" else 0.0)
	return {"visible":visibility_state!="UNSEEN","visibility_state":visibility_state,
		"terrain_id":terrain_id,"raised":raised,"extrusion_px":extrusion_px,
		"side_offset":Vector2(0,extrusion_px),"shadow_offset":Vector2(extrusion_px*0.72,
			extrusion_px*1.18) if raised else Vector2.ZERO,
		"side_hex":"#070b12","shadow_hex":"#010304","opacity":opacity,
		"draw_cell_border":false,"draw_image":false}.duplicate(true)


static func layer_order() -> Array:
	return DRAW_LAYERS.duplicate()


static func actor_motion_sample(from_world: Vector2, to_world: Vector2,
		elapsed_ms: int, duration_ms: int = ACTOR_MOTION_DEFAULT_MS) -> Dictionary:
	var safe_duration := clampi(duration_ms, ACTOR_MOTION_MIN_MS, ACTOR_MOTION_MAX_MS)
	var progress := clampf(float(maxi(0, elapsed_ms)) / float(safe_duration), 0.0, 1.0)
	var remaining := 1.0 - progress
	var eased := 1.0 - remaining * remaining * remaining
	var step_phase := "SETTLE"
	var stride_sign := 0
	if progress < 0.30:
		step_phase = "CONTACT"
		stride_sign = 1
	elif progress < 0.74:
		step_phase = "PASS"
		stride_sign = -1
	var bob_ratio := -sin(PI * progress) if progress < 1.0 else 0.0
	return {
		"active":progress < 1.0 and not from_world.is_equal_approx(to_world),
		"duration_ms":safe_duration,
		"progress":progress,
		"eased_progress":eased,
		"world_position":from_world.lerp(to_world, eased),
		"step_phase":step_phase,
		"stride_sign":stride_sign,
		"glyph_bob_ratio":bob_ratio,
	}.duplicate(true)


static func quantized_light_spec(position:Vector2i,hero_position:Vector2i,
		visibility_state:String)->Dictionary:
	var state:=visibility_state.to_upper()
	if state=="UNSEEN":
		return {"band":"UNSEEN","distance":-1,"background_multiplier":0.0,
			"foreground_multiplier":0.0,"saturation":0.0}.duplicate(true)
	if state=="MEMORY":
		return {"band":"MEMORY","distance":-1,"background_multiplier":0.74,
			"foreground_multiplier":0.72,"saturation":0.14}.duplicate(true)
	if hero_position==Vector2i(-1,-1):
		return {"band":"UNANCHORED","distance":-1,"background_multiplier":1.0,
			"foreground_multiplier":1.0,"saturation":1.0}.duplicate(true)
	var distance:=maxi(absi(position.x-hero_position.x),absi(position.y-hero_position.y))
	if distance<=2:
		return {"band":"NEAR","distance":distance,"background_multiplier":1.0,
			"foreground_multiplier":1.0,"saturation":1.0}.duplicate(true)
	if distance<=4:
		return {"band":"MID","distance":distance,"background_multiplier":0.82,
			"foreground_multiplier":0.90,"saturation":0.92}.duplicate(true)
	return {"band":"EDGE","distance":distance,"background_multiplier":0.64,
		"foreground_multiplier":0.76,"saturation":0.78}.duplicate(true)


static func wall_role_spec(connected_mask:int,exposed_mask:int)->Dictionary:
	var mask:=connected_mask&ALL_CARDINALS
	var connection_count:=0
	for bit in [NORTH,EAST,SOUTH,WEST]:
		if mask&bit:connection_count+=1
	var role:="END"
	if connection_count==4:
		role="SOLID"
	elif connection_count>=3:
		role="JUNCTION"
	elif connection_count==2:
		role="STRAIGHT" if mask in [NORTH|SOUTH,EAST|WEST] else "CORNER"
	var emphasis:=float({"END":1.0,"CORNER":0.98,"JUNCTION":1.0,
		"STRAIGHT":0.90,"SOLID":0.78}.get(role,0.90))
	return {"role":role,"connected_mask":mask,"exposed_mask":exposed_mask,
		"connection_count":connection_count,"core_glyph":"#",
		"face_glyph":"#" if exposed_mask&SOUTH else "",
		"face_visible":bool(exposed_mask&SOUTH),"foreground_emphasis":emphasis,
		"slab_ratio":Vector2(0.94,0.92),
		"glyph_offset":Vector2(0.0,-0.025 if role in ["END","CORNER"] else 0.0),
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
			"visible":false, "fire":0, "wetness":0,
			"phase":0, "fire_glow_alpha":0.0, "wet_reflection_alpha":0.0,
		}.duplicate(true)
	var fire := clampi(int(row.get("fire_intensity", row.get("fire", 0))), 0, 100)
	var wetness := clampi(int(row.get("wetness", 0)), 0, 100)
	return {
		"visible":fire > 0 or wetness > 0,
		"fire":fire,
		"wetness":wetness,
		"phase":visual_hash(position, 131) % 4,
		"fire_glow_alpha":0.08 + 0.24 * float(fire) / 100.0 if fire > 0 else 0.0,
		"wet_reflection_alpha":0.06 + 0.18 * float(wetness) / 100.0 if wetness > 0 else 0.0,
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
