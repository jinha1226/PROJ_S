class_name PartyGridView
extends Control

signal world_cell_pressed(position: Vector2i)
signal actor_pressed(entity_id: int)
signal tile_long_pressed(position: Vector2i)
signal pointer_gesture_started()
signal pointer_gesture_finished(outcome: String)

const GRID_SIZE := 15
const AsciiStyleScript = preload("res://playtest/ascii_visual_style.gd")
const AsciiPortraitScript = preload("res://playtest/ascii_actor_portrait.gd")
const DioramaScript = preload("res://playtest/ascii_diorama_projection.gd")
const MeleeVfxScript = preload("res://playtest/melee_vfx_overlay.gd")
const LONG_PRESS_SECONDS := 0.50
const POINTER_SLOP_PX := 14.0
const EMULATED_MOUSE_SUPPRESS_MSEC := 300
const CAMERA_SETTLE_DURATION_MS := 70
const TORCH_FLICKER_QUANTUM_MS := 125 # 8 Hz: intentionally below 10 Hz.
const MAX_VISIBLE_TORCHES := 6
const MAX_MEMORY_TORCHES := 6
const TORCH_SPACING_CELLS := 5
const TORCH_AMBER_HEX := "#f0a64d"
const TORCH_GLYPH_HEX := "#ffd078"
const ACTOR_WORLD_GLYPH_OFFSET_Y := -0.105
# The shared standing pose ends at 0.47. The world projection deliberately
# extends below it, while its shifted figure bounds keep the feet inside the
# logical cell. This is presentation only; hit rectangles remain cell based.
const ACTOR_WORLD_LEG_END_Y := 0.485
const ACTOR_WORLD_FIGURE_BOTTOM_INSET_PX := 1.0
const AWARENESS_PULSE_DURATION_MS := 220
const MONSTER_LIST_MAX_ROWS := 5
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
var _neutral_phase_map:=false
var _presentation_style: Dictionary = {}
var _active_visual_effects: Array[Dictionary] = []
var _played_effect_ids: Dictionary = {}
var _played_effect_event_ids: Dictionary = {}
var _actor_motion_requests: Dictionary = {}
var _actor_motions: Dictionary = {}
var _hero_camera_position:=Vector2i(-1,-1)
var _hero_camera_actor_id:=-1
var _camera_settle:Dictionary={}
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
var _static_projection_cache:Dictionary={}
var _static_projection_dirty:=true
var _static_projection_rebuild_count:=0
var _static_observation_hash:=0
var _static_occupancy_hash:=0
var _actor_projection_hash:=0
var _static_hash_initialized:=false
var _occupied_visible_cells:Dictionary={}
var _torch_positions:Array[Vector2i]=[]
var _visible_torch_count:=0
var _torch_cache_rebuild_count:=0
var _torch_timer:Timer
var _awareness_pulses:Dictionary={}
var melee_vfx:MeleeVfxOverlay

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP; focus_mode = Control.FOCUS_ALL
	clip_contents=true; resized.connect(_on_visual_geometry_changed)
	_ensure_melee_vfx()
	_torch_timer=Timer.new();_torch_timer.name="TorchFlickerTimer"
	_torch_timer.wait_time=float(TORCH_FLICKER_QUANTUM_MS)/1000.0
	_torch_timer.one_shot=false;_torch_timer.timeout.connect(_on_torch_flicker_tick)
	add_child(_torch_timer)
	set_process(false)

func _on_torch_flicker_tick()->void:
	if _visible_torch_count>0:queue_redraw()

func _sync_torch_timer()->void:
	if _torch_timer==null:return
	if _visible_torch_count>0:
		if _torch_timer.is_stopped():_torch_timer.start()
	elif not _torch_timer.is_stopped():_torch_timer.stop()

func _ensure_melee_vfx()->void:
	if melee_vfx!=null:return
	melee_vfx=MeleeVfxScript.new()
	melee_vfx.name="MeleeVfxOverlay"
	melee_vfx.z_index=50
	melee_vfx.bind_grid(self)
	add_child(melee_vfx)

func _on_visual_geometry_changed()->void:
	_invalidate_static_projection_cache()
	queue_redraw()

func _invalidate_static_projection_cache()->void:
	_static_projection_dirty=true

func _exit_tree()->void:
	_reset_pointer_gesture()

func set_observation(observation: Dictionary, ghosts: Array = []) -> void:
	cancel_pointer_gesture()
	var observed_at_ms:=Time.get_ticks_msec()
	var previous_visible_cells:Dictionary={}
	var previous_actors:Dictionary={}
	var previous_visual_world:Dictionary={}
	for actor in _actors:
		var previous_id:=int(actor.get("entity_id",-1))
		if previous_id<=0:continue
		previous_actors[previous_id]=actor
		previous_visual_world[previous_id]=_actor_visual_world_position(previous_id,observed_at_ms)
		var previous_position:=_position_from_actor(actor)
		var previous_row:Dictionary=_cells.get(_key(previous_position),{})
		if not previous_row.is_empty() \
				and AsciiStyleScript.visibility_state(previous_row)=="VISIBLE":
			previous_visible_cells[_key(previous_position)]=true
	_cells.clear(); _actors.clear(); _ghosts.clear()
	world_grid_size=Vector2i(maxi(1,int(observation.get("width",GRID_SIZE))),maxi(1,int(observation.get("height",GRID_SIZE))))
	for raw in observation.get("cells",[]):
		if not raw is Dictionary or not raw.get("position") is Array \
				or raw.position.size()!=2:continue
		# Cell presentation fields are scalar; actors are normalized into the
		# dedicated detached _actors array below. One shallow row copy avoids both
		# aliasing and the former two full deep-copy passes.
		var row:Dictionary=raw.duplicate(false)
		var p:=Vector2i(int(raw.position[0]),int(raw.position[1]))
		row["position"]=[p.x,p.y]
		row["actors"]=[]
		# Ground item authority never enters this presentation cache. Keep only one
		# approved scalar glyph, and only for a currently visible cell. This also
		# prevents a malformed MEMORY observation from retaining live item details.
		var visibility_state:=AsciiStyleScript.visibility_state(row)
		var ground_item_spec:=AsciiStyleScript.ground_item_spec(raw) \
			if visibility_state=="VISIBLE" else AsciiStyleScript.item_presentation_spec("")
		row.erase("ground_items")
		row["ground_item_glyph"]=str(ground_item_spec.glyph) \
			if bool(ground_item_spec.visible) else ""
		_cells[_key(p)]=row
		if visibility_state=="VISIBLE":
			for actor in raw.get("actors",[]):
				if not actor is Dictionary:continue
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
	_reconcile_actor_motions(previous_actors,previous_visual_world,
		previous_visible_cells,observed_at_ms)
	_reconcile_awareness_pulses(previous_actors,observed_at_ms)
	# Damage-only combat observations change actor vitals but not the terrain,
	# FOV, feature or occupancy projection. Retain that expensive 15x15 static
	# projection until an actual presentation input changes.
	var next_observation_hash:=hash([world_grid_size,_cells])
	var occupied_keys:Array[String]=[]
	for actor in _actors:
		occupied_keys.append(_key(_position_from_actor(actor)))
	occupied_keys.sort()
	var next_occupancy_hash:=hash(occupied_keys)
	var next_actor_projection_hash:=_visual_actor_projection_hash()
	var projection_changed:=not _static_hash_initialized \
		or next_observation_hash!=_static_observation_hash \
		or next_occupancy_hash!=_static_occupancy_hash
	if projection_changed:
		_invalidate_static_projection_cache()
	if projection_changed or next_actor_projection_hash!=_actor_projection_hash:
		queue_redraw()
	_static_observation_hash=next_observation_hash
	_static_occupancy_hash=next_occupancy_hash
	_actor_projection_hash=next_actor_projection_hash
	_static_hash_initialized=true
	_update_process_enabled()
	if melee_vfx!=null:melee_vfx.queue_redraw()

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
		"eased_progress":float(sample.eased_progress),"step_phase":str(sample.step_phase),
		"stride_sign":int(sample.stride_sign),"glyph_bob_ratio":float(sample.glyph_bob_ratio),
		"duration_ms":int(sample.duration_ms),"started_at_ms":int(motion.started_at_ms)}.duplicate(true)

func actor_visual_center(entity_id:int,sample_time_ms:int=-1)->Vector2:
	var actor:=_actor_by_id(entity_id)
	if actor.is_empty():return Vector2(-1,-1)
	var target:=_position_from_actor(actor)
	if not is_world_cell_visible(target):return Vector2(-1,-1)
	return _world_position_to_pixel_center(_actor_visual_world_position(entity_id,sample_time_ms))

func _reconcile_actor_motions(previous_actors:Dictionary,previous_visual_world:Dictionary,
		previous_visible_cells:Dictionary,observed_at_ms:int)->void:
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
		var next_row:Dictionary=_cells.get(_key(next_display),{})
		var fov_safe:=bool(previous_visible_cells.get(_key(previous_display),false)) \
			and not next_row.is_empty() \
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
		view_origin=Vector2i.ZERO;_invalidate_static_projection_cache();queue_redraw(); return
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
		view_origin=Vector2i.ZERO;_invalidate_static_projection_cache();queue_redraw();return
	var center:=Vector2i(world_grid_size.x/2,world_grid_size.y/2)
	if found:center=Vector2i((minimum.x+maximum.x)/2,(minimum.y+maximum.y)/2)
	var next_origin:=center-Vector2i(visible_cell_count/2,visible_cell_count/2)
	if found:
		var minimum_origin:=Vector2i(maxi(0,maximum.x-visible_cell_count+1),maxi(0,maximum.y-visible_cell_count+1))
		var maximum_origin:=Vector2i(mini(minimum.x,world_grid_size.x-visible_cell_count),mini(minimum.y,world_grid_size.y-visible_cell_count))
		next_origin=Vector2i(clampi(next_origin.x,minimum_origin.x,maximum_origin.x),clampi(next_origin.y,minimum_origin.y,maximum_origin.y))
	next_origin=_clamp_view_origin(next_origin)
	view_origin=next_origin;_invalidate_static_projection_cache();queue_redraw()

