extends RefCounted
const SHEET = preload("res://assets/mobile/ui-atlas.png")
const ACTOR_SHEET = preload("res://assets/8bit/classic/actors.png")
const MONSTER_SHEET = preload("res://assets/8bit/classic/monsters.png")
const MASTERY_SHEET = preload("res://assets/8bit/classic/mastery-icons.png")
const SPELL_SHEET = preload("res://assets/8bit/classic/spell-icons.png")
const TIER_SHEETS = [preload("res://assets/8bit/classic/spells-fire.png"),preload("res://assets/8bit/classic/spells-ice.png"),preload("res://assets/8bit/classic/spells-air.png"),preload("res://assets/8bit/classic/spells-hex.png"),preload("res://assets/8bit/classic/spells-summon.png")]
const MAGIC_SCHOOLS := ["fire","ice","air","hex","summon"]
const EQUIPMENT_SHEET = preload("res://assets/8bit/classic/equipment-icons.png")
const BOSS = preload("res://assets/8bit/classic/fire-lizard-boss.png")
const ACTOR_IDS := ["human","dwarf","elf","orc","wolf","mage","merchant","wanderer"]
const MONSTER_IDS := ["dcss_rat","dcss_frilled_lizard","kobold","goblin","dcss_hobgoblin","dcss_orc","dcss_gnoll","dcss_river_rat"]
const MASTERY_IDS := ["sword","spear","mace","axe","bow","fire","ice","air","hex","summon"]
const SPELL_IDS := ["bolt","blast","cone","cloud","confuse","blink","passwall","ward","hound","turret","ignite","mend"]
const EQUIPMENT_IDS := ["sword","dagger","spear","mace","axe","bow","staff","armour","shield","ring","book","scroll"]
const STONE = preload("res://assets/mobile/stone_floor_a.png")
const WOOD = preload("res://assets/mobile/wood_floor.png")
const WATER = preload("res://assets/mobile/water.png")
const TOPDOWN = [preload("res://assets/topdown/floor1_atlas_16x1_16.png"),preload("res://assets/topdown/floor2_atlas_16x1_16.png")]
const Masonry = preload("res://expedition/art/masonry_tiles.gd")
const FirstFloor = preload("res://expedition/art/floor1_art.gd")
const FLAGSTONE = preload("res://assets/topdown/flagstone-floor-v1.png")
const UI_ATLAS_8BIT = preload("res://assets/ui/ui-atlas-8bit-v1.png")
const UI_BUTTON_FRAMES = preload("res://assets/ui/button-frames-8bit-v2.png")
const UI_CELL := 256
const UI_ROW_BOUNDS := [Vector2i(24,291),Vector2i(292,526),Vector2i(528,728),Vector2i(734,992)]
static var terrain_cache: Dictionary = {}
static var ui_frame_cache: Dictionary = {}
static var pixel_cache: Dictionary = {}

static func pixel_region(sheet: Texture2D, columns: int, rows: int, index: int, key: String) -> AtlasTexture:
	if not pixel_cache.has(key):
		var column := index % columns
		var row := index / columns
		var x0 := floori(float(column*sheet.get_width())/columns)
		var x1 := floori(float((column+1)*sheet.get_width())/columns)
		var y0 := floori(float(row*sheet.get_height())/rows)
		var y1 := floori(float((row+1)*sheet.get_height())/rows)
		var texture := AtlasTexture.new()
		texture.atlas = sheet
		texture.region = Rect2(x0,y0,x1-x0,y1-y0)
		texture.filter_clip = true
		pixel_cache[key] = texture
	return pixel_cache[key]

static func actor_texture(index: int) -> AtlasTexture:
	index = posmod(index,ACTOR_IDS.size())
	return pixel_region(ACTOR_SHEET,4,2,index,"actor/"+str(index))

static func enemy_sprite(species_id: String) -> AtlasTexture:
	var index := MONSTER_IDS.find(species_id)
	if index < 0: index = MONSTER_IDS.find("kobold")
	return pixel_region(MONSTER_SHEET,4,2,index,"monster/"+str(index))

static func mastery_icon(axis: String) -> AtlasTexture:
	var index := MASTERY_IDS.find(axis)
	return pixel_region(MASTERY_SHEET,5,2,maxi(0,index),"mastery/"+str(index))

static func spell_icon(id: String) -> AtlasTexture:
	for school in range(MAGIC_SCHOOLS.size()):
		if id.begins_with(MAGIC_SCHOOLS[school]+"_"):
			var rank := int(id.get_slice("_",1))
			if rank >= 1 and rank <= 10:
				return pixel_region(TIER_SHEETS[school],5,2,rank-1,"spell/"+id)
	var index := SPELL_IDS.find(id)
	if index < 0:
		index = 0
	return pixel_region(SPELL_SHEET,4,3,index,"spell/"+str(index))

static func equipment_icon(slot: String, kind: String = "") -> AtlasTexture:
	var id: String = kind if slot == "weapon" else "armour" if slot == "armour" else slot
	var index := EQUIPMENT_IDS.find(id)
	return pixel_region(EQUIPMENT_SHEET,4,3,maxi(0,index),"equipment/"+str(index))

static func paint_actor(canvas: CanvasItem, index: int, rect: Rect2, tint: Color = Color.WHITE) -> void:
	# All eight sprites share a baseline; let the character rise above its cell.
	var extent := rect.size*1.92
	var display := Rect2(rect.position+Vector2((rect.size.x-extent.x)*0.5,rect.size.y-extent.y),extent)
	canvas.draw_texture_rect(actor_texture(index),display,false,tint)

static func terrain(cell: Dictionary, point: Vector2i = Vector2i.ZERO, theme_id: String = "") -> AtlasTexture:
	if theme_id in ["F1_RUINS","F2_MINES"]: return FirstFloor.terrain(cell,point,theme_id)
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
	return actor_texture(index)

static func portrait_face(index: int) -> AtlasTexture:
	return actor_texture(index)

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

## Frames extracted from row 3 of the 8-bit UI artwork and sized for 9-slice.
static func ui_frame(state: int) -> Texture2D:
	state = clampi(state,0,5)
	if ui_frame_cache.has(state): return ui_frame_cache[state]
	var texture := AtlasTexture.new()
	texture.atlas = UI_BUTTON_FRAMES
	texture.region = Rect2(state*48,0,48,48)
	texture.filter_clip = true
	ui_frame_cache[state] = texture
	return ui_frame_cache[state]
