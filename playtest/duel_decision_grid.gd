class_name DuelDecisionGrid
extends Control

signal actor_pressed(actor_id: String)

const GRID_SIZE := 21
const MAX_CELL_SIZE := 15.0
const MIN_CELL_SIZE := 11.0

var _actors: Array = []
var _selected_actor_id := ""
var _intent_by_actor_id: Dictionary = {}
var _escaped_actor_ids: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)


func set_observation(observation: Dictionary, selected_actor_id: String = "") -> void:
	_actors.clear()
	_escaped_actor_ids.clear()
	for value in observation.get("actors", []):
		if value is Dictionary:
			_actors.append(value.duplicate(true))
	_actors.sort_custom(func(a: Dictionary, b: Dictionary):
		return _actor_id(a) < _actor_id(b))
	_selected_actor_id = selected_actor_id
	for value in observation.get("recent_events", []):
		if value is Dictionary and str(value.get("type", "")) == "ESCAPED":
			_escaped_actor_ids[str(value.get("actor_id", ""))] = true
	for actor_value in _actors:
		if actor_value is Dictionary and str(actor_value.get("presence", "ACTIVE")) == "ESCAPED":
			_escaped_actor_ids[_actor_id(actor_value)] = true
	queue_redraw()


func set_intent_presentation(breakdowns: Array, visible: bool) -> void:
	_intent_by_actor_id.clear()
	if visible:
		for value in breakdowns:
			if not value is Dictionary:
				continue
			var actor_id := str(value.get("actor_id", ""))
			var action_id := str(value.get("selected_action_id", ""))
			var target_id := str(value.get("selected_target_id", value.get("target_id", "-1")))
			if not actor_id.is_empty() and not intent_visual_spec(action_id).is_empty():
				_intent_by_actor_id[actor_id] = {"action_id": action_id, "target_id": target_id}
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
		var intent: Dictionary = _intent_by_actor_id.get(actor_id, {})
		var stance := str(intent.get("action_id", "IDLE"))
		var facing := _actor_facing(actor_id, position_value, str(intent.get("target_id", "")))
		if stance == "FLEE":
			facing=-facing
		var presence := _presence(actor_id, actor)
		result.append({
			"actor_id": actor_id,
			"center": center,
			"position": position_value,
			"color": color,
			"glyph": _actor_glyph(index, actor),
			"hp_ratio": clampf(float(actor.get("hp", 0)) / maxf(1.0, float(actor.get("max_hp", 1))), 0.0, 1.0),
			"alive": bool(actor.get("alive", true)) and presence != "DEAD",
			"presence": presence, "interactive": presence == "ACTIVE",
			"selected": actor_id == _selected_actor_id,
			"facing": facing, "stance": stance,
			"weapon":str(actor.get("weapon","")),
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
		if not bool(row.get("interactive", true)):
			continue
		if not row.hit_rect.has_point(local_position):
			continue
		var distance: float = local_position.distance_squared_to(row.center)
		if distance < best_distance:
			best_distance = distance
			best_id = str(row.actor_id)
	return best_id


func actor_glyph_specs() -> Array:
	var result: Array = []
	for value in actor_render_specs():
		if value is Dictionary:
			result.append(_duel_glyph_layout(value))
	return result.duplicate(true)


func display_spec() -> Dictionary:
	return {
		"grid_size": GRID_SIZE,
		"visible_cell_count": visible_cell_count(),
		"actor_count": actor_count(),
		"selected_actor_id": _selected_actor_id,
		"grid_rect": grid_rect(),
		"terrain": floor_presentation_spec(),
	}


static func floor_presentation_spec() -> Dictionary:
	return {"terrain_id":"floor","glyph":".","glyph_color":Color("#46545d"),
		"background_color":Color("#09131c"),"source":"CORE_OPEN_FLOOR",
		"draw_image":false,"draw_tile_border":false,"fake_terrain_count":0}.duplicate(true)


func target_link_specs() -> Array:
	var result: Array = []
	var actor_rows: Dictionary = {}
	for row_value in actor_render_specs():
		if row_value is Dictionary:
			actor_rows[str(row_value.actor_id)] = row_value
	for actor_id_value in _intent_by_actor_id:
		var actor_id := str(actor_id_value)
		if not actor_rows.has(actor_id):
			continue
		var source: Dictionary = actor_rows[actor_id]
		if not bool(source.get("interactive", false)):
			continue
		var intent: Dictionary = _intent_by_actor_id.get(actor_id, {})
		var action_id := str(intent.get("action_id", ""))
		if action_id not in ["APPROACH", "ENGAGE", "FLEE"]:
			continue
		var target_id := str(intent.get("target_id", ""))
		if target_id.is_empty() or target_id == "-1" or not actor_rows.has(target_id):
			continue
		var target: Dictionary = actor_rows[target_id]
		var delta: Vector2 = Vector2(target.center) - Vector2(source.center)
		if delta.is_zero_approx():
			continue
		var direction := delta.normalized()
		var cell := cell_size_px()
		var from: Vector2 = Vector2(source.center) + direction * cell * 0.48
		var to: Vector2
		var kind := "TARGET"
		if action_id == "FLEE":
			kind = "FLEE_AWAY"
			from = Vector2(source.center) - direction * cell * 0.42
			to = Vector2(source.center) - direction * cell * 1.20
		else:
			to = Vector2(target.center) - direction * cell * 0.55
		var visual := intent_visual_spec(action_id)
		result.append({"actor_id": actor_id, "target_id": target_id,
			"action_id": action_id, "kind": kind, "from": from, "to": to,
			"color": Color(visual.get("color", Color.WHITE), 0.62),
			"line_width": 1.1, "hit_surface": false, "visible_after_intent": true})
	return result.duplicate(true)


static func intent_visual_spec(action_id: String, status: String = "") -> Dictionary:
	if status == "DEAD":
		return {"shape_id": "DEAD_X", "color": Color("#89939b"), "label_ko": "쓰러짐"}
	if status == "ESCAPED":
		return {"shape_id": "EXIT_MARK", "color": Color("#8da9bd"), "label_ko": "이탈"}
	return {
		"APPROACH": {"shape_id": "INWARD_CHEVRON", "color": Color("#55d9de"), "label_ko": "접근"},
		"ENGAGE": {"shape_id": "CROSSED_BLADES", "color": Color("#ff6572"), "label_ko": "공격"},
		"FLEE": {"shape_id": "OUTWARD_ARROW", "color": Color("#6daeff"), "label_ko": "도주"},
		"SELF_TREAT": {"shape_id": "MEDICAL_CROSS", "color": Color("#63dc87"), "label_ko": "치료"},
		"HOLD": {"shape_id": "GUARD_SHIELD", "color": Color("#e2b85e"), "label_ko": "경계"},
	}.get(action_id, {}).duplicate(true)


func intent_badge_specs() -> Array:
	var result: Array = []
	var actor_rows := actor_render_specs()
	var rect := grid_rect()
	var radius := maxf(3.8, cell_size_px() * 0.27)
	for index in range(actor_rows.size()):
		var actor_row: Dictionary = actor_rows[index]
		var actor_id := str(actor_row.actor_id)
		var actor := _actor_by_id(actor_id)
		var status := ""
		if not bool(actor.get("alive", true)):
			status = "DEAD"
		elif _escaped_actor_ids.has(actor_id):
			status = "ESCAPED"
		var intent: Dictionary = _intent_by_actor_id.get(actor_id, {})
		var action_id := "" if not status.is_empty() else str(intent.get("action_id", ""))
		var visual := intent_visual_spec(action_id, status)
		if visual.is_empty():
			continue
		var direction := 1.0
		var target_id := str(intent.get("target_id", ""))
		for target_row_value in actor_rows:
			if target_row_value is Dictionary and str(target_row_value.actor_id) == target_id:
				direction = -1.0 if float(target_row_value.center.x) < float(actor_row.center.x) else 1.0
				break
		if action_id == "FLEE":
			direction *= -1.0
		var center: Vector2 = actor_row.center + Vector2(-cell_size_px() * 0.38, -cell_size_px() * 0.82)
		center.x = clampf(center.x, rect.position.x + radius, rect.end.x - radius)
		center.y = clampf(center.y, rect.position.y + radius, rect.end.y - radius)
		result.append(visual.merged({
			"actor_id": actor_id, "action_id": action_id, "status": status,
			"center": center, "radius": radius, "direction": direction,
		}))
	return result


static func draw_intent_badge(canvas: CanvasItem, center: Vector2, radius: float,
		spec: Dictionary) -> void:
	if spec.is_empty() or radius <= 0.0:
		return
	var color: Color = spec.get("color", Color.WHITE)
	var shape_id := str(spec.get("shape_id", ""))
	var direction := float(spec.get("direction", 1.0))
	var width := maxf(1.15, radius * 0.28)
	canvas.draw_circle(center, radius, Color("#061018dd"))
	canvas.draw_arc(center, radius, 0.0, TAU, 16, color.darkened(0.18), width)
	match shape_id:
		"INWARD_CHEVRON":
			var tip := center + Vector2(radius * 0.50 * direction, 0.0)
			canvas.draw_line(center + Vector2(-radius * 0.48 * direction, -radius * 0.42), tip,
				color, width)
			canvas.draw_line(center + Vector2(-radius * 0.48 * direction, radius * 0.42), tip,
				color, width)
		"CROSSED_BLADES":
			canvas.draw_line(center + Vector2(-radius * 0.48, -radius * 0.48),
				center + Vector2(radius * 0.48, radius * 0.48), color, width)
			canvas.draw_line(center + Vector2(radius * 0.48, -radius * 0.48),
				center + Vector2(-radius * 0.48, radius * 0.48), color, width)
			canvas.draw_circle(center + Vector2(-radius * 0.39, radius * 0.39), width * 0.52, color)
			canvas.draw_circle(center + Vector2(radius * 0.39, radius * 0.39), width * 0.52, color)
		"OUTWARD_ARROW":
			var tail := center + Vector2(-radius * 0.48 * direction, 0.0)
			var tip := center + Vector2(radius * 0.52 * direction, 0.0)
			canvas.draw_line(tail, tip, color, width)
			canvas.draw_line(tip, tip + Vector2(-radius * 0.34 * direction, -radius * 0.34), color, width)
			canvas.draw_line(tip, tip + Vector2(-radius * 0.34 * direction, radius * 0.34), color, width)
		"MEDICAL_CROSS":
			canvas.draw_line(center + Vector2(-radius * 0.50, 0.0), center + Vector2(radius * 0.50, 0.0),
				color, width * 1.35)
			canvas.draw_line(center + Vector2(0.0, -radius * 0.50), center + Vector2(0.0, radius * 0.50),
				color, width * 1.35)
		"GUARD_SHIELD":
			canvas.draw_polyline(PackedVector2Array([
				center + Vector2(-radius * 0.48, -radius * 0.43),
				center + Vector2(radius * 0.48, -radius * 0.43),
				center + Vector2(radius * 0.34, radius * 0.22),
				center + Vector2(0.0, radius * 0.55),
				center + Vector2(-radius * 0.34, radius * 0.22),
				center + Vector2(-radius * 0.48, -radius * 0.43),
			]), color, width)
			canvas.draw_circle(center + Vector2(0.0, -radius * 0.05), width * 0.55, color)
		"DEAD_X":
			canvas.draw_line(center + Vector2(-radius * 0.46, -radius * 0.46),
				center + Vector2(radius * 0.46, radius * 0.46), color, width)
			canvas.draw_line(center + Vector2(radius * 0.46, -radius * 0.46),
				center + Vector2(-radius * 0.46, radius * 0.46), color, width)
		"EXIT_MARK":
			canvas.draw_line(center + Vector2(-radius * 0.45, -radius * 0.50),
				center + Vector2(-radius * 0.45, radius * 0.50), color, width)
			canvas.draw_line(center + Vector2(-radius * 0.30, 0.0),
				center + Vector2(radius * 0.50, 0.0), color, width)
			canvas.draw_line(center + Vector2(radius * 0.50, 0.0),
				center + Vector2(radius * 0.18, -radius * 0.30), color, width)
			canvas.draw_line(center + Vector2(radius * 0.50, 0.0),
				center + Vector2(radius * 0.18, radius * 0.30), color, width)


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
	var floor_spec:=floor_presentation_spec()
	var floor_font:=get_theme_default_font()
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var center := rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_size
			_draw_centered_duel_glyph(floor_font,str(floor_spec.glyph),center,
				maxi(8,int(cell_size*0.53)),Color("#46545d88"))
	for guide in range(0, GRID_SIZE + 1, 5):
		var px := rect.position.x + float(guide) * cell_size
		var py := rect.position.y + float(guide) * cell_size
		draw_line(Vector2(px, rect.position.y), Vector2(px, rect.end.y), Color("#1b303b80"), 1.0)
		draw_line(Vector2(rect.position.x, py), Vector2(rect.end.x, py), Color("#1b303b80"), 1.0)
	var rows := actor_render_specs()
	for link_value in target_link_specs():
		if link_value is Dictionary:
			_draw_target_link(link_value)
	for row_value in rows:
		_draw_actor(row_value)
	for badge_value in intent_badge_specs():
		if badge_value is Dictionary:
			draw_intent_badge(self, badge_value.center, float(badge_value.radius), badge_value)
	draw_rect(rect, Color("#355063"), false, 1.0)


func _draw_actor(row: Dictionary) -> void:
	var center: Vector2 = row.center
	var cell_size := cell_size_px()
	var color: Color = row.color if bool(row.alive) else Color("#68727a")
	var layout := _duel_glyph_layout(row)
	var outline := Color("#04080c")
	draw_set_transform(Vector2.ZERO)
	_draw_ground_ellipse(center + Vector2(2.0, cell_size * 0.29), Vector2(cell_size * 0.38, cell_size * 0.13), Color("#010407a8"))
	var font := get_theme_default_font()
	_draw_weighted_duel_glyph(font,str(row.glyph),layout.glyph_center,
		int(layout.font_size),outline,color.lightened(0.18))
	if bool(row.alive) and bool(layout.draw_equipment):
		_draw_centered_duel_glyph(font,str(layout.weapon_glyph),layout.weapon_center,
			int(layout.weapon_font_size),Color("#d9cfaa"))
	var bar := Rect2(center + Vector2(-cell_size * 0.36, cell_size * 0.43), Vector2(cell_size * 0.72, 3.0))
	draw_rect(bar, Color("#32171d"), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(row.hp_ratio), bar.size.y)), Color("#e86568"), true)


