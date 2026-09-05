extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const TerrainRegistry=preload("res://sim/terrain_registry.gd")
const VisualMap=preload("res://playtest/party_visual_test_map.gd")
const AsciiGaugeScript=preload("res://playtest/ascii_gauge.gd")
const AUTO_INTENDED_CADENCE_MSEC:=190
const AUTO_HEADLESS_GROSS_CEILING_MSEC:=310

var failures:Array[String]=[]

func _init()->void:call_deferred("_run")

func _run()->void:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:await _check_viewport(viewport_size)
	if failures.is_empty():print("PASS fixed-cell DOS UI smoke: 360x640, 450x800")
	else:
		for failure in failures:print("FAIL fixed-cell DOS UI smoke -- ",failure)
	quit(1 if not failures.is_empty() else 0)

func _check_viewport(viewport_size:Vector2)->void:
	var sandbox=Sandbox.new();sandbox.name="DOSPartySandbox";root.add_child(sandbox)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.position=Vector2.ZERO;sandbox.size=viewport_size
	sandbox.initialize_for_headless_test(Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID),true)
	await process_frame;await process_frame
	_check(not bool(sandbox.session.opening_event_status().get("can_interact",false)) \
		and sandbox.product_auto_button.text=="[AUTO]" \
		and sandbox.product_interact_button.text=="[INTERACT]",
		"%s opening event was exposed before the actor was discovered"%viewport_size)
	_check(sandbox.theme.default_font.resource_path=="res://assets/fonts/LivingWorldMonoKR.ttf",
		"%s UI default is not bundled Coding font"%viewport_size)
	_check(sandbox.theme.default_font_size==16,
		"%s party UI body typography did not shrink to 16px"%viewport_size)
	_check(sandbox.root_layout.get_global_rect().size.is_equal_approx(viewport_size),
		"%s product layout is not full bleed"%viewport_size)
	_check(sandbox.build_label!=null and sandbox.build_label.text=="BUILD LOCAL" \
		and sandbox.build_label.mouse_filter==Control.MOUSE_FILTER_IGNORE,
		"%s local build label is missing or intercepts input"%viewport_size)
	_check(_inside_rect(sandbox,sandbox.build_label),
		"%s build label clips the viewport"%viewport_size)
	_check(_inside_rect(sandbox.event_surface,sandbox.build_label) \
		and not sandbox.build_label.get_global_rect().intersects(sandbox.event_label.get_global_rect()),
		"%s build label is not isolated in the event surface"%viewport_size)
	var grid_size_before_build_probe:Vector2=sandbox.grid.size
	var action_visibility_before_probe:bool=sandbox.combat_action_area.visible
	sandbox.combat_action_area.visible=true;sandbox._position_build_label();await process_frame
	sandbox._position_build_label();await process_frame
	_check(not sandbox.build_label.get_global_rect().intersects(
		sandbox.combat_action_area.get_global_rect()),
		"%s build label %s overlaps bottom action rect %s"%[viewport_size,
			sandbox.build_label.get_global_rect(),sandbox.combat_action_area.get_global_rect()])
	sandbox.combat_action_area.visible=action_visibility_before_probe
	sandbox._position_build_label();await process_frame
	_check(sandbox.grid.size.is_equal_approx(grid_size_before_build_probe),
		"%s absolute build overlay changed the map footprint"%viewport_size)
	_check(sandbox.grid.size.x>=viewport_size.x-1.0,"%s map lost full width"%viewport_size)
	_check(sandbox.grid.visible_cell_count==19,
		"%s product camera did not use the requested 19-cell default"%viewport_size)
	_check(not sandbox.phase_panel.visible and sandbox.phase_panel.custom_minimum_size.y==0.0 \
		and not sandbox.top_hud_actions.visible \
		and sandbox.find_child("Ascii3DLabButton",true,false)==null,
		"%s obsolete product top rail remains visible"%viewport_size)
	if viewport_size.x>=450.0:
		_check(sandbox.grid.size.is_equal_approx(Vector2(450,450)),
			"%s logical map footprint changed from 450x450: %s"%[viewport_size,sandbox.grid.size])
	var card=sandbox.cards.get_child(0) as Button
	var card_content=card.find_child("CardContent",true,false) as Control
	_check(card.find_child("DossierAsciiFrame",true,false)==null \
		and card_content!=null and _inside_rect(card,card_content),
		"%s compact status strip retained a nested dossier frame"%viewport_size)
	var solo_identity=card.find_child("SoloIdentity",true,false) as Control
	var actor_seal=card.find_child("ActorGlyphSeal",true,false) as Label
	_check(card.find_child("Portrait",true,false)==null and solo_identity!=null \
		and actor_seal!=null and actor_seal.text=="@" and actor_seal.custom_minimum_size.x==44,
		"%s solo dossier did not use the 44px ASCII actor seal"%viewport_size)
	_check(int(sandbox.party_card_layout_spec(1,viewport_size.x).party_height)==68 \
		and int(sandbox.party_card_layout_spec(2,viewport_size.x).party_height)==80 \
		and int(sandbox.party_card_layout_spec(3,viewport_size.x).party_height)==84,
		"%s responsive status heights differ from 68/80/84"%viewport_size)
	for contract in [["MapNavigation","[지도]"],["PersonNavigation","[인물]"],
			["SkillNavigation","[숙련]"],["EquipmentNavigation","[장비]"],
			["HistoryNavigation","[기록]"]]:
		var action=sandbox.find_child(str(contract[0]),true,false) as Button
		_check(action!=null and action.text==str(contract[1]) and "\n" not in action.text \
			and bool(action.get_meta("ascii_rail",false)) and action.custom_minimum_size==Vector2(44,44),
			"%s %s is not a single-line DOS command"%[viewport_size,contract[0]])
		_check(_inside_rect(sandbox.bottom_navigation,action),
			"%s %s overflows the fixed bottom navigation"%[viewport_size,contract[0]])
	_check(sandbox.combat_action_area.visible and sandbox.action_feedback_label.visible==false \
		and sandbox.combat_action_dock.visible,
		"%s product movement/context dock is not persistently visible"%viewport_size)
	var control_metrics:Dictionary=sandbox._product_controls_metrics(1)
	var expected_target:=44 if viewport_size.x>=450.0 else 40
	_check(int(control_metrics.get("target",0))==expected_target,
		"%s product direction target is not the intended compact size"%viewport_size)
	var direction_rects:Array[Rect2]=[]
	for direction in [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),
			Vector2i.ZERO,Vector2i(1,0),Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1)]:
		var direction_button=sandbox.product_direction_buttons.get(direction) as Button
		_check(direction_button!=null and direction_button.custom_minimum_size==Vector2(expected_target,expected_target) \
			and bool(direction_button.get_meta("ascii_rail",false)) \
			and direction_button.get_theme_stylebox("pressed")!=direction_button.get_theme_stylebox("normal"),
			"%s direction %s lacks an independent pressed real-Button target"%[viewport_size,direction])
		if direction_button!=null:direction_rects.append(direction_button.get_global_rect())
	for first in range(direction_rects.size()):
		for second in range(first+1,direction_rects.size()):
			_check(not direction_rects[first].intersects(direction_rects[second]),
				"%s direction hit rects overlap: %s / %s"%[viewport_size,first,second])
	for button in [sandbox.product_attack_button,sandbox.product_pickup_button,sandbox.product_auto_button,
			sandbox.product_interact_button,sandbox.product_wait_guard_button,
			sandbox.product_execute_button]:
		_check(button is Button and bool(button.get_meta("product_control",false)) \
			and _inside_rect(sandbox.combat_action_dock,button),
			"%s contextual control is not a real contained Button"%viewport_size)
	_check(sandbox.product_interact_button.disabled,
		"%s unavailable INTERACT backend was exposed as a dummy action"%viewport_size)
	_check(not sandbox.product_auto_button.disabled and sandbox.product_auto_button.toggle_mode \
		and sandbox.product_attack_button.visible and not sandbox.product_attack_button.disabled \
		and sandbox.product_attack_button.text=="[공격]" \
		and sandbox.product_pickup_button.visible and not sandbox.product_pickup_button.disabled \
		and sandbox.product_pickup_button.text.begins_with("[줍기") \
		and not sandbox.product_wait_guard_button.disabled \
		and sandbox.product_execute_button.disabled,
		"%s exploration contextual controls do not match AUTO/ATTACK/WAIT/EXECUTE authority"%viewport_size)
	var attack_session=_baseline_solo_session(44)
	var attack_probe=Sandbox.new();root.add_child(attack_probe)
	attack_probe.initialize_for_headless_test(attack_session,true)
	var attack_time:=int(attack_session.sim.world.world_time)
	var attack_origin:Vector2i=attack_session.sim.world.entities[
		attack_session.sim.world.party_encounter.protagonist_id].position
	attack_probe._on_product_attack()
	var attack_position:Vector2i=attack_session.sim.world.entities[
		attack_session.sim.world.party_encounter.protagonist_id].position
	_check(int(attack_session.sim.world.world_time)==attack_time+100 \
		and attack_position!=attack_origin,
		"%s ATTACK did not spend one turn approaching the nearest visible enemy"%viewport_size)
	attack_probe.queue_free()
	sandbox._refresh();await process_frame;await process_frame
	_check(sandbox.event_surface.visible and sandbox.event_label.max_lines_visible==2 \
		and not sandbox.info_scroll.visible and not sandbox.deck.visible and not sandbox.log_label.visible,
		"%s compact event surface did not replace generic context/log copies"%viewport_size)
	_check(sandbox._compact_meaningful_event_text({"groups":[]},{"safe_phase":"ENGAGED"}).is_empty() \
		and sandbox._compact_meaningful_event_text({"groups":[]},{"safe_phase":"GROUPED"}).is_empty(),
		"%s empty event history synthesized product-log filler"%viewport_size)
	var compact_history:Dictionary={"groups":[
		{"rows":[{"type":"combat.physical_damage","message":"오래된 피해"}]},
		{"rows":[{"type":"item.pickup","message":"새 아이템을 주웠다."}]}
	]}
	_check(sandbox._compact_meaningful_event_text(compact_history,{})=="새 아이템을 주웠다.",
		"%s compact event feed stayed pinned to older combat damage"%viewport_size)
	var visible_product_nodes:Array=[sandbox.cards,sandbox.grid,sandbox.event_surface]
	if sandbox.combat_action_area.visible:visible_product_nodes.append(sandbox.combat_action_area)
	visible_product_nodes.append(sandbox.bottom_navigation)
	for index in range(1,visible_product_nodes.size()):
		_check(visible_product_nodes[index-1].get_global_rect().end.y<=visible_product_nodes[index].get_global_rect().position.y+0.5,
			"%s Pixel HUD vertical order overlaps at %s"%[viewport_size,visible_product_nodes[index].name])
	_check(absf(sandbox.bottom_navigation.get_global_rect().end.y-viewport_size.y)<=0.5,
		"%s bottom navigation is not fixed to the viewport foot: %s"%[
			viewport_size,sandbox.bottom_navigation.get_global_rect()])
	var hp=sandbox.find_child("MemberState",true,false)
	var xp=sandbox.find_child("CompactXPBar",true,false)
	_check(_gauge_ok(hp,"HP") and _gauge_ok(xp,"XP"),"%s dossier lacks visible #/. DOS gauges"%viewport_size)
	_check(_semantic_gauge_ok(hp,"HP",AsciiGaugeScript.HP_FILL) \
		and _semantic_gauge_ok(xp,"XP",AsciiGaugeScript.XP_FILL),
		"%s dossier HP/XP filled # cells lack semantic red/green ink"%viewport_size)
	_check(int(hp.gauge_spec().font_size)==14 and int(xp.gauge_spec().font_size)==14,
		"%s DOS gauges did not use the reduced readable UI size"%viewport_size)
	_check(sandbox.find_children("*","ProgressBar",true,false).is_empty(),
		"%s solo DOS HUD still contains a visible modern ProgressBar"%viewport_size)
	var command_probe:=HBoxContainer.new();sandbox.add_child(command_probe)
	var execute=sandbox._add_button(command_probe,"지금 실행","TurnConfirm",func():pass)
	_check(execute.text=="[E 실행]" and execute.custom_minimum_size.y>=44 \
		and bool(execute.get_meta("dos_command",false)),"%s bottom command grammar missing"%viewport_size)
	command_probe.queue_free()
	var compact_rows:Array=[]
	for index in range(3):
		compact_rows.append({"entity_id":index+1,"display_name":"원정대원%d"%(index+1),
			"role":"PROTAGONIST" if index==0 else "COMPANION","health":8-index,
			"max_health":10,"stress":index*20,"readiness":"행동 준비","status_ids":[],
			"emotion":{"icon":"·","label":"평온"},"progression":{"available":true,
				"level":2,"xp_current":3,"xp_required":10}})
	var speeches:Array=[{"actor_id":2,"headline":"방어할게.","reason_summary":"피해를 줄이려고"}]
	sandbox.render_party_cards_for_headless_test(compact_rows,speeches);await process_frame
	for compact_card in sandbox.cards.get_children():
		var compact_content=compact_card.find_child("CardContent",true,false) as Control
		_check(compact_content!=null and _inside_rect(compact_card,compact_content),
			"%s 3-member status content escaped strip card=%s content=%s"%[
				viewport_size,compact_card.get_global_rect(),compact_content.get_global_rect()])
	var speech_text=sandbox.find_child("CompanionSpeechText",true,false) as Label
	_check(speech_text!=null and "\n" not in speech_text.text and speech_text.max_lines_visible==1,
		"%s companion speech is not one compact line"%viewport_size)
	var compact_event_before:String=sandbox.event_label.text
	sandbox.map_nav_button.pressed.emit();await process_frame
	_check(sandbox.map_overlay.visible and sandbox.map_nav_button.button_pressed \
		and sandbox.grid.modal_open and bool(sandbox.map_overlay.overlay_spec().stores_compact_scalars_only),
		"%s map navigation did not open the leak-safe discovered-map modal"%viewport_size)
	sandbox.map_nav_button.pressed.emit();await process_frame
	_check(not sandbox.map_overlay.visible and not sandbox.map_nav_button.button_pressed,
		"%s map navigation toggle did not close and synchronize"%viewport_size)
	sandbox.history_nav_button.pressed.emit();await process_frame
	_check(sandbox.record_modal.visible and sandbox.history_nav_button.button_pressed \
		and not sandbox.record_body.text.is_empty() and sandbox.event_label.text==compact_event_before,
		"%s history modal replaced or emptied the compact event surface"%viewport_size)
	sandbox.history_nav_button.pressed.emit();await process_frame
	_check(not sandbox.record_modal.visible and not sandbox.history_nav_button.button_pressed,
		"%s history navigation toggle did not close and synchronize"%viewport_size)

	sandbox.skill_nav_button.pressed.emit();await process_frame;await process_frame
	_check(sandbox.member_detail_current_tab=="SKILL" and sandbox.member_progression_window.visible,
		"%s skill navigation did not open hero directly on SKILL"%viewport_size)
	sandbox._close_member_detail();sandbox.equipment_nav_button.pressed.emit();await process_frame
	_check(sandbox.member_detail_current_tab=="ITEM" and sandbox.member_item_window.visible,
		"%s equipment navigation did not open hero directly on ITEM"%viewport_size)
	sandbox._close_member_detail();sandbox.person_nav_button.pressed.emit();await process_frame;await process_frame
	var panel=sandbox.member_detail_panel;var folio=sandbox.find_child("MemberDetailAsciiFrame",true,false)
	var stack=sandbox.find_child("MemberDetailStack",true,false) as Control
	_check(panel.get_global_rect().end.x<=viewport_size.x+0.5 and panel.get_global_rect().end.y<=viewport_size.y+0.5,
		"%s DOS folio clips viewport: %s"%[viewport_size,panel.get_global_rect()])
	_check(_fixed_frame_ok(folio) and panel.get_child_count()==1 and panel.get_child(0)==folio \
		and _single_nested(folio,stack),"%s folio hierarchy is not Panel -> Frame -> Stack"%viewport_size)
	_check(int(folio.frame_spec().font_size)==14,
		"%s full-size modal frame did not use reduced 14px cells"%viewport_size)
	_check(_strictly_inside(folio,stack),"%s folio content touches border cells"%viewport_size)
	var detail_header=sandbox.find_child("MemberDetailHeader",true,false) as Control
	var detail_seal=sandbox.find_child("MemberDetailGlyphSeal",true,false) as Label
	_check(detail_header!=null and detail_header.custom_minimum_size.y==52 \
		and detail_seal!=null and detail_seal.custom_minimum_size==Vector2(44,44) \
		and sandbox.member_detail_close.custom_minimum_size==Vector2(44,44),
		"%s compact detail identity header contract is missing"%viewport_size)
	_check(sandbox.find_child("StatusIdentityPanel",true,false)==null \
		and sandbox.find_child("StatusIdentityAsciiFrame",true,false)==null,
		"%s status tab still duplicates the header identity/frame"%viewport_size)
	var status_grid=sandbox.find_child("StatusFolioGrid",true,false) as GridContainer
	_check(status_grid!=null and status_grid.columns==2,
		"%s status emotion/combat sections are not a 2-column folio"%viewport_size)
	_check(sandbox.find_child("MemberDetailPortrait",true,false)==null \
		and sandbox.find_child("StatusPortrait",true,false)==null,
		"%s member folio still duplicates the map actor as a portrait"%viewport_size)
	_check(_gauge_ok(sandbox.find_child("StatusHealthBar",true,false),"HP"),
		"%s status tab health is not a DOS gauge"%viewport_size)
	_check(_semantic_gauge_ok(sandbox.find_child("StatusHealthBar",true,false),
		"HP",AsciiGaugeScript.HP_FILL),
		"%s status tab HP filled # cells are not red"%viewport_size)
	_check(sandbox.member_detail_status_tab.text=="[상태]" and "◆" not in sandbox.member_detail_status_tab.text,
		"%s DOS tab selection grammar missing"%viewport_size)
	for tab in [sandbox.member_detail_status_tab,sandbox.member_detail_skill_tab,
			sandbox.member_detail_item_tab]:
		_check(tab.custom_minimum_size.y>=44 and _inside_rect(sandbox.member_detail_tab_row,tab),
			"%s detail tab text/target overflows its rail"%viewport_size)

	sandbox._select_member_detail_tab("SKILL");await process_frame;await process_frame
	_check(sandbox.member_detail_skill_tab.text=="[숙련]","%s selected skill tab is not bracketed"%viewport_size)
	sandbox._toggle_weapon_mastery_category();await process_frame
	var equipped_skill_rows:=0;var focused_skill_rows:=0
	for skill_id in ["SWORD","AXE","BLUNT","SPEAR","RANGED","UNARMED"]:
		var skill_panel=sandbox.find_child("SkillCard%s"%skill_id,true,false)
		_check(skill_panel.find_child("SkillAsciiFrame",true,false)==null,
			"%s %s still has a nested ASCII frame"%[viewport_size,skill_id])
		var mode_button=skill_panel.find_child("SkillModeButton",true,false)
		var rank_label=skill_panel.find_child("SkillRank",true,false) as Label
		var name_label=skill_panel.find_child("SkillName",true,false) as Label
		var effect_label=skill_panel.find_child("CurrentEffect",true,false) as Label
		var mode_label=skill_panel.find_child("TrainingMode",true,false) as Label
		var xp_label=skill_panel.find_child("TrainingXP",true,false) as Label
		_check(mode_button is Button and mode_button.custom_minimum_size.y>=44 \
			and skill_panel.custom_minimum_size.y==44,
			"%s %s training mode is not touch sized"%[viewport_size,skill_id])
		var raw_weight:=int(mode_button.get_meta("raw_training_weight",-1))
		var transparent_style:StyleBoxFlat=mode_button.get_theme_stylebox("normal") as StyleBoxFlat
		_check(bool(mode_button.get_meta("no_button_chrome",false)) and transparent_style!=null \
			and transparent_style.bg_color.a==0.0 and transparent_style.border_width_left==0 \
			and mode_button.text.is_empty() and raw_weight in [0,1,3],
			"%s %s ledger row shows chrome or a non-authoritative XP multiplier"%[viewport_size,skill_id])
		_check(rank_label!=null and rank_label.text.begins_with("R") \
			and name_label!=null and not name_label.text.is_empty() \
			and effect_label!=null and "명중" in effect_label.text and "피해" in effect_label.text \
			and mode_label!=null and "×%d"%raw_weight in mode_label.text \
			and xp_label!=null and "/" in xp_label.text,
			"%s %s fixed ledger omits rank/name/effect/mode/current XP"%[viewport_size,skill_id])
		var equipped:=bool(mode_button.get_meta("equipped_proficiency",false))
		if equipped:equipped_skill_rows+=1
		if raw_weight==3:focused_skill_rows+=1
		var expected_tone:=AsciiUIFrame.BRASS if equipped or raw_weight==3 \
			else (AsciiUIFrame.MUTED if raw_weight==0 else AsciiUIFrame.CYAN)
		_check(mode_label.get_theme_color("font_color").is_equal_approx(expected_tone),
			"%s %s ledger mode tone does not match its 3/1/0 state"%[viewport_size,skill_id])
		_check(("장착·" in mode_label.text)==equipped \
			and bool(mode_button.get_meta("training_paused",false))==(raw_weight==0),
			"%s %s ledger loses equipped/temporary-OFF semantics"%[viewport_size,skill_id])
		if raw_weight==0:
			_check("중지×0" in mode_label.text,
				"%s %s paused mastery is not labelled as resumable stop"%[viewport_size,skill_id])
		_check(mode_label.get_global_rect().end.x<=xp_label.get_global_rect().position.x+0.5 \
			and xp_label.get_global_rect().end.x<=skill_panel.get_global_rect().end.x+0.5,
			"%s %s current XP is not the far-right ledger column"%[viewport_size,skill_id])
	_check(equipped_skill_rows==1 and focused_skill_rows==1,
		"%s new expedition does not start with exactly its equipped weapon focused"%viewport_size)
	_check(sandbox.find_child("SkillDetail",true,false)==null \
		and sandbox.find_child("TrainingProgress",true,false)==null \
		and sandbox.find_child("FutureMilestone",true,false)==null,
		"%s proficiency selection still creates extra detail content"%viewport_size)
	_check(panel.get_global_rect().end.x<=viewport_size.x+0.5,
		"%s fixed skill ledger widened/clipped the 420px folio"%viewport_size)
	var zoom_before_item:int=int(sandbox.grid.visible_cell_count)
	sandbox._select_member_detail_tab("ITEM");await process_frame;await process_frame
	_check(sandbox.member_item_window.visible and sandbox.member_detail_item_tab.text=="[아이템]",
		"%s item tab is not independently selectable"%viewport_size)
	var combat_summary=sandbox.find_child("EquippedCombatSummary",true,false) as Label
	var equipment_slot_rows:=0
	for item_control in sandbox.member_item_equipment_rows.get_children():
		if item_control is Button and item_control.has_meta("item_instance_id"):
			equipment_slot_rows+=1
	_check(combat_summary!=null and "공격" in combat_summary.text \
		and "방어" in combat_summary.text and "회피" in combat_summary.text \
		and "막기" in combat_summary.text and "장착" not in combat_summary.text \
		and sandbox.member_item_ammo_text.custom_minimum_size.y>=44 \
		and equipment_slot_rows==5 \
		and sandbox.member_item_backpack_rows.get_child_count()==12 \
		and sandbox.member_item_drop_button.custom_minimum_size.y>=44,
		"%s item/status UI lacks one-line stats, 5 slots, 12 backpack rows, or 44px popover actions"%viewport_size)
	_check(sandbox.member_item_backpack_rows.is_visible_in_tree() \
		and not sandbox.member_item_equipment_rows.is_visible_in_tree(),
		"%s item tab does not lead directly with the bag"%viewport_size)
	_check(sandbox.member_item_equip_button.custom_minimum_size.y>=44 \
		and sandbox.member_item_unequip_button.custom_minimum_size.y>=44 \
		and sandbox.member_item_use_button.custom_minimum_size.y>=44 \
		and sandbox.member_item_drop_button.custom_minimum_size.y>=44 \
		and sandbox.member_item_drop_button.text=="[버리기]",
		"%s product item actions do not meet the touch-safe equipment/consumable contract"%viewport_size)
	sandbox._on_item_row_selected("START_POTION_001","");await process_frame
	var item_ascii_frame=sandbox.find_child("ItemDetailAsciiFrame",true,false)
	_check(sandbox.member_item_popover.visible and sandbox.member_item_use_button.visible \
		and not sandbox.member_item_use_button.disabled \
		and sandbox.member_item_use_button.text=="[사용]" \
		and item_ascii_frame!=null \
		and str(item_ascii_frame.frame_spec().get("primitive",""))=="FIXED_CELL_GLYPHS",
		"%s healing potion popover lacks a usable action or ASCII glyph border"%viewport_size)
	sandbox._hide_item_popover()
	_check(panel.get_global_rect().end.x<=viewport_size.x+0.5,
		"%s item tab widened/clipped the detail folio"%viewport_size)
	var item_scroll:ScrollContainer=sandbox.member_detail_scroll as ScrollContainer
	var item_scroll_bar:VScrollBar=item_scroll.get_v_scroll_bar()
	_check(item_scroll.clip_contents and item_scroll_bar.max_value>item_scroll_bar.page,
		"%s 5+12 row item ledger is not vertically scrollable scroll=%s max=%s page=%s content=%s"%[
			viewport_size,item_scroll.size,item_scroll_bar.max_value,item_scroll_bar.page,
			sandbox.member_item_window.size])
	for ledger in [sandbox.member_item_equipment_rows,sandbox.member_item_backpack_rows]:
		var previous_bottom:=-INF
		for row in ledger.get_children():
			if not row is Button:continue
			_check(row.custom_minimum_size.y>=44 and row.size.y>=43.9,
				"%s item ledger row is below 44px: %s"%[viewport_size,row.name])
			_check(row.position.y>=previous_bottom-0.1,
				"%s item ledger rows overlap: %s"%[viewport_size,row.name])
			previous_bottom=row.position.y+row.size.y
	item_scroll.scroll_vertical=int(item_scroll_bar.max_value);await process_frame;await process_frame
	var scroll_rect:Rect2=item_scroll.get_global_rect()
	var last_bag_row:=sandbox.member_item_backpack_rows.get_child(
		sandbox.member_item_backpack_rows.get_child_count()-1) as Control
	var last_bag_rect:Rect2=last_bag_row.get_global_rect()
	var scroll_content:=item_scroll.get_child(0) as Control
	var item_scroll_diagnostic:="%s final bag row is not reachable at scroll end scroll=%s row=%s value=%s " \
		+ "bar(max=%s page=%s) content(size=%s min=%s) item(size=%s min=%s pos=%s) action(local=%s min=%s)"
	_check(scroll_rect.intersection(last_bag_rect).size.y>=43.9,
		item_scroll_diagnostic%[
			viewport_size,scroll_rect,last_bag_rect,item_scroll.scroll_vertical,
			item_scroll_bar.max_value,item_scroll_bar.page,
			scroll_content.size if scroll_content!=null else Vector2(),
			scroll_content.get_combined_minimum_size() if scroll_content!=null else Vector2(),
			sandbox.member_item_window.size,sandbox.member_item_window.get_combined_minimum_size(),
			sandbox.member_item_window.position,
			last_bag_row.position,last_bag_row.get_combined_minimum_size()])
	_check(not sandbox.grid_zoom_controls.visible,
		"%s map zoom controls remain above the item modal"%viewport_size)
	_check(sandbox.find_children("*","ProgressBar",true,false).is_empty(),
		"%s DOS modal still contains a modern ProgressBar"%viewport_size)
	sandbox._close_member_detail();await process_frame;await process_frame
	_check(sandbox.grid_zoom_controls.visible and sandbox.grid.visible_cell_count==zoom_before_item,
		"%s closing item modal did not restore the same map zoom"%viewport_size)
	sandbox.queue_free();await process_frame
	await _check_item_equipment_touch(viewport_size)
	await _check_nearby_npc_card_touch(viewport_size)
	await _check_product_direction_touch(viewport_size)
	await _check_active_route_direction_override(viewport_size)
	await _check_product_auto_scheduler(viewport_size)
	await _check_direct_solo_combat_log(viewport_size)

