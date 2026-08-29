extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const Action=preload("res://sim/party_action_command.gd")
const TerrainRegistry=preload("res://sim/terrain_registry.gd")
const AsciiPortrait=preload("res://playtest/ascii_actor_portrait.gd")

var failures:Array[String]=[]

func _init()->void: call_deferred("_run")

func _run()->void:
	for viewport_size in [Vector2(450,800),Vector2(360,640)]:
		root.size=Vector2i(int(viewport_size.x),int(viewport_size.y));await process_frame
		await _party_card_count_layouts(viewport_size)
		await _roster_lifecycle_layout(viewport_size)
		await _auto_showcase_and_combat_flow(viewport_size)
		await _companion_card_speech_layout(viewport_size)
		await _mvp_run_objective_and_restart(viewport_size)
		await _exploration_route_and_popover(viewport_size)
		await _portrait_detail_modal(viewport_size)
		await _combat_log_history(viewport_size)
		for preset in ["WEDGE","LINE","COLUMN"]:
			await _journey(viewport_size,preset)
		await _wide_camera_fallback(viewport_size)
		await _terminal(viewport_size)
	await _validate_authoritative_rejection_layouts_360()
	for failure in failures: printerr("FAIL "+failure)
	print("---- party UI layout smoke: %d journeys + %d wide fallbacks, %d failed ----"%[6,2,failures.size()])
	quit(1 if not failures.is_empty() else 0)

func _party_card_count_layouts(viewport_size:Vector2)->void:
	var session=_engaged_session([1,2],"WEDGE")
	session.prepare_auto_combat_plan()
	var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(session)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size;root.add_child(sandbox)
	await process_frame;await process_frame
	var all_rows:Array=session.party_cards();var speeches:Array=session.companion_speech_bubbles()
	for count in [1,2,3]:
		var rows:Array=[]
		for index in range(count):rows.append(all_rows[index].duplicate(true))
		var spec:Dictionary=sandbox.render_party_cards_for_headless_test(rows,speeches)
		await process_frame;await process_frame
		var expected_layout:String=["SPOTLIGHT","DUAL","COMPACT"][count-1]
		if str(spec.layout_id)!=expected_layout or sandbox.cards.get_child_count()!=count:
			failures.append("%s party count %d layout/render mismatch"%[viewport_size,count]);continue
		var party_rect:Rect2=sandbox.cards.get_global_rect();var viewport_rect:Rect2=sandbox.get_global_rect()
		if not _rect_contains(viewport_rect,party_rect):
			failures.append("%s count %d party area outside viewport %s"%[viewport_size,count,party_rect])
		if sandbox.grid.get_global_rect().intersects(party_rect):
			failures.append("%s count %d party area overlaps map"%[viewport_size,count])
		if sandbox.combat_action_area.visible and sandbox.combat_action_area.get_global_rect().intersects(party_rect):
			failures.append("%s count %d party area overlaps fixed action dock"%[viewport_size,count])
		var previous_rect:=Rect2()
		for index in range(count):
			var card:=sandbox.cards.get_child(index) as Button;var card_rect:=card.get_global_rect()
			if not _rect_contains(party_rect,card_rect):
				failures.append("%s count %d card %d outside party area"%[viewport_size,count,index])
			if index>0 and previous_rect.intersects(card_rect):
				failures.append("%s count %d cards overlap"%[viewport_size,count])
			previous_rect=card_rect
			var portrait:=card.find_child("Portrait",true,false) as Control
			if portrait==null or not _rect_contains(card_rect,portrait.get_global_rect()) \
					or portrait.custom_minimum_size.x<float(spec.portrait_min_size[0]):
				failures.append("%s count %d portrait bounds/budget"%[viewport_size,count])
			for label_name in ["MemberName","Readiness","EmotionState","MemberState","StressState"]:
				var label:=card.find_child(label_name,true,false) as Label
				if label==null or label.get_theme_font_size("font_size")<12 \
						or not _rect_contains(card_rect,label.get_global_rect()):
					failures.append("%s count %d %s bounds/font"%[viewport_size,count,label_name])
			var strip:=card.find_child("CompanionSpeechStrip",true,false) as PanelContainer
			if index==0 and strip!=null:failures.append("%s count %d hero speech present"%[viewport_size,count])
			elif index>0 and strip!=null and (strip.mouse_filter!=Control.MOUSE_FILTER_IGNORE \
					or not _rect_contains(card_rect,strip.get_global_rect())):
				failures.append("%s count %d speech input/bounds"%[viewport_size,count])
	sandbox.queue_free();await process_frame

func _roster_lifecycle_layout(viewport_size:Vector2)->void:
	var session=Session.new(44,20260828,"SHOWCASE_V1");var state=session.sim.world.party_encounter
	var dismissed:=int(state.party_member_ids[1])
	var candidate:=int(session.party_status().rescue_candidate_ids[0])
	if not session.dismiss_companion(dismissed).accepted:
		failures.append("%s roster layout dismiss rejected"%viewport_size);return
	if not session.stabilize_recruit_candidate(candidate).accepted:
		failures.append("%s rescue stabilization rejected"%viewport_size);return
	var sandbox=Sandbox.new();sandbox.size=viewport_size
	sandbox.initialize_for_headless_test(session);sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sandbox.size=viewport_size;root.add_child(sandbox);await process_frame;await process_frame
	if sandbox.cards.get_child_count()!=2:
		failures.append("%s dismissed roster did not render two cards"%viewport_size)
	var row:=sandbox.deck.find_child("RecruitCandidate%d"%candidate,true,false) as Control
	var recruit:=sandbox.deck.find_child("RecruitMember%d"%candidate,true,false) as Button
	var row_rect:Rect2=row.get_global_rect() if row!=null else Rect2()
	var scroll_rect:Rect2=sandbox.info_scroll.get_global_rect()
	var row_inside_scroll_width:bool=row!=null and _rect_contains(scroll_rect,row_rect)
	if row==null or recruit==null or recruit.custom_minimum_size.y<44.0 \
			or not row_inside_scroll_width or not _rect_contains(row_rect,recruit.get_global_rect()) \
			or recruit.get_global_rect().intersects(sandbox.grid.get_global_rect()):
		failures.append("%s candidate row/button bounds or touch target"%viewport_size)
	if sandbox.deck.find_child("RecruitCandidate%d"%dismissed,true,false)!=null:
		failures.append("%s exiled member leaked into candidate list"%viewport_size)
	var active_companion:=int(session.party_status().party_member_ids[1])
	sandbox._open_member_detail(active_companion);await process_frame
	if not sandbox.member_detail_dismiss.visible or sandbox.member_detail_dismiss.custom_minimum_size.y<44.0 \
			or not _rect_contains(sandbox.member_detail_panel.get_global_rect(),
				sandbox.member_detail_dismiss.get_global_rect()):
		failures.append("%s detail dismiss bounds or touch target"%viewport_size)
	sandbox.queue_free();await process_frame

func _auto_showcase_and_combat_flow(viewport_size:Vector2)->void:
	var main=Sandbox.new();main.size=viewport_size
	main.set_personality_entropy_source_for_headless_test(func():return 123456)
	main.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);main.size=viewport_size;root.add_child(main)
	await process_frame
	if str(main.session.party_status().get("scenario_id",""))!="SOLO_COMBAT_V1" \
			or not main.auto_orchestration_enabled:
		failures.append("%s main sandbox did not start SOLO auto mode"%viewport_size)
	if main.session.party_status().party_member_ids.size()!=1 or main.duel_lab_button.visible \
			or main.find_child("RosterManagement",true,false)!=null:
		failures.append("%s main SOLO product leaked party/LAB management"%viewport_size)
	if int(main.session.personality_seed)!=Session.new_expedition_personality_seed(123456):
		failures.append("%s main sandbox did not issue boundary personality seed"%viewport_size)
	main.queue_free();await process_frame

	var session=Session.new();var hero:=int(session.party_status().protagonist_id)
	if not session.commit_exploration(Command.wait(hero)).accepted:
		failures.append("%s auto CONTACT fixture rejected"%viewport_size);return
	var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(session,true)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size;root.add_child(sandbox)
	var deploy_step:=int(session.sim.world.step_index);var deploy_journal:int=session.command_journal.size()
	await process_frame
	if session.party_status().safe_phase!="CONTACT" or session.sim.world.step_index!=deploy_step \
			or session.command_journal.size()!=deploy_journal:
		failures.append("%s first deployment render barrier mutated session"%viewport_size)
	await process_frame
	if session.party_status().safe_phase!="ENGAGED":
		failures.append("%s second deployment barrier did not engage"%viewport_size);sandbox.queue_free();await process_frame;return
	if session.turn_intent_overlays().size()!=2:
		failures.append("%s ENGAGED placeholder omitted companion suggestions"%viewport_size)
	if sandbox.find_child("TurnConfirm",true,false)!=null:
		failures.append("%s auto mode created TurnConfirm"%viewport_size)
	var turn_step:=int(session.sim.world.step_index);var turn_journal:int=session.command_journal.size()
	var hold_button:=_button(sandbox,"ActorHold")
	if hold_button==null or not hold_button.is_visible_in_tree():
		failures.append("%s auto hero HOLD unreachable"%viewport_size)
		sandbox.queue_free();await process_frame;return
	var hold_center:=hold_button.get_global_rect().get_center()
	var hold_press:=InputEventMouseButton.new();hold_press.button_index=MOUSE_BUTTON_LEFT
	hold_press.pressed=true;hold_press.button_mask=MOUSE_BUTTON_MASK_LEFT
	hold_press.position=hold_center;hold_press.global_position=hold_center
	root.push_input(hold_press,true)
	await process_frame
	if session.sim.world.step_index!=turn_step or session.command_journal.size()!=turn_journal:
		failures.append("%s pressed-frame mutated auto combat"%viewport_size)
	var hold_release:=InputEventMouseButton.new();hold_release.button_index=MOUSE_BUTTON_LEFT
	hold_release.pressed=false;hold_release.button_mask=0
	hold_release.position=hold_center;hold_release.global_position=hold_center
	root.push_input(hold_release,true)
	await process_frame
	if session.sim.world.step_index!=turn_step or session.command_journal.size()!=turn_journal \
			or not sandbox.auto_combat_pending or sandbox.auto_combat_render_stage!=0:
		failures.append("%s release dispatch omitted pending final plan"%viewport_size)
	await process_frame
	if session.sim.world.step_index!=turn_step or session.command_journal.size()!=turn_journal \
			or not sandbox.auto_combat_pending or sandbox.auto_combat_render_stage!=1:
		failures.append("%s rendered final-plan frame mutated or dropped pending"%viewport_size)
	await process_frame
	if session.sim.world.step_index!=turn_step+1 or session.command_journal.size()!=turn_journal+1:
		failures.append("%s auto hero action did not commit exactly once"%viewport_size)
	await process_frame
	if session.sim.world.step_index!=turn_step+1 or session.command_journal.size()!=turn_journal+1 \
			or sandbox.auto_combat_pending:
		failures.append("%s auto hero action duplicated or remained pending"%viewport_size)
	sandbox.queue_free();await process_frame

