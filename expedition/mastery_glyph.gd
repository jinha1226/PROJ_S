extends Control
## Compact vector symbols for the ten Model B masteries.
var axis := "sword"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(30,30)

func _draw() -> void:
	var ink := Color("e2d6be")
	var accent := Color("c6a34c") if axis in ["sword","spear","mace","axe","bow"] else Color("69cfc2")
	match axis:
		"sword":
			draw_line(Vector2(6,25),Vector2(24,5),ink,3)
			draw_line(Vector2(9,18),Vector2(17,26),accent,3)
			draw_line(Vector2(4,27),Vector2(9,22),accent,3)
		"spear":
			draw_line(Vector2(5,26),Vector2(23,7),ink,2)
			draw_colored_polygon(PackedVector2Array([Vector2(20,10),Vector2(27,2),Vector2(19,5)]),accent)
		"mace":
			draw_line(Vector2(6,27),Vector2(21,10),ink,3)
			draw_rect(Rect2(18,4,9,9),accent)
		"axe":
			draw_line(Vector2(7,27),Vector2(22,4),ink,3)
			draw_colored_polygon(PackedVector2Array([Vector2(20,6),Vector2(27,7),Vector2(25,17),Vector2(17,15)]),accent)
		"bow":
			draw_arc(Vector2(10,16),13,-PI/2,PI/2,12,accent,2)
			draw_line(Vector2(10,3),Vector2(10,29),ink,1)
			draw_line(Vector2(5,16),Vector2(27,16),ink,2)
			draw_colored_polygon(PackedVector2Array([Vector2(27,16),Vector2(22,12),Vector2(22,20)]),accent)
		"fire":
			draw_colored_polygon(PackedVector2Array([Vector2(15,2),Vector2(7,17),Vector2(10,27),Vector2(22,27),Vector2(25,17),Vector2(19,11),Vector2(17,19)]),Color("db8057"))
			draw_colored_polygon(PackedVector2Array([Vector2(15,17),Vector2(12,26),Vector2(20,26),Vector2(19,20)]),accent)
		"ice":
			for angle in [0.0,PI/3,2*PI/3]:
				var direction := Vector2.RIGHT.rotated(angle)
				draw_line(Vector2(16,16)-direction*12,Vector2(16,16)+direction*12,accent,2)
			draw_circle(Vector2(16,16),3,ink)
		"air":
			draw_arc(Vector2(14,13),10,PI,TAU,14,accent,2)
			draw_arc(Vector2(18,19),8,0,PI,12,ink,2)
			draw_line(Vector2(3,13),Vector2(17,13),accent,2)
		"hex":
			draw_arc(Vector2(16,16),11,0,TAU,16,accent,2)
			draw_line(Vector2(8,9),Vector2(24,23),ink,2)
			draw_line(Vector2(24,9),Vector2(8,23),ink,2)
		"summon":
			draw_arc(Vector2(16,18),10,0,TAU,16,accent,2)
			draw_circle(Vector2(16,11),4,ink)
			draw_line(Vector2(10,27),Vector2(10,22),ink,2)
			draw_line(Vector2(22,27),Vector2(22,22),ink,2)