func _check_item_equipment_touch(viewport_size:Vector2)->void:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.name="ItemTouchProbe";root.add_child(sandbox)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sandbox.position=Vector2.ZERO;sandbox.size=viewport_size
	sandbox.initialize_for_headless_test(session,false)
	sandbox._open_hero_detail_tab("ITEM");await process_frame;await process_frame
	var axe_row:=sandbox._find_item_row_button("START_HAND_AXE_001","") as Button
	_check(axe_row!=null,"%s item touch probe has no hand axe row"%viewport_size)
	if axe_row!=null:
		sandbox.member_detail_scroll.ensure_control_visible(axe_row)
		await process_frame;await process_frame
		await _screen_touch_plain_button(axe_row,69)
	await process_frame;await process_frame
	_check(sandbox.member_item_popover.visible and sandbox.member_item_equip_button.text=="[교체]",
		"%s item touch did not open the comparison popover"%viewport_size)
	var fixed_popover_position:Vector2=sandbox.member_item_popover.position
	if sandbox.member_item_popover.visible:
		_check(str(sandbox.member_item_equip_button.get_meta("item_instance_id","")) \
			=="START_HAND_AXE_001" and str(sandbox.member_item_equip_button.get_meta(
			"item_slot",""))=="MAIN_HAND",
			"%s popover replacement action lost its stable item/slot target"%viewport_size)
		await _screen_touch_plain_button(sandbox.member_item_equip_button,71)
		_check(str(session.protagonist_equipment().weapon_id)=="HAND_AXE",
			"%s popover equipment ScreenTouch was swallowed before [교체]"%viewport_size)
	var mace_row:=sandbox._find_item_row_button("START_MACE_001","") as Button
	_check(mace_row!=null,"%s item touch probe has no mace row after replacement"%viewport_size)
	if mace_row!=null:
		sandbox.member_detail_scroll.ensure_control_visible(mace_row)
		await process_frame;await process_frame
		await _screen_touch_plain_button(mace_row,76)
		_check(sandbox.member_item_popover.visible \
			and sandbox.member_item_popover.position.is_equal_approx(fixed_popover_position) \
			and str(sandbox.member_item_equip_button.get_meta("item_instance_id","")) \
				=="START_MACE_001",
			"%s second replacement lost its fixed popover or stable item target"%viewport_size)
		if sandbox.member_item_popover.visible:
			await _screen_touch_plain_button(sandbox.member_item_equip_button,77)
		_check(str(session.protagonist_equipment().weapon_id)=="MACE",
			"%s second consecutive equipment replacement failed"%viewport_size)
	var potion_row:=sandbox._find_item_row_button("START_POTION_001","") as Button
	if potion_row!=null:
		sandbox.member_detail_scroll.ensure_control_visible(potion_row)
		await process_frame;await process_frame
		await _screen_touch_plain_button(potion_row,74)
		_check(sandbox.member_item_popover.position.is_equal_approx(fixed_popover_position),
			"%s item popover moved with the selected row or scroll offset"%viewport_size)
		await _screen_touch_plain_button(sandbox.member_detail_item_tab,75)
		_check(not sandbox.member_item_popover.visible and sandbox.member_detail_modal.visible,
			"%s outside touch did not dismiss only the item popover"%viewport_size)
	sandbox._select_member_detail_tab("STATUS");await process_frame;await process_frame
	var equipped_row:=sandbox._find_item_row_button("START_MACE_001","MAIN_HAND") as Button
	_check(equipped_row!=null and sandbox.member_item_equipment_rows.is_visible_in_tree(),
		"%s status bottom has no equipped main-hand row"%viewport_size)
	if equipped_row!=null:
		sandbox.member_detail_scroll.ensure_control_visible(equipped_row)
		await process_frame;await process_frame
		await _screen_touch_plain_button(equipped_row,72)
		await process_frame
		await _screen_touch_plain_button(sandbox.member_item_unequip_button,73)
		_check(bool(session.protagonist_inventory().equipment_slots[0].empty),
			"%s popover unequip ScreenTouch did not clear the main hand"%viewport_size)
	sandbox.queue_free();await process_frame

