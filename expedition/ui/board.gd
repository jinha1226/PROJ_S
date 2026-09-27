extends Control
var input_actor := -1
var targeting_skill := ""
var action_footer := false
signal world_pressed(point: Vector2)
var fullscreen := false
var world_walks: Dictionary = {}
var movement_vfx = preload("res://expedition/ui/movement_vfx.gd").new()
var motion_depth := -1
var terrain_layer: Node2D
var terrain_key: Array = []
var terrain_anchor := Vector2.ZERO
var painting := false
var paint_camera := Vector2.ZERO
const JOYSTICK_RADIUS := 46.0
const JOYSTICK_DEADZONE := 12.0
var joystick_active := false
var joystick_pointer := -2
var joystick_origin := Vector2.ZERO
var joystick_offset := Vector2.ZERO
var joystick_dragged := false
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
const Hazards = preload("res://expedition/level/hazards.gd")
const THEME_TINT := {"F3_TEMPLE":Color(0.82,0.95,1.0),"F4_CRYPT":Color(0.86,0.8,0.95)}
const MEMORY_TINT := Color(0.18,0.20,0.23)
## A dungeon npc is neither the party's green nor the monsters' red.
const NPC_COLOR := Color("d8c98a")
const HOSTILE_NPC_COLOR := Color("eea38c")
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
## Hit feel: a turn's blows land one after another STAGGER apart; the
## attacker lunges for LUNGE seconds, the one struck reels for KNOCK.
const STAGGER := 0.12
const LUNGE := 0.2
const KNOCK := 0.3
const INK := Color("1c1b22")
const ALLY_INTENT := Color("7fe0c8")
var impact_time := 0.0
var companion_previews: Array = []
var touch_pressed_at := 0
signal playback_finished
const Vfx = preload("res://expedition/ui/effect_vfx.gd")
const StatusVfx = preload("res://expedition/ui/status_vfx.gd")
var status_visual_clock := 0.0
var status_redraw_clock := 0.0
var status_visual_active := false
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
	if session.free_movement:
		return project(display_world_position(actor))
	if not is_presenting() and walk_actor_id == int(actor.id) and actor.pos == walk_to:
		var t := clampf(walk_elapsed/walk_duration,0.0,1.0)
		center = project(walk_visual_from+Vector2.ONE*0.5).lerp(center,t)
	# The lunge and the recoil of a blow are applied where the sprite is drawn (hit_offset).
	return center

func display_world_position(actor: Dictionary) -> Vector2:
	if world_walks.has(int(actor.id)):
		var walk: Dictionary = world_walks[int(actor.id)]
		return Vector2(walk.from).lerp(walk.to,clampf(float(walk.elapsed)/float(walk.duration),0,1))
	return session.Free.position(actor)

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
		if effect.get("body_injury",false) and effect_visible(effect): return effect
	return {}

func impact_transform() -> Dictionary:
	var shake := hit_shake()
	if injury_focus().is_empty() or impact_time >= 0.45: return {"zoom":1.0,"offset":shake}
	var strength := sin(clampf(impact_time/0.45,0,1)*PI)
	var zoom := 1.0+0.18*strength
	var focus := cell_center(injury_focus().cell)
	return {"zoom":zoom,"offset":focus*(1.0-zoom)+Vector2(sin(impact_time*110),cos(impact_time*93))*4*strength+shake}

## How far into its own animation an effect is: in manual play a turn's blows
## are staggered so each lands on its own beat.
func clock_of(effect: Dictionary) -> float:
	if is_presenting(): return effect_time
	# Auxiliary visuals share the preceding blow's beat; adding particles or
	# status notices must not delay the next attack.
	var beat := -1
	for row in effects:
		if str(row.get("kind","")) in ["","ATTACK_SWING","ENEMY_ATTACK","MISS"]: beat += 1
		if is_same(row,effect): break
	return float(effect.get("visual_clock",effect_time-minf(maxi(0,beat),6)*STAGGER))

## A blow that took HP from somebody, and whether that somebody is ours.
func is_hit(effect: Dictionary) -> bool:
	return str(effect.get("kind","")) == "" and int(effect.get("amount",0)) > 0

func hits_party(effect: Dictionary) -> bool:
	return is_hit(effect) and not bool(effect.get("enemy",true))

## Visible blows tremble briefly: hard when one lands on the party.
func hit_shake() -> Vector2:
	var strength := 0.0
	for effect in effects:
		if not is_hit(effect) or not effect_visible(effect): continue
		var t := clock_of(effect)
		if t < 0 or t >= 0.24: continue
		strength = maxf(strength,(1.0-t/0.24)*(7.0 if hits_party(effect) else 2.5))
	return Vector2(sin(effect_time*97),cos(effect_time*83))*strength

## The pose an actor strikes this instant: an attacker lunges at its target,
## the one struck is knocked back and trembles, the one missed sidesteps.
func hit_offset(point: Vector2i) -> Vector2:
	var offset := Vector2.ZERO
	var lunged := false
	for effect in effects:
		var kind := str(effect.get("kind",""))
		if kind not in ["","ATTACK_SWING","MISS"] or not effect_visible(effect): continue
		var t := clock_of(effect)
		if t < 0: continue
		var direction := Vector2(effect.cell-effect.from).normalized()
		if effect.from == point and effect.cell != point and t < LUNGE and not lunged:
			offset += direction*half_width*0.55*sin(PI*t/LUNGE); lunged = true
		if effect.cell != point: continue
		if kind == "MISS" and t < 0.25:
			offset += Vector2(-direction.y,direction.x)*half_width*0.35*sin(PI*t/0.25)
		elif is_hit(effect) and t < KNOCK:
			var left := 1.0-t/KNOCK
			offset += direction*half_width*0.32*left*left+Vector2(sin(t*90),cos(t*77))*3.5*left
	return offset

