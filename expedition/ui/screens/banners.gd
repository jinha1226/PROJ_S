extends RefCounted
## §4 알림: the big centre banners — a level gained, an essence found. They
## come from `session.events`, one at a time, and a tap on 확인 brings the next.
const Essences = preload("res://expedition/progression/essences.gd")
const EssenceTab = preload("res://expedition/ui/screens/essence_tab.gd")
const KINDS := ["LEVEL_UP","ESSENCE"]
const NODES := ["LevelUpBanner","EssenceBanner"]
const GOLD := Color("c6a34c")

static func showing(ui) -> bool:
	return NODES.any(func(n): return ui.has_node(n))

static func member(s, id: int) -> Dictionary:
	for actor in s.party:
		if int(actor.id) == id: return actor
	return {}

## Pops the next banner-worthy event and shows it; false when nothing shows.
static func show_next(ui) -> bool:
	if ui.session == null or showing(ui): return false
	if is_instance_valid(ui.board) and ui.board.is_presenting(): return false
	while true:
		var at: int = ui.session.events.find_custom(func(e): return str(e.get("kind","")) in KINDS)
		if at < 0: return false
		var event: Dictionary = ui.session.events.pop_at(at)
		if str(event.kind) == "LEVEL_UP":
			var actor: Dictionary = member(ui.session,int(event.get("actor",-1)))
			if actor.is_empty(): continue
			level_banner(ui,actor,int(event.get("level",1)))
			return true
		essence_banner(ui,str(event.get("id","")),bool(event.get("new",true)))
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

static func level_banner(ui, actor: Dictionary, level: int) -> void:
	var box := frame(ui,"LevelUpBanner",GOLD)
	line(box,"레벨 %d" % level,36,Color("ffe0a3"))
	line(box,str(actor.name),18)
	line(box,"HP +4 · MP +2",16)
	if level <= Essences.MAX_LEVEL: line(box,"이능 슬롯 +1",22,GOLD).name = "BannerSlotLine"
	finish(ui,box)

static func essence_banner(ui, id: String, is_new: bool) -> void:
	var box := frame(ui,"EssenceBanner",EssenceTab.border_for(id,GOLD))
	line(box,"새 이능" if is_new else "이능 획득",16,GOLD)
	line(box,Essences.title(id),28,Color("ffe0a3"))
	var tags: String = EssenceTab.tag_line(id)
	if not tags.is_empty(): line(box,tags,16)
	line(box,EssenceTab.stat_line(id,1),15)
	line(box,EssenceTab.active_line(id),14)
	var owners: Array = ui.session.party.filter(func(a): return Essences.tier(a,id) > 0 and Essences.tier(a,id) < Essences.MAX_TIER).map(func(a): return str(a.name))
	if not owners.is_empty(): line(box,"단계 상승 가능 · "+", ".join(owners),16,GOLD).name = "BannerUpgrade"
	finish(ui,box)