func _duel_glyph_layout(row: Dictionary) -> Dictionary:
	var cell := cell_size_px()
	var cell_rect := _world_cell_rect(row.position)
	var glyph_center: Vector2 = row.center
	var font := get_theme_default_font()
	var glyph := str(row.glyph)
	var font_size := int(clampf(cell*0.82,10.0,19.0))
	var extent := font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var inset_rect:=cell_rect.grow(-1.2)
	var max_size:=Vector2(2.0*minf(glyph_center.x-inset_rect.position.x,
		inset_rect.end.x-glyph_center.x),2.0*minf(glyph_center.y-inset_rect.position.y,
		inset_rect.end.y-glyph_center.y))
	while font_size>9 and (extent.x>max_size.x or extent.y>max_size.y):
		font_size-=1
		extent=font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var glyph_rect := Rect2(glyph_center-extent*0.5,extent)
	var stance := str(row.get("stance","IDLE"))
	var weapon_glyph:=_weapon_glyph(str(row.get("weapon","")))
	var weapon_font_size:=maxi(8,int(font_size*0.66))
	var weapon_center:=_clamp_point_to_rect(glyph_center+Vector2(cell*0.34,-cell*0.05),
		cell_rect.grow(-maxf(1.0,weapon_font_size*0.20)))
	return {"actor_id":str(row.actor_id),"glyph":glyph,"glyph_center":glyph_center,
		"glyph_rect":glyph_rect,"cell_rect":cell_rect,"font_size":font_size,
		"glyph_is_body":true,"detached_head":false,"head_primitive_count":0,
		"outline_passes":8,"selected_outline":false,"stance":stance,
		"limb_segments":[],"draw_limbs":false,
		"weapon_glyph":weapon_glyph,"weapon_center":weapon_center,
		"weapon_font_size":weapon_font_size,
		"draw_equipment":not weapon_glyph.is_empty(),
		"equipment_primitive_count":1 if not weapon_glyph.is_empty() else 0}.duplicate(true)


