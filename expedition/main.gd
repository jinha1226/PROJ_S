extends Control
const Session = preload("res://expedition/session.gd")
const Board = preload("res://expedition/board.gd")
const MapView = preload("res://expedition/map_view.gd")
const Art = preload("res://expedition/mobile_art.gd")
const InventorySlot = preload("res://expedition/inventory_slot.gd")
const CharacterUI = preload("res://expedition/character_ui.gd")
var portrait_gesture = preload("res://expedition/legacy/portrait_gesture.gd").new()
var navigation = preload("res://expedition/exploration_navigation.gd").new()
var navigation_clock := 0.0
var view_side := 10
var log_popup: PopupPanel
var auto_explore_button: Button
var inventory_filter := "전체"
var inventory_selected := ""
var inventory_slots: Array = []
var item_popup: PopupPanel
var item_detail: VBoxContainer
const FONT = preload("res://assets/fonts/NanumSquareR.ttf")
const SKILLS = [["PUSH","GUARD"],["ATTACK","GUARD"],["WATER","ELECTRIC"]]
const SKILL_NAMES = [["밀쳐내기","방어"],["강타","방어"],["물","방전"]]
var session = Session.new(randi(),true,false,true)
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
var notice := "":
	set(value):
		notice = value
		if is_instance_valid(toast):
			toast.text = value
			toast.visible = not value.is_empty()
			toast_remaining = 2.5
var toast: Label
var toast_remaining := 0.0
var command_targeting := false
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
	skin.set_stylebox("panel","PopupPanel",CharacterUI.surface(Color("101416")))
	theme = skin
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,0 if side in ["left","right"] else 8)
	add_child(margin)
	root_layout = VBoxContainer.new(); root_layout.add_theme_constant_override("separation",5); margin.add_child(root_layout)
	map_popup = PopupPanel.new(); add_child(map_popup)
	var map_box := VBoxContainer.new(); map_box.custom_minimum_size = Vector2(300,360); map_popup.add_child(map_box)
	map_view = MapView.new(); map_view.session = session; map_view.ui_font = FONT; map_view.minimum_side = 280
	map_view.room_pressed.connect(on_room); map_box.add_child(map_view)
	button(map_box,"닫기",func(): map_popup.hide())
	details_popup = PopupPanel.new(); add_child(details_popup)
	modal_content = VBoxContainer.new(); modal_content.custom_minimum_size = Vector2(minf(300,size.x-32),210); details_popup.add_child(modal_content)
	item_popup = PopupPanel.new(); details_popup.add_child(item_popup)
	item_popup.transient = true; item_popup.exclusive = true
	item_detail = VBoxContainer.new(); item_detail.custom_minimum_size = Vector2(300,200); item_popup.add_child(item_detail)
	log_popup = PopupPanel.new(); add_child(log_popup)
	toast = Label.new(); toast.name = "NoticeToast"; toast.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(toast); toast.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	toast.anchor_top = 0.22; toast.anchor_bottom = 0.22
	toast.offset_left = 16; toast.offset_right = -16
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.add_theme_font_size_override("font_size",16)
	toast.add_theme_stylebox_override("normal",CharacterUI.surface(Color(0.04,0.05,0.07,0.92)))
	toast.z_index = 10; toast.visible = false
	refresh()

func stop_navigation() -> void:
	navigation.stop(); navigation_clock = 0
	if is_instance_valid(auto_explore_button): auto_explore_button.text = "자동탐험"

func _process(delta: float) -> void:
	toast_remaining = maxf(0,toast_remaining-delta)
	if is_instance_valid(toast): toast.visible = toast_remaining > 0 and not notice.is_empty()
	portrait_gesture.tick(self)
	if not navigation.active: return
	if details_popup.visible or map_popup.visible or log_popup.visible or not get_window().has_focus(): stop_navigation(); return
	navigation_clock += delta
	if navigation_clock >= 0.2:
		navigation_clock = 0; navigation_tick()

func navigation_tick() -> void:
	var step: Vector2i = navigation.next_step(session)
	if step.x < 0: stop_navigation(); return
	var health: Array = session.party.map(func(a): return a.hp)
	run_action(func(): return session.act("MOVE",step),true)
	if session.party.map(func(a): return a.hp) != health or not session.combat_enemies().is_empty() or session.party[session.selected].pos != step:
		stop_navigation()
	elif not navigation.automatic and step == navigation.destination: stop_navigation()

func _input(event: InputEvent) -> void:
	portrait_gesture.handle(self,event)

func toggle_explore() -> void:
	if navigation.active: stop_navigation(); return
	mode = ""; pending_item = -1; reservation_actor = -1
	if navigation.explore(session): auto_explore_button.text = "탐험 중지"
	else: notice = "주변에 적이 있습니다"; refresh()

