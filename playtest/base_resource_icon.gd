extends RefCounted

const ItemAssets=preload("res://playtest/pixel24_item_assets.gd")

static func draw_icon(canvas:CanvasItem,rect:Rect2,resource_id:String)->void:
	var texture:=ItemAssets.texture_for_id(resource_id)
	if texture!=null:
		var side:=minf(rect.size.x,rect.size.y)
		canvas.draw_texture_rect(texture,Rect2(rect.get_center()-Vector2.ONE*side*0.5,
			Vector2.ONE*side),false,Color.WHITE)
		return
	var c:=rect.get_center();var s:=minf(rect.size.x,rect.size.y)*0.65
	var edge:=maxf(1.0,s*0.08)
	match resource_id:
		"TIMBER":
			for y in [-0.19,0.19]:
				var log_rect:=Rect2(c+Vector2(-0.45,y-0.14)*s,Vector2(0.9,0.28)*s)
				canvas.draw_rect(log_rect,Color("#231a12"))
				canvas.draw_rect(log_rect.grow(-edge),Color("#c18b4c"))
			canvas.draw_line(c+Vector2(0.1,-0.36)*s,c+Vector2(0.1,0.36)*s,Color("#e8d5a2"),edge)
		"STONE":
			var points:=PackedVector2Array([c+Vector2(-0.46,0.3)*s,c+Vector2(-0.34,-0.24)*s,
				c+Vector2(0.14,-0.4)*s,c+Vector2(0.44,0.1)*s,c+Vector2(0.32,0.38)*s])
			canvas.draw_colored_polygon(points,Color("#bdc4c9"))
			points.append(points[0]);canvas.draw_polyline(points,Color("#303b42"),edge)
		"HERBS":
			canvas.draw_line(c+Vector2(0,0.4)*s,c+Vector2(0,-0.3)*s,Color("#d2e3a4"),edge)
			for side in [-1,1]:
				canvas.draw_colored_polygon(PackedVector2Array([c,c+Vector2(side*0.45,-0.33)*s,
					c+Vector2(side*0.39,0.1)*s]),Color("#8bce78"))
