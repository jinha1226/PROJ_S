class_name PartyEncounterSandbox
extends Control

const SessionScript=preload("res://playtest/party_playtest_session.gd")
const GridScript=preload("res://playtest/party_grid_view.gd")
const MinimapScript=preload("res://playtest/party_minimap.gd")
const CommandScript=preload("res://sim/sim_command.gd")
const ActionScript=preload("res://sim/party_action_command.gd")
const PortraitScript=preload("res://playtest/ascii_actor_portrait.gd")
const AsciiFrameScript=preload("res://playtest/ascii_ui_frame.gd")
const KoreanFont:FontFile=preload("res://assets/fonts/NanumSquareR.ttf")
const DUEL_DECISION_LAB_SCENE_PATH="res://playtest/duel_decision_lab.tscn"
const ASCII_3D_LAB_SCENE=preload("res://playtest/ascii_3d_lab.tscn")
const FONT_AUX:=16
const FONT_BODY:=18
const FONT_KEY:=22
const TOUCH_TARGET:=44
const AUTO_FORMATION_ORDER:=["WEDGE","LINE","COLUMN"]

var session
var grid
var root_layout:VBoxContainer
var phase_panel:PanelContainer
var phase_row:HBoxContainer
var phase_label:Label
var run_objective_bar:PanelContainer
var run_objective_label:Label
var reward_badge:Label
var minimap
var minimap_frame
var recent_event_label:Label
var record_button:Button
var hero_detail_button:Button
var ascii_3d_lab_button:Button
var ascii_3d_lab_view:Control
var top_hud_actions:HBoxContainer
var duel_lab_button:Button
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
var member_detail_portrait
var member_detail_subtitle:Label
var member_detail_scroll:ScrollContainer
var member_detail_body:Label
var member_status_window:VBoxContainer
var member_detail_tab_row:HBoxContainer
var member_detail_status_tab:Button
var member_detail_skill_tab:Button
var member_detail_current_tab:="STATUS"
var member_detail_has_skills:=false
var member_detail_dismiss_available:=false
var member_detail_candidate_available:=false
var member_progression_window:VBoxContainer
var member_progression_xp:ProgressBar
var member_progression_xp_text:Label
var member_progression_stats:Label
var member_progression_skill_rows:Dictionary={}
var member_skill_help:Label
var member_detail_close:Button
var member_detail_dismiss:Button
var member_detail_candidate_action:Button
var member_detail_focus_buttons:HBoxContainer
var member_detail_entity_id:int=-1
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
var _narrative_log_visible:=true
var _compact_fixed_surface_active:=false

func _ready()->void:
	_build_ui()
	if not _initialized_for_headless_test and session==null:
		session=SessionScript.new(SessionScript.DEFAULT_WORLD_SEED,
			_issue_new_personality_seed(),SessionScript.SOLO_COMBAT_SCENARIO_ID)
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
	var bg:=ColorRect.new(); bg.color=Color("#071018"); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	root_layout=VBoxContainer.new(); root_layout.name="PartyLayout"; root_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layout.offset_left=6; root_layout.offset_right=-6; root_layout.offset_top=4; root_layout.offset_bottom=-4; root_layout.add_theme_constant_override("separation",4); add_child(root_layout)
	phase_panel=PanelContainer.new();phase_panel.name="TopExplorationHUD"
	phase_panel.add_theme_stylebox_override("panel",AsciiFrameScript.borderless_surface(Color("#08131ad9"),4))
	phase_panel.custom_minimum_size.y=92;root_layout.add_child(phase_panel)
	phase_row=HBoxContainer.new();phase_row.name="TopExplorationHUDRow"
	phase_row.add_theme_constant_override("separation",4);phase_panel.add_child(phase_row)
	minimap_frame=AsciiFrameScript.new();minimap_frame.name="MinimapAsciiFrame"
	minimap_frame.configure("MAP",AsciiFrameScript.CYAN,Color("#050c12e6"),true)
	minimap_frame.custom_minimum_size=Vector2(86,82);phase_row.add_child(minimap_frame)
	minimap=MinimapScript.new();minimap.name="ExplorationMinimap"
	minimap.custom_minimum_size=Vector2(76,72);minimap_frame.add_child(minimap)
	var situation_stack:=VBoxContainer.new();situation_stack.name="SituationStack"
	situation_stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	situation_stack.add_theme_constant_override("separation",1);phase_row.add_child(situation_stack)
	var situation_row:=HBoxContainer.new();situation_row.name="SituationRow"
	situation_row.add_theme_constant_override("separation",4);situation_stack.add_child(situation_row)
	phase_label=Label.new();phase_label.name="SituationStatus"
	phase_label.add_theme_font_size_override("font_size",FONT_KEY)
	phase_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	phase_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	phase_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;situation_row.add_child(phase_label)
	reward_badge=Label.new();reward_badge.name="RewardBadge";reward_badge.text="$ 1"
	reward_badge.custom_minimum_size=Vector2(42,34);reward_badge.visible=false
	reward_badge.add_theme_font_size_override("font_size",FONT_AUX)
	reward_badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	reward_badge.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var reward_style:=AsciiFrameScript.borderless_surface(Color("#0a241aa8"),4)
	reward_badge.add_theme_stylebox_override("normal",reward_style)
	reward_badge.add_theme_color_override("font_color",AsciiFrameScript.JADE)
	situation_row.add_child(reward_badge)
	recent_event_label=Label.new();recent_event_label.name="RecentWorldEvent"
	recent_event_label.add_theme_font_size_override("font_size",FONT_AUX)
	recent_event_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	recent_event_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	recent_event_label.size_flags_vertical=Control.SIZE_EXPAND_FILL
	recent_event_label.clip_text=true;situation_stack.add_child(recent_event_label)
	top_hud_actions=HBoxContainer.new();top_hud_actions.name="TopHUDActions"
	top_hud_actions.custom_minimum_size.x=168;top_hud_actions.alignment=BoxContainer.ALIGNMENT_CENTER
	top_hud_actions.add_theme_constant_override("separation",4)
	phase_row.add_child(top_hud_actions)
	record_button=Button.new();record_button.name="NarrativeLogToggle";record_button.text="≡\n기록"
	record_button.custom_minimum_size=Vector2(44,44);record_button.toggle_mode=true
	record_button.tooltip_text="하단 사건 기록 표시/숨기기"
	record_button.pressed.connect(_toggle_narrative_log);top_hud_actions.add_child(record_button)
	AsciiFrameScript.apply_rail_button(record_button,AsciiFrameScript.CYAN)
	hero_detail_button=Button.new();hero_detail_button.name="HeroDetailButton";hero_detail_button.text="@\n인물"
	hero_detail_button.custom_minimum_size=Vector2(44,44);hero_detail_button.tooltip_text="주인공 상세 정보"
	hero_detail_button.pressed.connect(_open_hero_detail);top_hud_actions.add_child(hero_detail_button)
	AsciiFrameScript.apply_rail_button(hero_detail_button,AsciiFrameScript.BRASS)
	ascii_3d_lab_button=Button.new();ascii_3d_lab_button.name="Ascii3DLabButton";ascii_3d_lab_button.text="◇\n3D"
	ascii_3d_lab_button.custom_minimum_size=Vector2(72,44);ascii_3d_lab_button.tooltip_text="저장과 무관한 3D 시각 실험"
	ascii_3d_lab_button.pressed.connect(_open_ascii_3d_lab);top_hud_actions.add_child(ascii_3d_lab_button)
	AsciiFrameScript.apply_rail_button(ascii_3d_lab_button,AsciiFrameScript.BRASS)
	# Compatibility aliases point at the unified HUD rather than preserving a
	# second objective/time strip in the product layout.
	run_objective_bar=phase_panel;run_objective_label=recent_event_label
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
	_build_duel_decision_lab_entry()
	resized.connect(_layout_floating_surfaces)

func _build_duel_decision_lab_entry()->void:
	duel_lab_button=Button.new();duel_lab_button.name="DuelDecisionLabButton"
	duel_lab_button.text="5인 관찰 실험";duel_lab_button.tooltip_text="다섯 캐릭터 판단 관찰 LAB 열기"
	duel_lab_button.add_theme_font_size_override("font_size",FONT_BODY)
	duel_lab_button.custom_minimum_size=Vector2(116,44)
	duel_lab_button.pressed.connect(_open_duel_decision_lab);duel_lab_button.visible=false
	phase_row.add_child(duel_lab_button)

