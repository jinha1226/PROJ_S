extends Button

## Code-native icons stay sharp at phone resolutions; text remains the command
## state/accessibility source so contextual AUTO/reload/portal actions still work.
func _ready()->void:
	add_theme_color_override("font_color",Color.TRANSPARENT)
	add_theme_color_override("font_hover_color",Color.TRANSPARENT)
	add_theme_color_override("font_pressed_color",Color.TRANSPARENT)
	add_theme_color_override("font_disabled_color",Color.TRANSPARENT)
	resized.connect(queue_redraw)

func _draw()->void:
	var ink:=Color("#e5e4da") if not disabled else Color("#727778")
	var center:=Vector2(size.x*0.5,18)
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
	match str(name):
		"ProductAttack":
			for direction in [-1,1]:
				var d:=float(direction)
				draw_line(center+Vector2(-9*d,10),center+Vector2(9*d,-10),ink,3,true)
				draw_line(center+Vector2(-10*d,2),center+Vector2(-2*d,9),ink,2,true)
		"ProductWaitGuard":
			var points:=PackedVector2Array([center+Vector2(-10,-10),center+Vector2(10,-10),center+Vector2(8,5),center+Vector2(0,11),center+Vector2(-8,5),center+Vector2(-10,-10)])
			draw_polyline(points,ink,2,true)
			draw_line(center+Vector2(0,-5),center+Vector2(0,5),ink,2,true)
		"ProductAuto":
			draw_arc(center,10,0,TAU,32,ink,1.5,true)
			draw_colored_polygon(PackedVector2Array([center+Vector2(5,-7),center+Vector2(2,3),center+Vector2(-5,7),center+Vector2(-2,-3)]),ink)
		"ProductBag":
			draw_style_box(preload("res://playtest/dark_pixel_ui_skin.gd").panel_surface(Color.TRANSPARENT,ink,0,2),Rect2(center-Vector2(10,6),Vector2(20,17)))
			draw_arc(center+Vector2(0,-5),6,PI,TAU,16,ink,2,true)
		_:
			draw_arc(center,9,0,TAU,24,ink,2,true)
			draw_line(center-Vector2(5,0),center+Vector2(5,0),ink,2,true)
			draw_line(center-Vector2(0,5),center+Vector2(0,5),ink,2,true)
	draw_string(get_theme_font("font"),Vector2(2,size.y-5),label,HORIZONTAL_ALIGNMENT_CENTER,size.x-4,11,ink)
