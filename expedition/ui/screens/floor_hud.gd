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

static func portrait_state(actor: Dictionary) -> String:
	var details: Array[String] = ["스트레스 %d" % int(actor.stress)]
	var names := {"burn":"화상","poison":"중독","bleed":"출혈","freeze":"빙결","bind":"속박","slow":"둔화","haste":"가속","stun":"기절","silence":"침묵"}
	for status in actor.get("statuses",{}): details.append(str(names.get(status,status)))
	var condition: String = str(actor.get("condition",""))
	if not condition.is_empty() and condition != "평온": details.append(condition)
	return " · ".join(details)

static func build(ui, elapsed: float, impact_elapsed: float) -> void:
	var session = ui.session
	var header := HBoxContainer.new(); header.name = "TopHUD"; header.add_theme_constant_override("separation",5)
	header.custom_minimum_size.y = 52; ui.root_layout.add_child(header)
	if not is_instance_valid(ui.minimap):
		ui.minimap = MapView.new(); ui.minimap.compact = true; ui.minimap.minimum_side = 44
		ui.minimap.ui_font = FONT; ui.minimap.expand_requested.connect(ui.show_map)
	if ui.minimap.get_parent() != null: ui.minimap.get_parent().remove_child(ui.minimap)
	ui.minimap.session = session; ui.minimap.visible = true; ui.minimap.queue_redraw(); header.add_child(ui.minimap)
	var place = ui.label(header,"%d층" % session.depth,18); place.name = "Location"; place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place.custom_minimum_size.y = 52
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; place.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var turns: Label = ui.label(place,"%d턴" % int(session.turn_serial if session.manual_mode else maxi(0,session.round_number-1)),11)
	turns.name = "TurnCount"; turns.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turns.add_theme_color_override("font_color",Color("aa9f8a"))
	turns.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	turns.offset_top = -20; turns.offset_bottom = -3
	var food_label = ui.label(header,"식량 %d" % session.food,14); food_label.name = "FoodLabel"
	food_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var menu = ui.button(header,"메뉴",ui.show_menu); menu.name = "ExpeditionMenu"; menu.size_flags_horizontal = Control.SIZE_SHRINK_END
	menu.custom_minimum_size.x = 44; menu.tooltip_text = "메뉴"
	if not is_instance_valid(ui.board):
		ui.board = Board.new(); ui.board.ui_font = FONT; ui.board.cell_pressed.connect(ui.on_cell)
		ui.board.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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
	for state in ["normal","hover","pressed","focus","disabled"]:
		log_button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	if session.manual_mode:
		log_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		log_button.autowrap_mode = TextServer.AUTOWRAP_OFF
		log_button.clip_text = true
		log_button.add_theme_font_size_override("font_size",12)
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
			ui.mark_selected(portrait)
		if actor.hp <= 0: portrait.modulate = Color("636369")
	if session.manual_mode:
		var spells := HBoxContainer.new(); spells.name = "SpellBar"; ui.root_layout.add_child(spells)
		for slot in range(Session.PREPARED_SLOTS):
			var prepared: Array = session.party[0].prepared
			var id: String = str(prepared[slot]) if slot < prepared.size() else ""
			var caption: String = str(Session.CombatStats.content.spells[id].name) if not id.is_empty() else "—"
			var spell = ui.button(spells,caption,func(): choose_spell(ui,id),not id.is_empty())
			if not id.is_empty(): spell.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR; spell.icon = Art.spell_icon(id); spell.add_theme_constant_override("icon_max_width",22)
			spell.name = "Spell%d" % slot; spell.custom_minimum_size.y = 44
	var nav := GridContainer.new(); nav.name = "BottomActions"; nav.columns = 4; ui.root_layout.add_child(nav)
	var attack = ui.action_button(nav,"공격",Art.ui_icon(0),func():
		if session.manual_mode:
			ui.mode = "ATTACK"; ui.show_attack_range = true; ui.refresh()
		else: ui.run_action(session.auto_attack),session.in_combat()); attack.name = "Attack"
	var wait = ui.action_button(nav,"대기",Art.ui_icon(2),func(): ui.run_action(func(): return session.act("WAIT",session.party[session.selected].pos))); wait.name = "Wait"; ui.wait_button = wait
	if session.manual_mode:
		var parts_button = ui.action_button(nav,"파츠",Art.ui_icon(4),func(): show_part_actions(ui),session.in_combat()); parts_button.name = "PartActions"
	if not session.manual_mode:
		var toggle = ui.action_button(nav,"⏸ 정지" if session.auto.running else "▶ 전투",Art.ui_icon(0),func(): AutoBattleHud.toggle_auto(ui),session.in_combat()); toggle.name = "AutoToggle"
		var speed = ui.button(nav,"%d×" % int(session.auto.speed),func(): AutoBattleHud.toggle_speed(ui)); speed.name = "SpeedToggle"
		var retreat = ui.action_button(nav,"후퇴 해제" if session.party_command == "RETREAT" else "후퇴",Art.ui_icon(20),func(): AutoBattleHud.toggle_retreat(ui),session.in_combat()); retreat.name = "RetreatToggle"
	ui.auto_explore_button = ui.action_button(nav,"중지" if ui.navigation.active else "자동탐험",Art.ui_icon(3),ui.toggle_explore,not session.in_combat() and not session.auto.running)
	ui.auto_explore_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	var camp = ui.action_button(nav,"야영",Art.ui_icon(19),func(): ui.run_action(session.camp),session.can_camp().is_empty() and not session.auto.running)
	camp.name = "CampButton"; camp.tooltip_text = session.can_camp()
	ui.action_button(nav,"가방",Art.ui_icon(5),func(): Popups.show_supplies(ui))
	if not session.manual_mode: build_stop_banner(ui)

