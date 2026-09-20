extends Control
const Session = preload("res://expedition/session.gd")
const Board = preload("res://expedition/board.gd")
const MapView = preload("res://expedition/map_view.gd")
const Art = preload("res://expedition/mobile_art.gd")
const InventorySlot = preload("res://expedition/inventory_slot.gd")
var inventory_filter := "전체"
var inventory_selected := ""
var inventory_slots: Array = []
var item_popup: PopupPanel
var item_detail: VBoxContainer
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
var reset_effects := false
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
	item_popup = PopupPanel.new(); add_child(item_popup)
	item_detail = VBoxContainer.new(); item_detail.custom_minimum_size = Vector2(300,200); item_popup.add_child(item_detail)
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
	var elapsed := 0.0
	# Opening an order/selection must not erase an attack that just resolved.
	if not reset_effects and action_effects.is_empty() and is_instance_valid(board):
		action_effects = board.effects.duplicate(true); elapsed = board.effect_time
	reset_effects = false
	clear(root_layout); item_buttons.clear(); skill_buttons.clear(); portrait_buttons.clear()
	map_view.session = session; map_view.queue_redraw()
	var header := HBoxContainer.new(); header.add_theme_constant_override("separation",6); root_layout.add_child(header)
	minimap = MapView.new(); minimap.compact = true; minimap.minimum_side = 76
	minimap.session = session; minimap.ui_font = FONT; minimap.expand_requested.connect(show_map)
	minimap.size_flags_horizontal = SIZE_SHRINK_BEGIN; header.add_child(minimap)
	var location := VBoxContainer.new(); location.size_flags_horizontal = SIZE_EXPAND_FILL; header.add_child(location)
	label(location,session.rooms[session.room].name if session.phase in ["EXPLORE","BATTLE"] else "원정 준비",12)
	if session.phase == "BATTLE": label(location,"행동 %d" % session.round_number if session.boss_trial else "%d턴 · AP %d" % [session.round_number,session.party[session.selected].ap],11)
	var resource := VBoxContainer.new(); resource.custom_minimum_size.x = 124; header.add_child(resource)
	label(resource,"식량 %d   횃불 %d" % [session.food,session.torches],12)
	label(resource,"배고픔 %d%%" % session.hunger,10); gauge(resource,session.hunger,100,Color("d9904d"))
	label(resource,"불빛 %d%%" % session.light,10); gauge(resource,session.light,100,Color("e6bd62"))
	board = Board.new(); board.session = session; board.ui_font = FONT; board.cell_pressed.connect(on_cell)
	board.action_footer = not session.boss_trial or not pending_attack.is_empty()
	root_layout.add_child(board)
	board.show_attack_range = show_attack_range
	board.input_actor = reservation_actor
	board.targeting_skill = mode
	board.effects = action_effects; action_effects = []
	board.effect_time = elapsed
	board.target_cell = pending_attack.get("cell",Vector2i(-1,-1))
	board.companion_previews = session.companion_previews()
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
	feedback.visible = not notice.is_empty()
	var hint := label(feedback,notice,10)
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
			var skill_id: String = actor.equipped_abilities[slot] if session.boss_trial else SKILLS[i][slot]
			var skill_name: String = Session.Rules.SKILLS.get(skill_id,{}).get("name",skill_id)
			var skill := icon_button(skills,Art.skill(slot if session.boss_trial else i*2+slot),func(): choose_skill(i,slot),skill_name)
			if Session.Abilities.DEFINITIONS.has(skill_id):
				var caption := label(skill,skill_name+ (" %d" % actor.cooldowns.get(skill_id,0) if actor.cooldowns.get(skill_id,0) > 0 else ""),10)
				caption.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE); caption.offset_top = -16; caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			skill.disabled = session.phase != "BATTLE" or actor.hp <= 0 or actor.ap <= 0; skill_buttons.append(skill)
			if actor.cooldowns.get(skill_id,0) > 0: skill.disabled = true
		var portrait_box := VBoxContainer.new(); portrait_box.size_flags_horizontal = SIZE_EXPAND_FILL; portrait_box.add_theme_constant_override("separation",2); column.add_child(portrait_box)
		var portrait := button(portrait_box,"",func(): select_actor(i)); portrait.custom_minimum_size.y = 48; portrait_buttons.append(portrait)
		var face := TextureRect.new(); face.texture = Art.portrait(i); face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; face.mouse_filter = MOUSE_FILTER_IGNORE
		portrait.add_child(face); face.set_anchors_and_offsets_preset(PRESET_FULL_RECT); face.offset_bottom = -18; face.offset_top = 2; face.offset_left = 2; face.offset_right = -2
		var name_label := label(portrait,"%s Lv.%d  %d/%d" % [actor.name,actor.growth.level,actor.hp,actor.max_hp],11); name_label.position = Vector2(4,30)
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
	button(nav,"상태",func(): show_character(session.selected,"상태"))
	if reservation_actor >= 0:
		button(nav,"예약 취소",func(): session.cancel_reservation(reservation_actor); reservation_actor = -1; mode = ""; notice = "예약 취소 · 자동 행동"; refresh())
	else: button(nav,"전술",show_orders)
	var essence_count := 0
	for quantity in session.essences.values(): essence_count += int(quantity)
	button(nav,"가방"+(" (%d)" % essence_count if essence_count > 0 else ""),show_supplies)
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
	var previous_essences: Dictionary = session.essences.duplicate()
	session.effects.clear()
	var accepted: bool = callback.call()
	pending_attack = {}
	notice = "" if accepted else "대상·거리·행동력·보유 수량을 확인하세요."
	if accepted:
		mode = ""; pending_item = -1; reservation_actor = -1
		for id in session.essences:
			if session.essences[id] > previous_essences.get(id,0): notice = "이능 획득 · "+Session.Abilities.DEFINITIONS[id].item+"! 가방에서 확인하세요."
		if not session.boss_trial and session.phase == "BATTLE" and session.alive().all(func(a): return a.ap <= 0): session.end_round()
	action_effects = session.effects.duplicate(true); session.effects.clear()
	reset_effects = accepted
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
	if actor < 0 or actor >= session.party.size() or slot not in [0,1] or session.party[actor].hp <= 0: return
	select_actor(actor); mode = session.party[actor].equipped_abilities[slot] if session.boss_trial else SKILLS[actor][slot]
	var self_target: bool = mode == "GUARD" or Session.Abilities.DEFINITIONS.get(mode,{}).get("target","") == "SELF"
	if reservation_actor >= 0:
		if self_target: queue_action(mode,session.party[actor].pos); return
		notice = session.party[actor].name+" · 스킬 예약 대상 선택"; refresh(); return
	if self_target: run_action(func(): return session.act(mode,session.party[actor].pos)); return
	notice = "%s · 대상 칸 선택" % Session.Rules.SKILLS.get(mode,{}).get("name",mode); refresh()

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
	for title in ["상태","성격","기억","숙련","이능","가방"]:
		var tab_button := button(tabs,title,func(): show_character(tactics_actor,title))
		tab_button.toggle_mode = true; tab_button.button_pressed = title == character_tab
	if tab == "숙련":
		build_tactics(); return
	if tab == "이능":
		build_abilities(); return
	if tab == "가방":
		build_inventory(); return
	var body := ""
	match tab:
		"상태": body = "Lv.%d · XP %d / %d\n체력 %d/%d · 스트레스 %d\n%s\n\n%s\n\n근력 %d · 민첩 %d · 지능 %d\n일반 공격 기본 위력 %d · 방어 피해 감소 %d%%\n3레벨마다 스탯 1점. 근력: 근접, 민첩: 원거리, 지능: 마법 기본 위력 +2." % [actor.growth.level,actor.growth.xp,Session.Growth.threshold(mini(21,actor.growth.level+1)),actor.hp,actor.max_hp,actor.stress,actor.condition,Session.Body.description(actor),actor.growth.stats.STR,actor.growth.stats.DEX,actor.growth.stats.INT,Session.Growth.power(actor,"MELEE",18),actor.growth.ranks.DEFENSE*4]
		"성격": body = actor.profile.style_summary().label
		"기억":
			for memory in actor.memory.records: body += "%s · 강도 %d\n" % [memory.kind,memory.salience]
			if body.is_empty(): body = "아직 기록된 기억이 없습니다."
		"가방":
			body = "소모품은 파티 공용입니다.\n\n"
			for i in range(6): body += "%s × %d\n" % [Session.SUPPLY_NAMES[i],session.supplies[i]]
	var text := RichTextLabel.new(); text.text = body; text.custom_minimum_size = Vector2(300,minf(300,size.y-270)); modal_content.add_child(text)
	if tab == "상태":
		label(modal_content,"남은 스탯 포인트 %d" % actor.growth.stat_points)
		var stats := HBoxContainer.new(); modal_content.add_child(stats)
		for id in Session.Growth.STATS:
			button(stats,Session.Growth.STATS[id]+" +",func(): session.spend_growth(tactics_actor,id,true); refresh(); show_character(tactics_actor,"상태"),session.phase in ["TOWN","EXPLORE"] and actor.hp > 0 and actor.growth.stat_points > 0)
	if tab == "가방": button(modal_content,"이능 전리품 · 먹을 인물 선택",show_essences)
	button(modal_content,"닫기",func(): details_popup.hide()); details_popup.popup_centered()

