class_name PlaytestGridView
extends Control

signal world_cell_pressed(position: Vector2i)

const GRID_RADIUS := 7
const GRID_DIAMETER := GRID_RADIUS * 2 + 1
const MAX_CELL_SIZE := 28.0

const TERRAIN_COLORS := {
	"floor": Color("#505762"),
	"stone_floor": Color("#536476"),
	"wood_floor": Color("#765638"),
	"metal": Color("#486878"),
	"rubble": Color("#806b45"),
	"shallow_water": Color("#286b78"),
	"wall": Color("#182536"),
}

const TERRAIN_GLYPHS := {
	"floor": ".",
	"stone_floor": ":",
	"wood_floor": "=",
	"metal": "+",
	"rubble": ",",
	"shallow_water": "~",
	"wall": "#",
}

var _cells: Dictionary = {}
var _camera_center := Vector2i.ZERO
var _selection := Vector2i.ZERO
var _has_selection := false
var _player_position := Vector2i.ZERO
var _has_player := false
var selected_trial_slot: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)


func set_view(cells: Array, camera_center: Vector2i, selection: Variant = null) -> void:
	_cells.clear()
	_camera_center = camera_center
	_has_player = false
	var camera_derived := false
	for raw_cell in cells:
		if not raw_cell is Dictionary:
			continue
		var cell: Dictionary = raw_cell.duplicate(true)
		var position: Variant = _position_from(cell.get("position", cell.get("world_position", null)))
		if position == null:
			continue
		if not camera_derived:
			var local_position: Variant = _position_from(cell.get("local_position", null))
			if local_position != null:
				_camera_center = position - local_position + Vector2i(GRID_RADIUS, GRID_RADIUS)
				camera_derived = true
		_cells[_position_key(position)] = cell
		if bool(cell.get("is_player", false)) or str(cell.get("entity_glyph", "")) == "@":
			_player_position = position
			_has_player = true
	if selection == null:
		_has_selection = false
	else:
		var parsed_selection: Variant = _position_from(selection)
		_has_selection = parsed_selection != null
		if _has_selection:
			_selection = parsed_selection
	queue_redraw()


func set_player_position(position: Vector2i) -> void:
	_player_position = position
	_has_player = true
	queue_redraw()


func grid_rect() -> Rect2:
	var cell_size := cell_size_px()
	var extent := cell_size * float(GRID_DIAMETER)
	return Rect2((size - Vector2(extent, extent)) * 0.5, Vector2(extent, extent))


func cell_size_px() -> float:
	return min(MAX_CELL_SIZE, floor(min(size.x, size.y) / float(GRID_DIAMETER)))


func local_cell_to_world(local_cell: Vector2i) -> Vector2i:
	return _camera_center + local_cell - Vector2i(GRID_RADIUS, GRID_RADIUS)


func world_to_local_cell(world_position: Vector2i) -> Vector2i:
	return world_position - _camera_center + Vector2i(GRID_RADIUS, GRID_RADIUS)


func position_to_world(local_position: Vector2) -> Variant:
	var rect := grid_rect()
	if not rect.has_point(local_position):
		return null
	var cell_size := cell_size_px()
	if cell_size <= 0.0:
		return null
	var local_cell := Vector2i(
		int(floor((local_position.x - rect.position.x) / cell_size)),
		int(floor((local_position.y - rect.position.y) / cell_size))
	)
	if local_cell.x < 0 or local_cell.y < 0 or local_cell.x >= GRID_DIAMETER or local_cell.y >= GRID_DIAMETER:
		return null
	var world_position := local_cell_to_world(local_cell)
	if not _cells.has(_position_key(world_position)):
		return null
	return world_position


func visible_cell_count() -> int:
	return _cells.size()


func _gui_input(event: InputEvent) -> void:
	var pressed := false
	var pointer_position := Vector2.ZERO
	if event is InputEventMouseButton:
		pressed = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
		pointer_position = event.position
	elif event is InputEventScreenTouch:
		pressed = event.pressed
		pointer_position = event.position
	if not pressed:
		return
	var world_position: Variant = position_to_world(pointer_position)
	if world_position == null:
		return
	accept_event()
	world_cell_pressed.emit(world_position)


func _draw() -> void:
	var rect := grid_rect()
	draw_rect(rect, Color("#05080d"), true)
	var cell_size := cell_size_px()
	if cell_size <= 0.0:
		return
	for local_y in range(GRID_DIAMETER):
		for local_x in range(GRID_DIAMETER):
			var local_cell := Vector2i(local_x, local_y)
			var world_position := local_cell_to_world(local_cell)
			var key := _position_key(world_position)
			var cell_rect := Rect2(
				rect.position + Vector2(local_x, local_y) * cell_size,
				Vector2(cell_size, cell_size)
			)
			if not _cells.has(key):
				draw_rect(cell_rect, Color("#030508"), true)
				continue
			var cell: Dictionary = _cells[key]
			_draw_cell(cell_rect, world_position, cell)


