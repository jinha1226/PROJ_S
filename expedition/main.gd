extends Control
const Session = preload("res://expedition/session.gd")
const Board = preload("res://expedition/board.gd")
const MapView = preload("res://expedition/map_view.gd")
const Art = preload("res://expedition/mobile_art.gd")
const FONT = preload("res://assets/fonts/NanumSquareR.ttf")
const SKILLS = [["PUSH","GUARD"],["ATTACK","GUARD"],["WATER","ELECTRIC"]]
const SKILL_NAMES = [["밀쳐내기","방어"],["강타","방어"],["물","방전"]]
var session = Session.new(randi())
var mode := ""
var pending_item := -1
var root_layout: VBoxContainer
var board
var minimap
var map_view
var map_popup: PopupPanel
var details_popup: PopupPanel
var modal_content: VBoxContainer
var notice := ""
var item_buttons: Array = []
var skill_buttons: Array = []
var portrait_buttons: Array = []

func _ready() -> void:
	var skin := Theme.new(); skin.default_font = FONT; skin.default_font_size = 12
	for state in ["normal","hover","pressed","focus","disabled"]:
		var box := StyleBoxFlat.new(); box.bg_color = Color("151c24") if state != "pressed" else Color("433c2c")
		box.border_color = Color("bba16b") if state in ["hover","pressed","focus"] else Color("50535a")
		box.set_border_width_all(1); box.set_corner_radius_all(4)
		box.content_margin_left = 3; box.content_margin_right = 3; skin.set_stylebox(state,"Button",box)
	theme = skin
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,8)
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
	label(location,"폐허 1층" if session.phase != "TOWN" else "변방의 여관",13)
	label(location,session.rooms[session.room].name if session.phase in ["EXPLORE","BATTLE"] else "원정 준비",12)
	if session.phase == "BATTLE": label(location,"%d턴 · AP %d" % [session.round_number,session.party[session.selected].ap],11)
	var resource := VBoxContainer.new(); resource.custom_minimum_size.x = 124; header.add_child(resource)
	button(resource,"식량 %d   횃불 %d" % [session.food,session.torches],show_supplies).custom_minimum_size.y = 28
	label(resource,"배고픔 %d%%" % session.hunger,10); gauge(resource,session.hunger,100,Color("d9904d"))
	label(resource,"불빛 %d%%" % session.light,10); gauge(resource,session.light,100,Color("e6bd62"))
	board = Board.new(); board.session = session; board.ui_font = FONT; board.cell_pressed.connect(on_cell); root_layout.add_child(board)
	if session.phase in ["TOWN","DEFEAT"]: button(root_layout,"출정" if session.phase == "TOWN" and not session.alive().is_empty() else "새 원정대",depart)
	var hint := label(root_layout,notice if not notice.is_empty() else "대원 선택 → 바닥 이동 · 적 공격 · 자신을 눌러 대기",10)
	hint.clip_text = true; hint.custom_minimum_size.y = 16
	var party_row := HBoxContainer.new(); party_row.add_theme_constant_override("separation",5); root_layout.add_child(party_row)
	for i in range(3):
		var actor: Dictionary = session.party[i]
		var column := VBoxContainer.new(); column.size_flags_horizontal = SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",3); party_row.add_child(column)
		var skills := HBoxContainer.new(); skills.add_theme_constant_override("separation",3); column.add_child(skills)
		for slot in range(2):
			var skill := icon_button(skills,Art.skill(i*2+slot),func(): choose_skill(i,slot),SKILL_NAMES[i][slot])
			skill.disabled = session.phase != "BATTLE" or actor.hp <= 0 or actor.ap <= 0; skill_buttons.append(skill)
		var portrait := button(column,"",func(): select_actor(i)); portrait.custom_minimum_size.y = 65; portrait_buttons.append(portrait)
		var face := TextureRect.new(); face.texture = Art.portrait(i); face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; face.mouse_filter = MOUSE_FILTER_IGNORE
		portrait.add_child(face); face.set_anchors_and_offsets_preset(PRESET_FULL_RECT); face.offset_bottom = -18; face.offset_top = 2; face.offset_left = 2; face.offset_right = -2
		var name_label := label(portrait,"%s  %d/%d" % [actor.name,actor.hp,actor.max_hp],11); name_label.position = Vector2(4,45)
		if i == session.selected:
			var gold := portrait.get_theme_stylebox("normal").duplicate(); gold.border_color = Color("e9c575"); gold.set_border_width_all(2); portrait.add_theme_stylebox_override("normal",gold)
		if actor.hp <= 0: portrait.modulate = Color("636369")
		gauge(column,actor.hp,actor.max_hp,Color("8ac77c")); gauge(column,actor.stress,200,Color("af80d0"))
	var shared := HBoxContainer.new(); shared.add_theme_constant_override("separation",4); root_layout.add_child(shared)
	for slot in range(6):
		var item := icon_button(shared,Art.item(slot),func(): choose_item(slot),Session.SUPPLY_NAMES[slot],str(session.supplies[slot]))
		item.disabled = session.phase not in ["BATTLE","EXPLORE"] or session.supplies[slot] == 0; item_buttons.append(item)
	var nav := HBoxContainer.new(); nav.add_theme_constant_override("separation",4); root_layout.add_child(nav)
	for index in range(4):
		var node := button(nav,"",func(): open_management(index)); node.custom_minimum_size.y = 49
		var icon := TextureRect.new(); icon.texture = Art.navigation(index); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.mouse_filter = MOUSE_FILTER_IGNORE
		node.add_child(icon); icon.set_anchors_and_offsets_preset(PRESET_FULL_RECT); icon.offset_bottom = -19; icon.offset_top = 3
		var title := label(node,["상태","가방","장비","원정"][index],12); title.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE); title.offset_top = -18; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func depart() -> void:
	if session.phase == "DEFEAT" or session.alive().is_empty(): session = Session.new(randi())
	run_action(session.depart)

