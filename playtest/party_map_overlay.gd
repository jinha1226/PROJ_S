class_name PartyMapOverlay
extends Control

## Trigger-independent, full discovered-map folio. The component accepts the
## same compact scalar cartography DTO as PartyMinimap, but never retains rich
## actor, intent, target or hazard data. It redraws only after data/layout/state
## changes; there is no per-frame processing.

signal opened
signal closed(reason:String)

const AsciiStyleScript=preload("res://playtest/ascii_visual_style.gd")
const AsciiFrame=preload("res://playtest/ascii_ui_frame.gd")
const CodingFont:FontFile=preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const CodingFontBold:FontFile=preload("res://assets/fonts/LivingWorldMonoKRBold.ttf")

const GLYPH_UNKNOWN:=""
const GLYPH_FLOOR:="."
const GLYPH_WALL:="#"
const GLYPH_EXIT:=">"
const GLYPH_PORTAL:="O"
const GLYPH_THREAT:="!"
const GLYPH_HERO:="@"

const BLACK_FIELD:=Color("#000306")
const SCRIM:=Color("#000306d9")
const PANEL:=Color("#071012")
const IRON_EDGE:=Color("#344447")
const MEMORY_INK:=Color("#566268")
const VISIBLE_FLOOR_INK:=Color("#918b7d")
const WALL_MEMORY_INK:=Color("#3b555b")
const WALL_VISIBLE_INK:=Color("#4f9aa3")
const HERO_INK:=Color("#b8954d")
const EXIT_INK:=Color("#5f8a66")
const PORTAL_INK:=Color("#48bfc8")
const THREAT_INK:=Color("#a74343")
const TITLE_INK:=Color("#d2c7aa")

const PANEL_MARGIN:=12.0
const PANEL_MAX_WIDTH:=420.0
const PANEL_INSET:=12.0
const HEADER_HEIGHT:=30.0
const FOOTER_HEIGHT:=30.0
const FRAME_FONT_SIZE:=12
const MIN_MAP_FONT_SIZE:=2
const MAX_MAP_FONT_SIZE:=9

var _world_width:=48
var _world_height:=48
var _cells:Dictionary={}

func _init()->void:
	visible=false
	clip_contents=true
	mouse_filter=Control.MOUSE_FILTER_STOP
	focus_mode=Control.FOCUS_ALL
	set_process(false)
	set_process_input(false)
	set_process_unhandled_key_input(true)

func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	queue_redraw()

func set_observation(observation:Dictionary)->void:
	_world_width=maxi(1,int(observation.get("width",48)))
	_world_height=maxi(1,int(observation.get("height",48)))
	_cells.clear()
	for value in observation.get("cells",[]):
		if not value is Dictionary:continue
		var raw_position:Variant=value.get("position",[])
		if not raw_position is Array or raw_position.size()!=2:continue
		var position:=Vector2i(int(raw_position[0]),int(raw_position[1]))
		if position.x<0 or position.y<0 \
				or position.x>=_world_width or position.y>=_world_height:continue
		var row:=_sanitized_row(value)
		if row.is_empty():continue
		var key:=_key(position)
		var incumbent:Dictionary=_cells.get(key,{})
		if incumbent.is_empty() or _row_priority(row)>_row_priority(incumbent):
			_cells[key]=row
	queue_redraw()

func open()->void:
	if visible:return
	visible=true
	if is_inside_tree():grab_focus()
	queue_redraw()
	opened.emit()

func close(reason:String="API")->void:
	if not visible:return
	visible=false
	if is_inside_tree():release_focus()
	closed.emit(reason)

func toggle()->void:
	if visible:close("TOGGLE")
	else:open()

func cell_draw_spec(position:Vector2i)->Dictionary:
	if position.x<0 or position.y<0 or position.x>=_world_width \
			or position.y>=_world_height:return _unknown_spec()
	var row:Dictionary=_cells.get(_key(position),{})
	if row.is_empty():return _unknown_spec()
	var state:=str(row.get("visibility_state","UNSEEN"))
	var marker:=str(row.get("marker",""))
	if state=="VISIBLE" and marker=="HERO":
		return _glyph_spec(GLYPH_HERO,HERO_INK,"HERO",state,true)
	if state=="VISIBLE" and marker=="ENEMY":
		return _glyph_spec(GLYPH_THREAT,THREAT_INK,"THREAT",state,true)
	if marker=="PORTAL":return _glyph_spec(GLYPH_PORTAL,PORTAL_INK,"PORTAL",state,true)
	if marker=="EXIT":return _glyph_spec(GLYPH_EXIT,EXIT_INK,"EXIT",state,true)
	if str(row.get("terrain_id","unknown"))=="wall":
		return _glyph_spec(GLYPH_WALL,WALL_VISIBLE_INK if state=="VISIBLE" \
			else WALL_MEMORY_INK,"STRUCTURE",state,true)
	return _glyph_spec(GLYPH_FLOOR,VISIBLE_FLOOR_INK if state=="VISIBLE" \
		else MEMORY_INK,"PASSABLE",state,false)

