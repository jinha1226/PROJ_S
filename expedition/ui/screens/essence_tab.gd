extends RefCounted
## The 영혼석 tab (§4): the slot grid, the bag with 흡수, what this member has
## absorbed, the sets that are on and, for a caster essence, its spell. The
## text helpers are shared with the banners and the monster inspection.
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const COLUMNS := 5
const BORDER := Color("6d5b3f")
const ELEMENT_COLORS := {"fire":Color("d9643a"),"ice":Color("6fb7e0"),"air":Color("e0cf52"),"poison":Color("79b84a"),"will":Color("a57ad6")}
const SCHOOL_NAMES := {"fire":"화염","ice":"냉기","air":"전기","hex":"변이","summon":"소환"}

## A variant essence ("<BASE>@<element>") wears its element's colour.
static func border_for(id: String, fallback: Color = BORDER) -> Color:
	if not id.contains("@"): return fallback
	return ELEMENT_COLORS.get(Essences.element(id),fallback)

static func tag_name(tag: String) -> String:
	return str(Essences.ROLES.get(tag,Essences.ELEMENTS.get(tag,tag)))

static func tag_line(id: String) -> String:
	var tags: Array = []
	if not str(Essences.role(id)).is_empty(): tags.append(tag_name(str(Essences.role(id))))
	if not str(Essences.element(id)).is_empty(): tags.append(tag_name(str(Essences.element(id))))
	return " · ".join(tags)

static func stat_line(id: String, tier: int) -> String:
	var stats: Dictionary = Essences.stats(id,clampi(tier,1,Essences.MAX_TIER))
	var parts: Array = []
	for key in StatSheet.KEYS:
		if int(stats.get(key,0)) != 0: parts.append("%s %+d" % [StatSheet.NAMES[key],int(stats[key])])
	return "기본 스탯 없음" if parts.is_empty() else " · ".join(parts)

## The passive and the active, as the parts catalogue words them; a caster
## essence's active is its school's spell.
static func active_line(id: String) -> String:
	var school: String = str(Essences.school(id))
	if not school.is_empty(): return "주문 영혼석 · %s 계열 주문 하나를 액티브로 쓴다" % str(SCHOOL_NAMES.get(school,school))
	var def: Dictionary = Abilities.DEFINITIONS.get(id.split("@")[0],{})
	return str(def.get("description",""))

static func surface(border: Color) -> StyleBoxFlat:
	var skin := StyleBoxFlat.new(); skin.bg_color = Color("1b1916"); skin.border_color = border
	skin.set_border_width_all(2); skin.set_content_margin_all(8)
	return skin

static func label(parent: Node, value: String, font_size: int = 14) -> Label:
	var line := Label.new(); line.text = value; line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL; line.add_theme_font_size_override("font_size",font_size)
	line.add_theme_color_override("font_color",Color("e0d4bc")); parent.add_child(line); return line

static func card(parent: Node, title: String, node_name: String) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.name = node_name; panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",surface(BORDER)); parent.add_child(panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation",6); panel.add_child(box)
	label(box,title,18).add_theme_color_override("font_color",Color("e5d0a4"))
	return box

static func owned(actor: Dictionary) -> Array:
	var ids: Array = actor.get("essences",{}).keys()
	ids.sort()
	return ids

