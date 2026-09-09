class_name BaseSettlementView
extends Control

signal building_selected(id:String)
signal resident_selected(id:int)
signal tile_pressed(position:Vector2i)
signal tile_dragged(position:Vector2i)

const DarkPixelSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
const BuildingAssets=preload("res://playtest/pixel24_building_assets.gd")
const ActorAssets=preload("res://playtest/fixed_front_topdown_assets.gd")
const KoreanFont:FontFile=DarkPixelSkin.PixelFont
const LANDMARK_IDS:=["STORAGE","LODGE","CLINIC","MARKET","ARMORY","GATE"]
const FACILITY_IDS:=["STORAGE","LODGE","CLINIC"]
const LABELS:={"STORAGE":"창고","LODGE":"숙소","CLINIC":"진료소",
	"MARKET":"시장","ARMORY":"대장간","GATE":"원정문"}
const GROUND:=Color("#101812")
const CLEARING:=Color("#273126")
const CLEARING_EDGE:=Color("#465343")
const PATH_DARK:=Color("#332f25")
const PATH:=Color("#675b43")
const TIMBER:=Color("#765237")
const TIMBER_DARK:=Color("#38291f")
const STONE:=Color("#6a6d68")
const STONE_DARK:=Color("#343936")
const TARP:=Color("#596052")
const ROOF:=Color("#503537")
const ROOF_LIGHT:=Color("#81504a")
const BONE:=Color("#d7cfb6")
const BONE_DIM:=Color("#a39b82")
const WINDOW:=Color("#edb85c")
const CYAN:=Color("#59ced1")
const EMBER:=Color("#df7546")
const SELECTED:=Color("#e8c66a")

var _overview:Dictionary={}
var _selected_id:="STORAGE"
var _buttons:Dictionary={}
var _settlement:Dictionary={}
var _placement_mode:=false
var _ghost:Dictionary={}
var _pointer_down:=false
var _last_drag_tile:=Vector2i(-1,-1)
var _pointer_origin:=Vector2.ZERO
var _pointer_dragged:=false
var camera=preload("res://playtest/base_map_camera.gd").new()
var _last_pointer:=Vector2.ZERO
var minimum_map_height:=320
var fit_map_height:=false


func _ready()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size=Vector2(0 if fit_map_height else 300,minimum_map_height)
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	mouse_filter=Control.MOUSE_FILTER_STOP
	clip_contents=true
	gui_input.connect(_on_map_gui_input)
	_resolve_layout()
	queue_redraw()


func present(overview:Dictionary,selected_id:String="STORAGE")->void:
	_overview=overview.duplicate(true)
	_settlement=_overview.get("settlement",{}).duplicate(true) \
		if _overview.get("settlement",{}) is Dictionary else {}
	_selected_id=selected_id
	_resolve_layout();queue_redraw()


func building_rect(id:String)->Rect2:
	var row:=_building_by_id(id)
	if row.is_empty():return Rect2()
	var origin:=_vector2i(row.get("tile_origin",[]))
	var footprint:=_vector2i(row.get("footprint",[]))
	return Rect2(_map_origin()+Vector2(origin)*_cell_size(),Vector2(footprint)*_cell_size())


func building_visual_state(id)->Dictionary:
	var normalized:=str(id)
	var row:=_building_by_id(normalized)
	if row.is_empty():return {}
	var type_id:=str(row.get("type_id",normalized));var level:=clampi(int(row.get("level",1)),1,3)
	var stage:String="LANDMARK" if type_id not in FACILITY_IDS else str(
		["CAMP","TIMBER","STONE"][level-1])
	var rect:=building_rect(normalized)
	return {"id":normalized,"type_id":type_id,"level":level,"visual_stage":stage,
		"footprint":[rect.position.x,
			rect.position.y,rect.size.x,rect.size.y],
		"tile_origin":row.get("tile_origin",[]),"selected":type_id==_selected_id}.duplicate(true)


func set_placement_mode(enabled:bool)->void:
	_placement_mode=enabled;_pointer_down=false;_sync_button_input();queue_redraw()


func set_placement_ghost(ghost:Dictionary)->void:
	_ghost=ghost.duplicate(true);queue_redraw()


func _notification(what:int)->void:
	if what==NOTIFICATION_RESIZED:
		if camera!=null:camera.clamp_pan(self)
		_resolve_layout();queue_redraw()


