class_name PartyGridView
extends Control

signal world_cell_pressed(position: Vector2i)
signal actor_pressed(entity_id: int)

const GRID_SIZE := 15
const COLORS := {"floor":Color("#344351"),"wall":Color("#111923"),"shallow_water":Color("#215e71"),"rubble":Color("#6a5b3d")}
const CHARACTER_ATLAS: Texture2D = preload("res://assets/sprites/character_atlas.png")
const CHARACTER_FRAME_SIZE := Vector2i(36,44)
const CHARACTER_ATLAS_COLUMNS := 3
var world_grid_size := Vector2i(GRID_SIZE,GRID_SIZE)
var visible_cell_count := GRID_SIZE
var view_origin := Vector2i.ZERO
var _cells: Dictionary = {}
var _actors: Array[Dictionary] = []
var _ghosts: Array[Dictionary] = []
var _intent_overlays: Array[Dictionary] = []
var _secondary_intent_overlays: Array[Dictionary] = []
var _route_path: Array[Vector2i] = []
var _route_completed_steps := 0
var _route_valid := false
var modal_open := false
var selected_actor_id := -1
var selected_target_id := -1
var cursor_cell := Vector2i(-1, -1)
var preview_actor_id := -1
var preview_origin := Vector2i(-1, -1)
var preview_destination := Vector2i(-1, -1)
var preview_valid := false
var combat_emphasis := false
var _presentation_style: Dictionary = {}
var _active_visual_effects: Array[Dictionary] = []
var _played_effect_ids: Dictionary = {}
var _played_effect_event_ids: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP; focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; clip_contents=true; resized.connect(queue_redraw)
	set_process(false)

func set_observation(observation: Dictionary, ghosts: Array = []) -> void:
	_cells.clear(); _actors.clear(); _ghosts.clear()
	world_grid_size=Vector2i(maxi(1,int(observation.get("width",GRID_SIZE))),maxi(1,int(observation.get("height",GRID_SIZE))))
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

func set_view_window(cell_count:int,focus_points:Array=[],priority_points:Array=[])->void:
	visible_cell_count=clampi(cell_count,1,mini(world_grid_size.x,world_grid_size.y))
	if visible_cell_count>=world_grid_size.x and visible_cell_count>=world_grid_size.y:
		view_origin=Vector2i.ZERO; queue_redraw(); return
	var minimum:=Vector2i(world_grid_size.x-1,world_grid_size.y-1); var maximum:=Vector2i.ZERO; var found:=false
	for source in [focus_points,priority_points]:
		for raw in source:
			if not raw is Vector2i:continue
			var point:=raw as Vector2i
			if not _world_in_bounds(point):continue
			minimum=Vector2i(mini(minimum.x,point.x),mini(minimum.y,point.y))
			maximum=Vector2i(maxi(maximum.x,point.x),maxi(maximum.y,point.y)); found=true
	if found and (maximum.x-minimum.x>visible_cell_count-1 or maximum.y-minimum.y>visible_cell_count-1):
		visible_cell_count=mini(world_grid_size.x,world_grid_size.y)
		view_origin=Vector2i.ZERO;queue_redraw();return
	var center:=Vector2i(world_grid_size.x/2,world_grid_size.y/2)
	if found:center=Vector2i((minimum.x+maximum.x)/2,(minimum.y+maximum.y)/2)
	var next_origin:=center-Vector2i(visible_cell_count/2,visible_cell_count/2)
	if found:
		var minimum_origin:=Vector2i(maxi(0,maximum.x-visible_cell_count+1),maxi(0,maximum.y-visible_cell_count+1))
		var maximum_origin:=Vector2i(mini(minimum.x,world_grid_size.x-visible_cell_count),mini(minimum.y,world_grid_size.y-visible_cell_count))
		next_origin=Vector2i(clampi(next_origin.x,minimum_origin.x,maximum_origin.x),clampi(next_origin.y,minimum_origin.y,maximum_origin.y))
	next_origin=_clamp_view_origin(next_origin)
	view_origin=next_origin; queue_redraw()

func set_combat_emphasis(enabled:bool)->void:combat_emphasis=enabled;queue_redraw()

func set_presentation_style(value:Dictionary)->void:
	_presentation_style=value.duplicate(true)
	combat_emphasis=str(_presentation_style.get("style_id",""))=="COMBAT"
	queue_redraw()

