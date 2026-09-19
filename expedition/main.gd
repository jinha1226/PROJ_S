extends Control
const Session = preload("res://expedition/session.gd")
const Board = preload("res://expedition/board.gd")
const FONT = preload("res://assets/fonts/NanumSquareR.ttf")
var session = Session.new()
var mode := "MOVE"
var root: VBoxContainer
var status: Label
var party_bar: HBoxContainer
var center: HBoxContainer
var stage: VBoxContainer
var details: RichTextLabel
var actions: HFlowContainer
var logs: RichTextLabel
var board
var notice := ""

func _ready() -> void:
	var skin := Theme.new()
	skin.default_font = FONT; skin.default_font_size = 16
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("272c38"); normal.border_color = Color("505065")
	normal.set_border_width_all(1); normal.set_corner_radius_all(5)
	normal.content_margin_left = 14; normal.content_margin_right = 14
	normal.content_margin_top = 10; normal.content_margin_bottom = 10
	skin.set_stylebox("normal", "Button", normal)
	var hover := normal.duplicate(); hover.bg_color = Color("484556")
	skin.set_stylebox("hover", "Button", hover)
	skin.set_stylebox("pressed", "Button", hover)
	theme = skin
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	add_child(margin)
	root = VBoxContainer.new(); root.add_theme_constant_override("separation",12); margin.add_child(root)
	var title := Label.new(); title.text = "잿빛 원정  /  ASHEN EXPEDITION"
	title.add_theme_font_size_override("font_size",26); title.modulate = Color("e6cea0"); root.add_child(title)
	status = Label.new(); root.add_child(status)
	party_bar = HBoxContainer.new(); root.add_child(party_bar)
	center = HBoxContainer.new(); center.size_flags_vertical = SIZE_EXPAND_FILL; root.add_child(center)
	stage = VBoxContainer.new(); stage.size_flags_horizontal = SIZE_EXPAND_FILL; center.add_child(stage)
	details = RichTextLabel.new(); details.custom_minimum_size.x = 285; details.size_flags_vertical = SIZE_EXPAND_FILL
	center.add_child(details)
	actions = HFlowContainer.new(); root.add_child(actions)
	logs = RichTextLabel.new(); logs.custom_minimum_size.y = 115; root.add_child(logs)
	refresh()

func clear(node: Node) -> void:
	for child in node.get_children(): node.remove_child(child); child.queue_free()

func button(parent: Node, text: String, callback: Callable, enabled: bool = true) -> Button:
	var item := Button.new(); item.text = text; item.disabled = not enabled
	item.custom_minimum_size.y = 44
	item.pressed.connect(callback); parent.add_child(item)
	return item

func run_action(callback: Callable) -> void:
	var accepted: bool = callback.call()
	notice = "" if accepted else "지금은 실행할 수 없습니다. 위치·행동력·자원을 확인하세요."
	refresh()

func label(text: String, parent: Node = null) -> Label:
	var item := Label.new(); item.text = text
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(parent if parent != null else stage).add_child(item)
	return item

