class_name PartyGridView
extends Control

signal world_cell_pressed(position: Vector2i)
signal actor_pressed(entity_id: int)
signal tile_long_pressed(position: Vector2i)
signal pointer_gesture_started()
signal pointer_gesture_finished(outcome: String)

const GRID_SIZE := 15
const COLORS := {"floor":Color("#344351"),"wall":Color("#111923"),"shallow_water":Color("#215e71"),"rubble":Color("#6a5b3d")}
const CHARACTER_ATLAS: Texture2D = preload("res://assets/sprites/character_atlas.png")
const CHARACTER_FRAME_SIZE := Vector2i(36,44)
const CHARACTER_ATLAS_COLUMNS := 3
const AsciiStyleScript = preload("res://playtest/ascii_visual_style.gd")
const AsciiPortraitScript = preload("res://playtest/ascii_actor_portrait.gd")
const LONG_PRESS_SECONDS := 0.50
const POINTER_SLOP_PX := 14.0
const EMULATED_MOUSE_SUPPRESS_MSEC := 300
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
var _exploration_follow_plan: Dictionary = {}
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
var _pointer_gesture_active := false
var _pointer_gesture_kind := ""
var _pointer_gesture_index := -1
var _pointer_gesture_cell := Vector2i(-1,-1)
var _pointer_gesture_target_kind := ""
var _pointer_gesture_target_actor_id := -1
var _pointer_gesture_start := Vector2.ZERO
var _pointer_gesture_last := Vector2.ZERO
var _pointer_gesture_long_fired := false
var _pointer_gesture_cancelled := false
var _pointer_gesture_generation := 0
var _suppress_mouse_until_msec := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP; focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; clip_contents=true; resized.connect(queue_redraw)
	set_process(false)

func _exit_tree()->void:
	_reset_pointer_gesture()

func set_observation(observation: Dictionary, ghosts: Array = []) -> void:
	cancel_pointer_gesture()
	_cells.clear(); _actors.clear(); _ghosts.clear()
	world_grid_size=Vector2i(maxi(1,int(observation.get("width",GRID_SIZE))),maxi(1,int(observation.get("height",GRID_SIZE))))
	for raw in observation.get("cells",[]):
		var row: Dictionary = raw.duplicate(true); var p := Vector2i(int(row.position[0]),int(row.position[1])); _cells[_key(p)] = row
	for raw in observation.get("cells",[]):
		var row: Dictionary = raw.duplicate(true); var p := Vector2i(int(row.position[0]),int(row.position[1]))
		if AsciiStyleScript.visibility_state(row)=="VISIBLE":
			for actor in row.get("actors",[]):
				var copy: Dictionary = actor.duplicate(true)
				var display_position:=_validated_display_position(copy,p)
				var logical_position:=_validated_logical_position(copy,p)
				copy["logical_position"]=[logical_position.x,logical_position.y]
				copy["display_position"]=[display_position.x,display_position.y]
				copy["position"]=[display_position.x,display_position.y]
				_actors.append(copy)
	_actors.sort_custom(func(a,b):
		if bool(a.get("is_protagonist",false)) != bool(b.get("is_protagonist",false)): return bool(a.get("is_protagonist",false))
		if int(a.get("roster_slot",99)) != int(b.get("roster_slot",99)): return int(a.get("roster_slot",99)) < int(b.get("roster_slot",99))
		return int(a.get("entity_id",-1)) < int(b.get("entity_id",-1)))
	var visible_actor_keys: Dictionary = {}
	for actor in _actors:
		if str(actor.get("display_role","")).to_upper()=="FOLLOWER":continue
		var actor_position:=_position_from_actor(actor)
		visible_actor_keys[_actor_visual_key(int(actor.get("entity_id",-1)),actor_position)]=true
	for raw_ghost in ghosts:
		if raw_ghost is Dictionary:
			var ghost_position:=_position_from_actor(raw_ghost)
			var ghost_key:=_actor_visual_key(int(raw_ghost.get("entity_id",-1)),ghost_position)
			if not visible_actor_keys.has(ghost_key) and ghost_position!=Vector2i(-1,-1) \
					and _cell_accepts_actor_input(ghost_position):
				var ghost_copy:Dictionary=raw_ghost.duplicate(true)
				ghost_copy["position"]=[ghost_position.x,ghost_position.y]
				_ghosts.append(ghost_copy)
				visible_actor_keys[ghost_key]=true
	_ghosts.sort_custom(func(a,b):
		if int(a.get("roster_slot",99)) != int(b.get("roster_slot",99)): return int(a.get("roster_slot",99)) < int(b.get("roster_slot",99))
		return int(a.get("entity_id",-1)) < int(b.get("entity_id",-1)))
	queue_redraw()

