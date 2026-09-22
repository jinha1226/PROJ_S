extends RefCounted
## Art-only catalog. Collision, spawning, light and damage remain game rules.
const OBJECTS = preload("res://assets/topdown/environment-v1/objects.png")
const TERRAIN = preload("res://assets/topdown/environment-v1/terrain.png")
const THEMES = preload("res://assets/topdown/environment-v1/themes.png")
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/topdown/environment-v1/catalog.json"))
static var cache: Dictionary = {}

static func region(sheet: Texture2D, coordinates: Array, key: String) -> AtlasTexture:
	if not cache.has(key):
		var texture := AtlasTexture.new()
		texture.atlas = sheet
		texture.region = Rect2(coordinates[0],coordinates[1],coordinates[2],coordinates[3])
		texture.filter_clip = true
		cache[key] = texture
	return cache[key]

static func object_texture(id: String) -> AtlasTexture:
	return region(OBJECTS,catalog.objects[id].rect,"object/"+id)

static func terrain_texture(id: String) -> AtlasTexture:
	return region(TERRAIN,catalog.terrain[id].rect,"terrain/"+id)

static func material(id: String) -> Dictionary:
	var result := {}
	for part in catalog.themes[id]:
		result[part] = region(THEMES,catalog.themes[id][part],id+"/"+part)
	return result

static func paint_object(canvas: CanvasItem, id: String, cell: Rect2) -> void:
	var texture := object_texture(id)
	var extent := texture.get_size()*cell.size.x/float(catalog.objects[id].source_cell_size)
	var position := cell.position+Vector2((cell.size.x-extent.x)*0.5,cell.size.y-extent.y)
	canvas.draw_texture_rect(texture,Rect2(position,extent),false)
