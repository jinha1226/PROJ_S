class_name PartyEncounterSandbox
extends Control

const EXPLORATION_ACTOR_MOTION_MSEC := 50
const CONTINUOUS_EXPLORATION_MOTION_MSEC := 160
const MANUAL_CAMERA_SETTLE_MSEC := 50
# Web canonical hops commonly finish around 105-120ms. Keep continuous motion
# alive beyond that interval so the next hop retargets the current draw position
# instead of visibly stopping on every cell.
const CONTINUOUS_CAMERA_SETTLE_MSEC := 160

const SessionScript=preload("res://playtest/party_playtest_session.gd")
const GridScript=preload("res://playtest/party_grid_view.gd")
const MinimapScript=preload("res://playtest/party_minimap.gd")
const MapOverlayScript=preload("res://playtest/party_map_overlay.gd")
const CommandScript=preload("res://sim/sim_command.gd")
const ActionScript=preload("res://sim/party_action_command.gd")
const ProgressionRegistryScript=preload("res://sim/progression_registry.gd")
const AsciiFrameScript=preload("res://playtest/ascii_ui_frame.gd")
const AsciiGaugeScript=preload("res://playtest/ascii_gauge.gd")
const BuildInfoScript=preload("res://playtest/build_info.gd")
const GrowthBuildRegistryScript=preload("res://sim/growth_build_registry.gd")
const AsciiMaterialGrammarScript=preload("res://playtest/ascii_material_grammar.gd")
const KoreanFont:FontFile=preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const DUEL_DECISION_LAB_SCENE_PATH="res://playtest/duel_decision_lab.tscn"
const NPC_EXPEDITION_LAB_SCENE_PATH="res://playtest/npc_expedition_lab.tscn"
const ASCII_3D_LAB_SCENE=preload("res://playtest/ascii_3d_lab.tscn")
const FONT_AUX:=14
const FONT_BODY:=16
const FONT_KEY:=20
const FONT_SECTION:=18
const FONT_COMMAND:=14
const FONT_CAPTION:=12
const FONT_MICRO:=11
const TOUCH_TARGET:=44
const AUTO_FORMATION_ORDER:=["WEDGE","LINE","COLUMN"]
const CONTINUOUS_TRAVEL_CADENCE_MSEC:=60
const PRODUCT_ZOOM_CELL_COUNTS:=SessionScript.PRODUCT_ZOOM_CELL_COUNTS
const PRODUCT_ZOOM_DEFAULT_CELL_COUNT:=SessionScript.PRODUCT_ZOOM_DEFAULT_CELL_COUNT
const PRODUCT_ZOOM_REFERENCE_CELL_COUNT:=SessionScript.PRODUCT_ZOOM_REFERENCE_CELL_COUNT

var session
var grid
var grid_zoom_controls:HBoxContainer
var grid_graphics_mode_button:Button
var grid_zoom_out_button:Button
var grid_zoom_in_button:Button
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
var event_surface:PanelContainer
var event_label:Label
var combat_action_area:VBoxContainer
var action_feedback_label:Label
var combat_action_dock:HBoxContainer
var party_command_menu:MenuButton
var product_direction_buttons:Dictionary={}
var product_attack_button:Button
var product_pickup_button:Button
var product_auto_button:Button
var product_interact_button:Button
var product_wait_guard_button:Button
var product_execute_button:Button
var hud_bottom_flex:Control
var build_label:Label
var bottom_navigation:HBoxContainer
var map_nav_button:Button
var person_nav_button:Button
var skill_nav_button:Button
var equipment_nav_button:Button
var history_nav_button:Button
var map_overlay:Control
var record_modal:Control
var record_panel:PanelContainer
var record_body:Label
var record_close_button:Button
var species_picker_modal:Control
var species_picker_panel:PanelContainer
var species_picker_buttons:VBoxContainer
var npc_expedition_lab_button:Button
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
var route_continue_due_frame:=-1
var route_continue_due_msec:=-1
var route_scheduled_generation:=-1
var route_last_hop_started_msec:=-1
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
var member_detail_subtitle:Label
var member_detail_glyph_seal:Label
var member_detail_scroll:ScrollContainer
var member_detail_scroll_content:VBoxContainer
var member_detail_tab_stash:Node
var member_detail_body:Label
var member_status_window:VBoxContainer
var member_detail_tab_row:HBoxContainer
var member_detail_status_tab:Button
var member_detail_skill_tab:Button
var member_detail_item_tab:Button
var member_detail_current_tab:="STATUS"
var member_detail_has_skills:=false
var member_detail_dismiss_available:=false
var member_detail_candidate_available:=false
var member_progression_window:VBoxContainer
var member_progression_xp
var member_progression_xp_text:Label
var member_progression_stats:Label
var member_progression_skill_rows:Dictionary={}
var member_skill_help:Label
var member_skill_category_button:Button
var member_skill_category_expanded:=false
var _skill_touch_index:=-1
var _skill_touch_id:=""
var _skill_touch_origin:=Vector2.ZERO
var _skill_touch_dragged:=false
var _item_touch_index:=-1
var _item_touch_id:=""
var _item_touch_slot:=""
var _item_touch_action:=""
var _item_touch_origin:=Vector2.ZERO
var _item_touch_dragged:=false
var member_item_window:VBoxContainer
var member_item_weapon_text:Label
var member_item_ammo_text:Label
var member_item_reload_button:Button
var member_item_empty_text:Label
var member_item_stats:Dictionary={}
var member_item_equipment_rows:VBoxContainer
var member_item_backpack_rows:VBoxContainer
var member_item_selected_stats:Label
var member_item_quick_unequip_button:Button
var member_item_action_row:HBoxContainer
var member_item_equip_button:Button
var member_item_unequip_button:Button
var member_item_drop_button:Button
var member_item_use_button:Button
var member_item_selected_id:=""
var member_item_selected_slot:=""
var pending_ground_pickup_id:=""
var pending_ground_pickup_label:=""
var member_detail_close:Button
var member_detail_dismiss:Button
var member_detail_candidate_action:Button
var member_detail_focus_buttons:GridContainer
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
var _product_touch_index:=-1
var _product_touch_control:=""
var _product_touch_origin:=Vector2.ZERO
var _product_touch_dragged:=false
var _product_mouse_control:=""
var _product_ignore_mouse_until_msec:=-1
var _product_auto_explore_generation:=0
var _product_auto_explore_pending:=false
var _product_auto_explore_due_frame:=-1
var _product_auto_explore_due_msec:=-1
var _product_auto_explore_scheduled_generation:=-1
var _product_auto_last_hop_started_msec:=-1
var _product_auto_stop_feedback:=""
var _product_attack_targeting:=false
var _party_command_targeting:=false
var _product_zoom_cell_count:=PRODUCT_ZOOM_DEFAULT_CELL_COUNT
var _product_zoom_touch_index:=-1
var _product_zoom_touch_step:=0
# Presentation cadence only. Tests may set this to zero; it never participates
# in canonical route choice, journal contents, simulation time, or replay.
var continuous_travel_cadence_msec:=CONTINUOUS_TRAVEL_CADENCE_MSEC

func _process(_delta:float)->void:
	var frame:=Engine.get_process_frames()
	var now_msec:=Time.get_ticks_msec()
	if _product_auto_explore_pending and frame>=_product_auto_explore_due_frame \
			and now_msec>=_product_auto_explore_due_msec:
		# A held product button is an unresolved user gesture. AUTO may keep its
		# running state, but no authoritative hop can occur until release/cancel.
		if _product_touch_index>=0:
			_product_auto_explore_due_frame=frame+1
		else:
			var expected_auto_generation:=_product_auto_explore_scheduled_generation
			_product_auto_explore_pending=false;_product_auto_explore_due_frame=-1
			_product_auto_explore_due_msec=-1;_product_auto_explore_scheduled_generation=-1
			_continue_product_auto_explore(expected_auto_generation)
	if route_continue_pending and frame>=route_continue_due_frame \
			and now_msec>=route_continue_due_msec:
		# Match AUTO's unresolved product-button gesture contract. A direction press
		# may be held past the cadence deadline, but the old route cannot advance
		# before release cancels it and commits the one manual step. Zoom has its own
		# touch index and deliberately leaves continuous travel running.
		if _product_touch_index>=0:
			route_continue_due_frame=frame+1
		else:
			var expected_route_generation:=route_scheduled_generation
			route_continue_pending=false;route_continue_due_frame=-1
			route_continue_due_msec=-1;route_scheduled_generation=-1
			_continue_route_on_cadence(expected_route_generation)

func _input(event:InputEvent)->void:
	if _handle_product_zoom_touch(event):return
	# Manual screen input wins the scheduling tie even when a pass-through UI
	# container receives the GUI event before PartyGrid. Do not consume the event:
	# the grid still owns tap/drag semantics, while the active route is cancelled
	# synchronously and generation-safe before another cadence hop can commit.
	if event is InputEventScreenTouch and event.pressed \
			and grid!=null and grid.visible and grid.get_global_rect().has_point(event.position) \
			and not _product_zoom_control_has_point(event.position) \
			and not grid.modal_open and session!=null:
		if session.has_method("auto_explore_state") \
				and bool(session.auto_explore_state().get("running",false)):
			_cancel_product_auto_explore("auto_explore_user_command",false)
		var route_state:Dictionary=session.exploration_route_state()
		if bool(route_state.get("active",false)):
			_cancel_active_route()
	if _handle_product_control_touch(event):return
	if member_detail_modal==null or not member_detail_modal.visible:return
	if member_detail_current_tab=="ITEM":
		_handle_item_ledger_touch(event);return
	if member_detail_current_tab!="SKILL":return
	if event is InputEventScreenTouch:
		if event.pressed and _skill_touch_index<0:
			var skill_id:=_skill_row_at_position(event.position)
			if skill_id.is_empty():return
			_skill_touch_index=event.index;_skill_touch_id=skill_id
			_skill_touch_origin=event.position;_skill_touch_dragged=false
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index==_skill_touch_index:
			var activate_id:=_skill_touch_id if not _skill_touch_dragged else ""
			_skill_touch_index=-1;_skill_touch_id="";_skill_touch_dragged=false
			get_viewport().set_input_as_handled()
			if not activate_id.is_empty():_on_training_mode_cycle(activate_id)
	elif event is InputEventScreenDrag and event.index==_skill_touch_index:
		if event.position.distance_to(_skill_touch_origin)>=float(member_detail_scroll.scroll_deadzone):
			_skill_touch_dragged=true
		member_detail_scroll.scroll_vertical-=int(event.relative.y)
		get_viewport().set_input_as_handled()

func _handle_item_ledger_touch(event:InputEvent)->void:
	if event is InputEventScreenTouch:
		if event.pressed and _item_touch_index<0:
			var action:=_item_action_at_position(event.position)
			if not action.is_empty():
				_item_touch_index=event.index;_item_touch_action=action
				_item_touch_id="";_item_touch_slot="";_item_touch_origin=event.position
				_item_touch_dragged=false;get_viewport().set_input_as_handled();return
			var row:=_item_row_at_position(event.position)
			if row.is_empty():return
			_item_touch_index=event.index;_item_touch_id=str(row.instance_id)
			_item_touch_slot=str(row.slot);_item_touch_action="";_item_touch_origin=event.position
			_item_touch_dragged=false;get_viewport().set_input_as_handled()
		elif not event.pressed and event.index==_item_touch_index:
			var activate_id:=_item_touch_id if not _item_touch_dragged else ""
			var activate_slot:=_item_touch_slot
			var activate_action:=_item_touch_action if not _item_touch_dragged else ""
			_item_touch_index=-1;_item_touch_id="";_item_touch_slot=""
			_item_touch_action="";_item_touch_dragged=false;get_viewport().set_input_as_handled()
			if not activate_action.is_empty():_activate_item_touch_action(activate_action)
			elif not activate_id.is_empty():_on_item_row_selected(activate_id,activate_slot)
	elif event is InputEventScreenDrag and event.index==_item_touch_index:
		if event.position.distance_to(_item_touch_origin)>=float(member_detail_scroll.scroll_deadzone):
			_item_touch_dragged=true
		member_detail_scroll.scroll_vertical-=int(event.relative.y)
		get_viewport().set_input_as_handled()

func _item_action_at_position(global_position:Vector2)->String:
	var buttons:Array=[
		[member_item_reload_button,"RELOAD"],
		[member_item_quick_unequip_button,"UNEQUIP"],
		[member_item_equip_button,"EQUIP"],
		[member_item_unequip_button,"UNEQUIP"],
		[member_item_use_button,"USE"],
		[member_item_drop_button,"DROP"],
	]
	var inline:=member_item_backpack_rows.find_child("ItemInlineEquip",true,false) \
		if member_item_backpack_rows!=null else null
	if inline!=null:buttons.push_front([inline,"EQUIP"])
	for entry in buttons:
		var button:=entry[0] as Button
		if button!=null and button.is_visible_in_tree() and not button.disabled \
				and button.get_global_rect().has_point(global_position):return str(entry[1])
	return ""

func _activate_item_touch_action(action:String)->void:
	match action:
		"RELOAD":_on_item_reload()
		"EQUIP":_on_item_equip_selected()
		"UNEQUIP":_on_item_unequip_selected()
		"USE":_on_item_use_selected()
		"DROP":_on_item_drop_selected()

func _item_row_at_position(global_position:Vector2)->Dictionary:
	for ledger in [member_item_equipment_rows,member_item_backpack_rows]:
		if ledger==null:continue
		for child in ledger.get_children():
			var button:=child as Button
			if button==null or not button.is_visible_in_tree() or button.disabled \
					or not button.get_global_rect().has_point(global_position):continue
			# Only ledger rows belong to the drag-safe row gesture. Inline actions are
			# children of the same VBox, but must keep their ordinary Button touch
			# path; consuming them here prevents [장착]/[교체] from ever emitting
			# `pressed` on mobile while mouse input still appears to work.
			var instance_id:=str(button.get_meta("item_instance_id",""))
			if instance_id.is_empty():continue
			return {"instance_id":instance_id,
				"slot":str(button.get_meta("item_slot",""))}
	return {}

func _handle_product_control_touch(event:InputEvent)->bool:
	if not event is InputEventScreenTouch and not event is InputEventScreenDrag:return false
	if not _is_solo_product_session() or not combat_action_area.visible:return false
	if member_detail_modal!=null and member_detail_modal.visible \
			or record_modal!=null and record_modal.visible \
			or map_overlay!=null and map_overlay.visible:return false
	if event is InputEventScreenTouch:
		if event.pressed:
			if _product_touch_index>=0:return false
			var control_name:=_product_control_at_position(event.position)
			if control_name.is_empty():return false
			_product_touch_index=event.index;_product_touch_control=control_name
			_product_touch_origin=event.position;_product_touch_dragged=false
			_product_ignore_mouse_until_msec=Time.get_ticks_msec()+750
			get_viewport().set_input_as_handled()
			# Combat feedback should begin under the finger, not after the full
			# press/release cycle. Keep movement and navigation drag-cancellable.
			if control_name=="ProductAttack":
				_product_touch_control="";_activate_product_control(control_name)
			return true
		if event.index!=_product_touch_index:return false
		# ScreenTouch coordinates may be reprojected by stretch mode between the
		# press and release frames. A gesture that began on one exact button and did
		# not cross the drag threshold is still that button's short tap.
		var activate_name:=_product_touch_control if not _product_touch_dragged else ""
		_product_touch_index=-1;_product_touch_control="";_product_touch_dragged=false
		_product_ignore_mouse_until_msec=Time.get_ticks_msec()+750
		get_viewport().set_input_as_handled()
		if not activate_name.is_empty():
			_activate_product_control(activate_name)
		return true
	if event.index==_product_touch_index:
		if event.position.distance_to(_product_touch_origin)>=8.0:_product_touch_dragged=true
		get_viewport().set_input_as_handled();return true
	return false

func _product_control_at_position(global_position:Vector2)->String:
	var controls:Array=[]
	for button in product_direction_buttons.values():controls.append(button)
	controls.append_array([product_attack_button,product_pickup_button,product_auto_button,
		product_interact_button,product_wait_guard_button,product_execute_button,
		map_nav_button,person_nav_button,skill_nav_button,equipment_nav_button,
		history_nav_button])
	for control_value in controls:
		var button:=control_value as Button
		if button!=null and button.is_visible_in_tree() and not button.disabled \
				and button.get_global_rect().has_point(global_position):return button.name
	return ""

func _activate_product_control(control_name:String)->void:
	match control_name:
		"ProductMoveNW":_on_product_direction(Vector2i(-1,-1))
		"ProductMoveN":_on_product_direction(Vector2i(0,-1))
		"ProductMoveNE":_on_product_direction(Vector2i(1,-1))
		"ProductMoveW":_on_product_direction(Vector2i(-1,0))
		"ProductWaitCenter":_on_product_direction(Vector2i.ZERO)
		"ProductMoveE":_on_product_direction(Vector2i(1,0))
		"ProductMoveSW":_on_product_direction(Vector2i(-1,1))
		"ProductMoveS":_on_product_direction(Vector2i(0,1))
		"ProductMoveSE":_on_product_direction(Vector2i(1,1))
		"ProductAttack":_on_product_attack()
		"ProductPickup":_on_product_pickup()
		"ProductAuto":_on_product_auto()
		"ProductInteract":_on_product_interact()
		"ProductWaitGuard":_on_product_wait_guard()
		"ProductExecute":_on_product_execute()
		"MapNavigation":_toggle_map_overlay()
		"PersonNavigation":_open_hero_detail_tab("STATUS")
		"SkillNavigation":_open_hero_detail_tab("SKILL")
		"EquipmentNavigation":_open_hero_detail_tab("ITEM")
		"HistoryNavigation":_toggle_record_modal()

func _on_product_button_gui_input(event:InputEvent,control_name:String)->void:
	# Product controls use one explicit pointer path. Connecting Button.pressed as
	# well as handling ScreenTouch in _input caused a mobile release to execute the
	# same authoritative command twice. Mouse activation is handled here; touch is
	# handled exclusively by _handle_product_control_touch above.
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT:return
	# Web/mobile may synthesize mouse press/release after a handled ScreenTouch.
	# Ignore that compatibility event so one physical release has one command.
	if Time.get_ticks_msec()<=_product_ignore_mouse_until_msec:
		_product_mouse_control="";accept_event();return
	if event.pressed:
		_product_mouse_control=control_name
		accept_event();return
	var activate:=_product_mouse_control==control_name
	_product_mouse_control="";accept_event()
	if activate:_activate_product_control(control_name)

func _skill_row_at_position(global_position:Vector2)->String:
	for skill_id in member_progression_skill_rows:
		var row:Dictionary=member_progression_skill_rows[skill_id]
		var button:=row.title as Button
		if button.is_visible_in_tree() and button.get_global_rect().has_point(global_position):return str(skill_id)
	return ""
var _reward_emphasis_count:=0
var _reward_emphasis_tween:Tween
var _run_locked_exit_feedback:=false
var _personality_entropy_source:Callable
var _narrative_log_visible:=false
var _compact_fixed_surface_active:=false
var _pending_visual_effect_rows:Array[Dictionary]=[]
var _refresh_pending:=false
var _last_direct_solo_refresh_profile:Dictionary={}
var _last_direct_solo_turn_profile:Dictionary={}
var _last_continuous_exploration_refresh_profile:Dictionary={}
var _species_picker_committed:=false

func _ready()->void:
	_build_ui()
	if not _initialized_for_headless_test and session==null:
		session=SessionScript.new(SessionScript.DEFAULT_WORLD_SEED,
			_issue_new_personality_seed(),SessionScript.SOLO_COMBAT_SCENARIO_ID)
		auto_orchestration_enabled=true;_reset_auto_flow()
	_refresh()
	if not _initialized_for_headless_test:show_species_picker_for_new_run()
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
	var bg:=ColorRect.new();bg.name="SandboxBackground"
	bg.color=AsciiFrameScript.SURFACE_DEEP;bg.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	root_layout=VBoxContainer.new(); root_layout.name="PartyLayout"; root_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layout.offset_left=6; root_layout.offset_right=-6; root_layout.offset_top=4; root_layout.offset_bottom=-4; root_layout.add_theme_constant_override("separation",4); add_child(root_layout)
	phase_panel=PanelContainer.new();phase_panel.name="TopExplorationHUD"
	var top_rail:=AsciiFrameScript.borderless_surface(AsciiFrameScript.BLACK,0)
	top_rail.border_width_bottom=1;top_rail.border_color=AsciiFrameScript.CYAN
	phase_panel.add_theme_stylebox_override("panel",top_rail)
	phase_panel.custom_minimum_size.y=64;root_layout.add_child(phase_panel)
	phase_row=HBoxContainer.new();phase_row.name="TopExplorationHUDRow"
	phase_row.add_theme_constant_override("separation",4);phase_panel.add_child(phase_row)
	minimap_frame=AsciiFrameScript.new();minimap_frame.name="MinimapAsciiFrame"
	minimap_frame.configure("지도",AsciiFrameScript.CYAN,AsciiFrameScript.BLACK,true)
	minimap_frame.custom_minimum_size=Vector2(62,60);phase_row.add_child(minimap_frame)
	minimap=MinimapScript.new();minimap.name="ExplorationMinimap"
	minimap.custom_minimum_size=Vector2(52,50);minimap_frame.add_child(minimap)
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
	var reward_style:=AsciiFrameScript.borderless_surface(AsciiFrameScript.BLACK,2)
	reward_badge.add_theme_stylebox_override("normal",reward_style)
	reward_badge.add_theme_color_override("font_color",AsciiFrameScript.JADE)
	situation_row.add_child(reward_badge)
	recent_event_label=Label.new();recent_event_label.name="RecentWorldEvent"
	recent_event_label.add_theme_font_size_override("font_size",FONT_AUX)
	recent_event_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	recent_event_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	recent_event_label.size_flags_vertical=Control.SIZE_EXPAND_FILL
	recent_event_label.clip_text=true;recent_event_label.visible=false;situation_stack.add_child(recent_event_label)
	top_hud_actions=HBoxContainer.new();top_hud_actions.name="TopHUDActions"
	top_hud_actions.custom_minimum_size.x=132;top_hud_actions.alignment=BoxContainer.ALIGNMENT_END
	top_hud_actions.add_theme_constant_override("separation",0)
	phase_row.add_child(top_hud_actions)
	record_button=Button.new();record_button.name="NarrativeLogToggle";record_button.text="[기록]"
	record_button.custom_minimum_size=Vector2(44,44);record_button.toggle_mode=true
	record_button.clip_text=true;record_button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	record_button.add_theme_font_size_override("font_size",FONT_COMMAND)
	record_button.tooltip_text="하단 사건 기록 표시/숨기기"
	record_button.pressed.connect(_toggle_narrative_log);top_hud_actions.add_child(record_button)
	AsciiFrameScript.apply_rail_button(record_button,AsciiFrameScript.CYAN)
	hero_detail_button=Button.new();hero_detail_button.name="HeroDetailButton";hero_detail_button.text="[인물]"
	hero_detail_button.custom_minimum_size=Vector2(44,44);hero_detail_button.add_theme_font_size_override("font_size",FONT_COMMAND);hero_detail_button.tooltip_text="주인공 상세 정보"
	hero_detail_button.clip_text=true;hero_detail_button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	hero_detail_button.pressed.connect(_open_hero_detail);top_hud_actions.add_child(hero_detail_button)
	AsciiFrameScript.apply_rail_button(hero_detail_button,AsciiFrameScript.BRASS)
	ascii_3d_lab_button=Button.new();ascii_3d_lab_button.name="Ascii3DLabButton";ascii_3d_lab_button.text="[3D]"
	ascii_3d_lab_button.custom_minimum_size=Vector2(44,44);ascii_3d_lab_button.add_theme_font_size_override("font_size",FONT_COMMAND);ascii_3d_lab_button.tooltip_text="저장과 무관한 3D 시각 실험"
	ascii_3d_lab_button.clip_text=true;ascii_3d_lab_button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
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
	_build_product_zoom_controls()
	cards=HBoxContainer.new(); cards.name="PartyCards"; cards.custom_minimum_size.y=160
	cards.add_theme_constant_override("separation",4); root_layout.add_child(cards)
	info_scroll=ScrollContainer.new(); info_scroll.name="InformationScroll"; info_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; root_layout.add_child(info_scroll)
	var info:=VBoxContainer.new(); info.name="InformationStack"; info.size_flags_horizontal=Control.SIZE_EXPAND_FILL; info.add_theme_constant_override("separation",6); info_scroll.add_child(info)
	deck=VBoxContainer.new(); deck.name="ContextDeck"; deck.add_theme_constant_override("separation",2); info.add_child(deck)
	log_label=Label.new(); log_label.name="NarrativeLog"; log_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("font_size",FONT_AUX); log_label.custom_minimum_size.y=44
	log_label.max_lines_visible=3;log_label.clip_text=true;info.add_child(log_label)
	event_surface=PanelContainer.new();event_surface.name="EventSurface";event_surface.visible=false
	event_surface.add_theme_stylebox_override("panel",AsciiFrameScript.borderless_surface(AsciiFrameScript.BLACK,2))
	root_layout.add_child(event_surface)
	var event_margin:=MarginContainer.new();event_margin.name="EventSurfaceInset"
	event_margin.size_flags_vertical=Control.SIZE_EXPAND_FILL
	event_margin.add_theme_constant_override("margin_left",6);event_margin.add_theme_constant_override("margin_right",100)
	event_surface.add_child(event_margin)
	event_label=Label.new();event_label.name="CompactMeaningfulEvent";event_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	# Two real combat rows must fit the fixed 36/38px event surface. The bundled
	# Korean font needs the micro size for two complete baselines in that budget.
	event_label.add_theme_font_size_override("font_size",FONT_MICRO);event_label.max_lines_visible=2
	event_label.size_flags_vertical=Control.SIZE_EXPAND_FILL;event_label.custom_minimum_size.y=28
	event_label.clip_text=true;event_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	event_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;event_margin.add_child(event_label)
	combat_action_area=VBoxContainer.new();combat_action_area.name="CombatActionArea";combat_action_area.custom_minimum_size.y=84
	combat_action_area.add_theme_constant_override("separation",2);combat_action_area.visible=false;root_layout.add_child(combat_action_area)
	action_feedback_label=Label.new();action_feedback_label.name="ActionFeedback";action_feedback_label.custom_minimum_size.y=38
	action_feedback_label.add_theme_font_size_override("font_size",FONT_AUX);action_feedback_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	action_feedback_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;action_feedback_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	combat_action_area.add_child(action_feedback_label)
	combat_action_dock=HBoxContainer.new(); combat_action_dock.name="CombatActionDock"; combat_action_dock.custom_minimum_size.y=TOUCH_TARGET
	combat_action_dock.add_theme_constant_override("separation",4);combat_action_dock.visible=false;combat_action_area.add_child(combat_action_dock)
	hud_bottom_flex=Control.new();hud_bottom_flex.name="HudBottomFlex"
	hud_bottom_flex.size_flags_vertical=Control.SIZE_EXPAND_FILL
	hud_bottom_flex.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud_bottom_flex.visible=false
	root_layout.add_child(hud_bottom_flex)
	_build_bottom_navigation()
	_build_build_label()
	_build_tile_popover()
	_build_member_detail_modal()
	_build_map_overlay()
	_build_record_modal()
	_build_species_picker()
	_build_duel_decision_lab_entry()
	resized.connect(_layout_floating_surfaces)

