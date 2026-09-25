extends RefCounted
## Flat illustrated materials for the ruins and mines; gameplay owns terrain rules.
const RUINS = preload("res://assets/topdown/flat-v1/ruins-materials.png")
const MINES = preload("res://assets/topdown/flat-v1/mines-materials.png")
const FLOOR_SLABS = preload("res://assets/topdown/flat-v1/ruins-floor-slabs.png")
const WALL_BLOCKS = preload("res://assets/topdown/flat-v1/ruins-wall-blocks.png")
const MINES_FLOOR_SLABS = preload("res://assets/topdown/flat-v1/mines-floor-slabs.png")
const MINES_WALL_BLOCKS = preload("res://assets/topdown/flat-v1/mines-wall-blocks.png")
## Floor objects in the paper-doll style (tools/art/build_objects.py), one PNG
## each, standing with their base on a 64-unit grid's y = OBJECT_FOOT.
const OBJECTS := {
	"pillar_broken":preload("res://assets/objects-v1/pillar_broken.png"),
	"rubble":preload("res://assets/objects-v1/rubble.png"),
	"crate":preload("res://assets/objects-v1/crate.png"),
	"barrel":preload("res://assets/objects-v1/barrel.png"),
	"torch_lit":preload("res://assets/objects-v1/torch_lit.png"),
	"torch_unlit":preload("res://assets/objects-v1/torch_unlit.png"),
	"brazier":preload("res://assets/objects-v1/brazier.png"),
	"campfire":preload("res://assets/objects-v1/campfire.png"),
	"locked_chest":preload("res://assets/objects-v1/locked_chest.png"),
	"dirt_pile":preload("res://assets/objects-v1/dirt_pile.png"),
	"sarcophagus":preload("res://assets/objects-v1/sarcophagus.png"),
	"altar":preload("res://assets/objects-v1/altar.png"),
	"relic":preload("res://assets/objects-v1/relic.png"),
	"gate":preload("res://assets/objects-v1/gate.png"),
	"bones":preload("res://assets/objects-v1/bones.png"),
	"barricade":preload("res://assets/objects-v1/barricade.png"),
	"stairs":preload("res://assets/objects-v1/stairs.png"),
	"pylon":preload("res://assets/objects-v1/pylon.png"),
	"supply_cache":preload("res://assets/objects-v1/supply_cache.png"),
	"broken_chest":preload("res://assets/objects-v1/broken_chest.png"),
	"dead_adventurer":preload("res://assets/objects-v1/dead_adventurer.png"),
	"mushrooms":preload("res://assets/objects-v1/mushrooms.png")}
const OBJECT_FOOT := 58.0/64.0
## Objects are drawn this many tiles wide; flat ones lie inside their tile.
const OBJECT_SCALE := 1.3
const FLAT_OBJECTS := ["stairs"]
const Regions = preload("res://expedition/art/environment_art.gd")
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/topdown/floor1-ink-v2/catalog.json"))

static func tile(id: String, theme_id: String = "F1_RUINS") -> AtlasTexture:
	var floors := ["floor_a","floor_b","floor_c","floor_d"]
	var floor_index := floors.find(id)
	if floor_index >= 0:
		var floor_sheet: Texture2D = MINES_FLOOR_SLABS if theme_id in ["F2_MINES","F4_CRYPT"] else FLOOR_SLABS
		var side := floor_sheet.get_width()/2
		return Regions.region(floor_sheet,[floor_index%2*side,floor_index/2*side,side,side],"flat/"+theme_id+"/floor/"+id)
	if id in ["front","top"]:
		var wall_sheet: Texture2D = MINES_WALL_BLOCKS if theme_id in ["F2_MINES","F4_CRYPT"] else WALL_BLOCKS
		var side := wall_sheet.get_width()/2
		return Regions.region(wall_sheet,[0 if id == "front" else side,0,side,side],"flat/"+theme_id+"/wall/"+id)
	var sheet: Texture2D = MINES if theme_id in ["F2_MINES","F4_CRYPT"] else RUINS
	return Regions.region(sheet,catalog.materials[id],"flat/"+theme_id+"/material/"+id)

static func material(theme_id: String = "F1_RUINS") -> Dictionary:
	return {"front":tile("front",theme_id),"top":tile("top",theme_id)}

static func terrain(cell: Dictionary, point: Vector2i, theme_id: String = "F1_RUINS") -> AtlasTexture:
	var id: String = {"wood":"wood","water":"water","metal":"metal","wall":"front","rubble":"rubble","dirt":"dirt",
		"lava":"rubble","deep_water":"water","bog":"water"}.get(cell.terrain,["floor_a","floor_b","floor_c","floor_d"][posmod(point.x*7+point.y*3,4)])
	return tile(id,theme_id)

## The object that stands for a map feature: every curio has its own, and
## the stairs and a foundry's levers are drawn as objects too.
static func feature_id(feature: Dictionary) -> String:
	if feature.kind == "curio":
		return {"SUPPLY_CACHE":"supply_cache","BROKEN_CHEST":"broken_chest","MUSHROOMS":"mushrooms","DEAD_ADVENTURER":"dead_adventurer"}.get(feature.get("curio_id",""),"")
	return {"entry":"gate","altar":"altar","relic":"relic","camp":"campfire","stairs":"stairs","lever":"pylon","binding":"altar"}.get(feature.kind,"")

static func paint_object(canvas: CanvasItem, id: String, cell: Rect2, tint: Color = Color.WHITE) -> void:
	var texture: Texture2D = OBJECTS.get(id)
	if texture == null: return
	if id in FLAT_OBJECTS:
		canvas.draw_texture_rect(texture,cell,false,tint); return
	var extent := cell.size*OBJECT_SCALE
	var feet := cell.end.y-cell.size.y*0.04
	canvas.draw_texture_rect(texture,Rect2(Vector2(cell.get_center().x-extent.x*0.5,feet-extent.y*OBJECT_FOOT),extent),false,tint)