static func build_manual_controls(ui) -> void:
	var session = ui.session
	var prepared: Array = session.party[0].prepared
	if not prepared.is_empty():
		var spells := HBoxContainer.new(); spells.name = "SpellBar"
		spells.add_theme_constant_override("separation",3); ui.root_layout.add_child(spells)
		for slot in range(Session.PREPARED_SLOTS):
			var id: String = str(prepared[slot]) if slot < prepared.size() else ""
			var caption: String = str(Session.CombatStats.content.spells[id].name) if not id.is_empty() else "—"
			var spell = ui.button(spells,caption,func(): choose_spell(ui,id),not id.is_empty())
			if not id.is_empty(): spell.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR; spell.icon = Art.spell_icon(id); spell.add_theme_constant_override("icon_max_width",22)
			spell.name = "Spell%d" % slot; spell.custom_minimum_size.y = 44
			spell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var portraits := HBoxContainer.new(); portraits.name = "PortraitRow"
	portraits.add_theme_constant_override("separation",4); ui.root_layout.add_child(portraits)
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var portrait = ui.button(portraits,"",func(): Popups.show_character(ui,i,"상태"))
		portrait.name = "HeroStatus" if i == 0 else "MemberStatus%d" % i
		portrait.custom_minimum_size.y = 82 if session.party.size() > 1 else 78
		portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait.size_flags_stretch_ratio = 1
		portrait.clip_contents = true
		if session.party.size() > 1:
			var compact := VBoxContainer.new(); compact.mouse_filter = Control.MOUSE_FILTER_IGNORE
			compact.add_theme_constant_override("separation",1)
			portrait.add_child(compact); compact.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			compact.offset_left = 5; compact.offset_right = -5; compact.offset_top = 3; compact.offset_bottom = -3
			var heading := HBoxContainer.new(); heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
			compact.add_child(heading)
			var icon := TextureRect.new(); icon.texture = Art.actor_portrait(actor)
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(40,40); icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; heading.add_child(icon)
			var name: Label = ui.label(heading,str(actor.name),11); name.clip_text = true
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var hp: Label = ui.label(compact,"HP%d/%d  MP%d/%d" % [actor.hp,actor.max_hp,actor.mp,actor.max_mp],9)
			hp.name = "HeroHP" if i == 0 else "MemberHP%d" % i
			hp.clip_text = true
			var state: Label = ui.label(compact,portrait_state(actor),9)
			state.name = "HeroState" if i == 0 else "MemberState%d" % i
			state.clip_text = true; state.tooltip_text = state.text
			continue
		var content := HBoxContainer.new(); content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation",6)
		portrait.add_child(content); content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 6; content.offset_right = -6; content.offset_top = 7; content.offset_bottom = -5
		var image := TextureRect.new(); image.texture = Art.actor_portrait(actor)
		image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size.x = 66 if session.party.size() == 1 else 42
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE; content.add_child(image)
		var values := VBoxContainer.new(); values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		values.add_theme_constant_override("separation",2); content.add_child(values)
		var name = ui.label(values,"%s  Lv.%d" % [actor.name,int(actor.level)],13 if session.party.size() == 1 else 11)
		name.add_theme_color_override("font_color",Color("e7d6b0"))
		var hp = ui.label(values,"HP %d/%d  ·  MP %d/%d" % [actor.hp,actor.max_hp,actor.mp,actor.max_mp],11)
		hp.name = "HeroHP" if i == 0 else "MemberHP%d" % i
		hp.clip_text = true
		var state = ui.label(values,portrait_state(actor),10)
		state.name = "HeroState" if i == 0 else "MemberState%d" % i
		state.clip_text = true; state.tooltip_text = state.text
	var nav := HBoxContainer.new(); nav.name = "BottomActions"
	nav.add_theme_constant_override("separation",3); ui.root_layout.add_child(nav)
	var attack = ui.action_button(nav,"공격",Art.ui_icon(0),func(): arm_attack(ui)); attack.name = "Attack"
	var wait = ui.action_button(nav,"대기",Art.ui_icon(2),func(): ui.run_action(func(): return session.act("WAIT",session.party[0].pos))); wait.name = "Wait"; ui.wait_button = wait
	ui.auto_explore_button = ui.action_button(nav,"중지" if ui.navigation.active else "탐색",Art.ui_icon(3),ui.toggle_explore,not session.in_combat())
	ui.auto_explore_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	var tactics = ui.action_button(nav,"전술",Art.ui_icon(4),func(): show_manual_tactics(ui)); tactics.name = "Tactics"
	ui.action_button(nav,"가방",Art.ui_icon(5),func(): Popups.show_supplies(ui))
	for action in nav.get_children():
		action.custom_minimum_size.y = 54
		action.add_theme_font_size_override("font_size",11)
		action.add_theme_constant_override("icon_max_width",16)
		for state in ["normal","hover","pressed","focus","disabled"]:
			var style: StyleBox = action.get_theme_stylebox(state).duplicate()
			style.content_margin_left = 3
			style.content_margin_right = 3
			action.add_theme_stylebox_override(state,style)

