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
const DioramaScript = preload("res://playtest/ascii_diorama_projection.gd")
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
var _actor_motion_requests: Dictionary = {}
var _actor_motions: Dictionary = {}
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
	var observed_at_ms:=Time.get_ticks_msec()
	var previous_cells:Dictionary=_cells.duplicate(true)
	var previous_actors:Dictionary={}
	var previous_visual_world:Dictionary={}
	for actor in _actors:
		var previous_id:=int(actor.get("entity_id",-1))
		if previous_id<=0:continue
		previous_actors[previous_id]=actor.duplicate(true)
		previous_visual_world[previous_id]=_actor_visual_world_position(previous_id,observed_at_ms)
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
	_reconcile_actor_motions(previous_actors,previous_visual_world,previous_cells,observed_at_ms)
	queue_redraw()

func arm_actor_motion(actor_ids:Array,duration_ms:int=DioramaScript.ACTOR_MOTION_DEFAULT_MS)->void:
	var safe_duration:=clampi(duration_ms,DioramaScript.ACTOR_MOTION_MIN_MS,
		DioramaScript.ACTOR_MOTION_MAX_MS)
	for value in actor_ids:
		var entity_id:=int(value)
		if entity_id>0:_actor_motion_requests[entity_id]=safe_duration

func actor_motion_sample(from_world:Vector2,to_world:Vector2,elapsed_ms:int,
		duration_ms:int=DioramaScript.ACTOR_MOTION_DEFAULT_MS)->Dictionary:
	return DioramaScript.actor_motion_sample(from_world,to_world,elapsed_ms,duration_ms)

func actor_motion_state()->Dictionary:
	return _actor_motions.duplicate(true)

func actor_motion_draw_spec(entity_id:int,sample_time_ms:int=-1)->Dictionary:
	var actor:=_actor_by_id(entity_id)
	if actor.is_empty():return {"active":false,"entity_id":entity_id}.duplicate(true)
	var target:=_position_from_actor(actor)
	var target_world:=Vector2(target)
	if not _actor_motions.has(entity_id):
		return {"active":false,"entity_id":entity_id,"from_world":target_world,
			"to_world":target_world,"world_position":target_world,"progress":1.0,
			"eased_progress":1.0,"duration_ms":0}.duplicate(true)
	var motion:Dictionary=_actor_motions[entity_id]
	var now:=Time.get_ticks_msec() if sample_time_ms<0 else sample_time_ms
	var sample:=DioramaScript.actor_motion_sample(motion.from_world,motion.to_world,
		now-int(motion.started_at_ms),int(motion.duration_ms))
	return {"active":bool(sample.active),"entity_id":entity_id,
		"from_world":motion.from_world,"to_world":motion.to_world,
		"world_position":sample.world_position,"progress":float(sample.progress),
		"eased_progress":float(sample.eased_progress),
		"duration_ms":int(sample.duration_ms),"started_at_ms":int(motion.started_at_ms)}.duplicate(true)

func actor_visual_center(entity_id:int,sample_time_ms:int=-1)->Vector2:
	var actor:=_actor_by_id(entity_id)
	if actor.is_empty():return Vector2(-1,-1)
	var target:=_position_from_actor(actor)
	if not is_world_cell_visible(target):return Vector2(-1,-1)
	return _world_position_to_pixel_center(_actor_visual_world_position(entity_id,sample_time_ms))

