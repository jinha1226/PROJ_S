class_name Ascii3DLab
extends Control

signal close_requested

const GRID_SIZE:=15
const CENTER:=7
const FONT:FontFile=preload("res://assets/fonts/NanumSquareR.ttf")
const HERO_START:=Vector2i(7,8)
const ENEMY_START:=Vector2i(10,8)
const VISIBLE_RADIUS:=5
const CAMERA_HEIGHT:=12.0
const CAMERA_BACK_OFFSET:=12.0
const CAMERA_ORTHO_SIZE:=19.6

var viewport_container:SubViewportContainer
var input_catcher:Control
var lab_viewport:SubViewport
var world_root:Node3D
var camera:Camera3D
var tile_nodes:Dictionary={}
var tile_glyphs:Dictionary={}
var tile_glyph_layers:Dictionary={}
var materials:Dictionary={}
var hero_root:Node3D
var enemy_root:Node3D
var enemy_glyph:Label3D
var effect_root:Node3D
var hero_cell:=HERO_START
var enemy_cell:=ENEMY_START
var enemy_health:=21
var seen_cells:Dictionary={}
var active_effects:Array=[]
var enemy_recoil_remaining:=0.0
var movement_settling:=false
var move_elapsed:=0.0
var move_duration:=0.16
var move_visual_from:=Vector3.ZERO
var move_visual_to:=Vector3.ZERO
var move_camera_from:=Vector3.ZERO
var move_camera_to:=Vector3.ZERO
var pointer_lock_remaining:=0.0
var pointer_cell_resolver_for_test:Callable
var interaction_count:=0
var authoritative_state_accessed:=false
var status_label:Label

func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	_build_viewport()
	_build_overlay()
	_build_room()
	_reset_demo()
	resized.connect(_sync_viewport_size)
	_sync_viewport_size()
	set_process(true)

func _build_viewport()->void:
	viewport_container=SubViewportContainer.new();viewport_container.name="Ascii3DViewportContainer"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch=false;viewport_container.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(viewport_container)
	lab_viewport=SubViewport.new();lab_viewport.name="Ascii3DSubViewport"
	lab_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	lab_viewport.msaa_3d=Viewport.MSAA_2X
	viewport_container.add_child(lab_viewport)
	world_root=Node3D.new();world_root.name="Ascii3DWorld";lab_viewport.add_child(world_root)
	var environment:=WorldEnvironment.new();environment.name="DarkEnvironment"
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("#03070b")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("#7890a2")
	env.ambient_light_energy=0.46;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment=env;world_root.add_child(environment)
	var light:=DirectionalLight3D.new();light.name="SoftKeyLight";light.light_color=Color("#d5e8ff")
	light.light_energy=1.25;light.rotation_degrees=Vector3(-58,-32,0);light.shadow_enabled=true
	world_root.add_child(light)
	camera=Camera3D.new();camera.name="FixedOrthographicCamera";camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=CAMERA_ORTHO_SIZE;camera.position=Vector3(0,CAMERA_HEIGHT,CAMERA_BACK_OFFSET);world_root.add_child(camera)
	effect_root=Node3D.new();effect_root.name="TransientGlyphEffects";world_root.add_child(effect_root)

