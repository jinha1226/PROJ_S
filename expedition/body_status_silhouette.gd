extends Control
var body:Dictionary={}
func _ready()->void:
	custom_minimum_size=Vector2(64,126);mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw()->void:
	var parts={"HEAD":Rect2(24,4,16,20),"TORSO":Rect2(18,28,28,44),
		"RIGHT_ARM":Rect2(6,30,9,46),"LEFT_ARM":Rect2(49,30,9,46),
		"RIGHT_LEG":Rect2(18,76,11,44),"LEFT_LEG":Rect2(35,76,11,44)}
	for id in parts:
		var color:=Color("697071")
		for part in body.get("parts",[]):
			if str(part.get("part_id",""))==id and str(part.get("condition","FUNCTIONAL"))!="FUNCTIONAL":color=Color("9f4544")
		draw_rect(parts[id],color)