func _check_nearby_npc_card_touch(viewport_size:Vector2)->void:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.name="NearbyNpcTouchProbe";root.add_child(sandbox)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sandbox.position=Vector2.ZERO;sandbox.size=viewport_size
	sandbox.initialize_for_headless_test(session,false)
	var npc_id:=int(session.opening_event_status().get("npc_entity_id",-1))
	# Make the opening actor a valid inspectable/recruitable re-encounter fixture.
	# Merely forcing its card visible while the opening is still undiscovered gives
	# the buttons a domain-invalid actor and cannot prove input dispatch.
	session.sim.world.party_encounter.opening_event.reencounter_event_id=1
	sandbox.nearby_npc_entity_id=npc_id;sandbox.nearby_npc_story_state="REUNION_READY"
	sandbox.nearby_npc_panel.visible=true;sandbox.nearby_npc_content.visible=true
	sandbox.nearby_npc_detail_button.disabled=false
	sandbox.nearby_npc_action_button.disabled=false
	sandbox.nearby_npc_attack_button.disabled=false
	await process_frame;await process_frame
	_check(sandbox.nearby_npc_name.get_theme_font_size("font_size")==16 \
		and sandbox.nearby_npc_personality.get_theme_font_size("font_size")==12 \
		and sandbox.nearby_npc_recruitment.get_theme_font_size("font_size")==11 \
		and sandbox.nearby_npc_action_button.get_theme_font_size("font_size")==12,
		"%s nearby NPC card typography was not compacted"%viewport_size)
	var step_before:int=session.sim.world.step_index
	await _screen_touch_plain_button(sandbox.nearby_npc_toggle_button,74)
	_check(sandbox.nearby_npc_collapsed and not sandbox.nearby_npc_content.visible,
		"%s nearby NPC card ScreenTouch did not collapse"%viewport_size)
	await _screen_touch_plain_button(sandbox.nearby_npc_toggle_button,75)
	_check(not sandbox.nearby_npc_collapsed and sandbox.nearby_npc_content.visible,
		"%s nearby NPC card ScreenTouch did not expand"%viewport_size)
	await _screen_touch_plain_button(sandbox.nearby_npc_detail_button,76)
	_check(sandbox.member_detail_modal.visible,
		"%s nearby NPC [상세] ScreenTouch was swallowed by the map"%viewport_size)
	sandbox._close_member_detail();await process_frame
	sandbox.nearby_npc_panel.visible=true;sandbox.nearby_npc_content.visible=true
	sandbox.nearby_npc_action_button.disabled=false
	sandbox.action_feedback_text=""
	await process_frame
	await _screen_touch_plain_button(sandbox.nearby_npc_action_button,77)
	_check(not sandbox.action_feedback_text.is_empty(),
		"%s nearby NPC recruitment ScreenTouch did not reach its action"%viewport_size)
	sandbox.nearby_npc_panel.visible=true;sandbox.nearby_npc_content.visible=true
	sandbox.nearby_npc_entity_id=npc_id;sandbox.nearby_npc_attack_button.disabled=false
	sandbox.action_feedback_text=""
	await process_frame
	await _screen_touch_plain_button(sandbox.nearby_npc_attack_button,78)
	_check(not sandbox.action_feedback_text.is_empty(),
		"%s nearby NPC attack ScreenTouch did not reach its action"%viewport_size)
	_check(session.sim.world.step_index==step_before,
		"%s nearby NPC card touch leaked through to map movement"%viewport_size)
	sandbox.queue_free();await process_frame

