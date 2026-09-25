extends RefCounted
## Small vector icons shared by the room map and the room interior.
static func paint(canvas: CanvasItem, kind: String, center: Vector2, radius: float, color: Color) -> void:
	match kind:
		"potion":
			canvas.draw_rect(Rect2(center+Vector2(-radius*0.3,-radius),Vector2(radius*0.6,radius*0.45)),color)
			canvas.draw_colored_polygon(PackedVector2Array([center+Vector2(-radius*0.4,-radius*0.55),center+Vector2(radius*0.4,-radius*0.55),center+Vector2(radius*0.65,radius*0.7),center+Vector2(-radius*0.65,radius*0.7)]),Color("6e354d"))
			canvas.draw_rect(Rect2(center+Vector2(-radius*0.65,-radius*0.55),Vector2(radius*1.3,radius*1.25)),color,false,2)
		"scroll":
			canvas.draw_rect(Rect2(center+Vector2(-radius*0.65,-radius*0.75),Vector2(radius*1.3,radius*1.5)),Color("d5bd87"))
			canvas.draw_line(center+Vector2(-radius*0.4,-radius*0.25),center+Vector2(radius*0.35,-radius*0.25),color,2)
			canvas.draw_line(center+Vector2(-radius*0.4,radius*0.2),center+Vector2(radius*0.25,radius*0.2),color,2)
		"stairs":
			canvas.draw_colored_polygon(PackedVector2Array([center+Vector2(-radius,radius*0.75),center+Vector2(radius,radius*0.75),center+Vector2(0,-radius)]),Color("24333d"))
			canvas.draw_line(center+Vector2(-radius,radius*0.75),center+Vector2(radius,radius*0.75),color,2)
			canvas.draw_line(center+Vector2(0,-radius),center+Vector2(0,radius*0.5),color,2)
		"lever":
			canvas.draw_rect(Rect2(center-Vector2(radius*0.3,radius),Vector2(radius*0.6,radius*2)),Color("24333d"))
			canvas.draw_circle(center-Vector2(0,radius*0.6),radius*0.36,color)
		"dirt":
			canvas.draw_colored_polygon(PackedVector2Array([center+Vector2(-radius,radius*0.6),center+Vector2(-radius*0.3,-radius*0.7),center+Vector2(radius*0.4,-radius*0.3),center+Vector2(radius,radius*0.6)]),Color("74563d"))
			canvas.draw_line(center+Vector2(-radius,radius*0.6),center+Vector2(radius,radius*0.6),color,2)
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
		"relic":
			var gem := PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius*0.75,0),center+Vector2(0,radius),center+Vector2(-radius*0.75,0)])
			canvas.draw_colored_polygon(gem,Color("1c3f52"))
			canvas.draw_polyline(gem+PackedVector2Array([gem[0]]),color,2,true)
			canvas.draw_line(center+Vector2(-radius*0.75,0),center+Vector2(radius*0.75,0),color,1)
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