func show_tactics() -> void:
	show_character(tactics_actor,"숙련")

func build_tactics() -> void:
	label(modal_content,"위쪽부터 사용 · 변경 즉시 적용 · 턴 소비 없음",11)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(310,minf(400,size.y-330))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; modal_content.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = SIZE_EXPAND_FILL; list.add_theme_constant_override("separation",10); scroll.add_child(list)
	var actor: Dictionary = session.party[tactics_actor]
	label(list,"Lv.%d · 숙련 포인트 %d" % [actor.growth.level,actor.growth.points],14)
	for axis in Session.Growth.AXES:
		var row := HBoxContainer.new(); list.add_child(row)
		label(row,"%s %d/10 · %s" % [Session.Growth.AXES[axis],actor.growth.ranks[axis],"피해 감소 +4%p" if axis == "DEFENSE" else "위력 +8%p"],11)
		button(row,"+",func(): session.spend_growth(tactics_actor,axis); refresh(); show_tactics(),session.phase in ["TOWN","EXPLORE"] and actor.hp > 0 and actor.growth.points > 0 and actor.growth.ranks[axis] < 10)
	label(list,"스킬 사용 순서",14)
	for index in range(actor.rules.size()):
		var rule: Dictionary = actor.rules[index]
		var card := VBoxContainer.new(); list.add_child(card)
		var header := HBoxContainer.new(); card.add_child(header)
		button(header,"%d. %s%s ⚙" % [index+1,Session.Rules.SKILLS[rule.skill].name,"" if rule.skill in actor.equipped_abilities else " (미장착)"],func(): tactics_expanded = -1 if tactics_expanded == index else index; show_tactics())
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
	button(modal_content,"행동방침 기본값 복원",func(): session.reset_rules(tactics_actor); refresh(); show_tactics())
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
	clear(modal_content); label(modal_content,"공용 가방",18); build_inventory()

