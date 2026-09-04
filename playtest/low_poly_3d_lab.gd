class_name LowPoly3DLab
extends Control

signal close_requested

const PawnScript=preload("res://playtest/low_poly_pawn_3d.gd")
const FONT:FontFile=preload("res://assets/fonts/LivingWorldMonoKRBold.ttf")
const VIEW_TOPDOWN := "TOPDOWN"
const VIEW_PITCHED := "PITCHED"

var viewport_container:SubViewportContainer
var lab_viewport:SubViewport
var world_root:Node3D
var camera:Camera3D
var pawn:LowPolyPawn3D
var enemy:LowPolyPawn3D
var torch_light:OmniLight3D
var torch_flame:MeshInstance3D
var status_label:Label
var topdown_button:Button
var pitched_button:Button
var skin_button:Button
var gear_button:Button
var view_mode:=VIEW_PITCHED
var pawn_cell:=Vector2i(0,1)
var gear_enabled:=true
var painted_skin_enabled:=true
var interaction_count:=0
var authoritative_state_accessed:=false
var _torch_time:=0.0
var _move_tween:Tween
var _is_moving:=false
var _floor_materials:Array[StandardMaterial3D]=[]

func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	_build_viewport()
	_build_world()
	_build_overlay()
	reset_demo()
	resized.connect(_sync_viewport_size)
	_sync_viewport_size()
	set_process(true)

func _build_viewport()->void:
	viewport_container=SubViewportContainer.new();viewport_container.name="LowPoly3DViewportContainer"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch=false;viewport_container.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(viewport_container)
	lab_viewport=SubViewport.new();lab_viewport.name="LowPoly3DSubViewport"
	lab_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	lab_viewport.msaa_3d=Viewport.MSAA_4X
	lab_viewport.scaling_3d_mode=Viewport.SCALING_3D_MODE_BILINEAR
	viewport_container.add_child(lab_viewport)
	world_root=Node3D.new();world_root.name="LowPolyWorld";lab_viewport.add_child(world_root)
	var environment:=WorldEnvironment.new();environment.name="DungeonEnvironment"
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("#08090b")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("#5c6a76")
	env.ambient_light_energy=0.42;env.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment=env;world_root.add_child(environment)
	camera=Camera3D.new();camera.name="SharedOrthographicCamera"
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=10.8
	camera.current=true;world_root.add_child(camera)
	var moon:=DirectionalLight3D.new();moon.name="ColdMoonLight";moon.light_color=Color("#9aaab7")
	moon.light_energy=0.74;moon.shadow_enabled=true;moon.rotation_degrees=Vector3(-58,-24,0)
	world_root.add_child(moon)

func _build_world()->void:
	_build_floor()
	_build_walls_and_props()
	pawn=PawnScript.new();pawn.name="PrototypeHero";pawn.species="human";world_root.add_child(pawn)
	if pawn.visual_root==null:pawn._ready()
	enemy=PawnScript.new();enemy.name="PrototypeGoblin";enemy.species="goblin"
	enemy.equipment_visible=false;enemy.scale=Vector3.ONE*0.88;world_root.add_child(enemy)
	if enemy.visual_root==null:enemy._ready()
	enemy.position=Vector3(2.25,0,-1.1);enemy.rotation.y=deg_to_rad(150)
	_build_blood_pool(Vector3(2.95,0.018,-2.25))

func _build_floor()->void:
	_floor_materials=[
		_material(Color("#2c2d2c"),0.0,1.0),
		_material(Color("#32312e"),0.0,1.0),
		_material(Color("#272a29"),0.0,1.0),
	]
	var floor_root:=Node3D.new();floor_root.name="StoneFloor";world_root.add_child(floor_root)
	for z in range(-5,5):
		for x in range(-5,5):
			var mesh:=BoxMesh.new();mesh.size=Vector3(0.97,0.12,0.97)
			var tile:=_mesh("Floor_%02d_%02d"%[x+5,z+5],mesh,
				_floor_materials[posmod(x*13+z*7,3)],floor_root,Vector3(x, -0.07,z))
			tile.rotation.y=deg_to_rad(float(posmod(x*17+z*11,3)-1)*0.45)
			if posmod(x*19+z*23,11)==0:_add_floor_crack(floor_root,Vector3(x,0.003,z))

func _add_floor_crack(parent:Node3D,position:Vector3)->void:
	var crack_material:=_material(Color("#111313"),0.0,1.0)
	for offset in [Vector3(-0.10,0,0),Vector3(0.09,0,0.08)]:
		var crack_mesh:=BoxMesh.new();crack_mesh.size=Vector3(0.30,0.012,0.025)
		var crack:=_mesh("StoneCrack",crack_mesh,crack_material,parent,position+offset)
		crack.rotation.y=0.45 if offset.x<0 else -0.72

