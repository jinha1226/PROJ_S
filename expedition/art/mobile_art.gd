extends RefCounted
const SHEET = preload("res://assets/mobile/ui-atlas.png")
## Paper-doll sprites, south facing, one PNG per look (tools/art/build_game_sprites.py).
## ACTOR_SPRITES follows ACTOR_IDS, MONSTER_SPRITES follows MONSTER_IDS, and
## BOSS_SPRITES follows a boss's `pattern`: mire, bomber, giant.
const ACTOR_SPRITES := [preload("res://assets/sprites-v1/actors/human.png"),preload("res://assets/sprites-v1/actors/dwarf.png"),
	preload("res://assets/sprites-v1/actors/elf.png"),preload("res://assets/sprites-v1/actors/orc.png"),
	preload("res://assets/sprites-v1/actors/wolf.png"),preload("res://assets/sprites-v1/actors/mage.png"),
	preload("res://assets/sprites-v1/actors/merchant.png"),preload("res://assets/sprites-v1/actors/wanderer.png")]
const MONSTER_SPRITES := [preload("res://assets/sprites-v1/monsters/dcss_rat.png"),preload("res://assets/sprites-v1/monsters/dcss_frilled_lizard.png"),
	preload("res://assets/sprites-v1/monsters/kobold.png"),preload("res://assets/sprites-v1/monsters/goblin.png"),
	preload("res://assets/sprites-v1/monsters/dcss_hobgoblin.png"),preload("res://assets/sprites-v1/monsters/dcss_orc.png"),
	preload("res://assets/sprites-v1/monsters/dcss_gnoll.png"),preload("res://assets/sprites-v1/monsters/dcss_river_rat.png")]
const BOSS_SPRITES := [preload("res://assets/sprites-v1/bosses/boss_mire.png"),preload("res://assets/sprites-v1/bosses/boss_bomber.png"),
	preload("res://assets/sprites-v1/bosses/boss_giant.png")]
## Potion flasks in `consumables.json` `appearances.potion` order, and the
## effect badges that sit on a flask's lower-right corner (tools/art/build_potions.py).
const POTION_LOOKS := [preload("res://assets/items-v1/potions/red.png"),preload("res://assets/items-v1/potions/blue.png"),
	preload("res://assets/items-v1/potions/green.png"),preload("res://assets/items-v1/potions/amber.png"),
	preload("res://assets/items-v1/potions/purple.png"),preload("res://assets/items-v1/potions/silver.png"),
	preload("res://assets/items-v1/potions/black.png"),preload("res://assets/items-v1/potions/white.png"),
	preload("res://assets/items-v1/potions/murky.png"),preload("res://assets/items-v1/potions/golden.png")]
const POTION_BADGES := {"healing":preload("res://assets/items-v1/potion-effects-badge/healing.png"),
	"strength":preload("res://assets/items-v1/potion-effects-badge/strength.png"),
	"haste":preload("res://assets/items-v1/potion-effects-badge/haste.png"),
	"liquid_flame":preload("res://assets/items-v1/potion-effects-badge/liquid_flame.png"),
	"frost":preload("res://assets/items-v1/potion-effects-badge/frost.png"),
	"toxic_gas":preload("res://assets/items-v1/potion-effects-badge/toxic_gas.png"),
	"experience":preload("res://assets/items-v1/potion-effects-badge/experience.png"),
	"calm":preload("res://assets/items-v1/potion-effects-badge/calm.png"),
	"unknown":preload("res://assets/items-v1/potion-effects-badge/unknown.png")}