func _build_bottom_navigation()->void:
	bottom_navigation=HBoxContainer.new();bottom_navigation.name="BottomNavigation"
	bottom_navigation.custom_minimum_size.y=TOUCH_TARGET;bottom_navigation.visible=false
	bottom_navigation.add_theme_constant_override("separation",0);root_layout.add_child(bottom_navigation)
	map_nav_button=_add_nav_button("[지도]","MapNavigation",_toggle_map_overlay);map_nav_button.toggle_mode=true
	person_nav_button=_add_nav_button("[인물]","PersonNavigation",_open_hero_detail_tab.bind("STATUS"))
	skill_nav_button=_add_nav_button("[숙련]","SkillNavigation",_open_hero_detail_tab.bind("SKILL"))
	equipment_nav_button=_add_nav_button("[장비]","EquipmentNavigation",_open_hero_detail_tab.bind("ITEM"))
	history_nav_button=_add_nav_button("[기록]","HistoryNavigation",_toggle_record_modal);history_nav_button.toggle_mode=true

func _add_nav_button(label:String,node_name:String,callback:Callable)->Button:
	var button:=Button.new();button.name=node_name;button.text=label
	button.custom_minimum_size=Vector2(TOUCH_TARGET,TOUCH_TARGET)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.add_theme_font_size_override("font_size",FONT_COMMAND)
	button.clip_text=true;button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	button.pressed.connect(callback);bottom_navigation.add_child(button)
	AsciiFrameScript.apply_rail_button(button,AsciiFrameScript.CYAN)
	return button

func _build_map_overlay()->void:
	map_overlay=MapOverlayScript.new();map_overlay.name="PartyMapOverlay";map_overlay.z_index=60
	map_overlay.closed.connect(_on_map_overlay_closed);add_child(map_overlay)

func _build_record_modal()->void:
	record_modal=Control.new();record_modal.name="NarrativeRecordModal";record_modal.visible=false
	record_modal.mouse_filter=Control.MOUSE_FILTER_STOP;record_modal.z_index=60
	record_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(record_modal)
	var scrim:=ColorRect.new();scrim.name="NarrativeRecordScrim";scrim.color=Color("#000306d9")
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);scrim.gui_input.connect(_on_record_backdrop_input)
	record_modal.add_child(scrim)
	record_panel=PanelContainer.new();record_panel.name="NarrativeRecordPanel"
	record_panel.add_theme_stylebox_override("panel",AsciiFrameScript.borderless_surface(AsciiFrameScript.SURFACE_DEEP,6))
	record_modal.add_child(record_panel)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",4);record_panel.add_child(stack)
	var header:=HBoxContainer.new();header.custom_minimum_size.y=TOUCH_TARGET;stack.add_child(header)
	var title:=Label.new();title.text="주요 기록";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size",FONT_SECTION);title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;header.add_child(title)
	npc_expedition_lab_button=Button.new();npc_expedition_lab_button.name="NpcExpeditionLabButton"
	npc_expedition_lab_button.text="[NPC 관찰]";npc_expedition_lab_button.tooltip_text="NPC 한 명의 원정 주기 관찰"
	npc_expedition_lab_button.custom_minimum_size=Vector2(92,TOUCH_TARGET)
	npc_expedition_lab_button.add_theme_font_size_override("font_size",FONT_COMMAND)
	npc_expedition_lab_button.pressed.connect(_open_npc_expedition_lab);header.add_child(npc_expedition_lab_button)
	AsciiFrameScript.apply_rail_button(npc_expedition_lab_button,AsciiFrameScript.JADE)
	record_close_button=Button.new();record_close_button.name="NarrativeRecordClose";record_close_button.text="[X]"
	record_close_button.custom_minimum_size=Vector2(TOUCH_TARGET,TOUCH_TARGET)
	record_close_button.pressed.connect(_close_record_modal.bind("BUTTON"));header.add_child(record_close_button)
	AsciiFrameScript.apply_rail_button(record_close_button,AsciiFrameScript.CYAN)
	var scroll:=ScrollContainer.new();scroll.name="NarrativeRecordScroll";scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;stack.add_child(scroll)
	record_body=Label.new();record_body.name="NarrativeRecordBody";record_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	record_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;record_body.add_theme_font_size_override("font_size",FONT_AUX)
	record_body.mouse_filter=Control.MOUSE_FILTER_IGNORE;scroll.add_child(record_body)

func _build_species_picker()->void:
	species_picker_modal=Control.new();species_picker_modal.name="SpeciesPickerModal"
	species_picker_modal.visible=false;species_picker_modal.mouse_filter=Control.MOUSE_FILTER_STOP
	species_picker_modal.z_index=80;species_picker_modal.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT);add_child(species_picker_modal)
	var scrim:=ColorRect.new();scrim.color=Color("#000306e8")
	scrim.mouse_filter=Control.MOUSE_FILTER_STOP
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);species_picker_modal.add_child(scrim)
	species_picker_panel=PanelContainer.new();species_picker_panel.name="SpeciesPickerPanel"
	species_picker_panel.add_theme_stylebox_override("panel",
		AsciiFrameScript.borderless_surface(AsciiFrameScript.SURFACE_DEEP,8))
	species_picker_modal.add_child(species_picker_panel)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",6)
	species_picker_panel.add_child(stack)
	var title:=Label.new();title.text="종족 선택";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",FONT_SECTION);stack.add_child(title)
	var help:=Label.new();help.text="새 원정의 주인공 종족을 선택하세요."
	help.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;stack.add_child(help)
	species_picker_buttons=VBoxContainer.new();species_picker_buttons.name="SpeciesPickerButtons"
	species_picker_buttons.add_theme_constant_override("separation",4);stack.add_child(species_picker_buttons)
	for species_id in GrowthBuildRegistryScript.picker_species_ids():
		var definition:=GrowthBuildRegistryScript.species_definition(species_id)
		var button:=Button.new();button.name="Species_%s"%species_id
		button.text=str(definition.label);button.custom_minimum_size=Vector2(220,TOUCH_TARGET)
		button.set_meta("species_id",species_id);button.focus_mode=Control.FOCUS_ALL
		button.pressed.connect(_commit_species_picker.bind(species_id))
		species_picker_buttons.add_child(button);AsciiFrameScript.apply_rail_button(
			button,AsciiFrameScript.BRASS if species_id=="human" else AsciiFrameScript.CYAN)

func show_species_picker_for_new_run()->void:
	if species_picker_modal==null:_build_species_picker()
	_species_picker_committed=false;species_picker_modal.visible=true
	if grid!=null:grid.modal_open=true
	_layout_floating_surfaces()

func _commit_species_picker(species_id:String)->void:
	if _species_picker_committed or species_picker_modal==null \
			or not species_picker_modal.visible:return
	_species_picker_committed=true
	var result:Dictionary=session.start_new_run_with_species(species_id) if session!=null else {}
	if not bool(result.get("accepted",false)):
		_species_picker_committed=false;return
	species_picker_modal.visible=false
	if grid!=null:grid.modal_open=false
	_reset_run_ui_transients();_request_refresh()

func _build_build_label()->void:
	build_label=Label.new();build_label.name="BuildLabel";build_label.text=BuildInfoScript.display_text()
	build_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;build_label.clip_text=true
	build_label.z_index=1
	build_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	build_label.vertical_alignment=VERTICAL_ALIGNMENT_BOTTOM
	build_label.add_theme_font_size_override("font_size",FONT_MICRO)
	build_label.add_theme_color_override("font_color",AsciiFrameScript.MUTED)
	build_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	add_child(build_label);_position_build_label()

func _position_build_label()->void:
	if build_label==null:return
	if event_surface!=null and event_surface.visible and event_surface.size.x>0.0:
		build_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var local_event_position:=event_surface.global_position-global_position
		build_label.position=Vector2(local_event_position.x+maxf(0.0,event_surface.size.x-98.0),
			local_event_position.y+maxf(0.0,event_surface.size.y-16.0))
		build_label.size=Vector2(92,16)
		return
	build_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var bottom_clearance:=4.0
	if combat_action_area!=null and combat_action_area.visible:
		bottom_clearance=maxf(bottom_clearance,float(combat_action_area.custom_minimum_size.y)+4.0)
		var action_top:=combat_action_area.global_position.y-global_position.y
		if action_top>0.0 and action_top<size.y:
			bottom_clearance=maxf(bottom_clearance,size.y-action_top+4.0)
	build_label.offset_left=-110.0;build_label.offset_right=-6.0
	build_label.offset_bottom=-bottom_clearance;build_label.offset_top=-bottom_clearance-16.0

func _build_duel_decision_lab_entry()->void:
	duel_lab_button=Button.new();duel_lab_button.name="DuelDecisionLabButton"
	duel_lab_button.text="5인 관찰 실험";duel_lab_button.tooltip_text="다섯 캐릭터 판단 관찰 LAB 열기"
	duel_lab_button.add_theme_font_size_override("font_size",FONT_BODY)
	duel_lab_button.custom_minimum_size=Vector2(116,44)
	duel_lab_button.pressed.connect(_open_duel_decision_lab);duel_lab_button.visible=false
	phase_row.add_child(duel_lab_button)

func _open_duel_decision_lab()->void:
	if is_inside_tree():get_tree().change_scene_to_file(DUEL_DECISION_LAB_SCENE_PATH)

func _open_npc_expedition_lab()->void:
	if is_inside_tree():get_tree().change_scene_to_file(NPC_EXPEDITION_LAB_SCENE_PATH)

func _build_tile_popover()->void:
	tile_popover=PanelContainer.new();tile_popover.name="TileRiskPopover";tile_popover.visible=false
	tile_popover.mouse_filter=Control.MOUSE_FILTER_IGNORE;tile_popover.z_index=20;add_child(tile_popover)
	tile_popover.add_theme_stylebox_override("panel",AsciiFrameScript.borderless_surface(AsciiFrameScript.BLACK,0))
	var popover_frame=AsciiFrameScript.new();popover_frame.name="TileRiskAsciiFrame"
	popover_frame.configure("지형",AsciiFrameScript.CYAN,AsciiFrameScript.BLACK,true);tile_popover.add_child(popover_frame)
	tile_popover_label=Label.new();tile_popover_label.name="TileRiskText";tile_popover_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	tile_popover_label.add_theme_font_size_override("font_size",FONT_AUX);tile_popover_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	popover_frame.add_child(tile_popover_label)

func _build_member_detail_modal()->void:
	member_detail_modal=Control.new();member_detail_modal.name="MemberDetailModal";member_detail_modal.visible=false
	member_detail_modal.mouse_filter=Control.MOUSE_FILTER_STOP;member_detail_modal.z_index=40
	member_detail_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(member_detail_modal)
	var scrim:=ColorRect.new();scrim.name="MemberDetailScrim";scrim.color=AsciiFrameScript.BLACK
	scrim.mouse_filter=Control.MOUSE_FILTER_STOP;scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(_on_member_detail_backdrop_input);member_detail_modal.add_child(scrim)
	member_detail_panel=PanelContainer.new();member_detail_panel.name="MemberDetailPanel";member_detail_panel.mouse_filter=Control.MOUSE_FILTER_STOP
	member_detail_panel.clip_contents=true
	var panel_style:=AsciiFrameScript.borderless_surface(AsciiFrameScript.BLACK,0)
	member_detail_panel.add_theme_stylebox_override("panel",panel_style);member_detail_modal.add_child(member_detail_panel)
	var folio_frame=AsciiFrameScript.new();folio_frame.name="MemberDetailAsciiFrame"
	folio_frame.configure("인물",AsciiFrameScript.CYAN,AsciiFrameScript.BLACK,false)
	folio_frame.set_meta("major_glyph_frame",true);member_detail_panel.add_child(folio_frame)
	var stack:=VBoxContainer.new();stack.name="MemberDetailStack";stack.add_theme_constant_override("separation",4);folio_frame.add_child(stack)
	var header:=HBoxContainer.new();header.name="MemberDetailHeader";header.custom_minimum_size.y=52
	header.add_theme_constant_override("separation",6);stack.add_child(header)
	member_detail_glyph_seal=Label.new();member_detail_glyph_seal.name="MemberDetailGlyphSeal"
	member_detail_glyph_seal.custom_minimum_size=Vector2(44,44)
	member_detail_glyph_seal.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	member_detail_glyph_seal.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	member_detail_glyph_seal.add_theme_font_override("font",AsciiFrameScript.CodingFontBold)
	member_detail_glyph_seal.add_theme_font_size_override("font_size",32)
	member_detail_glyph_seal.add_theme_color_override("font_color",AsciiFrameScript.CYAN)
	header.add_child(member_detail_glyph_seal)
	var title_stack:=VBoxContainer.new();title_stack.name="MemberDetailIdentity"
	title_stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title_stack.add_theme_constant_override("separation",0);header.add_child(title_stack)
	member_detail_title=Label.new();member_detail_title.name="MemberDetailTitle";member_detail_title.add_theme_font_size_override("font_size",FONT_KEY)
	member_detail_title.add_theme_font_override("font",AsciiFrameScript.CodingFontBold)
	member_detail_title.add_theme_color_override("font_color",AsciiFrameScript.INK)
	member_detail_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;member_detail_title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;title_stack.add_child(member_detail_title)
	member_detail_subtitle=Label.new();member_detail_subtitle.name="MemberDetailSubtitle"
	AsciiFrameScript.label_tone(member_detail_subtitle,Color("#8ca4ae"),FONT_AUX);title_stack.add_child(member_detail_subtitle)
	member_detail_close=Button.new();member_detail_close.name="MemberDetailClose";member_detail_close.text="[X]"
	member_detail_close.custom_minimum_size=Vector2(44,TOUCH_TARGET)
	member_detail_close.add_theme_font_size_override("font_size",FONT_COMMAND)
	member_detail_close.gui_input.connect(_on_member_detail_close_input.bind(member_detail_close))
	member_detail_close.pressed.connect(_close_member_detail);header.add_child(member_detail_close)
	AsciiFrameScript.apply_rail_button(member_detail_close,AsciiFrameScript.CYAN)
	member_detail_tab_row=HBoxContainer.new();member_detail_tab_row.name="MemberDetailTabs"
	member_detail_tab_row.custom_minimum_size.y=TOUCH_TARGET;member_detail_tab_row.add_theme_constant_override("separation",6)
	stack.add_child(member_detail_tab_row)
	member_detail_status_tab=Button.new();member_detail_status_tab.name="MemberStatusTab";member_detail_status_tab.text="상태"
	member_detail_status_tab.toggle_mode=true;member_detail_status_tab.custom_minimum_size=Vector2(0,TOUCH_TARGET)
	member_detail_status_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_status_tab.tooltip_text="현재 상태와 관계 정보";member_detail_status_tab.pressed.connect(_select_member_detail_tab.bind("STATUS"))
	member_detail_tab_row.add_child(member_detail_status_tab);AsciiFrameScript.apply_rail_button(member_detail_status_tab,AsciiFrameScript.BRASS,true)
	member_detail_skill_tab=Button.new();member_detail_skill_tab.name="MemberSkillTab";member_detail_skill_tab.text="숙련"
	member_detail_skill_tab.toggle_mode=true;member_detail_skill_tab.custom_minimum_size=Vector2(0,TOUCH_TARGET)
	member_detail_skill_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_skill_tab.tooltip_text="무기 숙련 효과와 훈련 설정";member_detail_skill_tab.pressed.connect(_select_member_detail_tab.bind("SKILL"))
	member_detail_tab_row.add_child(member_detail_skill_tab);AsciiFrameScript.apply_rail_button(member_detail_skill_tab,AsciiFrameScript.BRASS)
	member_detail_item_tab=Button.new();member_detail_item_tab.name="MemberItemTab";member_detail_item_tab.text="아이템"
	member_detail_item_tab.toggle_mode=true;member_detail_item_tab.custom_minimum_size=Vector2(0,TOUCH_TARGET)
	member_detail_item_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_item_tab.tooltip_text="장착 무기와 탄약";member_detail_item_tab.pressed.connect(_select_member_detail_tab.bind("ITEM"))
	member_detail_tab_row.add_child(member_detail_item_tab);AsciiFrameScript.apply_rail_button(member_detail_item_tab,AsciiFrameScript.BRASS)
	member_detail_scroll=ScrollContainer.new();member_detail_scroll.name="MemberDetailScroll";member_detail_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	member_detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	member_detail_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	member_detail_scroll.scroll_deadzone=12;member_detail_scroll.follow_focus=false
	member_detail_scroll.clip_contents=true;stack.add_child(member_detail_scroll)
	member_detail_scroll_content=VBoxContainer.new();member_detail_scroll_content.name="MemberDetailContent"
	member_detail_scroll_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	# ScrollContainer must follow the active folio's real minimum rather than
	# retaining an old tall allocation after STATUS/SKILL → ITEM.
	member_detail_scroll_content.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	member_detail_scroll_content.add_theme_constant_override("separation",8)
	member_detail_scroll.add_child(member_detail_scroll_content)
	member_detail_tab_stash=Node.new();member_detail_tab_stash.name="MemberDetailTabStash"
	member_detail_modal.add_child(member_detail_tab_stash)
	_build_progression_window(member_detail_scroll_content)
	_build_item_window(member_detail_scroll_content)
	member_status_window=VBoxContainer.new();member_status_window.name="MemberStatusWindow"
	member_status_window.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_status_window.add_theme_constant_override("separation",8);member_detail_scroll_content.add_child(member_status_window)
	member_detail_body=Label.new();member_detail_body.name="MemberDetailBody";member_detail_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	member_detail_body.add_theme_font_size_override("font_size",FONT_AUX);member_detail_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_body.mouse_filter=Control.MOUSE_FILTER_IGNORE;member_detail_scroll_content.add_child(member_detail_body)
	member_detail_dismiss=Button.new();member_detail_dismiss.name="MemberDetailDismiss"
	member_detail_dismiss.text="[D 추방]";member_detail_dismiss.custom_minimum_size=Vector2(120,TOUCH_TARGET)
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
	member_progression_window.add_theme_constant_override("separation",4);member_progression_window.visible=false
	parent.add_child(member_progression_window)
	var summary:=VBoxContainer.new();summary.name="ProgressionSummary";summary.custom_minimum_size.y=72
	summary.add_theme_constant_override("separation",2);member_progression_window.add_child(summary)
	member_progression_xp_text=Label.new();member_progression_xp_text.name="ProgressionXPText"
	member_progression_xp_text.add_theme_font_size_override("font_size",FONT_SECTION)
	member_progression_xp_text.clip_text=true;member_progression_xp_text.max_lines_visible=1
	member_progression_xp_text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;summary.add_child(member_progression_xp_text)
	member_progression_xp=_gauge("ProgressionXPBar","XP",0,100,12,AsciiFrameScript.YELLOW)
	summary.add_child(member_progression_xp)
	member_progression_stats=Label.new();member_progression_stats.name="DerivedCombatStats"
	member_progression_stats.add_theme_font_size_override("font_size",FONT_AUX);member_progression_stats.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	member_progression_stats.max_lines_visible=1;member_progression_stats.clip_text=true;summary.add_child(member_progression_stats)
	member_skill_help=Label.new();member_skill_help.name="SkillFocusHelp"
	member_skill_help.text="행 터치: 집중×3 → 보통×1 → 끄기×0"
	member_skill_help.add_theme_font_size_override("font_size",FONT_AUX);member_skill_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	member_skill_help.max_lines_visible=1;member_skill_help.clip_text=true
	member_skill_help.modulate=AsciiFrameScript.MUTED;member_progression_window.add_child(member_skill_help)
	member_skill_category_button=Button.new();member_skill_category_button.name="WeaponMasteryCategory"
	member_skill_category_button.custom_minimum_size.y=TOUCH_TARGET
	member_skill_category_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_skill_category_button.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
	member_skill_category_button.focus_mode=Control.FOCUS_NONE
	member_skill_category_button.clip_text=true
	member_skill_category_button.pressed.connect(_toggle_weapon_mastery_category)
	member_progression_window.add_child(member_skill_category_button)
	AsciiFrameScript.apply_rail_button(member_skill_category_button,AsciiFrameScript.CYAN)
	for skill_id in ["SWORD","AXE","BLUNT","SPEAR","RANGED","UNARMED"]:
		var panel:=PanelContainer.new();panel.name="SkillCard%s"%skill_id
		panel.custom_minimum_size.y=TOUCH_TARGET;panel.clip_contents=true
		panel.set_meta("fixed_single_line_ledger",true)
		panel.add_theme_stylebox_override("panel",AsciiFrameScript.borderless_surface(AsciiFrameScript.SURFACE,0))
		member_progression_window.add_child(panel)
		var ledger:=HBoxContainer.new();ledger.name="SkillLedgerRow"
		ledger.mouse_filter=Control.MOUSE_FILTER_IGNORE;ledger.add_theme_constant_override("separation",4)
		panel.add_child(ledger)
		var rank:=Label.new();rank.name="SkillRank";rank.custom_minimum_size.x=34
		rank.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;rank.add_theme_font_size_override("font_size",FONT_AUX)
		rank.add_theme_color_override("font_color",AsciiFrameScript.INK);rank.mouse_filter=Control.MOUSE_FILTER_IGNORE
		ledger.add_child(rank)
		var skill_name:=Label.new();skill_name.name="SkillName";skill_name.custom_minimum_size.x=44
		skill_name.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;skill_name.add_theme_font_size_override("font_size",FONT_AUX)
		skill_name.add_theme_color_override("font_color",AsciiFrameScript.INK);skill_name.mouse_filter=Control.MOUSE_FILTER_IGNORE
		ledger.add_child(skill_name)
		var effect:=Label.new();effect.name="CurrentEffect";effect.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		effect.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;effect.add_theme_font_size_override("font_size",FONT_AUX)
		effect.add_theme_color_override("font_color",AsciiFrameScript.INK);effect.clip_text=true
		effect.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;effect.mouse_filter=Control.MOUSE_FILTER_IGNORE
		ledger.add_child(effect)
		var mode:=Label.new();mode.name="TrainingMode";mode.custom_minimum_size.x=82
		mode.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;mode.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		mode.add_theme_font_size_override("font_size",FONT_AUX);mode.mouse_filter=Control.MOUSE_FILTER_IGNORE
		ledger.add_child(mode)
		var xp:=Label.new();xp.name="TrainingXP";xp.custom_minimum_size.x=54
		xp.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;xp.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		xp.add_theme_font_size_override("font_size",FONT_AUX);xp.add_theme_color_override("font_color",AsciiFrameScript.MUTED)
		xp.mouse_filter=Control.MOUSE_FILTER_IGNORE;ledger.add_child(xp)
		var title:=Button.new();title.name="SkillModeButton";title.custom_minimum_size.y=TOUCH_TARGET
		title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.set_meta("skill_id",skill_id)
		title.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE;title.focus_mode=Control.FOCUS_NONE
		title.flat=true;title.text="";title.tooltip_text="훈련 모드 변경"
		title.pressed.connect(_on_training_mode_cycle.bind(skill_id));panel.add_child(title)
		_apply_skill_ledger_style(title,mode,"NORMAL",false)
		member_progression_skill_rows[skill_id]={"panel":panel,"title":title,
			"rank":rank,"name":skill_name,"effect":effect,"mode":mode,"xp":xp}
		panel.visible=member_skill_category_expanded
	_update_weapon_mastery_category_label()

