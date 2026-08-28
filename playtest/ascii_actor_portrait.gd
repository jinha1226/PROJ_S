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
		spec: Dictionary, draw_shadow: bool = true) -> void:
	if bounds.size.x <= 1.0 or bounds.size.y <= 1.0:
		return
	var opacity := clampf(float(spec.get("opacity", 1.0)), 0.0, 1.0)
	var main_color := _color(str(spec.get("color_hex", "#c2ccd5")), opacity)
	var highlight := _color(str(spec.get("highlight_hex", "#eef4f8")), opacity)
	var outline := _color(str(spec.get("outline_hex", "#0a1016")), opacity)
	var shadow := _color(str(spec.get("shadow_hex", "#03070b")), opacity*0.72)
	var life_state := str(spec.get("life_state", "ACTIVE"))
	if draw_shadow:
		var shadow_y := bounds.end.y - maxf(1.0,bounds.size.y*0.035)
		var shadow_half := bounds.size.x*(0.38 if life_state=="DOWNED" else 0.27)
		canvas.draw_line(Vector2(bounds.get_center().x-shadow_half,shadow_y),
			Vector2(bounds.get_center().x+shadow_half,shadow_y),shadow,
			maxf(2.0,bounds.size.y*0.075),true)
	var limb_width := maxf(1.4,bounds.size.y*0.045)
	if bool(spec.get("draw_limbs", true)):
		for raw_segment in spec.get("limb_segments", []):
			if raw_segment is Array and raw_segment.size()==2:
				canvas.draw_line(_point(bounds,raw_segment[0]),_point(bounds,raw_segment[1]),
					outline,limb_width+1.2,true)
				canvas.draw_line(_point(bounds,raw_segment[0]),_point(bounds,raw_segment[1]),
					main_color,limb_width,true)
	var body_center := _point(bounds,spec.get("body_center",Vector2.ZERO))
	var glyph := str(spec.get("glyph","?"))
	var font_size := maxi(12,int(floor(bounds.size.y*(0.47 if life_state=="DOWNED" else 0.53))))
	_draw_centered_glyph(canvas,font,glyph,body_center+Vector2(1.5,2.0),font_size,shadow)
	_draw_centered_glyph(canvas,font,glyph,body_center,font_size,main_color)
	if bool(spec.get("draw_head", true)):
		var head := _point(bounds,spec.get("head_center",Vector2(0,-0.31)))
		var head_radius := maxf(2.0,bounds.size.y*0.060)
		canvas.draw_circle(head,head_radius+1.0,outline)
		canvas.draw_circle(head,head_radius,main_color)
		if life_state=="ACTIVE":
			var facing_point := _point(bounds,spec.get("facing_point",Vector2(0,-0.24)))
			canvas.draw_circle(facing_point,maxf(1.0,head_radius*0.34),highlight)
	for raw_segment in spec.get("guard_segments", []):
		if raw_segment is Array and raw_segment.size()==2:
			canvas.draw_line(_point(bounds,raw_segment[0]),_point(bounds,raw_segment[1]),
				_color("#74d5ff",opacity),maxf(2.0,limb_width+0.8),true)
	if bool(spec.get("bleeding",false)):
		_draw_centered_glyph(canvas,font,"!",_point(bounds,Vector2(0.36,-0.31)),
			maxi(11,int(bounds.size.y*0.24)),_color("#ff5364",opacity))


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
