class_name MeleeVfxOverlay
extends Node2D

# Every adjustable melee-presentation value lives here. These values affect no
# simulation clock, action result, entity position, glyph, or input mapping.
const PARAMS := {
	"contact_at_ms":28,
	"hit_stop_ms":55,
	"slash_duration_ms":70,
	# Attack-axis span is measured against the distance between cell centers.
	# A value above 1.0 puts one endpoint inside each participating cell.
	"slash_span_ratio":1.36,
	# Total perpendicular displacement, measured against the smaller cell edge.
	# This keeps every cardinal strike diagonal instead of drawing a grid-parallel bar.
	"slash_tilt_ratio":0.32,
	"slash_width_px":2.2,
	"slash_color_hex":"#ffe4a3",
	"flash_duration_ms":90,
	"flash_intensity":0.38,
	"flash_color_hex":"#ff334d",
	"particle_count_min":3,
	"particle_count_max":6,
	"particle_duration_ms":190,
	"particle_travel_ratio":0.58,
	"particle_color_hex":"#ffb36a",
	"particle_font_ratio":0.42,
	"shake_strength_px":1.5,
	"shake_duration_ms":80,
}

const PARTICLE_GLYPHS := [".", ":", "*"]
const MAX_ACTIVE_EFFECTS := 24

var _grid:Control
var _effects:Array[Dictionary]=[]
var _sequence:=0


func _ready()->void:
	set_process(false)


func bind_grid(grid:Control)->void:
	_grid=grid
	queue_redraw()


func parameter_spec()->Dictionary:
	var result:=PARAMS.duplicate(true)
	result["effect_duration_ms"]=_effect_duration_ms()
	result["particle_glyphs"]=PARTICLE_GLYPHS.duplicate()
	return result


# Public product API. The passed pair is the canonical event-time pair; the
# overlay never searches occupants or mutates either position.
func play(attacker_grid_pos:Vector2i,target_grid_pos:Vector2i)->bool:
	if _grid==null or attacker_grid_pos==target_grid_pos:return false
	var delta:=target_grid_pos-attacker_grid_pos
	if maxi(absi(delta.x),absi(delta.y))!=1:return false
	if _screen_center(attacker_grid_pos)==Vector2(-1,-1) \
			or _screen_center(target_grid_pos)==Vector2(-1,-1):return false
	_sequence+=1
	var particle_count:=int(PARAMS.particle_count_min)+(_sequence-1) \
		% (int(PARAMS.particle_count_max)-int(PARAMS.particle_count_min)+1)
	_effects.append({
		"sequence":_sequence,
		"attacker_grid_pos":attacker_grid_pos,
		"target_grid_pos":target_grid_pos,
		"started_at_ms":Time.get_ticks_msec(),
		"particles":_particle_seeds(_sequence,particle_count),
	})
	if _effects.size()>MAX_ACTIVE_EFFECTS:
		_effects=_effects.slice(_effects.size()-MAX_ACTIVE_EFFECTS)
	set_process(true)
	_request_redraw()
	return true


func clear()->void:
	_effects.clear()
	set_process(false)
	_request_redraw()


func active_effect_count()->int:
	return _effects.size()


func active_effects()->Array[Dictionary]:
	return _effects.duplicate(true)


func effect_draw_specs(sample_time_ms:int=-1)->Array[Dictionary]:
	var now:=Time.get_ticks_msec() if sample_time_ms<0 else sample_time_ms
	var result:Array[Dictionary]=[]
	for effect in _effects:
		var spec:=_effect_draw_spec(effect,now)
		if bool(spec.get("active",false)):result.append(spec)
	return result.duplicate(true)


func background_flash_specs(sample_time_ms:int=-1)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for spec in effect_draw_specs(sample_time_ms):
		if bool(spec.get("flash_visible",false)):
			result.append({"sequence":int(spec.sequence),
				"target_grid_pos":spec.target_grid_pos,
				"rect":spec.target_rect,"color_hex":str(PARAMS.flash_color_hex),
				"opacity":float(spec.flash_opacity)})
	return result.duplicate(true)