func _build_item_window(parent:VBoxContainer)->void:
	member_item_window=VBoxContainer.new();member_item_window.name="ItemWindow"
	member_item_window.visible=false;member_item_window.add_theme_constant_override("separation",8)
	parent.add_child(member_item_window)
	var weapon_panel:=PanelContainer.new();weapon_panel.name="EquippedWeaponCard"
	weapon_panel.add_theme_stylebox_override("panel",AsciiFrameScript.borderless_surface(AsciiFrameScript.SURFACE,4))
	member_item_window.add_child(weapon_panel)
	var weapon_stack:=VBoxContainer.new();weapon_stack.add_theme_constant_override("separation",5);weapon_panel.add_child(weapon_stack)
	member_item_weapon_text=Label.new();member_item_weapon_text.name="EquippedWeaponText"
	member_item_weapon_text.add_theme_font_override("font",AsciiFrameScript.CodingFontBold)
	member_item_weapon_text.add_theme_font_size_override("font_size",FONT_SECTION)
	member_item_weapon_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;weapon_stack.add_child(member_item_weapon_text)
	var stats_grid:=GridContainer.new();stats_grid.name="EquippedWeaponStats";stats_grid.columns=2
	stats_grid.add_theme_constant_override("h_separation",8);stats_grid.add_theme_constant_override("v_separation",4);weapon_stack.add_child(stats_grid)
	for stat_id in ["FORM","DAMAGE","RANGE","TIME"]:
		var stat:=Label.new();stat.name="Weapon%sStat"%stat_id.capitalize();stat.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		stat.add_theme_font_size_override("font_size",FONT_BODY);stats_grid.add_child(stat);member_item_stats[stat_id]=stat
	member_item_ammo_text=Label.new();member_item_ammo_text.name="AmmoPoolsText"
	member_item_ammo_text.custom_minimum_size.y=TOUCH_TARGET
	member_item_ammo_text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	member_item_ammo_text.add_theme_font_size_override("font_size",FONT_AUX);weapon_stack.add_child(member_item_ammo_text)
	member_item_reload_button=Button.new();member_item_reload_button.name="ReloadWeaponButton"
	member_item_reload_button.text="재장전";member_item_reload_button.custom_minimum_size.y=TOUCH_TARGET
	member_item_reload_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_item_reload_button.pressed.connect(_on_item_reload);weapon_stack.add_child(member_item_reload_button)
	AsciiFrameScript.apply_rail_button(member_item_reload_button,AsciiFrameScript.BRASS)
	# Keep the selected item's full numbers above the long 5-slot/12-row ledger.
	# Putting this below the backpack made the information technically present but
	# invisible until the player scrolled to the very end.
	member_item_selected_stats=Label.new();member_item_selected_stats.name="SelectedItemStats"
	member_item_selected_stats.visible=false;member_item_selected_stats.custom_minimum_size.y=42
	member_item_selected_stats.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	member_item_selected_stats.add_theme_font_size_override("font_size",FONT_AUX)
	member_item_selected_stats.add_theme_color_override("font_color",AsciiFrameScript.INK)
	member_item_window.add_child(member_item_selected_stats)
	var equipment_title:=_card_label("장비 슬롯","ItemEquipmentHeading",FONT_SECTION)
	equipment_title.add_theme_color_override("font_color",AsciiFrameScript.CYAN)
	member_item_window.add_child(equipment_title)
	member_item_equipment_rows=VBoxContainer.new();member_item_equipment_rows.name="ItemEquipmentLedger"
	member_item_equipment_rows.add_theme_constant_override("separation",2);member_item_window.add_child(member_item_equipment_rows)
	member_item_quick_unequip_button=Button.new()
	member_item_quick_unequip_button.name="ItemQuickUnequip"
	member_item_quick_unequip_button.text="[해제]"
	member_item_quick_unequip_button.custom_minimum_size.y=TOUCH_TARGET
	member_item_quick_unequip_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_item_quick_unequip_button.visible=false
	member_item_quick_unequip_button.pressed.connect(_on_item_unequip_selected)
	member_item_window.add_child(member_item_quick_unequip_button)
	AsciiFrameScript.apply_rail_button(member_item_quick_unequip_button,AsciiFrameScript.BRASS)
	var backpack_title:=_card_label("가방 0 / 12","ItemBackpackHeading",FONT_SECTION)
	backpack_title.add_theme_color_override("font_color",AsciiFrameScript.CYAN)
	member_item_window.add_child(backpack_title)
	member_item_backpack_rows=VBoxContainer.new();member_item_backpack_rows.name="ItemBackpackLedger"
	member_item_backpack_rows.add_theme_constant_override("separation",2);member_item_window.add_child(member_item_backpack_rows)
	member_item_action_row=HBoxContainer.new();member_item_action_row.name="ItemActionRow"
	member_item_action_row.add_theme_constant_override("separation",4);member_item_window.add_child(member_item_action_row)
	member_item_equip_button=_item_action_button("[장착]","ItemEquip",_on_item_equip_selected)
	member_item_unequip_button=_item_action_button("[해제]","ItemUnequip",_on_item_unequip_selected)
	member_item_use_button=_item_action_button("[사용]","ItemUse",_on_item_use_selected)
	member_item_drop_button=_item_action_button("[버리기]","ItemDrop",_on_item_drop_selected)
	member_item_empty_text=backpack_title

func _item_action_button(label:String,node_name:String,callable:Callable)->Button:
	var button:=Button.new();button.name=node_name;button.text=label
	button.custom_minimum_size.y=TOUCH_TARGET;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.pressed.connect(callable);member_item_action_row.add_child(button)
	AsciiFrameScript.apply_rail_button(button,AsciiFrameScript.BRASS);return button

func _build_product_zoom_controls()->void:
	grid_zoom_controls=HBoxContainer.new();grid_zoom_controls.name="ProductZoomControls"
	grid_zoom_controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grid_zoom_controls.offset_left=-160;grid_zoom_controls.offset_right=-4
	grid_zoom_controls.offset_top=4;grid_zoom_controls.offset_bottom=48
	grid_zoom_controls.custom_minimum_size=Vector2(156,TOUCH_TARGET)
	grid_zoom_controls.add_theme_constant_override("separation",0)
	grid_zoom_controls.mouse_filter=Control.MOUSE_FILTER_IGNORE
	grid_zoom_controls.z_index=80;grid_zoom_controls.visible=false
	grid.add_child(grid_zoom_controls)
	grid_graphics_mode_button=Button.new();grid_graphics_mode_button.name="GraphicsModeToggle"
	grid_graphics_mode_button.text="[2D]";grid_graphics_mode_button.tooltip_text="그래픽 모드 · ASCII 재질형 2D"
	grid_graphics_mode_button.custom_minimum_size=Vector2(68,TOUCH_TARGET)
	grid_graphics_mode_button.mouse_filter=Control.MOUSE_FILTER_STOP
	grid_graphics_mode_button.add_theme_font_size_override("font_size",FONT_CAPTION)
	grid_graphics_mode_button.pressed.connect(_on_product_graphics_mode_toggle)
	grid_zoom_controls.add_child(grid_graphics_mode_button)
	AsciiFrameScript.apply_rail_button(grid_graphics_mode_button,AsciiFrameScript.BRASS)
	grid_zoom_out_button=Button.new();grid_zoom_out_button.name="ProductZoomOut"
	grid_zoom_out_button.text="[-]";grid_zoom_out_button.tooltip_text="시야 축소"
	grid_zoom_out_button.custom_minimum_size=Vector2(TOUCH_TARGET,TOUCH_TARGET)
	grid_zoom_out_button.mouse_filter=Control.MOUSE_FILTER_STOP
	grid_zoom_out_button.add_theme_font_size_override("font_size",FONT_CAPTION)
	grid_zoom_out_button.pressed.connect(_on_product_zoom_step.bind(1))
	grid_zoom_controls.add_child(grid_zoom_out_button)
	AsciiFrameScript.apply_rail_button(grid_zoom_out_button,AsciiFrameScript.CYAN)
	grid_zoom_in_button=Button.new();grid_zoom_in_button.name="ProductZoomIn"
	grid_zoom_in_button.text="[+]";grid_zoom_in_button.tooltip_text="시야 확대"
	grid_zoom_in_button.custom_minimum_size=Vector2(TOUCH_TARGET,TOUCH_TARGET)
	grid_zoom_in_button.mouse_filter=Control.MOUSE_FILTER_STOP
	grid_zoom_in_button.add_theme_font_size_override("font_size",FONT_CAPTION)
	grid_zoom_in_button.pressed.connect(_on_product_zoom_step.bind(-1))
	grid_zoom_controls.add_child(grid_zoom_in_button)
	AsciiFrameScript.apply_rail_button(grid_zoom_in_button,AsciiFrameScript.CYAN)

func _layout_floating_surfaces()->void:
	_position_build_label()
	if member_detail_panel!=null:
		var panel_width:=minf(size.x-24.0,420.0 if size.x>=450.0 else 336.0)
		var panel_height:=minf(size.y-24.0,720.0)
		member_detail_panel.position=(size-Vector2(panel_width,panel_height))*0.5
		member_detail_panel.size=Vector2(panel_width,panel_height)
		member_detail_body.custom_minimum_size.x=maxf(1.0,panel_width-48.0)
	if record_panel!=null:
		var record_width:=minf(size.x-24.0,420.0)
		var record_height:=minf(size.y-24.0,620.0)
		record_panel.position=(size-Vector2(record_width,record_height))*0.5
		record_panel.size=Vector2(record_width,record_height)
	if species_picker_panel!=null:
		var picker_width:=minf(size.x-24.0,360.0)
		var picker_height:=minf(size.y-24.0,360.0)
		species_picker_panel.position=(size-Vector2(picker_width,picker_height))*0.5
		species_picker_panel.size=Vector2(picker_width,picker_height)
	if tile_popover!=null and tile_popover.visible:_position_tile_popover()

func _refresh()->void:
	_refresh_pending=false
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
			route_generation+=1;_clear_route_continue_schedule()
			route_preview.clear();grid.clear_route_overlay();_hide_tile_popover()
	var presentation:Dictionary=session.presentation_state()
	var combat_active:=str(status.view_mode)=="COMBAT"
	var combat_actions_visible:=safe_phase=="ENGAGED" and not bool(status.terminal) \
		or run_terminal or _run_locked_exit_feedback
	var party_rows:Array=session.party_cards()
	var product_hud:=_is_solo_product_session()
	# SOLO keeps one continuous dungeon surface. CONTACT/ENGAGED remain internal
	# turn authority, not a taller combat panel or a visible mode switch.
	if product_hud and safe_phase=="ENGAGED":
		combat_actions_visible=run_terminal or _run_locked_exit_feedback
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
	phase_panel.visible=not product_hud
	minimap_frame.visible=false;minimap.visible=false;recent_event_label.visible=false
	top_hud_actions.visible=false
	ascii_3d_lab_button.visible=not product_hud
	event_surface.visible=product_hud;bottom_navigation.visible=product_hud
	hud_bottom_flex.visible=product_hud
	info_scroll.visible=not product_hud
	_apply_product_root_order(product_hud)
	var card_layout:=party_card_layout_spec(party_rows.size(),size.x)
	_apply_screen_budget(combat_active,combat_actions_visible,run_available,run_terminal,
		int(card_layout.get("party_height",160)))
	cards.visible=true
	if selected_member_id not in status.party_member_ids:selected_member_id=int(status.protagonist_id)
	if selected_target_id not in status.visible_enemy_ids:selected_target_id=-1
	if not pending_move_mode.is_empty() and pending_move_mode!=str(status.view_mode):_clear_move_preview()
	_apply_phase_banner(status,presentation)
	var deployment:Dictionary=session.deployment_draft()
	var ghosts:Array=deployment.placements if str(status.view_mode)=="ENCOUNTER_PREVIEW" \
		and not _is_solo_product_session() else []
	_sync_product_zoom_controls(product_hud)
	var view_cell_count:=_current_grid_view_cell_count()
	var ui_observation:Dictionary=session.observe_party_ui(view_cell_count)
	var observation:Dictionary=ui_observation.get("grid",{})
	var direct_solo_combat:=_is_direct_solo_combat(status)
	# A one-member product turn commits on the touched actor/cell. There is no
	# pending plan to annotate; keeping old intent/cursor marks here made the
	# already-authoritative result look as though it still awaited confirmation.
	var intent_overlays:Array=session.turn_intent_overlays() \
		if combat_active and not run_complete and not direct_solo_combat else []
	grid.set_observation(observation,ghosts)
	minimap.set_observation(ui_observation.get("minimap",{}))
	if product_hud:
		var hero_position:=Vector2i(int(status.protagonist_position[0]),
			int(status.protagonist_position[1]))
		grid.set_hero_centered_view(hero_position,view_cell_count,int(status.protagonist_id))
	else:grid.set_view_window(15)
	var grid_style:Dictionary=presentation.get("grid_style",{}).duplicate(true)
	if product_hud:grid_style["vignette"]=false
	grid.set_neutral_phase_map(product_hud)
	grid.set_presentation_style(grid_style)
	if direct_solo_combat:selected_target_id=-1
	grid.set_selection(selected_member_id,selected_target_id)
	grid.set_intent_overlays(intent_overlays)
	var world_speeches:Array=[]
	if not run_complete and session.has_method("world_speech_bubbles"):
		world_speeches=session.world_speech_bubbles()
	grid.set_speech_bubbles(world_speeches)
	if run_complete:
		route_generation+=1;_clear_route_continue_schedule();route_preview.clear()
		grid.clear_route_overlay();_clear_companion_follow_plan();_clear_move_preview()
	elif str(status.view_mode)=="EXPLORATION":
		var route_state:Dictionary=session.exploration_route_state()
		var state_matches_local:=route_preview.is_empty() or _route_goal(route_state)==_route_goal(route_preview)
		if bool(route_state.get("has_preview",false)) \
				and not bool(route_state.get("completed",false)) \
				and not bool(route_state.get("terminal",false)) and state_matches_local:
			route_preview=route_state.duplicate(true);_apply_route_overlay(route_state);_apply_companion_follow_plan(route_state)
		elif route_preview.is_empty() or not bool(route_preview.get("accepted",false)):
			grid.clear_route_overlay();_clear_companion_follow_plan()
	else:
		grid.clear_route_overlay();_clear_companion_follow_plan()
	if direct_solo_combat:
		grid.clear_route_overlay();grid.clear_cursor_preview()
	elif pending_move_actor_id>0:grid.set_cursor_preview(pending_move_actor_id,pending_move_origin,pending_move_destination,pending_move_valid)
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
	_position_build_label();call_deferred("_position_build_label")
	if _run_locked_exit_feedback and not run_terminal and safe_phase!="ENGAGED":
		combat_action_area.custom_minimum_size.y=TOUCH_TARGET
	if run_complete:_run_complete_deck(run_progress)
	else:
		match str(status.view_mode):
			"EXPLORATION":_exploration_deck()
			"ENCOUNTER_PREVIEW":
				# Product solo resolves CONTACT at the refresh boundary and keeps the
				# same map/HUD shell. Never construct a hidden entry screen as a fallback.
				if not _is_solo_product_session():_deployment_deck(deployment)
			"COMBAT":_combat_deck(status,session.current_turn_preview())
			"REGROUP":_legacy_regroup_notice()
	if run_terminal and not product_hud:_build_run_restart_area()
	if product_hud:_build_product_controls_dock(status)
	var combat_history:Dictionary=session.combat_log(8,80)
	log_label.text=_combat_log_text(combat_history)
	log_label.visible=not product_hud and _narrative_log_visible
	log_label.max_lines_visible=1 if combat_active else 3
	deck.visible=not product_hud and not _narrative_log_visible
	if product_hud:
		event_label.text=_compact_meaningful_event_text(combat_history,status)
		if not _product_auto_stop_feedback.is_empty():
			event_label.text=_product_auto_stop_feedback
			_product_auto_stop_feedback=""
		if _run_locked_exit_feedback and not action_feedback_text.is_empty():
			event_label.text=action_feedback_text
		if record_modal.visible:
			record_body.text=_full_meaningful_record_text(session.combat_log(64,500))
	record_button.button_pressed=_narrative_log_visible
	AsciiFrameScript.apply_rail_button(record_button,AsciiFrameScript.CYAN,_narrative_log_visible)
	_update_recent_event(combat_history,status)
	if _scroll_log_after_refresh:
		_scroll_log_after_refresh=false;call_deferred("_scroll_information_to_latest_log")
	_flush_pending_visual_effects()

func _apply_product_root_order(product_hud:bool)->void:
	if product_hud:
		root_layout.move_child(cards,0);root_layout.move_child(grid,1)
		root_layout.move_child(event_surface,2);root_layout.move_child(hud_bottom_flex,3)
		# Keep the two interactive bottom surfaces as the final direct siblings.
		# The transparent flex consumes only otherwise-unused height before them.
		root_layout.move_child(combat_action_area,root_layout.get_child_count()-1)
		root_layout.move_child(bottom_navigation,root_layout.get_child_count()-1)
	else:
		hud_bottom_flex.visible=false
		root_layout.move_child(phase_panel,0);root_layout.move_child(grid,1)
		root_layout.move_child(cards,2);root_layout.move_child(info_scroll,3)
		root_layout.move_child(combat_action_area,4)

func _refresh_direct_solo_combat_surface(status:Dictionary)->void:
	# The stable one-member combat shell does not need to destroy and recreate
	# every card, button and dossier after each turn. Refresh the authoritative
	# world projection and mutate the few live HUD values whose data can change.
	var profile_started:=Time.get_ticks_usec()
	grid.cancel_pointer_gesture()
	var presentation:Dictionary=session.presentation_state()
	var party_rows:Array=session.party_cards()
	var observe_started:=Time.get_ticks_usec()
	var view_cell_count:=_current_grid_view_cell_count()
	var ui_observation:Dictionary=session.observe_party_ui(view_cell_count)
	var observe_finished:=Time.get_ticks_usec()
	grid.set_observation(ui_observation.get("grid",{}),[])
	minimap.set_observation(ui_observation.get("minimap",{}))
	var hero_position:=Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	grid.set_hero_centered_view(hero_position,view_cell_count,int(status.protagonist_id),
		MANUAL_CAMERA_SETTLE_MSEC)
	var grid_style:Dictionary=presentation.get("grid_style",{}).duplicate(true)
	grid_style["vignette"]=false
	grid.set_neutral_phase_map(true);grid.set_presentation_style(grid_style)
	grid.set_selection(selected_member_id,-1);grid.set_intent_overlays([])
	grid.clear_route_overlay();grid.clear_cursor_preview();_clear_companion_follow_plan()
	var grid_finished:=Time.get_ticks_usec()
	_update_direct_solo_card(party_rows)
	notice_text="";action_feedback_text=""
	action_feedback_label.text="행동 선택 → 즉시 실행"
	for node_name in ["TurnSummary","IntentLegend","SelectedMemberDetail","ExpectedAction"]:
		var stale:=deck.find_child(node_name,true,false)
		if stale!=null:stale.visible=false
	var action_status:=deck.find_child("ActionStatus",true,false) as Label
	if action_status!=null:action_status.text="적 공격 · 빈 칸 이동 · 하단 방어"
	var combat_history:Dictionary=session.combat_log(8,80)
	log_label.text=_combat_log_text(combat_history)
	_update_recent_event(combat_history,status)
	event_label.text=_compact_meaningful_event_text(combat_history,status)
	if record_modal.visible:
		record_body.text=_full_meaningful_record_text(session.combat_log(64,500))
	var hud_finished:=Time.get_ticks_usec()
	_sync_product_control_state(status)
	var effect_count:=_flush_pending_visual_effects()
	var finished:=Time.get_ticks_usec()
	_last_direct_solo_refresh_profile={
		"observe_ui_usec":observe_finished-observe_started,
		"grid_minimap_usec":grid_finished-observe_finished,
		"stable_hud_usec":hud_finished-grid_finished,
		"effects_usec":finished-hud_finished,"effect_count":effect_count,
		"total_usec":finished-profile_started,
	}.duplicate(true)

func _refresh_continuous_exploration_surface(status:Dictionary,
		continuous_motion:bool=false)->void:
	# AUTO and long routes already have a stable exploration shell. Rebuilding
	# cards and every dock button after each canonical hop delays the next hop and
	# adds no new interaction state. Update only live world/HUD data; a phase
	# transition still falls back to the full refresh below.
	var safe_phase:=str(status.get("safe_phase",""))
	var run_progress:=_current_run_progress()
	var run_terminal:=bool(run_progress.get("available",false)) \
		and (bool(run_progress.get("complete",false)) \
			or bool(run_progress.get("terminal",false)))
	if str(status.get("view_mode",""))!="EXPLORATION" \
			or bool(status.get("terminal",false)) or run_terminal \
			or safe_phase not in ["GROUPED","GROUPED_COMPLETE"] \
			or not _action_feedback_phase.is_empty() and _action_feedback_phase!=safe_phase:
		_refresh();return
	var started_usec:=Time.get_ticks_usec()
	var observe_started_usec:=Time.get_ticks_usec()
	var view_cell_count:=_current_grid_view_cell_count()
	var ui_observation:Dictionary=session.observe_party_ui(view_cell_count)
	var observe_finished_usec:=Time.get_ticks_usec()
	grid.set_observation(ui_observation.get("grid",{}),[])
	minimap.set_observation(ui_observation.get("minimap",{}))
	var hero_position:=Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	if _is_solo_product_session():
		grid.set_hero_centered_view(hero_position,view_cell_count,int(status.protagonist_id),
			CONTINUOUS_CAMERA_SETTLE_MSEC if continuous_motion \
			else MANUAL_CAMERA_SETTLE_MSEC)
	else:grid.set_view_window(15)
	grid.set_selection(selected_member_id,-1);grid.set_intent_overlays([])
	grid.set_speech_bubbles(session.world_speech_bubbles() \
		if session.has_method("world_speech_bubbles") else [])
	var route_state:Dictionary=session.exploration_route_state()
	if bool(route_state.get("has_preview",false)) \
			and not bool(route_state.get("completed",false)) \
			and not bool(route_state.get("terminal",false)):
		route_preview=route_state.duplicate(true);_apply_route_state(route_state)
		_apply_companion_follow_plan(route_state)
	else:
		route_preview.clear();grid.clear_route_overlay();grid.clear_cursor_preview()
		_clear_companion_follow_plan()
	var grid_finished_usec:=Time.get_ticks_usec()
	_update_stable_party_cards(session.party_cards())
	var combat_history:Dictionary=session.combat_log(8,80)
	log_label.text=_combat_log_text(combat_history)
	_update_recent_event(combat_history,status)
	if _is_solo_product_session():
		event_label.text=_compact_meaningful_event_text(combat_history,status)
		if not _product_auto_stop_feedback.is_empty():
			event_label.text=_product_auto_stop_feedback
			_product_auto_stop_feedback=""
	else:
		_update_action_feedback(status)
	_sync_product_control_state(status)
	var hud_finished_usec:=Time.get_ticks_usec()
	var effect_count:=_flush_pending_visual_effects()
	var finished_usec:=Time.get_ticks_usec()
	_last_continuous_exploration_refresh_profile={
		"observe_ui_usec":observe_finished_usec-observe_started_usec,
		"grid_minimap_usec":grid_finished_usec-observe_finished_usec,
		"stable_hud_usec":hud_finished_usec-grid_finished_usec,
		"effects_usec":finished_usec-hud_finished_usec,
		"effect_count":effect_count,"total_usec":finished_usec-started_usec,
	}.duplicate(true)