## The tint of someone just struck: white-hot for a blink, then hurt red.
func hit_flash(point: Vector2i) -> Color:
	for effect in effects:
		if effect.cell != point or not is_hit(effect) or not effect_visible(effect): continue
		var t := clock_of(effect)
		if t < 0: continue
		if t < 0.07: return Color(4,4,4)
		if t < KNOCK: return Color(1,1,1).lerp(Color(2.4,0.5,0.45),1.0-(t-0.07)/(KNOCK-0.07))
	return Color(0,0,0,0)

func preview_rect(actor: Dictionary) -> Rect2:
	var center := cell_center(actor.pos)
	return Rect2(Vector2(clampf(center.x-29,0,maxf(0,size.x-58)),maxf(origin.y,center.y-half_width-19)),Vector2(58,18))

func _process(delta: float) -> void:
	var moving: bool = not world_walks.is_empty()
	var feedback: bool = movement_vfx.advance(delta,world_walks.keys())
	for id in world_walks.keys():
		var from: Vector2 = Vector2(world_walks[id].from).lerp(world_walks[id].to,clampf(float(world_walks[id].elapsed)/float(world_walks[id].duration),0,1))
		world_walks[id].elapsed += delta
		var to: Vector2 = Vector2(world_walks[id].from).lerp(world_walks[id].to,clampf(float(world_walks[id].elapsed)/float(world_walks[id].duration),0,1))
		var cell := Vector2i(floori(to.x),floori(to.y))
		var dusty: bool = session != null and session.inside(cell) and session.floor_state.visible.has(cell) and session.tile(cell).terrain not in Hazards.WATERY and session.tile(cell).terrain != "lava"
		movement_vfx.travel(int(id),from,to,dusty)
		if float(world_walks[id].elapsed) >= float(world_walks[id].duration): world_walks.erase(id)
	if moving or feedback: queue_redraw()
	# This clock keeps moving while the player waits; it never ticks statuses.
	if is_visible_in_tree():
		status_visual_clock = fposmod(status_visual_clock+delta,4096.0)
		status_redraw_clock += delta
		if status_redraw_clock >= 1.0/30.0:
			status_redraw_clock = fposmod(status_redraw_clock,1.0/30.0)
			var active: bool = not status_actors().is_empty()
			if is_instance_valid(foreground) and (active or status_visual_active): foreground.queue_redraw()
			status_visual_active = active
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
	# Hit-stop: time crawls for the first instant of every blow.
	var stopping := effects.any(func(e): return is_hit(e) and effect_visible(e) and clock_of(e) >= 0 and clock_of(e) < 0.06)
	effect_time += (slow_delta*0.25+(delta-slow_delta))*(0.3 if stopping else 1.0)
	if effect_time > 1.0+minf(effects.size()-1,6)*STAGGER: effects.clear()
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
	var map_side: float = maxf(2,size.x if fullscreen else minf(size.x,size.y-8))
	half_width = maxf(1,map_side/(visible_side()*2.0))
	half_height = half_width
	origin = Vector2.ZERO if fullscreen else (size-Vector2.ONE*map_side)*0.5

func project(cell: Vector2) -> Vector2:
	return origin + (cell-(paint_camera if painting else camera_origin()))*half_width*2

func camera_origin() -> Vector2:
	if session == null or session.tiles.is_empty(): return Vector2.ZERO
	if session.free_movement and not is_presenting():
		var hero: Dictionary = session.party[session.selected]
		var focus := display_world_position(hero)
		return focus-Vector2(size.x*0.5,size.y*0.40)/(half_width*2.0)
	var focus: Vector2 = Vector2(playback_focus) if is_presenting() else Vector2(session.party[session.selected].pos)
	if not is_presenting() and walk_actor_id == int(session.party[session.selected].id) and walk_to == session.party[session.selected].pos:
		focus = walk_visual_from.lerp(Vector2(walk_to),clampf(walk_elapsed/walk_duration,0.0,1.0))
	return focus-Vector2.ONE*float((visible_side()-1)/2)

func camera_cell() -> Vector2i:
	var top_left := paint_camera if painting else camera_origin()
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
	outline_on(self,points,color,width)

func outline_on(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float = 1) -> void:
	var closed := points.duplicate(); closed.append(points[0]); canvas.draw_polyline(closed,color,width,true)

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

## A companion's planned attack or skill, telegraphed on the floor the way
## enemy intents are but in the allies' teal: the target tile, a reticle, a
## dotted line from the companion and the action's name.
func action_previews() -> Array:
	var result: Array = []
	if session == null or not session.on_floor(): return result
	for preview in companion_previews:
		var kind := str(preview.get("kind",""))
		if kind in ["","MOVE","WAIT"] or preview.actor == session.party[0].id: continue
		var member: Array = session.party.filter(func(a): return a.id == preview.actor)
		if member.is_empty() or member[0].hp <= 0 or not session.inside(preview.cell): continue
		var title := "공격" if kind == "ATTACK" else str(session.Abilities.definition(kind).get("name",kind))
		result.append({"actor":member[0].id,"from":member[0].pos,"cell":preview.cell,"title":title,"reserved":preview.get("reserved",false)})
	return result

