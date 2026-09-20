extends Control
const Session = preload("res://expedition/session.gd")
const Board = preload("res://expedition/board.gd")
const MapView = preload("res://expedition/map_view.gd")
const Art = preload("res://expedition/mobile_art.gd")
const FONT = preload("res://assets/fonts/NanumSquareR.ttf")
const SKILLS = [["PUSH","GUARD"],["ATTACK","GUARD"],["WATER","ELECTRIC"]]
const SKILL_NAMES = [["밀쳐내기","방어"],["강타","방어"],["물","방전"]]
var session = Session.new(randi(),true,true)
var mode := ""
var reservation_actor := -1
var pending_item := -1
var pending_attack: Dictionary = {}
var attack_button: Button
var show_attack_range := false
var action_effects: Array = []
var root_layout: VBoxContainer
var board
var end_turn_button: Button
var wait_button: Button
var advance_attack_button: Button
var character_tab := "상태"
var minimap
var map_view
var map_popup: PopupPanel
var details_popup: PopupPanel
var modal_content: VBoxContainer
var notice := ""
var item_buttons: Array = []
var skill_buttons: Array = []
var portrait_buttons: Array = []
var tactics_actor := 0
var tactics_expanded := -1

func _ready() -> void:
	var skin := Theme.new(); skin.default_font = FONT; skin.default_font_size = 12
	for state in ["normal","hover","pressed","focus","disabled"]:
		var box := StyleBoxFlat.new(); box.bg_color = Color("151c24") if state != "pressed" else Color("433c2c")
		box.border_color = Color("bba16b") if state in ["hover","pressed","focus"] else Color("50535a")
		box.set_border_width_all(1); box.set_corner_radius_all(4)
		box.content_margin_left = 3; box.content_margin_right = 3; skin.set_stylebox(state,"Button",box)
	theme = skin
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,0 if side in ["left","right"] else 8)
	add_child(margin)
	root_layout = VBoxContainer.new(); root_layout.add_theme_constant_override("separation",5); margin.add_child(root_layout)
	map_popup = PopupPanel.new(); add_child(map_popup)
	var map_box := VBoxContainer.new(); map_box.custom_minimum_size = Vector2(320,400); map_popup.add_child(map_box)
	map_view = MapView.new(); map_view.session = session; map_view.ui_font = FONT; map_view.minimum_side = 300
	map_view.room_pressed.connect(on_room); map_box.add_child(map_view)
	button(map_box,"닫기",func(): map_popup.hide())
	details_popup = PopupPanel.new(); add_child(details_popup)
	modal_content = VBoxContainer.new(); modal_content.custom_minimum_size = Vector2(320,340); details_popup.add_child(modal_content)
	refresh()

func clear(node: Node) -> void:
	for child in node.get_children(): node.remove_child(child); child.queue_free()

func label(parent: Node, text: String, font_size: int = 12) -> Label:
	var node := Label.new(); node.text = text; node.add_theme_font_size_override("font_size",font_size)
	node.mouse_filter = MOUSE_FILTER_IGNORE; parent.add_child(node); return node

func button(parent: Node, text: String, callback: Callable, enabled: bool = true) -> Button:
	var node := Button.new(); node.text = text; node.disabled = not enabled
	node.custom_minimum_size = Vector2(0,44); node.size_flags_horizontal = SIZE_EXPAND_FILL
	node.pressed.connect(callback); parent.add_child(node); return node

func icon_button(parent: Node, texture: Texture2D, callback: Callable, hint: String, count: String = "") -> Button:
	var node := button(parent,"",callback)
	node.tooltip_text = hint; node.custom_minimum_size = Vector2(0,48)
	var picture := TextureRect.new(); picture.texture = texture; picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; picture.mouse_filter = MOUSE_FILTER_IGNORE
	node.add_child(picture); picture.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	picture.offset_left = 4; picture.offset_right = -4; picture.offset_top = 4; picture.offset_bottom = -4
	if count != "":
		var number := label(node,count,12); number.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
		number.offset_left = -18; number.offset_top = -18; number.offset_right = -2; number.offset_bottom = -2
		number.add_theme_color_override("font_shadow_color",Color.BLACK); number.add_theme_constant_override("shadow_offset_x",1); number.add_theme_constant_override("shadow_offset_y",1)
	return node