func _resolve_layout()->void:
	var live:Dictionary={}
	for value in _settlement.get("buildings",[]):
		if not value is Dictionary:continue
		var type_id:=str(value.get("type_id",""));var instance_id:=str(value.get("instance_id",type_id))
		if type_id.is_empty():continue
		var button:Button=_buttons.get(instance_id)
		if button==null:
			button=Button.new();button.name="SettlementHit%s"%type_id
			button.text="";button.flat=true;button.focus_mode=Control.FOCUS_ALL
			for state_name in ["normal","hover","pressed","disabled"]:
				button.add_theme_stylebox_override(state_name,StyleBoxEmpty.new())
			button.add_theme_stylebox_override("focus",_outline_box(SELECTED,2,2))
			button.pressed.connect(_select_building.bind(type_id));add_child(button)
			_buttons[instance_id]=button
		button.tooltip_text=str(value.get("label",LABELS.get(type_id,type_id)))
		var physical:=building_rect(instance_id);var hit_size:=Vector2(
			maxf(48.0,physical.size.x),maxf(48.0,physical.size.y))
		var hit:=Rect2(physical.get_center()-hit_size*0.5,hit_size)
		button.position=hit.position;button.size=hit.size
		button.set_meta("building_id",type_id);live[instance_id]=true
	for instance_id in _buttons.keys():
		if not live.has(instance_id):
			var old:Button=_buttons[instance_id];_buttons.erase(instance_id);old.queue_free()
	_sync_button_input()


func _select_building(id:String)->void:
	_selected_id=id;queue_redraw();building_selected.emit(id)


func _sync_button_input()->void:
	for button in _buttons.values():
		# Parent resolves expanded hit ties by nearest visual centre. Buttons remain
		# focusable for keyboard/gamepad but never steal tile placement pointers.
		(button as Button).mouse_filter=Control.MOUSE_FILTER_IGNORE


func _draw()->void:
	var canvas:=Rect2(_map_origin(),Vector2(_grid_size())*_cell_size())
	draw_rect(canvas,GROUND)
	_draw_tile_grid(canvas)
	for value in _settlement.get("buildings",[]):
		if value is Dictionary:_draw_building(value)
	_draw_work_and_residents()
	_draw_placement_ghost()


func _draw_work_and_residents()->void:
	var job:Dictionary=_overview.get("work",{})
	if not job.is_empty():
		var p:=_vector2i(job.tile_origin);var footprint:=_vector2i(job.footprint)
		var rect:=Rect2(_map_origin()+Vector2(p)*_cell_size(),Vector2(footprint)*_cell_size())
		var tone:=SELECTED if str(job.action)=="PRODUCE" else CYAN
		if str(job.action)=="REST":tone=Color("#8faad4")
		draw_rect(rect,Color(tone,0.15));draw_rect(rect,tone,false,2)
		for x in range(1,footprint.x):
			if str(job.action) in ["BUILD","UPGRADE"]:draw_line(rect.position+Vector2(x*_cell_size(),0),rect.position+Vector2(x*_cell_size(),rect.size.y),Color(CYAN,0.4),1)
		var bar:=Rect2(rect.position+Vector2(2,rect.size.y-5),Vector2(rect.size.x-4,3))
		draw_rect(bar,Color("#111a1c"));bar.size.x*=float(job.progress)/float(job.required)
		draw_rect(bar,tone)
	for recipe in _overview.get("production",[]):
		if int(recipe.ready)<1:continue
		var rect:=building_rect(str(recipe.facility_id))
		if rect.size==Vector2.ZERO:continue
		var center:=rect.position+Vector2(rect.size.x-8,8)
		draw_circle(center,8,SELECTED)
		draw_string(KoreanFont,center+Vector2(-3,4),str(recipe.ready),HORIZONTAL_ALIGNMENT_LEFT,-1,12,GROUND)
	if str(_overview.get("phase",""))!="TOWN":return
	var index:=0
	for resident in _overview.get("residents",[]):
		var tile:=Vector2i(7+index,7);index+=1
		if resident.has("tile"):tile=_vector2i(resident.tile)
		var working:bool=not job.is_empty() and int(job.worker_id)==int(resident.entity_id)
		if working:tile=preload("res://sim/base_work_rules.gd").worker_position(job)
		var center:=_map_origin()+(Vector2(tile)+Vector2.ONE*0.5)*_cell_size()
		var resting:bool=working and str(job.action)=="REST" \
			and int(job.progress)>=job.route.size()-1
		_draw_resident(resident,center,working,resting)