func _weapon_glyph(value:String)->String:
	var normalized:=value.strip_edges().to_upper()
	if "활" in value or "BOW" in normalized:return ")"
	if "쇠뇌" in value or "CROSSBOW" in normalized:return "+"
	if "도끼" in value or "AXE" in normalized:return "7"
	if "철퇴" in value or "둔기" in value or "MACE" in normalized:return "o"
	if "창" in value or "SPEAR" in normalized:return "|"
	if "검" in value or "SWORD" in normalized:return "/"
	return ""


func _world_cell_rect(position:Vector2i)->Rect2:
	var cell:=cell_size_px()
	return Rect2(grid_rect().position+Vector2(position)*cell,Vector2.ONE*cell)


func _clamp_point_to_rect(point:Vector2,rect:Rect2)->Vector2:
	return Vector2(clampf(point.x,rect.position.x,rect.end.x),
		clampf(point.y,rect.position.y,rect.end.y))


func _draw_weighted_duel_glyph(font:Font,glyph:String,center:Vector2,font_size:int,
		outline:Color,color:Color)->void:
	for direction in [Vector2(-1,-1),Vector2(0,-1),Vector2(1,-1),Vector2(-1,0),
			Vector2(1,0),Vector2(-1,1),Vector2(0,1),Vector2(1,1)]:
		_draw_centered_duel_glyph(font,glyph,center+direction,font_size,outline)
	_draw_centered_duel_glyph(font,glyph,center+Vector2(-0.28,0),font_size,color)
	_draw_centered_duel_glyph(font,glyph,center+Vector2(0.28,0),font_size,color)
	_draw_centered_duel_glyph(font,glyph,center,font_size,color)


