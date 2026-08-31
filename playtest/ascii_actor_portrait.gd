class_name AsciiActorPortrait
extends Control

const StyleScript = preload("res://playtest/ascii_visual_style.gd")

var _actor: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)


func set_actor(value: Dictionary) -> void:
	_actor = value.duplicate(true)
	queue_redraw()


func actor_dto() -> Dictionary:
	return _actor.duplicate(true)


func actor_draw_spec() -> Dictionary:
	return StyleScript.actor_spec(_actor)


func _draw() -> void:
	var spec := actor_draw_spec()
	var panel := Rect2(Vector2.ZERO, size).grow(-1.0)
	draw_rect(panel, Color("#0c151e"), true)
	var border := _color(str(spec.get("color_hex", "#c2ccd5")), 0.62)
	draw_rect(panel, border, false, 1.5)
	var inset := maxf(3.0, minf(size.x,size.y)*0.06)
	draw_figure(self, get_theme_default_font(), panel.grow(-inset), spec, true)


static func draw_figure(canvas: CanvasItem, font: Font, bounds: Rect2,
		spec: Dictionary, draw_shadow: bool = true, world_context: bool = false) -> void:
	if bounds.size.x <= 1.0 or bounds.size.y <= 1.0:
		return
	var opacity := clampf(float(spec.get("opacity", 1.0)), 0.0, 1.0)
	var main_color := _color(str(spec.get("color_hex", "#c2ccd5")), opacity)
	var outline := _color(str(spec.get("outline_hex", "#0a1016")), opacity)
	var shadow := _color(str(spec.get("shadow_hex", "#03070b")), opacity*0.72)
	var life_state := str(spec.get("life_state", "ACTIVE"))
	if draw_shadow:
		_draw_ground_shadow(canvas,bounds,shadow,life_state,world_context)
	var glyph_layout := glyph_layout_spec(font,bounds,spec,world_context)
	_draw_glyph_underlay(canvas,glyph_layout,spec,opacity)
	_draw_weighted_glyph(canvas,font,str(spec.get("glyph","?")),glyph_layout.center,
		int(glyph_layout.font_size),outline,main_color,world_context,
		int(spec.get("glyph_outline_passes",4)),int(spec.get("glyph_weight_passes",2)))
	_draw_equipment(canvas,font,equipment_draw_spec(bounds,spec,glyph_layout,world_context),opacity)
	for raw_segment in spec.get("guard_segments", []):
		if raw_segment is Array and raw_segment.size()==2:
			canvas.draw_line(_point(bounds,raw_segment[0]),_point(bounds,raw_segment[1]),
				_color("#74d5ff",opacity),maxf(1.5,bounds.size.y*0.045),true)
	if bool(spec.get("bleeding",false)):
		_draw_centered_glyph(canvas,font,"!",_point(bounds,Vector2(0.44,-0.02)),
			maxi(11,int(bounds.size.y*0.24)),_color("#ff5364",opacity))


static func shadow_draw_spec(bounds:Rect2,spec:Dictionary,
		world_context:bool=false)->Dictionary:
	if bounds.size.x<=1.0 or bounds.size.y<=1.0:
		return {"visible":false}.duplicate(true)
	var opacity:=clampf(float(spec.get("opacity",1.0)),0.0,1.0)
	var life_state:=str(spec.get("life_state","ACTIVE"))
	var center:=Vector2(bounds.get_center().x,
		bounds.end.y-maxf(1.0,bounds.size.y*0.025))
	var width_ratio:=0.82 if life_state=="DOWNED" else 0.58
	var radius:=Vector2(maxf(2.0,bounds.size.x*width_ratio*0.5),
		maxf(1.2,bounds.size.y*0.075))
	return {"visible":opacity>0.0,"center":center,"radius":radius,
		"color_hex":str(spec.get("shadow_hex","#03070b")),"opacity":opacity*0.72,
		"directional":world_context and life_state!="DEAD",
		"directional_offset":Vector2(bounds.size.x*0.18,bounds.size.y*0.1196),
		"draw_image":false,"draw_border":false}.duplicate(true)