func _draw_cell(cell_rect: Rect2, world_position: Vector2i, cell: Dictionary) -> void:
	var terrain_id := str(cell.get("terrain_id", cell.get("terrain", "floor")))
	var base_color: Color = TERRAIN_COLORS.get(terrain_id, Color("#3e4650"))
	draw_rect(cell_rect.grow(-1.0), base_color, true)
	draw_rect(cell_rect, Color("#26313e"), false, 1.0)

	var wetness := int(cell.get("wetness", 0))
	if wetness > 0:
		var wet_width: float = maxf(4.0, cell_rect.size.x * 0.15)
		draw_rect(Rect2(cell_rect.position + Vector2(2, 2), Vector2(wet_width, cell_rect.size.y - 4)), Color("#36a9e8"), true)

	var fire := int(cell.get("fire_intensity", cell.get("fire", 0)))
	if fire > 0:
		var fire_alpha: float = 0.25 + 0.45 * clampf(float(fire) / 100.0, 0.0, 1.0)
		draw_rect(cell_rect.grow(-3.0), Color(0.95, 0.2, 0.06, fire_alpha), true)

	var glyph := str(cell.get("glyph", TERRAIN_GLYPHS.get(terrain_id, "?")))
	if bool(cell.get("has_corpse", false)):
		glyph = "x"
	var entities: Array = cell.get("entities", [])
	for entity in entities:
		if not entity is Dictionary:
			continue
		if not str(entity.get("glyph", "")).is_empty():
			glyph = str(entity.glyph)
			break
		if bool(entity.get("is_player", false)):
			glyph = "@"
			break
		if not str(entity.get("role_glyph", "")).is_empty():
			glyph = str(entity.get("role_glyph"))
			continue
		if not bool(entity.get("alive", true)):
			glyph = "x"
		elif glyph != "x":
			glyph = str(entity.get("kind", "e")).left(1).to_lower()
	if cell.has("entity_glyph") and not str(cell.entity_glyph).is_empty():
		glyph = str(cell.entity_glyph)
	if bool(cell.get("is_player", false)) or (_has_player and world_position == _player_position):
		glyph = "@"
	var font := get_theme_default_font()
	var font_size := int(clamp(cell_rect.size.x * 0.48, 13.0, 22.0))
	var glyph_size := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var glyph_pos := cell_rect.position + Vector2((cell_rect.size.x - glyph_size.x) * 0.5, (cell_rect.size.y + glyph_size.y) * 0.5 - 2.0)
	draw_string(font, glyph_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#f5f7fa"))

	if fire > 0:
		draw_string(font, cell_rect.position + Vector2(3, 11), "F%d" % fire, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#fff0d5"))
	elif wetness > 0:
		draw_string(font, cell_rect.position + Vector2(3, 11), "W%d" % wetness, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#d8f3ff"))

	var hint := str(cell.get("traversal_hint", ""))
	if hint == "passable" or hint == "safe":
		draw_rect(cell_rect.grow(-2.0), Color("#55d47a"), false, 1.5)
	elif hint == "blocked":
		draw_rect(cell_rect.grow(-2.0), Color("#ef5b68"), false, 1.5)
	elif hint == "risky":
		draw_rect(cell_rect.grow(-2.0), Color("#f1b84b"), false, 1.5)
	if _has_selection and world_position == _selection:
		draw_rect(cell_rect.grow(-1.5), Color("#ffd84d"), false, 3.0)
	if selected_trial_slot >= 0 and _trial_slot(world_position) == selected_trial_slot:
		var local := _trial_local(world_position)
		if local.x in [0, 5] or local.y in [0, 5]:
			draw_rect(cell_rect.grow(-0.5), Color("#f2c94c"), false, 1.5)


func _trial_slot(position: Vector2i) -> int:
	if position.x < 1 or position.x > 13 or position.y < 1 or position.y > 13 or position.x == 7 or position.y == 7:
		return -1
	return (1 if position.x >= 8 else 0) + (2 if position.y >= 8 else 0)


func _trial_local(position: Vector2i) -> Vector2i:
	var slot := _trial_slot(position)
	return position - Vector2i(8 if slot % 2 == 1 else 1, 8 if slot >= 2 else 1)


func _position_key(position: Vector2i) -> String:
	return "%d,%d" % [position.x, position.y]


func _position_from(value: Variant) -> Variant:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Dictionary and value.has("x") and value.has("y"):
		return Vector2i(int(value.x), int(value.y))
	return null