func _companion_card_speech_layout(viewport_size:Vector2)->void:
	var session=Session.new();var hero:=int(session.party_status().protagonist_id)
	if not session.commit_exploration(Command.wait(hero)).accepted:
		failures.append("%s card speech CONTACT fixture rejected"%viewport_size);return
	var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(session,true)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size;root.add_child(sandbox)
	await process_frame
	if not sandbox.find_children("CompanionSpeechStrip","PanelContainer",true,false).is_empty():
		failures.append("%s CONTACT shows companion card speech"%viewport_size)
	await process_frame
	if session.party_status().safe_phase!="ENGAGED":
		failures.append("%s card speech auto fixture did not engage"%viewport_size)
		sandbox.queue_free();await process_frame;return
	await process_frame
	var label:="%s CARD_SPEECH"%viewport_size
	_validate_layout(sandbox,label)
	if sandbox.grid.has_method("speech_bubble_draw_specs"):
		failures.append("%s grid still exposes speech bubbles"%label)
	var bubbles:Array=session.companion_speech_bubbles()
	if bubbles.size()!=2:failures.append("%s expected two companion speeches"%label)
	var strip_rects:Array[Rect2]=[];var first_strip:PanelContainer=null;var first_actor:=-1
	var hero_card:Button=_button(sandbox,"MemberCard%d"%hero)
	if hero_card.find_child("CompanionSpeechStrip",true,false)!=null:
		failures.append("%s protagonist has card speech"%label)
	for bubble in bubbles:
		var actor_id:=int(bubble.actor_id);var card:Button=_button(sandbox,"MemberCard%d"%actor_id)
		var strip:=card.find_child("CompanionSpeechStrip",true,false) as PanelContainer
		var text:=card.find_child("CompanionSpeechText",true,false) as Label
		if strip==null or text==null:
			failures.append("%s missing speech on actor %d"%[label,actor_id]);continue
		if first_strip==null:first_strip=strip;first_actor=actor_id
		var lines:=text.text.split("\n")
		if lines.size()!=2 or str(lines[0])!=str(bubble.headline) \
				or str(lines[1])!=str(bubble.reason_summary):
			failures.append("%s actor %d speech is not exact two-line compact DTO: %s"%[label,actor_id,text.text])
		if str(lines[1]).length()>14:failures.append("%s actor %d speech reason too long"%[label,actor_id])
		if text.get_theme_font_size("font_size")<12:failures.append("%s actor %d speech font below 12"%[label,actor_id])
		if strip.mouse_filter!=Control.MOUSE_FILTER_IGNORE or text.mouse_filter!=Control.MOUSE_FILTER_IGNORE:
			failures.append("%s actor %d speech intercepts input"%[label,actor_id])
		var card_rect:=card.get_global_rect();var strip_rect:=strip.get_global_rect()
		if not _rect_contains(card_rect,strip_rect):failures.append("%s actor %d speech leaves card %s"%[label,actor_id,strip_rect])
		if strip_rect.intersects(sandbox.grid.get_global_rect()):failures.append("%s actor %d speech covers map"%[label,actor_id])
		if strip_rect.intersects(sandbox.combat_action_area.get_global_rect()):failures.append("%s actor %d speech covers bottom actions"%[label,actor_id])
		if text.get_line_count()!=2 or text.get_visible_line_count()!=2:
			failures.append("%s actor %d speech lines clipped %d/%d"%[label,actor_id,text.get_visible_line_count(),text.get_line_count()])
		strip_rects.append(strip_rect)
	if strip_rects.size()==2 and strip_rects[0].intersects(strip_rects[1]):
		failures.append("%s companion speech strips overlap"%label)
	if first_strip!=null:
		_touch_control_now(first_strip,false,7);await process_frame;await process_frame
		if sandbox.selected_member_id!=first_actor or sandbox.member_detail_modal.visible:
			failures.append("%s speech-area first tap did not select its portrait"%label)
		first_strip=_button(sandbox,"MemberCard%d"%first_actor).find_child(
			"CompanionSpeechStrip",true,false) as PanelContainer
		_touch_control_now(first_strip,true,7);await process_frame;await process_frame
		if not sandbox.member_detail_modal.visible:
			failures.append("%s speech-area double tap did not open portrait detail"%label)
		else:_touch_control_now(sandbox.member_detail_close,false,7)
		await process_frame;await process_frame
	var override_actor:=int(bubbles[0].actor_id) if not bubbles.is_empty() else -1
	if override_actor>0:
		if not session.override_companion(override_actor,Action.hold(override_actor)).accepted:
			failures.append("%s card speech override rejected"%label)
		sandbox._refresh();await process_frame;await process_frame
		var override_text:=(_button(sandbox,"MemberCard%d"%override_actor).find_child(
			"CompanionSpeechText",true,false) as Label).text
		if override_text!="방어할게.\n지시를 따라서":failures.append("%s override speech stale: %s"%[label,override_text])
		if sandbox.find_children("CompanionSpeechStrip","PanelContainer",true,false).size()!=2:
			failures.append("%s secondary suggestion created extra card speech"%label)
		if not session.clear_companion_override(override_actor).accepted:
			failures.append("%s card speech clear rejected"%label)
		sandbox._refresh();await process_frame;await process_frame
		var cleared_text:=(_button(sandbox,"MemberCard%d"%override_actor).find_child(
			"CompanionSpeechText",true,false) as Label).text
		if cleared_text==override_text:failures.append("%s clear did not refresh card speech"%label)
	sandbox.queue_free();await process_frame

func _mvp_run_objective_and_restart(viewport_size:Vector2)->void:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(session,true)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size;root.add_child(sandbox)
	await process_frame;await process_frame
	var label:="%s MVP_RUN"%viewport_size
	var objective:Label=sandbox.recent_event_label;var objective_bar:PanelContainer=sandbox.phase_panel
	if sandbox.root_layout.get_global_rect()!=sandbox.get_global_rect():
		failures.append("%s product root does not use the full viewport root=%s viewport=%s"%[
			label,sandbox.root_layout.get_global_rect(),sandbox.get_global_rect()])
	if absf(sandbox.grid.size.x-viewport_size.x)>0.1:
		failures.append("%s product exploration playfield does not use viewport width grid=%s"%[
			label,sandbox.grid.get_global_rect()])
	if not objective_bar.is_visible_in_tree() or objective_bar.size.y<87.9 \
			or objective_bar.size.y>96.1 or sandbox.minimap.size.x<77.9:
		failures.append("%s top HUD accessibility"%label)
	if sandbox.reward_badge.visible or sandbox.phase_label.text in ["탐험","시간","목표"]:
		failures.append("%s initial HUD leaks objective/time copy %s"%[label,sandbox.phase_label.text])
	_validate_run_objective_geometry(sandbox,label+" INITIAL")
	var grid_id:int=sandbox.grid.get_instance_id()
	var initial_cell_size:float=sandbox.grid.cell_size_px()
	var state=session.sim.world.party_encounter;var near_exit:=Vector2i(12,1);var exit:=Vector2i(13,1)
	state.group_anchor=near_exit;state.facing=Vector2i.RIGHT
	for member_id in state.party_member_ids:session.sim.world.entities[int(member_id)].position=near_exit
	sandbox._refresh();await process_frame;await process_frame
	var locked_before:Dictionary=session.sim.snapshot();var journal_before:Array=session.command_journal.duplicate(true)
	await _touch_cell(sandbox,exit)
	if sandbox.action_feedback_label.text!="적을 쓰러뜨리면 출구가 열립니다." \
			or not sandbox.combat_action_area.is_visible_in_tree() or sandbox.combat_action_dock.visible:
		failures.append("%s locked exit fixed feedback unavailable"%label)
	if session.sim.snapshot()!=locked_before or session.command_journal!=journal_before:
		failures.append("%s locked exit touch mutated authority"%label)
	sandbox._on_tile_long_pressed(exit);await process_frame;await process_frame
	if not sandbox.tile_popover.visible or not "출구 · 잠김" in sandbox.tile_popover_label.text:
		failures.append("%s locked exit inspector text"%label)
	_validate_run_objective_geometry(sandbox,label+" LOCKED")

	# This direct smoke fixture models a restored EXIT_OPEN save. A refresh must
	# synchronize the badge without replaying the live reward emphasis.
	state.safe_phase="GROUPED_COMPLETE";sandbox._refresh();await process_frame;await process_frame
	if not sandbox.reward_badge.visible or sandbox.reward_badge.text!="$ 1" \
			or sandbox.phase_label.text!="승리":
		failures.append("%s persistent reward/victory HUD"%label)
	if sandbox._reward_emphasis_count!=0:
		failures.append("%s loaded progress replayed reward emphasis"%label)
	sandbox._on_tile_long_pressed(exit);await process_frame;await process_frame
	if not "출구 · 열림" in sandbox.tile_popover_label.text:
		failures.append("%s open exit inspector text"%label)

	state.group_anchor=exit
	for member_id in state.party_member_ids:session.sim.world.entities[int(member_id)].position=exit
	sandbox._hide_tile_popover();sandbox._refresh();await process_frame;await process_frame
	if not bool(session.run_progress().complete) or sandbox.phase_label.text!="승리":
		failures.append("%s complete situation"%label)
	var restart:=_button(sandbox,"RestartSameRun")
	if restart==null or not restart.is_visible_in_tree() or sandbox.combat_action_dock.get_child_count()!=1 \
			or sandbox.action_feedback_label.visible:
		failures.append("%s complete fixed area is not one restart button"%label)
	if restart!=null and restart.text!="같은 원정 다시 시작":
		failures.append("%s solo restart button copy"%label)
	if sandbox.grid.visible_cell_count!=15 or not sandbox.grid._intent_overlays.is_empty() \
			or not sandbox.grid.route_draw_spec().segments.is_empty():
		failures.append("%s complete left stale camera/action overlays"%label)
	_validate_run_objective_geometry(sandbox,label+" COMPLETE")

	# Dirty every presentation seam that must not cross a run boundary.
	sandbox.grid.play_effects([{"effect_id":"restart-smoke","event_id":99991,"order":0,
		"kind":"HIT_FLASH","damage_type":"physical","world_position":[13,1],"text":""}])
	sandbox.grid.set_route_overlay([[13,1],[12,1]],0,true)
	sandbox.auto_deployment_pending=true;sandbox.auto_combat_pending=true
	sandbox.route_preview={"accepted":true,"path":[[13,1],[12,1]]}
	sandbox.selected_tile=exit;sandbox.selected_tile_inspection={"accepted":true}
	sandbox.member_detail_modal.visible=true;sandbox.grid.modal_open=true
	sandbox._scroll_log_after_refresh=true
	var personality_seed_before:=int(session.personality_seed)
	if restart!=null:restart.pressed.emit()
	await process_frame;await process_frame
	var fresh:Dictionary=session.run_progress()
	var fresh_status:Dictionary=session.party_status()
	var fresh_hero:=int(fresh_status.protagonist_id)
	var fresh_hero_position:Vector2i=session.sim.world.entities[fresh_hero].position
	if sandbox.grid.get_instance_id()!=grid_id or sandbox.grid.visible_cell_count!=15 \
			or sandbox.grid.view_origin!=fresh_hero_position-Vector2i(7,7) \
			or absf(sandbox.grid.cell_size_px()-initial_cell_size)>0.001:
		failures.append("%s restart replaced grid or lost 15x15 mapping"%label)
	if str(fresh.run_state)!="EXPLORE" or bool(fresh.reward.granted) or not session.command_journal.is_empty():
		failures.append("%s restart did not restore fresh run progress"%label)
	if int(session.personality_seed)!=personality_seed_before:
		failures.append("%s solo restart unexpectedly rerolled identity"%label)
	if sandbox.auto_deployment_pending or sandbox.auto_combat_pending or not sandbox.route_preview.is_empty() \
			or sandbox.member_detail_modal.visible or sandbox.grid.modal_open \
			or not sandbox.grid._active_visual_effects.is_empty() or not sandbox.grid._played_effect_ids.is_empty():
		failures.append("%s restart retained UI/grid transient state"%label)
	if _button(sandbox,"RestartSameRun")!=null or sandbox.combat_action_area.visible:
		failures.append("%s restart left terminal controls"%label)
	if sandbox.reward_badge.visible or sandbox.phase_label.text!="조용함":
		failures.append("%s restart HUD did not return to calm"%label)
	_validate_run_objective_geometry(sandbox,label+" RESTARTED")
	sandbox.queue_free();await process_frame