func set_hero_centered_view(hero_position:Vector2i,cell_count:int=GRID_SIZE,
		hero_actor_id:int=-1,settle_duration_msec:int=CAMERA_SETTLE_DURATION_MS)->void:
	# Product camera authority is the protagonist only. Negative origins are
	# intentional at map edges: those screen cells render as void rather than
	# pushing the hero away from the center cell.
	cancel_pointer_gesture()
	var previous_origin:=view_origin
	var previous_count:=visible_cell_count
	var previous_hero:=_hero_camera_position
	var previous_settle:=_camera_settle.duplicate(true)
	var now:=Time.get_ticks_msec()
	var carried_offset_cells:=Vector2.ZERO
	if not _camera_settle.is_empty():
		carried_offset_cells=Vector2(camera_settle_draw_spec(now).get(
			"offset_px",Vector2.ZERO))/maxf(1.0,cell_size_px())
	visible_cell_count=clampi(cell_count,1,64)
	if _hero_camera_position!=Vector2i(-1,-1) and hero_position!=_hero_camera_position:
		var delta:=hero_position-_hero_camera_position
		if maxi(absi(delta.x),absi(delta.y))==1:
			# Retarget from the currently drawn camera position. Repeated one-cell
			# hops therefore preserve visual continuity instead of restarting from a
			# full-cell offset every turn.
			_camera_settle={"from_offset_cells":carried_offset_cells+Vector2(delta),
				"started_at_ms":now,"duration_ms":maxi(1,settle_duration_msec)}
		else:_camera_settle.clear()
	elif _hero_camera_position==Vector2i(-1,-1):_camera_settle.clear()
	_hero_camera_position=hero_position;_hero_camera_actor_id=hero_actor_id
	view_origin=hero_position-Vector2i(visible_cell_count/2,visible_cell_count/2)
	if hero_actor_id>0:_actor_motions.erase(hero_actor_id)
	var presentation_changed:=previous_origin!=view_origin or previous_count!=visible_cell_count \
		or previous_hero!=_hero_camera_position or previous_settle!=_camera_settle
	if previous_origin!=view_origin or previous_count!=visible_cell_count \
			or previous_hero!=_hero_camera_position:
		_invalidate_static_projection_cache()
	_update_process_enabled()
	if presentation_changed:queue_redraw()

func camera_settle_draw_spec(sample_time_ms:int=-1)->Dictionary:
	if _camera_settle.is_empty():
		return {"active":false,"progress":1.0,"offset_px":Vector2.ZERO,
			"hero_counter_offset_px":Vector2.ZERO,"duration_ms":0,
			"input_blocked":false,"curve":"SNAP"}.duplicate(true)
	var now:=Time.get_ticks_msec() if sample_time_ms<0 else sample_time_ms
	var started_at:=int(_camera_settle.get("started_at_ms",now))
	var duration:=int(_camera_settle.get("duration_ms",CAMERA_SETTLE_DURATION_MS))
	var progress:=clampf(float(maxi(0,now-started_at))/float(maxi(1,duration)),0.0,1.0)
	var remaining:=pow(1.0-progress,3.0)
	var offset_cells:Vector2=_camera_settle.get("from_offset_cells",Vector2.ZERO)
	var offset_px:=offset_cells*cell_size_px()*remaining
	return {"active":progress<1.0,"progress":progress,"offset_px":offset_px,
		"hero_counter_offset_px":-offset_px,
		"duration_ms":duration,"started_at_ms":started_at,
		"input_blocked":progress<1.0,"curve":"CUBIC_EASE_OUT"}.duplicate(true)

func _camera_input_blocked()->bool:
	return bool(camera_settle_draw_spec().active)

func set_neutral_phase_map(enabled:bool)->void:
	var before:=[_neutral_phase_map,combat_emphasis]
	_neutral_phase_map=enabled
	if enabled:combat_emphasis=false
	if before!=[_neutral_phase_map,combat_emphasis]:queue_redraw()

func set_combat_emphasis(enabled:bool)->void:
	combat_emphasis=enabled and not _neutral_phase_map;queue_redraw()

func set_presentation_style(value:Dictionary)->void:
	var before_style:=_presentation_style
	var before_emphasis:=combat_emphasis
	_presentation_style=value.duplicate(true)
	combat_emphasis=not _neutral_phase_map \
		and str(_presentation_style.get("style_id",""))=="COMBAT"
	if before_style!=_presentation_style or before_emphasis!=combat_emphasis:queue_redraw()

func play_effects(rows:Array)->int:
	var started_at:=Time.get_ticks_msec();var appended:=0
	for raw in rows:
		if not raw is Dictionary:continue
		var effect_id:=str(raw.get("effect_id",""));var event_id:=int(raw.get("event_id",-1))
		if effect_id.is_empty() or event_id<0 or _played_effect_ids.has(effect_id):continue
		if str(raw.get("kind",""))=="MELEE_VFX":
			_ensure_melee_vfx()
			var attacker:=_array_to_world_position(raw.get("attacker_grid_pos",[]))
			var target:=_array_to_world_position(raw.get("target_grid_pos",[]))
			if not melee_vfx.play(attacker,target):continue
			_played_effect_ids[effect_id]=true;_played_effect_event_ids[event_id]=true
			appended+=1;continue
		if str(raw.get("kind",""))=="MISS":
			_play_miss_attacker_swing(raw)
		var row:Dictionary=raw.duplicate(true);row["started_at_ms"]=started_at
		_active_visual_effects.append(row);_played_effect_ids[effect_id]=true
		_played_effect_event_ids[event_id]=true;appended+=1
	if appended==0:return 0
	_active_visual_effects.sort_custom(func(a,b):
		if int(a.get("order",0))!=int(b.get("order",0)):return int(a.get("order",0))<int(b.get("order",0))
		return str(a.get("effect_id",""))<str(b.get("effect_id","")))
	if _active_visual_effects.size()>48:_active_visual_effects=_active_visual_effects.slice(_active_visual_effects.size()-48)
	_update_process_enabled();_ensure_melee_vfx();melee_vfx.queue_redraw();return appended

func _play_miss_attacker_swing(raw:Dictionary)->void:
	_ensure_melee_vfx()
	# Prefer the event-time pair. A combat.attack_missed event is a result leaf and
	# does not itself own the attacker's actor_id, so post-refresh occupant lookup
	# used to silently drop every real MISS swing.
	var historical_attacker:=_array_to_world_position(raw.get("attacker_grid_pos",[]))
	var historical_target:=_array_to_world_position(raw.get("target_grid_pos",[]))
	if historical_attacker!=Vector2i(-1,-1) and historical_target!=Vector2i(-1,-1):
		melee_vfx.play_attacker_swing(historical_attacker,historical_target);return
	var attacker_id:=int(raw.get("actor_id",-1));var target_id:=int(raw.get("target_id",-1))
	var attacker:=_actor_by_id(attacker_id)
	if attacker.is_empty():return
	var attacker_position:=_position_from_actor(attacker);var target_position:=Vector2i(-1,-1)
	var target:=_actor_by_id(target_id)
	if not target.is_empty():target_position=_position_from_actor(target)
	if target_position==Vector2i(-1,-1):
		target_position=_array_to_world_position(raw.get("target_grid_pos",
			raw.get("world_position",[])))
	if target_position==Vector2i(-1,-1):return
	melee_vfx.play_attacker_swing(attacker_position,target_position)

func has_played_effect_event(event_id:int)->bool:return _played_effect_event_ids.has(event_id)
func has_played_effect(effect_id:String)->bool:return _played_effect_ids.has(effect_id)

func clear_transient_visuals()->void:
	_active_visual_effects.clear();_played_effect_ids.clear();_played_effect_event_ids.clear()
	if melee_vfx!=null:melee_vfx.clear()
	_awareness_pulses.clear()
	_actor_motion_requests.clear();_actor_motions.clear()
	_camera_settle.clear();_hero_camera_position=Vector2i(-1,-1);_hero_camera_actor_id=-1
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
	var product_style:=_neutral_phase_map
	var color_hex:String=({"fire":"#ff824a","water":"#67d7ff","electric":"#ffe45c",
		"poison":"#8bea63","bleed":"#ff526e","bleeding":"#ff526e",
		"heal":"#61efc0","healing":"#61efc0","physical":"#ffd98a"}.get(
			damage_type,"#fff0df") if product_style else {"fire":"#ff7a55","water":"#67c9ff",
			"electric":"#ffe46b","poison":"#9ee86f","physical":"#fff0df"}.get(
				damage_type,"#fff0df")) as String
	if kind=="DEATH":color_hex="#ff6b78"
	elif kind=="MISS":color_hex="#b8d5df" if product_style else "#b8e9ff"
	var duration_ms:=int({"HIT_FLASH":210,"FLOATING_AMOUNT":650,
		"MISS":500,"DEATH":780}.get(kind,360)) if product_style \
		else (900 if kind in ["FLOATING_AMOUNT","DEATH"] else (700 if kind=="MISS" else 520))
	var now:=Time.get_ticks_msec() if sample_time_ms<0 else sample_time_ms
	var started_at:=int(effect.get("started_at_ms",now))
	var elapsed_ms:=maxi(0,now-started_at)
	var age_ratio:=clampf(float(elapsed_ms)/float(duration_ms),0.0,1.0)
	var eased_progress:=1.0-pow(1.0-age_ratio,3.0)
	var pixel_center:=world_to_pixel_center(world_position)
	if product_style and kind=="FLOATING_AMOUNT":
		pixel_center.y-=cell_size_px()*(0.42+0.90*eased_progress)
	elif product_style and kind=="MISS":
		pixel_center.y-=cell_size_px()*(0.32+0.45*eased_progress)
	elif kind in ["FLOATING_AMOUNT","MISS"]:pixel_center.y-=cell_size_px()*0.52*age_ratio
	var primitive:=str({"HIT_FLASH":"GLYPH_FLASH" if product_style else "FLASH_RING",
		"FLOATING_AMOUNT":"TEXT","MISS":"TEXT","DEATH":"DEATH_CROSS"}.get(kind,"NONE"))
	var opacity:=clampf(1.0-age_ratio*0.88,0.12,1.0)
	if product_style:
		if kind in ["FLOATING_AMOUNT","MISS"]:opacity=pow(1.0-age_ratio,1.15)
		elif kind=="DEATH":
			opacity=0.0 if age_ratio<0.22 else 0.48*(1.0-(age_ratio-0.22)/0.78)
		else:opacity=1.0-age_ratio
	var particles:Array=[]
	if product_style and kind=="HIT_FLASH" and is_world_cell_visible(world_position):
		particles=_deterministic_hit_particles(int(effect.get("event_id",0)),pixel_center,
			cell_size_px(),age_ratio)
	return {"effect_id":str(effect.get("effect_id","")),"event_id":int(effect.get("event_id",-1)),
		"kind":kind,"primitive":primitive,"product_style":product_style,
		"world_position":[world_position.x,world_position.y],"visible":is_world_cell_visible(world_position),
		"pixel_center":pixel_center,"camera_offset_px":camera_settle_draw_spec(now).offset_px,
		"color_hex":color_hex,"age_ratio":age_ratio,"elapsed_ms":elapsed_ms,
		"eased_progress":eased_progress,"opacity":clampf(opacity,0.0,1.0),
		"flash_active":product_style and kind=="HIT_FLASH" and elapsed_ms<=125,
		"particles":particles,"particle_count":particles.size(),
		"line_width":4.0 if kind=="DEATH" else 3.0,
		"radius":cell_size_px()*0.28,
		"text":str(effect.get("text","")),
		"font_size":15 if kind=="MISS" and product_style else (maxi(24,int(cell_size_px()*0.82)) \
			if kind=="FLOATING_AMOUNT" and product_style else (16 if kind=="MISS" else 18)),
		"duration_ms":duration_ms}.duplicate(true)