func _update_direct_solo_card(rows:Array)->void:
	if not rows.is_empty() and rows[0] is Dictionary:_update_stable_party_card(rows[0])

func _update_stable_party_cards(rows:Array)->void:
	for row in rows:
		if row is Dictionary:_update_stable_party_card(row)

func _update_stable_party_card(row:Dictionary)->void:
	var card:=cards.find_child("MemberCard%d"%int(row.get("entity_id",-1)),true,false)
	if card==null:return
	var health:=card.find_child("MemberState",true,false)
	if health!=null and health.has_method("configure"):
		var current:=int(row.get("health",0));var maximum:=maxi(1,int(row.get("max_health",1)))
		health.call("configure_semantic","HP",current,maximum,10,
			AsciiFrameScript.RED if current*4<=maximum else AsciiFrameScript.GREEN)
	var stress:=card.find_child("StressState",true,false) as Label
	if stress!=null:stress.text="ST %d"%int(row.get("stress",0))
	var emotion:Dictionary=row.get("emotion",{}) if row.get("emotion",{}) is Dictionary else {}
	var state:=card.find_child("EmotionState",true,false) as Label
	if state!=null:
		state.text="%s%s · %s"%[str(emotion.get("icon","")),
			str(emotion.get("label","평온")),"준비" if str(row.get("readiness","행동 준비"))=="행동 준비" else "행동중"]
	var progression:Dictionary=row.get("progression",{}) if row.get("progression",{}) is Dictionary else {}
	var level_label:=card.find_child("LevelProgress",true,false) as Label
	if level_label!=null and bool(progression.get("available",false)):
		var level:=int(progression.get("level",1))
		if level_label.text.begins_with("LV "):level_label.text="LV %02d"%level
		elif level_label.text.begins_with("LV"):level_label.text="LV%02d"%level
		else:
			var stats:Dictionary=progression.get("combat_stats",{}) \
				if progression.get("combat_stats",{}) is Dictionary else {}
			level_label.text="Lv.%d · 공 %d / 방 %d · 태세 %d%%"%[level,
				int(stats.get("attack_power",0)),int(stats.get("armor_flat",0)),
				int(int(stats.get("guard_reduction_milli",250))/10)]
	var xp:=card.find_child("CompactXPBar",true,false)
	if xp!=null and xp.has_method("configure") and bool(progression.get("available",false)):
		xp.call("configure_semantic","XP",int(progression.get("xp_current",0)),
			maxi(1,int(progression.get("xp_required",1))),5,AsciiFrameScript.YELLOW)
	elif xp is Range and bool(progression.get("available",false)):
		xp.max_value=maxi(1,int(progression.get("xp_required",1)))
		xp.value=int(progression.get("xp_current",0))
		xp.tooltip_text="XP %d/%d"%[int(progression.get("xp_current",0)),
			int(progression.get("xp_required",1))]

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
	if deck!=null:deck.visible=not _narrative_log_visible
	if record_button!=null:
		record_button.button_pressed=_narrative_log_visible
		record_button.tooltip_text="하단 사건 기록 숨기기" if _narrative_log_visible \
			else "하단 사건 기록 표시하기"
	_request_refresh()

func _open_hero_detail()->void:
	_open_hero_detail_tab("STATUS")

func _open_hero_detail_tab(tab_id:String)->void:
	if session==null:return
	var status:Dictionary=session.party_status()
	var hero_id:=int(status.get("protagonist_id",-1))
	if hero_id>0:_open_member_detail(hero_id,tab_id)

func _toggle_map_overlay()->void:
	if map_overlay.visible:
		map_overlay.close("TOGGLE");return
	_product_attack_targeting=false
	_cancel_product_auto_explore("auto_explore_modal",false)
	_cancel_route_for_user_interruption()
	if record_modal.visible:_close_record_modal("MAP")
	var observation:Dictionary=session.observe_party_ui(15).get("minimap",{})
	map_overlay.set_observation(observation)
	grid.cancel_pointer_gesture();grid.modal_open=true
	map_nav_button.set_pressed_no_signal(true);map_overlay.open()
	_sync_product_zoom_controls(_is_solo_product_session())

func _on_map_overlay_closed(_reason:String)->void:
	map_nav_button.set_pressed_no_signal(false)
	grid.modal_open=member_detail_modal.visible or record_modal.visible
	_sync_product_zoom_controls(_is_solo_product_session())
	route_paused_by_modal=false
	if auto_orchestration_enabled:_request_refresh()

func _toggle_record_modal()->void:
	if record_modal.visible:
		_close_record_modal("TOGGLE");return
	_product_attack_targeting=false
	_cancel_product_auto_explore("auto_explore_modal",false)
	_cancel_route_for_user_interruption()
	if map_overlay.visible:map_overlay.close("HISTORY")
	var history:Dictionary=session.combat_log(64,500)
	record_body.text=_full_meaningful_record_text(history)
	grid.cancel_pointer_gesture();grid.modal_open=true
	record_modal.visible=true;history_nav_button.set_pressed_no_signal(true)
	_sync_product_zoom_controls(_is_solo_product_session())
	_layout_floating_surfaces()
	if record_close_button.is_inside_tree():record_close_button.grab_focus()

func _close_record_modal(_reason:String="API")->void:
	if not record_modal.visible:return
	record_modal.visible=false;history_nav_button.set_pressed_no_signal(false)
	grid.modal_open=member_detail_modal.visible or map_overlay.visible
	_sync_product_zoom_controls(_is_solo_product_session())
	route_paused_by_modal=false
	if auto_orchestration_enabled:_request_refresh()

func _on_record_backdrop_input(event:InputEvent)->void:
	if event is InputEventScreenTouch and event.pressed:_close_record_modal("OUTSIDE")
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index==MOUSE_BUTTON_LEFT:_close_record_modal("OUTSIDE")

func _open_ascii_3d_lab()->void:
	if ascii_3d_lab_view!=null and is_instance_valid(ascii_3d_lab_view):return
	if auto_orchestration_enabled:_cancel_auto_pending(true)
	_cancel_product_auto_explore("auto_explore_modal",false)
	_cancel_route_for_user_interruption()
	grid.cancel_pointer_gesture();grid.modal_open=true
	ascii_3d_lab_view=ASCII_3D_LAB_SCENE.instantiate();ascii_3d_lab_view.name="Ascii3DLabOverlay"
	ascii_3d_lab_view.z_index=100;add_child(ascii_3d_lab_view)
	ascii_3d_lab_view.close_requested.connect(_close_ascii_3d_lab)
	_sync_product_zoom_controls(_is_solo_product_session())

func _close_ascii_3d_lab()->void:
	if ascii_3d_lab_view==null or not is_instance_valid(ascii_3d_lab_view):return
	ascii_3d_lab_view.queue_free();ascii_3d_lab_view=null
	grid.modal_open=false
	_sync_product_zoom_controls(_is_solo_product_session())
	route_paused_by_modal=false
	if auto_orchestration_enabled:_request_refresh()

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
			# A one-member product turn has no companion suggestion surface and commits
			# directly from the next tap. Preparing a placeholder plan here duplicated a
			# large canonical preview without producing any visible or authoritative work.
			if _is_direct_solo_combat(status):return
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
	var effective_count:=clampi(count,0,SessionScript.ACTIVE_PARTY_LIMIT)
	if effective_count==0:
		return {"layout_id":"EMPTY","requested_count":count,"effective_count":0,
			"party_height":0,"gap":0,"card_min_width":0,
			"portrait_min_size":[0,0],"portrait_removed":true,"font_size":FONT_AUX}.duplicate(true)
	var gap:=4
	var available_width:=maxi(44,int(floor(viewport_width))-12-gap*(effective_count-1))
	var spec:Dictionary={"layout_id":"COMPACT","requested_count":count,
		"effective_count":effective_count,"party_height":84,"gap":gap,
		"card_min_width":maxi(44,int(floor(float(available_width)/effective_count))),
		"portrait_min_size":[0,0],"portrait_removed":true,"font_size":FONT_AUX}
	if effective_count==1:
		spec.layout_id="SPOTLIGHT";spec.party_height=68
	elif effective_count==2:
		spec.layout_id="DUAL";spec.party_height=80
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
	var spec:=layout_spec if not layout_spec.is_empty() else party_card_layout_spec(
		SessionScript.ACTIVE_PARTY_LIMIT,size.x)
	var button:=Button.new(); var member_id:=int(row.entity_id); button.name="MemberCard%d"%member_id
	button.custom_minimum_size=Vector2(float(spec.get("card_min_width",44)),float(spec.get("party_height",160)))
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.size_flags_stretch_ratio=1.0
	button.text=""; button.clip_contents=true
	AsciiFrameScript.apply_rail_button(button,AsciiFrameScript.CYAN,false)
	var inset:=MarginContainer.new(); inset.name="CardContent"; inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for margin in ["margin_left","margin_right","margin_top","margin_bottom"]:
		var inset_amount:=0
		if _is_solo_product_session():
			# Three compact dossier rows naturally consume the whole 84px strip.
			# Keep horizontal breathing room without making the content 2px taller
			# than its touch/card surface.
			inset_amount=2 if margin in ["margin_left","margin_right"] else 1
		inset.add_theme_constant_override(margin,inset_amount)
	inset.mouse_filter=Control.MOUSE_FILTER_IGNORE
	# PartyCards is the single outer rail; per-member nested glyph frames consumed
	# most of an 80/84px strip and forced its measured content outside the button.
	button.add_child(inset)
	_add_compact_dossier_content(inset,row,speech,spec)
	button.gui_input.connect(_on_member_card_gui_input.bind(member_id,str(row.display_name),button))
	button.pressed.connect(_on_member_card_pressed.bind(member_id,str(row.display_name))); cards.add_child(button)

func _add_compact_dossier_content(inset:MarginContainer,row:Dictionary,speech:Dictionary,spec:Dictionary)->void:
	var root:=HBoxContainer.new();root.name="SpotlightDetails" if int(spec.get("effective_count",1))==1 else "CardIdentity"
	root.clip_contents=true
	root.add_theme_constant_override("separation",4);root.mouse_filter=Control.MOUSE_FILTER_IGNORE;inset.add_child(root)
	var count:=int(spec.get("effective_count",1));var seal_size:=44 if count==1 else (40 if count==2 else 34)
	var seal:=Label.new();seal.name="ActorGlyphSeal";seal.text=_actor_seal_glyph(row)
	seal.custom_minimum_size=Vector2(seal_size,seal_size);seal.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	seal.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;seal.add_theme_font_override("font",AsciiFrameScript.CodingFontBold)
	seal.add_theme_font_size_override("font_size",28 if count==1 else (24 if count==2 else 20))
	seal.add_theme_color_override("font_color",AsciiFrameScript.CYAN if str(row.get("role",""))=="PROTAGONIST" else AsciiFrameScript.MUTED)
	seal.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(seal)
	var stack:=VBoxContainer.new();stack.name="DossierText";stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	stack.clip_contents=true
	stack.add_theme_constant_override("separation",0);stack.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(stack)
	var progression:Dictionary=row.get("progression",{}) if row.get("progression",{}) is Dictionary else {}
	var identity:=HBoxContainer.new();identity.name="SoloIdentity";identity.add_theme_constant_override("separation",4);stack.add_child(identity)
	var selected:=int(row.get("entity_id",-1))==selected_member_id
	var display_name:=("> " if selected else "")+str(row.get("display_name","파티원"))
	var name_label:=_card_label(display_name,"MemberName",FONT_BODY if count<=2 else FONT_AUX)
	name_label.add_theme_font_override("font",AsciiFrameScript.CodingFontBold)
	name_label.add_theme_color_override("font_color",AsciiFrameScript.BRASS if selected else AsciiFrameScript.INK)
	name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;identity.add_child(name_label)
	var level_label:=_card_label("LV%02d"%int(progression.get("level",1)),"LevelProgress",FONT_AUX)
	level_label.add_theme_color_override("font_color",AsciiFrameScript.BRASS);identity.add_child(level_label)
	var hp_current:=int(row.get("health",0));var hp_max:=maxi(1,int(row.get("max_health",1)));var low_hp:=hp_current*4<=hp_max
	var health_gauge:Control=_gauge("MemberState","HP",hp_current,hp_max,8 if count>=3 else 10,
		AsciiFrameScript.RED if low_hp else AsciiFrameScript.GREEN)
	health_gauge.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stack.add_child(health_gauge)
	var emotion:Dictionary=row.get("emotion",{}) if row.get("emotion",{}) is Dictionary else {}
	var readiness:="준비" if str(row.get("readiness","행동 준비"))=="행동 준비" else "행동중"
	var footer:=HBoxContainer.new();footer.name="DossierVitals";footer.add_theme_constant_override("separation",3);stack.add_child(footer)
	# Status, stress and XP share one compact ledger line. Keeping emotion on its
	# own line made a companion speech strip exceed the fixed 80/84px cards.
	var state_label:=_card_label("%s%s · %s"%[str(emotion.get("icon","")),str(emotion.get("label","평온")),readiness],"EmotionState",FONT_AUX)
	state_label.max_lines_visible=1;state_label.clip_text=true
	state_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	state_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(state_label)
	var ready_label:=_card_label(readiness,"Readiness",FONT_AUX);ready_label.visible=false;footer.add_child(ready_label)
	var stress_label:=_card_label("ST %d"%int(row.get("stress",0)),"StressState",FONT_AUX);footer.add_child(stress_label)
	if bool(progression.get("available",false)):
		var xp_gauge:Control=_gauge("CompactXPBar","XP",int(progression.get("xp_current",0)),maxi(1,int(progression.get("xp_required",1))),5,AsciiFrameScript.YELLOW)
		xp_gauge.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(xp_gauge)
	if str(row.get("role",""))=="COMPANION" and not speech.is_empty():_add_companion_speech_strip(stack,speech)

func _actor_seal_glyph(actor:Dictionary)->String:
	# Dossier seals share the map identity grammar; equipment stays separate.
	return "@" if bool(actor.get("is_protagonist",false)) \
		or str(actor.get("role","")).to_upper()=="PROTAGONIST" else \
		AsciiMaterialGrammarScript.species_bare_glyph(str(actor.get("species_id","human")))

func _add_spotlight_card_content(inset:MarginContainer,row:Dictionary,speech:Dictionary)->void:
	var stack:=VBoxContainer.new();stack.name="CardStack";stack.add_theme_constant_override("separation",1)
	stack.mouse_filter=Control.MOUSE_FILTER_IGNORE;inset.add_child(stack)
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
	name_label.add_theme_font_override("font",AsciiFrameScript.CodingFontBold)
	name_label.add_theme_color_override("font_color",AsciiFrameScript.INK)
	name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	identity.add_child(name_label)
	var level_label:=_card_label("LV %02d"%int(progression.get("level",1)),"LevelProgress",FONT_AUX)
	level_label.add_theme_color_override("font_color",AsciiFrameScript.BRASS)
	level_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;identity.add_child(level_label)
	var hp_current:=int(row.get("health",0));var hp_max:=maxi(1,int(row.get("max_health",1)))
	var low_hp:=hp_current*4<=hp_max
	var health_gauge:Control=_gauge("MemberState","HP",hp_current,hp_max,10,
		AsciiFrameScript.RED if low_hp else AsciiFrameScript.GREEN)
	health_gauge.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(health_gauge)
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
		var xp_gauge:Control=_gauge("CompactXPBar","XP",int(progression.get("xp_current",0)),
			maxi(1,int(progression.get("xp_required",1))),10,AsciiFrameScript.YELLOW)
		xp_gauge.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(xp_gauge)

func _add_stacked_card_content(inset:MarginContainer,row:Dictionary,speech:Dictionary)->void:
	var stack:=VBoxContainer.new(); stack.name="CardStack"; stack.add_theme_constant_override("separation",0); stack.mouse_filter=Control.MOUSE_FILTER_IGNORE; inset.add_child(stack)
	if str(row.get("role",""))=="COMPANION" and not speech.is_empty():_add_companion_speech_strip(stack,speech)
	var identity:=VBoxContainer.new();identity.name="CardIdentity";identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation",0);identity.mouse_filter=Control.MOUSE_FILTER_IGNORE;stack.add_child(identity)
	var name_label:=_card_label(str(row.display_name),"MemberName",FONT_AUX)
	name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	identity.add_child(name_label)
	var ready_label:=_card_label("준비" if str(row.readiness)=="행동 준비" else "행동중","Readiness",FONT_AUX)
	ready_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;identity.add_child(ready_label)
	var emotion_label:=_card_label("%s%s"%[str(row.emotion.icon),str(row.emotion.label)],"EmotionState",FONT_AUX)
	emotion_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;emotion_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	identity.add_child(emotion_label)
	_add_vitals(stack,row,false)

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
	var product_strip:=_is_solo_product_session()
	var strip:=PanelContainer.new();strip.name="CompanionSpeechStrip"
	strip.custom_minimum_size.y=16 if product_strip else 22
	strip.mouse_filter=Control.MOUSE_FILTER_IGNORE;strip.clip_contents=true
	strip.set_meta("actor_id",int(speech.get("actor_id",-1)))
	strip.set_meta("source",str(speech.get("source","SUGGESTED")))
	strip.set_meta("full_reason",str(speech.get("reason","")))
	var source:=str(speech.get("source","SUGGESTED"))
	var style:=AsciiFrameScript.borderless_surface(AsciiFrameScript.NAVY,0 if product_strip else 2)
	strip.add_theme_stylebox_override("panel",style);parent.add_child(strip)
	var text:=Label.new();text.name="CompanionSpeechText"
	text.text="%s · %s"%[str(speech.get("headline","방어할게.")),
		str(speech.get("reason_summary","피해를 줄이려고"))]
	text.max_lines_visible=1;text.clip_text=true
	text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_theme_font_size_override("font_size",FONT_MICRO)
	text.add_theme_color_override("font_color",AsciiFrameScript.RED if source=="OVERRIDE" else AsciiFrameScript.CYAN)
	text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter=Control.MOUSE_FILTER_IGNORE;strip.add_child(text)

func _bar(node_name:String,value:int,maximum:int,color:Color)->ProgressBar:
	var bar:=ProgressBar.new(); bar.name=node_name; bar.min_value=0; bar.max_value=maximum; bar.value=value
	bar.show_percentage=false; bar.custom_minimum_size.y=7; bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	AsciiFrameScript.apply_progress(bar,color);return bar

func _gauge(node_name:String,prefix:String,value:int,maximum:int,columns:int,
		color:Color):
	var gauge=AsciiGaugeScript.new();gauge.name=node_name
	gauge.configure_semantic(prefix,value,maximum,columns,color);return gauge

func _card_label(value:String,node_name:String,font_size:int)->Label:
	var label:=Label.new(); label.name=node_name; label.text=value; label.add_theme_font_size_override("font_size",maxi(FONT_AUX,font_size))
	label.clip_text=true;label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE; return label
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
	# are already visible as dossier cards and remain dismissible from detail.
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
			label.text="영입 후보 · %s · %s"%[str(row.get("display_name","동료")),str(row.get("style_label","동료"))]
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
		if not _is_solo_product_session() \
				and selected_member_id!=int(status.get("protagonist_id",-1)):
			instruction="%s 판단 관찰 · 전투 입력은 주인공 행동으로 처리됩니다."%actor_name
	if not notice_text.is_empty():instruction=notice_text
	elif not bool(preview.get("accepted",false)):instruction+=" · "+str(preview.get("message","주인공 행동을 먼저 지정하세요."))
	_add_notice(instruction)
	if not _is_solo_product_session():_add_party_command_menu(status)
	var direct_solo:=_is_direct_solo_combat(status)
	var lines:Array[String]=[]
	if not direct_solo:
		for line in session.turn_summary_lines():lines.append(str(line))
	if not lines.is_empty():
		var summary_label:=_add_notice("이번 턴 예정\n"+"\n".join(lines),
			"TurnSummary",FONT_BODY)
		summary_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var has_original_suggestion:=false
	if not direct_solo:
		for overlay in session.turn_intent_overlays():
			if overlay.get("automatic_suggestion",null) is Dictionary:has_original_suggestion=true;break
	if has_original_suggestion:
		_add_notice("표시: 주황 실선/□ 개별 지시 · 파랑 점선/○ 원래 자동 제안","IntentLegend",FONT_AUX)
	# The product HUD owns one persistent movement/context dock below the event
	# surface. Keep legacy planning controls for non-product harnesses only.
	if not event_surface.visible:_build_combat_action_area(status,preview)
	_selected_detail()


func _add_party_command_menu(status:Dictionary)->void:
	party_command_menu=MenuButton.new();party_command_menu.name="PartyExceptionCommandMenu"
	var current:Dictionary=status.get("party_command",{})
	var labels:={"ATTACK_TARGET":"표적 지정","RETREAT":"후퇴",
		"STOP_ATTACK":"공격 중지","HOLD_POSITION":"자리 지키기","FOLLOW":"따라오기"}
	var current_id:=str(current.get("command_id","FOLLOW"))
	party_command_menu.text="파티 명령 · %s"%str(labels.get(current_id,"따라오기"))
	party_command_menu.custom_minimum_size.y=TOUCH_TARGET
	party_command_menu.add_theme_font_size_override("font_size",FONT_COMMAND)
	party_command_menu.tooltip_text="평소에는 주인공 행동을 따라 자동 전투합니다. 필요할 때만 예외 명령을 사용합니다."
	AsciiFrameScript.apply_rail_button(party_command_menu,AsciiFrameScript.CYAN)
	var popup:=party_command_menu.get_popup()
	for row in [[0,"공격 대상 지정"],[1,"후퇴"],[2,"공격 중지"],
			[3,"자리 지키기"],[4,"따라오기"]]:
		popup.add_item(str(row[1]),int(row[0]))
	popup.id_pressed.connect(_on_party_command_menu_id)
	deck.add_child(party_command_menu)


func _on_party_command_menu_id(item_id:int)->void:
	if session==null:return
	if item_id==0:
		_party_command_targeting=true
		notice_text="공격 대상으로 지정할 적을 선택하세요."
		action_feedback_text=notice_text;_request_refresh();return
	var command_id:String=str({1:"RETREAT",2:"STOP_ATTACK",3:"HOLD_POSITION",
		4:"FOLLOW"}.get(item_id,""))
	if str(command_id).is_empty():return
	_party_command_targeting=false
	if auto_orchestration_enabled:_cancel_auto_pending(false)
	var result:Dictionary=session.issue_party_command(str(command_id))
	_record_result(result,false,"파티 명령 적용 불가")
	if bool(result.get("accepted",false)):
		notice_text="파티 명령 · %s"%str(result.get("command_label",command_id))
		action_feedback_text=notice_text
	_request_refresh()

func _legacy_regroup_notice()->void:_add_notice("승리했습니다. 호환 상태를 자동 재집결 처리하는 중입니다.","ActionStatus",FONT_KEY)

func _build_combat_action_area(status:Dictionary,preview:Dictionary)->void:
	if str(status.safe_phase)!="ENGAGED":return
	combat_action_area.visible=true;combat_action_dock.visible=true
	if auto_orchestration_enabled:
		_build_auto_combat_action_area(status);return
	var guard_percent:=_guard_percent_for_actor(selected_member_id)
	if not action_feedback_text.is_empty():action_feedback_label.text=action_feedback_text
	elif bool(preview.get("accepted",false)):action_feedback_label.text="행동 준비 완료 · 필요하면 수정한 뒤 실행하세요."
	else:action_feedback_label.text="행동 지정 → 실행\n이동 · 공격 · 방어(200시간/%d%%)"%guard_percent
	var hold:=_add_button(combat_action_dock,"방어","ActorHold",_on_actor_hold)
	hold.tooltip_text="200 시간 동안 물리 피해를 %d%% 줄입니다."%guard_percent
	hold.size_flags_stretch_ratio=1.0
	var clear:=_add_button(combat_action_dock,"자동 제안 복원","OverrideClear",_on_override_clear)
	clear.size_flags_stretch_ratio=1.35;clear.disabled=selected_member_id==int(status.protagonist_id)
	var confirm:=_add_button(combat_action_dock,"지금 실행","TurnConfirm",_on_turn_confirm)
	confirm.size_flags_stretch_ratio=0.9;confirm.disabled=not bool(preview.get("accepted",false))

