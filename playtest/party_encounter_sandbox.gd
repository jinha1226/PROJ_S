class_name PartyEncounterSandbox
extends Control

const SessionScript=preload("res://playtest/party_playtest_session.gd")
const GridScript=preload("res://playtest/party_grid_view.gd")
const CommandScript=preload("res://sim/sim_command.gd")
const ActionScript=preload("res://sim/party_action_command.gd")
const PortraitScript=preload("res://playtest/ascii_actor_portrait.gd")
const KoreanFont:FontFile=preload("res://assets/fonts/NanumSquareR.ttf")
const FONT_AUX:=16
const FONT_BODY:=18
const FONT_KEY:=22
const TOUCH_TARGET:=44
const AUTO_FORMATION_ORDER:=["WEDGE","LINE","COLUMN"]

var session
var grid
var root_layout:VBoxContainer
var phase_panel:PanelContainer
var phase_label:Label
var run_objective_bar:PanelContainer
var run_objective_label:Label
var reward_badge:Label
var cards:HBoxContainer
var deck:VBoxContainer
var log_label:Label
var info_scroll:ScrollContainer
var combat_action_area:VBoxContainer
var action_feedback_label:Label
var combat_action_dock:HBoxContainer
var selected_member_id:=-1
var selected_target_id:=-1
var notice_text:=""
var pending_move_actor_id:=-1
var pending_move_origin:=Vector2i(-1,-1)
var pending_move_destination:=Vector2i(-1,-1)
var pending_move_valid:=false
var pending_move_mode:=""
var pending_move_cost:=0
var pending_exploration_wait:=false
var action_feedback_text:=""
var _action_feedback_phase:=""
var route_preview:Dictionary={}
var route_generation:=0
var route_continue_pending:=false
var route_paused_by_modal:=false
var route_paused_by_pointer:=false
var selected_tile:=Vector2i(-1,-1)
var selected_tile_view_mode:=""
var selected_tile_inspection:Dictionary={}
var tile_popover:PanelContainer
var tile_popover_label:Label
var member_detail_modal:Control
var member_detail_panel:PanelContainer
var member_detail_title:Label
var member_detail_scroll:ScrollContainer
var member_detail_body:Label
var member_detail_close:Button
var _pending_card_pointer:Dictionary={}
var _last_card_tap_id:=-1
var _last_card_tap_msec:=-1000
var _last_card_tap_position:=Vector2(-10000,-10000)
var _direct_card_touch_id:=-1
var _direct_card_touch_msec:=-1000
var _scroll_log_after_refresh:=false
var auto_orchestration_enabled:=false
var auto_generation:=0
var auto_deployment_pending:=false
var auto_deployment_fallback:=false
var auto_deployment_signature:=""
var auto_deployment_step_index:=-1
var auto_deployment_render_stage:=0
var auto_combat_pending:=false
var auto_combat_fallback:=false
var auto_combat_plan_hash:=""
var auto_combat_step_index:=-1
var auto_combat_render_stage:=0
var auto_override_edit:=false
var auto_phase:=""
var exploration_follow_plan:Dictionary={}
var _initialized_for_headless_test:=false
var _run_progress_initialized:=false
var _observed_reward_granted:=false
var _reward_emphasis_pending:=false
var _reward_emphasis_count:=0
var _reward_emphasis_tween:Tween
var _run_locked_exit_feedback:=false
var _personality_entropy_source:Callable

func _ready()->void:
	_build_ui()
	if not _initialized_for_headless_test and session==null:
		session=SessionScript.new(SessionScript.DEFAULT_WORLD_SEED,
			_issue_new_personality_seed(),SessionScript.SHOWCASE_SCENARIO_ID)
		auto_orchestration_enabled=true;_reset_auto_flow()
	_refresh()
	if _initialized_for_headless_test and auto_orchestration_enabled:
		_arm_pending_auto_after_tree_entry()
func initialize_for_headless_test(custom_session=null,auto_orchestration:bool=false)->void:
	if grid==null: _build_ui()
	_initialized_for_headless_test=true
	session=custom_session if custom_session!=null else SessionScript.new()
	auto_orchestration_enabled=auto_orchestration
	_reset_auto_flow();_refresh()

func set_personality_entropy_source_for_headless_test(source:Callable)->void:
	_personality_entropy_source=source

func _issue_new_personality_seed(avoid_seed:int=-1)->int:
	var entropy_seed:=0
	if _personality_entropy_source.is_valid():
		entropy_seed=int(_personality_entropy_source.call())
	else:
		var entropy:=RandomNumberGenerator.new();entropy.randomize()
		entropy_seed=int(entropy.randi())
	return SessionScript.new_expedition_personality_seed(entropy_seed,avoid_seed)

func _build_ui()->void:
	if grid!=null:return
	var ui_theme:=Theme.new(); ui_theme.default_font=KoreanFont; ui_theme.default_font_size=FONT_BODY; theme=ui_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg:=ColorRect.new(); bg.color=Color("#09111b"); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	root_layout=VBoxContainer.new(); root_layout.name="PartyLayout"; root_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layout.offset_left=6; root_layout.offset_right=-6; root_layout.offset_top=4; root_layout.offset_bottom=-4; root_layout.add_theme_constant_override("separation",4); add_child(root_layout)
	phase_panel=PanelContainer.new(); phase_panel.name="PhaseBanner"; phase_panel.custom_minimum_size.y=48; root_layout.add_child(phase_panel)
	phase_label=Label.new(); phase_label.name="PhaseStatus"; phase_label.add_theme_font_size_override("font_size",FONT_KEY)
	phase_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; phase_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; phase_panel.add_child(phase_label)
	run_objective_bar=PanelContainer.new();run_objective_bar.name="RunObjectiveBar"
	run_objective_bar.custom_minimum_size.y=TOUCH_TARGET;run_objective_bar.visible=false;root_layout.add_child(run_objective_bar)
	var objective_style:=StyleBoxFlat.new();objective_style.bg_color=Color("#122233")
	objective_style.border_color=Color("#36536b");objective_style.set_border_width_all(1)
	objective_style.set_corner_radius_all(6);objective_style.content_margin_left=8
	objective_style.content_margin_right=8;objective_style.content_margin_top=3;objective_style.content_margin_bottom=3
	run_objective_bar.add_theme_stylebox_override("panel",objective_style)
	var objective_row:=HBoxContainer.new();objective_row.name="RunObjectiveRow"
	objective_row.add_theme_constant_override("separation",6);run_objective_bar.add_child(objective_row)
	run_objective_label=Label.new();run_objective_label.name="RunObjectiveText"
	run_objective_label.add_theme_font_size_override("font_size",FONT_BODY)
	run_objective_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	run_objective_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	run_objective_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;objective_row.add_child(run_objective_label)
	reward_badge=Label.new();reward_badge.name="RewardBadge";reward_badge.text="$ 1"
	reward_badge.custom_minimum_size=Vector2(52,TOUCH_TARGET-8);reward_badge.visible=false
	reward_badge.add_theme_font_size_override("font_size",FONT_BODY)
	reward_badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	reward_badge.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var reward_style:=StyleBoxFlat.new();reward_style.bg_color=Color("#2b402d")
	reward_style.border_color=Color("#75d7a0");reward_style.set_border_width_all(2)
	reward_style.set_corner_radius_all(6);reward_badge.add_theme_stylebox_override("normal",reward_style)
	objective_row.add_child(reward_badge)
	grid=GridScript.new(); grid.name="PartyGrid"; grid.custom_minimum_size=Vector2(348,348); grid.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	grid.world_cell_pressed.connect(_on_cell); grid.actor_pressed.connect(_on_actor)
	grid.tile_long_pressed.connect(_on_tile_long_pressed)
	grid.pointer_gesture_started.connect(_on_grid_pointer_started)
	grid.pointer_gesture_finished.connect(_on_grid_pointer_finished); root_layout.add_child(grid)
	cards=HBoxContainer.new(); cards.name="PartyCards"; cards.custom_minimum_size.y=160
	cards.add_theme_constant_override("separation",4); root_layout.add_child(cards)
	info_scroll=ScrollContainer.new(); info_scroll.name="InformationScroll"; info_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; root_layout.add_child(info_scroll)
	var info:=VBoxContainer.new(); info.name="InformationStack"; info.size_flags_horizontal=Control.SIZE_EXPAND_FILL; info.add_theme_constant_override("separation",6); info_scroll.add_child(info)
	deck=VBoxContainer.new(); deck.name="ContextDeck"; deck.add_theme_constant_override("separation",6); info.add_child(deck)
	log_label=Label.new(); log_label.name="NarrativeLog"; log_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("font_size",FONT_AUX); log_label.custom_minimum_size.y=48; info.add_child(log_label)
	combat_action_area=VBoxContainer.new();combat_action_area.name="CombatActionArea";combat_action_area.custom_minimum_size.y=84
	combat_action_area.add_theme_constant_override("separation",2);combat_action_area.visible=false;root_layout.add_child(combat_action_area)
	action_feedback_label=Label.new();action_feedback_label.name="ActionFeedback";action_feedback_label.custom_minimum_size.y=38
	action_feedback_label.add_theme_font_size_override("font_size",FONT_AUX);action_feedback_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	action_feedback_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;action_feedback_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	combat_action_area.add_child(action_feedback_label)
	combat_action_dock=HBoxContainer.new(); combat_action_dock.name="CombatActionDock"; combat_action_dock.custom_minimum_size.y=TOUCH_TARGET
	combat_action_dock.add_theme_constant_override("separation",4);combat_action_dock.visible=false;combat_action_area.add_child(combat_action_dock)
	_build_tile_popover()
	_build_member_detail_modal()
	resized.connect(_layout_floating_surfaces)

func _build_tile_popover()->void:
	tile_popover=PanelContainer.new();tile_popover.name="TileRiskPopover";tile_popover.visible=false
	tile_popover.mouse_filter=Control.MOUSE_FILTER_IGNORE;tile_popover.z_index=20;add_child(tile_popover)
	var style:=StyleBoxFlat.new();style.bg_color=Color("#172838e8");style.border_color=Color("#75c8ff")
	style.set_border_width_all(2);style.set_corner_radius_all(7)
	style.content_margin_left=8;style.content_margin_right=8;style.content_margin_top=6;style.content_margin_bottom=6
	tile_popover.add_theme_stylebox_override("panel",style)
	tile_popover_label=Label.new();tile_popover_label.name="TileRiskText";tile_popover_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	tile_popover_label.add_theme_font_size_override("font_size",FONT_AUX);tile_popover_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	tile_popover.add_child(tile_popover_label)

func _build_member_detail_modal()->void:
	member_detail_modal=Control.new();member_detail_modal.name="MemberDetailModal";member_detail_modal.visible=false
	member_detail_modal.mouse_filter=Control.MOUSE_FILTER_STOP;member_detail_modal.z_index=40
	member_detail_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(member_detail_modal)
	var scrim:=ColorRect.new();scrim.name="MemberDetailScrim";scrim.color=Color("#02060bd9")
	scrim.mouse_filter=Control.MOUSE_FILTER_STOP;scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(_on_member_detail_backdrop_input);member_detail_modal.add_child(scrim)
	member_detail_panel=PanelContainer.new();member_detail_panel.name="MemberDetailPanel";member_detail_panel.mouse_filter=Control.MOUSE_FILTER_STOP
	var panel_style:=StyleBoxFlat.new();panel_style.bg_color=Color("#142434");panel_style.border_color=Color("#75c8ff")
	panel_style.set_border_width_all(2);panel_style.set_corner_radius_all(9)
	panel_style.content_margin_left=12;panel_style.content_margin_right=12;panel_style.content_margin_top=12;panel_style.content_margin_bottom=12
	member_detail_panel.add_theme_stylebox_override("panel",panel_style);member_detail_modal.add_child(member_detail_panel)
	var stack:=VBoxContainer.new();stack.name="MemberDetailStack";stack.add_theme_constant_override("separation",8);member_detail_panel.add_child(stack)
	var header:=HBoxContainer.new();header.name="MemberDetailHeader";header.custom_minimum_size.y=TOUCH_TARGET;stack.add_child(header)
	member_detail_title=Label.new();member_detail_title.name="MemberDetailTitle";member_detail_title.add_theme_font_size_override("font_size",FONT_KEY)
	member_detail_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;member_detail_title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;header.add_child(member_detail_title)
	member_detail_close=Button.new();member_detail_close.name="MemberDetailClose";member_detail_close.text="닫기"
	member_detail_close.custom_minimum_size=Vector2(64,TOUCH_TARGET);member_detail_close.add_theme_font_size_override("font_size",FONT_BODY)
	member_detail_close.gui_input.connect(_on_member_detail_close_input.bind(member_detail_close))
	member_detail_close.pressed.connect(_close_member_detail);header.add_child(member_detail_close)
	member_detail_scroll=ScrollContainer.new();member_detail_scroll.name="MemberDetailScroll";member_detail_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	member_detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;stack.add_child(member_detail_scroll)
	member_detail_body=Label.new();member_detail_body.name="MemberDetailBody";member_detail_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	member_detail_body.add_theme_font_size_override("font_size",FONT_AUX);member_detail_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_body.mouse_filter=Control.MOUSE_FILTER_IGNORE;member_detail_scroll.add_child(member_detail_body)

