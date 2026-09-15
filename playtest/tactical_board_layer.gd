extends Node2D
## Retained ground commands: items, bodies, lights and camera motion cannot
## change terrain identity. Observed data only; no hidden world reads.
var cells:Array=[]
var viewport:=Rect2()
var board_origin:=Vector2i.ZERO
var count:=13
const TacticalProjection=preload("res://playtest/tactical_board_projection.gd")
const Art=preload("res://playtest/handcrafted_tile_assets.gd")
var biome:=0

func synchronize(cache:Dictionary,rect:Rect2,origin:Vector2i,cell_count:int,theme:String="dungeon")->void:
	viewport=rect;board_origin=origin;count=cell_count
	biome=Art.biome_index(theme)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	# Warm bounded caches when terrain changes, not on movement animation frames.
	for column in [0,1,2,3,5]:Art.tile(biome,column)
	Art.wall(0);Art.wall(3)
	if biome!=0:Art.obstacle(biome)
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
		if not spec.get("is_wall",false):
			var terrain:String=str(row.terrain.get("terrain_id",""))
			var column:int=5 if terrain=="shallow_water" else 2 if terrain=="rubble" else Art.variant(row.position,biome)
			_draw_tile(p,Art.tile(biome,column),tint)
			var outline:=PackedVector2Array(p);outline.append(p[0])
			draw_polyline(outline,Color(0.08,0.13,0.17,0.25),1.0)
	# Low, opaque faces keep walls readable without covering adjacent actors.
	for row in cells:
		var spec:Dictionary=row.get("tile_spec",{})
		if not spec.get("visible",false) or not spec.get("is_wall",false):continue
		var p:PackedVector2Array=row.polygon
		if p.size()!=4:continue
		var memory:bool=str(row.visibility_state)!="VISIBLE"
		if biome!=0:
			var width:float=p[1].x-p[3].x
			draw_texture_rect(Art.obstacle(biome),Rect2(Vector2(p[3].x,p[0].y-width*0.5),Vector2(width,width)),false,Color(0.30,0.33,0.36,1) if memory else Color.WHITE)
			continue
		var height:=absf(p[1].x-p[0].x)*0.30
		var lift:=Vector2(0,-height)
		var top:=PackedVector2Array()
		for point in p:top.append(point+lift)
		var shade:=0.32 if memory else 1.0
		var uv:=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
		var face:Texture2D=Art.wall(0)
		draw_polygon(PackedVector2Array([top[3],top[2],p[2],p[3]]),PackedColorArray([Color(0.85*shade,0.88*shade,0.90*shade,1)]),uv,face)
		draw_polygon(PackedVector2Array([top[1],top[2],p[2],p[1]]),PackedColorArray([Color(0.60*shade,0.65*shade,0.70*shade,1)]),uv,face)
		_draw_tile(top,Art.tile(biome,Art.variant(row.position,biome)),Color(shade,shade,shade,1))
		var edge:=PackedVector2Array(top);edge.append(top[0])
		draw_polyline(edge,Color("#99acb5")*shade,1.0)
		draw_line(top[3].lerp(top[2],0.5),p[3].lerp(p[2],0.5),Color("#202d36")*shade,1.0)

func _draw_tile(p:PackedVector2Array,texture:Texture2D,tint:Color)->void:
	# The source is already isometric. Mapping a square's UVs would distort it twice.
	draw_texture_rect(texture,Rect2(Vector2(p[3].x,p[0].y),Vector2(p[1].x-p[3].x,p[2].y-p[0].y)),false,tint)

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