func _deterministic_hit_particles(event_id:int,center:Vector2,cell:float,
		age_ratio:float)->Array:
	var rows:Array=[];var count:=3+absi(event_id)%4
	var glyphs:=[".",":","*"]
	for index in range(count):
		var seed:=DioramaScript.visual_hash(Vector2i(event_id%997,index),211+index*17)
		var angle:=TAU*float(seed%6283)/6283.0
		var direction:=Vector2(cos(angle),sin(angle))
		var spread:=cell*(0.08+0.18*age_ratio)
		var start:=center+direction*spread
		var length:=cell*(0.10+0.035*float(seed%4))*(1.0-age_ratio*0.45)
		rows.append({"from":start,"to":start+direction*length,
			"glyph":glyphs[(seed+index)%glyphs.size()],
			"font_size":maxi(10,int(cell*0.42)),
			"line_width":maxf(1.0,cell*0.055),"opacity":1.0-age_ratio})
	return rows.duplicate(true)

func _is_enemy_actor(actor:Dictionary)->bool:
	return bool(actor.get("is_enemy",false)) \
		or str(actor.get("faction_id","")).to_lower()=="enemy"

func _awareness_state(actor:Dictionary)->String:
	return str(AsciiStyleScript.awareness_spec(actor.get(
		"awareness_state","UNAWARE")).state)

func _reconcile_awareness_pulses(previous_actors:Dictionary,observed_at_ms:int)->void:
	var next_enemy_ids:Dictionary={}
	for actor in _actors:
		if not _is_enemy_actor(actor):continue
		var entity_id:=int(actor.get("entity_id",-1))
		if entity_id<=0:continue
		next_enemy_ids[entity_id]=true
		if not previous_actors.has(entity_id):continue
		var previous:Dictionary=previous_actors[entity_id]
		var next_state:=_awareness_state(actor)
		if _awareness_state(previous)!=next_state and next_state!="UNAWARE":
			_awareness_pulses[entity_id]={"started_at_ms":observed_at_ms,
				"duration_ms":AWARENESS_PULSE_DURATION_MS,"state":next_state}
	for raw_id in _awareness_pulses.keys():
		if not next_enemy_ids.has(int(raw_id)):_awareness_pulses.erase(raw_id)

func _process(_delta:float)->void:
	var had_visual_effects:=not _active_visual_effects.is_empty()
	var now:=Time.get_ticks_msec();var retained:Array[Dictionary]=[]
	for effect in _active_visual_effects:
		var spec:=visual_effect_draw_spec(effect)
		if now-int(effect.get("started_at_ms",now))<int(spec.duration_ms):retained.append(effect)
	_active_visual_effects=retained
	for raw_id in _actor_motions.keys():
		var motion:Dictionary=_actor_motions[raw_id]
		if now-int(motion.get("started_at_ms",now))>=int(motion.get("duration_ms",150)):
			_actor_motions.erase(raw_id)
	if not _camera_settle.is_empty() and not bool(camera_settle_draw_spec(now).active):
		_camera_settle.clear()
	var awareness_changed:=false
	for raw_id in _awareness_pulses.keys():
		var pulse:Dictionary=_awareness_pulses[raw_id]
		if now-int(pulse.get("started_at_ms",now))>=int(pulse.get(
				"duration_ms",AWARENESS_PULSE_DURATION_MS)):
			_awareness_pulses.erase(raw_id);awareness_changed=true
	_update_process_enabled()
	if not _actor_motions.is_empty() or not _camera_settle.is_empty() \
			or not _awareness_pulses.is_empty() or awareness_changed:queue_redraw()
	if melee_vfx!=null and (had_visual_effects or not _active_visual_effects.is_empty()):
		melee_vfx.queue_redraw()

func _update_process_enabled()->void:
	set_process(not _active_visual_effects.is_empty() or not _actor_motions.is_empty() \
		or not _camera_settle.is_empty() or not _awareness_pulses.is_empty())

func view_bounds()->Rect2i:return Rect2i(view_origin,Vector2i(visible_cell_count,visible_cell_count))
func is_world_cell_visible(position:Vector2i)->bool:
	return _world_in_bounds(position) and view_bounds().has_point(position)
func _world_in_bounds(position:Vector2i)->bool:
	return position.x>=0 and position.y>=0 and position.x<world_grid_size.x and position.y<world_grid_size.y
func _clamp_view_origin(origin:Vector2i)->Vector2i:
	return Vector2i(clampi(origin.x,0,maxi(0,world_grid_size.x-visible_cell_count)),
		clampi(origin.y,0,maxi(0,world_grid_size.y-visible_cell_count)))

func set_selection(actor_id: int, target_id: int = -1) -> void:
	if selected_actor_id==actor_id and selected_target_id==target_id:return
	selected_actor_id = actor_id; selected_target_id = target_id; queue_redraw()

func set_cursor_preview(actor_id: int, origin: Vector2i, destination: Vector2i, valid: bool) -> void:
	preview_actor_id = actor_id; preview_origin = origin; preview_destination = destination
	cursor_cell = destination; preview_valid = valid; queue_redraw()

func clear_cursor_preview() -> void:
	if preview_actor_id==-1 and preview_origin==Vector2i(-1,-1) \
			and preview_destination==Vector2i(-1,-1) \
			and cursor_cell==Vector2i(-1,-1) and not preview_valid:return
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
	if _route_path.is_empty() and _route_completed_steps==0 and not _route_valid:return
	_route_path.clear();_route_completed_steps=0;_route_valid=false;queue_redraw()

func set_exploration_companion_follow_plan(dto:Dictionary)->void:
	if _exploration_follow_plan==dto:return
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
	return {"path":path_rows,"valid":_route_valid,"completed_steps":_route_completed_steps,
		"tiles":tiles,"segments":segments,"direction_cues":direction_cues,"markers":markers,
		"color_hex":color_hex,"render_style":"CHALK_CENTERLINE","draw_tile_cards":false,
		"draw_endpoint_markers":false,"draw_ground_markers":false}.duplicate(true)

func set_intent_overlays(rows: Array) -> void:
	var next_intents:Array[Dictionary]=[];var next_secondary:Array[Dictionary]=[]
	for row in rows:
		if not row is Dictionary: continue
		var copy:Dictionary=row.duplicate(true); var secondary=copy.get("automatic_suggestion",null)
		if secondary is Dictionary:next_secondary.append(secondary.duplicate(true))
		next_intents.append(copy)
	if _intent_overlays==next_intents and _secondary_intent_overlays==next_secondary:return
	_intent_overlays=next_intents;_secondary_intent_overlays=next_secondary
	queue_redraw()


func grid_rect() -> Rect2:
	var extent := minf(size.x,size.y); return Rect2((size-Vector2(extent,extent))*0.5,Vector2(extent,extent))
func cell_size_px() -> float: return grid_rect().size.x / float(visible_cell_count)
func world_cell_rect(position: Vector2i) -> Rect2:
	if not is_world_cell_visible(position):return Rect2()
	return _camera_cell_rect(position)
func _camera_cell_rect(position:Vector2i)->Rect2:
	if not view_bounds().has_point(position):return Rect2()
	var rect:=grid_rect();var cell:=cell_size_px();var local:=position-view_origin
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
	var world_position:=view_origin+local_cell
	return world_position if _world_in_bounds(world_position) else Vector2i(-1,-1)
func mapping_signature() -> Array:
	var rows: Array = [[view_origin.x,view_origin.y],visible_cell_count,[world_grid_size.x,world_grid_size.y]]
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var world:=view_origin+Vector2i(x,y); rows.append([[world.x,world.y],world_to_pixel_center(world)])
	return rows
func void_padding_draw_spec(position:Vector2i)->Dictionary:
	var visible:=view_bounds().has_point(position) and not _world_in_bounds(position)
	return {"visible":visible,"world_position":[position.x,position.y],
		"rect":_camera_cell_rect(position) if visible else Rect2(),
		"color_hex":str(AsciiStyleScript.diorama_palette_spec().get("void_hex","#010203")),
		"accepts_input":false}.duplicate(true)
func actor_hit_rect(entity_id: int) -> Rect2:
	for actor in _actors:
		if int(actor.get("entity_id",-1)) == entity_id:
			var p := Vector2i(int(actor.position[0]),int(actor.position[1]))
			if is_world_cell_visible(p):return Rect2(world_to_pixel_center(p)-Vector2(22,22),Vector2(44,44))
	return Rect2()
func actor_at_pointer(pointer: Vector2) -> int:
	if _camera_input_blocked():return -1
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