func _screen_touch_plain_button(button:Button,touch_index:int)->void:
	var center:=button.get_global_rect().get_center()
	var press:=InputEventScreenTouch.new();press.index=touch_index
	press.pressed=true;press.position=center;root.push_input(press,true)
	await process_frame
	var release:=InputEventScreenTouch.new();release.index=touch_index
	release.pressed=false;release.position=center;root.push_input(release,true)
	await process_frame;await process_frame

func _check_product_auto_scheduler(viewport_size:Vector2)->void:
	var session=_safe_auto_product_session()
	var sandbox=Sandbox.new();sandbox.name="ProductAutoSchedulerProbe";sandbox.size=viewport_size
	_check(sandbox.continuous_travel_cadence_msec>=170 \
		and sandbox.continuous_travel_cadence_msec<=220,
		"%s continuous travel cadence is outside the visible 170-220ms window"%viewport_size)
	sandbox.initialize_for_headless_test(session,false)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size
	root.add_child(sandbox);await process_frame;await process_frame
	var canonical:Dictionary={"accepted":true,"event_ids":[],"visual_effects":[{
		"effect_id":"nested-auto-vfx","event_id":90001,"order":0,
		"kind":"HIT_FLASH","damage_type":"physical","world_position":[0,0],"text":""}]}
	var route_wrapper:Dictionary={"last_step_result":canonical}
	var advanced:Dictionary={"advanced":true,"running":true,"last_step_result":route_wrapper}
	sandbox._consume_product_auto_explore_result(advanced)
	var effect_count:int=sandbox._pending_visual_effect_rows.size()
	sandbox._consume_product_auto_explore_result({"advanced":false,"running":false,
		"stop_reason":"auto_explore_user_cancel","last_step_result":route_wrapper})
	_check(effect_count==1 and sandbox._pending_visual_effect_rows.size()==1,
		"%s AUTO nested canonical VFX was omitted or replayed by cancel"%viewport_size)
	sandbox._pending_visual_effect_rows.clear()
	# Start commits its first hop; a held AUTO touch must pause every continuation.
	sandbox._on_product_auto();sandbox._sync_product_control_state()
	var running:=bool(session.auto_explore_state().get("running",false))
	_check(running and sandbox.product_auto_button.text=="[AUTO ■]",
		"%s AUTO did not enter a visible running state"%viewport_size)
	if running:
		var moving_hero_id:=int(session.party_status().get("protagonist_id",-1))
		var auto_motion:Dictionary=sandbox.grid.actor_motion_state()
		_check(auto_motion.has(moving_hero_id) \
			and int((auto_motion.get(moving_hero_id,{}) as Dictionary).get("duration_ms",0)) \
				==sandbox.CONTINUOUS_EXPLORATION_MOTION_MSEC,
			"%s AUTO hop did not arm the visible modular walk cycle"%viewport_size)
		var first_hop_started:int=sandbox._product_auto_last_hop_started_msec
		var due_from_hop_start:int=int(sandbox._product_auto_explore_due_msec)-first_hop_started
		_check(due_from_hop_start>=185 and due_from_hop_start<=200,
			"%s AUTO continuation was not scheduled 185-200ms from hop start: %d"%[
				viewport_size,due_from_hop_start])
		var cadence_step:int=int(session.party_status().step_index)
		var wait_started:int=Time.get_ticks_msec()
		# Product scheduling leaves enough time for the 180ms walk cycle to render.
		# Headless CI occasionally stretches a frame; 310ms is a gross ceiling,
		# while the lower bound and exact one-hop assertion still catch early/duplicate
		# commits rather than treating scheduler jitter as product work.
		while sandbox._product_auto_last_hop_started_msec==first_hop_started \
				and Time.get_ticks_msec()-wait_started<AUTO_HEADLESS_GROSS_CEILING_MSEC+20:
			await create_timer(0.005).timeout
		var actual_start_interval:int=sandbox._product_auto_last_hop_started_msec-first_hop_started
		_check(int(session.party_status().step_index)==cadence_step+1 \
			and actual_start_interval>=AUTO_INTENDED_CADENCE_MSEC-5 \
			and actual_start_interval<=AUTO_HEADLESS_GROSS_CEILING_MSEC,
			("%s AUTO commit-start was not exactly one hop within 185-310ms " \
			+ "(intended=190ms gross=310ms): step=%d/%d interval=%d")%[
				viewport_size,int(session.party_status().step_index),cadence_step,actual_start_interval])
		var auto_camera:Dictionary=sandbox.grid.camera_settle_draw_spec()
		_check(int(auto_camera.get("duration_ms",0))==sandbox.CONTINUOUS_CAMERA_SETTLE_MSEC \
			and bool(auto_camera.get("active",false)),
			"%s AUTO camera stopped between cadence hops: %s"%[viewport_size,auto_camera])
		# _on_product_auto synchronously rebuilds the dock. Quiesce only the test
		# scheduler until Container layout has produced the next drawn hit rects.
		sandbox._product_auto_explore_pending=false
		sandbox._product_auto_explore_due_frame=-1
		sandbox._product_auto_explore_due_msec=-1
		sandbox._product_auto_explore_scheduled_generation=-1
		# The remaining gesture probes advance synthetic frames rather than wall
		# time. Zero only their presentation delay; production remains 190ms.
		sandbox.continuous_travel_cadence_msec=0
		await process_frame;await process_frame
		var held_step:=int(session.party_status().step_index)
		var center:Vector2=sandbox.product_auto_button.get_global_rect().get_center()
		var press:=InputEventScreenTouch.new();press.index=51;press.pressed=true;press.position=center
		root.push_input(press,true);sandbox._schedule_product_auto_explore()
		await process_frame;await process_frame;await process_frame
		_check(sandbox._product_touch_control=="ProductAuto",
			"%s laid-out AUTO hit rect overlapped %s"%[viewport_size,sandbox._product_touch_control])
		_check(int(session.party_status().step_index)==held_step,
			"%s AUTO committed a hop while its ScreenTouch was held"%viewport_size)
		_check(bool(session.auto_explore_state().get("running",false)),
			"%s AUTO stopped while its ScreenTouch was held: %s"%[viewport_size,
				session.auto_explore_state()])
		var release:=InputEventScreenTouch.new();release.index=51;release.pressed=false;release.position=center
		root.push_input(release,true);await process_frame;await process_frame
		_check(not bool(session.auto_explore_state().get("running",false)) \
			and int(session.party_status().step_index)==held_step \
			and sandbox.product_auto_button.text=="[AUTO]" \
			and not sandbox.product_auto_button.button_pressed,
			"%s AUTO held-touch cancel restarted, advanced, or left stale chrome state=%s step=%d/%d text=%s pressed=%s"%[
				viewport_size,session.auto_explore_state(),int(session.party_status().step_index),held_step,
				sandbox.product_auto_button.text,sandbox.product_auto_button.button_pressed])
	# Drag-cancelling a button gesture is not a command. AUTO stays running,
	# remains paused for the held gesture, then resumes with one scheduled hop.
	session=_safe_auto_product_session()
	sandbox._reset_run_ui_transients();sandbox.initialize_for_headless_test(session,false)
	await process_frame;await process_frame
	sandbox._on_product_auto();sandbox._sync_product_control_state()
	if bool(session.auto_explore_state().get("running",false)):
		sandbox._product_auto_explore_pending=false
		sandbox._product_auto_explore_due_frame=-1
		sandbox._product_auto_explore_due_msec=-1
		sandbox._product_auto_explore_scheduled_generation=-1
		await process_frame;await process_frame
		var drag_step:=int(session.party_status().step_index)
		var drag_origin:Vector2=sandbox.product_auto_button.get_global_rect().get_center()
		var drag_press:=InputEventScreenTouch.new();drag_press.index=52
		drag_press.pressed=true;drag_press.position=drag_origin;root.push_input(drag_press,true)
		sandbox._schedule_product_auto_explore()
		await process_frame
		var drag:=InputEventScreenDrag.new();drag.index=52;drag.position=drag_origin+Vector2(20,0)
		drag.relative=Vector2(20,0);root.push_input(drag,true)
		await process_frame;await process_frame
		_check(int(session.party_status().step_index)==drag_step,
			"%s AUTO committed while a drag-cancel gesture was held"%viewport_size)
		var drag_release:=InputEventScreenTouch.new();drag_release.index=52
		drag_release.pressed=false;drag_release.position=drag.position;root.push_input(drag_release,true)
		await process_frame
		_check(int(session.party_status().step_index)==drag_step+1,
			"%s drag-cancelled AUTO did not resume exactly one next-frame hop state=%s"%[
				viewport_size,session.auto_explore_state()])
	# A modal cancel synchronizes the button immediately without rebuilding grid.
	session=_safe_auto_product_session()
	sandbox._reset_run_ui_transients();sandbox.initialize_for_headless_test(session,false)
	await process_frame;await process_frame
	var grid_id:int=sandbox.grid.get_instance_id();sandbox._on_product_auto()
	if bool(session.auto_explore_state().get("running",false)):
		sandbox._toggle_map_overlay()
		_check(not bool(session.auto_explore_state().get("running",false)) \
			and sandbox.product_auto_button.text=="[AUTO]" \
			and not sandbox.product_auto_button.button_pressed \
			and sandbox.grid.get_instance_id()==grid_id,
			"%s modal AUTO cancel left stale state or rebuilt the grid"%viewport_size)
		sandbox.map_overlay.close("TEST");await process_frame
	# The character/item modal pauses AUTO and resumes it on close. Repeatedly
	# inspecting gear must not permanently kill automatic travel.
	session=_safe_auto_product_session()
	sandbox._reset_run_ui_transients();sandbox.initialize_for_headless_test(session,false)
	sandbox.continuous_travel_cadence_msec=0;await process_frame;await process_frame
	sandbox._on_product_auto()
	if bool(session.auto_explore_state().get("running",false)):
		var modal_step:=int(session.party_status().step_index)
		sandbox._open_hero_detail_tab("ITEM")
		await process_frame;await process_frame;await process_frame
		_check(int(session.party_status().step_index)==modal_step \
			and bool(session.auto_explore_state().get("running",false)),
			"%s item modal cancelled or advanced AUTO instead of pausing it"%viewport_size)
		sandbox._close_member_detail();await process_frame;await process_frame;await process_frame
		_check(int(session.party_status().step_index)>modal_step \
			or not bool(session.auto_explore_state().get("running",false)),
			"%s AUTO stayed dead after the item modal closed"%viewport_size)
		sandbox._cancel_product_auto_explore("auto_explore_user_cancel",false)
	# Grid press wins before GUI routing: it cancels AUTO turn-free even when a
	# pass-through container, rather than PartyGrid, becomes the headless GUI hit.
	session=_safe_auto_product_session()
	sandbox._reset_run_ui_transients();sandbox.initialize_for_headless_test(session,false)
	await process_frame;await process_frame
	sandbox._on_product_auto()
	if bool(session.auto_explore_state().get("running",false)):
		sandbox._product_auto_explore_pending=false
		var manual_before:=int(session.party_status().step_index)
		var hero_value:Array=session.party_status().protagonist_position
		var hero_cell:=Vector2i(int(hero_value[0]),int(hero_value[1]))
		var manual_point:Vector2=sandbox.grid.get_global_rect().position \
			+sandbox.grid.world_to_pixel_center(hero_cell)
		var manual_press:=InputEventScreenTouch.new();manual_press.index=54
		manual_press.pressed=true;manual_press.position=manual_point;root.push_input(manual_press,true)
		_check(not bool(session.auto_explore_state().get("running",false)) \
			and str(session.auto_explore_state().get("stop_reason",""))=="auto_explore_user_command" \
			and int(session.party_status().step_index)==manual_before,
			"%s grid press did not cancel AUTO generation-safe before a turn"%viewport_size)
		var manual_release:=InputEventScreenTouch.new();manual_release.index=54
		manual_release.pressed=false;manual_release.canceled=true;manual_release.position=manual_point
		root.push_input(manual_release,true)
	# Rapid cancel followed by a fresh start cannot retain the old scheduled hop.
	session=_safe_auto_product_session()
	sandbox._reset_run_ui_transients();sandbox.initialize_for_headless_test(session,false)
	await process_frame;await process_frame
	sandbox._on_product_auto()
	if bool(session.auto_explore_state().get("running",false)):
		sandbox._cancel_product_auto_explore("auto_explore_user_cancel",false)
		var cancelled_step:=int(session.party_status().step_index)
		sandbox._on_product_auto()
		var restarted_running:=bool(session.auto_explore_state().get("running",false))
		var restart_step:=int(session.party_status().step_index)
		await process_frame;await process_frame
		var delta:=int(session.party_status().step_index)-restart_step
		_check(cancelled_step<=restart_step and (delta==1 if restarted_running else delta==0),
			"%s rapid AUTO cancel/restart duplicated or stuck its scheduled hop cancel=%d restart=%d running=%s delta=%d state=%s"%[
				viewport_size,cancelled_step,restart_step,restarted_running,delta,session.auto_explore_state()])
	# Any enemy confirmed in FOV stops before a hop and presents that exact reason.
	var contact_session=_baseline_solo_session(45)
	sandbox._reset_run_ui_transients();sandbox.initialize_for_headless_test(contact_session,false)
	await process_frame;await process_frame
	var contact_result:Dictionary=contact_session.start_auto_explore()
	sandbox._consume_product_auto_explore_result(contact_result);sandbox._refresh()
	_check(str(contact_result.get("stop_reason",""))=="auto_explore_enemy_visible" \
		and contact_session.command_journal.is_empty() \
		and "적을 발견해" in sandbox.event_label.text \
		and not "가까운" in sandbox.event_label.text,
		"%s visible-enemy AUTO stop was not explicit and turn-free: %s / %s"%[
			viewport_size,contact_result,sandbox.event_label.text])
	sandbox.queue_free();await process_frame