func refresh() -> void:
	status.text = "원정 %d   |   밝기 %d   ·   횃불 %d   ·   식량 %d   |   전리품 %d   ·   자금 %d" % [
		session.expedition_number,session.light,session.torches,session.food,session.loot,session.bank]
	clear(party_bar); clear(stage); clear(actions)
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var text := "%s%s  HP %d/%d\n스트레스 %d · %s%s" % ["◆ " if i == session.selected else "",actor.name,
			actor.hp,actor.max_hp,actor.stress,"사망" if actor.hp <= 0 else actor.condition,
			" · AP %d" % actor.ap if session.phase == "BATTLE" else ""]
		var select := button(party_bar,text,func(): session.selected = i; refresh())
		select.size_flags_horizontal = SIZE_EXPAND_FILL
	match session.phase:
		"TOWN":
			label("변방의 여관").add_theme_font_size_override("font_size",26)
			label("폐허 깊숙한 수문장을 처치하세요.\n\n방 사이의 복도를 지날 때 식량과 밝기가 줄어듭니다.\n야영, 우회, 유물 탐색을 선택하고 원정대를 무사히 데려오세요.\n\n사망한 동료는 돌아오지 않습니다. 기억과 부위 손상은 다음 원정에도 이어집니다.")
			button(actions,"출정",func(): run_action(session.depart),not session.alive().is_empty())
			button(actions,"요양 · 20 자금",func(): run_action(session.rest_town),session.bank >= 20)
		"BATTLE":
			label("%s  ·  라운드 %d  ·  %s" % [Session.ROOMS[session.room].name,session.round_number,mode])
			board = Board.new(); board.session = session; board.ui_font = FONT
			board.cell_pressed.connect(on_cell); stage.add_child(board)
			label("붉은 칸: 다음 적 공격 · 파란 밑줄: 젖음\n이동 2칸 / 행동마다 AP 1 · 붕괴 시 AP 1 · 밀치기로 적 예고 취소")
			for choice in [["MOVE","이동"],["ATTACK","공격"],["PUSH","밀치기"],["FIRE","점화"],["WATER","물"],["ELECTRIC","방전"]]:
				button(actions,("● " if mode == choice[0] else "")+choice[1],func(): mode = choice[0]; refresh())
			button(actions,"라운드 종료",func(): run_action(session.end_round))
		"EXPLORE", "EVENT":
			label(Session.ROOMS[session.room].name).add_theme_font_size_override("font_size",26)
			label("원정 경로  ·  [완료]는 방문한 방입니다.")
			for row in [[0],[1,2],[3],[4,5],[6]]:
				var line := HBoxContainer.new(); stage.add_child(line)
				for index in row:
					var room: Dictionary = Session.ROOMS[index]
					button(line,("[현재] " if index == session.room else "[완료] " if index in session.visited else "")+room.name,
						func(): run_action(func(): return session.travel(index)),
						session.phase == "EXPLORE" and index in Session.ROOMS[session.room].next)
			label("입구 → 병영 / 납골당 → 야영지 → 무기고 / 제단 → 수문장\n복도 이동: 생존 인원만큼 식량 소모, 밝기 -18. 선택한 경로는 되돌아갈 수 없습니다.")
			if session.phase == "EVENT":
				label("봉인된 유물입니다. 조사하면 전리품을 얻지만 선택한 대원이 함정에 다칠 수 있습니다.")
				button(actions,"선택한 대원으로 조사",func(): run_action(func(): return session.event_choice(true)))
				button(actions,"지나가기",func(): run_action(func(): return session.event_choice(false)))
			elif Session.ROOMS[session.room].kind == "camp":
				button(actions,"야영 · 식량 %d" % session.alive().size(),func(): run_action(session.camp),not session.used_camp and session.food >= session.alive().size())
			elif session.room == 6: label("수문장을 처치했습니다. 전리품을 가지고 귀환하세요.")
			button(actions,"횃불 사용",func(): run_action(session.use_torch),session.torches > 0 and session.light < 100)
		"DEFEAT": label("원정대 전멸\n모든 전리품을 잃었습니다. 새 원정대로 다시 시작할 수 있습니다.")
	if session.phase in ["EXPLORE","EVENT","BATTLE"]:
		button(actions,"전투 철수 · 전리품 절반" if session.phase == "BATTLE" else "귀환 · 전리품 정산",func(): run_action(session.retreat))
	if session.phase == "DEFEAT" or session.phase == "TOWN" and session.alive().is_empty():
		button(actions,"새 원정대",func(): session = Session.new(); refresh())
	show_details()
	var recent: Array = session.log_lines.slice(maxi(0,session.log_lines.size()-5))
	logs.text = (notice+"\n" if not notice.is_empty() else "") + "\n".join(recent)

func on_cell(point: Vector2i) -> void:
	var actor: Dictionary = session.at(point)
	if not actor.is_empty() and not actor.enemy:
		session.selected = actor.id; refresh(); return
	run_action(func(): return session.act(mode,point))

func show_details() -> void:
	var actor: Dictionary = session.party[session.selected]
	var text := "%s\n%s\n\n" % [actor.name,actor.profile.style_summary().label]
	text += Session.Body.description(actor)
	text += "\n\nHEXACO\n"
	for facet in Session.Hexaco.FACETS: text += "%s %d  " % [facet,actor.profile.value(facet)]
	text += "\n\n기억 (최대 8개)\n"
	var names := {"SELF_HARM":"다친 기억","ALLY_LOST":"동료를 잃음","AID_RECEIVED":"도움받음"}
	for memory in actor.memory.records:
		text += "%s · 강도 %d\n" % [names.get(memory.kind,memory.kind),memory.salience]
	if actor.memory.records.is_empty(): text += "아직 강렬한 기억이 없습니다.\n"
	text += "\n감수성(E)이 높으면 스트레스 증가가 큽니다.\n상처·상실의 기억은 이후 스트레스를 증폭합니다.\n야영 시 가장 온화한(A) 대원이 회복을 돕습니다.\n스트레스 150 이상: 행동력 1."
	details.text = text