func draw_action_previews() -> void:
	var pulse := 0.75+0.25*sin(Time.get_ticks_msec()*0.006)
	for preview in action_previews():
		var color := Color("f1ca79") if preview.reserved else ALLY_INTENT
		var polygon := tile_polygon(Vector2(preview.cell))
		var target := cell_center(preview.cell)
		draw_colored_polygon(polygon,Color(color,0.2*pulse))
		outline(polygon,Color(color,0.9),2.5)
		var start := cell_center(preview.from)
		if preview.from != preview.cell:
			var direction := (target-start).normalized()
			draw_dashed_line(start+direction*half_width*0.55,target-direction*half_width*0.6,Color(INK,0.7),4,7,true)
			draw_dashed_line(start+direction*half_width*0.55,target-direction*half_width*0.6,color,2,7,true)

## The reticle and the action's name go over the sprites, so the target
## standing on the tile never hides them.
func draw_action_overlay(canvas: Node2D) -> void:
	for preview in action_previews():
		var color := Color("f1ca79") if preview.reserved else ALLY_INTENT
		var target := cell_center(preview.cell)-Vector2(0,half_width*0.55)
		var ring := half_width*0.5
		canvas.draw_arc(target,ring,0,TAU,24,Color(INK,0.8),5,true)
		canvas.draw_arc(target,ring,0,TAU,24,color,2.5,true)
		for direction in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
			canvas.draw_line(target+direction*ring*0.55,target+direction*ring*1.4,Color(INK,0.8),5,true)
			canvas.draw_line(target+direction*ring*0.55,target+direction*ring*1.4,color,2.5,true)
		if ui_font != null:
			var text: String = preview.title
			var width := ui_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+10
			var box := Rect2(cell_center(preview.cell)+Vector2(-width/2,half_width*0.95),Vector2(width,16))
			canvas.draw_rect(box,Color(0.03,0.06,0.07,0.9)); canvas.draw_rect(box,color,false,1.5)
			canvas.draw_string(ui_font,box.position+Vector2(5,12),text,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("eafff9"))

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

func invalidate_terrain() -> void:
	terrain_key.clear()

## Retain the terrain draw commands between turns. Fractional camera movement
## only translates this layer; visibility and hazards are repainted on a turn.
func sync_terrain_layer(camera: Dictionary) -> bool:
	var retained: bool = session != null and session.free_movement and not is_presenting()
	if not is_instance_valid(terrain_layer):
		terrain_layer = Node2D.new(); terrain_layer.name = "TerrainLayer"; terrain_layer.z_index = -1
		add_child(terrain_layer)
		terrain_layer.draw.connect(func():
			draw_terrain_layer())
	terrain_layer.visible = retained
	if not retained: return false
	var key: Array = [session.get_instance_id(),session.depth,session.turn_serial,session.time,camera_cell(),size,view_side,session.floor_state.theme_id,show_attack_range,targeting_skill,target_cell,input_actor]
	if terrain_key != key:
		terrain_key = key
		terrain_anchor = camera_origin()
		terrain_layer.queue_redraw()
	terrain_layer.position = camera.offset+(terrain_anchor-camera_origin())*half_width*2*float(camera.zoom)
	terrain_layer.scale = Vector2.ONE*float(camera.zoom)
	return true

func draw_terrain_layer() -> void:
	if session == null or session.tiles.is_empty(): return
	terrain_anchor = camera_origin()
	var camera := impact_transform()
	terrain_layer.position = camera.offset
	var margin := Vector2.ONE*half_width*2
	terrain_layer.draw_rect(Rect2(-margin,size+margin*2),Color("0b1117"))
	paint_camera = terrain_anchor; painting = true
	paint_terrain(terrain_layer)
	paint_cells(terrain_layer)
	painting = false

func paint_terrain(canvas: CanvasItem) -> void:
	var walls: Array = []
	var camera := camera_cell()
	# One additional row supplies the raised portion of walls below the viewport.
	for y in range(camera.y,camera.y+ceili(size.y/(half_width*2))+2):
		for x in range(camera.x,camera.x+visible_side()+2):
			var point := Vector2i(x,y)
			if not session.inside(point): continue
			var visibility := terrain_visibility(point)
			if visibility == 0: continue
			var cell: Dictionary = session.tile(point)
			var rect := Rect2(project(Vector2(point)),Vector2.ONE*half_width*2)
			var tint := MEMORY_TINT if visibility == 1 else Color.WHITE
			tint *= THEME_TINT.get(session.floor_state.theme_id,Color.WHITE)
			if cell.terrain == "wall":
				canvas.draw_rect(rect,Color("090c10"))
				walls.append({"point":point,"rect":rect,"tint":tint})
			else:
				if visibility == 1: canvas.draw_rect(rect,Color("151b22"))
				else: canvas.draw_texture_rect(Art.terrain(cell,point,session.floor_state.theme_id if uses_pixel_floor_art() else ""),rect,false,tint)
				if visibility != 1:
					var wash: Color = Hazards.overlay(cell)
					if wash.a > 0: canvas.draw_rect(rect,wash)
					if bool(cell.get("fog",false)): canvas.draw_rect(rect,Hazards.FOG_COLOR)
				Art.Masonry.paint_floor_shadow(canvas,rect,point,is_wall_tile)
				# Single-slab art already marks its own edges; remembered cells keep one fine rim.
				if visibility == 1: canvas.draw_rect(rect,Color(0,0,0,0.16),false,1.0)
	Art.Masonry.paint_walls(canvas,walls,is_wall_tile,Art.FirstFloor.material(session.floor_state.theme_id) if uses_pixel_floor_art() else {})

func uses_pixel_floor_art() -> bool:
	return session.floor_state.theme_id in ["F1_RUINS","F2_MINES","F3_TEMPLE","F4_CRYPT"]