static func glyph_layout_spec(font: Font, bounds: Rect2, spec: Dictionary,
		world_context: bool = false) -> Dictionary:
	var glyph := str(spec.get("glyph", "?"))
	var center := _point(bounds,spec.get("glyph_center",
		spec.get("body_center",Vector2.ZERO)))
	if world_context:
		var logical_cell_size:=bounds.size.x/0.72
		center=Vector2(bounds.get_center().x,bounds.end.y-1.0-logical_cell_size*0.5)
	var glyph_offset:Vector2=spec.get("glyph_offset",Vector2.ZERO)
	center+=Vector2(glyph_offset.x*bounds.size.x,glyph_offset.y*bounds.size.y)
	var glyph_scale:=clampf(float(spec.get("glyph_scale",1.0)),0.82,1.16)
	var max_width := bounds.size.x*0.96*glyph_scale
	var max_height := minf(bounds.size.y*(0.50 if world_context else 0.62),
		bounds.size.x*(1.14 if world_context else 1.35))*glyph_scale
	var font_size := maxi(9,int(floor(max_height)))
	var extent := font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	while font_size>9 and (extent.x>max_width or extent.y>max_height):
		font_size-=1
		extent=font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	return {"glyph":glyph,"center":center,"font_size":font_size,
		"glyph_rect":Rect2(center-extent*0.5,extent),"glyph_is_body":true,
		"detached_head":false,"outline_passes":8,"draw_equipment":false,
		"equipment_primitive_count":0}.duplicate(true)


static func limb_draw_segments(bounds:Rect2,spec:Dictionary,glyph_layout:Dictionary)->Array:
	if not bool(spec.get("draw_limbs",true)):return []
	var result:Array=[]
	var glyph_rect:Rect2=glyph_layout.get("glyph_rect",Rect2())
	var glyph_center:Vector2=glyph_layout.get("center",bounds.get_center())
	var raw_segments:Variant=spec.get("limb_segments",[])
	if not raw_segments is Array:return []
	for index in range(raw_segments.size()):
		var raw:Variant=raw_segments[index]
		if not raw is Array or raw.size()!=2:continue
		var anchor:=_point(bounds,raw[0])
		match index:
			0:anchor=Vector2(glyph_rect.position.x,glyph_center.y)
			1:anchor=Vector2(glyph_rect.end.x,glyph_center.y)
			2:anchor=Vector2(glyph_center.x-glyph_rect.size.x*0.18,glyph_rect.end.y)
			3:anchor=Vector2(glyph_center.x+glyph_rect.size.x*0.18,glyph_rect.end.y)
		result.append([anchor,_point(bounds,raw[1])])
	return result


