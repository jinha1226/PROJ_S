extends RefCounted
## The floor HUD: the header, the board, the log button, the party cards or the
## manual portrait row, the spell bar, the bottom actions and the stop banner —
## plus the taps they arm. Moved out of main.gd's refresh().
const Session = preload("res://expedition/run/session.gd")
const Board = preload("res://expedition/ui/board.gd")
const MapView = preload("res://expedition/ui/map_view.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const Stances = preload("res://expedition/ai/stances.gd")
const Popups = preload("res://expedition/ui/screens/popups.gd")
const AutoBattleHud = preload("res://expedition/ui/screens/autobattle_hud.gd")
const FONT = preload("res://assets/fonts/NanumSquareR.ttf")

static func build(ui, elapsed: float, impact_elapsed: float) -> void:
	var session = ui.session
	var header := HBoxContainer.new(); header.name = "TopHUD"; header.add_theme_constant_override("separation",3); ui.root_layout.add_child(header)
	if not is_instance_valid(ui.minimap):
		ui.minimap = MapView.new(); ui.minimap.compact = true; ui.minimap.minimum_side = 44
		ui.minimap.ui_font = FONT; ui.minimap.expand_requested.connect(ui.show_map)
	if ui.minimap.get_parent() != null: ui.minimap.get_parent().remove_child(ui.minimap)
	ui.minimap.session = session; ui.minimap.visible = true; ui.minimap.queue_redraw(); header.add_child(ui.minimap)
	var place = ui.label(header,"%d층" % session.depth,18); place.name = "Location"; place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var food_label = ui.label(header,"식량 %d" % session.food,14); food_label.name = "FoodLabel"
	food_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var menu = ui.button(header,"메뉴",ui.show_menu); menu.name = "ExpeditionMenu"; menu.size_flags_horizontal = Control.SIZE_SHRINK_END
	if not is_instance_valid(ui.board):
		ui.board = Board.new(); ui.board.ui_font = FONT; ui.board.cell_pressed.connect(ui.on_cell)
		ui.board.cell_inspected.connect(ui.inspect_cell)
		ui.board.zoom_changed.connect(func(value): ui.view_side = value)
		ui.board.gesture_started.connect(ui.stop_navigation); ui.board.playback_finished.connect(ui.finish_presentation)
	ui.board.session = session; ui.board.view_side = ui.view_side; ui.board.action_footer = not session.manual_mode and not ui.pending_attack.is_empty()
	if ui.board.get_parent() != null: ui.board.get_parent().remove_child(ui.board)
	ui.board.visible = true
	ui.board.size_flags_vertical = Control.SIZE_EXPAND_FILL; ui.root_layout.add_child(ui.board); ui.board.queue_redraw()
	ui.board.show_attack_range = ui.show_attack_range; ui.board.targeting_skill = ui.mode
	ui.board.effects = ui.action_effects; ui.action_effects = []; ui.board.target_cell = ui.pending_attack.get("cell",Vector2i(-1,-1))
	ui.board.effect_time = elapsed; ui.board.impact_time = impact_elapsed
	ui.board.companion_previews = session.companion_previews(); ui.board.companion_intents = session.companion_intent_snapshot()
	if not session.in_combat(): ui.board.reset_intent_ui()
	if not session.manual_mode and not ui.pending_attack.is_empty():
		var warning := Session.Scheduler.double_movers(session,int(ui.pending_attack.time))
		var preview = ui.label(ui.board,"명중 %d%% · 피해 %d–%d · %d tick%s" % [ui.pending_attack.chance,ui.pending_attack.damage_min,ui.pending_attack.damage_max,ui.pending_attack.time," · 느린 행동" if not warning.is_empty() else ""],12)
		preview.name = "ActionPreview"
		preview.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		preview.offset_left = 8; preview.offset_right = -8; preview.offset_top = -82; preview.offset_bottom = -58
		ui.attack_button = ui.button(ui.board,"공격",func(): confirm_attack(ui))
		ui.attack_button.name = "ConfirmAttack"
		ui.attack_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		ui.attack_button.offset_left = 8; ui.attack_button.offset_top = -56; ui.attack_button.offset_right = 210; ui.attack_button.offset_bottom = -8
	var recent: Array = session.log_lines.slice(maxi(0,session.log_lines.size()-(4 if session.manual_mode else 1)))
	var log_button = ui.button(ui.root_layout,"\n".join(recent),ui.show_logs)
	log_button.name = "RecentLog"; log_button.custom_minimum_size.y = 72 if session.manual_mode else 36
	if session.manual_mode:
		log_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		log_button.autowrap_mode = TextServer.AUTOWRAP_OFF
		log_button.clip_text = true
	if session.manual_mode:
		build_manual_controls(ui)
		return
	var party_row := HBoxContainer.new(); party_row.name = "PartyRow"
	party_row.add_theme_constant_override("separation",5); ui.root_layout.add_child(party_row)
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",2); party_row.add_child(column)
		# The card reports each member's state; the hero's actions are below.
		var portrait = ui.button(column,"",func(): select_actor(ui,i)); portrait.name = "MemberCard%d" % i
		portrait.tooltip_text = "길게 누르기: 상태"; portrait.custom_minimum_size.y = 62
		ui.portrait_buttons.append(portrait)
		var caption := "%s [%s] · HP %d/%d\n스트레스 %d · %s\n%s" % [actor.name,Stances.SHORT[Stances.effective(actor)],actor.hp,actor.max_hp,actor.stress,actor.condition,actor.last_action]
		if bool(actor.get("conflicted",false)): caption += " ⚠ 갈등"
		var stats = ui.label(portrait,caption,12 if session.party.size() == 1 else 10)
		stats.name = "MemberCaption%d" % i
		stats.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); stats.offset_left = 4; stats.offset_right = -4
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if i == session.selected:
			var gold = portrait.get_theme_stylebox("normal").duplicate(); gold.border_color = Color("e9c575")
			gold.set_border_width_all(2); portrait.add_theme_stylebox_override("normal",gold)
		if actor.hp <= 0: portrait.modulate = Color("636369")
	var shared := HBoxContainer.new(); ui.root_layout.add_child(shared)
	for slot in range(5):
		var item = ui.icon_button(shared,Art.item(slot),func(): choose_item(ui,slot),Session.SUPPLY_NAMES[slot],str(session.supplies[slot]))
		item.disabled = session.supplies[slot] <= 0 or session.auto.running; ui.item_buttons.append(item)
	if session.manual_mode:
		var spells := HBoxContainer.new(); spells.name = "SpellBar"; ui.root_layout.add_child(spells)
		for slot in range(Session.PREPARED_SLOTS):
			var prepared: Array = session.party[0].prepared
			var id: String = str(prepared[slot]) if slot < prepared.size() else ""
			var caption: String = str(Session.CombatStats.content.spells[id].name) if not id.is_empty() else "—"
			var spell = ui.button(spells,caption,func(): choose_spell(ui,id),not id.is_empty())
			spell.name = "Spell%d" % slot; spell.custom_minimum_size.y = 44
	var nav := GridContainer.new(); nav.name = "BottomActions"; nav.columns = 4; ui.root_layout.add_child(nav)
	var attack = ui.button(nav,"공격",func():
		if session.manual_mode:
			ui.mode = "ATTACK"; ui.show_attack_range = true; ui.refresh()
		else: ui.run_action(session.auto_attack),session.in_combat()); attack.name = "Attack"
	var wait = ui.button(nav,"대기",func(): ui.run_action(func(): return session.act("WAIT",session.party[session.selected].pos))); wait.name = "Wait"; ui.wait_button = wait
	if session.manual_mode:
		var parts_button = ui.button(nav,"파츠",func(): show_part_actions(ui),session.in_combat()); parts_button.name = "PartActions"
	if not session.manual_mode:
		var toggle = ui.button(nav,"⏸ 정지" if session.auto.running else "▶ 전투",func(): AutoBattleHud.toggle_auto(ui),session.in_combat()); toggle.name = "AutoToggle"
		var speed = ui.button(nav,"%d×" % int(session.auto.speed),func(): AutoBattleHud.toggle_speed(ui)); speed.name = "SpeedToggle"
		var retreat = ui.button(nav,"후퇴 해제" if session.party_command == "RETREAT" else "후퇴",func(): AutoBattleHud.toggle_retreat(ui),session.in_combat()); retreat.name = "RetreatToggle"
	ui.auto_explore_button = ui.button(nav,"중지" if ui.navigation.active else "자동탐험",ui.toggle_explore,not session.in_combat() and not session.auto.running)
	var camp = ui.button(nav,"야영",func(): ui.run_action(session.camp),session.can_camp().is_empty() and not session.auto.running)
	camp.name = "CampButton"; camp.tooltip_text = session.can_camp()
	ui.button(nav,"가방",func(): Popups.show_supplies(ui))
	if not session.manual_mode: build_stop_banner(ui)