func paint_cells(canvas: CanvasItem) -> void:
	var corner := camera_cell()
	var attacks: Array = []
	if show_attack_range and targeting_skill == "ATTACK":
		attacks = session.attack_cells()
	elif session.Abilities.has(targeting_skill) and session.Abilities.definition(targeting_skill).target == "ENEMY" and session.Abilities.definition(targeting_skill).range > 0:
		attacks.clear()
		var caster: Dictionary = session.party[session.selected if input_actor < 0 else input_actor]
		for y in range(corner.y,corner.y+visible_side()+2):
			for x in range(corner.x,corner.x+visible_side()+2):
				if x < 0 or y < 0 or x >= session.BOARD_SIDE or y >= session.BOARD_SIDE: continue
				var cell := Vector2i(x,y)
				if session.distance(caster.pos,cell) <= int(session.Abilities.definition(targeting_skill).range) and session.tile(cell).terrain != "wall" and session.TurnCore.Geometry.sees(caster.pos,cell,func(p): return session.tile(p).terrain == "wall"): attacks.append(cell)
	for depth in range(visible_side()+ceili(size.y/(half_width*2))+3):
		for local_x in range(visible_side()+2):
			var local_y := depth-local_x
			if local_y < 0 or local_y >= ceili(size.y/(half_width*2))+2: continue
			var x: int = local_x+corner.x
			var y: int = local_y+corner.y
			if x < 0 or y < 0 or x >= session.BOARD_SIDE or y >= session.BOARD_SIDE: continue
			var point := Vector2i(x,y)
			if not (visual_state.explored if is_presenting() else session.floor_state.explored).has(point): continue
			if not (visual_state.visible if is_presenting() else session.floor_state.visible).has(point): continue
			var cell: Dictionary = session.tile(point)
			var polygon := tile_polygon(Vector2(point))
			if cell.terrain not in ["stone","wall"]: outline_on(canvas,polygon,Color(0.08,0.10,0.12,0.25))
			var center := project(Vector2(point)+Vector2.ONE*0.5)
			if session.floor_state.features.has(point):
				var feature: Dictionary = session.floor_state.features[point]
				var icon: String = ("potion" if session.Consumables.definition(str(feature.get("item_id",""))).get("class","") == "potion" else "scroll") if feature.kind == "item" else session.Curios.definition(feature).get("icon",feature.kind)
				var object_id: String = Art.FirstFloor.feature_id(feature) if uses_pixel_floor_art() else ""
				var item_kind: String = str(feature.get("item_id","")) if feature.kind == "item" else ""
				if not item_kind.is_empty():
					# A dropped potion or scroll wears its run look; a known one shows its effect.
					var known: bool = session.known.has(item_kind)
					var texture: Texture2D = Art.item_icon(icon,session.Consumables.look_index(session,item_kind))
					Art.paint_item(canvas,Rect2(center-Vector2.ONE*half_width*0.95,Vector2.ONE*half_width*1.9),texture,Art.item_badge(item_kind,true) if known else null)
				elif not object_id.is_empty():
					Art.FirstFloor.paint_object(canvas,object_id,Rect2(center-Vector2.ONE*half_width,Vector2.ONE*half_width*2),Color("777777") if bool(feature.get("used",false)) else Color.WHITE)
				else:
					Icons.paint(canvas,"entry" if feature.kind in ["entry","altar"] else icon,center,half_width*0.65,Color("655a43") if bool(feature.get("used",false)) else Color("9fe3ff") if feature.kind in ["stairs","lever"] else Color("e4c98e"))
			if point in attacks:
				canvas.draw_colored_polygon(polygon,Color(0.95,0.15,0.18,0.3)); outline_on(canvas,polygon,Color("f37575"),2)
			if point == target_cell: outline_on(canvas,polygon,Color.WHITE,3)
			if cell.wet > 0 and cell.terrain not in Hazards.WATERY: outline_on(canvas,polygon,Color(0.3,0.6,0.8,0.6))
			if bool(cell.get("ice",false)):
				canvas.draw_colored_polygon(polygon,Color(0.78,0.92,1.0,0.55)); outline_on(canvas,polygon,Color("e8f7ff"),2)
			if bool(cell.get("poison_pool",false)): canvas.draw_colored_polygon(polygon,Color(0.35,0.75,0.2,0.4))
			if int(cell.get("steam_until",0)) > int(session.time): canvas.draw_colored_polygon(polygon,Color(0.9,0.9,0.92,0.55))
			if bool(cell.get("gas",false)): canvas.draw_circle(center,half_width*0.3,Hazards.GAS_COLOR)
			if cell.has("collapse"):
				var armed: bool = bool(cell.collapse.get("armed",false))
				outline_on(canvas,polygon,Hazards.COLLAPSE_ARMED if armed else Hazards.COLLAPSE_IDLE,3 if armed else 1)
				if armed: canvas.draw_string(ui_font,center+Vector2(-4,4),"!",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
			for intent in (visual_state.intents if is_presenting() else session.intents):
				if intent.cell == point and not intent.has("world_center"):
					canvas.draw_colored_polygon(polygon,Color(1,0.45,0.05,0.4)); outline_on(canvas,polygon,Color("ffb447"),3)
					canvas.draw_string(ui_font,center+Vector2(-4,4),"!"+(session.Abilities.badge(intent.kind) if not str(intent.get("kind","")).is_empty() else ""),HORIZONTAL_ALIGNMENT_LEFT,-1,12 if not str(intent.get("kind","")).is_empty() else 18,Color.WHITE)
			if cell.fire > 0:
				canvas.draw_circle(center,half_width*0.4,Color("a74b24")); canvas.draw_circle(center-Vector2(0,4),half_width*0.2,Color("ffc675"))

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
	if session == null or session.tiles.is_empty():
		draw_rect(Rect2(Vector2.ZERO,size),Color("0b1117"))
		draw_string(ui_font,Vector2(18,size.y*0.45),"",HORIZONTAL_ALIGNMENT_CENTER,size.x-36,20,Color("cfbd91"))
		return
	var camera := impact_transform()
	paint_camera = camera_origin(); painting = true
	var retained_terrain := sync_terrain_layer(camera)
	draw_set_transform(camera.offset,0,Vector2.ONE*camera.zoom)
	if not retained_terrain:
		draw_rect(Rect2(Vector2.ZERO,size),Color("0b1117"))
		paint_terrain(self)
	if not retained_terrain: paint_cells(self)
	movement_vfx.paint(self,project,half_width,visual_state.visible if is_presenting() else session.floor_state.visible)
	for actor in (visual_state.actors if is_presenting() else session.party+session.npcs+session.enemies):
		var point: Vector2i = actor.pos
		if actor.hp > 0 and (visual_state.visible if is_presenting() else session.floor_state.visible).has(point):
			var center := display_center(actor)
			draw_set_transform(center*camera.zoom+camera.offset,0,Vector2(1,0.45)*camera.zoom)
			draw_circle(Vector2.ZERO,half_width*0.6,Color(0,0,0,0.5))
			draw_set_transform(camera.offset,0,Vector2.ONE*camera.zoom)
			var side := half_width*1.65
			var flash := Color.WHITE
			if actor.enemy:
				flash = {"MELEE":Color.WHITE,"RANGED":Color("b8d9a2"),"CASTER":Color("c5a5ef")}.get(actor.get("role","MELEE"),Color.WHITE)
			center += hit_offset(point)
			var struck := hit_flash(point)
			if struck.a > 0: flash = struck
			var body: Vector2 = center+(movement_vfx.body_offset(int(actor.id),half_width) if session.free_movement and not is_presenting() else Vector2.ZERO)
			var actor_rect := Rect2(body-Vector2.ONE*side/2,Vector2.ONE*side)
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

	draw_free_intents()
	draw_distant_npcs()
	draw_movement_previews()
	draw_action_previews()
	draw_set_transform(Vector2.ZERO)
	painting = false

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
	var color := HOSTILE_NPC_COLOR if visual_wanderer(actor) and actor.get("hostile",false) else NPC_COLOR if visual_wanderer(actor) else Color("eea38c") if actor.enemy else Color("b9dcd6")
	var base := center+Vector2(0,half_width*0.65)
	if actor.enemy:
		outline(PackedVector2Array([base+Vector2(-half_width*0.65,0),base+Vector2(0,-half_width*0.23),base+Vector2(half_width*0.65,0),base+Vector2(0,half_width*0.23)]),color,1.5)
	else:
		draw_set_transform(base*impact_transform().zoom+impact_transform().offset,0,Vector2(1,0.36)*impact_transform().zoom)
		draw_arc(Vector2.ZERO,half_width*0.65,0,TAU,32,color,2.0,true)
		draw_set_transform(impact_transform().offset,0,Vector2.ONE*impact_transform().zoom)

func visual_wanderer(actor: Dictionary) -> bool:
	return session.wanderer(actor) and not bool(actor.get("party_member",false))

func status_actors() -> Array:
	if session == null: return []
	var actors: Array = visual_state.get("actors",[]) if is_presenting() else session.party+session.enemies+session.npcs
	var seen: Dictionary = visual_state.get("visible",{}) if is_presenting() else session.floor_state.visible
	var time: int = int(visual_state.get("time",session.time)) if is_presenting() else int(session.time)
	return actors.filter(func(actor): return seen.has(actor.pos) and not StatusVfx.styles(actor,time).is_empty() and Rect2(Vector2(-half_width*2,-half_width*2),size+Vector2.ONE*half_width*4).has_point(display_center(actor)))

func draw_status_visuals(canvas) -> void:
	if session == null: return
	var time: int = int(visual_state.get("time",session.time)) if is_presenting() else int(session.time)
	for actor in status_actors():
		var foot := display_center(actor)+hit_offset(actor.pos)+Vector2(0,half_width*0.69)
		StatusVfx.draw(canvas,actor,time,foot,half_width*(1.25 if actor.get("boss",false) else 1.0),status_visual_clock)

func _draw_foreground(canvas: Node2D) -> void:
	if session == null or session.tiles.is_empty(): return
	var camera := impact_transform()
	canvas.draw_set_transform(camera.offset,0,Vector2.ONE*camera.zoom)
	draw_status_visuals(canvas)
	var actors: Array = visual_state.actors if is_presenting() else session.party+session.enemies+session.npcs
	for actor in actors:
		if actor.hp <= 0: continue
		# A recruit is a companion now: the third colour and the name tag belong
		# to those still out on their own.
		var npc: bool = visual_wanderer(actor)
		var seen: bool = (visual_state.visible if is_presenting() else session.floor_state.visible).has(actor.pos)
		# An awake npc keeps its tag out of sight; anyone else is only drawn in the light.
		if not seen and not (npc and actor.get("awake",false)): continue
		var fade: float = 1.0 if seen else 0.5
		var center := display_center(actor)
		if npc:
			var npc_color: Color = HOSTILE_NPC_COLOR if actor.get("hostile",false) else NPC_COLOR
			canvas.draw_string(ui_font,center+Vector2(-40,-half_width*1.1),str(actor.name),HORIZONTAL_ALIGNMENT_CENTER,80,10,Color(npc_color,fade))
			var doing: String = str(actor.get("activity",""))
			if not doing.is_empty():
				canvas.draw_string(ui_font,center+Vector2(-45,half_width+10),doing,HORIZONTAL_ALIGNMENT_CENTER,90,9,Color("cfc6ab",fade))
		canvas.draw_rect(Rect2(center+Vector2(-12,half_width-5),Vector2(24,3)),Color(Color("191d24"),fade))
		canvas.draw_rect(Rect2(center+Vector2(-12,half_width-5),Vector2(24*float(actor.hp)/actor.max_hp,3)),Color(HOSTILE_NPC_COLOR if actor.get("hostile",false) else NPC_COLOR,fade) if npc else Color("ce7770") if actor.enemy else Color("9ec987"))
	if not is_presenting():
		for actor in session.party:
			if not session.Downed.is_downed(actor) or not session.floor_state.visible.has(actor.pos): continue
			var center := cell_center(actor.pos)
			canvas.draw_circle(center,half_width*0.45,Color(0.38,0.07,0.07,0.9))
			canvas.draw_arc(center,half_width*0.45,0,TAU,24,Color("ffad91"),2.0,true)
			canvas.draw_string(ui_font,center+Vector2(-15,5),"%d" % int(actor.bleedout_turns),HORIZONTAL_ALIGNMENT_CENTER,30,15,Color("fff0dd"))
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
		var definition: Dictionary = session.Abilities.definition(skill_id)
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
	for actor in actors:
		if str(actor.get("boss_kind","")) != "golem" or int(actor.hp) <= 0 or not _label_visible(actor): continue
		var above := cell_center(actor.pos)-Vector2(0,half_width*3.4)
		var gauge := Rect2(above-Vector2(30,9),Vector2(60,18))
		canvas.draw_rect(gauge,Color(0.2,0.05,0.02,0.85))
		canvas.draw_string(ui_font,gauge.position+Vector2(2,13),"열기 %d" % int(actor.get("heat",0)),HORIZONTAL_ALIGNMENT_CENTER,56,11,Color("ffb36b"))
	if not is_presenting(): draw_action_overlay(canvas)
	for effect in effects:
		if not effect_visible(effect): continue
		var kind := str(effect.get("kind",""))
		if kind == "VFX": draw_effect_visual(effect,canvas)
		elif kind == "ENEMY_ATTACK": draw_enemy_attack(effect,canvas)
		elif kind == "ATTACK_SWING": draw_swing(effect,canvas)
		elif kind == "MISS": draw_miss(effect,canvas)
		elif kind == "SPEECH": draw_speech(effect,canvas)
		elif kind == "REACTION": draw_reaction(effect,canvas)
		elif kind == "PROC": draw_proc(effect,canvas)
		elif effect.has("amount"): draw_hit(effect,canvas)
	canvas.draw_set_transform(Vector2.ZERO)
	# The edges of the screen flare red while the party is being hurt.
	for effect in effects:
		if not hits_party(effect) or not effect_visible(effect): continue
		var t := clock_of(effect)
		if t < 0 or t >= 0.32: continue
		var alpha := 0.22*(1.0-t/0.32)
		var edge := minf(size.x,size.y)*0.08
		for band in [Rect2(0,0,size.x,edge),Rect2(0,size.y-edge,size.x,edge),Rect2(0,0,edge,size.y),Rect2(size.x-edge,0,edge,size.y)]:
			canvas.draw_rect(band,Color(0.85,0.05,0.02,alpha))
		canvas.draw_rect(Rect2(Vector2.ZERO,size),Color(0.7,0.04,0.02,alpha*0.45))
		break
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
	if joystick_active:
		canvas.draw_circle(joystick_origin,JOYSTICK_RADIUS,Color(0.05,0.06,0.08,0.65))
		canvas.draw_arc(joystick_origin,JOYSTICK_RADIUS,0,TAU,48,Color("dbcaa2",0.8),2,true)
		canvas.draw_circle(joystick_origin+joystick_offset,19,Color("dbcaa2",0.9))
		canvas.draw_arc(joystick_origin+joystick_offset,19,0,TAU,32,Color("242126"),2,true)

## Outlined text, the Forge Master way: an ink rim under a bright fill.
func draw_outlined(canvas: Node2D, position: Vector2, text: String, font_size: int, color: Color) -> void:
	if ui_font == null: return
	var width := ui_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var at := position-Vector2(width/2,0)
	canvas.draw_string_outline(ui_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,maxi(4,font_size/4),Color(INK,color.a))
	canvas.draw_string(ui_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

## Actual damage keeps its semantic impact and a rising number.
func draw_hit(effect: Dictionary, canvas: Node2D) -> void:
	var t := clock_of(effect)
	if t < 0 or t >= 0.95: return
	if int(effect.get("amount",0)) <= 0: return
	draw_effect_visual(effect,canvas)
	var party := hits_party(effect)
	var center := effect_center(effect)-Vector2(0,half_width*0.7)
	var seed := float((int(effect.cell.x)*73+int(effect.cell.y)*151+int(effect.get("amount",0))*17)%360)
	var amount := int(effect.get("amount",0))
	var pop := 1.0+0.7*maxf(0,1.0-t/0.1)
	var font_size := int((26 if party else 22)*pop)
	var alpha := clampf((0.95-t)/0.35,0,1)
	var drift := Vector2(sin(deg_to_rad(seed))*10,-half_width*0.5-t*42)
	draw_outlined(canvas,center+drift,"-%d" % amount,font_size,Color(Color("ff5a48") if party else Color("fff4c8"),alpha))

## A melee swing: a bright crescent sweeping across the target.
func draw_swing(effect: Dictionary, canvas: Node2D) -> void:
	var t := clock_of(effect)
	if t < 0 or t >= 0.22: return
	var progress := t/0.22
	var target := effect_center(effect)-Vector2(0,half_width*0.6)
	var heading := Vector2(effect.cell-effect.from).angle()
	var start := heading-PI*0.6+PI*1.2*maxf(0,progress-0.35)
	var end := heading-PI*0.6+PI*1.2*minf(1,progress*1.6)
	if end <= start: return
	var radius := half_width*0.95
	canvas.draw_arc(target,radius,start,end,16,Color(INK,1.0-progress),9,true)
	canvas.draw_arc(target,radius,start,end,16,Color(1,0.96,0.85,1.0-progress),4.5,true)

## A blow that found nothing: the word floats off the target, pale.
func draw_miss(effect: Dictionary, canvas: Node2D) -> void:
	var t := clock_of(effect)
	if t < 0 or t >= 0.8: return
	draw_effect_visual(effect,canvas)
	var center := effect_center(effect)-Vector2(0,half_width*(1.2+t*0.8))
	draw_outlined(canvas,center,str(effect.get("text","회피")),int(18*(1.0+0.4*maxf(0,1.0-t/0.1))),Color(0.8,0.9,1.0,clampf((0.8-t)/0.3,0,1)))

func draw_reaction(effect: Dictionary, canvas: Node2D) -> void:
	var t := clock_of(effect)
	if t < 0 or t >= 1.1: return
	draw_effect_visual(effect,canvas)
	var center := effect_center(effect)-Vector2(0,half_width*(1.6+t*0.9))
	var grow := 1.0+0.6*maxf(0,1.0-t/0.12)
	draw_outlined(canvas,center,str(effect.get("text","")),int(24*grow),Color(1.0,0.86,0.35,clampf((1.1-t)/0.35,0,1)))

## A soul stone's proc: its word over the cell, smaller than a reaction's and
## in its tone's colour. Several on one cell stack upward instead of overlapping.
const PROC_COLORS := {"buff":Color("ffd35a"),"heal":Color("6fe07a"),"debuff":Color("c58cff"),"crit":Color("ff4a3a")}
func draw_proc(effect: Dictionary, canvas: Node2D) -> void:
	var t := clock_of(effect)
	if t < 0 or t >= 1.0: return
	draw_effect_visual(effect,canvas)
	var stack := 0
	for other in effects:
		if is_same(other,effect): break
		if str(other.get("kind","")) == "PROC" and other.get("cell") == effect.get("cell"): stack += 1
	# Above the rising damage number, not on it: one line higher for every
	# earlier proc on the same cell.
	var center := effect_center(effect)-Vector2(0,half_width*2.7+t*16+stack*19)
	var color: Color = PROC_COLORS.get(str(effect.get("tone","buff")),PROC_COLORS.buff)
	color.a = clampf((1.0-t)/0.3,0,1)
	draw_outlined(canvas,center,str(effect.get("text","")),int(15*(1.0+0.4*maxf(0,1.0-t/0.1))),color)

func draw_speech(effect: Dictionary, canvas: Node2D) -> void:
	if clock_of(effect) >= 2.5: return
	var text := str(effect.get("text",""))
	var width := clampf(text.length()*11.0+8.0,70.0,220.0)
	var center := effect_center(effect)-Vector2(0,half_width*2.6)
	var box := Rect2(Vector2(clampf(center.x-width/2.0,2,maxf(2,size.x-width-2)),maxf(origin.y,center.y-18)),Vector2(width,18))
	canvas.draw_rect(box,Color(0.08,0.03,0.04,0.88))
	canvas.draw_rect(box,Color("d98a8a",0.8),false,1)
	canvas.draw_string(ui_font,box.position+Vector2(4,13),text,HORIZONTAL_ALIGNMENT_CENTER,width-8,11,Color("fff0e8"))

func draw_enemy_attack(effect: Dictionary, canvas: Node2D) -> void:
	# Empty affected cells still show the actual strike, never a generic blast.
	# Occupied cells use their damage event, avoiding a double impact.
	var visible: Dictionary = visual_state.get("visible",{}) if is_presenting() else session.floor_state.visible
	for cell in effect.get("cells",[]):
		if not visible.has(cell): continue
		if effects.any(func(e): return e.get("kind","") == "" and e.get("cell") == cell and int(e.get("amount",0)) > 0): continue
		var strike: Dictionary = effect.duplicate()
		strike.cell = cell
		strike.kind = "VFX"
		strike.visual_clock = clock_of(effect)
		strike.vfx = Vfx.damage_style(str(effect.get("element",effect.get("form","IMPACT"))),str(effect.get("form","IMPACT")))
		draw_effect_visual(strike,canvas)

func effect_visible(effect: Dictionary) -> bool:
	if session == null: return false
	var seen: Dictionary = visual_state.get("visible",{}) if is_presenting() else session.floor_state.visible
	if str(effect.get("kind","")) == "ENEMY_ATTACK":
		return effect.get("cells",[]).any(func(cell): return seen.has(cell))
	return seen.has(effect.get("cell",Vector2i(-1,-1)))

func draw_effect_visual(effect: Dictionary, canvas) -> void:
	if not effect_visible(effect): return
	var style := str(effect.get("vfx",""))
	if style.is_empty() and effect.get("kind","") == "": style = Vfx.damage_style(str(effect.get("element",effect.get("form",""))),str(effect.get("form","")))
	var center := effect_center(effect)-Vector2(0,half_width*0.7)
	var seen: Dictionary = visual_state.get("visible",{}) if is_presenting() else session.floor_state.visible
	var from: Vector2i = effect.get("from",effect.cell)
	var start := center
	# A trail is drawn only when every cell along it is visible, including its
	# origin. Offscreen autonomous combat never leaks through fog.
	var steps := maxi(absi(from.x-effect.cell.x),absi(from.y-effect.cell.y))
	var path_visible := steps > 0
	for i in range(steps+1):
		var point := Vector2i(Vector2(from).lerp(Vector2(effect.cell),float(i)/maxi(1,steps)).round())
		if not seen.has(point): path_visible = false; break
	if path_visible: start = cell_center(from)-Vector2(0,half_width*0.7)
	var t := clock_of(effect)
	if steps > 1 and path_visible and effect.get("kind","") == "" and style in ["pierce","fire","ice","poison","hex"]:
		Vfx.projectile(canvas,style,start,center,half_width,t)
	Vfx.draw(canvas,style,center,start,half_width,t)

func _input(event: InputEvent) -> void:
	# HUD refreshes reparent this map. Keep the active finger captured even if
	# it crosses a HUD button or the original GUI touch capture was cleared.
	if not fullscreen or not joystick_active: return
	var owned := false
	if event is InputEventScreenDrag: owned = event.index == joystick_pointer
	elif event is InputEventScreenTouch: owned = not event.pressed and event.index == joystick_pointer
	elif event is InputEventMouseMotion: owned = joystick_pointer == -1
	elif event is InputEventMouseButton: owned = joystick_pointer == -1 and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if owned:
		joystick_input(event); get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if fullscreen and session != null and session.free_movement and joystick_input(event):
		accept_event(); return
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

func begin_joystick(at: Vector2, pointer: int) -> void:
	gesture_started.emit()
	joystick_active = true; joystick_pointer = pointer
	joystick_origin = at; joystick_offset = Vector2.ZERO; joystick_dragged = false
	touch_pressed_at = Time.get_ticks_msec()
	queue_redraw()

func drag_joystick(at: Vector2) -> void:
	joystick_offset = (at-joystick_origin).limit_length(JOYSTICK_RADIUS)
	if joystick_offset.length() > JOYSTICK_DEADZONE: joystick_dragged = true
	queue_redraw()

func cancel_joystick() -> void:
	joystick_active = false; joystick_pointer = -2; joystick_offset = Vector2.ZERO
	queue_redraw()

func end_joystick(at: Vector2, canceled: bool = false) -> void:
	var tap: bool = not joystick_dragged and not canceled
	cancel_joystick()
	if tap:
		if Time.get_ticks_msec()-touch_pressed_at >= 450: emit_inspection(at)
		else: emit_cell(at)

func joystick_direction() -> Vector2:
	return joystick_offset.normalized() if joystick_active and joystick_offset.length() > JOYSTICK_DEADZONE else Vector2.ZERO

func joystick_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		suppress_mouse_until = Time.get_ticks_msec()+500
		if event.pressed:
			if not joystick_active: begin_joystick(event.position,event.index)
		elif joystick_active and joystick_pointer == event.index: end_joystick(event.position,event.canceled)
		return true
	if event is InputEventScreenDrag:
		suppress_mouse_until = Time.get_ticks_msec()+500
		if joystick_active and event.index == joystick_pointer: drag_joystick(event.position)
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec() < suppress_mouse_until: return true
		if event.pressed: begin_joystick(event.position,-1)
		elif joystick_active and joystick_pointer == -1: end_joystick(event.position)
		return true
	if event is InputEventMouseMotion and joystick_active and joystick_pointer == -1:
		drag_joystick(event.position); return true
	return false

func emit_cell(position: Vector2) -> void:
	if is_presenting(): return
	if fullscreen:
		world_pressed.emit(world_at(position)); return
	if position.y < origin.y or position.y >= origin.y+size.x: return
	var point := cell_at(position)
	if session != null and session.inside(point): cell_pressed.emit(point)

func emit_inspection(position: Vector2) -> void:
	if is_presenting(): return
	if fullscreen:
		if not Rect2(Vector2.ZERO,size).has_point(position): return
	elif position.y < origin.y or position.y >= origin.y+size.x: return
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

func world_at(screen: Vector2) -> Vector2:
	geometry()
	var camera := impact_transform()
	return ((screen-camera.offset)/camera.zoom-origin)/(half_width*2)+camera_origin()

func animate_world(before: Dictionary, duration: float = 0.11) -> void:
	for actor in session.party+session.npcs+session.enemies:
		var id: int = int(actor.id)
		var end: Vector2 = session.Free.position(actor)
		if before.has(id) and Vector2(before[id]).distance_to(end) > 0.001:
			var start: Vector2 = display_world_position(actor) if world_walks.has(id) else Vector2(before[id])
			world_walks[id] = {"from":start,"to":end,"elapsed":0.0,"duration":maxf(0.01,duration)}
	queue_redraw()

func reset_motion() -> void:
	world_walks.clear(); movement_vfx.reset(); walk_actor_id = -1
	queue_redraw()

func effect_center(effect: Dictionary) -> Vector2:
	return project(effect.world_cell) if effect.has("world_cell") else cell_center(effect.cell)

func effect_source(effect: Dictionary) -> Vector2:
	return project(effect.world_from) if effect.has("world_from") else cell_center(effect.get("from",effect.cell))

func draw_free_intents() -> void:
	if not session.free_movement: return
	var drawn: Dictionary = {}
	for intent in session.intents:
		if not intent.has("world_center") or drawn.has(int(intent.id)) or not session.floor_state.visible.has(intent.cell): continue
		drawn[int(intent.id)] = true
		var center: Vector2 = project(intent.world_center)
		var radius: float = float(intent.world_radius)*half_width*2
		draw_circle(center,radius,Color(1,0.45,0.05,0.2))
		draw_arc(center,radius,0,TAU,48,Color("ffb447"),2,true)
		draw_string(ui_font,center+Vector2(-4,4),"!",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.WHITE)
