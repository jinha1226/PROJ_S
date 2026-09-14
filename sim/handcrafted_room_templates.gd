extends RefCounted
## Terrain and spawn positions only. Biome art/objectives are not combat rules.
const Loader = preload("res://sim/json_content_loader.gd")
static var CONTENT: Dictionary = Loader.load_document("res://data/content/handcrafted_rooms.json")

static func stamp(terrain: Array[String], width: int, origin: Vector2i, index: int) -> Dictionary:
	var template: Dictionary = CONTENT.templates[posmod(index, CONTENT.templates.size())]
	for y in range(8):
		for x in range(8):
			terrain[(origin.y + y) * width + origin.x + x] = CONTENT.legend[template.rows[y][x]]
	return template