func set_view_window(cell_count:int,focus_points:Array=[],priority_points:Array=[])->void:
	cancel_pointer_gesture()
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

func set_exploration_companion_follow_plan(dto:Dictionary)->void:
	_exploration_follow_plan=dto.duplicate(true)
	queue_redraw()

func exploration_companion_follow_draw_spec()->Dictionary:
	var result:={"active":false,"path":[],"rows":[]}
	if not bool(_exploration_follow_plan.get("accepted",false)):
		return result.duplicate(true)
	var shared_path:Array=[]
	for value in _exploration_follow_plan.get("path",[]):
		var point:=_array_to_world_position(value)
		if point!=Vector2i(-1,-1):shared_path.append([point.x,point.y])
	result.active=shared_path.size()>=2
	result.path=shared_path.duplicate(true)
	for raw_row in _exploration_follow_plan.get("companion_rows",[]):
		if not raw_row is Dictionary:continue
		var row:Dictionary=raw_row
		var roster_slot:=maxi(0,int(row.get("roster_slot",0)))
		var lane_rank:=maxi(1,ceili(float(roster_slot)/2.0))
		var lane_sign:=-1.0 if roster_slot%2==1 else 1.0
		var lane_offset_px:=lane_sign*float(lane_rank)*cell_size_px()*0.12
		var pixel_offset:=Vector2(lane_offset_px,-lane_offset_px*0.35)
		var row_path:Array=[]
		for value in row.get("path",shared_path):
			var point:=_array_to_world_position(value)
			if point!=Vector2i(-1,-1):row_path.append(point)
		var segments:Array=[]
		for index in range(maxi(0,row_path.size()-1)):
			var from:Vector2i=row_path[index];var to:Vector2i=row_path[index+1]
			var visible:=_cell_allows_overlay(from) and _cell_allows_overlay(to)
			segments.append({"index":index,"visible":visible,
				"from_position":[from.x,from.y],"to_position":[to.x,to.y],
				"from_pixel":world_to_pixel_center(from)+pixel_offset if visible else Vector2(-1,-1),
				"to_pixel":world_to_pixel_center(to)+pixel_offset if visible else Vector2(-1,-1),
				"color_hex":"#67bfe2","line_width":maxf(1.2,cell_size_px()*0.045),
				"dash_count":4})
		var next_position:=_array_to_world_position(row.get("next_position",[]))
		var next_visible:=next_position!=Vector2i(-1,-1) and _cell_allows_overlay(next_position)
		var next_center:=world_to_pixel_center(next_position)+pixel_offset if next_visible else Vector2(-1,-1)
		var risk:=maxi(0,int(row.get("max_total_risk",0)))
		var risk_hex:="#ff6b70" if risk>=60 else ("#ffd467" if risk>=25 else "#75d7a0")
		result.rows.append({"entity_id":int(row.get("entity_id",-1)),"roster_slot":roster_slot,
			"offset_px":pixel_offset,"segments":segments,
			"next_cue":{"visible":next_visible,"position":[next_position.x,next_position.y],
				"pixel_center":next_center,"glyph":">","color_hex":"#9cdbef"},
			"risk_badge":{"visible":next_visible,"value":risk,"text":str(risk),
				"pixel_center":next_center+Vector2(cell_size_px()*0.26,-cell_size_px()*0.27) \
					if next_visible else Vector2(-1,-1),"color_hex":risk_hex}})
	return result.duplicate(true)