func _build_overlay()->void:
	# A plain sibling Control owns pointer input. SubViewportContainer forwards
	# embedded input internally on Web and is not a reliable gui_input source.
	input_catcher=Control.new();input_catcher.name="WorldInputCatcher"
	input_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_catcher.offset_top=88;input_catcher.offset_bottom=-76
	input_catcher.mouse_filter=Control.MOUSE_FILTER_STOP
	input_catcher.gui_input.connect(_on_world_input);add_child(input_catcher)
	var scrim:=ColorRect.new();scrim.name="TopScrim";scrim.color=Color("#07101bd9")
	scrim.set_anchors_preset(Control.PRESET_TOP_WIDE);scrim.custom_minimum_size.y=88;scrim.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var header:=HBoxContainer.new();header.name="LabHeader";header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left=10;header.offset_right=-10;header.offset_top=8;header.offset_bottom=80;header.add_theme_constant_override("separation",8)
	add_child(header)
	var title:=Label.new();title.name="LabTitle";title.text="3D 시각 실험\n45° 경사 탑뷰 · 축 정렬";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font",FONT);title.add_theme_font_size_override("font_size",18);header.add_child(title)
	var reset:=Button.new();reset.name="LabReset";reset.text="초기화";reset.custom_minimum_size=Vector2(68,48)
	reset.add_theme_font_override("font",FONT);reset.pressed.connect(_reset_demo);header.add_child(reset)
	var close:=Button.new();close.name="BackTo2D";close.text="2D로";close.custom_minimum_size=Vector2(68,48)
	close.add_theme_font_override("font",FONT);close.pressed.connect(func():close_requested.emit());header.add_child(close)
	var footer:=PanelContainer.new();footer.name="LabInstructions";footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left=8;footer.offset_right=-8;footer.offset_top=-76;footer.offset_bottom=-8;footer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(footer)
	status_label=Label.new();status_label.name="LabStatus";status_label.add_theme_font_override("font",FONT)
	status_label.add_theme_font_size_override("font_size",16);status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;footer.add_child(status_label)

func _build_room()->void:
	var terrain_meshes:Dictionary={}
	for row in [{"id":"floor","size":Vector3(0.98,0.025,0.98)},
			{"id":"metal","size":Vector3(0.96,0.10,0.96)},
			{"id":"water","size":Vector3(0.98,0.025,0.98)},
			{"id":"rubble","size":Vector3(0.86,0.07,0.86)},
			{"id":"wall","size":Vector3(0.94,0.68,0.94)}]:
		var mesh:=BoxMesh.new();mesh.size=row.size;terrain_meshes[str(row.id)]=mesh
	var substrate_mesh:=BoxMesh.new();substrate_mesh.size=Vector3(15.7,0.12,15.7)
	var substrate:=MeshInstance3D.new();substrate.name="DarkSubstrate";substrate.mesh=substrate_mesh
	substrate.position=Vector3(0,-0.15,0);substrate.material_override=_material("substrate","VISIBLE")
	world_root.add_child(substrate)
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var cell:=Vector2i(x,y);var terrain:=_terrain_at(cell)
			var tile:=MeshInstance3D.new();tile.name="Tile_%02d_%02d"%[x,y]
			tile.mesh=terrain_meshes[terrain]
			var height_offset:float={"floor":-0.0125,"metal":0.05,"water":-0.0625,
				"rubble":0.035+float((x*17+y*31)%3)*0.012,"wall":0.34}[terrain]
			var rubble_offset:=Vector3(float((x*7+y*3)%3-1)*0.045,0,
				float((x*5+y*11)%3-1)*0.04) if terrain=="rubble" else Vector3.ZERO
			tile.position=_cell_world(cell)+Vector3(0,float(height_offset),0)+rubble_offset
			world_root.add_child(tile);tile_nodes[cell]=tile
			var layers:=_build_terrain_glyph_layers(cell,terrain,rubble_offset)
			tile_glyph_layers[cell]=layers;tile_glyphs[cell]=layers[0]
	_build_actors()

func _build_terrain_glyph_layers(cell:Vector2i,terrain:String,offset:Vector3)->Array:
	var base:=_cell_world(cell)+offset;var layers:Array=[]
	var top_height:float={"floor":0.018,"metal":0.118,"water":-0.038,
		"rubble":0.085+float((cell.x*17+cell.y*31)%3)*0.012,"wall":0.70}[terrain]
	var top_colors:={"floor":Color("#a8b3bc"),"metal":Color("#77d6e5"),
		"water":Color("#56c9f2"),"rubble":Color("#d0a67a"),"wall":Color("#d5e5ef")}
	var top_color:Color=top_colors[terrain]
	layers.append(_terrain_label("TopGlyph_%02d_%02d"%[cell.x,cell.y],_terrain_glyph(terrain),
		base+Vector3(0,top_height,0),44,top_color,true,terrain=="wall",0.0))
	if terrain=="water":
		layers.append(_terrain_label("RippleGlyph_%02d_%02d"%[cell.x,cell.y],"~",
			base+Vector3(0.12,-0.052,0.10),34,Color("#287da2"),true,false,0.12))
	elif terrain=="rubble":
		layers.append(_terrain_label("RubbleShadow_%02d_%02d"%[cell.x,cell.y],".",
			base+Vector3(-0.12,float(top_height)-0.012,0.10),30,Color("#765e4b"),true,false,0.18))
	elif terrain=="wall":
		# Camera is always on +Z. Two restrained vertical layers make the
		# extrusion itself ASCII while the box only supplies occlusion/shadow.
		layers.append(_terrain_label("WallFace_%02d_%02d"%[cell.x,cell.y],"#",
			base+Vector3(0,0.43,0.475),38,Color("#718493"),false,true,0.20))
		layers.append(_terrain_label("WallFoot_%02d_%02d"%[cell.x,cell.y],":",
			base+Vector3(0,0.14,0.478),28,Color("#42515e"),false,true,0.34))
	return layers

