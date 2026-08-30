class_name AsciiUIFrame
extends MarginContainer

## Fixed-cell DOS/TUI frame. Every boundary glyph is placed at an explicit
## column/row; no repeated border string or proportional layout is used.

const CodingFont:FontFile=preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const CodingFontBold:FontFile=preload("res://assets/fonts/LivingWorldMonoKRBold.ttf")

const BLACK:=Color("#000306")
const NAVY:=Color("#05090b")
const SURFACE:=Color("#071012")
const SURFACE_DEEP:=Color("#000306")
const INK:=Color("#c7c2b3")
const BRIGHT:=Color("#ddd7c8")
const MUTED:=Color("#66737b")
const CYAN:=Color("#4f9aa3")
const YELLOW:=Color("#b8954d")
const RED:=Color("#a74343")
const GREEN:=Color("#5f8a66")

const BRASS:=YELLOW
const JADE:=GREEN
const DANGER:=RED
const TRACK:=Color("#303030")

var frame_title:=""
var frame_color:=CYAN
var title_color:=INK
var backdrop_color:=SURFACE
var glyph_font_size:=14
var compact_inset:=false
var danger_edge:=false

func _init()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	_refresh_insets()

func _ready()->void:
	resized.connect(queue_redraw)
	queue_redraw()

func configure(title:String="",tone:Color=CYAN,backdrop:Color=SURFACE,
		compact:bool=false,_rounded:bool=false)->void:
	frame_title=title;frame_color=tone;title_color=tone
	backdrop_color=backdrop;compact_inset=compact
	glyph_font_size=9 if compact else 14
	_refresh_insets();queue_redraw()

func cell_metrics()->Dictionary:
	var cell_width:=1
	for glyph in ["M","─","│","┌","┐","└","┘"]:
		cell_width=maxi(cell_width,int(ceil(CodingFont.get_string_size(glyph,
			HORIZONTAL_ALIGNMENT_LEFT,-1,glyph_font_size).x)))
	var line_height:=maxi(1,int(ceil(CodingFont.get_height(glyph_font_size))))
	return {"cell_width":cell_width,"line_height":line_height,
		"ascent":CodingFont.get_ascent(glyph_font_size),"font_size":glyph_font_size}.duplicate(true)

func _refresh_insets()->void:
	var metrics:=cell_metrics()
	add_theme_constant_override("margin_left",int(metrics.cell_width)+1)
	add_theme_constant_override("margin_right",int(metrics.cell_width)+1)
	add_theme_constant_override("margin_top",int(metrics.line_height))
	add_theme_constant_override("margin_bottom",int(metrics.line_height))
	update_minimum_size()

func _draw()->void:
	var spec:=frame_spec()
	if int(spec.columns)<2 or int(spec.rows)<2:return
	draw_rect(Rect2(Vector2.ZERO,size),backdrop_color,true)
	var cell_width:=float(spec.cell_width);var line_height:=float(spec.line_height)
	var ascent:=float(spec.ascent);var columns:=int(spec.columns);var rows:=int(spec.rows)
	var right_column:=columns-1;var bottom_row:=rows-1
	var title_cells:Dictionary=spec.title_cells
	for column in range(columns):
		var top_glyph:="─"
		if column==0:top_glyph="┌"
		elif column==right_column:top_glyph="┐"
		if not title_cells.has(column):_draw_cell(top_glyph,column,0,frame_color,cell_width,line_height,ascent)
		var bottom_glyph:="─"
		if column==0:bottom_glyph="└"
		elif column==right_column:bottom_glyph="┘"
		_draw_cell(bottom_glyph,column,bottom_row,frame_color,cell_width,line_height,ascent)
	for row in range(1,bottom_row):
		_draw_cell("│",0,row,frame_color,cell_width,line_height,ascent)
		_draw_cell("│",right_column,row,RED if danger_edge else frame_color,cell_width,line_height,ascent)
	if not frame_title.is_empty():
		var title_text:="[ %s ]"%frame_title
		var title_column:=int(spec.title_start_column)
		draw_string(CodingFontBold,Vector2(float(title_column)*cell_width,ascent),title_text,
			HORIZONTAL_ALIGNMENT_LEFT,-1,glyph_font_size,title_color)

