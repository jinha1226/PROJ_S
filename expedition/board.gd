extends Control
signal cell_pressed(cell: Vector2i)
const Art = preload("res://expedition/mobile_art.gd")
const Icons = preload("res://expedition/map_icons.gd")
var session
var ui_font: Font
var half_width := 22.0
var half_height := 11.0
var origin := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(0,180)
	size_flags_vertical = SIZE_EXPAND_FILL
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	resized.connect(_resize_board)
	_resize_board()

func _resize_board() -> void:
	custom_minimum_size.y = maxf(180,size.x/2+96 if session != null and session.phase == "BATTLE" else size.x/2+40)
	queue_redraw()

func geometry() -> void:
	var available_height := size.y - (56.0 if session != null and session.phase == "BATTLE" else 0.0)
	half_width = maxf(1,size.x/16.0)
	half_height = half_width/2
	origin = Vector2(size.x/2,(available_height-half_height*16)/2+12)

func project(cell: Vector2) -> Vector2:
	return origin + Vector2((cell.x-cell.y)*half_width,(cell.x+cell.y)*half_height)

func cell_center(cell: Vector2i) -> Vector2:
	geometry()
	return project(Vector2(cell)+Vector2.ONE*0.5)

func cell_at(point: Vector2) -> Vector2i:
	geometry()
	var delta := point-origin
	return Vector2i(floori((delta.x/half_width+delta.y/half_height)/2),floori((delta.y/half_height-delta.x/half_width)/2))

func diamond(point: Vector2, lift: float = 0) -> PackedVector2Array:
	var result := PackedVector2Array()
	for offset in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]: result.append(project(point+offset)-Vector2(0,lift))
	return result

func outline(points: PackedVector2Array, color: Color, width: float = 1) -> void:
	var closed := points.duplicate(); closed.append(points[0]); draw_polyline(closed,color,width,true)

func _draw() -> void:
	geometry()
	draw_rect(Rect2(Vector2.ZERO,size),Color("0b1117"))
	if session == null or session.tiles.is_empty():
		draw_string(ui_font,Vector2(18,size.y*0.45),"원정을 준비하세요",HORIZONTAL_ALIGNMENT_CENTER,size.x-36,20,Color("cfbd91"))
		return
	var floor_edge := PackedVector2Array([project(Vector2(0,8)),project(Vector2(8,8)),project(Vector2(8,0)),project(Vector2(8,0))+Vector2(0,20),project(Vector2(8,8))+Vector2(0,20),project(Vector2(0,8))+Vector2(0,20)])
	draw_colored_polygon(floor_edge,Color("20232a"))
	for depth in range(15):
		for x in range(8):
			var y := depth-x
			if y < 0 or y > 7: continue
			var point := Vector2i(x,y)
			var cell: Dictionary = session.tile(point)
			var polygon := diamond(Vector2(point))
			var texture: Texture2D = Art.WATER if cell.terrain == "water" else Art.WOOD if cell.terrain == "wood" else Art.STONE
			var tint := Color("809098") if cell.terrain == "metal" else Color("899095")
			draw_polygon(polygon,PackedColorArray([tint]),PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]),texture)
			outline(polygon,Color("242a30"))
			var center := project(Vector2(point)+Vector2.ONE*0.5)
			if session.phase == "BATTLE" and session.is_free(point) and session.party[session.selected].ap > 0 and session.distance(session.party[session.selected].pos,point) == 1:
				draw_colored_polygon(polygon,Color(0.35,0.7,0.4,0.14))
			if cell.wet > 0 and cell.terrain != "water": outline(polygon,Color(0.3,0.6,0.8,0.6))
			if session.doors().has(point):
				outline(polygon,Color("c2aa76"),2)
				Icons.paint(self,"entry",center,half_width*0.3,Color("d8c28d"))
			for intent in session.intents:
				if intent.cell == point: draw_colored_polygon(polygon,Color(0.8,0.18,0.15,0.25)); outline(polygon,Color("d9695d"),2)
			if cell.fire > 0:
				draw_circle(center,half_width*0.4,Color("a74b24")); draw_circle(center-Vector2(0,4),half_width*0.2,Color("ffc675"))
			if cell.terrain == "wall":
				var top := diamond(Vector2(point),half_width*0.7)
				draw_colored_polygon(PackedVector2Array([polygon[1],polygon[2],polygon[3],top[3],top[2],top[1]]),Color("383c43"))
				draw_colored_polygon(top,Color("62676a")); outline(top,Color("91908b"))
			var room: Dictionary = session.rooms[session.room]
			if room.kind in ["camp","loot"] and room.feature == point:
				Icons.paint(self,room.kind,center-Vector2(0,5),half_width*0.45,Color("68716a") if room.used else Color("b5d4a6") if room.kind == "camp" else Color("e0b96e"))
			var actor: Dictionary = session.at(point)
			if not actor.is_empty():
				if not actor.enemy and actor.id == session.selected: outline(polygon,Color("e8c276"),2)
				draw_set_transform(center,0,Vector2(1,0.45)); draw_circle(Vector2.ZERO,half_width*0.6,Color(0,0,0,0.5)); draw_set_transform(Vector2.ZERO)
				var sprite: Texture2D = Art.BOSS if actor.enemy and actor.name == "수문장" else Art.ENEMY if actor.enemy else Art.ACTORS[actor.id]
				var side := half_width*2.1
				draw_texture_rect(sprite,Rect2(center-Vector2(side/2,side*0.88),Vector2.ONE*side),false)
				draw_rect(Rect2(center+Vector2(-12,6),Vector2(24,3)),Color("191d24"))
				draw_rect(Rect2(center+Vector2(-12,6),Vector2(24*float(actor.hp)/actor.max_hp,3)),Color("ce7770") if actor.enemy else Color("9ec987"))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point := cell_at(event.position)
		if session != null and session.inside(point): cell_pressed.emit(point); accept_event()
