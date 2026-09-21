extends RefCounted
const SHEET = preload("res://assets/mobile/ui-atlas.png")
const ACTORS = [preload("res://assets/mobile/human.png"),preload("res://assets/mobile/dwarf.png"),preload("res://assets/mobile/elf.png")]
const ENEMY = preload("res://assets/mobile/kobold.png")
const BOSS = preload("res://assets/mobile/fire_lizard.png")
const STONE = preload("res://assets/mobile/stone_floor_a.png")
const WOOD = preload("res://assets/mobile/wood_floor.png")
const WATER = preload("res://assets/mobile/water.png")
const TOPDOWN = [preload("res://assets/topdown/floor1_atlas_16x1_16.png"),preload("res://assets/topdown/floor2_atlas_16x1_16.png")]
static var terrain_cache: Dictionary = {}

static func terrain(cell: Dictionary) -> AtlasTexture:
	var palette: int = cell.get("palette",0)
	var index: int = {"stone":[0,2,3][cell.get("variant",0)],"wood":4,"water":7,"metal":5,"wall":9}.get(cell.terrain,0)
	var key := palette*16+index
	if not terrain_cache.has(key):
		var texture := AtlasTexture.new(); texture.atlas = TOPDOWN[palette]
		texture.region = Rect2(index*16,0,16,16); texture.filter_clip = true
		terrain_cache[key] = texture
	return terrain_cache[key]

static func region(rect: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new(); texture.atlas = SHEET; texture.region = rect
	texture.filter_clip = true
	return texture

static func portrait(index: int) -> AtlasTexture:
	return region(Rect2([43,344,645][index],1254,245,88))

static func skill(index: int) -> AtlasTexture:
	return region(Rect2([48,180,347,480,647,780][index],1156,105,78))

static func item(index: int) -> AtlasTexture:
	return region(Rect2([43,187,333,478,624,771][index],1424,109,78))

static func navigation(index: int) -> AtlasTexture:
	return region(Rect2([93,315,546,777][index],1560,60,49))