func inventory_rows() -> Array:
	var rows: Array = []
	var descriptions := ["선택한 대원의 체력 20 회복 및 부상 치료.","선택한 대원의 스트레스 25 감소.","파티 배고픔 30, 대상 스트레스 10 감소.","전투 중 나무 바닥에 불을 붙입니다. 사거리 4.","전투 중 대상 바닥을 적십니다. 사거리 4.","선택한 대원의 체력 10 회복 및 부상 치료."]
	for i in range(6):
		if session.supplies[i] > 0: rows.append({"id":"supply:%d"%i,"label":Session.SUPPLY_NAMES[i],"quantity":session.supplies[i],"category":"소모품","slot":i,"description":descriptions[i],"icon":Art.item(i)})
	for id in Session.Abilities.DEFINITIONS:
		if session.essences.get(id,0) <= 0: continue
		var def: Dictionary = Session.Abilities.DEFINITIONS[id]
		rows.append({"id":id,"label":def.item,"quantity":session.essences[id],"category":"이능","description":"습득: "+def.name+"\n"+def.description,"icon":Art.item(3 if id == "BOMB" else 4 if id == "SHOCKWAVE" else 5)})
	for entry in [["food","식량",session.food,"방 이동 시 자동 소모합니다."],["torch","횃불",session.torches,"탐험 중 불빛을 50 회복합니다."]]:
		if entry[2] > 0: rows.append({"id":entry[0],"label":entry[1],"quantity":entry[2],"category":"자원","description":entry[3],"icon":Art.navigation(3)})
	return rows