func _build_walls_and_props()->void:
	var wall_material:=_material(Color("#242726"),0.0,0.98)
	var mortar_material:=_material(Color("#161818"),0.0,1.0)
	var walls:=Node3D.new();walls.name="DungeonWalls";world_root.add_child(walls)
	for x in range(-5,6):
		for level in range(2):
			var block_mesh:=BoxMesh.new();block_mesh.size=Vector3(0.94,0.64,0.58)
			var offset:=0.0 if level==0 else 0.18
			_mesh("NorthWall",block_mesh,wall_material if posmod(x+level,3) else mortar_material,
				walls,Vector3(x+offset,0.32+level*0.64,-5.05))
	for z in range(-4,4):
		var side_mesh:=BoxMesh.new();side_mesh.size=Vector3(0.58,1.28,0.94)
		_mesh("WestWall",side_mesh,wall_material,walls,Vector3(-5.05,0.64,z))
	_build_crate(walls,Vector3(-2.6,0, -2.8))
	_build_crate(walls,Vector3(-2.05,0,-3.0),0.78)
	_build_torch(walls,Vector3(2.7,1.25,-4.68))

func _build_crate(parent:Node3D,position:Vector3,scale_factor:float=1.0)->void:
	var wood:=_material(Color("#493326"),0.0,0.95)
	var band:=_material(Color("#252525"),0.55,0.58)
	var crate_root:=Node3D.new();crate_root.name="Crate";crate_root.position=position
	crate_root.scale=Vector3.ONE*scale_factor;parent.add_child(crate_root)
	var crate_mesh:=BoxMesh.new();crate_mesh.size=Vector3(0.78,0.78,0.78)
	_mesh("CrateBody",crate_mesh,wood,crate_root,Vector3(0,0.39,0))
	for x in [-0.30,0.30]:
		var band_mesh:=BoxMesh.new();band_mesh.size=Vector3(0.07,0.82,0.82)
		_mesh("CrateBand",band_mesh,band,crate_root,Vector3(x,0.39,0))

func _build_torch(parent:Node3D,position:Vector3)->void:
	var torch_root:=Node3D.new();torch_root.name="WallTorch";torch_root.position=position;parent.add_child(torch_root)
	var iron:=_material(Color("#353739"),0.7,0.45)
	var wood:=_material(Color("#543423"),0.0,0.92)
	var bracket_mesh:=BoxMesh.new();bracket_mesh.size=Vector3(0.10,0.10,0.52)
	_mesh("TorchBracket",bracket_mesh,iron,torch_root,Vector3(0,0,0.18),Vector3(deg_to_rad(-18),0,0))
	var handle_mesh:=CylinderMesh.new();handle_mesh.top_radius=0.055;handle_mesh.bottom_radius=0.075
	handle_mesh.height=0.58;handle_mesh.radial_segments=7
	_mesh("TorchHandle",handle_mesh,wood,torch_root,Vector3(0,-0.03,0.36),Vector3(deg_to_rad(-18),0,0))
	var flame_material:=_material(Color("#ff9a36"),0.0,0.72)
	flame_material.emission_enabled=true;flame_material.emission=Color("#ff6d22")
	flame_material.emission_energy_multiplier=2.2
	var flame_mesh:=SphereMesh.new();flame_mesh.radius=0.15;flame_mesh.height=0.38
	flame_mesh.radial_segments=7;flame_mesh.rings=4
	torch_flame=_mesh("TorchFlame",flame_mesh,flame_material,torch_root,Vector3(0,0.43,0.50))
	torch_flame.scale=Vector3(0.72,1.25,0.72)
	torch_light=OmniLight3D.new();torch_light.name="WarmTorchLight"
	torch_light.position=Vector3(0,0.43,0.52);torch_light.light_color=Color("#ff9b54")
	torch_light.light_energy=4.2;torch_light.omni_range=5.8
	torch_light.omni_attenuation=1.25;torch_light.shadow_enabled=true;torch_root.add_child(torch_light)

func _build_blood_pool(position:Vector3)->void:
	var blood_material:=_material(Color("#28070a"),0.0,0.78)
	var pool_mesh:=CylinderMesh.new();pool_mesh.top_radius=0.46;pool_mesh.bottom_radius=0.40
	pool_mesh.height=0.018;pool_mesh.radial_segments=11
	var pool:=_mesh("OldBloodPool",pool_mesh,blood_material,world_root,position)
	pool.scale=Vector3(1.15,1.0,0.66);pool.rotation.y=0.42

func _material(color:Color,metallic:float,roughness:float)->StandardMaterial3D:
	var material:=StandardMaterial3D.new();material.albedo_color=color
	material.metallic=metallic;material.roughness=roughness
	material.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON
	return material

