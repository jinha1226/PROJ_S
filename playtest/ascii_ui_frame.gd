class_name AsciiUIFrame
extends MarginContainer

## Presentation-only responsive frame. The visible boundary is rendered from
## font glyphs, never from StyleBox borders or polygon/line primitives.

const KoreanFont:FontFile=preload("res://assets/fonts/NanumSquareR.ttf")

const INK:=Color("#d8e7ed")
const MUTED:=Color("#55707d")
const BRASS:=Color("#c9a95d")
const CYAN:=Color("#5ed8e8")
const JADE:=Color("#68d3a0")
const DANGER:=Color("#e55d46")
const SURFACE:=Color("#09141bde")
const SURFACE_DEEP:=Color("#061017f2")
const TRACK:=Color("#182831")

var frame_title:=""
var frame_color:=MUTED
var title_color:=BRASS
var backdrop_color:=SURFACE
var glyph_font_size:=14
var rounded_corners:=false
var compact_inset:=false
var danger_edge:=false

func _init()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=false
	_refresh_insets()

func _ready()->void:
	resized.connect(queue_redraw)
	queue_redraw()

func configure(title:String="",tone:Color=MUTED,backdrop:Color=SURFACE,
		compact:bool=false,rounded:bool=false)->void:
	frame_title=title;frame_color=tone;title_color=tone
	backdrop_color=backdrop;compact_inset=compact;rounded_corners=rounded
	_refresh_insets();queue_redraw()

func _refresh_insets()->void:
	var horizontal:=5 if compact_inset else 10
	var vertical:=3 if compact_inset else 8
	add_theme_constant_override("margin_left",horizontal)
	add_theme_constant_override("margin_right",horizontal)
	add_theme_constant_override("margin_top",vertical)
	add_theme_constant_override("margin_bottom",vertical)

func _draw()->void:
	if size.x<8.0 or size.y<8.0:return
	draw_rect(Rect2(Vector2.ZERO,size),backdrop_color,true)
	var left_top:="╭" if rounded_corners else "┌"
	var right_top:="╮" if rounded_corners else "┐"
	var left_bottom:="╰" if rounded_corners else "└"
	var right_bottom:="╯" if rounded_corners else "┘"
	var advance:=maxf(4.0,KoreanFont.get_string_size("─",HORIZONTAL_ALIGNMENT_LEFT,-1,glyph_font_size).x)
	var line_height:=maxf(8.0,KoreanFont.get_height(glyph_font_size))
	var ascent:=KoreanFont.get_ascent(glyph_font_size)
	var repeat_count:=maxi(0,int(floor((size.x-advance*2.0)/advance)))
	var top_line:=left_top+"─".repeat(repeat_count)+right_top
	var bottom_line:=left_bottom+"─".repeat(repeat_count)+right_bottom
	draw_string(KoreanFont,Vector2(0.0,ascent),top_line,HORIZONTAL_ALIGNMENT_LEFT,-1,glyph_font_size,frame_color)
	draw_string(KoreanFont,Vector2(0.0,size.y-line_height+ascent),bottom_line,HORIZONTAL_ALIGNMENT_LEFT,-1,glyph_font_size,frame_color)
	var y:=line_height
	while y<size.y-line_height:
		draw_string(KoreanFont,Vector2(0.0,y+ascent),"│",HORIZONTAL_ALIGNMENT_LEFT,-1,glyph_font_size,frame_color)
		draw_string(KoreanFont,Vector2(size.x-advance,y+ascent),"│",HORIZONTAL_ALIGNMENT_LEFT,-1,glyph_font_size,
			DANGER if danger_edge else frame_color)
		y+=maxf(8.0,line_height-2.0)
	if not frame_title.is_empty():
		var title:=" ◆ %s "%frame_title
		draw_string(KoreanFont,Vector2(advance*2.0,ascent),title,HORIZONTAL_ALIGNMENT_LEFT,-1,glyph_font_size,title_color)

func frame_spec()->Dictionary:
	var advance:=maxf(4.0,KoreanFont.get_string_size("─",HORIZONTAL_ALIGNMENT_LEFT,-1,glyph_font_size).x)
	return {"primitive":"GLYPH_TEXT","boundary_glyphs":"┌─┐│└┘",
		"title":frame_title,"horizontal_repeat":maxi(0,int(floor((size.x-advance*2.0)/advance))),
		"font_size":glyph_font_size,"frame_color":frame_color.to_html(),
		"backdrop_color":backdrop_color.to_html(),"stylebox_border_width":0,
		"content_inset":[get_theme_constant("margin_left"),get_theme_constant("margin_top"),
			get_theme_constant("margin_right"),get_theme_constant("margin_bottom")]}.duplicate(true)

static func borderless_surface(color:Color=SURFACE,margin:int=0)->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=color
	style.set_border_width_all(0);style.set_corner_radius_all(0)
	style.set_content_margin_all(float(margin));return style

static func apply_rail_button(button:Button,accent:Color=CYAN,selected:bool=false,
		danger:bool=false)->void:
	var normal:=borderless_surface(Color("#00000000"),3)
	var hover:=borderless_surface(Color(accent,0.14),3)
	var pressed:=borderless_surface(Color(accent,0.22),3)
	var disabled:=borderless_surface(Color("#00000000"),3)
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",pressed)
	button.add_theme_stylebox_override("focus",pressed if selected else normal)
	button.add_theme_stylebox_override("disabled",disabled)
	button.add_theme_color_override("font_color",DANGER if danger else (BRASS if selected else INK))
	button.add_theme_color_override("font_hover_color",accent)
	button.add_theme_color_override("font_pressed_color",accent)
	button.add_theme_color_override("font_focus_color",BRASS if selected else accent)
	button.add_theme_color_override("font_disabled_color",Color("#52636b"))
	button.add_theme_constant_override("outline_size",0)
	button.set_meta("ascii_rail",true)
	button.set_meta("visible_stylebox_border",false)

static func apply_progress(bar:ProgressBar,accent:Color,low:bool=false)->void:
	var fill:=borderless_surface(DANGER if low else accent,0)
	var background:=borderless_surface(TRACK,0)
	bar.add_theme_stylebox_override("fill",fill)
	bar.add_theme_stylebox_override("background",background)
	bar.set_meta("ascii_gauge",true)
	bar.set_meta("low_vital",low)

static func label_tone(label:Label,tone:Color=INK,size_px:int=16)->void:
	label.add_theme_color_override("font_color",tone)
	label.add_theme_font_size_override("font_size",size_px)