func gauge(parent: Node, value: int, maximum: int, color: Color) -> void:
	var bar := ProgressBar.new(); bar.max_value = maximum; bar.value = value; bar.show_percentage = false
	bar.custom_minimum_size.y = 4; bar.mouse_filter = MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new(); fill.bg_color = color; fill.set_corner_radius_all(2)
	var background := StyleBoxFlat.new(); background.bg_color = Color("0b1016")
	bar.add_theme_stylebox_override("fill",fill); bar.add_theme_stylebox_override("background",background); parent.add_child(bar)

func refresh() -> void:
	clear(root_layout); item_buttons.clear(); skill_buttons.clear(); portrait_buttons.clear()
	map_view.session = session; map_view.queue_redraw()
	var header := HBoxContainer.new(); header.add_theme_constant_override("separation",6); root_layout.add_child(header)
	minimap = MapView.new(); minimap.compact = true; minimap.minimum_side = 76
	minimap.session = session; minimap.ui_font = FONT; minimap.expand_requested.connect(show_map)
	minimap.size_flags_horizontal = SIZE_SHRINK_BEGIN; header.add_child(minimap)
	var location := VBoxContainer.new(); location.size_flags_horizontal = SIZE_EXPAND_FILL; header.add_child(location)
	button(location,"인물 · 상태",func(): show_character(session.selected,"상태")).custom_minimum_size.y = 28
	label(location,session.rooms[session.room].name if session.phase in ["EXPLORE","BATTLE"] else "원정 준비",12)
	if session.phase == "BATTLE": label(location,"행동 %d" % session.round_number if session.boss_trial else "%d턴 · AP %d" % [session.round_number,session.party[session.selected].ap],11)
	var resource := VBoxContainer.new(); resource.custom_minimum_size.x = 124; header.add_child(resource)
	button(resource,"식량 %d   횃불 %d" % [session.food,session.torches],show_supplies).custom_minimum_size.y = 28
	label(resource,"배고픔 %d%%" % session.hunger,10); gauge(resource,session.hunger,100,Color("d9904d"))
	label(resource,"불빛 %d%%" % session.light,10); gauge(resource,session.light,100,Color("e6bd62"))
	board = Board.new(); board.session = session; board.ui_font = FONT; board.cell_pressed.connect(on_cell)
	board.action_footer = not session.boss_trial or not pending_attack.is_empty()
	root_layout.add_child(board)
	board.show_attack_range = show_attack_range
	board.input_actor = reservation_actor
	board.effects = action_effects; action_effects = []
	board.target_cell = pending_attack.get("cell",Vector2i(-1,-1))
	board.companion_previews = session.companion_previews()
	if session.boss_trial and session.phase == "BATTLE":
		var boss_info := label(board,session.rooms[session.room].name+" · HP %d/%d\n" % [session.enemies[0].hp,session.enemies[0].max_hp]+Session.BossTrial.HINTS[session.rooms[session.room].pattern],11)
		boss_info.position = Vector2(8,4)
		var fuse: int = session.enemies[0].get("fuse",0)
		if fuse > 0 and not session.intents.is_empty(): boss_info.text += "\n폭발까지 %d행동" % fuse
		elif session.enemies[0].get("recovery",0) > 0: boss_info.text += "\n탈진 · %d행동 동안 반격 없음" % session.enemies[0].recovery
	attack_button = null
	end_turn_button = null
	if session.phase == "BATTLE":
		if not session.boss_trial:
			var advance := button(board,"턴 종료",func(): run_action(session.end_round)); end_turn_button = advance
			advance.custom_minimum_size = Vector2(96,48)
			advance.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
			advance.offset_left = -104; advance.offset_top = -56
			advance.offset_right = -8; advance.offset_bottom = -8
		if not pending_attack.is_empty():
			attack_button = button(board,"공격 · %d%% / 피해 %d" % [pending_attack.chance,pending_attack.damage],confirm_attack)
			attack_button.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
			attack_button.offset_left = 8; attack_button.offset_top = -56
			attack_button.offset_right = 230; attack_button.offset_bottom = -8
			attack_button.custom_minimum_size.y = 48
	if session.phase in ["TOWN","DEFEAT"]: button(root_layout,"출정" if session.phase == "TOWN" and not session.alive().is_empty() else "새 원정대",depart)
	var feedback := HBoxContainer.new(); root_layout.add_child(feedback)
	var hint := label(feedback,notice if not notice.is_empty() else "8방향 이동 / 공격 / 대기 → 적 행동" if session.boss_trial else "녹색: 이동(1 AP) · 자신: 대기",10)
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	hint.clip_text = true; hint.custom_minimum_size.y = 16
	var party_row := HBoxContainer.new(); party_row.add_theme_constant_override("separation",5); root_layout.add_child(party_row)
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var column: BoxContainer = HBoxContainer.new() if session.party.size() == 1 else VBoxContainer.new()
		column.size_flags_horizontal = SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",3); party_row.add_child(column)
		var skills := HBoxContainer.new(); skills.add_theme_constant_override("separation",3); column.add_child(skills)
		if session.party.size() == 1: skills.custom_minimum_size.x = 128
		for slot in range(2):
			var skill := icon_button(skills,Art.skill(slot if session.companions else i*2+slot),func(): choose_skill(i,slot),SKILL_NAMES[0 if session.companions else i][slot])
			skill.disabled = session.phase != "BATTLE" or actor.hp <= 0 or actor.ap <= 0; skill_buttons.append(skill)
		var portrait_box := VBoxContainer.new(); portrait_box.size_flags_horizontal = SIZE_EXPAND_FILL; portrait_box.add_theme_constant_override("separation",2); column.add_child(portrait_box)
		var portrait := button(portrait_box,"",func(): select_actor(i)); portrait.custom_minimum_size.y = 48; portrait_buttons.append(portrait)
		var face := TextureRect.new(); face.texture = Art.portrait(i); face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; face.mouse_filter = MOUSE_FILTER_IGNORE
		portrait.add_child(face); face.set_anchors_and_offsets_preset(PRESET_FULL_RECT); face.offset_bottom = -18; face.offset_top = 2; face.offset_left = 2; face.offset_right = -2
		var name_label := label(portrait,"%s  %d/%d" % [actor.name,actor.hp,actor.max_hp],11); name_label.position = Vector2(4,30)
		if i == session.selected:
			var gold := portrait.get_theme_stylebox("normal").duplicate(); gold.border_color = Color("e9c575"); gold.set_border_width_all(2); portrait.add_theme_stylebox_override("normal",gold)
		if actor.hp <= 0: portrait.modulate = Color("636369")
		gauge(portrait_box,actor.hp,actor.max_hp,Color("8ac77c")); gauge(portrait_box,actor.stress,200,Color("af80d0"))
		if session.party.size() > 1: column.move_child(skills,column.get_child_count()-1)
	var shared := HBoxContainer.new(); shared.add_theme_constant_override("separation",4); root_layout.add_child(shared)
	for slot in range(6):
		var item := icon_button(shared,Art.item(slot),func(): choose_item(slot),Session.SUPPLY_NAMES[slot],str(session.supplies[slot]))
		item.disabled = session.phase not in ["BATTLE","EXPLORE"] or session.supplies[slot] == 0; item_buttons.append(item)
	var nav := HBoxContainer.new(); nav.add_theme_constant_override("separation",4); root_layout.add_child(nav)
	advance_attack_button = button(nav,"공격",func(): run_action(session.auto_attack),session.phase == "BATTLE")
	wait_button = button(nav,"한 턴\n대기",func(): run_action(func(): return session.act("WAIT",session.party[session.selected].pos)),session.phase == "BATTLE")
	if reservation_actor >= 0:
		button(nav,"예약 취소",func(): session.cancel_reservation(reservation_actor); reservation_actor = -1; mode = ""; notice = "예약 취소 · 자동 행동"; refresh())
	else: button(nav,"탐험",show_map,session.phase in ["BATTLE","EXPLORE"])
	button(nav,"전술",show_orders)
	button(nav,"가방",show_supplies)
	for node in nav.get_children(): node.custom_minimum_size.y = 49