func _open_duel_decision_lab()->void:
	if is_inside_tree():get_tree().change_scene_to_file(DUEL_DECISION_LAB_SCENE_PATH)

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
	var panel_style:=AsciiFrameScript.borderless_surface(Color("#07131bf7"),12)
	member_detail_panel.add_theme_stylebox_override("panel",panel_style);member_detail_modal.add_child(member_detail_panel)
	var folio_frame=AsciiFrameScript.new();folio_frame.name="MemberDetailAsciiFrame"
	folio_frame.configure("CHARACTER FOLIO",AsciiFrameScript.BRASS,Color("#00000000"),true)
	folio_frame.set_meta("major_glyph_frame",true);member_detail_panel.add_child(folio_frame)
	var stack:=VBoxContainer.new();stack.name="MemberDetailStack";stack.add_theme_constant_override("separation",8);member_detail_panel.add_child(stack)
	var header:=HBoxContainer.new();header.name="MemberDetailHeader";header.custom_minimum_size.y=76
	header.add_theme_constant_override("separation",9);stack.add_child(header)
	member_detail_portrait=PortraitScript.new();member_detail_portrait.name="MemberDetailPortrait"
	member_detail_portrait.custom_minimum_size=Vector2(66,66);member_detail_portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	header.add_child(member_detail_portrait)
	var title_stack:=VBoxContainer.new();title_stack.name="MemberDetailIdentity"
	title_stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title_stack.add_theme_constant_override("separation",0);header.add_child(title_stack)
	var folio_kicker:=Label.new();folio_kicker.name="MemberDetailKicker";folio_kicker.text="◆ 인물 기록"
	AsciiFrameScript.label_tone(folio_kicker,AsciiFrameScript.BRASS,14);title_stack.add_child(folio_kicker)
	member_detail_title=Label.new();member_detail_title.name="MemberDetailTitle";member_detail_title.add_theme_font_size_override("font_size",FONT_KEY)
	member_detail_title.add_theme_color_override("font_color",AsciiFrameScript.INK)
	member_detail_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;member_detail_title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;title_stack.add_child(member_detail_title)
	member_detail_subtitle=Label.new();member_detail_subtitle.name="MemberDetailSubtitle"
	AsciiFrameScript.label_tone(member_detail_subtitle,Color("#8ca4ae"),FONT_AUX);title_stack.add_child(member_detail_subtitle)
	member_detail_close=Button.new();member_detail_close.name="MemberDetailClose";member_detail_close.text="닫기"
	member_detail_close.custom_minimum_size=Vector2(64,TOUCH_TARGET);member_detail_close.add_theme_font_size_override("font_size",FONT_BODY)
	member_detail_close.gui_input.connect(_on_member_detail_close_input.bind(member_detail_close))
	member_detail_close.pressed.connect(_close_member_detail);header.add_child(member_detail_close)
	AsciiFrameScript.apply_rail_button(member_detail_close,AsciiFrameScript.CYAN)
	member_detail_tab_row=HBoxContainer.new();member_detail_tab_row.name="MemberDetailTabs"
	member_detail_tab_row.custom_minimum_size.y=TOUCH_TARGET;member_detail_tab_row.add_theme_constant_override("separation",6)
	stack.add_child(member_detail_tab_row)
	member_detail_status_tab=Button.new();member_detail_status_tab.name="MemberStatusTab";member_detail_status_tab.text="상태"
	member_detail_status_tab.toggle_mode=true;member_detail_status_tab.custom_minimum_size=Vector2(96,TOUCH_TARGET)
	member_detail_status_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_status_tab.tooltip_text="현재 상태와 관계 정보";member_detail_status_tab.pressed.connect(_select_member_detail_tab.bind("STATUS"))
	member_detail_tab_row.add_child(member_detail_status_tab);AsciiFrameScript.apply_rail_button(member_detail_status_tab,AsciiFrameScript.BRASS,true)
	member_detail_skill_tab=Button.new();member_detail_skill_tab.name="MemberSkillTab";member_detail_skill_tab.text="스킬"
	member_detail_skill_tab.toggle_mode=true;member_detail_skill_tab.custom_minimum_size=Vector2(96,TOUCH_TARGET)
	member_detail_skill_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_skill_tab.tooltip_text="레벨, 기술 효과와 훈련 집중";member_detail_skill_tab.pressed.connect(_select_member_detail_tab.bind("SKILL"))
	member_detail_tab_row.add_child(member_detail_skill_tab);AsciiFrameScript.apply_rail_button(member_detail_skill_tab,AsciiFrameScript.BRASS)
	member_detail_scroll=ScrollContainer.new();member_detail_scroll.name="MemberDetailScroll";member_detail_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	member_detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;stack.add_child(member_detail_scroll)
	var detail_content:=VBoxContainer.new();detail_content.name="MemberDetailContent"
	detail_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;detail_content.add_theme_constant_override("separation",8)
	member_detail_scroll.add_child(detail_content)
	_build_progression_window(detail_content)
	member_status_window=VBoxContainer.new();member_status_window.name="MemberStatusWindow"
	member_status_window.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_status_window.add_theme_constant_override("separation",8);detail_content.add_child(member_status_window)
	member_detail_body=Label.new();member_detail_body.name="MemberDetailBody";member_detail_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	member_detail_body.add_theme_font_size_override("font_size",FONT_AUX);member_detail_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_body.mouse_filter=Control.MOUSE_FILTER_IGNORE;detail_content.add_child(member_detail_body)
	member_detail_focus_buttons=HBoxContainer.new();member_detail_focus_buttons.name="TrainingFocusButtons"
	member_detail_focus_buttons.add_theme_constant_override("separation",4);member_detail_focus_buttons.visible=false
	for skill in [{"id":"MELEE","label":"근접"},{"id":"GUARD","label":"방어"},{"id":"EXPLORATION","label":"탐험"}]:
		var focus_button:=Button.new();focus_button.name="Focus%s"%str(skill.id)
		focus_button.text=str(skill.label);focus_button.custom_minimum_size=Vector2(72,TOUCH_TARGET)
		focus_button.toggle_mode=true;focus_button.set_meta("skill_id",str(skill.id))
		focus_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		focus_button.pressed.connect(_on_training_focus.bind(str(skill.id)))
		member_detail_focus_buttons.add_child(focus_button)
		AsciiFrameScript.apply_rail_button(focus_button,AsciiFrameScript.BRASS)
	stack.add_child(member_detail_focus_buttons)
	member_detail_dismiss=Button.new();member_detail_dismiss.name="MemberDetailDismiss"
	member_detail_dismiss.text="추방";member_detail_dismiss.custom_minimum_size=Vector2(120,TOUCH_TARGET)
	member_detail_dismiss.add_theme_font_size_override("font_size",FONT_BODY)
	member_detail_dismiss.pressed.connect(_on_member_detail_dismiss);member_detail_dismiss.visible=false
	stack.add_child(member_detail_dismiss);AsciiFrameScript.apply_rail_button(member_detail_dismiss,AsciiFrameScript.DANGER,false,true)
	member_detail_candidate_action=Button.new();member_detail_candidate_action.name="MemberDetailCandidateAction"
	member_detail_candidate_action.custom_minimum_size=Vector2(160,TOUCH_TARGET)
	member_detail_candidate_action.add_theme_font_size_override("font_size",FONT_BODY)
	member_detail_candidate_action.pressed.connect(_on_member_detail_candidate_action)
	member_detail_candidate_action.visible=false;stack.add_child(member_detail_candidate_action)
	AsciiFrameScript.apply_rail_button(member_detail_candidate_action,AsciiFrameScript.JADE)

func _build_progression_window(parent:VBoxContainer)->void:
	member_progression_window=VBoxContainer.new();member_progression_window.name="ProgressionWindow"
	member_progression_window.add_theme_constant_override("separation",7);member_progression_window.visible=false
	parent.add_child(member_progression_window)
	member_progression_xp_text=Label.new();member_progression_xp_text.name="ProgressionXPText"
	member_progression_xp_text.add_theme_font_size_override("font_size",FONT_KEY);member_progression_window.add_child(member_progression_xp_text)
	member_progression_xp=_bar("ProgressionXPBar",0,100,AsciiFrameScript.BRASS);member_progression_xp.custom_minimum_size.y=8
	member_progression_window.add_child(member_progression_xp)
	member_progression_stats=Label.new();member_progression_stats.name="DerivedCombatStats"
	member_progression_stats.add_theme_font_size_override("font_size",FONT_BODY);member_progression_stats.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	member_progression_window.add_child(member_progression_stats)
	member_skill_help=Label.new();member_skill_help.name="SkillFocusHelp"
	member_skill_help.text="훈련 집중 · 선택 기술 60%, 나머지 기술 20%씩\n레벨은 피해나 방어에 직접 곱해지지 않습니다."
	member_skill_help.add_theme_font_size_override("font_size",FONT_AUX);member_skill_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	member_skill_help.modulate=Color("#c6d8e5");member_progression_window.add_child(member_skill_help)
	for skill_id in ["MELEE","GUARD","EXPLORATION"]:
		var panel:=PanelContainer.new();panel.name="SkillCard%s"%skill_id
		panel.add_theme_stylebox_override("panel",AsciiFrameScript.borderless_surface(Color("#08151c99"),8))
		member_progression_window.add_child(panel)
		var row_frame=AsciiFrameScript.new();row_frame.name="SkillAsciiFrame"
		row_frame.configure("TRAINING",AsciiFrameScript.MUTED,Color("#00000000"),true)
		row_frame.set_meta("major_glyph_frame",true);panel.add_child(row_frame)
		var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",3);panel.add_child(stack)
		var skill_header:=HBoxContainer.new();skill_header.name="SkillHeader";skill_header.add_theme_constant_override("separation",8);stack.add_child(skill_header)
		var rank:=Label.new();rank.name="SkillRank";rank.custom_minimum_size.x=36
		AsciiFrameScript.label_tone(rank,AsciiFrameScript.BRASS,FONT_KEY);skill_header.add_child(rank)
		var title:=Label.new();title.name="SkillTitle";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		AsciiFrameScript.label_tone(title,AsciiFrameScript.INK,FONT_BODY);skill_header.add_child(title)
		var progress:=_bar("TrainingProgress",0,50,Color("#75c8ff"));progress.custom_minimum_size.y=11;stack.add_child(progress)
		var effect:=Label.new();effect.name="CurrentEffect";effect.add_theme_font_size_override("font_size",FONT_AUX);effect.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stack.add_child(effect)
		var future:=Label.new();future.name="FutureMilestone";future.add_theme_font_size_override("font_size",14);future.modulate=Color("#9cb0bf");future.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stack.add_child(future)
		member_progression_skill_rows[skill_id]={"panel":panel,"rank":rank,"title":title,"progress":progress,"effect":effect,"future":future}

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
	if duel_lab_button!=null:duel_lab_button.visible=not _is_solo_product_session()
	if auto_orchestration_enabled:
		_orchestrate_auto_phase(status)
		status=session.party_status()
		if str(status.get("safe_phase",""))!=auto_phase:
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
	var combat_active:=str(status.view_mode)=="COMBAT"
	var combat_actions_visible:=safe_phase=="ENGAGED" and not bool(status.terminal) \
		or run_terminal or _run_locked_exit_feedback
	var party_rows:Array=session.party_cards()
	var product_hud:=_is_solo_product_session()
	var compact_fixed_surface:=product_hud and size.x<450.0 and combat_actions_visible
	if compact_fixed_surface and not _compact_fixed_surface_active:
		_narrative_log_visible=false
	_compact_fixed_surface_active=compact_fixed_surface
	if product_hud:
		root_layout.offset_left=0;root_layout.offset_right=0
		root_layout.offset_top=0;root_layout.offset_bottom=0
	else:
		root_layout.offset_left=6;root_layout.offset_right=-6
		root_layout.offset_top=4;root_layout.offset_bottom=-4
	minimap.visible=product_hud;recent_event_label.visible=product_hud
	top_hud_actions.visible=product_hud
	var card_layout:=party_card_layout_spec(party_rows.size(),size.x)
	if compact_fixed_surface and int(card_layout.get("effective_count",0))==1:
		card_layout["party_height"]=98;card_layout["portrait_min_size"]=[88,88]
	_apply_portrait_budget(combat_active,combat_actions_visible,run_available,run_terminal,
		int(card_layout.get("party_height",160)))
	if compact_fixed_surface:
		cards.visible=not _narrative_log_visible
		info_scroll.visible=_narrative_log_visible
	else:
		cards.visible=true;info_scroll.visible=true
	if selected_member_id not in status.party_member_ids:selected_member_id=int(status.protagonist_id)
	if selected_target_id not in status.visible_enemy_ids:selected_target_id=-1
	if not pending_move_mode.is_empty() and pending_move_mode!=str(status.view_mode):_clear_move_preview()
	_apply_phase_banner(status,presentation)
	var deployment:Dictionary=session.deployment_draft()
	var ghosts:Array=deployment.placements if str(status.view_mode)=="ENCOUNTER_PREVIEW" \
		and not _is_solo_product_session() else []
	var observation:Dictionary=session.observe_party_world()
	var intent_overlays:Array=session.turn_intent_overlays() if combat_active and not run_complete else []
	grid.set_observation(observation,ghosts)
	minimap.set_observation(observation)
	if product_hud:
		var hero_position:=Vector2i(int(status.protagonist_position[0]),
			int(status.protagonist_position[1]))
		grid.set_hero_centered_view(hero_position,15,int(status.protagonist_id))
	else:grid.set_view_window(15)
	var grid_style:Dictionary=presentation.get("grid_style",{}).duplicate(true)
	if product_hud:grid_style["vignette"]=false
	grid.set_neutral_phase_map(product_hud)
	grid.set_presentation_style(grid_style)
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
			"ENCOUNTER_PREVIEW":
				if _is_solo_product_session():
					_add_notice("단독 전투를 시작합니다.","SoloCombatStarting",FONT_KEY)
					_add_button(deck,"전투 시작","SoloCombatStart",_on_solo_combat_start)
				else:_deployment_deck(deployment)
			"COMBAT":_combat_deck(status,session.current_turn_preview())
			"REGROUP":_legacy_regroup_notice()
	if run_terminal:_build_run_restart_area()
	var combat_history:Dictionary=session.combat_log(8,80)
	log_label.text=_combat_log_text(combat_history)
	log_label.visible=_narrative_log_visible
	record_button.button_pressed=_narrative_log_visible
	AsciiFrameScript.apply_rail_button(record_button,AsciiFrameScript.CYAN,_narrative_log_visible)
	_update_recent_event(combat_history,status)
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
	if not available:
		_run_progress_initialized=false;_observed_reward_granted=false
		_reward_emphasis_pending=false
		reward_badge.visible=false;return
	var reward:Dictionary=progress.get("reward",{}) if progress.get("reward",{}) is Dictionary else {}
	var granted:=bool(reward.get("granted",false))
	reward_badge.visible=granted;reward_badge.text="$ %d"%int(reward.get("amount",0))
	if _reward_emphasis_pending and granted:_play_reward_emphasis()
	_reward_emphasis_pending=false;_observed_reward_granted=granted;_run_progress_initialized=true