func _build_auto_combat_action_area(status:Dictionary)->void:
	var planning:Dictionary=session.auto_combat_planning_state()
	var protagonist_id:=int(status.get("protagonist_id",-1))
	var guard_percent:=_guard_percent_for_actor(protagonist_id)
	if auto_combat_pending:
		action_feedback_label.text="최종 행동을 표시 중입니다." if _is_solo_product_session() \
			else "최종 행동과 동료 제안을 표시 중입니다."
		combat_action_dock.visible=false;return
	if not action_feedback_text.is_empty():action_feedback_label.text=action_feedback_text
	elif bool(planning.get("placeholder",false)):
		action_feedback_label.text="행동 선택 · 방어: 200시간 동안 물리 피해 %d%% 감소"%guard_percent \
			if _is_solo_product_session() else "동료 제안 준비 완료 · 주인공 행동을 선택하세요."
	else:action_feedback_label.text="행동 선택 시 최종 계획을 보여 준 뒤 자동 실행합니다."
	var hold:=_add_button(combat_action_dock,"주인공 방어","ActorHold",_on_actor_hold);hold.size_flags_stretch_ratio=1.0
	hold.tooltip_text="200 시간 동안 물리 피해를 %d%% 줄입니다."%guard_percent
	if bool(planning.get("commit_ready",false)) and (auto_override_edit or auto_combat_fallback):
		var execute:=_add_button(combat_action_dock,"지금 실행","AutoExecute",_on_auto_execute)
		execute.size_flags_stretch_ratio=0.9

func _product_controls_metrics(party_count:int)->Dictionary:
	var wide:=size.x>=450.0
	var gap:=3 if wide else 2
	var target:=44
	if not wide:
		# 360x640 has no spare vertical row: cards + map + event + controls +
		# navigation must all remain inside the viewport.
		var party_height:=int(party_card_layout_spec(party_count,size.x).get("party_height",68))
		var available:=int(size.y)-party_height-int(size.x)-36-TOUCH_TARGET-8
		target=clampi(int(floor(float(available-gap*2)/3.0)),32,40)
	var dock_height:=target*3+gap*2
	return {"target":target,"gap":gap,"dock_height":dock_height}.duplicate(true)

func _build_product_controls_dock(status:Dictionary)->void:
	product_direction_buttons.clear()
	product_attack_button=null;product_pickup_button=null;product_auto_button=null;product_interact_button=null
	product_wait_guard_button=null;product_execute_button=null
	combat_action_area.visible=true;action_feedback_label.visible=false
	combat_action_dock.visible=true;combat_action_area.add_theme_constant_override("separation",0)
	var members:Variant=status.get("party_member_ids",[])
	var party_count:int=members.size() if members is Array else 1
	var metrics:=_product_controls_metrics(party_count)
	var target:=int(metrics.target);var gap:=int(metrics.gap);var dock_height:=int(metrics.dock_height)
	combat_action_area.custom_minimum_size.y=dock_height
	combat_action_dock.custom_minimum_size.y=dock_height
	combat_action_dock.add_theme_constant_override("separation",gap)
	if bool(_current_run_progress().get("terminal",false)):
		product_execute_button=_add_product_context_button(combat_action_dock,
			"[RESTART]","ProductExecute",_on_product_execute,target)
		product_execute_button.disabled=false
		product_execute_button.tooltip_text="같은 원정을 처음부터 다시 시작"
		return
	var dpad:=GridContainer.new();dpad.name="ProductDirectionPad";dpad.columns=3
	dpad.custom_minimum_size=Vector2(dock_height,dock_height)
	dpad.add_theme_constant_override("h_separation",gap);dpad.add_theme_constant_override("v_separation",gap)
	combat_action_dock.add_child(dpad)
	var direction_rows:Array=[
		["ProductMoveNW","↖",Vector2i(-1,-1)],
		["ProductMoveN","↑",Vector2i(0,-1)],
		["ProductMoveNE","↗",Vector2i(1,-1)],
		["ProductMoveW","←",Vector2i(-1,0)],
		["ProductWaitCenter","·",Vector2i.ZERO],
		["ProductMoveE","→",Vector2i(1,0)],
		["ProductMoveSW","↙",Vector2i(-1,1)],
		["ProductMoveS","↓",Vector2i(0,1)],
		["ProductMoveSE","↘",Vector2i(1,1)],
	]
	var can_step:=_product_can_step(status)
	for row in direction_rows:
		var button:=Button.new();button.name=str(row[0]);button.text=str(row[1])
		button.custom_minimum_size=Vector2(target,target)
		button.add_theme_font_size_override("font_size",FONT_SECTION)
		button.focus_mode=Control.FOCUS_NONE;button.disabled=not can_step
		button.set_meta("direction",row[2]);button.set_meta("product_control",true)
		button.gui_input.connect(_on_product_button_gui_input.bind(button.name));dpad.add_child(button)
		AsciiFrameScript.apply_rail_button(button,AsciiFrameScript.CYAN)
		product_direction_buttons[row[2]]=button
	var contextual:=VBoxContainer.new();contextual.name="ProductContextControls"
	contextual.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	contextual.add_theme_constant_override("separation",gap);combat_action_dock.add_child(contextual)
	var primary:=GridContainer.new();primary.name="ProductPrimaryControls";primary.columns=2
	primary.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	primary.add_theme_constant_override("h_separation",gap);contextual.add_child(primary)
	product_attack_button=_add_product_context_button(primary,"[공격]","ProductAttack",
		_on_product_attack,target)
	product_attack_button.tooltip_text="가장 가까운 보이는 적에게 접근하거나 공격합니다."
	product_pickup_button=_add_product_context_button(primary,"[줍기]","ProductPickup",
		_on_product_pickup,target)
	product_pickup_button.tooltip_text="현재 칸에 떨어진 아이템을 가방에 줍습니다."
	var secondary:=GridContainer.new();secondary.name="ProductSecondaryControls";secondary.columns=2
	secondary.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	secondary.add_theme_constant_override("h_separation",gap);secondary.add_theme_constant_override("v_separation",gap)
	contextual.add_child(secondary)
	product_auto_button=_add_product_context_button(secondary,"[AUTO]","ProductAuto",
		_on_product_auto,target)
	product_interact_button=_add_product_context_button(secondary,"[INTERACT]","ProductInteract",
		_on_product_interact,target)
	product_wait_guard_button=_add_product_context_button(secondary,
		"[GUARD]" if str(status.get("view_mode",""))=="COMBAT" else "[WAIT]",
		"ProductWaitGuard",_on_product_wait_guard,target)
	product_execute_button=_add_product_context_button(secondary,"[EXECUTE]","ProductExecute",
		_on_product_execute,target)
	product_interact_button.tooltip_text="인접한 인물이나 사물과 상호작용합니다."
	_sync_product_control_state(status)

func _sync_product_control_state(status_override:Dictionary={}) -> void:
	if session==null:return
	var run_terminal:=bool(_current_run_progress().get("terminal",false))
	if product_attack_button==null or not is_instance_valid(product_attack_button):
		if run_terminal and product_execute_button!=null and is_instance_valid(product_execute_button):
			product_execute_button.text="[RESTART]";product_execute_button.disabled=false
		return
	var status:Dictionary=status_override if not status_override.is_empty() else session.party_status()
	var mode:=str(status.get("view_mode",""))
	var terminal:=bool(status.get("terminal",false)) or run_terminal
	var can_step:=_product_can_step(status)
	for button_value in product_direction_buttons.values():
		var direction_button:=button_value as Button
		if direction_button!=null and is_instance_valid(direction_button):
			direction_button.disabled=not can_step
			direction_button.tooltip_text="적 방향이면 이동 대신 범프 공격" \
				if mode=="COMBAT" else "한 칸 이동"
	# Product ATTACK is a one-turn DCSS-style Tab command. It remains enabled with
	# no target so the player receives explicit fog-safe feedback rather than an
	# unexplained inert control.
	product_attack_button.disabled=terminal
	if terminal:_product_attack_targeting=false
	var equipment:Dictionary=session.protagonist_equipment() \
		if session.has_method("protagonist_equipment") else {}
	var ranged:=int(equipment.get("range_max",1))>1
	product_attack_button.text="[사격]" if ranged else "[공격]"
	if ranged:
		product_attack_button.tooltip_text= \
			"가장 가까운 보이는 적을 %d–%d칸 거리에서 사격하거나 사거리까지 접근합니다." \
			%[int(equipment.get("range_min",2)),int(equipment.get("range_max",2))]
	else:product_attack_button.tooltip_text= \
		"가장 가까운 보이는 적에게 한 칸 접근하거나 공격합니다."
	product_pickup_button.disabled=terminal or not mode in ["EXPLORATION","COMBAT"]
	var ground_items:Array=session.ground_items_at_protagonist() \
		if session.has_method("ground_items_at_protagonist") else []
	product_pickup_button.text="[줍기 %d]"%ground_items.size() \
		if ground_items.size()>1 else "[줍기]"
	product_pickup_button.tooltip_text="현재 칸의 %s을(를) 가방에 줍습니다." \
		%str(ground_items[0].get("label","아이템")) if not ground_items.is_empty() \
		else "현재 칸에 아이템이 없으면 턴을 소비하지 않습니다."
	product_interact_button.disabled=true
	var protagonist_id:=int(status.get("protagonist_id",-1))
	var opening:Dictionary=session.opening_event_status() \
		if session.has_method("opening_event_status") else {}
	var opening_choice:=bool(opening.get("can_interact",false))
	if opening_choice:
		if event_label!=null:
			event_label.text=str(opening.get("scene_summary",
				"부상당한 여행자가 벽에 기대 숨을 몰아쉬고 있습니다."))
		product_auto_button.toggle_mode=false
		product_auto_button.set_pressed_no_signal(false)
		product_auto_button.text="[물약 주기]"
		product_auto_button.disabled=not bool(opening.get("give_enabled",false))
		product_auto_button.tooltip_text="회복 물약 1개를 건네 실제 체력을 회복시킵니다."
		product_interact_button.text="[돕지 않기]"
		product_interact_button.disabled=not bool(opening.get("pass_enabled",false))
		product_interact_button.tooltip_text="여행자를 돕지 않고 원정을 계속합니다."
		product_auto_button.custom_minimum_size.y=maxf(44.0,
			product_auto_button.custom_minimum_size.y)
		product_interact_button.custom_minimum_size.y=maxf(44.0,
			product_interact_button.custom_minimum_size.y)
	elif mode=="EXPLORATION":
		product_interact_button.text="[INTERACT]"
		var auto_state:Dictionary=session.auto_explore_state() if session.has_method("auto_explore_state") else {}
		product_auto_button.disabled=terminal or not session.has_method("start_auto_explore")
		product_auto_button.toggle_mode=true
		product_auto_button.set_pressed_no_signal(bool(auto_state.get("running",false)))
		product_auto_button.text="[AUTO ■]" if bool(auto_state.get("running",false)) else "[AUTO]"
		product_auto_button.tooltip_text="안전한 발견 지점까지 자동 탐험"
	else:
		var reload_weapon:=bool(equipment.get("reload_required",false))
		product_interact_button.text="[RELOAD]" if reload_weapon else "[INTERACT]"
		product_interact_button.disabled=(terminal \
			or not bool(equipment.get("can_reload",false))) if reload_weapon else true
		if reload_weapon:
			if bool(equipment.get("loaded",false)):
				product_interact_button.tooltip_text="쇠뇌가 장전되어 있습니다."
			else:product_interact_button.tooltip_text= \
				"쇠뇌를 장전합니다. 볼트 %d개 · %d시간" \
				%[int(equipment.get("bolts",0)),int(equipment.get("reload_time",0))]
		product_auto_button.toggle_mode=false;product_auto_button.set_pressed_no_signal(false)
		product_auto_button.text="[AUTO]"
		product_auto_button.disabled=terminal or mode!="COMBAT" or selected_member_id==protagonist_id
		product_auto_button.tooltip_text="선택한 동료를 자동 제안으로 되돌립니다."
	product_wait_guard_button.text="[WAIT]" if _is_solo_product_session() \
		else ("[GUARD]" if mode=="COMBAT" else "[WAIT]")
	product_wait_guard_button.disabled=terminal or not mode in ["EXPLORATION","COMBAT"]
	if mode=="COMBAT":
		var guard_actor:=selected_member_id if selected_member_id>0 else protagonist_id
		product_wait_guard_button.tooltip_text="200 시간 동안 물리 피해를 %d%% 줄입니다." \
			%_guard_percent_for_actor(guard_actor)
	else:
		product_wait_guard_button.tooltip_text="현재 위치에서 한 턴 대기합니다."
	var planning:Dictionary=session.auto_combat_planning_state() if mode=="COMBAT" else {}
	product_execute_button.text="[RESTART]" if run_terminal else "[EXECUTE]"
	product_execute_button.disabled=false if run_terminal else (terminal or mode!="COMBAT" \
		or _is_direct_solo_combat(status) or not bool(planning.get("commit_ready",false)))

func _add_product_context_button(parent:Control,label:String,node_name:String,
		_callback:Callable,target:int)->Button:
	var button:=Button.new();button.name=node_name;button.text=label
	button.custom_minimum_size=Vector2(target,target)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size",FONT_COMMAND)
	button.focus_mode=Control.FOCUS_NONE;button.set_meta("product_control",true)
	button.gui_input.connect(_on_product_button_gui_input.bind(node_name));parent.add_child(button)
	var accent:=AsciiFrameScript.BRASS if node_name in ["ProductAttack","ProductExecute"] else AsciiFrameScript.CYAN
	AsciiFrameScript.apply_rail_button(button,accent)
	return button

func _product_can_step(status:Dictionary)->bool:
	if bool(status.get("terminal",false)) or bool(_current_run_progress().get("terminal",false)):return false
	var mode:=str(status.get("view_mode",""))
	return mode=="EXPLORATION" or mode=="COMBAT" and str(status.get("safe_phase",""))=="ENGAGED"

func _product_adjacent_enemy_id(status:Dictionary,destination:Vector2i=Vector2i(-999,-999))->int:
	var rows:=_product_adjacent_enemies(status,destination)
	return int(rows[0]) if not rows.is_empty() else -1

func _product_adjacent_enemies(status:Dictionary,
		destination:Vector2i=Vector2i(-999,-999))->Array[int]:
	var result:Array[int]=[]
	var origin:=_selected_position()
	if origin.x<0 or origin.y<0:
		var raw_origin:Variant=status.get("protagonist_position",[])
		if raw_origin is Array and raw_origin.size()==2:
			origin=Vector2i(int(raw_origin[0]),int(raw_origin[1]))
	var rows:Array=session.enemy_targets();rows.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.get("entity_id",-1))<int(b.get("entity_id",-1)))
	for row in rows:
		var raw:Variant=row.get("position",[])
		if not raw is Array or raw.size()!=2:continue
		var position:=Vector2i(int(raw[0]),int(raw[1]))
		if destination!=Vector2i(-999,-999) and position!=destination:continue
		if maxi(absi(position.x-origin.x),absi(position.y-origin.y))==1:
			result.append(int(row.get("entity_id",-1)))
	return result

func _on_product_direction(direction:Vector2i)->void:
	var status:Dictionary=session.party_status()
	if not _product_can_step(status):return
	if _product_attack_targeting:
		_product_attack_targeting=false
		_show_product_command_feedback("공격 선택을 취소했습니다.")
	if str(status.get("view_mode",""))=="EXPLORATION":
		_cancel_product_auto_explore("auto_explore_user_command",false)
		var active_route:Dictionary=session.exploration_route_state()
		if bool(active_route.get("active",false)) or bool(active_route.get("has_preview",false)):
			_cancel_active_route()
	if direction==Vector2i.ZERO:
		_on_product_wait_guard();return
	if str(status.get("view_mode",""))=="EXPLORATION":
		_on_explore(direction);return
	var destination:=_selected_position()+direction
	var enemy_id:=_product_adjacent_enemy_id(status,destination)
	if enemy_id>0:_on_actor(enemy_id)
	else:_on_cell(destination)

func _on_product_attack()->void:
	var status:Dictionary=session.party_status()
	if bool(status.get("terminal",false)) or bool(_current_run_progress().get("terminal",false)):return
	if not session.has_method("tab_attack_assessment"):
		_show_product_command_feedback("자동 공격을 사용할 수 없습니다.");return
	_cancel_product_auto_explore("auto_explore_user_command",false)
	var route_state:Dictionary=session.exploration_route_state()
	if bool(route_state.get("active",false)) or bool(route_state.get("has_preview",false)):
		_cancel_active_route()
	var assessment:Dictionary=session.tab_attack_assessment()
	if not bool(assessment.get("accepted",false)):
		_product_attack_targeting=false
		_show_product_command_feedback(str(assessment.get("message",
			"시야 안에 공격할 적이 없습니다.")))
		return
	var tab_action:=str(assessment.get("tab_action",""))
	var target_id:=int(assessment.get("target_id",-1))
	match tab_action:
		"ENTER_COMBAT":
			var entered:Dictionary=session.enter_solo_combat()
			if not bool(entered.get("accepted",false)):
				_show_product_command_feedback(str(entered.get("message",
					"전투에 진입할 수 없습니다.")));return
			_on_product_attack()
		"ATTACK":
			_product_attack_targeting=false
			_submit_product_melee(target_id,session.party_status())
		"APPROACH":
			var destination_value:Variant=assessment.get("destination",[])
			if not destination_value is Array or destination_value.size()!=2:
				_show_product_command_feedback("적에게 다가갈 길이 없습니다.");return
			var destination:=Vector2i(int(destination_value[0]),int(destination_value[1]))
			if str(status.get("view_mode",""))=="EXPLORATION":
				_on_cell(destination)
			elif str(status.get("view_mode",""))=="COMBAT":
				_stage_auto_combat_action("MOVE",[destination.x,destination.y])
			else:_show_product_command_feedback("지금은 적에게 다가갈 수 없습니다.")
		_:
			_show_product_command_feedback("자동 공격 행동을 결정할 수 없습니다.")

func _on_product_pickup()->void:
	var status:Dictionary=session.party_status()
	if bool(status.get("terminal",false)) or bool(_current_run_progress().get("terminal",false)):return
	_cancel_product_auto_explore("auto_explore_user_command",false)
	var route_state:Dictionary=session.exploration_route_state()
	if bool(route_state.get("active",false)) or bool(route_state.get("has_preview",false)):
		_cancel_active_route()
	var ground_items:Array=session.ground_items_at_protagonist()
	if ground_items.is_empty():
		_show_product_command_feedback("현재 칸에 주울 아이템이 없습니다.")
		_request_refresh();return
	var item:Dictionary=ground_items[0]
	var result:Dictionary=session.pickup_ground_item(str(item.get("instance_id","")))
	_record_result(result,true,"아이템을 주울 수 없습니다.")
	if bool(result.get("accepted",false)):
		notice_text="%s 확인 · 가방에 주웠습니다. (100시간)"%str(item.get("label","아이템"))
		action_feedback_text=notice_text
		if pending_ground_pickup_id==str(item.get("instance_id","")):
			pending_ground_pickup_id="";pending_ground_pickup_label=""
	_request_refresh()

func _show_product_command_feedback(message:String)->void:
	notice_text=message;action_feedback_text=message
	if event_label!=null:event_label.text=message

func _on_product_auto()->void:
	var opening:Dictionary=session.opening_event_status() \
		if session.has_method("opening_event_status") else {}
	if bool(opening.get("can_interact",false)):
		_cancel_product_auto_explore("auto_explore_interaction_discovered",false)
		var choice_result:Dictionary=session.commit_opening_event_choice("GIVE_POTION")
		_record_result(choice_result,true)
		_show_product_command_feedback("회복 물약을 건넸습니다." \
			if bool(choice_result.get("accepted",false)) else str(choice_result.get("message","물약을 건넬 수 없습니다.")))
		_request_refresh();return
	var status:Dictionary=session.party_status()
	if str(status.get("view_mode",""))=="EXPLORATION":
		if not session.has_method("start_auto_explore"):return
		var state:Dictionary=session.auto_explore_state()
		if bool(state.get("running",false)):
			_cancel_product_auto_explore("auto_explore_user_cancel",true);return
		var route_state:Dictionary=session.exploration_route_state()
		if bool(route_state.get("active",false)) or bool(route_state.get("has_preview",false)):
			_cancel_active_route()
		_product_auto_explore_generation+=1
		var hop_started_msec:=Time.get_ticks_msec()
		_product_auto_last_hop_started_msec=hop_started_msec
		var result:Dictionary=session.start_auto_explore()
		_consume_product_auto_explore_result(result)
		_refresh_continuous_exploration_surface(session.party_status(),true)
		if bool(result.get("running",false)):_schedule_product_auto_explore(hop_started_msec)
		return
	if selected_member_id!=int(status.get("protagonist_id",-1)):_on_override_clear()

func _consume_product_auto_explore_result(result:Dictionary)->void:
	# AUTO state retains the previous route wrapper even on cancel/pre-hop DTOs.
	# Consume effects/log feedback only for the newly advanced hop, then unwrap
	# route-wrapper.last_step_result to the canonical committed result.
	if bool(result.get("advanced",false)):
		var route_wrapper:Variant=result.get("last_step_result",{})
		var canonical_result:Variant=route_wrapper.get("last_step_result",{}) \
			if route_wrapper is Dictionary else {}
		if canonical_result is Dictionary and bool(canonical_result.get("accepted",false)):
			_record_result(canonical_result,true,"",false,
				CONTINUOUS_EXPLORATION_MOTION_MSEC)
	if bool(result.get("running",false)):
		_product_auto_stop_feedback=""
	else:
		var reason:=str(result.get("stop_reason",result.get("reason","auto_explore_stopped")))
		action_feedback_text={
			"auto_explore_user_cancel":"자동 탐험을 멈췄습니다.",
			"auto_explore_combat_contact":"적과 접촉해 자동 탐험을 멈췄습니다.",
			"auto_explore_enemy_visible":"적을 발견해 자동 탐험을 멈췄습니다.",
			"auto_explore_hazard_discovered":"위험 지형을 발견해 자동 탐험을 멈췄습니다.",
			"auto_explore_interaction_discovered":"새 상호작용을 발견해 자동 탐험을 멈췄습니다.",
			"auto_explore_no_frontier":"더 탐험할 안전한 지점이 없습니다.",
		}.get(reason,"자동 탐험을 멈췄습니다.")
		notice_text=action_feedback_text
		_product_auto_stop_feedback=action_feedback_text
		# A hop can atomically enter CONTACT. Preserve this meaningful stop copy
		# across the refresh phase-change guard instead of replacing it with filler.
		if session!=null:_action_feedback_phase=str(session.party_status().get("safe_phase",""))

func _schedule_product_auto_explore(previous_hop_started_msec:int=-1)->void:
	if _product_auto_explore_pending or not is_inside_tree():return
	if not bool(session.auto_explore_state().get("running",false)):return
	_product_auto_explore_pending=true
	_product_auto_explore_due_frame=Engine.get_process_frames()+1
	var cadence_origin:=previous_hop_started_msec if previous_hop_started_msec>=0 \
		else Time.get_ticks_msec()
	_product_auto_explore_due_msec=cadence_origin+maxi(0,continuous_travel_cadence_msec)
	_product_auto_explore_scheduled_generation=_product_auto_explore_generation

func _continue_product_auto_explore(expected_generation:int)->void:
	if expected_generation!=_product_auto_explore_generation:return
	if member_detail_modal.visible or record_modal.visible or map_overlay.visible \
			or bool(grid.pointer_gesture_state().get("active",false)):
		_cancel_product_auto_explore("auto_explore_modal",true);return
	if not bool(session.auto_explore_state().get("running",false)):return
	var hop_started_msec:=Time.get_ticks_msec()
	_product_auto_last_hop_started_msec=hop_started_msec
	var result:Dictionary=session.continue_auto_explore()
	_consume_product_auto_explore_result(result)
	_refresh_continuous_exploration_surface(session.party_status(),true)
	if bool(result.get("running",false)):_schedule_product_auto_explore(hop_started_msec)

func _cancel_product_auto_explore(reason:String,refresh_after:bool)->void:
	_product_auto_explore_generation+=1;_product_auto_explore_pending=false
	_product_auto_explore_due_frame=-1;_product_auto_explore_due_msec=-1
	_product_auto_explore_scheduled_generation=-1
	_product_auto_last_hop_started_msec=-1
	_product_auto_stop_feedback=""
	if session==null or not session.has_method("auto_explore_state"):
		_sync_product_control_state();return
	if bool(session.auto_explore_state().get("running",false)):
		var result:Dictionary=session.cancel_auto_explore(reason)
		_consume_product_auto_explore_result(result)
	_sync_product_control_state()
	if refresh_after:_request_refresh()

