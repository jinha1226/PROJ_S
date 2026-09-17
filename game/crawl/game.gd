extends Control
const World=preload("res://game/crawl/world.gd")
const Board=preload("res://game/crawl/board.gd")
const GameFont=preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const DarkSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
const SAVE="user://model_b_run_v1.json"
var world=World.new()
var board
var status:Label
var info:Label
var history:Label
var spell_bar:GridContainer
var auto_button:Button
var dialog:AcceptDialog
var content:VBoxContainer
var timer:Timer
var save_timer:Timer
var targeting=""
var target_kind="CAST"
var preview=-1
var save_allowed=true
var error_label=""

func _ready()->void:
	var theme_data=Theme.new();DarkSkin.configure_theme(theme_data);theme_data.default_font=GameFont;theme_data.default_font_size=14;theme=theme_data
	var bg=ColorRect.new();bg.color=Color("10151f");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bg)
	var margin=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,8)
	add_child(margin)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",5);margin.add_child(column)
	status=label(column,"");status.add_theme_font_size_override("font_size",16)
	board=Board.new();board.custom_minimum_size=Vector2(0,250);board.size_flags_vertical=Control.SIZE_EXPAND_FILL;board.cell_pressed.connect(on_cell);board.inspect_requested.connect(inspect_cell);column.add_child(board)
	info=label(column,"");info.custom_minimum_size.y=36;info.add_theme_font_size_override("font_size",12)
	history=label(column,"");history.custom_minimum_size.y=48;history.max_lines_visible=3;history.add_theme_font_size_override("font_size",12)
	spell_bar=GridContainer.new();spell_bar.columns=3;column.add_child(spell_bar)
	var actions=GridContainer.new();actions.columns=4;column.add_child(actions)
	button(actions,"대기",func():command("WAIT"))
	auto_button=button(actions,"탐색",explore)
	button(actions,"휴식",func():pause();world.start_rest();timer.start();refresh())
	button(actions,"사용/계단",func():command("INTERACT"))
	button(actions,"가방",bag)
	button(actions,"성장/주문",growth)
	button(actions,"신앙",faith)
	button(actions,"메뉴",menu)
	timer=Timer.new();timer.wait_time=0.16;timer.timeout.connect(auto_tick);add_child(timer)
	save_timer=Timer.new();save_timer.one_shot=true;save_timer.wait_time=0.5;save_timer.timeout.connect(save);add_child(save_timer)
	dialog=AcceptDialog.new();dialog.title="탐험";dialog.min_size=Vector2i(320,300);add_child(dialog)
	var scroll=ScrollContainer.new();scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);scroll.custom_minimum_size=Vector2(300,380);dialog.add_child(scroll)
	content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(content)
	if FileAccess.file_exists(SAVE):
		var data=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if not data is Dictionary or not world.restore(data):save_allowed=false;world.message("저장 읽기 실패. 기존 저장 보존. 메뉴에서 새 탐험을 선택하세요.")
	refresh(false)
	if not FileAccess.file_exists(SAVE):new_game_menu()

func label(parent:Node,text:String)->Label:
	var l=Label.new();l.text=text;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(l);return l
func button(parent:Node,text:String,callback:Callable)->Button:
	var b=Button.new();b.text=text;b.custom_minimum_size=Vector2(0,44);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.pressed.connect(callback);parent.add_child(b);return b
