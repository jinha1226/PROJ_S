extends "res://game/rebuilt/board.gd"
const Pawns=preload("res://playtest/fantasy_pawn_assets.gd")
signal inspect_requested(cell:int)
var pressed_at=0
var target_cells:Array[int]=[]
var cursor=-1
func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("080b12"))
	if world==null:return
	var unit=cell_size();var origin=Vector2i(floori(camera.x)-9,floori(camera.y)-10)
	var t=progress();t=t*t*(3.0-2.0*t)
	for y in range(22):
		for x in range(20):
			var p=origin+Vector2i(x,y)
			if not world.in_bounds(p):continue
			var c=world.index(p)
			if world.memory[c]==0:continue
			var center=pixel(Vector2(p));var rect=Rect2(center-Vector2.ONE*unit/2,Vector2.ONE*unit)
			var seen=world.visible[c]==1
			var tile=world.terrain[c]
			var cache_key=str(c)+":"+tile
			if not specs.has(cache_key):specs[cache_key]=Tiles.tile_spec({"terrain_id":tile,"visibility_state":"VISIBLE"},p,world.floor_number)
			var spec:Dictionary=specs[cache_key]
			var tint=Color.WHITE if seen else Color(0.25,0.28,0.32)
			draw_texture_rect_region(spec.texture,rect,spec.region,tint)
			var hazard:Dictionary=world.current().hazards.get(str(c),{})
			if not hazard.is_empty():
				var color:Color={"fire":Color("e96338"),"poison":Color("73a939"),"ice":Color("57b5dd"),"fog":Color("a4abbc"),"trap":Color("deac4e")}[hazard.kind]
				color.a=0.45 if seen else 0.15;draw_rect(rect,color)
				if hazard.kind=="trap":draw_string(GameFont,center+Vector2(-unit/4,unit/4),"^",0,-1,int(unit*0.7),Color.GOLD)
			var f:Dictionary=world.current().features.get(str(c),{})
			if not f.is_empty():
				var symbol={"stairs":">","altar":"A","rune":"R","orb":"O","cache":"$"}.get(f.kind,"?")
				if f.kind=="stairs" and (f.to=="OUT" or f.to=="D1" or f.to=="D2" or f.to=="D3"):symbol="<"
				draw_string(GameFont,center+Vector2(-unit*0.3,unit*0.3),symbol,0,-1,int(unit*0.9),Color("78e2da")*tint)
			if seen and world.current().loot.has(str(c)):draw_circle(center,unit*0.13,Color("edcb7b"))
			if c in target_cells:draw_rect(rect,Color(1,0.4,0.2,0.35))
			if c==cursor:draw_rect(rect.grow(-1),Color.WHITE,false,2)
	for a in world.actors:
		if a.floor!=world.floor_id or a.hp<=0 or world.visible[int(a.cell)]==0:continue
		var p=Vector2(world.position(a.cell))
		if motions.has(a.id):p=Vector2(world.position(motions[a.id][0])).lerp(p,t)
		var center=pixel(p);var rect=Rect2(center-Vector2.ONE*unit/2,Vector2.ONE*unit)
		draw_texture_rect(Pawns.body_texture(a.sprite),rect,false,Color.WHITE if a.team!="ally" else Color("a9cbea"))
		if int(a.id)==0:draw_rect(rect.grow(-1),Color("e9c366"),false,1.5)
		if a.team=="ally":draw_arc(center,unit*0.44,0,TAU,16,Color("72d1db"),1.5)
		if a.hp<a.max_hp:
			draw_rect(Rect2(rect.position+Vector2(0,unit-3),Vector2(unit,3)),Color("3a2020"))
			draw_rect(Rect2(rect.position+Vector2(0,unit-3),Vector2(unit*float(a.hp)/a.max_hp,3)),Color("b9d47a") if a.team!="enemy" else Color("d96659"))

func inspect_at(pointer:Vector2)->void:
	var point=(pointer-size*0.5)/cell_size()+camera
	var cell=Vector2i(roundi(point.x),roundi(point.y))
	if world.in_bounds(cell):inspect_requested.emit(world.index(cell))
func _gui_input(event:InputEvent)->void:
	if event is InputEventScreenTouch:
		suppress_mouse=Time.get_ticks_msec()+600
		if event.pressed:touch_start=event.position;pressed_at=Time.get_ticks_msec()
		elif not event.canceled and touch_start.distance_to(event.position)<12:
			if Time.get_ticks_msec()-pressed_at>=450:inspect_at(event.position)
			else:tap(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and Time.get_ticks_msec()>suppress_mouse:
		if event.button_index==MOUSE_BUTTON_LEFT:tap(event.position)
		elif event.button_index==MOUSE_BUTTON_RIGHT:inspect_at(event.position)
		accept_event()
