extends Control

const BACKGROUND := Color("17233a")
const PANEL := Color("233653")
const PANEL_BORDER := Color("3e5a78")
const TEXT_MAIN := Color("f5f0dc")
const TEXT_MUTED := Color("a8bdd0")
const ACCENT := Color("70dfb4")
const COACH := Color("f4a85f")
const TICK_SECONDS := 0.1

var _session: GameSession
var _tick_accumulator: float = 0.0
var _selected_slime_id: StringName = &""
var _wood_label: Label
var _crystal_label: Label
var _population_label: Label
var _instruction_label: Label
var _status_label: Label
var _detail_label: Label
var _progress_bar: ProgressBar
var _coach_button: Button
var _world: WorkshopWorld
var _feedback_text: String = ""
var _feedback_until_tick: int = -1


func _ready() -> void:
	_session = App.game_session
	_build_interface()
	_session.domain_event.connect(_on_domain_event)
	_refresh_state()


func _process(delta: float) -> void:
	_tick_accumulator += minf(delta, 0.25)
	var advanced := false
	while _tick_accumulator >= TICK_SECONDS:
		_tick_accumulator -= TICK_SECONDS
		_session.advance_ticks(1)
		advanced = true
	if advanced:
		_refresh_state()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var safe_margin := MarginContainer.new()
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_margin.add_theme_constant_override("margin_left", 24)
	safe_margin.add_theme_constant_override("margin_right", 24)
	safe_margin.add_theme_constant_override("margin_top", 32)
	safe_margin.add_theme_constant_override("margin_bottom", 26)
	add_child(safe_margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	safe_margin.add_child(content)

	content.add_child(_label("SLIME WORKSHOP", 34, TEXT_MAIN, HORIZONTAL_ALIGNMENT_CENTER))
	_instruction_label = _label("Tap Momo, then tap the forest", 18, Color("ffd27c"), HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(_instruction_label)

	var counters := HBoxContainer.new()
	counters.add_theme_constant_override("separation", 10)
	content.add_child(counters)
	_wood_label = _counter(counters, "WOOD", "0")
	_crystal_label = _counter(counters, "CRYSTAL", "0")
	_population_label = _counter(counters, "SLIMES", "1 / 4")

	_world = WorkshopWorld.new()
	_world.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_world.slime_pressed.connect(_on_slime_pressed)
	_world.forest_pressed.connect(_on_forest_pressed)
	content.add_child(_world)

	var context_panel := PanelContainer.new()
	context_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, PANEL_BORDER, 22))
	content.add_child(context_panel)
	var context_margin := MarginContainer.new()
	context_margin.add_theme_constant_override("margin_left", 20)
	context_margin.add_theme_constant_override("margin_right", 20)
	context_margin.add_theme_constant_override("margin_top", 14)
	context_margin.add_theme_constant_override("margin_bottom", 14)
	context_panel.add_child(context_margin)
	var context_box := VBoxContainer.new()
	context_box.add_theme_constant_override("separation", 7)
	context_margin.add_child(context_box)
	_status_label = _label("Momo is waiting", 21, TEXT_MAIN, HORIZONTAL_ALIGNMENT_CENTER)
	context_box.add_child(_status_label)
	_detail_label = _label("Select the slime to teach a job", 15, TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	context_box.add_child(_detail_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0.0, 18.0)
	_progress_bar.show_percentage = false
	_progress_bar.add_theme_stylebox_override("background", _panel_style(Color("15243a"), Color.TRANSPARENT, 8))
	_progress_bar.add_theme_stylebox_override("fill", _panel_style(ACCENT, Color.TRANSPARENT, 8))
	context_box.add_child(_progress_bar)
	_coach_button = _button("COACH • SPEED UP")
	_coach_button.pressed.connect(_on_coach_pressed)
	_coach_button.visible = false
	context_box.add_child(_coach_button)


func _refresh_state() -> void:
	if _session == null or _session.state == null:
		return
	var state := _session.state
	var inventory := state.inventories[&"town_storage"] as InventoryState
	_wood_label.text = str(inventory.amounts.get("wood", 0))
	_crystal_label.text = str(inventory.amounts.get("crystal", 0))
	var habitat := state.facilities[&"habitat"] as FacilityState
	_population_label.text = "%d / %d" % [state.get_population(), habitat.population_capacity]
	_world.set_game_state(state)
	_world.set_selection(_selected_slime_id)

	var slime := state.slimes.values()[0] as SlimeState
	var logging := slime.skill_memories.get(&"logging") as SkillProgress
	var runtime := slime.current_job
	_progress_bar.value = 0.0
	_coach_button.visible = false

	if logging == null:
		_status_label.text = "Momo is waiting"
		_detail_label.text = "Select Momo, then tap the forest"
		_instruction_label.text = "Tap Momo, then tap the forest"
		_apply_feedback()
		return

	var skill_definition := _session.content_registry.get_skill(&"logging")
	var next_xp := 0 if logging.level >= 5 else skill_definition.level_xp_requirements[logging.level - 1]
	var xp_text := "MAX" if logging.level >= 5 else "%d / %d XP" % [logging.xp, next_xp]
	_instruction_label.text = "Momo learned logging — coaching is optional"
	match runtime.phase:
		JobRuntime.IDLE:
			_status_label.text = "Choosing the next tree..."
		JobRuntime.MOVING:
			_status_label.text = "Momo is heading to the forest"
			_progress_bar.value = 100.0 * float(runtime.elapsed_ticks) / maxf(1.0, float(runtime.movement_ticks))
		JobRuntime.WORKING:
			var ratio := float(runtime.elapsed_ticks) / maxf(1.0, float(runtime.duration_ticks))
			_status_label.text = "Chopping wood... %d%%" % int(ratio * 100.0)
			_progress_bar.value = ratio * 100.0
			_coach_button.visible = not runtime.coaching_used
			if _coach_button.visible:
				var remaining := runtime.duration_ticks - runtime.elapsed_ticks
				var job := _session.content_registry.get_job(runtime.job_id)
				_coach_button.text = "PERFECT COACH!" if remaining <= job.perfect_window_ticks else "COACH • SPEED UP"
		JobRuntime.BLOCKED:
			_status_label.text = "Waiting for an open work spot"
		JobRuntime.BLOCKED_OUTPUT:
			_status_label.text = "Storage is full"
	var split_requirement := _session.content_registry.balance.division_requirement(slime.skill_memories.size())
	_detail_label.text = "Logging Lv.%d  •  %s  •  Split %d/%d" % [logging.level, xp_text, slime.division_meter, split_requirement]
	_apply_feedback()


func _on_slime_pressed(slime_id: StringName) -> void:
	_selected_slime_id = &"" if _selected_slime_id == slime_id else slime_id
	if _selected_slime_id == &"":
		_set_feedback("Selection cleared", 8)
	else:
		_set_feedback("Momo selected — tap the forest", 12)
	_refresh_state()


func _on_forest_pressed() -> void:
	if _selected_slime_id == &"":
		_set_feedback("Select Momo first", 12)
		_refresh_state()
		return
	var result := _session.teach(_selected_slime_id, &"forest", &"job_logging")
	if result.ok:
		_selected_slime_id = &""
		_set_feedback("Logging learned! Momo will work automatically", 20)
	else:
		_set_feedback(_friendly_error(result.code), 15)
	_refresh_state()


func _on_coach_pressed() -> void:
	var slime := _session.state.slimes.values()[0] as SlimeState
	var result := _session.coach(slime.id, slime.current_job.cycle_id)
	if not result.ok:
		_set_feedback(_friendly_error(result.code), 12)
	_refresh_state()


func _on_domain_event(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"job_cycle_completed":
			_set_feedback("+1 WOOD — Momo keeps going", 12)
		"coaching_resolved":
			var result_type := str(event.get("payload", {}).get("result_type", "NORMAL"))
			_set_feedback("PERFECT! Instant finish" if result_type == "PERFECT" else "Nice coaching! Work sped up", 14)
		"proficiency_changed":
			_set_feedback("LEVEL UP! Logging is faster now", 20)


func _set_feedback(message: String, duration_ticks: int) -> void:
	_feedback_text = message
	_feedback_until_tick = _session.state.simulation_tick + duration_ticks


func _apply_feedback() -> void:
	if not _feedback_text.is_empty() and _session.state.simulation_tick <= _feedback_until_tick:
		_status_label.text = _feedback_text


func _counter(parent: HBoxContainer, caption: String, value: String) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL, PANEL_BORDER, 16))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	margin.add_child(box)
	box.add_child(_label(caption, 12, TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var value_label := _label(value, 21, TEXT_MAIN, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(value_label)
	return value_label


func _button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0.0, 62.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("2c2633"))
	button.add_theme_color_override("font_hover_color", Color("2c2633"))
	button.add_theme_stylebox_override("normal", _panel_style(COACH, Color("ffd49c"), 18))
	button.add_theme_stylebox_override("hover", _panel_style(COACH.lightened(0.08), Color("ffe2b7"), 18))
	button.add_theme_stylebox_override("pressed", _panel_style(COACH.darkened(0.12), Color("d27c43"), 18))
	return button


static func _label(text: String, font_size: int, color: Color, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func _panel_style(color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(2 if border_color.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	return style


static func _friendly_error(code: StringName) -> String:
	match code:
		&"FACILITY_FULL": return "The forest work spot is full"
		&"COACHING_ALREADY_USED": return "Already coached this job"
		&"NOT_WORKING": return "Wait until Momo starts working"
		_: return "That action is not available yet"