func route_draw_spec() -> Dictionary:
	var color_hex := "#65f29a" if _route_valid else "#ff6b78"
	var path_rows: Array = []
	var tiles: Array = []
	var segments: Array = []
	var direction_cues: Array = []
	var markers: Array = []
	for index in range(_route_path.size()):
		var point:Vector2i=_route_path[index]
		path_rows.append([point.x,point.y])
		var visible:=_cell_allows_overlay(point)
		var completed:=index<=_route_completed_steps
		var kind:="START" if index==0 else ("GOAL" if index==_route_path.size()-1 else ("NEXT" if index==_route_completed_steps+1 else "STEP"))
		tiles.append({"index":index,"position":[point.x,point.y],"visible":visible,
			"pixel_rect":world_cell_rect(point).grow(-maxf(1.0,cell_size_px()*0.08)) if visible else Rect2(),"kind":kind,"completed":completed,
			"fill_hex":"#607b87" if completed else color_hex,
			"fill_alpha":0.10 if completed else (0.30 if kind in ["NEXT","GOAL"] else 0.18),
			"border_hex":"#607b87" if completed else color_hex,"border_width":1.5 if completed else 2.0})
	for index in range(maxi(0,_route_path.size()-1)):
		var from: Vector2i = _route_path[index]
		var to: Vector2i = _route_path[index+1]
		var visible := _cell_allows_overlay(from) and _cell_allows_overlay(to)
		var from_pixel:=world_to_pixel_center(from);var to_pixel:=world_to_pixel_center(to)
		var direction:Vector2=(to_pixel-from_pixel).normalized() if visible else Vector2.ZERO
		var perpendicular:=Vector2(-direction.y,direction.x);var cue_center:=from_pixel.lerp(to_pixel,0.68)
		var cue_length:=cell_size_px()*0.18;var cue_width:=cell_size_px()*0.12
		segments.append({"index":index,"from_position":[from.x,from.y],"to_position":[to.x,to.y],
			"from_pixel":from_pixel,"to_pixel":to_pixel,
			"visible":visible,"completed":index<_route_completed_steps,
			"color_hex":"#607b87" if index<_route_completed_steps else color_hex,
			"line_width":2.5 if index<_route_completed_steps else 4.0})
		direction_cues.append({"index":index,"visible":visible,"completed":index<_route_completed_steps,
			"color_hex":"#607b87" if index<_route_completed_steps else color_hex,"line_width":2.0,
			"points":[cue_center-direction*cue_length+perpendicular*cue_width,cue_center,
				cue_center-direction*cue_length-perpendicular*cue_width]})
	for index in range(_route_path.size()):
		var position: Vector2i = _route_path[index]
		var kind := "STEP"
		if index == 0:kind="START"
		elif index == _route_path.size()-1:kind="GOAL"
		elif index == _route_completed_steps+1:kind="NEXT"
		markers.append({"index":index,"position":[position.x,position.y],
			"pixel_center":world_to_pixel_center(position),"visible":_cell_allows_overlay(position),
			"kind":kind,"completed":index<=_route_completed_steps,
			"color_hex":"#607b87" if index<=_route_completed_steps else color_hex,
			"radius":maxf(3.0,cell_size_px()*(0.20 if kind in ["START","GOAL"] else 0.12))})
	return {"path":path_rows,"valid":_route_valid,"completed_steps":_route_completed_steps,
		"tiles":tiles,"segments":segments,"direction_cues":direction_cues,"markers":markers,"color_hex":color_hex}.duplicate(true)

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
		if int(actor.get("entity_id",-1)) == entity_id:
			var p := Vector2i(int(actor.position[0]),int(actor.position[1]))
			if is_world_cell_visible(p):return Rect2(world_to_pixel_center(p)-Vector2(22,22),Vector2(44,44))
	return Rect2()
func actor_at_pointer(pointer: Vector2) -> int:
	var matches: Array = []
	for actor in _actors:
		if actor_hit_rect(int(actor.get("entity_id",-1))).has_point(pointer):
			var p := Vector2i(int(actor.position[0]),int(actor.position[1])); matches.append({"id":int(actor.get("entity_id",-1)),"distance":pointer.distance_squared_to(world_to_pixel_center(p)),"protagonist":bool(actor.get("is_protagonist",false)),"slot":int(actor.get("roster_slot",99))})
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
		if bool(a.get("is_protagonist",false)) != bool(b.get("is_protagonist",false)): return bool(a.get("is_protagonist",false))
		if int(a.get("roster_slot",99)) != int(b.get("roster_slot",99)): return int(a.get("roster_slot",99)) < int(b.get("roster_slot",99))
		return int(a.get("entity_id",-1)) < int(b.get("entity_id",-1)))
	return -1 if matches.is_empty() else int(matches[0].get("entity_id",-1))

