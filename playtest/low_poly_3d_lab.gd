class_name LowPoly3DLab
extends Control

signal close_requested

const PawnScript=preload("res://playtest/low_poly_pawn_3d.gd")
const FONT:FontFile=preload("res://assets/fonts/LivingWorldMonoKRBold.ttf")
const FLOOR_TEXTURE:Texture2D=preload(
	"res://assets/generated/dark_fantasy_topdown_v2/runtime/floor_flagstone_tileable_512.png")
const WALL_CAP_TEXTURE:Texture2D=preload(
	"res://assets/generated/dark_fantasy_topdown_v2/runtime/wall_cap_tileable_512.png")
const CRATE_TEXTURE:Texture2D=preload(
	"res://assets/generated/dark_fantasy_topdown_v2/runtime/crate_top_256.png")
const BLOOD_TEXTURE:Texture2D=preload(
	"res://assets/generated/dark_fantasy_topdown_v2/runtime/blood_pool_256.png")
const TORCH_TEXTURE:Texture2D=preload(
	"res://assets/generated/dark_fantasy_topdown_v2/runtime/wall_torch_front_256.png")
const VIEW_TOPDOWN := "TOPDOWN"

var viewport_container:SubViewportContainer
var lab_viewport:SubViewport
var world_root:Node3D
var camera:Camera3D
var pawn:LowPolyPawn3D
var enemy:LowPolyPawn3D
var torch_light:OmniLight3D
var torch_flame:Sprite3D
var status_label:Label
var topdown_button:Button
var gear_button:Button
var view_mode:=VIEW_TOPDOWN
var pawn_cell:=Vector2i(0,1)
var gear_enabled:=true
var interaction_count:=0
var authoritative_state_accessed:=false
var _torch_time:=0.0
var _move_tween:Tween
var _is_moving:=false

func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	_build_viewport();_build_world();_build_overlay();reset_demo()
	resized.connect(_sync_viewport_size);_sync_viewport_size();set_process(true)

func _build_viewport()->void:
	viewport_container=SubViewportContainer.new();viewport_container.name="Topdown2DViewportContainer"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch=false;viewport_container.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(viewport_container)
	lab_viewport=SubViewport.new();lab_viewport.name="Topdown2DSubViewport"
	lab_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	lab_viewport.msaa_3d=Viewport.MSAA_4X;viewport_container.add_child(lab_viewport)
	world_root=Node3D.new();world_root.name="Topdown2DWorld";lab_viewport.add_child(world_root)
	var environment:=WorldEnvironment.new();environment.name="FlatPaintedEnvironment"
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("#08090b")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE
	env.ambient_light_energy=1.0;env.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
	environment.environment=env;world_root.add_child(environment)
	camera=Camera3D.new();camera.name="TrueTopdownOrthographicCamera"
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=10.7;camera.current=true
	camera.position=Vector3(0,14.0,0);camera.rotation_degrees=Vector3(-90,0,0)
	world_root.add_child(camera)

func _build_world()->void:
	_build_floor();_build_walls_and_props()
	pawn=PawnScript.new();pawn.name="TopdownCutoutHero";pawn.species="human";world_root.add_child(pawn)
	if pawn.visual_root==null:pawn._ready()
	enemy=PawnScript.new();enemy.name="TopdownCutoutGoblin";enemy.species="goblin"
	enemy.equipment_visible=false;enemy.scale=Vector3.ONE*0.84;world_root.add_child(enemy)
	if enemy.visual_root==null:enemy._ready()
	enemy.position=Vector3(2.25,0,-1.1);enemy.face_direction(Vector3(-1,0,1))
	_build_blood_pool(Vector3(2.95,0.018,-2.25))

func _build_floor()->void:
	var floor_root:=Node3D.new();floor_root.name="Painted2DFloor";world_root.add_child(floor_root)
	for z in range(-5,5):
		for x in range(-5,5):
			var tile:=_flat_sprite("Floor_%02d_%02d"%[x+5,z+5],FLOOR_TEXTURE,
				floor_root,Vector3(x,0,z),1.0/512.0,0)
			var variation:=0.90+float(posmod(x*13+z*7,4))*0.025
			tile.modulate=Color(variation,variation,variation,1.0)
			tile.flip_h=posmod(x*17+z*11,2)==0;tile.flip_v=posmod(x*5+z*19,2)==0

