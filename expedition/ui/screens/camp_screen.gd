extends RefCounted
## The camp screen and the popups it opens — gear, prepared spells, reading —
## plus the stairs popup that ends a floor. Moved out of main.gd.
const Session = preload("res://expedition/run/session.gd")
const Popups = preload("res://expedition/ui/screens/popups.gd")
const CharacterUI = preload("res://expedition/ui/screens/character_folio.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const CAMP_BACKGROUND = preload("res://assets/8bit/classic/camp-background.png")

static func build_camp_screen(ui) -> void:
	var session = ui.session
	var box := VBoxContainer.new(); box.name = "CampScreen"; box.size_flags_vertical = Control.SIZE_EXPAND_FILL; ui.root_layout.add_child(box)
	box.add_theme_constant_override("separation",5)
	var header := HBoxContainer.new(); box.add_child(header)
	var title = ui.label(header,"야영",22); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.label(header,"식량 %d" % session.food,15)
	var scene_art := TextureRect.new(); scene_art.name = "CampArt"
	scene_art.texture = CAMP_BACKGROUND; scene_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene_art.custom_minimum_size.y = minf(175,ui.get_viewport_rect().size.y*0.21)
	scene_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(scene_art)
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var frame := PanelContainer.new(); frame.add_theme_stylebox_override("panel",CharacterUI.surface(Color("211e1a")))
		box.add_child(frame)
		var card := VBoxContainer.new(); card.name = "CampMember%d" % i; frame.add_child(card)
		var name = ui.label(card,"%s  HP %d/%d  MP %d/%d  스트레스 %d" % [actor.name,actor.hp,actor.max_hp,actor.mp,actor.max_mp,actor.stress],13)
		name.clip_text = true
		ui.gauge(card,actor.hp,actor.max_hp,Color("bf5450"))
		var actions := HBoxContainer.new(); card.add_child(actions)
		if not session.manual_mode:
			ui.button(actions,"태세",func(): Popups.show_character(ui,i,"성격"))
			ui.button(actions,"파츠",func(): Popups.show_character(ui,i,"파츠"))
		if session.manual_mode:
			ui.button(actions,"장비",func(): show_gear(ui,i))
			ui.button(actions,"주문 준비",func(): show_prepare(ui,i))
			ui.button(actions,"주문 배우기",func(): show_learn(ui,i))
	var spacer := Control.new(); spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; box.add_child(spacer)
	ui.button(box,"가방",func(): Popups.show_supplies(ui))
	var end = ui.button(box,"야영 끝",func(): ui.run_action(session.end_camp)); end.name = "CampEnd"

static func show_gear(ui, index: int) -> void:
	var session = ui.session
	if session.phase != "CAMP" or index < 0 or index >= session.party.size(): return
	ui.clear(ui.modal_content)
	var box := VBoxContainer.new(); box.name = "GearScreen"; ui.modal_content.add_child(box)
	var actor: Dictionary = session.party[index]
	ui.label(box,actor.name+" · 장비",20)
	for slot in ["weapon","armour","shield","ring"]:
		var equipped: Dictionary = actor.gear[slot]
		var name: String = str(equipped.get("type","—"))
		var row := HBoxContainer.new(); box.add_child(row)
		ui.label(row,slot+"  "+name,14)
		ui.button(row,"해제",func():
			if session.unequip_gear(index,slot): show_gear(ui,index),not equipped.is_empty())
	var current: Dictionary = Session.CombatStats.stats(session,actor)
	for i in range(session.gear_bag.size()):
		var item: Dictionary = session.gear_bag[i]
		var slot: String = session.gear_slot(item)
		if slot.is_empty(): continue
		var probe: Dictionary = actor.duplicate(true); probe.gear[slot] = item
		var next: Dictionary = Session.CombatStats.stats(session,probe)
		var choice = ui.button(box,"%s  Δ피해 %+d  Δ시간 %+d  ΔAC %+d  ΔEV %+d" % [item.type,int(next.damage)-int(current.damage),int(next.delay)-int(current.delay),int(next.ac)-int(current.ac),int(next.ev)-int(current.ev)],func():
			if session.equip_gear(index,item): ui.refresh(); show_gear(ui,index))
		choice.icon = Art.equipment_icon(slot,str(item.get("type","")))
		choice.add_theme_constant_override("icon_max_width",28)
		choice.name = "GearOption%d" % i
		choice.custom_minimum_size.y = 44
	ui.button(box,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()

static func show_prepare(ui, index: int) -> void:
	var session = ui.session
	if session.phase != "CAMP" or index < 0 or index >= session.party.size(): return
	ui.clear(ui.modal_content)
	var box := VBoxContainer.new(); box.name = "PrepareScreen"; ui.modal_content.add_child(box)
	var actor: Dictionary = session.party[index]
	ui.label(box,actor.name+" · 주문",20)
	for id in actor.spells:
		var spell: Dictionary = Session.CombatStats.content.spells[id]
		var choice = ui.button(box,("✓ " if id in actor.prepared else "○ ")+str(spell.name),func():
			if session.prepare_spell(index,id,id not in actor.prepared): show_prepare(ui,index))
		choice.icon = Art.spell_icon(str(id)); choice.add_theme_constant_override("icon_max_width",28)
	ui.button(box,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()

## The camp's reading. Every spell the bag's books hold is listed; the ones
## this rank cannot take yet say why beside their name.
static func show_learn(ui, index: int) -> void:
	var session = ui.session
	if session.phase != "CAMP" or index < 0 or index >= session.party.size(): return
	ui.clear(ui.modal_content)
	var box := VBoxContainer.new(); box.name = "LearnList"; ui.modal_content.add_child(box)
	var actor: Dictionary = session.party[index]
	ui.label(box,actor.name+" · 주문 배우기",20)
	if actor.books.is_empty(): ui.label(box,"주문서 없음",14)
	for entry in actor.books:
		var book_id: String = str(entry)
		var row: Dictionary = Session.Spells.book(book_id)
		ui.label(box,str(row.get("name",book_id)),15)
		for spell_entry in Session.Spells.book_spells(book_id):
			var spell_id: String = str(spell_entry)
			var spell: Dictionary = Session.CombatStats.content.spells[spell_id]
			var reason: String = Session.Spells.learnable(session,actor,spell_id)
			var caption: String = "%s · Lv%d · %dMP" % [str(spell.name),int(spell.level),int(spell.mp)]
			if not reason.is_empty(): caption += "  (%s)" % reason
			var choice = ui.button(box,caption,func():
				if session.learn_spell(index,spell_id): show_learn(ui,index),reason.is_empty())
			choice.icon = Art.spell_icon(spell_id); choice.add_theme_constant_override("icon_max_width",28)
			choice.name = "Learn_"+spell_id
			choice.custom_minimum_size.y = 44
	ui.button(box,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()

static func show_stairs(ui) -> void:
	var session = ui.session
	ui.clear(ui.modal_content)
	var box := VBoxContainer.new(); box.name = "StairsPopup"; ui.modal_content.add_child(box)
	ui.label(box,"봉인됨" if session.stairs_sealed() else "%d층" % (session.depth+1),20)
	var descend_button = ui.button(box,"내려가기",func(): ui.details_popup.hide(); ui.run_action(session.descend),not session.stairs_sealed())
	descend_button.name = "Descend"
	ui.button(box,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()
