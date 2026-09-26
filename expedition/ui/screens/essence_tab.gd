extends RefCounted
## The 영혼석 tab (§4): the slot grid, the bag with 흡수, what this member has
## absorbed, the role combos and element sets and, for a caster essence, its
## spell. A stone has no tiers: its base stats, headline effect and active are
## fixed. The text helpers are shared with the banners and the monster inspection.
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Folio = preload("res://expedition/ui/screens/character_folio.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const BuildSense = preload("res://expedition/ai/build_sense.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const COLUMNS := 5
const BORDER := Color("6d5b3f")
const ELEMENT_COLORS := {"fire":Color("d9643a"),"ice":Color("6fb7e0"),"air":Color("e0cf52"),"poison":Color("79b84a"),"will":Color("a57ad6")}
const SCHOOL_NAMES := {"fire":"화염","ice":"냉기","air":"전기","hex":"변이","summon":"소환"}

static func node_key(id: String) -> String:
	return Essences.canonical(id).replace("/","_").replace("@","_")

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

static func stat_line(id: String) -> String:
	var stats: Dictionary = Essences.stats(id)
	var parts: Array = []
	for key in StatSheet.KEYS:
		if int(stats.get(key,0)) != 0: parts.append("%s %+d%s" % [StatSheet.NAMES[key],int(stats[key]),"%" if key in ["speed","dodge"] else ""])
	return "기본 스탯 없음" if parts.is_empty() else " · ".join(parts)

## The stone's headline effect: its name and what it does.
static func effect_line(id: String) -> String:
	var effect: String = StoneEffects.effect_of(id)
	if effect.is_empty(): return "효과 없음"
	var row: Dictionary = StoneEffects.EFFECTS[effect]
	return "%s · %s" % [str(row.name),str(row.text)]

## The passive and the active, as the parts catalogue words them; a caster
## essence's active is its school's spell.
static func active_line(id: String) -> String:
	var school: String = str(Essences.school(id))
	if not school.is_empty(): return "주문 영혼석 · %s 계열 주문 하나를 액티브로 쓴다" % str(SCHOOL_NAMES.get(school,school))
	var def: Dictionary = Abilities.DEFINITIONS.get(Essences.base_of(id),{})
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
	Essences.normalize_actor(actor)
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

## Every role worn with its count and the next bracket, the bracket on and
## what it does; then the element sets that are on.
static func sets(list: VBoxContainer, actor: Dictionary) -> void:
	var box := card(list,"역할 조합 · 속성 세트","EssenceSets")
	var rows: Array = TagSets.active(actor)
	if rows.is_empty(): label(box,"장착한 영혼석 없음",13)
	for row in rows:
		if TagSets.ROLE_TEXT.has(str(row.tag)):
			var tally: String = "%d / %d" % [int(row.count),int(row.next)] if int(row.next) > 0 else "%d · 최고 구간" % int(row.count)
			label(box,"%s %s · %s" % [tag_name(str(row.tag)),tally,str(row.text) if int(row.level) > 0 else "구간 전"],13)
		else: label(box,"%s %d · %s" % [tag_name(str(row.tag)),int(row.level),str(row.text)],13)

	var builds: Dictionary = BuildSense.profile(actor)
	if not builds.is_empty(): label(box,"빌드 · "+" · ".join(builds.keys().map(func(f): return "%s %d%%" % [BuildSense.NAMES[int(f)],roundi(float(builds[f])*100)])),12)

static func group_key(id: String) -> String:
	return Essences.base_of(id)+("@"+Essences.variant_element(id) if not Essences.variant_element(id).is_empty() else "")

static func groups(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	var ordered: Array = ids.duplicate(); ordered.sort()
	for entry in ordered:
		var id: String = Essences.canonical(str(entry))
		if id.is_empty(): continue
		var key := group_key(id)
		if not result.has(key): result[key] = []
		result[key].append(id)
	return result

static func siblings(id: String) -> Array:
	var base := Essences.base_of(id)
	if not Essences.content.rows.get(base,{}).has("parts"): return [Essences.canonical(id)]
	var suffix: String = "@"+Essences.variant_element(id) if not Essences.variant_element(id).is_empty() else ""
	return Forms.PARTS.map(func(part): return base+"/"+part+suffix)

static func family_line(id: String) -> String:
	var effect: String = StoneEffects.effect_of(id)
	return " · ".join(StoneEffects.EFFECTS.get(effect,{}).get("families",[]).map(func(f): return str(BuildSense.NAMES.get(int(f),""))))

static func collection(actor: Dictionary, id: String) -> String:
	var count := 0
	for part in siblings(id):
		if Essences.absorbed(actor,str(part)): count += 1
	return "같은 종족 %d/3" % count if siblings(id).size() == 3 else ""

static func bag(ui, list: VBoxContainer, actor: Dictionary, editable: bool) -> void:
	ui.session.parts_bag = Essences.normalize_keys(ui.session.parts_bag,true)
	var index: int = ui.tactics_actor
	var box := card(list,"가방의 영혼석","EssenceBag")
	var ids: Array = ui.session.parts_bag.keys().filter(func(id): return int(ui.session.parts_bag[id]) > 0)
	for group in groups(ids):
		label(box,Essences.title(str(group))+" · "+collection(actor,str(group)),14)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation",4); box.add_child(row)
		for entry in siblings(str(group)):
			var id: String = str(entry)
			var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(info)
			var amount: int = int(ui.session.parts_bag.get(id,0))
			var known: bool = Essences.absorbed(actor,id)
			var part_index := Forms.PARTS.find(Essences.part_of(id))
			var hint: String = Forms.NAMES[Forms.FORMS[part_index]] if part_index >= 0 else ""
			label(info,Essences.title(id),12)
			label(info,"×%d" % amount if amount > 0 else hint,11)
			if known: label(info,"이미 흡수함",11)
			var absorb: Button = ui.button(info,"흡수",func(): absorb_press(ui,index,id),editable and not known and amount > 0)
			absorb.name = "EssenceAbsorb_"+node_key(id); absorb.tooltip_text = stat_line(id)+"\n"+effect_line(id)
			absorb.custom_minimum_size.x = 0; absorb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ids.is_empty(): label(box,"가방에 영혼석 없음",13)

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
		label(box,"%s%s" % [Essences.title(id)," · 장착" if id in actor.equipped_abilities else ""],15)
		if not tag_line(id).is_empty(): label(box,tag_line(id),12)
		label(box,stat_line(id),12)
		label(box,effect_line(id),12)
		label(box,family_line(id)+" · "+collection(actor,id),12)
		if not str(Essences.school(id)).is_empty():
			var spell_id: String = str(actor.get("essence_spells",{}).get(id,""))
			var spell: Dictionary = ui.session.CombatStats.content.spells.get(spell_id,{})
			label(box,"주문: %s" % str(spell.get("name","선택 안 함")),12)
			var pick: Button = ui.button(box,"주문 선택",func(): pick_spell(ui,index,id),editable)
			pick.name = "EssenceSpellPick_"+node_key(str(id))

## The absorbed essences this member is not wearing yet, one tap each, with
## what each would change: "공격력 12 → 16".
static func chooser(ui, slot: int) -> void:
	var index: int = ui.tactics_actor
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail); label(ui.item_detail,"영혼석 장착",20)
	var shown := 0
	for id in owned(actor):
		if id in actor.equipped_abilities: continue
		shown += 1
		var change: PackedStringArray = Folio.changes(ui.session,actor,slot,id)
		var caption: String = Essences.title(id) if change.is_empty() else "%s\n%s" % [Essences.title(id)," · ".join(change)]
		var pick: Button = ui.button(ui.item_detail,caption,func():
			if ui.session.equip_part(index,slot,id):
				ui.item_popup.hide(); ui.refresh(); ui.show_character(index,"영혼석"),Essences.can_manage(ui.session) and actor.hp > 0)
		pick.name = "EssencePick_"+node_key(str(id))
	if shown == 0: label(ui.item_detail,"흡수한 영혼석 없음",14)
	ui.button(ui.item_detail,"취소",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()

static func slot_detail(ui, slot: int, id: String) -> void:
	var index: int = ui.tactics_actor
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail)
	label(ui.item_detail,Essences.title(id),20)
	if not tag_line(id).is_empty(): label(ui.item_detail,tag_line(id),13)
	label(ui.item_detail,stat_line(id),13)
	label(ui.item_detail,effect_line(id),13).custom_minimum_size.x = minf(ui.popup_width(),ui.size.x-40)
	label(ui.item_detail,active_line(id),13).custom_minimum_size.x = minf(ui.popup_width(),ui.size.x-40)
	if not str(Essences.school(id)).is_empty():
		var pick: Button = ui.button(ui.item_detail,"주문 선택",func(): pick_spell(ui,index,id),Essences.can_manage(ui.session))
		pick.name = "EssenceSpellPick_"+node_key(id)
	var off: Button = ui.button(ui.item_detail,"해제",func():
		if ui.session.unequip_part(index,slot):
			ui.item_popup.hide(); ui.refresh(); ui.show_character(index,"영혼석"),Essences.can_manage(ui.session) and actor.hp > 0)
	off.name = "EssenceUnequip"
	ui.button(ui.item_detail,"닫기",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()

## The spells this caster essence opens up to the member's level; the chosen one is ticked.
static func pick_spell(ui, index: int, id: String) -> void:
	id = Essences.canonical(id)
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
