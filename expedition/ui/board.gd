extends Control
var input_actor := -1
var targeting_skill := ""
var action_footer := false
signal cell_pressed(cell: Vector2i)
signal cell_inspected(cell: Vector2i)
signal zoom_changed(side: int)
signal gesture_started
var view_side := 11
var camera_gesture = preload("res://expedition/legacy/base_map_camera.gd").new()
var _pointer_down := false
var _pointer_dragged := false
var touch_start := Vector2.ZERO
var suppress_mouse_until := 0
const Art = preload("res://expedition/art/mobile_art.gd")
const MEMORY_TINT := Color(0.18,0.20,0.23)
## A dungeon npc is neither the party's green nor the monsters' red.
const NPC_COLOR := Color("d8c98a")
const Icons = preload("res://expedition/art/map_icons.gd")
var session
var ui_font: Font
var half_width := 22.0
var half_height := 11.0
var origin := Vector2.ZERO
var show_attack_range := false
var target_cell := Vector2i(-1,-1)
var effects: Array = []
var effect_time := 0.0
var impact_time := 0.0
var companion_previews: Array = []
var touch_pressed_at := 0
signal playback_finished
const ActorVisual = preload("res://expedition/ui/battle_actor_visual.gd")
var playback: Array = []
var playback_clock := 0.0
var playback_speed := 1.0
var visual_state: Dictionary = {}
var playback_focus := Vector2i.ZERO
var actor_visuals: Dictionary = {}
var foreground: Node2D
const IntentUI = preload("res://expedition/ui/companion_intent_ui.gd")
const IntentOverlay = preload("res://expedition/ui/companion_intent_overlay.gd")
var intent_ui = IntentUI.new()
var intent_overlay: Node2D
var companion_intents: Array = []
var playback_decision_recorded := false
var ui_elapsed := 0.0
var skill_badges: Dictionary = {}
var walk_actor_id := -1
var walk_from := Vector2i.ZERO
var walk_to := Vector2i.ZERO
var walk_visual_from := Vector2.ZERO
var walk_elapsed := 0.0
var walk_duration := 0.11

func animate_walk(actor_id: int, from: Vector2i, to: Vector2i, duration: float = 0.11) -> void:
	var start := Vector2(from)
	if walk_actor_id == actor_id and walk_to == from:
		start = walk_visual_from.lerp(Vector2(from),clampf(walk_elapsed/walk_duration,0.0,1.0))
	walk_actor_id = actor_id
	walk_from = from
	walk_to = to
	walk_visual_from = start
	walk_elapsed = 0.0
	walk_duration = maxf(0.01,duration)
	queue_redraw()

func display_center(actor: Dictionary) -> Vector2:
	var center := cell_center(actor.pos)
	if not is_presenting() and walk_actor_id == int(actor.id) and actor.pos == walk_to:
		var t := clampf(walk_elapsed/walk_duration,0.0,1.0)
		center = project(walk_visual_from+Vector2.ONE*0.5).lerp(center,t)
	for effect in effects:
		if effect.get("kind","") == "ATTACK_SWING" and effect.from == actor.pos and effect_time < 0.2:
			var progress := clampf(effect_time/0.2,0.0,1.0)
			center += (cell_center(effect.cell)-cell_center(effect.from)).normalized()*half_width*0.48*sin(progress*PI)
	return center

func is_presenting() -> bool:
	return not playback.is_empty()

func reset_intent_ui() -> void:
	intent_ui = IntentUI.new()
	companion_intents.clear()
	skill_badges.clear()
	ui_elapsed = 0.0
	if is_instance_valid(intent_overlay):
		intent_overlay.intents = []
		intent_overlay.queue_redraw()
	queue_redraw()

func play_frames(frames: Array) -> void:
	if frames.is_empty(): return
	walk_actor_id = -1
	playback_focus = frames[0].before.focus
	playback = frames.duplicate(true)
	playback_clock = 0.0
	visual_state = playback[0].before
	playback_decision_recorded = false
	effects = []; effect_time = 0.0; impact_time = 0.0
	queue_redraw()

func display_at(point: Vector2i) -> Dictionary:
	if not is_presenting(): return session.at(point)
	for actor in visual_state.actors:
		if actor.pos == point: return actor
	return {}