func _layout_floating_surfaces()->void:
	if member_detail_panel!=null:
		var panel_width:=minf(size.x-24.0,420.0 if size.x>=450.0 else 336.0)
		var panel_height:=minf(size.y-24.0,720.0)
		member_detail_panel.position=(size-Vector2(panel_width,panel_height))*0.5
		member_detail_panel.size=Vector2(panel_width,panel_height)
		member_detail_body.custom_minimum_size.x=maxf(1.0,panel_width-48.0)
	if tile_popover!=null and tile_popover.visible:_position_tile_popover()

func _refresh()->void:
	if session==null:return
	grid.cancel_pointer_gesture()
	var status:Dictionary=session.party_status()
	if not bool(status.get("ok",false)):return
	if auto_orchestration_enabled:
		_orchestrate_auto_phase(status)
		status=session.party_status()
	var run_progress:=_current_run_progress()
	var run_available:=bool(run_progress.get("available",false))
	var run_complete:=bool(run_progress.get("complete",false))
	var run_terminal:=run_available and bool(run_progress.get("terminal",false))
	var run_exit:Dictionary=run_progress.get("exit",{}) if run_progress.get("exit",{}) is Dictionary else {}
	if bool(run_exit.get("open",false)) or run_terminal:_run_locked_exit_feedback=false
	_update_run_objective_bar(run_progress)
	var safe_phase:=str(status.safe_phase)
	if _action_feedback_phase!=safe_phase:
		action_feedback_text="";_action_feedback_phase=safe_phase
		if str(status.view_mode)!="EXPLORATION":
			route_generation+=1;route_continue_pending=false;route_preview.clear();grid.clear_route_overlay();_hide_tile_popover()
	var presentation:Dictionary=session.presentation_state()
	var combat_zoomed:=str(status.view_mode)=="COMBAT"
	var combat_actions_visible:=safe_phase=="ENGAGED" and not bool(status.terminal) \
		or run_terminal or _run_locked_exit_feedback
	var party_rows:Array=session.party_cards()
	var card_layout:=party_card_layout_spec(party_rows.size(),size.x)
	_apply_portrait_budget(combat_zoomed,combat_actions_visible,run_available,run_terminal,
		int(card_layout.get("party_height",160)))
	if selected_member_id not in status.party_member_ids:selected_member_id=int(status.protagonist_id)
	if selected_target_id not in status.visible_enemy_ids:selected_target_id=-1
	if not pending_move_mode.is_empty() and pending_move_mode!=str(status.view_mode):_clear_move_preview()
	_apply_phase_banner(status,presentation)
	var deployment:Dictionary=session.deployment_draft(); var ghosts:Array=deployment.placements if str(status.view_mode)=="ENCOUNTER_PREVIEW" else []
	var observation:Dictionary=session.observe_party_world()
	var intent_overlays:Array=session.turn_intent_overlays() if combat_zoomed and not run_complete else []
	grid.set_observation(observation,ghosts)
	grid.set_view_window(9 if combat_zoomed else 15,_camera_focus_points(observation,intent_overlays),
		_camera_priority_points(observation))
	grid.set_presentation_style(presentation.get("grid_style",{}))
	grid.set_selection(selected_member_id,selected_target_id)
	grid.set_intent_overlays(intent_overlays)
	if run_complete:
		route_generation+=1;route_continue_pending=false;route_preview.clear()
		grid.clear_route_overlay();_clear_companion_follow_plan();_clear_move_preview()
	elif str(status.view_mode)=="EXPLORATION":
		var route_state:Dictionary=session.exploration_route_state()
		var state_matches_local:=route_preview.is_empty() or _route_goal(route_state)==_route_goal(route_preview)
		if bool(route_state.get("has_preview",false)) and state_matches_local:
			route_preview=route_state.duplicate(true);_apply_route_overlay(route_state);_apply_companion_follow_plan(route_state)
		elif route_preview.is_empty() or not bool(route_preview.get("accepted",false)):
			grid.clear_route_overlay();_clear_companion_follow_plan()
	else:
		grid.clear_route_overlay();_clear_companion_follow_plan()
	if pending_move_actor_id>0:grid.set_cursor_preview(pending_move_actor_id,pending_move_origin,pending_move_destination,pending_move_valid)
	else:grid.clear_cursor_preview()
	_refresh_tile_popover(status)
	var companion_speech_by_actor:Dictionary={}
	if safe_phase=="ENGAGED" and str(status.view_mode)=="COMBAT" \
			and not bool(status.terminal) and not run_complete \
			and session.has_method("companion_speech_bubbles"):
		for speech in session.companion_speech_bubbles():
			if speech is Dictionary:
				companion_speech_by_actor[int(speech.get("actor_id",-1))]=speech.duplicate(true)
	_render_party_cards(party_rows,companion_speech_by_actor,card_layout)
	_clear_container(deck)
	_clear_container(combat_action_dock);combat_action_dock.visible=false
	action_feedback_label.visible=true
	combat_action_area.visible=combat_actions_visible;_update_action_feedback(status)
	if _run_locked_exit_feedback and not run_terminal and safe_phase!="ENGAGED":
		combat_action_area.custom_minimum_size.y=TOUCH_TARGET
	if run_complete:_run_complete_deck(run_progress)
	else:
		match str(status.view_mode):
			"EXPLORATION":_exploration_deck()
			"ENCOUNTER_PREVIEW":_deployment_deck(deployment)
			"COMBAT":_combat_deck(status,session.current_turn_preview())
			"REGROUP":_legacy_regroup_notice()
	if run_terminal:_build_run_restart_area()
	var combat_history:Dictionary=session.combat_log(8,80)
	log_label.text=_combat_log_text(combat_history)
	if _scroll_log_after_refresh:
		_scroll_log_after_refresh=false;call_deferred("_scroll_information_to_latest_log")

func _current_run_progress()->Dictionary:
	if session!=null and session.has_method("run_progress"):
		var value:Variant=session.call("run_progress")
		if value is Dictionary:return value.duplicate(true)
	return {"schema_version":1,"available":false,"scenario_id":"","objective_id":"",
		"run_state":"UNAVAILABLE","entry_position":[],"exit_position":[],
		"encounter_cleared":false,"reward":{"reward_id":"","amount":0,"granted":false},
		"exit":{"feature_id":"","open":false},"complete":false,"terminal":false}

func _update_run_objective_bar(progress:Dictionary)->void:
	var available:=bool(progress.get("available",false))
	run_objective_bar.visible=available
	if not available:
		_run_progress_initialized=false;_observed_reward_granted=false
		_reward_emphasis_pending=false;return
	var state:=str(progress.get("run_state","EXPLORE"))
	run_objective_label.text={
		"EXIT_OPEN":"보상 +1 · 출구가 열렸습니다",
		"COMPLETE":"원정 완료 · 보상 1",
		"DEFEATED":"원정 실패",
	}.get(state,"목표 · 고블린을 쓰러뜨리세요")
	var reward:Dictionary=progress.get("reward",{}) if progress.get("reward",{}) is Dictionary else {}
	var granted:=bool(reward.get("granted",false))
	reward_badge.visible=granted;reward_badge.text="$ %d"%int(reward.get("amount",0))
	if _reward_emphasis_pending and granted:_play_reward_emphasis()
	_reward_emphasis_pending=false;_observed_reward_granted=granted;_run_progress_initialized=true

func _play_reward_emphasis()->void:
	_reward_emphasis_count+=1
	if reward_badge==null:return
	if _reward_emphasis_tween!=null and _reward_emphasis_tween.is_valid():_reward_emphasis_tween.kill()
	reward_badge.modulate=Color("#fff0a6")
	if not is_inside_tree():reward_badge.modulate=Color.WHITE;return
	_reward_emphasis_tween=create_tween()
	_reward_emphasis_tween.tween_property(reward_badge,"modulate",Color.WHITE,0.45)

func _reset_auto_flow()->void:
	auto_generation+=1
	auto_deployment_pending=false;auto_deployment_fallback=false
	auto_deployment_signature="";auto_deployment_step_index=-1;auto_deployment_render_stage=0
	auto_combat_pending=false;auto_combat_fallback=false
	auto_combat_plan_hash="";auto_combat_step_index=-1;auto_combat_render_stage=0
	auto_override_edit=false;auto_phase="";exploration_follow_plan.clear()

func _arm_pending_auto_after_tree_entry()->void:
	if not is_inside_tree():return
	if auto_deployment_pending and auto_deployment_render_stage==0:
		get_tree().process_frame.connect(_advance_auto_deployment_preview.bind(auto_generation),CONNECT_ONE_SHOT)
	elif auto_combat_pending and auto_combat_render_stage==0:
		_arm_auto_combat_preview(auto_generation)

func _orchestrate_auto_phase(status:Dictionary)->void:
	var phase:=str(status.get("safe_phase",""))
	if phase!=auto_phase:
		auto_generation+=1;auto_deployment_pending=false;auto_combat_pending=false
		auto_deployment_signature="";auto_combat_plan_hash=""
		auto_deployment_render_stage=0;auto_combat_render_stage=0
		auto_deployment_fallback=false;auto_combat_fallback=false;auto_override_edit=false
		auto_phase=phase
	match phase:
		"CONTACT":
			if not auto_deployment_pending and not auto_deployment_fallback:_prepare_auto_deployment(status)
		"ENGAGED":
			var planning:Dictionary=session.auto_combat_planning_state()
			if not bool(planning.get("active",false)):planning=session.prepare_auto_combat_plan()
			if not bool(planning.get("accepted",false)):
				auto_combat_fallback=true
				action_feedback_text=str(planning.get("message","자동 계획을 준비할 수 없습니다. 행동을 직접 지정하세요."))
		_:
			auto_deployment_pending=false;auto_combat_pending=false

func _prepare_auto_deployment(status:Dictionary)->void:
	var companion_ids:Array=session.available_companion_ids()
	for preset in AUTO_FORMATION_ORDER:
		var result:Dictionary=session.preview_deployment(preset,companion_ids)
		if not bool(result.get("accepted",false)):continue
		var draft:Dictionary=session.deployment_draft()
		auto_generation+=1;auto_deployment_pending=true;auto_deployment_render_stage=0
		auto_deployment_signature=JSON.stringify(draft)
		auto_deployment_step_index=int(status.get("step_index",-1))
		notice_text="%s 대형을 자동 배치합니다."%{"WEDGE":"쐐기","LINE":"횡대","COLUMN":"종대"}.get(preset,preset)
		action_feedback_text="자동 배치 미리보기"
		if is_inside_tree():
			get_tree().process_frame.connect(_advance_auto_deployment_preview.bind(auto_generation),CONNECT_ONE_SHOT)
		return
	auto_deployment_fallback=true
	notice_text="자동 배치가 불가능합니다. 대형을 직접 선택하세요."
	action_feedback_text=notice_text