func depart() -> void:
	if session.phase == "DEFEAT" or session.alive().is_empty(): session = Session.new(randi(),true,true)
	run_action(session.depart)

func select_actor(index: int) -> void:
	if session.party[index].hp <= 0: return
	pending_attack = {}; show_attack_range = false
	if session.companions:
		reservation_actor = index if index != session.selected and session.phase == "BATTLE" else -1
		mode = ""; pending_item = -1
		notice = session.party[index].name+" · 예약할 이동 칸 / 적 / 스킬 선택" if reservation_actor >= 0 else "직접 조작 · 동료의 예약은 유지됩니다."
		refresh(); return
	session.selected = index; mode = ""; pending_item = -1; notice = session.party[index].name; refresh()

func run_action(callback: Callable) -> void:
	session.effects.clear()
	var accepted: bool = callback.call()
	pending_attack = {}
	notice = "" if accepted else "대상·거리·행동력·보유 수량을 확인하세요."
	if accepted:
		mode = ""; pending_item = -1; reservation_actor = -1
		if not session.boss_trial and session.phase == "BATTLE" and session.alive().all(func(a): return a.ap <= 0): session.end_round()
	action_effects = session.effects.duplicate(true); session.effects.clear()
	refresh()

func preview_attack(point: Vector2i) -> void:
	pending_attack = session.attack_preview(point)
	show_attack_range = true
	notice = "공격 범위 밖이거나 행동력이 없습니다." if pending_attack.is_empty() else "%s · 명중 %d%% · 예상 피해 %d · 공격 버튼으로 확정" % [pending_attack.name,pending_attack.chance,pending_attack.damage]
	refresh()

