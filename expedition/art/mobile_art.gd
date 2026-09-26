extends RefCounted
const SHEET = preload("res://assets/mobile/ui-atlas.png")
## Paper-doll sprites, south facing, one PNG per look (tools/art/build_game_sprites.py).
## ACTOR_SPRITES follows ACTOR_IDS, MONSTER_SPRITES follows MONSTER_IDS, and
const ACTOR_SPRITES := [preload("res://assets/sprites-v1/actors/human.png"),preload("res://assets/sprites-v1/actors/dwarf.png"),
	preload("res://assets/sprites-v1/actors/elf.png"),preload("res://assets/sprites-v1/actors/orc.png"),
	preload("res://assets/sprites-v1/actors/wolf.png"),preload("res://assets/sprites-v1/actors/mage.png"),
	preload("res://assets/sprites-v1/actors/merchant.png"),preload("res://assets/sprites-v1/actors/wanderer.png")]
const MONSTER_SPRITES := [preload("res://assets/sprites-v1/monsters/dcss_rat.png"),preload("res://assets/sprites-v1/monsters/dcss_frilled_lizard.png"),
	preload("res://assets/sprites-v1/monsters/kobold.png"),preload("res://assets/sprites-v1/monsters/goblin.png"),
	preload("res://assets/sprites-v1/monsters/dcss_hobgoblin.png"),preload("res://assets/sprites-v1/monsters/dcss_orc.png"),
	preload("res://assets/sprites-v1/monsters/dcss_gnoll.png"),preload("res://assets/sprites-v1/monsters/dcss_river_rat.png"),
	preload("res://assets/sprites-v1/monsters/kobold_firecaller.png"),preload("res://assets/sprites-v1/monsters/frost_imp.png"),
	preload("res://assets/sprites-v1/monsters/storm_bat.png"),preload("res://assets/sprites-v1/monsters/goblin_hexer.png"),
	preload("res://assets/sprites-v1/monsters/gnoll_summoner.png"),
	preload("res://assets/sprites-v1/monsters/goblin_archer.png"),preload("res://assets/sprites-v1/monsters/goblin_shield.png"),
	preload("res://assets/sprites-v1/monsters/orc_thrower.png"),preload("res://assets/sprites-v1/monsters/cave_spider.png"),
	preload("res://assets/sprites-v1/monsters/rock_beetle.png"),preload("res://assets/sprites-v1/monsters/ore_golem.png"),
	preload("res://assets/sprites-v1/monsters/giant_leech.png"),preload("res://assets/sprites-v1/monsters/swamp_toad.png"),
	preload("res://assets/sprites-v1/monsters/temple_serpent.png"),preload("res://assets/sprites-v1/monsters/water_spirit.png"),
	preload("res://assets/sprites-v1/monsters/skeleton_soldier.png"),preload("res://assets/sprites-v1/monsters/skeleton_archer.png"),
	preload("res://assets/sprites-v1/monsters/ghoul.png"),preload("res://assets/sprites-v1/monsters/vampire_bat.png"),
	preload("res://assets/sprites-v1/monsters/wraith_knight.png"),preload("res://assets/sprites-v1/monsters/wraith.png"),
	preload("res://assets/sprites-v1/monsters/gravekeeper.png")]
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
## Spell icons: the fifty school spells and the twelve basic ones, each its
## own card in its school's colours (tools/art/build_spells.py).
const SPELL_ICONS := {
	"fire_1":preload("res://assets/items-v1/spells/fire_1.png"),
	"fire_2":preload("res://assets/items-v1/spells/fire_2.png"),
	"fire_3":preload("res://assets/items-v1/spells/fire_3.png"),
	"fire_4":preload("res://assets/items-v1/spells/fire_4.png"),
	"fire_5":preload("res://assets/items-v1/spells/fire_5.png"),
	"fire_6":preload("res://assets/items-v1/spells/fire_6.png"),
	"fire_7":preload("res://assets/items-v1/spells/fire_7.png"),
	"fire_8":preload("res://assets/items-v1/spells/fire_8.png"),
	"fire_9":preload("res://assets/items-v1/spells/fire_9.png"),
	"fire_10":preload("res://assets/items-v1/spells/fire_10.png"),
	"ice_1":preload("res://assets/items-v1/spells/ice_1.png"),
	"ice_2":preload("res://assets/items-v1/spells/ice_2.png"),
	"ice_3":preload("res://assets/items-v1/spells/ice_3.png"),
	"ice_4":preload("res://assets/items-v1/spells/ice_4.png"),
	"ice_5":preload("res://assets/items-v1/spells/ice_5.png"),
	"ice_6":preload("res://assets/items-v1/spells/ice_6.png"),
	"ice_7":preload("res://assets/items-v1/spells/ice_7.png"),
	"ice_8":preload("res://assets/items-v1/spells/ice_8.png"),
	"ice_9":preload("res://assets/items-v1/spells/ice_9.png"),
	"ice_10":preload("res://assets/items-v1/spells/ice_10.png"),
	"air_1":preload("res://assets/items-v1/spells/air_1.png"),
	"air_2":preload("res://assets/items-v1/spells/air_2.png"),
	"air_3":preload("res://assets/items-v1/spells/air_3.png"),
	"air_4":preload("res://assets/items-v1/spells/air_4.png"),
	"air_5":preload("res://assets/items-v1/spells/air_5.png"),
	"air_6":preload("res://assets/items-v1/spells/air_6.png"),
	"air_7":preload("res://assets/items-v1/spells/air_7.png"),
	"air_8":preload("res://assets/items-v1/spells/air_8.png"),
	"air_9":preload("res://assets/items-v1/spells/air_9.png"),
	"air_10":preload("res://assets/items-v1/spells/air_10.png"),
	"hex_1":preload("res://assets/items-v1/spells/hex_1.png"),
	"hex_2":preload("res://assets/items-v1/spells/hex_2.png"),
	"hex_3":preload("res://assets/items-v1/spells/hex_3.png"),
	"hex_4":preload("res://assets/items-v1/spells/hex_4.png"),
	"hex_5":preload("res://assets/items-v1/spells/hex_5.png"),
	"hex_6":preload("res://assets/items-v1/spells/hex_6.png"),
	"hex_7":preload("res://assets/items-v1/spells/hex_7.png"),
	"hex_8":preload("res://assets/items-v1/spells/hex_8.png"),
	"hex_9":preload("res://assets/items-v1/spells/hex_9.png"),
	"hex_10":preload("res://assets/items-v1/spells/hex_10.png"),
	"summon_1":preload("res://assets/items-v1/spells/summon_1.png"),
	"summon_2":preload("res://assets/items-v1/spells/summon_2.png"),
	"summon_3":preload("res://assets/items-v1/spells/summon_3.png"),
	"summon_4":preload("res://assets/items-v1/spells/summon_4.png"),
	"summon_5":preload("res://assets/items-v1/spells/summon_5.png"),
	"summon_6":preload("res://assets/items-v1/spells/summon_6.png"),
	"summon_7":preload("res://assets/items-v1/spells/summon_7.png"),
	"summon_8":preload("res://assets/items-v1/spells/summon_8.png"),
	"summon_9":preload("res://assets/items-v1/spells/summon_9.png"),
	"summon_10":preload("res://assets/items-v1/spells/summon_10.png"),
	"bolt":preload("res://assets/items-v1/spells/bolt.png"),
	"blast":preload("res://assets/items-v1/spells/blast.png"),
	"cone":preload("res://assets/items-v1/spells/cone.png"),
	"cloud":preload("res://assets/items-v1/spells/cloud.png"),
	"confuse":preload("res://assets/items-v1/spells/confuse.png"),
	"blink":preload("res://assets/items-v1/spells/blink.png"),
	"passwall":preload("res://assets/items-v1/spells/passwall.png"),
	"ward":preload("res://assets/items-v1/spells/ward.png"),
	"hound":preload("res://assets/items-v1/spells/hound.png"),
	"turret":preload("res://assets/items-v1/spells/turret.png"),
	"ignite":preload("res://assets/items-v1/spells/ignite.png"),
	"mend":preload("res://assets/items-v1/spells/mend.png")}
