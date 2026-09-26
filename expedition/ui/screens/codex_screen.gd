extends RefCounted
## Soul stones by species, equipment, and arena-ready example builds.
const Codex = preload("res://expedition/progression/codex.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const Keywords = preload("res://expedition/ui/screens/keyword_popup.gd")
const Subtypes = preload("res://expedition/progression/subtypes.gd")
const Builds = preload("res://expedition/progression/example_builds.gd")
const Sets = preload("res://expedition/progression/tag_sets.gd")

static func name_for(key: String) -> String:
	return "CodexEntry_"+key.replace("/","_").replace(":","_")

static func data_of(ui) -> Dictionary:
	return ui.session.codex if ui.session != null and not ui.session.codex.is_empty() else Codex.read()

static func text(ui, parent: Control, value: String, size: int = 12) -> Label:
	var line = ui.label(parent,value,size)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line

static func show(ui, tab: String = "stones", focus: String = "", filter: String = "") -> void:
	if tab == "monsters": tab = "stones"
	if tab == "unrands": tab = "items"
	if tab not in ["stones","items","builds"]: tab = "stones"
	ui.stop_navigation()
	var data := data_of(ui)
	ui.clear(ui.modal_content)
	ui.modal_content.custom_minimum_size = Vector2(ui.popup_width(),0)
	var box := VBoxContainer.new(); box.name = "CodexScreen"; ui.modal_content.add_child(box)
	var header := HBoxContainer.new(); box.add_child(header)
	text(ui,header,"도감",18)
	ui.button(header,"×",func(): ui.details_popup.hide()).custom_minimum_size.x = 44
	var done := Codex.completion(data)
	var line := text(ui,box,"영혼석 %d/%d · 몬스터 %d/%d · 유물 %d/%d" % [done.stones[0],done.stones[1],done.monsters[0],done.monsters[1],done.unrands[0],done.unrands[1]])
	line.name = "CodexCompletion"
	var tabs := HBoxContainer.new(); box.add_child(tabs)
	var names := {"stones":"영혼석","items":"아이템","builds":"빌드"}
	for id in names:
		var b = ui.button(tabs,str(names[id]),func(): show(ui,id))
		b.name = "CodexTab_"+str(id); b.toggle_mode = true; b.button_pressed = id == tab
	var scroll := ScrollContainer.new(); scroll.name = "CodexScroll"
	scroll.custom_minimum_size = Vector2(ui.popup_width(),clampf(ui.get_viewport_rect().size.y-240,80,520))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; box.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	match tab:
		"stones":
			if not focus.is_empty(): monster_detail(ui,list,Codex.monster_entry(data,focus))
			else: stones(ui,list,data,filter)
		"items": items(ui,list,data)
		"builds":
			if not Builds.build(focus).is_empty(): build_detail(ui,list,data,Builds.build(focus))
			elif not Builds.party(focus).is_empty(): party_detail(ui,list,Builds.party(focus))
			else: build_list(ui,list)
	ui.details_popup.popup_centered()
	# Wrapping settles later; avoid reopening a popup closed or replaced meanwhile.
	var tree = ui.get_tree()
	for _i in range(2): await tree.process_frame
	if not is_instance_valid(ui) or not is_instance_valid(box): return
	if box.get_parent() != ui.modal_content or not ui.details_popup.visible: return
	var viewport: Vector2 = ui.get_viewport_rect().size
	ui.details_popup.reset_size()
	ui.details_popup.popup_centered(Vector2i(roundi(ui.popup_width())+16,mini(roundi(ui.modal_content.get_combined_minimum_size().y)+16,roundi(viewport.y)-24)))

static func monster_detail(ui, list: VBoxContainer, entry: Dictionary) -> void:
	var box := VBoxContainer.new(); box.name = "CodexMonsterDetail"; box.set_meta("key",entry.key); list.add_child(box)
	ui.button(box,"← 목록",func(): show(ui,"stones"))
	text(ui,box,"%s · 구역 %d" % [str(entry.get("name","???")),int(entry.zone)],18)
	if not entry.known: return
	text(ui,box,str(entry.get("role","")))
	text(ui,box,str(entry.get("active_text","")))
	if not str(entry.body_line).is_empty(): text(ui,box,str(entry.body_line),13)
	if not str(entry.effect_text).is_empty(): text(ui,box,"대표 효과 · "+str(entry.effect_text),13)
	for part in entry.parts:
		text(ui,box,"%s — %s%s" % [str(part.name),str(Codex.FORM_HINT.get(part.form,"")),"  ✓" if part.found else ""],13)
	if not entry.variants.is_empty(): text(ui,box,"변종 · "+" · ".join(entry.variants.map(func(v): return str(Codex.Essences.ELEMENTS.get(str(v),v)))))
	text(ui,box,"처치 %d" % int(entry.kills))

static func stones(ui, list: VBoxContainer, data: Dictionary, filter: String) -> void:
	var group: String = filter if Subtypes.GROUP_NAMES.has(filter) else str(Subtypes.GROUP.get(filter,""))
	var chips := HFlowContainer.new(); list.add_child(chips)
	for id in Subtypes.GROUP_NAMES:
		var chip = ui.button(chips,str(Subtypes.GROUP_NAMES[id]),func(): show(ui,"stones","","" if group == id else id))
		chip.name = "CodexGroup_"+str(id); chip.toggle_mode = true; chip.button_pressed = group == id
	if not group.is_empty():
		var subs := HFlowContainer.new(); list.add_child(subs)
		for id in Subtypes.IDS:
			if Subtypes.GROUP[id] != group: continue
			var chip = ui.button(subs,Subtypes.label(id),func(): show(ui,"stones","",group if filter == id else id))
			chip.name = "CodexFilter_"+str(id); chip.toggle_mode = true; chip.button_pressed = filter == id
	var zone := -1
	var all_stones := Codex.stone_list()
	var monsters := Codex.monster_list()
	monsters.sort_custom(func(a,b): return int(a.zone) < int(b.zone) if int(a.zone) != int(b.zone) else not a.boss if a.boss != b.boss else str(a.key) < str(b.key))
	for m in monsters:
		var species: String = str(m.key)
		var base := Codex.species_stone(species)
		if m.boss: base = {"boss:chief":"GOBLIN_CHIEF","boss:golem":"FURNACE_HEART","boss:eater":"SOUL_EATER"}.get(species,"")
		var ids: Array = all_stones.filter(func(id): return Codex.Essences.base_of(str(id)) == base)
		if not filter.is_empty():
			ids = ids.filter(func(id):
				var e := Codex.stone_entry(data,str(id))
				return e.subtype == filter if Subtypes.NAMES.has(filter) else e.group == filter)
			if ids.is_empty(): continue
		if int(m.zone) != zone:
			zone = int(m.zone); text(ui,list,"구역 %d" % zone,16)
		var e := Codex.monster_entry(data,species)
		var header := HBoxContainer.new(); header.name = "CodexSpecies_"+species.replace(":","_")
		header.set_meta("known",bool(e.known)); list.add_child(header)
		var picture := TextureRect.new(); picture.custom_minimum_size = Vector2(48,48)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture = Art.enemy_sprite(species) if not m.boss else Art.portrait_face(0) if species == "boss:fallen" else Art.enemy_sprite(str(Codex.BossAI.SPRITES.get(species.trim_prefix("boss:"),"dcss_hobgoblin")))
		if not e.known: picture.modulate = Color.BLACK
		header.add_child(picture)
		var pick = ui.button(header,"%s\n%s · 처치 %d" % [str(e.get("name","???")),str(e.get("role","")),int(e.get("kills",0))],func(): show(ui,"stones",species),e.known)
		pick.clip_text = true; pick.add_theme_font_size_override("font_size",13)
		for id in ids: stone_row(ui,list,Codex.stone_entry(data,str(id)))

static func stone_row(ui, list: VBoxContainer, entry: Dictionary) -> void:
	var row := VBoxContainer.new(); row.name = name_for(str(entry.key)); list.add_child(row)
	var head := text(ui,row,str(entry.name)+("  ✓흡수" if entry.absorbed else ""),14)
	if not entry.found:
		head.modulate = Color(1,1,1,0.45)
		if entry.species_known: text(ui,row,str(entry.hint))
		return
	text(ui,row,Subtypes.long_label(str(entry.subtype)),11)
	text(ui,row,str(entry.text))
	Keywords.chips(ui,row,entry.keywords)

static func items(ui, list: VBoxContainer, data: Dictionary) -> void:
	var names := {"weapons":"무기","offhands":"왼손","armours":"갑옷","rings":"반지","affixes":"발견한 옵션","unrands":"고정 유물"}
	for group in Codex.item_rows(data):
		var box := VBoxContainer.new(); box.name = "CodexItems_"+str(group.group); list.add_child(box)
		text(ui,box,str(names[group.group]),16)
		if group.rows.is_empty(): text(ui,box,"—")
		for e in group.rows:
			var row := VBoxContainer.new(); row.name = name_for(str(e.key)); box.add_child(row)
			text(ui,row,(str(e.get("slot",""))+" · " if e.has("slot") else "")+str(e.name),14)
			if not str(e.get("text","")).is_empty(): text(ui,row,str(e.text))
			if e.has("subtype"): text(ui,row,Subtypes.long_label(str(e.subtype)),11)
			if e.has("keywords"): Keywords.chips(ui,row,e.keywords)

static func build_list(ui, list: VBoxContainer) -> void:
	for b in Builds.data.builds:
		var box := VBoxContainer.new(); list.add_child(box)
		var pick = ui.button(box,str(b.name),func(): show(ui,"builds",str(b.id))); pick.name = "CodexBuild_"+str(b.id)
		text(ui,box,Subtypes.long_label(str(b.subtype))+" · "+str(Codex.Equipment.content.weapons[b.weapon].name))
		text(ui,box,str(b.flow[0]))
	text(ui,list,"3인 파티",16)
	for p in Builds.data.parties:
		var pick = ui.button(list,str(p.name),func(): show(ui,"builds",str(p.id))); pick.name = "CodexParty_"+str(p.id)

static func build_detail(ui, list: VBoxContainer, data: Dictionary, b: Dictionary) -> void:
	var box := VBoxContainer.new(); box.name = "CodexBuildDetail"; box.set_meta("key",b.id); list.add_child(box)
	ui.button(box,"← 목록",func(): show(ui,"builds"))
	text(ui,box,str(b.name),18); text(ui,box,Subtypes.long_label(str(b.subtype))+" · 레벨 %d" % int(b.level))
	var gear: PackedStringArray = []
	for slot in ["weapon","offhand","armour"]:
		if not str(b.get(slot,"")).is_empty(): gear.append(Codex.Equipment.title({"type":str(b[slot])}))
	text(ui,box," · ".join(gear))
	var counts: Dictionary = {}
	for id in b.stones:
		var info := Codex.Essences.row(str(id)); var sub := Subtypes.of(str(info.effect))
		var role: String = str(info.role); counts[role] = int(counts.get(role,0))+1
		var collected: bool = int(data.get("stones",{}).get(id,{}).get("found",0)) > 0
		var row := VBoxContainer.new(); row.name = "CodexBuildStone_"+str(id).replace("/","_"); box.add_child(row)
		text(ui,row,("✓ " if collected else "")+Codex.Essences.title(str(id))+" · "+Subtypes.label(sub),13)
		text(ui,row,str(Codex.effects.get(info.effect,{}).get("text","")))
		if not collected: row.modulate = Color(1,1,1,0.65)
	for line in b.flow: text(ui,box,str(line),13)
	for role in counts:
		var bracket: int = Sets.bracket_of(int(counts[role]))
		if bracket > 0: text(ui,box,"%s %d개 · %d구간 — %s" % [Subtypes.GROUP_NAMES.get(role,role),int(counts[role]),bracket,Sets.ROLE_TEXT.get(role,{}).get(bracket,"")])
	var test = ui.button(box,"전투 시험에서 해보기",func(): ui.show_arena_setup_with([str(b.id)])); test.name = "CodexTryBuild"

static func party_detail(ui, list: VBoxContainer, p: Dictionary) -> void:
	var box := VBoxContainer.new(); box.name = "CodexPartyDetail"; box.set_meta("key",p.id); list.add_child(box)
	ui.button(box,"← 목록",func(): show(ui,"builds")); text(ui,box,str(p.name),18)
	for id in p.members:
		var b := Builds.build(str(id))
		ui.button(box,str(b.name),func(): show(ui,"builds",str(id)))
		text(ui,box,Subtypes.long_label(str(b.subtype)))
	var test = ui.button(box,"파티로 전투 시험",func(): ui.show_arena_setup_with(p.members.duplicate())); test.name = "CodexTryParty"
