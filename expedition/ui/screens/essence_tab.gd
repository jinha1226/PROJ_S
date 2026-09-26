extends RefCounted
## The 영혼석 tab: slots, active combos and the absorbed collection.
## Absorption stays in inventory and permanently fills one of six slots.
## Casters may choose spells; shared text helpers also serve item inspection.
const Keywords = preload("res://expedition/ui/screens/keyword_popup.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const Summary = preload("res://expedition/ui/screens/essence_summary.gd")
const COLUMNS := 3
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

## Exact linked spell names also appear in monster inspection.
static func active_line(id: String) -> String:
	var spells := Essences.spell_catalog(id)
	if not spells.is_empty(): return "주문 · "+" · ".join(spells.map(func(spell): return str(Essences.combat.spells[spell].name)))
	var def: Dictionary = Abilities.DEFINITIONS.get(Essences.base_of(id),{})
	return str(def.get("description",""))

## Preview every linked spell before a permanent choice, including later unlocks.
static func spell_preview(parent: Node, id: String, actor: Dictionary = {}) -> void:
	var spells := Essences.spell_catalog(id)
	if spells.is_empty(): return
	label(parent,"주문",15)
	var chosen := str(actor.get("essence_spells",{}).get(Essences.canonical(id),""))
	for spell_id in spells:
		var spell: Dictionary = Essences.combat.spells[spell_id]
		var line := label(parent,"%s%s · Lv%d · MP %d\n%s" % ["✓ " if spell_id == chosen else "",str(spell.name),int(spell.level),int(spell.mp),str(spell.get("note",""))],13)
		line.name = "EssenceSpellPreview_"+str(spell_id)
		if not actor.is_empty() and int(spell.level) > Essences.spell_cap(actor): line.modulate = Color("9b9487")

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

static func build(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var slots := GridContainer.new(); slots.name = "EssenceSlots"; slots.columns = COLUMNS
	slots.add_theme_constant_override("h_separation",4); slots.add_theme_constant_override("v_separation",4)
	list.add_child(slots)
	var open: int = Essences.slot_count(actor)
	for slot in range(Essences.MAX_SLOTS): slot_cell(ui,slots,actor,slot,slot < open)
	sets(list,actor)
	summary(list,actor)

static func slot_cell(ui, grid: GridContainer, actor: Dictionary, slot: int, open: bool) -> void:
	var id: String = str(actor.equipped_abilities[slot]) if open and slot < actor.equipped_abilities.size() else ""
	var caption: String = "Lv.%d" % (slot+1) if not open else ("+" if id.is_empty() else Essences.title(id))
	var cell: Button = ui.button(grid,caption,func(): pressed_slot(ui,slot),open and not id.is_empty())
	if not id.is_empty() and id not in Essences.equipped(actor): cell.text += " · 봉인"
	cell.name = "EssenceSlot%d" % slot
	cell.custom_minimum_size = Vector2(0,72)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.clip_text = true
	if not id.is_empty():
		cell.icon = Art.part_icon(id)
		cell.add_theme_constant_override("icon_max_width",24)
	cell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cell.add_theme_font_size_override("font_size",11)
	if not id.is_empty(): cell.add_theme_stylebox_override("normal",surface(border_for(id,Color("c6a34c"))))

static func pressed_slot(ui, slot: int) -> void:
	var actor: Dictionary = ui.session.party[ui.tactics_actor]
	var id: String = str(actor.equipped_abilities[slot]) if slot < actor.equipped_abilities.size() else ""
	if not id.is_empty(): slot_detail(ui,slot,id)

## Only bonuses that are active now; progress thresholds live in details.
static func sets(list: VBoxContainer, actor: Dictionary) -> void:
	var rows: Array = TagSets.active(actor).filter(func(row): return int(row.level) > 0 and not str(row.text).is_empty())
	if rows.is_empty(): return
	var box := card(list,"조합 효과","EssenceSets")
	for row in rows:
		label(box,"%s · %s" % [tag_name(str(row.tag)),str(row.text)],13)

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

## All absorbed stones are permanent; the summary reads those used by combat.
static func summary(list: VBoxContainer, actor: Dictionary) -> void:
	if Essences.equipped(actor).is_empty(): return
	var box := card(list,"영혼석 효과","EssenceSummary")
	var fixed := Summary.stats(actor)
	if not fixed.is_empty(): label(box,fixed,13).name = "EssenceSummaryStats"
	var passive := Summary.passives(actor)
	if not passive.is_empty(): label(box,passive,13).name = "EssenceSummaryPassives"
	var names: Array = []
	for id in Abilities.held(actor):
		if not Abilities.usable_by(actor,str(id)): continue
		var entry: Dictionary = Abilities.definition(str(id))
		if not str(entry.get("name","")).is_empty(): names.append(str(entry.name))
	for spell_id in actor.get("prepared",[]):
		var spell: Dictionary = Essences.combat.spells.get(str(spell_id),{})
		if not str(spell.get("name","")).is_empty(): names.append(str(spell.name))
	if not names.is_empty(): label(box,"기술 · "+" · ".join(names),13)

static func slot_detail(ui, slot: int, id: String) -> void:
	var index: int = ui.tactics_actor
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail)
	label(ui.item_detail,Essences.title(id),20)
	if not tag_line(id).is_empty(): label(ui.item_detail,tag_line(id),13)
	label(ui.item_detail,stat_line(id),13)
	label(ui.item_detail,effect_line(id),13).custom_minimum_size.x = minf(ui.popup_width(),ui.size.x-40)
	Keywords.chips(ui,ui.item_detail,StoneEffects.EFFECTS.get(StoneEffects.effect_of(id),{}).get("keywords",[]))
	var extra: String = str(Essences.row(id).get("active",""))
	if Abilities.has(extra): label(ui.item_detail,str(Abilities.definition(extra).description),13)
	if not Essences.spell_catalog(id).is_empty(): spell_preview(ui.item_detail,id,actor)
	if Abilities.usable_by(actor,id):
		label(ui.item_detail,str(Abilities.definition(id).get("description","")),13).custom_minimum_size.x = minf(ui.popup_width(),ui.size.x-40)
	if not Essences.spell_catalog(id).is_empty():
		var pick: Button = ui.button(ui.item_detail,"주문 선택",func(): pick_spell(ui,index,id),Essences.can_manage(ui.session) and not Essences.spell_choices(actor,id).is_empty())
		pick.name = "EssenceSpellPick_"+node_key(id)
	ui.button(ui.item_detail,"닫기",func(): ui.item_popup.hide()); ui.popup_item_detail()

## The spells this caster essence opens up to the member's level; the chosen one is ticked.
static func pick_spell(ui, index: int, id: String) -> void:
	id = Essences.canonical(id)
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail); label(ui.item_detail,"%s · 주문 선택" % Essences.title(id),18)
	var chosen: String = str(actor.get("essence_spells",{}).get(id,""))
	var catalogue: Dictionary = ui.session.CombatStats.content.spells
	for entry in Essences.spell_catalog(id):
		var spell_id: String = str(entry)
		var row: Dictionary = catalogue.get(spell_id,{})
		var caption: String = "%s%s · Lv%d · %dMP" % ["✓ " if spell_id == chosen else "",str(row.get("name",spell_id)),int(row.get("level",1)),int(row.get("mp",0))]
		var pick: Button = ui.button(ui.item_detail,caption,func():
			if ui.session.choose_essence_spell(index,id,spell_id):
				ui.item_popup.hide(); ui.show_character(index,"영혼석"),Essences.can_manage(ui.session) and spell_id in Essences.spell_choices(actor,id))
		pick.name = "EssenceSpell_"+spell_id
		pick.icon = Art.spell_icon(spell_id); pick.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pick.add_theme_constant_override("icon_max_width",28)
		label(ui.item_detail,str(row.get("note","")),13)
	ui.button(ui.item_detail,"취소",func(): ui.item_popup.hide()); ui.popup_item_detail()
