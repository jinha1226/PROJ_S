extends Control
var kind:="TIMBER"
func _ready()->void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw()->void:
	var scale:=minf(size.x,size.y)/32.0
	draw_set_transform((size-Vector2.ONE*32*scale)*0.5,0,Vector2.ONE*scale)
	var ink:=Color("d5d8ce")
	match kind:
		"TIMBER":
			draw_rect(Rect2(5,8,22,16),Color("94633d"));draw_rect(Rect2(7,10,19,3),Color("be8b54"))
			draw_circle(Vector2(7,16),7,Color("c79a60"));draw_arc(Vector2(7,16),4,0,TAU,16,Color("80532f"),2)
		"STONE":draw_colored_polygon(PackedVector2Array([Vector2(3,23),Vector2(7,10),Vector2(18,5),Vector2(28,16),Vector2(25,26)]),Color("9eabb5"))
		"HERBS":
			draw_line(Vector2(9,28),Vector2(22,4),Color("779b52"),3)
			draw_colored_polygon(PackedVector2Array([Vector2(15,19),Vector2(3,15),Vector2(5,7),Vector2(16,12)]),Color("9ab96c"))
			draw_colored_polygon(PackedVector2Array([Vector2(19,13),Vector2(20,4),Vector2(30,3),Vector2(27,12)]),Color("6c9c51"))
		"FOOD":draw_circle(Vector2(16,18),10,Color("c87650"));draw_line(Vector2(16,8),Vector2(20,3),Color("84a665"),4)
		"RESIDENT":draw_circle(Vector2(16,9),6,ink);draw_rect(Rect2(7,19,18,10),ink)
		"EXPEDITION":draw_colored_polygon(PackedVector2Array([Vector2(3,7),Vector2(11,4),Vector2(21,8),Vector2(29,4),Vector2(29,25),Vector2(21,29),Vector2(11,25),Vector2(3,28)]),ink)
		_:
			draw_line(Vector2(6,28),Vector2(24,7),ink,5)
			draw_colored_polygon(PackedVector2Array([Vector2(14,5),Vector2(20,2),Vector2(30,11),Vector2(25,17)]),ink)
			if kind=="BUILD":draw_line(Vector2(7,6),Vector2(26,27),Color("bd9b61"),4)
