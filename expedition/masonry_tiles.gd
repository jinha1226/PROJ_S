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

static func paint_wall(canvas: CanvasItem, rect: Rect2, point: Vector2i, is_wall: Callable) -> void:
	var mask := exposed(point,is_wall)
	var front := (mask & SOUTH) != 0
	var face := 0 if front else 1 if mask & EAST else 2 if mask & WEST else 3
	# Raise the back edge only into solid wall space; never cover a walkable cell.
	var raised := rect
	if front and is_wall.call(point+Vector2i.UP):
		raised.position.y -= rect.size.y*0.30
		raised.size.y += rect.size.y*0.30
	canvas.draw_texture_rect(wall_tile(face),raised,false,Color.WHITE if face != 3 else Color(0.52,0.55,0.60))
	# Narrow exposed side ends preserve vertical coping at outside corners.
	if front and mask & EAST:
		var strip := Rect2(rect.position+Vector2(rect.size.x*0.80,0),Vector2(rect.size.x*0.20,rect.size.y))
		canvas.draw_texture_rect_region(WALLS,strip,Rect2(Vector2(WALLS.get_width()*0.5,0),Vector2(WALLS.get_width()*0.10,WALLS.get_height()*0.5)))
	if front and mask & WEST:
		var strip := Rect2(rect.position,Vector2(rect.size.x*0.20,rect.size.y))
		canvas.draw_texture_rect_region(WALLS,strip,Rect2(Vector2(WALLS.get_width()*0.40,WALLS.get_height()*0.5),Vector2(WALLS.get_width()*0.10,WALLS.get_height()*0.5)))
	var rim := maxf(1,rect.size.x*0.07)
	var shade := Color("101114")
	var highlight := Color("5a5650")
	# Edge treatment is shared, so junctions never depend on AI-generated corners.
	if mask & NORTH:
		canvas.draw_rect(Rect2(rect.position,Vector2(rect.size.x,rim)),highlight)
		canvas.draw_line(rect.position+Vector2(0,rim),rect.position+Vector2(rect.size.x,rim),shade,1)
	if mask & WEST:
		canvas.draw_rect(Rect2(rect.position,Vector2(rim,rect.size.y)),highlight)
		canvas.draw_line(rect.position+Vector2(rim,0),rect.position+Vector2(rim,rect.size.y),shade,1)
	if mask & EAST: canvas.draw_rect(Rect2(rect.position+Vector2(rect.size.x-rim,0),Vector2(rim,rect.size.y)),shade)
	if mask & SOUTH: canvas.draw_rect(Rect2(rect.position+Vector2(0,rect.size.y-rim),Vector2(rect.size.x,rim)),shade)
	# Concave junctions: two connected walls with an open diagonal.
	for corner in range(4):
		var a: Vector2i = [Vector2i.UP,Vector2i.UP,Vector2i.DOWN,Vector2i.DOWN][corner]
		var b: Vector2i = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.RIGHT,Vector2i.LEFT][corner]
		if is_wall.call(point+a) and is_wall.call(point+b) and not is_wall.call(point+a+b):
			var offset := Vector2(0 if b.x < 0 else rect.size.x-rim,0 if a.y < 0 else rect.size.y-rim)
			canvas.draw_rect(Rect2(rect.position+offset,Vector2.ONE*rim),highlight if corner == 0 else shade)

static func paint_floor_shadow(canvas: CanvasItem, rect: Rect2, point: Vector2i, is_wall: Callable) -> void:
	# Shadows stay inside the walkable cell; they never change collision or hide actors.
	var band := maxf(1,rect.size.x*0.10)
	if is_wall.call(point+Vector2i.UP):
		canvas.draw_rect(Rect2(rect.position,Vector2(rect.size.x,band)),Color(0,0,0,0.35))
	if is_wall.call(point+Vector2i.LEFT):
		canvas.draw_rect(Rect2(rect.position,Vector2(band,rect.size.y)),Color(0,0,0,0.20))