func _terrain_label(node_name:String,text:String,position:Vector3,font_size:int,
		color:Color,flat:bool,no_depth:bool,memory_bias:float)->Label3D:
	var glyph:=Label3D.new();glyph.name=node_name;glyph.text=text;glyph.font=FONT
	glyph.font_size=font_size;glyph.outline_size=4;glyph.position=position
	glyph.rotation_degrees.x=-90.0 if flat else 0.0
	glyph.no_depth_test=no_depth;glyph.modulate=color
	glyph.set_meta("base_color",color);glyph.set_meta("memory_bias",memory_bias)
	world_root.add_child(glyph);return glyph

func _build_actors()->void:
	hero_root=Node3D.new();hero_root.name="GoldProtagonist";world_root.add_child(hero_root)
	var hero_base:=CylinderMesh.new();hero_base.top_radius=0.24;hero_base.bottom_radius=0.3;hero_base.height=0.12
	var base:=MeshInstance3D.new();base.name="HeroGrounding";base.mesh=hero_base;base.position.y=0.08
	base.material_override=_material("hero","VISIBLE");hero_root.add_child(base)
	for limb in [{"p":Vector3(-0.16,0.42,0),"s":Vector3(0.08,0.55,0.08),"r":-13.0},
			{"p":Vector3(0.16,0.42,0),"s":Vector3(0.08,0.55,0.08),"r":13.0}]:
		var mesh:=BoxMesh.new();mesh.size=limb.s
		var node:=MeshInstance3D.new();node.mesh=mesh;node.position=limb.p;node.rotation_degrees.z=limb.r
		node.material_override=_material("hero","VISIBLE");hero_root.add_child(node)
	var hero_glyph:=Label3D.new();hero_glyph.name="HeroGlyph";hero_glyph.text="@";hero_glyph.font=FONT
	hero_glyph.font_size=96;hero_glyph.outline_size=8;hero_glyph.modulate=Color("#ffd34e")
	hero_glyph.billboard=BaseMaterial3D.BILLBOARD_ENABLED;hero_glyph.no_depth_test=true;hero_glyph.position.y=1.05
	hero_root.add_child(hero_glyph)
	enemy_root=Node3D.new();enemy_root.name="RedGoblin";world_root.add_child(enemy_root)
	var enemy_base:=CylinderMesh.new();enemy_base.top_radius=0.2;enemy_base.bottom_radius=0.28;enemy_base.height=0.1
	var enemy_ground:=MeshInstance3D.new();enemy_ground.name="EnemyGrounding";enemy_ground.mesh=enemy_base;enemy_ground.position.y=0.06
	enemy_ground.material_override=_material("enemy","VISIBLE");enemy_root.add_child(enemy_ground)
	enemy_glyph=Label3D.new();enemy_glyph.name="EnemyGlyph";enemy_glyph.text="g";enemy_glyph.font=FONT
	enemy_glyph.font_size=86;enemy_glyph.outline_size=8;enemy_glyph.modulate=Color("#ff5b5b")
	enemy_glyph.billboard=BaseMaterial3D.BILLBOARD_ENABLED;enemy_glyph.no_depth_test=true;enemy_glyph.position.y=0.78
	enemy_root.add_child(enemy_glyph)