func _advance_auto_deployment_preview(expected_generation:int)->void:
	if not auto_orchestration_enabled or not auto_deployment_pending or expected_generation!=auto_generation:return
	var status:Dictionary=session.party_status()
	if str(status.get("safe_phase",""))!="CONTACT" or member_detail_modal.visible \
			or bool(grid.pointer_gesture_state().get("active",false)):
		_cancel_auto_pending(true);_request_refresh();return
	auto_deployment_render_stage=1
	if is_inside_tree():
		get_tree().process_frame.connect(_commit_auto_deployment.bind(expected_generation),CONNECT_ONE_SHOT)

func _commit_auto_deployment(expected_generation:int)->void:
	if not auto_orchestration_enabled or not auto_deployment_pending or expected_generation!=auto_generation:return
	var status:Dictionary=session.party_status()
	var pointer_active:=bool(grid.pointer_gesture_state().get("active",false))
	var draft:Dictionary=session.deployment_draft()
	if str(status.get("safe_phase",""))!="CONTACT" or int(status.get("step_index",-1))!=auto_deployment_step_index \
			or pointer_active or member_detail_modal.visible or not bool(draft.get("accepted",false)) \
			or JSON.stringify(draft)!=auto_deployment_signature:
		_cancel_auto_pending(true);_request_refresh();return
	auto_deployment_pending=false
	var result:Dictionary=session.commit_deployment()
	if not bool(result.get("accepted",false)):auto_deployment_fallback=true
	_record_result(result,true,"자동 배치 불가")
	_refresh()

func _cancel_auto_pending(use_manual_fallback:bool=false)->void:
	auto_generation+=1;auto_deployment_pending=false;auto_combat_pending=false
	auto_deployment_signature="";auto_combat_plan_hash=""
	auto_deployment_render_stage=0;auto_combat_render_stage=0
	if use_manual_fallback:
		var phase:=str(session.party_status().get("safe_phase","")) if session!=null else ""
		if phase=="CONTACT":auto_deployment_fallback=true
		elif phase=="ENGAGED":auto_combat_fallback=true

func _apply_companion_follow_plan(route_state:Dictionary)->void:
	exploration_follow_plan=session.exploration_companion_follow_plan(route_state) \
		if session.has_method("exploration_companion_follow_plan") else {}
	if grid.has_method("set_exploration_companion_follow_plan"):
		grid.call("set_exploration_companion_follow_plan",exploration_follow_plan)
	elif grid.has_method("set_companion_follow_plan"):
		grid.call("set_companion_follow_plan",exploration_follow_plan)

func _clear_companion_follow_plan()->void:
	exploration_follow_plan.clear()
	if grid.has_method("set_exploration_companion_follow_plan"):
		grid.call("set_exploration_companion_follow_plan",{})
	elif grid.has_method("set_companion_follow_plan"):
		grid.call("set_companion_follow_plan",{})

func auto_flow_state()->Dictionary:
	return {"enabled":auto_orchestration_enabled,"phase":auto_phase,"generation":auto_generation,
		"deployment_pending":auto_deployment_pending,"deployment_fallback":auto_deployment_fallback,
		"deployment_render_stage":auto_deployment_render_stage,
		"combat_pending":auto_combat_pending,"combat_fallback":auto_combat_fallback,
		"combat_render_stage":auto_combat_render_stage,
		"override_edit":auto_override_edit,"plan_hash":auto_combat_plan_hash,
		"follow_plan":exploration_follow_plan.duplicate(true)}.duplicate(true)

func party_card_layout_spec(count:int,viewport_width:float)->Dictionary:
	var effective_count:=clampi(count,0,3)
	if effective_count==0:
		return {"layout_id":"EMPTY","requested_count":count,"effective_count":0,
			"party_height":0,"gap":0,"card_min_width":0,
			"portrait_min_size":[0,0],"font_size":FONT_AUX}.duplicate(true)
	var gap:=4
	var available_width:=maxi(44,int(floor(viewport_width))-12-gap*(effective_count-1))
	var spec:Dictionary={"layout_id":"COMPACT","requested_count":count,
		"effective_count":effective_count,"party_height":160,"gap":gap,
		"card_min_width":maxi(44,int(floor(float(available_width)/effective_count))),
		"portrait_min_size":[52,54],"font_size":FONT_AUX}
	if effective_count==1:
		spec.layout_id="SPOTLIGHT";spec.party_height=112
		spec.portrait_min_size=[88,88]
	elif effective_count==2:
		spec.layout_id="DUAL";spec.party_height=150
		spec.portrait_min_size=[68,68]
	return spec.duplicate(true)

func render_party_cards_for_headless_test(rows:Array,speeches:Array=[])->Dictionary:
	var speech_by_actor:Dictionary={}
	for speech in speeches:
		if speech is Dictionary:
			speech_by_actor[int(speech.get("actor_id",-1))]=speech.duplicate(true)
	var spec:=party_card_layout_spec(rows.size(),size.x)
	_render_party_cards(rows,speech_by_actor,spec)
	return spec.duplicate(true)

func _render_party_cards(rows:Array,speech_by_actor:Dictionary,spec:Dictionary)->void:
	_clear_container(cards)
	cards.custom_minimum_size.y=int(spec.get("party_height",160))
	cards.add_theme_constant_override("separation",int(spec.get("gap",4)))
	var effective_count:=mini(rows.size(),int(spec.get("effective_count",0)))
	for index in range(effective_count):
		var row:Variant=rows[index]
		if row is Dictionary:
			_add_member_card(row,speech_by_actor.get(int(row.get("entity_id",-1)),{}),spec)

func _add_member_card(row:Dictionary,speech:Dictionary={},layout_spec:Dictionary={})->void:
	var spec:=layout_spec if not layout_spec.is_empty() else party_card_layout_spec(3,size.x)
	var button:=Button.new(); var member_id:=int(row.entity_id); button.name="MemberCard%d"%member_id
	button.custom_minimum_size=Vector2(float(spec.get("card_min_width",44)),float(spec.get("party_height",160)))
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.size_flags_stretch_ratio=1.0
	button.text=""; button.clip_contents=true
	button.modulate=Color("#d8f3ff") if member_id==selected_member_id else Color.WHITE
	var inset:=MarginContainer.new(); inset.name="CardContent"; inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for margin in ["margin_left","margin_right"]:inset.add_theme_constant_override(margin,3)
	for margin in ["margin_top","margin_bottom"]:inset.add_theme_constant_override(margin,2)
	inset.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(inset)
	if str(spec.get("layout_id","COMPACT"))=="SPOTLIGHT":
		_add_spotlight_card_content(inset,row,speech,spec)
	else:
		_add_stacked_card_content(inset,row,speech,spec)
	button.gui_input.connect(_on_member_card_gui_input.bind(member_id,str(row.display_name),button))
	button.pressed.connect(_on_member_card_pressed.bind(member_id,str(row.display_name))); cards.add_child(button)

func _add_spotlight_card_content(inset:MarginContainer,row:Dictionary,speech:Dictionary,
		spec:Dictionary)->void:
	var stack:=HBoxContainer.new();stack.name="CardStack";stack.add_theme_constant_override("separation",8)
	stack.mouse_filter=Control.MOUSE_FILTER_IGNORE;inset.add_child(stack)
	var portrait_view=_member_portrait(row,spec);stack.add_child(portrait_view)
	var details:=VBoxContainer.new();details.name="SpotlightDetails"
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_constant_override("separation",1)
	details.mouse_filter=Control.MOUSE_FILTER_IGNORE;stack.add_child(details)
	if str(row.get("role",""))=="COMPANION" and not speech.is_empty():
		_add_companion_speech_strip(details,speech)
	var name_label:=_card_label(str(row.display_name),"MemberName",FONT_BODY)
	name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;details.add_child(name_label)
	var state_line:=HBoxContainer.new();state_line.name="SpotlightState"
	state_line.mouse_filter=Control.MOUSE_FILTER_IGNORE;details.add_child(state_line)
	var ready_label:=_card_label("준비" if str(row.readiness)=="행동 준비" else "행동중","Readiness",FONT_AUX)
	ready_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;state_line.add_child(ready_label)
	var emotion_label:=_card_label("%s%s"%[str(row.emotion.icon),str(row.emotion.label)],"EmotionState",FONT_AUX)
	emotion_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;emotion_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	state_line.add_child(emotion_label)
	_add_vitals(details,row,true)

func _add_stacked_card_content(inset:MarginContainer,row:Dictionary,speech:Dictionary,
		spec:Dictionary)->void:
	var stack:=VBoxContainer.new(); stack.name="CardStack"; stack.add_theme_constant_override("separation",0); stack.mouse_filter=Control.MOUSE_FILTER_IGNORE; inset.add_child(stack)
	if str(row.get("role",""))=="COMPANION" and not speech.is_empty():_add_companion_speech_strip(stack,speech)
	var heading:=HBoxContainer.new(); heading.name="CardHeading"; heading.alignment=BoxContainer.ALIGNMENT_CENTER
	var portrait_size:Array=spec.get("portrait_min_size",[52,54])
	heading.custom_minimum_size.y=float(portrait_size[1]);heading.add_theme_constant_override("separation",0)
	heading.mouse_filter=Control.MOUSE_FILTER_IGNORE; stack.add_child(heading)
	var portrait_view=_member_portrait(row,spec);heading.add_child(portrait_view)
	var identity:=VBoxContainer.new();identity.name="CardIdentity";identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation",0);identity.mouse_filter=Control.MOUSE_FILTER_IGNORE;heading.add_child(identity)
	var name_label:=_card_label(str(row.display_name),"MemberName",FONT_AUX)
	name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	identity.add_child(name_label)
	var ready_label:=_card_label("준비" if str(row.readiness)=="행동 준비" else "행동중","Readiness",FONT_AUX)
	ready_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;identity.add_child(ready_label)
	var emotion_label:=_card_label("%s%s"%[str(row.emotion.icon),str(row.emotion.label)],"EmotionState",FONT_AUX)
	emotion_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;emotion_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	identity.add_child(emotion_label)
	_add_vitals(stack,row,false)

func _member_portrait(row:Dictionary,spec:Dictionary):
	var portrait_size:Array=spec.get("portrait_min_size",[52,54])
	var portrait_view=PortraitScript.new();portrait_view.name="Portrait"
	portrait_view.custom_minimum_size=Vector2(float(portrait_size[0]),float(portrait_size[1]))
	portrait_view.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var member_id:=int(row.entity_id);var portrait_actor:Dictionary=row.duplicate(true)
	var detail:Dictionary=session.inspect_party_member(member_id)
	portrait_actor["is_protagonist"]=str(row.get("role",""))=="PROTAGONIST";portrait_actor["faction_id"]="party"
	portrait_actor["species_id"]=str(detail.get("species_id",portrait_actor.get("species_id","human")))
	portrait_actor["life_state"]="ACTIVE" if bool(row.get("alive",true)) else "DEAD"
	portrait_actor["status_ids"]=row.get("status_ids",[]).duplicate(true)
	portrait_view.set_actor(portrait_actor);return portrait_view

func _add_vitals(parent:VBoxContainer,row:Dictionary,show_exact_max:bool)->void:
	var vitals_text:=HBoxContainer.new();vitals_text.name="VitalsText";vitals_text.add_theme_constant_override("separation",2)
	vitals_text.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(vitals_text)
	var hp_value:="HP %d/%d"%[int(row.health),int(row.max_health)] if show_exact_max else "HP %d"%int(row.health)
	var health_text:=_card_label(hp_value,"MemberState",FONT_AUX)
	health_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;health_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;vitals_text.add_child(health_text)
	var stress_text:=_card_label("ST %d"%int(row.stress),"StressState",FONT_AUX)
	stress_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;stress_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;vitals_text.add_child(stress_text)
	var bars:=HBoxContainer.new(); bars.name="VitalsBars"; bars.add_theme_constant_override("separation",3);parent.add_child(bars)
	var health_bar:=_bar("HealthBar",int(row.health),int(row.max_health),Color("#62d98b")); health_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL; bars.add_child(health_bar)
	var stress_bar:=_bar("StressBar",int(row.stress),1000,Color("#ffae5f")); stress_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL; bars.add_child(stress_bar)

