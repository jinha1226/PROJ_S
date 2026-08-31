class_name AsciiGauge
extends Label

const CodingFont:FontFile=preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const GREEN:=Color("#5f8a66")
const HP_FILL:=Color("#b84b4b")
const MP_FILL:=Color("#4f82b8")
const XP_FILL:=Color("#5f9b66")
const BLACK_IRON:=Color("#000306")
const AGED_BONE:=Color("#c7c2b3")
const BONE_DIM:=Color("#918b7d")
const EMPTY_IRON:=Color("#344447")

var prefix:="HP"
var columns:=10
var value:int=0:
	set(new_value):value=new_value;_refresh_text()
var max_value:int=100:
	set(new_value):max_value=maxi(1,new_value);_refresh_text()
var accent:=GREEN:
	set(new_value):accent=new_value;queue_redraw()
var semantic_role:=""

func _init()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_text=true;clip_contents=true;text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	add_theme_font_override("font",CodingFont)
	add_theme_font_size_override("font_size",14)
	# Label still owns text measurement/accessibility while custom drawing gives
	# prefix, fill, track and value their own restrained ink hierarchy.
	add_theme_color_override("font_color",Color.TRANSPARENT)
	set_meta("dos_ascii_gauge",true)
	set_meta("visual_family","DARK_FANTASY_BONE_GAUGE")
	set_process(false)
	_refresh_text()

func _ready()->void:
	resized.connect(queue_redraw)
	queue_redraw()

func configure(label_prefix:String,current:int,maximum:int,width_columns:int=10,
		tone:Color=GREEN)->void:
	semantic_role=""
	prefix=label_prefix;columns=maxi(4,width_columns);max_value=maxi(1,maximum)
	value=clampi(current,0,max_value);accent=tone;_refresh_text()

func configure_semantic(label_prefix:String,current:int,maximum:int,width_columns:int=10,
		fallback_tone:Color=GREEN)->void:
	var role:=label_prefix.strip_edges().to_upper()
	configure(label_prefix,current,maximum,width_columns,
		semantic_accent(role,fallback_tone))
	semantic_role=role if role in ["HP","MP","XP"] else ""

static func semantic_accent(role:String,fallback_tone:Color=GREEN)->Color:
	match role.strip_edges().to_upper():
		"HP":return HP_FILL
		"MP":return MP_FILL
		"XP":return XP_FILL
		_:return fallback_tone

func _refresh_text()->void:
	var filled:=clampi(int(floor(float(value)*float(columns)/float(maxi(1,max_value)))),0,columns)
	text="%s [%s%s] %d/%d"%[prefix,"#".repeat(filled),".".repeat(columns-filled),value,max_value]
	tooltip_text=text
	queue_redraw()

func _draw()->void:
	if size.x<=0.0 or size.y<=0.0:return
	var font_size:int=get_theme_font_size("font_size")
	var line_height:float=CodingFont.get_height(font_size)
	var baseline_y:float=float(floor((size.y-line_height)*0.5+CodingFont.get_ascent(font_size)))
	var filled:=clampi(int(floor(float(value)*float(columns)/float(maxi(1,max_value)))),0,columns)
	var segments:Array[Dictionary]=[
		{"text":"%s ["%prefix,"color":AGED_BONE},
		{"text":"#".repeat(filled),"color":accent},
		{"text":".".repeat(columns-filled),"color":EMPTY_IRON},
		{"text":"] ","color":AGED_BONE},
		{"text":"%d/%d"%[value,max_value],"color":AGED_BONE},
	]
	var cursor_x:=0.0
	for segment in segments:
		var segment_text:=str(segment.text)
		if segment_text.is_empty():continue
		var segment_color:Color=segment.color
		draw_string(CodingFont,Vector2(cursor_x,baseline_y),segment_text,
			HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,segment_color)
		cursor_x+=CodingFont.get_string_size(segment_text,
			HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x

func gauge_spec()->Dictionary:
	var filled:=clampi(int(floor(float(value)*float(columns)/float(maxi(1,max_value)))),0,columns)
	return {"primitive":"DOS_TEXT_GAUGE","font_path":"res://assets/fonts/LivingWorldMonoKR.ttf",
		"prefix":prefix,"columns":columns,"value":value,"max_value":max_value,
		"filled_glyph":"#","empty_glyph":".","text":text,
		"font_size":get_theme_font_size("font_size"),
		"visual_family":"DARK_FANTASY_BONE_GAUGE","material":"ETCHED_IRON",
		"semantic_role":semantic_role,
		"filled_columns":filled,"empty_columns":columns-filled,
		"segment_colors":{"label":AGED_BONE.to_html(),"fill":accent.to_html(),
			"empty":EMPTY_IRON.to_html(),"value":AGED_BONE.to_html()},
		"uses_texture":false,"uses_image":false,"per_frame_process":false}.duplicate(true)