func actor_draw_spec(actor:Dictionary,ghost:bool=false,sample_time_ms:int=-1)->Dictionary:
	var projected := actor.duplicate(true)
	var entity_id := int(actor.get("entity_id",-1))
	if not ghost and _actor_motions.has(entity_id):
		var motion: Dictionary = _actor_motions[entity_id]
		var delta: Vector2 = motion.get("to_world",Vector2.ZERO) \
			- motion.get("from_world",Vector2.ZERO)
		if not delta.is_zero_approx():
			projected["facing"]=[signi(int(roundf(delta.x))),signi(int(roundf(delta.y)))]
			projected["visual_stance"]="MOVING"
			var sample:=actor_motion_draw_spec(entity_id,sample_time_ms)
			projected["step_phase"]=str(sample.get("step_phase","SETTLE"))
			projected["stride_sign"]=int(sample.get("stride_sign",0))
			projected["glyph_bob_ratio"]=float(sample.get("glyph_bob_ratio",0.0))
	elif bool(actor.get("guarded",false)):
		projected["visual_stance"]="GUARD"
	var style:Dictionary=AsciiStyleScript.actor_spec(projected,ghost)
	if ghost or str(style.get("life_state","ACTIVE"))!="ACTIVE":return style
	# A longer grounded lower body and slightly raised single body glyph create a
	# compact pseudo-depth silhouette without changing the logical actor cell.
	style["glyph_offset"]=Vector2(0.0,ACTOR_WORLD_GLYPH_OFFSET_Y)
	var limbs:Array=style.get("limb_segments",[]).duplicate(true)
	for leg_index in [2,3]:
		if leg_index<limbs.size() and limbs[leg_index] is Array \
				and limbs[leg_index].size()==2:
			var endpoint:=Vector2(limbs[leg_index][1]);endpoint.y=ACTOR_WORLD_LEG_END_Y
			limbs[leg_index][1]=endpoint
	if melee_vfx!=null:
		var swing:Dictionary=melee_vfx.attacker_swing_draw_spec(
			_position_from_actor(actor),sample_time_ms)
		if bool(swing.get("active",false)):_apply_melee_arm_swing(limbs,swing)
		style["melee_swing"]=swing
	style["limb_segments"]=limbs
	return style

func _apply_melee_arm_swing(limbs:Array,swing:Dictionary)->void:
	var arm_index:=int(swing.get("arm_index",1))
	if arm_index<0 or arm_index>=min(2,limbs.size()) \
			or not limbs[arm_index] is Array or limbs[arm_index].size()!=2:return
	var direction:=Vector2(swing.get("direction",Vector2.RIGHT)).normalized()
	var side_sign:=-1.0 if arm_index==0 else 1.0
	var resting:=Vector2(limbs[arm_index][1])
	var windup:=Vector2(-direction.x*float(MeleeVfxScript.PARAMS.swing_windup_reach) \
		+side_sign*float(MeleeVfxScript.PARAMS.swing_windup_side_offset),
		float(MeleeVfxScript.PARAMS.swing_center_y)-direction.y*float(
		MeleeVfxScript.PARAMS.swing_windup_reach_y))
	var strike:=Vector2(direction.x*float(MeleeVfxScript.PARAMS.swing_arm_reach_x) \
		+side_sign*float(MeleeVfxScript.PARAMS.swing_side_offset),
		float(MeleeVfxScript.PARAMS.swing_center_y)+direction.y*float(
		MeleeVfxScript.PARAMS.swing_arm_reach_y))
	var progress:=clampf(float(swing.get("phase_progress",0.0)),0.0,1.0)
	var endpoint:=resting
	match str(swing.get("phase","SETTLE")):
		"WIND_UP":endpoint=resting.lerp(windup,pow(progress,0.72))
		"SWING":endpoint=windup.lerp(strike,1.0-pow(1.0-progress,3.0))
		_:endpoint=strike.lerp(resting,1.0-pow(1.0-progress,2.0))
	limbs[arm_index][1]=endpoint

func actor_glyph_draw_spec(entity_id:int,sample_time_ms:int=-1)->Dictionary:
	var actor:=_actor_by_id(entity_id)
	if actor.is_empty():return {"visible":false,"entity_id":entity_id}.duplicate(true)
	var position:=_position_from_actor(actor)
	if not is_world_cell_visible(position):
		return {"visible":false,"entity_id":entity_id}.duplicate(true)
	var bounds:=_actor_figure_bounds(actor,cell_size_px(),false,sample_time_ms)
	if bounds.size.x<=0.0:return {"visible":false,"entity_id":entity_id}.duplicate(true)
	var style:=actor_draw_spec(actor,false,sample_time_ms)
	var glyph:=AsciiPortraitScript.glyph_layout_spec(get_theme_default_font(),bounds,style,true)
	var projected_segments:=AsciiPortraitScript.limb_draw_segments(bounds,style,glyph)
	var shadow:=AsciiPortraitScript.shadow_draw_spec(bounds,style,true)
	return glyph.merged({"visible":true,"entity_id":entity_id,"cell_rect":world_cell_rect(position),
		"limb_segments":projected_segments,"facing":style.facing,"stance":style.stance,
		"figure_bounds":bounds,"logical_position":[position.x,position.y],
		"top_overlap_px":maxf(0.0,world_cell_rect(position).position.y-float(glyph.glyph_rect.position.y)),
		"feet_bottom_margin_px":maxf(0.0,world_cell_rect(position).end.y-maxf(
			Vector2(projected_segments[2][1]).y,Vector2(projected_segments[3][1]).y)) \
			if projected_segments.size()>=4 else 0.0,
		"one_cell_one_glyph":true,"melee_swing":style.get("melee_swing",{"active":false}),
		"shadow":shadow,
		"selected_outline":false,"draw_equipment":false,
		"equipment_primitive_count":0}).duplicate(true)

