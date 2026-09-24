extends Control
signal room_pressed(id: int)
signal expand_requested
const Icons = preload("res://expedition/map_icons.gd")
const KIND_COLORS = {"entry":Color("c0c8dc"),"battle":Color("da8178"),"boss":Color("d2a4ef"),"camp":Color("79c9a2"),"loot":Color("e8c779")}
const KIND_NAMES = {"entry":"입구","battle":"전투","boss":"수문장","camp":"회복","loot":"전리품"}
var session
var ui_font: Font
var hovered := -1
var compact := false
var minimum_side := 0
const LegacyMinimap = preload("res://expedition/legacy/party_minimap.gd")
var floor_minimap
var floor_stamp := ""

func _ready() -> void:
	custom_minimum_size = Vector2.ONE * (minimum_side if minimum_side > 0 else 140 if compact else 390)
	if compact: mouse_default_cursor_shape = CURSOR_POINTING_HAND
	size_flags_horizontal = SIZE_SHRINK_BEGIN if compact else SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): hovered = -1; queue_redraw())

func room_rect(id: int) -> Rect2:
	var span := minf(size.x,size.y) - 16.0
	var step := span / 3.0
	var side := step * 0.78
	var origin := (size-Vector2.ONE*span)/2.0 + Vector2.ONE * (step-side)/2.0
	return Rect2(origin+Vector2(id%3,id/3)*step,Vector2.ONE*side)

func room_at(point: Vector2) -> int:
	for id in range(9):
		if room_rect(id).has_point(point): return id
	return -1

func _draw() -> void:
	if session != null and not session.tiles.is_empty(): draw_floor()

func _gui_input(event: InputEvent) -> void:
	if compact and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		expand_requested.emit(); accept_event()

func draw_floor() -> void:
	if floor_minimap == null:
		floor_minimap = LegacyMinimap.new(); add_child(floor_minimap)
	var stamp: String = session.floor_state.epoch+"/"+str(session.world_time)+"/"+str(session.serial)+"/"+str(session.party[session.selected].pos)
	if floor_stamp != stamp:
		var observation: Dictionary = session.floor_state.observation(session)
		var first: bool = floor_minimap.stream_state().epoch != session.floor_state.epoch
		floor_minimap.set_observation(observation)
		if first: floor_minimap.set_observation(observation)
		floor_stamp = stamp
	floor_minimap.visible = compact
	floor_minimap.size = size
	if compact: return
	var side := minf(size.x,size.y)
	var step := side/float(session.BOARD_SIDE)
	var offset := (size-Vector2.ONE*side)/2
	draw_rect(Rect2(offset,Vector2.ONE*side),Color("0d0b09"))
	for point in session.floor_state.explored:
		var spec: Dictionary = floor_minimap.cell_draw_spec(point)
		var shade := 0.18 if session.floor_state.visible.has(point) else 0.68
		draw_rect(Rect2(offset+Vector2(point)*step,Vector2.ONE*step),spec.color.darkened(shade))
		if spec.marker != "":
			var color := Color("e6c776") if spec.marker == "HERO" else Color("e36762") if spec.marker == "ENEMY" else Color("d8b36c") if spec.marker == "STAIRS" else Color("86b0a3")
			draw_circle(offset+(Vector2(point)+Vector2.ONE*0.5)*step,maxf(2,step*0.65),color)
