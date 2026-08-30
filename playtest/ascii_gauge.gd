class_name AsciiGauge
extends Label

const CodingFont:FontFile=preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const GREEN:=Color("#55ff55")

var prefix:="HP"
var columns:=10
var value:int=0:
	set(new_value):value=new_value;_refresh_text()
var max_value:int=100:
	set(new_value):max_value=maxi(1,new_value);_refresh_text()
var accent:=GREEN:
	set(new_value):accent=new_value;add_theme_color_override("font_color",accent)

func _init()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_text=true;text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	add_theme_font_override("font",CodingFont)
	add_theme_font_size_override("font_size",14)
	add_theme_color_override("font_color",accent)
	set_meta("dos_ascii_gauge",true)
	_refresh_text()

func configure(label_prefix:String,current:int,maximum:int,width_columns:int=10,
		tone:Color=GREEN)->void:
	prefix=label_prefix;columns=maxi(4,width_columns);max_value=maxi(1,maximum)
	value=clampi(current,0,max_value);accent=tone;_refresh_text()

func _refresh_text()->void:
	var filled:=clampi(int(floor(float(value)*float(columns)/float(maxi(1,max_value)))),0,columns)
	text="%s [%s%s] %d/%d"%[prefix,"#".repeat(filled),".".repeat(columns-filled),value,max_value]
	tooltip_text=text

func gauge_spec()->Dictionary:
	return {"primitive":"DOS_TEXT_GAUGE","font_path":"res://assets/fonts/LivingWorldMonoKR.ttf",
		"prefix":prefix,"columns":columns,"value":value,"max_value":max_value,
		"filled_glyph":"#","empty_glyph":".","text":text,
		"font_size":get_theme_font_size("font_size")}.duplicate(true)
