extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const TerrainRegistry=preload("res://sim/terrain_registry.gd")

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
	sandbox.combat_action_area.visible=true;sandbox._position_build_label();await process_frame
	sandbox._position_build_label();await process_frame
	_check(not sandbox.build_label.get_global_rect().intersects(
		sandbox.combat_action_area.get_global_rect()),
		"%s build label %s overlaps bottom action rect %s"%[viewport_size,
			sandbox.build_label.get_global_rect(),sandbox.combat_action_area.get_global_rect()])
	sandbox.combat_action_area.visible=false;sandbox._position_build_label();await process_frame
	_check(sandbox.grid.size.is_equal_approx(grid_size_before_build_probe),
		"%s absolute build overlay changed the map footprint"%viewport_size)
	_check(sandbox.grid.size.x>=viewport_size.x-1.0,"%s map lost full width"%viewport_size)
	_check(sandbox.grid.visible_cell_count==15,
		"%s product camera changed from the full-width 15x15 contract"%viewport_size)
	_check(not sandbox.phase_panel.visible and sandbox.phase_panel.custom_minimum_size.y==0.0 \
		and not sandbox.top_hud_actions.visible and not sandbox.ascii_3d_lab_button.visible,
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
	_check(sandbox.event_surface.visible and sandbox.event_label.max_lines_visible==2 \
		and not sandbox.info_scroll.visible and not sandbox.deck.visible and not sandbox.log_label.visible,
		"%s compact event surface did not replace generic context/log copies"%viewport_size)
	_check(sandbox._compact_meaningful_event_text({"groups":[]},{"safe_phase":"ENGAGED"}).is_empty() \
		and sandbox._compact_meaningful_event_text({"groups":[]},{"safe_phase":"GROUPED"}).is_empty(),
		"%s empty event history synthesized product-log filler"%viewport_size)
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
	_check(sandbox.member_detail_status_tab.text=="[상태]" and "◆" not in sandbox.member_detail_status_tab.text,
		"%s DOS tab selection grammar missing"%viewport_size)
	for tab in [sandbox.member_detail_status_tab,sandbox.member_detail_skill_tab,
			sandbox.member_detail_item_tab]:
		_check(tab.custom_minimum_size.y>=44 and _inside_rect(sandbox.member_detail_tab_row,tab),
			"%s detail tab text/target overflows its rail"%viewport_size)

	sandbox._select_member_detail_tab("SKILL");await process_frame;await process_frame
	_check(sandbox.member_detail_skill_tab.text=="[숙련]","%s selected skill tab is not bracketed"%viewport_size)
	sandbox._toggle_weapon_mastery_category();await process_frame
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
		var expected_tone:=AsciiUIFrame.BRASS if raw_weight==3 else (AsciiUIFrame.MUTED if raw_weight==0 else AsciiUIFrame.CYAN)
		_check(mode_label.get_theme_color("font_color").is_equal_approx(expected_tone),
			"%s %s ledger mode tone does not match its 3/1/0 state"%[viewport_size,skill_id])
		_check(mode_label.get_global_rect().end.x<=xp_label.get_global_rect().position.x+0.5 \
			and xp_label.get_global_rect().end.x<=skill_panel.get_global_rect().end.x+0.5,
			"%s %s current XP is not the far-right ledger column"%[viewport_size,skill_id])
	_check(sandbox.find_child("SkillDetail",true,false)==null \
		and sandbox.find_child("TrainingProgress",true,false)==null \
		and sandbox.find_child("FutureMilestone",true,false)==null,
		"%s proficiency selection still creates extra detail content"%viewport_size)
	_check(panel.get_global_rect().end.x<=viewport_size.x+0.5,
		"%s fixed skill ledger widened/clipped the 420px folio"%viewport_size)
	sandbox._select_member_detail_tab("ITEM");await process_frame
	_check(sandbox.member_item_window.visible and sandbox.member_detail_item_tab.text=="[아이템]",
		"%s item tab is not independently selectable"%viewport_size)
	var weapon_stats=sandbox.find_child("EquippedWeaponStats",true,false) as GridContainer
	_check(weapon_stats!=null and weapon_stats.columns==2 and weapon_stats.get_child_count()==4 \
		and sandbox.member_item_ammo_text.custom_minimum_size.y>=44 \
		and sandbox.member_item_empty_text.custom_minimum_size.y>=44,
		"%s item tab lacks compact 2x2 stats/ammo/empty inventory rows"%viewport_size)
	_check(panel.get_global_rect().end.x<=viewport_size.x+0.5,
		"%s item tab widened/clipped the detail folio"%viewport_size)
	_check(sandbox.find_children("*","ProgressBar",true,false).is_empty(),
		"%s DOS modal still contains a modern ProgressBar"%viewport_size)
	sandbox.queue_free();await process_frame
	await _check_direct_solo_combat_log(viewport_size)

func _check_direct_solo_combat_log(viewport_size:Vector2)->void:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
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
	sandbox._stage_auto_combat_action("MELEE",[],enemy)
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
	var messages:Array[String]=[];var groups:Variant=history.get("groups",[])
	if not groups is Array:return messages
	for group_index in range(groups.size()-1,-1,-1):
		var rows:Variant=groups[group_index].get("rows",[]) if groups[group_index] is Dictionary else []
		if not rows is Array:continue
		for row_index in range(rows.size()-1,-1,-1):
			var message:=str(rows[row_index].get("message","")) \
				if rows[row_index] is Dictionary else ""
			message=message.strip_edges().replace("\n"," ")
			if message.is_empty() or sandbox._is_persistent_log_filler(message):continue
			messages.append(message)
			if messages.size()>=limit:return messages
	return messages

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