func _reconcile_actor_motions(previous_actors:Dictionary,previous_visual_world:Dictionary,
		previous_cells:Dictionary,observed_at_ms:int)->void:
	var next_actors:Dictionary={}
	for actor in _actors:
		var entity_id:=int(actor.get("entity_id",-1))
		if entity_id>0:next_actors[entity_id]=actor
	for raw_id in _actor_motions.keys():
		var entity_id:=int(raw_id)
		if not next_actors.has(entity_id):
			_actor_motions.erase(entity_id);continue
		if _actor_motion_requests.has(entity_id):continue
		var target:=Vector2(_position_from_actor(next_actors[entity_id]))
		var motion:Dictionary=_actor_motions[entity_id]
		if not (motion.get("to_world",Vector2(-1,-1)) as Vector2).is_equal_approx(target):
			_actor_motions.erase(entity_id)
	for raw_id in _actor_motion_requests.keys():
		var entity_id:=int(raw_id)
		if not previous_actors.has(entity_id) or not next_actors.has(entity_id):
			_actor_motions.erase(entity_id);continue
		var previous:Dictionary=previous_actors[entity_id]
		var next:Dictionary=next_actors[entity_id]
		var previous_logical:=_logical_position_from_actor(previous)
		var next_logical:=_logical_position_from_actor(next)
		var logical_delta:=next_logical-previous_logical
		var one_step:=logical_delta!=Vector2i.ZERO \
			and maxi(absi(logical_delta.x),absi(logical_delta.y))==1
		var previous_display:=_position_from_actor(previous)
		var next_display:=_position_from_actor(next)
		var previous_row:Dictionary=previous_cells.get(_key(previous_display),{})
		var next_row:Dictionary=_cells.get(_key(next_display),{})
		var fov_safe:=not previous_row.is_empty() and not next_row.is_empty() \
			and AsciiStyleScript.visibility_state(previous_row)=="VISIBLE" \
			and AsciiStyleScript.visibility_state(next_row)=="VISIBLE" \
			and is_world_cell_visible(previous_display) and is_world_cell_visible(next_display)
		var from_world:Vector2=previous_visual_world.get(entity_id,Vector2(previous_display))
		var to_world:=Vector2(next_display)
		if not one_step or not fov_safe or from_world.is_equal_approx(to_world):
			_actor_motions.erase(entity_id);continue
		_actor_motions[entity_id]={"from_world":from_world,"to_world":to_world,
			"started_at_ms":observed_at_ms,"duration_ms":int(_actor_motion_requests[entity_id])}
	_actor_motion_requests.clear()
	_update_process_enabled()

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
	_update_process_enabled();queue_redraw();return appended

func has_played_effect_event(event_id:int)->bool:return _played_effect_event_ids.has(event_id)
func has_played_effect(effect_id:String)->bool:return _played_effect_ids.has(effect_id)

func clear_transient_visuals()->void:
	_active_visual_effects.clear();_played_effect_ids.clear();_played_effect_event_ids.clear()
	_actor_motion_requests.clear();_actor_motions.clear()
	_intent_overlays.clear();_secondary_intent_overlays.clear();_ghosts.clear()
	_route_path.clear();_route_completed_steps=0;_route_valid=false
	_exploration_follow_plan.clear()
	preview_actor_id=-1;preview_origin=Vector2i(-1,-1)
	preview_destination=Vector2i(-1,-1);preview_valid=false
	cursor_cell=Vector2i(-1,-1);selected_actor_id=-1;selected_target_id=-1
	_reset_pointer_gesture();_update_process_enabled();queue_redraw()

func visual_effect_draw_spec(effect:Dictionary,sample_time_ms:int=-1)->Dictionary:
	var world_value=effect.get("world_position",[-1,-1]);var world_position:=Vector2i(-1,-1)
	if world_value is Array and world_value.size()==2:world_position=Vector2i(int(world_value[0]),int(world_value[1]))
	var kind:=str(effect.get("kind",""));var damage_type:=str(effect.get("damage_type","physical"))
	var color_hex:String={"fire":"#ff7a55","water":"#67c9ff","electric":"#ffe46b","poison":"#9ee86f","physical":"#fff0df"}.get(damage_type,"#fff0df")
	if kind=="DEATH":color_hex="#ff6b78"
	var duration_ms:=900 if kind in ["FLOATING_AMOUNT","DEATH"] else 520
	var now:=Time.get_ticks_msec() if sample_time_ms<0 else sample_time_ms
	var started_at:=int(effect.get("started_at_ms",now))
	var age_ratio:=clampf(float(maxi(0,now-started_at))/float(duration_ms),0.0,1.0)
	var pixel_center:=world_to_pixel_center(world_position)
	if kind=="FLOATING_AMOUNT":pixel_center.y-=cell_size_px()*0.52*age_ratio
	return {"effect_id":str(effect.get("effect_id","")),"event_id":int(effect.get("event_id",-1)),
		"kind":kind,"primitive":{"SLASH":"SLASH_LINES","HIT_FLASH":"FLASH_RING","FLOATING_AMOUNT":"TEXT","DEATH":"DEATH_CROSS"}.get(kind,"NONE"),
		"world_position":[world_position.x,world_position.y],"visible":is_world_cell_visible(world_position),
		"pixel_center":pixel_center,"color_hex":color_hex,"age_ratio":age_ratio,
		"opacity":clampf(1.0-age_ratio*0.88,0.12,1.0),
		"line_width":4.0 if kind in ["SLASH","DEATH"] else 3.0,
		"radius":cell_size_px()*(0.34+0.10*age_ratio if kind=="HIT_FLASH" else 0.28),
		"text":str(effect.get("text","")),"font_size":18,
		"duration_ms":duration_ms}.duplicate(true)

