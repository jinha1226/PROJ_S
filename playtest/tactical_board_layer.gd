extends Node2D
## Retained ground commands: items, bodies, lights and camera motion cannot
## change terrain identity. Observed data only; no hidden world reads.
var cells:Array=[]
var viewport:=Rect2()
var board_origin:=Vector2i.ZERO
var count:=13

func synchronize(cache:Dictionary,rect:Rect2,origin:Vector2i,cell_count:int,_theme:String="dungeon")->void:
	viewport=rect;board_origin=origin;count=cell_count
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
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
		var tint:=Color(0.30,0.33,0.36,1) if memory else Color(0.72,0.77,0.80,1)
		if not spec.get("is_wall",false):_draw_tile(p,row,spec,tint)
	# Low, opaque faces keep walls readable without covering adjacent actors.
	for row in cells:
		var spec:Dictionary=row.get("tile_spec",{})
		if not spec.get("visible",false) or not spec.get("is_wall",false):continue
		var p:PackedVector2Array=row.polygon
		if p.size()!=4:continue
		var memory:bool=str(row.visibility_state)!="VISIBLE"
		_draw_wall(p,row,spec,Color(0.30,0.33,0.36,1) if memory else Color.WHITE)

func _draw_tile(p:PackedVector2Array,row:Dictionary,spec:Dictionary,tint:Color)->void:
	var texture:Variant=spec.get("texture",null);var rect:=_tile_rect(p)
	if texture is Texture2D:
		var region:Rect2=spec.get("region",Rect2(Vector2.ZERO,texture.get_size()))
		draw_texture_rect_region(texture,rect,region,tint)
	else:_draw_vector_tile(p,str(row.terrain.get("terrain_id","floor")),tint)
	var outline:=PackedVector2Array(p);outline.append(p[0])
	draw_polyline(outline,Color(0.08,0.13,0.17,0.25),1.0)

func _draw_wall(p:PackedVector2Array,row:Dictionary,spec:Dictionary,tint:Color)->void:
	var texture:Variant=spec.get("texture",null)
	if texture is Texture2D:
		var region:Rect2=spec.get("region",Rect2(Vector2.ZERO,texture.get_size()))
		draw_texture_rect_region(texture,_tile_rect(p),region,tint);return
	var memory:bool=str(row.get("visibility_state",""))!="VISIBLE"
	var color:=Color("#46535d") if memory else Color("#77828b")
	draw_colored_polygon(p,color)
	var center:Vector2=(p[0]+p[2])*0.5;var inset:=PackedVector2Array()
	for point in p:inset.append(center+(point-center)*0.80)
	draw_colored_polygon(inset,Color("#1a252d") if memory else Color("#313d46"))

func _tile_rect(p:PackedVector2Array)->Rect2:
	return Rect2(Vector2(p[3].x,p[0].y),Vector2(absf(p[1].x-p[3].x),absf(p[2].y-p[0].y)))

func _draw_vector_tile(p:PackedVector2Array,terrain:String,tint:Color)->void:
	var color:=tint
	if terrain in ["shallow_water","water"]:color=Color("#446f80") if tint.a>0.5 else Color("#263d4a")
	elif terrain=="rubble":color=Color("#667078") if tint.a>0.5 else Color("#3a434a")
	else:color=Color("#596168") if tint.a>0.5 else Color("#323941")
	draw_colored_polygon(p,color)

func _detail(row:Dictionary,p:PackedVector2Array)->void:
	var terrain:String=str(row.terrain.get("terrain_id",""))
	var center:Vector2=(p[0]+p[2])*0.5
	var h:=absf(p[1].x-p[0].x)
	if terrain=="rubble":
		for offset in [Vector2(-0.35,0.02),Vector2(0.2,0.12),Vector2(0.04,-0.2)]:
			var c:Vector2=center+offset*h
			draw_colored_polygon(PackedVector2Array([c+Vector2(-0.2,0.06)*h,c+Vector2(-0.1,-0.18)*h,c+Vector2(0.17,-0.08)*h,c+Vector2(0.2,0.13)*h]),Color("#89999a"))
	elif terrain=="shallow_water":
		for offset in [-0.15,0.18]:
			var c:Vector2=center+Vector2(0,offset*h)
			draw_line(c-Vector2(h*0.28,0),c+Vector2(h*0.28,0),Color("#87c8cd"),1.0)
