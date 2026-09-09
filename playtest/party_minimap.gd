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
# Incremental stream identity: the session appends static rows to one persistent
# list per epoch and reports which cells are visible / carry live markers.
var _epoch:=""
var _static_count:=0
var _sector_static:Dictionary={}
# Cell rows keep exactly the three compact scalars; static exit/portal markers
# live beside them so a live marker can be reverted after visibility passes.
var _static_markers:Dictionary={}
var _visible_keys:Array=[]
var _marker_keys:Array=[]

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
	if not observation.has("cells"):return
	var rows:Array=observation.get("cells",[]) if observation.get("cells",[]) is Array else []
	var epoch:=str(observation.get("epoch",""))
	var static_count:=int(observation.get("static_count",-1))
	var incremental:bool=not epoch.is_empty() and epoch==_epoch \
		and observation.get("visible") is Array and observation.get("markers") is Array \
		and observation.get("added") is Array \
		and static_count==rows.size() and static_count>=_static_count \
		and static_count-_static_count==observation.added.size() \
		and _width==maxi(1,int(observation.get("width",15))) \
		and _height==maxi(1,int(observation.get("height",15)))
	if not incremental:
		_width=maxi(1,int(observation.get("width",15)))
		_height=maxi(1,int(observation.get("height",15)))
		_cells.clear();_sector_static.clear();_static_markers.clear();_visible_keys=[];_marker_keys=[]
		_epoch=epoch;_static_count=0
		for value in rows:_ingest_row(value)
		_static_count=rows.size() if not epoch.is_empty() else 0
	else:
		for row in observation.added:_ingest_row(row,true)
		_static_count=rows.size()
		for key in _visible_keys:
			if _cells.has(key):_cells[key].visibility_state="MEMORY"
		for key in _marker_keys:
			if _cells.has(key):_cells[key].marker=str(_static_markers.get(key,""))
		_visible_keys=[];_marker_keys=[]
		for value in observation.visible:
			if not value is Array or value.size()!=2:continue
			var key:=_key(Vector2i(int(value[0]),int(value[1])))
			if not _cells.has(key):continue
			_cells[key].visibility_state="VISIBLE";_visible_keys.append(key)
		for value in observation.markers:
			if not value is Dictionary or not value.get("position") is Array \
					or value.position.size()!=2:continue
			var key:=_key(Vector2i(int(value.position[0]),int(value.position[1])))
			var marker:=str(value.get("marker","")).to_upper()
			if not _cells.has(key) or marker not in ["HERO","ENEMY"] \
					or str(_cells[key].visibility_state)!="VISIBLE":continue
			_cells[key].marker=marker;_marker_keys.append(key)
	_recompute_sectors()
	queue_redraw()

func _ingest_row(value:Variant,static_only:bool=false)->void:
	if not value is Dictionary or not value.get("position") is Array \
			or value.position.size()!=2:return
	var position:=Vector2i(int(value.position[0]),int(value.position[1]))
	if position.x<0 or position.y<0 or position.x>=_width or position.y>=_height:return
	var state:=AsciiStyleScript.visibility_state(value)
	if state=="UNSEEN":return
	var marker:=str(value.get("marker","")).to_upper()
	if marker.is_empty() and state=="VISIBLE":marker=_legacy_actor_marker(value)
	var feature_id:=str(value.get("feature_id",""))
	if marker.is_empty() and _is_exit_feature(feature_id):marker="EXIT"
	if marker.is_empty() and _is_anchor_feature(feature_id):marker="PORTAL"
	# Remembered static exits are safe. Every live marker is stripped outside
	# current visibility, so actors, targets and plans never leak through fog.
	if state!="VISIBLE" and marker not in ["EXIT","PORTAL"]:marker=""
	if marker not in ["","HERO","ENEMY","EXIT","PORTAL"]:marker=""
	var static_marker:=marker if marker in ["EXIT","PORTAL"] else ""
	if static_only:state="MEMORY";marker=static_marker
	var key:=_key(position)
	# Rich actor, feature, hazard, direction and target payloads do not enter
	# minimap state; only compact scalar fields are retained.
	_cells[key]={"visibility_state":state,
		"terrain_id":str(value.get("terrain_id","unknown")),"marker":marker}
	_static_markers[key]=static_marker
	var sector_key:=_key(world_to_sector(position))
	var flags:Dictionary=_sector_static.get(sector_key,{"wall":false,"passable":false,
		"exit":[],"portal":[]})
	if str(value.get("terrain_id","unknown"))=="wall":flags.wall=true
	else:flags.passable=true
	if static_marker=="EXIT" and key not in flags.exit:flags.exit.append(key)
	if static_marker=="PORTAL" and key not in flags.portal:flags.portal.append(key)
	_sector_static[sector_key]=flags
	if state=="VISIBLE":_visible_keys.append(key)
	if marker in ["HERO","ENEMY"]:_marker_keys.append(key)