func _build_walls_and_props()->void:
	var walls:=Node3D.new();walls.name="Painted2DBoundary";world_root.add_child(walls)
	for x in range(-5,6):
		_flat_sprite("NorthWallCap",WALL_CAP_TEXTURE,walls,Vector3(x,0.025,-5.02),1.0/512.0,1)
	for z in range(-4,5):
		var cap:=_flat_sprite("WestWallCap",WALL_CAP_TEXTURE,walls,
			Vector3(-5.02,0.025,z),1.0/512.0,1)
		cap.rotation_degrees.y=90
	_build_crate(walls,Vector3(-2.6,0,-2.8))
	_build_crate(walls,Vector3(-2.05,0,-3.0),0.78)
	_build_torch(walls,Vector3(2.7,0.055,-4.68))

func _build_crate(parent:Node3D,position:Vector3,scale_factor:float=1.0)->void:
	var crate:=_flat_sprite("Crate2D",CRATE_TEXTURE,parent,
		position+Vector3(0,0.040,0),0.0031*scale_factor,4)
	crate.rotation_degrees.y=float(posmod(int(position.x*100.0),7)-3)*2.0

func _build_torch(parent:Node3D,position:Vector3)->void:
	torch_flame=_flat_sprite("WallTorch2D",TORCH_TEXTURE,parent,position,0.0034,6)
	torch_light=OmniLight3D.new();torch_light.name="TorchSpatialCue"
	torch_light.position=position+Vector3(0,0.35,0);torch_light.light_color=Color("#ff9b54")
	torch_light.light_energy=0.0;torch_light.omni_range=3.5;world_root.add_child(torch_light)

func _build_blood_pool(position:Vector3)->void:
	var pool:=_flat_sprite("BloodPool2D",BLOOD_TEXTURE,world_root,position,0.0038,2)
	pool.scale=Vector3(1.15,1.0,0.66);pool.rotation_degrees.y=24

func _flat_sprite(node_name:String,texture:Texture2D,parent:Node3D,position:Vector3,
		pixel_size:float,priority:int)->Sprite3D:
	var sprite:=Sprite3D.new();sprite.name=node_name;sprite.texture=texture;sprite.position=position
	sprite.rotation_degrees.x=-90;sprite.pixel_size=pixel_size;sprite.shaded=false
	sprite.double_sided=true;sprite.render_priority=priority
	sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(sprite);return sprite

func _build_overlay()->void:
	var top_scrim:=ColorRect.new();top_scrim.name="TopScrim";top_scrim.color=Color("#080a0ddd")
	top_scrim.set_anchors_preset(Control.PRESET_TOP_WIDE);top_scrim.custom_minimum_size.y=110
	top_scrim.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(top_scrim)
	var header:=VBoxContainer.new();header.name="PrototypeHeader";header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left=10;header.offset_right=-10;header.offset_top=8;header.offset_bottom=104
	header.add_theme_constant_override("separation",4);add_child(header)
	var title_row:=HBoxContainer.new();title_row.add_theme_constant_override("separation",6);header.add_child(title_row)
	var title:=Label.new();title.name="LabTitle";title.text="2D 탑뷰 리그 테스트\n화면은 2D · 관절과 좌표만 3D"
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.add_theme_font_override("font",FONT)
	title.add_theme_font_size_override("font_size",16);title_row.add_child(title)
	var close:=_button("BackToGame","닫기",Vector2(58,48));close.pressed.connect(func():close_requested.emit())
	title_row.add_child(close)
	var view_row:=HBoxContainer.new();view_row.add_theme_constant_override("separation",6);header.add_child(view_row)
	topdown_button=_button("TopdownCamera","2D 탑뷰 고정",Vector2(112,44));topdown_button.toggle_mode=true
	topdown_button.set_pressed_no_signal(true);topdown_button.disabled=true;view_row.add_child(topdown_button)
	gear_button=_button("GearToggle","장비 켜짐",Vector2(92,44));gear_button.pressed.connect(toggle_gear)
	view_row.add_child(gear_button)
	var rig_note:=Label.new();rig_note.text="메시 0 · 분절 파츠 리그";rig_note.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rig_note.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;rig_note.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	rig_note.add_theme_font_override("font",FONT);rig_note.add_theme_font_size_override("font_size",12)
	view_row.add_child(rig_note)

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
	button.add_theme_font_override("font",FONT);button.add_theme_font_size_override("font_size",13);return button

