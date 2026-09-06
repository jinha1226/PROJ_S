class_name PartyMapOverlay
extends Control

## Trigger-independent, full discovered-map folio. The component accepts the
## same compact scalar cartography DTO as PartyMinimap, but never retains rich
## actor, intent, target or hazard data. Map cells and markers are vector shapes,
## not ASCII glyphs. It redraws only after data/layout/state changes.

signal opened
signal closed(reason:String)

const AsciiStyleScript=preload("res://playtest/ascii_visual_style.gd")
const AsciiFrame=preload("res://playtest/ascii_ui_frame.gd")
const CodingFont:FontFile=preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const CodingFontBold:FontFile=preload("res://assets/fonts/LivingWorldMonoKRBold.ttf")

const PRIMITIVE_NONE:="NONE"
const PRIMITIVE_TILE:="TILE"
const PRIMITIVE_CIRCLE:="CIRCLE"
const PRIMITIVE_DIAMOND:="DIAMOND"
const PRIMITIVE_RING:="RING"
const PRIMITIVE_TRIANGLE:="TRIANGLE"

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
		return _shape_spec(PRIMITIVE_CIRCLE,HERO_INK,"HERO",state,0.92)
	if state=="VISIBLE" and marker=="ENEMY":
		return _shape_spec(PRIMITIVE_DIAMOND,THREAT_INK,"THREAT",state,0.92)
	if marker=="PORTAL":return _shape_spec(PRIMITIVE_RING,PORTAL_INK,"PORTAL",state,0.96)
	if marker=="EXIT":return _shape_spec(PRIMITIVE_TRIANGLE,EXIT_INK,"EXIT",state,0.92)
	if str(row.get("terrain_id","unknown"))=="wall":
		return _shape_spec(PRIMITIVE_TILE,WALL_VISIBLE_INK if state=="VISIBLE" \
			else WALL_MEMORY_INK,"STRUCTURE",state,0.92)
	return _shape_spec(PRIMITIVE_TILE,VISIBLE_FLOOR_INK if state=="VISIBLE" \
		else MEMORY_INK,"PASSABLE",state,0.62 if state=="VISIBLE" else 0.48)

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
		"minimum_marker_size":maxf(1.0,minf(slot.x,slot.y)*0.48),"world_width":_world_width,
		"world_height":_world_height,"trigger_independent":true}.duplicate(true)

func overlay_spec()->Dictionary:
	return {"primitive":"FULL_VECTOR_CARTOGRAPHY","visual_family":"DARK_FANTASY_IRON_FOLIO",
		"ui_font_path":"res://assets/fonts/LivingWorldMonoKR.ttf",
		"uses_world_coordinates":true,"uses_sector_folding":false,
		"stores_compact_scalars_only":true,"leaks_memory_actor":false,
		"leaks_hazard":false,"leaks_target":false,"leaks_direction":false,
		"uses_tile_rects":true,"uses_circles":true,"uses_polygons":true,
		"uses_map_fonts":false,"uses_images":false,"uses_textures":false,
		"per_frame_process":false,
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

func _shape_spec(primitive:String,color:Color,role:String,state:String,
		fill_ratio:float)->Dictionary:
	return {"primitive":primitive,"color":color,"role":role,"visibility_state":state,
		"fill_ratio":fill_ratio,
		"leaks_actor":false,"leaks_hazard":false,"leaks_target":false,
		"leaks_direction":false}.duplicate(true)

func _unknown_spec()->Dictionary:
	return _shape_spec(PRIMITIVE_NONE,BLACK_FIELD,"UNKNOWN","UNSEEN",0.0)

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
	_draw_vector_frame(panel)
	draw_rect(map_rect,BLACK_FIELD,true)
	var slot:Vector2=layout.cell_size
	for y in range(_world_height):
		for x in range(_world_width):
			var origin:=map_rect.position+Vector2(float(x)*slot.x,float(y)*slot.y)
			_draw_map_shape(Rect2(origin,slot),cell_draw_spec(Vector2i(x,y)),BLACK_FIELD)
	_draw_vector_legend(panel)

func _draw_map_shape(rect:Rect2,spec:Dictionary,hole_color:Color)->void:
	var primitive:=str(spec.get("primitive",PRIMITIVE_NONE))
	if primitive==PRIMITIVE_NONE:return
	var color:Color=spec.get("color",BLACK_FIELD)
	var ratio:=clampf(float(spec.get("fill_ratio",0.7)),0.1,1.0)
	var center:=rect.get_center();var half:=minf(rect.size.x,rect.size.y)*ratio*0.5
	match primitive:
		PRIMITIVE_TILE:
			draw_rect(Rect2(center-Vector2(half,half),Vector2(half*2.0,half*2.0)),color,true)
		PRIMITIVE_CIRCLE:
			draw_circle(center,maxf(0.75,half),color)
		PRIMITIVE_DIAMOND:
			draw_colored_polygon(PackedVector2Array([center+Vector2(0,-half),
				center+Vector2(half,0),center+Vector2(0,half),center+Vector2(-half,0)]),color)
		PRIMITIVE_RING:
			draw_circle(center,maxf(0.75,half),color)
			draw_circle(center,maxf(0.35,half*0.48),hole_color)
		PRIMITIVE_TRIANGLE:
			draw_colored_polygon(PackedVector2Array([center+Vector2(0,-half),
				center+Vector2(half,half),center+Vector2(-half,half)]),color)

func _draw_vector_frame(panel:Rect2)->void:
	draw_rect(panel,IRON_EDGE,false,2.0)
	draw_line(panel.position+Vector2(2,2),Vector2(panel.end.x-2,panel.position.y+2),
		IRON_EDGE.lerp(TITLE_INK,0.18),1.0)
	draw_line(Vector2(panel.position.x+2,panel.end.y-2),panel.end-Vector2(2,2),
		IRON_EDGE.lerp(BLACK_FIELD,0.45),1.0)
	var title:="발견 지도";var title_size:=CodingFontBold.get_string_size(title,
		HORIZONTAL_ALIGNMENT_LEFT,-1,FRAME_FONT_SIZE)
	draw_string(CodingFontBold,Vector2(panel.get_center().x-title_size.x*0.5,
		panel.position.y+20.0),title,HORIZONTAL_ALIGNMENT_LEFT,-1,FRAME_FONT_SIZE,TITLE_INK)

func _draw_vector_legend(panel:Rect2)->void:
	var rows:=[
		[PRIMITIVE_CIRCLE,HERO_INK,"주인공"],
		[PRIMITIVE_DIAMOND,THREAT_INK,"위협"],
		[PRIMITIVE_RING,PORTAL_INK,"거점"],
		[PRIMITIVE_TRIANGLE,EXIT_INK,"층간"],
	]
	var usable_width:=panel.size.x-PANEL_INSET*2.0;var column_width:=usable_width/4.0
	var y:=panel.end.y-FOOTER_HEIGHT*0.5
	for index in range(rows.size()):
		var origin:=Vector2(panel.position.x+PANEL_INSET+float(index)*column_width,y)
		_draw_map_shape(Rect2(origin+Vector2(3,-5),Vector2(10,10)),
			_shape_spec(str(rows[index][0]),rows[index][1],"LEGEND","VISIBLE",0.9),PANEL)
		draw_string(CodingFont,origin+Vector2(17,4),str(rows[index][2]),
			HORIZONTAL_ALIGNMENT_LEFT,column_width-19.0,10,AsciiFrame.BONE_DIM)

func _key(position:Vector2i)->String:
	return "%d:%d"%[position.x,position.y]
