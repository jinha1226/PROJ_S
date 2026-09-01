class_name NpcExpeditionGrid
extends Control

const CodingFont: FontFile = preload("res://assets/fonts/LivingWorldMonoKR.ttf")

const COLOR_VOID := Color("#050a0e")
const COLOR_FLOOR := Color("#10202a")
const COLOR_WALL := Color("#31424b")
const COLOR_GRID := Color("#172933")
const COLOR_NPC := Color("#69e5dc")
const COLOR_MONSTER := Color("#ef725f")
const COLOR_LOOT := Color("#e7bd62")
const COLOR_CORPSE := Color("#a83339")
const COLOR_ENTRY := Color("#7ebd83")
const COLOR_TEXT := Color("#dce7e8")

var _observation: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(360, 300)


func set_observation(value: Dictionary) -> void:
	_observation = value.duplicate(true)
	queue_redraw()


func cell_center(position: Vector2i) -> Vector2:
	var layout := _layout()
	return layout.origin + Vector2(position.x + 0.5, position.y + 0.5) * float(layout.cell)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_VOID, true)
	if _observation.is_empty():
		return
	var layout := _layout()
	var rows: Array = _observation.get("terrain_rows", [])
	for y in range(rows.size()):
		var row := str(rows[y])
		for x in range(row.length()):
			var rect := Rect2(layout.origin + Vector2(x, y) * float(layout.cell),
				Vector2.ONE * float(layout.cell))
			var wall := row.substr(x, 1) == "#"
			draw_rect(rect, COLOR_WALL if wall else COLOR_FLOOR, true)
			draw_rect(rect, COLOR_GRID, false, 1.0)
			if not wall:
				_draw_glyph("·", Vector2i(x, y), COLOR_GRID, 0.43)
	var entry_value: Array = _observation.get("entry", [-1, -1])
	if entry_value.size() == 2:
		_draw_glyph(">", Vector2i(int(entry_value[0]), int(entry_value[1])), COLOR_ENTRY, 0.72)
	for corpse_value in _observation.get("corpses", []):
		if corpse_value is Dictionary:
			_draw_row_glyph(corpse_value, COLOR_CORPSE, 0.75)
	for item_value in _observation.get("ground_items", []):
		if item_value is Dictionary:
			_draw_row_glyph(item_value, COLOR_LOOT, 0.82)
	var monsters: Array = _observation.get("monsters", [])
	if monsters.is_empty():
		var fallback: Dictionary = _observation.get("monster", {})
		if not fallback.is_empty():
			monsters.append(fallback)
	for monster_value in monsters:
		if monster_value is Dictionary and bool(monster_value.get("visible", false)):
			_draw_actor(monster_value, COLOR_MONSTER)
	var npc: Dictionary = _observation.get("npc", {})
	if bool(npc.get("visible", false)):
		_draw_actor(npc, COLOR_NPC)
	if str(_observation.get("location", "TOWN")) == "TOWN":
		draw_rect(Rect2(layout.origin, Vector2(float(layout.cell * 15),
			float(layout.cell * 13))), Color("#02080ab8"), true)
		var message := "마을에서 준비 중" if str(_observation.get("phase", "")) == "TOWN_PREPARE" \
			else "마을에서 치료·정산 중"
		var font_size := maxi(15, int(layout.cell * 0.72))
		var width := CodingFont.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var center: Vector2 = layout.origin + Vector2(float(layout.cell * 15),
			float(layout.cell * 13)) * 0.5
		draw_string(CodingFont, center + Vector2(-width * 0.5, font_size * 0.35), message,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_TEXT)


func _draw_actor(actor: Dictionary, color: Color) -> void:
	var position_value: Array = actor.get("position", [-1, -1])
	if position_value.size() != 2:
		return
	var position := Vector2i(int(position_value[0]), int(position_value[1]))
	_draw_glyph(str(actor.get("glyph", "?")), position, color, 0.82)
	var layout := _layout()
	var cell := float(layout.cell)
	var top_left: Vector2 = layout.origin + Vector2(position.x, position.y) * cell
	var hp := int(actor.get("hp", 0))
	var max_hp := maxi(1, int(actor.get("max_hp", 1)))
	var bar := Rect2(top_left + Vector2(cell * 0.12, cell * 0.08),
		Vector2(cell * 0.76, maxf(2.0, cell * 0.08)))
	draw_rect(bar, Color("#1d2428"), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(hp) / max_hp, 0.0, 1.0),
		bar.size.y)), color, true)


func _draw_row_glyph(row: Dictionary, color: Color, scale: float) -> void:
	var position_value: Array = row.get("position", [-1, -1])
	if position_value.size() == 2:
		_draw_glyph(str(row.get("glyph", "?")),
			Vector2i(int(position_value[0]), int(position_value[1])), color, scale)


func _draw_glyph(glyph: String, position: Vector2i, color: Color, scale: float) -> void:
	var layout := _layout()
	var font_size := maxi(8, int(float(layout.cell) * scale))
	var center := cell_center(position)
	var extent := CodingFont.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(CodingFont, center + Vector2(-extent.x * 0.5,
		CodingFont.get_ascent(font_size) * 0.5 - CodingFont.get_descent(font_size) * 0.5),
		glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _layout() -> Dictionary:
	var map_size: Array = _observation.get("map_size", [15, 13])
	var width := maxi(1, int(map_size[0]))
	var height := maxi(1, int(map_size[1]))
	var cell := maxi(1, int(minf(size.x / width, size.y / height)))
	var map_pixels := Vector2(width * cell, height * cell)
	return {"cell": cell, "origin": (size - map_pixels) * 0.5}
