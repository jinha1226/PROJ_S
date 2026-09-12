extends Control

const World=preload("res://game/rebuilt/world.gd")
const Board=preload("res://game/rebuilt/board.gd")
const GameFont=preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const SAVE:="user://rebuilt_dungeon_v4.json"
const GrowthPanel=preload("res://game/rebuilt/growth_panel.gd")
const DarkSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
const Gauge=preload("res://playtest/ascii_gauge.gd")
const ActionButton=preload("res://playtest/illustrated_action_button.gd")
var world=World.new()
var board
var status:Label
var history:Label
var auto_button:Button
var timer:Timer
var save_timer:Timer
var save_allowed:=true
var party_dialog:AcceptDialog
var party_info:Label
var gear_dialog
var targeting:String=""
var targeting_label:Label
var growth_button:Button
var hp_gauge
var mp_gauge
var xp_gauge
var menu_dialog:AcceptDialog
var shot_button:Button
var fire_button:Button
var potion_button:Button
var torch_button:Button
var descend_button:Button

func _ready()->void:
	var theme_data:=Theme.new();DarkSkin.configure_theme(theme_data);theme_data.default_font=GameFont;theme_data.default_font_size=14;theme=theme_data
	var background:=ColorRect.new();background.color=Color("10151f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,8)
	add_child(margin)
	var column:=VBoxContainer.new();margin.add_child(column)
	var header:=PanelContainer.new();DarkSkin.apply_panel(header);column.add_child(header)
	var header_column:=VBoxContainer.new();header.add_child(header_column)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;header_column.add_child(status)
	DarkSkin.apply_heading(status)
	var meters:=HBoxContainer.new();header_column.add_child(meters)
	hp_gauge=Gauge.new();hp_gauge.size_flags_horizontal=Control.SIZE_EXPAND_FILL;meters.add_child(hp_gauge)
	mp_gauge=Gauge.new();mp_gauge.size_flags_horizontal=Control.SIZE_EXPAND_FILL;meters.add_child(mp_gauge)
	xp_gauge=Gauge.new();header_column.add_child(xp_gauge)
	board=Board.new();board.custom_minimum_size=Vector2(0,180);board.size_flags_vertical=Control.SIZE_EXPAND_FILL
	board.cell_pressed.connect(on_cell);column.add_child(board)
	targeting_label=Label.new();targeting_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(targeting_label)
	history=Label.new();history.custom_minimum_size.y=54;history.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;history.max_lines_visible=3;history.add_theme_font_size_override("font_size",12);column.add_child(history)
	var actions:=GridContainer.new();actions.columns=4;column.add_child(actions)
	add_action(actions,"대기","ProductWaitGuard",func():command("WAIT"))
	auto_button=add_action(actions,"탐험","ProductAuto",toggle_auto)
	add_action(actions,"가방","ProductBag",func():show_character(1))
	add_action(actions,"동료","ProductTactics",show_party)
	potion_button=add_button(actions,"회복약",func():command("POTION"))
	shot_button=add_button(actions,"사격",func():begin_target("SHOOT"))
	fire_button=add_button(actions,"화염탄",func():begin_target("FIREBOLT"))
	torch_button=add_button(actions,"횃불",func():command("TORCH"))
	growth_button=add_button(actions,"성장",show_equipment)
	add_button(actions,"상태",show_status)
	descend_button=add_button(actions,"다음 층",func():command("DESCEND"))
	add_button(actions,"메뉴",show_menu)
	menu_dialog=AcceptDialog.new();menu_dialog.title="탐험 메뉴";add_child(menu_dialog)
	var menu_column:=VBoxContainer.new();menu_dialog.add_child(menu_column)
	add_button(menu_column,"저장",func():save_game();menu_dialog.hide())
	add_button(menu_column,"새 게임",func():menu_dialog.hide();confirm_new())
	party_dialog=AcceptDialog.new();party_dialog.title="동료";add_child(party_dialog)
	var party_column:=VBoxContainer.new();party_dialog.add_child(party_column)
	party_info=Label.new();party_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;party_column.add_child(party_info)
	var party_actions:=HBoxContainer.new();party_column.add_child(party_actions)
	add_button(party_actions,"추종/대기",func():command("ORDER");update_party())
	add_button(party_actions,"동료 회복",func():
		var allies:Array[Dictionary]=world.companions()
		if not allies.is_empty():command("POTION",allies[0].id);update_party())
	add_button(party_actions,"합류",func():command("RECRUIT");update_party())
	gear_dialog=GrowthPanel.new();add_child(gear_dialog)
	gear_dialog.changed.connect(func():refresh();save_timer.start())
	timer=Timer.new();timer.wait_time=0.16;timer.timeout.connect(continue_auto);add_child(timer)
	save_timer=Timer.new();save_timer.one_shot=true;save_timer.wait_time=0.6;save_timer.timeout.connect(save_game);add_child(save_timer)
	if FileAccess.file_exists(SAVE):
		var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if data is Dictionary and world.restore(data):world.message("저장한 탐험을 불러왔습니다.")
		else:save_allowed=false;world.message("저장 읽기 실패 · 새 게임 선택 전까지 저장을 잠급니다.")
	if not FileAccess.file_exists(SAVE) and FileAccess.file_exists("user://rebuilt_dungeon_v1.json"):
		world.message("새 성장 규칙으로 시작합니다. 이전 저장은 보존됩니다.")
	refresh(false)

func add_button(parent:Node,label:String,callback:Callable)->Button:
	var button:=Button.new();button.text=label;button.custom_minimum_size=Vector2(0,44)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.pressed.connect(callback);parent.add_child(button);return button

func add_action(parent:Node,label:String,id:String,callback:Callable)->Button:
	var button:=ActionButton.new();button.name=id;button.text=label
	DarkSkin.apply_action_button(button);button.custom_minimum_size=Vector2(0,54)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.pressed.connect(callback);parent.add_child(button);return button

func refresh(animate:bool=true)->void:
	board.sync(world,animate)
	var hero:Dictionary=world.hero()
	status.text="%d층 · Lv%d · 횃불 %s · 약 %d턴"%[world.floor_number,hero.growth.level,
		"켜짐" if world.torch_lit else "꺼짐",ceili(world.torch_fuel/100.0)]
	hp_gauge.configure_semantic("HP",hero.hp,hero.max_hp,4)
	mp_gauge.configure_semantic("MP",hero.mp,hero.max_mp,4)
	var level:int=hero.growth.level
	var threshold:int=World.Growth.threshold(level)
	var next:int=World.Growth.threshold(mini(level+1,World.Growth.DATA.max_level))
	xp_gauge.configure_semantic("XP",hero.growth.xp-threshold if next>threshold else 1,maxi(1,next-threshold),8)
	growth_button.text="성장 · %dP"%world.hero().growth.points
	targeting_label.text=("%s 대상 터치 · 다시 눌러 취소"%("사격" if targeting=="SHOOT" else "화염탄") if not targeting.is_empty() else "회복약 %d · 화살 %d · 금화 %d"%[world.potions,world.arrows,world.gold])
	auto_button.text="중지" if world.auto_explore or not world.route_steps.is_empty() else "탐험"
	auto_button.queue_redraw()
	potion_button.disabled=hero.hp<=0 or world.potions<=0
	shot_button.disabled=hero.hp<=0 or World.Equipment.effective_weapon(hero)!="BOW" or world.arrows<1
	fire_button.disabled=hero.hp<=0 or "FIREBOLT" not in hero.bound_abilities or hero.mp<int(World.Growth.DATA.actions.FIREBOLT.mp)
	shot_button.text="취소" if targeting=="SHOOT" else "사격"
	fire_button.text="취소" if targeting=="FIREBOLT" else "화염탄"
	torch_button.text="횃불 끄기" if world.torch_lit else "횃불 켜기"
	torch_button.disabled=hero.hp<=0 or world.torch_fuel<=0
	descend_button.disabled=hero.hp<=0 or hero.cell!=world.exit_cell
	history.text="\n".join(world.log.slice(maxi(0,world.log.size()-3)))

func on_cell(cell:int)->void:
	world.stop_auto();timer.stop()
	if not targeting.is_empty():
		if world.submit(targeting,cell):targeting="";refresh();save_timer.start()
		else:world.message("대상·사거리·장비·MP/화살을 확인하세요.");refresh(false)
		return
	if world.memory[cell]==0:return
	var delta:Vector2i=world.position(cell)-world.position(world.hero().cell)
	if delta==Vector2i.ZERO:command("WAIT");return
	if maxi(absi(delta.x),absi(delta.y))==1:command("MOVE",cell);return
	if world.plan_route(cell):
		continue_auto()
		if not world.route_steps.is_empty():timer.start()
	else:world.message("이동할 수 있는 경로가 없습니다.");refresh(false)

func command(kind:String,target:int=-1)->void:
	world.stop_auto();timer.stop();targeting=""
	if world.submit(kind,target):refresh();save_timer.start()
	else:world.message("지금은 할 수 없는 행동입니다.");refresh(false)

func toggle_auto()->void:
	targeting=""
	if world.auto_explore or not world.route_steps.is_empty():world.stop_auto();timer.stop();refresh(false);return
	world.auto_explore=true;continue_auto()
	if world.auto_explore:timer.start()

func continue_auto()->void:
	if not world.auto_step():timer.stop();refresh(false);return
	refresh();save_timer.start()
	if not world.auto_explore and world.route_steps.is_empty():timer.stop()

func show_status()->void:
	show_character(3)

func begin_target(kind:String)->void:
	world.stop_auto();timer.stop()
	if targeting==kind:targeting="";refresh(false);return
	if kind=="SHOOT" and (world.Equipment.effective_weapon(world.hero())!="BOW" or world.arrows<1):
		world.message("성장 → 장비에서 활을 장착하고 화살을 준비하세요.");refresh(false);return
	if kind=="FIREBOLT" and ("FIREBOLT" not in world.hero().bound_abilities or world.hero().mp<int(world.Growth.DATA.actions.FIREBOLT.mp)):
		world.message("화염탄 결속과 MP가 필요합니다.");refresh(false);return
	targeting=kind;refresh(false)

func show_equipment()->void:
	show_character(0)

func pause_play()->void:
	world.stop_auto();timer.stop();targeting="";refresh(false)

func show_character(tab:int)->void:
	pause_play();gear_dialog.open(world,tab)

func show_menu()->void:
	pause_play();menu_dialog.popup_centered(Vector2i(280,180))

func update_party()->void:
	var allies:Array[Dictionary]=world.companions()
	party_info.text="동료 없음 · 합류를 누르면 동료 1명이 합류합니다."
	if not allies.is_empty():
		var ally:Dictionary=allies[0]
		party_info.text="%s · %s\n성격: %s\n%s"%[
			"동료" if ally.hp>0 else "사망",
			"추종" if ally.order=="FOLLOW" else "대기",ally.personality,World.Body.description(ally)]

func show_party()->void:
	pause_play();update_party()
	party_dialog.popup_centered(Vector2i(mini(380,int(size.x)-24),390))

func confirm_new()->void:
	pause_play()
	var dialog:=ConfirmationDialog.new();dialog.dialog_text="현재 재구축 버전의 탐험을 끝내고 새로 시작할까요?"
	dialog.confirmed.connect(func():world=World.new(int(Time.get_unix_time_from_system()));save_allowed=true;refresh(false);save_game())
	dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free)
	add_child(dialog);dialog.popup_centered(Vector2i(mini(350,int(size.x)-24),160))

func save_game()->void:
	if not save_allowed:return
	# A separate versioned file; never reads or overwrites the legacy journal.
	var temp:=SAVE+".tmp"
	var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:world.message("저장 실패");return
	file.store_string(JSON.stringify(world.save_data()));file.close()
	if FileAccess.file_exists(SAVE):
		var backup_error:=DirAccess.copy_absolute(SAVE,SAVE+".bak")
		if backup_error!=OK:world.message("저장 백업 실패");return
	if DirAccess.rename_absolute(temp,SAVE)!=OK:world.message("저장 실패")

func _unhandled_key_input(event:InputEvent)->void:
	if not event.is_pressed() or event.is_echo() or get_viewport().gui_get_visible_popup_count()>0:return
	for pair in [["move_up",Vector2i.UP],["move_down",Vector2i.DOWN],["move_left",Vector2i.LEFT],["move_right",Vector2i.RIGHT]]:
		if event.is_action_pressed(pair[0]):
			var point:Vector2i=world.position(world.hero().cell)+pair[1]
			if world.in_bounds(point):command("MOVE",world.index(point))
			get_viewport().set_input_as_handled();return
	if event.is_action_pressed("wait"):command("WAIT");get_viewport().set_input_as_handled()