func play_effects(rows:Array)->int:
	var started_at:=Time.get_ticks_msec();var appended:=0
	for raw in rows:
		if not raw is Dictionary:continue
		var effect_id:=str(raw.get("effect_id",""));var event_id:=int(raw.get("event_id",-1))
		if effect_id.is_empty() or event_id<0 or _played_effect_ids.has(effect_id):continue
		var row:Dictionary=raw.duplicate(true);row["started_at_ms"]=started_at
		_active_visual_effects.append(row);_played_effect_ids[effect_id]=true
		_played_effect_event_ids[event_id]=true;appended+=1
	if appended==0:return 0
	_active_visual_effects.sort_custom(func(a,b):
		if int(a.get("order",0))!=int(b.get("order",0)):return int(a.get("order",0))<int(b.get("order",0))
		return str(a.get("effect_id",""))<str(b.get("effect_id","")))
	if _active_visual_effects.size()>48:_active_visual_effects=_active_visual_effects.slice(_active_visual_effects.size()-48)
	set_process(true);queue_redraw();return appended

func has_played_effect_event(event_id:int)->bool:return _played_effect_event_ids.has(event_id)
func has_played_effect(effect_id:String)->bool:return _played_effect_ids.has(effect_id)

func visual_effect_draw_spec(effect:Dictionary)->Dictionary:
	var world_value=effect.get("world_position",[-1,-1]);var world_position:=Vector2i(-1,-1)
	if world_value is Array and world_value.size()==2:world_position=Vector2i(int(world_value[0]),int(world_value[1]))
	var kind:=str(effect.get("kind",""));var damage_type:=str(effect.get("damage_type","physical"))
	var color_hex:String={"fire":"#ff7a55","water":"#67c9ff","electric":"#ffe46b","poison":"#9ee86f","physical":"#fff0df"}.get(damage_type,"#fff0df")
	if kind=="DEATH":color_hex="#ff6b78"
	return {"effect_id":str(effect.get("effect_id","")),"event_id":int(effect.get("event_id",-1)),
		"kind":kind,"primitive":{"SLASH":"SLASH_LINES","HIT_FLASH":"FLASH_RING","FLOATING_AMOUNT":"TEXT","DEATH":"DEATH_CROSS"}.get(kind,"NONE"),
		"world_position":[world_position.x,world_position.y],"visible":is_world_cell_visible(world_position),
		"pixel_center":world_to_pixel_center(world_position),"color_hex":color_hex,
		"line_width":4.0 if kind in ["SLASH","DEATH"] else 3.0,
		"radius":cell_size_px()*(0.34 if kind=="HIT_FLASH" else 0.28),
		"text":str(effect.get("text","")),"font_size":18,
		"duration_ms":900 if kind in ["FLOATING_AMOUNT","DEATH"] else 520}.duplicate(true)

func _process(_delta:float)->void:
	if _active_visual_effects.is_empty():set_process(false);return
	var now:=Time.get_ticks_msec();var retained:Array[Dictionary]=[]
	for effect in _active_visual_effects:
		var spec:=visual_effect_draw_spec(effect)
		if now-int(effect.get("started_at_ms",now))<int(spec.duration_ms):retained.append(effect)
	_active_visual_effects=retained
	if _active_visual_effects.is_empty():set_process(false)
	queue_redraw()

func view_bounds()->Rect2i:return Rect2i(view_origin,Vector2i(visible_cell_count,visible_cell_count))
func is_world_cell_visible(position:Vector2i)->bool:return view_bounds().has_point(position)
func _world_in_bounds(position:Vector2i)->bool:
	return position.x>=0 and position.y>=0 and position.x<world_grid_size.x and position.y<world_grid_size.y
func _clamp_view_origin(origin:Vector2i)->Vector2i:
	return Vector2i(clampi(origin.x,0,maxi(0,world_grid_size.x-visible_cell_count)),
		clampi(origin.y,0,maxi(0,world_grid_size.y-visible_cell_count)))

func set_selection(actor_id: int, target_id: int = -1) -> void:
	selected_actor_id = actor_id; selected_target_id = target_id; queue_redraw()

func set_cursor_preview(actor_id: int, origin: Vector2i, destination: Vector2i, valid: bool) -> void:
	preview_actor_id = actor_id; preview_origin = origin; preview_destination = destination
	cursor_cell = destination; preview_valid = valid; queue_redraw()

func clear_cursor_preview() -> void:
	preview_actor_id = -1; preview_origin = Vector2i(-1, -1)
	preview_destination = Vector2i(-1, -1); cursor_cell = Vector2i(-1, -1)
	preview_valid = false; queue_redraw()

