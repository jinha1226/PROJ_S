extends Control

const Core = preload("res://prototype/room_tactics_core.gd")
var core := Core.new()
var cells:Array[Button] = []
var header:Label
var party:Label
var intent_label:Label
var log_label:Label
var guard_button:Button
var end_button:Button

func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	header = Label.new(); root.add_child(header)
	party = Label.new(); party.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; root.add_child(party)
	intent_label = Label.new(); intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; root.add_child(intent_label)
	var board := GridContainer.new(); board.columns = Core.SIZE.x; root.add_child(board)
	for y in range(Core.SIZE.y):
		for x in range(Core.SIZE.x):
			var button := Button.new()
			button.custom_minimum_size = Vector2(54, 54)
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(_tap.bind(Vector2i(x,y)))
			board.add_child(button); cells.append(button)
	var actions := HBoxContainer.new(); root.add_child(actions)
	guard_button = Button.new(); guard_button.text = "방어"; guard_button.pressed.connect(_guard); actions.add_child(guard_button)
	end_button = Button.new(); end_button.text = "턴 종료"; end_button.pressed.connect(_end_turn); actions.add_child(end_button)
	var reset := Button.new(); reset.text = "방 다시 시작"; reset.pressed.connect(_reset); actions.add_child(reset)
	log_label = Label.new(); log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; root.add_child(log_label)
	refresh()

func _tap(cell:Vector2i) -> void:
	var actor := core.actor_at(cell)
	if not actor.is_empty() and actor.team == "HERO" and not actor.acted:
		core.select_hero(int(actor.id)); log_label.text = "%s 선택" % actor.name; refresh(); return
	var result := core.act_on(cell)
	log_label.text = _events_text(result.get("events", [])) if result.get("accepted", false) else "행동 불가: %s" % result.get("reason", "")
	refresh()

func _guard() -> void:
	var result := core.guard_selected()
	log_label.text = _events_text(result.get("events", [])) if result.get("accepted", false) else "방어 불가"
	refresh()

func _end_turn() -> void:
	log_label.text = _events_text(core.end_turn())
	refresh()

func _reset() -> void:
	core = Core.new(); log_label.text = ""; refresh()

func refresh() -> void:
	header.text = "ROOM TACTICS · TURN %d/%d · %s" % [mini(core.turn, Core.MAX_TURNS), Core.MAX_TURNS, core.terminal()]
	var rows:Array[String] = []
	for hero in core.living("HERO"):
		rows.append("%s  HP %d/%d  STRESS %d%s" % [hero.name, hero.hp, hero.max_hp, hero.stress,
			"  ✓" if hero.acted else "  ◀" if hero.id == core.selected_hero_id else ""])
	party.text = "\n".join(rows)
	var intents:Array[String] = []
	for intent in core.intents:
		var foe := core.actor_by_id(int(intent.enemy_id))
		var target := core.actor_by_id(int(intent.target_id))
		if intent.kind == "ATTACK": intents.append("%s → %s : HP -%d" % [foe.name, target.name, intent.amount])
		elif intent.kind == "STRESS": intents.append("%s → %s : STRESS +%d" % [foe.name, target.name, intent.amount])
		else: intents.append("%s → 이동 예정" % foe.name)
	intent_label.text = "적 의도\n" + "\n".join(intents)
	for y in range(Core.SIZE.y):
		for x in range(Core.SIZE.x):
			var cell := Vector2i(x,y)
			var button := cells[y*Core.SIZE.x+x]
			button.text = "■" if core.walls.has(cell) else "·"
			button.modulate = Color.WHITE
			var actor := core.actor_at(cell)
			if not actor.is_empty():
				if actor.team == "HERO":
					button.text = "%s\n%d" % [actor.name.left(1), actor.hp]
					if actor.id == core.selected_hero_id: button.text = "▶" + button.text
				else:
					var intent := core.intent_for_enemy(int(actor.id))
					var mark := "!"
					if intent.get("kind") == "STRESS": mark = "Ψ"
					elif intent.get("kind") == "MOVE": mark = "→"
					button.text = "%s%s\n%d" % [mark, actor.name.left(1), actor.hp]
	guard_button.disabled = not core.terminal().is_empty()
	end_button.disabled = not core.terminal().is_empty()

func _events_text(events:Array) -> String:
	var lines:Array[String] = []
	for event in events:
		match event.kind:
			"hit": lines.append("영웅 %d → 적 %d : %d 피해" % [event.actor,event.target,event.amount])
			"enemy_hit": lines.append("적 %d → 영웅 %d : %d 피해" % [event.actor,event.target,event.amount])
			"stress": lines.append("영웅 %d : 스트레스 +%d" % [event.target,event.amount])
			"guard": lines.append("영웅 %d 방어" % event.actor)
			"move": lines.append("영웅 %d 이동" % event.actor)
			"enemy_move": lines.append("적 %d 이동" % event.actor)
	return "\n".join(lines)
