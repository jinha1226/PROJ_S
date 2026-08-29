extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const AsciiFrame=preload("res://playtest/ascii_ui_frame.gd")

var failures:Array[String]=[]

func _init()->void:
	call_deferred("_run")

func _run()->void:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		await _check_viewport(viewport_size)
	if failures.is_empty():
		print("PASS party UI ASCII folio smoke: 360x640, 450x800")
	else:
		for failure in failures:print("FAIL party UI ASCII folio smoke -- ",failure)
	quit(1 if not failures.is_empty() else 0)

func _check_viewport(viewport_size:Vector2)->void:
	var sandbox=Sandbox.new();sandbox.name="StyledPartySandbox"
	root.add_child(sandbox);sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sandbox.position=Vector2.ZERO;sandbox.size=viewport_size
	sandbox.initialize_for_headless_test(
		Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID),true)
	await process_frame;await process_frame
	_check(sandbox.size.is_equal_approx(viewport_size),"%s root is not full rect: %s"%[viewport_size,sandbox.size])
	_check(sandbox.root_layout.get_global_rect().size.is_equal_approx(viewport_size),
		"%s product layout is not full bleed"%viewport_size)
	_check(sandbox.phase_panel.get_global_rect().end.x<=viewport_size.x+0.5,
		"%s top HUD clips horizontally"%viewport_size)
	_check(sandbox.top_hud_actions.get_global_rect().end.x<=viewport_size.x+0.5,
		"%s action rail clips horizontally"%viewport_size)
	_check(sandbox.grid.size.x>=viewport_size.x-1.0,
		"%s map is not the full-width visual anchor: %.1f"%[viewport_size,sandbox.grid.size.x])
	var minimap_frame=sandbox.find_child("MinimapAsciiFrame",true,false)
	var dossier_frame=sandbox.find_child("DossierAsciiFrame",true,false)
	_check(_glyph_frame_ok(minimap_frame),"%s minimap lacks a real glyph boundary"%viewport_size)
	_check(str(minimap_frame.get_meta("state_tone","")) in ["CALM","CONTACT"],
		"%s calm HUD did not publish its glyph state tone"%viewport_size)
	_check(_glyph_frame_ok(dossier_frame),"%s dossier lacks a real glyph boundary"%viewport_size)
	_check(_borderless(sandbox.phase_panel,"panel"),"%s top HUD revived a visible StyleBox border"%viewport_size)
	var card=sandbox.cards.get_child(0) as Control
	_check(card.get_global_rect().end.x<=viewport_size.x+0.5,
		"%s dossier clips horizontally"%viewport_size)
	for action_name in ["NarrativeLogToggle","HeroDetailButton","Ascii3DLabButton"]:
		var action=sandbox.find_child(action_name,true,false) as Button
		_check(action!=null and bool(action.get_meta("ascii_rail",false)) and action.custom_minimum_size.y>=44,
			"%s %s is not a touch-sized glyph rail action"%[viewport_size,action_name])
	var hp=sandbox.find_child("HealthBar",true,false) as ProgressBar
	var xp=sandbox.find_child("CompactXPBar",true,false) as ProgressBar
	_check(hp!=null and xp!=null and bool(hp.get_meta("ascii_gauge",false)) \
		and bool(xp.get_meta("ascii_gauge",false)) and hp.custom_minimum_size.y<=8,
		"%s HP/XP still use generic ProgressBar grammar"%viewport_size)
	sandbox._open_hero_detail();await process_frame;await process_frame
	var folio_rect:Rect2=sandbox.member_detail_panel.get_global_rect()
	_check(folio_rect.position.x>=0.0 \
		and sandbox.member_detail_panel.get_global_rect().end.x<=viewport_size.x+0.5 \
		and sandbox.member_detail_panel.get_global_rect().end.y<=viewport_size.y+0.5,
		"%s character folio clips viewport: %s min=%s"%[viewport_size,folio_rect,
			[sandbox.member_detail_panel.get_combined_minimum_size(),
			sandbox.find_child("MemberDetailStack",true,false).get_combined_minimum_size(),
			sandbox.find_child("MemberDetailHeader",true,false).get_combined_minimum_size(),
			sandbox.member_detail_scroll.get_combined_minimum_size()]])
	_check(_glyph_frame_ok(sandbox.find_child("MemberDetailAsciiFrame",true,false)),
		"%s character folio lacks glyph boundary"%viewport_size)
	_check(_borderless(sandbox.member_detail_panel,"panel"),
		"%s character folio revived a visible StyleBox border"%viewport_size)
	_check(sandbox.find_child("MemberDetailPortrait",true,false)!=null \
		and sandbox.member_detail_subtitle.text.contains("인간") \
		and sandbox.find_child("StatusFolioGrid",true,false)!=null,
		"%s status folio hierarchy is incomplete"%viewport_size)
	var status_grid=sandbox.find_child("StatusFolioGrid",true,false) as GridContainer
	_check(status_grid.columns==(2 if viewport_size.x>=540.0 else 1),
		"%s status folio did not adapt columns"%viewport_size)
	sandbox._select_member_detail_tab("SKILL");await process_frame
	_check(sandbox.find_children("SkillAsciiFrame","",true,false).size()==3,
		"%s skill folio does not expose three glyph-framed training rows"%viewport_size)
	for skill_id in ["MELEE","GUARD","EXPLORATION"]:
		_check(_borderless(sandbox.find_child("SkillCard%s"%skill_id,true,false),"panel"),
			"%s %s skill row revived a visible StyleBox border"%[viewport_size,skill_id])
	_check("━" in sandbox.member_detail_skill_tab.text,
		"%s selected skill tab lacks glyph underline"%viewport_size)
	for child in sandbox.member_detail_focus_buttons.get_children():
		_check(child is Button and bool(child.get_meta("ascii_rail",false)) \
			and child.custom_minimum_size.y>=44,"%s focus sigil is not touch-safe"%viewport_size)
	sandbox.queue_free();await process_frame

func _glyph_frame_ok(node:Node)->bool:
	if node==null or not node.has_method("frame_spec"):return false
	var spec:Dictionary=node.call("frame_spec")
	return str(spec.get("primitive",""))=="GLYPH_TEXT" \
		and "┌" in str(spec.get("boundary_glyphs","")) \
		and int(spec.get("horizontal_repeat",0))>0 \
		and int(spec.get("stylebox_border_width",-1))==0

func _borderless(control:Control,style_name:String)->bool:
	if control==null:return false
	var style:=control.get_theme_stylebox(style_name)
	if not style is StyleBoxFlat:return false
	return style.get_border_width(SIDE_LEFT)==0 and style.get_border_width(SIDE_TOP)==0 \
		and style.get_border_width(SIDE_RIGHT)==0 and style.get_border_width(SIDE_BOTTOM)==0

func _check(condition:bool,message:String)->void:
	if not condition:failures.append(message)
