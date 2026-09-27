extends PopupPanel
const Essences = preload("res://expedition/progression/essences.gd")
const Drop = preload("res://expedition/progression/stone_drop.gd")
const Tab = preload("res://expedition/ui/screens/essence_tab.gd")
const Banners = preload("res://expedition/ui/screens/banners.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
var ui
var source = null
var token := -1
var content: VBoxContainer
var scroll: ScrollContainer

func setup(owner_ui) -> void:
	ui = owner_ui; name = "StoneDropCard"
	transient = true; exclusive = true
	# Outside taps and Escape keep the loot, just like the explicit bag button.
	popup_hide.connect(on_closed)
	scroll = ScrollContainer.new(); scroll.name = "StoneDropScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	content = VBoxContainer.new(); content.name = "StoneDropContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",8); scroll.add_child(content)

func dismiss_preserving() -> void:
	source = null; token = -1; hide()

func update() -> void:
	if source != null and (source != ui.session or ui.mode_arena_setup or source.pending_stone_drops.is_empty() or int(source.pending_stone_drops[0].token) != token): dismiss_preserving()
	var s = ui.session
	if s == null or ui.mode_arena_setup or s.pending_stone_drops.is_empty(): return
	ui.stop_navigation(); s.auto.running = false
	if is_instance_valid(ui.board):
		if ui.board.is_presenting(): return
		if not ui.board.effects.is_empty() and ui.board.effect_time < 0.45+minf(ui.board.effects.size()-1,6)*ui.board.STAGGER: return
	if not s.pending_choice.is_empty() or ui.offer_popup.visible or Banners.showing(ui):
		if visible: dismiss_preserving()
		return
	if visible: return
	if ui.details_popup.visible or ui.item_popup.visible or ui.map_popup.visible or ui.log_popup.visible: return
	source = s; token = int(s.pending_stone_drops[0].token)
	var choice_token := token
	var stone: String = str(s.pending_stone_drops[0].stone)
	ui.clear(content)
	var heading := HBoxContainer.new(); content.add_child(heading)
	var icon := TextureRect.new(); icon.texture = Art.part_icon(stone)
	icon.custom_minimum_size = Vector2(48,48); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; heading.add_child(icon)
	Tab.label(heading,Essences.title(stone),18).name = "StoneDropTitle"
	if s.pending_stone_drops.size() > 1: Tab.label(content,"남은 영혼석 %d" % s.pending_stone_drops.size(),12)
	var hero: Dictionary = s.party[0] if not s.party.is_empty() else {}
	Tab.label(content,Tab.stat_line(stone,hero),14).name = "StoneDropStats"
	Tab.label(content,Tab.effect_line(stone,hero),14).name = "StoneDropEffect"
	var active := Tab.active_line(stone)
	if not s.MobileEffects.active(hero) and not active.is_empty(): Tab.label(content,active,13)
	for index in range(s.party.size()):
		var actor: Dictionary = s.party[index]
		var panel := PanelContainer.new(); panel.name = "StoneDropMember_%d" % index
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel",Tab.surface(Tab.BORDER)); content.add_child(panel)
		var box := VBoxContainer.new(); panel.add_child(box)
		var used: int = actor.get("equipped_abilities",[]).slice(0,Essences.slot_count(actor)).filter(func(id): return not str(id).is_empty()).size()
		Tab.label(box,"%s · %d/%d" % [actor.name,used,Essences.slot_count(actor)],15)
		var fit := Drop.fit(actor,stone)
		var line := Tab.label(box,str(fit.text),13); line.name = "StoneDropFit_%d" % index
		line.add_theme_color_override("font_color",Color("92c988") if fit.kind == "linked" else Color("dfb76c") if fit.kind in ["missing","duplicate"] else Color("a9a397"))
		if Essences.stats(stone,actor) != Essences.stats(stone,hero): Tab.label(box,Tab.stat_line(stone,actor),12)
		var reason := Drop.unavailable(actor,stone)
		if s.phase in ["DEFEAT","VICTORY"]: reason = "원정 종료"
		var pick: Button = ui.button(box,"흡수" if reason.is_empty() else reason,func(): choose(index,s,choice_token))
		pick.name = "StoneDropAbsorb_%d" % index; pick.disabled = not reason.is_empty()
	ui.button(content,"가방에 보관",func(): choose(-1,s,choice_token)).name = "StoneDropKeep"
	ui.button(content,"두고 가기",func(): choose(-2,s,choice_token)).name = "StoneDropLeave"
	var bounds: Vector2 = ui.get_viewport_rect().size.min(ui.size)
	var width := maxi(1,mini(340,int(bounds.x)-32))
	var height := maxi(1,mini(620,int(bounds.y)-48))
	scroll.custom_minimum_size = Vector2(width-16,height-16)
	scroll.scroll_vertical = 0
	popup_centered(Vector2i(width,height))

func choose(index: int, expected_source = null, expected_token: int = -1) -> void:
	if expected_source != null and (source != expected_source or token != expected_token): return
	if source == null or source != ui.session: dismiss_preserving(); return
	var reason: String = source.resolve_stone_drop(token,index)
	if not reason.is_empty():
		ui.notice = reason; return
	dismiss_preserving(); ui.refresh()

func on_closed() -> void:
	if source != null and source == ui.session and token >= 0:
		source.resolve_stone_drop(token,-1)
	source = null; token = -1