func monster_awareness_marker_draw_spec(entity_id:int,sample_time_ms:int=-1)->Dictionary:
	var actor:=_actor_by_id(entity_id)
	if actor.is_empty() or not _is_enemy_actor(actor):return {"visible":false}.duplicate(true)
	var position:=_position_from_actor(actor);var row:Dictionary=_cells.get(_key(position),{})
	if not is_world_cell_visible(position) or row.is_empty() \
			or AsciiStyleScript.visibility_state(row)!="VISIBLE":return {"visible":false}.duplicate(true)
	var awareness:Dictionary=AsciiStyleScript.awareness_spec(actor.get("awareness_state","UNAWARE"))
	if not bool(awareness.visible):return {"visible":false,"state":str(awareness.state)}.duplicate(true)
	var now:=Time.get_ticks_msec() if sample_time_ms<0 else sample_time_ms
	var pulse_progress:=1.0;var pulse_active:=false
	if _awareness_pulses.has(entity_id):
		var pulse:Dictionary=_awareness_pulses[entity_id]
		pulse_progress=clampf(float(maxi(0,now-int(pulse.started_at_ms))) \
			/float(maxi(1,int(pulse.duration_ms))),0.0,1.0);pulse_active=pulse_progress<1.0
	var rect:=world_cell_rect(position);var cell:=rect.size.x
	var font_size:=clampi(int(floor(cell*0.40)),8,13)
	if pulse_active:font_size=maxi(font_size,int(roundf(font_size*(1.14-0.14*pulse_progress))))
	var extent:=get_theme_default_font().get_string_size(str(awareness.glyph),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var inset:=Vector2(maxf(extent.x*0.5+1.0,cell*0.20),maxf(extent.y*0.5+1.0,cell*0.20))
	var center:=rect.end-inset
	return {"visible":true,"entity_id":entity_id,"state":str(awareness.state),
		"glyph":str(awareness.glyph),"color_hex":str(awareness.color_hex),
		"world_position":[position.x,position.y],"cell_rect":rect,"center":center,
		"text_rect":Rect2(center-extent*0.5,extent),"font_size":font_size,
		"pulse_active":pulse_active,"pulse_progress":pulse_progress,
		"pulse_duration_ms":AWARENESS_PULSE_DURATION_MS,"changes_hit_rect":false}.duplicate(true)

func monster_awareness_marker_draw_specs(sample_time_ms:int=-1)->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	for actor in _actors:
		var spec:=monster_awareness_marker_draw_spec(int(actor.get("entity_id",-1)),sample_time_ms)
		if bool(spec.get("visible",false)):rows.append(spec)
	rows.sort_custom(func(a:Dictionary,b:Dictionary):
		var ap:=_array_to_world_position(a.world_position);var bp:=_array_to_world_position(b.world_position)
		return ap.y<bp.y if ap.y!=bp.y else (ap.x<bp.x if ap.x!=bp.x else int(a.entity_id)<int(b.entity_id)))
	return rows.duplicate(true)

func monster_list_draw_spec()->Dictionary:
	var groups:Dictionary={};var priority:={"HUNTING":0,"ALERT":1,"SUSPICIOUS":2,
		"SEARCHING":3,"RETURNING":4,"UNAWARE":5}
	for actor in _actors:
		if not _is_enemy_actor(actor):continue
		var position:=_position_from_actor(actor);var cell_row:Dictionary=_cells.get(_key(position),{})
		if not is_world_cell_visible(position) or cell_row.is_empty() \
				or AsciiStyleScript.visibility_state(cell_row)!="VISIBLE":continue
		var identity:Dictionary=AsciiStyleScript.monster_identity_spec(actor)
		var awareness:Dictionary=AsciiStyleScript.awareness_spec(actor.get("awareness_state","UNAWARE"))
		var key:="%s|%s"%[str(identity.species_id),str(awareness.state)]
		if not groups.has(key):groups[key]={"species_id":str(identity.species_id),
			"glyph":str(identity.glyph),"name":str(identity.name),
			"species_color_hex":str(identity.color_hex),"state":str(awareness.state),
			"mark":str(awareness.glyph),"mark_color_hex":str(awareness.color_hex),
			"count":0,"priority":int(priority.get(str(awareness.state),99))}
		groups[key].count=int(groups[key].count)+1
	var grouped:Array[Dictionary]=[]
	for value in groups.values():grouped.append((value as Dictionary).duplicate(true))
	grouped.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.priority)<int(b.priority) if int(a.priority)!=int(b.priority) \
			else (str(a.name)<str(b.name) if str(a.name)!=str(b.name) else str(a.state)<str(b.state)))
	if grouped.size()>MONSTER_LIST_MAX_ROWS:grouped=grouped.slice(0,MONSTER_LIST_MAX_ROWS)
	if grouped.is_empty():return {"visible":false,"rows":[],"mouse_filter":"IGNORE"}.duplicate(true)
	var font:=get_theme_default_font();var font_size:=clampi(int(cell_size_px()*0.43),10,13)
	var row_height:=float(font_size+4);var padding:=6.0;var max_width:=0.0
	for group in grouped:
		group["count_text"]=" ×%d"%int(group.count) if int(group.count)>1 else ""
		group["text"]="%s %s%s%s"%[str(group.glyph),str(group.name),
			(" "+str(group.mark)) if not str(group.mark).is_empty() else "",str(group.count_text)]
		max_width=maxf(max_width,font.get_string_size(str(group.text),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
	var rect:=grid_rect();var panel_size:=Vector2(max_width+padding*2.0,row_height*grouped.size()+padding*2.0)
	var bounds:=Rect2(rect.end-panel_size-Vector2(4,4),panel_size)
	for index in range(grouped.size()):grouped[index]["baseline"]=bounds.position+Vector2(padding,padding+row_height*index+font_size)
	return {"visible":true,"rows":grouped,"row_count":grouped.size(),"max_rows":MONSTER_LIST_MAX_ROWS,
		"font_size":font_size,"row_height":row_height,"bounds":bounds,"background_hex":"#030608e8",
		"border_hex":"#42666a","name_color_hex":"#d2c8ad","mouse_filter":"IGNORE",
		"process":false,"fov_safe":true}.duplicate(true)

func ground_item_draw_spec(position:Vector2i)->Dictionary:
	var hidden:={"visible":false,"glyph":"","kind":"","world_position":[position.x,position.y],
		"occupied_corner":false,"changes_hit_rect":false,"mouse_filter":"IGNORE",
		"draw_image":false,"texture_free":true,"fov_safe":true}
	if not is_world_cell_visible(position):return hidden.duplicate(true)
	_ensure_static_projection_cache()
	var cached:Dictionary=_static_projection_cache.get(_key(position),{})
	if cached.is_empty() or str(cached.get("visibility_state","UNSEEN"))!="VISIBLE":
		return hidden.duplicate(true)
	var row:Dictionary=cached.get("row",{})
	var item:Dictionary=AsciiStyleScript.item_presentation_spec(
		str(row.get("ground_item_glyph","")))
	if not bool(item.visible):return hidden.duplicate(true)
	var rect:=world_cell_rect(position);var occupied:=bool(cached.get("occupied",false))
	var font_ratio:=float(item.corner_font_ratio) if occupied else float(item.font_ratio)
	var font_size:=maxi(8,int(floor(rect.size.x*font_ratio)))
	var font:=get_theme_default_font()
	var extent:=font.get_string_size(str(item.glyph),
		HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	while font_size>8 and (extent.x>rect.size.x-2.0 or extent.y>rect.size.y-2.0):
		font_size-=1
		extent=font.get_string_size(str(item.glyph),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var center:=rect.position+extent*0.5+Vector2(1.0,0.0) \
		if occupied else rect.get_center()+Vector2(0.0,rect.size.y*0.03)
	return {"visible":true,"glyph":str(item.glyph),"kind":str(item.kind),
		"world_position":[position.x,position.y],"cell_rect":rect,"center":center,
		"text_rect":Rect2(center-extent*0.5,extent),"font_size":font_size,
		"color_hex":str(item.color_hex),"highlight_hex":str(item.highlight_hex),
		"underlay_hex":str(item.underlay_hex),
		"underlay_opacity":float(item.underlay_opacity),"occupied_corner":occupied,
		"layer":"GROUND_ITEMS","draw_after":["GROUND_FEATURES","GROUND_HAZARDS"],
		"draw_before":["ACTORS"],"changes_hit_rect":false,"mouse_filter":"IGNORE",
		"draw_image":false,"texture_free":true,"fov_safe":true}.duplicate(true)

func ground_item_draw_specs()->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var spec:=ground_item_draw_spec(view_origin+Vector2i(x,y))
			if bool(spec.visible):rows.append(spec)
	return rows.duplicate(true)

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
	_ensure_static_projection_cache()
	var cached:Dictionary=_static_projection_cache.get(_key(position),{})
	if not cached.is_empty():return (cached.get("cell_spec",{}) as Dictionary).duplicate(true)
	return _compute_diorama_cell_spec(position)

func _compute_diorama_cell_spec(position:Vector2i)->Dictionary:
	if not _world_in_bounds(position):
		return DioramaScript.cell_spec(position,{}, {})
	var neighbors:={
		"N":DioramaScript.sanitize_observed_cell(_cells.get(_key(position+Vector2i.UP),{})),
		"E":DioramaScript.sanitize_observed_cell(_cells.get(_key(position+Vector2i.RIGHT),{})),
		"S":DioramaScript.sanitize_observed_cell(_cells.get(_key(position+Vector2i.DOWN),{})),
		"W":DioramaScript.sanitize_observed_cell(_cells.get(_key(position+Vector2i.LEFT),{})),
	}
	return DioramaScript.cell_spec(position,_cells.get(_key(position),{}),neighbors)

func _ensure_static_projection_cache()->void:
	if not _static_projection_dirty:return
	_static_projection_cache.clear();_occupied_visible_cells.clear()
	for actor in _actors:
		var actor_position:=_position_from_actor(actor)
		if is_world_cell_visible(actor_position):_occupied_visible_cells[_key(actor_position)]=true
	var cell_size:=cell_size_px()
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y);var key:=_key(position)
			var in_world:=_world_in_bounds(position)
			var rect:=_camera_cell_rect(position)
			if not in_world:
				_static_projection_cache[key]={"position":position,"in_world":false,
					"rect":rect,"visibility_state":"VOID","occupied":false,
					"light":DioramaScript.quantized_light_spec(position,
						_hero_camera_position,"UNSEEN"),"cell_spec":DioramaScript.cell_spec(position,{}, {})}
				continue
			var row:Dictionary=_cells.get(key,{})
			var state:=_diorama_visibility_state(row)
			var terrain:=AsciiStyleScript.terrain_spec(row)
			var cell_spec:=_compute_diorama_cell_spec(position)
			var depth:=DioramaScript.terrain_depth_spec(row,cell_size)
			depth["position"]=[position.x,position.y];depth["top_rect"]=rect
			depth["side_rect"]=Rect2(rect.position+Vector2(depth.side_offset),rect.size) \
				if bool(depth.raised) else Rect2()
			var wall_role:=DioramaScript.wall_role_spec(int(cell_spec.get("connected_mask",0)),
				int(cell_spec.get("exposed_mask",0))) if str(terrain.get("terrain_id",""))=="wall" else {}
			_static_projection_cache[key]={"position":position,"in_world":true,"rect":rect,
				"row":row,"visibility_state":state,"terrain":terrain,"cell_spec":cell_spec,
				"depth":depth,"wall_role":wall_role,"occupied":_occupied_visible_cells.has(key),
				"light":DioramaScript.quantized_light_spec(position,_hero_camera_position,state)}
	_rebuild_torch_cache()
	_static_projection_dirty=false;_static_projection_rebuild_count+=1

func _rebuild_torch_cache()->void:
	var visible_candidates:Array[Dictionary]=[]
	var memory_candidates:Array[Dictionary]=[]
	for cached_value in _static_projection_cache.values():
		var cached:=cached_value as Dictionary
		if str((cached.get("terrain",{}) as Dictionary).get("terrain_id",""))!="wall":continue
		var state:=str(cached.get("visibility_state","UNSEEN"))
		if state=="UNSEEN":continue
		var cell_spec:Dictionary=cached.get("cell_spec",{})
		if int(cell_spec.get("exposed_mask",0))==0:continue
		var position:Vector2i=cached.get("position",Vector2i(-1,-1))
		var candidate:={"position":position,
			"score":DioramaScript.visual_hash(position,907)}
		if state=="VISIBLE":visible_candidates.append(candidate)
		else:memory_candidates.append(candidate)
	visible_candidates.sort_custom(func(a:Dictionary,b:Dictionary):
		if int(a.score)!=int(b.score):return int(a.score)<int(b.score)
		var ap:Vector2i=a.position;var bp:Vector2i=b.position
		return ap.y<bp.y or ap.y==bp.y and ap.x<bp.x)
	memory_candidates.sort_custom(func(a:Dictionary,b:Dictionary):
		if int(a.score)!=int(b.score):return int(a.score)<int(b.score)
		var ap:Vector2i=a.position;var bp:Vector2i=b.position
		return ap.y<bp.y or ap.y==bp.y and ap.x<bp.x)
	_torch_positions.clear();_visible_torch_count=0
	for candidate in visible_candidates:
		if _visible_torch_count>=MAX_VISIBLE_TORCHES:break
		var position:Vector2i=candidate.position
		if _torch_spacing_clear(position):
			_torch_positions.append(position);_visible_torch_count+=1
	var memory_count:=0
	for candidate in memory_candidates:
		if memory_count>=MAX_MEMORY_TORCHES:break
		var position:Vector2i=candidate.position
		if _torch_spacing_clear(position):
			_torch_positions.append(position);memory_count+=1
	_torch_cache_rebuild_count+=1;_sync_torch_timer()

func _torch_spacing_clear(position:Vector2i)->bool:
	for selected in _torch_positions:
		if maxi(absi(position.x-selected.x),absi(position.y-selected.y))<TORCH_SPACING_CELLS:
			return false
	return true

func torch_draw_specs(sample_time_ms:int=-1)->Array[Dictionary]:
	_ensure_static_projection_cache()
	var now:=Time.get_ticks_msec() if sample_time_ms<0 else sample_time_ms
	var tick:=int(floor(float(now)/float(TORCH_FLICKER_QUANTUM_MS)))
	var rows:Array[Dictionary]=[]
	for position in _torch_positions:
		var cached:Dictionary=_static_projection_cache.get(_key(position),{})
		var state:=str(cached.get("visibility_state","UNSEEN"))
		if state=="UNSEEN" or not is_world_cell_visible(position):continue
		var animated:=state=="VISIBLE"
		var phase:=(tick+DioramaScript.visual_hash(position,313))%4 if animated else 0
		var brightness:float=float([0.92,1.0,0.95,0.98][phase]) if animated else 0.20
		rows.append({"position":[position.x,position.y],"visibility_state":state,
			"visible":true,"animated":animated,"glyph":"!","glyph_count":1,
			"glyph_hex":TORCH_GLYPH_HEX if animated else "#4d463c",
			"brightness":brightness,"flicker_tick":tick if animated else 0,
			"flicker_hz":1000.0/float(TORCH_FLICKER_QUANTUM_MS) if animated else 0.0,
			"pool_radius_cells":4.0 if animated else 0.0,
			"draw_light_pool":animated,"draw_image":false,"texture":null,
			"pixel_center":world_to_pixel_center(position)}.duplicate(true))
	return rows.duplicate(true)

func torch_light_draw_spec(position:Vector2i,sample_time_ms:int=-1)->Dictionary:
	_ensure_static_projection_cache()
	var now:=Time.get_ticks_msec() if sample_time_ms<0 else sample_time_ms
	return _torch_light_draw_spec_cached(position,now).duplicate(true)

func _torch_light_draw_spec_cached(position:Vector2i,now:int)->Dictionary:
	var cached:Dictionary=_static_projection_cache.get(_key(position),{})
	var state:=str(cached.get("visibility_state","UNSEEN"))
	if state!="VISIBLE":
		return {"active":false,"visibility_state":state,"distance":-1,
			"brightness":0.0,"color_hex":TORCH_AMBER_HEX}
	var tick:=int(floor(float(now)/float(TORCH_FLICKER_QUANTUM_MS)))
	var best_distance:=99;var best_brightness:=0.0
	for torch_position in _torch_positions:
		var torch_cached:Dictionary=_static_projection_cache.get(_key(torch_position),{})
		if str(torch_cached.get("visibility_state","UNSEEN"))!="VISIBLE":continue
		var distance:=maxi(absi(position.x-torch_position.x),absi(position.y-torch_position.y))
		if distance>4:continue
		var phase:=(tick+DioramaScript.visual_hash(torch_position,313))%4
		var torch_brightness:float=float([0.92,1.0,0.95,0.98][phase])
		var strength:=torch_brightness*maxf(0.0,1.0-float(distance)/4.75)
		if strength>best_brightness:
			best_brightness=strength;best_distance=distance
	return {"active":best_brightness>0.0,"visibility_state":state,
		"distance":best_distance if best_brightness>0.0 else -1,
		"brightness":best_brightness,"color_hex":TORCH_AMBER_HEX,
		"radius_cells":4.0,"composite_alpha":0.07+0.17*best_brightness}

func torch_cache_stats()->Dictionary:
	_ensure_static_projection_cache()
	return {"cached_count":_torch_positions.size(),"visible_count":_visible_torch_count,
		"max_visible":MAX_VISIBLE_TORCHES,"rebuild_count":_torch_cache_rebuild_count,
		"flicker_hz":1000.0/float(TORCH_FLICKER_QUANTUM_MS)}.duplicate(true)

func _cached_static_cell(position:Vector2i)->Dictionary:
	_ensure_static_projection_cache()
	return _static_projection_cache.get(_key(position),{})

func static_projection_cache_stats()->Dictionary:
	_ensure_static_projection_cache()
	return {"cell_count":_static_projection_cache.size(),"viewport_capacity":
		visible_cell_count*visible_cell_count,"rebuild_count":_static_projection_rebuild_count,
		"dirty":_static_projection_dirty,"world_cell_count":_cells.size()}.duplicate(true)

func terrain_depth_draw_spec(position:Vector2i)->Dictionary:
	if not is_world_cell_visible(position):
		return {"visible":false,"position":[position.x,position.y],"raised":false,
			"extrusion_px":0.0,"draw_image":false,"draw_cell_border":false}.duplicate(true)
	var cached:=_cached_static_cell(position)
	return (cached.get("depth",{}) as Dictionary).duplicate(true)

func terrain_glyph_draw_spec(position:Vector2i)->Dictionary:
	if not _world_in_bounds(position):
		return {"visible":false,"position":[position.x,position.y],"glyph":"",
			"registered":false,"draw_image":false,"draw_tile_border":false}.duplicate(true)
	var row:Dictionary=_cells.get(_key(position),{})
	var terrain:Dictionary=AsciiStyleScript.terrain_spec(row)
	var state:=_diorama_visibility_state(row)
	var cached:=_cached_static_cell(position)
	var light:Dictionary=cached.get("light",DioramaScript.quantized_light_spec(
		position,_hero_camera_position,state))
	var occupied:=bool(cached.get("occupied",false))
	var visible:=bool(terrain.get("glyph_primary",false)) and state!="UNSEEN"
	var rendered_glyph:=_diorama_ink_color(str(terrain.glyph_hex),float(terrain.opacity) \
		*(0.46 if occupied else 1.0),state,light,true) if visible else Color(0,0,0,0)
	return {"visible":visible,"position":[position.x,position.y],
		"terrain_id":str(terrain.terrain_id) if visible else "",
		"visibility_state":state,"glyph":str(terrain.glyph) if visible else "",
		"base_hex":str(terrain.base_hex) if visible else "",
		"glyph_hex":str(terrain.glyph_hex) if visible else "",
		"rendered_glyph_color":rendered_glyph,
		"light_band":str(light.get("band","UNANCHORED")),"occupied":occupied,
		"ink_family":str(terrain.get("ink_family","")),
		"font_ratio":float(terrain.get("font_ratio",0.54)),
		"glyph_offset":terrain.get("glyph_offset",Vector2.ZERO),
		"slab_ratio":terrain.get("slab_ratio",Vector2.ZERO),
		"outline_passes":int(terrain.get("outline_passes",0)),
		"weight_passes":int(terrain.get("weight_passes",1)),
		"opacity":float(terrain.opacity) if visible else 0.0,
		"registered":bool(terrain.get("registered",false)),
		"glyph_primary":visible,"draw_image":false,"draw_tile_border":false,
		"draw_cell_surface":bool(terrain.get("draw_cell_surface",false)) if visible else false,
		"background_source":str(terrain.get("background_source","GRID_FLAT")),
		"pixel_rect":world_cell_rect(position) if visible else Rect2()}.duplicate(true)

func visibility_ground_draw_spec(position:Vector2i)->Dictionary:
	if view_bounds().has_point(position) and not _world_in_bounds(position):
		return {"visible":true,"visibility_state":"VOID",
			"color_hex":str(AsciiStyleScript.diorama_palette_spec().get("void_hex","#010203")),
			"draw_terrain":false,"draw_actors":false,"draw_hazards":false,
			"pixel_rect":_camera_cell_rect(position)}.duplicate(true)
	if not is_world_cell_visible(position):
		return {"visible":false,"visibility_state":"OFF_CAMERA","color_hex":"",
			"draw_terrain":false,"draw_actors":false,"draw_hazards":false,
			"pixel_rect":Rect2()}.duplicate(true)
	var row:Dictionary=_cells.get(_key(position),{})
	var visibility:Dictionary=AsciiStyleScript.visibility_spec(_diorama_visibility_state(row))
	return {"visible":true,"visibility_state":str(visibility.state),
		"color_hex":str(visibility.background_hex),
		"draw_terrain":bool(visibility.draw_terrain),
		"draw_actors":bool(visibility.draw_actors),
		"draw_hazards":bool(visibility.draw_hazards),
		"pixel_rect":world_cell_rect(position)}.duplicate(true)

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
	return not _camera_input_blocked() and is_world_cell_visible(position) \
		and _cells.has(_key(position)) \
		and bool(AsciiStyleScript.visibility_spec(_cells[_key(position)]).accepts_actor_input)

func _cell_allows_overlay(position:Vector2i)->bool:
	return is_world_cell_visible(position) and _cells.has(_key(position)) \
		and AsciiStyleScript.visibility_state(_cells.get(_key(position),{}))!="UNSEEN"

func _array_to_world_position(value:Variant)->Vector2i:
	if value is Vector2i:return value
	if value is Array and value.size()==2:return Vector2i(int(value[0]),int(value[1]))
	return Vector2i(-1,-1)

func _actor_visual_key(entity_id:int,position:Vector2i)->String:
	return "%d:%d:%d"%[entity_id,position.x,position.y]

func _visual_actor_projection_hash()->int:
	var rows:Array=[]
	for source in [_actors,_ghosts]:
		for actor in source:
			if not actor is Dictionary:continue
			var visual:Dictionary=actor.duplicate(true)
			# These values are card/log concerns and never affect the grid glyph.
			for key in ["health","max_health","stress","emotion","readiness",
					"progression","expected_action","remaining_time"]:
				visual.erase(key)
			rows.append(visual)
	return hash(rows)

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
	_ensure_melee_vfx()
	_ensure_static_projection_cache()
	var palette:=AsciiStyleScript.diorama_palette_spec()
	draw_rect(grid_rect(),Color(str(palette.get("substrate_hex","#091017"))),true)
	var camera_offset:Vector2=camera_settle_draw_spec().offset_px
	draw_set_transform(camera_offset)
	_draw_void_padding(Color(str(palette.get("void_hex","#010203"))))
	_draw_ground_pass("MEMORY")
	_draw_ground_pass("VISIBLE")
	_draw_terrain_glyph_pass("MEMORY")
	_draw_terrain_glyph_pass("VISIBLE")
	_draw_material_mark_pass("MEMORY")
	_draw_material_mark_pass("VISIBLE")
	_draw_wall_shadow_pass("MEMORY")
	_draw_wall_shadow_pass("VISIBLE")
	_draw_wall_pass("MEMORY")
	_draw_wall_pass("VISIBLE")
	# Warm light is composited after both ground and wall ink so it remains
	# visible on neighboring surfaces rather than being painted over.
	_draw_torch_light_pools()
	_draw_wall_torches()
	_draw_ground_features()
	_draw_ground_hazards()
	_draw_follower_footprints()
	_draw_route_overlay()
	_draw_exploration_companion_follow_plan()
	_draw_ground_items()
	for visual_row in _sorted_visual_actor_rows():
		_draw_actor(visual_row.actor,cell_size_px(),bool(visual_row.ghost),camera_offset)
	_draw_monster_awareness_marks()
	for intent in _secondary_intent_overlays:
		_draw_intent(intent)
	for intent in _intent_overlays:
		_draw_intent(intent)
	_draw_actor_selection_overlays()
	_draw_cursor_preview()
	_draw_fov_edge_haze()
	draw_set_transform(Vector2.ZERO)
	_draw_monster_list()
	# Phase is communicated inside the field (glyph motion, ink impact and HUD),
	# never by shrinking the playable view behind a decorative screen border.

func _draw_monster_awareness_marks()->void:
	for spec in monster_awareness_marker_draw_specs():
		var color:=Color(str(spec.color_hex))
		if bool(spec.pulse_active):
			var pulse_alpha:=0.24*(1.0-float(spec.pulse_progress))
			draw_circle(Vector2(spec.center),maxf(4.0,float(spec.font_size)*0.62),
				Color(color,pulse_alpha))
		_draw_centered_text(get_theme_default_font(),str(spec.glyph),Vector2(spec.center),
			int(spec.font_size),color)

func _draw_monster_list()->void:
	var spec:=monster_list_draw_spec()
	if not bool(spec.visible):return
	var bounds:Rect2=spec.bounds;draw_rect(bounds,Color(str(spec.background_hex)),true)
	draw_rect(bounds,Color(str(spec.border_hex)),false,1.0)
	var font:=get_theme_default_font();var font_size:=int(spec.font_size)
	for row in spec.rows:
		var baseline:=Vector2(row.baseline);var x:=baseline.x
		for segment in [[str(row.glyph),str(row.species_color_hex)],
				[" "+str(row.name),str(spec.name_color_hex)],
				[(" "+str(row.mark)) if not str(row.mark).is_empty() else "",str(row.mark_color_hex)],
				[str(row.count_text),"#849097"]]:
			var value:=str(segment[0])
			if value.is_empty():continue
			draw_string(font,Vector2(x,baseline.y),value,HORIZONTAL_ALIGNMENT_LEFT,-1,
				font_size,Color(str(segment[1])))
			x+=font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x

func _draw_ground_items()->void:
	var font:=get_theme_default_font()
	for spec in ground_item_draw_specs():
		var center:=Vector2(spec.center);var font_size:=int(spec.font_size)
		var underlay_color:=_visual_color(str(spec.underlay_hex),float(spec.underlay_opacity))
		var underlay_radius:=maxf(2.0,float(font_size)*0.48)
		draw_circle(center+Vector2(0.7,1.0),underlay_radius,underlay_color)
		_draw_centered_text(font,str(spec.glyph),center+Vector2(0.8,1.0),font_size,
			Color("#020304c8"))
		_draw_centered_text(font,str(spec.glyph),center,font_size,Color(str(spec.color_hex)))

func _draw_void_padding(void_color:Color)->void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y)
			if not _world_in_bounds(position):
				draw_rect(_camera_cell_rect(position),void_color,true)

func _draw_melee_target_background_flashes()->void:
	if melee_vfx==null:return
	for spec in melee_vfx.background_flash_specs():
		var color:=Color(str(spec.get("color_hex","#ff334d")))
		color.a=clampf(float(spec.get("opacity",0.0)),0.0,1.0)
		# This pass is intentionally below every feature, actor, and glyph. Only
		# the target cell background changes during impact registration.
		draw_rect(Rect2(spec.get("rect",Rect2())),color,true)

func _draw_ground_pass(visibility_state:String)->void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y)
			var cached:=_cached_static_cell(position)
			if str(cached.get("visibility_state",""))!=visibility_state:continue
			var row:Dictionary=cached.get("row",{})
			var visibility:Dictionary=AsciiStyleScript.visibility_spec(row)
			var light:Dictionary=cached.get("light",{})
			# Borderless overlapping fills make adjacent visible cells read as one
			# continuous pool of light instead of a tile checkerboard.
			var wash_rect:=world_cell_rect(position)
			var wash_overlap:=clampf(cell_size_px()*0.035,0.75,1.5)
			draw_rect(wash_rect.grow(wash_overlap).intersection(grid_rect()),
				_diorama_ink_color(str(visibility.background_hex),1.0,
				visibility_state,light,false),true)
			var terrain:Dictionary=cached.get("terrain",{})
			if not bool(terrain.visible) or str(terrain.terrain_id)=="wall":continue
			_draw_ground_surface(position,terrain,visibility_state,light,
				bool(cached.get("occupied",false)))

func _draw_ground_surface(position:Vector2i,terrain:Dictionary,
		visibility_state:String,light:Dictionary,occupied:bool)->void:
	# Ordinary floor owns no per-cell surface at all: the single grid-wide
	# substrate is its background and `.` is its only cell-local identity.
	if str(terrain.get("terrain_id",""))=="floor":return
	if not bool(terrain.get("draw_cell_surface",true)):return
	var rect:=world_cell_rect(position)
	var slab_ratio:Vector2=terrain.get("slab_ratio",Vector2(0.72,0.52))
	if slab_ratio.x<=0.0 or slab_ratio.y<=0.0:return
	var slab_size:=Vector2(rect.size.x*slab_ratio.x,rect.size.y*slab_ratio.y)
	var glyph_offset:Vector2=terrain.get("glyph_offset",Vector2.ZERO)
	var slab_center:=rect.get_center()+Vector2(glyph_offset.x*rect.size.x,
		glyph_offset.y*rect.size.y)
	var slab_rect:=Rect2(slab_center-slab_size*0.5,slab_size)
	var base:=_diorama_ink_color(str(terrain.get("slab_hex",terrain.base_hex)),
		float(terrain.opacity)*(0.68 if occupied else 0.84),visibility_state,light,false)
	draw_rect(slab_rect,base,true)

func _draw_torch_light_pools()->void:
	# Cell-clipped washes cannot illuminate MEMORY/UNSEEN neighbors. This keeps
	# the warm pool FOV-safe without a texture, shader, or offscreen viewport.
	var now:=Time.get_ticks_msec()
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y)
			var light:=_torch_light_draw_spec_cached(position,now)
			if not bool(light.active):continue
			var amber:=Color(str(light.color_hex))
			amber.a=float(light.get("composite_alpha",0.07+0.17*float(light.brightness)))
			var overlap:=clampf(cell_size_px()*0.025,0.5,1.0)
			draw_rect(world_cell_rect(position).grow(overlap).intersection(grid_rect()),amber,true)