func _mesh(node_name:String,mesh:PrimitiveMesh,material:Material,parent:Node3D,
		position:Vector3,rotation:Vector3=Vector3.ZERO)->MeshInstance3D:
	var instance:=MeshInstance3D.new();instance.name=node_name;instance.mesh=mesh
	instance.material_override=material;instance.position=position;instance.rotation=rotation
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON;parent.add_child(instance)
	return instance

func _build_overlay()->void:
	var top_scrim:=ColorRect.new();top_scrim.name="TopScrim";top_scrim.color=Color("#080a0ddd")
	top_scrim.set_anchors_preset(Control.PRESET_TOP_WIDE);top_scrim.custom_minimum_size.y=116
	top_scrim.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(top_scrim)
	var header:=VBoxContainer.new();header.name="PrototypeHeader";header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left=10;header.offset_right=-10;header.offset_top=8;header.offset_bottom=110
	header.add_theme_constant_override("separation",4);add_child(header)
	var title_row:=HBoxContainer.new();title_row.add_theme_constant_override("separation",6);header.add_child(title_row)
	var title:=Label.new();title.name="LabTitle";title.text="실제 3D 폰 테스트\n한 모델 · 두 탑뷰 · 분리 장비"
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.add_theme_font_override("font",FONT)
	title.add_theme_font_size_override("font_size",16);title_row.add_child(title)
	var close:=_button("BackToGame","닫기",Vector2(58,48));close.pressed.connect(func():close_requested.emit())
	title_row.add_child(close)
	var view_row:=HBoxContainer.new();view_row.add_theme_constant_override("separation",6);header.add_child(view_row)
	topdown_button=_button("TopdownCamera","2D 탑뷰",Vector2(82,44));topdown_button.toggle_mode=true
	topdown_button.pressed.connect(func():set_view_mode(VIEW_TOPDOWN));view_row.add_child(topdown_button)
	pitched_button=_button("PitchedCamera","2.5D 탑뷰",Vector2(94,44));pitched_button.toggle_mode=true
	pitched_button.pressed.connect(func():set_view_mode(VIEW_PITCHED));view_row.add_child(pitched_button)
	skin_button=_button("PaintedSkinToggle","2D 스킨",Vector2(96,44));skin_button.toggle_mode=true
	skin_button.set_pressed_no_signal(true);skin_button.pressed.connect(toggle_painted_skin)
	view_row.add_child(skin_button)
	gear_button=_button("GearToggle","갑옷 켜짐",Vector2(88,44));gear_button.pressed.connect(toggle_gear)
	view_row.add_child(gear_button)
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;view_row.add_child(spacer)

	var footer:=PanelContainer.new();footer.name="PrototypeControls";footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left=8;footer.offset_right=-8;footer.offset_top=-132;footer.offset_bottom=-8;add_child(footer)
	var controls:=VBoxContainer.new();controls.add_theme_constant_override("separation",5);footer.add_child(controls)
	status_label=Label.new();status_label.name="PrototypeStatus";status_label.add_theme_font_override("font",FONT)
	status_label.add_theme_font_size_override("font_size",13);status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;controls.add_child(status_label)
	var move_row:=HBoxContainer.new();move_row.alignment=BoxContainer.ALIGNMENT_CENTER
	move_row.add_theme_constant_override("separation",4);controls.add_child(move_row)
	for spec in [["MoveLeft","←",Vector2i.LEFT],["MoveUp","↑",Vector2i.UP],
			["MoveDown","↓",Vector2i.DOWN],["MoveRight","→",Vector2i.RIGHT]]:
		var move_button:=_button(str(spec[0]),str(spec[1]),Vector2(48,48))
		var direction:Vector2i=spec[2];move_button.pressed.connect(func():move_pawn(direction))
		move_row.add_child(move_button)
	var attack:=_button("Attack","공격",Vector2(64,48));attack.pressed.connect(attack_demo);move_row.add_child(attack)
	var reset:=_button("Reset","초기화",Vector2(64,48));reset.pressed.connect(reset_demo);move_row.add_child(reset)

func _button(node_name:String,text:String,minimum_size:Vector2)->Button:
	var button:=Button.new();button.name=node_name;button.text=text;button.custom_minimum_size=minimum_size
	button.add_theme_font_override("font",FONT);button.add_theme_font_size_override("font_size",13)
	return button