func _material(terrain:String,visibility:String)->StandardMaterial3D:
	var key:=terrain+"/"+visibility
	if materials.has(key):return materials[key]
	var colors:={"substrate":Color("#071017"),"floor":Color("#26303a"),"metal":Color("#476270"),
		"water":Color("#102f43"),"rubble":Color("#3f352d"),"wall":Color("#1e2a34"),
		"hero":Color("#d7a91f"),"enemy":Color("#9c252e")}
	var color:Color=colors.get(terrain,Color("#252d35"))
	if visibility=="MEMORY":color=color.darkened(0.56)
	elif visibility=="UNSEEN":color=Color("#071017")
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=0.82
	if visibility=="VISIBLE" and terrain in ["metal","water","hero","enemy"]:
		mat.emission_enabled=true;mat.emission=color.lightened(0.08);mat.emission_energy_multiplier=0.32
	materials[key]=mat;return mat

func _terrain_at(cell:Vector2i)->String:
	if cell.x==0 or cell.y==0 or cell.x==GRID_SIZE-1 or cell.y==GRID_SIZE-1:return "wall"
	if cell in [Vector2i(4,4),Vector2i(5,4),Vector2i(6,4),Vector2i(4,5),Vector2i(9,10),Vector2i(9,11)]:return "wall"
	if cell.x in range(2,6) and cell.y in range(10,13):return "water"
	if cell.x in range(9,13) and cell.y in range(3,6):return "metal"
	if cell in [Vector2i(3,7),Vector2i(4,7),Vector2i(11,11),Vector2i(12,11)]:return "rubble"
	return "floor"

func _terrain_glyph(terrain:String)->String:
	return {"floor":".","metal":"=","water":"~","rubble":":","wall":"#"}.get(terrain,".")

func _cell_world(cell:Vector2i)->Vector3:
	return Vector3(cell.x-CENTER,0,cell.y-CENTER)

func _reset_demo()->void:
	hero_cell=HERO_START;enemy_cell=ENEMY_START;enemy_health=21;interaction_count=0;enemy_recoil_remaining=0.0
	movement_settling=false;move_elapsed=0.0;pointer_lock_remaining=0.0
	seen_cells.clear();_reveal_visible();_update_visuals();_clear_effects()
	status_label.text="바닥을 터치해 한 칸 이동 · 인접한 빨간 g를 터치해 공격"

func _reveal_visible()->void:
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var cell:=Vector2i(x,y)
			if _distance(hero_cell,cell)<=VISIBLE_RADIUS:seen_cells[cell]=true

func _update_visuals(snap_hero:bool=true,snap_camera:bool=true)->void:
	for cell in tile_nodes:
		var visibility:="VISIBLE" if _distance(hero_cell,cell)<=VISIBLE_RADIUS else ("MEMORY" if seen_cells.has(cell) else "UNSEEN")
		var terrain:=_terrain_at(cell);tile_nodes[cell].material_override=_material(terrain,visibility)
		for glyph_value in tile_glyph_layers[cell]:
			var glyph:=glyph_value as Label3D;glyph.visible=visibility!="UNSEEN"
			var base_color:Color=glyph.get_meta("base_color",Color.WHITE)
			var bias:=float(glyph.get_meta("memory_bias",0.0))
			glyph.modulate=base_color if visibility=="VISIBLE" else Color.from_hsv(
				base_color.h,base_color.s*0.22,base_color.v*maxf(0.18,0.34-bias),base_color.a*0.72)
	if snap_hero:hero_root.position=_cell_world(hero_cell)
	enemy_root.position=_cell_world(enemy_cell);enemy_root.visible=enemy_health>0 and _distance(hero_cell,enemy_cell)<=VISIBLE_RADIUS
	if snap_camera:_follow_hero()

func _follow_hero()->void:
	_set_camera_focus(_cell_world(hero_cell))

func _set_camera_focus(focus:Vector3)->void:
	# Cardinal-axis 45-degree pitch: no yaw or diagonal/isometric map rotation.
	# Screen-right remains world +X while screen-down advances world +Z.
	camera.look_at_from_position(focus+Vector3(0,CAMERA_HEIGHT,CAMERA_BACK_OFFSET),focus,Vector3.UP)

