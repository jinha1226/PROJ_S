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
	_check(sandbox.root_layout.get_global_rect().size.is_equal_approx(viewport_size),
		"%s product layout is not full bleed"%viewport_size)
	_check(sandbox.grid.size.x>=viewport_size.x-1.0,"%s map lost full width"%viewport_size)
	var minimap_frame=sandbox.find_child("MinimapAsciiFrame",true,false)
	var dossier_frame=sandbox.find_child("DossierAsciiFrame",true,false)
	_check(_fixed_frame_ok(minimap_frame),"%s minimap frame is not fixed-cell safe"%viewport_size)
	_check(_fixed_frame_ok(dossier_frame),"%s dossier frame is not fixed-cell safe"%viewport_size)
	_check(_single_nested(minimap_frame,sandbox.minimap),"%s minimap frame/content are siblings"%viewport_size)
	var card=sandbox.cards.get_child(0) as Button
	var card_content=card.find_child("CardContent",true,false) as Control
	_check(dossier_frame.get_parent()==card and _single_nested(dossier_frame,card_content),
		"%s dossier hierarchy is not Button -> Frame -> Content"%viewport_size)
	_check(_strictly_inside(dossier_frame,card_content),"%s dossier content touches frame glyph cells"%viewport_size)
	var solo_identity=card.find_child("SoloIdentity",true,false) as Control
	_check(card.find_child("Portrait",true,false)==null and solo_identity!=null \
		and solo_identity.size.x>=card_content.size.x-0.5,
		"%s solo dossier did not reclaim the portrait width for identity"%viewport_size)
	for contract in [["NarrativeLogToggle","[F1 기록]"],["HeroDetailButton","[F2 인물]"],["Ascii3DLabButton","[F3 3D]"]]:
		var action=sandbox.find_child(str(contract[0]),true,false) as Button
		_check(action!=null and action.text==str(contract[1]) and "\n" not in action.text \
			and bool(action.get_meta("dos_command",false)) and action.custom_minimum_size.y>=44,
			"%s %s is not a single-line DOS command"%[viewport_size,contract[0]])
	var hp=sandbox.find_child("MemberState",true,false)
	var xp=sandbox.find_child("CompactXPBar",true,false)
	_check(_gauge_ok(hp,"HP") and _gauge_ok(xp,"XP"),"%s dossier lacks visible #/. DOS gauges"%viewport_size)
	_check(sandbox.find_children("*","ProgressBar",true,false).is_empty(),
		"%s solo DOS HUD still contains a visible modern ProgressBar"%viewport_size)
	var command_probe:=HBoxContainer.new();sandbox.add_child(command_probe)
	var execute=sandbox._add_button(command_probe,"지금 실행","TurnConfirm",func():pass)
	_check(execute.text=="[E 실행]" and execute.custom_minimum_size.y>=44 \
		and bool(execute.get_meta("dos_command",false)),"%s bottom command grammar missing"%viewport_size)
	command_probe.queue_free()

	sandbox._open_hero_detail();await process_frame;await process_frame
	var panel=sandbox.member_detail_panel;var folio=sandbox.find_child("MemberDetailAsciiFrame",true,false)
	var stack=sandbox.find_child("MemberDetailStack",true,false) as Control
	_check(panel.get_global_rect().end.x<=viewport_size.x+0.5 and panel.get_global_rect().end.y<=viewport_size.y+0.5,
		"%s DOS folio clips viewport: %s"%[viewport_size,panel.get_global_rect()])
	_check(_fixed_frame_ok(folio) and panel.get_child_count()==1 and panel.get_child(0)==folio \
		and _single_nested(folio,stack),"%s folio hierarchy is not Panel -> Frame -> Stack"%viewport_size)
	_check(_strictly_inside(folio,stack),"%s folio content touches border cells"%viewport_size)
	var identity_panel=sandbox.find_child("StatusIdentityPanel",true,false)
	var identity_frame=sandbox.find_child("StatusIdentityAsciiFrame",true,false)
	var identity=sandbox.find_child("StatusIdentity",true,false)
	_check(identity_panel.get_child_count()==1 and identity_panel.get_child(0)==identity_frame \
		and _single_nested(identity_frame,identity) and _strictly_inside(identity_frame,identity),
		"%s status hierarchy overlaps its frame"%viewport_size)
	_check(sandbox.find_child("MemberDetailPortrait",true,false)==null \
		and sandbox.find_child("StatusPortrait",true,false)==null,
		"%s member folio still duplicates the map actor as a portrait"%viewport_size)
	_check(_gauge_ok(sandbox.find_child("StatusHealthBar",true,false),"HP"),
		"%s status tab health is not a DOS gauge"%viewport_size)
	_check(sandbox.member_detail_status_tab.text=="[상태]" and "◆" not in sandbox.member_detail_status_tab.text,
		"%s DOS tab selection grammar missing"%viewport_size)

	sandbox._select_member_detail_tab("SKILL");await process_frame;await process_frame
	_check(sandbox.member_detail_skill_tab.text=="[스킬]","%s selected skill tab is not bracketed"%viewport_size)
	for skill_id in ["MELEE","GUARD","EXPLORATION"]:
		var skill_panel=sandbox.find_child("SkillCard%s"%skill_id,true,false)
		var skill_frame=skill_panel.find_child("SkillAsciiFrame",false,false)
		var skill_content=skill_frame.get_child(0) if skill_frame!=null and skill_frame.get_child_count()==1 else null
		_check(skill_panel.get_child_count()==1 and skill_panel.get_child(0)==skill_frame \
			and skill_content is Control and _strictly_inside(skill_frame,skill_content),
			"%s %s skill hierarchy overlaps its frame"%[viewport_size,skill_id])
		_check(_gauge_ok(skill_frame.find_child("TrainingProgress",true,false),"숙련"),
			"%s %s skill mastery is not a DOS gauge"%[viewport_size,skill_id])
	for child in sandbox.member_detail_focus_buttons.get_children():
		_check(child is Button and child.custom_minimum_size.y>=44 and "◆" not in child.text and "◇" not in child.text,
			"%s training focus retained decorative sigils"%viewport_size)
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

func _check(condition:bool,message:String)->void:
	if not condition:failures.append(message)