func resident_visual_spec(resident:Dictionary,center:Vector2,cell_size:float)->Dictionary:
	var actor:=resident.duplicate(true)
	if str(actor.get("species_id","")).is_empty():actor["species_id"]="human"
	var layer:=ActorAssets.actor_layer_spec(actor)
	var sprite_size:=maxf(12.0,floorf(cell_size*0.92))
	var bounds:=Rect2(center-Vector2.ONE*sprite_size*0.5,Vector2.ONE*sprite_size)
	return layer.merged({"bounds":bounds,
		"uses_actual_asset":bool(layer.get("uses_sprite",false)),
		"ascii_glyph":false},true).duplicate(true)


func _draw_resident(resident:Dictionary,center:Vector2,working:bool,resting:bool)->void:
	var spec:=resident_visual_spec(resident,center,_cell_size())
	var bounds:Rect2=spec.bounds
	var radius:=bounds.size.x*0.24
	if resting:
		var bed:=Rect2(center-Vector2(bounds.size.x*0.54,bounds.size.y*0.38),
			Vector2(bounds.size.x*1.08,bounds.size.y*0.76))
		draw_rect(bed,Color("#3e516b"))
		draw_rect(bed.grow(-2),Color("#718bac"))
		draw_rect(Rect2(bed.position+Vector2(2,2),Vector2(bed.size.x*0.29,bed.size.y-4)),BONE)
	else:
		draw_circle(center+Vector2(0,bounds.size.y*0.36),radius,Color("#111816bb"))
	if working:
		draw_arc(center,bounds.size.x*0.48,0,TAU,16,CYAN,2.0)
	if bool(spec.get("uses_actual_asset",false)):
		for texture_key in ["body_texture","armor_texture","offhand_texture",
				"weapon_texture","foreground_texture"]:
			var texture:Texture2D=spec.get(texture_key,null)
			if texture!=null:draw_texture_rect(texture,bounds,false,Color.WHITE)
		return
	# Unknown future species remain visible instead of disappearing from town.
	draw_circle(center+Vector2(0,radius*0.35),radius,
		CYAN if working else Color("#96a889"))
	draw_circle(center-Vector2(0,radius*0.65),radius*0.67,BONE)


func _draw_tile_grid(canvas:Rect2)->void:
	for value in _settlement.get("tiles",[]):
		if not value is Dictionary:continue
		var p:=_vector2i(value.get("position",[]))
		var rect:=Rect2(_map_origin()+Vector2(p)*_cell_size(),Vector2.ONE*_cell_size())
		var terrain_id:=str(value.get("terrain_id","GRASS")).to_upper()
		var fill:=PATH_DARK if bool(value.get("reserved",false)) else (
			CLEARING if bool(value.get("buildable",false)) else GROUND)
		draw_rect(rect,fill)
		if not fit_map_height:draw_rect(rect,Color(CLEARING_EDGE,0.32),false,1.0)
		if bool(value.get("reserved",false)):
			if not fit_map_height:draw_circle(rect.get_center(),maxf(1.5,_cell_size()*0.11),PATH)
		elif terrain_id in ["TREE","WOODS","FOREST"]:
			draw_rect(Rect2(rect.get_center()+Vector2(-1,2),Vector2(3,_cell_size()*0.34)),TIMBER_DARK)
			draw_circle(rect.get_center()-Vector2(0,_cell_size()*0.12),_cell_size()*0.28,
				Color("#29452e"))


