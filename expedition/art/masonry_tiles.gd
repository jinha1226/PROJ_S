extends RefCounted
## A 32px logical tileset; high-resolution source remains intact for inspection.
const SHEET = preload("res://assets/topdown/dark-masonry-tiles-v1.png")
const WALLS = preload("res://assets/topdown/dark-masonry-walls-v2.png")
const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8
const DIRECTIONS = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
static var cache: Dictionary = {}

static func tile(index: int) -> AtlasTexture:
	if not cache.has(index):
		var result := AtlasTexture.new(); result.atlas = SHEET
		var unit := Vector2(SHEET.get_size())/4.0
		result.region = Rect2(Vector2(index%4,index/4)*unit,unit)
		result.filter_clip = true; cache[index] = result
	return cache[index]

static func wall_tile(index: int) -> AtlasTexture:
	var key := 100+index
	if not cache.has(key):
		var result := AtlasTexture.new(); result.atlas = WALLS
		var unit := Vector2(WALLS.get_size())/2.0
		result.region = Rect2(Vector2(index%2,index/2)*unit,unit)
		result.filter_clip = true; cache[key] = result
	return cache[key]

static func variant(point: Vector2i) -> int:
	# Most floor stones stay quiet; cracks are sparse and deterministic.
	var value := posmod(point.x*73+point.y*151+point.x*point.y*7,19)
	return 0 if value < 12 else 1 if value < 15 else 2 if value < 17 else 3

static func floor_tile(point: Vector2i) -> AtlasTexture:
	return tile(variant(point))

static func exposed(point: Vector2i, is_wall: Callable) -> int:
	var mask := 0
	for i in range(4):
		if not is_wall.call(point+DIRECTIONS[i]): mask |= 1 << i
	return mask

## 0x72-style construction: one raised wall mass, a continuous coping outline,
## and south-facing masonry below it. Side walls are the SAME coping, not facades.
const HEIGHT := 0.72
const COPING := 0.23

static func raised_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position-Vector2(0,rect.size.y*HEIGHT),rect.size)

static func contour_parts(point: Vector2i, is_wall: Callable) -> Array:
	var mask := exposed(point,is_wall)
	var parts: Array = []
	if mask & NORTH: parts.append(Rect2(0,0,1,COPING))
	if mask & EAST: parts.append(Rect2(1-COPING,0,COPING,1))
	if mask & SOUTH: parts.append(Rect2(0,1-COPING,1,COPING))
	if mask & WEST: parts.append(Rect2(0,0,COPING,1))
	for corner in range(4):
		var a: Vector2i = [Vector2i.UP,Vector2i.UP,Vector2i.DOWN,Vector2i.DOWN][corner]
		var b: Vector2i = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.RIGHT,Vector2i.LEFT][corner]
		if is_wall.call(point+a) and is_wall.call(point+b) and not is_wall.call(point+a+b):
			parts.append(Rect2(Vector2(0 if b.x < 0 else 1-COPING,0 if a.y < 0 else 1-COPING),Vector2.ONE*COPING))
	return parts

static func paint_walls(canvas: CanvasItem, cells: Array, is_wall: Callable, material: Dictionary = {}) -> void:
	var front: AtlasTexture = material.get("front",wall_tile(0))
	var top: AtlasTexture = material.get("top",wall_tile(3))
	# Explicit passes prevent a later tile from painting over an earlier corner.
	for cell in cells:
		var rect := raised_rect(cell.rect)
		canvas.draw_texture_rect(top,rect,false,cell.tint)
	for cell in cells:
		if not (exposed(cell.point,is_wall) & SOUTH): continue
		var rect: Rect2 = cell.rect
		var face := Rect2(rect.position+Vector2(0,rect.size.y*(1-HEIGHT)),Vector2(rect.size.x,rect.size.y*HEIGHT))
		var region: Rect2 = front.region
		region.position.y += region.size.y*0.25; region.size.y *= 0.75
		canvas.draw_texture_rect_region(front.atlas,face,region,cell.tint)
		canvas.draw_rect(Rect2(face.position+Vector2(0,face.size.y-1),Vector2(face.size.x,1)),Color("090b0e")*cell.tint)
	for cell in cells:
		var rect := raised_rect(cell.rect)
		for part in contour_parts(cell.point,is_wall):
			var strip := Rect2(rect.position+part.position*rect.size,part.size*rect.size)
			paint_coping(canvas,strip,cell.tint,front)

static func paint_coping(canvas: CanvasItem, rect: Rect2, tint: Color, front: AtlasTexture = null) -> void:
	# Every orientation uses one material sample and the same physical width.
	# Texture UV rotation is in the renderer; no independent vertical art is mixed in.
	if front == null: front = wall_tile(0)
	var source: Rect2 = front.region
	var top_left := source.position+source.size*Vector2(0.035,0.035)
	var extent := source.size*Vector2(0.93,0.13)
	var uv := PackedVector2Array([top_left,top_left+Vector2(extent.x,0),top_left+extent,top_left+Vector2(0,extent.y)])
	for i in range(4): uv[i] /= Vector2(front.atlas.get_size())
	if rect.size.y > rect.size.x:
		uv = PackedVector2Array([uv[3],uv[0],uv[1],uv[2]])
	var points := PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)])
	canvas.draw_polygon(points,PackedColorArray([tint]),uv,front.atlas)

static func paint_floor_shadow(canvas: CanvasItem, rect: Rect2, point: Vector2i, is_wall: Callable) -> void:
	# Shadows stay inside the walkable cell; they never change collision or hide actors.
	var band := maxf(1,rect.size.x*0.10)
	if is_wall.call(point+Vector2i.UP):
		canvas.draw_rect(Rect2(rect.position,Vector2(rect.size.x,band)),Color(0,0,0,0.35))
	if is_wall.call(point+Vector2i.LEFT):
		canvas.draw_rect(Rect2(rect.position,Vector2(band,rect.size.y)),Color(0,0,0,0.20))