func _advance_playback(delta: float) -> void:
	ui_elapsed += delta
	intent_ui.tick(delta,false)
	playback_clock += delta*playback_speed
	var frame: Dictionary = playback[0]
	if not playback_decision_recorded:
		playback_decision_recorded = true
		var event: Dictionary = frame.get("executed_intent",{})
		intent_ui.record_execution(event,true,ui_elapsed)
		var skill_id := str(event.get("skill_id",""))
		if not skill_id.is_empty():
			skill_badges[int(event.actor_id)] = {"skill_id":skill_id,"remaining":maxf(0.3,0.6/maxf(0.01,playback_speed))}
	for actor_id in skill_badges.keys():
		var badge: Dictionary = skill_badges[actor_id]
		badge.remaining = float(badge.remaining)-delta
		if badge.remaining <= 0: skill_badges.erase(actor_id)
	# Wind-up / target highlight, then impact and HP loss, then recovery.
	if playback_clock >= 0.18:
		visual_state = frame.after
		effects = frame.effects
		effect_time = playback_clock-0.18
		impact_time = effect_time
	if playback_clock >= (0.68 if not frame.effects.is_empty() else 0.32):
		playback.pop_front(); playback_clock = 0.0
		effects = []; effect_time = 0.0; impact_time = 0.0
		if playback.is_empty():
			visual_state = {}
			playback_finished.emit()
		else:
			visual_state = playback[0].before
			playback_decision_recorded = false
	queue_redraw()

var radial_light = preload("res://expedition/art/radial_light.gd").new()

func injury_focus() -> Dictionary:
	for effect in effects:
		if effect.get("body_injury",false): return effect
	return {}

func impact_transform() -> Dictionary:
	if injury_focus().is_empty() or impact_time >= 0.45: return {"zoom":1.0,"offset":Vector2.ZERO}
	var strength := sin(clampf(impact_time/0.45,0,1)*PI)
	var zoom := 1.0+0.18*strength
	var focus := cell_center(injury_focus().cell)
	return {"zoom":zoom,"offset":focus*(1.0-zoom)+Vector2(sin(impact_time*110),cos(impact_time*93))*4*strength}

func preview_rect(actor: Dictionary) -> Rect2:
	var center := cell_center(actor.pos)
	return Rect2(Vector2(clampf(center.x-29,0,maxf(0,size.x-58)),maxf(origin.y,center.y-half_width-19)),Vector2(58,18))

func _process(delta: float) -> void:
	var had_labels: bool = not skill_badges.is_empty() or not intent_ui.speech.is_empty()
	if walk_actor_id >= 0:
		walk_elapsed += delta
		if walk_elapsed >= walk_duration: walk_actor_id = -1
		queue_redraw()
	if not is_presenting() and session != null and bool(session.auto.get("running",false)):
		ui_elapsed += delta
		intent_ui.tick(delta,false)
		for actor_id in skill_badges.keys():
			var badge: Dictionary = skill_badges[actor_id]
			badge.remaining = float(badge.remaining)-delta
			if badge.remaining <= 0: skill_badges.erase(actor_id)
	if is_presenting():
		_advance_playback(delta); return
	if effects.is_empty():
		if had_labels: queue_redraw()
		return
	var slow_delta := minf(delta,maxf(0,0.3-impact_time)) if not injury_focus().is_empty() else 0.0
	impact_time += delta
	effect_time += slow_delta*0.25+(delta-slow_delta)
	if effect_time > 1.0: effects.clear()
	queue_redraw()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	clip_contents = true
	custom_minimum_size = Vector2(0,180)
	size_flags_vertical = SIZE_EXPAND_FILL
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	resized.connect(_resize_board)
	_resize_board()

func _resize_board() -> void:
	# The HUD owns the remaining height on short screens; the map scales to it.
	custom_minimum_size.y = 160+(56 if action_footer else 0)
	queue_redraw()

func geometry() -> void:
	var map_side: float = maxf(2,minf(size.x,size.y-8))
	half_width = maxf(1,map_side/(visible_side()*2.0))
	half_height = half_width
	origin = (size-Vector2.ONE*map_side)*0.5

func project(cell: Vector2) -> Vector2:
	return origin + (cell-camera_origin())*half_width*2

func camera_origin() -> Vector2:
	if session == null or session.tiles.is_empty(): return Vector2.ZERO
	var focus: Vector2 = Vector2(playback_focus) if is_presenting() else Vector2(session.party[session.selected].pos)
	if not is_presenting() and walk_actor_id == int(session.party[session.selected].id) and walk_to == session.party[session.selected].pos:
		focus = walk_visual_from.lerp(Vector2(walk_to),clampf(walk_elapsed/walk_duration,0.0,1.0))
	return focus-Vector2.ONE*float((visible_side()-1)/2)