static func build(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var editable: bool = Essences.can_manage(ui.session) and actor.hp > 0
	var slots := GridContainer.new(); slots.name = "EssenceSlots"; slots.columns = COLUMNS
	slots.add_theme_constant_override("h_separation",4); slots.add_theme_constant_override("v_separation",4)
	list.add_child(slots)
	var open: int = Essences.slot_count(actor)
	for slot in range(Essences.MAX_LEVEL): slot_cell(ui,slots,actor,slot,slot < open,editable)
	sets(list,actor)
	bag(ui,list,actor,editable)
	absorbed(ui,list,actor,editable)

static func slot_cell(ui, grid: GridContainer, actor: Dictionary, slot: int, open: bool, editable: bool) -> void:
	var id: String = str(actor.equipped_abilities[slot]) if open and slot < actor.equipped_abilities.size() else ""
	var caption: String = "Lv.%d" % (slot+1) if not open else ("+" if id.is_empty() else Essences.title(id))
	var cell: Button = ui.button(grid,caption,func(): pressed_slot(ui,slot),open and (editable or not id.is_empty()))
	cell.name = "EssenceSlot%d" % slot
	cell.custom_minimum_size = Vector2(66,66)
	cell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cell.add_theme_font_size_override("font_size",11)
	if not id.is_empty(): cell.add_theme_stylebox_override("normal",surface(border_for(id,Color("c6a34c"))))

static func pressed_slot(ui, slot: int) -> void:
	var actor: Dictionary = ui.session.party[ui.tactics_actor]
	var id: String = str(actor.equipped_abilities[slot]) if slot < actor.equipped_abilities.size() else ""
	if id.is_empty(): chooser(ui,slot)
	else: slot_detail(ui,slot,id)

static func sets(list: VBoxContainer, actor: Dictionary) -> void:
	var box := card(list,"켜진 세트","EssenceSets")
	var rows: Array = TagSets.active(actor)
	if rows.is_empty(): label(box,"켜진 세트 없음",13)
	for row in rows: label(box,"%s %d · %s" % [tag_name(str(row.tag)),int(row.level),str(row.text)],13)

static func bag(ui, list: VBoxContainer, actor: Dictionary, editable: bool) -> void:
	var index: int = ui.tactics_actor
	var box := card(list,"가방의 영혼석","EssenceBag")
	var ids: Array = ui.session.parts_bag.keys()
	ids.sort()
	var shown := 0
	for entry in ids:
		var id: String = str(entry)
		if int(ui.session.parts_bag[id]) <= 0 or not Essences.has(id): continue
		shown += 1
		var tier: int = Essences.tier(actor,id)
		var row := HBoxContainer.new(); box.add_child(row)
		var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(info)
		label(info,"%s ×%d" % [Essences.title(id),int(ui.session.parts_bag[id])],15)
		if not tag_line(id).is_empty(): label(info,tag_line(id),12)
		if tier >= Essences.MAX_TIER: label(info,"최고 단계",12)
		elif tier == 0: label(info,"새 영혼석 · "+stat_line(id,1),12)
		else: label(info,"단계 %d → %d · %s" % [tier,tier+1,stat_line(id,tier+1)],12)
		var absorb: Button = ui.button(row,"흡수",func(): absorb_press(ui,index,id),editable and tier < Essences.MAX_TIER)
		absorb.name = "EssenceAbsorb_"+id
	if shown == 0: label(box,"가방에 영혼석 없음",13)

static func absorb_press(ui, index: int, id: String) -> void:
	var reason: String = ui.session.absorb_essence(index,id)
	if not reason.is_empty(): ui.notice = reason
	ui.show_character(index,"영혼석")

static func absorbed(ui, list: VBoxContainer, actor: Dictionary, editable: bool) -> void:
	var index: int = ui.tactics_actor
	var box := card(list,"흡수한 영혼석","EssenceOwned")
	var ids: Array = owned(actor)
	if ids.is_empty(): label(box,"흡수한 영혼석 없음",13)
	for id in ids:
		var tier: int = Essences.tier(actor,id)
		label(box,"%s · %d단계%s" % [Essences.title(id),tier," · 장착" if id in actor.equipped_abilities else ""],15)
		if not tag_line(id).is_empty(): label(box,tag_line(id),12)
		label(box,stat_line(id,tier),12)
		if not str(Essences.school(id)).is_empty():
			var spell_id: String = str(actor.get("essence_spells",{}).get(id,""))
			var spell: Dictionary = ui.session.CombatStats.content.spells.get(spell_id,{})
			label(box,"주문: %s" % str(spell.get("name","선택 안 함")),12)
			var pick: Button = ui.button(box,"주문 선택",func(): pick_spell(ui,index,id),editable)
			pick.name = "EssenceSpellPick_"+str(id)

## The absorbed essences this member is not wearing yet, one tap each.
static func chooser(ui, slot: int) -> void:
	var index: int = ui.tactics_actor
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail); label(ui.item_detail,"영혼석 장착",20)
	var shown := 0
	for id in owned(actor):
		if id in actor.equipped_abilities: continue
		shown += 1
		var pick: Button = ui.button(ui.item_detail,"%s · %d단계" % [Essences.title(id),Essences.tier(actor,id)],func():
			if ui.session.equip_part(index,slot,id):
				ui.item_popup.hide(); ui.refresh(); ui.show_character(index,"영혼석"),Essences.can_manage(ui.session) and actor.hp > 0)
		pick.name = "EssencePick_"+str(id)
	if shown == 0: label(ui.item_detail,"흡수한 영혼석 없음",14)
	ui.button(ui.item_detail,"취소",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()

static func slot_detail(ui, slot: int, id: String) -> void:
	var index: int = ui.tactics_actor
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail)
	label(ui.item_detail,"%s · %d단계" % [Essences.title(id),Essences.tier(actor,id)],20)
	if not tag_line(id).is_empty(): label(ui.item_detail,tag_line(id),13)
	label(ui.item_detail,stat_line(id,Essences.tier(actor,id)),13)
	label(ui.item_detail,active_line(id),13).custom_minimum_size.x = ui.popup_width()
	if not str(Essences.school(id)).is_empty():
		var pick: Button = ui.button(ui.item_detail,"주문 선택",func(): pick_spell(ui,index,id),Essences.can_manage(ui.session))
		pick.name = "EssenceSpellPick_"+id
	var off: Button = ui.button(ui.item_detail,"해제",func():
		if ui.session.unequip_part(index,slot):
			ui.item_popup.hide(); ui.refresh(); ui.show_character(index,"영혼석"),Essences.can_manage(ui.session) and actor.hp > 0)
	off.name = "EssenceUnequip"
	ui.button(ui.item_detail,"닫기",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()

## The spells this caster essence's tier allows; the chosen one is ticked.
static func pick_spell(ui, index: int, id: String) -> void:
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail); label(ui.item_detail,"%s · 주문 선택" % Essences.title(id),18)
	var chosen: String = str(actor.get("essence_spells",{}).get(id,""))
	var catalogue: Dictionary = ui.session.CombatStats.content.spells
	for entry in Essences.spell_choices(actor,id):
		var spell_id: String = str(entry)
		var row: Dictionary = catalogue.get(spell_id,{})
		var caption: String = "%s%s · Lv%d · %dMP" % ["✓ " if spell_id == chosen else "",str(row.get("name",spell_id)),int(row.get("level",1)),int(row.get("mp",0))]
		var pick: Button = ui.button(ui.item_detail,caption,func():
			if ui.session.choose_essence_spell(index,id,spell_id):
				ui.item_popup.hide(); ui.show_character(index,"영혼석"),Essences.can_manage(ui.session))
		pick.name = "EssenceSpell_"+spell_id
		pick.icon = Art.spell_icon(spell_id); pick.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pick.add_theme_constant_override("icon_max_width",28)
	ui.button(ui.item_detail,"취소",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()