static func build_stop_banner(ui) -> void:
	var banner = ui.label(ui.root_layout,ui.stop_text,15)
	banner.name = "StopBanner"; banner.visible = not ui.stop_text.is_empty()
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; banner.clip_text = true

static func arm_attack(ui) -> void:
	if ui.session == null or not ui.session.manual_mode: return
	var session = ui.session
	var hero: Dictionary = session.party[0]
	var targets: Array = session.enemies.filter(func(enemy): return enemy.hp > 0 and session.floor_state.visible.has(enemy.pos))
	if targets.is_empty(): return
	if session.party_command == "ATTACK_TARGET":
		var marked: Array = targets.filter(func(enemy): return enemy.id == session.command_target)
		if not marked.is_empty(): targets = marked
	targets.sort_custom(func(a,b):
		var da: int = session.distance(hero.pos,a.pos)
		var db: int = session.distance(hero.pos,b.pos)
		return da < db if da != db else a.id < b.id)
	for enemy in targets:
		if not session.attack_preview(enemy.pos).is_empty() and not session.status_blocks(hero,"ATTACK"):
			ui.run_action(func(): return session.act("ATTACK",enemy.pos))
			return
	if session.status_blocks(hero,"MOVE"): return
	var reach: int = int(Session.CombatStats.stats(session,hero).range)
	var goals: Array = []
	for enemy in targets:
		for y in range(maxi(0,enemy.pos.y-reach),mini(session.BOARD_SIDE,enemy.pos.y+reach+1)):
			for x in range(maxi(0,enemy.pos.x-reach),mini(session.BOARD_SIDE,enemy.pos.x+reach+1)):
				var cell := Vector2i(x,y)
				if not session.floor_state.visible.has(cell) or not session.is_free(cell): continue
				var in_reach: bool = session.melee_reach(cell,enemy.pos) if reach <= 1 else Session.Floor.MonsterAI.line(session,cell,enemy.pos,reach)
				if not in_reach: continue
				if cell not in goals: goals.append(cell)
	if goals.is_empty(): return
	var route: Dictionary = session.TurnCore.path(session.BOARD_SIDE,session.BOARD_SIDE,hero.pos,goals,
		func(a,b): return session.floor_state.visible.has(b) and session.can_step(a,b),func(_p): return 100)
	if route.found and route.path.size() > 1: ui.run_action(func(): return session.act("MOVE",route.path[1]))