func camera_cell() -> Vector2i:
	var top_left := camera_origin()
	return Vector2i(floori(top_left.x),floori(top_left.y))

func visible_side() -> int:
	return view_side

func set_view_side(value: int) -> void:
	view_side = clampi(value,6,24); zoom_changed.emit(view_side); queue_redraw()

func cell_center(cell: Vector2i) -> Vector2:
	geometry()
	return project(Vector2(cell)+Vector2.ONE*0.5)

func cell_at(point: Vector2) -> Vector2i:
	geometry()
	var camera := impact_transform()
	var delta: Vector2 = (point-camera.offset)/camera.zoom-origin
	var world: Vector2 = delta/(half_width*2)+camera_origin()
	return Vector2i(floori(world.x),floori(world.y))

func tile_polygon(point: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for offset in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]: result.append(project(point+offset))
	return result

func is_wall_tile(point: Vector2i) -> bool:
	if not session.inside(point): return true
	return session.tile(point).terrain == "wall"

# Wall geometry belongs to the room boundary, not to actor line of sight.
# Draw its one-cell rim from adjacent known floors without revealing those
# walls to gameplay, the minimap, or any actor/feature behind them.
func terrain_visibility(point: Vector2i) -> int:
	if not session.inside(point): return 0

	var state = session.floor_state
	var seen: Dictionary = visual_state.visible if is_presenting() else state.visible
	var known_cells: Dictionary = visual_state.explored if is_presenting() else state.explored
	var known := 2 if seen.has(point) else 1 if known_cells.has(point) else 0
	if not is_wall_tile(point): return known
	for direction in session.DIRECTIONS:
		var neighbor: Vector2i = point+direction
		if not session.inside(neighbor) or is_wall_tile(neighbor): continue
		if seen.has(neighbor): return 2
		if known_cells.has(neighbor): known = maxi(known,1)
	return known

func outline(points: PackedVector2Array, color: Color, width: float = 1) -> void:
	var closed := points.duplicate(); closed.append(points[0]); draw_polyline(closed,color,width,true)

func movement_previews() -> Array:
	var result: Array = []
	if session == null or not session.on_floor(): return result
	for preview in companion_previews:
		if preview.kind != "MOVE": continue
		if preview.actor == session.party[0].id: continue
		var member: Array = session.party.filter(func(a): return a.id == preview.actor)
		if member.is_empty(): continue
		var actor: Dictionary = member[0]
		if actor.hp <= 0 or preview.cell == actor.pos or not session.inside(preview.cell): continue
		result.append({"actor":actor.id,"sprite":actor_sprite(actor),"from":actor.pos,"cell":preview.cell,"reserved":preview.get("reserved",false)})
	return result

## A companion's planned step, drawn ahead of it: the destination tile, a ghost
## of the pawn standing on it and an arrow from where it stands now.
func draw_movement_previews() -> void:
	for preview in movement_previews():
		var start := cell_center(preview.from)
		var destination := cell_center(preview.cell)
		var color := Color("f1ca79") if preview.reserved else Color("a6d8e8")
		var polygon := tile_polygon(Vector2(preview.cell))
		draw_colored_polygon(polygon,Color(color,0.13))
		outline(polygon,Color(color,0.8),2)
		var side := half_width*1.65
		Art.paint_actor(self,int(preview.sprite),Rect2(destination-Vector2.ONE*side/2,Vector2.ONE*side),Color(color,0.35))
		var direction := (destination-start).normalized()
		var tip := destination-direction*half_width*0.4
		var tail := start+direction*half_width*0.6
		var normal := Vector2(-direction.y,direction.x)
		draw_line(tail,tip,Color(0,0,0,0.7),5,true)
		draw_line(tail,tip,color,2.5,true)
		draw_colored_polygon(PackedVector2Array([tip,tip-direction*8+normal*5,tip-direction*8-normal*5]),color)

