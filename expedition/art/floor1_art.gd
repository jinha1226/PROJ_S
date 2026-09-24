extends RefCounted
## Pixel materials for the ruins and mines; gameplay still owns terrain rules.
const RUINS = preload("res://assets/8bit/ruins-tiles.png")
const MINES = preload("res://assets/8bit/mines-tiles.png")
const PROPS = preload("res://assets/8bit/props.png")
const Regions = preload("res://expedition/art/environment_art.gd")
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/topdown/floor1-ink-v2/catalog.json"))

static func tile(id: String, theme_id: String = "F1_RUINS") -> AtlasTexture:
	var sheet: Texture2D = MINES if theme_id == "F2_MINES" else RUINS
	return Regions.region(sheet,catalog.materials[id],"8bit/"+theme_id+"/material/"+id)

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
	var texture := Regions.region(PROPS,catalog.objects[id].rect,"8bit/object/"+id)
	var extent := texture.get_size()*cell.size.x/float(catalog.objects[id].source_cell_size)
	canvas.draw_texture_rect(texture,Rect2(cell.position+Vector2((cell.size.x-extent.x)*0.5,cell.size.y-extent.y),extent),false,tint)
