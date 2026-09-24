extends RefCounted
## The camp screen and the popups it opens — gear, prepared spells, reading —
## plus the stairs popup that ends a floor. Moved out of main.gd.
const Session = preload("res://expedition/run/session.gd")
const Popups = preload("res://expedition/ui/screens/popups.gd")

static func build_camp_screen(ui) -> void:
	var session = ui.session
	var box := VBoxContainer.new(); box.name = "CampScreen"; box.size_flags_vertical = Control.SIZE_EXPAND_FILL; ui.root_layout.add_child(box)
	ui.label(box,"야영 · 식량 %d" % session.food,22)
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var card := VBoxContainer.new(); card.name = "CampMember%d" % i; box.add_child(card)
		ui.label(card,"%s  HP %d/%d  MP %d/%d" % [actor.name,actor.hp,actor.max_hp,actor.mp,actor.max_mp],15)
		if not session.manual_mode:
			ui.button(card,"태세 · %s" % actor.stance,func(): Popups.show_character(ui,i,"태세"))
			ui.button(card,"파츠",func(): Popups.show_character(ui,i,"파츠"))
		if session.manual_mode:
			ui.button(card,"장비",func(): show_gear(ui,i))
			ui.button(card,"주문 준비",func(): show_prepare(ui,i))
			ui.button(card,"주문 배우기",func(): show_learn(ui,i))
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
		ui.button(box,("✓ " if id in actor.prepared else "○ ")+str(spell.name),func():
			if session.prepare_spell(index,id,id not in actor.prepared): show_prepare(ui,index))
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
