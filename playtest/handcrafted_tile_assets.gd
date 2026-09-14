extends RefCounted
## Approved HTML atlas, sampled once at native 64px. No per-frame image work.
const SOURCE = preload("res://assets/handcrafted64/fantasy-terrain-pixel64-source.png")
const WALL_SOURCE = preload("res://assets/handcrafted64/dungeon-wall-faces-coarse64.png")
const CENTERS = [151,445,740,1035,1330,1624]
const TOPS = [110,365,638]
static var tiles: Dictionary = {}
static var walls: Dictionary = {}
static var obstacles: Dictionary = {}

static func biome_index(biome: String) -> int:
	return {"dungeon":0,"cave":1,"forest":2}.get(biome,0)

static func variant(position: Vector2i, biome: int) -> int:
	var roll := ((position.x*73856093) ^ (position.y*19349663) ^ ((biome+1)*83492791)) & 0xffffffff
	roll %= 10
	return 0 if roll<5 else 1 if roll<7 else 3 if roll<9 else 2

static func tile(biome: int, column: int) -> Texture2D:
	var key := biome*6+column
	if tiles.has(key): return tiles[key]
	var source: Image = SOURCE.get_image()
	var result := Image.create(64,32,false,Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(64):
			# Diamond top only: never include source background or slab sides.
			if absf((x+0.5-32.0)/32.0)+absf((y+0.5-16.0)/16.0)>1.0: continue
			var sx := int(CENTERS[column]-136+(x+0.5)*272.0/64.0)
			var sy := int(TOPS[biome]+(y+0.5)*150.0/32.0)
			result.set_pixel(x,y,source.get_pixel(sx,sy))
	tiles[key] = ImageTexture.create_from_image(result)
	return tiles[key]

static func wall(column: int) -> Texture2D:
	if walls.has(column): return walls[column]
	var source: Image = WALL_SOURCE.get_image()
	var width := source.get_width()/4
	var face := source.get_region(Rect2i(column*width,0,width,source.get_height()))
	face.resize(32,48,Image.INTERPOLATE_NEAREST)
	walls[column] = ImageTexture.create_from_image(face)
	return walls[column]

static func obstacle(biome: int) -> Texture2D:
	if obstacles.has(biome): return obstacles[biome]
	var source:Image=SOURCE.get_image()
	var result:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	var source_top:int=[48,320,552][biome]
	for y in range(64):
		for x in range(64):
			if y>=48 and absf(x+0.5-32.0)>(64-y-0.5)*2:continue
			var sy:=int(TOPS[biome]+(y+0.5-32)*150.0/32.0)
			if sy<source_top:continue
			var sx:=int(CENTERS[4]-136+(x+0.5)*272.0/64.0)
			result.set_pixel(x,y,source.get_pixel(sx,sy))
	obstacles[biome]=ImageTexture.create_from_image(result)
	return obstacles[biome]