func actor_render_order() -> Array:
	var ids: Array = []
	for row in _sorted_visual_actor_rows():ids.append(int(row.actor.get("entity_id",-1)))
	return ids.duplicate()

func actor_draw_spec(actor:Dictionary,ghost:bool=false)->Dictionary:
	return AsciiStyleScript.actor_spec(actor,ghost)

func _position_from_actor(actor:Dictionary)->Vector2i:
	var value:Variant=actor.get("display_position",actor.get("position",[]))
	return Vector2i(int(value[0]),int(value[1])) if value is Array and value.size()==2 else Vector2i(-1,-1)

func _logical_position_from_actor(actor:Dictionary)->Vector2i:
	var value:Variant=actor.get("logical_position",actor.get("position",[]))
	return Vector2i(int(value[0]),int(value[1])) if value is Array and value.size()==2 else Vector2i(-1,-1)

func _validated_display_position(actor:Dictionary,logical_position:Vector2i)->Vector2i:
	var raw:Variant=actor.get("display_position",[])
	if not raw is Array or raw.size()!=2:return logical_position
	var candidate:=Vector2i(int(raw[0]),int(raw[1]))
	if not _world_in_bounds(candidate):return logical_position
	var target_cell:Dictionary=_cells.get(_key(candidate),{})
	return candidate if not target_cell.is_empty() and AsciiStyleScript.visibility_state(target_cell)=="VISIBLE" else logical_position

func _validated_logical_position(actor:Dictionary,fallback:Vector2i)->Vector2i:
	var raw:Variant=actor.get("logical_position",[])
	if not raw is Array or raw.size()!=2:return fallback
	var candidate:=Vector2i(int(raw[0]),int(raw[1]))
	return candidate if _world_in_bounds(candidate) else fallback

func _cell_accepts_actor_input(position:Vector2i)->bool:
	var row:Dictionary=_cells.get(_key(position),{})
	return not row.is_empty() and bool(AsciiStyleScript.visibility_spec(row).accepts_actor_input)

func _cell_accepts_world_interaction(position:Vector2i)->bool:
	return bool(AsciiStyleScript.visibility_spec(_cells.get(_key(position),{})).accepts_actor_input)

func _cell_allows_overlay(position:Vector2i)->bool:
	return is_world_cell_visible(position) \
		and AsciiStyleScript.visibility_state(_cells.get(_key(position),{}))!="UNSEEN"

func _array_to_world_position(value:Variant)->Vector2i:
	if value is Vector2i:return value
	if value is Array and value.size()==2:return Vector2i(int(value[0]),int(value[1]))
	return Vector2i(-1,-1)

func _actor_visual_key(entity_id:int,position:Vector2i)->String:
	return "%d:%d:%d"%[entity_id,position.x,position.y]

func _sorted_visual_actor_rows()->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	for actor in _actors:rows.append({"actor":actor,"ghost":false})
	for ghost in _ghosts:rows.append({"actor":ghost,"ghost":true})
	rows.sort_custom(func(a,b):
		var pa:=_position_from_actor(a.actor);var pb:=_position_from_actor(b.actor)
		if pa.y!=pb.y:return pa.y<pb.y
		if pa.x!=pb.x:return pa.x<pb.x
		var aid:=int(a.actor.get("entity_id",-1));var bid:=int(b.actor.get("entity_id",-1))
		if aid!=bid:return aid<bid
		return not bool(a.ghost) and bool(b.ghost))
	return rows

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:return
	if modal_open:
		cancel_pointer_gesture();return
	if event is InputEventScreenTouch:
		_suppress_mouse_until_msec=Time.get_ticks_msec()+EMULATED_MOUSE_SUPPRESS_MSEC
		if event.pressed:_begin_pointer_gesture("TOUCH",event.index,event.position)
		else:_finish_pointer_gesture("TOUCH",event.index,event.position,event.canceled)
		accept_event();return
	if event is InputEventScreenDrag:
		if _pointer_gesture_active and _pointer_gesture_kind=="TOUCH" and event.index==_pointer_gesture_index:
			_update_pointer_gesture(event.position);accept_event()
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec()<=_suppress_mouse_until_msec:accept_event();return
		if event.pressed:_begin_pointer_gesture("MOUSE",-1,event.position)
		else:_finish_pointer_gesture("MOUSE",-1,event.position,false)
		accept_event();return
	if event is InputEventMouseMotion and _pointer_gesture_active and _pointer_gesture_kind=="MOUSE":
		if Time.get_ticks_msec()<=_suppress_mouse_until_msec:return
		_update_pointer_gesture(event.position);accept_event()

