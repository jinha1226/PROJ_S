extends RefCounted
const Essences = preload("res://expedition/progression/essences.gd")
const Mobile = preload("res://expedition/progression/attack_wait.gd")
const Icons = preload("res://expedition/art/soulstone_icons.gd")
const Tab = preload("res://expedition/ui/screens/essence_tab.gd")

static func build(ui) -> void:
	var s = ui.session
	var box := VBoxContainer.new(); box.name = "RestScreen"
	box.add_theme_constant_override("separation",8); ui.root_layout.add_child(box)
	ui.label(box,"휴식처 · %d층" % s.depth,21)
	var members := HBoxContainer.new(); box.add_child(members)
	for i in range(s.party.size()):
		var actor: Dictionary = s.party[i]
		var select = ui.button(members,str(actor.name),func(): ui.rest_actor = i; ui.refresh())
		select.name = "RestMember%d" % i; select.toggle_mode = true; select.button_pressed = ui.rest_actor == i
	ui.rest_actor = clampi(ui.rest_actor,0,s.party.size()-1)
	var actor: Dictionary = s.party[ui.rest_actor]
	ui.label(box,"%s  HP %d/%d  스트레스 %d" % [actor.name,actor.hp,actor.max_hp,actor.stress],13)
	var slots := GridContainer.new(); slots.name = "RestSlots"; slots.columns = 3; box.add_child(slots)
	for slot in range(Essences.MAX_SLOTS):
		var unlocked: bool = slot < Essences.slot_count(actor)
		var old_id: String = str(actor.get("equipped_abilities",[])[slot]) if unlocked and slot < actor.get("equipped_abilities",[]).size() else ""
		var caption: String = "잠김" if not unlocked else "+" if old_id.is_empty() else Essences.title(old_id)
		var btn = ui.button(slots,caption,func(): choose_slot(ui,slot),unlocked)
		btn.name = "RestSlot%d" % slot; btn.custom_minimum_size = Vector2(0,66); btn.clip_text = true
		if not old_id.is_empty(): btn.icon = Icons.stone_icon(old_id) if Mobile.active(actor) else null
	ui.label(box,"가방 %d/%d" % [Essences.bag_count(s),Essences.bag_limit(s)],15)
	var bag := HFlowContainer.new(); bag.name = "RestBag"; box.add_child(bag)
	for id in s.parts_bag:
		if int(s.parts_bag[id]) <= 0: continue
		var pick = ui.button(bag,"%s ×%d" % [Essences.title(str(id)),int(s.parts_bag[id])],func(): ui.rest_selected_stone = str(id); ui.refresh())
		pick.name = "RestBag_"+Tab.node_key(str(id)); pick.icon = Icons.stone_icon(str(id)) if Mobile.active(actor) else null
		pick.add_theme_constant_override("icon_max_width",24)
		pick.toggle_mode = true; pick.button_pressed = ui.rest_selected_stone == str(id)
	if not ui.rest_selected_stone.is_empty(): ui.label(box,Tab.effect_line(ui.rest_selected_stone,actor),13)
	var spacer := Control.new(); spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; box.add_child(spacer)
	var actions := HBoxContainer.new(); box.add_child(actions)
	ui.button(actions,"도감",func(): ui.show_codex()).name = "RestCodex"
	ui.button(actions,"다음 구역으로",func(): ui.rest_selected_stone = ""; ui.run_action(s.leave_rest)).name = "RestLeave"

static func choose_slot(ui, slot: int) -> void:
	var id: String = ui.rest_selected_stone
	if id.is_empty(): return
	var s = ui.session
	var actor: Dictionary = s.party[ui.rest_actor]
	var old_id: String = str(actor.get("equipped_abilities",[])[slot]) if slot < actor.get("equipped_abilities",[]).size() else ""
	if old_id.is_empty():
		var reason: String = s.absorb_essence(ui.rest_actor,id)
		if not reason.is_empty(): ui.notice = reason
		else: ui.rest_selected_stone = ""; ui.refresh()
		return
	if Essences.colour(old_id) == Essences.colour(id):
		var reason: String = s.swap_stone(ui.rest_actor,slot,id)
		if not reason.is_empty(): ui.notice = reason
		else: ui.rest_selected_stone = ""; ui.refresh()
		return
	ui.clear(ui.modal_content)
	ui.label(ui.modal_content,"영혼석 교체",18)
	ui.label(ui.modal_content,"%s → %s" % [Essences.title(old_id),Essences.title(id)],15)
	ui.label(ui.modal_content,Tab.effect_line(old_id,actor),13)
	ui.label(ui.modal_content,Tab.effect_line(id,actor),13)
	ui.label(ui.modal_content,"%s 소멸" % Essences.title(old_id),13)
	ui.button(ui.modal_content,"교체",func():
		var reason: String = s.overwrite_stone(ui.rest_actor,slot,id)
		ui.details_popup.hide()
		if not reason.is_empty(): ui.notice = reason
		else: ui.rest_selected_stone = ""; ui.refresh())
	ui.button(ui.modal_content,"취소",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()
