extends Control

const Core = preload("res://prototype/combat_core.gd")
var core = Core.new()
var cells:Array[Button] = []
var status:Label
var history:Label

func _ready() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	status = Label.new()
	column.add_child(status)
	var hint := Label.new()
	hint.text = "전투 코어 1단계\n상하좌우 인접 칸 터치 · 적을 누르면 공격\n방향키/WASD 이동 · Space 대기"
	column.add_child(hint)
	var board := GridContainer.new()
	board.columns = Core.SIZE.x
	column.add_child(board)
	for y in range(Core.SIZE.y):
		for x in range(Core.SIZE.x):
			var button := Button.new()
			button.custom_minimum_size = Vector2(44,44)
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(tap.bind(Vector2i(x,y)))
			board.add_child(button)
			cells.append(button)
	var wait_button := Button.new()
	wait_button.text = "대기"
	wait_button.pressed.connect(act.bind(Vector2i.ZERO))
	column.add_child(wait_button)
	var reset_button := Button.new()
	reset_button.text = "다시 시작"
	reset_button.pressed.connect(func():core = Core.new();history.text = "";refresh())
	column.add_child(reset_button)
	history = Label.new()
	column.add_child(history)
	refresh()

func tap(cell:Vector2i) -> void:act(cell-core.actors[0].position)

func act(delta:Vector2i) -> void:
	var result:Dictionary = core.submit(delta)
	var lines:Array[String] = []
	if not result.accepted:lines.append("이동 불가: " + str(result.reason))
	for event in result.get("events",[]):
		if event.kind == "hit":lines.append("%d → %d: 피해 %d"%[event.actor,event.target,event.amount])
		elif event.kind == "death":lines.append("%d 사망"%event.actor)
	history.text = "\n".join(lines)
	refresh()

func refresh() -> void:
	status.text = "시간 %d · HP %d · %s"%[core.time,core.actors[0].hp,core.terminal()]
	for y in range(Core.SIZE.y):
		for x in range(Core.SIZE.x):
			var cell := Vector2i(x,y)
			var actor:Dictionary = core.actor_at(cell)
			cells[y*Core.SIZE.x+x].text = "#" if core.walls.has(cell) else "."
			if not actor.is_empty():cells[y*Core.SIZE.x+x].text = "@" if actor.id == 1 else "E%d"%actor.hp

func _unhandled_key_input(event:InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():return
	for row in [["move_up",Vector2i.UP],["move_down",Vector2i.DOWN],
		["move_left",Vector2i.LEFT],["move_right",Vector2i.RIGHT],["wait",Vector2i.ZERO]]:
		if event.is_action_pressed(row[0]):act(row[1]);get_viewport().set_input_as_handled();return
