class_name DarkPixelUIFrame
extends MarginContainer

## Responsive square-edged frame used by product panels. It keeps the old
## frame state API (tone/danger/frame_spec) while replacing font glyph borders
## with deterministic pixel primitives.

const DarkSkin=preload("res://playtest/dark_pixel_ui_skin.gd")

var frame_title:=""
var frame_color:=DarkSkin.IRON_EDGE
var title_color:=DarkSkin.BONE
var backdrop_color:=DarkSkin.FOLIO
var compact_inset:=false
var danger_edge:=false


func _init()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	set_meta("visual_family",DarkSkin.VISUAL_FAMILY)
	set_meta("pixel_material","BLACK_IRON_FRAME")
	_refresh_insets()


func _ready()->void:
	set_meta("visual_family",DarkSkin.VISUAL_FAMILY)
	set_meta("pixel_material","BLACK_IRON_FRAME")
	resized.connect(queue_redraw)
	queue_redraw()


func configure(title:String="",tone:Color=DarkSkin.IRON_EDGE,
		backdrop:Color=DarkSkin.FOLIO,compact:bool=false,_rounded:bool=false)->void:
	frame_title=title
	frame_color=tone
	title_color=tone
	backdrop_color=backdrop
	compact_inset=compact
	_refresh_insets()
	queue_redraw()


func _refresh_insets()->void:
	var side:=4 if compact_inset else 8
	var top:=14 if compact_inset else 25
	var bottom:=4 if compact_inset else 8
	add_theme_constant_override("margin_left",side)
	add_theme_constant_override("margin_right",side)
	add_theme_constant_override("margin_top",top)
	add_theme_constant_override("margin_bottom",bottom)
	update_minimum_size()


func _draw()->void:
	if size.x<4.0 or size.y<4.0:return
	var bounds:=Rect2(Vector2.ZERO,size).grow(-1.0)
	var edge:=DarkSkin.BLOOD if danger_edge else frame_color
	var surface:=DarkSkin.panel_surface(DarkSkin.FOLIO,edge.darkened(0.25),0,1)
	draw_style_box(surface,bounds)
	if not frame_title.is_empty():
		var font_size:=10 if compact_inset else 14
		var title_size:=DarkSkin.PixelFont.get_string_size(frame_title,
			HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		var title_position:=Vector2(floor((size.x-title_size.x)*0.5),
			3.0+DarkSkin.PixelFont.get_ascent(font_size))
		draw_rect(Rect2(title_position-Vector2(4,DarkSkin.PixelFont.get_ascent(font_size)),
			title_size+Vector2(8,DarkSkin.PixelFont.get_height(font_size))),backdrop_color,true)
		draw_string(DarkSkin.PixelFont,title_position,frame_title,
			HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,title_color)


func _draw_corner_brackets(bounds:Rect2,tone:Color)->void:
	var length:=8.0 if compact_inset else 12.0
	var tl:=bounds.position+Vector2(1,1)
	var tr:=Vector2(bounds.end.x-1,bounds.position.y+1)
	var bl:=Vector2(bounds.position.x+1,bounds.end.y-1)
	var br:=bounds.end-Vector2(1,1)
	for segment in [[tl,tl+Vector2(length,0)],[tl,tl+Vector2(0,length)],
		[tr,tr-Vector2(length,0)],[tr,tr+Vector2(0,length)],
		[bl,bl+Vector2(length,0)],[bl,bl-Vector2(0,length)],
		[br,br-Vector2(length,0)],[br,br-Vector2(0,length)]]:
		draw_line(segment[0],segment[1],tone,2.0)


func frame_spec()->Dictionary:
	var bounds:=Rect2(Vector2.ZERO,size).grow(-1.0)
	return {"primitive":"PIXEL_BEVEL_FRAME","visual_family":DarkSkin.VISUAL_FAMILY,
		"frame_material":"BLACK_IRON","title":frame_title,
		"font_path":"res://assets/fonts/Galmuri14.ttf",
		"font_size":10 if compact_inset else 14,
		"frame_color":frame_color.to_html(),"title_color":title_color.to_html(),
		"backdrop_color":backdrop_color.to_html(),"danger_edge":danger_edge,
		"right_edge_inside":bounds.end.x<=size.x,
		"bottom_edge_inside":bounds.end.y<=size.y,
		"title_overdraws_border":false,
		"content_inset":[get_theme_constant("margin_left"),get_theme_constant("margin_top"),
			get_theme_constant("margin_right"),get_theme_constant("margin_bottom")]}.duplicate(true)