func _process(_delta:float)->void:
	var now:=Time.get_ticks_msec();var retained:Array[Dictionary]=[]
	for effect in _active_visual_effects:
		var spec:=visual_effect_draw_spec(effect)
		if now-int(effect.get("started_at_ms",now))<int(spec.duration_ms):retained.append(effect)
	_active_visual_effects=retained
	for raw_id in _actor_motions.keys():
		var motion:Dictionary=_actor_motions[raw_id]
		if now-int(motion.get("started_at_ms",now))>=int(motion.get("duration_ms",150)):
			_actor_motions.erase(raw_id)
	_update_process_enabled()
	queue_redraw()

func _update_process_enabled()->void:
	set_process(not _active_visual_effects.is_empty() or not _actor_motions.is_empty())

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
		"tiles":tiles,"segments":segments,"direction_cues":direction_cues,"markers":markers,
		"color_hex":color_hex,"render_style":"CHALK_CENTERLINE","draw_tile_cards":false}.duplicate(true)

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
func _world_position_to_pixel_center(position:Vector2)->Vector2:
	var local:=position-Vector2(view_origin)
	return grid_rect().position+(local+Vector2(0.5,0.5))*cell_size_px()
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

func selection_overlay_draw_specs()->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	for actor in _actors:
		var entity_id:=int(actor.get("entity_id",-1))
		if entity_id!=selected_target_id:continue
		var position:=_position_from_actor(actor)
		if not is_world_cell_visible(position):continue
		rows.append({"kind":"TARGET","entity_id":entity_id,
			"position":[position.x,position.y],"color_hex":"#ff6b70","line_width":2.5,
			"segments":AsciiStyleScript.bracket_segments(world_cell_rect(position))})
	for ghost in _ghosts:
		var position:=_position_from_actor(ghost)
		if not is_world_cell_visible(position):continue
		rows.append({"kind":"DEPLOYMENT_GHOST","entity_id":int(ghost.get("entity_id",-1)),
			"position":[position.x,position.y],"color_hex":"#73ccff","opacity":0.72,
			"line_width":1.4,"segments":AsciiStyleScript.bracket_segments(
				world_cell_rect(position),0.12,0.18)})
	return rows.duplicate(true)

func diorama_layer_order()->Array:
	return DioramaScript.layer_order()

func diorama_cell_draw_spec(position:Vector2i)->Dictionary:
	if not _world_in_bounds(position):
		return DioramaScript.cell_spec(position,{}, {})
	var neighbors:={
		"N":DioramaScript.sanitize_observed_cell(_cells.get(_key(position+Vector2i.UP),{})),
		"E":DioramaScript.sanitize_observed_cell(_cells.get(_key(position+Vector2i.RIGHT),{})),
		"S":DioramaScript.sanitize_observed_cell(_cells.get(_key(position+Vector2i.DOWN),{})),
		"W":DioramaScript.sanitize_observed_cell(_cells.get(_key(position+Vector2i.LEFT),{})),
	}
	return DioramaScript.cell_spec(position,_cells.get(_key(position),{}),neighbors)

func diorama_hazard_draw_spec(position:Vector2i)->Dictionary:
	return DioramaScript.hazard_floor_spec(position,_cells.get(_key(position),{}))

func _position_from_actor(actor:Dictionary)->Vector2i:
	var value:Variant=actor.get("display_position",actor.get("position",[]))
	return Vector2i(int(value[0]),int(value[1])) if value is Array and value.size()==2 else Vector2i(-1,-1)

func _actor_by_id(entity_id:int)->Dictionary:
	for actor in _actors:
		if int(actor.get("entity_id",-1))==entity_id:return actor
	return {}

func _actor_visual_world_position(entity_id:int,sample_time_ms:int=-1)->Vector2:
	var actor:=_actor_by_id(entity_id)
	if actor.is_empty():return Vector2(-1,-1)
	var target:=Vector2(_position_from_actor(actor))
	if not _actor_motions.has(entity_id):return target
	var motion:Dictionary=_actor_motions[entity_id]
	var now:=Time.get_ticks_msec() if sample_time_ms<0 else sample_time_ms
	return DioramaScript.actor_motion_sample(motion.from_world,motion.to_world,
		now-int(motion.started_at_ms),int(motion.duration_ms)).world_position

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

