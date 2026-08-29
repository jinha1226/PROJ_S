class_name DuelDecisionGrid
extends Control

signal actor_pressed(actor_id: String)

const GRID_SIZE := 15
const MAX_CELL_SIZE := 23.0
const MIN_CELL_SIZE := 15.0

var _actors: Array = []
var _selected_actor_id := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)


func set_observation(observation: Dictionary, selected_actor_id: String = "") -> void:
	_actors.clear()
	for value in observation.get("actors", []):
		if value is Dictionary:
			_actors.append(value.duplicate(true))
	_actors.sort_custom(func(a: Dictionary, b: Dictionary):
		return _actor_id(a) < _actor_id(b))
	_selected_actor_id = selected_actor_id
	queue_redraw()


func visible_cell_count() -> int:
	return GRID_SIZE * GRID_SIZE


func actor_count() -> int:
	return _actors.size()


func grid_rect() -> Rect2:
	var available := maxf(0.0, minf(size.x, size.y))
	var cell_size := minf(MAX_CELL_SIZE, floorf(available / float(GRID_SIZE)))
	if cell_size < MIN_CELL_SIZE and available >= float(GRID_SIZE):
		cell_size = floorf(available / float(GRID_SIZE))
	var extent := maxf(0.0, cell_size * float(GRID_SIZE))
	return Rect2((size - Vector2(extent, extent)) * 0.5, Vector2(extent, extent))


func cell_size_px() -> float:
	return grid_rect().size.x / float(GRID_SIZE)


func world_to_pixel_center(position: Vector2i) -> Vector2:
	return grid_rect().position + (Vector2(position) + Vector2(0.5, 0.5)) * cell_size_px()


func pixel_to_world_cell(local_position: Vector2) -> Variant:
	var rect := grid_rect()
	if not rect.has_point(local_position):
		return null
	var cell_size := cell_size_px()
	if cell_size <= 0.0:
		return null
	var result := Vector2i(
		int(floor((local_position.x - rect.position.x) / cell_size)),
		int(floor((local_position.y - rect.position.y) / cell_size))
	)
	return result if result.x >= 0 and result.y >= 0 and result.x < GRID_SIZE and result.y < GRID_SIZE else null


func actor_render_specs() -> Array:
	var result: Array = []
	for index in range(_actors.size()):
		var actor: Dictionary = _actors[index]
		var position_value: Variant = _position_from(actor.get("position", null))
		if position_value == null or position_value.x < 0 or position_value.y < 0 \
				or position_value.x >= GRID_SIZE or position_value.y >= GRID_SIZE:
			continue
		var center := world_to_pixel_center(position_value)
		if _actors.size() == 2 and _position_from(_actors[1 - index].get("position", null)) == position_value:
			center.x += (-0.20 if index == 0 else 0.20) * cell_size_px()
		var actor_id := _actor_id(actor)
		var color := _actor_color(index, actor)
		var hit_half := maxf(9.0, cell_size_px() * 0.48)
		result.append({
			"actor_id": actor_id,
			"center": center,
			"position": position_value,
			"color": color,
			"glyph": "A" if index == 0 else "B",
			"weapon": str(actor.get("weapon", "맨손")),
			"hp_ratio": clampf(float(actor.get("hp", 0)) / maxf(1.0, float(actor.get("max_hp", 1))), 0.0, 1.0),
			"alive": bool(actor.get("alive", true)),
			"selected": actor_id == _selected_actor_id,
			"hit_rect": Rect2(center - Vector2.ONE * hit_half, Vector2.ONE * hit_half * 2.0),
		})
	return result


func actor_screen_center(actor_id: String) -> Variant:
	for value in actor_render_specs():
		if str(value.actor_id) == actor_id:
			return value.center
	return null


func actor_id_at_point(local_position: Vector2) -> String:
	var best_id := ""
	var best_distance := INF
	for value in actor_render_specs():
		var row: Dictionary = value
		if not row.hit_rect.has_point(local_position):
			continue
		var distance: float = local_position.distance_squared_to(row.center)
		if distance < best_distance:
			best_distance = distance
			best_id = str(row.actor_id)
	return best_id


func display_spec() -> Dictionary:
	return {
		"grid_size": GRID_SIZE,
		"visible_cell_count": visible_cell_count(),
		"actor_count": actor_count(),
		"selected_actor_id": _selected_actor_id,
		"grid_rect": grid_rect(),
	}


func _gui_input(event: InputEvent) -> void:
	var pressed := false
	var local_position := Vector2.ZERO
	if event is InputEventMouseButton:
		pressed = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
		local_position = event.position
	elif event is InputEventScreenTouch:
		pressed = event.pressed
		local_position = event.position
	if not pressed:
		return
	var actor_id := actor_id_at_point(local_position)
	if actor_id.is_empty():
		return
	accept_event()
	actor_pressed.emit(actor_id)


