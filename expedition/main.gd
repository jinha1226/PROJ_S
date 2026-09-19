extends Control
const Session = preload("res://expedition/session.gd")
const Board = preload("res://expedition/board.gd")
const MapView = preload("res://expedition/map_view.gd")
const FONT = preload("res://assets/fonts/NanumSquareR.ttf")
var session = Session.new(randi())
var mode := "MOVE"
var status: Label
var party_bar: HBoxContainer
var stage: HBoxContainer
var actions: HFlowContainer
var logs: Label
var board
var map_view
var notice := ""
var details_popup: PopupPanel
var details: RichTextLabel

func _ready() -> void:
	var skin := Theme.new()
	skin.default_font = FONT; skin.default_font_size = 16
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("272e3c"); normal.border_color = Color("4c586b")
	normal.set_border_width_all(1); normal.set_corner_radius_all(5)
	normal.content_margin_left = 14; normal.content_margin_right = 14
	normal.content_margin_top = 10; normal.content_margin_bottom = 10
	skin.set_stylebox("normal","Button",normal)
	var hover := normal.duplicate(); hover.bg_color = Color("40504e")
	skin.set_stylebox("hover","Button",hover); skin.set_stylebox("pressed","Button",hover)
	theme = skin
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	add_child(margin)
	var layout := VBoxContainer.new(); layout.add_theme_constant_override("separation",12); margin.add_child(layout)
	var title := Label.new(); title.text = "잿빛 원정  /  폐허 탐험"
	title.add_theme_font_size_override("font_size",26); title.modulate = Color("e6cea0"); layout.add_child(title)
	status = Label.new(); layout.add_child(status)
	party_bar = HBoxContainer.new(); party_bar.add_theme_constant_override("separation",12); layout.add_child(party_bar)
	stage = HBoxContainer.new(); stage.add_theme_constant_override("separation",24)
	stage.size_flags_vertical = SIZE_EXPAND_FILL; layout.add_child(stage)
	actions = HFlowContainer.new(); layout.add_child(actions)
	logs = Label.new(); logs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	logs.custom_minimum_size.y = 45; logs.modulate = Color("a6b2c2"); layout.add_child(logs)
	details_popup = PopupPanel.new(); add_child(details_popup)
	var info := VBoxContainer.new(); info.custom_minimum_size = Vector2(430,500); details_popup.add_child(info)
	details = RichTextLabel.new(); details.size_flags_vertical = SIZE_EXPAND_FILL; info.add_child(details)
	button(info,"닫기",func(): details_popup.hide())
	refresh()

func clear(node: Node) -> void:
	for child in node.get_children(): node.remove_child(child); child.queue_free()

func button(parent: Node, text: String, callback: Callable, enabled: bool = true) -> Button:
	var item := Button.new(); item.text = text; item.disabled = not enabled
	item.custom_minimum_size.y = 44; item.pressed.connect(callback); parent.add_child(item)
	return item

func caption(parent: Node, text: String, font_size: int = 16) -> Label:
	var item := Label.new(); item.text = text; item.add_theme_font_size_override("font_size",font_size)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(item)
	return item

func run_action(callback: Callable) -> void:
	var accepted: bool = callback.call()
	notice = "" if accepted else "이동할 수 없는 통로이거나, 실행할 수 없는 행동입니다."
	refresh()

func gauge(parent: Node, value: int, maximum: int, color: Color) -> void:
	var bar := ProgressBar.new(); bar.max_value = maximum; bar.value = value
	bar.show_percentage = false; bar.custom_minimum_size.y = 6
	var fill := StyleBoxFlat.new(); fill.bg_color = color
	bar.add_theme_stylebox_override("fill",fill); parent.add_child(bar)