func _add_companion_speech_strip(parent:VBoxContainer,speech:Dictionary)->void:
	var strip:=PanelContainer.new();strip.name="CompanionSpeechStrip";strip.custom_minimum_size.y=36
	strip.mouse_filter=Control.MOUSE_FILTER_IGNORE;strip.clip_contents=true
	strip.set_meta("actor_id",int(speech.get("actor_id",-1)))
	strip.set_meta("source",str(speech.get("source","SUGGESTED")))
	strip.set_meta("full_reason",str(speech.get("reason","")))
	var source:=str(speech.get("source","SUGGESTED"))
	var style:=StyleBoxFlat.new();style.bg_color=Color("#101C28")
	style.border_color=Color("#ff9f68" if source=="OVERRIDE" else "#75c8ff")
	style.set_border_width_all(1);style.set_corner_radius_all(4)
	style.content_margin_left=3;style.content_margin_right=3
	style.content_margin_top=1;style.content_margin_bottom=1
	strip.add_theme_stylebox_override("panel",style);parent.add_child(strip)
	var text:=Label.new();text.name="CompanionSpeechText"
	text.text="%s\n%s"%[str(speech.get("headline","엄호할게.")),
		str(speech.get("reason_summary","자리를 지키려고"))]
	text.max_lines_visible=2;text.clip_text=true
	text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_theme_font_size_override("font_size",12)
	text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter=Control.MOUSE_FILTER_IGNORE;strip.add_child(text)

func _bar(node_name:String,value:int,maximum:int,color:Color)->ProgressBar:
	var bar:=ProgressBar.new(); bar.name=node_name; bar.min_value=0; bar.max_value=maximum; bar.value=value
	bar.show_percentage=false; bar.custom_minimum_size.y=7; bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var fill:=StyleBoxFlat.new(); fill.bg_color=color; fill.corner_radius_top_left=3; fill.corner_radius_top_right=3; fill.corner_radius_bottom_left=3; fill.corner_radius_bottom_right=3
	var background:=StyleBoxFlat.new(); background.bg_color=Color("#25313d")
	bar.add_theme_stylebox_override("fill",fill); bar.add_theme_stylebox_override("background",background); return bar

func _card_label(value:String,node_name:String,font_size:int)->Label:
	var label:=Label.new(); label.name=node_name; label.text=value; label.add_theme_font_size_override("font_size",maxi(FONT_AUX,font_size)); label.mouse_filter=Control.MOUSE_FILTER_IGNORE; return label
func _compact_action(action:Dictionary)->String:
	var source:=str(action.get("source_label","자동 제안")); var action_type:=str(action.get("type","HOLD"))
	if action_type=="MOVE":var destination:Array=action.get("destination",[-1,-1]); return "%s · 이동 (%d,%d)"%[source,int(destination[0]),int(destination[1])]
	if action_type=="MELEE":return "%s · 공격 %s"%[source,str(action.get("target_name","적"))]
	return "%s · 대기"%source

func _exploration_deck()->void:
	_add_notice(notice_text if not notice_text.is_empty() else "탐험: 이동할 목적지를 눌러 경로와 위험을 미리보세요.")
	if pending_move_mode=="EXPLORATION":
		var actor_name:=_protagonist_name(); var summary:=""
		if pending_exploration_wait:
			summary="대표 대기: %s (%d,%d)\n현재 칸을 한 번 더 누르면 대기합니다."%[actor_name,pending_move_origin.x,pending_move_origin.y]
		else:
			summary="대표 경로: %s (%d,%d) → (%d,%d) · %d칸 · 시간 %d"%[actor_name,pending_move_origin.x,pending_move_origin.y,
				pending_move_destination.x,pending_move_destination.y,int(route_preview.get("total_steps",1)),pending_move_cost]
			summary+="\n같은 목적지를 다시 누르면 한 칸씩 이동합니다." if pending_move_valid else "\n"+notice_text
		_add_notice(summary,"MovePreviewSummary",FONT_KEY)
	_selected_detail()

func _run_complete_deck(progress:Dictionary)->void:
	var reward:Dictionary=progress.get("reward",{}) if progress.get("reward",{}) is Dictionary else {}
	_add_notice("원정 완료 · 고블린을 쓰러뜨리고 출구에 도달했습니다.\n보상 $ %d"%int(reward.get("amount",1)),
		"RunCompleteSummary",FONT_KEY)
	_selected_detail()

func _build_run_restart_area()->void:
	combat_action_area.visible=true;combat_action_area.custom_minimum_size.y=TOUCH_TARGET
	action_feedback_label.visible=false;combat_action_dock.visible=true
	var restart:=_add_button(combat_action_dock,"새 성격으로 다시 시작","RestartSameRun",_on_restart_with_new_personality)
	restart.size_flags_stretch_ratio=1.0

func _deployment_deck(deployment:Dictionary)->void:
	var preset_label:String={"WEDGE":"쐐기","LINE":"횡대","COLUMN":"종대","NONE":"미선택"}.get(str(deployment.preset_id),"미선택")
	_add_notice(notice_text if not notice_text.is_empty() else "배치 대형: %s · %s"%[preset_label,str(deployment.message)])
	if auto_orchestration_enabled and auto_deployment_pending:
		_add_notice("%s 대형 ghost를 확인한 뒤 자동으로 전투를 시작합니다."%preset_label,"AutoDeploymentPreview",FONT_AUX)
		_selected_detail();return
	var controls:=HBoxContainer.new(); controls.name="FormationControls"; deck.add_child(controls)
	for preset in ["WEDGE","LINE","COLUMN"]:
		var button:=_add_button(controls,{"WEDGE":"쐐기","LINE":"횡대","COLUMN":"종대"}[preset],"Preset%s"%preset,_on_preset.bind(preset)); button.toggle_mode=true; button.button_pressed=str(deployment.preset_id)==preset
	var confirm:=_add_button(deck,"배치 확정","DeployConfirm",_on_deploy_confirm); confirm.disabled=not bool(deployment.accepted)
	_selected_detail()
func _combat_deck(status:Dictionary,preview:Dictionary)->void:
	if bool(status.terminal):_add_notice("파티가 패배했습니다. 주인공이 쓰러져 더 행동할 수 없습니다.","TerminalOverlay",FONT_KEY); return
	var actor_name:=_selected_name(); var instruction:="%s 선택 · 빈 칸은 이동, 적은 공격"%actor_name
	if auto_orchestration_enabled:
		var planning:Dictionary=session.auto_combat_planning_state()
		if bool(planning.get("placeholder",false)):
			instruction="동료 제안이 준비되었습니다 · 주인공의 실제 행동을 선택하세요."
		elif auto_combat_pending:instruction="최종 계획을 표시했습니다 · 잠시 뒤 자동 실행합니다."
		elif auto_override_edit:instruction="동료 지시 편집 중 · 준비되면 지금 실행을 누르세요."
	if not notice_text.is_empty():instruction=notice_text
	elif not bool(preview.get("accepted",false)):instruction+=" · "+str(preview.get("message","주인공 행동을 먼저 지정하세요."))
	_add_notice(instruction)
	var lines:Array[String]=session.turn_summary_lines()
	if not lines.is_empty():_add_notice("이번 턴 예정\n"+"\n".join(lines),"TurnSummary",FONT_BODY)
	var has_original_suggestion:=false
	for overlay in session.turn_intent_overlays():
		if overlay.get("automatic_suggestion",null) is Dictionary:has_original_suggestion=true;break
	if has_original_suggestion:
		_add_notice("표시: 주황 실선/□ 개별 지시 · 파랑 점선/○ 원래 자동 제안","IntentLegend",FONT_AUX)
	_build_combat_action_area(status,preview)
	_selected_detail()
func _legacy_regroup_notice()->void:_add_notice("승리했습니다. 호환 상태를 자동 재집결 처리하는 중입니다.","ActionStatus",FONT_KEY)

func _build_combat_action_area(status:Dictionary,preview:Dictionary)->void:
	if str(status.safe_phase)!="ENGAGED":return
	combat_action_area.visible=true;combat_action_dock.visible=true
	if auto_orchestration_enabled:
		_build_auto_combat_action_area(status);return
	if not action_feedback_text.is_empty():action_feedback_label.text=action_feedback_text
	elif bool(preview.get("accepted",false)):action_feedback_label.text="행동 준비 완료 · 필요하면 수정한 뒤 실행하세요."
	else:action_feedback_label.text="행동 지정 → 실행\n빈 칸 이동 · 적 공격 · 선택 대기"
	var hold:=_add_button(combat_action_dock,"선택 대기","ActorHold",_on_actor_hold)
	hold.size_flags_stretch_ratio=1.0
	var clear:=_add_button(combat_action_dock,"자동 제안 복원","OverrideClear",_on_override_clear)
	clear.size_flags_stretch_ratio=1.35;clear.disabled=selected_member_id==int(status.protagonist_id)
	var confirm:=_add_button(combat_action_dock,"지금 실행","TurnConfirm",_on_turn_confirm)
	confirm.size_flags_stretch_ratio=0.9;confirm.disabled=not bool(preview.get("accepted",false))

func _build_auto_combat_action_area(status:Dictionary)->void:
	var planning:Dictionary=session.auto_combat_planning_state()
	if auto_combat_pending:
		action_feedback_label.text="최종 행동과 동료 제안을 표시 중입니다."
		combat_action_dock.visible=false;return
	if not action_feedback_text.is_empty():action_feedback_label.text=action_feedback_text
	elif bool(planning.get("placeholder",false)):action_feedback_label.text="동료 제안 준비 완료 · 주인공 행동을 선택하세요."
	elif auto_override_edit:action_feedback_label.text="개별 지시 편집 중 · 준비되면 지금 실행"
	else:action_feedback_label.text="행동 선택 시 최종 계획을 보여 준 뒤 자동 실행합니다."
	var protagonist_id:=int(status.get("protagonist_id",-1))
	var hold_text:="주인공 대기" if selected_member_id==protagonist_id else "개별 대기"
	var hold:=_add_button(combat_action_dock,hold_text,"ActorHold",_on_actor_hold);hold.size_flags_stretch_ratio=1.0
	if selected_member_id!=protagonist_id:
		var clear:=_add_button(combat_action_dock,"자동 제안 복원","OverrideClear",_on_override_clear)
		clear.size_flags_stretch_ratio=1.35
	if bool(planning.get("commit_ready",false)) and (auto_override_edit or auto_combat_fallback):
		var execute:=_add_button(combat_action_dock,"지금 실행","AutoExecute",_on_auto_execute)
		execute.size_flags_stretch_ratio=0.9

func _selected_detail()->void:
	for row in session.party_cards():
		if int(row.entity_id)!=selected_member_id:continue
		_add_notice("선택 상세 · %s · %s · %s"%[str(row.display_name),str(row.readiness),str(row.emotion.reason)],"SelectedMemberDetail",FONT_AUX)
		var action_text:="행동 미지정"
		if row.expected_action is Dictionary:
			action_text=_compact_action(row.expected_action)
			var automatic=row.expected_action.get("automatic_suggestion",null)
			if str(row.expected_action.get("source",""))=="OVERRIDE" and automatic is Dictionary:
				action_text="개별 지시: %s / 원래 제안: %s"%[_action_only(row.expected_action),_action_only(automatic)]
			action_text+=" — "+str(row.expected_action.reason)
		_add_notice(action_text,"ExpectedAction",FONT_AUX)
		return

func _select_member(member_id:int,display_name:String)->void:
	var view_mode:=str(session.party_status().get("view_mode",""))
	if auto_orchestration_enabled and view_mode=="COMBAT" \
			and member_id!=int(session.party_status().get("protagonist_id",-1)):
		_cancel_auto_pending(true);auto_override_edit=true
	selected_member_id=member_id;selected_target_id=-1;notice_text="%s 선택"%display_name
	action_feedback_text="%s 선택 · 행동을 지정하세요."%display_name
	if view_mode=="COMBAT":_clear_move_preview()
	_request_refresh()