func _baseline_solo_session(p_world_seed:int=44):
	var session=Session.new(p_world_seed,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	if not session.reset_party(p_world_seed,20260828,
			Session.SOLO_COMBAT_SCENARIO_ID,
			VisualMap.previous_product_dungeon(p_world_seed),false):
		failures.append("baseline solo fixture failed to disable the opening event")
	return session


func _safe_auto_product_session():
	var session=_baseline_solo_session()
	var state=session.sim.world.party_encounter;var enemy_id:=int(state.enemy_ids[0])
	var snapshot:Dictionary=session._auto_explore_fog_snapshot();var hidden:=Vector2i(-1,-1)
	for y in range(session.sim.world.height-1,-1,-1):
		for x in range(session.sim.world.width-1,-1,-1):
			var position:=Vector2i(x,y);var key:="%d:%d"%[x,y]
			if snapshot.visible.has(key):continue
			var definition:Dictionary=TerrainRegistry.definition(str(session.sim.world.tile_at(position).terrain))
			if bool(definition.get("passable",false)) \
					and session.sim.world.blocking_entity_at(position,enemy_id)==null:
				hidden=position;break
		if hidden!=Vector2i(-1,-1):break
	if hidden!=Vector2i(-1,-1):session.sim.world.entities[enemy_id].position=hidden
	state.enemy_busy_rows[enemy_id]=1000000000
	return session

func _check_active_route_direction_override(viewport_size:Vector2)->void:
	var session=null;var started:Dictionary={}
	for goal_offset in [Vector2i(-3,0),Vector2i(0,-3),Vector2i(3,0),Vector2i(0,3)]:
		var candidate=_baseline_solo_session()
		var status:Dictionary=candidate.party_status()
		var origin:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
		var preview:Dictionary=candidate.preview_exploration_route(origin+goal_offset)
		if not bool(preview.get("accepted",false)) or int(preview.get("total_steps",0))<3:continue
		var result:Dictionary=candidate.start_exploration_route(origin+goal_offset,str(preview.get("plan_hash","")))
		if bool(result.get("active",false)):
			session=candidate;started=result;break
	_check(session!=null,"%s could not create an active route override fixture"%viewport_size)
	if session==null:return
	var sandbox=Sandbox.new();sandbox.name="ProductRouteOverrideProbe";sandbox.size=viewport_size
	sandbox.initialize_for_headless_test(session,false)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size
	root.add_child(sandbox);await process_frame;await process_frame
	var status:Dictionary=session.party_status();var origin:=Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]));var chosen:=Vector2i.ZERO
	for direction in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,
			Vector2i(-1,-1),Vector2i(1,-1),Vector2i(1,1),Vector2i(-1,1)]:
		if bool(session.preview_exploration(Command.move_to(int(status.protagonist_id),origin+direction)).get("accepted",false)):
			chosen=direction;break
	_check(chosen!=Vector2i.ZERO,"%s active route fixture has no manual direction"%viewport_size)
	if chosen!=Vector2i.ZERO:
		var step_before:=int(status.step_index);var journal_before:int=session.command_journal.size()
		var direction_button:=sandbox.product_direction_buttons.get(chosen) as Button
		var center:=direction_button.get_global_rect().get_center()
		sandbox._schedule_route_continue(Time.get_ticks_msec())
		var press:=InputEventScreenTouch.new();press.index=52;press.pressed=true;press.position=center
		root.push_input(press,true);await process_frame
		_check(sandbox._product_immediate_touch_indices.has(52),
			"%s held route override press did not reach product input"%viewport_size)
		await create_timer(float(sandbox.continuous_travel_cadence_msec+40)/1000.0).timeout
		await process_frame
		_check(int(session.party_status().step_index)==step_before+1 \
			and session.command_journal.size()==journal_before+1 \
			and not bool(session.exploration_route_state().get("active",false)),
			"%s direction press did not cancel the route and commit immediately"%viewport_size)
		var release:=InputEventScreenTouch.new();release.index=52;release.pressed=false;release.position=center
		root.push_input(release,true);await process_frame;await process_frame
		_check(int(session.party_status().step_index)==step_before+1 \
			and session.command_journal.size()==journal_before+1 \
			and not bool(session.exploration_route_state().get("active",false)) \
			and not sandbox._product_immediate_touch_indices.has(52),
			"%s active route → direction did not cancel then commit exactly once"%viewport_size)
		await process_frame;await process_frame
		_check(int(session.party_status().step_index)==step_before+1,
			"%s cancelled route retained a deferred continuation"%viewport_size)
	sandbox.queue_free();await process_frame