func _draw_cell(glyph:String,column:int,row:int,color:Color,cell_width:float,
		line_height:float,ascent:float)->void:
	draw_string(CodingFont,Vector2(float(column)*cell_width,float(row)*line_height+ascent),glyph,
		HORIZONTAL_ALIGNMENT_LEFT,cell_width,glyph_font_size,color)

func frame_spec()->Dictionary:
	var metrics:=cell_metrics();var cell_width:=float(metrics.cell_width);var line_height:=float(metrics.line_height)
	var columns:=maxi(0,int(floor(size.x/cell_width)));var rows:=maxi(0,int(floor(size.y/line_height)))
	var title_text:="[ %s ]"%frame_title if not frame_title.is_empty() else ""
	var title_span:=_text_cell_span(title_text);var title_start:=mini(2,maxi(1,columns-title_span-1))
	var title_cells:Dictionary={}
	for column in range(title_start,mini(columns-1,title_start+title_span)):title_cells[column]=true
	var right_x:=float(maxi(0,columns-1))*cell_width
	var bottom_y:=float(maxi(0,rows-1))*line_height
	return {"primitive":"FIXED_CELL_GLYPHS","boundary_glyphs":"┌─┐│└┘",
		"font_path":"res://assets/fonts/LivingWorldMonoKR.ttf","title":frame_title,
		"title_text":title_text,"title_start_column":title_start,"title_cell_span":title_span,
		"title_cells":title_cells,"title_overdraws_border":false,
		"columns":columns,"rows":rows,"cell_width":int(metrics.cell_width),
		"line_height":int(metrics.line_height),"ascent":float(metrics.ascent),
		"right_edge_x":right_x,"bottom_edge_y":bottom_y,
		"right_edge_inside":right_x+cell_width<=size.x+0.01,
		"bottom_edge_inside":bottom_y+line_height<=size.y+0.01,
		"font_size":glyph_font_size,"frame_color":frame_color.to_html(),
		"backdrop_color":backdrop_color.to_html(),"stylebox_border_width":0,
		"content_inset":[get_theme_constant("margin_left"),get_theme_constant("margin_top"),
			get_theme_constant("margin_right"),get_theme_constant("margin_bottom")]}.duplicate(true)

func _text_cell_span(value:String)->int:
	var span:=0
	for character in value:span+=2 if character.unicode_at(0)>127 else 1
	return span

static func borderless_surface(color:Color=SURFACE,margin:int=0)->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=color
	style.set_border_width_all(0);style.set_corner_radius_all(0)
	style.set_content_margin_all(float(margin));return style

static func apply_rail_button(button:Button,accent:Color=CYAN,selected:bool=false,
		danger:bool=false)->void:
	var normal:=borderless_surface(Color("#00000000"),2)
	var active_color:=RED if danger else accent
	var reverse:=borderless_surface(active_color,2)
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",reverse)
	button.add_theme_stylebox_override("pressed",reverse)
	button.add_theme_stylebox_override("focus",reverse if selected else normal)
	button.add_theme_stylebox_override("disabled",normal)
	button.add_theme_color_override("font_color",YELLOW if selected else (RED if danger else INK))
	button.add_theme_color_override("font_hover_color",BLACK)
	button.add_theme_color_override("font_pressed_color",BLACK)
	button.add_theme_color_override("font_focus_color",BLACK if selected else active_color)
	button.add_theme_color_override("font_disabled_color",MUTED)
	button.add_theme_constant_override("outline_size",0)
	button.set_meta("ascii_rail",true);button.set_meta("dos_command",true)
	button.set_meta("visible_stylebox_border",false)

static func apply_progress(bar:ProgressBar,accent:Color,low:bool=false)->void:
	var fill:=borderless_surface(RED if low else accent,0)
	var background:=borderless_surface(TRACK,0)
	bar.add_theme_stylebox_override("fill",fill);bar.add_theme_stylebox_override("background",background)
	bar.set_meta("ascii_gauge",false);bar.set_meta("legacy_progress",true);bar.set_meta("low_vital",low)

static func label_tone(label:Label,tone:Color=INK,size_px:int=16)->void:
	label.add_theme_font_override("font",CodingFont)
	label.add_theme_color_override("font_color",tone)
	label.add_theme_font_size_override("font_size",size_px)