func _toggle_narrative_log()->void:
	_narrative_log_visible=not _narrative_log_visible
	if log_label!=null:log_label.visible=_narrative_log_visible
	if record_button!=null:
		record_button.button_pressed=_narrative_log_visible
		record_button.tooltip_text="하단 사건 기록 숨기기" if _narrative_log_visible \
			else "하단 사건 기록 표시하기"
	if _compact_fixed_surface_active:_request_refresh()

func _open_hero_detail()->void:
	if session==null:return
	var status:Dictionary=session.party_status()
	var hero_id:=int(status.get("protagonist_id",-1))
	if hero_id>0:_open_member_detail(hero_id)

func _open_ascii_3d_lab()->void:
	if ascii_3d_lab_view!=null and is_instance_valid(ascii_3d_lab_view):return
	if auto_orchestration_enabled:_cancel_auto_pending(true)
	var route_state:Dictionary=session.exploration_route_state() if session!=null else {}
	route_paused_by_modal=bool(route_state.get("active",false))
	grid.cancel_pointer_gesture();grid.modal_open=true
	ascii_3d_lab_view=ASCII_3D_LAB_SCENE.instantiate();ascii_3d_lab_view.name="Ascii3DLabOverlay"
	ascii_3d_lab_view.z_index=100;add_child(ascii_3d_lab_view)
	ascii_3d_lab_view.close_requested.connect(_close_ascii_3d_lab)

func _close_ascii_3d_lab()->void:
	if ascii_3d_lab_view==null or not is_instance_valid(ascii_3d_lab_view):return
	ascii_3d_lab_view.queue_free();ascii_3d_lab_view=null
	grid.modal_open=false
	var resume:=route_paused_by_modal;route_paused_by_modal=false
	if resume:_schedule_route_continue()
	elif auto_orchestration_enabled:_request_refresh()

func _update_recent_event(history:Dictionary,status:Dictionary)->void:
	var latest:=""
	var groups:Variant=history.get("groups",[])
	if groups is Array and not groups.is_empty():
		var last_group:Variant=groups.back()
		if last_group is Dictionary:
			var rows:Variant=last_group.get("rows",[])
			if rows is Array and not rows.is_empty() and rows.back() is Dictionary:
				latest=str(rows.back().get("message",""))
	if latest.is_empty():
		latest="위험한 기척이 느껴진다" if str(status.get("safe_phase","")) in ["CONTACT","ENGAGED"] \
			else "주변을 살피는 중"
	latest=latest.replace("다시 탐험할 수 있다","출구를 찾을 수 있다")
	latest=latest.replace("다시 탐험을 시작한다","다시 움직이기 시작한다")
	recent_event_label.text=latest.replace("\n"," ")

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
			if _is_solo_product_session():
				var result:Dictionary=session.enter_solo_combat()
				_record_result(result,true,"단독 전투 시작 불가")
			elif not auto_deployment_pending and not auto_deployment_fallback:
				_prepare_auto_deployment(status)
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
	AsciiFrameScript.apply_rail_button(button,AsciiFrameScript.BRASS,false)
	var dossier_frame=AsciiFrameScript.new();dossier_frame.name="DossierAsciiFrame"
	dossier_frame.configure("PROTAGONIST" if str(row.get("role",""))=="PROTAGONIST" else "COMPANION",
		AsciiFrameScript.BRASS if str(row.get("role",""))=="PROTAGONIST" else AsciiFrameScript.CYAN,
		Color("#07131be8"),true)
	dossier_frame.set_meta("major_glyph_frame",true);button.add_child(dossier_frame)
	dossier_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset:=MarginContainer.new(); inset.name="CardContent"; inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for margin in ["margin_left","margin_right"]:inset.add_theme_constant_override(margin,10)
	for margin in ["margin_top","margin_bottom"]:inset.add_theme_constant_override(margin,7)
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
	var portrait_frame=AsciiFrameScript.new();portrait_frame.name="PortraitGlyphFrame"
	portrait_frame.configure("@",AsciiFrameScript.BRASS,Color("#0b1a22a8"),true)
	portrait_frame.custom_minimum_size=Vector2(98,96);stack.add_child(portrait_frame)
	var portrait_view=_member_portrait(row,spec);portrait_frame.add_child(portrait_view)
	var details:=VBoxContainer.new();details.name="SpotlightDetails"
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_constant_override("separation",1)
	details.mouse_filter=Control.MOUSE_FILTER_IGNORE;stack.add_child(details)
	if str(row.get("role",""))=="COMPANION" and not speech.is_empty():
		_add_companion_speech_strip(details,speech)
	if _is_solo_product_session():
		_add_solo_spotlight_summary(details,row)
	else:
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

func _add_solo_spotlight_summary(parent:VBoxContainer,row:Dictionary)->void:
	var progression:Dictionary=row.get("progression",{}) if row.get("progression",{}) is Dictionary else {}
	var identity:=HBoxContainer.new();identity.name="SoloIdentity";identity.add_theme_constant_override("separation",6)
	identity.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(identity)
	var name_label:=_card_label(str(row.get("display_name","주인공")),"MemberName",FONT_KEY)
	name_label.add_theme_color_override("font_color",AsciiFrameScript.INK)
	name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	identity.add_child(name_label)
	var level_label:=_card_label("Lv.%d"%int(progression.get("level",1)),"LevelProgress",FONT_AUX)
	level_label.add_theme_color_override("font_color",AsciiFrameScript.BRASS)
	level_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;identity.add_child(level_label)
	var hp_current:=int(row.get("health",0));var hp_max:=maxi(1,int(row.get("max_health",1)))
	var low_hp:=hp_current*4<=hp_max
	var hp_label:=_card_label("HP  %3d / %3d"%[hp_current,hp_max],"MemberState",FONT_AUX)
	hp_label.add_theme_color_override("font_color",AsciiFrameScript.DANGER if low_hp else AsciiFrameScript.JADE)
	hp_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT;parent.add_child(hp_label)
	var health_bar:=_bar("HealthBar",hp_current,hp_max,AsciiFrameScript.JADE)
	AsciiFrameScript.apply_progress(health_bar,AsciiFrameScript.JADE,low_hp)
	health_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(health_bar)
	var tokens:Array[String]=[]
	var emotion:Dictionary=row.get("emotion",{}) if row.get("emotion",{}) is Dictionary else {}
	var emotion_text:="%s%s"%[str(emotion.get("icon","")),str(emotion.get("label",""))]
	if not emotion_text.strip_edges().is_empty():tokens.append(emotion_text)
	if str(row.get("readiness","행동 준비"))!="행동 준비":tokens.append("행동 중")
	var status_ids:Variant=row.get("status_ids",[])
	if status_ids is Array:
		for status_id in status_ids:
			if tokens.size()>=3:break
			var status_text:=str(status_id).strip_edges()
			if not status_text.is_empty():tokens.append(_status_label(status_text))
	if low_hp:tokens.push_front("! 위태")
	var state_label:=_card_label("  ".join(tokens.map(func(value):return "[%s]"%str(value))),"EmotionState",FONT_AUX)
	state_label.add_theme_color_override("font_color",AsciiFrameScript.DANGER if low_hp else Color("#9bb1bb"))
	state_label.max_lines_visible=1;state_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;parent.add_child(state_label)
	if bool(progression.get("available",false)):
		var xp_row:=HBoxContainer.new();xp_row.name="CompactXPRow";xp_row.add_theme_constant_override("separation",5)
		xp_row.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(xp_row)
		var xp_label:=_card_label("XP  %3d / %3d"%[int(progression.get("xp_current",0)),int(progression.get("xp_required",1))],"XPProgress",14)
		xp_label.add_theme_color_override("font_color",AsciiFrameScript.BRASS)
		xp_label.custom_minimum_size.x=74;xp_row.add_child(xp_label)
		var xp_bar:=_bar("CompactXPBar",int(progression.get("xp_current",0)),
			maxi(1,int(progression.get("xp_required",1))),Color("#ffd467"));xp_bar.custom_minimum_size.y=7
		xp_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;xp_bar.tooltip_text=xp_label.text;xp_row.add_child(xp_bar)

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
	var progression:Variant=row.get("progression",{})
	if _is_solo_product_session() and progression is Dictionary \
			and bool(progression.get("available",false)):
		var stats:Dictionary=progression.get("combat_stats",{}) if progression.get("combat_stats",{}) is Dictionary else {}
		var level_text:=_card_label("Lv.%d · 공 %d / 방 %d · 태세 %d%%"%[int(progression.get("level",1)),
			int(stats.get("attack_power",0)),int(stats.get("armor_flat",0)),
			int(int(stats.get("guard_reduction_milli",250))/10)],
			"LevelProgress",FONT_AUX)
		level_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;parent.add_child(level_text)
		var xp_bar:=_bar("CompactXPBar",int(progression.get("xp_current",0)),
			maxi(1,int(progression.get("xp_required",1))),Color("#ffd467"));xp_bar.custom_minimum_size.y=7
		xp_bar.tooltip_text="XP %d/%d"%[int(progression.get("xp_current",0)),int(progression.get("xp_required",1))]
		parent.add_child(xp_bar)
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
	text.text="%s\n%s"%[str(speech.get("headline","방어할게.")),
		str(speech.get("reason_summary","피해를 줄이려고"))]
	text.max_lines_visible=2;text.clip_text=true
	text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_theme_font_size_override("font_size",12)
	text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter=Control.MOUSE_FILTER_IGNORE;strip.add_child(text)

