extends Control
signal cell_pressed(cell: Vector2i)
const Icons = preload("res://expedition/map_icons.gd")
var session
var cell_size := 56.0
var origin := Vector2.ZERO
var ui_font: Font
const COLORS = {"stone":Color("252b35"), "wood":Color("584735"),
	"water":Color("284859"), "metal":Color("49515b"), "wall":Color("111720")}

func _ready() -> void:
	custom_minimum_size = Vector2(390,390)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)

func _draw() -> void:
	if session == null or session.tiles.is_empty(): return
	cell_size = minf(size.x, size.y) / 8.0
	origin = (size - Vector2.ONE * cell_size * 8) / 2
	var font: Font = ui_font if ui_font != null else ThemeDB.fallback_font
	for y in range(8):
		for x in range(8):
			var point := Vector2i(x,y)
			var cell: Dictionary = session.tile(point)
			var rect := Rect2(origin + Vector2(point) * cell_size, Vector2.ONE * cell_size)
			draw_rect(rect.grow(-1), COLORS[cell.terrain])
			if cell.wet > 0: draw_line(rect.position + Vector2(8,cell_size-10), rect.end-Vector2(8,10), Color("66b0c8"), 2)
			if cell.fire > 0:
				draw_circle(rect.get_center(), cell_size * 0.3, Color("ba592d"))
				draw_string(font, rect.position+Vector2(6,18), "불 %d" % cell.fire, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffd6a0"))
			for intent in session.intents:
				if intent.cell == point:
					draw_rect(rect.grow(-4), Color("d26561"), false, 2)
					draw_line(rect.position+Vector2(5,5),rect.end-Vector2(5,5),Color(0.9,0.3,0.3,0.45),2)
	for point in session.doors():
		var rect := Rect2(origin+Vector2(point)*cell_size,Vector2.ONE*cell_size)
		var color := Color("81c6ad") if session.phase == "EXPLORE" else Color("73535a")
		draw_rect(rect.grow(-3),color,false,3)
		Icons.paint(self,"entry",rect.get_center(),cell_size*0.24,color)
	if not session.rooms.is_empty():
		var row: Dictionary = session.rooms[session.room]
		if row.kind in ["camp","loot"]:
			var color := Color("53616b") if row.used else Color("79c9a2") if row.kind == "camp" else Color("e8c779")
			Icons.paint(self,row.kind,origin+(Vector2(row.feature)+Vector2.ONE*0.5)*cell_size,cell_size*0.32,color)
	for actor in session.party + session.enemies:
		if actor.hp <= 0: continue
		var center: Vector2 = origin + (Vector2(actor.pos) + Vector2.ONE * 0.5) * cell_size
		var color := Color("ce726b") if actor.enemy else Color("dfc98e")
		if not actor.enemy and actor.id == session.selected: draw_circle(center,cell_size*0.36,Color("f8e9bb"),false,2)
		draw_circle(center,cell_size*0.28,Color("171c26"))
		draw_string(font,center+Vector2(-10,6),str(actor.name).substr(0,1),HORIZONTAL_ALIGNMENT_LEFT,-1,20,color)
		var health := Rect2(center+Vector2(-cell_size*0.3,cell_size*0.32),Vector2(cell_size*0.6,4))
		draw_rect(health,Color("151820"))
		health.size.x *= float(actor.hp) / actor.max_hp
		draw_rect(health,color)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point := Vector2i(((event.position-origin) / cell_size).floor())
		if point.x >= 0 and point.y >= 0 and point.x < 8 and point.y < 8:
			cell_pressed.emit(point)
			accept_event()