func confirm_attack() -> void:
	if pending_attack.is_empty(): return
	var current: Dictionary = session.attack_preview(pending_attack.cell)
	if current != pending_attack:
		pending_attack = {}; notice = "상황이 바뀌었습니다. 대상을 다시 선택하세요."; refresh(); return
	var point: Vector2i = pending_attack.cell
	run_action(func(): return session.act("ATTACK",point))

func choose_skill(actor: int, slot: int) -> void:
	select_actor(actor); mode = SKILLS[0 if session.companions else actor][slot]
	if reservation_actor >= 0:
		if mode == "GUARD": queue_action("GUARD",session.party[actor].pos); return
		notice = session.party[actor].name+" · 스킬 예약 대상 선택"; refresh(); return
	if mode == "GUARD": run_action(func(): return session.act("GUARD",session.party[actor].pos)); return
	notice = "%s · 대상 칸 선택" % SKILL_NAMES[0 if session.companions else actor][slot]; refresh()

func choose_item(slot: int) -> void:
	reservation_actor = -1
	pending_attack = {}
	mode = ""; pending_item = slot
	if slot in [3,4]: notice = Session.SUPPLY_NAMES[slot]+" · 대상 칸 선택"; refresh()
	else: run_action(func(): return session.use_supply(slot))

func queue_action(kind: String, point: Vector2i) -> void:
	if session.reserve_action(reservation_actor,kind,point):
		notice = session.party[reservation_actor].name+" · 다음 행동 예약 완료"
		reservation_actor = -1; mode = ""
	else: notice = "예약 불가 · 대상과 거리를 확인하세요."
	refresh()

func on_cell(point: Vector2i) -> void:
	if reservation_actor >= 0:
		var target: Dictionary = session.at(point)
		var kind := mode if not mode.is_empty() else "ATTACK" if target.get("enemy",false) else "WAIT" if point == session.party[reservation_actor].pos else "MOVE"
		queue_action(kind,point); return
	if session.boss_trial and session.phase == "BATTLE" and session.rooms[session.room].shield and point == session.rooms[session.room].pylon:
		run_action(func(): return session.act("PYLON",point)); return
	if pending_item >= 0: run_action(func(): return session.use_supply(pending_item,point)); return
	if mode == "ATTACK": run_action(func(): return session.act("ATTACK",point)); return
	if not mode.is_empty(): run_action(func(): return session.act(mode,point)); return
	var actor: Dictionary = session.at(point)
	if not actor.is_empty() and not actor.enemy:
		if session.phase == "BATTLE" and actor.id == session.selected: run_action(func(): return session.act("WAIT",point))
		else: select_actor(actor.id)
		return
	if session.phase == "EXPLORE": run_action(func(): return session.interact_room(point))
	elif session.phase == "BATTLE":
		if not actor.is_empty(): run_action(func(): return session.act("ATTACK",point))
		else:
			show_attack_range = true
			run_action(func(): return session.act("MOVE",point))

func show_map() -> void:
	if session.phase not in ["BATTLE","EXPLORE"]: return
	map_view.session = session; map_view.queue_redraw(); map_popup.popup_centered()

func show_orders() -> void:
	clear(modal_content); label(modal_content,"동료 행동 예약",18)
	for i in range(session.party.size()):
		if i == session.selected: continue
		label(modal_content,session.party[i].name)
		button(modal_content,"다음 행동 예약",func(): details_popup.hide(); select_actor(i),session.phase == "BATTLE" and session.party[i].hp > 0)
		button(modal_content,"예약 취소 · 자동 행동",func(): session.cancel_reservation(i); refresh(); show_orders())
		button(modal_content,"상태 · 숙련 확인",func(): show_character(i,"상태"))
	button(modal_content,"주인공 상태",func(): show_character(session.selected,"상태"))
	button(modal_content,"원정 · 귀환",func(): open_management(3))
	button(modal_content,"닫기",func(): details_popup.hide()); details_popup.popup_centered()