func _draw_terrain_glyph_pass(visibility_state:String)->void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y)
			var cached:=_cached_static_cell(position)
			if str(cached.get("visibility_state",""))!=visibility_state:continue
			var terrain:Dictionary=cached.get("terrain",{})
			if str(terrain.terrain_id)=="wall":continue
			_draw_terrain_glyph(world_cell_rect(position),terrain,
				visibility_state,cached.get("light",{}),bool(cached.get("occupied",false)))

func _draw_material_mark_pass(visibility_state:String)->void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y)
			var cached:=_cached_static_cell(position)
			if str(cached.get("visibility_state",""))!=visibility_state \
					or bool(cached.get("occupied",false)):continue
			var cell_spec:Dictionary=cached.get("cell_spec",{})
			var mark:Dictionary=cell_spec.get("material_mark",{})
			if not bool(mark.get("visible",false)):continue
			var terrain:Dictionary=cached.get("terrain",{})
			var rect:=world_cell_rect(position)
			var offset:Vector2=mark.get("offset",Vector2.ZERO)
			var center:=rect.get_center()+Vector2(offset.x*rect.size.x,offset.y*rect.size.y)
			var opacity:=float(mark.get("opacity",0.0))*float(terrain.get("opacity",1.0))
			var color:=_diorama_ink_color(str(terrain.get("glyph_hex","#8090a0")),
				opacity,visibility_state,cached.get("light",{}),true)
			_draw_centered_text(get_theme_default_font(),str(mark.get("glyph","")),center,
				maxi(7,int(rect.size.x*0.28)),color)