func select_actor(index: int) -> void:
	session.selected = index; mode = ""; pending_item = -1; notice = session.party[index].name; refresh()

func run_action(callback: Callable) -> void:
	var accepted: bool = callback.call()
	notice = "" if accepted else "대상·거리·행동력·보유 수량을 확인하세요."
	if accepted:
		mode = ""; pending_item = -1
		if session.phase == "BATTLE" and session.alive().all(func(a): return a.ap <= 0): session.end_round()
	refresh()

func choose_skill(actor: int, slot: int) -> void:
	select_actor(actor); mode = SKILLS[actor][slot]
	if mode == "GUARD": run_action(func(): return session.act("GUARD",session.party[actor].pos)); return
	notice = "%s · 대상 칸 선택" % SKILL_NAMES[actor][slot]; refresh()

func choose_item(slot: int) -> void:
	mode = ""; pending_item = slot
	if slot in [3,4]: notice = Session.SUPPLY_NAMES[slot]+" · 대상 칸 선택"; refresh()
	else: run_action(func(): return session.use_supply(slot))

func on_cell(point: Vector2i) -> void:
	if pending_item >= 0: run_action(func(): return session.use_supply(pending_item,point)); return
	if not mode.is_empty(): run_action(func(): return session.act(mode,point)); return
	var actor: Dictionary = session.at(point)
	if not actor.is_empty() and not actor.enemy:
		if session.phase == "BATTLE" and actor.id == session.selected: run_action(func(): return session.act("WAIT",point))
		else: select_actor(actor.id)
		return
	if session.phase == "EXPLORE": run_action(func(): return session.interact_room(point))
	elif session.phase == "BATTLE": run_action(func(): return session.act("ATTACK" if not actor.is_empty() else "MOVE",point))

func show_map() -> void:
	if session.phase not in ["BATTLE","EXPLORE"]: return
	map_view.session = session; map_view.queue_redraw(); map_popup.popup_centered()

func on_room(id: int) -> void:
	if id == session.room: map_popup.hide(); return
	if session.can_travel(id): map_popup.hide(); run_action(func(): return session.travel(id))

func modal(title: String, body: String) -> void:
	clear(modal_content); label(modal_content,title,18)
	var text := RichTextLabel.new(); text.text = body; text.custom_minimum_size = Vector2(300,210); text.size_flags_vertical = SIZE_EXPAND_FILL; modal_content.add_child(text)
	button(modal_content,"닫기",func(): details_popup.hide()); details_popup.popup_centered()

func open_management(index: int) -> void:
	var actor: Dictionary = session.party[session.selected]
	match index:
		0:
			var body: String = actor.name+" · "+actor.profile.style_summary().label+"\n\n"+Session.Body.description(actor)+"\n\n기억\n"
			for memory in actor.memory.records: body += "%s · 강도 %d\n" % [memory.kind,memory.salience]
			modal("상태",body)
		1: show_supplies()
		2: modal("장비",actor.name+"\n\n부위 기능 반영 공격력: %d%%\n이동 비용: %d%%\n\n현재 공통 기본 공격을 사용합니다.\n장비 목록과 교체 기능은 준비 중입니다." % [actor.attack_factor,actor.move_factor])
		3:
			modal("원정","목표: 수문장 처치 후 귀환\n탐색: %d / 9개 방\n전리품: %d\n자금: %d\n\n전원 행동력 소진 시 적 차례. 선택한 대원을 다시 누르면 행동력 1을 사용해 대기합니다." % [session.visited.size(),session.loot,session.bank])
			if session.phase == "BATTLE": button(modal_content,"남은 행동을 마치고 적 차례",func(): details_popup.hide(); run_action(session.end_round))
			if session.phase in ["BATTLE","EXPLORE"]: button(modal_content,"철수 · 전리품 절반" if session.phase == "BATTLE" else "귀환",func(): details_popup.hide(); run_action(session.retreat))
			if session.phase == "TOWN": button(modal_content,"요양 · 20 자금",func(): details_popup.hide(); run_action(session.rest_town),session.bank >= 20)

func show_supplies() -> void:
	var body := "파티 공용 소모품\n선택한 대원: %s\n\n" % session.party[session.selected].name
	for i in range(6): body += "%s × %d\n" % [Session.SUPPLY_NAMES[i],session.supplies[i]]
	modal("가방",body+"\n아래 공용 슬롯에서 사용합니다. 전투 중 행동력 1 소비.")
	button(modal_content,"횃불 사용 · 밝기 +50",func(): details_popup.hide(); run_action(session.use_torch),session.phase == "EXPLORE" and session.torches > 0 and session.light < 100)