static func build_manual_controls(ui) -> void:
	var session = ui.session
	var portraits := HBoxContainer.new(); portraits.name = "PortraitRow"
	portraits.add_theme_constant_override("separation",4); ui.root_layout.add_child(portraits)
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var portrait = ui.button(portraits,"",func(): Popups.show_character(ui,i,"상태"))
		portrait.name = "HeroStatus" if i == 0 else "MemberStatus%d" % i
		portrait.custom_minimum_size.y = 68
		var content := HBoxContainer.new(); content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.add_child(content); content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var image := TextureRect.new(); image.texture = Art.portrait(i)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size.x = 56 if session.party.size() == 1 else 40
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE; content.add_child(image)
		var caption = ui.label(content,"%s · Lv%d\nHP %d/%d · MP %d/%d\n스트레스 %d" % [actor.name,int(actor.level),int(actor.hp),int(actor.max_hp),int(actor.mp),int(actor.max_mp),int(actor.stress)],12 if session.party.size() == 1 else 10)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	var prepared: Array = session.party[0].prepared
	if not prepared.is_empty():
		var spells := HBoxContainer.new(); spells.name = "SpellBar"
		spells.add_theme_constant_override("separation",3); ui.root_layout.add_child(spells)
		for slot in range(Session.PREPARED_SLOTS):
			var id: String = str(prepared[slot]) if slot < prepared.size() else ""
			var caption: String = str(Session.CombatStats.content.spells[id].name) if not id.is_empty() else "—"
			var spell = ui.button(spells,caption,func(): choose_spell(ui,id),not id.is_empty())
			spell.name = "Spell%d" % slot; spell.custom_minimum_size.y = 44
			spell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nav := HBoxContainer.new(); nav.name = "BottomActions"
	nav.add_theme_constant_override("separation",3); ui.root_layout.add_child(nav)
	var attack = ui.button(nav,"공격",func(): arm_attack(ui)); attack.name = "Attack"
	attack.toggle_mode = true; attack.button_pressed = ui.mode == "ATTACK"
	var wait = ui.button(nav,"대기",func(): ui.run_action(func(): return session.act("WAIT",session.party[0].pos))); wait.name = "Wait"; ui.wait_button = wait
	ui.auto_explore_button = ui.button(nav,"중지" if ui.navigation.active else "탐색",ui.toggle_explore,not session.in_combat())
	var tactics = ui.button(nav,"전술",func(): show_manual_tactics(ui)); tactics.name = "Tactics"
	ui.button(nav,"가방",func(): Popups.show_supplies(ui))
	for action in nav.get_children(): action.custom_minimum_size.y = 48