func refresh(animate:bool=true)->void:
	var h=world.hero();var s=world.stats(h)
	status.text="%s · Lv%d · 룬 %d/2%s\nHP %d/%d   MP %d/%d   AC %d  EV %d  SH %d%%"%[world.floor_name(),world.level,world.runes.size()," · 오브" if world.orb else "",h.hp,h.max_hp,h.mp,h.max_mp,s.ac,s.ev,s.sh]
	info.text="%s%s"%["상태: "+", ".join(h.statuses.keys())+" · " if not h.statuses.is_empty() else "",("대상: "+str(World.DATA.spells.get(targeting,{}).get("name",targeting))+" · 취소는 같은 버튼") if not targeting.is_empty() else "칸 터치: 이동/공격 · 길게: 상세 · 멀리: 안전 경로"]
	var feature:Dictionary=world.current().features.get(str(h.cell),{})
	if targeting.is_empty() and not feature.is_empty():
		var destination:String=str(feature.get("to",""))
		info.text="사용/계단: "+("지상 출구 (오브 필요)" if destination=="OUT" else str(World.DATA.floors.get(destination,{}).get("name",feature.get("god",{"cache":"보물","rune":"룬","orb":"오브","altar":"제단"}.get(feature.kind,feature.kind)))))
	if world.terminal():info.text="승리! 오브를 탈출시켰습니다." if world.won else "사망 · 메뉴에서 새로운 탐험"
	history.text="\n".join(world.log.slice(maxi(0,world.log.size()-3)))
	auto_button.text="중지" if world.auto_explore or world.resting or not world.route_steps.is_empty() else "탐색"
	for child in spell_bar.get_children():spell_bar.remove_child(child);child.queue_free()
	for id in world.prepared:
		var sp:Dictionary=World.DATA.spells[id]
		var b=button(spell_bar,"%s %dMP"%[sp.name,sp.mp],begin.bind("CAST",id))
		b.disabled=world.terminal() or world.god=="war" or h.mp<int(sp.mp)
	board.sync(world,animate)
func pause()->void:
	world.stop_auto();timer.stop();targeting="";preview=-1;board.target_cells.clear();board.cursor=-1
func command(kind:String,target:int=-1,value:String="")->void:
	pause();world.submit(kind,target,value);refresh();save_timer.start()
func begin(kind:String,id:String)->void:
	if targeting==id:pause();refresh(false);return
	pause();targeting=id;target_kind=kind
	if kind=="CAST" and World.DATA.spells[id].effect in ["ward","mend","blink","ignite"]:
		if id=="ignite":confirm_action("독 점화는 화면 안의 중독된 아군도 해칩니다. 시전할까요?",func():command(kind,-1,id))
		else:command(kind,-1,id)
	else:refresh(false)
func on_cell(cell:int)->void:
	if world.terminal() or world.memory[cell]==0:return
	world.stop_auto();timer.stop()
	if not targeting.is_empty():
		if target_kind=="CAST" and World.DATA.spells[targeting].effect in ["blast","cloud","cone"] and preview!=cell:
			preview=cell;board.target_cells=world.spell_cells(targeting,cell);board.cursor=cell;board.queue_redraw();info.text="범위 표시 · 같은 칸을 다시 누르면 시전 (아군 피해)";return
		command(target_kind,cell,targeting);return
	var occupant=world.occupancy[cell]
	if occupant>0 and world.visible[cell]==1 and world.actors[occupant].team=="enemy":
		if world.can_see(world.hero(),cell,int(world.stats(world.hero()).range)):command("ATTACK",cell)
		else:enemy_panel(occupant)
		return
	if cell==world.hero().cell:command("INTERACT" if world.current().features.has(str(cell)) else "WAIT");return
	if world.open_edge(world.hero().cell,cell):command("MOVE",cell);return
	if world.plan_route(cell):timer.start();auto_tick()
	else:refresh(false)
func explore()->void:
	if world.auto_explore or world.resting or not world.route_steps.is_empty():pause();refresh(false);return
	pause();world.auto_explore=true;timer.start();auto_tick()
func auto_tick()->void:
	if not world.auto_step():timer.stop()
	refresh();save_timer.start()
func panel(title:String)->void:
	pause();dialog.title=title
	for child in content.get_children():content.remove_child(child);child.queue_free()
	dialog.popup_centered(Vector2i(mini(420,int(size.x)-16),mini(610,int(size.y)-60)))