static func equipment_draw_spec(bounds:Rect2,spec:Dictionary,glyph_layout:Dictionary,
		world_context:bool=false)->Dictionary:
	var equipment:Variant=spec.get("equipment",{})
	if not bool(spec.get("draw_equipment",false)) or not equipment is Dictionary:
		return {"visible":false,"weapon_visible":false,"armor_visible":false,
			"primitive_count":0,"tile_local":true}.duplicate(true)
	var glyph_rect:Rect2=glyph_layout.get("glyph_rect",Rect2())
	var center:Vector2=glyph_layout.get("center",bounds.get_center())
	var base_size:=int(glyph_layout.get("font_size",12))
	var armor_visible:=bool(equipment.get("armor_visible",false))
	var weapon_visible:=bool(equipment.get("weapon_visible",false))
	var armor_font_size:=maxi(8,int(roundf(float(base_size)*(0.74 if world_context else 0.82))))
	var weapon_font_size:=maxi(8,int(roundf(float(base_size)*(0.68 if world_context else 0.76))))
	var armor_spread:=maxf(glyph_rect.size.x*0.64,5.0)
	var facing:=StyleScript.normalized_facing(spec.get("facing",[0,1]))
	var side_sign:=-1.0 if facing.x<0 else 1.0
	if facing.x==0:side_sign=1.0
	var weapon_direction:=Vector2(facing)
	if weapon_direction==Vector2.ZERO:weapon_direction=Vector2.DOWN
	weapon_direction=weapon_direction.normalized()
	var weapon_offset:=Vector2(side_sign*maxf(glyph_rect.size.x*0.68,5.0),
		-glyph_rect.size.y*0.06)+weapon_direction*glyph_rect.size.y*0.08
	var swing:Variant=spec.get("weapon_swing",{})
	if swing is Dictionary and bool(swing.get("active",false)):
		var direction:=Vector2(swing.get("direction",weapon_direction)).normalized()
		var progress:=clampf(float(swing.get("phase_progress",0.0)),0.0,1.0)
		var sweep:float
		match str(swing.get("phase","SETTLE")):
			"WIND_UP":sweep=-0.32*progress
			"SWING":sweep=-0.32+0.94*(1.0-pow(1.0-progress,2.0))
			_:sweep=0.62*(1.0-progress)
		weapon_offset=(direction.rotated(sweep))*maxf(glyph_rect.size.y*0.53,5.0)
	var tile_rect:=bounds
	if world_context:
		var logical_cell_size:=bounds.size.x/0.72
		# PartyGridView grounds figure bounds one pixel above the cell bottom.
		# Recover that exact logical cell for presentation clamping; the raised core
		# glyph offset is intentionally irrelevant to equipment containment.
		var logical_center:=Vector2(bounds.get_center().x,
			bounds.end.y+1.0-logical_cell_size*0.5)
		tile_rect=Rect2(logical_center-Vector2.ONE*logical_cell_size*0.5,
			Vector2.ONE*logical_cell_size)
	var equipment_inset:=maxf(1.0,float(weapon_font_size)*0.20)
	var safe_rect:=tile_rect.grow(-equipment_inset)
	var weapon_center:=_clamp_point(center+weapon_offset,safe_rect)
	var armor_left_center:=_clamp_point(center+Vector2(-armor_spread,0),safe_rect)
	var armor_right_center:=_clamp_point(center+Vector2(armor_spread,0),safe_rect)
	return {
		"visible":weapon_visible or armor_visible,
		"armor_visible":armor_visible,
		"armor_left_glyph":str(equipment.get("armor_left_glyph","")),
		"armor_right_glyph":str(equipment.get("armor_right_glyph","")),
		"armor_color_hex":str(equipment.get("armor_color_hex","#00000000")),
		"armor_left_center":armor_left_center,
		"armor_right_center":armor_right_center,
		"armor_font_size":armor_font_size,
		"weapon_visible":weapon_visible,
		"weapon_id":str(equipment.get("weapon_id","UNARMED")),
		"weapon_family":str(equipment.get("weapon_family","UNARMED")),
		"weapon_glyph":str(equipment.get("weapon_glyph","")),
		"weapon_color_hex":str(equipment.get("weapon_color_hex","#00000000")),
		"weapon_center":weapon_center,"weapon_font_size":weapon_font_size,
		"weapon_swing_active":swing is Dictionary and bool(swing.get("active",false)),
		"primitive_count":(1 if weapon_visible else 0)+(2 if armor_visible else 0),
		"tile_local":true,"changes_core_glyph":false,"draw_image":false,
	}.duplicate(true)


static func _clamp_point(value:Vector2,rect:Rect2)->Vector2:
	return Vector2(clampf(value.x,rect.position.x,rect.end.x),
		clampf(value.y,rect.position.y,rect.end.y))


static func _draw_equipment(canvas:CanvasItem,font:Font,draw_spec:Dictionary,
		opacity:float)->void:
	if not bool(draw_spec.get("visible",false)):return
	if bool(draw_spec.get("armor_visible",false)):
		var armor_color:=_color(str(draw_spec.armor_color_hex),opacity*0.92)
		_draw_centered_glyph(canvas,font,str(draw_spec.armor_left_glyph),
			Vector2(draw_spec.armor_left_center),int(draw_spec.armor_font_size),armor_color)
		_draw_centered_glyph(canvas,font,str(draw_spec.armor_right_glyph),
			Vector2(draw_spec.armor_right_center),int(draw_spec.armor_font_size),armor_color)
	if bool(draw_spec.get("weapon_visible",false)):
		var weapon_color:=_color(str(draw_spec.weapon_color_hex),opacity)
		_draw_centered_glyph(canvas,font,str(draw_spec.weapon_glyph),
			Vector2(draw_spec.weapon_center),int(draw_spec.weapon_font_size),weapon_color)