func set_view_mode(mode:String)->void:
	view_mode=VIEW_TOPDOWN if mode==VIEW_TOPDOWN else VIEW_PITCHED
	if view_mode==VIEW_TOPDOWN:
		camera.position=Vector3(0,14.5,4.45);camera.size=10.7
	else:
		camera.position=Vector3(0,10.0,9.25);camera.size=10.9
	camera.look_at_from_position(camera.position,Vector3(0,0.45,-0.25),Vector3.UP)
	if topdown_button!=null:topdown_button.set_pressed_no_signal(view_mode==VIEW_TOPDOWN)
	if pitched_button!=null:pitched_button.set_pressed_no_signal(view_mode==VIEW_PITCHED)
	if status_label!=null:
		status_label.text=("거의 수직인 2D 탑뷰 · 모델/장비는 그대로" if view_mode==VIEW_TOPDOWN \
			else "기울어진 2.5D 탑뷰 · 같은 모델을 카메라만 변경")

func toggle_gear()->void:
	gear_enabled=not gear_enabled;pawn.set_equipment_visible(gear_enabled)
	gear_button.text="갑옷 켜짐" if gear_enabled else "갑옷 꺼짐"
	status_label.text="갑옷·검·방패를 별도 메시로 %s"%("장착" if gear_enabled else "해제")

func toggle_painted_skin()->void:
	painted_skin_enabled=not painted_skin_enabled
	pawn.set_painted_skin_enabled(painted_skin_enabled)
	skin_button.set_pressed_no_signal(painted_skin_enabled)
	skin_button.text="2D 스킨" if painted_skin_enabled else "기본 3D"
	status_label.text=("손그림 텍스처·얼굴 데칼·외곽선 적용" if painted_skin_enabled \
		else "비교용 기본 단색 3D 재질")

func move_pawn(direction:Vector2i)->void:
	if _is_moving or direction==Vector2i.ZERO:return
	var target:=pawn_cell+direction
	if absi(target.x)>3 or absi(target.y)>3:
		status_label.text="테스트 구역의 끝입니다.";return
	pawn_cell=target;interaction_count+=1;_is_moving=true
	var world_direction:=Vector3(direction.x,0,direction.y)
	pawn.face_direction(world_direction);pawn.set_walking(true)
	if _move_tween!=null and _move_tween.is_valid():_move_tween.kill()
	_move_tween=create_tween();_move_tween.set_trans(Tween.TRANS_SINE);_move_tween.set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_property(pawn,"position",_cell_world(pawn_cell),0.28)
	_move_tween.finished.connect(func():_is_moving=false;pawn.set_walking(false);status_label.text="이동: 팔·다리 교차 보행 · 방향별 스프라이트 불필요")

func attack_demo()->void:
	if _is_moving:return
	interaction_count+=1;pawn.face_direction(enemy.position-pawn.position);pawn.play_attack()
	status_label.text="공격: 오른팔과 분리된 검을 함께 휘두름"
	var origin:=enemy.position
	var recoil:=create_tween();recoil.set_trans(Tween.TRANS_BACK);recoil.set_ease(Tween.EASE_OUT)
	recoil.tween_property(enemy,"position",origin+Vector3(0,0,0.18),0.10)
	recoil.tween_property(enemy,"position",origin,0.18)

func reset_demo()->void:
	if _move_tween!=null and _move_tween.is_valid():_move_tween.kill()
	_is_moving=false;pawn_cell=Vector2i(0,1);interaction_count=0;gear_enabled=true
	painted_skin_enabled=true
	pawn.position=_cell_world(pawn_cell);pawn.rotation=Vector3(0,PI,0);pawn.set_walking(false)
	pawn.set_painted_skin_enabled(true);pawn.set_equipment_visible(true);enemy.position=Vector3(2.25,0,-1.1)
	enemy.rotation.y=deg_to_rad(150)
	if gear_button!=null:gear_button.text="갑옷 켜짐"
	if skin_button!=null:
		skin_button.text="2D 스킨";skin_button.set_pressed_no_signal(true)
	set_view_mode(VIEW_PITCHED)

func _cell_world(cell:Vector2i)->Vector3:
	return Vector3(float(cell.x),0,float(cell.y))

func _process(delta:float)->void:
	_torch_time+=delta
	if torch_light!=null:
		var flicker:=sin(_torch_time*9.7)*0.22+sin(_torch_time*17.3)*0.11
		torch_light.light_energy=4.2+flicker
	if torch_flame!=null:
		torch_flame.scale.y=1.24+sin(_torch_time*13.0)*0.09

func _sync_viewport_size()->void:
	if lab_viewport==null:return
	var target:=Vector2i(maxi(1,int(size.x)),maxi(1,int(size.y)))
	if target.x<=1 or target.y<=1:target=Vector2i(450,800)
	lab_viewport.size=target

func demo_contract()->Dictionary:
	return {
		"view_mode":view_mode,
		"camera_projection":camera.projection if camera!=null else -1,
		"hero_instance_id":pawn.get_instance_id() if pawn!=null else 0,
		"hero":pawn.visual_contract() if pawn!=null else {},
		"gear_enabled":gear_enabled,
		"authoritative_state_accessed":authoritative_state_accessed,
	}