func _validate_run_objective_geometry(sandbox,label:String)->void:
	var viewport:Rect2=sandbox.get_global_rect();var bar:=sandbox.run_objective_bar as Control
	if not bar.is_visible_in_tree() or not _rect_contains(viewport,bar.get_global_rect()):
		failures.append("%s top HUD outside viewport %s"%[label,bar.get_global_rect()]);return
	var bar_rect:Rect2=bar.get_global_rect()
	var grid_rect:Rect2=sandbox.grid.get_global_rect()
	if sandbox._is_solo_product_session():
		if sandbox.root_layout.get_global_rect()!=viewport:
			failures.append("%s product root has an outer frame"%label)
		if absf(grid_rect.size.x-viewport.size.x)>0.1:
			failures.append("%s product grid leaves horizontal outer gutters"%label)
	if bar_rect.end.y>grid_rect.position.y+0.1:
		failures.append("%s top HUD overlaps grid"%label)
	if sandbox.minimap.size.x<77.9 or sandbox.record_button.size.x<43.9 \
			or sandbox.hero_detail_button.size.x<43.9:
		failures.append("%s top HUD controls below geometry contract"%label)
	for forbidden in ["탐험","시간","목표"]:
		if forbidden in sandbox.phase_label.text:
			failures.append("%s top HUD contains %s"%[label,forbidden])
	for child in sandbox.root_layout.get_children():
		if child is Control and child.is_visible_in_tree() and not _rect_contains(viewport,child.get_global_rect()):
			failures.append("%s root child outside viewport %s %s"%[label,child.name,child.get_global_rect()])
	if sandbox.info_scroll.size.y<29.9:
		failures.append("%s information scroll below 30px %s"%[label,sandbox.info_scroll.size])

func _exploration_route_and_popover(viewport_size:Vector2)->void:
	var session=Session.new();var status:Dictionary=session.party_status()
	var origin:=Vector2i(int(status.anchor[0]),int(status.anchor[1]));var far_goal:=Vector2i(-1,-1)
	for candidate in [origin+Vector2i(-3,0),origin+Vector2i(0,3),origin+Vector2i(0,-3)]:
		var probe:Dictionary=session.preview_exploration_route(candidate)
		if bool(probe.get("accepted",false)) and int(probe.get("total_steps",0))>=3:far_goal=candidate
		session.cancel_exploration_route()
		if far_goal!=Vector2i(-1,-1):break
	if far_goal==Vector2i(-1,-1):failures.append("%s no far route fixture"%viewport_size);return
	var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(session)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size;root.add_child(sandbox)
	await process_frame;await process_frame
	var before_world:Dictionary=session.sim.snapshot();var before_journal:Array=session.command_journal.duplicate(true)
	var before_route_draft:Dictionary=session.exploration_route_draft()
	# Mouse hold on an occupied actor tile is inspection-only. The release must not
	# become the protagonist's ordinary same-cell WAIT preview.
	await _mouse_hold_cell(sandbox,origin,0.62)
	if session.sim.snapshot()!=before_world or session.command_journal!=before_journal \
			or session.exploration_route_draft()!=before_route_draft or sandbox.pending_exploration_wait:
		failures.append("%s actor-tile mouse hold/release mutated route or world"%viewport_size)
	if sandbox.selected_tile!=origin:failures.append("%s actor-tile mouse hold inspected %s"%[viewport_size,sandbox.selected_tile])
	_validate_tile_popover(sandbox,viewport_size,"ACTOR_MOUSE_HOLD",false)
	if not "짧게 누르면 경로 확인 후 이동합니다" in sandbox.tile_popover_label.text or "다시" in sandbox.tile_popover_label.text:
		failures.append("%s pre-preview popover misstates the next short-tap action"%viewport_size)
	sandbox._hide_tile_popover()
	# A touch drag beyond the 14px slop cancels both the tap and the pending long
	# press, even if it remains held beyond the timeout.
	await _drag_hold_cell(sandbox,far_goal,Vector2(20,0),0.62)
	if session.sim.snapshot()!=before_world or session.command_journal!=before_journal \
			or session.exploration_route_draft()!=before_route_draft or sandbox.pending_exploration_wait:
		failures.append("%s dragged grid gesture emitted a route action"%viewport_size)
	if sandbox.tile_popover.visible:failures.append("%s dragged grid gesture opened tile popover"%viewport_size)
	# A short release previews and starts exactly one route hop in the same input.
	var first_short:bool=await _short_touch_cell(sandbox,far_goal,0.06,5)
	if not first_short:sandbox.queue_free();await process_frame;return
	if session.sim.world.step_index!=int(before_world.step_index)+1 \
			or session.command_journal.size()!=before_journal.size()+1:
		failures.append("%s far-route one ScreenTouch did not commit exactly one first hop"%viewport_size)
	if sandbox.tile_popover.visible:failures.append("%s short route start opened tile risk popover"%viewport_size)
	var preview:Dictionary=session.exploration_route_state();var spec:Dictionary=sandbox.grid.route_draw_spec()
	if not bool(preview.get("accepted",false)) or int(preview.get("total_steps",0))<3:
		failures.append("%s far-route one ScreenTouch did not retain active route"%viewport_size)
	if spec.segments.size()!=int(preview.get("total_steps",0)):
		failures.append("%s route overlay omitted steps %d/%d"%[viewport_size,spec.segments.size(),preview.get("total_steps",0)])
	if spec.tiles.size()!=preview.path.size() or spec.direction_cues.size()!=spec.segments.size():
		failures.append("%s route overlay omitted tile highlights/direction cues"%viewport_size)
	for tile in spec.tiles:
		if bool(tile.visible) and float(tile.fill_alpha)<0.099:
			failures.append("%s route tile highlight too faint %s"%[viewport_size,tile])
	# Drag cancellation retains pointer ownership: the queued route must remain
	# paused for the full 620ms hold and through release, then resume one hop on the
	# following frame.
	if bool(session.exploration_route_state().get("active",false)):
		var active_drag_step:=int(session.sim.world.step_index);var active_drag_state:Dictionary=session.exploration_route_state()
		var drag_position:=_cell_global_position(sandbox,far_goal);var drag_offset:=Vector2(20,0)
		_push_touch_now(drag_position,true,7)
		var active_drag:=InputEventScreenDrag.new();active_drag.index=7;active_drag.position=drag_position+drag_offset
		active_drag.relative=drag_offset;root.push_input(active_drag,true)
		await create_timer(0.62).timeout;await process_frame
		if session.sim.world.step_index!=active_drag_step or session.exploration_route_state()!=active_drag_state:
			failures.append("%s active route advanced while cancelled drag remained held"%viewport_size)
		var drag_gesture:Dictionary=sandbox.grid.pointer_gesture_state()
		if not bool(drag_gesture.get("active",false)) or not bool(drag_gesture.get("cancelled",false)):
			failures.append("%s active drag released pointer ownership before finger release"%viewport_size)
		_push_touch_now(drag_position+drag_offset,false,7)
		if session.sim.world.step_index!=active_drag_step:
			failures.append("%s active drag release emitted an immediate move"%viewport_size)
		await process_frame
		if session.sim.world.step_index!=active_drag_step+1:
			failures.append("%s active route did not resume one hop after drag release"%viewport_size)
	# A long press also pauses continuation. Inspection and release preserve the
	# route; release resumes exactly one hop on the next process frame.
	if bool(session.exploration_route_state().get("active",false)):
		var active_hold_step:=int(session.sim.world.step_index);var active_hold_state:Dictionary=session.exploration_route_state()
		var hold_position:=_cell_global_position(sandbox,far_goal)
		_push_touch_now(hold_position,true,8)
		await create_timer(0.62).timeout;await process_frame
		if session.sim.world.step_index!=active_hold_step or session.exploration_route_state()!=active_hold_state:
			failures.append("%s pointer hold failed to pause active route"%viewport_size)
		if not sandbox.tile_popover.visible:failures.append("%s active-route long hold did not inspect"%viewport_size)
		_push_touch_now(hold_position,false,8)
		if session.sim.world.step_index!=active_hold_step:
			failures.append("%s active-route long release emitted an immediate move"%viewport_size)
		await process_frame
		if session.sim.world.step_index!=active_hold_step+1:
			failures.append("%s active route did not resume one hop after long release"%viewport_size)
	var frame_guard:=0
	while bool(session.exploration_route_state().get("active",false)) and frame_guard<16:
		var prior_step:int=int(session.sim.world.step_index);await process_frame
		var delta:int=int(session.sim.world.step_index)-prior_step
		if delta!=1:failures.append("%s route frame committed %d hops instead of one"%[viewport_size,delta])
		frame_guard+=1
	var finished:Dictionary=session.exploration_route_state()
	if not bool(finished.get("completed",false)) or session.party_status().anchor!=[far_goal.x,far_goal.y]:
		failures.append("%s route did not finish at exact goal: %s"%[viewport_size,finished])
	sandbox.queue_free();await process_frame

	var contact_session=Session.new();var contact_status:Dictionary=contact_session.party_status()
	var contact_origin:=Vector2i(int(contact_status.anchor[0]),int(contact_status.anchor[1]));var contact_goal:=contact_origin+Vector2i(3,0)
	var contact=Sandbox.new();contact.size=viewport_size;contact.initialize_for_headless_test(contact_session)
	contact.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);contact.size=viewport_size;root.add_child(contact)
	await process_frame;await process_frame
	var contact_before:int=int(contact_session.sim.world.step_index)
	_touch_cell_now(contact,contact_goal)
	var stopped:Dictionary=contact_session.exploration_route_state();var stopped_step:int=int(contact_session.sim.world.step_index)
	if contact_session.party_status().safe_phase!="CONTACT" or str(stopped.get("stop_reason",""))!="route_contact":
		failures.append("%s route contact did not stop with facade state: %s"%[viewport_size,stopped])
	if stopped_step!=contact_before+1:failures.append("%s contact route committed more than one hop"%viewport_size)
	if str(stopped.get("message",""))!=contact.notice_text:failures.append("%s contact stop facade message not shown"%viewport_size)
	await process_frame;await process_frame
	if contact_session.sim.world.step_index!=stopped_step:failures.append("%s contact stop left queued movement"%viewport_size)
	contact.queue_free();await process_frame

