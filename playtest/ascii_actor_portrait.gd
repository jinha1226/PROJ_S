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
	var equipment: Dictionary = spec.get("equipment", {})
	if life_state=="DEAD":equipment={}
	if draw_shadow:
		_draw_ground_shadow(canvas,bounds,equipment,shadow,life_state,world_context)
	_draw_lantern_glow(canvas,bounds,equipment,opacity,world_context)
	_draw_equipment_segments(canvas,bounds,equipment.get("back_segments",[]),
		outline,opacity)
	var glyph_layout := glyph_layout_spec(font,bounds,spec,world_context)
	var limb_width := maxf(1.4,bounds.size.y*0.045)
	for segment in limb_draw_segments(bounds,spec,glyph_layout):
		canvas.draw_line(segment[0],segment[1],outline,limb_width+1.2,true)
		canvas.draw_line(segment[0],segment[1],main_color,limb_width,true)
	_draw_equipment_segments(canvas,bounds,equipment.get("front_segments",[]),
		outline,opacity)
	_draw_equipment_polyline(canvas,bounds,equipment.get("front_polyline",[]),
		outline,_color("#dce4e5",opacity),maxf(1.4,bounds.size.y*0.035))
	_draw_equipment_shield(canvas,bounds,equipment.get("shield_points",[]),
		outline,opacity)
	_draw_lantern_body(canvas,bounds,equipment,outline,opacity)
	_draw_weighted_glyph(canvas,font,str(spec.get("glyph","?")),glyph_layout.center,
		int(glyph_layout.font_size),outline,main_color,world_context)
	for raw_segment in spec.get("guard_segments", []):
		if raw_segment is Array and raw_segment.size()==2:
			canvas.draw_line(_point(bounds,raw_segment[0]),_point(bounds,raw_segment[1]),
				_color("#74d5ff",opacity),maxf(2.0,limb_width+0.8),true)
	if bool(spec.get("bleeding",false)):
		_draw_centered_glyph(canvas,font,"!",_point(bounds,Vector2(0.44,-0.02)),
			maxi(11,int(bounds.size.y*0.24)),_color("#ff5364",opacity))


static func glyph_layout_spec(font: Font, bounds: Rect2, spec: Dictionary,
		world_context: bool = false) -> Dictionary:
	var glyph := str(spec.get("glyph", "?"))
	var center := _point(bounds,spec.get("glyph_center",
		spec.get("body_center",Vector2.ZERO)))
	if world_context:
		var logical_cell_size:=bounds.size.x/0.72
		center=Vector2(bounds.get_center().x,bounds.end.y-1.0-logical_cell_size*0.5)
	var max_width := bounds.size.x*0.96
	var max_height := minf(bounds.size.y*(0.50 if world_context else 0.62),
		bounds.size.x*(1.14 if world_context else 1.35))
	var font_size := maxi(9,int(floor(max_height)))
	var extent := font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	while font_size>9 and (extent.x>max_width or extent.y>max_height):
		font_size-=1
		extent=font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	return {"glyph":glyph,"center":center,"font_size":font_size,
		"glyph_rect":Rect2(center-extent*0.5,extent),"glyph_is_body":true,
		"detached_head":false,"outline_passes":8}.duplicate(true)


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


static func _draw_weighted_glyph(canvas: CanvasItem, font: Font, glyph: String,
		center: Vector2, font_size: int, outline: Color, color: Color,
		world_context: bool) -> void:
	var radius := 1.0 if world_context else 1.45
	for direction in [Vector2(-1,-1),Vector2(0,-1),Vector2(1,-1),Vector2(-1,0),
			Vector2(1,0),Vector2(-1,1),Vector2(0,1),Vector2(1,1)]:
		_draw_centered_glyph(canvas,font,glyph,center+direction*radius,font_size,outline)
	_draw_centered_glyph(canvas,font,glyph,center+Vector2(-0.32,0),font_size,color)
	_draw_centered_glyph(canvas,font,glyph,center+Vector2(0.32,0),font_size,color)
	_draw_centered_glyph(canvas,font,glyph,center,font_size,color)