func _bar(node_name:String,value:int,maximum:int,color:Color)->ProgressBar:
	var bar:=ProgressBar.new(); bar.name=node_name; bar.min_value=0; bar.max_value=maximum; bar.value=value
	bar.show_percentage=false; bar.custom_minimum_size.y=7; bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	AsciiFrameScript.apply_progress(bar,color);return bar

func _card_label(value:String,node_name:String,font_size:int)->Label:
	var label:=Label.new(); label.name=node_name; label.text=value; label.add_theme_font_size_override("font_size",maxi(FONT_AUX,font_size)); label.mouse_filter=Control.MOUSE_FILTER_IGNORE; return label
func _compact_action(action:Dictionary)->String:
	var source:=str(action.get("source_label","자동 제안")); var action_type:=str(action.get("type","HOLD"))
	if action_type=="MOVE":var destination:Array=action.get("destination",[-1,-1]); return "%s · 이동 (%d,%d)"%[source,int(destination[0]),int(destination[1])]
	if action_type=="MELEE":return "%s · 공격 %s"%[source,str(action.get("target_name","적"))]
	return "%s · 방어"%source

func _exploration_deck()->void:
	if not _is_solo_product_session():_add_recruitment_candidates()
	_add_notice(notice_text if not notice_text.is_empty() else "탐험: 목적지를 한 번 누르면 경로를 확인하고 바로 이동합니다.")
	if pending_move_mode=="EXPLORATION":
		var actor_name:=_protagonist_name(); var summary:=""
		if pending_exploration_wait:
			summary="대표 대기: %s (%d,%d)\n현재 칸을 한 번 더 누르면 대기합니다."%[actor_name,pending_move_origin.x,pending_move_origin.y]
		else:
			summary="대표 경로: %s (%d,%d) → (%d,%d) · %d칸 · 시간 %d"%[actor_name,pending_move_origin.x,pending_move_origin.y,
				pending_move_destination.x,pending_move_destination.y,int(route_preview.get("total_steps",1)),pending_move_cost]
			summary+="\n한 칸씩 이동 중입니다." if bool(route_preview.get("active",false)) \
				else ("\n목적지를 누르면 즉시 이동합니다." if pending_move_valid else "\n"+notice_text)
		_add_notice(summary,"MovePreviewSummary",FONT_KEY)
	_selected_detail()

func _add_recruitment_candidates()->void:
	if session==null or not session.has_method("recruitable_companions"):return
	var status:Dictionary=session.party_status()
	var active_ids:Variant=status.get("party_member_ids",[])
	var exiled_ids:Variant=status.get("exiled_member_ids",[])
	var management_title:=_add_notice("동료 관리 모드 · %d/%d · 완전 이탈 %d"%[
		active_ids.size() if active_ids is Array else 0,SessionScript.ACTIVE_PARTY_LIMIT,
		exiled_ids.size() if exiled_ids is Array else 0],"RosterManagementTitle",FONT_KEY)
	var management:=VBoxContainer.new();management.name="RosterManagement"
	management.add_theme_constant_override("separation",4);deck.add_child(management)
	# The actionable rescue row gets the first scroll viewport; active companions
	# are already visible as portrait cards and remain dismissible from detail.
	deck.move_child(management,management_title.get_index())
	var candidate_rows:Variant=session.call("recruitable_companions")
	if not candidate_rows is Array or candidate_rows.is_empty():return
	for value in candidate_rows:
		if not value is Dictionary:continue
		var row:Dictionary=value
		var rescue_state:=str(row.get("rescue_state","AVAILABLE"))
		# Legacy direct-recruit fixtures remain available to core regression tests,
		# but product controls only expose the relationship-gated rescue story.
		if rescue_state=="AVAILABLE":continue
		var line:=HBoxContainer.new();line.name="RecruitCandidate%d"%int(row.get("entity_id",-1))
		line.custom_minimum_size.y=60;line.add_theme_constant_override("separation",6);management.add_child(line)
		var label:=Label.new();label.name="RecruitCandidateLabel";label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size",FONT_AUX);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		if rescue_state=="COLLAPSED_STORY":
			label.text="%s · 쓰러짐(사망 아님)\n한 턴 안정화"%str(row.get("display_name","동료"))
		elif bool(row.get("decision_available",false)):
			var recruitment:Dictionary=row.get("recruitment",{}) if row.get("recruitment",{}) is Dictionary else {}
			label.text="%s · 영입 수락 %d%%\n%s"%[str(row.get("display_name","동료")),
				int(recruitment.get("probability_percent",0)),_recruitment_reason_summary(recruitment)]
		else:
			label.text="영입 후보 · %s · %s"%[str(row.get("display_name","동료")),str(row.get("archetype_label","동료"))]
		label.tooltip_text=str(row.get("message",""));label.mouse_filter=Control.MOUSE_FILTER_IGNORE;line.add_child(label)
		if rescue_state=="COLLAPSED_STORY":
			var stabilize:=_add_button(line,"안정화","StabilizeMember%d"%int(row.get("entity_id",-1)),
				_on_stabilize_candidate.bind(int(row.get("entity_id",-1))))
			stabilize.custom_minimum_size=Vector2(84,TOUCH_TARGET)
			stabilize.size_flags_horizontal=Control.SIZE_SHRINK_END
			stabilize.disabled=not bool(row.get("can_stabilize",false))
			stabilize.tooltip_text=str(row.get("stabilization",{}).get("message",row.get("message","")))
		else:
			var recruit_text:="제안" if bool(row.get("decision_available",false)) else "영입"
			var recruit:=_add_button(line,recruit_text,"RecruitMember%d"%int(row.get("entity_id",-1)),
				_on_recruit_companion.bind(int(row.get("entity_id",-1))))
			recruit.custom_minimum_size=Vector2(72,TOUCH_TARGET);recruit.disabled=not bool(row.get("can_recruit",false))
			recruit.size_flags_horizontal=Control.SIZE_SHRINK_END
			recruit.tooltip_text=str(row.get("message",""))

func _run_complete_deck(progress:Dictionary)->void:
	var reward:Dictionary=progress.get("reward",{}) if progress.get("reward",{}) is Dictionary else {}
	_add_notice("원정 완료 · 고블린을 쓰러뜨리고 출구에 도달했습니다.\n보상 $ %d"%int(reward.get("amount",1)),
		"RunCompleteSummary",FONT_KEY)
	_selected_detail()

func _build_run_restart_area()->void:
	combat_action_area.visible=true;combat_action_area.custom_minimum_size.y=TOUCH_TARGET
	action_feedback_label.visible=false;combat_action_dock.visible=true
	var restart:=_add_button(combat_action_dock,
		"같은 원정 다시 시작" if _is_solo_product_session() else "새 성격으로 다시 시작",
		"RestartSameRun",_on_restart_same_run if _is_solo_product_session() \
		else _on_restart_with_new_personality)
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
	if bool(status.terminal):
		_add_notice("주인공이 쓰러져 더 행동할 수 없습니다." if _is_solo_product_session() \
			else "파티가 패배했습니다. 주인공이 쓰러져 더 행동할 수 없습니다.","TerminalOverlay",FONT_KEY)
		return
	var actor_name:=_selected_name(); var instruction:="%s 선택 · 빈 칸 이동 · 적 공격 · 하단 방어"%actor_name
	if auto_orchestration_enabled:
		var planning:Dictionary=session.auto_combat_planning_state()
		if bool(planning.get("placeholder",false)):
			instruction="주인공의 행동을 선택하세요 · 공격할 적이나 이동할 칸을 누를 수 있습니다." \
				if _is_solo_product_session() else "동료 제안이 준비되었습니다 · 주인공의 실제 행동을 선택하세요."
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
	var guard_percent:=_guard_percent_for_actor(selected_member_id)
	if not action_feedback_text.is_empty():action_feedback_label.text=action_feedback_text
	elif bool(preview.get("accepted",false)):action_feedback_label.text="행동 준비 완료 · 필요하면 수정한 뒤 실행하세요."
	else:action_feedback_label.text="행동 지정 → 실행\n빈 칸 이동 · 적 공격 · 방어(200시간·피해 %d%% 감소)"%guard_percent
	var hold:=_add_button(combat_action_dock,"방어","ActorHold",_on_actor_hold)
	hold.tooltip_text="200 시간 동안 물리 피해를 %d%% 줄입니다."%guard_percent
	hold.size_flags_stretch_ratio=1.0
	var clear:=_add_button(combat_action_dock,"자동 제안 복원","OverrideClear",_on_override_clear)
	clear.size_flags_stretch_ratio=1.35;clear.disabled=selected_member_id==int(status.protagonist_id)
	var confirm:=_add_button(combat_action_dock,"지금 실행","TurnConfirm",_on_turn_confirm)
	confirm.size_flags_stretch_ratio=0.9;confirm.disabled=not bool(preview.get("accepted",false))

