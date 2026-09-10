extends Control
## Vector silhouettes, independent of fonts and display resolution.
var kind:="HOUSE"
var color:=Color("#c6ac78")
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw()->void:
	var scale:=minf(size.x,size.y)/32.0
	draw_set_transform((size-Vector2.ONE*32*scale)*0.5,0,Vector2.ONE*scale)
	match kind:
		"FOOD":
			draw_rect(Rect2(7,12,18,13),color,false,2)
			draw_arc(Vector2(16,12),9,PI,TAU,16,color,2,true)
			draw_line(Vector2(12,18),Vector2(21,18),color,2,true)
		"POTION":
			draw_rect(Rect2(12,5,8,5),color,true)
			draw_rect(Rect2(8,10,16,17),color,false,2)
			draw_line(Vector2(10,18),Vector2(22,18),color,2,true)
		"TORCH":
			draw_line(Vector2(16,27),Vector2(16,10),color,3,true)
			draw_polyline(PackedVector2Array([Vector2(10,11),Vector2(16,4),Vector2(22,11),Vector2(16,15),Vector2(10,11)]),color,2,true)
		"INN":
			draw_circle(Vector2(12,10),4,color)
			draw_arc(Vector2(12,25),8,PI,TAU,16,color,2,true)
			draw_arc(Vector2(22,10),3,-PI/2,PI/2,12,color,2,true)
			draw_arc(Vector2(22,24),6,-PI/2,0,12,color,2,true)
		"CLINIC":
			draw_rect(Rect2(12,5,8,22),color);draw_rect(Rect2(5,12,22,8),color)
		"MARKET":
			draw_polyline(PackedVector2Array([Vector2(5,13),Vector2(8,5),Vector2(24,5),Vector2(27,13),Vector2(5,13)]),color,2,true)
			draw_rect(Rect2(7,14,18,13),color,false,2)
			draw_line(Vector2(17,18),Vector2(17,27),color,2,true)
		"ARMORY":
			draw_polyline(PackedVector2Array([Vector2(8,25),Vector2(24,7),Vector2(25,15)]),color,3,true)
			draw_line(Vector2(7,17),Vector2(16,25),color,3,true)
		"GATE":
			draw_rect(Rect2(5,5,16,22),color,false,2)
			draw_line(Vector2(14,16),Vector2(29,16),color,2,true)
			draw_polyline(PackedVector2Array([Vector2(24,11),Vector2(29,16),Vector2(24,21)]),color,2,true)
		_:
			draw_polyline(PackedVector2Array([Vector2(4,15),Vector2(16,5),Vector2(28,15)]),color,2,true)
			draw_polyline(PackedVector2Array([Vector2(8,14),Vector2(8,27),Vector2(24,27),Vector2(24,14)]),color,2,true)
			draw_rect(Rect2(14,19,5,8),color,false,2)