func show_logs() -> void:
	stop_navigation(); clear(log_popup)
	var skin: Theme = theme.duplicate()
	var panel := CharacterUI.surface(Color("101416")); panel.set_content_margin_all(8); panel.shadow_size = 0
	skin.set_stylebox("panel","PopupPanel",panel); log_popup.theme = skin
	var box := VBoxContainer.new(); box.custom_minimum_size = size-Vector2(16,16); log_popup.add_child(box)
	label(box,"전체 기록",22)
	var history := RichTextLabel.new(); history.name = "FullHistory"; history.size_flags_vertical = SIZE_EXPAND_FILL
	history.add_theme_font_size_override("normal_font_size",18); history.text = "\n\n".join(session.log_lines)
	history.scroll_following = true; box.add_child(history)
	button(box,"닫기",func(): log_popup.hide())
	log_popup.popup_centered(Vector2i(size))

func clear(node: Node) -> void:
	if node == modal_content:
		item_popup.hide()
		details_popup.theme = theme
		modal_content.custom_minimum_size = Vector2(minf(300,size.x-32),210)
	for child in node.get_children(): node.remove_child(child); child.queue_free()
	if node == modal_content: details_popup.reset_size()

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
	var impact_elapsed := 0.0
	# Opening an order/selection must not erase an attack that just resolved.
	if not reset_effects and action_effects.is_empty() and is_instance_valid(board):
		action_effects = board.effects.duplicate(true); elapsed = board.effect_time
		impact_elapsed = board.impact_time
	reset_effects = false
	# Retain the renderer and minimap's incremental cache across action refreshes.
	if is_instance_valid(board): root_layout.remove_child(board); clear(board)
	if is_instance_valid(minimap): minimap.get_parent().remove_child(minimap)
	clear(root_layout); item_buttons.clear(); skill_buttons.clear(); portrait_buttons.clear()
	map_view.session = session; map_view.queue_redraw()
	var header := HBoxContainer.new(); header.name = "TopHUD"; header.add_theme_constant_override("separation",3); root_layout.add_child(header)
	if not is_instance_valid(minimap):
		minimap = MapView.new(); minimap.compact = true; minimap.minimum_side = 44
		minimap.ui_font = FONT; minimap.expand_requested.connect(show_map)
	minimap.session = session; minimap.queue_redraw()
	minimap.size_flags_horizontal = SIZE_SHRINK_BEGIN; header.add_child(minimap)
	var place := label(header,("1층" if session.floor_mode else session.rooms[session.room].name) if session.phase in ["BATTLE","EXPLORE"] else "거점",18)
	place.name = "Location"; place.clip_text = true; place.size_flags_horizontal = SIZE_EXPAND_FILL
	place.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var food_button := button(header,"식량\n%d" % session.food,func(): run_action(session.use_food),session.phase == "BATTLE" and session.food > 0)
	food_button.name = "FoodButton"; food_button.custom_minimum_size.x = 44
	var torch_button := button(header,"횃불\n%d" % session.torches,func(): run_action(session.use_torch),session.phase == "BATTLE" and session.torches > 0)
	torch_button.name = "TorchButton"; torch_button.custom_minimum_size.x = 44
	var goal := button(header,"유물찾기",show_goal); goal.name = "ObjectiveChip"
	goal.custom_minimum_size.x = 56
	var menu := button(header,"☰",show_objective); menu.name = "ExpeditionMenu"; menu.custom_minimum_size.x = 44
	for control in [food_button,torch_button,goal,menu]: control.size_flags_horizontal = SIZE_SHRINK_END
	if not is_instance_valid(board):
		board = Board.new(); board.ui_font = FONT; board.cell_pressed.connect(on_cell)
		board.zoom_changed.connect(func(value): view_side = value)
		board.gesture_started.connect(stop_navigation)
	board.session = session; board.view_side = view_side; board.queue_redraw()
	board.action_footer = not session.boss_trial or not pending_attack.is_empty()
	root_layout.add_child(board)
	# The result card takes the board's place until the player refits.
	board.visible = session.result.is_empty() or session.phase != "TOWN"
	board.show_attack_range = show_attack_range
	board.input_actor = reservation_actor
	board.targeting_skill = mode
	board.effects = action_effects; action_effects = []
	board.effect_time = elapsed
	board.impact_time = impact_elapsed
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
	if session.phase == "TOWN" and not session.result.is_empty(): build_result_card()
	elif session.phase in ["TOWN","DEFEAT"]:
		var preparation := HBoxContainer.new(); root_layout.add_child(preparation)
		button(preparation,"출정" if session.phase == "TOWN" and not session.alive().is_empty() else "새 원정대",depart)
		if session.phase == "TOWN" and session.floor_mode:
			button(preparation,"상점 · 자금 %d" % session.bank,show_shop)
			button(preparation,"요양 · 20 자금",func(): run_action(session.rest_town),session.bank >= 20)
	var log_holder := Control.new(); log_holder.name = "LogOverlap"; log_holder.custom_minimum_size.y = 48
	log_holder.mouse_filter = MOUSE_FILTER_IGNORE; root_layout.add_child(log_holder)
	var log_button := button(log_holder,"",show_logs); log_button.name = "RecentLog"; log_button.custom_minimum_size.y = 66
	log_button.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	log_button.offset_top = -18; log_button.offset_bottom = 48; log_button.z_index = 2
	for state in ["normal","hover","pressed","focus","disabled"]:
		var panel := log_button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		panel.bg_color = Color(0.05,0.07,0.09,0.86); log_button.add_theme_stylebox_override(state,panel)
	var log_box := VBoxContainer.new(); log_box.mouse_filter = MOUSE_FILTER_IGNORE; log_button.add_child(log_box)
	log_box.set_anchors_and_offsets_preset(PRESET_FULL_RECT); log_box.offset_left = 6; log_box.offset_right = -6; log_box.add_theme_constant_override("separation",0)
	for i in range(3):
		var index: int = session.log_lines.size()-3+i
		var line := label(log_box,session.log_lines[index] if index >= 0 else "",16); line.clip_text = true
	var party_row := HBoxContainer.new(); party_row.add_theme_constant_override("separation",5); root_layout.add_child(party_row)
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var column: BoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",3); party_row.add_child(column)
		var skills := HBoxContainer.new(); skills.add_theme_constant_override("separation",3); column.add_child(skills)
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
		var portrait := button(portrait_box,"",func(): select_actor(i)); portrait.name = "MemberCard%d" % i
		portrait.tooltip_text = "짧게: 행동 예약 · 길게: 상태" if session.companions else "길게 누르기: 상태"; portrait.custom_minimum_size.y = 48; portrait_buttons.append(portrait)
		var stats := label(portrait,"%s\nHP %d/%d   MP %s   스트레스 %d" % [actor.name,actor.hp,actor.max_hp,str(actor.mp)+"/"+str(actor.max_mp) if actor.has("mp") else "—",actor.stress],12 if session.party.size() == 1 else 10)
		stats.set_anchors_and_offsets_preset(PRESET_FULL_RECT); stats.offset_left = 4; stats.offset_right = -4
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if i == session.selected:
			var gold := portrait.get_theme_stylebox("normal").duplicate(); gold.border_color = Color("e9c575"); gold.set_border_width_all(2); portrait.add_theme_stylebox_override("normal",gold)
		if actor.hp <= 0: portrait.modulate = Color("636369")
	var shared := HBoxContainer.new(); shared.add_theme_constant_override("separation",4); root_layout.add_child(shared)
	for slot in range(6):
		var item := icon_button(shared,Art.item(slot),func(): choose_item(slot),Session.SUPPLY_NAMES[slot],str(session.supplies[slot]))
		item.disabled = session.phase not in ["BATTLE","EXPLORE"] or session.supplies[slot] == 0; item_buttons.append(item)
	var nav := HBoxContainer.new(); nav.add_theme_constant_override("separation",4); root_layout.add_child(nav)
	advance_attack_button = button(nav,"공격",func(): run_action(session.auto_attack),session.phase == "BATTLE")
	var fighting: bool = not session.combat_enemies().is_empty()
	wait_button = button(nav,"대기" if fighting else "휴식",func(): run_action(func(): return session.act("WAIT",session.party[session.selected].pos) if fighting else session.rest_field()),session.phase == "BATTLE")
	auto_explore_button = button(nav,"중지" if navigation.active else "자동탐험",toggle_explore,session.floor_mode and session.phase == "BATTLE")
	button(nav,"전술",show_party_tactics)
	button(nav,"가방",show_supplies)
	for node in nav.get_children(): node.custom_minimum_size.y = 49