func _build_auto_combat_action_area(status:Dictionary)->void:
	var planning:Dictionary=session.auto_combat_planning_state()
	var guard_percent:=_guard_percent_for_actor(selected_member_id)
	if auto_combat_pending:
		action_feedback_label.text="최종 행동을 표시 중입니다." if _is_solo_product_session() \
			else "최종 행동과 동료 제안을 표시 중입니다."
		combat_action_dock.visible=false;return
	if not action_feedback_text.is_empty():action_feedback_label.text=action_feedback_text
	elif bool(planning.get("placeholder",false)):
		action_feedback_label.text="행동 선택 · 방어: 200시간 동안 물리 피해 %d%% 감소"%guard_percent \
			if _is_solo_product_session() else "동료 제안 준비 완료 · 주인공 행동을 선택하세요."
	elif auto_override_edit:action_feedback_label.text="개별 지시 편집 중 · 준비되면 지금 실행"
	else:action_feedback_label.text="행동 선택 시 최종 계획을 보여 준 뒤 자동 실행합니다."
	var protagonist_id:=int(status.get("protagonist_id",-1))
	var hold_text:="주인공 방어" if selected_member_id==protagonist_id else "개별 방어"
	var hold:=_add_button(combat_action_dock,hold_text,"ActorHold",_on_actor_hold);hold.size_flags_stretch_ratio=1.0
	hold.tooltip_text="200 시간 동안 물리 피해를 %d%% 줄입니다."%guard_percent
	if selected_member_id!=protagonist_id:
		var clear:=_add_button(combat_action_dock,"자동 제안 복원","OverrideClear",_on_override_clear)
		clear.size_flags_stretch_ratio=1.35
	if bool(planning.get("commit_ready",false)) and (auto_override_edit or auto_combat_fallback):
		var execute:=_add_button(combat_action_dock,"지금 실행","AutoExecute",_on_auto_execute)
		execute.size_flags_stretch_ratio=0.9

func _guard_percent_for_actor(actor_id:int)->int:
	if session==null:return 25
	var status:Dictionary=session.party_status()
	if actor_id!=int(status.get("protagonist_id",-1)):return 25
	var progression:Dictionary=session.protagonist_progression()
	var stats:Variant=progression.get("combat_stats",{})
	return int(int(stats.get("guard_reduction_milli",250))/10) if stats is Dictionary else 25

func _selected_detail()->void:
	if selected_target_id>0:
		var enemy:Dictionary=session.inspect_enemy(selected_target_id)
		if bool(enemy.get("accepted",false)):
			_add_notice("적 정보 · %s · 레벨 %d · %s · HP %d/%d\n기준: 전투 프로필과 최대 HP에서 도출"%[
				str(enemy.get("display_name","적")),int(enemy.get("level",1)),
				str(enemy.get("threat_label","대등")),int(enemy.get("health",0)),
				int(enemy.get("max_health",0))],"EnemyInspector",FONT_AUX)
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

func _update_member_status_window(detail:Dictionary)->void:
	_clear_container(member_status_window)
	var identity_panel:=PanelContainer.new();identity_panel.name="StatusIdentityPanel"
	identity_panel.add_theme_stylebox_override("panel",AsciiFrameScript.borderless_surface(Color("#08151ca8"),8))
	member_status_window.add_child(identity_panel)
	var identity_frame=AsciiFrameScript.new();identity_frame.name="StatusIdentityAsciiFrame"
	identity_frame.configure("VITAL DOSSIER",AsciiFrameScript.BRASS,Color("#00000000"),true)
	identity_frame.set_meta("major_glyph_frame",true);identity_panel.add_child(identity_frame)
	var identity:=HBoxContainer.new();identity.name="StatusIdentity";identity.add_theme_constant_override("separation",10)
	identity_panel.add_child(identity)
	var portrait=PortraitScript.new();portrait.name="StatusPortrait"
	portrait.custom_minimum_size=Vector2(108,112);portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var portrait_actor:Dictionary=detail.duplicate(true)
	portrait_actor["is_protagonist"]=str(detail.get("role",""))=="PROTAGONIST"
	portrait_actor["faction_id"]="party";portrait.set_actor(portrait_actor);identity.add_child(portrait)
	var facts:=VBoxContainer.new();facts.name="StatusIdentityFacts";facts.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	facts.add_theme_constant_override("separation",4);identity.add_child(facts)
	var name_label:=_card_label(str(detail.get("display_name","파티원")),"StatusName",FONT_KEY)
	name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;facts.add_child(name_label)
	var progression:Dictionary=detail.get("progression",{}) if detail.get("progression",{}) is Dictionary else {}
	var identity_parts:Array[String]=[_species(str(detail.get("species_id","default")))]
	if bool(progression.get("available",false)):identity_parts.append("Lv.%d"%int(progression.get("level",1)))
	var species_level:=_card_label(" · ".join(identity_parts),"StatusSpeciesLevel",FONT_BODY);facts.add_child(species_level)
	var life_parts:Array[String]=[_life_state_label(str(detail.get("life_state","ACTIVE")))]
	var presence:=str(detail.get("presence","GROUPED"))
	if presence not in ["", "GROUPED"]:life_parts.append(_presence(presence))
	var life_label:=_card_label(" · ".join(life_parts),"StatusLife",FONT_AUX);facts.add_child(life_label)
	var hp_label:=_card_label("HP %d/%d"%[int(detail.get("health",0)),int(detail.get("max_health",0))],"StatusHP",FONT_BODY)
	facts.add_child(hp_label)
	var health_bar:=_bar("StatusHealthBar",int(detail.get("health",0)),maxi(1,int(detail.get("max_health",1))),Color("#62d98b"))
	health_bar.custom_minimum_size.y=10;health_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;facts.add_child(health_bar)
	var status_grid:=GridContainer.new();status_grid.name="StatusFolioGrid"
	status_grid.columns=2 if size.x>=540.0 else 1;status_grid.add_theme_constant_override("h_separation",14)
	status_grid.add_theme_constant_override("v_separation",8);member_status_window.add_child(status_grid)
	var emotion_cluster:=VBoxContainer.new();emotion_cluster.name="EmotionSealCluster"
	emotion_cluster.size_flags_horizontal=Control.SIZE_EXPAND_FILL;emotion_cluster.add_theme_constant_override("separation",3)
	status_grid.add_child(emotion_cluster)
	var emotion_heading:=_card_label("◆ 감정 · 스트레스  ─────","EmotionSection",14)
	emotion_heading.add_theme_color_override("font_color",AsciiFrameScript.BRASS);emotion_cluster.add_child(emotion_heading)
	var emotion:Dictionary=detail.get("emotion",{}) if detail.get("emotion",{}) is Dictionary else {}
	var emotion_label:=_card_label("[%s%s]"%[str(emotion.get("icon","")),str(emotion.get("label","감정 정보 없음"))],"StatusEmotion",FONT_BODY)
	emotion_label.add_theme_color_override("font_color",AsciiFrameScript.INK);emotion_cluster.add_child(emotion_label)
	var reason:=str(emotion.get("reason","")).strip_edges()
	if not reason.is_empty() and reason!="이유 정보 없음":
		var reason_label:=_card_label(reason,"StatusEmotionReason",FONT_AUX);reason_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		reason_label.modulate=Color("#8fa5ae");emotion_cluster.add_child(reason_label)
	var stress:=int(detail.get("stress",0))
	var stress_label:=_card_label("STRESS  %4d / 1000"%stress,"StatusStress",FONT_AUX);emotion_cluster.add_child(stress_label)
	if stress>0:
		var stress_bar:=_bar("StatusStressBar",stress,1000,Color("#d58a55"));stress_bar.custom_minimum_size.y=7
		emotion_cluster.add_child(stress_bar)
	var combat_cluster:=VBoxContainer.new();combat_cluster.name="CombatSealCluster"
	combat_cluster.size_flags_horizontal=Control.SIZE_EXPAND_FILL;combat_cluster.add_theme_constant_override("separation",3)
	status_grid.add_child(combat_cluster)
	var combat_heading:=_card_label("◆ 전투 · 상태  ─────────","CombatSection",14)
	combat_heading.add_theme_color_override("font_color",AsciiFrameScript.CYAN);combat_cluster.add_child(combat_heading)
	var status_ids:Variant=detail.get("status_ids",[])
	if status_ids is Array and not status_ids.is_empty():
		var status_labels:Array[String]=[]
		for status_id in status_ids:status_labels.append(_status_label(str(status_id)))
		var statuses:=_card_label(" ".join(status_labels.map(func(value):return "[%s]"%str(value))),"StatusEffects",FONT_AUX)
		statuses.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;combat_cluster.add_child(statuses)
	else:
		var clear_status:=_card_label("[이상 없음]","StatusEffects",FONT_AUX)
		clear_status.add_theme_color_override("font_color",AsciiFrameScript.JADE);combat_cluster.add_child(clear_status)
	var stats:Dictionary=progression.get("combat_stats",{}) if progression.get("combat_stats",{}) is Dictionary else {}
	if not stats.is_empty():
		var combat:=_card_label("공격 %d  ·  방어 %d\n방어 태세 %d%%"%[
			int(stats.get("attack_power",0)),int(stats.get("armor_flat",0)),
			int(int(stats.get("guard_reduction_milli",250))/10)],"StatusCombatSummary",FONT_AUX)
		combat.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;combat_cluster.add_child(combat)