func refresh() -> void:
	status.text = "밝기 %d   ·   횃불 %d   ·   식량 %d      전리품 %d   /   자금 %d" % [session.light,session.torches,session.food,session.loot,session.bank]
	clear(party_bar); clear(stage); clear(actions)
	board = null; map_view = null
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var card := VBoxContainer.new(); card.size_flags_horizontal = SIZE_EXPAND_FILL; party_bar.add_child(card)
		button(card,"%s%s   %d/%d%s" % ["◆ " if i == session.selected else "",actor.name,actor.hp,actor.max_hp,
			"   AP %d" % actor.ap if session.phase == "BATTLE" else ""],func(): session.selected = i; refresh())
		gauge(card,actor.hp,actor.max_hp,Color("85bea4"))
		gauge(card,actor.stress,200,Color("b583a7"))
	if session.phase in ["EXPLORE","BATTLE"]:
		var left := VBoxContainer.new(); left.size_flags_horizontal = SIZE_EXPAND_FILL; stage.add_child(left)
		caption(left,"탐험 지도   3 × 3",22)
		map_view = MapView.new(); map_view.session = session; map_view.ui_font = FONT
		map_view.room_pressed.connect(on_room); left.add_child(map_view)
		caption(left,"통로로 연결된 방을 클릭하여 이동",14)
		var right := VBoxContainer.new(); right.size_flags_horizontal = SIZE_EXPAND_FILL; stage.add_child(right)
		caption(right,"%s   8 × 8%s" % [session.rooms[session.room].name," · %d턴" % session.round_number if session.phase == "BATTLE" else ""],22)
		board = Board.new(); board.session = session; board.ui_font = FONT
		board.cell_pressed.connect(on_cell); right.add_child(board)
		var row: Dictionary = session.rooms[session.room]
		var hint := "문을 누르거나 왼쪽 지도에서 다음 방을 선택하세요."
		if session.phase == "BATTLE":
			hint = "붉은 칸: 적 공격 예고   ·   선택: " + {"MOVE":"이동","ATTACK":"공격","PUSH":"밀치기","FIRE":"점화","WATER":"물","ELECTRIC":"방전"}[mode]
			for choice in [["MOVE","이동"],["ATTACK","공격"],["PUSH","밀치기"],["FIRE","점화"],["WATER","물"],["ELECTRIC","방전"]]:
				button(actions,("● " if mode == choice[0] else "")+choice[1],func(): mode = choice[0]; refresh())
			button(actions,"턴 종료",func(): run_action(session.end_round))
		else:
			if row.kind == "camp": hint = "샘의 힘을 이미 사용했습니다." if row.used else "방 안의 초록색 회복 샘을 클릭하세요."
			if row.kind == "loot": hint = "보물상자를 열었습니다." if row.used else "방 안의 보물상자를 클릭하세요. 함정에 주의하세요."
			if row.kind == "boss" and row.cleared: hint = "수문장을 처치했습니다. 귀환하거나 탐험을 계속하세요."
			button(actions,"횃불 +50",func(): run_action(session.use_torch),session.torches > 0 and session.light < 100)
		caption(right,hint,14)
		button(actions,"철수 · 전리품 절반" if session.phase == "BATTLE" else "귀환",func(): run_action(session.retreat))
	else:
		var panel := VBoxContainer.new(); panel.size_flags_horizontal = SIZE_EXPAND_FILL; stage.add_child(panel)
		caption(panel,"변방의 여관" if session.phase == "TOWN" else "원정대 전멸",30)
		caption(panel,"9개의 방, 무작위 통로. 수문장을 처치하고 돌아오세요.\n출정할 때마다 새로운 지도가 만들어집니다." if session.phase == "TOWN" else "새 원정대로 다시 시작할 수 있습니다.",18)
		if session.phase == "TOWN":
			button(actions,"출정",func(): run_action(session.depart),not session.alive().is_empty())
			button(actions,"요양 · 20 자금",func(): run_action(session.rest_town),session.bank >= 20)
		if session.phase == "DEFEAT" or session.alive().is_empty(): button(actions,"새 원정대",func(): session = Session.new(randi()); refresh())
	button(actions,"대원 상세",show_details)
	logs.text = notice if not notice.is_empty() else "\n".join(session.log_lines.slice(maxi(0,session.log_lines.size()-2)))

func on_room(id: int) -> void:
	if id == session.room: return
	run_action(func(): return session.travel(id))

func on_cell(point: Vector2i) -> void:
	var actor: Dictionary = session.at(point)
	if not actor.is_empty() and not actor.enemy:
		session.selected = actor.id; refresh(); return
	if session.phase == "EXPLORE": run_action(func(): return session.interact_room(point))
	else: run_action(func(): return session.act(mode,point))

func show_details() -> void:
	var actor: Dictionary = session.party[session.selected]
	var text := "%s\n%s\n\n" % [actor.name,actor.profile.style_summary().label]
	text += Session.Body.description(actor) + "\n\nHEXACO\n"
	for facet in Session.Hexaco.FACETS: text += "%s %d  " % [facet,actor.profile.value(facet)]
	text += "\n\n기억\n"
	var names := {"SELF_HARM":"다친 기억","ALLY_LOST":"동료를 잃음","AID_RECEIVED":"도움받음"}
	for memory in actor.memory.records: text += "%s · 강도 %d\n" % [names.get(memory.kind,memory.kind),memory.salience]
	if actor.memory.records.is_empty(): text += "아직 강렬한 기억이 없습니다."
	details.text = text
	details_popup.popup_centered()