func _recompute_sectors()->void:
	# Sixty-four sectors from per-sector static flags plus the current visible /
	# marker sets: O(64 + visible) instead of a full pass over explored cells.
	var visible_wall:Dictionary={};var visible_passable:Dictionary={}
	for key in _visible_keys:
		var row:Dictionary=_cells.get(key,{})
		if row.is_empty():continue
		var sector_key:=_key(world_to_sector(_position_from_key(key)))
		if str(row.get("terrain_id",""))=="wall":visible_wall[sector_key]=true
		else:visible_passable[sector_key]=true
	var hero_sectors:Dictionary={};var threat_sectors:Dictionary={}
	for key in _marker_keys:
		var row:Dictionary=_cells.get(key,{})
		if row.is_empty() or str(row.get("visibility_state",""))!="VISIBLE":continue
		var sector_key:=_key(world_to_sector(_position_from_key(key)))
		if str(row.get("marker",""))=="HERO":hero_sectors[sector_key]=true
		elif str(row.get("marker",""))=="ENEMY":threat_sectors[sector_key]=true
	_sectors.clear()
	for y in range(SECTOR_ROWS):
		for x in range(SECTOR_COLUMNS):
			var sector:=Vector2i(x,y);var sector_key:=_key(sector)
			var flags:Dictionary=_sector_static.get(sector_key,{})
			var spec:Dictionary
			if hero_sectors.has(sector_key):
				spec=_shape_spec(PRIMITIVE_CIRCLE,HERO_COLOR,PRIORITY_HERO,"HERO","VISIBLE",0.78)
			elif threat_sectors.has(sector_key):
				spec=_shape_spec(PRIMITIVE_DIAMOND,ENEMY_COLOR,PRIORITY_THREAT,"THREAT","VISIBLE",0.78)
			elif not flags.is_empty() and not flags.portal.is_empty():
				spec=_shape_spec(PRIMITIVE_RING,PORTAL_COLOR,PRIORITY_PORTAL,"PORTAL",
					_static_visibility(flags.portal),0.86)
			elif not flags.is_empty() and not flags.exit.is_empty():
				spec=_shape_spec(PRIMITIVE_TRIANGLE,EXIT_COLOR,PRIORITY_EXIT,"EXIT",
					_static_visibility(flags.exit),0.80)
			elif not flags.is_empty() and bool(flags.wall):
				var wall_visible:bool=visible_wall.has(sector_key)
				spec=_shape_spec(PRIMITIVE_TILE,WALL_VISIBLE_COLOR if wall_visible \
					else WALL_MEMORY_COLOR,PRIORITY_WALL,"STRUCTURE",
					"VISIBLE" if wall_visible else "MEMORY",0.88)
			elif not flags.is_empty() and bool(flags.passable):
				var passable_visible:bool=visible_passable.has(sector_key)
				spec=_shape_spec(PRIMITIVE_TILE,VISIBLE_COLOR if passable_visible \
					else MEMORY_COLOR,PRIORITY_MEMORY,"PASSABLE",
					"VISIBLE" if passable_visible else "MEMORY",0.42)
			else:spec=_unknown_sector_spec(sector)
			spec["sector"]=sector
			_sectors[sector_key]=spec

func _static_visibility(keys:Array)->String:
	for key in keys:
		if str(_cells.get(key,{}).get("visibility_state",""))=="VISIBLE":return "VISIBLE"
	return "MEMORY"

func stream_state()->Dictionary:
	return {"epoch":_epoch,"static_count":_static_count,"cell_count":_cells.size(),
		"visible_count":_visible_keys.size(),"marker_count":_marker_keys.size()}.duplicate(true)

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