func set_view_mode(_mode:String)->void:
	view_mode=VIEW_TOPDOWN
	if camera!=null:
		camera.position=Vector3(0,14.0,0);camera.rotation_degrees=Vector3(-90,0,0);camera.size=10.7
	if topdown_button!=null:topdown_button.set_pressed_no_signal(true)
	if status_label!=null:status_label.text="수직 2D 탑뷰 · 캐릭터는 가독성 높은 탑다운 3/4 파츠"

func toggle_gear()->void:
	gear_enabled=not gear_enabled;pawn.set_equipment_visible(gear_enabled)
	gear_button.text="장비 켜짐" if gear_enabled else "장비 꺼짐"
	status_label.text="갑옷·검·방패 2D 파츠를 %s"%("장착" if gear_enabled else "해제")

func move_pawn(direction:Vector2i)->void:
	if _is_moving or direction==Vector2i.ZERO:return
	var target:=pawn_cell+direction
	if absi(target.x)>3 or absi(target.y)>3:status_label.text="테스트 구역의 끝입니다.";return
	pawn_cell=target;interaction_count+=1;_is_moving=true
	var world_direction:=Vector3(direction.x,0,direction.y)
	pawn.face_direction(world_direction);pawn.set_walking(true)
	if _move_tween!=null and _move_tween.is_valid():_move_tween.kill()
	_move_tween=create_tween();_move_tween.set_trans(Tween.TRANS_SINE);_move_tween.set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_property(pawn,"position",_cell_world(pawn_cell),0.28)
	_move_tween.finished.connect(func():
		_is_moving=false;pawn.set_walking(false)
		status_label.text="이동: 3D 관절 좌표가 2D 팔·다리 파츠를 구동")

func attack_demo()->void:
	if _is_moving:return
	interaction_count+=1;pawn.face_direction(enemy.position-pawn.position);pawn.play_attack()
	status_label.text="공격: 상완·하완·검 파츠가 관절 체인으로 회전"
	var origin:=enemy.position
	var recoil:=create_tween();recoil.set_trans(Tween.TRANS_BACK);recoil.set_ease(Tween.EASE_OUT)
	recoil.tween_property(enemy,"position",origin+Vector3(0,0,0.18),0.10)
	recoil.tween_property(enemy,"position",origin,0.18)

func reset_demo()->void:
	if _move_tween!=null and _move_tween.is_valid():_move_tween.kill()
	_is_moving=false;pawn_cell=Vector2i(0,1);interaction_count=0;gear_enabled=true
	pawn.position=_cell_world(pawn_cell);pawn.face_direction(Vector3(0,0,1));pawn.set_walking(false)
	pawn.set_equipment_visible(true);enemy.position=Vector3(2.25,0,-1.1)
	enemy.face_direction(Vector3(-1,0,1))
	if gear_button!=null:gear_button.text="장비 켜짐"
	set_view_mode(VIEW_TOPDOWN)

func _cell_world(cell:Vector2i)->Vector3:
	return Vector3(float(cell.x),0,float(cell.y))

func _process(delta:float)->void:
	_torch_time+=delta
	if torch_flame!=null:
		var pulse:=0.92+sin(_torch_time*11.0)*0.08
		torch_flame.modulate=Color(1.0,pulse,0.82,1.0)

func _sync_viewport_size()->void:
	if lab_viewport==null:return
	var target:=Vector2i(maxi(1,int(size.x)),maxi(1,int(size.y)))
	if target.x<=1 or target.y<=1:target=Vector2i(450,800)
	lab_viewport.size=target

func demo_contract()->Dictionary:
	return {
		"view_mode":view_mode,
		"camera_projection":camera.projection if camera!=null else -1,
		"camera_rotation":camera.rotation_degrees if camera!=null else Vector3.ZERO,
		"hero_instance_id":pawn.get_instance_id() if pawn!=null else 0,
		"hero":pawn.visual_contract() if pawn!=null else {},
		"gear_enabled":gear_enabled,
		"authoritative_state_accessed":authoritative_state_accessed,
	}
