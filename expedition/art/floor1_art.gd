extends RefCounted
## Flat illustrated materials for the ruins and mines; gameplay owns terrain rules.
const RUINS = preload("res://assets/topdown/flat-v1/ruins-materials.png")
const MINES = preload("res://assets/topdown/flat-v1/mines-materials.png")
const FLOOR_SLABS = preload("res://assets/topdown/flat-v1/ruins-floor-slabs.png")
const WALL_BLOCKS = preload("res://assets/topdown/flat-v1/ruins-wall-blocks.png")
const MINES_FLOOR_SLABS = preload("res://assets/topdown/flat-v1/mines-floor-slabs.png")
const MINES_WALL_BLOCKS = preload("res://assets/topdown/flat-v1/mines-wall-blocks.png")
const PROPS = preload("res://assets/topdown/flat-v1/props.png")
const Regions = preload("res://expedition/art/environment_art.gd")
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/topdown/floor1-ink-v2/catalog.json"))

static func tile(id: String, theme_id: String = "F1_RUINS") -> AtlasTexture:
	var floors := ["floor_a","floor_b","floor_c","floor_d"]
	var floor_index := floors.find(id)
	if floor_index >= 0:
		var floor_sheet: Texture2D = MINES_FLOOR_SLABS if theme_id == "F2_MINES" else FLOOR_SLABS
		var side := floor_sheet.get_width()/2
		return Regions.region(floor_sheet,[floor_index%2*side,floor_index/2*side,side,side],"flat/"+theme_id+"/floor/"+id)
	if id in ["front","top"]:
		var wall_sheet: Texture2D = MINES_WALL_BLOCKS if theme_id == "F2_MINES" else WALL_BLOCKS
		var side := wall_sheet.get_width()/2
		return Regions.region(wall_sheet,[0 if id == "front" else side,0,side,side],"flat/"+theme_id+"/wall/"+id)
	var sheet: Texture2D = MINES if theme_id == "F2_MINES" else RUINS
	return Regions.region(sheet,catalog.materials[id],"flat/"+theme_id+"/material/"+id)

static func material(theme_id: String = "F1_RUINS") -> Dictionary:
	return {"front":tile("front",theme_id),"top":tile("top",theme_id)}

static func terrain(cell: Dictionary, point: Vector2i, theme_id: String = "F1_RUINS") -> AtlasTexture:
	var id: String = {"wood":"wood","water":"water","metal":"metal","wall":"front","rubble":"rubble","dirt":"dirt"}.get(cell.terrain,["floor_a","floor_b","floor_c","floor_d"][posmod(point.x*7+point.y*3,4)])
	return tile(id,theme_id)

static func feature_id(feature: Dictionary) -> String:
	if feature.kind == "curio":
		return {"SUPPLY_CACHE":"locked_chest","BROKEN_CHEST":"locked_chest","MUSHROOMS":"dirt_pile","DEAD_ADVENTURER":"locked_chest"}.get(feature.get("curio_id",""),"")
	return {"entry":"gate","altar":"altar","relic":"relic","camp":"campfire"}.get(feature.kind,"")

static func paint_object(canvas: CanvasItem, id: String, cell: Rect2, tint: Color = Color.WHITE) -> void:
	var entry: Dictionary = catalog.objects[id]
	var texture := Regions.region(PROPS,entry.rect,"flat/object/"+id)
	var extent := texture.get_size()*cell.size.x/float(entry.source_cell_size)
	var position := cell.position+Vector2((cell.size.x-extent.x)*0.5,cell.size.y-extent.y)
	canvas.draw_texture_rect(texture,Rect2(position,extent),false,tint)
