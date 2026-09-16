extends Control
## Presentation only: no detection rolls or time progression.
var kind:="STEALTH"
var state:="UNAWARE"
func configure(next_state:String)->void:
	if state==next_state:return
	state=next_state;queue_redraw()
func _draw()->void:
	var ink:=Color("74bb68")
	var label:="은신"
	if state in ["ALERT","HUNTING"]:ink=Color("df775d");label="발각"
	elif state in ["SUSPICIOUS","SEARCHING"]:ink=Color("dbb55e");label="경계"
	var c:=Vector2(11,size.y*0.5)
	if kind=="NOISE":
		ink=Color("968c79");label="소음 —"
		for i in range(3):
			draw_rect(Rect2(c+Vector2(-8+i*6,-3-i*3),Vector2(3,6+i*6)),ink)
	else:
		draw_polyline(PackedVector2Array([c+Vector2(-11,0),c+Vector2(-5,-6),c+Vector2(5,-6),c+Vector2(11,0),c+Vector2(5,6),c+Vector2(-5,6),c+Vector2(-11,0)]),ink,2)
		draw_rect(Rect2(c+Vector2(-2,-3),Vector2(4,6)),ink)
	draw_line(Vector2(0,5),Vector2(0,size.y-5),Color("393c3a"),1)
	if kind=="NOISE":
		draw_string(get_theme_font("font"),Vector2(22,size.y*0.5-2),"소음",HORIZONTAL_ALIGNMENT_CENTER,size.x-22,11,ink)
		draw_string(get_theme_font("font"),Vector2(22,size.y*0.5+12),"—",HORIZONTAL_ALIGNMENT_CENTER,size.x-22,11,ink)
	else:
		draw_string(get_theme_font("font"),Vector2(24,size.y*0.5+4),label,HORIZONTAL_ALIGNMENT_CENTER,size.x-24,12,ink)
