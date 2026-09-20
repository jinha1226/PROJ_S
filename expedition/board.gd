extends Control
var input_actor := -1
var action_footer := false
signal cell_pressed(cell: Vector2i)
const Art = preload("res://expedition/mobile_art.gd")
const Icons = preload("res://expedition/map_icons.gd")
var session
var ui_font: Font
var half_width := 22.0
var half_height := 11.0
var origin := Vector2.ZERO
var show_attack_range := false
var target_cell := Vector2i(-1,-1)
var effects: Array = []
var effect_time := 0.0
var companion_previews: Array = []

func preview_rect(actor: Dictionary) -> Rect2:
	var center := cell_center(actor.pos)
	return Rect2(Vector2(clampf(center.x-29,0,maxf(0,size.x-58)),maxf(origin.y,center.y-half_width-19)),Vector2(58,18))

func _process(delta: float) -> void:
	if effects.is_empty(): return
	effect_time += delta
	if effect_time > 0.75: effects.clear()
	queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(0,180)
	size_flags_vertical = SIZE_EXPAND_FILL
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	resized.connect(_resize_board)
	_resize_board()

func _resize_board() -> void:
	custom_minimum_size.y = maxf(180,size.x+56+(56 if action_footer else 8) if session != null and session.phase == "BATTLE" else size.x+8)
	queue_redraw()

func geometry() -> void:
	var battle: bool = session != null and session.phase == "BATTLE"
	var top := 56.0 if battle else 4.0
	var bottom := (56.0 if action_footer else 8.0) if battle else 4.0
	half_width = maxf(1,size.x/16.0)
	half_height = half_width
	origin = Vector2(0,top+maxf(0,(size.y-top-bottom-size.x)/2))

func project(cell: Vector2) -> Vector2:
	return origin + cell*half_width*2

func cell_center(cell: Vector2i) -> Vector2:
	geometry()
	return project(Vector2(cell)+Vector2.ONE*0.5)

func cell_at(point: Vector2) -> Vector2i:
	geometry()
	var delta := point-origin
	return Vector2i(floori(delta.x/(half_width*2)),floori(delta.y/(half_width*2)))

func tile_polygon(point: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for offset in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]: result.append(project(point+offset))
	return result

func outline(points: PackedVector2Array, color: Color, width: float = 1) -> void:
	var closed := points.duplicate(); closed.append(points[0]); draw_polyline(closed,color,width,true)

func movement_previews() -> Array:
	var result: Array = []
	if session == null or session.phase != "BATTLE": return result
	for preview in companion_previews:
		if preview.kind != "MOVE": continue
		var actor: Dictionary = session.party[preview.actor]
		if actor.hp <= 0 or preview.cell == actor.pos or not session.inside(preview.cell): continue
		result.append({"actor":actor.id,"from":actor.pos,"cell":preview.cell,"reserved":preview.get("reserved",false)})
	return result

func draw_movement_previews() -> void:
	for preview in movement_previews():
		var start := cell_center(preview.from)
		var destination := cell_center(preview.cell)
		var color := Color("f1ca79") if preview.reserved else Color("a6d8e8")
		var polygon := tile_polygon(Vector2(preview.cell))
		draw_colored_polygon(polygon,Color(color,0.13))
		outline(polygon,Color(color,0.8),2)
		var side := half_width*1.65
		draw_texture_rect(Art.ACTORS[preview.actor],Rect2(destination-Vector2.ONE*side/2,Vector2.ONE*side),false,Color(color,0.35))
		var direction := (destination-start).normalized()
		var tip := destination-direction*half_width*0.4
		var tail := start+direction*half_width*0.6
		var normal := Vector2(-direction.y,direction.x)
		draw_line(tail,tip,Color(0,0,0,0.7),5,true)
		draw_line(tail,tip,color,2.5,true)
		draw_colored_polygon(PackedVector2Array([tip,tip-direction*8+normal*5,tip-direction*8-normal*5]),color)