func _on_product_interact()->void:
	var status:Dictionary=session.party_status()
	if str(status.get("view_mode",""))=="COMBAT" \
			and session.has_method("protagonist_equipment"):
		var equipment:Dictionary=session.protagonist_equipment()
		if bool(equipment.get("reload_required",false)):
			var reload_result:Dictionary=session.reload_protagonist_weapon()
			notice_text="쇠뇌를 재장전했습니다." \
				if bool(reload_result.get("accepted",false)) \
				else str(reload_result.get("message","재장전할 수 없습니다."))
			action_feedback_text=notice_text
			_sync_product_control_state();_request_refresh();return
	if not session.has_method("opening_event_status") \
			or not bool(session.opening_event_status().get("can_interact",false)):
		return
	_cancel_product_auto_explore("auto_explore_interaction_discovered",false)
	var result:Dictionary=session.commit_opening_event_choice("PASS")
	_record_result(result,true)
	_show_product_command_feedback("여행자를 돕지 않기로 했습니다." \
		if bool(result.get("accepted",false)) else str(result.get("message","선택할 수 없습니다.")))
	_request_refresh()

func _on_product_wait_guard()->void:
	var status:Dictionary=session.party_status()
	if str(status.get("view_mode",""))=="EXPLORATION":
		_cancel_product_auto_explore("auto_explore_user_command",false)
		var active_route:Dictionary=session.exploration_route_state()
		if bool(active_route.get("active",false)) or bool(active_route.get("has_preview",false)):
			_cancel_active_route()
		_on_explore(Vector2i.ZERO)
	elif str(status.get("view_mode",""))=="COMBAT":_on_actor_hold()

func _on_product_execute()->void:
	if bool(_current_run_progress().get("terminal",false)):
		_on_restart_same_run();return
	if auto_orchestration_enabled:_on_auto_execute()
	else:_on_turn_confirm()

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
	if _is_direct_solo_combat(session.party_status()):return
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
	selected_member_id=member_id;selected_target_id=-1;notice_text="%s 선택"%display_name
	action_feedback_text="판단 관찰 · 전투 입력은 주인공 행동으로 처리됩니다." \
		if auto_orchestration_enabled and view_mode=="COMBAT" \
			and member_id!=int(session.party_status().get("protagonist_id",-1)) \
		else "%s 선택 · 행동을 지정하세요."%display_name
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
	var progression:Dictionary=detail.get("progression",{}) if detail.get("progression",{}) is Dictionary else {}
	var vitals:=HBoxContainer.new();vitals.name="StatusVitals";vitals.custom_minimum_size.y=44
	vitals.add_theme_constant_override("separation",8);member_status_window.add_child(vitals)
	var health_bar:Control=_gauge("StatusHealthBar","HP",int(detail.get("health",0)),
		maxi(1,int(detail.get("max_health",1))),4,AsciiFrameScript.GREEN)
	health_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;vitals.add_child(health_bar)
	var stress:=int(detail.get("stress",0))
	var stress_bar:Control=_gauge("StatusStressBar","ST",stress,1000,4,AsciiFrameScript.YELLOW)
	stress_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;vitals.add_child(stress_bar)
	var status_grid:=GridContainer.new();status_grid.name="StatusFolioGrid"
	status_grid.columns=2;status_grid.add_theme_constant_override("h_separation",10)
	status_grid.add_theme_constant_override("v_separation",8);member_status_window.add_child(status_grid)
	var emotion_cluster:=VBoxContainer.new();emotion_cluster.name="EmotionSealCluster"
	emotion_cluster.size_flags_horizontal=Control.SIZE_EXPAND_FILL;emotion_cluster.add_theme_constant_override("separation",3)
	status_grid.add_child(emotion_cluster)
	var emotion_heading:=_card_label("감정 / 스트레스","EmotionSection",FONT_AUX)
	emotion_heading.add_theme_color_override("font_color",AsciiFrameScript.CYAN);emotion_cluster.add_child(emotion_heading)
	var emotion:Dictionary=detail.get("emotion",{}) if detail.get("emotion",{}) is Dictionary else {}
	var emotion_label:=_card_label("[%s%s]"%[str(emotion.get("icon","")),str(emotion.get("label","감정 정보 없음"))],"StatusEmotion",FONT_BODY)
	emotion_label.add_theme_color_override("font_color",AsciiFrameScript.INK);emotion_cluster.add_child(emotion_label)
	var reason:=str(emotion.get("reason","")).strip_edges()
	if not reason.is_empty() and reason!="이유 정보 없음":
		var reason_label:=_card_label(reason,"StatusEmotionReason",FONT_AUX);reason_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		reason_label.modulate=Color("#8fa5ae");emotion_cluster.add_child(reason_label)
	var stress_label:=_card_label("ST %d/1000"%stress,"StatusStress",FONT_AUX);emotion_cluster.add_child(stress_label)
	var combat_cluster:=VBoxContainer.new();combat_cluster.name="CombatSealCluster"
	combat_cluster.size_flags_horizontal=Control.SIZE_EXPAND_FILL;combat_cluster.add_theme_constant_override("separation",3)
	status_grid.add_child(combat_cluster)
	var combat_heading:=_card_label("전투 / 상태","CombatSection",FONT_AUX)
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
	var dossier_heading:=_card_label("특성/내성/노출","StatusDossierSection",FONT_SECTION)
	dossier_heading.add_theme_color_override("font_color",AsciiFrameScript.CYAN);member_status_window.add_child(dossier_heading)

func _life_state_label(life_state:String)->String:
	match life_state:
		"DOWNED":return "쓰러짐"
		"DEAD":return "사망"
		_:return "생존"

func _status_label(status_id:String)->String:
	return {"BLEEDING":"출혈","POISONED":"중독","WET":"젖음","GUARDED":"방어 태세"}.get(status_id,status_id)

func _open_member_detail(member_id:int,initial_tab:String="STATUS")->void:
	if auto_orchestration_enabled:_cancel_auto_pending(true)
	_product_attack_targeting=false
	_cancel_product_auto_explore("auto_explore_modal",false)
	_cancel_route_for_user_interruption()
	var detail:Dictionary=session.inspect_party_member(member_id)
	if not bool(detail.get("accepted",false)):
		notice_text=str(detail.get("message","파티원 상세 정보를 불러올 수 없습니다."));_request_refresh();return
	member_detail_title.text=str(detail.get("display_name","파티원"))
	member_detail_glyph_seal.text=_actor_seal_glyph(detail)
	var detail_progression:Dictionary=detail.get("progression",{}) if detail.get("progression",{}) is Dictionary else {}
	var subtitle_parts:Array[String]=[_species(str(detail.get("species_id","default")))]
	subtitle_parts.append(_role(str(detail.get("role",""))))
	if bool(detail_progression.get("available",false)):subtitle_parts.append("LV%02d"%int(detail_progression.get("level",1)))
	subtitle_parts.append(_life_state_label(str(detail.get("life_state","ACTIVE"))))
	member_detail_subtitle.text=" / ".join(subtitle_parts)
	member_detail_body.text=_member_detail_text(detail)
	_update_member_status_window(detail)
	member_detail_entity_id=member_id
	var progression:Variant=detail.get("progression",{})
	member_detail_has_skills=progression is Dictionary and bool(progression.get("available",false))
	member_detail_current_tab=initial_tab if initial_tab in ["STATUS","SKILL","ITEM"] \
		and (initial_tab=="STATUS" or member_detail_has_skills) else "STATUS"
	_update_progression_window(progression)
	_update_item_window(progression.get("equipment",{}) if progression is Dictionary else {})
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
	_sync_product_zoom_controls(_is_solo_product_session())
	route_paused_by_modal=false
	_layout_floating_surfaces();call_deferred("_measure_member_detail_body")
	if member_detail_close.is_inside_tree():member_detail_close.grab_focus()

func _close_member_detail()->void:
	if member_detail_modal==null or not member_detail_modal.visible:return
	member_detail_modal.visible=false;member_detail_entity_id=-1;_product_attack_targeting=false
	grid.modal_open=record_modal.visible or map_overlay.visible
	_sync_product_zoom_controls(_is_solo_product_session())
	route_paused_by_modal=false
	if auto_orchestration_enabled:_request_refresh()

func _select_member_detail_tab(tab_id:String)->void:
	if tab_id not in ["STATUS","SKILL","ITEM"] \
			or tab_id in ["SKILL","ITEM"] and not member_detail_has_skills:return
	member_detail_current_tab=tab_id;member_detail_scroll.scroll_vertical=0
	_apply_member_detail_tab();_reflow_member_detail_scroll()

func _apply_member_detail_tab()->void:
	var skill_selected:=member_detail_has_skills and member_detail_current_tab=="SKILL"
	var item_selected:=member_detail_has_skills and member_detail_current_tab=="ITEM"
	member_detail_tab_row.visible=member_detail_has_skills
	member_detail_status_tab.set_pressed_no_signal(not skill_selected and not item_selected)
	member_detail_skill_tab.set_pressed_no_signal(skill_selected)
	member_detail_item_tab.set_pressed_no_signal(item_selected)
	member_detail_status_tab.text="[상태]" if not skill_selected and not item_selected else " 상태 "
	member_detail_skill_tab.text="[숙련]" if skill_selected else " 숙련 "
	member_detail_item_tab.text="[아이템]" if item_selected else " 아이템 "
	AsciiFrameScript.apply_rail_button(member_detail_status_tab,AsciiFrameScript.BRASS,not skill_selected and not item_selected)
	AsciiFrameScript.apply_rail_button(member_detail_skill_tab,AsciiFrameScript.BRASS,skill_selected)
	AsciiFrameScript.apply_rail_button(member_detail_item_tab,AsciiFrameScript.BRASS,item_selected)
	member_status_window.visible=not skill_selected and not item_selected
	member_detail_body.visible=not skill_selected and not item_selected
	member_progression_window.visible=skill_selected
	member_item_window.visible=item_selected
	member_detail_dismiss.visible=not skill_selected and not item_selected and member_detail_dismiss_available
	member_detail_candidate_action.visible=not skill_selected and not item_selected and member_detail_candidate_available
	_sync_member_detail_scroll_children()
	_reflow_member_detail_scroll()

func _sync_member_detail_scroll_children()->void:
	if member_detail_scroll_content==null or member_detail_tab_stash==null:return
	var desired:Array[Control]=[]
	if member_item_window.visible:
		desired=[member_item_window]
	elif member_progression_window.visible:
		desired=[member_progression_window]
	else:
		desired=[member_status_window,member_detail_body]
	var managed:Array[Control]=[member_progression_window,member_item_window,
		member_status_window,member_detail_body]
	for control in managed:
		if control==null or control in desired:continue
		if control.get_parent()!=member_detail_tab_stash:control.reparent(member_detail_tab_stash)
	if desired.size()==1:
		# A single tall ITEM/SKILL folio is the ScrollContainer's direct child.
		# Keeping an empty VBoxContainer as an intermediary left its stale cached
		# minimum in the scrollbar range even after the inactive folios moved away.
		if member_detail_scroll_content.get_parent()==member_detail_scroll:
			member_detail_scroll_content.reparent(member_detail_tab_stash)
		var folio:=desired[0]
		if folio.get_parent()!=member_detail_scroll:folio.reparent(member_detail_scroll)
		member_detail_scroll.move_child(folio,0)
		folio.update_minimum_size()
		return
	# STATUS has two independent controls, so retain the shared VBox only for it.
	for index in range(desired.size()):
		var control:=desired[index]
		if control.get_parent()!=member_detail_scroll_content:
			control.reparent(member_detail_scroll_content)
		member_detail_scroll_content.move_child(control,index)
	if member_detail_scroll_content.get_parent()!=member_detail_scroll:
		member_detail_scroll_content.reparent(member_detail_scroll)
	member_detail_scroll.move_child(member_detail_scroll_content,0)
	member_detail_scroll_content.update_minimum_size()

func _on_training_mode_cycle(skill_id:String)->void:
	if member_detail_entity_id<=0:return
	var progression:Dictionary=session.protagonist_progression()
	var current_mode:="NORMAL"
	for skill in progression.get("skills",[]):
		if skill is Dictionary and str(skill.get("skill_id",""))==skill_id:
			current_mode=str(skill.get("training_mode","NORMAL"));break
	var next_mode:=ProgressionRegistryScript.next_training_mode(current_mode)
	var result:Dictionary=session.set_training_mode(skill_id,next_mode)
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","훈련 설정을 변경할 수 없습니다."));return
	var detail:Dictionary=session.inspect_party_member(member_detail_entity_id)
	member_detail_body.text=_member_detail_text(detail)
	_update_member_status_window(detail)
	_update_progression_window(detail.get("progression",{}))
	member_detail_current_tab="SKILL";_apply_member_detail_tab()
	notice_text="%s 훈련을 %s(으)로 변경했습니다."%[skill_id,
		ProgressionRegistryScript.mode_label(next_mode)];_request_refresh()

func _on_training_focus(skill_id:String)->void:
	# Headless/client compatibility: a direct focus request now changes only the
	# requested row instead of applying a dominant preset.
	if member_detail_entity_id<=0:return
	var result:Dictionary=session.set_training_mode(skill_id,"FOCUS")
	if not bool(result.get("accepted",false)) \
			and str(result.get("reason",""))!="training_mode_unchanged":return
	var detail:Dictionary=session.inspect_party_member(member_detail_entity_id)
	_update_progression_window(detail.get("progression",{}))
	member_detail_current_tab="SKILL";_apply_member_detail_tab()

func _update_progression_window(progression:Variant)->void:
	var available:=progression is Dictionary and bool(progression.get("available",false))
	if not available:return
	member_progression_xp_text.text="Lv.%d · XP %d/%d · 누적 %d → 다음 %d"%[int(progression.get("level",1)),
		int(progression.get("xp_current",0)),int(progression.get("xp_required",1)),
		int(progression.get("xp_total",0)),int(progression.get("next_level_threshold",0))]
	member_progression_xp.max_value=maxi(1,int(progression.get("xp_required",1)))
	member_progression_xp.value=int(progression.get("xp_current",0))
	var equipment:Dictionary=progression.get("equipment",{}) \
		if progression.get("equipment",{}) is Dictionary else {}
	var equipped_proficiency:=str(equipment.get("proficiency_id",""))
	var equipped_label:=str(equipment.get("weapon_label","없음"))
	member_progression_stats.text="장착 숙련 · %s · 명중·피해 적용 · 장비는 아이템 탭"%equipped_label
	for skill_value in progression.get("skills",[]):
		if not skill_value is Dictionary:continue
		var skill:Dictionary=skill_value;var skill_id:=str(skill.get("skill_id",""))
		if not member_progression_skill_rows.has(skill_id):continue
		var row:Dictionary=member_progression_skill_rows[skill_id]
		var mode:=str(skill.get("training_mode","NORMAL"))
		var equipped:=not equipped_proficiency.is_empty() and skill_id==equipped_proficiency
		var weight:=int(skill.get("raw_weight",ProgressionRegistryScript.MODE_WEIGHTS.get(mode,0)))
		var effect_text:=str(skill.get("effect_label","")).replace("명중 ","명중").replace("피해 ","피해").replace(" · ","·")
		(row.rank as Label).text="R%02d"%int(skill.get("rank",0))
		(row.name as Label).text=str(skill.get("label","기술"))
		(row.effect as Label).text=effect_text
		var mode_label:="중지" if mode=="OFF" else str(skill.get("training_mode_label","보통"))
		(row.mode as Label).text="%s%s×%d"%[
			"장착·" if equipped else "",mode_label,weight]
		(row.xp as Label).text="%d/%d"%[int(skill.get("training_current",0)),
			maxi(1,int(skill.get("training_required",1)))]
		(row.title as Button).tooltip_text=("장착 무기 숙련 · " if equipped else (
			"훈련 중지 · " if mode=="OFF" else ""))+"터치하여 %s로 변경" \
			%ProgressionRegistryScript.mode_label(ProgressionRegistryScript.next_training_mode(mode))
		_apply_skill_ledger_style(row.title,row.mode,mode,equipped,row.name,row.panel)
	_reflow_member_detail_scroll()

func _apply_skill_ledger_style(button:Button,mode_label:Label,mode:String,
		equipped:bool=false,name_label:Label=null,panel:PanelContainer=null)->void:
	var clear:=AsciiFrameScript.borderless_surface(Color("#00000000"),0)
	for state in ["normal","hover","pressed","focus","disabled"]:
		button.add_theme_stylebox_override(state,clear)
	var tone:=AsciiFrameScript.BRASS if equipped or mode=="FOCUS" \
		else (AsciiFrameScript.MUTED if mode=="OFF" else AsciiFrameScript.CYAN)
	mode_label.add_theme_color_override("font_color",tone)
	button.set_meta("no_button_chrome",true);button.set_meta("raw_training_weight",
		int(ProgressionRegistryScript.MODE_WEIGHTS.get(mode,0)))
	button.set_meta("equipped_proficiency",equipped)
	button.set_meta("training_paused",mode=="OFF")
	if name_label!=null:
		name_label.add_theme_color_override("font_color",AsciiFrameScript.BRASS if equipped \
			else (AsciiFrameScript.MUTED if mode=="OFF" else AsciiFrameScript.INK))
	if panel!=null:
		panel.add_theme_stylebox_override("panel",AsciiFrameScript.borderless_surface(
			AsciiFrameScript.SURFACE if equipped else AsciiFrameScript.SURFACE_DEEP,0))

func _toggle_weapon_mastery_category()->void:
	member_skill_category_expanded=not member_skill_category_expanded
	for skill_id in member_progression_skill_rows:
		var row:Dictionary=member_progression_skill_rows[skill_id]
		(row.panel as Control).visible=member_skill_category_expanded
	# A collapsed ledger has no meaningful retained offset. Reset synchronously so
	# the released touch cannot leave its previous overflow position visible while
	# Godot recalculates the shorter ScrollContainer range on the deferred pass.
	if not member_skill_category_expanded and member_detail_scroll!=null:
		member_detail_scroll.scroll_vertical=0
	_update_weapon_mastery_category_label()
	_reflow_member_detail_scroll()

func _update_weapon_mastery_category_label()->void:
	if member_skill_category_button==null:return
	member_skill_category_button.text=("▼" if member_skill_category_expanded else "▶")+"  무기 숙련  ·  6개"

func _reflow_member_detail_scroll()->void:
	if member_progression_window!=null:member_progression_window.update_minimum_size()
	if member_detail_scroll==null:return
	# ITEM rebuilds seventeen touch rows dynamically. Propagate that new combined
	# minimum through the sole scroll content before sorting; otherwise the panel
	# clips a 1000px ledger while its scrollbar keeps the previous STATUS height.
	if member_item_window!=null:member_item_window.update_minimum_size()
	if member_detail_scroll.get_child_count()>0:
		var content:=member_detail_scroll.get_child(0) as Control
		if content!=null:
			# Only one ledger window is visible at once. Publish its current combined
			# minimum immediately so the ScrollContainer does not remain one layout pass
			# behind after an ITEM tab switch or a SKILL category collapse/re-expand.
			if content==member_item_window or content==member_progression_window:
				content.custom_minimum_size.y=0.0
			else:content.custom_minimum_size.y=_member_detail_active_children_minimum(content)
			content.update_minimum_size()
	member_detail_scroll.queue_sort()
	call_deferred("_clamp_member_detail_scroll")

func _resize_member_detail_scroll_content(content:Control)->void:
	if content==null:return
	var active_minimum:=content.get_combined_minimum_size().y if content==member_item_window \
		or content==member_progression_window else _member_detail_active_children_minimum(content)
	var viewport_minimum:=member_detail_scroll.size.y if member_detail_scroll!=null else 0.0
	var target_height:=maxf(active_minimum,viewport_minimum)
	if content!=member_item_window and content!=member_progression_window:
		content.custom_minimum_size.y=target_height
	# `custom_minimum_size` alone cannot shrink a ScrollContainer child whose old
	# size was allocated for a different tab. Force the sole content rect down to
	# the active folio height so its scrollbar maximum ends at the action row.
	content.size=Vector2(content.size.x,target_height)
	content.update_minimum_size()

func _member_detail_active_children_minimum(content:Control)->float:
	var total:=0.0;var count:=0
	for child in content.get_children():
		var child_control:=child as Control
		if child_control==null:continue
		if count>0:total+=float(content.get_theme_constant("separation"))
		total+=child_control.get_combined_minimum_size().y
		count+=1
	return total

func _clamp_member_detail_scroll()->void:
	if member_detail_scroll==null:return
	if member_detail_scroll.get_child_count()>0:
		var content:=member_detail_scroll.get_child(0) as Control
		if content!=null:
			# `size.y` can be a stale allocation from a previously expanded item
			# ledger. Publishing that old value creates a blank tail after the action
			# row, so ScrollContainer reaches its maximum before [사용]/[버리기] are
			# actually visible. The active window's fresh combined minimum is the
			# sole-scroll-content contract for the current tab.
			_resize_member_detail_scroll_content(content)
			# Re-enter AUTO after the sole child's current minimum is known. Without
			# this, Godot exposes the previous tab/category's max and page for a frame.
			member_detail_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_NEVER
			member_detail_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
			member_detail_scroll.queue_sort()
	call_deferred("_finish_member_detail_scroll_clamp")

func _finish_member_detail_scroll_clamp()->void:
	if member_detail_scroll==null:return
	if member_detail_scroll.get_child_count()>0:
		_resize_member_detail_scroll_content(member_detail_scroll.get_child(0) as Control)
	var bar:=member_detail_scroll.get_v_scroll_bar()
	var maximum_scroll:=maxi(0,int(bar.max_value-bar.page))
	member_detail_scroll.scroll_vertical=mini(member_detail_scroll.scroll_vertical,
		maximum_scroll)

func _update_item_window(equipment:Variant)->void:
	if not equipment is Dictionary or not bool(equipment.get("available",false)):return
	member_item_weapon_text.text="장착 · %s"%str(equipment.get("weapon_label","없음"))
	(member_item_stats.FORM as Label).text="형태  %s"%str(equipment.get("attack_form","-"))
	(member_item_stats.DAMAGE as Label).text="피해  %d"%int(equipment.get("raw_damage",0))
	(member_item_stats.RANGE as Label).text="사거리  %d-%d칸"%[int(equipment.get("range_min",1)),int(equipment.get("range_max",1))]
	(member_item_stats.TIME as Label).text="공격시간  %d"%int(equipment.get("attack_time",100))
	var load_state:="해당 없음"
	if bool(equipment.get("reload_required",false)):
		load_state="장전됨" if bool(equipment.get("loaded",false)) else "미장전"
	member_item_ammo_text.text="화살 %d · 볼트 %d · 쇠뇌 %s"%[
		int(equipment.get("arrows",0)),int(equipment.get("bolts",0)),load_state]
	member_item_reload_button.visible=bool(equipment.get("reload_required",false))
	member_item_reload_button.disabled=not bool(equipment.get("can_reload",false))
	member_item_reload_button.text="재장전 · %d시간"%int(equipment.get("reload_time",0))
	_update_item_inventory_ledger()

func _update_item_inventory_ledger()->void:
	if member_item_equipment_rows==null:return
	# Detach old rows immediately so a just-rebuilt ledger has one input layer.
	# queue_free() alone leaves the outgoing buttons in hit-testing until the end
	# of the frame, directly on top of the fresh mobile actions.
	_detach_item_ledger_children(member_item_equipment_rows)
	_detach_item_ledger_children(member_item_backpack_rows)
	var dto:Dictionary=session.protagonist_inventory()
	var slot_labels:={"MAIN_HAND":"주무기","OFF_HAND":"보조","ARMOR":"갑옷",
		"ACCESSORY_1":"장신구1","ACCESSORY_2":"장신구2"}
	for row in dto.get("equipment_slots",[]):
		var slot:=str(row.get("slot",""))
		_add_item_ledger_button(member_item_equipment_rows,row,
			"%-5s %s"%[str(slot_labels.get(slot,slot)),_item_row_text(row)],true)
	var backpack:Array=dto.get("backpack_rows",[])
	member_item_empty_text.text="가방 %d / %d"%[backpack.size(),int(dto.get("capacity",12))]
	for index in range(12):
		var row:Dictionary=backpack[index] if index<backpack.size() else {"empty":true}
		_add_item_ledger_button(member_item_backpack_rows,row,
			"%02d  %s"%[index+1,_item_row_text(row)],false)
		if not bool(row.get("empty",false)) \
				and str(row.get("instance_id",""))==member_item_selected_id:
			_add_inline_item_equip_button(member_item_backpack_rows,row,dto)
	var selected_equipped:=not member_item_selected_slot.is_empty()
	var has_selection:=not member_item_selected_id.is_empty()
	var selected_row:=_selected_item_ledger_row(dto)
	member_item_selected_stats.visible=has_selection
	member_item_selected_stats.text=_item_stats_text(selected_row) if has_selection else ""
	member_item_equip_button.disabled=not has_selection or selected_equipped
	member_item_unequip_button.disabled=not selected_equipped
	member_item_quick_unequip_button.visible=selected_equipped
	member_item_quick_unequip_button.disabled=not selected_equipped
	member_item_quick_unequip_button.text="[해제]  %s"%str(selected_row.get("label","장비"))
	member_item_use_button.visible=_is_healing_item_row(selected_row)
	member_item_use_button.disabled=not has_selection or selected_equipped \
		or not session.has_method("use_inventory_item")
	member_item_drop_button.disabled=not has_selection or selected_equipped