func depart() -> void:
	if session.phase == "DEFEAT" or session.alive().is_empty(): session = Session.new(randi(),true,false,true)
	run_action(session.depart)

func select_actor(index: int) -> void:
	stop_navigation()
	if session.party[index].hp <= 0: return
	pending_attack = {}; show_attack_range = false
	if session.companions:
		reservation_actor = index if index != session.selected and session.phase == "BATTLE" else -1
		mode = ""; pending_item = -1
		notice = session.party[index].name+" · 예약할 이동 칸 / 적 / 스킬 선택" if reservation_actor >= 0 else "직접 조작 · 동료의 예약은 유지됩니다."
		refresh(); return
	session.selected = index; mode = ""; pending_item = -1; notice = session.party[index].name; refresh()

func run_action(callback: Callable, navigating: bool = false) -> void:
	if not navigating: stop_navigation()
	var previous_essences: Dictionary = session.essences.duplicate()
	session.effects.clear()
	var accepted: bool = callback.call()
	pending_attack = {}
	notice = "" if accepted else "지금은 사용할 수 없습니다"
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
	notice = "공격 불가" if pending_attack.is_empty() else "%s · 명중 %d%% · 예상 피해 %d · 공격 버튼으로 확정" % [pending_attack.name,pending_attack.chance,pending_attack.damage]
	refresh()

