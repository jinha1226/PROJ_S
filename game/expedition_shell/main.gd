extends Control
## New scene root. This first milestone owns only a fixed visual room fixture.
const RoomView=preload("res://game/expedition_shell/room_view.gd")
const MEMBERS=["주인공 · 인간","나래 · 엘프","보린 · 드워프"]
var board
var detail:Label
var buttons:Array[Button]=[]

func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A missing font import must not prevent the scene script from loading.
	var ui_font=load("res://assets/fonts/Galmuri14.ttf")
	if ui_font is Font:
		theme=Theme.new();theme.default_font=ui_font;theme.default_font_size=14
	var background:=ColorRect.new();background.color=Color("#10171c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,12)
	add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);margin.add_child(column)
	var title:=Label.new();title.text="버려진 회랑";title.add_theme_font_size_override("font_size",24);column.add_child(title)
	var subtitle:=Label.new();subtitle.text="원정대 · 3명";subtitle.modulate=Color("#b8ada0");column.add_child(subtitle)
	board=RoomView.new();board.name="RoomBoard";board.size_flags_vertical=Control.SIZE_EXPAND_FILL
	board.custom_minimum_size=Vector2(0,220);column.add_child(board)
	board.member_selected.connect(_select_member)
	board.cell_selected.connect(func(cell:Vector2i):
		detail.text="선택한 칸 (%d, %d) · %s"%[cell.x+1,cell.y+1,"벽" if board.blocked(cell) else "바닥"])
	detail=Label.new();detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(detail)
	var party:=HBoxContainer.new();party.add_theme_constant_override("separation",6);column.add_child(party)
	for i in range(MEMBERS.size()):
		var button:=Button.new();button.text=MEMBERS[i];button.toggle_mode=true
		button.custom_minimum_size=Vector2(0,52);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.clip_text=true
		button.pressed.connect(func():_select_member(i));party.add_child(button);buttons.append(button)
	var note:=Label.new();note.text="동료나 바닥을 눌러 살펴보세요 · 전투 준비 중"
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.modulate=Color("#b8ada0");column.add_child(note)
	_select_member(0)

func _select_member(index:int)->void:
	board.select_member(index)
	detail.text=MEMBERS[index]+" · 대기 중"
	for i in range(buttons.size()):buttons[i].set_pressed_no_signal(i==index)