## Scrolls in `appearances.scroll` order and their effect badges; an unknown
## scroll wears the same question mark as an unknown potion (tools/art/build_gear.py).
const SCROLL_LOOKS := [preload("res://assets/items-v1/scrolls/zelgo_mer.png"),preload("res://assets/items-v1/scrolls/kirje.png"),preload("res://assets/items-v1/scrolls/andova.png"),preload("res://assets/items-v1/scrolls/pratyav.png"),preload("res://assets/items-v1/scrolls/venzar.png"),preload("res://assets/items-v1/scrolls/nafa.png"),preload("res://assets/items-v1/scrolls/temov.png"),preload("res://assets/items-v1/scrolls/gari.png"),preload("res://assets/items-v1/scrolls/lomas.png"),preload("res://assets/items-v1/scrolls/xixaxa.png")]
const SCROLL_BADGES := {"identify":preload("res://assets/items-v1/scroll-effects-badge/identify.png"),"upgrade":preload("res://assets/items-v1/scroll-effects-badge/upgrade.png"),"magic_mapping":preload("res://assets/items-v1/scroll-effects-badge/magic_mapping.png"),"teleportation":preload("res://assets/items-v1/scroll-effects-badge/teleportation.png"),"mirror_image":preload("res://assets/items-v1/scroll-effects-badge/mirror_image.png"),"lullaby":preload("res://assets/items-v1/scroll-effects-badge/lullaby.png"),"rage":preload("res://assets/items-v1/scroll-effects-badge/rage.png"),"recharging":preload("res://assets/items-v1/scroll-effects-badge/recharging.png")}
## Gear by combat.json id: every weapon, armour and ring has its own picture.
const WEAPON_ICONS := {"sword":preload("res://assets/items-v1/gear/weapons/sword.png"),"dagger":preload("res://assets/items-v1/gear/weapons/dagger.png"),"spear":preload("res://assets/items-v1/gear/weapons/spear.png"),"mace":preload("res://assets/items-v1/gear/weapons/mace.png"),"axe":preload("res://assets/items-v1/gear/weapons/axe.png"),"bow":preload("res://assets/items-v1/gear/weapons/bow.png"),"staff":preload("res://assets/items-v1/gear/weapons/staff.png")}
const ARMOUR_ICONS := {"robe":preload("res://assets/items-v1/gear/armours/robe.png"),"leather":preload("res://assets/items-v1/gear/armours/leather.png"),"mail":preload("res://assets/items-v1/gear/armours/mail.png"),"plate":preload("res://assets/items-v1/gear/armours/plate.png")}
const RING_ICONS := {"fire":preload("res://assets/items-v1/gear/rings/fire.png"),"ice":preload("res://assets/items-v1/gear/rings/ice.png"),"poison":preload("res://assets/items-v1/gear/rings/poison.png"),"air":preload("res://assets/items-v1/gear/rings/air.png"),"power":preload("res://assets/items-v1/gear/rings/power.png"),"ev":preload("res://assets/items-v1/gear/rings/ev.png")}
const SHIELD_ICON := preload("res://assets/items-v1/gear/shield.png")
const BOOK_ICON := preload("res://assets/items-v1/gear/book.png")
## A badge covers this share of its flask's side.
const BADGE_SHARE := 0.55
## Where the figure stands inside a paper-doll PNG, as fractions of its side:
## feet on FEET_Y, and the head and shoulders inside PORTRAIT for cards.
const FEET_Y := 55.0/64.0
const PORTRAIT := Rect2(0.2,0.1,0.6,0.62)
const MASTERY_SHEET = preload("res://assets/8bit/classic/mastery-icons.png")
const SPELL_SHEET = preload("res://assets/8bit/classic/spell-icons.png")
const TIER_SHEETS = [preload("res://assets/8bit/classic/spells-fire.png"),preload("res://assets/8bit/classic/spells-ice.png"),preload("res://assets/8bit/classic/spells-air.png"),preload("res://assets/8bit/classic/spells-hex.png"),preload("res://assets/8bit/classic/spells-summon.png")]
const MAGIC_SCHOOLS := ["fire","ice","air","hex","summon"]
const ITEM_SHEET = preload("res://assets/topdown/flat-v1/items.png")
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
const ACTION_ICONS = preload("res://assets/topdown/flat-v1/action-icons.png")
const UI_BUTTON_FRAMES = preload("res://assets/ui/button-frames-flat-v1.png")
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

