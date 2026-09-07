class_name PartyMinimap
extends Control

## Low-resolution vector cartography. The world is folded into eight square
## sectors so the compact top rail remains legible at 360px without font glyphs.
## Static presentation state is cached only when its observation changes.

const AsciiStyleScript=preload("res://playtest/ascii_visual_style.gd")
const DarkSkin=preload("res://playtest/dark_pixel_ui_skin.gd")

const SECTOR_COLUMNS:=8
const SECTOR_ROWS:=8

const UNSEEN_COLOR:=DarkSkin.CANVAS
const MEMORY_COLOR:=Color("#66737b")
const VISIBLE_COLOR:=Color("#c7c2b3")
const WALL_MEMORY_COLOR:=Color("#3b555b")
const WALL_VISIBLE_COLOR:=Color("#4f9aa3")
const HERO_COLOR:=Color("#b8954d")
const ENEMY_COLOR:=Color("#a74343")
const EXIT_COLOR:=Color("#5f8a66")
const PORTAL_COLOR:=Color("#48bfc8")

const PRIMITIVE_NONE:="NONE"
const PRIMITIVE_TILE:="TILE"
const PRIMITIVE_CIRCLE:="CIRCLE"
const PRIMITIVE_DIAMOND:="DIAMOND"
const PRIMITIVE_RING:="RING"
const PRIMITIVE_TRIANGLE:="TRIANGLE"

const PRIORITY_UNKNOWN:=0
const PRIORITY_MEMORY:=10
const PRIORITY_WALL:=20
const PRIORITY_EXIT:=30
const PRIORITY_PORTAL:=31
const PRIORITY_THREAT:=40
const PRIORITY_HERO:=50

var _width:=15
var _height:=15
var _cells:Dictionary={}
var _sectors:Dictionary={}

func _init()->void:
	clip_contents=true
	set_process(false)

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_meta("visual_family",DarkSkin.VISUAL_FAMILY)
	set_meta("pixel_material","COMPACT_CARTOGRAPHY")
	clip_contents=true
	set_process(false)
	resized.connect(queue_redraw)

func set_observation(observation:Dictionary)->void:
	_width=maxi(1,int(observation.get("width",15)))
	_height=maxi(1,int(observation.get("height",15)))
	_cells.clear()
	for value in observation.get("cells",[]):
		if not value is Dictionary or not value.get("position") is Array \
				or value.position.size()!=2:continue
		var position:=Vector2i(int(value.position[0]),int(value.position[1]))
		if position.x<0 or position.y<0 or position.x>=_width or position.y>=_height:continue
		var state:=AsciiStyleScript.visibility_state(value)
		if state=="UNSEEN":continue
		var marker:=str(value.get("marker","")).to_upper()
		if marker.is_empty() and state=="VISIBLE":marker=_legacy_actor_marker(value)
		var feature_id:=str(value.get("feature_id",""))
		if marker.is_empty() and _is_exit_feature(feature_id):marker="EXIT"
		if marker.is_empty() and _is_anchor_feature(feature_id):marker="PORTAL"
		# Remembered static exits are safe. Every live marker is stripped outside
		# current visibility, so actors, targets and plans never leak through fog.
		if state!="VISIBLE" and marker not in ["EXIT","PORTAL"]:marker=""
		if marker not in ["","HERO","ENEMY","EXIT","PORTAL"]:marker=""
		# Rich actor, feature, hazard, direction and target payloads do not enter
		# minimap state; only three compact scalar fields are retained.
		_cells[_key(position)]={"visibility_state":state,
			"terrain_id":str(value.get("terrain_id","unknown")),"marker":marker}
	_rebuild_sector_cache()
	queue_redraw()

func _legacy_actor_marker(row:Dictionary)->String:
	for actor in row.get("actors",[]):
		if not actor is Dictionary:continue
		if bool(actor.get("is_protagonist",false)):return "HERO"
		if bool(actor.get("is_enemy",false)) or str(actor.get("faction_id",""))=="enemy":
			return "ENEMY"
	return ""

func _is_exit_feature(feature_id:String)->bool:
	return feature_id in ["run_exit_locked","run_exit_open",
		"floor_transition_portal_locked","floor_transition_portal"]