func _draw() -> void:
	var rect := grid_rect()
	if rect.size.x <= 0.0:
		return
	draw_rect(rect, Color("#09131c"), true)
	var cell_size := cell_size_px()
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var center := rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_size
			if ((x * 19 + y * 31) & 3) == 0:
				draw_circle(center, maxf(0.7, cell_size * 0.04), Color("#35505c55"))
	for guide in range(0, GRID_SIZE + 1, 5):
		var px := rect.position.x + float(guide) * cell_size
		var py := rect.position.y + float(guide) * cell_size
		draw_line(Vector2(px, rect.position.y), Vector2(px, rect.end.y), Color("#1b303b80"), 1.0)
		draw_line(Vector2(rect.position.x, py), Vector2(rect.end.x, py), Color("#1b303b80"), 1.0)
	var rows := actor_render_specs()
	if rows.size() == 2:
		draw_dashed_line(rows[0].center, rows[1].center, Color("#7b89905c"), 1.0, 5.0)
	for row_value in rows:
		_draw_actor(row_value)
	draw_rect(rect, Color("#355063"), false, 1.0)


func _draw_actor(row: Dictionary) -> void:
	var center: Vector2 = row.center
	var cell_size := cell_size_px()
	var color: Color = row.color if bool(row.alive) else Color("#68727a")
	var body_top := center - Vector2(0.0, cell_size * 0.60)
	var body_bottom := center + Vector2(0.0, cell_size * 0.16)
	draw_set_transform(Vector2.ZERO)
	_draw_ground_ellipse(center + Vector2(2.0, cell_size * 0.29), Vector2(cell_size * 0.38, cell_size * 0.13), Color("#010407a8"))
	draw_line(body_top + Vector2(0.0, cell_size * 0.24), body_bottom, color, maxf(2.0, cell_size * 0.12))
	draw_circle(body_top, maxf(3.2, cell_size * 0.20), Color("#091016"))
	draw_circle(body_top, maxf(3.2, cell_size * 0.20), color, false, maxf(1.5, cell_size * 0.08))
	draw_line(body_bottom, center + Vector2(-cell_size * 0.22, cell_size * 0.36), color, 2.0)
	draw_line(body_bottom, center + Vector2(cell_size * 0.22, cell_size * 0.36), color, 2.0)
	draw_line(body_top + Vector2(0.0, cell_size * 0.28), center + Vector2(-cell_size * 0.32, 0.0), color, 2.0)
	_draw_weapon(center, str(row.weapon), color)
	var font := get_theme_default_font()
	var glyph := str(row.glyph)
	var font_size := int(clampf(cell_size * 0.55, 10.0, 15.0))
	var glyph_size := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, body_top + Vector2(-glyph_size.x * 0.5, glyph_size.y * 0.35), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color.lightened(0.28))
	if bool(row.selected):
		draw_arc(center - Vector2(0.0, cell_size * 0.12), cell_size * 0.50, 0.0, TAU, 24,
			Color("#f5d66f"), 2.0)
	var bar := Rect2(center + Vector2(-cell_size * 0.36, cell_size * 0.43), Vector2(cell_size * 0.72, 3.0))
	draw_rect(bar, Color("#32171d"), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(row.hp_ratio), bar.size.y)), Color("#e86568"), true)


func _draw_weapon(center: Vector2, weapon: String, color: Color) -> void:
	var cell_size := cell_size_px()
	var hand := center + Vector2(cell_size * 0.23, -cell_size * 0.20)
	var weapon_lower := weapon.to_lower()
	if "활" in weapon or "bow" in weapon_lower:
		draw_arc(hand + Vector2(cell_size * 0.18, 0.0), cell_size * 0.28, -PI * 0.5, PI * 0.5, 8, color, 1.5)
		draw_line(hand + Vector2(cell_size * 0.18, -cell_size * 0.28),
			hand + Vector2(cell_size * 0.18, cell_size * 0.28), color, 1.0)
	elif "창" in weapon or "spear" in weapon_lower:
		draw_line(hand + Vector2(0.0, cell_size * 0.28), hand + Vector2(cell_size * 0.42, -cell_size * 0.48), color, 2.0)
		draw_colored_polygon(PackedVector2Array([hand + Vector2(cell_size * 0.42, -cell_size * 0.48),
			hand + Vector2(cell_size * 0.31, -cell_size * 0.38), hand + Vector2(cell_size * 0.48, -cell_size * 0.34)]), color)
	elif "검" in weapon or "칼" in weapon or "dagger" in weapon_lower or "sword" in weapon_lower:
		draw_line(hand, hand + Vector2(cell_size * 0.34, -cell_size * 0.36), color.lightened(0.25), 2.0)
		draw_line(hand + Vector2(-cell_size * 0.07, -cell_size * 0.08),
			hand + Vector2(cell_size * 0.09, cell_size * 0.07), color, 2.0)
	else:
		draw_circle(hand + Vector2(cell_size * 0.08, 0.0), maxf(2.0, cell_size * 0.10), color)


func _draw_ground_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(16):
		var angle := TAU * float(index) / 16.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)


func _actor_color(index: int, actor: Dictionary) -> Color:
	var explicit := str(actor.get("color_hex", ""))
	if not explicit.is_empty() and Color.html_is_valid(explicit):
		return Color(explicit)
	return Color("#69d7e8") if index == 0 else Color("#ef9a62")


func _actor_id(actor: Dictionary) -> String:
	return str(actor.get("id", actor.get("entity_id", "")))


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