func _portrait_detail_modal(viewport_size:Vector2)->void:
	var session=Session.new();var initial:Dictionary=session.party_status()
	var anchor:=Vector2i(int(initial.anchor[0]),int(initial.anchor[1]))
	if session.sim.world.bootstrap_set_fire(anchor,100)==null:failures.append("%s modal exposure fixture"%viewport_size)
	var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(session)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size;root.add_child(sandbox)
	await process_frame;await process_frame
	var hero:=int(initial.protagonist_id);var companion:=int(initial.party_member_ids[1])
	_touch_control_now(_button(sandbox,"MemberCard%d"%companion),false)
	await process_frame;await process_frame
	if sandbox.selected_member_id!=companion or sandbox.member_detail_modal.visible:
		failures.append("%s portrait first touch must only select"%viewport_size)
	_touch_control_now(_button(sandbox,"MemberCard%d"%hero),false)
	await process_frame;await process_frame
	if sandbox.selected_member_id!=hero or sandbox.member_detail_modal.visible:
		failures.append("%s different portrait second touch opened modal"%viewport_size)
	_touch_control_now(_button(sandbox,"MemberCard%d"%companion),false)
	await process_frame;await process_frame
	_touch_control_now(_button(sandbox,"MemberCard%d"%companion),true)
	if not sandbox.member_detail_modal.visible or not sandbox.grid.modal_open:
		failures.append("%s native portrait double_tap did not open modal"%viewport_size)
	await process_frame;await process_frame
	_validate_member_modal(sandbox,viewport_size)
	var blocked_world:Dictionary=session.sim.snapshot();var blocked_journal:Array=session.command_journal.duplicate(true)
	var blocked_route:Dictionary=session.exploration_route_state();var blocked_selection:int=int(sandbox.selected_member_id)
	_touch_cell_now(sandbox,anchor+Vector2i.LEFT)
	await process_frame;await process_frame
	if session.sim.snapshot()!=blocked_world or session.command_journal!=blocked_journal or session.exploration_route_state()!=blocked_route:
		failures.append("%s modal backdrop touch leaked to grid/session"%viewport_size)
	if sandbox.selected_member_id!=blocked_selection:failures.append("%s modal backdrop changed selection"%viewport_size)
	if not sandbox.member_detail_modal.visible or not sandbox.grid.modal_open:failures.append("%s modal panel touch unexpectedly closed modal"%viewport_size)
	_touch_screen_now(sandbox.get_global_rect().position+Vector2(4,4),2)
	if sandbox.member_detail_modal.visible or sandbox.grid.modal_open:failures.append("%s backdrop did not close modal gate"%viewport_size)
	_touch_control_now(_button(sandbox,"MemberCard%d"%companion),true)
	await process_frame;await process_frame
	if not sandbox.member_detail_modal.visible:failures.append("%s detail modal failed to reopen"%viewport_size)
	_touch_control_now(sandbox.member_detail_close,false)
	if sandbox.member_detail_modal.visible or sandbox.grid.modal_open:failures.append("%s actual close touch did not release modal gate"%viewport_size)
	_touch_control_now(_button(sandbox,"MemberCard%d"%companion),true);await process_frame;await process_frame
	_press_escape_now();await process_frame
	if sandbox.member_detail_modal.visible or sandbox.grid.modal_open:failures.append("%s Escape did not release modal gate"%viewport_size)

	var route_goal:=anchor+Vector2i(-5,0)
	_touch_cell_now(sandbox,route_goal);await process_frame;await process_frame
	_touch_cell_now(sandbox,route_goal)
	# Wait through one route frame and then through the same frame's deferred layout
	# queue, without crossing another process_frame (which would advance another hop).
	await process_frame;await create_timer(0.0).timeout
	var paused_at:int=int(session.sim.world.step_index)
	if not bool(session.exploration_route_state().get("active",false)):failures.append("%s modal pause route fixture not active"%viewport_size)
	var route_before_card:Dictionary=session.exploration_route_state();var route_card:Button=_button(sandbox,"MemberCard%d"%companion)
	_touch_control_now(route_card,false)
	if sandbox.selected_member_id!=companion:
		failures.append("%s active-route first portrait tap selected %d not %d"%[viewport_size,sandbox.selected_member_id,companion])
	var route_after_card:Dictionary=session.exploration_route_state()
	if route_after_card!=route_before_card:
		failures.append("%s active-route first portrait tap changed route %s -> %s"%[viewport_size,route_before_card,route_after_card])
	_touch_control_now(route_card,true)
	await process_frame;await process_frame
	if session.sim.world.step_index!=paused_at:failures.append("%s active route advanced behind modal"%viewport_size)
	if not sandbox.route_paused_by_modal:failures.append("%s active route was not marked paused"%viewport_size)
	_touch_control_now(sandbox.member_detail_close,false)
	var resume_before:int=int(session.sim.world.step_index);await process_frame
	if session.sim.world.step_index!=resume_before+1:failures.append("%s closing modal did not resume exactly one route hop"%viewport_size)
	sandbox._cancel_active_route();sandbox.queue_free();await process_frame

func _validate_member_modal(sandbox,viewport_size:Vector2)->void:
	var modal:Control=sandbox.member_detail_modal;var panel:PanelContainer=sandbox.member_detail_panel
	var body:Label=sandbox.member_detail_body;var scroll:ScrollContainer=sandbox.member_detail_scroll
	if not modal.is_visible_in_tree():failures.append("%s detail modal not visible in tree"%viewport_size);return
	if modal.mouse_filter!=Control.MOUSE_FILTER_STOP or (modal.find_child("MemberDetailScrim",true,false) as Control).mouse_filter!=Control.MOUSE_FILTER_STOP:
		failures.append("%s modal/scrim does not block input"%viewport_size)
	var viewport_rect:Rect2=sandbox.get_global_rect();var panel_rect:=panel.get_global_rect()
	if not _rect_contains(viewport_rect,panel_rect):failures.append("%s detail panel outside viewport %s"%[viewport_size,panel_rect])
	var max_width:=420.0 if viewport_size.x>=450.0 else 336.0
	if panel.size.x>max_width+0.1 or panel_rect.position.x<11.9 or panel_rect.position.y<11.9 \
			or panel_rect.end.x>viewport_rect.end.x-11.9 or panel_rect.end.y>viewport_rect.end.y-11.9:
		failures.append("%s detail panel margin/width %s"%[viewport_size,panel_rect])
	if sandbox.member_detail_close.size.x<43.9 or sandbox.member_detail_close.size.y<43.9 \
			or sandbox.member_detail_close.get_theme_font_size("font_size")<18:
		failures.append("%s detail close accessibility"%viewport_size)
	if body.get_theme_font_size("font_size")<16:failures.append("%s detail body font below 16"%viewport_size)
	var line_height:=body.get_theme_font("font").get_height(body.get_theme_font_size("font_size"))
	if body.custom_minimum_size.y+0.5<float(body.get_line_count())*line_height:
		failures.append("%s detail body clips wrapped lines min=%s lines=%d"%[viewport_size,body.custom_minimum_size,body.get_line_count()])
	if not _rect_contains(panel_rect,scroll.get_global_rect()):failures.append("%s detail scroll outside panel"%viewport_size)
	for token in ["HP ","스트레스","준비:","감정:","종족/역할:","상태 효과:","성격:","원소 친화/내성:","현재 노출:","행동 제안:","관계"]:
		if not token in body.text:failures.append("%s detail modal missing %s"%[viewport_size,token])
	var detail:Dictionary=sandbox.session.inspect_party_member(sandbox.selected_member_id)
	var expected_fire:=int(detail.get("current_exposure",{}).get("risk",{}).get("fire",0))
	if expected_fire<=0 or not "현재 노출: 불 %d"%expected_fire in body.text:
		failures.append("%s detail modal lost nested current exposure %d"%[viewport_size,expected_fire])

func _combat_log_history(viewport_size:Vector2)->void:
	var session=Session.new();var state=session.sim.world.party_encounter;var hero:=int(state.protagonist_id)
	var all_ids:Array=state.party_member_ids.duplicate();all_ids.append_array(state.enemy_ids)
	for entity_id in all_ids:
		var entity=session.sim.world.entities[int(entity_id)];entity.max_health=10000;entity.health=10000
	if not session.commit_exploration(Command.wait(hero)).accepted:failures.append("%s log contact fixture"%viewport_size);return
	if not session.preview_deployment("LINE",session.available_companion_ids()).accepted or not session.commit_deployment().accepted:
		failures.append("%s log deployment fixture"%viewport_size);return
	for turn_index in range(8):
		if not session.set_actor_action(hero,"HOLD").accepted or not session.commit_turn().accepted:
			failures.append("%s log history fixture turn %d"%[viewport_size,turn_index]);return
	var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(session)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size;root.add_child(sandbox)
	await process_frame;await process_frame
	await _press(sandbox,"ActorHold");await _press(sandbox,"TurnConfirm")
	await process_frame;await process_frame;await process_frame
	var history:Dictionary=session.combat_log(8,80)
	if int(history.get("group_count",0))!=8:failures.append("%s combat log did not retain exact recent 8 turns: %s"%[viewport_size,history.get("group_count",0)])
	if sandbox.log_label.text!=sandbox._combat_log_text(history):failures.append("%s rendered combat log diverges from facade DTO"%viewport_size)
	if not "주요 기록 · 최근 8개 사건 턴" in sandbox.log_label.text:failures.append("%s important log section title missing"%viewport_size)
	var companion_ids:Array=state.party_member_ids.duplicate();companion_ids.erase(hero)
	var companion_attack:=false;var companion_damage:=false;var numeric_damage:=false
	for group in history.get("groups",[]):
		if not group is Dictionary:continue
		if not "턴 %d"%int(group.get("step_index",0)) in sandbox.log_label.text:failures.append("%s combat log turn boundary missing"%viewport_size)
		for row in group.get("rows",[]):
			if not row is Dictionary:continue
			var message:=str(row.get("message",""))
			if str(row.get("type","")) in ["action.move","action.wait","action.hold"] \
					or message=="세계에 변화가 일어났다.":
				failures.append("%s important log retained noise %s"%[viewport_size,row.get("type","")])
			if not message in sandbox.log_label.text:failures.append("%s combat log omitted row %s"%[viewport_size,message])
			if str(row.get("type",""))=="action.melee_attack" and int(row.get("actor_id",-1)) in companion_ids:
				companion_attack=true
				if not str(row.get("actor_name","")) in message:failures.append("%s companion attack lost actor name"%viewport_size)
			if str(row.get("type","")).begins_with("combat.") and int(row.get("instigator_id",-1)) in companion_ids:
				companion_damage=true
				if not str(row.get("instigator_name","")) in message:failures.append("%s companion damage lost instigator name"%viewport_size)
			if int(row.get("magnitude",0))>0 and str(int(row.magnitude)) in message:numeric_damage=true
	if not companion_attack or not companion_damage:failures.append("%s combat log lacks automatic companion attack/damage attribution"%viewport_size)
	if not numeric_damage:failures.append("%s combat log lacks visible damage number"%viewport_size)
	if _scroll_ancestor(sandbox.log_label)!=sandbox.info_scroll:failures.append("%s combat log is outside InformationScroll"%viewport_size)
	var bar:VScrollBar=sandbox.info_scroll.get_v_scroll_bar();var expected_bottom:=maxi(0,int(bar.max_value-bar.page))
	if absi(sandbox.info_scroll.scroll_vertical-expected_bottom)>1:
		failures.append("%s latest combat commit did not scroll log to bottom %d/%d"%[viewport_size,sandbox.info_scroll.scroll_vertical,expected_bottom])
	var retained_text:String=sandbox.log_label.text;sandbox.info_scroll.scroll_vertical=0;await process_frame;await process_frame
	if sandbox.info_scroll.scroll_vertical!=0 or sandbox.log_label.text!=retained_text:
		failures.append("%s user cannot scroll retained combat history"%viewport_size)
	sandbox.queue_free();await process_frame

