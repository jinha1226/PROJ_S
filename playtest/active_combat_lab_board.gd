extends Control

signal picked(cell:Vector2i)
const Tiles=preload("res://playtest/topdown_tile_assets.gd")
const Actors=preload("res://playtest/fixed_front_topdown_assets.gd")
var model
var skill:=""
var selected_id:=-1
var _pressed:=Vector2.ZERO
var _touch:=-1
var _ignore_mouse_until:=0

func _ready()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(queue_redraw)

func board_rect()->Rect2:
	var side:=minf(size.x,size.y)
	return Rect2((size-Vector2.ONE*side)*0.5,Vector2.ONE*side)

func _draw()->void:
	if model==null:return
	var rect:=board_rect();var cell:=rect.size.x/18.0
	for y in range(18):
		for x in range(18):
			var position:=Vector2i(x,y)
			var spec:=Tiles.tile_spec({"visibility_state":"VISIBLE","terrain_id":"wall" if model.blocked.has(position) else "stone_floor"},position,1)
			draw_texture_rect_region(spec.texture,Rect2(rect.position+Vector2(position)*cell,Vector2.ONE*cell),spec.region,Color("#b3b8b6"))
	for actor in model.actors:
		if int(actor.hp)<=0:continue
		var center:Vector2=rect.position+(Vector2(actor.position)+Vector2(0.5,0.5))*cell
		var texture:Texture2D=Actors.BODY_TEXTURES.get(actor.species_id,Actors.MONSTER_TEXTURES.get(actor.species_id))
		if texture!=null:draw_texture_rect(texture,Rect2(center-Vector2(cell*0.6,cell*0.7),Vector2.ONE*cell*1.2),false)
		var bar:=Rect2(center+Vector2(-cell*0.4,-cell*0.62),Vector2(cell*0.8,3))
		draw_rect(bar,Color.BLACK)
		var filled:=bar;filled.size.x*=float(actor.hp)/int(actor.max_hp)
		draw_rect(filled,Color("#70bc59") if actor.team=="PARTY" else Color("#d24d4d"))
		if int(actor.barrier)>0:draw_arc(center,cell*0.58,0,TAU,24,Color("#55cce0"),2,true)
		var marker:=str(actor.id) if actor.team=="PARTY" else "E%d"%(int(actor.id)-4)
		var marker_pos:=center+Vector2(-cell*0.5,cell*0.65)
		draw_string_outline(ThemeDB.fallback_font,marker_pos,marker,HORIZONTAL_ALIGNMENT_LEFT,-1,11,3,Color.BLACK)
		draw_string(ThemeDB.fallback_font,marker_pos,marker,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#b8e8a0") if actor.team=="PARTY" else Color("#ffac9e"))
		if not skill.is_empty() and model.preview(1,skill,int(actor.id)).accepted:
			draw_rect(Rect2(center-Vector2.ONE*cell*0.47,Vector2.ONE*cell*0.94),Color("#d4b96a"),false,1)
		if actor.id==selected_id:draw_arc(center,cell*0.65,0,TAU,24,Color.WHITE,2,true)

func _gui_input(event:InputEvent)->void:
	if event is InputEventScreenTouch:
		_ignore_mouse_until=Time.get_ticks_msec()+700
		if event.pressed:_touch=event.index;_pressed=event.position
		elif event.index==_touch:
			_touch=-1
			if not event.canceled and _pressed.distance_to(event.position)<10:_pick(event.position)
		accept_event()
	elif event is InputEventScreenDrag and event.index==_touch:
		if _pressed.distance_to(event.position)>=10:_touch=-1
		accept_event()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.device==InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec()<_ignore_mouse_until:return
		if event.pressed:_pressed=event.position
		elif _pressed.distance_to(event.position)<10:_pick(event.position)
		accept_event()

func _pick(position:Vector2)->void:
	var rect:=board_rect()
	if not rect.has_point(position):return
	var offset:Vector2=(position-rect.position)/(rect.size.x/18.0)
	picked.emit(Vector2i(floori(offset.x),floori(offset.y)))