func _begin_pointer_gesture(kind:String,pointer_index:int,pointer:Vector2)->void:
	if _pointer_gesture_active:cancel_pointer_gesture()
	var cell:=pixel_to_world_cell(pointer)
	if cell==Vector2i(-1,-1) or not _cell_accepts_world_interaction(cell):return
	_pointer_gesture_generation+=1
	_pointer_gesture_active=true;_pointer_gesture_kind=kind;_pointer_gesture_index=pointer_index
	_pointer_gesture_cell=cell;_pointer_gesture_start=pointer;_pointer_gesture_last=pointer
	var target:=_short_tap_target(cell,pointer)
	_pointer_gesture_target_kind=str(target.kind);_pointer_gesture_target_actor_id=int(target.actor_id)
	_pointer_gesture_long_fired=false;_pointer_gesture_cancelled=false
	if is_inside_tree():
		get_tree().create_timer(LONG_PRESS_SECONDS).timeout.connect(
			_on_long_press_timeout.bind(_pointer_gesture_generation),CONNECT_ONE_SHOT)
	pointer_gesture_started.emit()

func _update_pointer_gesture(pointer:Vector2)->void:
	if not _pointer_gesture_active:return
	_pointer_gesture_last=pointer
	if pointer.distance_to(_pointer_gesture_start)>POINTER_SLOP_PX:_pointer_gesture_cancelled=true

func _finish_pointer_gesture(kind:String,pointer_index:int,pointer:Vector2,cancelled:bool)->void:
	if not _pointer_gesture_active or _pointer_gesture_kind!=kind or _pointer_gesture_index!=pointer_index:return
	var cell:=_pointer_gesture_cell;var long_fired:=_pointer_gesture_long_fired;var gesture_cancelled:=_pointer_gesture_cancelled
	var target_kind:=_pointer_gesture_target_kind;var target_actor_id:=_pointer_gesture_target_actor_id
	var valid_release:=not cancelled and not gesture_cancelled and pointer.distance_to(_pointer_gesture_start)<=POINTER_SLOP_PX \
		and pixel_to_world_cell(pointer)==cell and is_world_cell_visible(cell) \
		and _cell_accepts_world_interaction(cell)
	_reset_pointer_gesture()
	if valid_release and not long_fired:_emit_short_target(target_kind,target_actor_id,cell)
	pointer_gesture_finished.emit("LONG_PRESS" if long_fired else ("SHORT_TAP" if valid_release else "CANCELLED"))

func _on_long_press_timeout(expected_generation:int)->void:
	if expected_generation!=_pointer_gesture_generation or not _pointer_gesture_active \
			or _pointer_gesture_long_fired or _pointer_gesture_cancelled:return
	if modal_open or not is_world_cell_visible(_pointer_gesture_cell) \
			or not _cell_accepts_world_interaction(_pointer_gesture_cell) \
			or _pointer_gesture_last.distance_to(_pointer_gesture_start)>POINTER_SLOP_PX \
			or pixel_to_world_cell(_pointer_gesture_last)!=_pointer_gesture_cell:
		cancel_pointer_gesture();return
	_pointer_gesture_long_fired=true
	tile_long_pressed.emit(_pointer_gesture_cell)

func cancel_pointer_gesture()->void:
	var was_active:=_pointer_gesture_active
	_reset_pointer_gesture()
	if was_active:pointer_gesture_finished.emit("CANCELLED")

func _reset_pointer_gesture()->void:
	_pointer_gesture_generation+=1;_pointer_gesture_active=false;_pointer_gesture_kind="";_pointer_gesture_index=-1
	_pointer_gesture_cell=Vector2i(-1,-1);_pointer_gesture_start=Vector2.ZERO;_pointer_gesture_last=Vector2.ZERO
	_pointer_gesture_target_kind="";_pointer_gesture_target_actor_id=-1
	_pointer_gesture_long_fired=false;_pointer_gesture_cancelled=false