func shake_offset_px(sample_time_ms:int=-1)->Vector2:
	var now:=Time.get_ticks_msec() if sample_time_ms<0 else sample_time_ms
	var combined:=Vector2.ZERO
	for effect in _effects:
		var raw_elapsed:=maxi(0,now-int(effect.started_at_ms))
		var shake_elapsed:=raw_elapsed-int(PARAMS.contact_at_ms)
		if shake_elapsed<0 or shake_elapsed>=int(PARAMS.shake_duration_ms):continue
		var envelope:=1.0-float(shake_elapsed)/float(PARAMS.shake_duration_ms)
		var phase:=int(shake_elapsed/12)+int(effect.sequence)
		var direction:=Vector2(-1.0 if phase%2==0 else 1.0,
			-0.55 if phase%3==0 else 0.55).normalized()
		combined+=direction*float(PARAMS.shake_strength_px)*envelope
	return combined.limit_length(float(PARAMS.shake_strength_px))


func _process(_delta:float)->void:
	var now:=Time.get_ticks_msec()
	var retained:Array[Dictionary]=[]
	for effect in _effects:
		if now-int(effect.started_at_ms)<_effect_duration_ms():retained.append(effect)
	_effects=retained
	set_process(not _effects.is_empty())
	_request_redraw()


func _draw()->void:
	if _grid==null:return
	var now:=Time.get_ticks_msec()
	var presentation_offset:=_presentation_offset(now)
	var font:Font=_grid.get_theme_default_font()
	for spec in effect_draw_specs(now):
		if bool(spec.line_visible):
			var line_color:=Color(str(PARAMS.slash_color_hex))
			line_color.a=float(spec.line_opacity)
			draw_line(Vector2(spec.line_from)+presentation_offset,
				Vector2(spec.line_to)+presentation_offset,line_color,
				float(PARAMS.slash_width_px),true)
		for particle in spec.particles:
			var particle_color:=Color(str(PARAMS.particle_color_hex))
			particle_color.a=float(particle.opacity)
			_draw_centered_glyph(font,str(particle.glyph),
				Vector2(particle.center)+presentation_offset,
				int(particle.font_size),particle_color)