func _on_member_card_gui_input(event:InputEvent,member_id:int,_display_name:String,button:Button)->void:
	var pressed:=false;var native_double:=false;var local_position:=Vector2.ZERO
	if event is InputEventScreenTouch:
		pressed=event.pressed;native_double=event.double_tap;local_position=event.position
	elif event is InputEventMouseButton:
		pressed=event.pressed and event.button_index==MOUSE_BUTTON_LEFT
		native_double=event.double_click;local_position=event.position
	if not pressed:return
	var pointer:={"member_id":member_id,"time_msec":Time.get_ticks_msec(),
		"global_position":button.get_global_rect().position+local_position,"native_double":native_double}
	if event is InputEventScreenTouch:
		_direct_card_touch_id=member_id;_direct_card_touch_msec=int(pointer.time_msec)
		_activate_member_card(member_id,_display_name,pointer);button.accept_event()
	else:_pending_card_pointer=pointer

func _on_member_card_pressed(member_id:int,display_name:String)->void:
	if member_id==_direct_card_touch_id and Time.get_ticks_msec()-_direct_card_touch_msec<=100:
		_direct_card_touch_id=-1;return
	var pointer:Dictionary=_pending_card_pointer.duplicate(true) if int(_pending_card_pointer.get("member_id",-1))==member_id else {}
	_pending_card_pointer.clear()
	if pointer.is_empty():
		_select_member(member_id,display_name);return
	_activate_member_card(member_id,display_name,pointer)

func _activate_member_card(member_id:int,display_name:String,pointer:Dictionary)->void:
	var now:=int(pointer.time_msec);var position:Vector2=pointer.global_position
	var repeated:=member_id==_last_card_tap_id and now-_last_card_tap_msec<=350 \
		and position.distance_to(_last_card_tap_position)<=24.0
	if bool(pointer.native_double) or repeated:
		_last_card_tap_id=-1;_last_card_tap_msec=-1000;_open_member_detail(member_id);return
	_last_card_tap_id=member_id;_last_card_tap_msec=now;_last_card_tap_position=position
	_select_member(member_id,display_name)

func _open_member_detail(member_id:int)->void:
	if auto_orchestration_enabled:_cancel_auto_pending(true)
	var detail:Dictionary=session.inspect_party_member(member_id)
	if not bool(detail.get("accepted",false)):
		notice_text=str(detail.get("message","파티원 상세 정보를 불러올 수 없습니다."));_request_refresh();return
	member_detail_title.text="%s 상세"%str(detail.get("display_name","파티원"))
	member_detail_body.text=_member_detail_text(detail)
	member_detail_scroll.scroll_vertical=0
	grid.cancel_pointer_gesture();member_detail_modal.visible=true;grid.modal_open=true
	var route_state:Dictionary=session.exploration_route_state()
	route_paused_by_modal=bool(route_state.get("active",false))
	_layout_floating_surfaces();call_deferred("_measure_member_detail_body")
	member_detail_close.grab_focus()

func _close_member_detail()->void:
	if member_detail_modal==null or not member_detail_modal.visible:return
	member_detail_modal.visible=false;grid.modal_open=false
	var resume:=route_paused_by_modal;route_paused_by_modal=false
	if resume:_schedule_route_continue()
	elif auto_orchestration_enabled:_request_refresh()

func _on_member_detail_backdrop_input(event:InputEvent)->void:
	if event is InputEventScreenTouch and event.pressed:_close_member_detail()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:_close_member_detail()

func _on_member_detail_close_input(event:InputEvent,button:Button)->void:
	if event is InputEventScreenTouch and event.pressed:
		_close_member_detail();button.accept_event()

func _unhandled_key_input(event:InputEvent)->void:
	if member_detail_modal!=null and member_detail_modal.visible and event is InputEventKey \
			and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		_close_member_detail();get_viewport().set_input_as_handled()

func _measure_member_detail_body()->void:
	if member_detail_body==null:return
	var font:Font=member_detail_body.get_theme_font("font")
	var line_height:=font.get_height(member_detail_body.get_theme_font_size("font_size"))
	member_detail_body.custom_minimum_size.y=maxf(line_height,float(member_detail_body.get_line_count())*line_height+8.0)
func _on_explore(direction:Vector2i)->void:_record_result(session.commit_exploration_direction(direction),true); _request_refresh()
func _on_restart_same_run()->void:
	if session==null or not session.has_method("restart_same_run"):
		notice_text="이 원정을 다시 시작할 수 없습니다.";_request_refresh();return
	var result:Variant=session.call("restart_same_run")
	if not result is Dictionary or not bool(result.get("accepted",false)):
		var message:="이 원정을 다시 시작할 수 없습니다." if not result is Dictionary \
			else str(result.get("message","이 원정을 다시 시작할 수 없습니다."))
		notice_text=message;action_feedback_text=message;_request_refresh();return
	_reset_run_ui_transients();_request_refresh()

func _on_restart_with_new_personality()->void:
	if session==null or not session.has_method("restart_with_personality_seed"):
		notice_text="새 성격으로 원정을 다시 시작할 수 없습니다.";_request_refresh();return
	var fresh_seed:=_issue_new_personality_seed(int(session.personality_seed))
	var result:Variant=session.call("restart_with_personality_seed",fresh_seed)
	if not result is Dictionary or not bool(result.get("accepted",false)):
		var message:="새 성격으로 원정을 다시 시작할 수 없습니다." if not result is Dictionary \
			else str(result.get("message","새 성격으로 원정을 다시 시작할 수 없습니다."))
		notice_text=message;action_feedback_text=message;_request_refresh();return
	_reset_run_ui_transients();_request_refresh()

func _reset_run_ui_transients()->void:
	_reset_auto_flow();route_generation+=1;route_continue_pending=false
	route_paused_by_modal=false;route_paused_by_pointer=false;route_preview.clear()
	_clear_move_preview();_clear_companion_follow_plan();_hide_tile_popover()
	selected_member_id=-1;selected_target_id=-1;notice_text="";action_feedback_text="";_action_feedback_phase=""
	_pending_card_pointer.clear();_last_card_tap_id=-1;_last_card_tap_msec=-1000
	_last_card_tap_position=Vector2(-10000,-10000);_direct_card_touch_id=-1;_direct_card_touch_msec=-1000
	_scroll_log_after_refresh=false;_run_locked_exit_feedback=false
	_reward_emphasis_pending=false;_run_progress_initialized=false;_observed_reward_granted=false
	if _reward_emphasis_tween!=null and _reward_emphasis_tween.is_valid():_reward_emphasis_tween.kill()
	if reward_badge!=null:reward_badge.modulate=Color.WHITE
	if member_detail_modal!=null:member_detail_modal.visible=false
	if grid!=null:
		grid.modal_open=false;grid.cancel_pointer_gesture()
		if grid.has_method("clear_transient_visuals"):grid.call("clear_transient_visuals")
		else:
			grid.clear_route_overlay();grid.clear_cursor_preview();grid.set_intent_overlays([])
			grid.set_selection(-1,-1)
	if info_scroll!=null:info_scroll.scroll_vertical=0

func _on_preset(preset:String)->void:
	if auto_orchestration_enabled:_cancel_auto_pending(true);auto_deployment_fallback=true
	var result:Dictionary=session.preview_deployment(preset,session.available_companion_ids()); notice_text="%s 대형: %s"%[{"WEDGE":"쐐기","LINE":"횡대","COLUMN":"종대"}[preset],str(result.message)]
	action_feedback_text="대형 미리보기 완료 · 배치 확정을 누르세요." if bool(result.get("accepted",false)) else str(result.get("message","배치할 수 없습니다."));_request_refresh()
func _on_deploy_confirm()->void:
	if auto_orchestration_enabled:_cancel_auto_pending(true);auto_deployment_fallback=true
	var draft:Dictionary=session.deployment_draft()
	if not bool(draft.accepted):notice_text=str(draft.message);_set_action_rejection(draft,"배치 확정 불가")
	else:_record_result(session.commit_deployment(),true)
	_request_refresh()
func _on_actor_hold()->void:
	_clear_move_preview()
	if auto_orchestration_enabled:_stage_auto_combat_action("HOLD")
	else:_record_result(session.set_actor_action(selected_member_id,"HOLD"),false,"%s 대기 불가"%_selected_name());_request_refresh()
func _on_override_clear()->void:
	_clear_move_preview()
	if auto_orchestration_enabled:
		_cancel_auto_pending(false);auto_override_edit=true
	_record_result(session.clear_companion_override(selected_member_id),false,"%s 자동 제안 복원 불가"%_selected_name());_request_refresh()
func _on_turn_confirm()->void:
	if auto_orchestration_enabled:_on_auto_execute();return
	var current:Dictionary=session.current_turn_preview()
	if not bool(current.get("accepted",false)):_record_result(current,false,"턴 확정 불가")
	else:
		_record_result(session.commit_turn(),true,"",true); _clear_move_preview()
		if session.party_status().safe_phase=="GROUPED_COMPLETE":notice_text="승리! 파티가 자동으로 재집결해 탐험을 다시 시작합니다."
		_request_refresh()

func _on_auto_execute()->void:
	var planning:Dictionary=session.auto_combat_planning_state()
	if not bool(planning.get("commit_ready",false)):
		_set_action_rejection(planning,"실행 불가");_request_refresh();return
	auto_override_edit=false;auto_combat_fallback=false
	_schedule_auto_combat_commit(planning)

func _stage_auto_combat_action(action_type:String,destination:Array=[],target_id:int=-1)->void:
	var status:Dictionary=session.party_status();var protagonist_id:=int(status.get("protagonist_id",-1))
	_cancel_auto_pending(false)
	if selected_member_id==protagonist_id:
		var action=_make_party_action(selected_member_id,action_type,destination,target_id)
		var planning:Dictionary=session.replace_auto_combat_protagonist_action(action)
		if not bool(planning.get("accepted",false)) or not bool(planning.get("commit_ready",false)):
			auto_combat_fallback=true;_set_action_rejection(planning,"%s 행동 불가"%_selected_name());_request_refresh();return
		auto_override_edit=false;auto_combat_fallback=false
		notice_text="";action_feedback_text="최종 계획을 확인했습니다."
		_schedule_auto_combat_commit(planning)
	else:
		auto_override_edit=true
		var result:Dictionary=session.set_actor_action(selected_member_id,action_type,destination,target_id)
		_record_result(result,false,"%s 개별 지시 불가"%_selected_name());_request_refresh()

func _make_party_action(actor_id:int,action_type:String,destination:Array,target_id:int):
	if action_type=="HOLD":return ActionScript.hold(actor_id)
	if action_type=="MOVE" and destination.size()==2:
		return ActionScript.move_to(actor_id,Vector2i(int(destination[0]),int(destination[1])))
	if action_type=="MELEE" and target_id>0:return ActionScript.melee(actor_id,target_id)
	return null

func _schedule_auto_combat_commit(planning:Dictionary)->void:
	var plan_hash:=str(planning.get("plan_hash",""))
	if not bool(planning.get("commit_ready",false)) or plan_hash.is_empty():
		auto_combat_fallback=true;return
	var status:Dictionary=session.party_status()
	auto_generation+=1;auto_combat_pending=true;auto_combat_fallback=false;auto_combat_render_stage=0
	auto_combat_plan_hash=plan_hash;auto_combat_step_index=int(status.get("step_index",-1))
	action_feedback_text="최종 계획 표시 · 자동 실행 대기"
	_request_refresh();call_deferred("_arm_auto_combat_preview",auto_generation)

func _arm_auto_combat_preview(expected_generation:int)->void:
	if not auto_orchestration_enabled or not auto_combat_pending or expected_generation!=auto_generation:return
	if is_inside_tree():
		get_tree().process_frame.connect(_advance_auto_combat_preview.bind(expected_generation),CONNECT_ONE_SHOT)

func _advance_auto_combat_preview(expected_generation:int)->void:
	if not auto_orchestration_enabled or not auto_combat_pending or expected_generation!=auto_generation:return
	var status:Dictionary=session.party_status()
	if str(status.get("safe_phase",""))!="ENGAGED" or member_detail_modal.visible \
			or bool(grid.pointer_gesture_state().get("active",false)):
		_cancel_auto_pending(true);_request_refresh();return
	auto_combat_render_stage=1
	if is_inside_tree():
		get_tree().process_frame.connect(_commit_auto_combat_plan.bind(expected_generation),CONNECT_ONE_SHOT)