static func show_manual_tactics(ui) -> void:
	var session = ui.session
	if session == null or not session.manual_mode: return
	ui.clear(ui.modal_content)
	ui.modal_content.custom_minimum_size = Vector2(ui.popup_width(),0)
	var box := VBoxContainer.new(); box.name = "ManualTactics"
	box.add_theme_constant_override("separation",4); ui.modal_content.add_child(box)
	var header := HBoxContainer.new(); box.add_child(header)
	var title = ui.label(header,"전술",18); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.button(header,"×",func(): ui.details_popup.hide()).custom_minimum_size.x = 44
	var actor: Dictionary = session.party[0]
	var targets: Array = session.combat_enemies().filter(func(enemy): return session.floor_state.visible.has(enemy.pos))
	var focus = ui.button(box,"집중 공격",func():
		ui.details_popup.hide(); ui.mode = "COMMAND_TARGET"; ui.refresh(),not targets.is_empty())
	focus.name = "TacticFocus"
	if session.party.size() == 1:
		var hold = ui.button(box,"제자리 대기",func():
			ui.details_popup.hide(); ui.run_action(func(): return session.act("WAIT",actor.pos)))
		hold.name = "TacticHold"
	else:
		for row in [["STOP_ATTACK","집합"],["HOLD_POSITION","자리 지키기"],["RETREAT","후퇴"],["FOLLOW","따라오기"]]:
			var command: String = row[0]
			var pick = ui.button(box,str(row[1]),func(): choose_party_command(ui,command),
				session.in_combat() or command in ["HOLD_POSITION","FOLLOW","STOP_ATTACK"])
			pick.name = "Tactic_"+command
			pick.toggle_mode = true; pick.button_pressed = session.party_command == command
	var skills = ui.button(box,"기술",func(): show_manual_skills(ui),not actor.prepared.is_empty() or not Session.Abilities.held(actor).is_empty())
	skills.name = "TacticSkills"
	center_tactics_popup(ui,204 if session.party.size() == 1 else 348)