func _draw_building(row:Dictionary)->void:
	var type_id:=str(row.get("type_id",""));var instance_id:=str(row.get("instance_id",type_id))
	var rect:=building_rect(instance_id)
	if instance_id=="__ghost":
		var origin:=_vector2i(row.get("tile_origin",[]));var footprint:=_vector2i(row.get("footprint",[3,3]))
		rect=Rect2(_map_origin()+Vector2(origin)*_cell_size(),Vector2(footprint)*_cell_size())
	var level:=clampi(int(row.get("level",1)),1,3)
	if type_id==_selected_id:_draw_selection(rect.grow(-1))
	var texture:=BuildingAssets.texture(type_id,level)
	if texture!=null:
		draw_texture_rect(texture,rect,false,Color.WHITE)
		_draw_label(rect,str(row.get("label",LABELS.get(type_id,type_id))))
		return
	if type_id in ["CLINIC","ARMORY"] or level>=2 and type_id in ["STORAGE","LODGE"]:
		preload("res://playtest/base_room_renderer.gd").draw_room(self,rect,type_id,level)
		_draw_label(rect,str(row.get("label",LABELS.get(type_id,type_id))))
		return
	match type_id:
		"STORAGE":
			if level==1:_draw_storage_camp(rect)
			elif level==2:_draw_storage_timber(rect)
			else:_draw_storage_stone(rect)
		"LODGE":
			if level==1:_draw_lodge_camp(rect)
			elif level==2:_draw_lodge_timber(rect)
			else:_draw_lodge_stone(rect)
		"CLINIC":
			if level==1:_draw_clinic_camp(rect)
			elif level==2:_draw_clinic_timber(rect)
			else:_draw_clinic_stone(rect)
		"MARKET":_draw_market(rect)
		"ARMORY":_draw_armory(rect)
		"GATE":_draw_gate(rect)


func _draw_placement_ghost()->void:
	if not _placement_mode or _ghost.is_empty():return
	var origin:=_vector2i(_ghost.get("tile_origin",[]));var footprint:=_vector2i(
		_ghost.get("footprint",[3,3]))
	var rect:=Rect2(_map_origin()+Vector2(origin)*_cell_size(),Vector2(footprint)*_cell_size())
	var valid:=bool(_ghost.get("accepted",false));var tone:=Color("#55d887") if valid else Color("#dc5b59")
	draw_rect(rect,Color(tone,0.28),true);draw_rect(rect,tone,false,3.0)
	var type_id:=str(_ghost.get("type_id",""));var preview:={"type_id":type_id,
		"instance_id":"__ghost","tile_origin":[origin.x,origin.y],
		"footprint":[footprint.x,footprint.y],"level":1}
	# Draw the prefab in-place with a translucent overlay rather than a detached icon.
	_draw_building(preview);draw_rect(rect,Color(tone,0.16),true)


func _on_map_gui_input(event:InputEvent)->void:
	if camera.handle(self,event):accept_event();return
	if event is InputEventScreenTouch:
		if event.pressed:
			_last_pointer=event.position
			_pointer_down=true;_pointer_origin=event.position;_pointer_dragged=false
			if _placement_mode:tile_pressed.emit(_pixel_to_tile(event.position))
		else:
			if not _placement_mode and _pointer_down and not _pointer_dragged:
				_select_building_at(event.position)
			_pointer_down=false
		accept_event()
	elif event is InputEventScreenDrag and _pointer_down:
		_pan_map(event.position)
		if event.position.distance_to(_pointer_origin)>=8.0:_pointer_dragged=true
		var tile:=_pixel_to_tile(event.position)
		if _placement_mode and tile!=_last_drag_tile:
			_last_drag_tile=tile;tile_dragged.emit(tile)
		accept_event()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			_last_pointer=event.position
			_pointer_down=true;_pointer_origin=event.position;_pointer_dragged=false
			if _placement_mode:tile_pressed.emit(_pixel_to_tile(event.position))
		else:
			if not _placement_mode and _pointer_down and not _pointer_dragged:
				_select_building_at(event.position)
			_pointer_down=false
		accept_event()
	elif event is InputEventMouseMotion and _pointer_down:
		_pan_map(event.position)
		if event.position.distance_to(_pointer_origin)>=8.0:_pointer_dragged=true
		var tile:=_pixel_to_tile(event.position)
		if _placement_mode and tile!=_last_drag_tile:
			_last_drag_tile=tile;tile_dragged.emit(tile)
		accept_event()

func _pan_map(position:Vector2)->void:
	if not _placement_mode and camera.zoom>1:
		camera.pan+=position-_last_pointer;camera.clamp_pan(self)
		_resolve_layout();queue_redraw()
	_last_pointer=position