func layout_spec(viewport_size:Vector2=size)->Dictionary:
	var safe_size:=Vector2(maxf(1.0,viewport_size.x),maxf(1.0,viewport_size.y))
	var panel_width:=minf(PANEL_MAX_WIDTH,maxf(1.0,safe_size.x-PANEL_MARGIN*2.0))
	var desired_map_side:=maxf(1.0,panel_width-PANEL_INSET*2.0)
	var panel_height:=desired_map_side+HEADER_HEIGHT+FOOTER_HEIGHT
	if panel_height>safe_size.y-PANEL_MARGIN*2.0:
		desired_map_side=maxf(1.0,safe_size.y-PANEL_MARGIN*2.0-HEADER_HEIGHT-FOOTER_HEIGHT)
		panel_width=minf(panel_width,desired_map_side+PANEL_INSET*2.0)
		panel_height=desired_map_side+HEADER_HEIGHT+FOOTER_HEIGHT
	var panel:=Rect2(Vector2(floor((safe_size.x-panel_width)*0.5),
		floor((safe_size.y-panel_height)*0.5)),Vector2(panel_width,panel_height))
	var map_side:=minf(desired_map_side,panel.size.x-PANEL_INSET*2.0)
	var map_rect:=Rect2(Vector2(floor(panel.position.x+(panel.size.x-map_side)*0.5),
		floor(panel.position.y+HEADER_HEIGHT)),Vector2(map_side,map_side))
	var slot:=Vector2(map_rect.size.x/float(_world_width),map_rect.size.y/float(_world_height))
	return {"panel_rect":panel,"map_rect":map_rect,"cell_size":slot,
		"font_size":_font_size_for_slot(slot),"world_width":_world_width,
		"world_height":_world_height,"trigger_independent":true}.duplicate(true)

func overlay_spec()->Dictionary:
	return {"primitive":"FULL_ASCII_CARTOGRAPHY","visual_family":"DARK_FANTASY_IRON_FOLIO",
		"font_path":"res://assets/fonts/LivingWorldMonoKR.ttf",
		"bold_font_path":"res://assets/fonts/LivingWorldMonoKRBold.ttf",
		"glyphs":{"hero":GLYPH_HERO,"threat":GLYPH_THREAT,"exit":GLYPH_EXIT,
			"portal":GLYPH_PORTAL,
			"wall":GLYPH_WALL,"floor":GLYPH_FLOOR,"unknown":GLYPH_UNKNOWN},
		"uses_world_coordinates":true,"uses_sector_folding":false,
		"stores_compact_scalars_only":true,"leaks_memory_actor":false,
		"leaks_hazard":false,"leaks_target":false,"leaks_direction":false,
		"uses_images":false,"uses_textures":false,"per_frame_process":false,
		"trigger_independent":true,
		"close_modes":["OUTSIDE","BACK","TOGGLE","API"]}.duplicate(true)

func _sanitized_row(value:Dictionary)->Dictionary:
	var state:=AsciiStyleScript.visibility_state(value)
	if state=="UNSEEN":return {}
	var marker:=str(value.get("marker","")).to_upper()
	if marker.is_empty() and state=="VISIBLE":marker=_legacy_actor_marker(value)
	var feature_id:=str(value.get("feature_id",""))
	if marker.is_empty() and _is_exit_feature(feature_id):marker="EXIT"
	if marker.is_empty() and _is_anchor_feature(feature_id):marker="PORTAL"
	if state!="VISIBLE" and marker not in ["EXIT","PORTAL"]:marker=""
	if marker not in ["","HERO","ENEMY","EXIT","PORTAL"]:marker=""
	# Deliberately retain no source dictionary and no rich/live fields.
	return {"visibility_state":state,"terrain_id":str(value.get("terrain_id","unknown")),
		"marker":marker}

func _legacy_actor_marker(value:Dictionary)->String:
	for actor in value.get("actors",[]):
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

func _row_priority(row:Dictionary)->int:
	var state:=str(row.get("visibility_state","UNSEEN"));var marker:=str(row.get("marker",""))
	if state=="VISIBLE" and marker=="HERO":return 50
	if state=="VISIBLE" and marker=="ENEMY":return 40
	if marker=="PORTAL":return 31
	if marker=="EXIT":return 30
	if str(row.get("terrain_id","unknown"))=="wall":return 20
	return 10

func _glyph_spec(glyph:String,color:Color,role:String,state:String,bold:bool)->Dictionary:
	return {"glyph":glyph,"color":color,"role":role,"visibility_state":state,"bold":bold,
		"leaks_actor":false,"leaks_hazard":false,"leaks_target":false,
		"leaks_direction":false}.duplicate(true)

func _unknown_spec()->Dictionary:
	return _glyph_spec(GLYPH_UNKNOWN,BLACK_FIELD,"UNKNOWN","UNSEEN",false)