func _journey(viewport_size:Vector2,preset:String)->void:
	var sandbox=Sandbox.new(); sandbox.size=viewport_size; sandbox.initialize_for_headless_test(Session.new())
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); sandbox.size=viewport_size; root.add_child(sandbox)
	await process_frame; await process_frame
	var grid_id=sandbox.grid.get_instance_id(); var exploration_mapping=sandbox.grid.mapping_signature()
	var exploration_cell_size:float=sandbox.grid.cell_size_px()
	_validate_layout(sandbox,"%s %s EXPLORATION"%[viewport_size,preset])
	var initial_actors:=0; for cell in sandbox.session.observe_party_world().cells: initial_actors+=cell.actors.size()
	if initial_actors!=3: failures.append("%s %s pre-contact actor visibility"%[viewport_size,preset])
	for button_name in ["ExploreN","ExploreNE","ExploreE","ExploreSE","ExploreS","ExploreSW","ExploreW","ExploreNW","ExploreHold"]:
		if _button(sandbox,button_name)!=null: failures.append("%s %s legacy D-pad remains %s"%[viewport_size,preset,button_name])
	await _explore_wait(sandbox)
	_validate_layout(sandbox,"%s %s CONTACT"%[viewport_size,preset])
	if sandbox.grid.mapping_signature()!=exploration_mapping: failures.append("%s %s contact changed full-view mapping"%[viewport_size,preset])
	var contact_actors:=0; for cell in sandbox.session.observe_party_world().cells: contact_actors+=cell.actors.size()
	if contact_actors!=4: failures.append("%s %s contact enemy reveal"%[viewport_size,preset])
	if not _button(sandbox,"DeployConfirm").disabled: failures.append("%s %s pre-preset confirm enabled"%[viewport_size,preset])
	sandbox._on_deploy_confirm(); await process_frame
	if not "먼저" in str(sandbox.find_child("ActionStatus",true,false).text): failures.append("%s %s rejected confirm invisible"%[viewport_size,preset])
	for preview_preset in ["WEDGE","LINE","COLUMN"]:
		await _press(sandbox,"Preset%s"%preview_preset)
		_validate_layout(sandbox,"%s %s PREVIEW_%s"%[viewport_size,preset,preview_preset])
		if sandbox.grid._ghosts.size()!=2: failures.append("%s %s %s ghost count"%[viewport_size,preset,preview_preset])
		for ghost in sandbox.grid._ghosts:
			var ghost_position:=Vector2i(int(ghost.position[0]),int(ghost.position[1]))
			if not sandbox.grid.is_world_cell_visible(ghost_position):failures.append("%s %s %s ghost outside deployment preview"%[viewport_size,preset,preview_preset])
	await _press(sandbox,"Preset%s"%preset)
	await _press(sandbox,"DeployConfirm")
	if sandbox.session.party_status().safe_phase!="ENGAGED": failures.append("%s %s did not engage"%[viewport_size,preset])
	if sandbox.grid.get_instance_id()!=grid_id:failures.append("%s %s grid replaced on combat"%[viewport_size,preset])
	if sandbox.grid.visible_cell_count!=15:failures.append("%s %s combat is not 15x15"%[viewport_size,preset])
	if sandbox.grid.cell_size_px()>exploration_cell_size+0.1:failures.append("%s %s combat increased tile scale"%[viewport_size,preset])
	if viewport_size.x>=450 and sandbox.grid.mapping_signature()!=exploration_mapping:
		failures.append("%s %s wide combat changed map size"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s COMBAT_HERO_PENDING"%[viewport_size,preset])
	await _validate_fixed_combat_area(sandbox,"%s %s"%[viewport_size,preset])
	_validate_camera_mapping(sandbox,"%s %s"%[viewport_size,preset])
	var status:Dictionary=sandbox.session.party_status();var hero:=int(status.protagonist_id);var companion:=int(status.party_member_ids[1])
	var draft_required:Dictionary=sandbox.session.preview_actor_action(companion,"HOLD");var draft_snapshot=sandbox.session.sim.snapshot()
	await _press(sandbox,"MemberCard%d"%companion);await _press(sandbox,"ActorHold")
	await _validate_fixed_feedback(sandbox,str(draft_required.message),"%s %s DRAFT_REQUIRED"%[viewport_size,preset])
	if sandbox.session.sim.snapshot()!=draft_snapshot:failures.append("%s %s draft-required button changed world"%[viewport_size,preset])
	await _press(sandbox,"MemberCard%d"%hero)
	await _press(sandbox,"ActorHold")
	if str(draft_required.message) in sandbox.action_feedback_label.text or not "실행" in sandbox.action_feedback_label.text:
		failures.append("%s %s accepted action did not replace stale rejection feedback"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s COMBAT_HERO_DIRECT"%[viewport_size,preset])
	await _press(sandbox,"MemberCard%d"%companion)
	var companion_position:=Vector2i.ZERO
	for row in sandbox.session.party_cards():
		if int(row.entity_id)==companion: companion_position=Vector2i(int(row.logical_position[0]),int(row.logical_position[1])); break
	var far_preview:Dictionary={};var far_destination:=Vector2i(-1,-1)
	for offset in [Vector2i(3,0),Vector2i(-3,0),Vector2i(0,3),Vector2i(0,-3),Vector2i(3,3),Vector2i(-3,-3)]:
		var candidate:Vector2i=companion_position+offset
		if not sandbox.grid.is_world_cell_visible(candidate) or sandbox.grid.actor_in_world_cell(candidate)!=-1:continue
		var candidate_preview:Dictionary=sandbox.session.preview_actor_action(companion,"MOVE",[candidate.x,candidate.y])
		if str(candidate_preview.get("reason_code",""))=="move_not_adjacent":far_destination=candidate;far_preview=candidate_preview;break
	if far_destination==Vector2i(-1,-1):failures.append("%s %s no visible nonadjacent companion fixture"%[viewport_size,preset])
	else:
		var far_snapshot=sandbox.session.sim.snapshot();await _touch_cell(sandbox,far_destination)
		await _validate_fixed_feedback(sandbox,str(far_preview.message),"%s %s NONADJACENT"%[viewport_size,preset])
		if sandbox.session.sim.snapshot()!=far_snapshot:failures.append("%s %s nonadjacent ScreenTouch changed world"%[viewport_size,preset])
	for direction in [Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i(1,-1),Vector2i(1,1),Vector2i(-1,-1),Vector2i(-1,1)]:
		var destination:Vector2i=companion_position+direction
		if not sandbox.session.sim.assess_move(companion,destination).accepted \
				or sandbox.grid.actor_in_world_cell(destination)!=-1: continue
		await _press(sandbox,"MemberCard%d"%companion)
		await _touch_cell(sandbox,destination)
		if sandbox.find_child("MovePreviewSummary",true,false)!=null or sandbox.pending_move_mode=="COMBAT":
			failures.append("%s %s one-tap companion MOVE left retap preview"%[viewport_size,preset])
		var found_override:=false
		for row in sandbox.session.party_cards():
			if int(row.entity_id)==companion and row.expected_action is Dictionary and str(row.expected_action.source)=="OVERRIDE": found_override=true
		if found_override: break
	_validate_layout(sandbox,"%s %s COMBAT_COMPANION_OVERRIDE"%[viewport_size,preset])
	var override_visible:=false
	for row in sandbox.session.party_cards():
		if int(row.entity_id)==companion and row.expected_action is Dictionary and str(row.expected_action.source)=="OVERRIDE": override_visible=true
	if not override_visible: failures.append("%s %s companion override not visible"%[viewport_size,preset])
	if sandbox.grid._secondary_intent_overlays.size()!=1: failures.append("%s %s original suggestion secondary overlay missing"%[viewport_size,preset])
	var summary=sandbox.find_child("TurnSummary",true,false) as Label
	var detail=sandbox.find_child("ExpectedAction",true,false) as Label
	if summary==null or not "원래 제안" in summary.text: failures.append("%s %s original suggestion absent from turn summary"%[viewport_size,preset])
	if detail==null or not "개별 지시:" in detail.text or not "원래 제안:" in detail.text: failures.append("%s %s override/original detail absent"%[viewport_size,preset])
	if sandbox.find_child("IntentLegend",true,false)==null: failures.append("%s %s intent legend missing"%[viewport_size,preset])
	await _press(sandbox,"OverrideClear")
	if not sandbox.grid._secondary_intent_overlays.is_empty(): failures.append("%s %s clear left secondary overlay"%[viewport_size,preset])
	summary=sandbox.find_child("TurnSummary",true,false) as Label
	if summary!=null and "원래 제안" in summary.text: failures.append("%s %s clear left dual summary"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s COMBAT_COMPANION_AUTO"%[viewport_size,preset])
	await _press(sandbox,"MemberCard%d"%hero)
	var enemy:=int(sandbox.session.party_status().visible_enemy_ids[0]); await _touch_entity(sandbox,enemy)
	if sandbox.selected_member_id!=hero: failures.append("%s %s enemy tap selected enemy"%[viewport_size,preset])
	if not _button(sandbox,"OverrideClear").disabled: failures.append("%s %s enemy tap exposed companion controls"%[viewport_size,preset])
	var melee_ready_checked:=false
	for combat_turn in range(12):
		if sandbox.session.party_status().safe_phase=="GROUPED_COMPLETE": break
		var hero_position:=Vector2i.ZERO
		for card in sandbox.session.party_cards():
			if int(card.entity_id)==hero:
				hero_position=Vector2i(int(card.logical_position[0]),int(card.logical_position[1])); break
		var targets:Array=sandbox.session.enemy_targets()
		if targets.is_empty(): break
		enemy=int(targets[0].entity_id)
		var enemy_position:=Vector2i(int(targets[0].position[0]),int(targets[0].position[1]))
		var distance:=maxi(absi(hero_position.x-enemy_position.x),absi(hero_position.y-enemy_position.y))
		if distance==1:
			await _touch_entity(sandbox,enemy)
			if not melee_ready_checked:
				_validate_layout(sandbox,"%s %s COMBAT_MELEE_READY"%[viewport_size,preset])
				melee_ready_checked=true
		else:
			var moved_toward_enemy:=false
			var directions:=[Vector2i(signi(enemy_position.x-hero_position.x),signi(enemy_position.y-hero_position.y)),
				Vector2i(signi(enemy_position.x-hero_position.x),0),Vector2i(0,signi(enemy_position.y-hero_position.y))]
			for direction in directions:
				if direction==Vector2i.ZERO: continue
				await _touch_cell(sandbox,hero_position+direction)
				var draft:Dictionary=sandbox.session.current_turn_preview()
				if bool(draft.get("accepted",false)) and str(draft.actor_rows[0].action.type)=="MOVE":
					moved_toward_enemy=true; break
			if not moved_toward_enemy: await _press(sandbox,"ActorHold")
		await _press(sandbox,"TurnConfirm")
	if sandbox.session.party_status().safe_phase!="GROUPED_COMPLETE": failures.append("%s %s automatic regroup phase"%[viewport_size,preset])
	var victory_history:Dictionary=sandbox.session.combat_log(8,80);var death_row_visible:=false
	for victory_group in victory_history.get("groups",[]):
		if not victory_group is Dictionary:continue
		for victory_row in victory_group.get("rows",[]):
			if victory_row is Dictionary and str(victory_row.get("type",""))=="entity.died":
				death_row_visible=str(victory_row.get("message","")) in sandbox.log_label.text
	if not death_row_visible:failures.append("%s %s enemy death absent from expanded combat log"%[viewport_size,preset])
	if _button(sandbox,"RegroupConfirm")!=null: failures.append("%s %s manual regroup button remains"%[viewport_size,preset])
	if not sandbox.grid._intent_overlays.is_empty(): failures.append("%s %s stale combat overlays"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s GROUPED_COMPLETE"%[viewport_size,preset])
	if sandbox.grid.visible_cell_count!=15 or sandbox.grid.view_origin!=Vector2i.ZERO:failures.append("%s %s victory did not restore full camera"%[viewport_size,preset])
	if sandbox.grid.mapping_signature()!=exploration_mapping:failures.append("%s %s victory changed persistent full mapping"%[viewport_size,preset])
	if sandbox.combat_action_area.visible or sandbox.combat_action_area.is_visible_in_tree():failures.append("%s %s combat action area remains after victory"%[viewport_size,preset])
	if sandbox.combat_action_dock.visible or sandbox.combat_action_dock.is_visible_in_tree():failures.append("%s %s combat dock remains after victory"%[viewport_size,preset])
	if sandbox.phase_label.text!="승리":failures.append("%s %s victory situation missing"%[viewport_size,preset])
	var old_anchor:Array=sandbox.session.party_status().anchor
	var regroup_goal:=Vector2i(-1,-1);var regroup_origin:=Vector2i(int(old_anchor[0]),int(old_anchor[1]))
	for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var candidate:Vector2i=regroup_origin+direction
		if sandbox.grid.actor_in_world_cell(candidate)!=-1:continue
		var probe:Dictionary=sandbox.session.preview_exploration_route(candidate)
		sandbox.session.cancel_exploration_route()
		if bool(probe.get("accepted",false)):regroup_goal=candidate;break
	if regroup_goal==Vector2i(-1,-1):failures.append("%s %s no follower-free regroup move"%[viewport_size,preset])
	else:
		sandbox._refresh();await _touch_cell(sandbox,regroup_goal)
	if sandbox.session.party_status().anchor==old_anchor: failures.append("%s %s grouped-complete anchor stale"%[viewport_size,preset])
	if sandbox.grid.get_instance_id()!=grid_id or sandbox.grid.mapping_signature()!=exploration_mapping: failures.append("%s %s grid identity/restored mapping changed"%[viewport_size,preset])
	if sandbox.phase_label.text!="승리":failures.append("%s %s post-regroup move lost victory situation"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s POST_REGROUP_MOVE"%[viewport_size,preset])
	print("PARTY UI %dx%d %s full journey ok grid=%.0f cell=%.1f"%[viewport_size.x,viewport_size.y,preset,sandbox.grid.size.x,sandbox.grid.cell_size_px()])
	sandbox.queue_free(); await process_frame

func _terminal(viewport_size:Vector2)->void:
	var session=Session.new(); var state=session.sim.world.party_encounter; session.sim.world.entities[state.protagonist_id].health=5
	session.sim.world.bootstrap_set_fire(state.group_anchor,100); session.commit_exploration(Command.wait(state.protagonist_id))
	var sandbox=Sandbox.new(); sandbox.size=viewport_size; sandbox.initialize_for_headless_test(session)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); sandbox.size=viewport_size; root.add_child(sandbox)
	await process_frame; await process_frame
	_validate_layout(sandbox,"%s TERMINAL"%viewport_size)
	if sandbox.find_child("TerminalOverlay",true,false)==null: failures.append("%s terminal overlay missing"%viewport_size)
	if sandbox.find_child("TurnConfirm",true,false)!=null: failures.append("%s terminal confirm visible"%viewport_size)
	if not sandbox.find_children("CompanionSpeechStrip","PanelContainer",true,false).is_empty():
		failures.append("%s terminal companion speech visible"%viewport_size)
	if sandbox.phase_label.text!="위험":failures.append("%s terminal danger situation missing"%viewport_size)
	if str(sandbox.grid._presentation_style.get("style_id",""))!="DEFEAT" or str(sandbox.grid._presentation_style.get("border_hex",""))!="#8f5367":
		failures.append("%s terminal presentation style missing"%viewport_size)
	var terminal_panel:=sandbox.phase_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if terminal_panel==null or terminal_panel.border_color!=Color("#8f5367"):failures.append("%s terminal panel border missing"%viewport_size)
	if sandbox.log_label.text.is_empty(): failures.append("%s terminal log empty"%viewport_size)
	sandbox.queue_free(); await process_frame

func _wide_camera_fallback(viewport_size:Vector2)->void:
	var session=Session.new();var state=session.sim.world.party_encounter
	session.commit_exploration(Command.wait(state.protagonist_id))
	session.preview_deployment("WEDGE",session.available_companion_ids());session.commit_deployment()
	var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(session)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size;root.add_child(sandbox)
	await process_frame;await process_frame
	var grid_id=sandbox.grid.get_instance_id();var status:Dictionary=session.party_status()
	var actor_ids:Array=[];actor_ids.append_array(status.party_member_ids);actor_ids.append_array(status.visible_enemy_ids)
	var corners:=[Vector2i(0,0),Vector2i(14,14),Vector2i(0,14),Vector2i(14,0)]
	for index in range(mini(actor_ids.size(),corners.size())):
		session.sim.world.entities[int(actor_ids[index])].position=corners[index]
	sandbox._refresh();await process_frame;await process_frame
	var label:="%s WIDE_COMBAT_FALLBACK"%viewport_size
	_validate_layout(sandbox,label,15)
	if sandbox.grid.get_instance_id()!=grid_id:failures.append("%s replaced PartyGridView"%label)
	if sandbox.grid.view_origin!=Vector2i.ZERO:failures.append("%s full fallback origin %s"%[label,sandbox.grid.view_origin])
	for cell in session.observe_party_world().cells:
		for actor in cell.actors:
			var actor_position:=Vector2i(int(cell.position[0]),int(cell.position[1]))
			if not sandbox.grid.is_world_cell_visible(actor_position):failures.append("%s hid required actor %s at %s"%[label,actor.entity_id,actor_position])
	var edge:=Vector2i(14,7);var routed:Array=[];var capture:Callable=func(position):routed.append(position)
	sandbox.grid.world_cell_pressed.connect(capture);await _touch_cell(sandbox,edge)
	if sandbox.grid.world_cell_pressed.is_connected(capture):sandbox.grid.world_cell_pressed.disconnect(capture)
	if routed!=[edge]:failures.append("%s real ScreenTouch routed %s instead of %s"%[label,routed,edge])
	if sandbox.grid.pixel_to_world_cell(sandbox.grid.world_to_pixel_center(Vector2i(14,14)))!=Vector2i(14,14):
		failures.append("%s full fallback edge roundtrip"%label)
	await _validate_fixed_combat_area(sandbox,label)
	sandbox.queue_free();await process_frame

func _validate_authoritative_rejection_layouts_360()->void:
	var viewport_size:=Vector2(360,640);root.size=Vector2i(360,640);await process_frame
	var cases:Array=[]
	var draft_session=_engaged_session([1,2],"WEDGE");var draft_status:Dictionary=draft_session.party_status();var draft_companion:=int(draft_status.party_member_ids[1])
	cases.append({"code":"turn_draft_required","result":draft_session.preview_actor_action(draft_companion,"HOLD"),"prefix":"%s 대기 불가"%_party_name(draft_session,draft_companion)})
	var busy_session=_engaged_session([1],"LINE");var busy_status:Dictionary=busy_session.party_status();var busy_hero:=int(busy_status.protagonist_id);var busy_companion:=int(busy_status.party_member_ids[1])
	busy_session.sim.world.party_encounter.member(busy_companion).busy_until=busy_session.sim.world.world_time+37;busy_session.set_actor_action(busy_hero,"HOLD")
	cases.append({"code":"party_actor_busy","result":busy_session.preview_actor_action(busy_companion,"HOLD"),"prefix":"%s 대기 불가"%_party_name(busy_session,busy_companion)})
	var wall_source=Session.new();var wall_state=wall_source.sim.world.party_encounter;var wall_destination:=Vector2i(5,6)
	if not wall_source.sim.world.bootstrap_set_terrain(wall_destination,"wall"):failures.append("360 rejection layout wall fixture")
	var wall_session=_engaged_session([1,2],"WEDGE",wall_source);var wall_companion:=int(wall_state.party_member_ids[1]);wall_session.set_actor_action(int(wall_state.protagonist_id),"HOLD")
	cases.append({"code":"move_terrain_blocked","result":wall_session.preview_actor_action(wall_companion,"MOVE",[wall_destination.x,wall_destination.y]),"prefix":"%s 이동 불가"%_party_name(wall_session,wall_companion)})
	var occupied_session=_engaged_session([1,2],"WEDGE");var occupied_status:Dictionary=occupied_session.party_status();var occupied_hero:=int(occupied_status.protagonist_id);var occupied_companion:=int(occupied_status.party_member_ids[1])
	var occupied_destination:=Vector2i(5,6);var blocker=occupied_session.sim.world.add_entity("obstacle","상자",occupied_destination,100,[],"human","neutral")
	if blocker==null:failures.append("360 rejection layout occupied fixture")
	if not occupied_session.set_actor_action(occupied_hero,"HOLD").accepted:failures.append("360 rejection layout occupied hero draft")
	cases.append({"code":"move_destination_occupied","result":occupied_session.preview_actor_action(occupied_companion,"MOVE",[occupied_destination.x,occupied_destination.y]),"prefix":"%s 이동 불가"%_party_name(occupied_session,occupied_companion)})
	var distant_session=_engaged_session([1,2],"WEDGE");var distant_status:Dictionary=distant_session.party_status();var distant_hero:=int(distant_status.protagonist_id);var distant_companion:=int(distant_status.party_member_ids[1]);distant_session.set_actor_action(distant_hero,"HOLD")
	var distant_origin:=_party_position(distant_session,distant_companion);var distant_destination:=distant_origin+Vector2i(3,0)
	cases.append({"code":"move_not_adjacent","result":distant_session.preview_actor_action(distant_companion,"MOVE",[distant_destination.x,distant_destination.y]),"prefix":"%s 이동 불가"%_party_name(distant_session,distant_companion)})
	var conflict_session=_engaged_session([1],"LINE");var conflict_status:Dictionary=conflict_session.party_status();var conflict_hero:=int(conflict_status.protagonist_id);var conflict_companion:=int(conflict_status.party_member_ids[1])
	if not _relocate_with_move_events(conflict_session.sim,conflict_companion,Vector2i(9,7)):failures.append("360 rejection layout conflict relocation")
	var conflict_destination:=Vector2i(8,7);var conflict_hero_result:Dictionary=conflict_session.set_actor_action(conflict_hero,"MOVE",[conflict_destination.x,conflict_destination.y])
	if not bool(conflict_hero_result.get("accepted",false)):failures.append("360 rejection layout conflict hero draft")
	cases.append({"code":"destination_conflict","result":conflict_session.preview_actor_action(conflict_companion,"MOVE",[conflict_destination.x,conflict_destination.y]),"prefix":"%s 이동 불가"%_party_name(conflict_session,conflict_companion)})
	var dormant_session=_engaged_session([],"LINE");var dormant_status:Dictionary=dormant_session.party_status();var dormant_hero:=int(dormant_status.protagonist_id);var dormant_companion:=int(dormant_status.party_member_ids[1]);dormant_session.set_actor_action(dormant_hero,"HOLD")
	cases.append({"code":"override_actor_not_deployed","result":dormant_session.preview_actor_action(dormant_companion,"HOLD"),"prefix":"%s 대기 불가"%_party_name(dormant_session,dormant_companion)})
	var live_session=_engaged_session([1,2],"WEDGE");var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(live_session)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size;root.add_child(sandbox);await process_frame;await process_frame
	for row in cases:
		var result:Dictionary=row.result
		if str(result.get("reason_code",""))!=str(row.code):failures.append("360 rejection layout wrong fixture %s: %s"%[row.code,result.get("reason_code","")]);continue
		sandbox._set_action_rejection(result,str(row.prefix));sandbox._refresh();await process_frame;await process_frame
		if not str(result.message) in sandbox.action_feedback_label.text:failures.append("360 %s facade message missing from fixed feedback"%row.code)
		_validate_feedback_lines(sandbox.action_feedback_label,"360 AUTHORITY_%s"%row.code)
	sandbox.queue_free();await process_frame

func _engaged_session(roster_slots:Array,preset:String="LINE",custom_session=null):
	var result_session=custom_session if custom_session!=null else Session.new();var state=result_session.sim.world.party_encounter;var selected:Array=[]
	for slot in roster_slots:selected.append(state.party_member_ids[int(slot)])
	if not result_session.commit_exploration(Command.wait(state.protagonist_id)).accepted:failures.append("rejection layout contact fixture")
	if not result_session.preview_deployment(preset,selected).accepted:failures.append("rejection layout deployment preview fixture")
	if not result_session.commit_deployment().accepted:failures.append("rejection layout deployment commit fixture")
	return result_session

func _party_name(custom_session,entity_id:int)->String:
	for card in custom_session.party_cards():
		if int(card.entity_id)==entity_id:return str(card.display_name)
	return "파티원"

func _party_position(custom_session,entity_id:int)->Vector2i:
	for card in custom_session.party_cards():
		if int(card.entity_id)==entity_id:return Vector2i(int(card.logical_position[0]),int(card.logical_position[1]))
	return Vector2i(-1,-1)

func _relocate_with_move_events(sim,entity_id:int,target:Vector2i)->bool:
	for attempt in range(64):
		var current:Vector2i=sim.world.entities[entity_id].position
		if current==target:return true
		var delta:=target-current;var directions:Array[Vector2i]=[Vector2i(signi(delta.x),signi(delta.y)),Vector2i(signi(delta.x),0),Vector2i(0,signi(delta.y))]
		var moved:=false
		for direction in directions:
			if direction==Vector2i.ZERO:continue
			var destination:=current+direction
			if maxi(absi(destination.x-target.x),absi(destination.y-target.y))>=maxi(absi(current.x-target.x),absi(current.y-target.y)):continue
			var assessment=sim.movement.assess_move(entity_id,destination)
			if not assessment.accepted:continue
			var definition:Dictionary=TerrainRegistry.definition(str(assessment.terrain_id))
			if sim.movement.commit_preflighted_move(entity_id,destination,str(assessment.terrain_id),int(definition.move_time_cost))==null:return false
			moved=true;break
		if not moved:return false
	return false

func _press(sandbox,node_name:String)->void:
	var button=_button(sandbox,node_name)
	if button==null:
		failures.append("missing button %s in %s"%[node_name,sandbox.session.party_status().safe_phase]); return
	var scroll=_scroll_ancestor(button)
	if scroll!=null:
		scroll.ensure_control_visible(button); await process_frame; await process_frame
	var sandbox_rect:Rect2=sandbox.get_global_rect();var button_rect:Rect2=button.get_global_rect()
	if not button.is_visible_in_tree() or not _rect_contains(sandbox_rect,button_rect):
		failures.append("unreachable button %s phase=%s rect=%s viewport=%s"%[node_name,sandbox.session.party_status().safe_phase,button_rect,sandbox_rect]);return
	if scroll!=null and not _rect_contains(scroll.get_global_rect(),button_rect):
		failures.append("button clipped by scroll %s rect=%s scroll=%s"%[node_name,button_rect,scroll.get_global_rect()]);return
	if button.disabled:
		failures.append("attempted disabled button %s phase=%s"%[node_name,sandbox.session.party_status().safe_phase]);return
	var center:=button_rect.get_center()
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
	press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.position=center;press.global_position=center
	root.push_input(press,true);await process_frame
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
	release.button_mask=0;release.position=center;release.global_position=center
	root.push_input(release,true);await process_frame;await process_frame

func _button(root_node:Node,node_name:String)->Button:
	return root_node.find_child(node_name,true,false) as Button

func _touch_cell(sandbox,position:Vector2i)->void:
	var local_position:Vector2=sandbox.grid.world_to_pixel_center(position)
	if local_position==Vector2(-1,-1):failures.append("ScreenTouch target outside camera %s"%position);return
	var global_position:Vector2=sandbox.grid.get_global_rect().position+local_position
	if not sandbox.get_global_rect().has_point(global_position):failures.append("ScreenTouch target outside viewport %s at %s"%[position,global_position]);return
	var event:=InputEventScreenTouch.new();event.index=0;event.pressed=true;event.position=global_position
	root.push_input(event,true);await process_frame
	var release:=InputEventScreenTouch.new();release.index=0;release.pressed=false;release.position=global_position
	root.push_input(release,true);await process_frame;await process_frame

func _touch_cell_now(sandbox,position:Vector2i,touch_index:int=0)->bool:
	var local_position:Vector2=sandbox.grid.world_to_pixel_center(position)
	if local_position==Vector2(-1,-1):failures.append("ScreenTouch target outside camera %s"%position);return false
	var global_position:Vector2=sandbox.grid.get_global_rect().position+local_position
	if not sandbox.get_global_rect().has_point(global_position):failures.append("ScreenTouch target outside viewport %s at %s"%[position,global_position]);return false
	var press:=InputEventScreenTouch.new();press.index=touch_index;press.pressed=true;press.position=global_position
	root.push_input(press,true)
	var release:=InputEventScreenTouch.new();release.index=touch_index;release.pressed=false;release.position=global_position
	root.push_input(release,true);return true

func _cell_global_position(sandbox,position:Vector2i)->Vector2:
	var local_position:Vector2=sandbox.grid.world_to_pixel_center(position)
	if local_position==Vector2(-1,-1):
		failures.append("gesture target outside camera %s"%position);return Vector2(-1,-1)
	var global_position:Vector2=sandbox.grid.get_global_rect().position+local_position
	if not sandbox.get_global_rect().has_point(global_position):
		failures.append("gesture target outside viewport %s at %s"%[position,global_position]);return Vector2(-1,-1)
	return global_position

func _push_touch_now(position:Vector2,pressed:bool,touch_index:int)->void:
	if position==Vector2(-1,-1):return
	var event:=InputEventScreenTouch.new();event.index=touch_index;event.pressed=pressed;event.position=position
	root.push_input(event,true)

func _short_touch_cell(sandbox,position:Vector2i,seconds:float,touch_index:int)->bool:
	var global_position:=_cell_global_position(sandbox,position)
	if global_position==Vector2(-1,-1):return false
	_push_touch_now(global_position,true,touch_index)
	await create_timer(seconds).timeout
	_push_touch_now(global_position,false,touch_index)
	return true

func _touch_hold_cell(sandbox,position:Vector2i,seconds:float,touch_index:int=4)->void:
	var global_position:=_cell_global_position(sandbox,position)
	if global_position==Vector2(-1,-1):return
	_push_touch_now(global_position,true,touch_index)
	await create_timer(seconds).timeout;await process_frame
	_push_touch_now(global_position,false,touch_index)
	await process_frame;await process_frame

func _mouse_hold_cell(sandbox,position:Vector2i,seconds:float)->void:
	var global_position:=_cell_global_position(sandbox,position)
	if global_position==Vector2(-1,-1):return
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
	press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.position=global_position;press.global_position=global_position
	root.push_input(press,true)
	await create_timer(seconds).timeout;await process_frame
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
	release.button_mask=0;release.position=global_position;release.global_position=global_position
	root.push_input(release,true);await process_frame;await process_frame

func _drag_hold_cell(sandbox,position:Vector2i,offset:Vector2,seconds:float,touch_index:int=3)->void:
	var global_position:=_cell_global_position(sandbox,position)
	if global_position==Vector2(-1,-1):return
	_push_touch_now(global_position,true,touch_index)
	var drag:=InputEventScreenDrag.new();drag.index=touch_index;drag.position=global_position+offset
	drag.relative=offset;root.push_input(drag,true)
	await create_timer(seconds).timeout;await process_frame
	_push_touch_now(global_position+offset,false,touch_index)
	await process_frame;await process_frame

func _touch_control_now(control:Control,native_double:bool=false,touch_index:int=1)->bool:
	if control==null or not control.is_visible_in_tree():failures.append("unreachable touch control");return false
	var rect:=control.get_global_rect();var center:=rect.get_center()
	if not root.get_visible_rect().has_point(center):failures.append("touch control outside viewport %s"%rect);return false
	var press:=InputEventScreenTouch.new();press.index=touch_index;press.pressed=true;press.position=center;press.double_tap=native_double
	root.push_input(press,true)
	var release:=InputEventScreenTouch.new();release.index=touch_index;release.pressed=false;release.position=center;release.double_tap=native_double
	root.push_input(release,true);return true

func _touch_screen_now(position:Vector2,touch_index:int=2)->void:
	var press:=InputEventScreenTouch.new();press.index=touch_index;press.pressed=true;press.position=position
	root.push_input(press,true)
	var release:=InputEventScreenTouch.new();release.index=touch_index;release.pressed=false;release.position=position
	root.push_input(release,true)

func _press_escape_now()->void:
	var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.physical_keycode=KEY_ESCAPE;event.pressed=true
	root.push_input(event,true)

func _validate_tile_popover(sandbox,viewport_size:Vector2,label:String,expects_retap:bool)->void:
	var popover:PanelContainer=sandbox.tile_popover;var text_label:Label=sandbox.tile_popover_label
	if popover==null or not popover.visible or not popover.is_visible_in_tree():failures.append("%s %s tile popover hidden"%[viewport_size,label]);return
	var viewport_rect:Rect2=sandbox.get_global_rect();var popover_rect:=popover.get_global_rect()
	if not _rect_contains(viewport_rect,popover_rect):failures.append("%s %s tile popover outside viewport %s"%[viewport_size,label,popover_rect])
	if popover_rect.position.x<viewport_rect.position.x+11.9 or popover_rect.position.y<viewport_rect.position.y+11.9 \
			or popover_rect.end.x>viewport_rect.end.x-11.9 or popover_rect.end.y>viewport_rect.end.y-11.9:
		failures.append("%s %s tile popover violates 12px clamp %s"%[viewport_size,label,popover_rect])
	if popover.size.x>minf(280.0,viewport_size.x-24.0)+0.1:failures.append("%s %s tile popover too wide %s"%[viewport_size,label,popover.size])
	if popover.mouse_filter!=Control.MOUSE_FILTER_IGNORE or text_label.mouse_filter!=Control.MOUSE_FILTER_IGNORE:
		failures.append("%s %s tile popover intercepts second touch"%[viewport_size,label])
	if text_label.get_theme_font_size("font_size")<16:failures.append("%s %s tile popover font below 16"%[viewport_size,label])
	if text_label.get_visible_line_count()<text_label.get_line_count():
		failures.append("%s %s tile popover clips lines visible=%d total=%d size=%s"%[viewport_size,label,text_label.get_visible_line_count(),text_label.get_line_count(),popover.size])
	for token in ["이동","불","물","전기","독","위험"]:
		if not token in text_label.text:failures.append("%s %s tile popover missing %s"%[viewport_size,label,token])
	if expects_retap and not "다시" in text_label.text:failures.append("%s %s exploration retap guidance missing"%[viewport_size,label])

func _touch_entity(sandbox,entity_id:int)->void:
	var position:=Vector2i(-1,-1)
	for cell in sandbox.session.observe_party_world().cells:
		for actor in cell.actors:
			if int(actor.entity_id)==entity_id: position=Vector2i(int(cell.position[0]),int(cell.position[1])); break
		if position!=Vector2i(-1,-1): break
	await _touch_cell(sandbox,position)

func _explore_wait(sandbox)->void:
	var hero:=int(sandbox.session.party_status().protagonist_id)
	await _touch_entity(sandbox,hero); await _touch_entity(sandbox,hero)

func _validate_layout(sandbox,label:String,expected_cells_override:int=-1)->void:
	var viewport_size:Vector2=sandbox.size;var combat_view:=str(sandbox.session.party_status().view_mode)=="COMBAT"
	var expected:=405.0 if viewport_size.x>=450 else (300.0 if combat_view else 348.0)
	if sandbox.grid.size.x+0.1<expected or sandbox.grid.size.y+0.1<expected: failures.append("%s grid below budget"%label)
	var expected_cells:=expected_cells_override if expected_cells_override>0 else 15
	if sandbox.grid.visible_cell_count!=expected_cells:failures.append("%s wrong camera cell count %d"%[label,sandbox.grid.visible_cell_count])
	var minimum_cell:=expected/float(expected_cells)-0.1
	if sandbox.grid.cell_size_px()<minimum_cell: failures.append("%s cell below phase budget"%label)
	if sandbox.cards.get_child_count()!=3: failures.append("%s card count"%label)
	_validate_card_content(sandbox,label)
	var root_box=sandbox.get_node("PartyLayout"); var prior_end:=-100000.0
	for child in root_box.get_children():
		if not child is Control or not child.is_visible_in_tree(): continue
		var rect:=Rect2(child.position,child.size)
		if rect.position.x<-0.1 or rect.end.x>viewport_size.x+0.1: failures.append("%s horizontal overflow %s"%[label,child.name])
		if rect.position.y<-0.1 or rect.end.y>viewport_size.y+0.1: failures.append("%s vertical overflow %s"%[label,child.name])
		if rect.position.y+0.1<prior_end: failures.append("%s vertical overlap %s"%[label,child.name])
		prior_end=maxf(prior_end,rect.end.y)
	var controls:Array[Node]=[]; _collect_controls(root_box,controls)
	for node in controls:
		var control:=node as Control
		if not control.is_visible_in_tree(): continue
		var global_rect:=control.get_global_rect()
		if not _inside_scroll(control) and (global_rect.position.x<-0.1 or global_rect.end.x>viewport_size.x+0.1 \
				or global_rect.position.y<-0.1 or global_rect.end.y>viewport_size.y+0.1):
			failures.append("%s child bounds %s %s"%[label,control.name,global_rect])
		if control is Button and (control.size.x<43.9 or control.size.y<43.9): failures.append("%s touch target %s %s"%[label,control.name,control.size])
		if control is Label:
			var minimum_font:=12 if control.name=="CompanionSpeechText" else 16
			if control.get_theme_font_size("font_size")<minimum_font:
				failures.append("%s font below %d %s"%[label,minimum_font,control.name])
		if control is Button and control.get_theme_font_size("font_size")<18: failures.append("%s button font below 18 %s"%[label,control.name])
	var deck_prior:=-100000.0
	for child in sandbox.deck.get_children():
		if child is Control and child.is_visible_in_tree():
			if child.position.y+0.1<deck_prior: failures.append("%s deck overlap %s"%[label,child.name])
			deck_prior=maxf(deck_prior,child.position.y+child.size.y)
	if sandbox.info_scroll.size.y<29.9:failures.append("%s InformationScroll below 30px: %s"%[label,sandbox.info_scroll.size])
	var engaged:=str(sandbox.session.party_status().safe_phase)=="ENGAGED" and not bool(sandbox.session.party_status().terminal)
	if engaged:
		if not sandbox.combat_action_area.visible or not sandbox.combat_action_area.is_visible_in_tree():failures.append("%s ENGAGED action area hidden"%label)
		if sandbox.combat_action_area.custom_minimum_size.y<83.9:failures.append("%s ENGAGED action area budget below 84"%label)
	else:
		if sandbox.combat_action_area.visible or sandbox.combat_action_area.is_visible_in_tree():failures.append("%s noncombat action area visible"%label)
		if sandbox.combat_action_area.custom_minimum_size.y>0.1:failures.append("%s hidden action area retains height %s"%[label,sandbox.combat_action_area.custom_minimum_size])
		if sandbox.combat_action_dock.visible or sandbox.combat_action_dock.is_visible_in_tree():failures.append("%s noncombat dock visible"%label)

func _validate_fixed_combat_area(sandbox,label:String)->void:
	var area:Control=sandbox.combat_action_area;var feedback:Label=sandbox.action_feedback_label
	var dock:Control=sandbox.combat_action_dock;var root_box:Control=sandbox.root_layout
	if not area.visible or not area.is_visible_in_tree():failures.append("%s combat action area not visible"%label);return
	if not dock.visible or not dock.is_visible_in_tree():failures.append("%s combat dock not visible"%label);return
	if area.get_parent()!=root_box:failures.append("%s action area is not direct PartyLayout sibling"%label)
	if root_box.get_child(root_box.get_child_count()-1)!=area:failures.append("%s action area is not final PartyLayout sibling"%label)
	if dock.get_parent()!=area or feedback.get_parent()!=area:failures.append("%s feedback/dock hierarchy"%label)
	if _scroll_ancestor(area)!=null or _scroll_ancestor(dock)!=null or _scroll_ancestor(feedback)!=null:
		failures.append("%s fixed action area remains inside InformationScroll"%label)
	var viewport_rect:Rect2=sandbox.get_global_rect();var area_rect:Rect2=area.get_global_rect()
	var dock_rect:Rect2=dock.get_global_rect();var feedback_rect:Rect2=feedback.get_global_rect()
	if not _rect_contains(viewport_rect,area_rect):failures.append("%s action area outside viewport %s"%[label,area_rect])
	if not _rect_contains(viewport_rect,dock_rect):failures.append("%s dock outside viewport %s"%[label,dock_rect])
	if not _rect_contains(viewport_rect,feedback_rect):failures.append("%s feedback outside viewport %s"%[label,feedback_rect])
	if absf(area_rect.end.y-root_box.get_global_rect().end.y)>0.6 or absf(dock_rect.end.y-area_rect.end.y)>0.6:
		failures.append("%s action area/dock is not fixed at bottom area=%s dock=%s"%[label,area_rect,dock_rect])
	if area.size.y<83.9 or feedback.size.y<37.9 or dock.size.y<43.9:failures.append("%s fixed row heights area=%s feedback=%s dock=%s"%[label,area.size,feedback.size,dock.size])
	if feedback.get_theme_font_size("font_size")<16:failures.append("%s feedback font below 16"%label)
	_validate_feedback_lines(feedback,label)
	for button_name in ["ActorHold","OverrideClear","TurnConfirm"]:
		var button:=_button(sandbox,button_name)
		if button==null:
			failures.append("%s missing fixed button %s"%[label,button_name]);continue
		if button.get_parent()!=dock:failures.append("%s %s is duplicated/outside dock"%[label,button_name])
		if not _rect_contains(viewport_rect,button.get_global_rect()):failures.append("%s %s outside viewport"%[label,button_name])
		if button.size.x<43.9 or button.size.y<43.9:failures.append("%s %s below 44 touch target"%[label,button_name])
		if button.get_theme_font_size("font_size")<18:failures.append("%s %s font below 18"%[label,button_name])
		var font:Font=button.get_theme_font("font")
		var rendered:=font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size"))
		if rendered.x>button.size.x-10.0:failures.append("%s dock text clips %s rendered=%s box=%s"%[label,button_name,rendered,button.size])
		if sandbox.deck.find_child(button_name,true,false)!=null:failures.append("%s duplicate %s in ContextDeck"%[label,button_name])
	if sandbox.phase_label.text!="전투":failures.append("%s persistent combat situation missing"%label)
	var phase_font:Font=sandbox.phase_label.get_theme_font("font")
	for line in sandbox.phase_label.text.split("\n"):
		var rendered:=phase_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,sandbox.phase_label.get_theme_font_size("font_size"))
		if rendered.x>sandbox.phase_label.size.x+0.5:failures.append("%s phase banner text clips rendered=%s box=%s"%[label,rendered,sandbox.phase_label.size])
	await _validate_fixed_feedback(sandbox,feedback.text,label+" FIXED_DEFAULT")

func _validate_fixed_feedback(sandbox,expected_message:String,label:String)->void:
	var area:Control=sandbox.combat_action_area;var feedback:Label=sandbox.action_feedback_label;var dock:Control=sandbox.combat_action_dock
	if not expected_message in feedback.text:failures.append("%s fixed feedback misses facade message: %s"%[label,feedback.text])
	if _scroll_ancestor(feedback)!=null:failures.append("%s fixed feedback has ScrollContainer ancestor"%label)
	if not feedback.is_visible_in_tree() or not _rect_contains(sandbox.get_global_rect(),feedback.get_global_rect()):
		failures.append("%s fixed feedback unreachable %s"%[label,feedback.get_global_rect()]);return
	_validate_feedback_lines(feedback,label)
	sandbox.info_scroll.scroll_vertical=0;await process_frame;await process_frame
	if sandbox.info_scroll.size.y<29.9:failures.append("%s combat InformationScroll below 30px"%label)
	var action_status:=sandbox.find_child("ActionStatus",true,false) as Label
	if action_status==null:failures.append("%s combat information body row missing"%label)
	else:
		var visible_body:=action_status.get_global_rect().intersection(sandbox.info_scroll.get_global_rect())
		var line_height:=action_status.get_theme_font("font").get_height(action_status.get_theme_font_size("font_size"))
		if action_status.get_theme_font_size("font_size")<18 or visible_body.size.y+0.5<line_height:
			failures.append("%s no unclipped 18px information line visible=%s line_height=%.1f"%[label,visible_body,line_height])
	var area_before:=area.get_global_rect();var feedback_before:=feedback.get_global_rect();var dock_before:=dock.get_global_rect();var text_before:=feedback.text
	var scrolled_control:Control=null
	for child in sandbox.deck.get_children():
		if child is Control:scrolled_control=child;break
	var scroll_child_before:=Rect2() if scrolled_control==null else scrolled_control.get_global_rect()
	sandbox.info_scroll.scroll_vertical=100000;await process_frame;await process_frame
	if sandbox.info_scroll.scroll_vertical<=0:failures.append("%s InformationScroll fixture did not actually move"%label)
	if scrolled_control!=null and scrolled_control.get_global_rect()==scroll_child_before:failures.append("%s scroll content did not move"%label)
	if area.get_global_rect()!=area_before or feedback.get_global_rect()!=feedback_before or dock.get_global_rect()!=dock_before:
		failures.append("%s information scroll moved fixed action area"%label)
	if feedback.text!=text_before:failures.append("%s information scroll changed fixed feedback"%label)

func _validate_feedback_lines(feedback:Label,label:String)->void:
	var line_count:=feedback.get_line_count();var visible_lines:=feedback.get_visible_line_count()
	if line_count<1 or visible_lines<line_count:failures.append("%s feedback lines clipped visible=%d total=%d size=%s text=%s"%[label,visible_lines,line_count,feedback.size,feedback.text])

func _validate_camera_mapping(sandbox,label:String)->void:
	var grid=sandbox.grid;var bounds:Rect2i=grid.view_bounds()
	for world_position in [bounds.position,bounds.position+bounds.size-Vector2i.ONE]:
		var pixel:Vector2=grid.world_to_pixel_center(world_position)
		if grid.pixel_to_world_cell(pixel)!=world_position:failures.append("%s crop roundtrip failed %s"%[label,world_position])
	if grid.visible_cell_count!=15 or grid.view_origin!=Vector2i.ZERO:
		failures.append("%s combat camera is not fixed full-world"%label)
	for edge in [Vector2i.ZERO,Vector2i(14,14)]:
		if not grid.is_world_cell_visible(edge) \
				or grid.pixel_to_world_cell(grid.world_to_pixel_center(edge))!=edge:
			failures.append("%s full-view edge mapping failed %s"%[label,edge])

func _validate_card_content(sandbox,label:String)->void:
	for child in sandbox.cards.get_children():
		if not child is Button: continue
		var card:=child as Button; var content:=card.find_child("CardContent",true,false) as Control
		if content==null:
			failures.append("%s missing measured card content %s"%[label,card.name]); continue
		var content_min:=content.get_combined_minimum_size()
		if content_min.x>card.size.x+0.1 or content_min.y>card.size.y+0.1:
			failures.append("%s card content minimum exceeds card %s min=%s card=%s"%[label,card.name,content_min,card.size])
		var card_rect:=card.get_global_rect(); var content_rect:=content.get_global_rect()
		if content_rect.position.x<card_rect.position.x-0.1 or content_rect.end.x>card_rect.end.x+0.1 \
				or content_rect.position.y<card_rect.position.y-0.1 or content_rect.end.y>card_rect.end.y+0.1:
			failures.append("%s card content bounds clip %s content=%s card=%s"%[label,card.name,content_rect,card_rect])
		var portrait:=card.find_child("Portrait",true,false)
		if not portrait is AsciiPortrait or portrait.actor_dto().is_empty():
			failures.append("%s card portrait missing %s"%[label,card.name])
		for node_name in ["MemberName","MemberState","StressState","Readiness","EmotionState"]:
			var text_label:=card.find_child(node_name,true,false) as Label
			if text_label==null:
				failures.append("%s missing card row %s/%s"%[label,card.name,node_name]); continue
			var font:Font=text_label.get_theme_font("font")
			var rendered:=font.get_string_size(text_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,
				text_label.get_theme_font_size("font_size"))
			if rendered.x>text_label.size.x+0.5 or rendered.y>text_label.size.y+0.5:
				failures.append("%s rendered card row clips %s/%s rendered=%s box=%s text=%s"%[
					label,card.name,node_name,rendered,text_label.size,text_label.text])

func _collect_controls(node:Node,rows:Array[Node])->void:
	for child in node.get_children():
		if child is Control: rows.append(child)
		_collect_controls(child,rows)

func _inside_scroll(control:Control)->bool:
	var node:Node=control.get_parent()
	while node!=null:
		if node is ScrollContainer:return true
		node=node.get_parent()
	return false

func _scroll_ancestor(control:Control):
	var node:Node=control.get_parent()
	while node!=null:
		if node is ScrollContainer:return node as ScrollContainer
		node=node.get_parent()
	return null

func _rect_contains(outer:Rect2,inner:Rect2)->bool:
	return inner.position.x>=outer.position.x-0.1 and inner.position.y>=outer.position.y-0.1 \
		and inner.end.x<=outer.end.x+0.1 and inner.end.y<=outer.end.y+0.1