## A whole sprite as an AtlasTexture, so callers keep one texture type.
static func whole(sheet: Texture2D, key: String) -> AtlasTexture:
	if not pixel_cache.has(key):
		var texture := AtlasTexture.new()
		texture.atlas = sheet
		texture.region = Rect2(Vector2.ZERO,sheet.get_size())
		texture.filter_clip = true
		pixel_cache[key] = texture
	return pixel_cache[key]

static func actor_texture(index: int) -> AtlasTexture:
	index = posmod(index,ACTOR_IDS.size())
	return whole(ACTOR_SPRITES[index],"actor/"+str(index))

static func actor_index(actor: Dictionary) -> int:
	var id := int(actor.get("id",0))
	return 1+posmod(id-1000,ACTOR_IDS.size()-1) if bool(actor.get("npc",false)) and id >= 1000 else posmod(id,ACTOR_IDS.size())

static func actor_portrait(actor: Dictionary) -> AtlasTexture:
	var index := actor_index(actor)
	var key := "actor/portrait/"+str(index)
	if not pixel_cache.has(key):
		var sheet: Texture2D = ACTOR_SPRITES[index]
		var size := Vector2(sheet.get_size())
		var texture := AtlasTexture.new()
		texture.atlas = sheet
		texture.region = Rect2(PORTRAIT.position*size,PORTRAIT.size*size)
		texture.filter_clip = true
		pixel_cache[key] = texture
	return pixel_cache[key]

static func enemy_sprite(species_id: String) -> AtlasTexture:
	var index := MONSTER_IDS.find(species_id)
	if index < 0: index = MONSTER_IDS.find("kobold")
	return whole(MONSTER_SPRITES[index],"monster/"+str(index))

static func boss_sprite(pattern: int) -> AtlasTexture:
	var index := posmod(pattern,BOSS_SPRITES.size())
	return whole(BOSS_SPRITES[index],"boss/"+str(index))

## A paper-doll sprite drawn `scale` tiles wide, centred on the tile, feet on
## the tile's lower edge so a figure stands in its cell and rises above it.
static func paint_standing(canvas: CanvasItem, texture: Texture2D, rect: Rect2, scale: float, tint: Color) -> void:
	var extent := rect.size*scale
	var feet := rect.end.y-rect.size.y*0.08
	var display := Rect2(Vector2(rect.get_center().x-extent.x*0.5,feet-extent.y*FEET_Y),extent)
	canvas.draw_texture_rect(texture,display,false,tint)

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

## The picture for a piece of gear: `slot` is weapon / armour / shield / ring
## (or book, scroll) and `kind` the combat.json id. Unknown ids fall back to
## the plainest piece of their slot.
static func equipment_icon(slot: String, kind: String = "") -> AtlasTexture:
	match slot:
		"weapon": return whole(WEAPON_ICONS.get(kind,WEAPON_ICONS.sword),"gear/weapon/"+kind)
		"armour": return whole(ARMOUR_ICONS.get(kind,ARMOUR_ICONS.leather),"gear/armour/"+kind)
		"ring": return whole(RING_ICONS.get(kind,RING_ICONS.power),"gear/ring/"+kind)
		"shield": return whole(SHIELD_ICON,"gear/shield")
		"book": return whole(BOOK_ICON,"gear/book")
		"scroll": return scroll_icon(0)
	return whole(WEAPON_ICONS.sword,"gear/weapon/sword")

static func scroll_icon(look: int) -> AtlasTexture:
	var index := posmod(look,SCROLL_LOOKS.size())
	return whole(SCROLL_LOOKS[index],"scroll/"+str(index))

## A potion or scroll's look, whichever class the kind is.
static func item_icon(item_class: String, look: int) -> AtlasTexture:
	return potion_icon(look) if item_class == "potion" else scroll_icon(look)