func _on_world_input(event:InputEvent)->void:
	var point:=Vector2(-1,-1)
	if event is InputEventScreenTouch and event.pressed:point=event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:point=event.position
	if point.x<0:return
	if movement_settling or pointer_lock_remaining>0.0:
		if input_catcher.is_inside_tree():input_catcher.accept_event()
		return
	var viewport_point:=point+input_catcher.position
	var cell:Vector2i=pointer_cell_resolver_for_test.call(viewport_point) \
		if pointer_cell_resolver_for_test.is_valid() else _screen_to_cell(viewport_point)
	if cell.x<0:return
	if _interact(cell):pointer_lock_remaining=0.18
	if input_catcher.is_inside_tree():input_catcher.accept_event()

func _screen_to_cell(point:Vector2)->Vector2i:
	if viewport_container.size.x<=0 or viewport_container.size.y<=0:return Vector2i(-1,-1)
	var projected:=Vector2(point.x/viewport_container.size.x*lab_viewport.size.x,
		point.y/viewport_container.size.y*lab_viewport.size.y)
	var origin:=camera.project_ray_origin(projected);var direction:=camera.project_ray_normal(projected)
	if absf(direction.y)<0.0001:return Vector2i(-1,-1)
	var world_point:=origin+direction*(-origin.y/direction.y)
	var cell:=Vector2i(roundi(world_point.x)+CENTER,roundi(world_point.z)+CENTER)
	return cell if cell.x>=0 and cell.y>=0 and cell.x<GRID_SIZE and cell.y<GRID_SIZE else Vector2i(-1,-1)

func _interact(target:Vector2i)->bool:
	if enemy_health>0 and target==enemy_cell and _distance(hero_cell,enemy_cell)<=1:
		_attack_enemy();return true
	var delta:=target-hero_cell
	if delta==Vector2i.ZERO:return false
	var candidates:Array[Vector2i]=[hero_cell+Vector2i(signi(delta.x),signi(delta.y))]
	if absi(delta.x)>=absi(delta.y):
		candidates.append(hero_cell+Vector2i(signi(delta.x),0));candidates.append(hero_cell+Vector2i(0,signi(delta.y)))
	else:
		candidates.append(hero_cell+Vector2i(0,signi(delta.y)));candidates.append(hero_cell+Vector2i(signi(delta.x),0))
	for candidate in candidates:
		if _walkable(candidate) and (enemy_health<=0 or candidate!=enemy_cell):
			var previous:=hero_cell;hero_cell=candidate;interaction_count+=1
			move_visual_from=hero_root.position;move_visual_to=_cell_world(hero_cell)
			move_camera_from=_cell_world(previous);move_camera_to=_cell_world(hero_cell)
			move_elapsed=0.0;movement_settling=true
			_reveal_visible();_spawn_target_flash(candidate,Color("#75c8ff"));_update_visuals(false,false)
			status_label.text="한 칸 이동 → (%d,%d) · g 체력 %d/21"%[hero_cell.x,hero_cell.y,enemy_health];return true
	status_label.text="# 벽은 지나갈 수 없습니다."
	return false

func _attack_enemy()->void:
	interaction_count+=1;enemy_health=maxi(0,enemy_health-7)
	_spawn_target_flash(enemy_cell,Color("#ff756d"));_spawn_damage_number(7);_spawn_shards()
	var away:=Vector3(signf(enemy_root.position.x-hero_root.position.x),0,signf(enemy_root.position.z-hero_root.position.z))*0.18
	enemy_root.position+=away;enemy_recoil_remaining=0.16
	status_label.text="7 피해! · g 체력 %d/21%s"%[enemy_health," · 초기화로 다시 보기" if enemy_health==0 else ""]

func _spawn_target_flash(cell:Vector2i,color:Color)->void:
	var label:=Label3D.new();label.name="TargetFlash";label.text="◇";label.font=FONT;label.font_size=72
	label.modulate=color;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=true
	label.position=_cell_world(cell)+Vector3(0,0.35,0);effect_root.add_child(label)
	active_effects.append({"node":label,"age":0.0,"duration":0.24,"velocity":Vector3(0,0.25,0)})