func _detach_item_ledger_children(container:VBoxContainer)->void:
	for node in container.get_children():
		container.remove_child(node)
		node.queue_free()

func _selected_item_ledger_row(dto:Dictionary)->Dictionary:
	if member_item_selected_id.is_empty():return {}
	var rows:Array=[]
	var equipped_rows:Variant=dto.get("equipment_slots",[])
	var backpack_rows:Variant=dto.get("backpack_rows",[])
	if equipped_rows is Array:rows.append_array(equipped_rows)
	if backpack_rows is Array:rows.append_array(backpack_rows)
	for row_value in rows:
		if row_value is Dictionary and str(row_value.get("instance_id",""))==member_item_selected_id:
			return row_value
	return {}

func _is_healing_item_row(row:Dictionary)->bool:
	if row.is_empty() or bool(row.get("empty",false)):return false
	if str(row.get("use_kind",""))=="HEALING":return true
	# Transitional DTO fallback: older item presentation rows do not expose
	# `use_kind`, but both supported healing-potion ids are still authoritative.
	return str(row.get("definition_id","")) in ["POTION_HEALING","POTION_UNSPECIFIED"]

func _item_row_text(row:Dictionary)->String:
	if bool(row.get("empty",false)):return "- 비어 있음 -"
	var quantity:=int(row.get("quantity",1))
	var requirement:=str(row.get("requirement_text",""))
	var requirement_suffix:=""
	if not requirement.is_empty():
		requirement_suffix=" · %s%s"%[requirement,
			" 부족" if not bool(row.get("requirements_met",true)) else ""]
	var compact_stat:=str(row.get("compact_stat_text",""))
	return "%s %s%s%s%s"%[str(row.get("glyph","*")),str(row.get("label","아이템")),
		(" ×%d"%quantity) if quantity>1 else "",
		(" · "+compact_stat) if not compact_stat.is_empty() else "",requirement_suffix]

func _item_stats_text(row:Dictionary)->String:
	if row.is_empty() or bool(row.get("empty",false)):return ""
	var lines:Array[String]=[str(row.get("label","아이템"))]
	if str(row.get("category",""))=="WEAPON":
		lines.append("공격력 %d · 명중 %d%% · 관통 %d · 사거리 %d-%d칸 · 공격시간 %d"%[
			int(row.get("raw_damage",0)),int(row.get("hit_chance_milli",500))/10,
			int(row.get("armor_penetration_flat",0)),int(row.get("range_min",1)),
			int(row.get("range_max",1)),int(row.get("attack_time",100))])
		var ammo:=str(row.get("ammo_kind","NONE"))
		if ammo!="NONE":
			lines.append("탄약 %s ×%d%s"%["화살" if ammo=="ARROW" else "볼트",
				int(row.get("ammo_cost",1))," · 사격 후 재장전" \
				if bool(row.get("reload_required",false)) else ""])
	else:
		var bonuses:Dictionary=row.get("bonuses",{}) if row.get("bonuses",{}) is Dictionary else {}
		var parts:Array[String]=[]
		for entry in [["armor_flat","방어"],["parry_milli","막기"],
				["dodge_milli","회피"],["stealth","은신"]]:
			var value:=int(bonuses.get(str(entry[0]),0))
			if value!=0:parts.append("%s %s%d"%[str(entry[1]),"+" if value>0 else "",value])
		if str(row.get("use_kind",""))=="HEALING":
			parts.append("체력 +%d"%int(row.get("heal_amount",0)))
		lines.append("효과 없음" if parts.is_empty() else " · ".join(parts))
	var requirement:=str(row.get("requirement_text",""))
	if not requirement.is_empty():lines.append("요구 능력 · "+requirement)
	return "\n".join(lines)

func _add_item_ledger_button(parent:VBoxContainer,row:Dictionary,label:String,equipped:bool)->void:
	var button:=Button.new();button.custom_minimum_size.y=TOUCH_TARGET
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.focus_mode=Control.FOCUS_NONE
	button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.text=label
	button.add_theme_font_size_override("font_size",FONT_AUX)
	button.disabled=bool(row.get("empty",false))
	var instance_id:=str(row.get("instance_id",""));var slot:=str(row.get("slot","")) if equipped else ""
	button.set_meta("item_instance_id",instance_id);button.set_meta("item_slot",slot)
	button.pressed.connect(_on_item_row_selected.bind(instance_id,slot))
	parent.add_child(button);AsciiFrameScript.apply_rail_button(button,
		AsciiFrameScript.BRASS,instance_id==member_item_selected_id and slot==member_item_selected_slot)

func _add_inline_item_equip_button(parent:VBoxContainer,row:Dictionary,dto:Dictionary)->void:
	var allowed_slots:Variant=row.get("equip_slots",[])
	if not allowed_slots is Array or allowed_slots.is_empty():return
	var slot:=item_preferred_equip_slot(dto,allowed_slots)
	if slot.is_empty():return
	var occupied:=false
	for equipped_row in dto.get("equipment_slots",[]):
		if str(equipped_row.get("slot",""))==slot:
			occupied=not bool(equipped_row.get("empty",false));break
	var slot_label:=str({"MAIN_HAND":"주무기","OFF_HAND":"보조",
		"ARMOR":"갑옷","ACCESSORY_1":"장신구1","ACCESSORY_2":"장신구2"}.get(slot,slot))
	var button:=Button.new();button.name="ItemInlineEquip"
	button.text="[%s]  %s → %s"%[
		"교체" if occupied else "장착",str(row.get("label","아이템")),slot_label]
	if not bool(row.get("requirements_met",true)):
		button.text="[능력 부족]  %s · %s"%[
			str(row.get("label","아이템")),str(row.get("requirement_text","요구치 확인"))]
		button.tooltip_text="현재 능력치가 장비 요구치보다 낮습니다."
	button.custom_minimum_size.y=TOUCH_TARGET
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.focus_mode=Control.FOCUS_NONE
	button.pressed.connect(_on_item_equip_selected)
	parent.add_child(button);AsciiFrameScript.apply_rail_button(button,AsciiFrameScript.CYAN,true)

func _on_item_row_selected(instance_id:String,slot:String)->void:
	member_item_selected_id=instance_id;member_item_selected_slot=slot
	_update_item_inventory_ledger();_reflow_member_detail_scroll()

func _on_item_equip_selected()->void:
	var dto:Dictionary=session.protagonist_inventory();var slot:="";var allowed_slots:Array=[]
	for row in dto.get("backpack_rows",[]):
		if str(row.get("instance_id",""))==member_item_selected_id:
			allowed_slots=row.get("equip_slots",[]);break
	slot=item_preferred_equip_slot(dto,allowed_slots)
	if slot.is_empty():notice_text="이 아이템은 장착할 수 없습니다.";return
	_on_item_operation_result(session.equip_inventory_item(member_item_selected_id,slot))

func item_preferred_equip_slot(dto:Dictionary,allowed_slots:Array)->String:
	# Prefer a vacant compatible slot, then deterministically replace the first
	# compatible occupied slot. This makes weapon/armor changes one touch while
	# still filling ACCESSORY_2 before replacing ACCESSORY_1.
	for allowed in allowed_slots:
		for equipped_row in dto.get("equipment_slots",[]):
			if str(equipped_row.get("slot",""))==str(allowed) \
					and bool(equipped_row.get("empty",false)):
				return str(allowed)
	for allowed in allowed_slots:
		for equipped_row in dto.get("equipment_slots",[]):
			if str(equipped_row.get("slot",""))==str(allowed):return str(allowed)
	return ""

func _on_item_unequip_selected()->void:
	_on_item_operation_result(session.unequip_inventory_slot(member_item_selected_slot))

func _on_item_drop_selected()->void:
	_on_item_operation_result(session.drop_inventory_item(member_item_selected_id))

func _on_item_use_selected()->void:
	if member_item_selected_id.is_empty() or not session.has_method("use_inventory_item"):
		notice_text="이 아이템은 지금 사용할 수 없습니다."
		action_feedback_text=notice_text;return
	var result:Dictionary=session.call("use_inventory_item",member_item_selected_id)
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","물약을 사용할 수 없습니다."))
		action_feedback_text=notice_text;_request_refresh();return
	var healed:=int(result.get("healed_amount",0))
	notice_text="회복 물약 사용 · HP +%d"%healed
	action_feedback_text=notice_text
	member_item_selected_id="";member_item_selected_slot=""
	_record_result(result,true)
	# A potion advances canonical time, so refresh cards, compact log, inventory,
	# and overlay effects together while leaving the detail modal and its scroll
	# surface in place.
	var detail:Dictionary=session.inspect_party_member(member_detail_entity_id)
	var progression:Dictionary=detail.get("progression",{}) if detail.get("progression",{}) is Dictionary else {}
	_update_item_window(progression.get("equipment",{}));_update_progression_window(progression)
	_apply_member_detail_tab();_reflow_member_detail_scroll();_refresh()

func _on_item_operation_result(result:Dictionary)->void:
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","아이템을 옮길 수 없습니다."))
	else:
		notice_text="아이템 상태를 변경했습니다. (100시간)"
		member_item_selected_id="";member_item_selected_slot=""
	var detail:Dictionary=session.inspect_party_member(member_detail_entity_id)
	var progression:Dictionary=detail.get("progression",{}) if detail.get("progression",{}) is Dictionary else {}
	_update_item_window(progression.get("equipment",{}));member_detail_current_tab="ITEM"
	_apply_member_detail_tab();action_feedback_text=notice_text;_reflow_member_detail_scroll()
	_request_refresh()

func _on_item_reload()->void:
	var result:Dictionary=session.reload_protagonist_weapon()
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","재장전할 수 없습니다."));return
	var detail:Dictionary=session.inspect_party_member(member_detail_entity_id)
	var progression:Dictionary=detail.get("progression",{}) if detail.get("progression",{}) is Dictionary else {}
	_update_item_window(progression.get("equipment",{}))
	member_detail_current_tab="ITEM";_apply_member_detail_tab()
	notice_text="쇠뇌를 재장전했습니다.";_request_refresh()

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
		member_detail_candidate_action.text="[J 영입] 수락 %d%%"%int(recruitment.get("probability_percent",0))
		member_detail_candidate_action.disabled=not bool(recruitment.get("accepted",false))
		member_detail_candidate_action.tooltip_text=_recruitment_reason_summary(recruitment);return
	member_detail_candidate_action.text="[J 영입 불가]"
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
				"PASSED_BY":"첫 만남에 외면함","PERSONAL_AFFECTION":"개인적 감사",
				"OPEN_PERSONALITY":"개방적 성향","GUARDED_PERSONALITY":"신중한 성향",
				"PARTY_VACANCY":"파티 여석","SURVIVAL_THREAT":"생존이 절실함"}
				.get(str(row.get("code","")),row.get("label",""))))
		if parts.size()>=2:break
	return " · ".join(parts) if not parts.is_empty() else str(assessment.get("message",""))

func _clear_roster_change_transients()->void:
	route_generation+=1;_clear_route_continue_schedule()
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
func _on_explore(direction:Vector2i)->void:
	var result:Dictionary=session.commit_exploration_direction(direction)
	_record_result(result,true);_request_refresh()
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
	_reset_auto_flow();route_generation+=1;_clear_route_continue_schedule()
	_product_auto_explore_generation+=1;_product_auto_explore_pending=false
	_product_auto_explore_due_frame=-1;_product_auto_explore_due_msec=-1
	_product_auto_explore_scheduled_generation=-1
	_product_auto_last_hop_started_msec=-1;route_last_hop_started_msec=-1
	_product_auto_stop_feedback="";_product_attack_targeting=false
	_product_touch_index=-1;_product_touch_control="";_product_touch_dragged=false
	_product_mouse_control="";_product_ignore_mouse_until_msec=-1
	_product_zoom_touch_index=-1;_product_zoom_touch_step=0
	route_paused_by_modal=false;route_paused_by_pointer=false;route_preview.clear()
	_clear_move_preview();_clear_companion_follow_plan();_hide_tile_popover()
	selected_member_id=-1;selected_target_id=-1;notice_text="";action_feedback_text="";_action_feedback_phase=""
	_pending_card_pointer.clear();_last_card_tap_id=-1;_last_card_tap_msec=-1000
	_last_card_tap_position=Vector2(-10000,-10000);_direct_card_touch_id=-1;_direct_card_touch_msec=-1000
	_scroll_log_after_refresh=false;_run_locked_exit_feedback=false
	_reward_emphasis_pending=false;_run_progress_initialized=false;_observed_reward_granted=false
	_pending_visual_effect_rows.clear()
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
	var action_started:=Time.get_ticks_usec()
	var status:Dictionary=session.party_status();var protagonist_id:=int(status.get("protagonist_id",-1))
	# Companion selection is observation-only in the product party loop. Every
	# ordinary combat tap remains a protagonist action; individual override stays
	# available only through the internal session API and regression harnesses.
	if not _is_solo_product_session() and selected_member_id!=protagonist_id:
		selected_member_id=protagonist_id
	_cancel_auto_pending(false)
	if selected_member_id==protagonist_id:
		var action=_make_party_action(selected_member_id,action_type,destination,target_id)
		var direct_solo:=_is_direct_solo_combat(status)
		if direct_solo:
			_last_direct_solo_refresh_profile.clear()
			auto_generation+=1;auto_combat_pending=false;auto_combat_render_stage=0
			auto_combat_plan_hash="";auto_combat_step_index=-1
			auto_override_edit=false;auto_combat_fallback=false
			var commit_started:=Time.get_ticks_usec()
			var result:Dictionary=session.commit_direct_solo_action(selected_member_id,
				action_type,destination,target_id)
			var commit_finished:=Time.get_ticks_usec()
			if not bool(result.get("accepted",false)):
				auto_combat_fallback=true;_set_action_rejection(result,
					"%s 행동 불가"%_selected_name());_request_refresh();return
			_record_result(result,true,"자동 실행 불가",true);_clear_move_preview()
			selected_target_id=-1
			var after_status:Dictionary=session.party_status()
			if _is_direct_solo_combat(after_status):
				_refresh_direct_solo_combat_surface(after_status)
			else:
				if str(after_status.get("safe_phase",""))=="GROUPED_COMPLETE":
					notice_text="승리! 출구를 향해 탐험을 계속하세요."
				_request_refresh()
			var action_finished:=Time.get_ticks_usec()
			_last_direct_solo_turn_profile={"draft_usec":0,
				"commit_usec":commit_finished-commit_started,
				"result_and_refresh_usec":action_finished-commit_finished,
				"refresh":_last_direct_solo_refresh_profile.duplicate(true),
				"total_usec":action_finished-action_started}.duplicate(true)
			return
		var planning:Dictionary=session.replace_auto_combat_protagonist_action(action)
		if not bool(planning.get("accepted",false)) \
				or not bool(planning.get("commit_ready",false)):
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
	if _party_command_targeting:
		_party_command_targeting=false
		notice_text="공격 대상 지정을 취소했습니다."
		action_feedback_text=notice_text;_request_refresh();return
	if _product_attack_targeting:
		_product_attack_targeting=false
		_show_product_command_feedback("공격 선택을 취소했습니다.")
		_sync_product_control_state(status);return
	if status.view_mode=="EXPLORATION":
		_cancel_product_auto_explore("auto_explore_user_command",false)
		var tapped_items:Array=session.visible_ground_items_at(position)
		pending_ground_pickup_id=str(tapped_items[0].get("instance_id","")) \
			if not tapped_items.is_empty() else ""
		pending_ground_pickup_label=str(tapped_items[0].get("label","아이템")) \
			if not tapped_items.is_empty() else ""
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
		var hero_position:=Vector2i(int(status.protagonist_position[0]),
			int(status.protagonist_position[1]))
		var direct_delta:=position-hero_position
		if direct_delta!=Vector2i.ZERO \
				and maxi(absi(direct_delta.x),absi(direct_delta.y))==1:
			# Adjacent taps need no macro-route snapshot/hash/path DTO. The canonical
			# one-cell facade performs the same authoritative preview, commit, journal,
			# turn, exposure and contact resolution without route-only bookkeeping.
			var command=CommandScript.move_to(int(status.protagonist_id),position)
			var direct_preview:Dictionary=session.preview_exploration(command)
			if bool(direct_preview.get("accepted",false)):
				route_generation+=1;_clear_route_continue_schedule();route_preview.clear()
				_clear_move_preview();_clear_companion_follow_plan()
				var result:Dictionary=session.commit_exploration(command)
				_record_result(result,true,"%s 이동 불가"%_protagonist_name())
				if bool(result.get("accepted",false)):
					action_feedback_text="한 칸 이동했습니다."
					_pickup_pending_ground_item_if_reached()
				_refresh_continuous_exploration_surface(session.party_status())
				return
		var preview:Dictionary=session.preview_exploration_route(position)
		route_preview=preview.duplicate(true);_apply_route_state(preview)
		if not bool(preview.get("accepted",false)):
			notice_text=str(preview.get("message","이 칸으로 이동할 수 없습니다."))
			_set_action_rejection(preview,"%s 이동 불가"%_protagonist_name())
			_update_tile_popover_route(preview);_request_refresh();return
		route_generation+=1;_clear_route_continue_schedule()
		var hop_started_msec:=Time.get_ticks_msec()
		route_last_hop_started_msec=hop_started_msec
		var started:Dictionary=session.start_exploration_route(position,str(preview.get("plan_hash","")))
		_consume_route_result(started)
		_refresh_continuous_exploration_surface(session.party_status(),true)
		_schedule_route_continue(hop_started_msec)
		return
	if status.view_mode!="COMBAT":return
	selected_target_id=-1;_clear_move_preview()
	if auto_orchestration_enabled and _is_direct_solo_combat(status):
		_stage_auto_combat_action("MOVE",[position.x,position.y]);return
	var action_actor_id:=int(status.get("protagonist_id",-1)) \
		if auto_orchestration_enabled else selected_member_id
	var preview:Dictionary=session.preview_actor_action(action_actor_id,"MOVE",[position.x,position.y])
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
	if _party_command_targeting:
		if entity_id not in status.get("visible_enemy_ids",[]):
			notice_text="활동 중인 적을 선택하세요."
			action_feedback_text=notice_text;_request_refresh();return
		_party_command_targeting=false
		if auto_orchestration_enabled:_cancel_auto_pending(false)
		var command_result:Dictionary=session.issue_party_command("ATTACK_TARGET",entity_id)
		_record_result(command_result,false,"공격 대상 지정 불가")
		if bool(command_result.get("accepted",false)):
			notice_text="파티 집중 표적 · %s"%str(session.inspect_enemy(
				entity_id).get("display_name","적"))
			action_feedback_text=notice_text
		_request_refresh();return
	if _product_attack_targeting:
		var adjacent:=_product_adjacent_enemies(status)
		if entity_id not in adjacent:
			_show_product_command_feedback("인접한 적을 선택하세요.");return
		_product_attack_targeting=false
		if _submit_product_melee(entity_id,status):return
	if status.view_mode=="EXPLORATION" and entity_id in status.get("rescue_candidate_ids",[]):
		if bool(session.exploration_route_state().get("has_preview",false)):_cancel_active_route()
		_open_member_detail(entity_id);return
	if status.view_mode=="EXPLORATION" \
			and session.has_method("is_opening_recruitment_candidate") \
			and bool(session.is_opening_recruitment_candidate(entity_id)):
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
		var ground_items:Array=session.ground_items_at_protagonist()
		if not ground_items.is_empty():
			var pickup:Dictionary=session.pickup_ground_item(str(ground_items[0].instance_id))
			_record_result(pickup,true,"아이템을 주울 수 없습니다.")
			if bool(pickup.get("accepted",false)):
				notice_text="%s 확인 · 가방에 주웠습니다. (100시간)"%str(ground_items[0].label)
				action_feedback_text=notice_text
			_request_refresh();return
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
		_submit_product_melee(entity_id,status)
		_request_refresh(); return
	if entity_id in status.party_member_ids:
		selected_member_id=entity_id;selected_target_id=-1
		notice_text="파티원 판단을 관찰합니다."
		action_feedback_text="전투 입력은 주인공 행동으로 처리됩니다." \
			if auto_orchestration_enabled and status.view_mode=="COMBAT" \
			else "%s 선택 · 행동을 지정하세요."%_selected_name()
		_clear_move_preview();_request_refresh()

func _submit_product_melee(entity_id:int,status:Dictionary)->bool:
	if bool(status.get("terminal",false)):return false
	var current_status:=status
	# CONTACT is an internal transition for the solo product. It never constructs
	# a deployment or a separate battle surface; the same tap continues into the
	# ordinary same-grid melee action when the backend accepts it.
	if str(current_status.get("view_mode",""))!="COMBAT" \
			and str(current_status.get("safe_phase",""))=="CONTACT" \
			and _is_solo_product_session() and session.has_method("enter_solo_combat"):
		var entered:Dictionary=session.enter_solo_combat()
		if not bool(entered.get("accepted",false)):
			_show_product_command_feedback(str(entered.get("message","공격을 준비할 수 없습니다.")))
			return false
		current_status=session.party_status()
	if str(current_status.get("view_mode",""))!="COMBAT":
		_show_product_command_feedback("지금은 공격할 수 없습니다.")
		return false
	if auto_orchestration_enabled:_stage_auto_combat_action("MELEE",[],entity_id)
	else:_record_result(session.set_actor_action(selected_member_id,"MELEE",[],entity_id),false,"%s 공격 불가"%_selected_name())
	return true

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
	if path is Array and path.size()>=2 \
			and not bool(value.get("completed",false)) \
			and not bool(value.get("terminal",false)):
		grid.set_route_overlay(path,int(value.get("completed_steps",value.get("current_index",0))),bool(value.get("accepted",false)))
	else:grid.clear_route_overlay()

func _consume_route_result(result:Dictionary)->void:
	var last_step:Variant=result.get("last_step_result",{})
	if last_step is Dictionary:_arm_actor_motion_from_result(last_step,
		CONTINUOUS_EXPLORATION_MOTION_MSEC)
	_apply_route_state(result)
	var effects:Variant=result.get("last_step_effects",[])
	if effects is Array and not effects.is_empty():grid.play_effects(effects)
	var message:=str(result.get("message","이동을 처리할 수 없습니다."))
	if bool(result.get("completed",false)):
		notice_text=message;action_feedback_text="목적지에 도착했습니다."
		_pickup_pending_ground_item_if_reached()
	elif bool(result.get("terminal",false)) or not bool(result.get("active",false)):
		notice_text=message;action_feedback_text=message
	else:
		notice_text=message;action_feedback_text="한 칸씩 이동 중 · %d/%d"%[int(result.get("completed_steps",0)),int(result.get("total_steps",0))]
	_update_tile_popover_route(result)

func _pickup_pending_ground_item_if_reached()->void:
	if pending_ground_pickup_id.is_empty():return
	var status:Dictionary=session.party_status()
	var hero_position:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
	var rows:Array=session.visible_ground_items_at(hero_position)
	if rows.all(func(row):return str(row.get("instance_id",""))!=pending_ground_pickup_id):return
	var item_label:=pending_ground_pickup_label
	var result:Dictionary=session.pickup_ground_item(pending_ground_pickup_id)
	if bool(result.get("accepted",false)):
		notice_text="%s 확인 · 가방에 주웠습니다. (100시간)"%item_label
		action_feedback_text=notice_text
	else:
		notice_text=str(result.get("message","아이템을 주울 수 없습니다."))
		action_feedback_text=notice_text
	pending_ground_pickup_id="";pending_ground_pickup_label=""

func _schedule_route_continue(previous_hop_started_msec:int=-1)->void:
	if route_continue_pending or route_paused_by_modal or route_paused_by_pointer or not is_inside_tree():return
	var state:Dictionary=session.exploration_route_state()
	if not bool(state.get("active",false)) or bool(state.get("completed",false)) or bool(state.get("terminal",false)):return
	route_continue_pending=true
	route_continue_due_frame=Engine.get_process_frames()+1
	var cadence_origin:=previous_hop_started_msec if previous_hop_started_msec>=0 \
		else Time.get_ticks_msec()
	route_continue_due_msec=cadence_origin+maxi(0,continuous_travel_cadence_msec)
	route_scheduled_generation=route_generation

