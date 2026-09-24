extends RefCounted
const SHEET = preload("res://assets/mobile/ui-atlas.png")
const ACTORS = [preload("res://assets/mobile/human.png"),preload("res://assets/mobile/dwarf.png"),preload("res://assets/mobile/elf.png")]
const InkTorso = preload("res://expedition/art/ink_torso_art.gd")
const ENEMY = preload("res://assets/mobile/kobold.png")
const BOSS = preload("res://assets/mobile/fire_lizard.png")
const STONE = preload("res://assets/mobile/stone_floor_a.png")
const WOOD = preload("res://assets/mobile/wood_floor.png")
const WATER = preload("res://assets/mobile/water.png")
const TOPDOWN = [preload("res://assets/topdown/floor1_atlas_16x1_16.png"),preload("res://assets/topdown/floor2_atlas_16x1_16.png")]
const Masonry = preload("res://expedition/art/masonry_tiles.gd")
const FirstFloor = preload("res://expedition/art/floor1_art.gd")
const FLAGSTONE = preload("res://assets/topdown/flagstone-floor-v1.png")
const UI_ATLAS_8BIT = preload("res://assets/ui/ui-atlas-8bit-v1.png")
const UI_CELL := 256
static var terrain_cache: Dictionary = {}

static func paint_actor(canvas: CanvasItem, index: int, rect: Rect2, tint: Color = Color.WHITE) -> void:
	# Keep the lower edge anchored while allowing the head above the movement cell.
	# The layered human has more transparent canvas padding than the legacy pawns.
	var extent := rect.size*(1.92 if index == 0 else 1.67)
	var display := Rect2(rect.position+Vector2((rect.size.x-extent.x)*0.5,rect.size.y-extent.y),extent)
	if index == 0:
		InkTorso.paint(canvas,display,tint)
	else:
		canvas.draw_texture_rect(ACTORS[index],display,false,tint)

static func terrain(cell: Dictionary, point: Vector2i = Vector2i.ZERO, first_floor: bool = false) -> AtlasTexture:
	if first_floor: return FirstFloor.terrain(cell,point)
	if cell.terrain == "stone": return Masonry.floor_tile(point)
	if cell.terrain == "wall": return Masonry.tile(4+posmod(point.x+point.y*3,4))
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

static func portrait_face(index: int) -> AtlasTexture:
	# The full atlas region includes a nameplate and gauges. Character cards
	# draw only the face; their labels and bars come from the current session.
	return region(Rect2([43,344,645][index]+50,1254,100,74))

static func skill(index: int) -> AtlasTexture:
	return region(Rect2([48,180,347,480,647,780][index],1156,105,78))

static func item(index: int) -> AtlasTexture:
	return region(Rect2([43,187,333,478,624,771][index],1424,109,78))

static func navigation(index: int) -> AtlasTexture:
	return region(Rect2([93,315,546,777][index],1560,60,49))

static func ui_region(column: int, row: int) -> AtlasTexture:
	var texture := AtlasTexture.new(); texture.atlas = UI_ATLAS_8BIT
	texture.region = Rect2(column*UI_CELL,row*UI_CELL,UI_CELL,UI_CELL)
	texture.filter_clip = true
	return texture

static func ui_icon(index: int) -> AtlasTexture:
	return ui_region(posmod(index,6),index/6)

static func ui_frame(state: int) -> AtlasTexture:
	return ui_region(clampi(state,0,5),2)