func _life_state_label(life_state:String)->String:
	match life_state:
		"DOWNED":return "쓰러짐"
		"DEAD":return "사망"
		_:return "생존"

func _status_label(status_id:String)->String:
	return {"BLEEDING":"출혈","POISONED":"중독","WET":"젖음","GUARDED":"방어 태세"}.get(status_id,status_id)

func _open_member_detail(member_id:int)->void:
	if auto_orchestration_enabled:_cancel_auto_pending(true)
	var detail:Dictionary=session.inspect_party_member(member_id)
	if not bool(detail.get("accepted",false)):
		notice_text=str(detail.get("message","파티원 상세 정보를 불러올 수 없습니다."));_request_refresh();return
	member_detail_title.text=str(detail.get("display_name","파티원"))
	var detail_progression:Dictionary=detail.get("progression",{}) if detail.get("progression",{}) is Dictionary else {}
	var subtitle_parts:Array[String]=[_species(str(detail.get("species_id","default"))),_role(str(detail.get("role","")))]
	if bool(detail_progression.get("available",false)):subtitle_parts.append("LV %02d"%int(detail_progression.get("level",1)))
	member_detail_subtitle.text=" · ".join(subtitle_parts)
	var header_actor:Dictionary=detail.duplicate(true)
	header_actor["is_protagonist"]=str(detail.get("role",""))=="PROTAGONIST";header_actor["faction_id"]="party"
	member_detail_portrait.set_actor(header_actor)
	member_detail_body.text=_member_detail_text(detail)
	_update_member_status_window(detail)
	member_detail_entity_id=member_id
	var progression:Variant=detail.get("progression",{})
	member_detail_has_skills=progression is Dictionary and bool(progression.get("available",false))
	member_detail_current_tab="STATUS"
	_update_progression_window(progression)
	var can_show_dismiss:=str(detail.get("role",""))=="COMPANION" \
		and bool(detail.get("active_party_member",false))
	member_detail_dismiss_available=can_show_dismiss
	if can_show_dismiss:
		var assessment:Dictionary=session.roster_change_assessment("DISMISS",member_id)
		member_detail_dismiss.disabled=not bool(assessment.get("accepted",false))
		member_detail_dismiss.tooltip_text=str(assessment.get("message",""))
	var can_show_candidate:=bool(detail.get("recruitable_member",false))
	member_detail_candidate_available=can_show_candidate
	if can_show_candidate:
		_configure_candidate_detail_action(detail)
	_apply_member_detail_tab()
	member_detail_scroll.scroll_vertical=0
	grid.cancel_pointer_gesture();member_detail_modal.visible=true;grid.modal_open=true
	var route_state:Dictionary=session.exploration_route_state()
	route_paused_by_modal=bool(route_state.get("active",false))
	_layout_floating_surfaces();call_deferred("_measure_member_detail_body")
	if member_detail_close.is_inside_tree():member_detail_close.grab_focus()

func _close_member_detail()->void:
	if member_detail_modal==null or not member_detail_modal.visible:return
	member_detail_modal.visible=false;member_detail_entity_id=-1;grid.modal_open=false
	var resume:=route_paused_by_modal;route_paused_by_modal=false
	if resume:_schedule_route_continue()
	elif auto_orchestration_enabled:_request_refresh()

func _select_member_detail_tab(tab_id:String)->void:
	if tab_id not in ["STATUS","SKILL"] or tab_id=="SKILL" and not member_detail_has_skills:return
	member_detail_current_tab=tab_id;member_detail_scroll.scroll_vertical=0
	_apply_member_detail_tab()

func _apply_member_detail_tab()->void:
	var skill_selected:=member_detail_has_skills and member_detail_current_tab=="SKILL"
	member_detail_tab_row.visible=member_detail_has_skills
	member_detail_status_tab.set_pressed_no_signal(not skill_selected)
	member_detail_skill_tab.set_pressed_no_signal(skill_selected)
	member_detail_status_tab.text="━ 상태 ━" if not skill_selected else "  상태  "
	member_detail_skill_tab.text="━ 스킬 ━" if skill_selected else "  스킬  "
	AsciiFrameScript.apply_rail_button(member_detail_status_tab,AsciiFrameScript.BRASS,not skill_selected)
	AsciiFrameScript.apply_rail_button(member_detail_skill_tab,AsciiFrameScript.BRASS,skill_selected)
	member_status_window.visible=not skill_selected
	member_detail_body.visible=not skill_selected
	member_progression_window.visible=skill_selected
	member_detail_focus_buttons.visible=skill_selected
	member_detail_dismiss.visible=not skill_selected and member_detail_dismiss_available
	member_detail_candidate_action.visible=not skill_selected and member_detail_candidate_available

func _on_training_focus(skill_id:String)->void:
	if member_detail_entity_id<=0:return
	var result:Dictionary=session.set_training_focus(skill_id)
	if not bool(result.get("accepted",false)) and str(result.get("reason",""))!="training_focus_unchanged":
		notice_text=str(result.get("message","훈련 집중을 변경할 수 없습니다."));return
	var detail:Dictionary=session.inspect_party_member(member_detail_entity_id)
	member_detail_body.text=_member_detail_text(detail)
	_update_member_status_window(detail)
	_update_progression_window(detail.get("progression",{}))
	member_detail_current_tab="SKILL";_apply_member_detail_tab()
	notice_text="훈련 집중을 변경했습니다.";_request_refresh()

func _update_progression_window(progression:Variant)->void:
	var available:=progression is Dictionary and bool(progression.get("available",false))
	if not available:return
	member_progression_xp_text.text="Lv.%d  ·  XP %d / %d\n누적 %d  →  다음 %d"%[int(progression.get("level",1)),
		int(progression.get("xp_current",0)),int(progression.get("xp_required",1)),
		int(progression.get("xp_total",0)),int(progression.get("next_level_threshold",0))]
	member_progression_xp.max_value=maxi(1,int(progression.get("xp_required",1)))
	member_progression_xp.value=int(progression.get("xp_current",0))
	var stats:Dictionary=progression.get("combat_stats",{}) if progression.get("combat_stats",{}) is Dictionary else {}
	member_progression_stats.text="현재 전투 능력\n공격력 %d   방어력 %d   방어 태세 %d%% · %d시간"%[
		int(stats.get("attack_power",0)),int(stats.get("armor_flat",0)),
		int(int(stats.get("guard_reduction_milli",250))/10),int(stats.get("guard_duration",200))]
	for skill_value in progression.get("skills",[]):
		if not skill_value is Dictionary:continue
		var skill:Dictionary=skill_value;var skill_id:=str(skill.get("skill_id",""))
		if not member_progression_skill_rows.has(skill_id):continue
		var row:Dictionary=member_progression_skill_rows[skill_id]
		(row.rank as Label).text="R%02d"%int(skill.get("rank",0))
		(row.title as Label).text="%s   ·   집중 %d%%"%[str(skill.get("label","기술")),int(skill.get("focus",0))]
		var progress:=row.progress as ProgressBar
		progress.max_value=maxi(1,int(skill.get("training_required",1)));progress.value=int(skill.get("training_current",0))
		progress.tooltip_text="훈련 %d/%d"%[int(skill.get("training_current",0)),int(skill.get("training_required",1))]
		(row.effect as Label).text="현재 · %s"%str(skill.get("effect_label",""))
		var milestone:Dictionary=skill.get("next_milestone",{}) if skill.get("next_milestone",{}) is Dictionary else {}
		(row.future as Label).text="미래 · R%d %s (미구현)"%[int(milestone.get("rank",0)),str(milestone.get("label","후속 기술"))]
	var dominant_focus_id:="";var dominant_focus_value:=-1
	for skill_value in progression.get("skills",[]):
		if skill_value is Dictionary and int(skill_value.get("focus",0))>dominant_focus_value:
			dominant_focus_value=int(skill_value.get("focus",0));dominant_focus_id=str(skill_value.get("skill_id",""))
	for child in member_detail_focus_buttons.get_children():
		if child is Button:
			var focus_id:=str(child.get_meta("skill_id",""));var selected:=focus_id==dominant_focus_id
			child.set_pressed_no_signal(selected)
			child.text=("[◆ %s]" if selected else "  ◇ %s  ")%{"MELEE":"근접","GUARD":"방어","EXPLORATION":"탐험"}.get(focus_id,focus_id)
			AsciiFrameScript.apply_rail_button(child,AsciiFrameScript.BRASS,selected)

func _on_member_detail_backdrop_input(event:InputEvent)->void:
	if event is InputEventScreenTouch and event.pressed:_close_member_detail()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:_close_member_detail()

func _on_member_detail_close_input(event:InputEvent,button:Button)->void:
	if event is InputEventScreenTouch and event.pressed:
		_close_member_detail();button.accept_event()

func _on_member_detail_dismiss()->void:
	if member_detail_entity_id<=0:return
	var result:Dictionary=session.dismiss_companion(member_detail_entity_id)
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","추방할 수 없습니다."));action_feedback_text=notice_text
		var assessment:Dictionary=session.roster_change_assessment("DISMISS",member_detail_entity_id)
		member_detail_dismiss.disabled=true;member_detail_dismiss.tooltip_text=str(assessment.get("message",notice_text));return
	_clear_roster_change_transients();_close_member_detail()
	selected_member_id=int(session.party_status().protagonist_id)
	notice_text="동료를 파티에서 추방했습니다.";action_feedback_text=notice_text
	_cancel_auto_pending(true);_request_refresh()

func _configure_candidate_detail_action(detail:Dictionary)->void:
	var story_state:=str(detail.get("rescue_story_state",""))
	if story_state=="COLLAPSED_STORY":
		var rescue:Dictionary=detail.get("rescue_assessment",{}) if detail.get("rescue_assessment",{}) is Dictionary else {}
		member_detail_candidate_action.text="상처 안정화 · %d 시간"%int(rescue.get("time_cost",0))
		member_detail_candidate_action.disabled=not bool(rescue.get("accepted",false))
		member_detail_candidate_action.tooltip_text=str(rescue.get("message","쓰러진 인물 곁에서 도울 수 있습니다."));return
	var recruitment:Dictionary=detail.get("recruitment_assessment",{}) if detail.get("recruitment_assessment",{}) is Dictionary else {}
	if not recruitment.is_empty():
		member_detail_candidate_action.text="영입 제안 · 수락 %d%%"%int(recruitment.get("probability_percent",0))
		member_detail_candidate_action.disabled=not bool(recruitment.get("accepted",false))
		member_detail_candidate_action.tooltip_text=_recruitment_reason_summary(recruitment);return
	member_detail_candidate_action.text="영입 제안 불가"
	member_detail_candidate_action.disabled=true
	member_detail_candidate_action.tooltip_text="먼저 구조와 안정화를 완료해야 합니다."

