extends Button

## Generated fantasy icons use linear filtering; text remains the command
## state/accessibility source so contextual AUTO/reload/portal actions still work.
func _ready()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	add_theme_color_override("font_color",Color.TRANSPARENT)
	add_theme_color_override("font_hover_color",Color.TRANSPARENT)
	add_theme_color_override("font_pressed_color",Color.TRANSPARENT)
	add_theme_color_override("font_disabled_color",Color.TRANSPARENT)
	resized.connect(queue_redraw)

func _draw()->void:
	var ink:=Color("#e5e4da") if not disabled else Color("#727778")
	var label:=text.replace("[","").replace("]","")
	match label:
		"AUTO":label="탐험"
		"STOP":label="중지"
		"ATTACK":label="공격"
		"INTERACT":label="상호작용"
		"WAIT":label="대기"
		"GUARD":label="방어"
		"RELOAD":label="재장전"
		"RESTART":label="재시작"
	var icon_key:String={"ProductAttack":"attack","ProductWaitGuard":"wait","ProductRest":"wait",
		"ProductAuto":"explore","ProductTactics":"tactics","ProductBag":"bag"}.get(str(name),"ability")
	var icons=preload("res://playtest/gameplay_pixel_icons.gd")
	var main_command:=str(name) in ["ProductAttack","ProductWaitGuard","ProductAuto","ProductTactics","ProductBag"]
	var icon:Texture2D=icons.monochrome_texture(icon_key) if main_command else icons.texture(icon_key)
	if main_command:ink=Color("#d1d6db") if not disabled else Color("#727778")
	draw_texture_rect(icon,Rect2(Vector2(size.x*0.5-18,0),Vector2(36,36)),false,
		Color(1,1,1,0.4) if disabled else Color.WHITE)
	draw_string(get_theme_font("font"),Vector2(2,size.y-5),label,HORIZONTAL_ALIGNMENT_CENTER,size.x-4,11,ink)