static func build_stop_banner(ui) -> void:
	var banner = ui.label(ui.root_layout,ui.stop_text,15)
	banner.name = "StopBanner"; banner.visible = not ui.stop_text.is_empty()
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; banner.clip_text = true

static func arm_attack(ui) -> void:
	if ui.session == null or not ui.session.manual_mode: return
	ui.mode = "" if ui.mode == "ATTACK" else "ATTACK"
	ui.show_attack_range = ui.mode == "ATTACK"
	ui.refresh()

static func show_manual_tactics(ui) -> void:
	var session = ui.session
	if session == null or not session.manual_mode: return
	ui.clear(ui.modal_content)
	var box := VBoxContainer.new(); box.name = "ManualTactics"; ui.modal_content.add_child(box)
	ui.label(box,"전술",20)
	var actor: Dictionary = session.party[0]
	for id in actor.prepared:
		var spell_id: String = str(id)
		var definition: Dictionary = Session.CombatStats.content.spells.get(spell_id,{})
		var spell = ui.button(box,"%s · %d MP" % [str(definition.get("name",spell_id)),int(definition.get("mp",0))],func(): ui.details_popup.hide(); choose_spell(ui,spell_id),actor.mp >= int(definition.get("mp",0)))
		spell.name = "Spell_"+spell_id
	for id in actor.equipped_abilities:
		var part_id: String = str(id)
		if part_id.is_empty() or not Session.Abilities.DEFINITIONS.has(part_id): continue
		var def: Dictionary = Session.Abilities.DEFINITIONS[part_id]
		var available: bool = session.in_combat() and int(actor.cooldowns.get(part_id,0)) <= 0
		if def.target == "SELF": available = available and Session.Abilities.legal(session,actor,part_id,actor.pos)
		var part = ui.button(box,str(def.name),func(): choose_part(ui,part_id),available)
		part.name = "Part_"+part_id
	ui.button(box,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()

static func show_part_actions(ui) -> void:
	var session = ui.session
	if session == null or not session.manual_mode or not session.in_combat(): return
	ui.clear(ui.modal_content)
	var box := VBoxContainer.new(); box.name = "PartActionMenu"; ui.modal_content.add_child(box)
	ui.label(box,"파츠",20)
	var actor: Dictionary = session.party[0]
	for id in actor.equipped_abilities:
		if str(id).is_empty() or not Session.Abilities.DEFINITIONS.has(id): continue
		var def: Dictionary = Session.Abilities.DEFINITIONS[id]
		var available: bool = int(actor.cooldowns.get(id,0)) <= 0
		if def.target == "SELF": available = Session.Abilities.legal(session,actor,str(id),actor.pos)
		var choice = ui.button(box,str(def.name),func(): choose_part(ui,str(id)),available)
		choice.custom_minimum_size.y = 44
	ui.button(box,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()

static func choose_part(ui, id: String) -> void:
	var session = ui.session
	if session == null or not Session.Abilities.DEFINITIONS.has(id): return
	ui.details_popup.hide()
	var actor: Dictionary = session.party[0]
	if Session.Abilities.DEFINITIONS[id].target == "SELF":
		ui.run_action(func(): return session.act(id,actor.pos))
	else:
		ui.mode = id
		ui.notice = "대상 선택"
		ui.refresh()

static func choose_spell(ui, id: String) -> void:
	if id.is_empty(): return
	if id in ["blink","mend"]:
		ui.run_action(func(): return ui.session.cast(id,ui.session.party[0].pos)); return
	ui.mode = "CAST:"+id; ui.notice = "대상 선택"; ui.refresh()

static func choose_item(ui, slot: int) -> void:
	ui.stop_navigation()
	ui.reservation_actor = -1
	ui.pending_attack = {}
	ui.mode = ""; ui.pending_item = slot
	if slot in [3,4]: ui.notice = Session.SUPPLY_NAMES[slot]+" · 대상 칸 선택"; ui.refresh()
	else: ui.run_action(func(): return ui.session.use_supply(slot))

static func preview_attack(ui, point: Vector2i) -> void:
	ui.pending_attack = ui.session.attack_preview(point)
	ui.show_attack_range = true
	ui.notice = "공격 불가" if ui.pending_attack.is_empty() else "%s · 명중 %d%% · 피해 %d–%d · %d tick" % [ui.pending_attack.name,ui.pending_attack.chance,ui.pending_attack.damage_min,ui.pending_attack.damage_max,ui.pending_attack.time]
	ui.refresh()

static func confirm_attack(ui) -> void:
	var session = ui.session
	if ui.pending_attack.is_empty(): return
	var current: Dictionary = session.attack_preview(ui.pending_attack.cell)
	if current != ui.pending_attack:
		ui.pending_attack = {}; ui.notice = "대상 선택"; ui.refresh(); return
	var point: Vector2i = ui.pending_attack.cell
	ui.run_action(func(): return session.act("ATTACK",point))

static func select_actor(ui, index: int) -> void:
	var session = ui.session
	ui.stop_navigation()
	if session.party[index].hp <= 0: return
	if session.manual_mode and index != 0:
		Popups.show_character(ui,index); return
	ui.pending_attack = {}; ui.show_attack_range = false
	session.selected = index; ui.mode = ""; ui.pending_item = -1; ui.notice = session.party[index].name; ui.refresh()