func _check_product_direction_touch(viewport_size:Vector2)->void:
	var session=_baseline_solo_session()
	var status:Dictionary=session.party_status();var hero:=int(status.protagonist_id)
	var origin:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
	var fixture_preview:Dictionary=session.preview_exploration(
		Command.move_to(hero,origin+Vector2i(-1,-1)))
	_check(bool(fixture_preview.get("accepted",false)),
		"%s direction fixture rejects its first diagonal: %s"%[viewport_size,fixture_preview])
	var sandbox=Sandbox.new();sandbox.name="ProductDirectionTouchProbe";sandbox.size=viewport_size
	# Manual orchestration isolates one user gesture from the legitimate CONTACT
	# auto-deploy commits that can follow an exploration step.
	sandbox.initialize_for_headless_test(session,false)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size
	root.add_child(sandbox);await process_frame;await process_frame
	var steps:Array=[
		["ProductMoveNW",Vector2i(-1,-1)],["ProductMoveN",Vector2i(0,-1)],
		["ProductMoveNE",Vector2i(1,-1)],["ProductMoveW",Vector2i(-1,0)],
		["ProductMoveE",Vector2i(1,0)],["ProductMoveSW",Vector2i(-1,1)],
		["ProductMoveS",Vector2i(0,1)],["ProductMoveSE",Vector2i(1,1)],
	]
	for row_index in range(steps.size()):
		var row:Variant=steps[row_index]
		if row_index>0:
			session=_baseline_solo_session()
			sandbox._reset_run_ui_transients();sandbox.initialize_for_headless_test(session,false)
			await process_frame;await process_frame
		var before_status:Dictionary=session.party_status()
		var before:=Vector2i(int(before_status.protagonist_position[0]),
			int(before_status.protagonist_position[1]))
		var step_before:=int(before_status.step_index);var journal_before:int=session.command_journal.size()
		var button=sandbox.find_child(str(row[0]),true,false) as Button
		if button==null or button.disabled or sandbox._product_control_at_position(
				button.get_global_rect().get_center())!=str(row[0]):
			failures.append("%s %s not hittable before ScreenTouch disabled=%s rect=%s map=%s"%[
				viewport_size,row[0],button.disabled if button!=null else true,
				button.get_global_rect() if button!=null else Rect2(),sandbox.map_overlay.visible])
		await _screen_touch_button(sandbox,button,31,true)
		var after_status:Dictionary=session.party_status()
		var after:=Vector2i(int(after_status.protagonist_position[0]),
			int(after_status.protagonist_position[1]))
		_check(after==before+Vector2i(row[1]) and int(after_status.step_index)==step_before+1 \
			and session.command_journal.size()==journal_before+1,
			"%s %s ScreenTouch was not exactly one authoritative step: %s/%s step %d/%d journal %d/%d phase %s/%s"%[
				viewport_size,row[0],before,after,step_before,int(after_status.step_index),journal_before,
				session.command_journal.size(),before_status.safe_phase,after_status.safe_phase])
		await process_frame;await process_frame
		_check(int(session.party_status().step_index)==step_before+1 \
			and session.command_journal.size()==journal_before+1,
			"%s %s ScreenTouch double-committed on deferred refresh"%[viewport_size,row[0]])
	session=_baseline_solo_session()
	sandbox._reset_run_ui_transients();sandbox.initialize_for_headless_test(session,false)
	await process_frame;await process_frame
	var wait_before:Dictionary=session.party_status();var wait_journal:int=session.command_journal.size()
	var wait_position:Array=wait_before.protagonist_position.duplicate()
	await _screen_touch_button(sandbox,sandbox.find_child("ProductWaitCenter",true,false) as Button,32,true)
	var wait_after:Dictionary=session.party_status()
	_check(wait_after.protagonist_position==wait_position \
		and int(wait_after.step_index)==int(wait_before.step_index)+1 \
		and session.command_journal.size()==wait_journal+1,
		"%s center WAIT was not exactly one stationary authoritative turn"%viewport_size)
	await process_frame;await process_frame
	_check(int(session.party_status().step_index)==int(wait_before.step_index)+1,
		"%s center WAIT double-committed"%viewport_size)
	# Some web touch stacks can repeat the same pressed packet before release.
	# One physical pointer id still owns exactly one immediate D-pad command.
	session=_baseline_solo_session()
	sandbox._reset_run_ui_transients();sandbox.initialize_for_headless_test(session,false)
	await process_frame;await process_frame
	var duplicate_before:Dictionary=session.party_status()
	var duplicate_origin:=Vector2i(int(duplicate_before.protagonist_position[0]),
		int(duplicate_before.protagonist_position[1]))
	var duplicate_direction:=Vector2i.LEFT
	var duplicate_button:=sandbox.product_direction_buttons.get(duplicate_direction) as Button
	var duplicate_point:=duplicate_button.get_global_rect().get_center()
	var duplicate_press:=InputEventScreenTouch.new();duplicate_press.index=39
	duplicate_press.pressed=true;duplicate_press.position=duplicate_point
	root.push_input(duplicate_press,true);root.push_input(duplicate_press,true);await process_frame
	# Simulate the same held pointer being redelivered after the former 250ms
	# debounce window, without making this smoke test sleep in real time.
	if sandbox._product_immediate_touch_indices.has(39):
		var held_touch:Dictionary=sandbox._product_immediate_touch_indices[39]
		held_touch["started_at_msec"]=Time.get_ticks_msec()-1000
		sandbox._product_immediate_touch_indices[39]=held_touch
	root.push_input(duplicate_press,true);await process_frame
	var duplicate_after:Dictionary=session.party_status()
	_check(Vector2i(int(duplicate_after.protagonist_position[0]),
		int(duplicate_after.protagonist_position[1]))==duplicate_origin+duplicate_direction,
		"%s immediate or delayed repeated D-pad press moved more than one tile"%viewport_size)
	var duplicate_release:=InputEventScreenTouch.new();duplicate_release.index=39
	duplicate_release.pressed=false;duplicate_release.position=duplicate_point
	root.push_input(duplicate_release,true);await process_frame
	# The browser may deliver a compatibility mouse pair after the completed
	# touch. Device provenance, not only a short timer, keeps it from committing a
	# second authoritative move after a slow Web frame.
	sandbox._product_ignore_mouse_until_msec=-1
	var compat_press:=InputEventMouseButton.new();compat_press.device=InputEvent.DEVICE_ID_EMULATION
	compat_press.button_index=MOUSE_BUTTON_LEFT;compat_press.pressed=true
	compat_press.position=duplicate_point;root.push_input(compat_press,true);await process_frame
	var compat_release:=InputEventMouseButton.new();compat_release.device=InputEvent.DEVICE_ID_EMULATION
	compat_release.button_index=MOUSE_BUTTON_LEFT;compat_release.pressed=false
	compat_release.position=duplicate_point;root.push_input(compat_release,true);await process_frame
	var compat_after:Dictionary=session.party_status()
	_check(Vector2i(int(compat_after.protagonist_position[0]),
		int(compat_after.protagonist_position[1]))==duplicate_origin+duplicate_direction \
		and int(compat_after.step_index)==int(duplicate_before.step_index)+1,
		"%s touch-emulated mouse pair committed a second D-pad step"%viewport_size)
	var opposite_button:=sandbox.product_direction_buttons.get(-duplicate_direction) as Button
	await _screen_touch_button(sandbox,opposite_button,40,true)
	var opposite_after:Dictionary=session.party_status()
	_check(Vector2i(int(opposite_after.protagonist_position[0]),
		int(opposite_after.protagonist_position[1]))==duplicate_origin,
		"%s one opposite D-pad touch moved more than one tile"%viewport_size)
	# The first step toward the nearby monster may atomically enter combat, but
	# the player still changes exactly one cell and keeps a visible camera settle.
	session=_baseline_solo_session()
	sandbox._reset_run_ui_transients();sandbox.initialize_for_headless_test(session,true)
	await process_frame;await process_frame
	var contact_before:Dictionary=session.party_status()
	var contact_origin:=Vector2i(int(contact_before.protagonist_position[0]),
		int(contact_before.protagonist_position[1]))
	var contact_button:=sandbox.product_direction_buttons.get(Vector2i.UP) as Button
	await _screen_touch_button(sandbox,contact_button,41)
	var contact_after:Dictionary=session.party_status()
	var contact_hero_id:=int(contact_after.get("protagonist_id",-1))
	var contact_facing:Vector2i=sandbox.grid.actor_last_facing_state().get(
		contact_hero_id,Vector2i.ZERO)
	_check(Vector2i(int(contact_after.protagonist_position[0]),
		int(contact_after.protagonist_position[1]))==contact_origin+Vector2i.UP \
		and contact_facing==Vector2i.UP,
		("%s first monster-facing D-pad touch jumped cells or lost its facing: " \
		+ "origin=%s after=%s phase=%s/%s facing=%s")%[viewport_size,contact_origin,
			contact_after.protagonist_position,contact_before.safe_phase,
			contact_after.safe_phase,contact_facing])
	var contact_reverse:=sandbox.product_direction_buttons.get(Vector2i.DOWN) as Button
	await _screen_touch_button(sandbox,contact_reverse,42,true)
	var contact_reversed:Dictionary=session.party_status()
	_check(Vector2i(int(contact_reversed.protagonist_position[0]),
		int(contact_reversed.protagonist_position[1]))==contact_origin,
		"%s opposite touch after first contact moved more than one tile"%viewport_size)
	# Map touch retains its original one-cell contract beside the button dock.
	session=_baseline_solo_session()
	sandbox._reset_run_ui_transients();sandbox.initialize_for_headless_test(session,false)
	await process_frame;await process_frame
	var map_before:Dictionary=session.party_status()
	var map_origin:=Vector2i(int(map_before.protagonist_position[0]),
		int(map_before.protagonist_position[1]));var map_destination:=map_origin+Vector2i.RIGHT
	var map_journal:int=session.command_journal.size()
	await _screen_touch_grid_cell(sandbox,map_destination,33)
	var map_after:Dictionary=session.party_status()
	_check(map_after.protagonist_position==[map_destination.x,map_destination.y] \
		and session.command_journal.size()==map_journal+1,
		"%s map ScreenTouch stopped being an independent one-cell move"%viewport_size)
	sandbox.queue_free();await process_frame