func _select_building_at(pixel:Vector2)->void:
	# Public map only. Match the visible marker, not a large invisible area
	# that would steal neighbouring building taps. Facility cards provide 48px access.
	if fit_map_height:
		var nearest_id:=-1;var nearest_distance:=maxf(8.0,_cell_size()*0.38)
		for row in _overview.get("residents",[]):
			var center:=_map_origin()+(Vector2(_vector2i(row.tile))+Vector2.ONE*0.5)*_cell_size()
			var distance:=pixel.distance_to(center)
			if distance<nearest_distance:nearest_distance=distance;nearest_id=int(row.entity_id)
		if nearest_id>0:resident_selected.emit(nearest_id);return
	var candidates:Array[Dictionary]=[]
	for value in _settlement.get("buildings",[]):
		if not value is Dictionary:continue
		var instance_id:=str(value.get("instance_id",value.get("type_id","")))
		var physical:=building_rect(instance_id);var hit_size:=Vector2(
			maxf(48.0,physical.size.x),maxf(48.0,physical.size.y))
		var hit:=Rect2(physical.get_center()-hit_size*0.5,hit_size)
		if hit.has_point(pixel):candidates.append({"type_id":str(value.get("type_id","")),
			"distance":pixel.distance_squared_to(physical.get_center())})
	if candidates.is_empty():return
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):
		if not is_equal_approx(float(a.distance),float(b.distance)):
			return float(a.distance)<float(b.distance)
		return str(a.type_id)<str(b.type_id))
	_select_building(str(candidates[0].type_id))


func _grid_size()->Vector2i:
	return Vector2i(maxi(1,int(_settlement.get("width",16))),maxi(1,int(_settlement.get("height",16))))


func _cell_size()->float:
	var grid:=_grid_size()
	var available_height:=maxf(1.0,size.y) if fit_map_height else 320.0
	return minf(maxf(1.0,size.x)/float(grid.x),available_height/float(grid.y))*camera.zoom


func _map_origin()->Vector2:
	var extent:=Vector2(_grid_size())*_cell_size()
	return Vector2((size.x-extent.x)*0.5,0)+camera.pan


func _pixel_to_tile(pixel:Vector2)->Vector2i:
	var local:Vector2=(pixel-_map_origin())/_cell_size()
	var grid:=_grid_size()
	return Vector2i(clampi(int(floor(local.x)),0,grid.x-1),
		clampi(int(floor(local.y)),0,grid.y-1))


func _vector2i(value:Variant)->Vector2i:
	if value is Array and value.size()==2:return Vector2i(int(value[0]),int(value[1]))
	return Vector2i.ZERO


func _building_by_id(id:String)->Dictionary:
	for value in _settlement.get("buildings",[]):
		if value is Dictionary and (str(value.get("instance_id",""))==id \
				or str(value.get("type_id",""))==id):return value
	return {}


func _draw_clearing(canvas:Rect2)->void:
	var center:=Vector2(canvas.size.x*0.5,canvas.size.y*0.47)
	var points:=PackedVector2Array()
	for index in range(32):
		var angle:=TAU*float(index)/32.0
		var rough:=1.0+0.035*sin(float(index)*4.7)
		points.append(center+Vector2(cos(angle)*canvas.size.x*0.47,
			sin(angle)*canvas.size.y*0.43)*rough)
	draw_colored_polygon(points,CLEARING)
	draw_polyline(points+PackedVector2Array([points[0]]),CLEARING_EDGE,2.0,true)
	for index in range(28):
		var p:=Vector2(18+posmod(index*83, int(canvas.size.x-36)),
			18+posmod(index*47, int(canvas.size.y-40)))
		draw_circle(p,1.2,Color(CLEARING_EDGE,0.32))


func _draw_paths()->void:
	var hub:=Vector2(maxf(size.x,300.0)*0.51,
		clampf(size.y if size.y>1.0 else 320.0,300.0,340.0)*0.49)
	for id in LANDMARK_IDS:
		var rect:=building_rect(id)
		var target:=Vector2(rect.get_center().x,rect.end.y-8)
		var elbow:=Vector2(lerpf(hub.x,target.x,0.55),lerpf(hub.y,target.y,0.42))
		var points:=PackedVector2Array([hub,elbow,target])
		draw_polyline(points,PATH_DARK,10.0,true)
		draw_polyline(points,PATH,5.0,true)
	draw_circle(hub,14,PATH_DARK);draw_circle(hub,10,PATH)
	draw_circle(hub,5,Color("#242b29"));draw_arc(hub,6,0,TAU,16,STONE,2)


func _draw_fence(canvas:Rect2)->void:
	var y:=canvas.size.y*0.885
	for x in range(16,int(canvas.size.x)-16,18):
		if x>canvas.size.x*0.69 and x<canvas.size.x*0.95:continue
		draw_line(Vector2(x,y-7),Vector2(x,y+7),TIMBER_DARK,3)
		draw_line(Vector2(x-7,y-2),Vector2(x+8,y-2),TIMBER,2)


