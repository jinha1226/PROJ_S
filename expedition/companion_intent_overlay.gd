extends Node2D
## Draws UI-only plans above actor sprites but below HP, damage and speech.
var board: Control
var intents: Array = []

const COLORS := [Color("78c9c2"), Color("e2bf70"), Color("b8a0e2")]

func _draw() -> void:
	if board == null or not is_instance_valid(board) or intents.is_empty(): return
	var camera: Dictionary = board.impact_transform()
	draw_set_transform(camera.offset,0,Vector2.ONE*camera.zoom)
	var visible: Dictionary = board.visual_state.get("visible",{}) if board.is_presenting() else (board.session.floor_state.visible if board.session.floor_mode else {})
	for row in intents:
		if not row is Dictionary: continue
		var actor_id := int(row.get("actor_id",-1))
		if actor_id < 0 or str(row.get("intent","")) == "HOLD": continue
		var from: Vector2i = row.get("from",Vector2i.ZERO)
		var cell: Vector2i = row.get("cell",from)
		if board.session.floor_mode and (not visible.has(from) or not visible.has(cell)): continue
		var viewport := Rect2(Vector2.ZERO,board.size)
		if not viewport.has_point(board.cell_center(from)) or not viewport.has_point(board.cell_center(cell)): continue
		var displayed_actors: Array = board.visual_state.get("actors",[]) if board.is_presenting() else board.session.party
		var source: Dictionary = board._actor_for_id(displayed_actors,actor_id)
		if source.is_empty() or int(source.get("id",-1)) != actor_id or int(source.get("hp",0)) <= 0: continue
		if int(row.get("target_id",-1)) >= 0:
			var target: Dictionary = board.display_at(cell)
			if target.is_empty() or int(target.get("id",-1)) != int(row.target_id) or int(target.get("hp",0)) <= 0: continue
		var color: Color = COLORS[posmod(actor_id,COLORS.size())]
		var intent := str(row.get("intent",""))
		if intent == "ATTACK":
			var a: Vector2 = board.cell_center(from); var b: Vector2 = board.cell_center(cell)
			var direction: Vector2 = (b-a).normalized()
			draw_line(a+direction*board.half_width*0.55,b-direction*board.half_width*0.55,Color(color,0.55),1.0,true)
			# Four short brackets identify the target, unlike an actor selection ring.
			var radius: float = maxf(6.0,board.half_width*0.62)
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
				var marker: Vector2 = b+corner*radius
				draw_line(marker,marker-Vector2(corner.x*4,0),Color(color,0.70),1.0,true)
				draw_line(marker,marker-Vector2(0,corner.y*4),Color(color,0.70),1.0,true)
		elif intent in ["APPROACH","RETREAT","EVADE"]:
			var points: Array = row.get("path",[])
			if points.is_empty(): points = [from,cell]
			var segments: Array = []
			for i in range(points.size()-1):
				var p0: Variant = points[i]; var p1: Variant = points[i+1]
				if not p0 is Vector2i or not p1 is Vector2i: continue
				if board.session.floor_mode and (not visible.has(p0) or not visible.has(p1)): continue
				segments.append([board.cell_center(p0),board.cell_center(p1)])
			if segments.is_empty(): continue
			for segment in segments: _dashed(segment[0],segment[1],Color(color,0.55),1.0)
			var last_segment: Array = segments[-1]
			var direction: Vector2 = (last_segment[1]-last_segment[0]).normalized()
			var tip: Vector2 = last_segment[1]
			var normal := Vector2(-direction.y,direction.x)
			draw_colored_polygon(PackedVector2Array([tip,tip-direction*7+normal*4,tip-direction*7-normal*4]),Color(color,0.65))
		elif intent == "PROTECT":
			var center: Vector2 = board.cell_center(cell)
			draw_line(center+Vector2(-5,0),center,Color(color,0.70),2,true)
			draw_line(center,center+Vector2(5,0),Color(color,0.70),2,true)
			draw_line(center+Vector2(-5,0),center+Vector2(-4,5),Color(color,0.70),2,true)
			draw_line(center+Vector2(5,0),center+Vector2(4,5),Color(color,0.70),2,true)
			draw_line(center+Vector2(-4,5),center+Vector2(0,8),Color(color,0.70),2,true)
			draw_line(center+Vector2(4,5),center+Vector2(0,8),Color(color,0.70),2,true)
	draw_set_transform(Vector2.ZERO)

func _dashed(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var length := a.distance_to(b)
	if length <= 0.1: return
	var direction := (b-a)/length
	var at := 0.0
	while at < length:
		var end := minf(length,at+5.0)
		draw_line(a+direction*at,a+direction*end,color,width,true)
		at += 9.0