func _diorama_visibility_state(row:Dictionary)->String:
	return "UNSEEN" if row.is_empty() else AsciiStyleScript.visibility_state(row)

func _draw() -> void:
	var palette:=AsciiStyleScript.diorama_palette_spec()
	draw_rect(grid_rect(),Color(str(palette.get("void_hex","#020406"))),true)
	_draw_ground_pass("MEMORY")
	_draw_ground_pass("VISIBLE")
	_draw_material_mark_pass("MEMORY")
	_draw_material_mark_pass("VISIBLE")
	_draw_wall_shadow_pass("MEMORY")
	_draw_wall_shadow_pass("VISIBLE")
	_draw_wall_pass("MEMORY")
	_draw_wall_pass("VISIBLE")
	_draw_ground_features()
	_draw_ground_hazards()
	_draw_route_ground_marks()
	_draw_follower_footprints()
	_draw_route_overlay()
	_draw_exploration_companion_follow_plan()
	for visual_row in _sorted_visual_actor_rows():
		_draw_actor(visual_row.actor,cell_size_px(),bool(visual_row.ghost))
	for intent in _secondary_intent_overlays:
		_draw_intent(intent)
	for intent in _intent_overlays:
		_draw_intent(intent)
	_draw_actor_selection_overlays()
	_draw_cursor_preview()
	for effect in _active_visual_effects:_draw_visual_effect(effect)
	_draw_fov_edge_haze()
	var style_id:=str(_presentation_style.get("style_id","DEFAULT"))
	if combat_emphasis or bool(_presentation_style.get("vignette",false)):
		var border:=Color(str(_presentation_style.get("border_hex","#ff7a80")))
		draw_rect(grid_rect().grow(-2),border,false,4.0 if style_id=="COMBAT" else 2.5)

func _draw_ground_pass(visibility_state:String)->void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y)
			var row:Dictionary=_cells.get(_key(position),{})
			if _diorama_visibility_state(row)!=visibility_state:continue
			var terrain:Dictionary=AsciiStyleScript.terrain_spec(row)
			if not bool(terrain.visible) or str(terrain.terrain_id)=="wall":continue
			_draw_ground_surface(position,row,terrain,visibility_state=="MEMORY")

func _draw_ground_surface(position:Vector2i,row:Dictionary,terrain:Dictionary,
		memory:bool)->void:
	var rect:=world_cell_rect(position)
	var overlap:=clampf(cell_size_px()*0.045,1.0,2.0)
	var base:=_diorama_color(str(terrain.base_hex),float(terrain.opacity),memory)
	var terrain_id:=str(terrain.terrain_id)
	if terrain_id in ["wood_floor","metal","rubble","shallow_water"]:
		var palette:=AsciiStyleScript.diorama_palette_spec()
		var substrate:=_diorama_color(str(palette.get("substrate_hex","#0b1015")),
			0.82*float(terrain.opacity),memory)
		draw_rect(rect.grow(overlap).intersection(grid_rect()),substrate,true)
		_draw_connected_material_blob(rect,diorama_cell_draw_spec(position),base,terrain_id)
	else:
		draw_rect(rect.grow(overlap).intersection(grid_rect()),base,true)

func _draw_connected_material_blob(rect:Rect2,spec:Dictionary,color:Color,
		terrain_id:String)->void:
	var cell:=rect.size.x
	var mask:=int(spec.get("connected_mask",0))
	if terrain_id in ["wood_floor","metal"]:
		var inset:=cell*0.08
		draw_rect(rect.grow(-inset),color,true)
	else:
		draw_colored_polygon(_ellipse_points(rect.get_center(),cell*0.48,cell*0.43),color)
	var bridge_width:=cell*(0.72 if terrain_id in ["wood_floor","metal"] else 0.56)
	var center:=rect.get_center()
	if mask&DioramaScript.NORTH:
		draw_rect(Rect2(Vector2(center.x-bridge_width*0.5,rect.position.y-1.0),
			Vector2(bridge_width,cell*0.56)),color,true)
	if mask&DioramaScript.EAST:
		draw_rect(Rect2(Vector2(center.x,center.y-bridge_width*0.5),
			Vector2(cell*0.56+1.0,bridge_width)),color,true)
	if mask&DioramaScript.SOUTH:
		draw_rect(Rect2(Vector2(center.x-bridge_width*0.5,center.y),
			Vector2(bridge_width,cell*0.56+1.0)),color,true)
	if mask&DioramaScript.WEST:
		draw_rect(Rect2(Vector2(rect.position.x-1.0,center.y-bridge_width*0.5),
			Vector2(cell*0.56+1.0,bridge_width)),color,true)