func paint_terrain() -> void:
	var walls: Array = []
	var camera := camera_cell()
	# One additional row supplies the raised portion of walls below the viewport.
	for y in range(camera.y,camera.y+visible_side()+2):
		for x in range(camera.x,camera.x+visible_side()+2):
			var point := Vector2i(x,y)
			if not session.inside(point): continue
			var visibility := terrain_visibility(point)
			if visibility == 0: continue
			var cell: Dictionary = session.tile(point)
			var rect := Rect2(project(Vector2(point)),Vector2.ONE*half_width*2)
			var tint := MEMORY_TINT if visibility == 1 else Color.WHITE
			if cell.terrain == "wall":
				draw_rect(rect,Color("090c10"))
				walls.append({"point":point,"rect":rect,"tint":tint})
			else:
				if visibility == 1: draw_rect(rect,Color("151b22"))
				else: draw_texture_rect(Art.terrain(cell,point,session.floor_state.theme_id if uses_pixel_floor_art() else ""),rect,false,tint)
				Art.Masonry.paint_floor_shadow(self,rect,point,is_wall_tile)
				# Single-slab art already marks its own edges; remembered cells keep one fine rim.
				if visibility == 1: draw_rect(rect,Color(0,0,0,0.16),false,1.0)
	Art.Masonry.paint_walls(self,walls,is_wall_tile,Art.FirstFloor.material(session.floor_state.theme_id) if uses_pixel_floor_art() else {})

func uses_pixel_floor_art() -> bool:
	return session.floor_state.theme_id in ["F1_RUINS","F2_MINES"]