func pointer_gesture_state()->Dictionary:
	return {"active":_pointer_gesture_active,"kind":_pointer_gesture_kind,"pointer_index":_pointer_gesture_index,
		"cell":[_pointer_gesture_cell.x,_pointer_gesture_cell.y],"long_fired":_pointer_gesture_long_fired,
		"cancelled":_pointer_gesture_cancelled,
		"target_kind":_pointer_gesture_target_kind,"target_actor_id":_pointer_gesture_target_actor_id,
		"generation":_pointer_gesture_generation}.duplicate(true)

func _short_tap_target(p:Vector2i,pointer:Vector2)->Dictionary:
	if not _cell_accepts_world_interaction(p):return {"kind":"NONE","actor_id":-1}
	var actor_id := actor_in_world_cell(p)
	if actor_id>0:return {"kind":"ACTOR","actor_id":actor_id}
	if _empty_cell_center_zone(p,pointer):return {"kind":"CELL","actor_id":-1}
	var nearby_actor_id:=actor_at_pointer(pointer)
	return {"kind":"ACTOR","actor_id":nearby_actor_id} if nearby_actor_id>0 else {"kind":"CELL","actor_id":-1}

func _emit_short_target(kind:String,actor_id:int,p:Vector2i)->void:
	if kind=="ACTOR" and actor_id>0:actor_pressed.emit(actor_id)
	elif kind=="CELL":world_cell_pressed.emit(p)

func _empty_cell_center_zone(position:Vector2i,pointer:Vector2)->bool:
	var inset:=cell_size_px()*0.25
	return world_cell_rect(position).grow(-inset).has_point(pointer)

func _draw() -> void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var p := view_origin+Vector2i(x,y); var row: Dictionary = _cells.get(_key(p),{}); var rect := world_cell_rect(p)
			_draw_ascii_tile(rect,row)
	_draw_route_tiles()
	_draw_follower_footprints()
	for visual_row in _sorted_visual_actor_rows():
		_draw_actor(visual_row.actor,cell_size_px(),bool(visual_row.ghost))
	_draw_route_overlay()
	_draw_exploration_companion_follow_plan()
	for intent in _secondary_intent_overlays:
		_draw_intent(intent)
	for intent in _intent_overlays:
		_draw_intent(intent)
	_draw_actor_selection_overlays()
	_draw_cursor_preview()
	for effect in _active_visual_effects:_draw_visual_effect(effect)
	var style_id:=str(_presentation_style.get("style_id","DEFAULT"))
	if combat_emphasis or bool(_presentation_style.get("vignette",false)):
		var border:=Color(str(_presentation_style.get("border_hex","#ff7a80")))
		draw_rect(grid_rect().grow(-2),border,false,4.0 if style_id=="COMBAT" else 2.5)

func _draw_ascii_tile(rect:Rect2,row:Dictionary)->void:
	var visibility:Dictionary=AsciiStyleScript.visibility_spec(row)
	if not bool(visibility.draw_terrain):
		draw_rect(rect,Color("#030609"),true);return
	var spec:Dictionary=AsciiStyleScript.terrain_spec(row)
	var opacity:=float(spec.opacity)
	var depth:=maxf(1.0,floorf(rect.size.x*float(spec.depth_ratio)))
	var edge:=_visual_color(str(spec.edge_hex),opacity)
	var base:=_visual_color(str(spec.base_hex),opacity)
	draw_rect(rect,edge,true)
	var top_rect:=Rect2(rect.position,Vector2(maxf(1.0,rect.size.x-depth),maxf(1.0,rect.size.y-depth)))
	draw_rect(top_rect.grow(-0.5),base,true)
	if bool(spec.raised):
		draw_line(Vector2(top_rect.position.x,top_rect.end.y),top_rect.end,edge,maxf(2.0,depth),false)
		draw_line(Vector2(top_rect.end.x,top_rect.position.y),top_rect.end,edge,maxf(2.0,depth),false)
	var font:=get_theme_default_font();var font_size:=maxi(10,int(floor(rect.size.x*(0.58 if bool(spec.raised) else 0.46))))
	_draw_centered_text(font,str(spec.glyph),top_rect.get_center()+Vector2(1,1),font_size,_visual_color("#05090d",opacity*0.72))
	_draw_centered_text(font,str(spec.glyph),top_rect.get_center(),font_size,_visual_color(str(spec.glyph_hex),opacity))
	_draw_hazard_cues(rect,row)