func _draw_material_mark_pass(visibility_state:String)->void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y)
			var row:Dictionary=_cells.get(_key(position),{})
			if _diorama_visibility_state(row)!=visibility_state:continue
			var terrain:Dictionary=AsciiStyleScript.terrain_spec(row)
			if str(terrain.terrain_id)=="wall":continue
			_draw_material_mark(world_cell_rect(position),terrain,
				diorama_cell_draw_spec(position).get("material_mark",{}),
				visibility_state=="MEMORY")

func _draw_material_mark(rect:Rect2,terrain:Dictionary,mark_value:Variant,
		memory:bool)->void:
	if not mark_value is Dictionary:return
	var mark:Dictionary=mark_value
	if not bool(mark.get("visible",false)):return
	var offset:Vector2=mark.get("offset",Vector2.ZERO)
	var center:=rect.get_center()+Vector2(offset.x*rect.size.x,offset.y*rect.size.y)
	var color:=_diorama_color(str(terrain.glyph_hex),float(mark.get("opacity",0.2)),memory)
	var cell:=rect.size.x;var variant:=int(mark.get("variant",0))
	match str(mark.get("kind","NONE")):
		"DUST":
			draw_circle(center,maxf(1.0,cell*0.035),color)
		"CRACK":
			var sign_x:=-1.0 if variant%2==0 else 1.0
			draw_line(center+Vector2(-cell*0.16*sign_x,-cell*0.07),center,
				color,maxf(1.0,cell*0.035),true)
			draw_line(center,center+Vector2(cell*0.12*sign_x,cell*0.10),
				color,maxf(1.0,cell*0.035),true)
		"PLANK":
			var horizontal:=variant%2==0
			var axis:=Vector2(cell*0.38,0) if horizontal else Vector2(0,cell*0.38)
			draw_line(center-axis,center+axis,color,maxf(1.0,cell*0.045),true)
		"SHEEN":
			var diagonal:=Vector2(cell*0.28,-cell*0.17)
			draw_line(center-diagonal,center+diagonal,color,maxf(1.0,cell*0.050),true)
		"DEBRIS":
			_draw_centered_text(get_theme_default_font(),str(mark.get("glyph",",")),center,
				maxi(8,int(cell*0.34)),color)
			draw_circle(center+Vector2(cell*0.18,-cell*0.12),maxf(1.0,cell*0.035),color)
		"RIPPLE":
			draw_arc(center,cell*0.19,0.12*PI,0.88*PI,10,color,maxf(1.0,cell*0.040),true)
			draw_arc(center+Vector2(cell*0.09,cell*0.10),cell*0.13,1.08*PI,1.92*PI,8,
				color,maxf(1.0,cell*0.032),true)

func _draw_wall_shadow_pass(visibility_state:String)->void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y)
			var row:Dictionary=_cells.get(_key(position),{})
			if _diorama_visibility_state(row)!=visibility_state \
					or str(row.get("terrain_id",row.get("terrain","floor")))!="wall":continue
			var spec:=diorama_cell_draw_spec(position)
			var exposed:=int(spec.get("exposed_mask",0))
			var rect:=world_cell_rect(position);var cell:=rect.size.x
			var alpha:=0.20 if visibility_state=="VISIBLE" else 0.07
			var shadow:=Color(str(AsciiStyleScript.diorama_palette_spec().get("shadow_hex","#010304")))
			shadow.a=alpha
			if exposed&DioramaScript.SOUTH:
				draw_colored_polygon(PackedVector2Array([
					Vector2(rect.position.x+cell*0.12,rect.end.y-cell*0.18),
					Vector2(rect.end.x-cell*0.12,rect.end.y-cell*0.18),
					Vector2(rect.end.x+cell*0.16,rect.end.y+cell*0.28),
					Vector2(rect.position.x+cell*0.18,rect.end.y+cell*0.28),
				]),shadow)
			if exposed&DioramaScript.EAST:
				draw_colored_polygon(PackedVector2Array([
					Vector2(rect.end.x-cell*0.18,rect.position.y+cell*0.10),
					Vector2(rect.end.x,rect.position.y+cell*0.16),
					Vector2(rect.end.x+cell*0.28,rect.end.y+cell*0.20),
					Vector2(rect.end.x+cell*0.12,rect.end.y-cell*0.04),
				]),shadow)