func _font_size_for_slot(slot:Vector2)->int:
	for candidate in range(MAX_MAP_FONT_SIZE,MIN_MAP_FONT_SIZE-1,-1):
		if CodingFontBold.get_height(candidate)<=slot.y+0.01 \
			and CodingFontBold.get_string_size("#",HORIZONTAL_ALIGNMENT_LEFT,-1,candidate).x<=slot.x+0.01:
			return candidate
	return MIN_MAP_FONT_SIZE

func _gui_input(event:InputEvent)->void:
	if not visible:return
	var press_position:=Vector2.ZERO;var pressed:=false
	if event is InputEventMouseButton:
		pressed=event.pressed and event.button_index==MOUSE_BUTTON_LEFT
		press_position=event.position
	elif event is InputEventScreenTouch:
		pressed=event.pressed;press_position=event.position
	if not pressed:return
	if not (layout_spec().panel_rect as Rect2).has_point(press_position):close("OUTSIDE")
	accept_event()

func _unhandled_key_input(event:InputEvent)->void:
	if not visible or not event.is_pressed() or event.is_echo():return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.keycode==KEY_ESCAPE):
		close("BACK")
		if get_viewport()!=null:get_viewport().set_input_as_handled()

func _draw()->void:
	if not visible or size.x<=0.0 or size.y<=0.0:return
	var layout:=layout_spec();var panel:Rect2=layout.panel_rect;var map_rect:Rect2=layout.map_rect
	draw_rect(Rect2(Vector2.ZERO,size),SCRIM,true)
	draw_rect(panel,PANEL,true)
	_draw_ascii_frame(panel)
	var slot:Vector2=layout.cell_size;var font_size:=int(layout.font_size)
	for y in range(_world_height):
		for x in range(_world_width):
			var spec:=cell_draw_spec(Vector2i(x,y));var glyph:=str(spec.glyph)
			if glyph.is_empty():continue
			var font:Font=CodingFontBold if bool(spec.bold) else CodingFont
			var line_height:=font.get_height(font_size);var ascent:=font.get_ascent(font_size)
			var origin:=map_rect.position+Vector2(float(x)*slot.x,float(y)*slot.y)
			var baseline:=Vector2(origin.x,floor(origin.y+(slot.y-line_height)*0.5+ascent))
			draw_string(font,baseline,glyph,HORIZONTAL_ALIGNMENT_CENTER,slot.x,font_size,spec.color)
	var footer_y:=panel.end.y-8.0
	draw_string(CodingFont,Vector2(panel.position.x+PANEL_INSET,footer_y),
		"@ 주인공  ! 위협  O 거점  > 층간  바깥 터치: 닫기",HORIZONTAL_ALIGNMENT_CENTER,
		panel.size.x-PANEL_INSET*2.0,10,AsciiFrame.BONE_DIM)

func _draw_ascii_frame(panel:Rect2)->void:
	var cell_width:=maxf(1.0,CodingFont.get_string_size("━",HORIZONTAL_ALIGNMENT_LEFT,-1,
		FRAME_FONT_SIZE).x);var line_height:=CodingFont.get_height(FRAME_FONT_SIZE)
	var columns:=maxi(4,int(floor(panel.size.x/cell_width)))
	var rows:=maxi(4,int(floor(panel.size.y/line_height)))
	var top:="┏"+"━".repeat(columns-2)+"┓"
	var bottom:="┗"+"━".repeat(columns-2)+"┛"
	var ascent:=CodingFont.get_ascent(FRAME_FONT_SIZE)
	draw_string(CodingFont,Vector2(panel.position.x,panel.position.y+ascent),top,
		HORIZONTAL_ALIGNMENT_LEFT,-1,FRAME_FONT_SIZE,IRON_EDGE)
	draw_string(CodingFont,Vector2(panel.position.x,panel.position.y+float(rows-1)*line_height+ascent),
		bottom,HORIZONTAL_ALIGNMENT_LEFT,-1,FRAME_FONT_SIZE,IRON_EDGE.lerp(BLACK_FIELD,0.32))
	for row in range(1,rows-1):
		var y:=panel.position.y+float(row)*line_height+ascent
		draw_string(CodingFont,Vector2(panel.position.x,y),"┃",HORIZONTAL_ALIGNMENT_LEFT,-1,
			FRAME_FONT_SIZE,IRON_EDGE)
		draw_string(CodingFont,Vector2(panel.end.x-cell_width,y),"┃",HORIZONTAL_ALIGNMENT_LEFT,-1,
			FRAME_FONT_SIZE,IRON_EDGE)
	draw_string(CodingFontBold,Vector2(panel.position.x+cell_width*2.0,panel.position.y+ascent),
		"┫ 발견 지도 ┣",HORIZONTAL_ALIGNMENT_LEFT,-1,FRAME_FONT_SIZE,TITLE_INK)

func _key(position:Vector2i)->String:
	return "%d:%d"%[position.x,position.y]