func _on_member_detail_candidate_action()->void:
	if member_detail_entity_id<=0:return
	var detail:Dictionary=session.inspect_party_member(member_detail_entity_id)
	var result:Dictionary
	if str(detail.get("rescue_story_state",""))=="COLLAPSED_STORY":
		result=session.stabilize_recruit_candidate(member_detail_entity_id)
	else:
		result=session.offer_recruitment(member_detail_entity_id)
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","처리할 수 없습니다."));action_feedback_text=notice_text
		_open_member_detail(member_detail_entity_id);_request_refresh();return
	_clear_roster_change_transients();_close_member_detail()
	if bool(result.get("joined",false)):
		notice_text="영입 제안을 받아들여 새 동료가 합류했습니다."
	elif bool(result.get("resolved",false)):
		notice_text="영입 제안을 거절했습니다. 사건 기록에 이유와 판정을 남겼습니다."
	else:
		notice_text="상처를 안정화했습니다. 이제 영입 가능성을 확인할 수 있습니다."
	action_feedback_text=notice_text;_cancel_auto_pending(true);_request_refresh()

func _on_recruit_companion(entity_id:int)->void:
	var result:Dictionary=session.offer_recruitment(entity_id)
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","영입할 수 없습니다."));action_feedback_text=notice_text
	else:
		notice_text="새 동료가 파티에 합류했습니다." if bool(result.get("joined",true)) \
			else "영입 제안을 거절했습니다. 판정과 이유를 사건 기록에 남겼습니다."
		action_feedback_text=notice_text
		_clear_roster_change_transients()
	_cancel_auto_pending(true);_request_refresh()

func _on_stabilize_candidate(entity_id:int)->void:
	var result:Dictionary=session.stabilize_recruit_candidate(entity_id)
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","안정화할 수 없습니다."))
	else:
		notice_text="상처를 안정화했습니다. 수락 가능성과 판단 근거가 공개되었습니다."
		_clear_roster_change_transients()
	action_feedback_text=notice_text;_cancel_auto_pending(true);_request_refresh()

func _on_quick_dismiss_companion(entity_id:int)->void:
	var result:Dictionary=session.dismiss_companion(entity_id)
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","추방할 수 없습니다."))
	else:
		notice_text="동료가 파티에서 완전히 이탈했습니다."
		selected_member_id=int(session.party_status().protagonist_id)
		_clear_roster_change_transients()
	action_feedback_text=notice_text;_cancel_auto_pending(true);_request_refresh()

func _recruitment_reason_summary(assessment:Dictionary)->String:
	var parts:Array[String]=[]
	for row in assessment.get("reasons",[]):
		if row is Dictionary:
			parts.append(str({"SPECIES_AFFINITY":"종족 호감","SPECIES_DISTRUST":"종족 경계",
				"SPECIES_WARY":"종족 차이","RESCUED":"구조를 기억함",
				"PERSONAL_AFFECTION":"개인적 감사","SURVIVAL_THREAT":"생존이 절실함"}
				.get(str(row.get("code","")),row.get("label",""))))
		if parts.size()>=2:break
	return " · ".join(parts) if not parts.is_empty() else str(assessment.get("message",""))

func _clear_roster_change_transients()->void:
	route_generation+=1;route_continue_pending=false
	route_paused_by_modal=false;route_paused_by_pointer=false;route_preview.clear()
	_clear_move_preview();_clear_companion_follow_plan()
	if grid!=null:
		grid.clear_route_overlay();grid.clear_cursor_preview();grid.cancel_pointer_gesture()

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
func _on_solo_combat_start()->void:
	var result:Dictionary=session.enter_solo_combat()
	_record_result(result,true,"단독 전투 시작 불가");_request_refresh()
func _on_actor_hold()->void:
	_clear_move_preview()
	if auto_orchestration_enabled:_stage_auto_combat_action("HOLD")
	else:_record_result(session.set_actor_action(selected_member_id,"HOLD"),false,"%s 방어 불가"%_selected_name());_request_refresh()
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
		if session.party_status().safe_phase=="GROUPED_COMPLETE":
			notice_text="승리! 출구를 향해 탐험을 계속하세요." if _is_solo_product_session() \
				else "승리! 파티가 자동으로 재집결해 탐험을 다시 시작합니다."
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
	if session.party_status().safe_phase=="GROUPED_COMPLETE":
		notice_text="승리! 출구를 향해 탐험을 계속하세요." if _is_solo_product_session() \
			else "승리! 파티가 자동으로 재집결해 탐험을 다시 시작합니다."
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
		if bool(active_state.get("active",false)) and _route_goal(active_state)==position:
			route_preview=active_state.duplicate(true);_apply_route_state(active_state)
			notice_text="선택한 목적지로 이미 이동 중입니다."
			action_feedback_text="한 칸씩 이동 중 · %d/%d"%[int(active_state.get("completed_steps",0)),
				int(active_state.get("total_steps",0))]
			_request_refresh();return
		if bool(active_state.get("active",false)):_cancel_active_route()
		var preview:Dictionary=session.preview_exploration_route(position)
		route_preview=preview.duplicate(true);_apply_route_state(preview)
		if not bool(preview.get("accepted",false)):
			notice_text=str(preview.get("message","이 칸으로 이동할 수 없습니다."))
			_set_action_rejection(preview,"%s 이동 불가"%_protagonist_name())
			_update_tile_popover_route(preview);_request_refresh();return
		route_generation+=1;route_continue_pending=false
		var started:Dictionary=session.start_exploration_route(position,str(preview.get("plan_hash","")))
		_consume_route_result(started);_refresh();_schedule_route_continue()
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
	if status.view_mode=="EXPLORATION" and entity_id in status.get("rescue_candidate_ids",[]):
		if bool(session.exploration_route_state().get("has_preview",false)):_cancel_active_route()
		_open_member_detail(entity_id);return
	if status.view_mode=="EXPLORATION" and entity_id in status.get("roster_member_ids",[]) \
			and entity_id not in status.get("party_member_ids",[]):
		if bool(session.exploration_route_state().get("has_preview",false)):_cancel_active_route()
		_open_member_detail(entity_id);return
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
	return "방어"
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
	var last_step:Variant=result.get("last_step_result",{})
	if last_step is Dictionary:_arm_actor_motion_from_result(last_step)
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
	_arm_actor_motion_from_result(result)
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

func _arm_actor_motion_from_result(result:Dictionary)->void:
	if grid==null or session==null or not bool(result.get("accepted",false)) \
			or not result.get("event_ids",[]) is Array:return
	var moved:Dictionary={}
	for value in result.get("event_ids",[]):
		var event=session.sim.world.event_by_id(int(value))
		if event!=null and str(event.type)=="action.move" and int(event.actor_id)>0:
			moved[int(event.actor_id)]=true
	if moved.is_empty():return
	var status:Dictionary=session.party_status()
	var protagonist_id:=int(status.get("protagonist_id",-1))
	if moved.has(protagonist_id) and str(status.get("view_mode",""))=="EXPLORATION":
		for member_id in status.get("party_member_ids",[]):moved[int(member_id)]=true
	grid.arm_actor_motion(moved.keys())

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
		if selected_tile_view_mode=="EXPLORATION" and bool(route.get("active",false)):
			route_line+=" · 이동 중"
		lines.append(route_line)
	elif selected_tile_view_mode=="EXPLORATION":lines.append("총 위험 %d · 짧게 누르면 경로 확인 후 이동합니다."%total)
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
	if str(detail.get("rescue_story_state",""))=="COLLAPSED_STORY":
		var rescue:Dictionary=detail.get("rescue_assessment",{}) if detail.get("rescue_assessment",{}) is Dictionary else {}
		var time_cost:=int(rescue.get("time_cost",0))
		lines.append("구조 · 곁에서 상처를 안정화합니다%s."%((" · %d 시간"%time_cost) if time_cost>0 else ""))
	var recruitment:Dictionary=detail.get("recruitment_assessment",{}) if detail.get("recruitment_assessment",{}) is Dictionary else {}
	if not recruitment.is_empty():
		var roll:=int(recruitment.get("roll_milli",-1))
		lines.append("영입 가능성 · %d%% · %s"%[
			int(recruitment.get("probability_percent",0)),
			("판정값 %d"%roll) if roll>=0 else "파티 여석이 생기면 판정"])
		for reason_index in range(mini(3,recruitment.get("reasons",[]).size())):
			var reason:Variant=recruitment.reasons[reason_index]
			if reason is Dictionary:lines.append("· "+str(reason.get("label","")))
	var ready_text:=str(detail.get("readiness","행동 준비"));var remaining:=int(detail.get("remaining_time",0))
	if ready_text!="행동 준비" or remaining>0:
		lines.append("행동 · %s%s"%[ready_text,(" · %d 시간 남음"%remaining) if remaining>0 else ""])
	var profile:Variant=detail.get("personality_profile",null)
	if profile is Dictionary:
		var facets:Array[String]=[]
		for row in profile.get("facet_rows",[]):
			if row is Dictionary:facets.append("%s %d"%[_facet_label(str(row.get("facet_id",""))),int(row.get("base_value",0))])
		var archetype:Dictionary=detail.get("personality_archetype",{}) if detail.get("personality_archetype",{}) is Dictionary else {}
		lines.append("성격 · %s%s"%[str(archetype.get("label","분류되지 않은 성향")),
			(" · "+" · ".join(facets)) if not facets.is_empty() else ""])
	var affinity:Dictionary=detail.get("species_affinity",{}) if detail.get("species_affinity",{}) is Dictionary else {}
	var affinity_values:=[int(affinity.get("fire_tolerance",0)),int(affinity.get("water_tolerance",0)),
		int(affinity.get("electric_tolerance",0)),int(affinity.get("poison_tolerance",0))]
	if affinity_values.any(func(value):return int(value)!=0):
		lines.append("원소 내성 · 불 %d · 물 %d · 전기 %d · 독 %d"%affinity_values)
	var exposure:Dictionary=detail.get("current_exposure",detail.get("element_exposure",{})) if detail.get("current_exposure",detail.get("element_exposure",{})) is Dictionary else {}
	var exposure_risk:Dictionary=exposure.get("risk",exposure) if exposure.get("risk",exposure) is Dictionary else {}
	var exposure_total:=int(exposure_risk.get("total_risk",exposure_risk.get("total",0)))
	if bool(exposure.get("applicable",false)) and exposure_total>0:
		lines.append("현재 노출 · 불 %d · 물 %d · 전기 %d · 독 %d · 합계 %d"%[_risk_value(exposure_risk,"fire"),_risk_value(exposure_risk,"water"),
			_risk_value(exposure_risk,"electric"),_risk_value(exposure_risk,"poison"),exposure_total])
	var action:Variant=detail.get("expected_action",null)
	if action is Dictionary:
		lines.append("행동 제안 · %s"%_compact_action(action))
		var action_reason:=str(action.get("reason","")).strip_edges()
		if not action_reason.is_empty() and action_reason!="-":lines.append("· "+action_reason)
		var original:Variant=action.get("automatic_suggestion",null)
		if original is Dictionary:lines.append("원래 자동 제안: %s"%_action_only(original))
	var relations:Variant=detail.get("relation_rows",[])
	if str(detail.get("role",""))=="COMPANION" and relations is Array and not relations.is_empty():
		lines.append("관계")
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
	lines.append("주요 기록 · 최근 8개 사건 턴")
	var groups:Variant=history.get("groups",[])
	if not groups is Array or groups.is_empty():
		lines.append("아직 주요 사건이 없습니다.");return "\n".join(lines)
	for group in groups:
		if not group is Dictionary:continue
		lines.append("── 턴 %d · 시간 %d→%d ──"%[int(group.get("step_index",0)),int(group.get("start_time",0)),int(group.get("end_time",0))])
		for row in group.get("rows",[]):
			if not row is Dictionary:continue
			var message:=str(row.get("message","")).strip_edges()
			if not message.is_empty():lines.append(message)
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
		"CONTACT":action_feedback_label.text="단독 전투 시작" if _is_solo_product_session() else ("자동 대형 미리보기" if auto_orchestration_enabled and not auto_deployment_fallback else "대형 선택 → 배치 실행")
		"GROUPED_COMPLETE":action_feedback_label.text="승리 · 출구를 향해 탐험하세요." \
			if _is_solo_product_session() else "승리 · 자동 재집결 완료 · 탐험 이동을 선택하세요."
		_:
			if str(status.view_mode)=="EXPLORATION":action_feedback_label.text="이동 목적지 한 번 선택 → 경로를 따라 이동"
			elif str(status.view_mode)=="COMBAT":action_feedback_label.text="행동 선택 → 자동 실행" if auto_orchestration_enabled else "행동 지정 → 실행"
			else:action_feedback_label.text="다음 행동을 선택하세요."