func _spawn_damage_number(value:int)->void:
	var label:=Label3D.new();label.name="DamageNumber";label.text="-%d"%value;label.font=FONT;label.font_size=118
	label.modulate=Color("#fff0a8");label.outline_size=12;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=true
	label.position=_cell_world(enemy_cell)+Vector3(0,1.28,0);effect_root.add_child(label)
	active_effects.append({"node":label,"age":0.0,"duration":0.9,"velocity":Vector3(0,1.25,0)})

func _spawn_shards()->void:
	var directions:=[Vector3(-0.7,0.8,0),Vector3(0.7,0.72,0),Vector3(0,0.88,-0.55),Vector3(0,0.65,0.62)]
	for index in range(directions.size()):
		var shard:=Label3D.new();shard.name="GlyphShard%d"%index;shard.text=["'","·","+","*"][index]
		shard.font=FONT;shard.font_size=44;shard.modulate=Color("#ff8a72");shard.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		shard.position=_cell_world(enemy_cell)+Vector3(0,0.78,0);effect_root.add_child(shard)
		active_effects.append({"node":shard,"age":0.0,"duration":0.55,"velocity":directions[index]})

func _process(delta:float)->void:
	pointer_lock_remaining=maxf(0.0,pointer_lock_remaining-delta)
	if movement_settling:
		move_elapsed=minf(move_duration,move_elapsed+delta)
		var move_t:=clampf(move_elapsed/move_duration,0.0,1.0)
		var move_eased:=move_t*move_t*(3.0-2.0*move_t)
		hero_root.position=move_visual_from.lerp(move_visual_to,move_eased)
		# Give the actor a brief visual lead before the fixed camera catches up.
		# This preserves centering without making a one-cell move disappear.
		var camera_t:=clampf((move_t-0.45)/0.55,0.0,1.0)
		var camera_eased:=camera_t*camera_t*(3.0-2.0*camera_t)
		_set_camera_focus(move_camera_from.lerp(move_camera_to,camera_eased))
		if move_elapsed>=move_duration:
			hero_root.position=move_visual_to
			_set_camera_focus(move_camera_to)
			movement_settling=false
	if enemy_recoil_remaining>0.0:
		enemy_recoil_remaining=maxf(0.0,enemy_recoil_remaining-delta)
		enemy_root.position=enemy_root.position.lerp(_cell_world(enemy_cell),minf(1.0,delta*14.0))
		if enemy_recoil_remaining<=0.0:enemy_root.position=_cell_world(enemy_cell)
	for index in range(active_effects.size()-1,-1,-1):
		var effect:Dictionary=active_effects[index];var node:Node3D=effect.node
		effect.age=float(effect.age)+delta
		if float(effect.age)>=float(effect.duration) or not is_instance_valid(node):
			if is_instance_valid(node):node.queue_free()
			active_effects.remove_at(index);continue
		node.position+=Vector3(effect.velocity)*delta
		if node is Label3D:node.modulate.a=1.0-float(effect.age)/float(effect.duration)
		active_effects[index]=effect

func _clear_effects()->void:
	for child in effect_root.get_children():child.queue_free()
	active_effects.clear()

func _walkable(cell:Vector2i)->bool:
	return cell.x>0 and cell.y>0 and cell.x<GRID_SIZE-1 and cell.y<GRID_SIZE-1 and _terrain_at(cell)!="wall"

func _distance(a:Vector2i,b:Vector2i)->int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

func _sync_viewport_size()->void:
	var target:=Vector2i(maxi(1,roundi(size.x)),maxi(1,roundi(size.y)))
	if lab_viewport!=null:lab_viewport.size=target

func demo_state()->Dictionary:
	return {"hero":[hero_cell.x,hero_cell.y],"enemy":[enemy_cell.x,enemy_cell.y],
		"enemy_health":enemy_health,"seen_count":seen_cells.size(),"interaction_count":interaction_count,
		"authoritative_state_accessed":authoritative_state_accessed}.duplicate(true)
