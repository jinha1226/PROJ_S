class_name PartyGridView
extends Control

signal world_cell_pressed(position: Vector2i)
signal actor_pressed(entity_id: int)

const GRID_SIZE := 15
const COLORS := {"floor":Color("#344351"),"wall":Color("#111923"),"shallow_water":Color("#215e71"),"rubble":Color("#6a5b3d")}
const CHARACTER_ATLAS: Texture2D = preload("res://assets/sprites/character_atlas.png")
const CHARACTER_FRAME_SIZE := Vector2i(36,44)
const CHARACTER_ATLAS_COLUMNS := 3
var _cells: Dictionary = {}
var _actors: Array[Dictionary] = []
var _ghosts: Array[Dictionary] = []
var _intent_overlays: Array[Dictionary] = []
var _secondary_intent_overlays: Array[Dictionary] = []
var modal_open := false
var selected_actor_id := -1
var selected_target_id := -1
var cursor_cell := Vector2i(-1, -1)
var preview_actor_id := -1
var preview_origin := Vector2i(-1, -1)
var preview_destination := Vector2i(-1, -1)
var preview_valid := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP; focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; resized.connect(queue_redraw)

func set_observation(observation: Dictionary, ghosts: Array = []) -> void:
	_cells.clear(); _actors.clear(); _ghosts.clear()
	for raw in observation.get("cells",[]):
		var row: Dictionary = raw.duplicate(true); var p := Vector2i(int(row.position[0]),int(row.position[1])); _cells[_key(p)] = row
		for actor in row.get("actors",[]):
			var copy: Dictionary = actor.duplicate(true); copy["position"] = [p.x,p.y]; _actors.append(copy)
	_actors.sort_custom(func(a,b):
		if bool(a.is_protagonist) != bool(b.is_protagonist): return bool(a.is_protagonist)
		if int(a.roster_slot) != int(b.roster_slot): return int(a.roster_slot) < int(b.roster_slot)
		return int(a.entity_id) < int(b.entity_id))
	var visible_actor_ids: Dictionary = {}
	for actor in _actors: visible_actor_ids[int(actor.entity_id)] = true
	for raw_ghost in ghosts:
		if raw_ghost is Dictionary and not visible_actor_ids.has(int(raw_ghost.get("entity_id",-1))):
			_ghosts.append(raw_ghost.duplicate(true))
	_ghosts.sort_custom(func(a,b):
		if int(a.get("roster_slot",99)) != int(b.get("roster_slot",99)): return int(a.get("roster_slot",99)) < int(b.get("roster_slot",99))
		return int(a.get("entity_id",-1)) < int(b.get("entity_id",-1)))
	queue_redraw()

func set_selection(actor_id: int, target_id: int = -1) -> void:
	selected_actor_id = actor_id; selected_target_id = target_id; queue_redraw()

func set_cursor_preview(actor_id: int, origin: Vector2i, destination: Vector2i, valid: bool) -> void:
	preview_actor_id = actor_id; preview_origin = origin; preview_destination = destination
	cursor_cell = destination; preview_valid = valid; queue_redraw()

func clear_cursor_preview() -> void:
	preview_actor_id = -1; preview_origin = Vector2i(-1, -1)
	preview_destination = Vector2i(-1, -1); cursor_cell = Vector2i(-1, -1)
	preview_valid = false; queue_redraw()

func set_intent_overlays(rows: Array) -> void:
	_intent_overlays.clear(); _secondary_intent_overlays.clear()
	for row in rows:
		if not row is Dictionary: continue
		var copy:Dictionary=row.duplicate(true); var secondary=copy.get("automatic_suggestion",null)
		if secondary is Dictionary:_secondary_intent_overlays.append(secondary.duplicate(true))
		_intent_overlays.append(copy)
	queue_redraw()

func grid_rect() -> Rect2:
	var extent := minf(size.x,size.y); return Rect2((size-Vector2(extent,extent))*0.5,Vector2(extent,extent))