static func _draw_weighted_glyph(canvas: CanvasItem, font: Font, glyph: String,
		center: Vector2, font_size: int, outline: Color, color: Color,
		world_context: bool, outline_passes:int=4, weight_passes:int=2) -> void:
	var radius := 1.0 if world_context else 1.45
	var outline_directions:=[Vector2(-1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,1),
		Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]
	for index in range(clampi(outline_passes,0,outline_directions.size())):
		var direction:Vector2=outline_directions[index]
		_draw_centered_glyph(canvas,font,glyph,center+direction*radius,font_size,outline)
	if weight_passes>=2:
		_draw_centered_glyph(canvas,font,glyph,center+Vector2(-0.28,0),font_size,color)
	_draw_centered_glyph(canvas,font,glyph,center,font_size,color)


static func _draw_glyph_underlay(canvas:CanvasItem,glyph_layout:Dictionary,
		spec:Dictionary,opacity:float)->void:
	var ratio:Vector2=spec.get("underlay_ratio",Vector2.ZERO)
	var underlay_opacity:=clampf(float(spec.get("underlay_opacity",0.0))*opacity,0.0,1.0)
	if ratio.x<=0.0 or ratio.y<=0.0 or underlay_opacity<=0.0:return
	var glyph_rect:Rect2=glyph_layout.get("glyph_rect",Rect2())
	if glyph_rect.size.x<=0.0:return
	var size:=Vector2(maxf(glyph_rect.size.x*ratio.x,glyph_rect.size.x*0.68),
		maxf(glyph_rect.size.y*ratio.y,glyph_rect.size.y*0.40))
	var rect:=Rect2(Vector2(glyph_layout.center)-size*0.5,size)
	canvas.draw_rect(rect,_color(str(spec.get("underlay_hex","#101820")),underlay_opacity),true)


static func _draw_ground_shadow(canvas: CanvasItem, bounds: Rect2,
		shadow: Color, life_state: String,
		world_context: bool) -> void:
	var depth:=shadow_draw_spec(bounds,{"opacity":shadow.a/0.72 if shadow.a>0.0 else 0.0,
		"shadow_hex":"#03070b","life_state":life_state},world_context)
	var center:Vector2=depth.center;var radius:Vector2=depth.radius
	var radius_x:=radius.x;var radius_y:=radius.y
	canvas.draw_colored_polygon(_ellipse_points(center,radius_x,radius_y),shadow)
	if not world_context or life_state=="DEAD":return
	var reach:Vector2=depth.directional_offset
	var long_shadow:=PackedVector2Array([
		center+Vector2(-radius_x*0.72,0.0), center+Vector2(radius_x*0.72,0.0),
		center+reach+Vector2(radius_x*0.38,radius_y*0.35),
		center+reach+Vector2(-radius_x*0.38,radius_y*0.35),
	])
	canvas.draw_colored_polygon(long_shadow,_color("#020507",shadow.a*0.56))


static func _ellipse_points(center:Vector2,radius_x:float,radius_y:float)->PackedVector2Array:
	var result:=PackedVector2Array()
	for index in range(16):
		var angle:=TAU*float(index)/16.0
		result.append(center+Vector2(cos(angle)*radius_x,sin(angle)*radius_y))
	return result


static func _point(bounds: Rect2, normalized: Variant) -> Vector2:
	var value := normalized as Vector2 if normalized is Vector2 else Vector2.ZERO
	return bounds.get_center()+Vector2(value.x*bounds.size.x,value.y*bounds.size.y)


static func _draw_centered_glyph(canvas: CanvasItem, font: Font, glyph: String,
		center: Vector2, font_size: int, color: Color) -> void:
	var extent := font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	canvas.draw_string(font,center+Vector2(-extent.x*0.5,extent.y*0.38),glyph,
		HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)


static func _color(value: String, opacity: float) -> Color:
	var color := Color(value)
	color.a *= clampf(opacity,0.0,1.0)
	return color
