extends RefCounted
const Keywords = preload("res://expedition/ui/screens/keyword_popup.gd")
const Forms = preload("res://expedition/combat/forms.gd")
## Every popup the HUD opens over a screen: the menu, the log, the map, curios,
## enemy info, npcs and their offers, the shared bag, the folio and the tactic
## rules. Moved out of main.gd; the popup nodes still live on `ui`.
const Session = preload("res://expedition/run/session.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const InventorySlot = preload("res://expedition/items/inventory_slot.gd")
const CharacterUI = preload("res://expedition/ui/screens/character_folio.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const EssenceTab = preload("res://expedition/ui/screens/essence_tab.gd")

static func show_menu(ui) -> void:
	var session = ui.session
	ui.clear(ui.modal_content)
	ui.modal_content.custom_minimum_size = Vector2(148,0)
	if session != null and session.manual_mode:
		ui.button(ui.modal_content,"야영",func(): ui.details_popup.hide(); ui.run_action(session.camp),session.can_camp().is_empty())
	ui.button(ui.modal_content,"기록",func(): show_logs(ui))
	ui.button(ui.modal_content,"가방",func(): show_supplies(ui))
	if session != null and session.manual_mode: ui.button(ui.modal_content,"인물",func(): show_character(ui,0,"상태"))
	ui.button(ui.modal_content,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()
	ui.details_popup.position = Vector2i(ui.get_viewport_rect().size.x-ui.details_popup.size.x-8,58)

static func show_logs(ui) -> void:
	ui.stop_navigation(); ui.clear(ui.log_popup)
	var skin: Theme = ui.theme.duplicate()
	var panel := CharacterUI.surface(Color("100f0d")); panel.set_content_margin_all(8); panel.shadow_size = 0
	skin.set_stylebox("panel","PopupPanel",panel); ui.log_popup.theme = skin
	var box := VBoxContainer.new(); box.custom_minimum_size = ui.get_viewport_rect().size-Vector2(16,16)
	box.add_theme_constant_override("separation",8); ui.log_popup.add_child(box)
	var header := HBoxContainer.new(); box.add_child(header)
	var title = ui.label(header,"기록",22); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.button(header,"×",func(): ui.log_popup.hide()).custom_minimum_size.x = 44
	var tabs := HBoxContainer.new(); box.add_child(tabs)
	for kind in ["전체","중요"]:
		var tab = ui.button(tabs,kind,func(): ui.log_filter = kind; show_logs(ui))
		tab.toggle_mode = true; tab.button_pressed = ui.log_filter == kind
	var history := RichTextLabel.new(); history.name = "FullHistory"; history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history.add_theme_font_size_override("normal_font_size",15)
	var entries: Array = ui.session.log_lines
	if ui.log_filter == "중요":
		entries = entries.filter(func(entry): return ["합류","보스","쓰러","내려","동행","전사"].any(func(term): return str(entry).contains(term)))
	history.text = "\n".join(entries)
	history.scroll_following = true; box.add_child(history)
	ui.button(box,"닫기",func(): ui.log_popup.hide())
	ui.log_popup.popup_centered(Vector2i(ui.get_viewport_rect().size))

static func show_map(ui) -> void:
	ui.stop_navigation()
	if ui.session == null or not ui.session.on_floor(): return
	var map_box := ui.map_view.get_parent() as VBoxContainer
	map_box.custom_minimum_size = ui.get_viewport_rect().size-Vector2(16,16)
	ui.map_view.session = ui.session; ui.map_view.queue_redraw()
	ui.map_popup.popup_centered(Vector2i(ui.get_viewport_rect().size))

static func show_curio(ui, point: Vector2i) -> void:
	var session = ui.session
	ui.stop_navigation(); ui.clear(ui.modal_content)
	var feature: Dictionary = session.floor_state.features.get(point,{})
	var def: Dictionary = Session.Curios.definition(feature)
	if def.is_empty(): return
	ui.label(ui.modal_content,def.name,22)
	if feature.used: ui.label(ui.modal_content,"조사 완료",16)
	else:
		for id in def.options:
			var choice: Dictionary = def.options[id]
			var caption: String = choice.label
			var reason: String = Session.Curios.error(session,point,id)
			ui.button(ui.modal_content,caption,func(): ui.details_popup.hide(); ui.collect_curio(point,id),reason in ["","거리 초과"])
			var hint_text: String = "" if reason == "거리 초과" else reason if not reason.is_empty() else str(choice.get("warning",""))
			if not hint_text.is_empty():
				var hint = ui.label(ui.modal_content,hint_text,14)
				hint.custom_minimum_size.x = ui.popup_width(); hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.button(ui.modal_content,"지나가기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()

static func show_enemy_info(ui, enemy: Dictionary) -> void:
	var session = ui.session
	if enemy.is_empty() or enemy.hp <= 0: return
	ui.clear(ui.modal_content)
	var values: Dictionary = Session.CombatStats.stats(session,enemy)
	var title = ui.label(ui.modal_content,str(enemy.name),20); title.name = "EnemyInfo"
	ui.button(ui.modal_content,"도감",func(): ui.show_codex("monsters",Session.Codex.monster_key(enemy))).name = "EnemyCodex"
	ui.label(ui.modal_content,"HP %d/%d   AC %d   EV %d   속도 %d" % [int(enemy.hp),int(enemy.max_hp),int(values.ac),int(values.ev),int(values.delay)],14)
	var sheet: Dictionary = StatSheet.sheet(session,enemy)
	var defence = ui.label(ui.modal_content,"방어 %d   회피 %d   막기 %d" % [int(sheet.ac.total),int(sheet.ev.total),int(sheet.sh.total)],14)
	defence.name = "EnemyDefence"
	var body = ui.label(ui.modal_content,Forms.body_line(enemy),13)
	body.name = "EnemyBody"
	var resists: Array = []
	for key in ["res_fire","res_ice","res_air","res_poison","res_will"]:
		if int(sheet[key].total) != 0: resists.append("%s %d%%" % [StatSheet.NAMES[key],int(sheet[key].total)])
	if not resists.is_empty():
		var resist = ui.label(ui.modal_content,"저항  "+"  ".join(resists),13)
		resist.name = "EnemyResist"
	var essence: String = str(enemy.get("part_id",""))
	if Essences.has(essence):
		var named = ui.label(ui.modal_content,"영혼석 · "+Essences.title(essence),15)
		named.name = "EnemyEssence"
		if not EssenceTab.tag_line(essence).is_empty(): ui.label(ui.modal_content,EssenceTab.tag_line(essence),13)
		var words = ui.label(ui.modal_content,EssenceTab.active_line(essence),13)
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; words.custom_minimum_size.x = ui.popup_width()
		# The monster fights with its own stone's headline effect (a boss has none).
		if not bool(enemy.get("boss",false)):
			var effect = ui.label(ui.modal_content,EssenceTab.effect_line(essence),13)
			effect.name = "EnemyEffect"; effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; effect.custom_minimum_size.x = ui.popup_width()
	if Essences.has(essence) and not Essences.part_of(Essences.canonical(essence)).is_empty():
		var names: Array = []
		for id in EssenceTab.siblings(essence):
			var part_index: int = Forms.PARTS.find(Essences.part_of(id))
			var possessed: bool = session.party.any(func(a): return Essences.absorbed(a,id)) or int(session.parts_bag.get(id,0)) > 0
			names.append("%s%s(%s)" % ["✓ " if possessed else "",Essences.title(id),Forms.NAMES[Forms.FORMS[part_index]]])
		var parts = ui.label(ui.modal_content," · ".join(names),12); parts.name = "EnemyParts"
		parts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parts.custom_minimum_size.x = minf(ui.popup_width(),ui.size.x-40)
	var preview: Dictionary = session.attack_preview(enemy.pos)
	if not preview.is_empty():
		ui.label(ui.modal_content,"명중 %d%%   피해 %d–%d   %d tick" % [int(preview.chance),int(preview.damage_min),int(preview.damage_max),int(preview.time)],14)
		var attack = ui.button(ui.modal_content,"공격",func(): ui.details_popup.hide(); ui.run_action(func(): return session.act("ATTACK",enemy.pos)))
		attack.name = "InspectAttack"
	ui.button(ui.modal_content,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()

static func inspect_cell(ui, point: Vector2i) -> void:
	if ui.session == null or not ui.session.manual_mode or not ui.session.floor_state.visible.has(point): return
	var actor: Dictionary = ui.session.at(point)
	if not actor.is_empty() and actor.enemy: show_enemy_info(ui,actor)

## One line of who this npc is: the nouns of its two social facets.
static func npc_personality(ui, npc: Dictionary) -> String:
	var words: Array = []
	for facet in ["X","A"]:
		var terms: Dictionary = Session.Hexaco.STYLE_AXES[facet]
		words.append(str(terms.high_noun if npc.profile.value(facet) >= 500 else terms.low_noun))
	return " · ".join(words)

## The npc popup: who it is, what it is doing, and the two things the party has
## to offer — a share of the food and a place in the line.
static func show_npc(ui, npc: Dictionary) -> void:
	var session = ui.session
	ui.stop_navigation(); ui.clear(ui.modal_content)
	ui.modal_content.custom_minimum_size = Vector2(ui.popup_width(),0)
	var page := VBoxContainer.new(); page.name = "NpcPopup"; ui.modal_content.add_child(page)
	page.add_theme_constant_override("separation",8)
	var talk: Dictionary = Session.Recruit.dialogue(session,npc)
	var heading := HBoxContainer.new(); page.add_child(heading)
	var portrait := TextureRect.new(); portrait.texture = Art.actor_portrait(npc)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(64,64); heading.add_child(portrait)
	var words := VBoxContainer.new(); heading.add_child(words)
	ui.label(words,str(npc.name),20)
	var worn: Array = Essences.equipped(npc).map(func(id): return Essences.title(str(id)))
	var level_line = ui.label(words,"Lv.%d · 영혼석 %s" % [int(npc.get("level",1)),", ".join(worn) if not worn.is_empty() else "없음"],13)
	level_line.name = "NpcLevel"
	var dialogue = ui.label(words,str(talk.line),15)
	dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ask = ui.button(page,"동행 제안",func(): propose_npc(ui,npc),bool(talk.can_propose))
	ask.name = "ProposeButton"
	var share = ui.button(page,"식량 1 나누기",func(): ui.details_popup.hide(); ui.run_action(func(): return session.aid(npc)),bool(talk.can_aid))
	share.name = "AidButton"
	var attack = ui.button(page,"공격",func(): ui.details_popup.hide(); ui.run_action(func(): return session.act("ATTACK",npc.pos)),not session.attack_preview(npc.pos).is_empty())
	attack.name = "AttackNpcButton"
	var close = ui.button(page,"닫기",func(): ui.details_popup.hide())
	close.name = "CloseNpc"
	ui.details_popup.popup_centered()

## The ask itself always goes through: what comes back is the npc's answer, and
## the sentence it answers with is the notice.
static func propose_npc(ui, npc: Dictionary) -> void:
	var session = ui.session
	ui.details_popup.hide()
	# A lambda captures its locals by value, so the answer comes back on the node.
	ui.proposal_line = ""
	ui.run_action(func(): ui.proposal_line = str(session.propose(npc).line); return true)
	ui.notice = ui.proposal_line

## An npc that asks to come along stops the run and waits for an answer; the
## popup lives exactly as long as the offer does.
static func update_offer_popup(ui) -> void:
	var session = ui.session
	if session == null or not is_instance_valid(ui.offer_popup): return
	var standing: Array = session.npcs.filter(func(n): return n.id == session.pending_offer) if session.pending_offer >= 0 else []
	if standing.is_empty():
		ui.offer_popup.hide(); return
	var npc: Dictionary = standing[0]
	session.auto.running = false
	ui.stop_navigation()
	ui.stop_text = "%s이(가) 말을 겁니다" % npc.name
	ui.clear(ui.offer_content)
	var heading := HBoxContainer.new(); ui.offer_content.add_child(heading)
	var portrait := TextureRect.new(); portrait.texture = Art.actor_portrait(npc)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(64,64); heading.add_child(portrait)
	var words := VBoxContainer.new(); heading.add_child(words)
	ui.label(words,str(npc.name),20)
	var dialogue = ui.label(words,str(Session.Recruit.dialogue(session,npc).line),15)
	dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var accept = ui.button(ui.offer_content,"동행",func(): ui.offer_popup.hide(); ui.run_action(func(): return session.answer_offer(true)),session.alive().size() < Session.Recruit.MAX_PARTY)
	accept.name = "OfferAccept"
	var refuse = ui.button(ui.offer_content,"거절",func(): ui.offer_popup.hide(); ui.run_action(func(): return session.answer_offer(false)))
	refuse.name = "OfferDecline"
	ui.offer_popup.popup_centered()

static func show_character(ui, index: int, tab: String = "상태") -> void:
	if tab == "파츠": tab = "영혼석"
	var session = ui.session
	ui.stop_navigation()
	ui.tactics_actor = clampi(index,0,session.party.size()-1); ui.character_tab = tab
	ui.clear(ui.modal_content)
	var list: VBoxContainer = CharacterUI.shell(ui,tab)
	var actor: Dictionary = session.party[ui.tactics_actor]
	match tab:
		"상태": CharacterUI.status(ui,list,actor)
		"영혼석": EssenceTab.build(ui,list,actor)
		"성격": CharacterUI.personality(ui,list,actor)
		"기억": CharacterUI.memories(ui,list,actor)
	ui.details_popup.popup_centered(Vector2i(ui.get_viewport_rect().size))

static func show_tactics(ui) -> void:
	show_character(ui,ui.tactics_actor,"영혼석")

static func open_rule(ui, index: int) -> void:
	ui.tactics_expanded = index
	ui.clear(ui.item_detail)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(ui.popup_width(),minf(400,ui.size.y-120))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ui.item_detail.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	build_skill_rules(ui,list)
	ui.item_popup.popup_centered()

static func build_skill_rules(ui, list: VBoxContainer) -> void:
	var session = ui.session
	var actor: Dictionary = session.party[ui.tactics_actor]
	ui.label(list,"스킬 사용 순서",14)
	for index in range(actor.rules.size()):
		if index != ui.tactics_expanded: continue
		var rule: Dictionary = actor.rules[index]
		var card = CharacterUI.card(list,"")
		var header := HBoxContainer.new(); card.add_child(header)
		ui.label(header,Session.Rules.skill(rule.skill).name,18)
		var enabled := CheckButton.new(); enabled.text = "자동"; enabled.button_pressed = rule.enabled; enabled.custom_minimum_size.y = 44; header.add_child(enabled)
		enabled.toggled.connect(func(value): change_tactic_rule(ui,index,"enabled",value))
		var summary = ui.label(card,Session.Rules.summary(rule),11); summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if ui.tactics_expanded != index: continue
		var def: Dictionary = Session.Rules.skill(rule.skill)
		tactic_pick(ui,card,"누구에게?",def.targets,Session.Rules.TARGET_NAMES,rule.target,func(value): change_tactic_rule(ui,index,"target",value))
		tactic_pick(ui,card,"언제?",def.conditions,Session.Rules.WHEN_NAMES,rule.when,func(value): change_tactic_rule(ui,index,"when",value))
		if rule.when in ["HP","STATUS"]:
			tactic_pick(ui,card,"누구 기준?",["SELF"] if rule.target == "SELF" else ["SELF","TARGET"],{"SELF":"자신","TARGET":"대상"},"SELF" if rule.target == "SELF" else rule.subject,func(value): change_tactic_rule(ui,index,"subject",value))
		if rule.when == "HP":
			var threshold = ui.label(card,"체력 %d%%" % rule.threshold)
			var slider := HSlider.new(); slider.min_value = 10; slider.max_value = 100; slider.step = 10; slider.value = rule.threshold; slider.custom_minimum_size = Vector2(280,44); card.add_child(slider)
			slider.value_changed.connect(func(value): session.update_rule(ui.tactics_actor,index,"threshold",int(value)); threshold.text = "체력 %d%%" % int(value); ui.refresh())
			tactic_pick(ui,card,"기준",["BELOW","ABOVE"],{"BELOW":"이하","ABOVE":"이상"},rule.comparison,func(value): change_tactic_rule(ui,index,"comparison",value))
		if rule.when == "STATUS":
			tactic_pick(ui,card,"어떤 상태?",Session.Rules.STATUS_NAMES.keys(),Session.Rules.STATUS_NAMES,rule.status,func(value): change_tactic_rule(ui,index,"status",value))
		var ordering := HBoxContainer.new(); card.add_child(ordering)
		ui.button(ordering,"↑ 먼저 사용",func(): session.reorder_rule(ui.tactics_actor,index,-1); ui.refresh(); show_tactics(ui); open_rule(ui,index-1),index > 0)
		ui.button(ordering,"↓ 나중에 사용",func(): session.reorder_rule(ui.tactics_actor,index,1); ui.refresh(); show_tactics(ui); open_rule(ui,index+1),index < actor.rules.size()-1)
	var basic := VBoxContainer.new(); list.add_child(basic)
	ui.label(basic,"기본 행동",14)
	tactic_pick(ui,basic,"일반 공격 대상",Session.Rules.BASIC_TARGETS,Session.Rules.TARGET_NAMES,actor.basic_target,func(value): change_basic_target(ui,value))
	ui.button(list,"행동방침 기본값 복원",func(): session.reset_rules(ui.tactics_actor); ui.refresh(); show_tactics(ui))
	ui.button(list,"완료",func(): ui.item_popup.hide())

static func change_basic_target(ui, value: String) -> void:
	if ui.session.set_basic_target(ui.tactics_actor,value): ui.refresh(); show_tactics(ui); open_rule(ui,ui.tactics_expanded)

static func change_tactic_rule(ui, index: int, field: String, value: Variant) -> void:
	if ui.session.update_rule(ui.tactics_actor,index,field,value): ui.refresh(); show_tactics(ui); open_rule(ui,index)

static func tactic_pick(ui, parent: Node, title: String, values: Array, names: Dictionary, current: String, changed: Callable) -> void:
	ui.label(parent,title,12)
	var pick := OptionButton.new(); pick.custom_minimum_size = Vector2(280,44)
	for value in values: pick.add_item(names[value])
	pick.select(maxi(0,values.find(current))); parent.add_child(pick)
	pick.item_selected.connect(func(index): changed.call(values[index]))

static func show_supplies(ui) -> void:
	if ui.session == null: return
	ui.stop_navigation()
	ui.clear(ui.modal_content)
	if ui.session.manual_mode: build_manual_inventory(ui)
	else: ui.label(ui.modal_content,"공용 가방",18); build_inventory(ui)

static func build_manual_inventory(ui) -> void:
	var available_width: float = minf(360,ui.size.x-32)
	var columns := 4 if available_width >= 4*68+3*6 else 3
	ui.modal_content.custom_minimum_size = Vector2(available_width,ui.size.y-32)
	var box := VBoxContainer.new(); box.name = "ManualInventory"; box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.x = available_width
	box.add_theme_constant_override("separation",8); ui.modal_content.add_child(box)
	var header := HBoxContainer.new(); box.add_child(header)
	var title = ui.label(header,"가방",22); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.button(header,"×",func(): ui.details_popup.hide()).custom_minimum_size.x = 44
	build_equipped_header(ui,box)
	var filters := HBoxContainer.new(); filters.name = "InventoryTabs"; filters.add_theme_constant_override("separation",2); box.add_child(filters)
	for category in ["전체","소모품","장비","파츠","자원"]:
		var pick = ui.button(filters,category,func(): ui.inventory_filter = category; show_supplies(ui))
		pick.toggle_mode = true; pick.button_pressed = category == ui.inventory_filter
		pick.add_theme_font_size_override("font_size",10)
	var rows: Array = inventory_rows(ui).filter(func(r): return ui.inventory_filter == "전체" or r.category == ui.inventory_filter)
	if not rows.any(func(r): return r.id == ui.inventory_selected):
		ui.inventory_selected = str(rows[0].id) if not rows.is_empty() else ""
	ui.label(box,"%s · %d종" % [ui.inventory_filter,rows.size()],13)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; box.add_child(scroll)
	ui.inventory_slots.clear()
	if ui.inventory_filter == "파츠":
		var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(list)
		var by_id: Dictionary = {}
		for item in rows: by_id[str(item.id)] = item
		for group in EssenceTab.groups(by_id.keys()):
			ui.label(list,Essences.title(str(group)),13)
			var parts := HBoxContainer.new(); parts.add_theme_constant_override("separation",4); list.add_child(parts)
			for id in EssenceTab.siblings(str(group)):
				var slot = InventorySlot.new(); slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parts.add_child(slot)
				var item: Dictionary = by_id.get(str(id),{})
				slot.configure(item,item.get("id","") == ui.inventory_selected); ui.inventory_slots.append(slot)
				if not item.is_empty(): slot.pressed.connect(func(): show_item_detail(ui,str(id)))
				else:
					var hint: int = Forms.PARTS.find(Essences.part_of(str(id)))
					if hint >= 0: slot.set_meta("missing_part",str(Forms.NAMES[Forms.FORMS[hint]]))
					slot.tooltip_text = Essences.title(str(id))+" · "+str(Forms.NAMES[Forms.FORMS[hint]]) if hint >= 0 else Essences.title(str(id))
	else:
		var grid := GridContainer.new(); grid.columns = columns; grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation",6); grid.add_theme_constant_override("v_separation",6); scroll.add_child(grid)
		ui.inventory_slots.clear()
		var minimum_rows := 2 if ui.size.y < 700 else 4
		for i in range(maxi(columns*minimum_rows,int(ceil(rows.size()/float(columns)))*columns)):
			var slot = InventorySlot.new(); grid.add_child(slot)
			var row: Dictionary = rows[i] if i < rows.size() else {}
			slot.configure(row,row.get("id","") == ui.inventory_selected); ui.inventory_slots.append(slot)
			if not row.is_empty(): slot.pressed.connect(func(): show_item_detail(ui,row.id))
	var selected: Array = inventory_rows(ui).filter(func(r): return r.id == ui.inventory_selected)
	var detail := PanelContainer.new(); detail.name = "InventorySelection"
	detail.custom_minimum_size.y = 72
	detail.add_theme_stylebox_override("panel",CharacterUI.surface(Color("211e1a"))); box.add_child(detail)
	var details := VBoxContainer.new(); detail.add_child(details)
	if not selected.is_empty():
		var item_name = ui.label(details,str(selected[0].label),16)
		if str(selected[0].category) == "장비": item_name.add_theme_color_override("font_color",Equipment.colour(selected[0].item))
		item_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var description = ui.label(details,str(selected[0].description),12)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.button(box,"닫기",func(): ui.details_popup.hide())
	var popup_size := Vector2i(roundi(available_width)+16,roundi(ui.size.y)-16)
	ui.details_popup.popup_centered(popup_size)
	ui.details_popup.size = popup_size
	ui.details_popup.position = (Vector2i(ui.size)-popup_size)/2
	# Switching tabs can briefly keep the previous content's minimum width.
	# Reapply the phone-sized rectangle once the new controls have laid out.
	ui.get_tree().process_frame.connect(func():
		if is_instance_valid(ui.details_popup) and ui.details_popup.visible:
			ui.details_popup.size = popup_size
			ui.details_popup.position = (Vector2i(ui.size)-popup_size)/2
	,CONNECT_ONE_SHOT)

static func gear_name(_ui, item: Dictionary, slot: String) -> String:
	return Forms.weapon_label(Equipment.title(item),str(item.type)) if slot == "weapon" else Equipment.title(item)

static func build_equipped_header(ui, parent: VBoxContainer) -> void:
	if ui.session.party.is_empty(): return
	ui.inventory_actor = clampi(ui.inventory_actor,0,ui.session.party.size()-1)
	var equipped := VBoxContainer.new(); equipped.name = "EquippedHeader"
	equipped.add_theme_constant_override("separation",3); parent.add_child(equipped)
	var heading := HBoxContainer.new(); equipped.add_child(heading)
	var title = ui.label(heading,"장착",14); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ui.session.party.size() > 1:
		var members := HBoxContainer.new(); members.name = "EquippedMembers"
		members.add_theme_constant_override("separation",3); equipped.add_child(members)
		for index in range(ui.session.party.size()):
			var member = ui.button(members,str(ui.session.party[index].name).left(4),func(): ui.inventory_actor = index; show_supplies(ui))
			member.name = "EquippedMember%d" % index
			member.size_flags_horizontal = Control.SIZE_EXPAND_FILL; member.clip_text = true
			member.toggle_mode = true; member.button_pressed = index == ui.inventory_actor
			member.add_theme_font_size_override("font_size",10)
	var actor: Dictionary = ui.session.party[ui.inventory_actor]
	var slots := HBoxContainer.new(); slots.name = "EquippedSlots"
	slots.add_theme_constant_override("separation",3); equipped.add_child(slots)
	for slot in Equipment.SLOTS:
		var item: Dictionary = Equipment.worn(actor).get(slot,{})
		var occupied: bool = not item.is_empty()
		var name: String = gear_name(ui,item,slot) if occupied else "없음"
		var pick = ui.button(slots,"",func(): open_equipped_slot(ui,ui.inventory_actor,slot))
		pick.name = "Equipped_"+slot
		pick.custom_minimum_size.y = 72; pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.clip_contents = true; pick.tooltip_text = (str(actor.name)+" · "+name) if occupied else "장비 보기"
		var slot_label = ui.label(pick,Equipment.SLOT_NAMES[slot],9)
		slot_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		slot_label.offset_top = 2; slot_label.offset_bottom = 16
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; slot_label.clip_text = true
		if occupied:
			var icon := TextureRect.new(); icon.texture = Art.equipment_icon(slot,str(item.get("type","")))
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; pick.add_child(icon)
			icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			icon.offset_left = 3; icon.offset_right = -3; icon.offset_top = 16; icon.offset_bottom = 49
		var item_label = ui.label(pick,name,10)
		item_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		item_label.offset_left = 2; item_label.offset_right = -2; item_label.offset_top = -20; item_label.offset_bottom = -3
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; item_label.clip_text = true
		item_label.add_theme_color_override("font_color",Equipment.colour(item))

static func open_equipped_slot(ui, index: int, slot: String) -> void:
	if index < 0 or index >= ui.session.party.size(): return
	if ui.session.party[index].gear.get(slot,{}).is_empty():
		ui.inventory_filter = "장비"; show_supplies(ui)
	else: show_item_detail(ui,"equipped:%d:%s" % [index,slot])

static func inventory_rows(ui) -> Array:
	var session = ui.session
	var rows: Array = []
	for kind in Session.Consumables.kinds():
		var count: int = int(session.bag.get(kind,0))
		if count <= 0: continue
		var def: Dictionary = Session.Consumables.definition(kind)
		var is_known: bool = session.known.has(kind)
		var row := {"id":"item:"+kind,"label":session.item_label(kind)+("" if is_known else " · 미감정"),"quantity":count,"category":"소모품","kind":kind,"class":str(def["class"]),"known":is_known,"area":bool(def.get("area",false)),"description":Session.Consumables.description(session,kind),"icon":Art.consumable_icon(str(def["class"]))}
		# A potion or scroll shows the look this run dressed it in, with its
		# effect badge once it is known and a question mark until then.
		row.icon = Art.item_icon(str(def["class"]),Session.Consumables.look_index(session,kind))
		row.badge = Art.item_badge(kind,is_known)
		rows.append(row)
	for i in range(session.gear_bag.size()):
		var item: Dictionary = session.gear_bag[i]
		var slot: String = session.gear_slot(item)
		if slot.is_empty(): continue
		var name: String = gear_name(ui,item,slot)
		rows.append({"id":"gear:%d"%i,"label":name,"quantity":1,"category":"장비","item":item,"colour":Equipment.colour(item),"gear_index":i,"gear_slot":slot,"description":Equipment.description(item),"icon":Art.equipment_icon(slot,str(item.get("type","")))})
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		for slot in Equipment.SLOTS:
			var equipped: Dictionary = Equipment.worn(actor).get(slot,{})
			if equipped.is_empty(): continue
			var name: String = gear_name(ui,equipped,slot)
			rows.append({"id":"equipped:%d:%s"%[i,slot],"label":name,"quantity":1,"category":"장비","item":equipped,"colour":Equipment.colour(equipped),"equipped_member":i,"equipped_slot":slot,"gear_slot":slot,"description":actor.name+" · 장착 중\n"+Equipment.description(equipped),"icon":Art.equipment_icon(slot,str(equipped.get("type","")))})
	session.parts_bag = Essences.normalize_keys(session.parts_bag,true)
	for id in session.parts_bag:
		if session.parts_bag.get(id,0) <= 0: continue
		if not Essences.has(str(id)): continue
		rows.append({"id":id,"label":Essences.title(str(id)),"quantity":session.parts_bag[id],"category":"파츠","description":EssenceTab.stat_line(str(id))+"\n"+EssenceTab.effect_line(str(id)),"icon":Art.part_icon(id)})
	rows.append({"id":"food","label":"식량","quantity":session.food,"category":"자원","description":"야영","icon":Art.food_icon()})
	return rows

static func build_inventory(ui) -> void:
	build_equipped_header(ui,ui.modal_content)
	var filters := HBoxContainer.new(); ui.modal_content.add_child(filters)
	for category in ["전체","소모품","장비","파츠","자원"]:
		var pick = ui.button(filters,category,func(): ui.inventory_filter = category; show_supplies(ui))
		pick.toggle_mode = true; pick.button_pressed = category == ui.inventory_filter
		pick.add_theme_font_size_override("font_size",10)
	var rows: Array = inventory_rows(ui).filter(func(r): return ui.inventory_filter == "전체" or r.category == ui.inventory_filter)
	ui.label(ui.modal_content,"%s · %d종 보유" % [ui.inventory_filter,rows.size()],12)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(ui.popup_width(),minf(220,ui.size.y-420)); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ui.modal_content.add_child(scroll)
	var grid := GridContainer.new(); grid.columns = 4; grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; grid.add_theme_constant_override("h_separation",4); grid.add_theme_constant_override("v_separation",4); scroll.add_child(grid)
	ui.inventory_slots.clear()
	for i in range(maxi(12,int(ceil(rows.size()/4.0))*4)):
		var slot = InventorySlot.new(); grid.add_child(slot)
		var row: Dictionary = rows[i] if i < rows.size() else {}
		slot.configure(row,row.get("id","") == ui.inventory_selected); ui.inventory_slots.append(slot)
		if not row.is_empty(): slot.pressed.connect(func(): show_item_detail(ui,row.id))
	ui.button(ui.modal_content,"닫기",func(): ui.details_popup.hide()); ui.details_popup.popup_centered()

static func show_item_detail(ui, id: String) -> void:
	if Essences.has(id): id = Essences.canonical(id)
	var session = ui.session
	var matches: Array = inventory_rows(ui).filter(func(r): return r.id == id)
	if matches.is_empty(): ui.item_popup.hide(); show_supplies(ui); return
	var row: Dictionary = matches[0]; ui.inventory_selected = id
	for slot in ui.inventory_slots:
		if is_instance_valid(slot): slot.selected = slot.row.get("id","") == id; slot.queue_redraw()
	ui.clear(ui.item_detail)
	var title = ui.label(ui.item_detail,"%s × %d" % [row.label,row.quantity],18)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if row.category == "장비": title.add_theme_color_override("font_color",Equipment.colour(row.item))
	var info = ui.label(ui.item_detail,row.description,12); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; info.custom_minimum_size.x = minf(290,ui.size.x-32)
	if row.category == "장비":
		var keywords: Array = []
		for effect_id in [row.item.get("affix",""),row.item.get("cost_effect","")]:
			for word in Equipment.effect_text.get(str(effect_id),{}).get("keywords",[]):
				if word not in keywords: keywords.append(word)
		Keywords.chips(ui,ui.item_detail,keywords)
	elif row.category == "파츠":
		Keywords.chips(ui,ui.item_detail,Equipment.effect_text.get(EssenceTab.StoneEffects.effect_of(id),{}).get("keywords",[]))
		var active: String = str(Essences.row(id).get("active",""))
		if Session.Abilities.has(active): EssenceTab.label(ui.item_detail,str(Session.Abilities.definition(active).description),13)
	if row.category == "소모품":
		var usable: bool = session.phase in ["EXPLORE","BATTLE","CAMP"]
		if row["class"] == "potion":
			for i in range(session.party.size()):
				ui.button(ui.item_detail,session.party[i].name+" 마신다",func(): ui.item_popup.hide(); ui.details_popup.hide(); ui.run_action(func(): return session.use_item(row.kind,Vector2i(-1,-1),i)),usable and session.party[i].hp > 0)
			if row.area or not row.known:
				ui.button(ui.item_detail,"던진다 · 바닥 선택",func(): ui.item_popup.hide(); ui.details_popup.hide(); ui.choose_item(row.kind),session.on_floor())
		else:
			ui.button(ui.item_detail,"읽는다",func(): ui.item_popup.hide(); ui.details_popup.hide(); ui.run_action(func(): return session.use_item(row.kind)),usable)
	elif row.category == "장비":
		if row.has("equipped_member"):
			var member: int = int(row.equipped_member)
			ui.button(ui.item_detail,"해제",func():
				if session.unequip_gear(member,str(row.equipped_slot)): ui.item_popup.hide(); ui.refresh(); show_supplies(ui),session.phase == "CAMP")
		else:
			var gear: Dictionary = session.gear_bag[int(row.gear_index)]
			for i in range(session.party.size()):
				var actor: Dictionary = session.party[i]
				var targets: Array = ["ring1","ring2"] if Equipment.slot(gear) == "ring1" else [Equipment.slot(gear)]
				for target_slot in targets:
					ui.button(ui.item_detail,actor.name+" · "+str(Equipment.SLOT_NAMES[target_slot])+" 장착",func():
						if session.equip_gear(i,gear,target_slot): ui.item_popup.hide(); ui.refresh(); show_supplies(ui),session.phase == "CAMP" and actor.hp > 0)
	elif row.category == "파츠":
		for i in range(session.party.size()):
			var member: Dictionary = session.party[i]
			var known: bool = Essences.absorbed(member,id)
			var full: bool = Essences.free_slot(member) < 0
			var caption: String = "%s · 이미 흡수함" % member.name if known else ("%s · 가득 참" % member.name if full else "%s 흡수" % member.name)
			var absorb = ui.button(ui.item_detail,caption,func(): absorb_from_bag(ui,i,id),Essences.can_manage(session) and member.hp > 0 and Essences.has(id) and not known and not full)
			absorb.name = "BagAbsorb%d" % i
	ui.button(ui.item_detail,"닫기",func(): ui.item_popup.hide()); ui.item_popup.popup_centered(); ui.item_popup.grab_focus()

static func popup_list(ui) -> VBoxContainer:
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(ui.popup_width(),minf(330,ui.size.y-300)); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ui.modal_content.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	return list

static func absorb_from_bag(ui, member: int, id: String) -> void:
	var reason: String = ui.session.absorb_essence(member,id)
	if not reason.is_empty():
		ui.notice = reason; return
	ui.item_popup.hide(); ui.refresh(); show_supplies(ui)

static func show_choice(ui) -> void:
	var session = ui.session
	var choice: Dictionary = session.pending_choice
	if choice.is_empty(): return
	ui.stop_navigation(); ui.clear(ui.modal_content)
	ui.label(ui.modal_content,"감정할 것" if choice.kind == "identify" else "강화할 장비",18)
	for option in choice.options:
		var caption: String = session.item_label(option) if choice.kind == "identify" else gear_name(ui,session.party[int(choice.actor)].gear[option],option)
		ui.button(ui.modal_content,caption,func(): pick_choice(ui,option))
	ui.details_popup.transient = true; ui.details_popup.exclusive = true
	ui.details_popup.popup_centered()

static func pick_choice(ui, option: String) -> void:
	if ui.session.resolve_choice(option):
		ui.details_popup.exclusive = false
		ui.details_popup.hide(); ui.refresh()
