extends RefCounted
## ASCII room templates (DCSS vault style). Pure: JSON in, terrain/feature maps out.
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/floor_templates.json"))
const GLYPH_TERRAIN := {"#":"wall","+":"wall",".":"stone",",":"rubble","~":"water","=":"wood","%":"metal",
	"@":"stone","*":"stone","$":"stone","^":"stone","A":"stone","C":"stone","M":"stone","P":"stone"}
const GLYPH_FEATURE := {
	"@":{"kind":"entry","label":"귀환 관문"},
	"*":{"kind":"relic","label":"봉인된 유물"},
	"$":{"kind":"curio","curio_id":"LOCKED_CHEST"},
	"^":{"kind":"curio","curio_id":"DIRT_PILE"},
	"A":{"kind":"altar","label":"갈림길 중계석"},
	"C":{"kind":"camp","label":"도움이 필요한 모험가"}}

static func definition(id: String) -> Dictionary:
	for row in content.get("templates",[]):
		if row.id == id: return row
	return {}

## Clockwise quarter turns. (x,y) in the source becomes (height-1-y, x).
static func rotate(rows: Array, turns: int) -> Array:
	var current: Array = rows.duplicate()
	for _turn in range(posmod(turns,4)):
		var height: int = current.size()
		var width: int = current[0].length()
		var next: Array = []
		for x in range(width):
			var line := ""
			for y in range(height-1,-1,-1): line += current[y][x]
			next.append(line)
		current = next
	return current

static func feature_for(glyph: String) -> Dictionary:
	if not GLYPH_FEATURE.has(glyph): return {}
	var feature: Dictionary = GLYPH_FEATURE[glyph].duplicate(true)
	feature.used = false
	if feature.kind == "curio":
		var curios: Dictionary = preload("res://expedition/curios.gd").content.curios
		feature.label = curios[feature.curio_id].name
	return feature

static func parse(rows: Array) -> Dictionary:
	var result := {"width":rows[0].length(),"height":rows.size(),"terrain":{},"doors":[],"features":{},
		"anchor":Vector2i(-1,-1),"backline":[],"floor":[]}
	for y in range(rows.size()):
		for x in range(rows[y].length()):
			var glyph: String = rows[y][x]
			var p := Vector2i(x,y)
			result.terrain[p] = GLYPH_TERRAIN.get(glyph,"wall")
			if glyph == "+": result.doors.append(p)
			elif glyph == "M": result.anchor = p
			elif glyph == "P": result.backline.append(p)
			var feature := feature_for(glyph)
			if not feature.is_empty(): result.features[p] = feature
			if result.terrain[p] != "wall": result.floor.append(p)
	return result

static func stamp(terrain: Array, size: int, origin: Vector2i, parsed: Dictionary) -> void:
	for p in parsed.terrain:
		var cell: Vector2i = origin+p
		if cell.x < 0 or cell.y < 0 or cell.x >= size or cell.y >= size: continue
		terrain[cell.y*size+cell.x] = parsed.terrain[p]
