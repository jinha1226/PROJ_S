extends Control

signal cell_pressed(cell:int)
const Tiles=preload("res://playtest/topdown_tile_assets.gd")
const Human=preload("res://assets/topdown_fixed_front/actors/base/human.png")
const Goblin=preload("res://assets/topdown_fixed_front/monsters/goblin.png")
const GameFont=preload("res://assets/fonts/LivingWorldMonoKRBold.ttf")
var world
var camera:=Vector2.ZERO
var camera_from:=Vector2.ZERO
var camera_to:=Vector2.ZERO
var animation_started:int=-1
var motions:Dictionary={}
var specs:Dictionary={}
var theme_floor:int=-1
var touch_start:=Vector2.ZERO
var suppress_mouse:int=0
var last_draw_usec:int=0
const VIEW:=15.0

func _ready()->void:
	clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)

func sync(p_world,animate:bool=true)->void:
	world=p_world
	if theme_floor!=world.floor_number:
		specs.clear();theme_floor=world.floor_number;animate=false
	camera_from=camera;camera_to=Vector2(world.position(world.hero().cell))
	motions.clear()
	if animate:
		for effect in world.effects:
			if effect.kind=="move":
				if not motions.has(effect.actor):motions[effect.actor]=[effect.from,effect.to]
				else:motions[effect.actor][1]=effect.to
		animation_started=Time.get_ticks_msec();set_process(true)
	else:camera=camera_to;animation_started=-1;set_process(false)
	queue_redraw()

func progress()->float:
	if animation_started<0:return 1.0
	return clampf(float(Time.get_ticks_msec()-animation_started)/120.0,0.0,1.0)

func _process(_delta:float)->void:
	var t:=progress();camera=camera_from.lerp(camera_to,t*t*(3.0-2.0*t))
	queue_redraw()
	if t>=1.0:animation_started=-1;motions.clear();set_process(false)

func cell_size()->float:return minf(size.x,size.y)/VIEW
func pixel(p:Vector2)->Vector2:return size*0.5+(p-camera)*cell_size()

func _draw()->void:
	var started:=Time.get_ticks_usec()
	draw_rect(Rect2(Vector2.ZERO,size),Color("080b12"))
	if world==null:return
	var unit:=cell_size()
	var origin:=Vector2i(floori(camera.x)-8,floori(camera.y)-8)
	var t:=progress();t=t*t*(3.0-2.0*t)
	var hero_cell:Vector2i=world.position(world.hero().cell)
	for y in range(18):
		for x in range(18):
			var p:=origin+Vector2i(x,y)
			if not world.in_bounds(p):continue
			var cell:int=world.index(p)
			if world.memory[cell]==0:continue
			var centre:=pixel(Vector2(p))
			var rect:=Rect2(centre-Vector2.ONE*unit*0.5,Vector2.ONE*unit)
			if not specs.has(cell):
				specs[cell]=Tiles.tile_spec({"terrain_id":world.terrain[cell],"visibility_state":"VISIBLE"},p,world.floor_number)
			var spec:Dictionary=specs[cell]
			var seen:bool=world.visible[cell]==1
			var brightness:=0.20
			if seen:
				var distance:=Vector2(p-hero_cell).length()/6.0
				brightness=lerpf(0.96,0.68,distance) if world.floor_number==1 else lerpf(0.85,0.40,distance)
				if world.torch_lit:brightness=maxf(brightness,lerpf(1.0,0.82,distance))
				brightness=maxf(brightness,world.light_strength[cell])
			draw_texture_rect_region(spec.texture,rect,spec.region,Color(brightness,brightness,brightness))
			if cell==world.exit_cell:draw_string(GameFont,centre+Vector2(-unit*0.25,unit*0.25),">",HORIZONTAL_ALIGNMENT_LEFT,-1,int(unit),Color("7ae1d0") if seen else Color("29423e"))
			if cell in world.lights:draw_circle(centre,unit*0.09,Color("ffbd60") if seen else Color("493720"))
			if seen and world.loot.has(str(cell)):draw_circle(centre,unit*0.10,Color("efbf55") if world.loot[str(cell)]=="gold" else Color("ed7280"))
	for actor in world.actors:
		if actor.hp<=0 or world.visible[int(actor.cell)]==0:continue
		var p:=Vector2(world.position(actor.cell))
		if motions.has(actor.id):p=Vector2(world.position(motions[actor.id][0])).lerp(p,t)
		var centre:=pixel(p)
		var rect:=Rect2(centre-Vector2.ONE*unit*0.5,Vector2.ONE*unit)
		draw_texture_rect(Human if actor.team!="enemy" else Goblin,rect,false)
		if actor.team=="enemy" and "FIREBOLT" in actor.bound_abilities:
			draw_circle(centre+Vector2(unit*0.3,-unit*0.3),unit*0.12,Color("ff8040"))
		if actor.team=="companion":draw_arc(centre,unit*0.43,0,TAU,16,Color("78d8c5"),1.0)
		if actor.id==0:draw_rect(rect.grow(-1.5),Color("e9c366"),false,1.0)
	last_draw_usec=Time.get_ticks_usec()-started

func _gui_input(event:InputEvent)->void:
	if event is InputEventScreenTouch:
		suppress_mouse=Time.get_ticks_msec()+600
		if event.pressed:touch_start=event.position
		elif not event.canceled and touch_start.distance_to(event.position)<12:tap(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		if Time.get_ticks_msec()>suppress_mouse:tap(event.position)
		accept_event()

func tap(pointer:Vector2)->void:
	if world==null:return
	var point:=(pointer-size*0.5)/cell_size()+camera
	var cell:=Vector2i(roundi(point.x),roundi(point.y))
	if world.in_bounds(cell):cell_pressed.emit(world.index(cell))