func confirm_attack() -> void:
	if pending_attack.is_empty(): return
	var current: Dictionary = session.attack_preview(pending_attack.cell)
	if current != pending_attack:
		pending_attack = {}; notice = "대상을 다시 선택하세요"; refresh(); return
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
	stop_navigation()
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
	stop_navigation()
	if command_targeting:
		var target: Dictionary = session.at(point)
		if target in session.combat_enemies():
			session.command_target = target.id; session.party_command = "ATTACK_TARGET"; command_targeting = false; notice = "집중 공격"
		else: notice = "시야 안의 적 선택"
		refresh(); return
	if session.floor_mode and session.phase == "BATTLE" and reservation_actor < 0 and mode.is_empty() and pending_item < 0:
		var feature: Dictionary = session.floor_state.features.get(point,{})
		if feature.get("kind","") == "curio" and session.floor_state.visible.has(point): show_curio(point); return
		if feature.get("kind","") == "relic" and session.floor_state.visible.has(point): show_relic(); return
		if feature.get("kind","") == "entry" and session.floor_state.visible.has(point) and point != session.party[session.selected].pos and maxi(absi(point.x-session.party[session.selected].pos.x),absi(point.y-session.party[session.selected].pos.y)) <= 1: show_return(); return
	if session.floor_mode and session.phase == "BATTLE" and reservation_actor < 0 and mode.is_empty() and pending_item < 0 and session.floor_state.features.has(point) and not session.floor_state.features[point].used and point != session.party[session.selected].pos and session.distance(session.party[session.selected].pos,point) <= 1:
		run_action(func(): return session.floor_state.interact(session,point)); return
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
			if session.floor_mode and maxi(absi(point.x-session.party[session.selected].pos.x),absi(point.y-session.party[session.selected].pos.y)) > 1:
				if navigation.start(session,point): navigation_tick()
				else: notice = "이동 불가"; refresh()
			else: run_action(func(): return session.act("MOVE",point))

func show_map() -> void:
	stop_navigation()
	if session.phase not in ["BATTLE","EXPLORE"]: return
	map_view.session = session; map_view.queue_redraw(); map_popup.popup_centered()

func show_curio(point: Vector2i) -> void:
	stop_navigation(); clear(modal_content)
	var feature: Dictionary = session.floor_state.features.get(point,{})
	var def: Dictionary = Session.Curios.definition(feature)
	if def.is_empty(): return
	label(modal_content,def.name,22)
	var description := label(modal_content,def.description,17)
	description.custom_minimum_size.x = minf(300,size.x-32); description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if feature.used: label(modal_content,"이미 조사를 마쳤습니다.",16)
	else:
		label(modal_content,"조사 시 행동 1회 · 결과는 되돌릴 수 없습니다.",13)
		for id in def.options:
			var choice: Dictionary = def.options[id]
			var caption: String = choice.label
			if choice.has("tool"):
				caption += " · %d개 소모 / 보유 %d" % [choice.cost,session.exploration_tools.get(choice.tool,0)]
			var reason: String = Session.Curios.error(session,point,id)
			button(modal_content,caption,func(): details_popup.hide(); run_action(func(): return Session.Curios.resolve(session,point,id)),reason.is_empty())
			var hint := label(modal_content,reason if not reason.is_empty() else choice.get("warning","안전하게 회수합니다."),14)
			hint.custom_minimum_size.x = minf(300,size.x-32); hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(modal_content,"지나가기",func(): details_popup.hide())
	details_popup.popup_centered()