func _draw_wall_shadow_pass(visibility_state:String)->void:
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y)
			var cached:=_cached_static_cell(position)
			if str(cached.get("visibility_state",""))!=visibility_state \
					or str((cached.get("terrain",{}) as Dictionary).get("terrain_id",""))!="wall":continue
			var spec:Dictionary=cached.get("cell_spec",{})
			var exposed:=int(spec.get("exposed_mask",0))
			var rect:=world_cell_rect(position);var cell:=rect.size.x
			var alpha:=0.10 if visibility_state=="VISIBLE" else 0.035
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
			var cached:=_cached_static_cell(position)
			if str(cached.get("visibility_state",""))!=visibility_state:continue
			var terrain:Dictionary=cached.get("terrain",{})
			if str(terrain.terrain_id)!="wall":continue
			var spec:Dictionary=cached.get("cell_spec",{});var connected:=int(spec.connected_mask)
			var wall_role:Dictionary=cached.get("wall_role",{})
			var rect:=world_cell_rect(position);var cell:=rect.size.x
			var overlap:=clampf(cell*0.045,1.0,2.0)
			var depth:Dictionary=cached.get("depth",{})
			var light:Dictionary=cached.get("light",{})
			if bool(depth.get("raised",false)):
				var side:=_diorama_ink_color(str(depth.side_hex),float(depth.opacity),
					visibility_state,light,false)
				draw_rect((depth.side_rect as Rect2).grow(overlap).intersection(grid_rect()),side,true)
				if bool(wall_role.get("face_visible",false)):
					var side_center:=rect.get_center()+Vector2(depth.side_offset)
					var side_font_size:=maxi(8,int(floor(cell*0.58)))
					_draw_centered_text(get_theme_default_font(),str(wall_role.face_glyph),
						side_center,side_font_size,_diorama_ink_color(str(terrain.glyph_hex),
						0.30*float(depth.opacity),visibility_state,light,true))
			var slab_ratio:Vector2=wall_role.get("slab_ratio",Vector2(0.94,0.92))
			var slab_size:=Vector2(rect.size.x*slab_ratio.x,rect.size.y*slab_ratio.y)
			var top_rect:=Rect2(rect.get_center()-slab_size*0.5,slab_size)
			var top:=_diorama_ink_color(str(terrain.base_hex),float(terrain.opacity),
				visibility_state,light,false)
			draw_rect(top_rect.grow(overlap).intersection(grid_rect()),top,true)
			# Two restrained masonry seams deepen the wall mass without introducing
			# per-tile borders or changing the canonical '#'.
			var inner_shadow:=Color("#030507",0.42 if visibility_state=="VISIBLE" else 0.18)
			draw_line(top_rect.position+Vector2(1,1),
				Vector2(top_rect.end.x-1,top_rect.position.y+1),inner_shadow,1.0,true)
			draw_line(top_rect.position+Vector2(1,1),
				Vector2(top_rect.position.x+1,top_rect.end.y-1),inner_shadow,1.0,true)
			var edge:=_diorama_ink_color(str(terrain.edge_hex),0.54*float(terrain.opacity),
				visibility_state,light,true)
			if not connected&DioramaScript.SOUTH:
				draw_line(Vector2(rect.position.x,rect.end.y-1),rect.end-Vector2(0,1),edge,1.0,true)
			if not connected&DioramaScript.EAST:
				draw_line(Vector2(rect.end.x-1,rect.position.y),rect.end-Vector2(1,0),edge,1.0,true)
			var role_terrain:=terrain.duplicate(false)
			role_terrain["glyph"]=str(wall_role.get("core_glyph","#"))
			role_terrain["glyph_offset"]=wall_role.get("glyph_offset",Vector2.ZERO)
			role_terrain["role_emphasis"]=float(wall_role.get("foreground_emphasis",0.82))
			_draw_terrain_glyph(rect,role_terrain,visibility_state,light,false)

