extends Node2D
## Presentation-only retained canvas commands. World-anchored chunks survive
## camera movement; only changed tile imagery/visibility rebuilds a chunk.
const CHUNK_SIZE:=4
const Perf=preload("res://sim/perf_probe.gd")
var chunks:Dictionary={}
var rebuild_count:=0
var background:=Rect2()
var substrate:=Color.BLACK
var void_color:=Color.BLACK
var void_rects:Array[Rect2]=[]
var camera_offset:=Vector2.ZERO
var world_offset:=Vector2.ZERO
var tile_size:=0.0
var has_fallback:=false

class TerrainChunk extends Node2D:
	var tiles:Array=[]
	var signature:Array=[]
	var cell_size:=0.0
	func _draw()->void:
		var begun:=Perf.begin()
		for tile in tiles:
			var rect:=Rect2(Vector2(tile.local)*cell_size,Vector2.ONE*cell_size)
			var spec:Dictionary=tile.spec
			var visible_cell:=str(spec.visibility_state)=="VISIBLE"
			if str(spec.get("asset_family",""))=="KENNEY_TINY_DUNGEON":
				var tint:Color=spec.get("tint",Color.WHITE)
				if not visible_cell:tint*=Color(0.30,0.32,0.35,0.55)
				draw_texture_rect_region(spec.texture,rect.grow(0.2),spec.region,tint)
				continue
			var modulate_color:=Color(0.78,0.82,0.84,0.84) if visible_cell else Color(0.30,0.32,0.33,0.42)
			if bool(spec.is_wall):
				draw_rect(rect.grow(0.35),Color("#151d26") if visible_cell else Color("#101419"))
				modulate_color=Color(0.48,0.56,0.66,1.0) if visible_cell else Color(0.21,0.25,0.30,0.7)
			draw_texture_rect_region(spec.texture,rect.grow(0.35),spec.region,modulate_color)
			if bool(spec.is_wall):
				draw_rect(rect.grow(-1.0),Color("#0b111a"),false,maxf(2.0,cell_size*0.08))
				draw_line(rect.position+Vector2(2,2),rect.position+Vector2(cell_size-2,2),
					Color("#78899b") if visible_cell else Color("#303d49"),maxf(1.0,cell_size*0.04))
		Perf.end("grid.retained_chunks",begun)

func synchronize(cache:Dictionary,rect:Rect2,origin:Vector2i,cell_size:float,
		palette:Dictionary)->void:
	background=rect;substrate=Color(str(palette.get("substrate_hex","#091017")))
	void_color=Color(str(palette.get("void_hex","#010203")))
	world_offset=rect.position-Vector2(origin)*cell_size;tile_size=cell_size
	void_rects.clear()
	has_fallback=false
	var grouped:Dictionary={}
	for cell in cache.values():
		if str(cell.get("visibility_state",""))=="VOID":
			void_rects.append(cell.rect)
		var spec:Dictionary=cell.get("tile_spec",{})
		if not bool(spec.get("visible",false)) or spec.get("texture")==null:
			if str(cell.get("visibility_state","")) in ["VISIBLE","MEMORY"]:has_fallback=true
			continue
		var p:Vector2i=cell.position
		var chunk_key:=Vector2i(floori(float(p.x)/CHUNK_SIZE),floori(float(p.y)/CHUNK_SIZE))
		if not grouped.has(chunk_key):grouped[chunk_key]=[]
		grouped[chunk_key].append({"local":p-chunk_key*CHUNK_SIZE,"spec":spec})
	for key in chunks.keys():
		if grouped.has(key):continue
		var removed:Node=chunks[key]
		remove_child(removed);removed.queue_free();chunks.erase(key)
	for key in grouped:
		var tiles:Array=grouped[key]
		# Explicit visual dependencies: actor HP, items, light and hazards do not
		# invalidate the tile atlas commands. No probabilistic hash collisions.
		var signature:Array=[cell_size]
		for tile in tiles:
			var spec:Dictionary=tile.spec
			signature.append([tile.local,spec.texture,spec.region,spec.is_wall,spec.visibility_state,spec.get("tint",Color.WHITE)])
		if not chunks.has(key):
			var fresh:=TerrainChunk.new();add_child(fresh);chunks[key]=fresh
		var chunk:TerrainChunk=chunks[key]
		if chunk.signature!=signature:
			chunk.signature=signature;chunk.tiles=tiles;chunk.cell_size=cell_size
			chunk.queue_redraw();rebuild_count+=1
		chunk.position=world_offset+Vector2(key*CHUNK_SIZE)*tile_size+camera_offset
	queue_redraw()

func set_camera_offset(offset:Vector2)->void:
	if camera_offset==offset:return
	camera_offset=offset
	for key in chunks:
		chunks[key].position=world_offset+Vector2(key*CHUNK_SIZE)*tile_size+camera_offset
	queue_redraw()

func _draw()->void:
	var begun:=Perf.begin()
	draw_rect(background,substrate)
	draw_set_transform(camera_offset)
	for rect in void_rects:draw_rect(rect,void_color)
	Perf.end("grid.retained_background",begun)