func _draw_centered_duel_glyph(font:Font,glyph:String,center:Vector2,font_size:int,
		color:Color)->void:
	var extent:=font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	draw_string(font,center+Vector2(-extent.x*0.5,extent.y*0.38),glyph,
		HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)


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
	var palette := [Color("#5ee8ff"), Color("#ff9b62"), Color("#8ee765"),
		Color("#d88cff"), Color("#ffe068")]
	return palette[index % palette.size()]


func _actor_glyph(index: int, actor: Dictionary) -> String:
	var explicit := str(actor.get("glyph", ""))
	if not explicit.is_empty():
		return explicit.substr(0, 1)
	return str(["A", "B", "C", "D", "E"][index % 5])


func _presence(actor_id: String, actor: Dictionary) -> String:
	var result := str(actor.get("presence", "ACTIVE")).to_upper()
	if not bool(actor.get("alive", true)):
		result = "DEAD"
	elif _escaped_actor_ids.has(actor_id):
		result = "ESCAPED"
	return result if result in ["ACTIVE", "DEAD", "ESCAPED"] else "ACTIVE"


func _actor_facing(actor_id: String, position: Vector2i, target_id: String) -> Vector2:
	var target := _actor_by_id(target_id)
	var target_position: Variant = _position_from(target.get("position", null))
	if target_position != null:
		var target_delta := Vector2(target_position - position)
		if not target_delta.is_zero_approx():
			return target_delta.normalized()
	var closest := Vector2.RIGHT
	var closest_distance := INF
	for other_value in _actors:
		if not other_value is Dictionary or _actor_id(other_value) == actor_id:
			continue
		var other_position: Variant = _position_from(other_value.get("position", null))
		if other_position == null:
			continue
		var delta := Vector2(other_position - position)
		var distance := delta.length_squared()
		if distance > 0.0 and distance < closest_distance:
			closest_distance = distance
			closest = delta.normalized()
	return closest


func _draw_target_link(spec: Dictionary) -> void:
	var from: Vector2 = spec.from
	var to: Vector2 = spec.to
	var color: Color = spec.color
	var width := float(spec.line_width)
	draw_line(from, to, color, width, true)
	var direction := (to - from).normalized()
	if direction.is_zero_approx():
		return
	var side := Vector2(-direction.y, direction.x)
	var arrow_length := maxf(3.0, cell_size_px() * 0.28)
	draw_line(to, to - direction * arrow_length + side * arrow_length * 0.55, color, width, true)
	draw_line(to, to - direction * arrow_length - side * arrow_length * 0.55, color, width, true)


func _actor_id(actor: Dictionary) -> String:
	return str(actor.get("id", actor.get("entity_id", "")))


func _actor_by_id(actor_id: String) -> Dictionary:
	for value in _actors:
		if value is Dictionary and _actor_id(value) == actor_id:
			return value
	return {}


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