func on_room(id: int) -> void:
	if id == session.room: map_popup.hide(); return
	if session.can_travel(id): map_popup.hide(); run_action(func(): return session.travel(id))

func modal(title: String, body: String) -> void:
	clear(modal_content); label(modal_content,title,18)
	var text := RichTextLabel.new(); text.text = body; text.custom_minimum_size = Vector2(300,210); text.size_flags_vertical = SIZE_EXPAND_FILL; modal_content.add_child(text)
	button(modal_content,"닫기",func(): details_popup.hide()); details_popup.popup_centered()

func open_management(index: int) -> void:
	match index:
		0:
			show_character(session.selected,"상태")
		1: show_supplies()
		2: show_tactics()
		3:
			modal("원정","목표: 보스 처치 후 귀환\n탐색: %d / 9개 방\n전리품: %d\n자금: %d\n\n" % [session.visited.size(),session.loot,session.bank]+("행동 한 번마다 적도 행동합니다. 자신을 누르면 대기. 미리보기는 시간을 쓰지 않습니다." if session.boss_trial else "전원 행동력 소진 시 적 차례."))
			if session.phase in ["BATTLE","EXPLORE"]: button(modal_content,"철수 · 전리품 절반" if session.phase == "BATTLE" else "귀환",func(): details_popup.hide(); run_action(session.retreat))
			if session.phase == "TOWN": button(modal_content,"요양 · 20 자금",func(): details_popup.hide(); run_action(session.rest_town),session.bank >= 20)

func show_character(index: int, tab: String = "상태") -> void:
	tactics_actor = clampi(index,0,session.party.size()-1); character_tab = tab
	clear(modal_content)
	var actor: Dictionary = session.party[tactics_actor]
	label(modal_content,actor.name+" · 캐릭터",18)
	var members := HBoxContainer.new(); modal_content.add_child(members)
	for i in range(session.party.size()):
		button(members,session.party[i].name,func(): tactics_expanded = -1; show_character(i,character_tab))
	var tabs := HBoxContainer.new(); modal_content.add_child(tabs)
	for title in ["상태","성격","기억","숙련","가방"]:
		var tab_button := button(tabs,title,func(): show_character(tactics_actor,title))
		tab_button.toggle_mode = true; tab_button.button_pressed = title == character_tab
	if tab == "숙련":
		build_tactics(); return
	var body := ""
	match tab:
		"상태": body = "체력 %d/%d · 스트레스 %d\n%s\n\n%s" % [actor.hp,actor.max_hp,actor.stress,actor.condition,Session.Body.description(actor)]
		"성격": body = actor.profile.style_summary().label
		"기억":
			for memory in actor.memory.records: body += "%s · 강도 %d\n" % [memory.kind,memory.salience]
			if body.is_empty(): body = "아직 기록된 기억이 없습니다."
		"가방":
			body = "소모품은 파티 공용입니다.\n\n"
			for i in range(6): body += "%s × %d\n" % [Session.SUPPLY_NAMES[i],session.supplies[i]]
	var text := RichTextLabel.new(); text.text = body; text.custom_minimum_size = Vector2(300,minf(300,size.y-270)); modal_content.add_child(text)
	button(modal_content,"닫기",func(): details_popup.hide()); details_popup.popup_centered()

func show_tactics() -> void:
	show_character(tactics_actor,"숙련")