func _draw_wall_pass(visibility_state:String)->void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y)
			var row:Dictionary=_cells.get(_key(position),{})
			if _diorama_visibility_state(row)!=visibility_state:continue
			var terrain:=AsciiStyleScript.terrain_spec(row)
			if str(terrain.terrain_id)!="wall":continue
			var spec:=diorama_cell_draw_spec(position);var connected:=int(spec.connected_mask)
			var rect:=world_cell_rect(position);var cell:=rect.size.x
			var depth:=maxf(3.0,cell*0.18);var overlap:=clampf(cell*0.045,1.0,2.0)
			var top_width:=rect.size.x+overlap if connected&DioramaScript.EAST else rect.size.x-depth
			var top_height:=rect.size.y+overlap if connected&DioramaScript.SOUTH else rect.size.y-depth
			var top_rect:=Rect2(rect.position-Vector2(overlap,overlap),
				Vector2(top_width+overlap,top_height+overlap))
			var top:=_diorama_color(str(terrain.base_hex),float(terrain.opacity),visibility_state=="MEMORY")
			var face:=_diorama_color(str(terrain.edge_hex),float(terrain.opacity),visibility_state=="MEMORY")
			draw_rect(top_rect,top,true)
			if not connected&DioramaScript.SOUTH:
				draw_colored_polygon(PackedVector2Array([
					Vector2(top_rect.position.x,top_rect.end.y),top_rect.end,
					Vector2(rect.end.x,rect.end.y),Vector2(rect.position.x,rect.end.y),
				]),face)
			if not connected&DioramaScript.EAST:
				draw_colored_polygon(PackedVector2Array([
					Vector2(top_rect.end.x,top_rect.position.y),top_rect.end,
					rect.end,Vector2(rect.end.x,rect.position.y),
				]),_diorama_color(str(AsciiStyleScript.diorama_palette_spec().get(
					"wall_side_hex","#070b0f")),float(terrain.opacity),visibility_state=="MEMORY"))
			if not connected&DioramaScript.NORTH:
				draw_line(top_rect.position,Vector2(top_rect.end.x,top_rect.position.y),
					_diorama_color(str(terrain.glyph_hex),0.22,visibility_state=="MEMORY"),maxf(1.0,cell*0.035),true)
			_draw_material_mark(top_rect,terrain,spec.material_mark,visibility_state=="MEMORY")

func _draw_ground_features()->void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y);var row:Dictionary=_cells.get(_key(position),{})
			if _diorama_visibility_state(row)=="VISIBLE":
				_draw_feature_cue(world_cell_rect(position),str(row.get("feature_id","")))

func _draw_ground_hazards()->void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y);var spec:=diorama_hazard_draw_spec(position)
			if bool(spec.get("visible",false)):_draw_ground_hazard(world_cell_rect(position),spec)

func _draw_ground_hazard(rect:Rect2,spec:Dictionary)->void:
	var center:=rect.get_center();var cell:=rect.size.x;var phase:=int(spec.get("phase",0))
	if int(spec.get("wetness",0))>0:
		var wet:=Color(0.32,0.78,1.0,float(spec.wet_reflection_alpha))
		draw_colored_polygon(_ellipse_points(center+Vector2(0,cell*0.12),cell*0.41,cell*0.22),wet)
		var shift:=(float(phase)-1.5)*cell*0.035
		draw_line(center+Vector2(-cell*0.31,shift),center+Vector2(cell*0.25,shift-cell*0.05),
			Color(0.65,0.92,1.0,wet.a*1.35),maxf(1.0,cell*0.040),true)
	if int(spec.get("fire",0))>0:
		var glow_alpha:=float(spec.fire_glow_alpha)
		draw_circle(center,cell*0.48,Color(1.0,0.26,0.08,glow_alpha*0.22))
		draw_circle(center+Vector2(0,cell*0.08),cell*0.29,Color(1.0,0.45,0.13,glow_alpha*0.48))
		_draw_centered_text(get_theme_default_font(),"*",center-Vector2(0,cell*0.02),
			maxi(10,int(cell*0.55)),Color(1.0,0.70,0.25,0.88))
	if int(spec.get("conductivity",0))>=25:
		var arc:=Color(0.70,0.94,1.0,float(spec.arc_alpha))
		var direction:=-1.0 if phase%2==0 else 1.0
		var points:=PackedVector2Array([
			center+Vector2(-cell*0.32,cell*0.12*direction),
			center+Vector2(-cell*0.08,-cell*0.13*direction),
			center+Vector2(cell*0.04,cell*0.08*direction),
			center+Vector2(cell*0.31,-cell*0.15*direction),
		])
		draw_polyline(points,arc,maxf(1.0,cell*0.045),true)