## The effect badge for any potion or scroll kind, or the question mark until known.
static func item_badge(kind: String, known: bool) -> Texture2D:
	if not known: return POTION_BADGES.unknown
	return POTION_BADGES.get(kind,SCROLL_BADGES.get(kind,POTION_BADGES.unknown))

static func consumable_icon(kind: String) -> AtlasTexture:
	return pixel_region(ITEM_SHEET,4,4,11 if kind == "scroll" else 12,"flat/consumable/"+kind)

static func potion_icon(look: int) -> AtlasTexture:
	var index := posmod(look,POTION_LOOKS.size())
	return whole(POTION_LOOKS[index],"potion/"+str(index))

## The effect badge for a potion kind, or the question mark until it is known.
static func potion_badge(kind: String, known: bool) -> Texture2D:
	return POTION_BADGES.get(kind if known else "unknown",POTION_BADGES.unknown)

## The badge's square inside a flask drawn in `rect`: its lower-right corner,
## lifted by `lift` so a count label along the bottom edge stays readable.
static func badge_rect(rect: Rect2, lift: float = 0.0) -> Rect2:
	var side := minf(rect.size.x,rect.size.y)*BADGE_SHARE
	return Rect2(rect.end-Vector2(side,side+lift)+Vector2(side*0.06,side*0.04),Vector2.ONE*side)

static func paint_potion(canvas: CanvasItem, rect: Rect2, look: int, badge: Texture2D = null, tint: Color = Color.WHITE) -> void:
	paint_item(canvas,rect,potion_icon(look),badge,tint)

## A potion or scroll picture with its badge on the lower-right corner.
static func paint_item(canvas: CanvasItem, rect: Rect2, texture: Texture2D, badge: Texture2D = null, tint: Color = Color.WHITE) -> void:
	canvas.draw_texture_rect(texture,rect,false,tint)
	if badge != null: canvas.draw_texture_rect(badge,badge_rect(rect),false,tint)

static func food_icon() -> AtlasTexture:
	return pixel_region(ITEM_SHEET,4,4,13,"flat/item/food")

static func paint_actor(canvas: CanvasItem, index: int, rect: Rect2, tint: Color = Color.WHITE) -> void:
	paint_standing(canvas,actor_texture(index),rect,2.2,tint)

static func paint_monster(canvas: CanvasItem, species_id: String, rect: Rect2, tint: Color = Color.WHITE) -> void:
	paint_standing(canvas,enemy_sprite(species_id),rect,2.2,tint)

static func paint_boss(canvas: CanvasItem, rect: Rect2, tint: Color = Color.WHITE, pattern: int = 0) -> void:
	paint_standing(canvas,boss_sprite(pattern),rect,3.0,tint)

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

static func part_icon(id: String) -> AtlasTexture:
	var icons := {"PUSH":10,"GUARD":10,"BOMB":12,"IRON_HIDE":8,
		"THROWING_KNIFE":1,"KOBOLD_SLING":5,"GOBLIN_SHIV":1,
		"HOB_CLUB":3,"ORC_CLEAVER":4,"GNOLL_SPEAR":2}
	var index: int = int(icons.get(id,14))
	return pixel_region(ITEM_SHEET,4,4,index,"flat/part/"+id)

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
	if index >= 0 and index < 6:
		return pixel_region(ACTION_ICONS,3,2,index,"flat/action/"+str(index))
	return ui_region(posmod(index,6),index/6)

## Precise 48px frames built for the flat UI and sized for nine-slice.
static func ui_frame(state: int) -> Texture2D:
	state = clampi(state,0,5)
	if ui_frame_cache.has(state): return ui_frame_cache[state]
	var texture := AtlasTexture.new()
	texture.atlas = UI_BUTTON_FRAMES
	texture.region = Rect2(state*48,0,48,48)
	texture.filter_clip = true
	ui_frame_cache[state] = texture
	return ui_frame_cache[state]