func _draw() -> void:
	geometry()
	draw_rect(Rect2(Vector2.ZERO,size),Color("0b1117"))
	if session == null or session.tiles.is_empty():
		draw_string(ui_font,Vector2(18,size.y*0.45),"원정을 준비하세요",HORIZONTAL_ALIGNMENT_CENTER,size.x-36,20,Color("cfbd91"))
		return
	var movement: Array = session.movement_cells(input_actor)
	var attacks: Array = session.attack_cells(input_actor) if show_attack_range or input_actor >= 0 else []
	for depth in range(15):
		for x in range(8):
			var y := depth-x
			if y < 0 or y > 7: continue
			var point := Vector2i(x,y)
			var cell: Dictionary = session.tile(point)
			var polygon := tile_polygon(Vector2(point))
			var texture: Texture2D = Art.WATER if cell.terrain == "water" else Art.WOOD if cell.terrain == "wood" else Art.STONE
			var tint := Color("809098") if cell.terrain == "metal" else Color("899095")
			draw_polygon(polygon,PackedColorArray([tint]),PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]),texture)
			outline(polygon,Color("242a30"))
			var center := project(Vector2(point)+Vector2.ONE*0.5)
			if point in movement:
				draw_colored_polygon(polygon,Color(0.2,0.85,0.35,0.32)); outline(polygon,Color("71d991"),1.5)
			if point in attacks:
				draw_colored_polygon(polygon,Color(0.95,0.15,0.18,0.3)); outline(polygon,Color("f37575"),2)
			if point == target_cell: outline(polygon,Color.WHITE,3)
			if cell.wet > 0 and cell.terrain != "water": outline(polygon,Color(0.3,0.6,0.8,0.6))
			if session.doors().has(point):
				outline(polygon,Color("c2aa76"),2)
				Icons.paint(self,"entry",center,half_width*0.3,Color("d8c28d"))
			for intent in session.intents:
				if intent.cell == point:
					draw_colored_polygon(polygon,Color(1,0.45,0.05,0.4)); outline(polygon,Color("ffb447"),3)
					draw_string(ui_font,center+Vector2(-4,4),"!",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
			if cell.fire > 0:
				draw_circle(center,half_width*0.4,Color("a74b24")); draw_circle(center-Vector2(0,4),half_width*0.2,Color("ffc675"))
			if cell.terrain == "wall":
				draw_colored_polygon(polygon,Color("383c43"))
				draw_rect(Rect2(project(Vector2(point))+Vector2.ONE*4,Vector2.ONE*(half_width*2-8)),Color("62676a"))
			var room: Dictionary = session.rooms[session.room]
			if session.boss_trial and room.shield and point == room.pylon:
				draw_line(center+Vector2(0,half_width*0.5),center-Vector2(0,half_width*0.5),Color("7eeaff"),8,true)
				draw_circle(center-Vector2(0,half_width*0.5),6,Color("bffaff"))
			if room.kind in ["camp","loot"] and room.feature == point:
				Icons.paint(self,room.kind,center-Vector2(0,5),half_width*0.45,Color("68716a") if room.used else Color("b5d4a6") if room.kind == "camp" else Color("e0b96e"))
			var actor: Dictionary = session.at(point)
			if not actor.is_empty():
				if not actor.enemy and actor.id == session.selected: outline(polygon,Color("e8c276"),2)
				draw_set_transform(center,0,Vector2(1,0.45)); draw_circle(Vector2.ZERO,half_width*0.6,Color(0,0,0,0.5)); draw_set_transform(Vector2.ZERO)
				var sprite: Texture2D = Art.BOSS if actor.enemy and actor.name == "수문장" else Art.ENEMY if actor.enemy else Art.ACTORS[actor.id]
				if session.boss_trial and actor.enemy: sprite = Art.BOSS
				if session.boss_trial and actor.enemy and room.shield:
					draw_arc(center,half_width*0.9,0,TAU,32,Color("7eeaff"),3,true)
				var side := half_width*1.65
				var flash := Color.WHITE
				for effect in effects:
					if effect.cell == point and effect_time < 0.35:
						center.x += sin(effect_time*65)*4*(1-effect_time/0.35)
						flash = Color(2,0.6,0.6)
				draw_texture_rect(sprite,Rect2(center-Vector2.ONE*side/2,Vector2.ONE*side),false,flash)
				draw_rect(Rect2(center+Vector2(-12,half_width-5),Vector2(24,3)),Color("191d24"))
				draw_rect(Rect2(center+Vector2(-12,half_width-5),Vector2(24*float(actor.hp)/actor.max_hp,3)),Color("ce7770") if actor.enemy else Color("9ec987"))
	draw_movement_previews()
	# Draw after all actors, so another tile cannot paint over the intent badge.
	for preview in companion_previews:
		var actor: Dictionary = session.party[preview.actor]
		if actor.hp <= 0: continue
		var badge := preview_rect(actor)
		var text: String = {"PUSH":"밀치기","GUARD":"방어","ATTACK":"공격","MOVE":"이동","WAIT":"대기"}.get(preview.kind,preview.kind)
		var color := Color("f1ca79") if preview.kind in ["PUSH","GUARD"] else Color("a6d8e8")
		draw_style_box(_preview_background(color),badge)
		draw_string(ui_font,badge.position+Vector2(2,13),text+(" 예약" if preview.get("reserved",false) else " 예정"),HORIZONTAL_ALIGNMENT_CENTER,badge.size.x-4,10,color)
	for effect in effects:
		var center := cell_center(effect.cell)-Vector2(0,half_width*0.65)
		var fade := 1.0-effect_time/0.75
		var color := Color(1,0.85,0.5,fade) if effect.form != "ELECTRIC" else Color(0.4,0.8,1,fade)
		if effect_time < 0.28:
			draw_line(cell_center(effect.from)-Vector2(0,half_width*0.65),center,color,3,true)
			draw_line(center-Vector2(15,-12),center+Vector2(15,-12),color,5,true)
			draw_arc(center,8+effect_time*45,0,TAU,20,color,2,true)
		draw_string(ui_font,center+Vector2(-12,-14-effect_time*30),"-%d" % effect.amount,HORIZONTAL_ALIGNMENT_LEFT,-1,20,color)

func _preview_background(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04,0.07,0.1,0.95); box.border_color = color
	box.set_border_width_all(1); box.set_corner_radius_all(3)
	return box

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point := cell_at(event.position)
		if session != null and session.inside(point): cell_pressed.emit(point); accept_event()
