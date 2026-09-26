extends RefCounted
const Equipment = preload("res://expedition/items/equipment.gd")
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
	var spacer := Control.new(); spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; box.add_child(spacer)
	ui.button(box,"가방",func(): Popups.show_supplies(ui))
	var end = ui.button(box,"야영 끝",func(): ui.run_action(session.end_camp)); end.name = "CampEnd"

static func show_gear(ui, index: int) -> void:
	var session = ui.session
	if session.phase != "CAMP" or index < 0 or index >= session.party.size(): return
	ui.clear(ui.modal_content)
	var list := Popups.popup_list(ui)
	var box := VBoxContainer.new(); box.name = "GearScreen"; list.add_child(box)
	var actor: Dictionary = session.party[index]
	ui.label(box,actor.name+" · 장비",20)
	for slot in Equipment.SLOTS:
		var equipped: Dictionary = Equipment.worn(actor)[slot]
		var name: String = Equipment.title(equipped)
		var row := HBoxContainer.new(); box.add_child(row)
		var caption = ui.label(row,str(Equipment.SLOT_NAMES[slot])+"  "+name,14)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.add_theme_color_override("font_color",Equipment.colour(equipped))
		ui.button(row,"해제",func():
			if session.unequip_gear(index,slot): show_gear(ui,index),not equipped.is_empty())
	var current: Dictionary = Session.CombatStats.stats(session,actor)
	for i in range(session.gear_bag.size()):
		var item: Dictionary = session.gear_bag[i]
		var slot: String = session.gear_slot(item)
		if slot.is_empty(): continue
		var slots: Array = ["ring1","ring2"] if slot == "ring1" else [slot]
		for target_slot in slots:
			var probe: Dictionary = actor.duplicate(true); Equipment.worn(probe)[target_slot] = item
			var next: Dictionary = Session.CombatStats.stats(session,probe)
			var choice = ui.button(box,"%s · %s" % [Equipment.title(item),Equipment.SLOT_NAMES[target_slot]],func():
				if session.equip_gear(index,item,target_slot): ui.refresh(); show_gear(ui,index))
			choice.clip_text = true
			choice.add_theme_color_override("font_color",Equipment.colour(item))
			choice.tooltip_text = Equipment.title(item)+"\n"+Equipment.description(item)+"\nΔ피해 %+d · Δ방어 %+d" % [int(next.damage)-int(current.damage),int(next.ac)-int(current.ac)]
			choice.name = "GearOption%d_%s" % [i,target_slot]; choice.custom_minimum_size.y = 44

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