func _add_notice(value:String,node_name:String="ActionStatus",font_size:int=FONT_BODY)->Label:
	var label:=Label.new(); label.name=node_name; label.text=value; label.custom_minimum_size.y=44; label.add_theme_font_size_override("font_size",maxi(FONT_AUX,font_size))
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; deck.add_child(label); return label
func _add_button(parent:Control,value:String,node_name:String,callback:Callable)->Button:
	var button:=Button.new(); button.name=node_name; button.text=value; button.custom_minimum_size=Vector2(TOUCH_TARGET,TOUCH_TARGET); button.add_theme_font_size_override("font_size",FONT_BODY)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.pressed.connect(callback); parent.add_child(button)
	var danger:=node_name in ["MemberDetailDismiss","RestartExpedition"]
	var accent:=AsciiFrameScript.DANGER if danger else (AsciiFrameScript.BRASS if node_name in ["TurnConfirm","AutoExecute","DeployConfirm"] else AsciiFrameScript.CYAN)
	AsciiFrameScript.apply_rail_button(button,accent,false,danger)
	var glyph:=Label.new();glyph.name="ActionGlyph";glyph.text=_action_glyph(node_name)
	glyph.mouse_filter=Control.MOUSE_FILTER_IGNORE;glyph.anchor_top=0.5;glyph.anchor_bottom=0.5
	glyph.offset_left=5;glyph.offset_right=21;glyph.offset_top=-10;glyph.offset_bottom=10
	glyph.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	AsciiFrameScript.label_tone(glyph,accent,14);button.add_child(glyph);return button
func _action_glyph(node_name:String)->String:
	if node_name in ["TurnConfirm","AutoExecute","DeployConfirm","SoloCombatStart"]:return ">"
	if node_name.begins_with("Stabilize") or node_name.begins_with("Recruit"):return "+"
	if node_name in ["MemberDetailDismiss","RestartExpedition"]:return "!"
	if node_name in ["OverrideClear"]:return "~"
	return "◆"
func _is_solo_product_session()->bool:
	return session!=null and session.has_method("is_solo_combat") \
		and bool(session.call("is_solo_combat"))
func _clear_container(container:Control)->void:
	for child in container.get_children():container.remove_child(child); child.free()
func _phase(value:String)->String:
	if value=="ENGAGED" and _is_solo_product_session():return "단독 전투"
	return {"GROUPED":"탐험","CONTACT":"조우 배치","ENGAGED":"파티 전투","REGROUP_READY":"자동 재집결","GROUPED_COMPLETE":"탐험 재개","PARTY_DEFEATED":"패배"}.get(value,value)
func _presence(value:String)->String:return {"DEPLOYED":"배치","GROUPED":"동행","DORMANT":"전투 대기","RECRUITABLE":"영입 후보","EXILED":"추방됨","DEFEATED":"쓰러짐"}.get(value,value)
func _role(value:String)->String:return {"PROTAGONIST":"주인공","COMPANION":"동료"}.get(value,value)
func _species(value:String)->String:return {"human":"인간","goblin":"고블린","amphibian":"양서인","dwarf":"드워프","default":"미상"}.get(value,value)
func _facet_label(value:String)->String:return {"aggression":"공격성","altruism":"이타성","boldness":"대담성","composure":"침착성"}.get(value,value)
func _disposition(value:String)->String:return {"HOSTILE":"적대","WARY":"경계","TRUSTING":"신뢰","FRIENDLY":"우호","NEUTRAL":"중립"}.get(value,value)
func _apply_portrait_budget(combat_active:bool,combat_actions_visible:bool,
		run_available:bool=false,run_terminal:bool=false,party_height:int=160)->void:
	var wide:=size.x>=450.0
	phase_panel.custom_minimum_size.y=(88 if size.x<450.0 else 92) \
		if _is_solo_product_session() else (52 if wide else 48)
	root_layout.add_theme_constant_override("separation",4 if wide else 2)
	combat_action_area.custom_minimum_size.y=84 if combat_actions_visible else 0
	if _is_solo_product_session():
		grid.custom_minimum_size=Vector2(size.x,size.x)
	elif wide:
		grid.custom_minimum_size=Vector2(405,405)
	elif combat_active:
		grid.custom_minimum_size=Vector2(248,248) if run_available else Vector2(300,300)
	else:
		grid.custom_minimum_size=Vector2(276,276) \
			if run_available and (run_terminal or _run_locked_exit_feedback) \
			else (Vector2(316,316) if run_available else Vector2(348,348))
	cards.custom_minimum_size.y=maxi(0,party_height)
	info_scroll.custom_minimum_size.y=30

func _apply_phase_banner(status:Dictionary,presentation:Dictionary)->void:
	var banner:Dictionary=presentation.get("banner",{})
	var tone:=str(banner.get("tone","CALM"))
	var situation:="조용함"
	if tone=="DEFEAT":situation="위험"
	elif tone=="VICTORY" or str(status.get("safe_phase",""))=="GROUPED_COMPLETE":situation="승리"
	elif str(status.get("safe_phase",""))=="ENGAGED":situation="전투"
	elif str(status.get("safe_phase",""))=="CONTACT" \
			or not status.get("visible_enemy_ids",[]).is_empty():situation="기척"
	var surface_color:=Color("#08131ad9")
	if situation=="전투":
		surface_color=Color("#1b1114df")
		phase_label.add_theme_font_size_override("font_size",FONT_KEY)
		phase_label.add_theme_color_override("font_color",AsciiFrameScript.DANGER); grid.set_combat_emphasis(true)
	elif situation=="승리":
		surface_color=Color("#091b17df")
		phase_label.add_theme_font_size_override("font_size",FONT_KEY)
		phase_label.add_theme_color_override("font_color",AsciiFrameScript.JADE); grid.set_combat_emphasis(false)
	elif situation=="위험":
		surface_color=Color("#171116df")
		phase_label.add_theme_font_size_override("font_size",FONT_KEY)
		phase_label.add_theme_color_override("font_color",AsciiFrameScript.DANGER);grid.set_combat_emphasis(true)
	else:
		surface_color=Color("#17150dd9") if situation=="기척" else Color("#08131ad9")
		phase_label.add_theme_font_size_override("font_size",FONT_KEY)
		phase_label.add_theme_color_override("font_color",AsciiFrameScript.BRASS if situation=="기척" else AsciiFrameScript.INK); grid.set_combat_emphasis(false)
	phase_label.text=situation
	phase_panel.add_theme_stylebox_override("panel",AsciiFrameScript.borderless_surface(surface_color,4))
	phase_panel.set_meta("visible_stylebox_border",false)
	if minimap_frame!=null:
		var glyph_tone:=AsciiFrameScript.CYAN
		if situation=="승리":glyph_tone=AsciiFrameScript.JADE
		elif situation in ["전투","위험"]:glyph_tone=AsciiFrameScript.DANGER
		elif situation=="기척":glyph_tone=AsciiFrameScript.BRASS
		minimap_frame.frame_color=glyph_tone;minimap_frame.title_color=glyph_tone
		minimap_frame.danger_edge=situation=="위험"
		minimap_frame.set_meta("state_tone",tone)
		minimap_frame.queue_redraw()

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
