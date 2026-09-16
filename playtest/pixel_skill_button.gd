extends Button
func _ready()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	hide_native_text()
func hide_native_text()->void:
	for key in ["font_color","font_hover_color","font_pressed_color","font_disabled_color","font_focus_color","font_hover_pressed_color"]:
		add_theme_color_override(key,Color.TRANSPARENT)
func _draw()->void:
	var icons=preload("res://playtest/gameplay_pixel_icons.gd")
	var key:String=icons.skill_key(str(get_meta("skill_id","")))
	draw_texture_rect(icons.texture(key),Rect2(Vector2(2,0),Vector2(28,28)),false,Color(1,1,1,0.4) if disabled else Color.WHITE)
	var lines:=text.split("\n")
	var full_label:String=str(get_meta("skill_label",lines[0]))
	var ink:=Color("839090") if disabled else Color("e1ddd0")
	draw_string(get_theme_font("font"),Vector2(2,size.y-5),full_label,HORIZONTAL_ALIGNMENT_CENTER,size.x-4,11,ink)
	if lines.size()>1:
		draw_string(get_theme_font("font"),Vector2(29,18),lines[1].replace("기력 ",""),HORIZONTAL_ALIGNMENT_CENTER,maxf(1,size.x-31),10,Color("69c6da"))