func _screen_touch_button(sandbox,button:Button,touch_index:int,
		assert_immediate_step:bool=false)->void:
	if button==null:
		failures.append("missing product control button");return
	var button_name:=button.name
	var immediate:bool=bool(sandbox._product_control_activates_on_press(button_name))
	var step_before:=int(sandbox.session.party_status().get("step_index",-1))
	var center:=button.get_global_rect().get_center()
	var press:=InputEventScreenTouch.new();press.index=touch_index;press.pressed=true;press.position=center
	root.push_input(press,true);await process_frame
	if immediate and not sandbox._product_immediate_touch_indices.has(touch_index):
		failures.append("immediate product ScreenTouch press did not reach sandbox _input at %s"%center)
	elif not immediate and sandbox._product_touch_index!=touch_index:
		failures.append("product ScreenTouch press did not reach sandbox _input at %s"%center)
	if assert_immediate_step and int(sandbox.session.party_status().get(
			"step_index",-1))!=step_before+1:
		failures.append("%s waited for touch release instead of committing on press"%button_name)
	var release:=InputEventScreenTouch.new();release.index=touch_index;release.pressed=false;release.position=center
	root.push_input(release,true);await process_frame;await process_frame
	if sandbox._product_touch_index!=-1 \
			or sandbox._product_immediate_touch_indices.has(touch_index):
		failures.append("product ScreenTouch release did not reach sandbox _input at %s"%center)

func _screen_touch_grid_cell(sandbox,position:Vector2i,touch_index:int)->void:
	var local_position:Vector2=sandbox.grid.world_to_pixel_center(position)
	var global_position:Vector2=sandbox.grid.get_global_rect().position+local_position
	var press:=InputEventScreenTouch.new();press.index=touch_index;press.pressed=true;press.position=global_position
	root.push_input(press,true);await process_frame
	var release:=InputEventScreenTouch.new();release.index=touch_index;release.pressed=false;release.position=global_position
	root.push_input(release,true);await process_frame;await process_frame

