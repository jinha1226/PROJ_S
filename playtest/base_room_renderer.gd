extends RefCounted

## Cutaway top-down rooms: the facility's purpose reads from furniture, not a
## roof icon. Macro footprints stay small enough for the mobile 16 x 16 base.
static func draw_room(canvas:CanvasItem,rect:Rect2,type_id:String,level:int)->void:
	var wall:=Color("#84918b") if level>=3 else Color("#a47b4e")
	var s:=minf(rect.size.x/3.0,rect.size.y/2.0)
	var room:=rect.grow(-2)
	canvas.draw_rect(room,Color("#171d1a"))
	var floor_rect:=room.grow(-maxf(3,s*0.15))
	canvas.draw_rect(floor_rect,Color("#514c3c") if level<3 else Color("#495451"))
	canvas.draw_rect(room,wall,false,maxf(2,s*0.13))
	var door:=Vector2(room.get_center().x,room.end.y)
	canvas.draw_line(door-Vector2(s*0.3,0),door+Vector2(s*0.3,0),Color("#514c3c"),maxf(3,s*0.2))
	match type_id:
		"STORAGE":
			for p in [Vector2(0.24,0.3),Vector2(0.67,0.3),Vector2(0.24,0.68)]:
				var box:=Rect2(room.position+room.size*p-Vector2.ONE*s*0.22,Vector2.ONE*s*0.44)
				canvas.draw_rect(box,Color("#bf9156"));canvas.draw_rect(box,Color("#31271a"),false,2)
				canvas.draw_line(box.position,box.end,Color("#e2c48b"),1)
		"LODGE","CLINIC":
			for x in [0.25,0.72]:
				var bed:=Rect2(room.position+room.size*Vector2(x-0.12,0.18),room.size*Vector2(0.25,0.56))
				canvas.draw_rect(bed,Color("#2b241c"))
				canvas.draw_rect(bed.grow(-2),Color("#8aaf91") if type_id=="CLINIC" else Color("#808bb0"))
				canvas.draw_rect(Rect2(bed.position+Vector2(3,3),Vector2(bed.size.x-6,bed.size.y*0.23)),Color("#ded4b8"))
			if type_id=="CLINIC":
				var c:=room.get_center()
				canvas.draw_line(c-Vector2(s*0.15,0),c+Vector2(s*0.15,0),Color("#dce8cc"),maxf(2,s*0.12))
				canvas.draw_line(c-Vector2(0,s*0.15),c+Vector2(0,s*0.15),Color("#dce8cc"),maxf(2,s*0.12))
		"ARMORY":
			var bench:=Rect2(room.position+room.size*Vector2(0.15,0.15),room.size*Vector2(0.7,0.3))
			canvas.draw_rect(bench,Color("#987341"));canvas.draw_rect(bench.grow(-3),Color("#748387"))
			canvas.draw_circle(room.position+room.size*Vector2(0.3,0.72),s*0.22,Color("#e69a56"))