func _continue_route_on_cadence(expected_generation:int)->void:
	if expected_generation!=route_generation or route_paused_by_modal or route_paused_by_pointer or member_detail_modal.visible:return
	var hop_started_msec:=Time.get_ticks_msec()
	route_last_hop_started_msec=hop_started_msec
	var result:Dictionary=session.continue_exploration_route()
	_consume_route_result(result)
	_refresh_continuous_exploration_surface(session.party_status(),true)
	if bool(result.get("active",false)) and not bool(result.get("completed",false)) and not bool(result.get("terminal",false)):
		_schedule_route_continue(hop_started_msec)

func _clear_route_continue_schedule()->void:
	route_continue_pending=false;route_continue_due_frame=-1
	route_continue_due_msec=-1;route_scheduled_generation=-1

func _cancel_route_for_user_interruption()->void:
	if session==null:return
	var state:Dictionary=session.exploration_route_state()
	if bool(state.get("active",false)) or bool(state.get("has_preview",false)):
		_cancel_active_route()
	route_paused_by_modal=false;route_paused_by_pointer=false

func _on_grid_pointer_started()->void:
	_cancel_product_auto_explore("auto_explore_user_command",false)
	_cancel_route_for_user_interruption()
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
	route_paused_by_pointer=false

func _on_grid_pointer_finished(_outcome:String)->void:
	route_paused_by_pointer=false

func _cancel_active_route()->void:
	route_generation+=1;_clear_route_continue_schedule()
	var state:Dictionary=session.exploration_route_state()
	if bool(state.get("has_preview",false)):session.cancel_exploration_route()
	route_preview.clear();grid.clear_route_overlay();grid.clear_cursor_preview()
	pending_move_actor_id=-1;pending_move_origin=Vector2i(-1,-1);pending_move_destination=Vector2i(-1,-1)
	pending_move_valid=false;pending_move_mode="";pending_move_cost=0;pending_exploration_wait=false

func _clear_move_preview()->void:
	pending_move_actor_id=-1; pending_move_origin=Vector2i(-1,-1); pending_move_destination=Vector2i(-1,-1); pending_move_valid=false
	pending_move_mode=""; pending_move_cost=0; pending_exploration_wait=false
	if grid!=null:grid.clear_cursor_preview();grid.clear_route_overlay()
func _request_refresh()->void:
	if _refresh_pending:return
	_refresh_pending=true
	call_deferred("_flush_requested_refresh")

func _flush_requested_refresh()->void:
	if not _refresh_pending:return
	_refresh_pending=false
	_refresh()
func _record_result(result:Dictionary,consume_effects:bool=false,rejection_prefix:String="",
		scroll_combat_log:bool=false,motion_duration_msec:int=-1)->void:
	_arm_actor_motion_from_result(result,motion_duration_msec)
	if consume_effects and bool(result.get("accepted",false)) and result.get("visual_effects",[]) is Array:
		for raw in result.get("visual_effects",[]):
			if raw is Dictionary:_pending_visual_effect_rows.append(raw.duplicate(true))
	if bool(result.get("accepted",false)):
		_product_attack_targeting=false
		# Only a committed live UI action may arm the reward highlight. A loaded
		# save or an arbitrary refresh synchronizes the badge without replaying it.
		if _run_progress_initialized and not _observed_reward_granted:
			var progress:=_current_run_progress()
			var reward:Dictionary=progress.get("reward",{}) if progress.get("reward",{}) is Dictionary else {}
			_reward_emphasis_pending=bool(reward.get("granted",false))
		if scroll_combat_log:_scroll_log_after_refresh=true
		notice_text="";action_feedback_text="턴이 처리되었습니다. 다음 행동을 지정하세요." if consume_effects else (
			"행동이 준비되었습니다." if auto_orchestration_enabled else "행동이 준비되었습니다. 지금 실행을 누르세요.")
		_settle_solo_product_contact()
	else:
		notice_text=str(result.get("message","행동을 처리할 수 없습니다."));_set_action_rejection(result,rejection_prefix)

func _settle_solo_product_contact()->void:
	# CONTACT is an internal authority boundary in the one-member product, not a
	# user-facing deployment mode. Complete it in the same input callback that
	# committed the triggering move, so the next tap can immediately move or bump.
	if not auto_orchestration_enabled or not _is_solo_product_session():return
	var status:Dictionary=session.party_status()
	if str(status.get("safe_phase",""))!="CONTACT":return
	auto_generation+=1;auto_deployment_pending=false;auto_combat_pending=false
	auto_deployment_signature="";auto_combat_plan_hash=""
	auto_deployment_render_stage=0;auto_combat_render_stage=0
	auto_deployment_fallback=false;auto_combat_fallback=false;auto_override_edit=false
	var result:Dictionary=session.enter_solo_combat()
	if not bool(result.get("accepted",false)):
		_set_action_rejection(result,"조우 처리 불가")
	auto_phase=str(session.party_status().get("safe_phase",""))

func _flush_pending_visual_effects()->int:
	if grid==null or _pending_visual_effect_rows.is_empty():return 0
	var rows:Array=_pending_visual_effect_rows.duplicate(true)
	_pending_visual_effect_rows.clear()
	# Begin the short presentation clock only after observation, camera mapping,
	# cards, and log have refreshed. Slow web layout can no longer consume the
	# complete effect lifetime before the first drawable frame.
	return grid.play_effects(rows)

func _arm_actor_motion_from_result(result:Dictionary,duration_override_msec:int=-1)->void:
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
	var duration_msec:=duration_override_msec if duration_override_msec>0 else (
		EXPLORATION_ACTOR_MOTION_MSEC \
		if str(status.get("view_mode",""))=="EXPLORATION" else -1)
	if duration_msec>0:grid.arm_actor_motion(moved.keys(),duration_msec)
	else:grid.arm_actor_motion(moved.keys())

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
	var frame:=tile_popover.find_child("TileRiskAsciiFrame",true,false) as MarginContainer
	var horizontal_inset:=16.0
	if frame!=null:
		horizontal_inset=float(frame.get_theme_constant("margin_left")+frame.get_theme_constant("margin_right"))
	var content_width:=maxf(1.0,width-horizontal_inset)
	tile_popover_label.custom_minimum_size=Vector2(content_width,0)
	tile_popover_label.size.x=content_width
	tile_popover.size=Vector2(width,1.0);tile_popover.visible=true
	call_deferred("_measure_tile_popover")

func _measure_tile_popover()->void:
	if tile_popover==null or not tile_popover.visible:return
	var font:Font=tile_popover_label.get_theme_font("font")
	var line_height:=font.get_height(tile_popover_label.get_theme_font_size("font_size"))
	var required_label_height:=maxf(line_height,float(tile_popover_label.get_line_count())*line_height)
	tile_popover_label.custom_minimum_size.y=required_label_height
	var frame:=tile_popover.find_child("TileRiskAsciiFrame",true,false) as MarginContainer
	var vertical_inset:=12.0
	if frame!=null:
		vertical_inset=float(frame.get_theme_constant("margin_top")+frame.get_theme_constant("margin_bottom"))
	tile_popover.size.y=required_label_height+vertical_inset
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
		for row in detail.get("personality_facets",[]):
			if row is Dictionary:facets.append("%s %d"%[_facet_label(str(row.get("facet_id",""))),int(row.get("value",0))])
		var style:Dictionary=detail.get("personality_style",{}) if detail.get("personality_style",{}) is Dictionary else {}
		lines.append("성격 · %s%s"%[str(style.get("label","균형 잡힌 성향")),
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
				if row is Dictionary:companion_parts.append("%s: %s"%[str(row.get("display_name","동료")),str(row.get("style_label","성향 미상"))])
			if not companion_parts.is_empty():lines.append("이번 원정 성향 · "+" · ".join(companion_parts))
	lines.append("주요 기록 · 최근 8개 사건 턴")
	var groups:Variant=history.get("groups",[])
	if not groups is Array or groups.is_empty():
		lines.append("아직 주요 사건이 없습니다.");return "\n".join(lines)
	var meaningful_group_count:=0
	for group in groups:
		if not group is Dictionary:continue
		var meaningful_messages:Array[String]=[]
		for row in group.get("rows",[]):
			if not row is Dictionary:continue
			var message:=_combat_log_row_message(row)
			if not message.is_empty() and not _is_persistent_log_filler(message):
				meaningful_messages.append(message)
		if meaningful_messages.is_empty():continue
		meaningful_group_count+=1
		lines.append("── 턴 %d · 시간 %d→%d ──"%[int(group.get("step_index",0)),int(group.get("start_time",0)),int(group.get("end_time",0))])
		lines.append_array(meaningful_messages)
	if meaningful_group_count==0:lines.append("아직 주요 사건이 없습니다.")
	return "\n".join(lines)

func _compact_meaningful_event_text(history:Dictionary,_status:Dictionary)->String:
	var damage_lines:Array[String]=[];var other_lines:Array[String]=[]
	var groups:Variant=history.get("groups",[])
	if groups is Array:
		for group_index in range(groups.size()-1,-1,-1):
			var group:Variant=groups[group_index]
			if not group is Dictionary:continue
			var rows:Variant=group.get("rows",[])
			if not rows is Array:continue
			for row_index in range(rows.size()-1,-1,-1):
				var row:Variant=rows[row_index]
				if not row is Dictionary:continue
				var message:=_combat_log_row_message(row).replace("\n"," ")
				if message.is_empty() or _is_persistent_log_filler(message):continue
				if str(row.get("type","")).begins_with("combat.") \
						and str(row.get("type","")).ends_with("_damage"):
					damage_lines.append(message)
				else:other_lines.append(message)
	# Two-line mobile feed prioritizes resolved damage over action declarations,
	# so a hero hit and enemy counter-hit cannot be displaced by their MELEE rows.
	var lines:Array[String]=damage_lines.slice(0,mini(2,damage_lines.size()))
	for message in other_lines:
		if lines.size()>=2:break
		lines.append(message)
	return "\n".join(lines)

func _full_meaningful_record_text(history:Dictionary)->String:
	var lines:Array[String]=[];var groups:Variant=history.get("groups",[])
	if groups is Array:
		for group in groups:
			if not group is Dictionary:continue
			var messages:Array[String]=[]
			for row in group.get("rows",[]):
				if not row is Dictionary:continue
				var message:=_combat_log_row_message(row)
				if not message.is_empty() and not _is_persistent_log_filler(message):messages.append(message)
			if messages.is_empty():continue
			lines.append("턴 %d · 시간 %d→%d"%[int(group.get("step_index",0)),
				int(group.get("start_time",0)),int(group.get("end_time",0))])
			lines.append_array(messages)
	if lines.is_empty():return "아직 기록된 주요 사건이 없습니다."
	return "\n".join(lines)

func _combat_log_row_message(row:Dictionary)->String:
	var message:=str(row.get("message","")).strip_edges()
	var event_type:=str(row.get("type",""))
	if not event_type.begins_with("combat.") or not event_type.ends_with("_damage"):
		return message
	# The session owns combat wording. A non-empty canonical message must flow
	# unchanged into both compact and full history surfaces.
	if not message.is_empty():return message
	var attacker:=str(row.get("instigator_name","")).strip_edges()
	var target:=str(row.get("target_name","")).strip_edges()
	var magnitude:=maxi(0,int(row.get("magnitude",0)))
	# Snapshot-era rows may lack the rendered sentence; only then use their own
	# recorded attribution and magnitude as a presentation fallback.
	if not attacker.is_empty() and not target.is_empty():
		return "%s → %s · %d 피해"%[attacker,target,magnitude]
	return ""

func _is_persistent_log_filler(message:String)->bool:
	var compact:=message.strip_edges()
	return compact.begins_with("선택 상세") \
		or "건강과 긴장이 안정적입니다" in compact \
		or "주인공 행동 준비" in compact

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
	var label:=Label.new(); label.name=node_name; label.text=value; label.custom_minimum_size.y=38; label.add_theme_font_size_override("font_size",maxi(FONT_AUX,font_size))
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible=3;label.clip_text=true;deck.add_child(label); return label
func _add_button(parent:Control,value:String,node_name:String,callback:Callable)->Button:
	var button:=Button.new(); button.name=node_name; button.text=_dos_command_label(node_name,value);button.set_meta("plain_label",value)
	button.custom_minimum_size=Vector2(TOUCH_TARGET,TOUCH_TARGET); button.add_theme_font_size_override("font_size",FONT_BODY)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.pressed.connect(callback); parent.add_child(button)
	var danger:=node_name in ["MemberDetailDismiss","RestartExpedition"]
	var accent:=AsciiFrameScript.DANGER if danger else (AsciiFrameScript.BRASS if node_name in ["TurnConfirm","AutoExecute","DeployConfirm"] else AsciiFrameScript.CYAN)
	AsciiFrameScript.apply_rail_button(button,accent,false,danger);return button
func _dos_command_label(node_name:String,value:String)->String:
	match node_name:
		"ActorHold":return "[R 방어]"
		"OverrideClear":return "[A 자동]"
		"TurnConfirm","AutoExecute":return "[E 실행]"
		"DeployConfirm":return "[E 배치]"
		"SoloCombatStart":return "[E 전투]"
		"RestartSameRun","RestartExpedition":return "[E 재시작]"
		_:return "[ %s ]"%value

func _current_grid_view_cell_count()->int:
	return _product_zoom_cell_count if _is_solo_product_session() else 15

func _sync_product_zoom_controls(product_hud:bool)->void:
	if grid_zoom_controls==null:return
	var front_surface_open:bool=grid!=null and grid.modal_open \
		or member_detail_modal!=null and member_detail_modal.visible \
		or record_modal!=null and record_modal.visible \
		or map_overlay!=null and map_overlay.visible \
		or ascii_3d_lab_view!=null and is_instance_valid(ascii_3d_lab_view)
	var show:bool=product_hud and grid!=null and grid.visible and not front_surface_open
	grid_zoom_controls.visible=show
	if not show:
		_product_zoom_touch_index=-1;_product_zoom_touch_step=0
		return
	var zoom_index:=PRODUCT_ZOOM_CELL_COUNTS.find(_product_zoom_cell_count)
	if zoom_index<0:
		_product_zoom_cell_count=PRODUCT_ZOOM_DEFAULT_CELL_COUNT
		zoom_index=PRODUCT_ZOOM_CELL_COUNTS.find(_product_zoom_cell_count)
	grid_zoom_out_button.disabled=zoom_index>=PRODUCT_ZOOM_CELL_COUNTS.size()-1
	grid_zoom_in_button.disabled=zoom_index<=0
	var flat_mode:bool=str(grid.graphics_mode_id())==GridScript.GRAPHICS_MODE_FLAT_2D
	grid_graphics_mode_button.text="[2D]" if flat_mode else "[2.5D]"
	grid_graphics_mode_button.tooltip_text="그래픽 모드 · %s · 눌러서 %s로 변경"%[
		"2D" if flat_mode else "2.5D","2.5D" if flat_mode else "2D"]
	var out_count:=int(PRODUCT_ZOOM_CELL_COUNTS[-1]) if grid_zoom_out_button.disabled \
		else int(PRODUCT_ZOOM_CELL_COUNTS[zoom_index+1])
	var in_count:=int(PRODUCT_ZOOM_CELL_COUNTS[0]) if grid_zoom_in_button.disabled \
		else int(PRODUCT_ZOOM_CELL_COUNTS[zoom_index-1])
	grid_zoom_out_button.tooltip_text="시야 축소 · %d칸 · %.2f×"%[
		out_count,_product_zoom_scale(out_count)]
	grid_zoom_in_button.tooltip_text="시야 확대 · %d칸 · %.2f×"%[
		in_count,_product_zoom_scale(in_count)]

func _product_zoom_scale(cell_count:int)->float:
	return float(PRODUCT_ZOOM_REFERENCE_CELL_COUNT)/float(maxi(1,cell_count))

func _product_zoom_control_has_point(global_position:Vector2)->bool:
	if grid_zoom_controls==null or not grid_zoom_controls.is_visible_in_tree():return false
	for button in [grid_graphics_mode_button,grid_zoom_out_button,grid_zoom_in_button]:
		if button!=null and button.visible and button.get_global_rect().has_point(global_position):
			return true
	return false

func _handle_product_zoom_touch(event:InputEvent)->bool:
	if not event is InputEventScreenTouch and not event is InputEventScreenDrag:return false
	if event is InputEventScreenDrag:
		if event.index!=_product_zoom_touch_index:return false
		get_viewport().set_input_as_handled();return true
	if event.pressed:
		if not _product_zoom_control_has_point(event.position):return false
		_product_zoom_touch_index=event.index
		_product_zoom_touch_step=0 if grid_graphics_mode_button.get_global_rect().has_point(
			event.position) else (1 if grid_zoom_out_button.get_global_rect().has_point(
			event.position) else -1)
		get_viewport().set_input_as_handled();return true
	if event.index!=_product_zoom_touch_index:return false
	var step:=_product_zoom_touch_step
	var matching_button:=grid_graphics_mode_button if step==0 else (
		grid_zoom_out_button if step>0 else grid_zoom_in_button)
	var activate:bool=not event.canceled and matching_button.get_global_rect().has_point(event.position) \
		and not matching_button.disabled
	_product_zoom_touch_index=-1;_product_zoom_touch_step=0
	get_viewport().set_input_as_handled()
	if activate:
		if step==0:_on_product_graphics_mode_toggle()
		else:_on_product_zoom_step(step)
	return true

func _on_product_graphics_mode_toggle()->void:
	if not _is_solo_product_session() or grid==null:return
	var next_mode:=GridScript.GRAPHICS_MODE_DIORAMA_2_5D \
		if grid.graphics_mode_id()==GridScript.GRAPHICS_MODE_FLAT_2D \
		else GridScript.GRAPHICS_MODE_FLAT_2D
	if grid.set_graphics_mode(next_mode):
		_sync_product_zoom_controls(true)

func _on_product_zoom_step(index_delta:int)->void:
	if not _is_solo_product_session():return
	var current_index:=PRODUCT_ZOOM_CELL_COUNTS.find(_product_zoom_cell_count)
	if current_index<0:current_index=PRODUCT_ZOOM_CELL_COUNTS.find(PRODUCT_ZOOM_DEFAULT_CELL_COUNT)
	var next_index:=clampi(current_index+index_delta,0,PRODUCT_ZOOM_CELL_COUNTS.size()-1)
	if next_index==current_index:
		_sync_product_zoom_controls(true);return
	_product_zoom_cell_count=int(PRODUCT_ZOOM_CELL_COUNTS[next_index])
	_apply_product_zoom_surface()

func _apply_product_zoom_surface()->void:
	_sync_product_zoom_controls(true)
	if session==null or grid==null:return
	var status:Dictionary=session.party_status()
	if not bool(status.get("ok",false)):return
	# Zoom is a pure camera projection change. It deliberately bypasses `_refresh`,
	# whose phase orchestration may own canonical work, and leaves AUTO/routes intact.
	grid.cancel_pointer_gesture()
	var ui_observation:Dictionary=session.observe_party_ui(_product_zoom_cell_count)
	grid.set_observation(ui_observation.get("grid",{}),[])
	minimap.set_observation(ui_observation.get("minimap",{}))
	var hero_position:=Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	grid.set_hero_centered_view(hero_position,_product_zoom_cell_count,
		int(status.protagonist_id))

func _is_solo_product_session()->bool:
	return session!=null and session.has_method("is_solo_combat") \
		and bool(session.call("is_solo_combat"))

func _is_direct_solo_combat(status:Dictionary)->bool:
	var members:Variant=status.get("party_member_ids",[])
	return _is_solo_product_session() and auto_orchestration_enabled \
		and str(status.get("safe_phase",""))=="ENGAGED" \
		and str(status.get("view_mode",""))=="COMBAT" \
		and members is Array and members.size()==1 \
		and selected_member_id==int(status.get("protagonist_id",-1))
func _clear_container(container:Control)->void:
	for child in container.get_children():container.remove_child(child); child.free()
func _phase(value:String)->String:
	if value=="ENGAGED" and _is_solo_product_session():return "단독 전투"
	return {"GROUPED":"탐험","CONTACT":"조우 배치","ENGAGED":"파티 전투","REGROUP_READY":"자동 재집결","GROUPED_COMPLETE":"탐험 재개","PARTY_DEFEATED":"패배"}.get(value,value)
func _presence(value:String)->String:return {"DEPLOYED":"배치","GROUPED":"동행","DORMANT":"전투 대기","RECRUITABLE":"영입 후보","EXILED":"추방됨","DEFEATED":"쓰러짐"}.get(value,value)
func _role(value:String)->String:return {"PROTAGONIST":"주인공","COMPANION":"동료"}.get(value,value)
func _species(value:String)->String:return {"human":"인간","elf":"엘프","dwarf":"드워프",
	"orc":"오크","beastkin":"수인","goblin":"고블린","default":"미상"}.get(value,value)
func _facet_label(value:String)->String:return {"H":"정직-겸손","E":"정서성","X":"외향성","A":"원만성","C":"성실성","O":"개방성"}.get(value,value)
func _disposition(value:String)->String:return {"HOSTILE":"적대","WARY":"경계","TRUSTING":"신뢰","FRIENDLY":"우호","NEUTRAL":"중립"}.get(value,value)
func _apply_screen_budget(combat_active:bool,combat_actions_visible:bool,
		run_available:bool=false,run_terminal:bool=false,party_height:int=160)->void:
	var wide:=size.x>=450.0
	var product_hud:=_is_solo_product_session()
	phase_panel.custom_minimum_size.y=0 if product_hud else (52 if wide else 48)
	# The 360px product stack has exactly eight spare pixels after its fixed
	# surfaces. A zero-gap transparent flex owns them deterministically; relying
	# on five implicit VBox separations intermittently inflated the root to 642.
	root_layout.add_theme_constant_override("separation",4 if wide else (0 if product_hud else 2))
	combat_action_area.custom_minimum_size.y=84 if combat_actions_visible else 0
	if product_hud:
		grid.custom_minimum_size=Vector2(size.x,size.x)
		hud_bottom_flex.visible=true
		var status:Dictionary=session.party_status()
		var members:Variant=status.get("party_member_ids",[])
		var product_metrics:=_product_controls_metrics(members.size() if members is Array else 1)
		combat_action_area.custom_minimum_size.y=int(product_metrics.get("dock_height",124))
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
	event_surface.custom_minimum_size.y=38 if wide else 36
	bottom_navigation.custom_minimum_size.y=TOUCH_TARGET

func _apply_phase_banner(status:Dictionary,presentation:Dictionary)->void:
	var banner:Dictionary=presentation.get("banner",{})
	var tone:=str(banner.get("tone","CALM"))
	var situation:="조용함"
	if tone=="DEFEAT":situation="위험"
	elif tone=="VICTORY" or str(status.get("safe_phase",""))=="GROUPED_COMPLETE":situation="승리"
	elif str(status.get("safe_phase",""))=="ENGAGED":situation="전투"
	elif str(status.get("safe_phase",""))=="CONTACT" \
			or not status.get("visible_enemy_ids",[]).is_empty():situation="기척"
	var surface_color:=AsciiFrameScript.NAVY
	if situation=="전투":
		surface_color=Color("#2a0000")
		phase_label.add_theme_font_size_override("font_size",FONT_KEY)
		phase_label.add_theme_color_override("font_color",AsciiFrameScript.DANGER); grid.set_combat_emphasis(true)
	elif situation=="승리":
		surface_color=Color("#002a00")
		phase_label.add_theme_font_size_override("font_size",FONT_KEY)
		phase_label.add_theme_color_override("font_color",AsciiFrameScript.JADE); grid.set_combat_emphasis(false)
	elif situation=="위험":
		surface_color=Color("#2a0000")
		phase_label.add_theme_font_size_override("font_size",FONT_KEY)
		phase_label.add_theme_color_override("font_color",AsciiFrameScript.DANGER);grid.set_combat_emphasis(true)
	else:
		surface_color=Color("#2a2a00") if situation=="기척" else AsciiFrameScript.NAVY
		phase_label.add_theme_font_size_override("font_size",FONT_KEY)
		phase_label.add_theme_color_override("font_color",AsciiFrameScript.BRASS if situation=="기척" else AsciiFrameScript.INK); grid.set_combat_emphasis(false)
	phase_label.text=situation
	var phase_style:=AsciiFrameScript.borderless_surface(surface_color,0)
	phase_style.border_width_bottom=1;phase_style.border_color=AsciiFrameScript.CYAN
	phase_panel.add_theme_stylebox_override("panel",phase_style)
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
