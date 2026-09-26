extends RefCounted
## The codex popup (codex spec §3): monsters, soul stones, fixed artefacts.
const Codex = preload("res://expedition/progression/codex.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const Keywords = preload("res://expedition/ui/screens/keyword_popup.gd")
const FAMILY_NAMES := {1:"출혈",2:"분쇄",3:"급소",4:"광폭",5:"수호",6:"사수",7:"원소",8:"저주",9:"독",10:"소환",11:"사령",12:"지원"}

static func name_for(key: String) -> String:
	return "CodexEntry_"+key.replace("/","_").replace(":","_")

static func data_of(ui) -> Dictionary:
	return ui.session.codex if ui.session != null and not ui.session.codex.is_empty() else Codex.read()

static func show(ui, tab: String = "monsters", focus: String = "", family: int = 0) -> void:
	ui.stop_navigation()
	var data := data_of(ui)
	ui.clear(ui.modal_content)
	ui.modal_content.custom_minimum_size = Vector2(ui.popup_width(),0)
	var box := VBoxContainer.new(); box.name = "CodexScreen"; ui.modal_content.add_child(box)
	var header := HBoxContainer.new(); box.add_child(header)
	var title = ui.label(header,"도감",18); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.button(header,"×",func(): ui.details_popup.hide()).custom_minimum_size.x = 44
	var done := Codex.completion(data)
	var line = ui.label(box,"몬스터 %d/%d · 영혼석 %d/%d · 장비 %d/%d" % [done.monsters[0],done.monsters[1],done.stones[0],done.stones[1],done.unrands[0],done.unrands[1]],12)
	line.name = "CodexCompletion"; line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tabs := HBoxContainer.new(); box.add_child(tabs)
	var names := {"monsters":"몬스터","stones":"영혼석"}
	if not Codex.unrand_ids().is_empty(): names["unrands"] = "장비"
	for id in names:
		var b = ui.button(tabs,str(names[id]),func(): show(ui,id)); b.name = "CodexTab_"+str(id)
		b.toggle_mode = true; b.button_pressed = id == tab
	var scroll := ScrollContainer.new(); scroll.name = "CodexScroll"
	scroll.custom_minimum_size = Vector2(ui.popup_width(),clampf(ui.get_viewport_rect().size.y-240,80,520))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; box.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	match tab:
		"monsters": monsters(ui,list,data,focus)
		"stones": stones(ui,list,data,family)
		"unrands": unrands(ui,list,data)
	ui.details_popup.popup_centered()
	# Flow containers settle their wrapping on the next frames. PopupPanel grows
	# for that first measurement but does not shrink on its own afterward.
	var tree = ui.get_tree()
	for _i in range(2): await tree.process_frame
	if not is_instance_valid(ui) or not is_instance_valid(box): return
	if box.get_parent() != ui.modal_content or not ui.details_popup.visible: return
	var viewport: Vector2 = ui.get_viewport_rect().size
	ui.details_popup.reset_size()
	ui.details_popup.popup_centered(Vector2i(roundi(ui.popup_width())+16,mini(roundi(ui.modal_content.get_combined_minimum_size().y)+16,roundi(viewport.y)-24)))

static func monsters(ui, list: VBoxContainer, data: Dictionary, focus: String) -> void:
	if not focus.is_empty():
		detail(ui,list,Codex.monster_entry(data,focus)); return
	var zone := -1; var grid: GridContainer = null
	for m in Codex.monster_list():
		if (not m.boss and int(m.zone) != zone) or (m.boss and (grid == null or grid.name != "Bosses")):
			zone = int(m.zone)
			ui.label(list,"보스" if m.boss else "구역 %d" % zone,14)
			grid = GridContainer.new(); grid.columns = 4; grid.name = "Bosses" if m.boss else "Zone%d" % zone; list.add_child(grid)
		var entry := Codex.monster_entry(data,str(m.key))
		var cell := VBoxContainer.new(); cell.name = name_for(str(m.key)); cell.set_meta("known",entry.known); grid.add_child(cell)
		var picture := TextureRect.new(); picture.custom_minimum_size = Vector2(64,64)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if not m.boss: picture.texture = Art.enemy_sprite(str(m.key))
		else:
			var kind: String = str(m.key).trim_prefix("boss:")
			picture.texture = Art.portrait_face(0) if kind == "fallen" else Art.enemy_sprite(str(Codex.BossAI.SPRITES.get(kind,"dcss_hobgoblin")))
		if not entry.known: picture.modulate = Color.BLACK
		cell.add_child(picture)
		var button = ui.button(cell,str(entry.get("name","???")),func(): show(ui,"monsters",str(m.key)),entry.known)
		button.clip_text = true; button.add_theme_font_size_override("font_size",10)

static func detail(ui, list: VBoxContainer, entry: Dictionary) -> void:
	var box := VBoxContainer.new(); box.name = "CodexDetail"; box.set_meta("key",entry.key); list.add_child(box)
	ui.button(box,"← 목록",func(): show(ui,"monsters"))
	ui.label(box,"%s · 구역 %d" % [str(entry.get("name","???")),int(entry.zone)],18)
	if not entry.known: return
	ui.label(box,str(entry.get("role","")),12)
	var active = ui.label(box,str(entry.get("active_text","")),12); active.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not str(entry.body_line).is_empty(): ui.label(box,str(entry.body_line),13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not str(entry.effect_text).is_empty(): ui.label(box,"대표 효과 · "+str(entry.effect_text),13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for part in entry.parts:
		ui.label(box,"%s — %s%s" % [str(part.name),str(Codex.FORM_HINT.get(part.form,"")),"  ✓" if part.found else ""],13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not entry.variants.is_empty(): ui.label(box,"변종 · "+" · ".join(entry.variants.map(func(v): return str(Codex.Essences.ELEMENTS.get(str(v),v)))),12)
	ui.label(box,"처치 %d" % int(entry.kills),12)

static func stones(ui, list: VBoxContainer, data: Dictionary, family: int) -> void:
	var chips := HFlowContainer.new(); list.add_child(chips)
	for f in FAMILY_NAMES:
		var chip = ui.button(chips,str(FAMILY_NAMES[f]),func(): show(ui,"stones","",0 if family == f else f)); chip.name = "CodexFilter_%d" % f
		chip.toggle_mode = true; chip.button_pressed = family == f
	var grids: Dictionary = {}
	for id in Codex.stone_list():
		var entry := Codex.stone_entry(data,str(id))
		if family > 0 and family not in entry.families: continue
		var base: String = Codex.Essences.base_of(str(id))
		if not grids.has(base):
			var species: String = str(Codex.Essences.row(str(id)).get("species",""))
			var heading = ui.label(list,str(Codex.Encounters.species(species).get("display_name",entry.name)) if entry.species_known or entry.found else "???",14)
			heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var grid := GridContainer.new(); grid.columns = 3
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_theme_constant_override("h_separation",4); list.add_child(grid); grids[base] = grid
		var row := VBoxContainer.new(); row.name = name_for(str(id)); grids[base].add_child(row)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size.x = (ui.popup_width()-16)/3.0
		var head = ui.label(row,str(entry.name)+("  ✓흡수" if entry.absorbed else ""),14)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if not entry.found:
			head.modulate = Color(1,1,1,0.45)
			if entry.species_known: ui.label(row,str(entry.hint),12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			continue
		var text = ui.label(row,str(entry.text),12); text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		Keywords.chips(ui,row,entry.keywords)
		ui.label(row," · ".join(entry.families.map(func(f): return str(FAMILY_NAMES.get(int(f),"")))),11).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

static func unrands(ui, list: VBoxContainer, data: Dictionary) -> void:
	for id in Codex.unrand_ids():
		var entry := Codex.unrand_entry(data,str(id))
		var row := VBoxContainer.new(); row.name = name_for(str(id)); list.add_child(row)
		var title = ui.label(row,"%s · %s" % [entry.slot,entry.name],14); title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if entry.found:
			var text = ui.label(row,str(entry.text),12); text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
