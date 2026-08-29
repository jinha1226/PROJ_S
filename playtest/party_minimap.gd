class_name PartyMinimap
extends Control

const AsciiStyleScript=preload("res://playtest/ascii_visual_style.gd")

const UNSEEN_COLOR:=Color("#010306")
const MEMORY_COLOR:=Color("#17212a")
const VISIBLE_COLOR:=Color("#526170")
const WALL_MEMORY_COLOR:=Color("#27323c")
const WALL_VISIBLE_COLOR:=Color("#9aa8b4")
const HERO_COLOR:=Color("#ffdc55")
const ENEMY_COLOR:=Color("#ff615c")

var _width:=15
var _height:=15
var _cells:Dictionary={}

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	resized.connect(queue_redraw)

func set_observation(observation:Dictionary)->void:
	_width=maxi(1,int(observation.get("width",15)))
	_height=maxi(1,int(observation.get("height",15)))
	_cells.clear()
	for value in observation.get("cells",[]):
		if not value is Dictionary or not value.get("position") is Array \
				or value.position.size()!=2:continue
		var position:=Vector2i(int(value.position[0]),int(value.position[1]))
		_cells[_key(position)]=value.duplicate(true)
	queue_redraw()

func cell_draw_spec(position:Vector2i)->Dictionary:
	var row:Dictionary=_cells.get(_key(position),{})
	var state:="UNSEEN" if row.is_empty() else AsciiStyleScript.visibility_state(row)
	var terrain_id:=str(row.get("terrain_id","unknown"))
	var color:=UNSEEN_COLOR
	if state=="MEMORY":color=WALL_MEMORY_COLOR if terrain_id=="wall" else MEMORY_COLOR
	elif state=="VISIBLE":color=WALL_VISIBLE_COLOR if terrain_id=="wall" else VISIBLE_COLOR
	var marker:=""
	if state=="VISIBLE":
		for actor in row.get("actors",[]):
			if not actor is Dictionary:continue
			if bool(actor.get("is_protagonist",false)):
				marker="HERO";break
			if bool(actor.get("is_enemy",false)) or str(actor.get("faction_id",""))=="enemy":
				marker="ENEMY"
	return {"visibility_state":state,"terrain_id":terrain_id,"color":color,
		"marker":marker,"leaks_direction":false,"leaks_target":false}.duplicate(true)

func _draw()->void:
	if _width<=0 or _height<=0:return
	var cell:=minf(size.x/float(_width),size.y/float(_height))
	var map_size:=Vector2(cell*float(_width),cell*float(_height))
	var origin:=(size-map_size)*0.5
	draw_rect(Rect2(origin,map_size),UNSEEN_COLOR,true)
	for y in range(_height):
		for x in range(_width):
			var spec:=cell_draw_spec(Vector2i(x,y))
			var rect:=Rect2(origin+Vector2(float(x)*cell,float(y)*cell),Vector2(cell,cell))
			draw_rect(rect,spec.color,true)
			if str(spec.marker)=="HERO":
				draw_circle(rect.get_center(),maxf(1.5,cell*0.42),HERO_COLOR)
			elif str(spec.marker)=="ENEMY":
				draw_circle(rect.get_center(),maxf(1.3,cell*0.36),ENEMY_COLOR)
	# The parent HUD supplies a responsive glyph-drawn ASCII frame. Keep this
	# surface borderless so the map never falls back to a generic rectangle.

func _key(position:Vector2i)->String:
	return "%d:%d"%[position.x,position.y]