func _is_anchor_feature(feature_id:String)->bool:
	return feature_id in ["anchor_portal_inactive","anchor_portal_active"]

func _rebuild_sector_cache()->void:
	_sectors.clear()
	for key_value in _cells:
		var position:=_position_from_key(str(key_value))
		var sector:=world_to_sector(position)
		var candidate:=_candidate_for_row(_cells[key_value])
		var sector_key:=_key(sector)
		var current:Dictionary=_sectors.get(sector_key,_unknown_sector_spec(sector))
		if _candidate_wins(candidate,current):
			candidate["sector"]=sector
			_sectors[sector_key]=candidate
	# Materialize blanks so draw/test iteration remains a bounded 8x8 contract.
	for y in range(SECTOR_ROWS):
		for x in range(SECTOR_COLUMNS):
			var sector:=Vector2i(x,y);var sector_key:=_key(sector)
			if not _sectors.has(sector_key):_sectors[sector_key]=_unknown_sector_spec(sector)

func _candidate_wins(candidate:Dictionary,current:Dictionary)->bool:
	var candidate_priority:=int(candidate.get("priority",PRIORITY_UNKNOWN))
	var current_priority:=int(current.get("priority",PRIORITY_UNKNOWN))
	if candidate_priority!=current_priority:return candidate_priority>current_priority
	# Same-role sectors prefer current visibility regardless of DTO row order.
	return str(candidate.get("visibility_state","UNSEEN"))=="VISIBLE" \
		and str(current.get("visibility_state","UNSEEN"))!="VISIBLE"

func _candidate_for_row(row:Dictionary)->Dictionary:
	var state:=AsciiStyleScript.visibility_state(row)
	var marker:=str(row.get("marker","")).to_upper()
	if state=="VISIBLE" and marker=="HERO":
		return _shape_spec(PRIMITIVE_CIRCLE,HERO_COLOR,PRIORITY_HERO,"HERO",state,0.78)
	if state=="VISIBLE" and marker=="ENEMY":
		return _shape_spec(PRIMITIVE_DIAMOND,ENEMY_COLOR,PRIORITY_THREAT,"THREAT",state,0.78)
	if marker=="EXIT":
		return _shape_spec(PRIMITIVE_TRIANGLE,EXIT_COLOR,PRIORITY_EXIT,"EXIT",state,0.80)
	if marker=="PORTAL":
		return _shape_spec(PRIMITIVE_RING,PORTAL_COLOR,PRIORITY_PORTAL,"PORTAL",state,0.86)
	if str(row.get("terrain_id","unknown"))=="wall":
		return _shape_spec(PRIMITIVE_TILE,WALL_VISIBLE_COLOR if state=="VISIBLE" \
			else WALL_MEMORY_COLOR,PRIORITY_WALL,"STRUCTURE",state,0.88)
	return _shape_spec(PRIMITIVE_TILE,VISIBLE_COLOR if state=="VISIBLE" else MEMORY_COLOR,
		PRIORITY_MEMORY,"PASSABLE",state,0.42)

func _shape_spec(primitive:String,color:Color,priority:int,role:String,
		visibility_state:String,fill_ratio:float)->Dictionary:
	return {"primitive":primitive,"color":color,"priority":priority,"role":role,
		"visibility_state":visibility_state,"fill_ratio":fill_ratio,"leaks_actor":false,
		"leaks_direction":false,"leaks_target":false,"leaks_hazard":false}

func _unknown_sector_spec(sector:Vector2i)->Dictionary:
	var result:=_shape_spec(PRIMITIVE_NONE,UNSEEN_COLOR,PRIORITY_UNKNOWN,"UNKNOWN",
		"UNSEEN",0.0)
	result["sector"]=sector
	return result

func world_to_sector(position:Vector2i)->Vector2i:
	return Vector2i(clampi(int(floor(float(position.x)*SECTOR_COLUMNS/float(_width))),
		0,SECTOR_COLUMNS-1),clampi(int(floor(float(position.y)*SECTOR_ROWS/float(_height))),
		0,SECTOR_ROWS-1))