func _draw() -> void:
	for visual in actor_visuals.values():
		if is_instance_valid(visual): visual.visible = false
	if not is_instance_valid(foreground):
		foreground = Node2D.new(); foreground.z_index = 3
		add_child(foreground)
		foreground.draw.connect(func(): _draw_foreground(foreground))
	if not is_instance_valid(intent_overlay):
		intent_overlay = IntentOverlay.new()
		intent_overlay.board = self
		intent_overlay.z_index = 2
		add_child(intent_overlay)
	intent_overlay.intents = displayed_companion_intents()
	intent_overlay.queue_redraw()
	foreground.queue_redraw()
	geometry()
	draw_rect(Rect2(Vector2.ZERO,size),Color("0b1117"))
	if session == null or session.tiles.is_empty():
		draw_string(ui_font,Vector2(18,size.y*0.45),"",HORIZONTAL_ALIGNMENT_CENTER,size.x-36,20,Color("cfbd91"))
		return
	var camera := impact_transform()
	draw_set_transform(camera.offset,0,Vector2.ONE*camera.zoom)
	paint_terrain()
	var attacks: Array = []
	if show_attack_range and targeting_skill == "ATTACK":
		attacks = session.attack_cells()
	elif session.Abilities.DEFINITIONS.has(targeting_skill) and session.Abilities.DEFINITIONS[targeting_skill].target == "ENEMY" and session.Abilities.DEFINITIONS[targeting_skill].range > 0:
		attacks.clear()
		var caster: Dictionary = session.party[session.selected if input_actor < 0 else input_actor]
		for y in range(camera_cell().y,camera_cell().y+visible_side()+2):
			for x in range(camera_cell().x,camera_cell().x+visible_side()+2):
				if x < 0 or y < 0 or x >= session.BOARD_SIDE or y >= session.BOARD_SIDE: continue
				var cell := Vector2i(x,y)
				if session.distance(caster.pos,cell) <= int(session.Abilities.DEFINITIONS[targeting_skill].range) and session.tile(cell).terrain != "wall" and session.TurnCore.Geometry.sees(caster.pos,cell,func(p): return session.tile(p).terrain == "wall"): attacks.append(cell)
	for depth in range((visible_side()+2)*2-1):
		for local_x in range(visible_side()+2):
			var local_y := depth-local_x
			if local_y < 0 or local_y >= visible_side()+2: continue
			var x: int = local_x+camera_cell().x
			var y: int = local_y+camera_cell().y
			if x < 0 or y < 0 or x >= session.BOARD_SIDE or y >= session.BOARD_SIDE: continue
			var point := Vector2i(x,y)
			if not (visual_state.explored if is_presenting() else session.floor_state.explored).has(point): continue
			var cell: Dictionary = session.tile(point)
			var polygon := tile_polygon(Vector2(point))
			if not (visual_state.visible if is_presenting() else session.floor_state.visible).has(point): continue
			if cell.terrain not in ["stone","wall"]: outline(polygon,Color(0.08,0.10,0.12,0.25))
			var center := project(Vector2(point)+Vector2.ONE*0.5)
			if session.floor_state.features.has(point):
				var feature: Dictionary = session.floor_state.features[point]
				var icon: String = ("potion" if session.Consumables.definition(str(feature.get("item_id",""))).get("class","") == "potion" else "scroll") if feature.kind == "item" else session.Curios.definition(feature).get("icon",feature.kind)
				var object_id: String = Art.FirstFloor.feature_id(feature) if uses_pixel_floor_art() else ""
				var item_kind: String = str(feature.get("item_id","")) if feature.kind == "item" else ""
				if icon == "potion" and not item_kind.is_empty():
					# A dropped potion wears its run look; a known one shows its effect.
					var known: bool = session.known.has(item_kind)
					Art.paint_potion(self,Rect2(center-Vector2.ONE*half_width*0.95,Vector2.ONE*half_width*1.9),session.Consumables.look_index(session,item_kind),Art.potion_badge(item_kind,true) if known else null)
				elif not object_id.is_empty():
					Art.FirstFloor.paint_object(self,object_id,Rect2(center-Vector2.ONE*half_width,Vector2.ONE*half_width*2),Color("777777") if bool(feature.get("used",false)) else Color.WHITE)
				else:
					Icons.paint(self,"entry" if feature.kind in ["entry","altar"] else icon,center,half_width*0.65,Color("655a43") if bool(feature.get("used",false)) else Color("9fe3ff") if feature.kind in ["stairs","pylon"] else Color("e4c98e"))
			if point in attacks:
				draw_colored_polygon(polygon,Color(0.95,0.15,0.18,0.3)); outline(polygon,Color("f37575"),2)
			if point == target_cell: outline(polygon,Color.WHITE,3)
			if cell.wet > 0 and cell.terrain != "water": outline(polygon,Color(0.3,0.6,0.8,0.6))
			for intent in (visual_state.intents if is_presenting() else session.intents):
				if intent.cell == point:
					draw_colored_polygon(polygon,Color(1,0.45,0.05,0.4)); outline(polygon,Color("ffb447"),3)
					draw_string(ui_font,center+Vector2(-4,4),"!"+(session.Abilities.badge(intent.kind) if not str(intent.get("kind","")).is_empty() else ""),HORIZONTAL_ALIGNMENT_LEFT,-1,12 if not str(intent.get("kind","")).is_empty() else 18,Color.WHITE)
			if cell.fire > 0:
				draw_circle(center,half_width*0.4,Color("a74b24")); draw_circle(center-Vector2(0,4),half_width*0.2,Color("ffc675"))
			var actor: Dictionary = display_at(point)
			if not actor.is_empty():
				center = display_center(actor)
				if not actor.enemy and session.party.find(actor) == session.selected: outline(polygon,Color("e8c276"),2)
				draw_set_transform(center*camera.zoom+camera.offset,0,Vector2(1,0.45)*camera.zoom)
				draw_circle(Vector2.ZERO,half_width*0.6,Color(0,0,0,0.5))
				draw_set_transform(camera.offset,0,Vector2.ONE*camera.zoom)
				var side := half_width*1.65
				var flash := Color.WHITE
				if actor.enemy:
					flash = {"MELEE":Color.WHITE,"RANGED":Color("b8d9a2"),"CASTER":Color("c5a5ef")}.get(actor.get("role","MELEE"),Color.WHITE)
				for effect in effects:
					if effect.get("kind","") == "ENEMY_ATTACK": continue
					if effect.cell == point and effect_time < 0.35:
						center.x += sin(effect_time*65)*4*(1-effect_time/0.35)
						flash = Color(2,0.6,0.6)
				var actor_rect := Rect2(center-Vector2.ONE*side/2,Vector2.ONE*side)
				# Separate sprite canvas permits an alpha-based one-screen-pixel rim.
				var key: String = str(actor.enemy)+"/"+str(actor.id)
				if not actor_visuals.has(key) or not is_instance_valid(actor_visuals[key]):
					actor_visuals[key] = ActorVisual.new(); add_child(actor_visuals[key])
				var visual = actor_visuals[key]
				visual.visible = true; visual.actor = actor; visual.rect = actor_rect
				visual.tint = flash; visual.boss = bool(actor.get("boss",false))
				visual.position = camera.offset; visual.scale = Vector2.ONE*camera.zoom
				visual.z_index = 1; move_child(visual,get_child_count()-1)
				visual.queue_redraw()
				paint_actor_base(center,actor)

	draw_distant_npcs()
	draw_movement_previews()
	draw_set_transform(Vector2.ZERO)

## Which pawn stands in for an actor: party members own one each, an npc
## borrows one by its roster id.
func actor_sprite(actor: Dictionary) -> int:
	return Art.actor_index(actor)