func _draw_wall_torches()->void:
	for spec in torch_draw_specs():
		if not bool(spec.visible):continue
		var center:Vector2=spec.pixel_center
		var color:=Color(str(spec.glyph_hex));color.a=float(spec.brightness)
		# One ASCII glyph, confined to its wall cell. No image/texture primitive.
		var glow:=Color(TORCH_AMBER_HEX);glow.a=0.19*float(spec.brightness)
		draw_circle(center+Vector2(0,cell_size_px()*0.10),cell_size_px()*0.18,glow)
		var shadow:=Color("#1a0b04",0.92)
		_draw_centered_text(get_theme_default_font(),str(spec.glyph),
			center+Vector2(0.8,cell_size_px()*0.10+0.8),maxi(9,int(cell_size_px()*0.50)),shadow)
		_draw_centered_text(get_theme_default_font(),str(spec.glyph),
			center+Vector2(0,cell_size_px()*0.10),maxi(9,int(cell_size_px()*0.50)),color)

func _draw_terrain_glyph(rect:Rect2,terrain:Dictionary,visibility_state:String,
		light:Dictionary,occupied:bool)->void:
	if not bool(terrain.get("glyph_primary",false)):return
	var glyph:=str(terrain.get("glyph",""))
	if glyph.is_empty():return
	var glyph_offset:Vector2=terrain.get("glyph_offset",Vector2.ZERO)
	var center:=rect.get_center()+Vector2(glyph_offset.x*rect.size.x,glyph_offset.y*rect.size.y)
	var font:=get_theme_default_font()
	var font_size:=maxi(8,int(floor(rect.size.x*float(terrain.get("font_ratio",0.54)))))
	var role_emphasis:=float(terrain.get("role_emphasis",1.0))
	var occupancy_multiplier:=0.46 if occupied else 1.0
	var outline:=_diorama_ink_color(str(terrain.get("outline_hex","#020508")),
		float(terrain.opacity)*role_emphasis,visibility_state,light,true)
	var color:=_diorama_ink_color(str(terrain.glyph_hex),float(terrain.opacity) \
		*role_emphasis*occupancy_multiplier,visibility_state,light,true)
	var directions:=[Vector2(-1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,1)]
	for index in range(clampi(int(terrain.get("outline_passes",0)),0,directions.size())):
		_draw_centered_text(font,glyph,center+directions[index]*0.72,font_size,outline)
	if int(terrain.get("weight_passes",1))>=2:
		_draw_centered_text(font,glyph,center+Vector2(-0.24,0),font_size,color)
	_draw_centered_text(font,glyph,center,font_size,color)

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

func _draw_fov_edge_haze()->void:
	var thickness:=clampf(cell_size_px()*0.13,2.0,5.0)
	for y in range(visible_cell_count):
		for x in range(visible_cell_count):
			var position:=view_origin+Vector2i(x,y)
			var cached:=_cached_static_cell(position);var spec:Dictionary=cached.get("cell_spec",{})
			if not bool(spec.get("visible",false)):continue
			var mask:=int(spec.get("fov_edge_mask",0));var rect:=world_cell_rect(position)
			var color:=Color(0.015,0.03,0.045,0.46 if str(spec.visibility_state)=="VISIBLE" else 0.27)
			if mask&DioramaScript.NORTH:draw_rect(Rect2(rect.position,Vector2(rect.size.x,thickness)),color,true)
			if mask&DioramaScript.EAST:draw_rect(Rect2(Vector2(rect.end.x-thickness,rect.position.y),Vector2(thickness,rect.size.y)),color,true)
			if mask&DioramaScript.SOUTH:draw_rect(Rect2(Vector2(rect.position.x,rect.end.y-thickness),Vector2(rect.size.x,thickness)),color,true)
			if mask&DioramaScript.WEST:draw_rect(Rect2(rect.position,Vector2(thickness,rect.size.y)),color,true)

func _diorama_color(value:String,opacity:float,memory:bool)->Color:
	return _diorama_ink_color(value,opacity,"MEMORY" if memory else "VISIBLE",
		{"background_multiplier":1.0,"foreground_multiplier":1.0,"saturation":0.22 \
		if memory else 1.0},true)

func _diorama_ink_color(value:String,opacity:float,visibility_state:String,
		light:Dictionary,foreground:bool)->Color:
	var color:=Color(value)
	var saturation:=clampf(float(light.get("saturation",1.0)),0.0,1.0)
	if visibility_state=="MEMORY":saturation=minf(saturation,0.14)
	if saturation<1.0:
		var luminance:=color.r*0.299+color.g*0.587+color.b*0.114
		color=color.lerp(Color(luminance,luminance,luminance,1.0),1.0-saturation)
	var multiplier:=float(light.get("foreground_multiplier",1.0)) if foreground \
		else float(light.get("background_multiplier",1.0))
	color.r*=multiplier;color.g*=multiplier;color.b*=multiplier
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
	var halo:=Color(str(spec.get("halo_hex","#05090d")));halo.a=0.72
	var slab_size:=Vector2(rect.size.x*0.58,rect.size.y*0.66)
	draw_rect(Rect2(center-slab_size*0.5,slab_size),halo,true)
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
		"FLASH_RING":draw_arc(center,radius,0,TAU,20,color,width)
		"GLYPH_FLASH":
			for particle in spec.particles:
				var particle_color:=color;particle_color.a*=float(particle.opacity)
				draw_line(particle.from,particle.to,particle_color,
					float(particle.line_width),true)
				_draw_centered_text(get_theme_default_font(),str(particle.get("glyph","*")),
					Vector2(particle.to),int(particle.get("font_size",11)),particle_color)
		"TEXT":
			if str(spec.kind)=="FLOATING_AMOUNT":
				_draw_centered_text(get_theme_default_font(),str(spec.text),center+Vector2(1.2,1.4),
					int(spec.font_size),Color(0.01,0.02,0.03,color.a*0.88))
			_draw_centered_text(get_theme_default_font(),str(spec.text),center,
				int(spec.font_size),color)
		"DEATH_CROSS":
			draw_line(center-Vector2(radius,radius),center+Vector2(radius,radius),color,width)
			draw_line(center+Vector2(radius,-radius),center+Vector2(-radius,radius),color,width)

func _draw_actor(actor: Dictionary, cell: float, ghost: bool,
		camera_offset:Vector2=Vector2.ZERO) -> void:
	if not actor.get("position") is Array or actor.position.size() != 2: return
	var p := Vector2i(int(actor.position[0]),int(actor.position[1]))
	if not is_world_cell_visible(p):return
	var bounds:=_actor_figure_bounds(actor,cell,ghost)
	if bounds.size.x<=0.0:return
	if not ghost and int(actor.get("entity_id",-1))==_hero_camera_actor_id:
		bounds.position-=camera_offset
	var style:=actor_draw_spec(actor,ghost)
	AsciiPortraitScript.draw_figure(self,get_theme_default_font(),bounds,style,true,true)

func _actor_figure_bounds(actor:Dictionary,cell:float,ghost:bool,
		sample_time_ms:int=-1)->Rect2:
	var position:=_position_from_actor(actor)
	var visual_center:=world_to_pixel_center(position) if ghost else actor_visual_center(
		int(actor.get("entity_id",-1)),sample_time_ms)
	if visual_center==Vector2(-1,-1):return Rect2()
	var figure_height:=clampf(cell*1.56,28.0,52.0);var figure_width:=cell*0.72
	var foot_y:=visual_center.y+cell*0.5
	var bounds:=Rect2(Vector2(visual_center.x-figure_width*0.5,
		foot_y-figure_height-ACTOR_WORLD_FIGURE_BOTTOM_INSET_PX),
		Vector2(figure_width,figure_height))
	return bounds

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
	var spec:=cursor_preview_draw_spec()
	if not bool(spec.visible):return
	var color:=Color(str(spec.color_hex))
	var center:Vector2=spec.pixel_center;var radius:=float(spec.radius)
	draw_circle(center,radius,Color(color,0.10))
	draw_arc(center,radius,0,TAU,20,color,3.0)
	if preview_origin.x >= 0 and is_world_cell_visible(preview_origin):
		_draw_arrow(world_to_pixel_center(preview_origin), world_to_pixel_center(preview_destination), color, 3.5, false)

func cursor_preview_draw_spec()->Dictionary:
	var suppressed_by_route:=_route_path.size()>=2
	var visible:=not suppressed_by_route and cursor_cell.x>=0 and is_world_cell_visible(cursor_cell)
	return {"visible":visible,"suppressed_by_route":suppressed_by_route,
		"position":[cursor_cell.x,cursor_cell.y],
		"pixel_center":world_to_pixel_center(cursor_cell) if visible else Vector2(-1,-1),
		"radius":cell_size_px()*0.36,"color_hex":"#65f29a" if preview_valid else "#ff5f68",
		"draw_circle":visible}.duplicate(true)

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
		# Keep the target-cell marker but never draw an attacker-target connector:
		# across adjacent glyphs it reads as a route and obscures the terrain.
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
		"primitive":"RING" if action_type=="HOLD" else ("TARGET_MARKER" if action_type=="MELEE" else "ARROW"),
		"draw_connector":action_type=="MOVE",
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