func cell_size_px() -> float: return grid_rect().size.x / GRID_SIZE
func world_cell_rect(position: Vector2i) -> Rect2:
	var rect := grid_rect(); var cell := cell_size_px(); return Rect2(rect.position+Vector2(position.x,position.y)*cell,Vector2(cell,cell))
func world_to_pixel_center(position: Vector2i) -> Vector2: return world_cell_rect(position).get_center()
func mapping_signature() -> Array:
	var rows: Array = []; for y in range(15): for x in range(15): rows.append(world_to_pixel_center(Vector2i(x,y)))
	return rows
func actor_hit_rect(entity_id: int) -> Rect2:
	for actor in _actors:
		if int(actor.entity_id) == entity_id:
			var p := Vector2i(int(actor.position[0]),int(actor.position[1])); return Rect2(world_to_pixel_center(p)-Vector2(22,22),Vector2(44,44))
	return Rect2()
func actor_at_pointer(pointer: Vector2) -> int:
	var matches: Array = []
	for actor in _actors:
		if actor_hit_rect(int(actor.entity_id)).has_point(pointer):
			var p := Vector2i(int(actor.position[0]),int(actor.position[1])); matches.append({"id":int(actor.entity_id),"distance":pointer.distance_squared_to(world_to_pixel_center(p)),"protagonist":bool(actor.is_protagonist),"slot":int(actor.roster_slot)})
	matches.sort_custom(func(a,b):
		if a.distance != b.distance: return a.distance < b.distance
		if a.protagonist != b.protagonist: return a.protagonist
		if a.slot != b.slot: return a.slot < b.slot
		return a.id < b.id)
	return -1 if matches.is_empty() else int(matches[0].id)

func actor_in_world_cell(position: Vector2i) -> int:
	var matches: Array = []
	for actor in _actors:
		if Vector2i(int(actor.position[0]), int(actor.position[1])) == position:
			matches.append(actor)
	matches.sort_custom(func(a,b):
		if bool(a.is_protagonist) != bool(b.is_protagonist): return bool(a.is_protagonist)
		if int(a.roster_slot) != int(b.roster_slot): return int(a.roster_slot) < int(b.roster_slot)
		return int(a.entity_id) < int(b.entity_id))
	return -1 if matches.is_empty() else int(matches[0].entity_id)

func _gui_input(event: InputEvent) -> void:
	if modal_open or event is InputEventKey and event.echo: return
	var pressed := false; var pointer := Vector2.ZERO
	if event is InputEventMouseButton: pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT; pointer = event.position
	elif event is InputEventScreenTouch: pressed = event.pressed; pointer = event.position
	if not pressed: return
	var rect := grid_rect()
	if not rect.has_point(pointer): return
	var local := pointer-rect.position; var cell := cell_size_px(); var p := Vector2i(int(floor(local.x/cell)),int(floor(local.y/cell)))
	if p.x < 0 or p.y < 0 or p.x >= 15 or p.y >= 15: return
	var actor_id := actor_in_world_cell(p)
	if actor_id > 0:
		actor_pressed.emit(actor_id)
	elif _empty_cell_center_zone(p,pointer):
		world_cell_pressed.emit(p)
	else:
		var nearby_actor_id:=actor_at_pointer(pointer)
		if nearby_actor_id>0:actor_pressed.emit(nearby_actor_id)
		else:world_cell_pressed.emit(p)
	accept_event()

func _empty_cell_center_zone(position:Vector2i,pointer:Vector2)->bool:
	var inset:=cell_size_px()*0.25
	return world_cell_rect(position).grow(-inset).has_point(pointer)