func inspect_cell(cell:int)->void:
	if world.visible[cell]==0:return
	var id=int(world.occupancy[cell])
	if id>0:enemy_panel(id)
func enemy_panel(id:int)->void:
	panel("적 살펴보기")
	var a=world.actors[id];var s=world.stats(a)
	label(content,"%s · HP %d/%d\n역할 %s · AC %d · EV %d · 행동 시간 %d\n저항 %s · 상태 %s"%[a.name,a.hp,a.max_hp,a.ai,s.ac,s.ev,a.speed,JSON.stringify(s.res),", ".join(a.statuses.keys())])
	button(content,"무기 공격 (사거리 %d)"%int(world.stats(world.hero()).range),func():dialog.hide();command("ATTACK",int(a.cell)))
	for spell_id in world.prepared:
		var chosen:String=spell_id
		button(content,World.DATA.spells[chosen].name+" 선택",func():dialog.hide();begin("CAST",chosen))
func bag()->void:
	panel("가방 · 교체도 시간을 소모합니다")
	for entry in [["heal","회복약"],["blink","순간이동 두루마리"],["haste","가속약"],["fog","안개 두루마리"],["wand","전기 마도구"]]:
		var id:String=entry[0]
		var b=button(content,"%s ×%d"%[entry[1],world.supplies[id]],func():
			dialog.hide()
			if id=="wand":begin("USE",id)
			else:command("USE",-1,id))
		b.disabled=world.supplies[id]<=0
	label(content,"장비 · 공격력뿐 아니라 지연/부담/저항을 비교하세요.")
	for i in range(world.inventory.size()):
		var idx=i;var it:Dictionary=world.inventory[i]
		if it.destroyed:continue
		var equipped=world.hero().gear[it.category]==i
		var detail=""
		if it.category=="weapon":
			var w:Dictionary=World.DATA.weapons[it.type];detail=" 피해%d 지연%d 사거리%d %s"%[w.damage,w.delay,w.range,{"cleave":"휩쓸기","reach":"찌르기","ranged":"양손","focus":"양손·마력","stab":"기습","pierce":"관통","balanced":"균형"}[w.trait]]
		elif it.category=="armour":
			var ar:Dictionary=World.DATA.armours[it.type];detail=" AC%d 회피-%d 부담%d"%[ar.ac,ar.ev_penalty,ar.enc]
		var b=button(content,("[장착] " if equipped else "")+world.item_name(it)+detail,func():dialog.hide();command("EQUIP",idx))
		b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;b.disabled=equipped
func growth()->void:
	panel("목표 훈련 · 주문 준비")
	label(content,"목표 최대 2개 · 전투 경험치 자동 분배\n현재 XP %d · 공격 지연 %d · 주문 부담 %d"%[world.xp,world.stats(world.hero()).delay,world.stats(world.hero()).enc])
	for key in World.DATA.skills:
		var axis:String=key
		button(content,"%s %s %d"%["●" if axis in world.focus else "○",World.DATA.skills[axis],world.skill_rank(axis)],func():world.submit("FOCUS",-1,axis);growth();refresh(false);save_timer.start())
	label(content,"배운 주문 · 준비 최대 6개 · 안전한 곳에서 변경")
	for key in world.spells:
		var id:String=key;var sp:Dictionary=World.DATA.spells[id]
		label(content,"%s · %s · Lv%d · %dMP · 실패%d%%\n%s"%[sp.name,World.DATA.skills[sp.school],sp.level,sp.mp,world.failure(id),sp.note])
		button(content,"준비 해제" if id in world.prepared else "준비",func():world.submit("PREPARE",-1,id);growth();refresh(false);save_timer.start())