func build_tactics() -> void:
	label(modal_content,"위쪽부터 사용 · 변경 즉시 적용 · 턴 소비 없음",11)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(310,minf(400,size.y-330))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; modal_content.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = SIZE_EXPAND_FILL; list.add_theme_constant_override("separation",10); scroll.add_child(list)
	var actor: Dictionary = session.party[tactics_actor]
	label(list,"스킬 사용 순서",14)
	for index in range(actor.rules.size()):
		var rule: Dictionary = actor.rules[index]
		var card := VBoxContainer.new(); list.add_child(card)
		var header := HBoxContainer.new(); card.add_child(header)
		button(header,"%d. %s  ⚙" % [index+1,Session.Rules.SKILLS[rule.skill].name],func(): tactics_expanded = -1 if tactics_expanded == index else index; show_tactics())
		var enabled := CheckButton.new(); enabled.text = "자동"; enabled.button_pressed = rule.enabled; enabled.custom_minimum_size.y = 44; header.add_child(enabled)
		enabled.toggled.connect(func(value): change_tactic_rule(index,"enabled",value))
		var summary := label(card,Session.Rules.summary(rule),11); summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; summary.custom_minimum_size.x = 290
		if tactics_expanded != index: continue
		var def: Dictionary = Session.Rules.SKILLS[rule.skill]
		tactic_pick(card,"누구에게?",def.targets,Session.Rules.TARGET_NAMES,rule.target,func(value): change_tactic_rule(index,"target",value))
		tactic_pick(card,"언제?",def.conditions,Session.Rules.WHEN_NAMES,rule.when,func(value): change_tactic_rule(index,"when",value))
		if rule.when in ["HP","STATUS"]:
			tactic_pick(card,"누구 기준?",["SELF"] if rule.target == "SELF" else ["SELF","TARGET"],{"SELF":"자신","TARGET":"대상"},"SELF" if rule.target == "SELF" else rule.subject,func(value): change_tactic_rule(index,"subject",value))
		if rule.when == "HP":
			var threshold := label(card,"체력 %d%%" % rule.threshold)
			var slider := HSlider.new(); slider.min_value = 10; slider.max_value = 100; slider.step = 10; slider.value = rule.threshold; slider.custom_minimum_size = Vector2(280,44); card.add_child(slider)
			slider.value_changed.connect(func(value): session.update_rule(tactics_actor,index,"threshold",int(value)); threshold.text = "체력 %d%%" % int(value); refresh())
			tactic_pick(card,"기준",["BELOW","ABOVE"],{"BELOW":"이하","ABOVE":"이상"},rule.comparison,func(value): change_tactic_rule(index,"comparison",value))
		if rule.when == "STATUS":
			tactic_pick(card,"어떤 상태?",Session.Rules.STATUS_NAMES.keys(),Session.Rules.STATUS_NAMES,rule.status,func(value): change_tactic_rule(index,"status",value))
		var ordering := HBoxContainer.new(); card.add_child(ordering)
		button(ordering,"↑ 먼저 사용",func(): session.reorder_rule(tactics_actor,index,-1); tactics_expanded = index-1; refresh(); show_tactics(),index > 0)
		button(ordering,"↓ 나중에 사용",func(): session.reorder_rule(tactics_actor,index,1); tactics_expanded = index+1; refresh(); show_tactics(),index < actor.rules.size()-1)
	var basic := VBoxContainer.new(); list.add_child(basic)
	label(basic,"기본 행동",14)
	tactic_pick(basic,"일반 공격 대상",Session.Rules.BASIC_TARGETS,Session.Rules.TARGET_NAMES,actor.basic_target,change_basic_target)
	var hint := label(basic,"사용할 스킬이 없으면 공격 가능한 적을 공격합니다.\n공격할 수 없으면 안전하게 접근하거나 대기합니다.",11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; hint.custom_minimum_size.x = 290
	label(modal_content,"위험 칸 회피 우선 · 자동 OFF여도 직접 사용 가능",10)
	button(modal_content,"기본값 복원",func(): actor.rules = Session.Rules.defaults(); session.set_basic_target(tactics_actor,Session.Rules.BASIC_TARGET_DEFAULT); refresh(); show_tactics())
	button(modal_content,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func change_basic_target(value: String) -> void:
	if session.set_basic_target(tactics_actor,value): refresh(); show_tactics()

func change_tactic_rule(index: int, field: String, value: Variant) -> void:
	if session.update_rule(tactics_actor,index,field,value): refresh(); show_tactics()

func tactic_pick(parent: Node, title: String, values: Array, names: Dictionary, current: String, changed: Callable) -> void:
	label(parent,title,12)
	var pick := OptionButton.new(); pick.custom_minimum_size = Vector2(280,44)
	for value in values: pick.add_item(names[value])
	pick.select(maxi(0,values.find(current))); parent.add_child(pick)
	pick.item_selected.connect(func(index): changed.call(values[index]))

func show_supplies() -> void:
	var body := "파티 공용 소모품\n선택한 대원: %s\n\n" % session.party[session.selected].name
	for i in range(6): body += "%s × %d\n" % [Session.SUPPLY_NAMES[i],session.supplies[i]]
	modal("가방",body+("\n사용하면 적도 한 번 행동합니다." if session.boss_trial else "\n전투 중 행동력 1 소비."))
	button(modal_content,"횃불 사용 · 밝기 +50",func(): details_popup.hide(); run_action(session.use_torch),session.phase == "EXPLORE" and session.torches > 0 and session.light < 100)