func _draw() -> void:
	var cell := cell_size_px()
	for y in range(15):
		for x in range(15):
			var p := Vector2i(x,y); var row: Dictionary = _cells.get(_key(p),{}); var rect := world_cell_rect(p)
			draw_rect(rect,COLORS.get(str(row.get("terrain_id","floor")),COLORS.floor),true); draw_rect(rect,Color("#617183"),false,1)
	for actor in _actors:
		_draw_actor(actor, cell, false)
	for ghost in _ghosts:
		_draw_actor(ghost, cell, true)
	for intent in _secondary_intent_overlays:
		_draw_intent(intent)
	for intent in _intent_overlays:
		_draw_intent(intent)
	_draw_cursor_preview()

func _draw_actor(actor: Dictionary, cell: float, ghost: bool) -> void:
	if not actor.get("position") is Array or actor.position.size() != 2: return
	var p := Vector2i(int(actor.position[0]),int(actor.position[1])); var rect := world_cell_rect(p)
	var frame := int(actor.get("sprite_frame", 4 if ghost else 0))
	var source := Rect2(Vector2((frame % CHARACTER_ATLAS_COLUMNS) * CHARACTER_FRAME_SIZE.x,
		floori(float(frame) / CHARACTER_ATLAS_COLUMNS) * CHARACTER_FRAME_SIZE.y), Vector2(CHARACTER_FRAME_SIZE))
	var sprite_height := minf(34.0, floorf(cell * 1.55)); var sprite_width := roundf(sprite_height * 36.0 / 44.0)
	var destination := Rect2(Vector2(roundf(rect.get_center().x-sprite_width*0.5), roundf(rect.end.y-sprite_height+1.0)), Vector2(sprite_width,sprite_height))
	var tint := Color(0.55,0.82,1.0,0.48) if ghost else Color.WHITE
	draw_texture_rect_region(CHARACTER_ATLAS,destination,source,tint)
	var entity_id := int(actor.get("entity_id",-1))
	if entity_id == selected_actor_id and not ghost: draw_rect(rect.grow(-1),Color("#ffd467"),false,2.5)
	if entity_id == selected_target_id and not ghost: draw_rect(rect.grow(-1),Color("#ff6b70"),false,2.5)
	if ghost: draw_rect(rect.grow(-2),Color(0.45,0.8,1.0,0.75),false,1.5)

func _draw_cursor_preview() -> void:
	if cursor_cell.x < 0: return
	var color := Color("#65f29a") if preview_valid else Color("#ff5f68")
	var destination_rect := world_cell_rect(cursor_cell)
	draw_rect(destination_rect.grow(-1), Color(color, 0.20), true)
	draw_rect(destination_rect.grow(-1), color, false, 4.0)
	if preview_origin.x >= 0:
		_draw_arrow(world_to_pixel_center(preview_origin), world_to_pixel_center(preview_destination), color, 3.5, false)

func _draw_intent(intent: Dictionary) -> void:
	if not intent.get("from_position") is Array or intent.from_position.size() != 2: return
	var origin := Vector2i(int(intent.from_position[0]), int(intent.from_position[1]))
	var spec := intent_draw_spec(intent)
	var color := Color(str(spec.color_hex))
	var action_type := str(spec.action_type)
	if action_type == "MOVE" and intent.get("destination") is Array and intent.destination.size() == 2:
		var destination := Vector2i(int(intent.destination[0]), int(intent.destination[1]))
		_draw_arrow(world_to_pixel_center(origin), world_to_pixel_center(destination), color,
			float(spec.line_width), bool(spec.dashed))
		_draw_source_marker(destination, str(spec.marker_style), color)
	elif action_type == "MELEE" and intent.get("target_position") is Array and intent.target_position.size() == 2:
		var target := Vector2i(int(intent.target_position[0]), int(intent.target_position[1]))
		_draw_arrow(world_to_pixel_center(origin), world_to_pixel_center(target), color,
			float(spec.line_width), bool(spec.dashed))
		var center := world_to_pixel_center(target); var radius := cell_size_px() * 0.28
		draw_line(center-Vector2(radius,radius), center+Vector2(radius,radius), color, float(spec.line_width))
		draw_line(center+Vector2(radius,-radius), center+Vector2(-radius,radius), color, float(spec.line_width))
		_draw_source_marker(target, str(spec.marker_style), color)
	else:
		var center := world_to_pixel_center(origin); var radius := cell_size_px() * 0.30
		_draw_ring(center, radius, color, float(spec.line_width), bool(spec.dashed), int(spec.dash_segments))
		_draw_source_marker(origin, str(spec.marker_style), color)

