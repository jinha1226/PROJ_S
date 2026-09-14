extends Node2D
## Retained ground commands: items, bodies, lights and camera motion cannot
## change terrain identity. Observed data only; no hidden world reads.
var cells:Array=[]
var viewport:=Rect2()
var board_origin:=Vector2i.ZERO
var count:=13
const Projection=preload("res://playtest/tactical_board_projection.gd")

func synchronize(cache:Dictionary,rect:Rect2,origin:Vector2i,cell_count:int)->void:
	viewport=rect;board_origin=origin;count=cell_count
	cells=cache.values().duplicate()
	cells.sort_custom(func(a,b):
		var pa:Vector2i=a.position;var pb:Vector2i=b.position
		return pa.x+pa.y<pb.x+pb.y if pa.x+pa.y!=pb.x+pb.y else pa.x<pb.x)
	queue_redraw()

func _draw()->void:
	draw_rect(viewport,Color("#0c131b"))
	for row in cells:
		var spec:Dictionary=row.get("tile_spec",{})
		if not spec.get("visible",false):continue
		var p:PackedVector2Array=row.polygon
		if p.size()!=4:continue
		var memory:bool=str(row.visibility_state)!="VISIBLE"
		var tint:=Color(0.27,0.30,0.33,1) if memory else Color(0.68,0.76,0.79,1)
		var uv:=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
		if not spec.get("is_wall",false):
			draw_polygon(p,PackedColorArray([tint]),uv,spec.texture)
			var outline:=PackedVector2Array(p);outline.append(p[0])
			draw_polyline(outline,Color(0.08,0.13,0.17,0.65),1.0)
			if not memory:_detail(row,p)
	# Low, opaque faces keep walls readable without covering adjacent actors.
	for row in cells:
		var spec:Dictionary=row.get("tile_spec",{})
		if not spec.get("visible",false) or not spec.get("is_wall",false):continue
		var p:PackedVector2Array=row.polygon
		if p.size()!=4:continue
		var memory:bool=str(row.visibility_state)!="VISIBLE"
		var height:=Projection.half_width(viewport,count)*0.9
		var lift:=Vector2(0,-height)
		var top:=PackedVector2Array()
		for point in p:top.append(point+lift)
		var shade:=0.32 if memory else 1.0
		draw_colored_polygon(PackedVector2Array([top[3],top[2],p[2],p[3]]),Color("#35414b")*shade)
		draw_colored_polygon(PackedVector2Array([top[1],top[2],p[2],p[1]]),Color("#222e38")*shade)
		draw_colored_polygon(top,Color("#71818b")*shade)
		var edge:=PackedVector2Array(top);edge.append(top[0])
		draw_polyline(edge,Color("#99acb5")*shade,1.0)
		draw_line(top[3].lerp(top[2],0.5),p[3].lerp(p[2],0.5),Color("#202d36")*shade,1.0)

func _detail(row:Dictionary,p:PackedVector2Array)->void:
	var terrain:String=str(row.terrain.get("terrain_id",""))
	var center:Vector2=(p[0]+p[2])*0.5
	var h:=Projection.half_width(viewport,count)
	if terrain=="rubble":
		for offset in [Vector2(-0.35,0.02),Vector2(0.2,0.12),Vector2(0.04,-0.2)]:
			var c:Vector2=center+offset*h
			draw_colored_polygon(PackedVector2Array([c+Vector2(-0.2,0.06)*h,c+Vector2(-0.1,-0.18)*h,c+Vector2(0.17,-0.08)*h,c+Vector2(0.2,0.13)*h]),Color("#89999a"))
	elif terrain=="shallow_water":
		for offset in [-0.15,0.18]:
			var c:Vector2=center+Vector2(0,offset*h)
			draw_line(c-Vector2(h*0.28,0),c+Vector2(h*0.28,0),Color("#87c8cd"),1.0)
