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
const UI_ROW_BOUNDS := [Vector2i(24,291),Vector2i(292,526),Vector2i(528,728),Vector2i(734,992)]
static var terrain_cache: Dictionary = {}
static var ui_frame_cache: Dictionary = {}

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
	# The generated sheet's artwork crosses the nominal 256px row boundaries.
	# Crop at the actual transparent gaps so one icon never shows its neighbour.
	var bounds: Vector2i = UI_ROW_BOUNDS[clampi(row,0,UI_ROW_BOUNDS.size()-1)]
	texture.region = Rect2(column*UI_CELL,bounds.x,UI_CELL,bounds.y-bounds.x)
	texture.filter_clip = true
	return texture

static func ui_icon(index: int) -> AtlasTexture:
	return ui_region(posmod(index,6),index/6)

## Small, clean source for nine-slice buttons. The atlas's large frame samples
## overlap their cell edges, so using them on 44px buttons clips the corners.
static func ui_frame(state: int) -> Texture2D:
	state = clampi(state,0,5)
	if ui_frame_cache.has(state): return ui_frame_cache[state]
	var borders := [Color("ad8e58"),Color("dcc17e"),Color("7d6848"),Color("595d60"),Color("9e8150"),Color("f0c765")]
	var fills := [Color("1b2530"),Color("263441"),Color("101820"),Color("1b2025"),Color("19222b"),Color("263039")]
	var image := Image.create(24,24,false,Image.FORMAT_RGBA8)
	for y in range(24):
		for x in range(24):
			var edge: int = mini(mini(x,23-x),mini(y,23-y))
			if x < 2 and y < 2 or x > 21 and y < 2 or x < 2 and y > 21 or x > 21 and y > 21:
				image.set_pixel(x,y,Color.TRANSPARENT)
			elif edge == 0:
				image.set_pixel(x,y,Color("080c11"))
			elif edge == 1:
				image.set_pixel(x,y,borders[state])
			elif edge == 2:
				image.set_pixel(x,y,borders[state].lightened(0.2) if x == 2 or y == 2 else borders[state].darkened(0.2))
			else:
				image.set_pixel(x,y,fills[state])
	ui_frame_cache[state] = ImageTexture.create_from_image(image)
	return ui_frame_cache[state]
