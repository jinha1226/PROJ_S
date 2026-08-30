extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")

var failures:Array[String]=[]

func _init()->void:call_deferred("_run")

func _run()->void:
	var session=Session.new(44,20260831,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new();root.add_child(sandbox)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	await process_frame;await process_frame
	sandbox._open_hero_detail();await process_frame
	sandbox._select_member_detail_tab("SKILL");sandbox._toggle_weapon_mastery_category()
	await process_frame;await process_frame;await process_frame
	var scroll:ScrollContainer=sandbox.member_detail_scroll
	var mode_button:=sandbox.find_child("SkillModeButton",true,false) as Button
	_check(scroll!=null and scroll.scroll_deadzone>=12 and not scroll.follow_focus,
		"detail scroll touch contract is missing")
	_check(mode_button!=null and mode_button.action_mode==BaseButton.ACTION_MODE_BUTTON_RELEASE \
		and mode_button.focus_mode==Control.FOCUS_NONE and mode_button.custom_minimum_size.y>=44,
		"skill mode button is not release-only/focus-free/touch-sized")
	_check(sandbox.find_child("SkillDetail",true,false)==null \
		and sandbox.find_child("TrainingProgress",true,false)==null,
		"fixed ledger still creates a tap-expanded detail panel")
	# The six 44px rows can fit this portrait viewport. Make one hidden-with-category
	# test row taller only for input testing so a real ScrollContainer drag is
	# exercised without adding product spacer/detail UI.
	var overflow_panel:=sandbox.find_child("SkillCardUNARMED",true,false) as Control
	if overflow_panel!=null:overflow_panel.custom_minimum_size.y=220
	sandbox._reflow_member_detail_scroll();await process_frame;await process_frame
	var maximum_before:=int(scroll.get_v_scroll_bar().max_value-scroll.get_v_scroll_bar().page)
	_check(maximum_before>0,"forced ledger overflow is not continuously scrollable")
	var mode_before:=_skill_mode(session,"SWORD")
	var center:=mode_button.get_global_rect().get_center()
	_push_touch(center,true,17)
	await process_frame
	for step in range(1,5):
		var drag:=InputEventScreenDrag.new();drag.index=17;drag.position=center+Vector2(0,-30*step)
		drag.relative=Vector2(0,-30);root.push_input(drag,true);await process_frame
	_push_touch(center+Vector2(0,-120),false,17)
	await process_frame;await process_frame
	_check(scroll.scroll_vertical>0,"ScreenTouch drag over SkillModeButton did not scroll the tab body")
	_check(_skill_mode(session,"SWORD")==mode_before,
		"ScreenTouch drag over SkillModeButton changed training mode")
	sandbox._toggle_weapon_mastery_category();await process_frame;await process_frame
	_check(scroll.scroll_vertical==0,"category collapse did not clamp scroll position")
	sandbox._toggle_weapon_mastery_category();await process_frame;await process_frame
	_check(int(scroll.get_v_scroll_bar().max_value-scroll.get_v_scroll_bar().page)>0,
		"category re-expand did not recalculate content height")
	sandbox._select_member_detail_tab("ITEM");await process_frame
	sandbox._select_member_detail_tab("SKILL");await process_frame
	_check(scroll.scroll_vertical==0,"tab switch did not reset scroll top")
	mode_button=sandbox.member_progression_skill_rows.SWORD.title as Button
	center=mode_button.get_global_rect().get_center()
	_push_touch(center,true,18);await process_frame;_push_touch(center,false,18)
	await process_frame;await process_frame
	var expected:String=str({"FOCUS":"NORMAL","NORMAL":"OFF","OFF":"FOCUS"}.get(mode_before,""))
	_check(_skill_mode(session,"SWORD")==expected,"short ScreenTouch did not cycle training mode exactly once")
	sandbox.queue_free();await process_frame
	if failures.is_empty():print("PASS detail scroll touch smoke: drag scrolls without mode cycle; short tap cycles once")
	else:
		for failure in failures:print("FAIL detail scroll touch smoke -- ",failure)
	quit(1 if not failures.is_empty() else 0)

func _skill_mode(session,skill_id:String)->String:
	for skill in session.protagonist_progression().get("skills",[]):
		if skill is Dictionary and str(skill.get("skill_id",""))==skill_id:
			return str(skill.get("training_mode",""))
	return ""

func _push_touch(position:Vector2,pressed:bool,index:int)->void:
	var touch:=InputEventScreenTouch.new();touch.index=index;touch.pressed=pressed
	touch.position=position;root.push_input(touch,true)

func _check(condition:bool,message:String)->void:
	if not condition:failures.append(message)
