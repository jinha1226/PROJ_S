extends Control
## Small code-native emblems; no animation, raster generation or per-frame work.
var symbol:="MELEE"
func _ready()->void:
	custom_minimum_size=Vector2(20,20);mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw()->void:
	var color:=Color("c6a34c")
	match symbol:
		"MELEE":
			draw_line(Vector2(10,2),Vector2(10,14),Color("d0c8b4"),3)
			draw_line(Vector2(5,13),Vector2(15,13),color,2);draw_line(Vector2(10,14),Vector2(10,19),color,2)
		"RANGED":
			draw_polyline(PackedVector2Array([Vector2(5,2),Vector2(14,7),Vector2(14,13),Vector2(5,18)]),Color("70a573"),2)
			draw_line(Vector2(5,2),Vector2(5,18),color,1);draw_line(Vector2(3,10),Vector2(19,10),color,2)
		"MAGIC":
			draw_colored_polygon(PackedVector2Array([Vector2(11,1),Vector2(9,8),Vector2(5,6),Vector2(3,13),Vector2(7,19),Vector2(14,19),Vector2(17,12)]),Color("4d8f98"))
		"DEFENSE":
			draw_colored_polygon(PackedVector2Array([Vector2(10,2),Vector2(18,5),Vector2(16,14),Vector2(10,19),Vector2(4,14),Vector2(2,5)]),Color("89969c"))
			draw_line(Vector2(10,5),Vector2(10,15),Color("d0c8b4"),2)