func intent_draw_spec(intent: Dictionary) -> Dictionary:
	# Presentation DTO fields are authoritative. Source-based defaults only keep
	# older detached callers legible; Canvas drawing consumes this exact projection.
	var source := str(intent.get("source", "SUGGESTED"))
	var line_style := str(intent.get("line_style", {
		"OVERRIDE":"SOLID_THICK", "DIRECT":"SOLID", "SUGGESTED":"DASHED_THIN"}.get(source,"SOLID")))
	var marker_style := str(intent.get("marker_style", {
		"OVERRIDE":"SQUARE", "DIRECT":"DIAMOND", "SUGGESTED":"CIRCLE"}.get(source,"CIRCLE")))
	var width: float = float({"DASHED_THIN":2.0, "SOLID_THICK":4.5, "SOLID":3.0}.get(line_style,3.0))
	return {"action_type":str(intent.get("type","HOLD")),
		"primitive":"RING" if str(intent.get("type","HOLD"))=="HOLD" else "ARROW",
		"line_style":line_style, "line_width":width,
		"dashed":line_style=="DASHED_THIN", "dash_segments":8 if line_style=="DASHED_THIN" else 0,
		"marker_style":marker_style,
		"color_hex":str(intent.get("source_color", {
			"DIRECT":"#ffd467", "OVERRIDE":"#ff9f68", "SUGGESTED":"#75c8ff"}.get(source,"#75c8ff")))}.duplicate(true)

func _draw_ring(center: Vector2, radius: float, color: Color, width: float,
		dashed: bool, dash_segments: int) -> void:
	if not dashed:
		draw_arc(center, radius, 0, TAU, 24, color, width)
		return
	var segments := maxi(1,dash_segments)
	var slice := TAU/float(segments)
	for index in range(segments):
		var start := float(index)*slice
		draw_arc(center,radius,start,start+slice*0.52,4,color,width)

func _draw_arrow(from: Vector2, to: Vector2, color: Color, width: float, dashed: bool) -> void:
	var delta := to-from
	if delta.length() < 1.0: return
	if dashed:
		for index in range(4):
			var start := from + delta * (float(index) / 4.0)
			var finish := from + delta * (float(index) / 4.0 + 0.13)
			draw_line(start, finish, color, width)
	else: draw_line(from, to, color, width)
	var direction := delta.normalized(); var side := Vector2(-direction.y,direction.x)
	draw_colored_polygon(PackedVector2Array([to, to-direction*10.0+side*5.0, to-direction*10.0-side*5.0]), color)

func _draw_source_marker(position: Vector2i, marker_style: String, color: Color) -> void:
	var center := world_to_pixel_center(position); var radius := cell_size_px() * 0.24
	if marker_style == "DIAMOND":
		draw_colored_polygon(PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius,0),
			center+Vector2(0,radius),center+Vector2(-radius,0)]),Color(color,0.38))
		draw_polyline(PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius,0),
			center+Vector2(0,radius),center+Vector2(-radius,0),center+Vector2(0,-radius)]),color,2.5)
	elif marker_style == "SQUARE":
		draw_rect(Rect2(center-Vector2(radius,radius),Vector2(radius*2,radius*2)),Color(color,0.30),true)
		draw_rect(Rect2(center-Vector2(radius,radius),Vector2(radius*2,radius*2)),color,false,3.5)
	else:
		draw_circle(center,radius,Color(color,0.25)); draw_arc(center,radius,0,TAU,18,color,2.5)

func _key(p:Vector2i)->String: return "%d:%d"%[p.x,p.y]