## Magic school icons for the mastery axes; the weapon axes reuse WEAPON_ICONS.
const SCHOOL_ICONS := {"fire":preload("res://assets/items-v1/schools/fire.png"),"ice":preload("res://assets/items-v1/schools/ice.png"),
	"air":preload("res://assets/items-v1/schools/air.png"),"hex":preload("res://assets/items-v1/schools/hex.png"),
	"summon":preload("res://assets/items-v1/schools/summon.png")}
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
const MONSTER_IDS := ["dcss_rat","dcss_frilled_lizard","kobold","goblin","dcss_hobgoblin","dcss_orc","dcss_gnoll","dcss_river_rat",
	"kobold_firecaller","frost_imp","storm_bat","goblin_hexer","gnoll_summoner",
	"goblin_archer","goblin_shield","orc_thrower","cave_spider","rock_beetle","ore_golem",
	"giant_leech","swamp_toad","temple_serpent","water_spirit","skeleton_soldier","skeleton_archer",
	"ghoul","vampire_bat","wraith_knight","wraith","gravekeeper"]
const ELEMENT_TINTS := {"fire":Color(1.0,0.72,0.62),"ice":Color(0.7,0.86,1.0),"air":Color(1.0,0.96,0.6),"poison":Color(0.72,1.0,0.62),"will":Color(0.86,0.72,1.0)}
const ELEMENT_MARKS := {"fire":Color("ff7a3a"),"ice":Color("7fc8ff"),"air":Color("ffe14a"),"poison":Color("7bd35a"),"will":Color("b889ff")}
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