func show_relic() -> void:
	stop_navigation(); clear(modal_content)
	label(modal_content,Session.Objective.RELIC_LABEL,22)
	var description := label(modal_content,Session.Objective.RELIC_DESCRIPTION,17)
	description.custom_minimum_size.x = minf(300,size.x-32); description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label(modal_content,"회수 시 행동 1회 · 주변에 적이 없어야 합니다.",13)
	var reason: String = Session.Objective.error(session)
	button(modal_content,"유물을 회수한다",func(): details_popup.hide(); run_action(session.pickup_relic),reason.is_empty())
	var hint := label(modal_content,reason if not reason.is_empty() else "회수 후 입구 관문으로 돌아가면 임무가 완료됩니다.",14)
	hint.custom_minimum_size.x = minf(300,size.x-32); hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(modal_content,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func show_return() -> void:
	stop_navigation(); clear(modal_content)
	label(modal_content,"귀환 관문",22)
	var carrying: bool = Session.Objective.carrying(session)
	var body := label(modal_content,(("유물을 가지고 귀환합니다. 임무 성공 · 전리품 %d + 회수 보너스 %d" % [session.loot,Session.Objective.RECOVERY_BONUS]) if carrying else "유물 없이 귀환합니다. 중도 귀환 · 전리품 %d 정산." % session.loot)+"\n남은 보급품 환전: %d 자금 (무료 지급분 제외)" % session.provision_sale_value(),16)
	body.custom_minimum_size.x = minf(300,size.x-32); body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var reason: String = session.return_error()
	button(modal_content,"귀환 확정",func(): details_popup.hide(); run_action(session.return_home),reason.is_empty())
	if not reason.is_empty(): label(modal_content,reason,14)
	button(modal_content,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func show_goal() -> void:
	stop_navigation(); clear(modal_content)
	label(modal_content,"원정 목표",20)
	label(modal_content,session.objective_text(),16)
	button(modal_content,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func show_objective() -> void:
	stop_navigation(); clear(modal_content)
	modal_content.custom_minimum_size.y = 0
	button(modal_content,"원정 목표",show_goal)
	button(modal_content,"입구까지 이동",start_return_walk,session.phase == "BATTLE" and session.combat_enemies().is_empty())
	button(modal_content,"원정포기",confirm_abandon,session.phase == "BATTLE")
	details_popup.popup_centered()

# Ported from ../playtest/party_encounter_sandbox.gd product tactics menu.
func show_party_tactics() -> void:
	stop_navigation(); clear(modal_content)
	modal_content.custom_minimum_size.y = 0
	var available: bool = session.companions and session.phase == "BATTLE"
	for entry in [["ATTACK_TARGET","공격 대상 지정"],["RETREAT","후퇴"],["HOLD_POSITION","자리 지키기"],["STOP_ATTACK","공격 중지"],["FOLLOW","따라오기"]]:
		var command: String = entry[0]
		button(modal_content,entry[1],func():
			details_popup.hide()
			if command == "ATTACK_TARGET": command_targeting = true; notice = "공격 대상 선택"
			else: session.party_command = command; notice = entry[1]
			refresh(),available)
	for entry in [["NONE","자유"],["COLUMN","종대"],["LINE","횡대"],["WEDGE","쐐기"]]:
		var formation: String = entry[0]
		button(modal_content,"대형 · "+entry[1],func(): session.formation = formation; details_popup.hide(); refresh(),available)
	button(modal_content,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func start_return_walk() -> void:
	stop_navigation()
	if not session.floor_mode or session.phase != "BATTLE": return
	mode = ""; pending_item = -1; pending_attack = {}; reservation_actor = -1
	if not session.return_error().is_empty():
		details_popup.hide()
		if navigation.start(session,session.entry_position()):
			notice = "입구로 이동 중"
		else: notice = "입구 경로 없음"
	else:
		show_return(); return
	refresh()

func show_shop() -> void:
	stop_navigation(); clear(modal_content)
	label(modal_content,"출정 준비 · 자금 %d" % session.bank,20)
	var hint := label(modal_content,"마을에서 식량 %d·횃불 %d·치유 물약 1·붕대 1·열쇠·삽 1개를 무료 지급합니다. 귀환 시 남은 구매·발견 보급품은 구매가 합계의 10%%로 환전(소수점 버림)하며 이월하지 않습니다. 무료 지급분은 환전 제외. 이번 방문 구매분은 출정 전 전액 환불됩니다." % [Session.MIN_KIT.food,Session.MIN_KIT.torches],12)
	hint.custom_minimum_size.x = minf(300,size.x-32); hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var list := popup_list()
	for row in Session.SHOP:
		var line := HBoxContainer.new(); line.name = "ShopRow_"+str(row.id).replace(":","_"); line.add_theme_constant_override("separation",4); list.add_child(line)
		var caption := label(line,"%s  %d자금 · 보유 %d" % [row.name,row.price,session.stock(row.id)],14); caption.size_flags_horizontal = SIZE_EXPAND_FILL
		var minus := button(line,"−",func(): session.refund(row.id); refresh(); show_shop(),session.purchases.get(row.id,0) > 0)
		minus.size_flags_horizontal = SIZE_SHRINK_END; minus.custom_minimum_size = Vector2(48,44)
		var plus := button(line,"+",func(): session.buy(row.id); refresh(); show_shop(),session.bank >= row.price)
		plus.size_flags_horizontal = SIZE_SHRINK_END; plus.custom_minimum_size = Vector2(48,44)
	button(modal_content,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func confirm_abandon() -> void:
	var reason: String = session.abandon_error()
	modal("원정 포기","입구로 돌아가지 않고 원정을 포기합니다.\n\n임무 유물과 완료 보너스는 포기합니다.\n전리품·이능·성장·부상·기억은 유지됩니다.\n생존자 스트레스 +20. 남은 구매·발견 보급품은 10%로 환전하며 다음 출정에 이월하지 않습니다.\n\n"+reason)
	button(modal_content,"포기하고 돌아가기",func(): details_popup.hide(); run_action(session.abandon),reason.is_empty())

func build_result_card() -> void:
	var card := PanelContainer.new(); card.name = "ResultCard"; card.add_theme_stylebox_override("panel",CharacterUI.surface(Color("151c24"))); card.size_flags_vertical = SIZE_EXPAND_FILL; root_layout.add_child(card)
	var list := VBoxContainer.new(); list.add_theme_constant_override("separation",4); card.add_child(list)
	var r: Dictionary = session.result
	var titles := {"SUCCESS":"임무 성공","PARTIAL":"중도 귀환","DEFEAT":"패배","ABANDON":"원정 포기"}
	label(list,"원정 %d · %s" % [r.expedition,titles.get(r.reason,r.reason)],22)
	label(list,"유물 회수: %s" % ("반납 완료" if r.relic else "없음"),15)
	if r.reason in ["SUCCESS","PARTIAL","ABANDON"]:
		label(list,"정산: 전리품 %d%s → 자금 %d" % [r.loot," + 보너스 %d" % r.bonus if r.bonus > 0 else "",r.bank],15)
		label(list,"보급품 환전 +%d 포함 · 무료 지급분 제외" % r.provisions,13)
		if r.reason == "ABANDON": label(list,"임무 보상 없음 · 생존자 스트레스 +20",13)
		var items: Array = []
		for id in r.essences: items.append("%s ×%d" % [Session.Abilities.DEFINITIONS[id].item,r.essences[id]])
		label(list,"획득 아이템: "+(", ".join(items) if not items.is_empty() else "없음"),13)
		label(list,"습득 이능: "+(", ".join(r.abilities.map(func(id): return Session.Abilities.DEFINITIONS[id].name)) if not r.abilities.is_empty() else "없음"),13)
		label(list,"숙련: 레벨 +%d · 새 부위 손상 %d · 새 기억 %d" % [r.levels,r.injuries,r.memories],13)
	else:
		label(list,"이번 출정의 획득물을 잃고 출정 전 상태로 돌아갔습니다. 자금 %d" % r.bank,13)
	button(list,"정비하기",func(): run_action(session.refit))

func show_orders() -> void:
	stop_navigation()
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
	var text := RichTextLabel.new(); text.text = body; text.custom_minimum_size = Vector2(minf(300,size.x-32),210); text.size_flags_vertical = SIZE_EXPAND_FILL; modal_content.add_child(text)
	button(modal_content,"닫기",func(): details_popup.hide()); details_popup.popup_centered()

func open_management(index: int) -> void:
	match index:
		0:
			show_character(session.selected,"상태")
		1: show_supplies()
		2: show_tactics()
		3:
			var overview: String = "목표: %s\n1층 · 100×100 연속 지도\n발견한 타일: %d / 10000\n전리품: %d\n자금: %d\n\n" % [session.objective_text(),session.floor_state.explored.size(),session.loot,session.bank] if session.floor_mode else "목표: 보스 처치 후 귀환\n탐색: %d / 9개 방\n전리품: %d\n자금: %d\n\n" % [session.visited.size(),session.loot,session.bank]
			modal("원정",overview+("행동 한 번마다 적도 행동합니다. 자신을 누르면 대기. 미리보기는 시간을 쓰지 않습니다." if session.boss_trial else "전원 행동력 소진 시 적 차례."))
			if session.floor_mode and session.phase == "BATTLE": button(modal_content,"원정 목표 · 포기",func(): show_objective())
			elif session.phase in ["BATTLE","EXPLORE"]: button(modal_content,"귀환" if session.safe_management() else "철수 · 전리품 절반",func(): details_popup.hide(); run_action(session.retreat))
			if session.phase == "TOWN": button(modal_content,"요양 · 20 자금",func(): details_popup.hide(); run_action(session.rest_town),session.bank >= 20)

func show_character(index: int, tab: String = "상태") -> void:
	stop_navigation()
	tactics_actor = clampi(index,0,session.party.size()-1); character_tab = tab
	clear(modal_content)
	var list: VBoxContainer = CharacterUI.shell(self,tab)
	var actor: Dictionary = session.party[tactics_actor]
	match tab:
		"상태": CharacterUI.status(self,list,actor)
		"숙련": CharacterUI.mastery(self,list,actor)
		"이능": CharacterUI.abilities(self,list,actor)
		"성격": CharacterUI.personality(list,actor)
		"기억": CharacterUI.memories(self,list,actor)
	details_popup.popup_centered(Vector2i(size))

func show_tactics() -> void:
	show_character(tactics_actor,"이능")

func open_rule(index: int) -> void:
	tactics_expanded = index
	clear(item_detail)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(minf(300,size.x-32),minf(400,size.y-120))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; item_detail.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(list)
	build_skill_rules(list)
	item_popup.popup_centered()

func build_skill_rules(list: VBoxContainer) -> void:
	var actor: Dictionary = session.party[tactics_actor]
	label(list,"스킬 사용 순서",14)
	for index in range(actor.rules.size()):
		if index != tactics_expanded: continue
		var rule: Dictionary = actor.rules[index]
		var card := CharacterUI.card(list,"")
		var header := HBoxContainer.new(); card.add_child(header)
		label(header,Session.Rules.SKILLS[rule.skill].name,18)
		var enabled := CheckButton.new(); enabled.text = "자동"; enabled.button_pressed = rule.enabled; enabled.custom_minimum_size.y = 44; header.add_child(enabled)
		enabled.toggled.connect(func(value): change_tactic_rule(index,"enabled",value))
		var summary := label(card,Session.Rules.summary(rule),11); summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		button(ordering,"↑ 먼저 사용",func(): session.reorder_rule(tactics_actor,index,-1); refresh(); show_tactics(); open_rule(index-1),index > 0)
		button(ordering,"↓ 나중에 사용",func(): session.reorder_rule(tactics_actor,index,1); refresh(); show_tactics(); open_rule(index+1),index < actor.rules.size()-1)
	var basic := VBoxContainer.new(); list.add_child(basic)
	label(basic,"기본 행동",14)
	tactic_pick(basic,"일반 공격 대상",Session.Rules.BASIC_TARGETS,Session.Rules.TARGET_NAMES,actor.basic_target,change_basic_target)
	var hint := label(basic,"사용할 스킬이 없으면 공격 가능한 적을 공격합니다.\n공격할 수 없으면 안전하게 접근하거나 대기합니다.",11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; hint.custom_minimum_size.x = minf(290,size.x-32)
	label(list,"위험 칸 회피 우선 · 자동 OFF여도 직접 사용 가능",10)
	button(list,"행동방침 기본값 복원",func(): session.reset_rules(tactics_actor); refresh(); show_tactics())
	button(list,"완료",func(): item_popup.hide())

func change_basic_target(value: String) -> void:
	if session.set_basic_target(tactics_actor,value): refresh(); show_tactics(); open_rule(tactics_expanded)

func change_tactic_rule(index: int, field: String, value: Variant) -> void:
	if session.update_rule(tactics_actor,index,field,value): refresh(); show_tactics(); open_rule(index)

func tactic_pick(parent: Node, title: String, values: Array, names: Dictionary, current: String, changed: Callable) -> void:
	label(parent,title,12)
	var pick := OptionButton.new(); pick.custom_minimum_size = Vector2(280,44)
	for value in values: pick.add_item(names[value])
	pick.select(maxi(0,values.find(current))); parent.add_child(pick)
	pick.item_selected.connect(func(index): changed.call(values[index]))

func show_supplies() -> void:
	stop_navigation()
	clear(modal_content); label(modal_content,"공용 가방",18); build_inventory()

func inventory_rows() -> Array:
	var rows: Array = []
	for id in Session.Curios.content.tools:
		var tool: Dictionary = Session.Curios.content.tools[id]
		rows.append({"id":"tool:"+id,"label":tool.name,"quantity":session.exploration_tools.get(id,0),"category":"도구","description":tool.description+"\n발견한 조사물을 눌러 사용하세요.","icon":Art.navigation(3)})
	var descriptions := ["선택한 대원의 체력 20 회복. 출혈·충격을 완화하지만 부위 손상은 남습니다.","선택한 대원의 스트레스 25 감소.","파티 배고픔 30, 대상 스트레스 10 감소.","전투 중 나무 바닥에 불을 붙입니다. 사거리 4.","전투 중 대상 바닥을 적십니다. 사거리 4.","선택한 대원의 체력 10 회복. 출혈·충격을 완화하지만 부위 손상은 남습니다."]
	for i in range(6):
		if session.supplies[i] > 0: rows.append({"id":"supply:%d"%i,"label":Session.SUPPLY_NAMES[i],"quantity":session.supplies[i],"category":"소모품","slot":i,"description":descriptions[i],"icon":Art.item(i)})
	for id in Session.Abilities.DEFINITIONS:
		if session.essences.get(id,0) <= 0: continue
		var def: Dictionary = Session.Abilities.DEFINITIONS[id]
		rows.append({"id":id,"label":def.item,"quantity":session.essences[id],"category":"이능","description":"습득: "+def.name+"\n"+def.description,"icon":Art.item(3 if id == "BOMB" else 4 if id == "SHOCKWAVE" else 5)})
	if session.floor_mode and Session.Objective.carrying(session):
		rows.append({"id":"mission:relic","label":Session.Objective.RELIC_LABEL,"quantity":1,"category":"임무","description":Session.Objective.RELIC_DESCRIPTION,"icon":Art.navigation(3)})
	for entry in [["food","식량",session.food,"방 이동 시 자동 소모합니다."],["torch","횃불",session.torches,"탐험 중 불빛을 50 회복합니다."]]:
		if entry[2] > 0: rows.append({"id":entry[0],"label":entry[1],"quantity":entry[2],"category":"자원","description":entry[3],"icon":Art.navigation(3)})
	return rows

func build_inventory() -> void:
	label(modal_content,"아이템 선택 → 상세 정보 / 사용할 대원 선택",11)
	var filters := HBoxContainer.new(); modal_content.add_child(filters)
	for category in ["전체","소모품","이능","자원","도구","임무"]:
		var pick := button(filters,category,func(): inventory_filter = category; show_supplies())
		pick.toggle_mode = true; pick.button_pressed = category == inventory_filter
	var rows: Array = inventory_rows().filter(func(r): return inventory_filter == "전체" or r.category == inventory_filter)
	label(modal_content,"%s · %d종 보유" % [inventory_filter,rows.size()],12)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(minf(300,size.x-32),minf(300,size.y-310)); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; modal_content.add_child(scroll)
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
	var info := label(item_detail,row.description,12); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; info.custom_minimum_size.x = minf(290,size.x-32)
	if row.category == "이능":
		for i in range(session.party.size()):
			button(item_detail,session.party[i].name+"에게 먹이기",func(): item_popup.hide(); confirm_essence(i,id),session.safe_management() and session.party[i].hp > 0 and id not in session.party[i].learned_abilities)
	elif row.category == "소모품":
		if row.slot in [3,4]:
			button(item_detail,"사용 · 바닥 선택",func(): item_popup.hide(); details_popup.hide(); choose_item(row.slot),session.phase == "BATTLE")
		else:
			for i in range(session.party.size()):
				button(item_detail,session.party[i].name+"에게 사용",func(): item_popup.hide(); details_popup.hide(); run_action(func(): return session.use_supply(row.slot,Vector2i(-1,-1),i)),session.phase in ["BATTLE","EXPLORE"] and session.party[i].hp > 0)
	elif id == "torch":
		button(item_detail,"횃불 사용",func(): item_popup.hide(); details_popup.hide(); run_action(session.use_torch),(session.phase == "EXPLORE" or session.floor_mode and session.phase == "BATTLE" and session.safe_management()) and session.light < 100)
	button(item_detail,"닫기",func(): item_popup.hide()); item_popup.popup_centered(); item_popup.grab_focus()

func popup_list() -> VBoxContainer:
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(minf(300,size.x-32),minf(330,size.y-300)); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; modal_content.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(list)
	return list

func build_abilities() -> void:
	var actor: Dictionary = session.party[tactics_actor]
	label(modal_content,"습득 목록 유지 · 장착 2개 · 전투 밖에서 교체",11)
	var list := popup_list()
	for id in actor.learned_abilities:
		var card := CharacterUI.card(list,Session.Rules.SKILLS[id].name)
		CharacterUI.text(card,Session.Abilities.DEFINITIONS.get(id,{}).get("description","시작 기술"))
		var row := HBoxContainer.new(); card.add_child(row)
		for slot in range(2):
			button(row,"%d번 장착%s" % [slot+1," 중" if actor.equipped_abilities[slot] == id else ""],func(): session.equip_ability(tactics_actor,slot,id); refresh(); show_character(tactics_actor,"이능"),session.phase in ["TOWN","EXPLORE"] and actor.hp > 0 and id not in actor.equipped_abilities)
	button(list,"이능 전리품 가방",show_essences)
	build_skill_rules(list)

func show_essences() -> void:
	inventory_filter = "이능"; show_supplies()

func confirm_essence(index: int, id: String) -> void:
	var def: Dictionary = Session.Abilities.DEFINITIONS[id]
	modal("이능 습득 확인",session.party[index].name+"이 "+def.item+"을 먹습니다.\n\n습득: "+def.name+"\n"+def.description+"\n\n아이템 1개 소모 · 습득 후 장착 필요")
	button(modal_content,"먹고 습득",func():
		if session.consume_essence(index,id): refresh(); show_character(index,"이능")
		else: show_essences())