static func show_manual_skills(ui) -> void:
	var session = ui.session
	if session == null or not session.manual_mode: return
	ui.clear(ui.modal_content)
	ui.modal_content.custom_minimum_size = Vector2(ui.popup_width(),0)
	var box := VBoxContainer.new(); box.name = "ManualSkills"; ui.modal_content.add_child(box)
	var header := HBoxContainer.new(); box.add_child(header)
	var title = ui.label(header,"기술",18); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.button(header,"×",func(): ui.details_popup.hide()).custom_minimum_size.x = 44
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.y = minf(330,ui.size.y-220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; box.add_child(scroll)
	var choices := VBoxContainer.new(); choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(choices)
	var actor: Dictionary = session.party[0]
	if not actor.prepared.is_empty(): ui.label(choices,"주문",15)
	for id in actor.prepared:
		var spell_id: String = str(id)
		var definition: Dictionary = Session.CombatStats.content.spells.get(spell_id,{})
		var spell = ui.button(choices,"%s   ·   MP %d" % [str(definition.get("name",spell_id)),int(definition.get("mp",0))],func(): ui.details_popup.hide(); choose_spell(ui,spell_id),actor.mp >= int(definition.get("mp",0)))
		spell.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR; spell.icon = Art.spell_icon(spell_id); spell.add_theme_constant_override("icon_max_width",28)
		spell.name = "Spell_"+spell_id
		spell.alignment = HORIZONTAL_ALIGNMENT_LEFT; spell.custom_minimum_size.y = 54
	if not Session.Abilities.held(actor).is_empty(): ui.label(choices,"파츠",15)
	for id in Session.Abilities.held(actor):
		var part_id: String = str(id)
		if part_id.is_empty() or not Session.Abilities.usable_by(actor,part_id): continue
		var def: Dictionary = Session.Abilities.definition(part_id)
		var available: bool = session.in_combat() and int(actor.cooldowns.get(part_id,0)) <= 0
		if def.target == "SELF": available = available and Session.Abilities.legal(session,actor,part_id,actor.pos)
		var part = ui.button(choices,"%s   ·   %d턴" % [str(def.name),int(actor.cooldowns.get(part_id,0))],func(): choose_part(ui,part_id),available)
		part.name = "Part_"+part_id
		part.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR; part.icon = Art.part_icon(part_id); part.add_theme_constant_override("icon_max_width",28)
		part.alignment = HORIZONTAL_ALIGNMENT_LEFT; part.custom_minimum_size.y = 54
	ui.button(box,"전술",func(): show_manual_tactics(ui))
	center_tactics_popup(ui,roundi(scroll.custom_minimum_size.y)+112)

static func center_tactics_popup(ui, height: int) -> void:
	var screen: Vector2i = Vector2i(ui.get_viewport_rect().size)
	var popup_size := Vector2i(roundi(ui.popup_width())+16,mini(height,screen.y-16))
	ui.details_popup.popup_centered(popup_size)
	ui.details_popup.size = popup_size
	ui.details_popup.position = (screen-popup_size)/2

static func choose_party_command(ui, command: String) -> void:
	if not ui.session.issue_party_command(command): return
	ui.details_popup.hide(); ui.mode = ""; ui.notice = ""; ui.refresh()

static func show_part_actions(ui) -> void:
	var session = ui.session
	if session == null or not session.manual_mode or not session.in_combat(): return
	ui.clear(ui.modal_content)
	var box := VBoxContainer.new(); box.name = "PartActionMenu"; ui.modal_content.add_child(box)
	ui.label(box,"파츠",20)
	var actor: Dictionary = session.party[0]
	for id in Session.Abilities.held(actor):
		if str(id).is_empty() or not Session.Abilities.usable_by(actor,str(id)): continue
		var def: Dictionary = Session.Abilities.definition(id)
		var available: bool = int(actor.cooldowns.get(id,0)) <= 0
		if def.target == "SELF": available = Session.Abilities.legal(session,actor,str(id),actor.pos)
		var choice = ui.button(box,str(def.name),func(): choose_part(ui,str(id)),available)
		choice.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR; choice.icon = Art.part_icon(str(id)); choice.add_theme_constant_override("icon_max_width",28)
		choice.custom_minimum_size.y = 44
	ui.button(box,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()

static func choose_part(ui, id: String) -> void:
	var session = ui.session
	if session == null or not Session.Abilities.has(id): return
	ui.details_popup.hide()
	var actor: Dictionary = session.party[0]
	if Session.Abilities.definition(id).target == "SELF":
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

static func choose_item(ui, kind: String) -> void:
	ui.stop_navigation()
	ui.reservation_actor = -1
	ui.pending_attack = {}
	ui.mode = ""; ui.pending_item = kind
	ui.notice = ui.session.item_label(kind)+" · 대상 칸 선택"; ui.refresh()

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
	session.selected = index; ui.mode = ""; ui.pending_item = ""; ui.notice = session.party[index].name; ui.refresh()
