extends Control

const BACKGROUND := Color("17233a")
const PANEL := Color("233653")
const PANEL_BORDER := Color("3e5a78")
const TEXT_MAIN := Color("f5f0dc")
const TEXT_MUTED := Color("a8bdd0")
const ACCENT := Color("70dfb4")
const BUTTON := Color("e69a55")
const TICK_SECONDS := 0.1

var _session: GameSession
var _tick_accumulator: float = 0.0
var _tick_label: Label
var _wood_label: Label
var _crystal_label: Label
var _population_label: Label
var _status_label: Label


func _ready() -> void:
	_session = App.game_session
	_build_interface()
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
	safe_margin.add_theme_constant_override("margin_left", 34)
	safe_margin.add_theme_constant_override("margin_right", 34)
	safe_margin.add_theme_constant_override("margin_top", 54)
	safe_margin.add_theme_constant_override("margin_bottom", 42)
	add_child(safe_margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	safe_margin.add_child(content)

	var title := _label("SLIME AUTOMATION", 42, TEXT_MAIN, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(title)
	var subtitle := _label("Teach once. Watch the workshop come alive.", 20, TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(subtitle)

	var counters := HBoxContainer.new()
	counters.add_theme_constant_override("separation", 12)
	content.add_child(counters)
	_wood_label = _counter(counters, "WOOD", "0")
	_crystal_label = _counter(counters, "CRYSTAL", "0")
	_population_label = _counter(counters, "SLIMES", "1 / 4")

	var mascot := SlimeMascot.new()
	mascot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(mascot)

	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, PANEL_BORDER, 24))
	content.add_child(status_panel)
	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 24)
	status_margin.add_theme_constant_override("margin_right", 24)
	status_margin.add_theme_constant_override("margin_top", 18)
	status_margin.add_theme_constant_override("margin_bottom", 18)
	status_panel.add_child(status_margin)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 8)
	status_margin.add_child(status_box)
	_status_label = _label("SYSTEM ONLINE", 22, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	status_box.add_child(_status_label)
	_tick_label = _label("Simulation tick: 0", 18, TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	status_box.add_child(_tick_label)
	status_box.add_child(_label("M0 foundation ready · Teaching arrives in M1", 16, TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	var advance_button := _button("ADVANCE 1 SEC")
	advance_button.pressed.connect(_on_advance_pressed)
	actions.add_child(advance_button)
	var reset_button := _button("RESET")
	reset_button.pressed.connect(_on_reset_pressed)
	actions.add_child(reset_button)

	content.add_child(_label("Deterministic 10 Hz simulation · Local state only", 14, TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))


func _refresh_state() -> void:
	if _session == null or _session.state == null:
		return
	var inventory: InventoryState = _session.state.inventories[&"town_storage"]
	_wood_label.text = str(inventory.amounts.get("wood", 0))
	_crystal_label.text = str(inventory.amounts.get("crystal", 0))
	var habitat: Dictionary = _session.state.facilities.get("habitat", {})
	var capacity := int(habitat.get("population_capacity", 4))
	_population_label.text = "%d / %d" % [_session.state.get_population(), capacity]
	_tick_label.text = "Simulation tick: %d" % _session.state.simulation_tick


func _on_advance_pressed() -> void:
	_session.advance_ticks(10)
	_status_label.text = "TIME ADVANCED"
	_refresh_state()


func _on_reset_pressed() -> void:
	_session = App.create_new_game()
	_tick_accumulator = 0.0
	_status_label.text = "NEW WORKSHOP READY"
	_refresh_state()


func _counter(parent: HBoxContainer, caption: String, value: String) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL, PANEL_BORDER, 18))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)
	box.add_child(_label(caption, 13, TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var value_label := _label(value, 24, TEXT_MAIN, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(value_label)
	return value_label


func _button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0.0, 72.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("2c2633"))
	button.add_theme_color_override("font_hover_color", Color("2c2633"))
	button.add_theme_stylebox_override("normal", _panel_style(BUTTON, Color("ffd19a"), 20))
	button.add_theme_stylebox_override("hover", _panel_style(BUTTON.lightened(0.08), Color("ffe2b7"), 20))
	button.add_theme_stylebox_override("pressed", _panel_style(BUTTON.darkened(0.12), Color("d27c43"), 20))
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
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style