func faith()->void:
	panel("신앙 · 계약은 플레이 규칙을 바꿉니다")
	label(content,"%s · 신앙 %d · 징벌 %d턴"%[World.DATA.gods[world.god].name if not world.god.is_empty() else "무신앙",world.piety,world.penance])
	if not world.god.is_empty():
		label(content,World.DATA.gods[world.god].note)
		button(content,"신앙 능력",func():dialog.hide();command("GOD"))
		button(content,"계약 파기",func():confirm_action("계약을 파기하면 12턴 징벌을 받습니다.",func():command("ABANDON")))
	if world.bound_weapon>=0:button(content,"결속 무기 파괴",func():confirm_action("현재 무기를 영구 파괴하고 결속을 해제할까요?",func():command("BREAK_BIND")))
	var f:Dictionary=world.current().features.get(str(world.hero().cell),{})
	for key in World.DATA.gods:
		var id:String=key;label(content,World.DATA.gods[id].name+"\n"+World.DATA.gods[id].note)
		var b=button(content,"계약",func():confirm_action("계약: "+World.DATA.gods[id].note,func():command("WORSHIP",-1,id)))
		b.disabled=f.get("kind")!="altar" or f.get("god")!=id or world.god==id
func menu()->void:
	panel("Model B")
	label(content,"두 룬 → 오브 → D1 출구\n> 계단  A 제단  R 룬  O 오브  $ 보물\n입력할 때만 시간 진행. 자동 탐색/휴식은 위험·발견에서 중지.\n신체 손상·성격 동료·흡수 이능은 후속 연결 대상입니다.")
	button(content,"저장",func():save();dialog.hide())
	button(content,"새 탐험",func():confirm_action("현재 Model B 탐험을 끝내고 새로 시작할까요?",new_game_menu))
func new_game_menu()->void:
	panel("새 탐험 · 종족 선택")
	for key in World.DATA.species:
		var id:String=key;var s:Dictionary=World.DATA.species[id]
		label(content,"%s · HP%d MP%d\n%s"%[s.name,s.hp,s.mp,s.note])
		button(content,s.name+" 시작",func():world=World.new(int(Time.get_unix_time_from_system()),id);save_allowed=true;dialog.hide();refresh(false);save())
func confirm_action(text:String,callback:Callable)->void:
	pause();dialog.hide()
	var confirm=ConfirmationDialog.new();confirm.dialog_text=text;add_child(confirm)
	confirm.confirmed.connect(func():callback.call();refresh(false);save_timer.start();confirm.queue_free())
	confirm.canceled.connect(confirm.queue_free);confirm.popup_centered(Vector2i(mini(390,int(size.x)-20),160))
func save()->void:
	if not save_allowed:return
	var data=world.save_data();var error=World.validation_error(data)
	if not error.is_empty():world.message("저장 검증 실패: "+error);refresh(false);return
	var file=FileAccess.open(SAVE+".tmp",FileAccess.WRITE)
	if file==null:world.message("저장 파일을 열 수 없습니다.");return
	file.store_string(JSON.stringify(data));file.close()
	if FileAccess.file_exists(SAVE) and DirAccess.copy_absolute(SAVE,SAVE+".bak")!=OK:world.message("저장 백업 실패");return
	if DirAccess.rename_absolute(SAVE+".tmp",SAVE)!=OK:world.message("저장 실패")
func _notification(what:int)->void:
	if what==NOTIFICATION_APPLICATION_PAUSED or what==NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(save_timer):pause();save()
func _unhandled_key_input(event:InputEvent)->void:
	if not event.is_pressed() or event.is_echo() or get_viewport().gui_get_visible_popup_count()>0:return
	for pair in [["move_up",Vector2i.UP],["move_down",Vector2i.DOWN],["move_left",Vector2i.LEFT],["move_right",Vector2i.RIGHT]]:
		if event.is_action_pressed(pair[0]):
			var p=world.position(world.hero().cell)+pair[1]
			if world.in_bounds(p):command("MOVE",world.index(p))
			get_viewport().set_input_as_handled();return
	if event.is_action_pressed("wait"):command("WAIT");get_viewport().set_input_as_handled()