func _commit_auto_combat_plan(expected_generation:int)->void:
	if not auto_orchestration_enabled or not auto_combat_pending or expected_generation!=auto_generation:return
	var status:Dictionary=session.party_status();var planning:Dictionary=session.auto_combat_planning_state()
	var pointer_active:=bool(grid.pointer_gesture_state().get("active",false))
	if str(status.get("safe_phase",""))!="ENGAGED" or bool(status.get("terminal",false)) \
			or int(status.get("step_index",-1))!=auto_combat_step_index or pointer_active \
			or member_detail_modal.visible or auto_override_edit \
			or not bool(planning.get("commit_ready",false)) \
			or str(planning.get("plan_hash",""))!=auto_combat_plan_hash:
		_cancel_auto_pending(true);_request_refresh();return
	auto_combat_pending=false;auto_generation+=1
	var result:Dictionary=session.commit_turn()
	if not bool(result.get("accepted",false)):auto_combat_fallback=true
	_record_result(result,true,"자동 실행 불가",true);_clear_move_preview()
	if session.party_status().safe_phase=="GROUPED_COMPLETE":notice_text="승리! 파티가 자동으로 재집결해 탐험을 다시 시작합니다."
	_refresh()

func flush_auto_flow_for_headless_test()->Dictionary:
	if auto_deployment_pending:
		if auto_deployment_render_stage==0:_advance_auto_deployment_preview(auto_generation)
		else:_commit_auto_deployment(auto_generation)
	elif auto_combat_pending:
		if auto_combat_render_stage==0:_advance_auto_combat_preview(auto_generation)
		else:_commit_auto_combat_plan(auto_generation)
	return auto_flow_state()
func _on_cell(position:Vector2i)->void:
	var status:Dictionary=session.party_status()
	_hide_tile_popover()
	var progress:=_current_run_progress()
	if bool(progress.get("terminal",false)) or bool(status.terminal):return
	if status.view_mode=="EXPLORATION":
		if _is_locked_visible_run_exit(position,progress):
			_run_locked_exit_feedback=true
			notice_text="적을 쓰러뜨리면 출구가 열립니다."
			action_feedback_text=notice_text;_request_refresh();return
		_run_locked_exit_feedback=false
		var active_state:Dictionary=session.exploration_route_state()
		var same_goal:=pending_move_mode=="EXPLORATION" and not pending_exploration_wait \
			and pending_move_destination==position and pending_move_valid and not bool(active_state.get("active",false))
		if same_goal:
			route_generation+=1;route_continue_pending=false
			var started:Dictionary=session.start_exploration_route(position,str(route_preview.get("plan_hash","")))
			_consume_route_result(started);_refresh();_schedule_route_continue()
		else:
			if bool(active_state.get("active",false)):_cancel_active_route()
			var preview:Dictionary=session.preview_exploration_route(position)
			route_preview=preview.duplicate(true);_apply_route_state(preview)
			if bool(preview.get("accepted",false)):
				notice_text="경로를 한 번 더 누르면 한 칸씩 이동합니다."
				action_feedback_text="경로 미리보기 · 같은 목적지를 한 번 더 누르세요."
			else:
				notice_text=str(preview.get("message","이 칸으로 이동할 수 없습니다."));_set_action_rejection(preview,"%s 이동 불가"%_protagonist_name())
			_update_tile_popover_route(preview);_request_refresh()
		return
	if status.view_mode!="COMBAT":return
	selected_target_id=-1;_clear_move_preview()
	var preview:Dictionary=session.preview_actor_action(selected_member_id,"MOVE",[position.x,position.y])
	if not bool(preview.get("accepted",false)):
		notice_text=str(preview.get("message","이 칸으로 이동할 수 없습니다."))
		_set_action_rejection(preview,"%s 이동 불가"%_selected_name());_request_refresh();return
	notice_text=""
	if auto_orchestration_enabled:
		_stage_auto_combat_action("MOVE",[position.x,position.y])
	else:
		_record_result(session.set_actor_action(selected_member_id,"MOVE",[position.x,position.y]),
			false,"%s 이동 불가"%_selected_name());_request_refresh()
func _on_actor(entity_id:int)->void:
	var status:Dictionary=session.party_status()
	_hide_tile_popover()
	if bool(_current_run_progress().get("terminal",false)):return
	if status.view_mode=="EXPLORATION" and entity_id!=int(status.protagonist_id) \
			and entity_id in status.party_member_ids:
		# Grouped companions are presentation-only followers during exploration.
		# Tapping their glyph must retain the map's primary navigation contract,
		# rather than selecting a logical actor that still occupies the hero anchor.
		var follower_cell:=_exploration_follower_display_position(entity_id)
		if follower_cell!=Vector2i(-1,-1):
			_on_cell(follower_cell);return
	if status.view_mode=="EXPLORATION" and entity_id==int(status.protagonist_id):
		if bool(session.exploration_route_state().get("has_preview",false)):_cancel_active_route()
		var hero_position:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
		if pending_move_mode=="EXPLORATION" and pending_exploration_wait:
			var result:Dictionary=session.commit_exploration(CommandScript.wait(entity_id)); _clear_move_preview(); _record_result(result,true)
		else:
			var preview:Dictionary=session.preview_exploration(CommandScript.wait(entity_id)); pending_move_mode="EXPLORATION"; pending_exploration_wait=true
			pending_move_actor_id=entity_id; pending_move_origin=hero_position; pending_move_destination=hero_position
			pending_move_valid=bool(preview.get("accepted",false)); pending_move_cost=int(preview.get("time_cost",0)); notice_text="현재 칸을 한 번 더 누르면 대기합니다."
			action_feedback_text="대기 미리보기 · 현재 칸을 한 번 더 누르세요." if pending_move_valid else str(preview.get("message","대기할 수 없습니다."))
		_request_refresh(); return
	if entity_id in status.visible_enemy_ids:
		selected_target_id=entity_id; _clear_move_preview()
		if status.view_mode=="COMBAT" and not bool(status.terminal):
			if auto_orchestration_enabled:_stage_auto_combat_action("MELEE",[],entity_id)
			else:_record_result(session.set_actor_action(selected_member_id,"MELEE",[],entity_id),false,"%s 공격 불가"%_selected_name())
		_request_refresh(); return
	if entity_id in status.party_member_ids:
		if auto_orchestration_enabled and status.view_mode=="COMBAT" and entity_id!=int(status.protagonist_id):
			_cancel_auto_pending(true);auto_override_edit=true
		selected_member_id=entity_id;selected_target_id=-1;notice_text="파티원을 선택했습니다."
		action_feedback_text="%s 선택 · 행동을 지정하세요."%_selected_name();_clear_move_preview();_request_refresh()

func _is_locked_visible_run_exit(position:Vector2i,progress:Dictionary)->bool:
	if not bool(progress.get("available",false)):return false
	var exit:Dictionary=progress.get("exit",{}) if progress.get("exit",{}) is Dictionary else {}
	if bool(exit.get("open",false)):return false
	var raw:Variant=progress.get("exit_position",[])
	if not raw is Array or raw.size()!=2 or position!=Vector2i(int(raw[0]),int(raw[1])):return false
	for cell in session.observe_party_world().get("cells",[]):
		if cell is Dictionary and cell.get("position",[])==[position.x,position.y]:
			return str(cell.get("visibility_state","UNSEEN"))=="VISIBLE"
	return false

func _exploration_follower_display_position(entity_id:int)->Vector2i:
	var observation:Dictionary=session.observe_party_world()
	for cell_value in observation.get("cells",[]):
		if not cell_value is Dictionary:continue
		var cell:Dictionary=cell_value
		for actor_value in cell.get("actors",[]):
			if not actor_value is Dictionary:continue
			var actor:Dictionary=actor_value
			if int(actor.get("entity_id",-1))!=entity_id \
					or str(actor.get("display_role","")).to_upper()!="FOLLOWER":continue
			var raw:Variant=actor.get("display_position",cell.get("position",[]))
			if raw is Array and raw.size()==2:return Vector2i(int(raw[0]),int(raw[1]))
	return Vector2i(-1,-1)

func _selected_name()->String:
	for row in session.party_cards():if int(row.entity_id)==selected_member_id:return str(row.display_name)
	return "파티원"
func _protagonist_name()->String:
	var protagonist_id:=int(session.party_status().get("protagonist_id",-1))
	for row in session.party_cards():
		if int(row.entity_id)==protagonist_id:return str(row.display_name)
	return "주인공"
func _action_only(action:Dictionary)->String:
	var action_type:=str(action.get("type","HOLD"))
	if action_type=="MOVE":
		var destination:Array=action.get("destination",[-1,-1])
		return "이동 (%d,%d)"%[int(destination[0]),int(destination[1])]
	if action_type=="MELEE":return "공격 %s"%str(action.get("target_name","적"))
	return "대기"
func _selected_position()->Vector2i:
	for row in session.party_cards():if int(row.entity_id)==selected_member_id:return Vector2i(int(row.logical_position[0]),int(row.logical_position[1]))
	return Vector2i(-1,-1)
func _apply_route_state(value:Dictionary)->void:
	route_preview=value.duplicate(true)
	var from_value:Variant=value.get("from",[-1,-1]);var goal_value:Variant=value.get("goal",[-1,-1])
	var from:=Vector2i(-1,-1);var goal:=Vector2i(-1,-1)
	if from_value is Array and from_value.size()==2:from=Vector2i(int(from_value[0]),int(from_value[1]))
	if goal_value is Array and goal_value.size()==2:goal=Vector2i(int(goal_value[0]),int(goal_value[1]))
	var has_preview:=bool(value.get("has_preview",false));var completed:=bool(value.get("completed",false));var terminal:=bool(value.get("terminal",false))
	pending_move_mode="EXPLORATION" if has_preview and not completed and not terminal else ""
	pending_exploration_wait=false;pending_move_actor_id=int(value.get("actor_id",-1)) if not pending_move_mode.is_empty() else -1
	pending_move_origin=from;pending_move_destination=goal;pending_move_valid=bool(value.get("accepted",false)) and has_preview
	pending_move_cost=int(value.get("total_cost",0))
	_apply_route_overlay(value)
	if pending_move_actor_id>0:grid.set_cursor_preview(pending_move_actor_id,from,goal,pending_move_valid)
	else:grid.clear_cursor_preview()

func _apply_route_overlay(value:Dictionary)->void:
	var path:Variant=value.get("path",[])
	if path is Array and path.size()>=2:
		grid.set_route_overlay(path,int(value.get("completed_steps",value.get("current_index",0))),bool(value.get("accepted",false)))
	else:grid.clear_route_overlay()

func _consume_route_result(result:Dictionary)->void:
	_apply_route_state(result)
	var effects:Variant=result.get("last_step_effects",[])
	if effects is Array and not effects.is_empty():grid.play_effects(effects)
	var message:=str(result.get("message","이동을 처리할 수 없습니다."))
	if bool(result.get("completed",false)):
		notice_text=message;action_feedback_text="목적지에 도착했습니다."
	elif bool(result.get("terminal",false)) or not bool(result.get("active",false)):
		notice_text=message;action_feedback_text=message
	else:
		notice_text=message;action_feedback_text="한 칸씩 이동 중 · %d/%d"%[int(result.get("completed_steps",0)),int(result.get("total_steps",0))]
	_update_tile_popover_route(result)

func _schedule_route_continue()->void:
	if route_continue_pending or route_paused_by_modal or route_paused_by_pointer or not is_inside_tree():return
	var state:Dictionary=session.exploration_route_state()
	if not bool(state.get("active",false)) or bool(state.get("completed",false)) or bool(state.get("terminal",false)):return
	route_continue_pending=true
	get_tree().process_frame.connect(_continue_route_on_frame.bind(route_generation),CONNECT_ONE_SHOT)

func _continue_route_on_frame(expected_generation:int)->void:
	route_continue_pending=false
	if expected_generation!=route_generation or route_paused_by_modal or route_paused_by_pointer or member_detail_modal.visible:return
	var result:Dictionary=session.continue_exploration_route()
	_consume_route_result(result);_refresh()
	if bool(result.get("active",false)) and not bool(result.get("completed",false)) and not bool(result.get("terminal",false)):
		_schedule_route_continue()