func _draw_trees(canvas:Rect2)->void:
	var points:=[Vector2(15,28),Vector2(36,48),Vector2(canvas.size.x-18,35),
		Vector2(canvas.size.x-38,58),Vector2(20,canvas.size.y-55),
		Vector2(canvas.size.x-20,canvas.size.y-50)]
	for p in points:
		draw_circle(p+Vector2(2,5),11,Color("#08100b"))
		draw_circle(p,9,Color("#1c3525"));draw_circle(p-Vector2(4,3),5,Color("#29452e"))
		draw_rect(Rect2(p.x-2,p.y+7,4,8),TIMBER_DARK)


func _draw_selection(rect:Rect2)->void:
	draw_style_box(_outline_box(SELECTED,2,7),rect.grow(3))
	for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,
		Vector2(rect.position.x,rect.end.y)]:draw_circle(corner,3,SELECTED)


func _draw_storage_camp(rect:Rect2)->void:
	var b:=rect.grow(-10)
	draw_colored_polygon(PackedVector2Array([b.position+Vector2(5,b.size.y*0.62),
		b.position+Vector2(b.size.x*0.48,5),b.position+Vector2(b.size.x-4,b.size.y*0.62)]),TARP)
	draw_line(b.position+Vector2(b.size.x*0.48,5),b.position+Vector2(b.size.x*0.48,b.size.y*0.72),BONE_DIM,2)
	_draw_crates(Rect2(b.position+Vector2(5,b.size.y*0.62),Vector2(b.size.x-10,18)),3)
	_draw_label(rect,"창고 · 야적막")


func _draw_storage_timber(rect:Rect2)->void:
	var b:=rect.grow(-9);_draw_house(b,TIMBER,ROOF,false)
	_draw_crates(Rect2(b.position+Vector2(b.size.x*0.65,b.size.y*0.58),Vector2(25,18)),3)
	_draw_label(rect,"창고 · 목조")


func _draw_storage_stone(rect:Rect2)->void:
	var b:=rect.grow(-7);_draw_house(b,STONE,ROOF_LIGHT,true)
	draw_rect(Rect2(b.position+Vector2(-2,b.size.y*0.42),Vector2(17,b.size.y*0.42)),STONE_DARK)
	_draw_crates(Rect2(b.position+Vector2(b.size.x*0.67,b.size.y*0.58),Vector2(29,20)),4)
	_draw_label(rect,"창고 · 석조고")


func _draw_lodge_camp(rect:Rect2)->void:
	var b:=rect.grow(-8)
	_draw_tent(Rect2(b.position+Vector2(1,10),Vector2(b.size.x*0.48,b.size.y*0.55)),ROOF)
	_draw_tent(Rect2(b.position+Vector2(b.size.x*0.48,4),Vector2(b.size.x*0.48,b.size.y*0.55)),TARP)
	var fire:=b.position+Vector2(b.size.x*0.5,b.size.y*0.75)
	draw_circle(fire,6,TIMBER_DARK);draw_circle(fire,3,EMBER)
	_draw_label(rect,"숙소 · 모닥불")


func _draw_lodge_timber(rect:Rect2)->void:
	var b:=rect.grow(-8);_draw_house(b,TIMBER,ROOF_LIGHT,false)
	draw_rect(Rect2(b.position+Vector2(6,b.size.y*0.56),Vector2(b.size.x-12,4)),TIMBER_DARK)
	_draw_label(rect,"숙소 · 장옥")


func _draw_lodge_stone(rect:Rect2)->void:
	var b:=rect.grow(-6);_draw_house(Rect2(b.position,Vector2(b.size.x*0.72,b.size.y)),STONE,ROOF_LIGHT,true)
	_draw_house(Rect2(b.position+Vector2(b.size.x*0.58,b.size.y*0.26),Vector2(b.size.x*0.42,b.size.y*0.72)),STONE_DARK,ROOF,false)
	draw_rect(Rect2(b.position+Vector2(b.size.x*0.18,-3),Vector2(8,18)),STONE_DARK)
	draw_circle(b.position+Vector2(b.size.x*0.22,-6),4,Color("#4b5150"))
	_draw_label(rect,"숙소 · 석조 여관")