## An awake npc is drawn where it is now even outside the party's sight — the
## approach the player should see coming (설계 §5.3) — half faded. One asleep
## is only ever drawn by the cell loop, inside the light.
func draw_distant_npcs() -> void:
	if session == null or is_presenting(): return
	var camera := impact_transform()
	draw_set_transform(camera.offset,0,Vector2.ONE*camera.zoom)
	for npc in session.npcs:
		if npc.hp <= 0 or not npc.get("awake",false): continue
		if session.floor_state.visible.has(npc.pos): continue
		var center := project(Vector2(npc.pos)+Vector2.ONE*0.5)
		if not Rect2(Vector2.ZERO,size).has_point(center): continue
		var side := half_width*1.65
		Art.paint_actor(self,actor_sprite(npc),Rect2(center-Vector2.ONE*side/2,Vector2.ONE*side),Color(1,1,1,0.5))
		paint_actor_base(center,npc)
		draw_set_transform(camera.offset,0,Vector2.ONE*camera.zoom)

func paint_actor_base(center: Vector2, actor: Dictionary) -> void:
	var color := NPC_COLOR if session.wanderer(actor) else Color("eea38c") if actor.enemy else Color("b9dcd6")
	var base := center+Vector2(0,half_width*0.65)
	if actor.enemy:
		outline(PackedVector2Array([base+Vector2(-half_width*0.65,0),base+Vector2(0,-half_width*0.23),base+Vector2(half_width*0.65,0),base+Vector2(0,half_width*0.23)]),color,1.5)
	else:
		draw_set_transform(base*impact_transform().zoom+impact_transform().offset,0,Vector2(1,0.36)*impact_transform().zoom)
		draw_arc(Vector2.ZERO,half_width*0.65,0,TAU,32,color,2.0,true)
		draw_set_transform(impact_transform().offset,0,Vector2.ONE*impact_transform().zoom)