func _on_grid_pointer_started()->void:
	var cancelled_auto:=auto_orchestration_enabled and (auto_deployment_pending or auto_combat_pending)
	if cancelled_auto:
		_cancel_auto_pending(true)
		var phase:=str(session.party_status().get("safe_phase","")) if session!=null else ""
		if phase=="CONTACT":
			notice_text="자동 배치를 멈췄습니다. 대형을 직접 선택하세요."
			action_feedback_text="대형 선택 → 배치 실행"
		elif phase=="ENGAGED":
			notice_text="자동 실행을 멈췄습니다. 현재 계획을 확인하세요."
			action_feedback_text="행동 계획 확인 → 지금 실행"
		_request_refresh()
	route_paused_by_pointer=true

func _on_grid_pointer_finished(_outcome:String)->void:
	if not route_paused_by_pointer:return
	route_paused_by_pointer=false
	if not route_paused_by_modal:_schedule_route_continue()

func _cancel_active_route()->void:
	route_generation+=1;route_continue_pending=false
	var state:Dictionary=session.exploration_route_state()
	if bool(state.get("has_preview",false)):session.cancel_exploration_route()
	route_preview.clear();grid.clear_route_overlay();grid.clear_cursor_preview()
	pending_move_actor_id=-1;pending_move_origin=Vector2i(-1,-1);pending_move_destination=Vector2i(-1,-1)
	pending_move_valid=false;pending_move_mode="";pending_move_cost=0;pending_exploration_wait=false

func _clear_move_preview()->void:
	pending_move_actor_id=-1; pending_move_origin=Vector2i(-1,-1); pending_move_destination=Vector2i(-1,-1); pending_move_valid=false
	pending_move_mode=""; pending_move_cost=0; pending_exploration_wait=false
	if grid!=null:grid.clear_cursor_preview();grid.clear_route_overlay()
func _request_refresh()->void:call_deferred("_refresh")
func _record_result(result:Dictionary,consume_effects:bool=false,rejection_prefix:String="",scroll_combat_log:bool=false)->void:
	if consume_effects and bool(result.get("accepted",false)) and result.get("visual_effects",[]) is Array:
		grid.play_effects(result.get("visual_effects",[]))
	if bool(result.get("accepted",false)):
		# Only a committed live UI action may arm the reward highlight. A loaded
		# save or an arbitrary refresh synchronizes the badge without replaying it.
		if _run_progress_initialized and not _observed_reward_granted:
			var progress:=_current_run_progress()
			var reward:Dictionary=progress.get("reward",{}) if progress.get("reward",{}) is Dictionary else {}
			_reward_emphasis_pending=bool(reward.get("granted",false))
		if scroll_combat_log:_scroll_log_after_refresh=true
		notice_text="";action_feedback_text="턴이 처리되었습니다. 다음 행동을 지정하세요." if consume_effects else (
			"행동이 준비되었습니다." if auto_orchestration_enabled else "행동이 준비되었습니다. 지금 실행을 누르세요.")
	else:
		notice_text=str(result.get("message","행동을 처리할 수 없습니다."));_set_action_rejection(result,rejection_prefix)

func _set_action_rejection(result:Dictionary,prefix:String)->void:
	if auto_orchestration_enabled and (auto_deployment_pending or auto_combat_pending):_cancel_auto_pending(true)
	var message:=str(result.get("message","행동을 처리할 수 없습니다."))
	action_feedback_text=message if prefix.is_empty() else "%s: %s"%[prefix,message]

func _show_tile_inspection(position:Vector2i,status:Dictionary)->void:
	var viewer_id:=selected_member_id if selected_member_id in status.get("party_member_ids",[]) else int(status.get("protagonist_id",-1))
	var inspection:Dictionary=session.inspect_tile(position,viewer_id)
	if not bool(inspection.get("accepted",false)):_hide_tile_popover();return
	selected_tile=position;selected_tile_view_mode=str(status.get("view_mode",""));selected_tile_inspection=inspection.duplicate(true);_render_tile_popover()

func _on_tile_long_pressed(position:Vector2i)->void:
	if session==null:return
	var status:Dictionary=session.party_status()
	if not bool(status.get("ok",false)):return
	_show_tile_inspection(position,status)

func _refresh_tile_popover(status:Dictionary)->void:
	if selected_tile==Vector2i(-1,-1) or not grid.is_world_cell_visible(selected_tile):
		_hide_tile_popover();return
	var viewer_id:=selected_member_id if selected_member_id in status.get("party_member_ids",[]) else int(status.get("protagonist_id",-1))
	var inspection:Dictionary=session.inspect_tile(selected_tile,viewer_id)
	if not bool(inspection.get("accepted",false)):_hide_tile_popover();return
	selected_tile_view_mode=str(status.get("view_mode",""));selected_tile_inspection=inspection.duplicate(true);_render_tile_popover()

func _update_tile_popover_route(value:Dictionary)->void:
	if tile_popover!=null and tile_popover.visible:
		route_preview=value.duplicate(true);_render_tile_popover()

func _hide_tile_popover()->void:
	selected_tile=Vector2i(-1,-1);selected_tile_view_mode="";selected_tile_inspection.clear()
	if tile_popover!=null:tile_popover.visible=false

func _render_tile_popover()->void:
	if selected_tile_inspection.is_empty() or tile_popover==null:return
	tile_popover_label.text=_tile_popover_text(selected_tile_inspection,route_preview)
	var width:=minf(280.0,maxf(1.0,size.x-24.0))
	tile_popover_label.custom_minimum_size=Vector2(maxf(1.0,width-16.0),0)
	tile_popover_label.size.x=maxf(1.0,width-16.0)
	tile_popover.size=Vector2(width,1.0);tile_popover.visible=true
	call_deferred("_measure_tile_popover")

func _measure_tile_popover()->void:
	if tile_popover==null or not tile_popover.visible:return
	var font:Font=tile_popover_label.get_theme_font("font")
	var line_height:=font.get_height(tile_popover_label.get_theme_font_size("font_size"))
	var required_label_height:=maxf(line_height,float(tile_popover_label.get_line_count())*line_height)
	tile_popover_label.custom_minimum_size.y=required_label_height
	tile_popover.size.y=required_label_height+12.0
	_position_tile_popover()

func _position_tile_popover()->void:
	if tile_popover==null or not tile_popover.visible or not grid.is_world_cell_visible(selected_tile):return
	var cell_rect:Rect2=grid.world_cell_rect(selected_tile)
	var global_cell:=Rect2(grid.get_global_rect().position+cell_rect.position,cell_rect.size)
	var local_cell:=Rect2(global_cell.position-get_global_rect().position,global_cell.size)
	var popover_size:=tile_popover.size
	var x:=clampf(local_cell.get_center().x-popover_size.x*0.5,12.0,maxf(12.0,size.x-popover_size.x-12.0))
	var y:=local_cell.position.y-popover_size.y-8.0
	if y<12.0:y=local_cell.end.y+8.0
	y=clampf(y,12.0,maxf(12.0,size.y-popover_size.y-12.0))
	tile_popover.position=Vector2(x,y)

func _tile_popover_text(inspection:Dictionary,route:Dictionary)->String:
	var risk:Dictionary=inspection.get("risk",{}) if inspection.get("risk",{}) is Dictionary else {}
	var terrain:=str(inspection.get("terrain_label",inspection.get("terrain_id","지형")))
	var passable:="통과 가능" if bool(inspection.get("passable",false)) else "통과 불가"
	var fire:=_risk_value(risk,"fire");var water:=_risk_value(risk,"water")
	var electric:=_risk_value(risk,"electric");var poison:=_risk_value(risk,"poison")
	var total:=int(risk.get("total_risk",risk.get("total",fire+water+electric+poison)))
	var lines:Array[String]=["%s · %s · 이동 %d"%[terrain,passable,int(inspection.get("move_time_cost",0))],
		"위험  불 %d · 물 %d · 전기 %d · 독 %d"%[fire,water,electric,poison]]
	var progress:=_current_run_progress()
	var exit_raw:Variant=progress.get("exit_position",[])
	if bool(progress.get("available",false)) and exit_raw is Array and exit_raw.size()==2 \
			and selected_tile==Vector2i(int(exit_raw[0]),int(exit_raw[1])):
		var exit:Dictionary=progress.get("exit",{}) if progress.get("exit",{}) is Dictionary else {}
		lines.append("출구 · %s"%("열림" if bool(exit.get("open",false)) else "잠김"))
	if _route_goal(route)==selected_tile and not bool(route.get("accepted",false)) and not route.is_empty():
		lines.append(str(route.get("message","이 칸으로 이동할 수 없습니다.")))
	elif bool(route.get("has_preview",false)) and _route_goal(route)==selected_tile:
		var route_risk:=0
		for step in route.get("steps",[]):
			if not step is Dictionary:continue
			var ceiling:Variant=step.get("max_total_risk",0)
			if ceiling is int:route_risk=maxi(route_risk,int(ceiling))
		var route_line:="경로 %d칸 · 시간 %d · 최고 위험 %d · %d/%d"%[int(route.get("total_steps",0)),
			int(route.get("total_cost",0)),route_risk,int(route.get("completed_steps",0)),int(route.get("total_steps",0))]
		if selected_tile_view_mode=="EXPLORATION" and not bool(route.get("active",false)) and not bool(route.get("completed",false)):
			route_line+=" · 짧게 다시 눌러 이동 시작"
		lines.append(route_line)
	elif selected_tile_view_mode=="EXPLORATION":lines.append("총 위험 %d · 짧게 누르면 경로를 미리 봅니다."%total)
	elif selected_tile_view_mode=="COMBAT":lines.append("총 위험 %d · 전투 이동은 인접한 한 칸만 선택합니다."%total)
	else:lines.append("총 위험 %d · 현재 타일 정보"%total)
	return "\n".join(lines)

func _risk_value(risk:Dictionary,key:String)->int:
	return int(risk.get(key+"_score",risk.get(key,0)))

func _route_goal(value:Dictionary)->Vector2i:
	var raw:Variant=value.get("goal",[-1,-1])
	return Vector2i(int(raw[0]),int(raw[1])) if raw is Array and raw.size()==2 else Vector2i(-1,-1)