func sector_draw_spec(sector:Vector2i)->Dictionary:
	if sector.x<0 or sector.y<0 or sector.x>=SECTOR_COLUMNS or sector.y>=SECTOR_ROWS:
		return _unknown_sector_spec(sector).duplicate(true)
	return (_sectors.get(_key(sector),_unknown_sector_spec(sector)) as Dictionary).duplicate(true)

func cell_draw_spec(position:Vector2i)->Dictionary:
	var row:Dictionary=_cells.get(_key(position),{})
	var state:="UNSEEN" if row.is_empty() else AsciiStyleScript.visibility_state(row)
	var terrain_id:=str(row.get("terrain_id","unknown"))
	var color:=UNSEEN_COLOR
	if state=="MEMORY":color=WALL_MEMORY_COLOR if terrain_id=="wall" else MEMORY_COLOR
	elif state=="VISIBLE":color=WALL_VISIBLE_COLOR if terrain_id=="wall" else VISIBLE_COLOR
	var marker:=str(row.get("marker",""))
	if state!="VISIBLE" and marker not in ["EXIT","PORTAL"]:marker=""
	return {"visibility_state":state,"terrain_id":terrain_id,"color":color,
		"marker":marker,"leaks_direction":false,"leaks_target":false}.duplicate(true)

func cartography_spec()->Dictionary:
	return {"columns":SECTOR_COLUMNS,"rows":SECTOR_ROWS,"sector_count":_sectors.size(),
		"primitive":"VECTOR_SECTOR_MARKS","background":"BLACK_FIELD",
		"visual_family":DarkSkin.VISUAL_FAMILY,
		"uses_tile_rects":true,"uses_circles":true,"uses_polygons":true,
		"uses_fonts":false,"uses_images":false,
		"per_frame_process":false}.duplicate(true)

func _draw()->void:
	if _width<=0 or _height<=0 or size.x<=0.0 or size.y<=0.0:return
	draw_rect(Rect2(Vector2.ZERO,size),UNSEEN_COLOR,true)
	var slot:=Vector2(size.x/float(SECTOR_COLUMNS),size.y/float(SECTOR_ROWS))
	for y in range(SECTOR_ROWS):
		for x in range(SECTOR_COLUMNS):
			var rect:=Rect2(Vector2(float(x)*slot.x,float(y)*slot.y),slot)
			_draw_sector_shape(rect,sector_draw_spec(Vector2i(x,y)))
	# The parent supplies the existing compact UI frame.

func _draw_sector_shape(rect:Rect2,spec:Dictionary)->void:
	var primitive:=str(spec.get("primitive",PRIMITIVE_NONE))
	if primitive==PRIMITIVE_NONE:return
	var color:Color=spec.get("color",UNSEEN_COLOR)
	var ratio:=clampf(float(spec.get("fill_ratio",0.7)),0.1,1.0)
	var center:=rect.get_center();var half:=minf(rect.size.x,rect.size.y)*ratio*0.5
	match primitive:
		PRIMITIVE_TILE:
			draw_rect(Rect2(center-Vector2(half,half),Vector2(half*2.0,half*2.0)),color,true)
		PRIMITIVE_CIRCLE:
			draw_circle(center,maxf(1.0,half),color)
		PRIMITIVE_DIAMOND:
			draw_colored_polygon(PackedVector2Array([center+Vector2(0,-half),
				center+Vector2(half,0),center+Vector2(0,half),center+Vector2(-half,0)]),color)
		PRIMITIVE_RING:
			draw_circle(center,maxf(1.0,half),color)
			draw_circle(center,maxf(0.5,half*0.48),UNSEEN_COLOR)
		PRIMITIVE_TRIANGLE:
			draw_colored_polygon(PackedVector2Array([center+Vector2(0,-half),
				center+Vector2(half,half),center+Vector2(-half,half)]),color)

func _key(position:Vector2i)->String:
	return "%d:%d"%[position.x,position.y]

func _position_from_key(value:String)->Vector2i:
	var parts:=value.split(":")
	return Vector2i(int(parts[0]),int(parts[1])) if parts.size()==2 else Vector2i(-1,-1)