func _draw_fov_edge_haze()->void:
	var thickness:=clampf(cell_size_px()*0.13,2.0,5.0)
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y);var spec:=diorama_cell_draw_spec(position)
			if not bool(spec.get("visible",false)):continue
			var mask:=int(spec.get("fov_edge_mask",0));var rect:=world_cell_rect(position)
			var color:=Color(0.015,0.03,0.045,0.46 if str(spec.visibility_state)=="VISIBLE" else 0.27)
			if mask&DioramaScript.NORTH:draw_rect(Rect2(rect.position,Vector2(rect.size.x,thickness)),color,true)
			if mask&DioramaScript.EAST:draw_rect(Rect2(Vector2(rect.end.x-thickness,rect.position.y),Vector2(thickness,rect.size.y)),color,true)
			if mask&DioramaScript.SOUTH:draw_rect(Rect2(Vector2(rect.position.x,rect.end.y-thickness),Vector2(rect.size.x,thickness)),color,true)
			if mask&DioramaScript.WEST:draw_rect(Rect2(rect.position,Vector2(thickness,rect.size.y)),color,true)

func _diorama_color(value:String,opacity:float,memory:bool)->Color:
	var color:=Color(value)
	if memory:
		var luminance:=color.r*0.299+color.g*0.587+color.b*0.114
		color=color.lerp(Color(luminance,luminance,luminance,1.0),0.68)
	color.a*=clampf(opacity,0.0,1.0)
	return color

func _ellipse_points(center:Vector2,radius_x:float,radius_y:float)->PackedVector2Array:
	var points:=PackedVector2Array()
	for index in range(16):
		var angle:=TAU*float(index)/16.0
		points.append(center+Vector2(cos(angle)*radius_x,sin(angle)*radius_y))
	return points

func _draw_feature_cue(rect:Rect2,feature_id:String)->void:
	var spec:Dictionary=AsciiStyleScript.feature_spec(feature_id)
	if not bool(spec.visible):return
	var center:=rect.get_center();var font:=get_theme_default_font()
	var font_size:=maxi(11,int(floor(rect.size.x*0.62)))
	_draw_centered_text(font,str(spec.glyph),center+Vector2(1,1),font_size,Color("#05090d"))
	_draw_centered_text(font,str(spec.glyph),center,font_size,Color(str(spec.color_hex)))

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
	var center:Vector2=spec.pixel_center;var color:=Color(str(spec.color_hex));color.a*=float(spec.opacity)
	var radius:=float(spec.radius);var width:=float(spec.line_width)*(1.0-float(spec.age_ratio)*0.38)
	match str(spec.primitive):
		"SLASH_LINES":
			var drift:=Vector2(radius*0.30,-radius*0.20)*float(spec.age_ratio)
			draw_line(center+Vector2(-radius,radius)+drift,center+Vector2(radius,-radius)+drift,color,width)
			draw_line(center+Vector2(-radius*0.55,radius)-drift*0.45,center+Vector2(radius,radius*-0.55)-drift*0.45,color,maxf(1.4,width-1.0))
		"FLASH_RING":draw_arc(center,radius,0,TAU,20,color,width)
		"TEXT":draw_string(get_theme_default_font(),center+Vector2(-16,-radius),str(spec.text),HORIZONTAL_ALIGNMENT_CENTER,32,int(spec.font_size),color)
		"DEATH_CROSS":
			draw_line(center-Vector2(radius,radius),center+Vector2(radius,radius),color,width)
			draw_line(center+Vector2(radius,-radius),center+Vector2(-radius,radius),color,width)