func _draw_foreground(canvas: Node2D) -> void:
	if session == null or session.tiles.is_empty(): return
	var camera := impact_transform()
	canvas.draw_set_transform(camera.offset,0,Vector2.ONE*camera.zoom)
	var actors: Array = visual_state.actors if is_presenting() else session.party+session.enemies+session.npcs
	for actor in actors:
		if actor.hp <= 0: continue
		# A recruit is a companion now: the third colour and the name tag belong
		# to those still out on their own.
		var npc: bool = session.wanderer(actor)
		var seen: bool = (visual_state.visible if is_presenting() else session.floor_state.visible).has(actor.pos)
		# An awake npc keeps its tag out of sight; anyone else is only drawn in the light.
		if not seen and not (npc and actor.get("awake",false)): continue
		var fade: float = 1.0 if seen else 0.5
		var center := display_center(actor)
		if npc:
			canvas.draw_string(ui_font,center+Vector2(-40,-half_width*1.1),str(actor.name),HORIZONTAL_ALIGNMENT_CENTER,80,10,Color(NPC_COLOR,fade))
			var doing: String = str(actor.get("activity",""))
			if not doing.is_empty():
				canvas.draw_string(ui_font,center+Vector2(-45,half_width+10),doing,HORIZONTAL_ALIGNMENT_CENTER,90,9,Color("cfc6ab",fade))
		canvas.draw_rect(Rect2(center+Vector2(-12,half_width-5),Vector2(24,3)),Color(Color("191d24"),fade))
		canvas.draw_rect(Rect2(center+Vector2(-12,half_width-5),Vector2(24*float(actor.hp)/actor.max_hp,3)),Color(NPC_COLOR,fade) if npc else Color("ce7770") if actor.enemy else Color("9ec987"))
	if is_presenting():
		var frame: Dictionary = playback[0]
		for actor in actors:
			if actor.id == frame.actor:
				var lift: float = half_width*(1.4 if actor.enemy else 2.7)
				if skill_badges.has(int(actor.id)) or intent_ui.speech.any(func(row): return int(row.actor_id) == int(actor.id)):
					lift += 24.0
				var tip := cell_center(actor.pos)-Vector2(0,lift)
				tip.y = maxf(origin.y+10,tip.y)
				canvas.draw_colored_polygon(PackedVector2Array([tip+Vector2(-5,-8),tip+Vector2(5,-8),tip]),Color("fff0b0"))
		if playback_clock < 0.18:
			for hit in frame.effects:
				canvas.draw_line(cell_center(hit.from),cell_center(hit.cell),Color(1,0.85,0.5,1),0.75,true)
	for actor_id in skill_badges:
		var skill_id := str(skill_badges[actor_id].skill_id)
		var actor := _actor_for_id(actors,int(actor_id))
		if not _label_visible(actor): continue
		var definition: Dictionary = session.Abilities.DEFINITIONS.get(skill_id,{})
		var title := str(definition.get("name",skill_id))
		if title.length() > 8: title = title.left(7)+"…"
		var center := cell_center(actor.pos)-Vector2(0,half_width*2.6)
		var box := Rect2(Vector2(clampf(center.x-43,2,maxf(2,size.x-88)),maxf(origin.y,center.y-15)),Vector2(86,17))
		canvas.draw_rect(box,Color(0.04,0.07,0.09,0.82))
		canvas.draw_rect(box,Color("e2bf70",0.7),false,1)
		canvas.draw_string(ui_font,box.position+Vector2(3,12),title,HORIZONTAL_ALIGNMENT_CENTER,80,10,Color("fff0c8"))
	for row in intent_ui.speech:
		if skill_badges.has(int(row.actor_id)): continue
		var actor := _actor_for_id(actors,int(row.actor_id))
		if not _label_visible(actor): continue
		var center := cell_center(actor.pos)-Vector2(0,half_width*2.6)
		var box := Rect2(Vector2(clampf(center.x-35,2,maxf(2,size.x-72)),maxf(origin.y,center.y-18)),Vector2(70,18))
		canvas.draw_rect(box,Color(0.03,0.05,0.07,0.85))
		canvas.draw_rect(box,Color("e5dfcf",0.68),false,1)
		canvas.draw_string(ui_font,box.position+Vector2(2,13),str(row.text),HORIZONTAL_ALIGNMENT_CENTER,66,11,Color("fff6e1"))
	for effect in effects:
		if effect.get("kind","") == "ENEMY_ATTACK":
			draw_enemy_attack(effect,canvas); continue
		if effect.get("kind","") == "ATTACK_SWING":
			if effect_time < 0.2:
				var progress := clampf(effect_time/0.2,0.0,1.0)
				var start := cell_center(effect.from)
				var target := cell_center(effect.cell)
				var center := start.lerp(target,0.55+0.45*progress)
				var tangent := (target-start).normalized().rotated(PI/2)*half_width*0.42
				canvas.draw_line(center-tangent,center+tangent,Color(1.0,0.9,0.67,1.0-progress),2.0,true)
			continue
		if effect_time >= 0.75: continue
		var center := cell_center(effect.cell)-Vector2(0,half_width*0.65)
		var fade := 1.0-effect_time/0.75
		var color := Color(1,0.85,0.5,fade) if effect.form != "ELECTRIC" else Color(0.4,0.8,1,fade)
		if effect_time < 0.28:
			canvas.draw_line(cell_center(effect.from)-Vector2(0,half_width*0.65),center,color,3,true)
			canvas.draw_line(center-Vector2(15,-12),center+Vector2(15,-12),color,5,true)
			canvas.draw_arc(center,8+effect_time*45,0,TAU,20,color,2,true)
		canvas.draw_string(ui_font,center+Vector2(-12,-14-effect_time*30),"-%d" % effect.amount,HORIZONTAL_ALIGNMENT_LEFT,-1,20,color)
	canvas.draw_set_transform(Vector2.ZERO)
	var injury := injury_focus()
	if not injury.is_empty() and impact_time < 0.45:
		var fade := 1.0-impact_time/0.45
		canvas.draw_rect(Rect2(Vector2.ZERO,size),Color(0.65,0.03,0.02,0.16*fade))
		var point := cell_center(injury.cell)
		point = point*camera.zoom+camera.offset
		for i in range(8):
			var direction := Vector2.RIGHT.rotated(i*TAU/8)
			canvas.draw_line(point+direction*(12+impact_time*35),point+direction*(28+impact_time*80),Color(1,0.7,0.45,fade),3,true)
		canvas.draw_string(ui_font,Vector2(clampf(point.x-65,2,maxf(2,size.x-132)),maxf(20,point.y-30)),str(injury.get("part","신체"))+" 손상!",HORIZONTAL_ALIGNMENT_CENTER,130,16,Color(1,0.85,0.7,fade))