func _draw_hazard_cues(rect:Rect2,row:Dictionary)->void:
	var spec:Dictionary=AsciiStyleScript.hazard_spec(row);var font:=get_theme_default_font()
	for cue in spec.cues:
		var color:=_visual_color(str(cue.color_hex),1.0);var center:=rect.get_center()
		match str(cue.corner):
			"BOTTOM_LEFT":center=rect.position+Vector2(rect.size.x*0.25,rect.size.y*0.76)
			"BOTTOM_RIGHT":center=rect.position+Vector2(rect.size.x*0.76,rect.size.y*0.76)
			"TOP_RIGHT":center=rect.position+Vector2(rect.size.x*0.77,rect.size.y*0.25)
		if float(cue.fill_alpha)>0.0:
			draw_circle(center,maxf(2.5,rect.size.x*0.19),_visual_color(str(cue.color_hex),float(cue.fill_alpha)))
		_draw_centered_text(font,str(cue.glyph),center,maxi(9,int(rect.size.x*0.38)),color)

func _draw_centered_text(font:Font,value:String,center:Vector2,font_size:int,color:Color)->void:
	var extent:=font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	draw_string(font,center+Vector2(-extent.x*0.5,extent.y*0.38),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _visual_color(value:String,opacity:float)->Color:
	var color:=Color(value);color.a*=clampf(opacity,0.0,1.0);return color

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
	var figure_height:=clampf(cell*1.46,28.0,50.0);var figure_width:=figure_height*0.72
	var bounds:=Rect2(Vector2(rect.get_center().x-figure_width*0.5,rect.end.y-figure_height+1.0),Vector2(figure_width,figure_height))
	AsciiPortraitScript.draw_figure(self,get_theme_default_font(),bounds,actor_draw_spec(actor,ghost),true)

func _draw_follower_footprints()->void:
	for actor in _actors:
		var follower:Dictionary=AsciiStyleScript.follower_spec(actor)
		if not bool(follower.visible):continue
		var logical:=_logical_position_from_actor(actor);var display:=_position_from_actor(actor)
		if not is_world_cell_visible(logical) or not is_world_cell_visible(display):continue
		var from:=world_to_pixel_center(logical);var to:=world_to_pixel_center(display)
		var delta:=to-from;var color:=_visual_color(str(follower.tether_hex),float(follower.opacity))
		var dash_count:=maxi(1,int(follower.dash_count))
		for index in range(dash_count):
			var start:=from+delta*(float(index)/float(dash_count))
			var finish:=from+delta*(float(index)/float(dash_count)+0.13)
			draw_line(start,finish,color,maxf(1.2,cell_size_px()*0.045),true)
		var radius:=maxf(2.0,cell_size_px()*float(follower.footprint_radius_ratio))
		var footprint_color:=_visual_color(str(follower.footprint_hex),float(follower.opacity))
		for offset in [Vector2(-radius*0.7,0),Vector2(radius*0.7,0),Vector2(0,-radius*0.72)]:
			draw_circle(from+offset,maxf(1.2,radius*0.34),footprint_color)

func _draw_exploration_companion_follow_plan()->void:
	var spec:Dictionary=exploration_companion_follow_draw_spec()
	if not bool(spec.active):return
	for row in spec.rows:
		for segment in row.segments:
			if not bool(segment.visible):continue
			var from:Vector2=segment.from_pixel;var to:Vector2=segment.to_pixel;var delta:=to-from
			var dash_count:=maxi(1,int(segment.dash_count));var color:=Color(str(segment.color_hex))
			for index in range(dash_count):
				var start:=from+delta*(float(index)/float(dash_count))
				var finish:=from+delta*(float(index)/float(dash_count)+0.13)
				draw_line(start,finish,color,float(segment.line_width),true)
		var next_cue:Dictionary=row.next_cue
		if bool(next_cue.visible):
			_draw_centered_text(get_theme_default_font(),str(next_cue.glyph),next_cue.pixel_center,
				maxi(10,int(cell_size_px()*0.42)),Color(str(next_cue.color_hex)))
		var risk_badge:Dictionary=row.risk_badge
		if bool(risk_badge.visible):
			var center:Vector2=risk_badge.pixel_center;var badge_size:=Vector2(maxf(14.0,cell_size_px()*0.52),maxf(10.0,cell_size_px()*0.34))
			draw_rect(Rect2(center-badge_size*0.5,badge_size),Color("#071018"),true)
			draw_rect(Rect2(center-badge_size*0.5,badge_size),Color(str(risk_badge.color_hex)),false,1.2)
			_draw_centered_text(get_theme_default_font(),str(risk_badge.text),center,
				maxi(8,int(cell_size_px()*0.25)),Color(str(risk_badge.color_hex)))

func _draw_actor_selection_overlays()->void:
	for actor in _actors:
		var p:=_position_from_actor(actor)
		if not is_world_cell_visible(p):continue
		var entity_id:=int(actor.get("entity_id",-1));var color:=Color.TRANSPARENT;var width:=2.5
		if entity_id==selected_actor_id:color=Color("#ffd467")
		elif entity_id==selected_target_id:color=Color("#ff6b70")
		else:continue
		for segment in AsciiStyleScript.bracket_segments(world_cell_rect(p)):
			draw_line(segment[0],segment[1],color,width,true)
	for ghost in _ghosts:
		var p:=_position_from_actor(ghost)
		if not is_world_cell_visible(p):continue
		for segment in AsciiStyleScript.bracket_segments(world_cell_rect(p),0.12,0.18):
			draw_line(segment[0],segment[1],Color(0.45,0.8,1.0,0.72),1.4,true)

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
	for cue in spec.direction_cues:
		if not bool(cue.visible):continue
		var points:=PackedVector2Array()
		for point in cue.points:points.append(point)
		draw_polyline(points,Color(str(cue.color_hex)),float(cue.line_width),true)
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

func _draw_route_tiles()->void:
	if _route_path.size()<2:return
	for tile in route_draw_spec().tiles:
		if not bool(tile.visible):continue
		var fill:=Color(str(tile.fill_hex));fill.a=float(tile.fill_alpha)
		draw_rect(tile.pixel_rect,fill,true)
		draw_rect(tile.pixel_rect,Color(str(tile.border_hex)),false,float(tile.border_width))

func _draw_intent(intent: Dictionary) -> void:
	if not intent.get("from_position") is Array or intent.from_position.size() != 2: return
	var origin := Vector2i(int(intent.from_position[0]), int(intent.from_position[1]))
	if not _cell_allows_overlay(origin):return
	var spec := intent_draw_spec(intent)
	if not bool(spec.visible):return
	var color := Color(str(spec.color_hex))
	var action_type := str(spec.action_type)
	if action_type == "MOVE" and intent.get("destination") is Array and intent.destination.size() == 2:
		var destination := Vector2i(int(intent.destination[0]), int(intent.destination[1]))
		if not _cell_allows_overlay(destination):return
		_draw_arrow(world_to_pixel_center(origin), world_to_pixel_center(destination), color,
			float(spec.line_width), bool(spec.dashed))
		_draw_source_marker(destination, str(spec.marker_style), color)
	elif action_type == "MELEE" and intent.get("target_position") is Array and intent.target_position.size() == 2:
		var target := Vector2i(int(intent.target_position[0]), int(intent.target_position[1]))
		if not _cell_allows_overlay(target):return
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
	var action_type:=str(intent.get("type","HOLD"))
	var origin:=_array_to_world_position(intent.get("from_position",[]))
	var visible:=origin!=Vector2i(-1,-1) and _cell_allows_overlay(origin)
	if action_type=="MOVE":
		var destination:=_array_to_world_position(intent.get("destination",[]))
		visible=visible and destination!=Vector2i(-1,-1) and _cell_allows_overlay(destination)
	elif action_type=="MELEE":
		var target:=_array_to_world_position(intent.get("target_position",[]))
		visible=visible and target!=Vector2i(-1,-1) and _cell_allows_overlay(target)
	return {"action_type":str(intent.get("type","HOLD")),
		"primitive":"RING" if str(intent.get("type","HOLD"))=="HOLD" else "ARROW",
		"visible":visible,
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