func _draw_clinic_camp(rect:Rect2)->void:
	var b:=rect.grow(-9);_draw_tent(Rect2(b.position+Vector2(5,2),Vector2(b.size.x-10,b.size.y*0.64)),Color("#51696a"))
	_draw_sigil(b.position+Vector2(b.size.x*0.5,b.size.y*0.38),9)
	_draw_herb_bed(Rect2(b.position+Vector2(4,b.size.y*0.69),Vector2(b.size.x-8,13)),3)
	_draw_label(rect,"진료소 · 약초막")


func _draw_clinic_timber(rect:Rect2)->void:
	var b:=rect.grow(-8);_draw_house(b,TIMBER,Color("#36565b"),false)
	_draw_sigil(b.position+Vector2(b.size.x*0.5,b.size.y*0.52),8)
	_draw_herb_bed(Rect2(b.position+Vector2(b.size.x*0.66,b.size.y*0.66),Vector2(28,13)),4)
	_draw_label(rect,"진료소 · 약방")


func _draw_clinic_stone(rect:Rect2)->void:
	var b:=rect.grow(-6);_draw_house(Rect2(b.position,Vector2(b.size.x*0.72,b.size.y)),STONE,Color("#35535a"),true)
	draw_rect(Rect2(b.position+Vector2(b.size.x*0.68,b.size.y*0.34),Vector2(b.size.x*0.31,b.size.y*0.48)),STONE_DARK)
	_draw_sigil(b.position+Vector2(b.size.x*0.48,b.size.y*0.48),10)
	_draw_herb_bed(Rect2(b.position+Vector2(b.size.x*0.67,b.size.y*0.68),Vector2(28,13)),5)
	_draw_label(rect,"진료소 · 치유원")


func _draw_market(rect:Rect2)->void:
	var b:=rect.grow(-8)
	draw_rect(Rect2(b.position+Vector2(3,b.size.y*0.43),Vector2(b.size.x-6,b.size.y*0.37)),TIMBER_DARK)
	var awning:=Rect2(b.position+Vector2(1,6),Vector2(b.size.x-2,b.size.y*0.44))
	draw_rect(awning,Color("#755247"))
	for x in range(int(awning.position.x),int(awning.end.x),12):
		draw_rect(Rect2(x,awning.position.y,6,awning.size.y),Color("#a27b57"))
	for index in range(3):draw_circle(b.position+Vector2(16+index*18,b.size.y*0.64),4,[EMBER,Color("#9aaa67"),BONE][index])
	_draw_label(rect,"시장")


func _draw_armory(rect:Rect2)->void:
	var b:=rect.grow(-8);_draw_house(b,TIMBER_DARK,Color("#41464a"),false)
	var forge:=b.position+Vector2(b.size.x*0.72,b.size.y*0.58)
	draw_rect(Rect2(forge-Vector2(8,6),Vector2(16,12)),STONE_DARK)
	draw_circle(forge,5,EMBER);draw_line(b.position+Vector2(10,b.size.y*0.68),b.position+Vector2(28,b.size.y*0.38),STONE,3)
	_draw_label(rect,"대장간")


func _draw_gate(rect:Rect2)->void:
	var b:=rect.grow(-8);var center:=b.position+Vector2(b.size.x*0.5,b.size.y*0.48)
	var radius:=minf(b.size.x,b.size.y)*0.32
	draw_arc(center,radius,PI,TAU,20,STONE_DARK,10,true)
	draw_arc(center,radius,PI,TAU,20,STONE,5,true)
	draw_line(center+Vector2(-radius,0),center+Vector2(-radius,radius*0.9),STONE_DARK,9)
	draw_line(center+Vector2(radius,0),center+Vector2(radius,radius*0.9),STONE_DARK,9)
	draw_circle(center,radius*0.65,Color(CYAN,0.12));draw_arc(center,radius*0.66,0,TAU,24,CYAN,2,true)
	_draw_label(rect,"원정문")