func draw_enemy_attack(effect: Dictionary, canvas: Node2D) -> void:
	var fade := clampf(1.0-effect_time,0,1)
	var impact := Color(1,0.25,0.12,fade)
	var center := Vector2.ZERO
	for cell in effect.cells:
		var point := cell_center(cell)
		center += point
		var polygon := tile_polygon(Vector2(cell))
		canvas.draw_colored_polygon(polygon,Color(1,0.12,0.04,fade*(0.55 if effect_time < 0.2 else 0.22)))
		canvas.draw_polyline(PackedVector2Array([polygon[0],polygon[1],polygon[2],polygon[3],polygon[0]]),impact,3,true)
		var radius := half_width*(0.25+minf(effect_time*3,0.7))
		canvas.draw_arc(point,radius,0,TAU,20,Color(1,0.8,0.4,fade),2,true)
		if effect_time < 0.4:
			for direction in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
				canvas.draw_line(point+direction*radius*0.45,point+direction*radius,impact,3,true)
	center /= maxf(1,effect.cells.size())
	if not effect.area:
		var start := cell_center(effect.from)
		var tip := start.lerp(center,clampf(effect_time*8,0,1))
		canvas.draw_line(start,tip,impact,5,true)
		var slash := Vector2(half_width*0.5,-half_width*0.5)
		canvas.draw_line(center-slash,center+slash,Color(1,0.85,0.65,fade),4,true)
	var caption := "폭발!" if effect.area else "공격!"
	var box := Rect2(Vector2(clampf(center.x-30,0,maxf(0,size.x-60)),center.y-half_width-20),Vector2(60,20))
	canvas.draw_style_box(_preview_background(impact),box)
	canvas.draw_string(ui_font,box.position+Vector2(2,15),caption,HORIZONTAL_ALIGNMENT_CENTER,56,13,Color(1,0.85,0.65,fade))

func _preview_background(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04,0.07,0.1,0.95); box.border_color = color
	box.set_border_width_all(1); box.set_corner_radius_all(3)
	return box

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		suppress_mouse_until = Time.get_ticks_msec()+500
		if event.pressed:
			gesture_started.emit()
			if camera_gesture.contacts.is_empty():
				touch_start = event.position; _pointer_down = true; _pointer_dragged = false
				touch_pressed_at = Time.get_ticks_msec()
				camera_gesture.zoom = 10.0/view_side
		if camera_gesture.handle(self,event): accept_event(); return
		if not event.pressed:
			var tap: bool = _pointer_down and not _pointer_dragged and not event.canceled
			_pointer_down = false
			if tap:
				if Time.get_ticks_msec()-touch_pressed_at >= 450: emit_inspection(event.position)
				else: emit_cell(event.position)
		accept_event(); return
	if event is InputEventScreenDrag:
		suppress_mouse_until = Time.get_ticks_msec()+500
		if event.position.distance_to(touch_start) > 12: _pointer_dragged = true
		camera_gesture.handle(self,event); accept_event(); return
	if event is InputEventMagnifyGesture or event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		gesture_started.emit()
		camera_gesture.zoom = 10.0/view_side
		camera_gesture.handle(self,event); accept_event(); return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec() < suppress_mouse_until: return
		gesture_started.emit(); emit_cell(event.position); accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		emit_inspection(event.position); accept_event()

func emit_cell(position: Vector2) -> void:
	if is_presenting(): return
	if position.y < origin.y or position.y >= origin.y+size.x: return
	var point := cell_at(position)
	if session != null and session.inside(point): cell_pressed.emit(point)

func emit_inspection(position: Vector2) -> void:
	if is_presenting() or position.y < origin.y or position.y >= origin.y+size.x: return
	var point := cell_at(position)
	if session != null and session.inside(point): cell_inspected.emit(point)

func _actor_for_id(actors: Array, actor_id: int) -> Dictionary:
	for actor in actors:
		if not actor.enemy and int(actor.id) == actor_id: return actor
	return {}

func _label_visible(actor: Dictionary) -> bool:
	if actor.is_empty() or int(actor.get("hp",0)) <= 0: return false
	var visible: Dictionary = visual_state.get("visible",{}) if is_presenting() else session.floor_state.visible
	return visible.has(actor.pos) and Rect2(Vector2.ZERO,size).has_point(cell_center(actor.pos))

## Keep the action being replayed readable through its entire frame, even
## after its AP was spent. Other members use only this frame's snapshot.
func displayed_companion_intents() -> Array:
	var rows: Array = companion_intents if not is_presenting() else visual_state.get("companion_intents",[]).duplicate(true)
	if not is_presenting(): return rows.filter(func(row): return int(row.get("actor_id",-1)) != int(session.party[0].id))
	var executed: Dictionary = playback[0].get("executed_intent",{})
	if not executed.is_empty():
		rows = rows.filter(func(row): return int(row.get("actor_id",-1)) != int(executed.actor_id))
		rows.append(executed.duplicate(true))
	return rows.filter(func(row): return int(row.get("actor_id",-1)) != int(session.party[0].id))