func _member_detail_text(detail:Dictionary)->String:
	var lines:Array[String]=[]
	lines.append("HP %d/%d · 스트레스 %d"%[int(detail.get("health",0)),int(detail.get("max_health",0)),int(detail.get("stress",0))])
	var ready_text:=str(detail.get("readiness","행동 준비"));var remaining:=int(detail.get("remaining_time",0))
	if remaining>0:ready_text+=" · %d 시간 남음"%remaining
	lines.append("준비: %s · 상태: %s"%[ready_text,_presence(str(detail.get("presence","GROUPED")))])
	var emotion:Dictionary=detail.get("emotion",{}) if detail.get("emotion",{}) is Dictionary else {}
	lines.append("감정: %s%s · %s"%[str(emotion.get("icon","")),str(emotion.get("label","-")),str(emotion.get("reason","이유 정보 없음"))])
	lines.append("종족/역할: %s · %s"%[_species(str(detail.get("species_id","default"))),_role(str(detail.get("role","COMPANION")))])
	var status_ids:Variant=detail.get("status_ids",[])
	lines.append("상태 효과: %s"%("없음" if not status_ids is Array or status_ids.is_empty() else ", ".join(status_ids)))
	var profile:Variant=detail.get("personality_profile",null)
	if profile is Dictionary:
		var facets:Array[String]=[]
		for row in profile.get("facet_rows",[]):
			if row is Dictionary:facets.append("%s %d"%[_facet_label(str(row.get("facet_id",""))),int(row.get("base_value",0))])
		var archetype:Dictionary=detail.get("personality_archetype",{}) if detail.get("personality_archetype",{}) is Dictionary else {}
		lines.append("성격: %s · %s"%[str(archetype.get("label","분류되지 않은 성향"))," · ".join(facets)])
	else:lines.append("성격: 주인공 직접 지휘")
	var affinity:Dictionary=detail.get("species_affinity",{}) if detail.get("species_affinity",{}) is Dictionary else {}
	lines.append("원소 친화/내성: 불 %d · 물 %d · 전기 %d · 독 %d"%[int(affinity.get("fire_tolerance",0)),
		int(affinity.get("water_tolerance",0)),int(affinity.get("electric_tolerance",0)),int(affinity.get("poison_tolerance",0))])
	var exposure:Dictionary=detail.get("current_exposure",detail.get("element_exposure",{})) if detail.get("current_exposure",detail.get("element_exposure",{})) is Dictionary else {}
	var exposure_risk:Dictionary=exposure.get("risk",exposure) if exposure.get("risk",exposure) is Dictionary else {}
	lines.append("현재 노출: 불 %d · 물 %d · 전기 %d · 독 %d · 합계 %d"%[_risk_value(exposure_risk,"fire"),_risk_value(exposure_risk,"water"),
		_risk_value(exposure_risk,"electric"),_risk_value(exposure_risk,"poison"),int(exposure_risk.get("total_risk",exposure_risk.get("total",0)))])
	var action:Variant=detail.get("expected_action",null)
	if action is Dictionary:
		lines.append("행동 제안: %s"%_compact_action(action))
		lines.append("이유: %s"%str(action.get("reason","-")))
		var original:Variant=action.get("automatic_suggestion",null)
		if original is Dictionary:lines.append("원래 자동 제안: %s"%_action_only(original))
	else:lines.append("행동 제안: 주인공 행동을 정하면 표시됩니다.")
	lines.append("관계")
	var relations:Variant=detail.get("relation_rows",[])
	if not relations is Array or relations.is_empty():lines.append("· 표시할 관계가 없습니다.")
	else:
		for relation in relations:
			if not relation is Dictionary:continue
			var other_name:=str(relation.get("display_name",relation.get("subject_name",relation.get("name","파티원"))))
			lines.append("· %s · %s · 신뢰 %d / 두려움 %d / 적대 %d / 감사 %d / 원한 %d"%[other_name,
				_disposition(str(relation.get("disposition","NEUTRAL"))),int(relation.get("trust",0)),int(relation.get("fear",0)),
				int(relation.get("hostility",0)),int(relation.get("gratitude",0)),int(relation.get("grievance",0))])
	return "\n".join(lines)

func _combat_log_text(history:Dictionary)->String:
	var lines:Array[String]=[]
	if session!=null and session.has_method("party_personality_summary"):
		var summary:Variant=session.call("party_personality_summary")
		if summary is Dictionary:
			var companion_parts:Array[String]=[]
			for row in summary.get("companion_rows",[]):
				if row is Dictionary:companion_parts.append("%s: %s"%[str(row.get("display_name","동료")),str(row.get("archetype_label","성향 미상"))])
			if not companion_parts.is_empty():lines.append("이번 원정 성향 · "+" · ".join(companion_parts))
	lines.append("전투 기록 · 최근 8턴")
	var groups:Variant=history.get("groups",[])
	if not groups is Array or groups.is_empty():
		lines.append("아직 전투 사건이 없습니다.");return "\n".join(lines)
	for group in groups:
		if not group is Dictionary:continue
		lines.append("── 턴 %d · 시간 %d→%d ──"%[int(group.get("step_index",0)),int(group.get("start_time",0)),int(group.get("end_time",0))])
		for row in group.get("rows",[]):
			if row is Dictionary:lines.append(str(row.get("message","세계에 변화가 일어났습니다.")))
	return "\n".join(lines)

func _scroll_information_to_latest_log()->void:
	if not is_inside_tree():return
	await get_tree().process_frame
	await get_tree().process_frame
	info_scroll.scroll_vertical=int(info_scroll.get_v_scroll_bar().max_value)

func _update_action_feedback(status:Dictionary)->void:
	if not action_feedback_text.is_empty():action_feedback_label.text=action_feedback_text;return
	var progress:=_current_run_progress()
	if bool(progress.get("complete",false)):
		action_feedback_label.text="원정 완료";return
	match str(status.safe_phase):
		"CONTACT":action_feedback_label.text="자동 대형 미리보기" if auto_orchestration_enabled and not auto_deployment_fallback else "대형 선택 → 배치 실행"
		"GROUPED_COMPLETE":action_feedback_label.text="승리 · 자동 재집결 완료 · 탐험 이동을 선택하세요."
		_:
			if str(status.view_mode)=="EXPLORATION":action_feedback_label.text="이동 목적지 미리보기 → 같은 칸을 한 번 더 눌러 이동"
			elif str(status.view_mode)=="COMBAT":action_feedback_label.text="행동 선택 → 자동 실행" if auto_orchestration_enabled else "행동 지정 → 실행"
			else:action_feedback_label.text="다음 행동을 선택하세요."
func _add_notice(value:String,node_name:String="ActionStatus",font_size:int=FONT_BODY)->Label:
	var label:=Label.new(); label.name=node_name; label.text=value; label.custom_minimum_size.y=44; label.add_theme_font_size_override("font_size",maxi(FONT_AUX,font_size))
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; deck.add_child(label); return label
func _add_button(parent:Control,value:String,node_name:String,callback:Callable)->Button:
	var button:=Button.new(); button.name=node_name; button.text=value; button.custom_minimum_size=Vector2(TOUCH_TARGET,TOUCH_TARGET); button.add_theme_font_size_override("font_size",FONT_BODY)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.pressed.connect(callback); parent.add_child(button); return button
func _clear_container(container:Control)->void:
	for child in container.get_children():container.remove_child(child); child.free()
func _phase(value:String)->String:return {"GROUPED":"탐험","CONTACT":"조우 배치","ENGAGED":"파티 전투","REGROUP_READY":"자동 재집결","GROUPED_COMPLETE":"탐험 재개","PARTY_DEFEATED":"패배"}.get(value,value)
func _presence(value:String)->String:return {"DEPLOYED":"배치","GROUPED":"동행","DORMANT":"대기","DEFEATED":"쓰러짐"}.get(value,value)
func _role(value:String)->String:return {"PROTAGONIST":"주인공","COMPANION":"동료"}.get(value,value)
func _species(value:String)->String:return {"human":"인간","goblin":"고블린","amphibian":"양서인","dwarf":"드워프","default":"미상"}.get(value,value)
func _facet_label(value:String)->String:return {"aggression":"공격성","altruism":"이타성","boldness":"대담성","composure":"침착성"}.get(value,value)
func _disposition(value:String)->String:return {"HOSTILE":"적대","WARY":"경계","TRUSTING":"신뢰","FRIENDLY":"우호","NEUTRAL":"중립"}.get(value,value)
func _apply_portrait_budget(combat_zoomed:bool,combat_actions_visible:bool,
		run_available:bool=false,run_terminal:bool=false,party_height:int=160)->void:
	var wide:=size.x>=450.0; phase_panel.custom_minimum_size.y=52 if wide else 48
	root_layout.add_theme_constant_override("separation",4 if wide else 2)
	combat_action_area.custom_minimum_size.y=84 if combat_actions_visible else 0
	if combat_zoomed:
		grid.custom_minimum_size=Vector2(360,360) if wide else Vector2(248,248) \
			if run_available else Vector2(300,300)
	else:
		grid.custom_minimum_size=Vector2(405,405) if wide else Vector2(276,276) \
			if run_available and (run_terminal or _run_locked_exit_feedback) \
			else (Vector2(316,316) if run_available else Vector2(348,348))
	cards.custom_minimum_size.y=maxi(0,party_height); info_scroll.custom_minimum_size.y=30

func _apply_phase_banner(status:Dictionary,presentation:Dictionary)->void:
	var contact_text:String={"NONE":"탐색 중","DETECTED":"상호 발견","PARTY_AMBUSH":"파티 선제","ENEMY_AMBUSH":"적 매복"}.get(str(status.contact_kind),"탐색 중")
	var banner:Dictionary=presentation.get("banner",{})
	var grid_style:Dictionary=presentation.get("grid_style",{})
	var tone:=str(banner.get("tone","CALM"));var title:=str(banner.get("title","탐험"));var subtitle:=str(banner.get("subtitle",""))
	var style:=StyleBoxFlat.new(); style.corner_radius_top_left=6; style.corner_radius_top_right=6; style.corner_radius_bottom_left=6; style.corner_radius_bottom_right=6
	if tone=="COMBAT":
		style.bg_color=Color("#4a2028"); style.border_color=Color(str(grid_style.get("border_hex","#ff7a80")))
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_border_width(side,2)
		phase_label.add_theme_font_size_override("font_size",FONT_BODY)
		phase_label.text="⚔ %s · %s\n시간 %d · %s"%[title,"행동 선택 → 자동 실행" if auto_orchestration_enabled else "행동 지정 → 실행",int(status.world_time),contact_text]
		phase_label.add_theme_color_override("font_color",Color("#fff0e8")); grid.set_combat_emphasis(true)
	elif tone=="VICTORY":
		style.bg_color=Color("#173c32"); style.border_color=Color(str(grid_style.get("border_hex","#62d98b")))
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_border_width(side,2)
		phase_label.add_theme_font_size_override("font_size",FONT_BODY)
		phase_label.text="%s\n%s · 시간 %d"%[title,subtitle,int(status.world_time)]
		phase_label.add_theme_color_override("font_color",Color("#dfffee")); grid.set_combat_emphasis(false)
	elif tone=="DEFEAT":
		style.bg_color=Color("#32232b");style.border_color=Color(str(grid_style.get("border_hex","#8f5367")))
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_border_width(side,2)
		phase_label.add_theme_font_size_override("font_size",FONT_BODY)
		phase_label.text="%s · 시간 %d\n%s"%[title,int(status.world_time),subtitle]
		phase_label.add_theme_color_override("font_color",Color("#f5dce8"));grid.set_combat_emphasis(true)
	else:
		style.bg_color=Color("#3b3018") if tone=="WARNING" else Color("#142434")
		style.border_color=Color(str(grid_style.get("border_hex","#334c63")))
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_border_width(side,1)
		phase_label.add_theme_font_size_override("font_size",FONT_KEY)
		phase_label.text="%s · 시간 %d · %s"%[title,int(status.world_time),contact_text]
		phase_label.add_theme_color_override("font_color",Color.WHITE); grid.set_combat_emphasis(false)
	phase_panel.add_theme_stylebox_override("panel",style)

func _camera_focus_points(observation:Dictionary,intents:Array)->Array[Vector2i]:
	var points:Array[Vector2i]=[]
	for cell in observation.get("cells",[]):
		if not cell is Dictionary or not cell.get("position") is Array or cell.position.size()!=2:continue
		if not cell.get("actors",[]).is_empty():points.append(Vector2i(int(cell.position[0]),int(cell.position[1])))
	for intent in intents:
		if not intent is Dictionary:continue
		for key in ["from_position","destination","target_position"]:
			var value=intent.get(key,[])
			if value is Array and value.size()==2 and int(value[0])>=0 and int(value[1])>=0:
				points.append(Vector2i(int(value[0]),int(value[1])))
		var automatic=intent.get("automatic_suggestion",null)
		if automatic is Dictionary:
			for key in ["from_position","destination","target_position"]:
				var value=automatic.get(key,[])
				if value is Array and value.size()==2 and int(value[0])>=0 and int(value[1])>=0:
					points.append(Vector2i(int(value[0]),int(value[1])))
	return points

func _camera_priority_points(observation:Dictionary)->Array[Vector2i]:
	var by_id:Dictionary={}
	for cell in observation.get("cells",[]):
		if not cell is Dictionary or not cell.get("position") is Array or cell.position.size()!=2:continue
		var position:=Vector2i(int(cell.position[0]),int(cell.position[1]))
		for actor in cell.get("actors",[]):
			if actor is Dictionary:by_id[int(actor.get("entity_id",-1))]=position
	var points:Array[Vector2i]=[]
	if by_id.has(selected_member_id):points.append(by_id[selected_member_id])
	if selected_target_id>0 and by_id.has(selected_target_id):points.append(by_id[selected_target_id])
	return points