func set_route_overlay(path: Array, completed_steps: int = 0, valid: bool = true) -> void:
	_route_path.clear()
	for value in path:
		var point := Vector2i(-1,-1)
		if value is Vector2i:
			point = value
		elif value is Array and value.size() == 2:
			point = Vector2i(int(value[0]),int(value[1]))
		elif value is Dictionary:
			var raw: Variant = value.get("position",value.get("to_position",[]))
			if raw is Array and raw.size() == 2:
				point = Vector2i(int(raw[0]),int(raw[1]))
		if _world_in_bounds(point) and (_route_path.is_empty() or _route_path[-1] != point):
			_route_path.append(point)
	_route_completed_steps = clampi(completed_steps,0,maxi(0,_route_path.size()-1))
	_route_valid = valid and _route_path.size() >= 2
	queue_redraw()

func clear_route_overlay() -> void:
	_route_path.clear();_route_completed_steps=0;_route_valid=false;queue_redraw()

func route_draw_spec() -> Dictionary:
	var color_hex := "#65f29a" if _route_valid else "#ff6b78"
	var path_rows: Array = []
	var segments: Array = []
	var markers: Array = []
	for point in _route_path:
		path_rows.append([point.x,point.y])
	for index in range(maxi(0,_route_path.size()-1)):
		var from: Vector2i = _route_path[index]
		var to: Vector2i = _route_path[index+1]
		var visible := is_world_cell_visible(from) and is_world_cell_visible(to)
		segments.append({"index":index,"from_position":[from.x,from.y],"to_position":[to.x,to.y],
			"from_pixel":world_to_pixel_center(from),"to_pixel":world_to_pixel_center(to),
			"visible":visible,"completed":index<_route_completed_steps,
			"color_hex":"#607b87" if index<_route_completed_steps else color_hex,
			"line_width":2.5 if index<_route_completed_steps else 4.0})
	for index in range(_route_path.size()):
		var position: Vector2i = _route_path[index]
		var kind := "STEP"
		if index == 0:kind="START"
		elif index == _route_path.size()-1:kind="GOAL"
		elif index == _route_completed_steps+1:kind="NEXT"
		markers.append({"index":index,"position":[position.x,position.y],
			"pixel_center":world_to_pixel_center(position),"visible":is_world_cell_visible(position),
			"kind":kind,"completed":index<=_route_completed_steps,
			"color_hex":"#607b87" if index<=_route_completed_steps else color_hex,
			"radius":maxf(3.0,cell_size_px()*(0.20 if kind in ["START","GOAL"] else 0.12))})
	return {"path":path_rows,"valid":_route_valid,"completed_steps":_route_completed_steps,
		"segments":segments,"markers":markers,"color_hex":color_hex}.duplicate(true)

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
func cell_size_px() -> float: return grid_rect().size.x / float(visible_cell_count)
func world_cell_rect(position: Vector2i) -> Rect2:
	if not is_world_cell_visible(position):return Rect2()
	var rect := grid_rect(); var cell := cell_size_px(); var local:=position-view_origin
	return Rect2(rect.position+Vector2(local.x,local.y)*cell,Vector2(cell,cell))
func world_to_pixel_center(position: Vector2i) -> Vector2:
	if not is_world_cell_visible(position):return Vector2(-1,-1)
	return world_cell_rect(position).get_center()
func pixel_to_world_cell(pointer:Vector2)->Vector2i:
	var rect:=grid_rect()
	if not rect.has_point(pointer):return Vector2i(-1,-1)
	var local:=pointer-rect.position;var cell:=cell_size_px()
	var local_cell:=Vector2i(int(floor(local.x/cell)),int(floor(local.y/cell)))
	if local_cell.x<0 or local_cell.y<0 or local_cell.x>=visible_cell_count or local_cell.y>=visible_cell_count:return Vector2i(-1,-1)
	return view_origin+local_cell
func mapping_signature() -> Array:
	var rows: Array = [[view_origin.x,view_origin.y],visible_cell_count,[world_grid_size.x,world_grid_size.y]]
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var world:=view_origin+Vector2i(x,y); rows.append([[world.x,world.y],world_to_pixel_center(world)])
	return rows
func actor_hit_rect(entity_id: int) -> Rect2:
	for actor in _actors:
		if int(actor.entity_id) == entity_id:
			var p := Vector2i(int(actor.position[0]),int(actor.position[1]))
			if is_world_cell_visible(p):return Rect2(world_to_pixel_center(p)-Vector2(22,22),Vector2(44,44))
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
	var p:=pixel_to_world_cell(pointer)
	if p==Vector2i(-1,-1):return
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
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var p := view_origin+Vector2i(x,y); var row: Dictionary = _cells.get(_key(p),{}); var rect := world_cell_rect(p)
			draw_rect(rect,COLORS.get(str(row.get("terrain_id","floor")),COLORS.floor),true); draw_rect(rect,Color("#617183"),false,1)
	for actor in _actors:
		_draw_actor(actor, cell, false)
	for ghost in _ghosts:
		_draw_actor(ghost, cell, true)
	_draw_route_overlay()
	for intent in _secondary_intent_overlays:
		_draw_intent(intent)
	for intent in _intent_overlays:
		_draw_intent(intent)
	_draw_cursor_preview()
	for effect in _active_visual_effects:_draw_visual_effect(effect)
	var style_id:=str(_presentation_style.get("style_id","DEFAULT"))
	if combat_emphasis or bool(_presentation_style.get("vignette",false)):
		var border:=Color(str(_presentation_style.get("border_hex","#ff7a80")))
		draw_rect(grid_rect().grow(-2),border,false,4.0 if style_id=="COMBAT" else 2.5)