## A paper-doll sprite drawn `scale` tiles wide, centred on the tile, feet on
## the tile's lower edge so a figure stands in its cell and rises above it.
static func paint_standing(canvas: CanvasItem, texture: Texture2D, rect: Rect2, scale: float, tint: Color) -> void:
	var extent := rect.size*scale
	var feet := rect.end.y-rect.size.y*0.08
	var display := Rect2(Vector2(rect.get_center().x-extent.x*0.5,feet-extent.y*FEET_Y),extent)
	canvas.draw_texture_rect(texture,display,false,tint)

## A mastery axis's picture: its weapon for the five weapon axes, its school
## emblem for the five magic ones (the kit picker and the mastery tab).
static func mastery_icon(axis: String) -> AtlasTexture:
	var texture: Texture2D = WEAPON_ICONS.get(axis,SCHOOL_ICONS.get(axis,WEAPON_ICONS.sword))
	return whole(texture,"mastery/"+axis)

## A spell's card; an unknown id falls back to the plain fire bolt.
static func spell_icon(id: String) -> AtlasTexture:
	var key := id if SPELL_ICONS.has(id) else "bolt"
	return whole(SPELL_ICONS[key],"spell/"+key)

## The picture for a piece of gear: `slot` is weapon / armour / shield / ring
## (or book, scroll) and `kind` the combat.json id. Unknown ids fall back to
## the plainest piece of their slot.
static func equipment_icon(slot: String, kind: String = "") -> AtlasTexture:
	slot = "ring" if slot in ["ring1","ring2"] else "shield" if slot == "offhand" and kind == "shield" else "weapon" if slot == "offhand" else slot
	kind = "staff" if kind == "orb" else kind.trim_prefix("off_")
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

static func paint_monster(canvas: CanvasItem, species_id: String, rect: Rect2, tint: Color = Color.WHITE, element: String = "") -> void:
	var wash: Color = tint*ELEMENT_TINTS[element] if ELEMENT_TINTS.has(element) else tint
	paint_standing(canvas,enemy_sprite(species_id),rect,2.2,wash)
	if not ELEMENT_MARKS.has(element): return
	var centre := Vector2(rect.end.x-rect.size.x*0.12,rect.position.y-rect.size.y*0.9)
	var radius: float = rect.size.x*0.13
	canvas.draw_circle(centre,radius+1.5,Color(0.1,0.08,0.07,tint.a))
	canvas.draw_circle(centre,radius,Color(ELEMENT_MARKS[element],tint.a))

static func paint_boss(canvas: CanvasItem, rect: Rect2, tint: Color = Color.WHITE, species_id: String = "goblin") -> void:
	paint_standing(canvas,enemy_sprite(species_id),rect,3.0,tint)

static func terrain(cell: Dictionary, point: Vector2i = Vector2i.ZERO, theme_id: String = "") -> AtlasTexture:
	if theme_id in ["F1_RUINS","F2_MINES","F3_TEMPLE","F4_CRYPT"]: return FirstFloor.terrain(cell,point,theme_id)
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

## A skill's own icon (tools/art/build_skill_icons.py), found by the part id
## before any "@element" of a variant; parts without one fall back to the old
## item sheet.
static func part_icon(id: String) -> AtlasTexture:
	var base: String = id.get_slice("@",0).get_slice("/",0)
	var path := "res://assets/items-v1/skills/%s.png" % base
	if ResourceLoader.exists(path): return whole(load(path),"skill/"+base)
	var icons := {"PUSH":10,"GUARD":10,"BOMB":12,"IRON_HIDE":8,
		"KOBOLD_SLING":5,"GOBLIN_SHIV":1,"SERPENT_SHED":8,"BEETLE_CURL":8,"SHIELD_STANCE":10,"THORN_ARMOUR":8,"SKELETON_WALL":10,
		"HOB_TAUNT":8,"ORE_SLAM":3,"ORC_CLEAVER":4,"GNOLL_SPEAR":2}
	var index: int = int(icons.get(base,14))
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
