extends Control

const World=preload("res://game/rebuilt/world.gd")
const Board=preload("res://game/rebuilt/board.gd")
const GameFont=preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const SAVE:="user://rebuilt_dungeon_v1.json"
var world=World.new()
var board
var status:Label
var history:Label
var details:AcceptDialog
var auto_button:Button
var timer:Timer
var save_timer:Timer
var save_allowed:=true

func _ready()->void:
	var theme_data:=Theme.new();theme_data.default_font=GameFont;theme_data.default_font_size=15;theme=theme_data
	var background:=ColorRect.new();background.color=Color("10151f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,8)
	add_child(margin)
	var column:=VBoxContainer.new();margin.add_child(column)
	status=Label.new();column.add_child(status)
	board=Board.new();board.custom_minimum_size=Vector2(0,430);board.size_flags_vertical=Control.SIZE_EXPAND_FILL
	board.cell_pressed.connect(on_cell);column.add_child(board)
	var actions:=GridContainer.new();actions.columns=4;column.add_child(actions)
	add_button(actions,"대기",func():command("WAIT"))
	add_button(actions,"회복약",func():command("POTION"))
	add_button(actions,"횃불",func():command("TORCH"))
	add_button(actions,"다음 층",func():command("DESCEND"))
	auto_button=add_button(actions,"자동탐험",toggle_auto)
	add_button(actions,"상태",show_status)
	add_button(actions,"저장",save_game)
	add_button(actions,"새 게임",confirm_new)
	history=Label.new();history.custom_minimum_size.y=70;column.add_child(history)
	details=AcceptDialog.new();add_child(details)
	timer=Timer.new();timer.wait_time=0.16;timer.timeout.connect(continue_auto);add_child(timer)
	save_timer=Timer.new();save_timer.one_shot=true;save_timer.wait_time=0.6;save_timer.timeout.connect(save_game);add_child(save_timer)
	if FileAccess.file_exists(SAVE):
		var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if data is Dictionary and world.restore(data):world.message("저장한 탐험을 불러왔습니다.")
		else:save_allowed=false;world.message("저장 읽기 실패 · 새 게임 선택 전까지 저장을 잠급니다.")
	refresh(false)

func add_button(parent:Node,label:String,callback:Callable)->Button:
	var button:=Button.new();button.text=label;button.custom_minimum_size=Vector2(100,42)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.pressed.connect(callback);parent.add_child(button);return button

func refresh(animate:bool=true)->void:
	board.sync(world,animate)
	status.text="%d층 · HP %d/%d · 금화 %d\n횃불 %s %d · 회복약 %d · 시간 %d"%[world.floor_number,world.hero().hp,world.hero().max_hp,world.gold,
		"켜짐" if world.torch_lit else "꺼짐",world.torch_fuel,world.potions,world.time]
	auto_button.text="중지" if world.auto_explore else "자동탐험"
	history.text="\n".join(world.log.slice(maxi(0,world.log.size()-3)))

func on_cell(cell:int)->void:
	world.stop_auto();timer.stop()
	if world.memory[cell]==0:return
	var delta:Vector2i=world.position(cell)-world.position(world.hero().cell)
	if delta==Vector2i.ZERO:command("WAIT");return
	if maxi(absi(delta.x),absi(delta.y))==1:command("MOVE",cell);return
	if world.plan_route(cell):
		continue_auto()
		if not world.route_steps.is_empty():timer.start()
	else:world.message("이동할 수 있는 경로가 없습니다.");refresh(false)

func command(kind:String,target:int=-1)->void:
	world.stop_auto();timer.stop()
	if world.submit(kind,target):refresh();save_timer.start()
	else:world.message("지금은 할 수 없는 행동입니다.");refresh(false)

func toggle_auto()->void:
	if world.auto_explore or not world.route_steps.is_empty():world.stop_auto();timer.stop();refresh(false);return
	world.auto_explore=true;continue_auto()
	if world.auto_explore:timer.start()

func continue_auto()->void:
	if not world.auto_step():timer.stop();refresh(false);return
	refresh();save_timer.start()
	if not world.auto_explore and world.route_steps.is_empty():timer.stop()

func show_status()->void:
	world.stop_auto();timer.stop()
	var a:Dictionary=world.hero()
	details.title="캐릭터 상태"
	details.dialog_text="성격: %s\nHP %d/%d · 스트레스 %d\n피부 질김 %d · 뼈 강도 %d · 혈액 %d%%\n무기: %s · 방어력 %d\n\n처리 %.2fms · 경로 %.2fms · 그리기 %.2fms"%[
		a.personality,a.hp,a.max_hp,a.stress,a.skin,a.bone,a.blood,world.weapon,world.armor,
		world.last_action_usec/1000.0,world.last_path_usec/1000.0,board.last_draw_usec/1000.0]
	details.popup_centered(Vector2i(380,280))

func confirm_new()->void:
	world.stop_auto();timer.stop()
	var dialog:=ConfirmationDialog.new();dialog.dialog_text="현재 재구축 버전의 탐험을 끝내고 새로 시작할까요?"
	dialog.confirmed.connect(func():world=World.new(int(Time.get_unix_time_from_system()));save_allowed=true;refresh(false);save_game())
	dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free)
	add_child(dialog);dialog.popup_centered(Vector2i(380,160))

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
	if not event.is_pressed() or event.is_echo() or details.visible:return
	for pair in [["move_up",Vector2i.UP],["move_down",Vector2i.DOWN],["move_left",Vector2i.LEFT],["move_right",Vector2i.RIGHT]]:
		if event.is_action_pressed(pair[0]):
			var point:Vector2i=world.position(world.hero().cell)+pair[1]
			if world.in_bounds(point):command("MOVE",world.index(point))
			get_viewport().set_input_as_handled();return
	if event.is_action_pressed("wait"):command("WAIT");get_viewport().set_input_as_handled()
