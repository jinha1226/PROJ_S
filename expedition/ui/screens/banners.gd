extends RefCounted
## The brief centre banner for boss introductions. They
## come from `session.events`, one at a time, and a tap on 확인 brings the next.
const KINDS := ["BOSS"]
const NODES := ["BossBanner"]

static func showing(ui) -> bool:
	return NODES.any(func(n): return ui.has_node(n))

## Pops the next banner-worthy event and shows it; false when nothing shows.
static func show_next(ui) -> bool:
	if ui.session == null or showing(ui): return false
	if is_instance_valid(ui.board) and ui.board.is_presenting(): return false
	while true:
		var at: int = ui.session.events.find_custom(func(e): return str(e.get("kind","")) in KINDS)
		if at < 0: return false
		var event: Dictionary = ui.session.events.pop_at(at)
		if str(event.kind) == "BOSS":
			boss_banner(ui,str(event.get("name","")),str(event.get("hint","")))
			return true
	return false

static func frame(ui, node_name: String, border: Color) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.name = node_name; panel.z_index = 50
	var skin := StyleBoxFlat.new(); skin.bg_color = Color(0.07,0.06,0.05,0.97); skin.border_color = border
	skin.set_border_width_all(4); skin.set_corner_radius_all(10); skin.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel",skin)
	panel.custom_minimum_size = Vector2(minf(340.0,ui.size.x-32.0),0)
	ui.add_child(panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation",8); panel.add_child(box)
	return box

static func line(box: VBoxContainer, value: String, font_size: int, color: Color = Color("e0d4bc")) -> Label:
	var label := Label.new(); label.text = value; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",font_size); label.add_theme_color_override("font_color",color)
	box.add_child(label); return label

## 확인 closes this banner and asks for the next; the panel leaves the tree at
## once so `showing` is false before the next one is built.
static func finish(ui, box: VBoxContainer) -> void:
	var panel: PanelContainer = box.get_parent()
	var ok := Button.new(); ok.name = "BannerOk"; ok.text = "확인"; ok.custom_minimum_size.y = 48
	ok.add_theme_font_size_override("font_size",20)
	ok.pressed.connect(func():
		ui.remove_child(panel); panel.queue_free(); show_next(ui))
	box.add_child(ok)
	panel.reset_size()
	var factor: float = minf(1.0,minf((ui.size.x-24.0)/panel.size.x,(ui.size.y-24.0)/panel.size.y))
	panel.scale = Vector2.ONE*factor
	panel.position = ((ui.size-panel.size*factor)/2).floor()

static func boss_banner(ui, boss_name: String, hint: String) -> void:
	var box := frame(ui,"BossBanner",Color("b0413e"))
	line(box,boss_name,30,Color("ffd9cf"))
	if not hint.is_empty(): line(box,hint,15)
	finish(ui,box)
