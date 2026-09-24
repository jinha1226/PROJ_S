extends RefCounted
## First-floor art only; gameplay uses the existing terrain and feature data.
const MATERIALS = preload("res://assets/topdown/floor1-ink-v2/materials-soft-v3.png")
const PROPS = preload("res://assets/topdown/floor1-ink-v2/props.png")
const Regions = preload("res://expedition/art/environment_art.gd")
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/topdown/floor1-ink-v2/catalog.json"))

static func tile(id: String) -> AtlasTexture:
	return Regions.region(MATERIALS,catalog.materials[id],"floor1-ink/material/"+id)

static func material() -> Dictionary:
	return {"front":tile("front"),"top":tile("top")}

static func terrain(cell: Dictionary, point: Vector2i) -> AtlasTexture:
	var id: String = {"wood":"wood","water":"water","metal":"metal","wall":"front","rubble":"rubble","dirt":"dirt"}.get(cell.terrain,["floor_a","floor_b","floor_c","floor_d"][posmod(point.x*7+point.y*3,4)])
	return tile(id)

static func feature_id(feature: Dictionary) -> String:
	if feature.kind == "curio":
		return {"SUPPLY_CACHE":"locked_chest","BROKEN_CHEST":"locked_chest","MUSHROOMS":"dirt_pile","DEAD_ADVENTURER":"locked_chest"}.get(feature.get("curio_id",""),"")
	return {"entry":"gate","altar":"altar","relic":"relic","camp":"campfire"}.get(feature.kind,"")

static func paint_object(canvas: CanvasItem, id: String, cell: Rect2, tint: Color = Color.WHITE) -> void:
	var texture := Regions.region(PROPS,catalog.objects[id].rect,"floor1-ink/object/"+id)
	var extent := texture.get_size()*cell.size.x/float(catalog.objects[id].source_cell_size)
	canvas.draw_texture_rect(texture,Rect2(cell.position+Vector2((cell.size.x-extent.x)*0.5,cell.size.y-extent.y),extent),false,tint)
