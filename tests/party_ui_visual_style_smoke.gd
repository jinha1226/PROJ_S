extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")

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
	_check(is_equal_approx(sandbox.build_label.anchor_left,1.0) \
		and is_equal_approx(sandbox.build_label.anchor_top,1.0) \
		and is_equal_approx(sandbox.build_label.anchor_right,1.0) \
		and is_equal_approx(sandbox.build_label.anchor_bottom,1.0),
		"%s build label is not bottom-right anchored"%viewport_size)
	_check(_inside_rect(sandbox,sandbox.build_label),
		"%s build label clips the viewport"%viewport_size)
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
	_check(is_equal_approx(sandbox.phase_panel.custom_minimum_size.y,64.0),
		"%s top HUD did not shrink to 64px"%viewport_size)
	if viewport_size.x>=450.0:
		_check(sandbox.grid.size.is_equal_approx(Vector2(450,450)),
			"%s logical map footprint changed from 450x450: %s"%[viewport_size,sandbox.grid.size])
	var minimap_frame=sandbox.find_child("MinimapAsciiFrame",true,false)
	var dossier_frame=sandbox.find_child("DossierAsciiFrame",true,false)
	_check(_fixed_frame_ok(minimap_frame),"%s minimap frame is not fixed-cell safe"%viewport_size)
	_check(_fixed_frame_ok(dossier_frame),"%s dossier frame is not fixed-cell safe"%viewport_size)
	_check(int(minimap_frame.frame_spec().font_size)==9 \
		and int(dossier_frame.frame_spec().font_size)==9,
		"%s compact UI frames did not retain a shared reduced cell size"%viewport_size)
	_check(_single_nested(minimap_frame,sandbox.minimap),"%s minimap frame/content are siblings"%viewport_size)
	var card=sandbox.cards.get_child(0) as Button
	var card_content=card.find_child("CardContent",true,false) as Control
	_check(dossier_frame.get_parent()==card and _single_nested(dossier_frame,card_content),
		"%s dossier hierarchy is not Button -> Frame -> Content"%viewport_size)
	_check(_strictly_inside(dossier_frame,card_content),"%s dossier content touches frame glyph cells"%viewport_size)
	var solo_identity=card.find_child("SoloIdentity",true,false) as Control
	var actor_seal=card.find_child("ActorGlyphSeal",true,false) as Label
	_check(card.find_child("Portrait",true,false)==null and solo_identity!=null \
		and actor_seal!=null and actor_seal.text=="@" and actor_seal.custom_minimum_size.x==44,
		"%s solo dossier did not use the 44px ASCII actor seal"%viewport_size)
	_check(int(sandbox.party_card_layout_spec(1,viewport_size.x).party_height)==90 \
		and int(sandbox.party_card_layout_spec(2,viewport_size.x).party_height)==100 \
		and int(sandbox.party_card_layout_spec(3,viewport_size.x).party_height)==108,
		"%s responsive dossier heights differ from 90/100/108"%viewport_size)
	for contract in [["NarrativeLogToggle","[기록]"],["HeroDetailButton","[인물]"],["Ascii3DLabButton","[3D]"]]:
		var action=sandbox.find_child(str(contract[0]),true,false) as Button
		_check(action!=null and action.text==str(contract[1]) and "\n" not in action.text \
			and bool(action.get_meta("dos_command",false)) and action.custom_minimum_size==Vector2(44,44),
			"%s %s is not a single-line DOS command"%[viewport_size,contract[0]])
		_check(_inside_rect(sandbox.phase_panel,action),
			"%s %s overflows the compact top HUD"%[viewport_size,contract[0]])
	_check(not sandbox.recent_event_label.visible and sandbox.deck.visible!=sandbox.log_label.visible,
		"%s duplicate recent/context/log surfaces remain visible"%viewport_size)
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
		var compact_frame=compact_card.find_child("DossierAsciiFrame",true,false) as Control
		_check(_inside_rect(compact_card,compact_frame),
			"%s 3-member dossier escaped its responsive card bounds"%viewport_size)
	var speech_text=sandbox.find_child("CompanionSpeechText",true,false) as Label
	_check(speech_text!=null and "\n" not in speech_text.text and speech_text.max_lines_visible==1,
		"%s companion speech is not one compact line"%viewport_size)

	sandbox._open_hero_detail();await process_frame;await process_frame
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
	var visible_details:=0
	var selected_ledger_rows:=0
	for skill_id in ["SWORD","AXE","BLUNT","SPEAR","RANGED","UNARMED"]:
		var skill_panel=sandbox.find_child("SkillCard%s"%skill_id,true,false)
		var detail=skill_panel.find_child("SkillDetail",true,false) as Control
		if detail.visible:visible_details+=1
		_check(skill_panel.find_child("SkillAsciiFrame",true,false)==null,
			"%s %s still has a nested ASCII frame"%[viewport_size,skill_id])
		_check(_gauge_ok(skill_panel.find_child("TrainingProgress",true,false),"훈련"),
			"%s %s skill mastery is not a DOS gauge"%[viewport_size,skill_id])
		var mode_button=skill_panel.find_child("SkillModeButton",true,false)
		_check(mode_button is Button and mode_button.custom_minimum_size.y>=44,
			"%s %s training mode is not touch sized"%[viewport_size,skill_id])
		if mode_button.text.begins_with("> "):selected_ledger_rows+=1
		var raw_weight:=int(mode_button.get_meta("raw_training_weight",-1))
		var transparent_style:StyleBoxFlat=mode_button.get_theme_stylebox("normal") as StyleBoxFlat
		_check(bool(mode_button.get_meta("no_button_chrome",false)) and transparent_style!=null \
			and transparent_style.bg_color.a==0.0 and transparent_style.border_width_left==0 \
			and "XP×%d"%raw_weight in mode_button.text and raw_weight in [0,1,3],
			"%s %s ledger row shows chrome or a non-authoritative XP multiplier"%[viewport_size,skill_id])
		var expected_tone:=AsciiUIFrame.BRASS if raw_weight==3 else (AsciiUIFrame.MUTED if raw_weight==0 else AsciiUIFrame.CYAN)
		_check(mode_button.get_theme_color("font_color").is_equal_approx(expected_tone),
			"%s %s ledger mode tone does not match its 3/1/0 state"%[viewport_size,skill_id])
	_check(visible_details==1,"%s skill list did not expand exactly one selected row"%viewport_size)
	_check(selected_ledger_rows==1,"%s skill ledger did not mark exactly one row with >"%viewport_size)
	_check(panel.get_global_rect().end.x<=viewport_size.x+0.5,
		"%s expanded skill ledger widened/clipped the 420px folio"%viewport_size)
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
