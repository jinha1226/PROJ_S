extends RefCounted
## Small vector icons shared by the room map and the room interior.
static func paint(canvas: CanvasItem, kind: String, center: Vector2, radius: float, color: Color) -> void:
	match kind:
		"camp":
			canvas.draw_circle(center,radius,Color("193d36"))
			canvas.draw_line(center-Vector2(radius*0.6,0),center+Vector2(radius*0.6,0),color,4)
			canvas.draw_line(center-Vector2(0,radius*0.6),center+Vector2(0,radius*0.6),color,4)
		"loot":
			var rect := Rect2(center-Vector2(radius,radius*0.65),Vector2(radius*2,radius*1.3))
			canvas.draw_rect(rect,Color("594528"))
			canvas.draw_rect(rect,color,false,2)
			canvas.draw_line(rect.position+Vector2(0,radius*0.5),rect.end-Vector2(0,radius*0.8),color,2)
			canvas.draw_rect(Rect2(center-Vector2(2,2),Vector2(4,7)),color)
		"battle", "boss":
			for direction in [-1,1]:
				var base := center+Vector2(radius*0.65*direction,radius*0.8)
				var tip := center-Vector2(radius*0.7*direction,radius*0.9)
				canvas.draw_line(base,tip,color,3)
				var guard := base.lerp(tip,0.24)
				canvas.draw_line(guard+Vector2(-radius*0.25,radius*0.2*direction),guard+Vector2(radius*0.25,-radius*0.2*direction),color,3)
			if kind == "boss": canvas.draw_arc(center,radius*1.3,PI,TAU,16,color,2)
		_:
			canvas.draw_rect(Rect2(center-Vector2(radius*0.65,radius),Vector2(radius*1.3,radius*2)),color,false,3)
			canvas.draw_circle(center+Vector2(radius*0.28,0),2,color)