func _draw_visual_effect(effect:Dictionary)->void:
	var spec:=visual_effect_draw_spec(effect)
	if not bool(spec.visible):return
	var center:Vector2=spec.pixel_center;var color:=Color(str(spec.color_hex));var radius:=float(spec.radius);var width:=float(spec.line_width)
	match str(spec.primitive):
		"SLASH_LINES":
			draw_line(center+Vector2(-radius,radius),center+Vector2(radius,-radius),color,width)
			draw_line(center+Vector2(-radius*0.55,radius),center+Vector2(radius,radius*-0.55),color,maxf(2.0,width-1.0))
		"FLASH_RING":draw_arc(center,radius,0,TAU,20,color,width)
		"TEXT":draw_string(get_theme_default_font(),center+Vector2(-16,-radius),str(spec.text),HORIZONTAL_ALIGNMENT_CENTER,32,int(spec.font_size),color)
		"DEATH_CROSS":
			draw_line(center-Vector2(radius,radius),center+Vector2(radius,radius),color,width)
			draw_line(center+Vector2(radius,-radius),center+Vector2(-radius,radius),color,width)

func _draw_actor(actor: Dictionary, cell: float, ghost: bool) -> void:
	if not actor.get("position") is Array or actor.position.size() != 2: return
	var p := Vector2i(int(actor.position[0]),int(actor.position[1])); var rect := world_cell_rect(p)
	if not is_world_cell_visible(p):return
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
	if cursor_cell.x < 0 or not is_world_cell_visible(cursor_cell): return
	var color := Color("#65f29a") if preview_valid else Color("#ff5f68")
	var destination_rect := world_cell_rect(cursor_cell)
	draw_rect(destination_rect.grow(-1), Color(color, 0.20), true)
	draw_rect(destination_rect.grow(-1), color, false, 4.0)
	if _route_path.size() < 2 and preview_origin.x >= 0 and is_world_cell_visible(preview_origin):
		_draw_arrow(world_to_pixel_center(preview_origin), world_to_pixel_center(preview_destination), color, 3.5, false)

func _draw_route_overlay() -> void:
	if _route_path.size()<2:return
	var spec:=route_draw_spec()
	for segment in spec.segments:
		if not bool(segment.visible):continue
		draw_line(segment.from_pixel,segment.to_pixel,Color(str(segment.color_hex)),float(segment.line_width),true)
	for marker in spec.markers:
		if not bool(marker.visible):continue
		var center:Vector2=marker.pixel_center;var radius:=float(marker.radius);var color:=Color(str(marker.color_hex))
		match str(marker.kind):
			"GOAL":
				draw_colored_polygon(PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius,0),
					center+Vector2(0,radius),center+Vector2(-radius,0)]),Color(color,0.55))
			"START":draw_arc(center,radius,0,TAU,16,color,2.0)
			"NEXT":draw_circle(center,radius,Color(color,0.90))
			_:draw_circle(center,radius,Color(color,0.65))

func _draw_intent(intent: Dictionary) -> void:
	if not intent.get("from_position") is Array or intent.from_position.size() != 2: return
	var origin := Vector2i(int(intent.from_position[0]), int(intent.from_position[1]))
	if not is_world_cell_visible(origin):return
	var spec := intent_draw_spec(intent)
	var color := Color(str(spec.color_hex))
	var action_type := str(spec.action_type)
	if action_type == "MOVE" and intent.get("destination") is Array and intent.destination.size() == 2:
		var destination := Vector2i(int(intent.destination[0]), int(intent.destination[1]))
		if not is_world_cell_visible(destination):return
		_draw_arrow(world_to_pixel_center(origin), world_to_pixel_center(destination), color,
			float(spec.line_width), bool(spec.dashed))
		_draw_source_marker(destination, str(spec.marker_style), color)
	elif action_type == "MELEE" and intent.get("target_position") is Array and intent.target_position.size() == 2:
		var target := Vector2i(int(intent.target_position[0]), int(intent.target_position[1]))
		if not is_world_cell_visible(target):return
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
