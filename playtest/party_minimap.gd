class_name PartyMinimap
extends Control

## Low-resolution Hangul cartography. The 48x48 world is folded into eight
## square sectors so the compact top rail retains legible glyph cells at 360px.
## Static presentation state is cached only when its observation changes.

const AsciiStyleScript=preload("res://playtest/ascii_visual_style.gd")
const CodingFont:FontFile=preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const CodingFontBold:FontFile=preload("res://assets/fonts/LivingWorldMonoKRBold.ttf")

const SECTOR_COLUMNS:=8
const SECTOR_ROWS:=8

const UNSEEN_COLOR:=Color("#000306")
const MEMORY_COLOR:=Color("#66737b")
const VISIBLE_COLOR:=Color("#c7c2b3")
const WALL_MEMORY_COLOR:=Color("#3b555b")
const WALL_VISIBLE_COLOR:=Color("#4f9aa3")
const HERO_COLOR:=Color("#b8954d")
const ENEMY_COLOR:=Color("#a74343")
const EXIT_COLOR:=Color("#5f8a66")

const GLYPH_UNKNOWN:=""
const GLYPH_MEMORY:="·"
const GLYPH_WALL:="벽"
const GLYPH_EXIT:="출"
const GLYPH_THREAT:="적"
const GLYPH_HERO:="ㅇ"

const PRIORITY_UNKNOWN:=0
const PRIORITY_MEMORY:=10
const PRIORITY_WALL:=20
const PRIORITY_EXIT:=30
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
		if marker.is_empty() and _is_exit_feature(str(value.get("feature_id",""))):marker="EXIT"
		# Remembered static exits are safe. Every live marker is stripped outside
		# current visibility, so actors, targets and plans never leak through fog.
		if state!="VISIBLE" and marker!="EXIT":marker=""
		if marker not in ["","HERO","ENEMY","EXIT"]:marker=""
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
	return feature_id in ["run_exit_locked","run_exit_open"]

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
		return _glyph_spec(GLYPH_HERO,HERO_COLOR,PRIORITY_HERO,"HERO",state,true)
	if state=="VISIBLE" and marker=="ENEMY":
		return _glyph_spec(GLYPH_THREAT,ENEMY_COLOR,PRIORITY_THREAT,"THREAT",state,true)
	if marker=="EXIT":
		return _glyph_spec(GLYPH_EXIT,EXIT_COLOR,PRIORITY_EXIT,"EXIT",state,true)
	if str(row.get("terrain_id","unknown"))=="wall":
		return _glyph_spec(GLYPH_WALL,WALL_VISIBLE_COLOR if state=="VISIBLE" \
			else WALL_MEMORY_COLOR,PRIORITY_WALL,"STRUCTURE",state,true)
	return _glyph_spec(GLYPH_MEMORY,VISIBLE_COLOR if state=="VISIBLE" else MEMORY_COLOR,
		PRIORITY_MEMORY,"PASSABLE",state,false)

func _glyph_spec(glyph:String,color:Color,priority:int,role:String,
		visibility_state:String,bold:bool)->Dictionary:
	return {"glyph":glyph,"color":color,"priority":priority,"role":role,
		"visibility_state":visibility_state,"bold":bold,"leaks_actor":false,
		"leaks_direction":false,"leaks_target":false,"leaks_hazard":false}

func _unknown_sector_spec(sector:Vector2i)->Dictionary:
	var result:=_glyph_spec(GLYPH_UNKNOWN,UNSEEN_COLOR,PRIORITY_UNKNOWN,"UNKNOWN",
		"UNSEEN",false)
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
	if state!="VISIBLE" and marker!="EXIT":marker=""
	return {"visibility_state":state,"terrain_id":terrain_id,"color":color,
		"marker":marker,"leaks_direction":false,"leaks_target":false}.duplicate(true)

func cartography_spec()->Dictionary:
	return {"columns":SECTOR_COLUMNS,"rows":SECTOR_ROWS,"sector_count":_sectors.size(),
		"font_path":"res://assets/fonts/LivingWorldMonoKR.ttf",
		"bold_font_path":"res://assets/fonts/LivingWorldMonoKRBold.ttf",
		"glyphs":{"hero":GLYPH_HERO,"threat":GLYPH_THREAT,"exit":GLYPH_EXIT,
			"wall":GLYPH_WALL,"memory":GLYPH_MEMORY,"unknown":GLYPH_UNKNOWN},
		"primitive":"HANGUL_SECTOR_GLYPHS","background":"BLACK_FIELD",
		"uses_tile_rects":false,"uses_circles":false,"uses_images":false,
		"per_frame_process":false}.duplicate(true)

func _draw()->void:
	if _width<=0 or _height<=0 or size.x<=0.0 or size.y<=0.0:return
	draw_rect(Rect2(Vector2.ZERO,size),UNSEEN_COLOR,true)
	var slot:=Vector2(size.x/float(SECTOR_COLUMNS),size.y/float(SECTOR_ROWS))
	var font_size:=_font_size_for_slot(slot)
	for y in range(SECTOR_ROWS):
		for x in range(SECTOR_COLUMNS):
			var spec:=sector_draw_spec(Vector2i(x,y));var glyph:=str(spec.glyph)
			if glyph.is_empty():continue
			var font:Font=CodingFontBold if bool(spec.bold) else CodingFont
			var line_height:=font.get_height(font_size);var ascent:=font.get_ascent(font_size)
			var cell_origin:=Vector2(float(x)*slot.x,float(y)*slot.y)
			var baseline:=Vector2(cell_origin.x,
				floor(cell_origin.y+(slot.y-line_height)*0.5+ascent))
			draw_string(font,baseline,glyph,HORIZONTAL_ALIGNMENT_CENTER,slot.x,font_size,spec.color)
	# The parent supplies the existing fixed-cell typographic frame.

func _font_size_for_slot(slot:Vector2)->int:
	for candidate in range(9,4,-1):
		if CodingFontBold.get_height(candidate)<=slot.y+0.01 \
			and CodingFontBold.get_string_size("벽",HORIZONTAL_ALIGNMENT_LEFT,-1,candidate).x<=slot.x+0.01:
			return candidate
	return 5

func _key(position:Vector2i)->String:
	return "%d:%d"%[position.x,position.y]

func _position_from_key(value:String)->Vector2i:
	var parts:=value.split(":")
	return Vector2i(int(parts[0]),int(parts[1])) if parts.size()==2 else Vector2i(-1,-1)