func build_inventory() -> void:
	label(modal_content,"아이템 선택 → 상세 정보 / 사용할 대원 선택",11)
	var filters := HBoxContainer.new(); modal_content.add_child(filters)
	for category in ["전체","소모품","이능","자원"]:
		var pick := button(filters,category,func(): inventory_filter = category; show_supplies())
		pick.toggle_mode = true; pick.button_pressed = category == inventory_filter
	var rows: Array = inventory_rows().filter(func(r): return inventory_filter == "전체" or r.category == inventory_filter)
	label(modal_content,"%s · %d종 보유" % [inventory_filter,rows.size()],12)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(310,minf(300,size.y-310)); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; modal_content.add_child(scroll)
	var grid := GridContainer.new(); grid.columns = 4; grid.size_flags_horizontal = SIZE_EXPAND_FILL; grid.add_theme_constant_override("h_separation",4); grid.add_theme_constant_override("v_separation",4); scroll.add_child(grid)
	inventory_slots.clear()
	for i in range(maxi(12,int(ceil(rows.size()/4.0))*4)):
		var slot = InventorySlot.new(); grid.add_child(slot)
		var row: Dictionary = rows[i] if i < rows.size() else {}
		slot.configure(row,row.get("id","") == inventory_selected); inventory_slots.append(slot)
		if not row.is_empty(): slot.pressed.connect(func(): show_item_detail(row.id))
	label(modal_content,"전투 중 사용: 주인공 행동 1회 · 이능 섭취는 전투 밖",10)
	button(modal_content,"닫기",func(): details_popup.hide()); details_popup.popup_centered()

func show_item_detail(id: String) -> void:
	var matches: Array = inventory_rows().filter(func(r): return r.id == id)
	if matches.is_empty(): item_popup.hide(); show_supplies(); return
	var row: Dictionary = matches[0]; inventory_selected = id
	for slot in inventory_slots:
		if is_instance_valid(slot): slot.selected = slot.row.get("id","") == id; slot.queue_redraw()
	clear(item_detail); label(item_detail,"%s × %d" % [row.label,row.quantity],18)
	var info := label(item_detail,row.description,12); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; info.custom_minimum_size.x = 290
	if row.category == "이능":
		for i in range(session.party.size()):
			button(item_detail,session.party[i].name+"에게 먹이기",func(): item_popup.hide(); confirm_essence(i,id),session.phase in ["TOWN","EXPLORE"] and session.party[i].hp > 0 and id not in session.party[i].learned_abilities)
	elif row.category == "소모품":
		if row.slot in [3,4]:
			button(item_detail,"사용 · 바닥 선택",func(): item_popup.hide(); details_popup.hide(); choose_item(row.slot),session.phase == "BATTLE")
		else:
			for i in range(session.party.size()):
				button(item_detail,session.party[i].name+"에게 사용",func(): item_popup.hide(); details_popup.hide(); run_action(func(): return session.use_supply(row.slot,Vector2i(-1,-1),i)),session.phase in ["BATTLE","EXPLORE"] and session.party[i].hp > 0)
	elif id == "torch":
		button(item_detail,"횃불 사용",func(): item_popup.hide(); details_popup.hide(); run_action(session.use_torch),session.phase == "EXPLORE" and session.light < 100)
	button(item_detail,"닫기",func(): item_popup.hide()); item_popup.popup_centered()

func popup_list() -> VBoxContainer:
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(310,minf(330,size.y-300)); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; modal_content.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(list)
	return list

func build_abilities() -> void:
	var actor: Dictionary = session.party[tactics_actor]
	label(modal_content,"습득 목록 유지 · 장착 2개 · 전투 밖에서 교체",11)
	var list := popup_list()
	for id in actor.learned_abilities:
		label(list,Session.Rules.SKILLS[id].name,14)
		var info := label(list,Session.Abilities.DEFINITIONS.get(id,{}).get("description","시작 기술"),11); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; info.custom_minimum_size.x = 290
		var row := HBoxContainer.new(); list.add_child(row)
		for slot in range(2):
			button(row,"%d번 장착%s" % [slot+1," 중" if actor.equipped_abilities[slot] == id else ""],func(): session.equip_ability(tactics_actor,slot,id); refresh(); show_character(tactics_actor,"이능"),session.phase in ["TOWN","EXPLORE"] and actor.hp > 0 and id not in actor.equipped_abilities)
	button(modal_content,"이능 전리품 가방",show_essences)
	button(modal_content,"닫기",func(): details_popup.hide()); details_popup.popup_centered()

func show_essences() -> void:
	inventory_filter = "이능"; show_supplies()

func confirm_essence(index: int, id: String) -> void:
	var def: Dictionary = Session.Abilities.DEFINITIONS[id]
	modal("이능 습득 확인",session.party[index].name+"이 "+def.item+"을 먹습니다.\n\n습득: "+def.name+"\n"+def.description+"\n\n아이템 1개 소모 · 습득 후 장착 필요")
	button(modal_content,"먹고 습득",func():
		if session.consume_essence(index,id): refresh(); show_character(index,"이능")
		else: show_essences())