func _draw_actor(actor: Dictionary, cell: float, ghost: bool) -> void:
	if not actor.get("position") is Array or actor.position.size() != 2: return
	var p := Vector2i(int(actor.position[0]),int(actor.position[1])); var rect := world_cell_rect(p)
	if not is_world_cell_visible(p):return
	var visual_center:=world_to_pixel_center(p) if ghost else actor_visual_center(
		int(actor.get("entity_id",-1)))
	if visual_center==Vector2(-1,-1):return
	var figure_height:=clampf(cell*1.46,28.0,50.0);var figure_width:=cell*0.72
	var foot_y:=visual_center.y+cell*0.5
	var bounds:=Rect2(Vector2(visual_center.x-figure_width*0.5,foot_y-figure_height+1.0),
		Vector2(figure_width,figure_height))
	bounds.position+=_actor_recoil_offset(actor)
	AsciiPortraitScript.draw_figure(self,get_theme_default_font(),bounds,actor_draw_spec(actor,ghost),true,true)

func _actor_recoil_offset(actor:Dictionary)->Vector2:
	var position:=_position_from_actor(actor);var entity_id:=int(actor.get("entity_id",-1))
	for effect in _active_visual_effects:
		if str(effect.get("kind",""))!="HIT_FLASH":continue
		var effect_position:=_array_to_world_position(effect.get("world_position",[]))
		if int(effect.get("target_id",-1))!=entity_id and effect_position!=position:continue
		var spec:=visual_effect_draw_spec(effect)
		var age:=float(spec.age_ratio)
		if age>0.42:continue
		var event_id:=int(effect.get("event_id",0));var direction:=-1.0 if event_id%2==0 else 1.0
		var amplitude:=2.0+float(absi(event_id)%3)
		var envelope:=1.0-age/0.42
		return Vector2(direction*amplitude*envelope,-amplitude*0.28*envelope)
	return Vector2.ZERO

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
	for row in selection_overlay_draw_specs():
		var color:=Color(str(row.color_hex))
		color.a*=float(row.get("opacity",1.0))
		for segment in row.segments:
			draw_line(segment[0],segment[1],color,float(row.line_width),true)

func _draw_cursor_preview() -> void:
	if cursor_cell.x < 0 or not is_world_cell_visible(cursor_cell): return
	var color := Color("#65f29a") if preview_valid else Color("#ff5f68")
	var center:=world_to_pixel_center(cursor_cell);var radius:=cell_size_px()*0.36
	draw_circle(center,radius,Color(color,0.10))
	draw_arc(center,radius,0,TAU,20,color,3.0)
	if _route_path.size() < 2 and preview_origin.x >= 0 and is_world_cell_visible(preview_origin):
		_draw_arrow(world_to_pixel_center(preview_origin), world_to_pixel_center(preview_destination), color, 3.5, false)

func _draw_route_overlay() -> void:
	if _route_path.size()<2:return
	var spec:=route_draw_spec()
	for segment in spec.segments:
		if not bool(segment.visible):continue
		_draw_chalk_segment(segment.from_pixel,segment.to_pixel,
			Color(str(segment.color_hex)),minf(2.5,float(segment.line_width)))
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
			_:draw_circle(center,radius,Color(color,0.42))

func _draw_route_ground_marks()->void:
	if _route_path.size()<2:return
	for tile in route_draw_spec().tiles:
		if not bool(tile.visible):continue
		var center:Vector2=tile.pixel_rect.get_center();var color:=Color(str(tile.fill_hex))
		var radius:=maxf(1.5,cell_size_px()*(0.10 if str(tile.kind) in ["START","GOAL","NEXT"] else 0.065))
		draw_circle(center,radius,Color(color,0.28 if not bool(tile.completed) else 0.16))
		if str(tile.kind)=="GOAL":draw_arc(center,cell_size_px()*0.31,0,TAU,20,Color(color,0.76),2.0)

func _draw_chalk_segment(from:Vector2,to:Vector2,color:Color,width:float)->void:
	var delta:=to-from
	if delta.length()<1.0:return
	var dash_count:=maxi(3,int(ceil(delta.length()/maxf(5.0,cell_size_px()*0.22))))
	for index in range(dash_count):
		if index%2==1:continue
		var start:=from+delta*(float(index)/float(dash_count))
		var finish:=from+delta*(minf(1.0,float(index+1)/float(dash_count)))
		draw_line(start,finish,Color(color,0.74),width,true)

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
