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
	if session == null or session.rooms.is_empty(): return
	if session.floor_mode:
		draw_floor(); return
	var font: Font = ui_font if ui_font != null else ThemeDB.fallback_font
	for row in session.rooms:
		for target in row.links:
			if target < row.id: continue
			var active: bool = (row.id == session.room or target == session.room)
			var color := Color("c5b68e") if active else Color("414b61")
			draw_line(room_rect(row.id).get_center(),room_rect(target).get_center(),Color("111722"),12)
			draw_line(room_rect(row.id).get_center(),room_rect(target).get_center(),color,4)
	for row in session.rooms:
		var rect := room_rect(row.id)
		var current: bool = row.id == session.room
		var reachable: bool = session.can_travel(row.id)
		var color: Color = KIND_COLORS[row.kind]
		draw_rect(rect,Color("1b2330"))
		if compact:
			Icons.paint(self,row.kind,rect.get_center(),rect.size.x*0.22,color)
			var outline := Color("edd49a") if current else Color("8bbbaa") if reachable else Color("3c4658")
			draw_rect(rect,outline,false,2 if current else 1)
			if row.used or row.cleared: draw_circle(rect.end-Vector2(4,4),2,Color("79c9a2"))
			continue
		# Every map tile previews its own authoritative 10x10 room terrain.
		var preview := Rect2(rect.position+Vector2(8,6),Vector2(rect.size.x-16,rect.size.y-32))
		var cell_size := minf(preview.size.x,preview.size.y)/float(session.BOARD_SIDE)
		var offset := preview.position+Vector2((preview.size.x-cell_size*session.BOARD_SIDE)/2,0)
		for y in range(session.BOARD_SIDE):
			for x in range(session.BOARD_SIDE):
				var cell: Dictionary = row.tiles[y*session.BOARD_SIDE+x]
				var shade: Color = {"stone":Color("2b3443"),"wood":Color("4b4035"),"water":Color("285266"),"metal":Color("495363"),"wall":Color("111721")}[cell.terrain]
				if cell.fire > 0: shade = Color("b86437")
				draw_rect(Rect2(offset+Vector2(x,y)*cell_size,Vector2.ONE*(cell_size-0.6)),shade)
		var icon_center := preview.get_center()
		draw_circle(icon_center,18,Color(0.06,0.08,0.12,0.92))
		Icons.paint(self,row.kind,icon_center,11,color)
		var border := Color("edd49a") if current else Color("8bbbaa") if reachable else Color("3c4658")
		draw_rect(rect,border,false,3 if current or row.id == hovered else 1)
		var caption: String = KIND_NAMES[row.kind]
		if current: caption = "현재 · " + caption
		elif row.used or row.cleared: caption += " ✓"
		draw_string(font,rect.position+Vector2(5,rect.size.y-8),caption,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x-10,14,color)
		if row.id in session.visited: draw_circle(rect.position+Vector2(8,8),3,Color("e6d8b3"))

func _gui_input(event: InputEvent) -> void:
	if compact:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			expand_requested.emit(); accept_event()
		return
	if session != null and session.floor_mode: return
	if event is InputEventMouseMotion:
		hovered = room_at(event.position)
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if hovered == session.room or session.can_travel(hovered) else CURSOR_ARROW
		queue_redraw()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := room_at(event.position)
		if id >= 0: room_pressed.emit(id); accept_event()

func draw_floor() -> void:
	if floor_minimap == null:
		floor_minimap = LegacyMinimap.new(); add_child(floor_minimap)
	var stamp: String = session.floor_state.epoch+"/"+str(session.world_time)+"/"+str(session.serial)+"/"+str(session.party[session.selected].pos)+"/"+str(session.light)
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
	draw_rect(Rect2(offset,Vector2.ONE*side),Color("101416"))
	for point in session.floor_state.explored:
		var spec: Dictionary = floor_minimap.cell_draw_spec(point)
		draw_rect(Rect2(offset+Vector2(point)*step,Vector2.ONE*step),spec.color.darkened(0.35))
		if spec.marker != "":
			var color := Color("e6c776") if spec.marker == "HERO" else Color("e36762") if spec.marker == "ENEMY" else Color("7fe0ff") if spec.marker == "PORTAL" else Color("5ccfc1")
			draw_circle(offset+(Vector2(point)+Vector2.ONE*0.5)*step,maxf(2,step*0.65),color)