func _draw_house(rect:Rect2,wall:Color,roof:Color,stone_base:bool)->void:
	# Orthographic roof plan: broad paired planes and a straight ridge occupy the
	# footprint. Only a narrow wall/threshold strip shows at the south edge.
	var foundation:=Rect2(rect.position+Vector2(3,4),Vector2(rect.size.x-6,rect.size.y-9))
	if stone_base:draw_rect(foundation.grow(3),STONE_DARK)
	draw_rect(foundation,wall)
	var roof_rect:=Rect2(foundation.position-Vector2(2,2),
		Vector2(foundation.size.x+4,foundation.size.y*0.78))
	var ridge_y:=roof_rect.position.y+roof_rect.size.y*0.48
	var upper:=PackedVector2Array([roof_rect.position,Vector2(roof_rect.end.x,roof_rect.position.y),
		Vector2(roof_rect.end.x-3,ridge_y),Vector2(roof_rect.position.x+3,ridge_y)])
	var lower:=PackedVector2Array([Vector2(roof_rect.position.x+3,ridge_y),
		Vector2(roof_rect.end.x-3,ridge_y),roof_rect.end,
		Vector2(roof_rect.position.x,roof_rect.end.y)])
	draw_colored_polygon(upper,roof.lightened(0.10))
	draw_colored_polygon(lower,roof.darkened(0.12))
	draw_rect(roof_rect,Color(roof).lightened(0.24),false,2)
	draw_line(Vector2(roof_rect.position.x+3,ridge_y),
		Vector2(roof_rect.end.x-3,ridge_y),Color(roof).lightened(0.34),2)
	for x in range(int(roof_rect.position.x+8),int(roof_rect.end.x-5),11):
		draw_line(Vector2(x,roof_rect.position.y+3),Vector2(x,ridge_y-2),Color(roof,0.55),1)
	var wall_strip:=Rect2(foundation.position.x,roof_rect.end.y,
		foundation.size.x,foundation.end.y-roof_rect.end.y)
	draw_rect(wall_strip,wall)
	var door:=Rect2(Vector2(foundation.get_center().x-5,wall_strip.position.y),
		Vector2(10,maxf(5,wall_strip.size.y)))
	draw_rect(door,TIMBER_DARK);draw_circle(door.position+Vector2(7,door.size.y*0.5),1,WINDOW)
	draw_rect(Rect2(wall_strip.position+Vector2(6,3),Vector2(7,5)),WINDOW)


func _draw_tent(rect:Rect2,color:Color)->void:
	var points:=PackedVector2Array([rect.position+Vector2(2,rect.size.y),
		rect.position+Vector2(rect.size.x*0.5,2),rect.end])
	draw_colored_polygon(points,color);draw_polyline(points,BONE_DIM,1.5,true)
	draw_line(rect.position+Vector2(rect.size.x*0.5,3),rect.position+Vector2(rect.size.x*0.5,rect.size.y),TIMBER_DARK,1)


func _draw_crates(rect:Rect2,count:int)->void:
	for index in range(count):
		var box:=Rect2(rect.position+Vector2(posmod(index*17,maxi(18,int(rect.size.x-13))),
			-index%2*5),Vector2(13,12))
		draw_rect(box,TIMBER);draw_rect(box.grow(-2),TIMBER_DARK,false,1)
		draw_line(box.position,box.end,TIMBER_DARK,1)


func _draw_herb_bed(rect:Rect2,count:int)->void:
	draw_rect(rect,Color("#17261b"));draw_rect(rect,TIMBER_DARK,false,2)
	for index in range(count):
		var p:=rect.position+Vector2(5+index*maxf(5,(rect.size.x-10)/maxi(1,count-1)),rect.size.y*0.5)
		draw_line(p+Vector2(0,4),p-Vector2(0,4),Color("#71905f"),2)
		draw_circle(p-Vector2(3,2),2,Color("#86a96d"));draw_circle(p+Vector2(3,-3),2,Color("#668f66"))


func _draw_sigil(center:Vector2,radius:float)->void:
	draw_circle(center,radius,Color("#183d42"));draw_arc(center,radius,0,TAU,18,CYAN,2,true)
	draw_line(center-Vector2(radius*0.55,0),center+Vector2(radius*0.55,0),CYAN,2)
	draw_line(center-Vector2(0,radius*0.55),center+Vector2(0,radius*0.55),CYAN,2)


func _draw_label(rect:Rect2,text:String)->void:
	var font_size:=11
	var width:=KoreanFont.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var position:=Vector2(rect.get_center().x-width*0.5,rect.end.y-3)
	draw_rect(Rect2(position-Vector2(3,font_size),Vector2(width+6,font_size+4)),Color("#09100dcc"))
	draw_string(KoreanFont,position,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,BONE)


func _outline_box(color:Color,width:int,radius:int)->StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=Color(color,0.06)
	box.border_color=color
	box.set_border_width_all(width);box.set_corner_radius_all(radius)
	return box