func _check_direct_solo_combat_log(viewport_size:Vector2)->void:
	var session=_baseline_solo_session()
	var state=session.sim.world.party_encounter;var hero:=int(state.protagonist_id)
	for _step in range(256):
		if session.party_status().safe_phase=="CONTACT":break
		var enemy_id:=int(state.enemy_ids[0])
		var path:Dictionary=session.sim.party_coordinator.pathfinder.find_path_to_any(
			hero,_adjacent_open_cells(session,enemy_id))
		if not bool(path.get("found",false)) or path.path.size()<2:break
		if not session.commit_exploration(Command.move_to(hero,path.path[1])).accepted:break
	if session.party_status().safe_phase=="CONTACT":session.enter_solo_combat()
	for _turn in range(4):
		var status:Dictionary=session.party_status();var enemy:=int(status.visible_enemy_ids[0])
		var hero_position:Vector2i=session.sim.world.entities[hero].position
		var enemy_position:Vector2i=session.sim.world.entities[enemy].position
		if maxi(absi(hero_position.x-enemy_position.x),absi(hero_position.y-enemy_position.y))==1:break
		var direction:=Vector2i(signi(enemy_position.x-hero_position.x),signi(enemy_position.y-hero_position.y))
		if not session.set_actor_action(hero,"MOVE",[hero_position.x+direction.x,
				hero_position.y+direction.y]).accepted:break
		if not session.commit_turn().accepted:break
	var status:Dictionary=session.party_status();var enemy:=int(status.visible_enemy_ids[0])
	var sandbox=Sandbox.new();sandbox.name="DirectSoloLogProbe";sandbox.size=viewport_size
	sandbox.initialize_for_headless_test(session,true)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size
	root.add_child(sandbox);await process_frame;await process_frame
	var stable_surface_rects:={
		"grid":sandbox.grid.get_global_rect(),"cards":sandbox.cards.get_global_rect(),
		"events":sandbox.event_surface.get_global_rect(),
		"controls":sandbox.combat_action_area.get_global_rect(),
		"navigation":sandbox.bottom_navigation.get_global_rect(),
	}
	_check(sandbox.grid.size.is_equal_approx(Vector2(viewport_size.x,viewport_size.x)) \
		and sandbox.cards.custom_minimum_size.y==68 \
		and sandbox.bottom_navigation.custom_minimum_size.y>=44,
		"%s hostile awareness changed the fixed product map/HUD budget"%viewport_size)
	_check(sandbox.find_child("SoloCombatStart",true,false)==null \
		and sandbox.find_child("DeployConfirm",true,false)==null \
		and sandbox.find_child("FormationChoices",true,false)==null,
		"%s product solo constructed a combat-entry or deployment surface"%viewport_size)
	for node in sandbox.find_children("*","Control",true,false):
		if not node.is_visible_in_tree() or not (node is Label or node is Button):continue
		var visible_copy:=str(node.text)
		_check("전투 모드" not in visible_copy and "단독 전투" not in visible_copy \
			and "전투 시작" not in visible_copy and "배치" not in visible_copy,
			"%s product solo leaked a separate-mode label: %s"%[viewport_size,visible_copy])
	var hero_position:Vector2i=session.sim.world.entities[hero].position
	var enemy_position:Vector2i=session.sim.world.entities[enemy].position
	var combat_step_before:=int(session.party_status().step_index)
	_check(not sandbox.product_attack_button.disabled and sandbox.product_auto_button.disabled \
		and not sandbox.product_wait_guard_button.disabled and sandbox.product_execute_button.disabled,
		"%s adjacent direct-solo controls were stale before the fast turn"%viewport_size)
	await _screen_touch_button(sandbox,sandbox.product_attack_button,41)
	_check(int(session.party_status().step_index)==combat_step_before+1,
		"%s explicit adjacent ATTACK did not commit exactly one combat turn"%viewport_size)
	var after_fast:Dictionary=session.party_status()
	_check(sandbox.product_attack_button.visible and sandbox.product_attack_button.text=="[공격]" \
		and sandbox.product_attack_button.disabled==bool(after_fast.get("terminal",false)) \
		and sandbox.product_auto_button.disabled \
		and sandbox.product_wait_guard_button.disabled==bool(after_fast.get("terminal",false)) \
		and sandbox.product_execute_button.disabled,
		"%s direct-solo fast refresh left contextual control state stale"%viewport_size)
	var melee_spec:Dictionary=sandbox.grid.intent_draw_spec({
		"type":"MELEE","from_position":[hero_position.x,hero_position.y],
		"target_position":[enemy_position.x,enemy_position.y],"source":"DIRECT"})
	_check(melee_spec.get("primitive","")=="TARGET_MARKER" \
		and not bool(melee_spec.get("draw_connector",true)) \
		and not str(melee_spec.get("marker_style","")).is_empty(),
		"%s melee selection restored an attacker-target connector or lost its target marker"%viewport_size)
	_check(sandbox.grid._intent_overlays.is_empty() and sandbox.grid._route_path.is_empty() \
		and sandbox.grid.cursor_cell==Vector2i(-1,-1),
		"%s direct solo bump left movement/intent marks over the map"%viewport_size)
	for surface_id in stable_surface_rects:
		var control:Control={"grid":sandbox.grid,"cards":sandbox.cards,
			"events":sandbox.event_surface,"controls":sandbox.combat_action_area,
			"navigation":sandbox.bottom_navigation}[surface_id]
		_check(control.get_global_rect().is_equal_approx(stable_surface_rects[surface_id]),
			"%s attack changed the persistent %s layout"%[viewport_size,surface_id])
	_check(not sandbox.grid.melee_vfx is Control,
		"%s melee VFX introduced an input-blocking Control"%viewport_size)
	for item_spec in sandbox.grid.ground_item_draw_specs():
		_check(not bool(item_spec.get("changes_hit_rect",true)) \
			and str(item_spec.get("mouse_filter",""))=="IGNORE",
			"%s floor item presentation intercepts map input"%viewport_size)
	for awareness_spec in sandbox.grid.monster_awareness_marker_draw_specs():
		_check(not bool(awareness_spec.get("changes_hit_rect",true)),
			"%s awareness mark changes actor/map hit authority"%viewport_size)
	var monster_list:Dictionary=sandbox.grid.monster_list_draw_spec()
	_check(str(monster_list.get("mouse_filter","IGNORE"))=="IGNORE",
		"%s monster list intercepts map input"%viewport_size)
	var history:Dictionary=session.combat_log(8,80)
	var latest_messages:=_newest_meaningful_messages(sandbox,history,2)
	var fast_text:String=sandbox.event_label.text
	_check(latest_messages.size()==2 and fast_text=="\n".join(latest_messages),
		"%s direct-solo fast refresh omitted or reordered latest combat rows: %s"%[
			viewport_size,fast_text])
	await process_frame
	var event_rect:Rect2=sandbox.event_label.get_global_rect()
	_check(event_rect.size.y>=27.9 and _inside_rect(sandbox.event_surface,sandbox.event_label) \
		and sandbox.event_label.get_visible_line_count()>=mini(2,
			sandbox.event_label.get_line_count()),
		"%s combat event text collapsed or clipped inside EventSurface: %s / %s"%[
			viewport_size,event_rect,sandbox.event_surface.get_global_rect()])
	_check(fast_text.split("\n",false).size()<=2 \
		and "교전 시작" not in fast_text and "원정 시작" not in fast_text,
		"%s compact combat feed exceeds two lines or contains filler"%viewport_size)
	var latest_group:Dictionary=history.groups[-1] if not history.groups.is_empty() else {}
	var saw_hero_attack:=false;var saw_enemy_attack:=false
	var saw_hero_damage:=false;var saw_enemy_damage:=false
	for row in latest_group.get("rows",[]):
		if not row is Dictionary:continue
		if str(row.get("type",""))=="action.melee_attack":
			saw_hero_attack=saw_hero_attack or int(row.get("actor_id",-1))==hero
			saw_enemy_attack=saw_enemy_attack or int(row.get("actor_id",-1))==enemy
		elif str(row.get("type","")).begins_with("combat."):
			saw_hero_damage=saw_hero_damage or int(row.get("instigator_id",-1))==hero
			saw_enemy_damage=saw_enemy_damage or int(row.get("instigator_id",-1))==enemy
	_check(saw_hero_attack and saw_enemy_attack and saw_hero_damage and saw_enemy_damage,
		"%s direct-solo turn lacks hero hit or enemy counter-hit rows"%viewport_size)
	sandbox._refresh();await process_frame;await process_frame
	_check(sandbox.event_label.text==fast_text,
		"%s normal refresh diverges from direct-solo fast combat feed"%viewport_size)
	sandbox._toggle_record_modal();await process_frame
	var full_history:Dictionary=session.combat_log(64,500);var attributed_rows:=0
	for group in full_history.get("groups",[]):
		if not group is Dictionary:continue
		for row in group.get("rows",[]):
			if not row is Dictionary:continue
			var message:=str(row.get("message","")).strip_edges()
			if message.is_empty() or sandbox._is_persistent_log_filler(message):continue
			_check(message in sandbox.record_body.text,
				"%s full record omitted meaningful combat row: %s"%[viewport_size,message])
			var event_type:=str(row.get("type",""));var attribution:=""
			if event_type.begins_with("status."):
				attribution=str(row.get("target_name",""))
			elif event_type.begins_with("combat."):
				attribution=str(row.get("instigator_name",""))
			else:
				attribution=str(row.get("actor_name",""))
				if attribution.is_empty():attribution=str(row.get("target_name",""))
			if not attribution.is_empty():
				attributed_rows+=1
				_check(attribution in message,
					"%s combat record row lost actor attribution: %s"%[viewport_size,message])
	_check(attributed_rows>0,"%s full combat record has no attributed rows"%viewport_size)
	sandbox.queue_free();await process_frame

func _newest_meaningful_messages(sandbox,history:Dictionary,limit:int)->Array[String]:
	var groups:Variant=history.get("groups",[])
	if not groups is Array:return []
	for group_index in range(groups.size()-1,-1,-1):
		var damage:Array[String]=[];var other:Array[String]=[]
		var rows:Variant=groups[group_index].get("rows",[]) if groups[group_index] is Dictionary else []
		if not rows is Array:continue
		for row_index in range(rows.size()-1,-1,-1):
			var row:Variant=rows[row_index]
			if not row is Dictionary:continue
			var message:String=str(sandbox._combat_log_row_message(row)).replace("\n"," ")
			if message.is_empty() or sandbox._is_persistent_log_filler(message):continue
			if str(row.get("type","")).begins_with("combat.") \
					and str(row.get("type","")).ends_with("_damage"):
				damage.append(message)
			else:other.append(message)
		if damage.is_empty() and other.is_empty():continue
		var messages:Array[String]=[]
		for message_value in damage+other:
			var message:String=str(message_value)
			messages.append(message)
			if messages.size()>=limit:break
		return messages
	return []

func _adjacent_open_cells(session,entity_id:int)->Array[Vector2i]:
	var result:Array[Vector2i]=[];var origin:Vector2i=session.sim.world.entities[entity_id].position
	for direction_value in session.sim.movement.MOVE_DIRECTIONS_8:
		var position:=origin+Vector2i(direction_value)
		if session.sim.world.in_bounds(position) \
				and bool(TerrainRegistry.definition(
					str(session.sim.world.tile_at(position).terrain)).get("passable",false)):
			result.append(position)
	return result

func _fixed_frame_ok(node:Node)->bool:
	if node==null or not node.has_method("frame_spec"):return false
	var spec:Dictionary=node.call("frame_spec")
	return str(spec.get("primitive",""))=="FIXED_CELL_GLYPHS" \
		and str(spec.get("font_path",""))=="res://assets/fonts/LivingWorldMonoKR.ttf" \
		and bool(spec.get("right_edge_inside",false)) and bool(spec.get("bottom_edge_inside",false)) \
		and not bool(spec.get("title_overdraws_border",true)) \
		and int(spec.get("columns",0))>=2 and int(spec.get("rows",0))>=2

func _gauge_ok(node:Node,prefix:String)->bool:
	if node==null or not node.has_method("gauge_spec"):return false
	var spec:Dictionary=node.call("gauge_spec")
	return str(spec.get("primitive",""))=="DOS_TEXT_GAUGE" and str(spec.get("prefix",""))==prefix \
		and "[" in str(spec.get("text","")) and str(spec.get("filled_glyph",""))=="#" \
		and str(spec.get("empty_glyph",""))=="."

func _semantic_gauge_ok(node:Node,role:String,color:Color)->bool:
	if node==null or not node.has_method("gauge_spec"):return false
	var spec:Dictionary=node.call("gauge_spec")
	var colors:Dictionary=spec.get("segment_colors",{}) \
		if spec.get("segment_colors",{}) is Dictionary else {}
	return str(spec.get("semantic_role",""))==role \
		and str(colors.get("fill",""))==color.to_html() \
		and str(colors.get("label",""))==AsciiGaugeScript.AGED_BONE.to_html() \
		and str(colors.get("empty",""))==AsciiGaugeScript.EMPTY_IRON.to_html() \
		and str(colors.get("value",""))==AsciiGaugeScript.AGED_BONE.to_html()

func _single_nested(frame:Node,content:Node)->bool:
	return frame!=null and content!=null and frame.get_child_count()==1 and frame.get_child(0)==content

func _strictly_inside(frame:Control,content:Control)->bool:
	if frame==null or content==null:return false
	var outer:=frame.get_global_rect();var inner:=content.get_global_rect()
	return inner.position.x>outer.position.x and inner.position.y>outer.position.y \
		and inner.end.x<outer.end.x and inner.end.y<outer.end.y

func _inside_rect(parent:Control,child:Control)->bool:
	if parent==null or child==null:return false
	var outer:=parent.get_global_rect();var inner:=child.get_global_rect()
	return inner.position.x>=outer.position.x-0.5 and inner.position.y>=outer.position.y-0.5 \
		and inner.end.x<=outer.end.x+0.5 and inner.end.y<=outer.end.y+0.5

func _check(condition:bool,message:String)->void:
	if not condition:failures.append(message)