static func _draw_ground_shadow(canvas: CanvasItem, bounds: Rect2,
		equipment: Dictionary, shadow: Color, life_state: String,
		world_context: bool) -> void:
	var shadow_spec: Dictionary = equipment.get("shadow", {})
	var center := Vector2(bounds.get_center().x,
		bounds.end.y-maxf(1.0,bounds.size.y*0.025))
	var width_ratio := float(shadow_spec.get("width_ratio",0.58))
	if life_state=="DOWNED":width_ratio=0.82
	var radius_x:=maxf(2.0,bounds.size.x*width_ratio*0.5)
	var radius_y:=maxf(1.2,bounds.size.y*float(shadow_spec.get("height_ratio",0.075)))
	canvas.draw_colored_polygon(_ellipse_points(center,radius_x,radius_y),shadow)
	if not world_context or life_state=="DEAD":return
	var length_ratio:=float(shadow_spec.get("length_ratio",0.26))
	var reach:=Vector2(bounds.size.x*0.18,bounds.size.y*length_ratio*0.46)
	var long_shadow:=PackedVector2Array([
		center+Vector2(-radius_x*0.72,0.0), center+Vector2(radius_x*0.72,0.0),
		center+reach+Vector2(radius_x*0.38,radius_y*0.35),
		center+reach+Vector2(-radius_x*0.38,radius_y*0.35),
	])
	canvas.draw_colored_polygon(long_shadow,_color("#020507",shadow.a*0.56))


static func _draw_lantern_glow(canvas: CanvasItem,bounds:Rect2,equipment:Dictionary,
		opacity:float,world_context:bool)->void:
	var lantern:Dictionary=equipment.get("lantern",{})
	if not bool(lantern.get("visible",false)):return
	var center:=_point(bounds,lantern.get("center",Vector2.ZERO))
	var radius:=maxf(2.0,bounds.size.y*float(lantern.get("radius_ratio",0.075)))
	var glow_scale:=3.1 if world_context else 1.8
	var glow:=_color(str(lantern.get("color_hex","#ffc45c")),opacity)
	canvas.draw_circle(center,radius*glow_scale,_with_alpha(glow,0.055 if world_context else 0.08))
	canvas.draw_circle(center,radius*glow_scale*0.58,_with_alpha(glow,0.11 if world_context else 0.13))


static func _draw_lantern_body(canvas:CanvasItem,bounds:Rect2,equipment:Dictionary,
		outline:Color,opacity:float)->void:
	var lantern:Dictionary=equipment.get("lantern",{})
	if not bool(lantern.get("visible",false)):return
	var center:=_point(bounds,lantern.get("center",Vector2.ZERO))
	var radius:=maxf(2.0,bounds.size.y*float(lantern.get("radius_ratio",0.075)))
	var color:=_color(str(lantern.get("color_hex","#ffc45c")),opacity)
	canvas.draw_circle(center,radius+1.0,outline)
	canvas.draw_circle(center,radius,color)
	canvas.draw_arc(center+Vector2(0,-radius*0.8),radius*0.72,PI,TAU,8,color,
		maxf(1.0,bounds.size.y*0.020),true)


static func _draw_equipment_segments(canvas:CanvasItem,bounds:Rect2,segments:Variant,
		outline:Color,opacity:float)->void:
	if not segments is Array:return
	for raw in segments:
		if not raw is Dictionary:continue
		var row:Dictionary=raw
		var from:=_point(bounds,row.get("from",Vector2.ZERO))
		var to:=_point(bounds,row.get("to",Vector2.ZERO))
		var width:=maxf(1.2,bounds.size.y*float(row.get("width_ratio",0.032)))
		canvas.draw_line(from,to,outline,width+1.4,true)
		canvas.draw_line(from,to,_color(str(row.get("color_hex","#dce4e5")),opacity),width,true)


static func _draw_equipment_polyline(canvas:CanvasItem,bounds:Rect2,points:Variant,
		outline:Color,color:Color,width:float)->void:
	if not points is Array or points.size()<2:return
	var projected:=PackedVector2Array()
	for point in points:projected.append(_point(bounds,point))
	canvas.draw_polyline(projected,outline,width+1.4,true)
	canvas.draw_polyline(projected,color,width,true)


static func _draw_equipment_shield(canvas:CanvasItem,bounds:Rect2,points:Variant,
		outline:Color,opacity:float)->void:
	if not points is Array or points.size()<3:return
	var projected:=PackedVector2Array()
	for point in points:projected.append(_point(bounds,point))
	canvas.draw_colored_polygon(projected,_color("#477793",opacity*0.72))
	var closed:=PackedVector2Array(projected)
	closed.append(projected[0])
	canvas.draw_polyline(closed,outline,maxf(1.2,bounds.size.y*0.030),true)
	canvas.draw_polyline(closed,_color("#8fd5ed",opacity),maxf(1.0,bounds.size.y*0.018),true)


static func _ellipse_points(center:Vector2,radius_x:float,radius_y:float)->PackedVector2Array:
	var result:=PackedVector2Array()
	for index in range(16):
		var angle:=TAU*float(index)/16.0
		result.append(center+Vector2(cos(angle)*radius_x,sin(angle)*radius_y))
	return result


static func _with_alpha(color:Color,alpha:float)->Color:
	var result:=color
	result.a*=clampf(alpha,0.0,1.0)
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