func _effect_draw_spec(effect:Dictionary,now:int)->Dictionary:
	var raw_elapsed:=maxi(0,now-int(effect.started_at_ms))
	if raw_elapsed>=_effect_duration_ms():return {"active":false}.duplicate(true)
	var contact_at:=int(PARAMS.contact_at_ms)
	var hold_end:=contact_at+int(PARAMS.hit_stop_ms)
	var visual_elapsed:=mini(raw_elapsed,contact_at) if raw_elapsed<hold_end \
		else raw_elapsed-int(PARAMS.hit_stop_ms)
	var hit_stop_active:=raw_elapsed>=contact_at and raw_elapsed<hold_end
	var impact_elapsed:=maxi(0,visual_elapsed-contact_at)
	var attacker:Vector2i=effect.attacker_grid_pos
	var target:Vector2i=effect.target_grid_pos
	var attacker_center:=_screen_center(attacker)
	var target_center:=_screen_center(target)
	var attacker_rect:=_screen_rect(attacker)
	var target_rect:=_screen_rect(target)
	var visible:=attacker_center!=Vector2(-1,-1) and target_center!=Vector2(-1,-1) \
		and attacker_rect.size.x>0.0 and target_rect.size.x>0.0
	if not visible:return {"active":true,"visible":false,
		"sequence":int(effect.sequence),"hit_stop_active":hit_stop_active}.duplicate(true)
	var direction:=(target_center-attacker_center).normalized()
	var perpendicular:=Vector2(-direction.y,direction.x)
	var cell:=minf(target_rect.size.x,target_rect.size.y)
	var midpoint:=(attacker_center+target_center)*0.5
	var half_span:=attacker_center.distance_to(target_center) \
		*float(PARAMS.slash_span_ratio)*0.5
	var half_tilt:=cell*float(PARAMS.slash_tilt_ratio)*0.5
	# `line_from` is always the attacker-cell endpoint and `line_to` the
	# target-cell endpoint. The opposing perpendicular offsets make the mark
	# diagonal without changing either cell or actor presentation.
	var line_from:=midpoint-direction*half_span+perpendicular*half_tilt
	var line_to:=midpoint+direction*half_span-perpendicular*half_tilt
	var slash_progress:=clampf(float(visual_elapsed)/float(PARAMS.slash_duration_ms),0.0,1.0)
	var line_opacity:=1.0 if hit_stop_active else 1.0-slash_progress
	var flash_progress:=clampf(float(impact_elapsed)/float(PARAMS.flash_duration_ms),0.0,1.0)
	var particles:Array[Dictionary]=[]
	var particle_progress:=clampf(float(impact_elapsed)/float(PARAMS.particle_duration_ms),0.0,1.0)
	if visual_elapsed>=contact_at and impact_elapsed<int(PARAMS.particle_duration_ms):
		for particle in effect.particles:
			var particle_direction:Vector2=particle.direction
			particles.append({"glyph":str(particle.glyph),
				"center":target_center+particle_direction*cell*float(
					PARAMS.particle_travel_ratio)*particle_progress,
				"font_size":maxi(9,int(cell*float(PARAMS.particle_font_ratio))),
				"opacity":1.0-particle_progress})
	return {"active":true,"visible":true,"sequence":int(effect.sequence),
		"attacker_grid_pos":attacker,"target_grid_pos":target,
		"raw_elapsed_ms":raw_elapsed,"visual_elapsed_ms":visual_elapsed,
		"hit_stop_active":hit_stop_active,
		"primitive":"LINE","slash_glyph":"","line_visible":line_opacity>0.0,
		"line_from":line_from,"line_to":line_to,"line_opacity":line_opacity,
		"attacker_rect":attacker_rect,
		"target_rect":target_rect,"flash_visible":visual_elapsed>=contact_at \
			and impact_elapsed<int(PARAMS.flash_duration_ms),
		"flash_opacity":float(PARAMS.flash_intensity)*(1.0-flash_progress),
		"particles":particles,"particle_count":particles.size(),
	}.duplicate(true)


func _particle_seeds(sequence:int,count:int)->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	for index in range(count):
		var lane:float=float((sequence*5+index*3)%16)/16.0
		var angle:=TAU*lane+float(index)*0.41
		rows.append({"glyph":PARTICLE_GLYPHS[(sequence+index)%PARTICLE_GLYPHS.size()],
			"direction":Vector2(cos(angle),sin(angle))})
	return rows.duplicate(true)


func _screen_center(position:Vector2i)->Vector2:
	return Vector2(-1,-1) if _grid==null else Vector2(_grid.call("world_to_pixel_center",position))


func _screen_rect(position:Vector2i)->Rect2:
	return Rect2() if _grid==null else Rect2(_grid.call("world_cell_rect",position))


func _presentation_offset(sample_time_ms:int)->Vector2:
	var camera_offset:=Vector2.ZERO
	if _grid!=null and _grid.has_method("camera_settle_draw_spec"):
		camera_offset=Vector2(_grid.call("camera_settle_draw_spec",sample_time_ms).get(
			"offset_px",Vector2.ZERO))
	return camera_offset+shake_offset_px(sample_time_ms)


func _effect_duration_ms()->int:
	return int(PARAMS.contact_at_ms)+int(PARAMS.hit_stop_ms)+maxi(
		int(PARAMS.particle_duration_ms),maxi(int(PARAMS.flash_duration_ms),
		int(PARAMS.slash_duration_ms)-int(PARAMS.contact_at_ms)))


func _request_redraw()->void:
	queue_redraw()
	if _grid!=null:_grid.queue_redraw()


func _draw_centered_glyph(font:Font,glyph:String,center:Vector2,
		font_size:int,color:Color)->void:
	var extent:=font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	draw_string(font,center+Vector2(-extent.x*0.5,extent.y*0.38),glyph,
		HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
