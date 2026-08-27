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
var modal_open := false
var selected_actor_id := -1
var selected_target_id := -1

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
	if actor_id > 0: actor_pressed.emit(actor_id)
	else: world_cell_pressed.emit(p)
	accept_event()

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

func _key(p:Vector2i)->String: return "%d:%d"%[p.x,p.y]
