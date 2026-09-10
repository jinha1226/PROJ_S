class_name PartyEncounterSandbox
extends Control
const PerfProbeScript=preload("res://sim/perf_probe.gd")

const EXPLORATION_ACTOR_MOTION_MSEC := 100
const CONTINUOUS_EXPLORATION_MOTION_MSEC := 110
const MANUAL_CAMERA_SETTLE_MSEC := 55
# AUTO and long routes should read as continuous travel rather than a sequence of
# deliberate single-cell inputs. Motion overlaps the next cadence so actor and
# camera interpolation remain visible without making a large floor tedious.
const CONTINUOUS_CAMERA_SETTLE_MSEC := 110

const SessionScript=preload("res://playtest/party_playtest_session.gd")
const GridScript=preload("res://playtest/party_grid_view.gd")
const MinimapScript=preload("res://playtest/party_minimap.gd")
const PortraitScript=preload("res://playtest/fixed_front_actor_portrait.gd")
const PersonalityPanelScript=preload("res://playtest/npc_personality_panel.gd")
const RelationshipPanelScript=preload("res://playtest/npc_relationship_panel.gd")
const SkillPanelScript=preload("res://playtest/npc_skill_panel.gd")
const ItemSlotScript=preload("res://playtest/item_inventory_slot.gd")
const DarkPixelSkinScript=preload("res://playtest/dark_pixel_ui_skin.gd")
const DarkPixelFrameScript=preload("res://playtest/dark_pixel_ui_frame.gd")
const CompactPortraitScript=preload("res://playtest/compact_party_portrait.gd")
const MapOverlayScript=preload("res://playtest/party_map_overlay.gd")
const BaseProgressPanelScript=preload("res://playtest/base_progress_panel.gd")
const ManualBattleDockScript=preload("res://playtest/manual_battle_dock.gd")
const CommandScript=preload("res://sim/sim_command.gd")
const ActionScript=preload("res://sim/party_action_command.gd")
const ProgressionRegistryScript=preload("res://sim/progression_registry.gd")
const AsciiFrameScript=preload("res://playtest/ascii_ui_frame.gd")
const AsciiGaugeScript=preload("res://playtest/ascii_gauge.gd")
const PartyCommandScript=preload("res://sim/party_exception_command.gd")
const BuildInfoScript=preload("res://playtest/build_info.gd")
const GrowthBuildRegistryScript=preload("res://sim/growth_build_registry.gd")
const AsciiMaterialGrammarScript=preload("res://playtest/ascii_material_grammar.gd")
# Proportional Korean/Latin pixel type keeps the dense mobile UI readable.
# ASCII frames, gauges, and map glyphs deliberately retain LivingWorldMonoKR
# because their column alignment is part of the drawing contract.
const KoreanFont:FontFile=preload("res://assets/fonts/Galmuri14.ttf")
const FONT_AUX:=14
const FONT_BODY:=16
const FONT_KEY:=20
const FONT_SECTION:=18
const FONT_COMMAND:=14
const FONT_CAPTION:=12
const FONT_MICRO:=11
const NEARBY_NPC_FONT_NAME:=16
const NEARBY_NPC_FONT_TEXT:=12
const NEARBY_NPC_FONT_CAPTION:=11
const NEARBY_NPC_FONT_BUTTON:=12
const TOUCH_TARGET:=44
# Field-first product shell: compact fixed rails leave the remaining rectangle
# to the dungeon camera instead of reserving a square map plus dead flex space.
const PRODUCT_TOP_HUD_HEIGHT:=48
# Three Korean-font baselines plus dark panel padding.
const PRODUCT_EVENT_HEIGHT:=66
const PRODUCT_PARTY_CARD_HEIGHT:=72
const AUTO_FORMATION_ORDER:=["WEDGE","LINE","COLUMN"]
# One hop per motion: the canonical step, its actor motion and the camera settle
# all take the same 110ms, so the drawn hero never trails the logical one and the
# main thread is idle between hops for touch input. The old 35ms cadence under a
# 200ms motion ran hops back to back (each ~40ms of CPU) and smeared movement.
const CONTINUOUS_TRAVEL_CADENCE_MSEC:=110
const PRODUCT_ZOOM_CELL_COUNTS:=SessionScript.PRODUCT_ZOOM_CELL_COUNTS
const PRODUCT_ZOOM_DEFAULT_CELL_COUNT:=SessionScript.PRODUCT_ZOOM_DEFAULT_CELL_COUNT
const PRODUCT_ZOOM_REFERENCE_CELL_COUNT:=SessionScript.PRODUCT_ZOOM_REFERENCE_CELL_COUNT
const PRODUCT_EMULATED_MOUSE_SUPPRESS_MSEC:=1500
const PRODUCT_PINCH_STEP_RATIO:=1.12
const ITEM_GRID_COLUMNS:=5
const ITEM_SLOT_MINIMUM:=52

var session
var grid
var grid_zoom_controls:HBoxContainer
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
var minimap_open_button:Button
var recent_event_label:Label
var record_button:Button
var hero_detail_button:Button
var enemy_vision_overlay_button:Button
var top_hud_actions:HBoxContainer
var product_menu_button:MenuButton
var product_bag_button:Button
var product_restart_confirm:ConfirmationDialog
var expedition_floor_label:Label
var return_timer_label:Label
var ration_label:Label
var cards:HBoxContainer
var deck:VBoxContainer
var log_label:Label
var guild_tutorial_hud:MenuButton
var info_scroll:ScrollContainer
var event_surface:PanelContainer
var event_label:Label
var combat_action_area:VBoxContainer
var action_feedback_label:Label
var combat_action_dock:HBoxContainer
var party_command_menu:MenuButton
var product_auto_button:Button
var product_interact_button:Button
var product_attack_button:Button
var product_wait_guard_button:Button
var product_rest_button:Button
var product_pickup_button:Button
# Rest macro (presentation-only): repeated journaled waits until HP is full.
var _product_rest_active:=false
var _product_rest_generation:=0
var _product_rest_due_msec:=-1
var _product_rest_last_health:=-1
var _product_rest_idle_waits:=0
var _product_rest_started_time:=0
const PRODUCT_REST_CADENCE_MSEC:=90
const PRODUCT_REST_IDLE_LIMIT:=16
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
var base_modal:Control
var base_modal_panel:PanelContainer
var base_preview
var base_close_button:Button
var species_picker_modal:Control
var species_picker_panel:PanelContainer
var species_picker_buttons:VBoxContainer
var selected_member_id:=-1
var selected_target_id:=-1
var enemy_vision_overlay_enabled:=false
var _last_torch_depletion_alert_event_id:=-1
var town_facility_id:=""
var town_ui_state:Dictionary={"filter":"ADVENTURERS","resident":-1,"trade":"BUY","owner":-1}
var selected_base_building_id:="STORAGE"
var _last_view_mode:=""
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
var nearby_npc_panel:PanelContainer
var nearby_npc_content:VBoxContainer
var nearby_npc_name:Label
var nearby_npc_condition:Label
var nearby_npc_personality:Label
var nearby_npc_affinity:Label
var nearby_npc_equipment:Label
var nearby_npc_recruitment:Label
var nearby_npc_detail_button:Button
var nearby_npc_action_button:Button
var nearby_npc_attack_button:Button
var nearby_npc_toggle_button:Button
var nearby_npc_entity_id:int=-1
var nearby_npc_last_entity_id:int=-1
var nearby_npc_story_state:=""
var nearby_npc_collapsed:=false
var _nearby_npc_touch_index:=-1
var _nearby_npc_touch_control:=""
var _nearby_npc_touch_origin:=Vector2.ZERO
var _nearby_npc_touch_dragged:=false
var _nearby_npc_mouse_control:=""
var _nearby_npc_ignore_mouse_until_msec:=-1
var member_detail_modal:Control
var member_detail_panel:PanelContainer
var member_detail_title:Label
var member_detail_subtitle:Label
var member_detail_glyph_seal
var member_detail_scroll:ScrollContainer
var member_detail_scroll_content:VBoxContainer
var member_detail_tab_stash:Control
var member_detail_body:Label
var member_status_window:VBoxContainer
var member_detail_tab_row:HBoxContainer
var member_detail_status_tab:Button
var member_detail_personality_tab:Button
var member_detail_relationship_tab:Button
var member_detail_skill_tab:Button
var member_detail_item_tab:Button
var member_detail_current_tab:="STATUS"
var member_detail_has_skills:=false
var member_detail_has_skill_summary:=false
var member_detail_has_personality:=false
var member_detail_has_relationships:=false
var member_personality_window
var member_relationship_window
var member_skill_window
var member_detail_dismiss_available:=false
var member_detail_candidate_available:=false
var member_detail_attack_available:=false
var member_progression_window:VBoxContainer
var member_ability_window:VBoxContainer
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
var member_status_equipment_window:VBoxContainer
var member_item_equipment_rows:VBoxContainer
var member_item_equipment_grid:GridContainer
var member_item_backpack_rows:GridContainer
var member_item_selected_stats:Label
var member_item_quick_unequip_button:Button
var member_item_action_row:HBoxContainer
var member_item_equip_button:Button
var member_item_unequip_button:Button
var member_item_drop_button:Button
var member_item_use_button:Button
var member_item_selected_id:=""
var member_item_selected_slot:=""
var member_item_popover:PanelContainer
var member_item_popover_title:Label
var member_item_popover_body:Label
var member_item_popover_compare:Label
var member_item_popover_close:Button
var member_item_popover_anchor:Control
var pending_ground_pickup_id:=""
var pending_ground_pickup_label:=""
var member_detail_close:Button
var member_detail_dismiss:Button
var member_detail_candidate_action:Button
var member_detail_attack:Button
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
var autonomous_battle_clock=preload("res://playtest/autonomous_battle_clock.gd").new()
var autonomous_battle_summary:=""
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
var companion_order_editor
var member_order_button:Button
var member_order_cancel:Button
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
var _product_immediate_touch_indices:Dictionary={}
var _product_touch_started_msec:=-1
var _product_mouse_control:=""
var _product_mouse_started_msec:=-1
var _product_mouse_origin:=Vector2.ZERO
var portrait_gesture=preload("res://playtest/portrait_gesture.gd").new()
var _product_ignore_mouse_until_msec:=-1
var _product_auto_explore_generation:=0
var _product_auto_explore_pending:=false
var _product_auto_explore_due_frame:=-1
var _product_auto_explore_due_msec:=-1
var _product_auto_explore_scheduled_generation:=-1
var _product_auto_last_hop_started_msec:=-1
var _product_auto_stop_feedback:=""
var _product_transient_event_feedback:=""
var _product_attack_targeting:=false
var _party_command_targeting:=false
var _battle_target_mode:=""
var _battle_target_actor_id:=-1
var _battle_target_skill_id:=""
var _battle_target_skill_label:=""
var _battle_target_prompt:=""
var _battle_target_prior_paused:=false
var _battle_target_committing:=false
var battle_drag:Control
var battle_enemy_strip:ScrollContainer
var hero_skill_row:HBoxContainer
var product_tactics_button:Button
var product_tactics_popup:PopupMenu
var _retreat_active:=false
var _approach_step_pending:=false
var battle_command_flow=preload("res://playtest/battle_command_flow.gd").new()
var battle_loot_panel:Control
var _shown_loot_battle_id:=-1
var _product_zoom_cell_count:=PRODUCT_ZOOM_DEFAULT_CELL_COUNT
var _resize_refresh_queued:=false
var _product_pinch_points:Dictionary={}
var _product_pinch_last_distance:=0.0
var _product_pinch_gesture_active:=false
var _product_magnify_accumulator:=1.0
# Presentation cadence only. Tests may set this to zero; it never participates
# in canonical route choice, journal contents, simulation time, or replay.
var continuous_travel_cadence_msec:=CONTINUOUS_TRAVEL_CADENCE_MSEC
# Combat actors glide for most of the 0.32s display tick instead of a 150ms hop
# followed by a dead pause; the diorama clamps at 240ms.
const BATTLE_ACTOR_MOTION_MSEC:=240
# Presentation-only combat pacing. HERO_TURN stops the display clock at every
# protagonist event until the player releases that turn (any accepted hero
# input, or [진행]); AUTO is the old free-running clock. Never saved.
var battle_mode:="HERO_TURN"
const HERO_TURN_UNITS_PER_SECOND:=400.0
var _hero_turn_released:=false
var _hero_turn_was_waiting:=false

var base_work_clock=preload("res://playtest/base_work_clock.gd").new()
var base_map_camera=preload("res://playtest/base_map_camera.gd").new()

func _notification(what:int)->void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and portrait_gesture!=null:
		portrait_gesture.actor_id=-1

func _process(_delta:float)->void:
	_tick_portrait_long_press()
	if portrait_gesture.actor_id>=0:return
	base_work_clock.tick(self,_delta)
	if not _battle_target_mode.is_empty() and grid!=null and grid.modal_open:
		_cancel_battle_targeting("대상 선택을 취소했습니다.")
	_tick_autonomous_battle(_delta)
	var frame:=Engine.get_process_frames()
	var now_msec:=Time.get_ticks_msec()
	if _product_rest_active and now_msec>=_product_rest_due_msec \
			and _product_touch_index<0 and (member_detail_modal==null or not member_detail_modal.visible):
		_continue_product_rest(_product_rest_generation)
	if _product_auto_explore_pending and frame>=_product_auto_explore_due_frame \
			and now_msec>=_product_auto_explore_due_msec:
		# A held product button is an unresolved user gesture. AUTO may keep its
		# running state, but no authoritative hop can occur until release/cancel.
		if _product_touch_index>=0 or member_detail_modal!=null \
				and member_detail_modal.visible:
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
		# before release cancels it and commits the one manual step. A pinch pauses
		# route presentation until both fingers leave, then resumes the same route.
		if _product_touch_index>=0 or route_paused_by_modal or route_paused_by_pointer \
				or _product_pinch_gesture_active \
				or member_detail_modal!=null and member_detail_modal.visible:
			route_continue_due_frame=frame+1
		else:
			var expected_route_generation:=route_scheduled_generation
			route_continue_pending=false;route_continue_due_frame=-1
			route_continue_due_msec=-1;route_scheduled_generation=-1
			_continue_route_on_cadence(expected_route_generation)

func _input(event:InputEvent)->void:
	if battle_loot_panel!=null and battle_loot_panel.visible:return
	if portrait_gesture.handle(self,event):return
	if _handle_field_shortcuts(event):return
	if grid!=null and (battle_drag==null or not battle_drag.active) \
			and grid.capture_nearby_list_input(event):return
	if battle_drag!=null and battle_drag.handle_input(self,event):return
	if _handle_product_pinch_zoom(event):return
	# The nearby-NPC card is a child of the map. Claim its touch before the map's
	# floor gesture sees it, otherwise its ordinary Buttons never receive mobile
	# taps and the same tap may issue a movement command behind the card.
	if _handle_nearby_npc_touch(event):return
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
		if bool(route_state.get("active",false)) and not grid.pinch_zoom_enabled:
			_cancel_active_route()
	if _handle_product_control_touch(event):return
	if member_detail_modal==null or not member_detail_modal.visible:return
	if _handle_item_popover_outside_pointer(event):return
	if member_detail_current_tab in ["STATUS","ITEM"]:
		_handle_item_ledger_touch(event);return
	if member_detail_current_tab!="SKILL":return
	if not member_detail_has_skills:return
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
			var action_info:=_item_action_at_position(event.position)
			if not action_info.is_empty():
				_item_touch_index=event.index;_item_touch_action=str(action_info.get("action",""))
				_item_touch_id="";_item_touch_slot=str(action_info.get("slot",""));_item_touch_origin=event.position
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
			if not activate_action.is_empty():_activate_item_touch_action(activate_action,activate_slot)
			elif not activate_id.is_empty():_on_item_row_selected(activate_id,activate_slot)
	elif event is InputEventScreenDrag and event.index==_item_touch_index:
		var slop:=24.0 if not _item_touch_action.is_empty() else float(member_detail_scroll.scroll_deadzone)
		if event.position.distance_to(_item_touch_origin)>=slop:
			_item_touch_dragged=true
			if _item_touch_action.is_empty():
				_hide_item_popover(false)
				member_detail_scroll.scroll_vertical-=int(event.relative.y)
		get_viewport().set_input_as_handled()

func _item_action_at_position(global_position:Vector2)->Dictionary:
	var buttons:Array=[
		[member_item_reload_button,"RELOAD",""],
		[member_item_equip_button,"EQUIP",""],
		[member_item_unequip_button,"UNEQUIP",str(member_item_unequip_button.get_meta(
			"item_slot",member_item_selected_slot)) if member_item_unequip_button!=null else ""],
		[member_item_use_button,"USE",""],
		[member_item_drop_button,"DROP",""],
		[member_item_popover_close,"CLOSE",""],
	]
	for entry in buttons:
		var button:=entry[0] as Button
		if button!=null and button.is_visible_in_tree() and not button.disabled \
				and button.get_global_rect().has_point(global_position):
			return {"action":str(entry[1]),"slot":str(entry[2])}
	return {}

func _handle_item_popover_outside_pointer(event:InputEvent)->bool:
	if member_item_popover==null or not member_item_popover.visible:return false
	var pointer:=Vector2.ZERO;var pressed:=false
	if event is InputEventScreenTouch:
		pointer=event.position;pressed=event.pressed
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		pointer=event.position;pressed=event.pressed
	else:return false
	if not pressed or member_item_popover.get_global_rect().has_point(pointer):return false
	var row:=_item_row_at_position(pointer)
	_hide_item_popover(row.is_empty())
	# A visible ledger row may replace the old popover in the same tap. Any other
	# outside pointer is exclusively a dismiss gesture and must not activate the
	# control hidden underneath it.
	if not row.is_empty():return false
	get_viewport().set_input_as_handled();return true

func _activate_item_touch_action(action:String,slot:String="")->void:
	match action:
		"RELOAD":_on_item_reload()
		"EQUIP":_on_item_equip_selected()
		"UNEQUIP":_on_item_unequip_slot(slot if not slot.is_empty() else member_item_selected_slot)
		"USE":_on_item_use_selected()
		"DROP":_on_item_drop_selected()
		"CLOSE":_hide_item_popover()

func _handle_nearby_npc_touch(event:InputEvent)->bool:
	if nearby_npc_panel==null:return false
	if not nearby_npc_panel.is_visible_in_tree() and _nearby_npc_touch_index<0:return false
	if member_detail_modal!=null and member_detail_modal.visible \
			or record_modal!=null and record_modal.visible \
			or map_overlay!=null and map_overlay.visible:return false
	if not event is InputEventScreenTouch and not event is InputEventScreenDrag:return false
	if event is InputEventScreenTouch:
		if event.pressed:
			if _nearby_npc_touch_index>=0 \
					or not nearby_npc_panel.get_global_rect().has_point(event.position):return false
			_nearby_npc_touch_index=event.index
			_nearby_npc_touch_control=_nearby_npc_control_at_position(event.position)
			_nearby_npc_touch_origin=event.position;_nearby_npc_touch_dragged=false
			_nearby_npc_ignore_mouse_until_msec=Time.get_ticks_msec() \
				+PRODUCT_EMULATED_MOUSE_SUPPRESS_MSEC
			_cancel_product_auto_explore("auto_explore_user_command",false)
			_cancel_route_for_user_interruption()
			# Recruitment and attack are explicit one-shot commands. Fire them on
			# touch-down so a browser-reprojected release cannot swallow the button;
			# the captured release below is still consumed and cannot run it twice.
			if _nearby_npc_touch_control in ["NearbyNpcRecruit","NearbyNpcAttack"]:
				var immediate_control:=_nearby_npc_touch_control
				_nearby_npc_touch_control=""
				_activate_nearby_npc_control(immediate_control)
			get_viewport().set_input_as_handled();return true
		if event.index!=_nearby_npc_touch_index:return false
		var activate:=_nearby_npc_touch_control if not _nearby_npc_touch_dragged else ""
		_nearby_npc_touch_index=-1;_nearby_npc_touch_control=""
		_nearby_npc_touch_dragged=false
		_nearby_npc_ignore_mouse_until_msec=Time.get_ticks_msec() \
			+PRODUCT_EMULATED_MOUSE_SUPPRESS_MSEC
		get_viewport().set_input_as_handled()
		if not activate.is_empty():_activate_nearby_npc_control(activate)
		return true
	if event.index==_nearby_npc_touch_index:
		if event.position.distance_to(_nearby_npc_touch_origin)>=8.0:
			_nearby_npc_touch_dragged=true
		get_viewport().set_input_as_handled();return true
	return false

func _nearby_npc_control_at_position(global_position:Vector2)->String:
	for button in [nearby_npc_toggle_button,nearby_npc_detail_button,
			nearby_npc_action_button,nearby_npc_attack_button]:
		if button!=null and button.is_visible_in_tree() and not button.disabled \
				and button.get_global_rect().has_point(global_position):return button.name
	return ""

func _activate_nearby_npc_control(control_name:String)->void:
	match control_name:
		"NearbyNpcToggle":_on_nearby_npc_toggle()
		"NearbyNpcDetail":_on_nearby_npc_detail()
		"NearbyNpcRecruit":_on_nearby_npc_action()
		"NearbyNpcAttack":_on_nearby_npc_attack()

func _on_nearby_npc_button_gui_input(event:InputEvent,control_name:String)->void:
	# Mouse and touch each own one path. This also drops the compatibility mouse
	# event browsers synthesize after an already handled ScreenTouch.
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT:return
	if event.device==InputEvent.DEVICE_ID_EMULATION \
			or Time.get_ticks_msec()<=_nearby_npc_ignore_mouse_until_msec:
		_nearby_npc_mouse_control="";accept_event();return
	if event.pressed:
		if control_name in ["NearbyNpcRecruit","NearbyNpcAttack"]:
			_nearby_npc_mouse_control="";accept_event()
			_activate_nearby_npc_control(control_name);return
		_nearby_npc_mouse_control=control_name
		_cancel_product_auto_explore("auto_explore_user_command",false)
		_cancel_route_for_user_interruption()
		accept_event();return
	var activate:=_nearby_npc_mouse_control==control_name
	_nearby_npc_mouse_control="";accept_event()
	if activate:_activate_nearby_npc_control(control_name)

func _item_row_at_position(global_position:Vector2)->Dictionary:
	for ledger in [member_item_equipment_rows,member_item_equipment_grid,
			member_item_backpack_rows]:
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

func _handle_field_shortcuts(event:InputEvent)->bool:
	if session==null:return false
	if grid==null or grid.modal_open or member_detail_modal!=null and member_detail_modal.visible:return false
	if record_modal!=null and record_modal.visible or map_overlay!=null and map_overlay.visible:return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_V:
		_toggle_enemy_vision_overlay()
		get_viewport().set_input_as_handled();return true
	if not session.field_turns_active():return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE and not _battle_target_mode.is_empty():
		_cancel_battle_targeting();_request_refresh()
		get_viewport().set_input_as_handled();return true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F1,KEY_F2,KEY_F3,KEY_F4]:
		var index:int=event.keycode-KEY_F1
		var ids:Array=session.sim.world.party_encounter.active_party_member_ids
		if index<ids.size():_on_compact_member_card_pressed(int(ids[index]),"")
		get_viewport().set_input_as_handled();return true
	return false

func _toggle_enemy_vision_overlay()->void:
	# This is a presentation toggle only: it never enters the field action path.
	enemy_vision_overlay_enabled=!enemy_vision_overlay_enabled
	_request_refresh()

func _handle_product_control_touch(event:InputEvent)->bool:
	if not event is InputEventScreenTouch and not event is InputEventScreenDrag:return false
	if event is InputEventScreenTouch and not event.pressed and event.index==_product_touch_index and _product_touch_dragged:
		_product_touch_index=-1;_product_touch_control="";_product_touch_dragged=false
		_product_ignore_mouse_until_msec=Time.get_ticks_msec()+PRODUCT_EMULATED_MOUSE_SUPPRESS_MSEC
		get_viewport().set_input_as_handled();return true
	if not _is_solo_product_session() or not combat_action_area.visible:return false
	if member_detail_modal!=null and member_detail_modal.visible \
			or record_modal!=null and record_modal.visible \
			or map_overlay!=null and map_overlay.visible:return false
	if event is InputEventScreenTouch:
		if event.pressed:
			# One touch index owns exactly one immediate command until its release.
			# Web input can redeliver a pressed packet after a slow frame or a HUD
			# rebuild; time-window deduplication allowed those late copies to step
			# the actor a second tile.
			if _product_immediate_touch_indices.has(event.index):
				get_viewport().set_input_as_handled();return true
			var control_name:=_product_control_at_position(event.position)
			if control_name.is_empty():return false
			if _product_control_activates_on_press(control_name):
				var now_msec:=Time.get_ticks_msec()
				_product_immediate_touch_indices[event.index]={
					"control":control_name,"started_at_msec":now_msec}
				_product_ignore_mouse_until_msec=now_msec+PRODUCT_EMULATED_MOUSE_SUPPRESS_MSEC
				get_viewport().set_input_as_handled()
				_activate_product_control(control_name)
				return true
			if _product_touch_index>=0:
				if Time.get_ticks_msec()-_product_touch_started_msec<1000:return false
				_product_touch_index=-1;_product_touch_control="";_product_touch_dragged=false
			_product_touch_index=event.index;_product_touch_control=control_name
			_product_touch_started_msec=Time.get_ticks_msec()
			_product_touch_origin=event.position;_product_touch_dragged=false
			_product_ignore_mouse_until_msec=Time.get_ticks_msec() \
				+PRODUCT_EMULATED_MOUSE_SUPPRESS_MSEC
			get_viewport().set_input_as_handled()
			return true
		if _product_immediate_touch_indices.has(event.index):
			_product_immediate_touch_indices.erase(event.index)
			_product_ignore_mouse_until_msec=Time.get_ticks_msec() \
				+PRODUCT_EMULATED_MOUSE_SUPPRESS_MSEC
			get_viewport().set_input_as_handled();return true
		if event.index!=_product_touch_index:return false
		# ScreenTouch coordinates may be reprojected by stretch mode between the
		# press and release frames. A gesture that began on one exact button and did
		# not cross the drag threshold is still that button's short tap.
		var activate_name:=_product_touch_control if not _product_touch_dragged and not event.canceled else ""
		_product_touch_index=-1;_product_touch_control="";_product_touch_dragged=false
		_product_touch_started_msec=-1
		_product_ignore_mouse_until_msec=Time.get_ticks_msec() \
			+PRODUCT_EMULATED_MOUSE_SUPPRESS_MSEC
		get_viewport().set_input_as_handled()
		if not activate_name.is_empty():
			_activate_product_control(activate_name)
		return true
	if event.index==_product_touch_index:
		if event.position.distance_to(_product_touch_origin)>=24.0:_product_touch_dragged=true
		get_viewport().set_input_as_handled();return true
	return false

func _product_control_activates_on_press(control_name:String)->bool:
	return false

func _tick_portrait_long_press()->void:
	portrait_gesture.tick(self)

func _product_control_at_position(global_position:Vector2)->String:
	var controls:Array=[]
	controls.append_array([product_auto_button,
		product_tactics_button,product_rest_button,product_pickup_button,
		product_interact_button,product_attack_button,product_wait_guard_button,
		product_execute_button,product_bag_button,minimap_open_button,
		map_nav_button,person_nav_button,skill_nav_button,equipment_nav_button,
		history_nav_button,enemy_vision_overlay_button])
	if session!=null and session.field_turns_active():
		if hero_skill_row!=null:controls.append_array(hero_skill_row.find_children("ActorSkill_*","Button",true,false))
	for control_value in controls:
		if not is_instance_valid(control_value):continue
		var button:=control_value as Button
		if button!=null and button.is_visible_in_tree() and not button.disabled \
				and button.get_global_rect().has_point(global_position):return button.name
	return ""

func _activate_product_control(control_name:String)->void:
	if control_name.begins_with("ActorSkill_"):
		var button=hero_skill_row.find_child(control_name,true,false)
		if button!=null and not button.disabled:
			_on_manual_skill_selected(int(button.get_meta("actor_id")),str(button.get_meta("skill_id")),str(button.get_meta("skill_label")))
		return
	if control_name.begins_with("MemberCard"):
		_on_compact_member_card_pressed(int(control_name.trim_prefix("MemberCard")),"");return
	match control_name:
		"EnemyVisionOverlay":_toggle_enemy_vision_overlay()
		"ProductTactics":_on_product_tactics()
		"ProductRest":_on_product_rest()
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
		"ProductBag":_open_hero_detail_tab("ITEM")
		"MinimapOpen":_toggle_map_overlay()
		"MapNavigation":_toggle_map_overlay()
		"PersonNavigation":_open_hero_detail_tab("STATUS")
		"SkillNavigation":_open_hero_detail_tab("SKILL")
		"EquipmentNavigation":_open_hero_detail_tab("ITEM")
		"HistoryNavigation":_toggle_record_modal()

func _on_product_button_gui_input(event:InputEvent,control_name:String)->void:
	if event is InputEventMouseMotion and _product_mouse_control==control_name:
		if event.position.distance_to(_product_mouse_origin)>=8.0:_product_mouse_control=""
		return
	# Product controls use one explicit pointer path. Connecting Button.pressed as
	# well as handling ScreenTouch in _input caused a mobile release to execute the
	# same authoritative command twice. Mouse activation is handled here; touch is
	# handled exclusively by _handle_product_control_touch above.
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT:return
	# Web/mobile may synthesize mouse press/release after a handled ScreenTouch.
	# Ignore that compatibility event so one physical release has one command.
	if event.device==InputEvent.DEVICE_ID_EMULATION \
			or Time.get_ticks_msec()<=_product_ignore_mouse_until_msec:
		_product_mouse_control="";accept_event();return
	if event.pressed:
		if _product_control_activates_on_press(control_name):
			_product_mouse_control="";accept_event()
			_activate_product_control(control_name);return
		_product_mouse_control=control_name
		_product_mouse_started_msec=Time.get_ticks_msec()
		_product_mouse_origin=event.position
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
var _refresh_after_pointer:=false
var _last_direct_solo_refresh_profile:Dictionary={}
var _last_direct_solo_turn_profile:Dictionary={}
var _last_continuous_exploration_refresh_profile:Dictionary={}
var _species_picker_committed:=false

func _ready()->void:
	_build_ui()
	if not _initialized_for_headless_test and session==null:
		session=SessionScript.new(SessionScript.DEFAULT_WORLD_SEED,
			_issue_new_personality_seed(),SessionScript.DUO_SCENARIO_ID,"human",true)
		auto_orchestration_enabled=true;_reset_auto_flow()
	_refresh()
	if not _initialized_for_headless_test and not _web_capture_preview_requested():
		show_species_picker_for_new_run()
	if _initialized_for_headless_test and auto_orchestration_enabled:
		_arm_pending_auto_after_tree_entry()

func _web_capture_preview_requested()->bool:
	if not OS.has_feature("web"):return false
	return bool(JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).has('capture_preview')"))
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
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var ui_theme:=Theme.new();ui_theme.default_font_size=FONT_BODY
	DarkPixelSkinScript.configure_theme(ui_theme);theme=ui_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg:=ColorRect.new();bg.name="SandboxBackground"
	bg.color=DarkPixelSkinScript.CANVAS;bg.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	root_layout=VBoxContainer.new(); root_layout.name="PartyLayout"; root_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layout.offset_left=6; root_layout.offset_right=-6; root_layout.offset_top=4; root_layout.offset_bottom=-4; root_layout.add_theme_constant_override("separation",4); add_child(root_layout)
	phase_panel=PanelContainer.new();phase_panel.name="TopExplorationHUD"
	var top_rail:=DarkPixelSkinScript.panel_surface(DarkPixelSkinScript.FOLIO,DarkPixelSkinScript.IRON_EDGE,0,1)
	phase_panel.add_theme_stylebox_override("panel",top_rail)
	phase_panel.custom_minimum_size.y=64;root_layout.add_child(phase_panel)
	phase_row=HBoxContainer.new();phase_row.name="TopExplorationHUDRow"
	phase_row.add_theme_constant_override("separation",4);phase_panel.add_child(phase_row)
	minimap_frame=DarkPixelFrameScript.new();minimap_frame.name="MinimapPixelFrame"
	minimap_frame.configure("",DarkPixelSkinScript.BRASS,DarkPixelSkinScript.FOLIO,true)
	minimap_frame.add_theme_constant_override("margin_top",4)
	minimap_frame.custom_minimum_size=Vector2(48,44);phase_row.add_child(minimap_frame)
	minimap=MinimapScript.new();minimap.name="ExplorationMinimap"
	minimap.custom_minimum_size=Vector2(40,26);minimap.mouse_filter=Control.MOUSE_FILTER_IGNORE
	minimap_frame.add_child(minimap)
	# The compact map itself is the navigation affordance. A transparent real
	# Button keeps desktop mouse and mobile touch on the same single-fire path.
	minimap_open_button=Button.new();minimap_open_button.name="MinimapOpen"
	minimap_open_button.flat=true;minimap_open_button.focus_mode=Control.FOCUS_NONE
	minimap_open_button.tooltip_text="발견한 전체 지도 열기"
	minimap_open_button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	minimap_open_button.set_meta("product_control",true)
	minimap_open_button.gui_input.connect(
		_on_product_button_gui_input.bind("MinimapOpen"))
	minimap_frame.add_child(minimap_open_button)
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
	expedition_floor_label=Label.new();expedition_floor_label.name="ExpeditionFloor"
	expedition_floor_label.add_theme_font_size_override("font_size",FONT_KEY)
	expedition_floor_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	expedition_floor_label.add_theme_color_override("font_color",AsciiFrameScript.INK)
	expedition_floor_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	expedition_floor_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	expedition_floor_label.visible=false;situation_row.add_child(expedition_floor_label)
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
	return_timer_label=Label.new();return_timer_label.name="ReturnTimer"
	return_timer_label.add_theme_font_size_override("font_size",FONT_AUX)
	return_timer_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	return_timer_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	return_timer_label.clip_text=true;return_timer_label.visible=false
	var clock_row:=HBoxContainer.new();clock_row.name="ClockRow"
	clock_row.add_theme_constant_override("separation",8);situation_stack.add_child(clock_row)
	return_timer_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;situation_row.add_child(return_timer_label)
	return_timer_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	return_timer_label.add_theme_font_size_override("font_size",16)
	expedition_floor_label.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	expedition_floor_label.custom_minimum_size.x=48
	expedition_floor_label.add_theme_font_size_override("font_size",16)
	ration_label=Label.new();ration_label.name="RationGauge"
	ration_label.add_theme_font_size_override("font_size",FONT_AUX)
	ration_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	ration_label.add_theme_font_override("font",DarkPixelSkinScript.PixelFont)
	ration_label.visible=false;clock_row.add_child(ration_label)
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
	DarkPixelSkinScript.apply_action_button(record_button,DarkPixelSkinScript.CYAN)
	hero_detail_button=Button.new();hero_detail_button.name="HeroDetailButton";hero_detail_button.text="[인물]"
	hero_detail_button.custom_minimum_size=Vector2(44,44);hero_detail_button.add_theme_font_size_override("font_size",FONT_COMMAND);hero_detail_button.tooltip_text="주인공 상세 정보"
	hero_detail_button.clip_text=true;hero_detail_button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	hero_detail_button.pressed.connect(_open_hero_detail);top_hud_actions.add_child(hero_detail_button)
	DarkPixelSkinScript.apply_action_button(hero_detail_button,DarkPixelSkinScript.BRASS)
	enemy_vision_overlay_button=Button.new();enemy_vision_overlay_button.name="EnemyVisionOverlay"
	enemy_vision_overlay_button.text="V";enemy_vision_overlay_button.custom_minimum_size=Vector2(44,44)
	enemy_vision_overlay_button.toggle_mode=true;enemy_vision_overlay_button.focus_mode=Control.FOCUS_NONE
	enemy_vision_overlay_button.add_theme_font_size_override("font_size",FONT_KEY)
	enemy_vision_overlay_button.tooltip_text="적 시야 표시 (V) · 시간 진행 없음"
	enemy_vision_overlay_button.pressed.connect(_toggle_enemy_vision_overlay)
	top_hud_actions.add_child(enemy_vision_overlay_button)
	DarkPixelSkinScript.apply_action_button(enemy_vision_overlay_button,DarkPixelSkinScript.BLOOD)
	product_menu_button=MenuButton.new();product_menu_button.name="ProductMainMenu"
	product_menu_button.text="☰";product_menu_button.custom_minimum_size=Vector2(44,44)
	product_menu_button.add_theme_font_size_override("font_size",FONT_COMMAND)
	product_menu_button.focus_mode=Control.FOCUS_NONE;product_menu_button.visible=false
	product_menu_button.tooltip_text="원정 다시 시작 · 새 원정"
	var menu_popup:=product_menu_button.get_popup()
	menu_popup.add_item("인물 · 상태",2);menu_popup.add_item("이능",3)
	menu_popup.add_item("가방 · 장비",4);menu_popup.add_item("사건 기록",5)
	menu_popup.add_item("거점 현황",7)
	menu_popup.add_item("4인 전투 테스트 · 마법",6)
	menu_popup.add_separator("환경 시험 · 선택 후 바닥 터치")
	menu_popup.add_item("물 생성 → 물웅덩이 / 소화",20)
	menu_popup.add_item("냉각 → 물 결빙",21)
	menu_popup.add_item("방전 → 물 / 금속 전도",22)
	menu_popup.add_item("화염구 → 증발 / 해빙 / 점화",23)
	menu_popup.add_separator()
	menu_popup.add_item("같은 원정 다시 시작",0);menu_popup.add_item("새 게임 · 새로운 재능",1)
	menu_popup.id_pressed.connect(_on_product_menu_id)
	top_hud_actions.add_child(product_menu_button)
	DarkPixelSkinScript.apply_action_button(product_menu_button,DarkPixelSkinScript.CYAN)
	# Compatibility aliases point at the unified HUD rather than preserving a
	# second objective/time strip in the product layout.
	run_objective_bar=phase_panel;run_objective_label=recent_event_label
	grid=GridScript.new(); grid.name="PartyGrid"; grid.custom_minimum_size=Vector2(348,348); grid.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	grid.animate_passive_terrain=false
	grid.world_cell_pressed.connect(_on_cell); grid.actor_pressed.connect(_on_actor)
	grid.actor_inspect_requested.connect(_open_member_detail)
	grid.tile_long_pressed.connect(_on_tile_long_pressed)
	grid.pointer_gesture_started.connect(_on_grid_pointer_started)
	grid.pointer_gesture_finished.connect(_on_grid_pointer_finished); root_layout.add_child(grid)
	_build_product_zoom_controls()
	_build_nearby_npc_card()
	guild_tutorial_hud=preload("res://playtest/guild_tutorial_hud.gd").new()
	grid.add_child(guild_tutorial_hud)
	guild_tutorial_hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	guild_tutorial_hud.offset_left=4;guild_tutorial_hud.offset_right=-4
	guild_tutorial_hud.offset_top=-48;guild_tutorial_hud.offset_bottom=-4
	guild_tutorial_hud.z_index=5;guild_tutorial_hud.hide()
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
	DarkPixelSkinScript.apply_panel(event_surface,"COMPACT")
	root_layout.add_child(event_surface)
	var event_margin:=MarginContainer.new();event_margin.name="EventSurfaceInset"
	event_margin.size_flags_vertical=Control.SIZE_EXPAND_FILL
	event_margin.add_theme_constant_override("margin_left",6);event_margin.add_theme_constant_override("margin_right",100)
	event_surface.add_child(event_margin)
	event_label=Label.new();event_label.name="CompactMeaningfulEvent";event_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	# Reserve three complete Korean-font baselines, including panel padding.
	event_label.add_theme_font_size_override("font_size",FONT_MICRO);event_label.max_lines_visible=3
	event_label.size_flags_vertical=Control.SIZE_EXPAND_FILL;event_label.custom_minimum_size.y=54
	event_label.tooltip_text="전체 사건은 메뉴의 사건 기록에서 확인"
	event_label.clip_text=true;event_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	event_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;event_margin.add_child(event_label)
	# Hero skills sit directly above the portraits in exploration and combat
	# alike. Tapping one paints the reachable cells red; tapping a target there
	# uses it (before contact: a first strike).
	hero_skill_row=HBoxContainer.new();hero_skill_row.name="HeroSkillRow"
	hero_skill_row.custom_minimum_size.y=48;hero_skill_row.visible=false
	hero_skill_row.add_theme_constant_override("separation",2);root_layout.add_child(hero_skill_row)
	combat_action_area=VBoxContainer.new();combat_action_area.name="CombatActionArea";combat_action_area.custom_minimum_size.y=84
	combat_action_area.add_theme_constant_override("separation",2);combat_action_area.visible=false;root_layout.add_child(combat_action_area)
	action_feedback_label=Label.new();action_feedback_label.name="ActionFeedback";action_feedback_label.custom_minimum_size.y=38
	action_feedback_label.add_theme_font_size_override("font_size",FONT_AUX);action_feedback_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	action_feedback_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;action_feedback_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	combat_action_area.add_child(action_feedback_label)
	combat_action_dock=HBoxContainer.new(); combat_action_dock.name="CombatActionDock"; combat_action_dock.custom_minimum_size.y=TOUCH_TARGET
	combat_action_dock.add_theme_constant_override("separation",4);combat_action_dock.visible=false;combat_action_area.add_child(combat_action_dock)
	companion_order_editor=preload("res://playtest/companion_order_editor.gd").new()
	combat_action_area.add_child(companion_order_editor)
	companion_order_editor.finished.connect(_finish_companion_order_edit)
	companion_order_editor.feedback.connect(func(message:String):
		notice_text=message;action_feedback_text=message
		_product_transient_event_feedback=message
		event_label.text=message)
	hud_bottom_flex=Control.new();hud_bottom_flex.name="HudBottomFlex"
	hud_bottom_flex.size_flags_vertical=Control.SIZE_EXPAND_FILL
	hud_bottom_flex.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud_bottom_flex.visible=false
	root_layout.add_child(hud_bottom_flex)
	_build_bottom_navigation()
	_build_build_label()
	_build_product_tactics_popup()
	_build_tile_popover()
	_build_member_detail_modal()
	_build_map_overlay()
	_build_record_modal()
	_build_base_modal()
	_build_species_picker()
	# No turn clock: combat is driven by the hero's taps. Enemy portraits float
	# over the map's top edge during a fight (party focus targets).
	battle_drag=preload("res://playtest/battle_target_drag.gd").new();add_child(battle_drag)
	battle_enemy_strip=preload("res://playtest/battle_enemy_strip.gd").new()
	grid.add_child(battle_enemy_strip);battle_enemy_strip.hide()
	battle_enemy_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	battle_enemy_strip.offset_bottom=48.0;battle_enemy_strip.z_index=20
	battle_loot_panel=preload("res://playtest/battle_loot_panel.gd").new();add_child(battle_loot_panel)
	battle_loot_panel.hide()
	battle_loot_panel.take_requested.connect(_take_battle_loot)
	battle_loot_panel.closed.connect(_close_battle_loot)
	_apply_dark_pixel_shell_skin()
	resized.connect(_on_surface_resized)

func _apply_dark_pixel_shell_skin()->void:
	for panel in [record_panel,species_picker_panel]:
		if panel is PanelContainer:DarkPixelSkinScript.apply_panel(panel,"FOLIO")
	if event_surface!=null:DarkPixelSkinScript.apply_panel(event_surface,"COMPACT")
	for button in find_children("*","Button",true,false):
		if not button is Button:continue
		if button==minimap_open_button or bool(button.get_meta("inventory_slot",false)) \
				or button.name=="SkillModeButton":continue
		var danger:=button.name in ["MemberDetailDismiss","MemberDetailAttack",
			"NearbyNpcAttack","ItemDrop","RestartExpedition"]
		var accent:=DarkPixelSkinScript.BLOOD if danger else (
			DarkPixelSkinScript.BRASS if button.name in ["HeroDetailButton",
				"TurnConfirm","AutoExecute","DeployConfirm","ProductAttack",
				"ProductExecute"] else DarkPixelSkinScript.CYAN)
		DarkPixelSkinScript.apply_action_button(button,accent,danger)

func _on_surface_resized()->void:
	_layout_floating_surfaces()
	if session==null or grid==null or _resize_refresh_queued:return
	_resize_refresh_queued=true
	call_deferred("_refresh_after_surface_resize")

func _refresh_after_surface_resize()->void:
	_resize_refresh_queued=false
	if is_inside_tree() and session!=null:_refresh()

func _build_bottom_navigation()->void:
	bottom_navigation=HBoxContainer.new();bottom_navigation.name="BottomNavigation"
	bottom_navigation.custom_minimum_size.y=TOUCH_TARGET;bottom_navigation.visible=false
	bottom_navigation.add_theme_constant_override("separation",0);root_layout.add_child(bottom_navigation)
	map_nav_button=_add_nav_button("[지도]","MapNavigation",_toggle_map_overlay);map_nav_button.toggle_mode=true
	person_nav_button=_add_nav_button("[인물]","PersonNavigation",_open_hero_detail_tab.bind("STATUS"))
	skill_nav_button=_add_nav_button("[이능]","SkillNavigation",_open_hero_detail_tab.bind("SKILL"))
	equipment_nav_button=_add_nav_button("[장비]","EquipmentNavigation",_open_hero_detail_tab.bind("ITEM"))
	history_nav_button=_add_nav_button("[기록]","HistoryNavigation",_toggle_record_modal);history_nav_button.toggle_mode=true

func _add_nav_button(label:String,node_name:String,callback:Callable)->Button:
	var button:=Button.new();button.name=node_name;button.text=label
	button.custom_minimum_size=Vector2(TOUCH_TARGET,TOUCH_TARGET)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.add_theme_font_size_override("font_size",FONT_COMMAND)
	button.clip_text=true;button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	button.pressed.connect(callback);bottom_navigation.add_child(button)
	DarkPixelSkinScript.apply_action_button(button,DarkPixelSkinScript.CYAN)
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
	DarkPixelSkinScript.apply_panel(record_panel,"FOLIO")
	record_modal.add_child(record_panel)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",4);record_panel.add_child(stack)
	var header:=HBoxContainer.new();header.custom_minimum_size.y=48;stack.add_child(header)
	var title:=Label.new();title.text="주요 기록";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size",FONT_SECTION);title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;header.add_child(title)
	record_close_button=Button.new();record_close_button.name="NarrativeRecordClose";record_close_button.text="×"
	record_close_button.custom_minimum_size=Vector2(TOUCH_TARGET,TOUCH_TARGET)
	record_close_button.pressed.connect(_close_record_modal.bind("BUTTON"));header.add_child(record_close_button)
	DarkPixelSkinScript.apply_action_button(record_close_button,DarkPixelSkinScript.CYAN)
	var scroll:=ScrollContainer.new();scroll.name="NarrativeRecordScroll";scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;stack.add_child(scroll)
	record_body=Label.new();record_body.name="NarrativeRecordBody";record_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	record_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;record_body.add_theme_font_size_override("font_size",FONT_AUX)
	record_body.mouse_filter=Control.MOUSE_FILTER_IGNORE;scroll.add_child(record_body)

func _build_base_modal()->void:
	base_modal=Control.new();base_modal.name="BaseProgressModal";base_modal.visible=false
	base_modal.mouse_filter=Control.MOUSE_FILTER_STOP;base_modal.z_index=65
	base_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(base_modal)
	var scrim:=ColorRect.new();scrim.name="BaseProgressScrim";scrim.color=Color("#000306e8")
	scrim.mouse_filter=Control.MOUSE_FILTER_STOP;scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(_on_base_backdrop_input);base_modal.add_child(scrim)
	base_modal_panel=PanelContainer.new();base_modal_panel.name="BaseProgressModalPanel"
	DarkPixelSkinScript.apply_panel(base_modal_panel,"FOLIO");base_modal.add_child(base_modal_panel)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",4)
	base_modal_panel.add_child(stack)
	var header:=HBoxContainer.new();header.custom_minimum_size.y=TOUCH_TARGET;stack.add_child(header)
	var title:=Label.new();title.text="거점 현황";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size",FONT_SECTION)
	title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;header.add_child(title)
	base_close_button=Button.new();base_close_button.name="BaseProgressClose";base_close_button.text="×"
	base_close_button.custom_minimum_size=Vector2(48,48)
	base_close_button.pressed.connect(_close_base_modal.bind("BUTTON"));header.add_child(base_close_button)
	DarkPixelSkinScript.apply_action_button(base_close_button,DarkPixelSkinScript.CYAN)
	var scroll:=ScrollContainer.new();scroll.name="BaseProgressScroll"
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;stack.add_child(scroll)
	base_preview=BaseProgressPanelScript.new();base_preview.name="BaseProgressPreview"
	base_preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(base_preview)
	base_preview.building_selected.connect(_on_base_preview_building_selected)
	base_preview.return_requested.connect(_on_base_return_requested)

func _build_species_picker()->void:
	species_picker_modal=Control.new();species_picker_modal.name="SpeciesPickerModal"
	species_picker_modal.visible=false;species_picker_modal.mouse_filter=Control.MOUSE_FILTER_STOP
	species_picker_modal.z_index=80;species_picker_modal.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT);add_child(species_picker_modal)
	var scrim:=ColorRect.new();scrim.color=Color("#000306e8")
	scrim.mouse_filter=Control.MOUSE_FILTER_STOP
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);species_picker_modal.add_child(scrim)
	species_picker_panel=PanelContainer.new();species_picker_panel.name="SpeciesPickerPanel"
	DarkPixelSkinScript.apply_panel(species_picker_panel,"FOLIO")
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
		species_picker_buttons.add_child(button);DarkPixelSkinScript.apply_action_button(
			button,DarkPixelSkinScript.BRASS if species_id=="human" else DarkPixelSkinScript.CYAN)

func _open_active_combat_lab()->void:
	if get_node_or_null("ActiveCombatLab")!=null:return
	_cancel_auto_pending(true)
	_cancel_product_auto_explore("auto_explore_user_command",false)
	_cancel_route_for_user_interruption()
	var lab=preload("res://playtest/active_combat_lab.gd").new();lab.name="ActiveCombatLab"
	lab.z_index=300
	set_process(false);set_process_input(false);set_process_unhandled_key_input(false)
	lab.closed.connect(func():
		set_process(true);set_process_input(true);set_process_unhandled_key_input(true)
		_request_refresh())
	add_child(lab)

func show_species_picker_for_new_run()->void:
	if species_picker_modal==null:_build_species_picker()
	_species_picker_committed=false;species_picker_modal.visible=true
	if grid!=null:grid.modal_open=true

func _commit_species_picker(species_id:String)->void:
	if _species_picker_committed or species_picker_modal==null \
			or not species_picker_modal.visible:return
	_species_picker_committed=true
	var result:Dictionary=session.start_new_run_with_species(species_id,true,true) if session!=null else {}
	if not bool(result.get("accepted",false)):
		_species_picker_committed=false;return
	species_picker_modal.visible=false
	if grid!=null:grid.modal_open=false
	_reset_run_ui_transients()
	# A journaled campaign start leaves old saves and headless DUO fixtures intact.
	if session!=null and session.is_duo_autobattle() and session.has_method("base_return"):
		var return_result:Dictionary=session.town_life_command({"action":"START"})
		if bool(return_result.get("accepted",false)):
			town_facility_id="BASE"
			notice_text=str(return_result.message)
		else:
			notice_text="원정 입구에서 시작합니다. %s"%str(return_result.get("message",
				"거점으로 바로 이동할 수 없습니다."))
	_request_refresh()

func _build_build_label()->void:
	build_label=Label.new();build_label.name="BuildLabel";build_label.text=BuildInfoScript.display_text()
	build_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;build_label.clip_text=true
	build_label.z_index=40
	build_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	build_label.vertical_alignment=VERTICAL_ALIGNMENT_BOTTOM
	build_label.add_theme_font_size_override("font_size",FONT_MICRO)
	build_label.add_theme_color_override("font_color",AsciiFrameScript.MUTED)
	build_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	add_child(build_label);_position_build_label()

func _position_build_label()->void:
	# Build version: always the bottom-right corner of the game screen, drawn
	# above whatever sits there. Input passes through it.
	if build_label==null:return
	build_label.visible=true
	build_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	build_label.offset_left=-110.0;build_label.offset_right=-4.0
	build_label.offset_bottom=-2.0;build_label.offset_top=-18.0

func _build_tile_popover()->void:
	tile_popover=PanelContainer.new();tile_popover.name="TileRiskPopover";tile_popover.visible=false
	tile_popover.mouse_filter=Control.MOUSE_FILTER_IGNORE;tile_popover.z_index=20;add_child(tile_popover)
	tile_popover.add_theme_stylebox_override("panel",AsciiFrameScript.borderless_surface(Color("#00000000"),0))
	var popover_frame=DarkPixelFrameScript.new();popover_frame.name="TileRiskPixelFrame"
	popover_frame.configure("지형",DarkPixelSkinScript.CYAN,DarkPixelSkinScript.FOLIO,true);tile_popover.add_child(popover_frame)
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
	var panel_style:=AsciiFrameScript.borderless_surface(Color("#00000000"),0)
	member_detail_panel.add_theme_stylebox_override("panel",panel_style);member_detail_modal.add_child(member_detail_panel)
	var folio_frame=DarkPixelFrameScript.new();folio_frame.name="MemberDetailPixelFrame"
	folio_frame.configure("인물",DarkPixelSkinScript.CYAN,DarkPixelSkinScript.CANVAS,false)
	folio_frame.set_meta("major_pixel_frame",true);member_detail_panel.add_child(folio_frame)
	var stack:=VBoxContainer.new();stack.name="MemberDetailStack";stack.add_theme_constant_override("separation",4);folio_frame.add_child(stack)
	var header:=HBoxContainer.new();header.name="MemberDetailHeader";header.custom_minimum_size.y=52
	header.add_theme_constant_override("separation",6);stack.add_child(header)
	member_detail_glyph_seal=PortraitScript.new();member_detail_glyph_seal.name="MemberDetailPortrait"
	member_detail_glyph_seal.custom_minimum_size=Vector2(44,44)
	header.add_child(member_detail_glyph_seal)
	var title_stack:=VBoxContainer.new();title_stack.name="MemberDetailIdentity"
	title_stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title_stack.add_theme_constant_override("separation",0);header.add_child(title_stack)
	member_detail_title=Label.new();member_detail_title.name="MemberDetailTitle";member_detail_title.add_theme_font_size_override("font_size",FONT_KEY)
	member_detail_title.add_theme_font_override("font",DarkPixelSkinScript.PixelFont)
	member_detail_title.add_theme_color_override("font_color",DarkPixelSkinScript.BONE)
	member_detail_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;member_detail_title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;title_stack.add_child(member_detail_title)
	member_detail_subtitle=Label.new();member_detail_subtitle.name="MemberDetailSubtitle"
	member_detail_subtitle.add_theme_font_override("font",DarkPixelSkinScript.PixelFont)
	member_detail_subtitle.add_theme_font_size_override("font_size",FONT_AUX)
	member_detail_subtitle.add_theme_color_override("font_color",DarkPixelSkinScript.BONE_DIM)
	title_stack.add_child(member_detail_subtitle)
	member_detail_close=Button.new();member_detail_close.name="MemberDetailClose";member_detail_close.text="×"
	member_detail_close.custom_minimum_size=Vector2(44,TOUCH_TARGET)
	member_detail_close.add_theme_font_size_override("font_size",FONT_COMMAND)
	member_detail_close.gui_input.connect(_on_member_detail_close_input.bind(member_detail_close))
	member_detail_close.pressed.connect(_close_member_detail);header.add_child(member_detail_close)
	DarkPixelSkinScript.apply_action_button(member_detail_close,DarkPixelSkinScript.CYAN)
	member_detail_tab_row=HBoxContainer.new();member_detail_tab_row.name="MemberDetailTabs"
	member_detail_tab_row.custom_minimum_size.y=TOUCH_TARGET;member_detail_tab_row.add_theme_constant_override("separation",6)
	stack.add_child(member_detail_tab_row)
	member_detail_status_tab=Button.new();member_detail_status_tab.name="MemberStatusTab";member_detail_status_tab.text="상태"
	member_detail_status_tab.toggle_mode=true;member_detail_status_tab.custom_minimum_size=Vector2(0,TOUCH_TARGET)
	member_detail_status_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_status_tab.tooltip_text="체력, 전투 능력, 육체 상태";member_detail_status_tab.pressed.connect(_select_member_detail_tab.bind("STATUS"))
	member_detail_tab_row.add_child(member_detail_status_tab);DarkPixelSkinScript.apply_tab_button(member_detail_status_tab,true)
	member_detail_personality_tab=Button.new();member_detail_personality_tab.name="MemberPersonalityTab";member_detail_personality_tab.text="성격"
	member_detail_personality_tab.toggle_mode=true;member_detail_personality_tab.custom_minimum_size=Vector2(0,TOUCH_TARGET)
	member_detail_personality_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_personality_tab.tooltip_text="성격 유형, 판단 경향, 현재 감정";member_detail_personality_tab.pressed.connect(_select_member_detail_tab.bind("PERSONALITY"))
	member_detail_tab_row.add_child(member_detail_personality_tab);DarkPixelSkinScript.apply_tab_button(member_detail_personality_tab)
	member_detail_relationship_tab=Button.new();member_detail_relationship_tab.name="MemberRelationshipTab";member_detail_relationship_tab.text="관계"
	member_detail_relationship_tab.toggle_mode=true;member_detail_relationship_tab.custom_minimum_size=Vector2(0,TOUCH_TARGET)
	member_detail_relationship_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_relationship_tab.tooltip_text="나와 동료·NPC에 대한 관계";member_detail_relationship_tab.pressed.connect(_select_member_detail_tab.bind("RELATIONSHIP"))
	member_detail_tab_row.add_child(member_detail_relationship_tab);DarkPixelSkinScript.apply_tab_button(member_detail_relationship_tab)
	member_detail_skill_tab=Button.new();member_detail_skill_tab.name="MemberSkillTab";member_detail_skill_tab.text="이능"
	member_detail_skill_tab.toggle_mode=true;member_detail_skill_tab.custom_minimum_size=Vector2(0,TOUCH_TARGET)
	member_detail_skill_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_skill_tab.tooltip_text="무기 숙련 효과와 훈련 설정";member_detail_skill_tab.pressed.connect(_select_member_detail_tab.bind("SKILL"))
	member_detail_tab_row.add_child(member_detail_skill_tab);DarkPixelSkinScript.apply_tab_button(member_detail_skill_tab)
	member_detail_item_tab=Button.new();member_detail_item_tab.name="MemberItemTab";member_detail_item_tab.text="아이템"
	member_detail_item_tab.toggle_mode=true;member_detail_item_tab.custom_minimum_size=Vector2(0,TOUCH_TARGET)
	member_detail_item_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_item_tab.tooltip_text="장착 무기와 탄약";member_detail_item_tab.pressed.connect(_select_member_detail_tab.bind("ITEM"))
	member_detail_tab_row.add_child(member_detail_item_tab);DarkPixelSkinScript.apply_tab_button(member_detail_item_tab)
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
	# The stash must be a hidden Control: a plain Node breaks the CanvasItem
	# visibility chain, so a stashed folio stayed drawn and kept swallowing map
	# touches after the modal closed from a single-folio tab.
	member_detail_tab_stash=Control.new();member_detail_tab_stash.name="MemberDetailTabStash"
	member_detail_tab_stash.visible=false;member_detail_tab_stash.mouse_filter=Control.MOUSE_FILTER_IGNORE
	member_detail_modal.add_child(member_detail_tab_stash)
	_build_progression_window(member_detail_scroll_content)
	_build_item_window(member_detail_scroll_content)
	member_status_window=VBoxContainer.new();member_status_window.name="MemberStatusWindow"
	member_status_window.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_status_window.add_theme_constant_override("separation",8);member_detail_scroll_content.add_child(member_status_window)
	member_personality_window=PersonalityPanelScript.new();member_personality_window.name="MemberPersonalityWindow"
	member_personality_window.visible=false;member_detail_scroll_content.add_child(member_personality_window)
	member_relationship_window=RelationshipPanelScript.new();member_relationship_window.name="MemberRelationshipWindow"
	member_relationship_window.visible=false;member_detail_scroll_content.add_child(member_relationship_window)
	member_skill_window=SkillPanelScript.new();member_skill_window.name="MemberNpcSkillWindow"
	member_skill_window.visible=false;member_detail_scroll_content.add_child(member_skill_window)
	member_detail_body=Label.new();member_detail_body.name="MemberDetailBody";member_detail_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	member_detail_body.add_theme_font_size_override("font_size",FONT_AUX);member_detail_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_detail_body.mouse_filter=Control.MOUSE_FILTER_IGNORE;member_detail_scroll_content.add_child(member_detail_body)
	_build_status_equipment_window(member_detail_scroll_content)
	_build_item_popover()
	member_detail_dismiss=Button.new();member_detail_dismiss.name="MemberDetailDismiss"
	member_detail_dismiss.text="[D 추방]";member_detail_dismiss.custom_minimum_size=Vector2(120,TOUCH_TARGET)
	member_detail_dismiss.add_theme_font_size_override("font_size",FONT_BODY)
	member_detail_dismiss.pressed.connect(_on_member_detail_dismiss);member_detail_dismiss.visible=false
	stack.add_child(member_detail_dismiss);DarkPixelSkinScript.apply_action_button(
		member_detail_dismiss,DarkPixelSkinScript.BLOOD,true)
	member_detail_candidate_action=Button.new();member_detail_candidate_action.name="MemberDetailCandidateAction"
	member_detail_candidate_action.custom_minimum_size=Vector2(160,TOUCH_TARGET)
	member_detail_candidate_action.add_theme_font_size_override("font_size",FONT_BODY)
	member_detail_candidate_action.pressed.connect(_on_member_detail_candidate_action)
	member_detail_candidate_action.visible=false;stack.add_child(member_detail_candidate_action)
	DarkPixelSkinScript.apply_action_button(member_detail_candidate_action,DarkPixelSkinScript.CYAN)
	member_detail_attack=Button.new();member_detail_attack.name="MemberDetailAttack"
	member_detail_attack.text="[공격] 적대 전환";member_detail_attack.custom_minimum_size=Vector2(160,TOUCH_TARGET)
	member_detail_attack.add_theme_font_size_override("font_size",FONT_BODY)
	member_detail_attack.pressed.connect(_on_member_detail_attack)
	member_detail_attack.visible=false;stack.add_child(member_detail_attack)
	DarkPixelSkinScript.apply_action_button(member_detail_attack,DarkPixelSkinScript.BLOOD,true)
	member_order_button=Button.new();member_order_button.text="다음 행동 지시"
	member_order_button.custom_minimum_size.y=44
	member_order_button.pressed.connect(_begin_companion_order_edit)
	stack.add_child(member_order_button);DarkPixelSkinScript.apply_action_button(member_order_button)
	member_order_cancel=Button.new();member_order_cancel.text="예약 취소 · 자동전투"
	member_order_cancel.custom_minimum_size.y=44
	member_order_cancel.pressed.connect(func():
		session.cancel_companion_order(member_detail_entity_id)
		_close_member_detail();_request_refresh())
	stack.add_child(member_order_cancel);DarkPixelSkinScript.apply_action_button(member_order_cancel)

func _build_progression_window(parent:VBoxContainer)->void:
	member_ability_window=preload("res://playtest/ability_loadout_mockup.gd").new()
	member_ability_window.visible=false;parent.add_child(member_ability_window)
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
	DarkPixelSkinScript.apply_action_button(member_skill_category_button,DarkPixelSkinScript.CYAN)
	for skill_id in ["SWORD","AXE","BLUNT","SPEAR","RANGED","UNARMED"]:
		var panel:=PanelContainer.new();panel.name="SkillCard%s"%skill_id
		panel.custom_minimum_size.y=TOUCH_TARGET;panel.clip_contents=true
		panel.set_meta("fixed_single_line_ledger",true)
		DarkPixelSkinScript.apply_panel(panel,"SECTION")
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
	member_item_window.visible=false
	member_item_window.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_item_window.add_theme_constant_override("separation",8)
	parent.add_child(member_item_window)
	var weapon_panel:=PanelContainer.new();weapon_panel.name="EquippedWeaponCard"
	DarkPixelSkinScript.apply_panel(weapon_panel,"SECTION")
	member_item_window.add_child(weapon_panel)
	var weapon_stack:=VBoxContainer.new();weapon_stack.add_theme_constant_override("separation",5);weapon_panel.add_child(weapon_stack)
	member_item_weapon_text=Label.new();member_item_weapon_text.name="EquippedCombatSummary"
	member_item_weapon_text.add_theme_font_override("font",DarkPixelSkinScript.PixelFont)
	member_item_weapon_text.add_theme_font_size_override("font_size",FONT_AUX)
	member_item_weapon_text.max_lines_visible=1;member_item_weapon_text.clip_text=true
	member_item_weapon_text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	member_item_weapon_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;weapon_stack.add_child(member_item_weapon_text)
	member_item_stats={"SUMMARY":member_item_weapon_text}
	var ammo_row:=HBoxContainer.new();ammo_row.name="AmmoPoolsRow"
	ammo_row.add_theme_constant_override("separation",4);weapon_stack.add_child(ammo_row)
	member_item_ammo_text=Label.new();member_item_ammo_text.name="AmmoPoolsText"
	member_item_ammo_text.custom_minimum_size.y=TOUCH_TARGET
	member_item_ammo_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_item_ammo_text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	member_item_ammo_text.add_theme_font_size_override("font_size",FONT_AUX);ammo_row.add_child(member_item_ammo_text)
	member_item_reload_button=Button.new();member_item_reload_button.name="ReloadWeaponButton"
	member_item_reload_button.text="재장전";member_item_reload_button.custom_minimum_size.y=TOUCH_TARGET
	member_item_reload_button.custom_minimum_size.x=92
	member_item_reload_button.pressed.connect(_on_item_reload);ammo_row.add_child(member_item_reload_button)
	DarkPixelSkinScript.apply_action_button(member_item_reload_button,DarkPixelSkinScript.BRASS)
	var equipment_panel:=PanelContainer.new();equipment_panel.name="InventoryEquipmentSection"
	DarkPixelSkinScript.apply_panel(equipment_panel,"SECTION")
	member_item_window.add_child(equipment_panel)
	var equipment_stack:=VBoxContainer.new();equipment_stack.add_theme_constant_override("separation",5)
	equipment_panel.add_child(equipment_stack)
	var equipment_title:=_card_label("장착","ItemEquipmentGridHeading",FONT_SECTION)
	DarkPixelSkinScript.apply_heading(equipment_title,DarkPixelSkinScript.BRASS)
	equipment_stack.add_child(equipment_title)
	member_item_equipment_grid=GridContainer.new()
	member_item_equipment_grid.name="ItemEquipmentGrid"
	member_item_equipment_grid.columns=ITEM_GRID_COLUMNS
	member_item_equipment_grid.add_theme_constant_override("h_separation",4)
	member_item_equipment_grid.add_theme_constant_override("v_separation",4)
	member_item_equipment_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	equipment_stack.add_child(member_item_equipment_grid)
	var backpack_panel:=PanelContainer.new();backpack_panel.name="InventoryBackpackSection"
	DarkPixelSkinScript.apply_panel(backpack_panel,"SECTION")
	member_item_window.add_child(backpack_panel)
	var backpack_stack:=VBoxContainer.new();backpack_stack.add_theme_constant_override("separation",5)
	backpack_panel.add_child(backpack_stack)
	var backpack_title:=_card_label("가방 0 / 20","ItemBackpackHeading",FONT_SECTION)
	DarkPixelSkinScript.apply_heading(backpack_title,DarkPixelSkinScript.BRASS)
	backpack_stack.add_child(backpack_title)
	member_item_backpack_rows=GridContainer.new();member_item_backpack_rows.name="ItemBackpackGrid"
	member_item_backpack_rows.columns=ITEM_GRID_COLUMNS
	member_item_backpack_rows.add_theme_constant_override("h_separation",4)
	member_item_backpack_rows.add_theme_constant_override("v_separation",4)
	member_item_backpack_rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	backpack_stack.add_child(member_item_backpack_rows)
	# Detail now belongs exclusively to the floating item popover and never
	# expands or shifts the scrolling ledger.
	member_item_selected_stats=null
	member_item_empty_text=backpack_title

func _build_status_equipment_window(parent:VBoxContainer)->void:
	member_status_equipment_window=VBoxContainer.new()
	member_status_equipment_window.name="StatusEquipmentWindow"
	member_status_equipment_window.add_theme_constant_override("separation",4)
	parent.add_child(member_status_equipment_window)
	var heading:=_card_label("장비 슬롯","StatusEquipmentHeading",FONT_SECTION)
	heading.add_theme_color_override("font_color",AsciiFrameScript.CYAN)
	member_status_equipment_window.add_child(heading)
	member_item_equipment_rows=VBoxContainer.new()
	member_item_equipment_rows.name="ItemEquipmentLedger"
	member_item_equipment_rows.add_theme_constant_override("separation",2)
	member_status_equipment_window.add_child(member_item_equipment_rows)

func _build_item_popover()->void:
	member_item_popover=PanelContainer.new();member_item_popover.name="ItemDetailPopover"
	member_item_popover.visible=false;member_item_popover.mouse_filter=Control.MOUSE_FILTER_STOP
	member_item_popover.z_index=8;member_item_popover.custom_minimum_size.x=288
	DarkPixelSkinScript.apply_panel(member_item_popover,"FOLIO")
	member_detail_modal.add_child(member_item_popover)
	var popover_frame:=VBoxContainer.new();popover_frame.name="ItemDetailPixelFrame"
	popover_frame.set_meta("visual_family",DarkPixelSkinScript.VISUAL_FAMILY)
	popover_frame.set_meta("pixel_material","BLACK_IRON_POPOVER")
	member_item_popover.add_child(popover_frame)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",6)
	popover_frame.add_child(stack)
	var header:=HBoxContainer.new();header.custom_minimum_size.y=TOUCH_TARGET
	header.add_theme_constant_override("separation",4);stack.add_child(header)
	member_item_popover_title=Label.new();member_item_popover_title.name="ItemPopoverTitle"
	member_item_popover_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	member_item_popover_title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	member_item_popover_title.add_theme_font_override("font",DarkPixelSkinScript.PixelFont)
	member_item_popover_title.add_theme_font_size_override("font_size",FONT_SECTION)
	header.add_child(member_item_popover_title)
	member_item_popover_close=Button.new();member_item_popover_close.name="ItemPopoverClose"
	member_item_popover_close.text="×";member_item_popover_close.custom_minimum_size=Vector2(TOUCH_TARGET,TOUCH_TARGET)
	member_item_popover_close.pressed.connect(_hide_item_popover);header.add_child(member_item_popover_close)
	DarkPixelSkinScript.apply_action_button(member_item_popover_close,DarkPixelSkinScript.CYAN)
	member_item_popover_body=Label.new();member_item_popover_body.name="ItemPopoverDescription"
	member_item_popover_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	member_item_popover_body.add_theme_font_size_override("font_size",FONT_AUX)
	member_item_popover_body.add_theme_color_override("font_color",AsciiFrameScript.INK)
	stack.add_child(member_item_popover_body)
	member_item_popover_compare=Label.new();member_item_popover_compare.name="ItemPopoverComparison"
	member_item_popover_compare.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	member_item_popover_compare.add_theme_font_size_override("font_size",FONT_AUX)
	member_item_popover_compare.add_theme_color_override("font_color",AsciiFrameScript.CYAN)
	stack.add_child(member_item_popover_compare)
	member_item_action_row=HBoxContainer.new();member_item_action_row.name="ItemPopoverActionRow"
	member_item_action_row.add_theme_constant_override("separation",4);stack.add_child(member_item_action_row)
	member_item_equip_button=_item_action_button("장착","ItemEquip",_on_item_equip_selected)
	member_item_unequip_button=_item_action_button("해제","ItemUnequip",_on_item_unequip_selected)
	member_item_use_button=_item_action_button("사용","ItemUse",_on_item_use_selected)
	member_item_drop_button=_item_action_button("버리기","ItemDrop",_on_item_drop_selected,true)
	member_item_quick_unequip_button=member_item_unequip_button

func _item_action_button(label:String,node_name:String,callable:Callable,
		danger:bool=false)->Button:
	var button:=Button.new();button.name=node_name;button.text=label
	button.custom_minimum_size.y=TOUCH_TARGET;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.pressed.connect(callable);member_item_action_row.add_child(button)
	DarkPixelSkinScript.apply_action_button(button,DarkPixelSkinScript.BRASS,danger);return button

func _build_product_zoom_controls()->void:
	# Named compatibility nodes remain in the tree, but camera zoom is exclusively
	# a two-finger pinch and no zoom button is drawn or allowed to claim input.
	grid_zoom_controls=HBoxContainer.new();grid_zoom_controls.name="ProductZoomControls"
	grid_zoom_controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grid_zoom_controls.offset_left=-100;grid_zoom_controls.offset_right=-4
	grid_zoom_controls.offset_top=4;grid_zoom_controls.offset_bottom=48
	grid_zoom_controls.custom_minimum_size=Vector2.ZERO
	grid_zoom_controls.add_theme_constant_override("separation",0)
	grid_zoom_controls.mouse_filter=Control.MOUSE_FILTER_IGNORE
	grid_zoom_controls.z_index=80;grid_zoom_controls.visible=false
	grid.add_child(grid_zoom_controls)
	grid_zoom_out_button=Button.new();grid_zoom_out_button.name="ProductZoomOut"
	grid_zoom_out_button.text="[-]";grid_zoom_out_button.tooltip_text="시야 축소"
	grid_zoom_out_button.custom_minimum_size=Vector2.ZERO
	grid_zoom_out_button.mouse_filter=Control.MOUSE_FILTER_IGNORE
	grid_zoom_out_button.add_theme_font_size_override("font_size",FONT_CAPTION)
	grid_zoom_out_button.visible=false
	grid_zoom_controls.add_child(grid_zoom_out_button)
	AsciiFrameScript.apply_rail_button(grid_zoom_out_button,AsciiFrameScript.CYAN)
	grid_zoom_in_button=Button.new();grid_zoom_in_button.name="ProductZoomIn"
	grid_zoom_in_button.text="[+]";grid_zoom_in_button.tooltip_text="시야 확대"
	grid_zoom_in_button.custom_minimum_size=Vector2.ZERO
	grid_zoom_in_button.mouse_filter=Control.MOUSE_FILTER_IGNORE
	grid_zoom_in_button.add_theme_font_size_override("font_size",FONT_CAPTION)
	grid_zoom_in_button.visible=false
	grid_zoom_controls.add_child(grid_zoom_in_button)
	AsciiFrameScript.apply_rail_button(grid_zoom_in_button,AsciiFrameScript.CYAN)

func _build_nearby_npc_card()->void:
	nearby_npc_panel=PanelContainer.new();nearby_npc_panel.name="NearbyNpcCard"
	nearby_npc_panel.visible=false;nearby_npc_panel.mouse_filter=Control.MOUSE_FILTER_STOP
	nearby_npc_panel.z_index=25;nearby_npc_panel.custom_minimum_size=Vector2(224,0)
	nearby_npc_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	nearby_npc_panel.position=Vector2(4,4)
	nearby_npc_panel.add_theme_stylebox_override("panel",
		AsciiFrameScript.borderless_surface(Color("#00000000"),0))
	grid.add_child(nearby_npc_panel)
	var frame=DarkPixelFrameScript.new();frame.name="NearbyNpcPixelFrame"
	frame.configure("가까운 인물",DarkPixelSkinScript.CYAN,Color("#081014f2"),true)
	nearby_npc_panel.add_child(frame)
	var stack:=VBoxContainer.new();stack.name="NearbyNpcStack"
	stack.add_theme_constant_override("separation",2);frame.add_child(stack)
	var identity:=HBoxContainer.new();identity.name="NearbyNpcIdentity"
	identity.add_theme_constant_override("separation",4);stack.add_child(identity)
	nearby_npc_name=_card_label("","NearbyNpcName",NEARBY_NPC_FONT_NAME)
	nearby_npc_name.add_theme_font_override("font",DarkPixelSkinScript.PixelFont)
	nearby_npc_name.add_theme_color_override("font_color",DarkPixelSkinScript.BONE)
	nearby_npc_name.size_flags_horizontal=Control.SIZE_EXPAND_FILL;identity.add_child(nearby_npc_name)
	nearby_npc_toggle_button=Button.new();nearby_npc_toggle_button.name="NearbyNpcToggle"
	nearby_npc_toggle_button.text="[-]";nearby_npc_toggle_button.tooltip_text="가까운 인물 정보 접기"
	nearby_npc_toggle_button.custom_minimum_size=Vector2(TOUCH_TARGET,TOUCH_TARGET)
	nearby_npc_toggle_button.focus_mode=Control.FOCUS_NONE
	nearby_npc_toggle_button.gui_input.connect(
		_on_nearby_npc_button_gui_input.bind(nearby_npc_toggle_button.name))
	identity.add_child(nearby_npc_toggle_button)
	DarkPixelSkinScript.apply_action_button(nearby_npc_toggle_button,DarkPixelSkinScript.CYAN)
	nearby_npc_content=VBoxContainer.new();nearby_npc_content.name="NearbyNpcContent"
	nearby_npc_content.add_theme_constant_override("separation",2);stack.add_child(nearby_npc_content)
	nearby_npc_condition=_card_label("","NearbyNpcCondition",NEARBY_NPC_FONT_CAPTION)
	nearby_npc_condition.add_theme_font_size_override("font_size",NEARBY_NPC_FONT_CAPTION)
	nearby_npc_condition.add_theme_color_override("font_color",AsciiFrameScript.MUTED)
	nearby_npc_content.add_child(nearby_npc_condition)
	nearby_npc_personality=_card_label("","NearbyNpcPersonality",NEARBY_NPC_FONT_TEXT)
	nearby_npc_personality.add_theme_font_size_override("font_size",NEARBY_NPC_FONT_TEXT)
	nearby_npc_personality.clip_text=true
	nearby_npc_personality.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	nearby_npc_content.add_child(nearby_npc_personality)
	nearby_npc_affinity=_card_label("","NearbyNpcAffinity",NEARBY_NPC_FONT_TEXT)
	nearby_npc_affinity.add_theme_font_size_override("font_size",NEARBY_NPC_FONT_TEXT)
	nearby_npc_content.add_child(nearby_npc_affinity)
	nearby_npc_equipment=_card_label("","NearbyNpcEquipment",NEARBY_NPC_FONT_TEXT)
	nearby_npc_equipment.add_theme_font_size_override("font_size",NEARBY_NPC_FONT_TEXT)
	nearby_npc_equipment.clip_text=true
	nearby_npc_equipment.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	nearby_npc_content.add_child(nearby_npc_equipment)
	nearby_npc_recruitment=_card_label("","NearbyNpcRecruitment",NEARBY_NPC_FONT_CAPTION)
	nearby_npc_recruitment.add_theme_font_size_override("font_size",NEARBY_NPC_FONT_CAPTION)
	nearby_npc_recruitment.clip_text=true
	nearby_npc_recruitment.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	nearby_npc_content.add_child(nearby_npc_recruitment)
	var actions:=HBoxContainer.new();actions.name="NearbyNpcActions"
	actions.add_theme_constant_override("separation",4);nearby_npc_content.add_child(actions)
	nearby_npc_detail_button=Button.new();nearby_npc_detail_button.name="NearbyNpcDetail"
	nearby_npc_detail_button.text="[상세]";nearby_npc_detail_button.custom_minimum_size.y=TOUCH_TARGET
	nearby_npc_detail_button.add_theme_font_size_override("font_size",NEARBY_NPC_FONT_BUTTON)
	nearby_npc_detail_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	nearby_npc_detail_button.gui_input.connect(
		_on_nearby_npc_button_gui_input.bind(nearby_npc_detail_button.name));actions.add_child(nearby_npc_detail_button)
	DarkPixelSkinScript.apply_action_button(nearby_npc_detail_button,DarkPixelSkinScript.CYAN)
	nearby_npc_action_button=Button.new();nearby_npc_action_button.name="NearbyNpcRecruit"
	nearby_npc_action_button.custom_minimum_size.y=TOUCH_TARGET
	nearby_npc_action_button.add_theme_font_size_override("font_size",NEARBY_NPC_FONT_BUTTON)
	nearby_npc_action_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	nearby_npc_action_button.gui_input.connect(
		_on_nearby_npc_button_gui_input.bind(nearby_npc_action_button.name));actions.add_child(nearby_npc_action_button)
	DarkPixelSkinScript.apply_action_button(nearby_npc_action_button,DarkPixelSkinScript.CYAN)
	nearby_npc_attack_button=Button.new();nearby_npc_attack_button.name="NearbyNpcAttack"
	nearby_npc_attack_button.text="[공격]";nearby_npc_attack_button.custom_minimum_size.y=TOUCH_TARGET
	nearby_npc_attack_button.add_theme_font_size_override("font_size",NEARBY_NPC_FONT_BUTTON)
	nearby_npc_attack_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	nearby_npc_attack_button.gui_input.connect(
		_on_nearby_npc_button_gui_input.bind(nearby_npc_attack_button.name));actions.add_child(nearby_npc_attack_button)
	DarkPixelSkinScript.apply_action_button(nearby_npc_attack_button,DarkPixelSkinScript.BLOOD,true)

func _update_nearby_npc_card(observation:Dictionary,status:Dictionary,
		product_hud:bool)->void:
	nearby_npc_entity_id=-1;nearby_npc_story_state=""
	if nearby_npc_panel==null:return
	nearby_npc_panel.visible=false
	if not product_hud or str(status.get("view_mode",""))!="EXPLORATION":return
	var hero_raw:Variant=status.get("protagonist_position",[])
	if not hero_raw is Array or hero_raw.size()!=2:return
	var hero_position:=Vector2i(int(hero_raw[0]),int(hero_raw[1]))
	var best_actor:Dictionary={};var best_distance:=999999
	for cell_value in observation.get("cells",[]):
		if not cell_value is Dictionary:continue
		var cell:Dictionary=cell_value
		if str(cell.get("visibility_state",""))!="VISIBLE":continue
		for actor_value in cell.get("actors",[]):
			if not actor_value is Dictionary:continue
			var actor:Dictionary=actor_value
			var entity_id:=int(actor.get("entity_id",-1))
			var display_role:=str(actor.get("display_role",""))
			var recruitable:bool=display_role in ["RESCUE_NPC","OPENING_NPC"]
			if not recruitable or str(actor.get("life_state","ACTIVE"))=="DEAD":continue
			var position_raw:Variant=actor.get("display_position",cell.get("position",[]))
			if not position_raw is Array or position_raw.size()!=2:continue
			var position:=Vector2i(int(position_raw[0]),int(position_raw[1]))
			var distance:=maxi(absi(position.x-hero_position.x),absi(position.y-hero_position.y))
			if distance<=6 and distance<best_distance:
				best_actor=actor;best_distance=distance
	if best_actor.is_empty():return
	var detail:Dictionary=session.inspect_party_member(int(best_actor.entity_id))
	if not bool(detail.get("accepted",false)):return
	nearby_npc_entity_id=int(best_actor.entity_id)
	if nearby_npc_last_entity_id!=nearby_npc_entity_id:
		nearby_npc_collapsed=false
		nearby_npc_last_entity_id=nearby_npc_entity_id
	nearby_npc_story_state=str(detail.get("rescue_story_state",""))
	nearby_npc_name.text="%s  %d/%d"%[str(detail.get("display_name","NPC")),
		int(detail.get("health",0)),int(detail.get("max_health",0))]
	nearby_npc_condition.text="%s · 거리 %d칸"%[
		"재회" if bool(detail.get("opening_reencounter",false)) else \
		("부상" if nearby_npc_story_state in ["COLLAPSED_STORY","OPENING_CHOICE"] \
		else "대화 가능"),best_distance]
	var personality:Dictionary=detail.get("personality_style",{}) \
		if detail.get("personality_style",{}) is Dictionary else {}
	nearby_npc_personality.text="성격 · %s"%str(personality.get("label","알 수 없음"))
	var affinity:Dictionary=detail.get("affinity_toward_protagonist",{}) \
		if detail.get("affinity_toward_protagonist",{}) is Dictionary else {}
	var affinity_score:=int(affinity.get("score",50))
	nearby_npc_affinity.text="관계 · 나에게 %s %d"%[
		str(affinity.get("label","보통")),affinity_score]
	nearby_npc_affinity.add_theme_color_override("font_color",
		AsciiFrameScript.JADE if affinity_score>=60 else (
			AsciiFrameScript.DANGER if affinity_score<25 else AsciiFrameScript.INK))
	var equipment:Dictionary=detail.get("equipment_summary",{}) \
		if detail.get("equipment_summary",{}) is Dictionary else {}
	nearby_npc_equipment.text="장비 · %s / %s"%[
		str(equipment.get("weapon_label","없음")),
		str(equipment.get("armor_label","방어구 없음"))]
	nearby_npc_detail_button.disabled=false
	nearby_npc_action_button.visible=true
	var attack:Dictionary=detail.get("attack_assessment",{}) \
		if detail.get("attack_assessment",{}) is Dictionary else {}
	nearby_npc_attack_button.disabled=not bool(attack.get("accepted",false))
	nearby_npc_attack_button.tooltip_text=str(attack.get("message","인접한 인물을 공격합니다."))
	if nearby_npc_story_state=="OPENING_CHOICE":
		nearby_npc_recruitment.text="하단의 [물약 주기] 또는 [돕지 않기]로 결정합니다."
		nearby_npc_action_button.text="[선택은 하단]"
		nearby_npc_action_button.disabled=true
		nearby_npc_action_button.tooltip_text="첫 조우 선택은 하단 행동 버튼에서 진행합니다."
	elif nearby_npc_story_state=="OPENING_DEPARTING":
		nearby_npc_recruitment.text="여행자가 먼저 던전 안쪽으로 이동합니다."
		nearby_npc_action_button.text="[이동 중]"
		nearby_npc_action_button.disabled=true
		nearby_npc_action_button.tooltip_text="던전 안쪽에서 다시 만날 수 있습니다."
	elif nearby_npc_story_state=="COLLAPSED_STORY":
		var rescue:Dictionary=detail.get("rescue_assessment",{}) \
			if detail.get("rescue_assessment",{}) is Dictionary else {}
		nearby_npc_recruitment.text="상처를 안정화해야 대화할 수 있습니다."
		nearby_npc_action_button.text="[안정화]"
		nearby_npc_action_button.disabled=not bool(rescue.get("accepted",false))
		nearby_npc_action_button.tooltip_text=str(rescue.get("message",""))
	elif not session.allows_companions():
		nearby_npc_recruitment.text=""
		nearby_npc_action_button.visible=false
	else:
		var recruitment:Dictionary=detail.get("recruitment_assessment",{}) \
			if detail.get("recruitment_assessment",{}) is Dictionary else {}
		var probability:=int(recruitment.get("probability_percent",0))
		var volunteers:=affinity_score>=75 and bool(recruitment.get("accepted",false)) \
			and bool(recruitment.get("would_accept",false))
		nearby_npc_recruitment.text=("먼저 제안 · 함께 가고 싶다고 합니다. %d%%"%probability) \
			if volunteers else "합류 의사 · %d%%"%probability
		if bool(recruitment.get("resolved",false)):
			nearby_npc_action_button.text="[대답 완료]"
			nearby_npc_action_button.disabled=true
		elif not bool(recruitment.get("accepted",false)):
			nearby_npc_action_button.text={"recruitment_candidate_too_far":"[더 가까이]",
				"party_full":"[파티 가득]"}.get(str(recruitment.get("reason","")),"[영입 불가]")
			nearby_npc_action_button.disabled=true
		else:
			nearby_npc_action_button.text="[동행 수락]" if volunteers else "[영입 권유]"
			nearby_npc_action_button.disabled=false
		nearby_npc_action_button.tooltip_text=_recruitment_reason_summary(recruitment)
	nearby_npc_content.visible=not nearby_npc_collapsed
	nearby_npc_toggle_button.text="[+]" if nearby_npc_collapsed else "[-]"
	nearby_npc_toggle_button.tooltip_text="가까운 인물 정보 펼치기" \
		if nearby_npc_collapsed else "가까운 인물 정보 접기"
	nearby_npc_panel.visible=true
	nearby_npc_panel.call_deferred("reset_size")

func _on_nearby_npc_toggle()->void:
	nearby_npc_collapsed=not nearby_npc_collapsed
	nearby_npc_content.visible=not nearby_npc_collapsed
	nearby_npc_toggle_button.text="[+]" if nearby_npc_collapsed else "[-]"
	nearby_npc_toggle_button.tooltip_text="가까운 인물 정보 펼치기" \
		if nearby_npc_collapsed else "가까운 인물 정보 접기"
	nearby_npc_panel.reset_size()

func _on_nearby_npc_detail()->void:
	if nearby_npc_entity_id>0:_open_member_detail(nearby_npc_entity_id)

func _on_nearby_npc_action()->void:
	if nearby_npc_entity_id<=0:return
	if nearby_npc_story_state=="COLLAPSED_STORY":
		_on_stabilize_candidate(nearby_npc_entity_id)
	else:_on_recruit_companion(nearby_npc_entity_id)

func _on_nearby_npc_attack()->void:
	if nearby_npc_entity_id>0:_attack_neutral_npc(nearby_npc_entity_id)

func _layout_floating_surfaces()->void:
	_position_build_label()
	if member_detail_panel!=null:
		var panel_width:=minf(size.x-24.0,420.0 if size.x>=450.0 else 336.0)
		var panel_height:=minf(size.y-24.0,720.0)
		member_detail_panel.position=(size-Vector2(panel_width,panel_height))*0.5
		member_detail_panel.size=Vector2(panel_width,panel_height)
		member_detail_body.custom_minimum_size.x=maxf(1.0,panel_width-48.0)
	if member_item_popover!=null and member_item_popover.visible:
		_position_item_popover(member_item_popover_anchor)
	if record_panel!=null:
		var record_width:=minf(size.x-24.0,420.0)
		var record_height:=minf(size.y-24.0,620.0)
		record_panel.position=(size-Vector2(record_width,record_height))*0.5
		record_panel.size=Vector2(record_width,record_height)
	if base_modal_panel!=null:
		var base_width:=minf(size.x-24.0,390.0)
		var base_height:=minf(size.y-24.0,720.0)
		base_modal_panel.position=(size-Vector2(base_width,base_height))*0.5
		base_modal_panel.size=Vector2(base_width,base_height)
	if species_picker_panel!=null:
		var picker_width:=minf(size.x-24.0,360.0)
		var picker_height:=minf(size.y-24.0,420.0)
		species_picker_panel.position=(size-Vector2(picker_width,picker_height))*0.5
		species_picker_panel.size=Vector2(picker_width,picker_height)
	if tile_popover!=null and tile_popover.visible:_position_tile_popover()

func _refresh()->void:
	_refresh_pending=false
	if session==null:return
	if get_node_or_null("ActiveCombatLab")!=null:return
	# Presentation refreshes queued by the last AUTO hop must not erase a new
	# finger-down before finger-up. Modal entry still cancels explicitly.
	if grid!=null and bool(grid.pointer_gesture_state().get("active",false)):
		_refresh_after_pointer=true
		return
	grid.cancel_pointer_gesture()
	var status:Dictionary=session.party_status()
	if not bool(status.get("ok",false)):return
	var torch_status:Variant=status.get("torch",{})
	if torch_status is Dictionary \
			and bool(torch_status.get("depleted",false)) \
			and str(torch_status.get("source_event_type",""))=="torch.ignited" \
			and int(torch_status.get("last_event_id",-1))!=_last_torch_depletion_alert_event_id:
		_last_torch_depletion_alert_event_id=int(torch_status.get("last_event_id",-1))
		notice_text="횃불 연료가 모두 소진되었습니다."
		action_feedback_text=notice_text
	_validate_battle_targeting(status)
	if auto_orchestration_enabled:
		_orchestrate_auto_phase(status)
		status=session.party_status()
		if str(status.get("safe_phase",""))!=auto_phase:
			_orchestrate_auto_phase(status)
			status=session.party_status()
	battle_command_flow.sync(self)
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
	var town_active:=str(status.view_mode)=="TOWN"
	guild_tutorial_hud.present(session.guild_tutorial_progress(),int(session.sim.world.get_instance_id()),
		str(session.sim.world.party_encounter.expedition_cycle.phase)=="DUNGEON" and not bool(status.terminal))
	var base_overview_state:Dictionary=session.base_overview() \
		if session.has_method("base_overview") else {}
	var base_available:=bool(base_overview_state.get("enabled",false))
	if town_active and _last_view_mode!="TOWN" and base_available:town_facility_id="BASE"
	_last_view_mode=str(status.view_mode)
	var town_base_active:bool=town_active and base_available \
		and (session.town_life_enabled() or town_facility_id in ["","BASE"])
	var combat_active:=str(status.view_mode)=="COMBAT"
	var combat_actions_visible:=safe_phase=="ENGAGED" and not bool(status.terminal) \
		or run_terminal or _run_locked_exit_feedback
	if town_active:combat_actions_visible=false
	var party_rows:Array=session.party_cards()
	# Town is a preparation screen in every scenario. Reusing the solo dungeon
	# shell here left movement/attack furniture around after an automatic return.
	var product_hud:=_is_solo_product_session() and not town_active
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
	# The product rail is the Pixel Dungeon style top HUD: minimap, current floor
	# with the return countdown, and the main menu. Legacy keeps the phase banner.
	phase_panel.visible=true
	minimap_frame.visible=product_hud;minimap.visible=product_hud;recent_event_label.visible=false
	top_hud_actions.visible=product_hud or town_base_active
	top_hud_actions.custom_minimum_size.x=44 if product_hud else (100 if town_active and session.town_life_enabled() else 132)
	record_button.visible=not product_hud and not (town_active and session.town_life_enabled())
	hero_detail_button.visible=not product_hud
	enemy_vision_overlay_button.visible=product_hud
	enemy_vision_overlay_button.set_pressed_no_signal(enemy_vision_overlay_enabled)
	enemy_vision_overlay_button.text="V✓" if enemy_vision_overlay_enabled else "V"
	var town_header_target:=48 if town_base_active else 44
	record_button.custom_minimum_size=Vector2(town_header_target,town_header_target)
	hero_detail_button.custom_minimum_size=Vector2(town_header_target,town_header_target)
	product_menu_button.visible=product_hud or (town_active and session.town_life_enabled())
	product_menu_button.custom_minimum_size=Vector2(town_header_target,town_header_target)
	var base_menu_index:=product_menu_button.get_popup().get_item_index(7)
	if base_menu_index>=0:
		var base_menu_enabled:bool=base_available
		product_menu_button.get_popup().set_item_disabled(base_menu_index,not base_menu_enabled)
	# SOLO keeps one continuous dungeon surface: the situation word stays a hidden
	# authority for tests/legacy while the rail centre names the floor and return.
	phase_label.visible=not product_hud
	event_surface.visible=product_hud or town_active and session.town_life_enabled()
	# Keep the requested status/build/equipment/history access at the foot. The
	# miniature map already opens from the top HUD, so its duplicate footer button
	# remains hidden and the four useful destinations each receive a wider target.
	bottom_navigation.visible=false
	map_nav_button.visible=false
	person_nav_button.visible=true;skill_nav_button.visible=true
	equipment_nav_button.visible=true;history_nav_button.visible=true
	hud_bottom_flex.visible=false
	info_scroll.visible=not product_hud
	grid.visible=not town_active
	_apply_product_root_order(product_hud)
	var card_layout:=party_card_layout_spec(party_rows.size(),size.x)
	_apply_screen_budget(combat_active,combat_actions_visible,run_available,run_terminal,
		int(card_layout.get("party_height",160)),product_hud)
	cards.visible=not town_base_active
	if selected_member_id not in status.party_member_ids or session.sim.world.combatant_states[selected_member_id].life_state=="DEAD":
		selected_member_id=int(status.protagonist_id)
	if session.is_duo_autobattle() and combat_active:
		var selected_alive:=false
		for row_value in party_rows:
			if row_value is Dictionary and int(row_value.get("entity_id",-1))==selected_member_id:
				selected_alive=bool(row_value.get("alive",true));break
		if not selected_alive:
			for row_value in party_rows:
				if row_value is Dictionary and bool(row_value.get("alive",true)):
					selected_member_id=int(row_value.get("entity_id",-1));break
	if selected_target_id not in status.visible_enemy_ids:selected_target_id=-1
	if not pending_move_mode.is_empty() and pending_move_mode!=str(status.view_mode):_clear_move_preview()
	_apply_phase_banner(status,presentation)
	var deployment:Dictionary=session.deployment_draft()
	var ghosts:Array=deployment.placements if str(status.view_mode)=="ENCOUNTER_PREVIEW" \
		and not _is_solo_product_session() else []
	_sync_product_zoom_controls(product_hud)
	var view_dimensions:=_current_grid_view_dimensions()
	var view_cell_count:=view_dimensions.x
	var ui_observation:Dictionary=session.observe_party_ui(view_dimensions.x,true,
		view_dimensions.y,true)
	var observation:Dictionary=ui_observation.get("grid",{})
	_decorate_visible_resource_caches(observation)
	var direct_solo_combat:=_is_direct_solo_combat(status)
	# A one-member product turn commits on the touched actor/cell. There is no
	# pending plan to annotate; keeping old intent/cursor marks here made the
	# already-authoritative result look as though it still awaited confirmation.
	var intent_overlays:Array=session.turn_intent_overlays() \
		if not run_complete and (session.field_turns_active() or combat_active and not direct_solo_combat) else []
	grid.set_observation(observation,ghosts)
	var enemy_vision:Dictionary=session.enemy_vision_overlay() \
		if enemy_vision_overlay_enabled else {"rows":[]}
	grid.set_enemy_vision_overlay(enemy_vision.get("rows",[]))
	minimap.set_observation(ui_observation.get("minimap",{}))
	_update_expedition_hud(product_hud,status)
	_update_nearby_npc_card(observation,status,product_hud)
	if product_hud:
		var hero_position:=Vector2i(int(status.protagonist_position[0]),
			int(status.protagonist_position[1]))
		grid.set_hero_centered_view(hero_position,view_cell_count,
			int(status.protagonist_id),MANUAL_CAMERA_SETTLE_MSEC,view_dimensions.y)
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
	_render_hero_skill_row(status,product_hud and not town_active)
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
			"TOWN":_town_deck(status)
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
	log_label.visible=not product_hud and _narrative_log_visible and not (town_active and session.town_life_enabled())
	log_label.max_lines_visible=3
	deck.visible=not product_hud and (not _narrative_log_visible or (town_active and session.town_life_enabled()))
	if event_surface.visible:
		event_label.text=_compact_meaningful_event_text(combat_history,status)
		if event_label.text.is_empty() and str(status.view_mode)=="TOWN":event_label.text=_town_summary_text(status)
		if not _product_transient_event_feedback.is_empty():
			event_label.text=_product_transient_event_feedback
			_product_transient_event_feedback=""
		if not _product_auto_stop_feedback.is_empty():
			event_label.text=_product_auto_stop_feedback
			_product_auto_stop_feedback=""
		if _run_locked_exit_feedback and not action_feedback_text.is_empty():
			event_label.text=action_feedback_text
		if record_modal.visible:
			record_body.text=_full_meaningful_record_text(session.combat_log(64,500))
	record_button.button_pressed=_narrative_log_visible
	DarkPixelSkinScript.apply_tab_button(record_button,_narrative_log_visible)
	_update_recent_event(combat_history,status)
	if _scroll_log_after_refresh:
		_scroll_log_after_refresh=false;call_deferred("_scroll_information_to_latest_log")
	_flush_pending_visual_effects()

func _decorate_visible_resource_caches(observation:Dictionary)->void:
	# The session exposes cache authority only on observed cells. Reuse the
	# established material glyph path so caches are visible without leaking an
	# undiscovered coordinate or copying cache state into UI-owned authority.
	var cells:Variant=observation.get("cells",[])
	if not cells is Array:return
	for value in cells:
		if not value is Dictionary:continue
		var row:Dictionary=value
		var cache:Variant=row.get("resource_cache",{})
		if not cache is Dictionary or not bool(cache.get("available",false)):continue
		var visibility:=str(row.get("visibility_state",row.get("visibility",""))).to_upper()
		if visibility!="VISIBLE":continue
		row["ground_item_glyph"]="*"

func _apply_product_root_order(product_hud:bool)->void:
	if product_hud:
		root_layout.move_child(phase_panel,0)
		root_layout.move_child(grid,1);root_layout.move_child(event_surface,2)
		root_layout.move_child(hero_skill_row,3);root_layout.move_child(cards,4)
		# The context dock is the only persistent footer. Hidden compatibility
		# controls remain in the tree but consume no product-screen height.
		root_layout.move_child(combat_action_area,root_layout.get_child_count()-1)
	else:
		hud_bottom_flex.visible=false
		root_layout.move_child(phase_panel,0);root_layout.move_child(grid,1)
		root_layout.move_child(cards,2);root_layout.move_child(info_scroll,3)
		root_layout.move_child(combat_action_area,4)
	# Keep the legacy footer last in both product and formation/debug layouts.
	# The hidden timeline must not become the trailing sibling in either mode.
	root_layout.move_child(bottom_navigation,root_layout.get_child_count()-1)

func _refresh_individual_battle_surface()->void:
	# Keep buttons and portraits alive across actions: rebuilding the full shell
	# interrupted gestures, layout and animation after every old party batch.
	var status:Dictionary=session.party_status()
	var dimensions:=_current_grid_view_dimensions()
	var _bo:=PerfProbeScript.begin()
	var observation:Dictionary=session.observe_party_ui(dimensions.x,true,dimensions.y,true)
	PerfProbeScript.end("bs.observe",_bo)
	var _bg:=PerfProbeScript.begin()
	grid.set_observation(observation.get("grid",{}),[])
	PerfProbeScript.end("bs.grid_set",_bg)
	var _bm:=PerfProbeScript.begin()
	minimap.set_observation(observation.get("minimap",{}))
	PerfProbeScript.end("bs.minimap",_bm)
	var position:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
	var _bc:=PerfProbeScript.begin()
	grid.set_hero_centered_view(position,dimensions.x,int(status.protagonist_id),
		MANUAL_CAMERA_SETTLE_MSEC,dimensions.y)
	grid.set_intent_overlays([])
	_update_expedition_hud(true,status)
	PerfProbeScript.end("bs.camera_hud",_bc)
	var _bp:=PerfProbeScript.begin()
	var battle_rows:Array=session.party_cards()
	PerfProbeScript.end("bs.party_cards",_bp)
	var _bu:=PerfProbeScript.begin()
	_update_stable_party_cards(battle_rows)
	PerfProbeScript.end("bs.cards_update",_bu)
	var _bk:=PerfProbeScript.begin()
	_update_hero_skill_row(status)
	PerfProbeScript.end("bs.skill_rows",_bk)
	var _bl:=PerfProbeScript.begin()
	var history:Dictionary=session.combat_log(8,80)
	_update_recent_event(history,status)
	event_label.text=_compact_meaningful_event_text(history,status)
	if not _product_transient_event_feedback.is_empty():
		event_label.text=_product_transient_event_feedback;_product_transient_event_feedback=""
	PerfProbeScript.end("bs.log",_bl)
	var _bf:=PerfProbeScript.begin()
	_flush_pending_visual_effects()
	PerfProbeScript.end("bs.effects",_bf)

func _refresh_direct_solo_combat_surface(status:Dictionary)->void:
	# The stable one-member combat shell does not need to destroy and recreate
	# every card, button and dossier after each turn. Refresh the authoritative
	# world projection and mutate the few live HUD values whose data can change.
	var profile_started:=Time.get_ticks_usec()
	grid.cancel_pointer_gesture()
	var presentation:Dictionary=session.presentation_state()
	var party_rows:Array=session.party_cards()
	var observe_started:=Time.get_ticks_usec()
	var view_dimensions:=_current_grid_view_dimensions()
	var view_cell_count:=view_dimensions.x
	var ui_observation:Dictionary=session.observe_party_ui(view_dimensions.x,false,
		view_dimensions.y)
	var observe_finished:=Time.get_ticks_usec()
	grid.set_observation(ui_observation.get("grid",{}),[])
	_update_nearby_npc_card(ui_observation.get("grid",{}),status,true)
	var hero_position:=Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	grid.set_hero_centered_view(hero_position,view_cell_count,int(status.protagonist_id),
		MANUAL_CAMERA_SETTLE_MSEC,view_dimensions.y)
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
	var view_dimensions:=_current_grid_view_dimensions()
	var view_cell_count:=view_dimensions.x
	var product_hud:=_is_solo_product_session()
	var _po:=PerfProbeScript.begin()
	var ui_observation:Dictionary=session.observe_party_ui(view_dimensions.x,true,
		view_dimensions.y,true) if product_hud else session.observe_party_ui(view_cell_count)
	PerfProbeScript.end("ui.observe",_po)
	var observe_finished_usec:=Time.get_ticks_usec()
	var _pg:=PerfProbeScript.begin()
	grid.set_observation(ui_observation.get("grid",{}),[])
	PerfProbeScript.end("ui.grid_set",_pg)
	var _pmm:=PerfProbeScript.begin()
	minimap.set_observation(ui_observation.get("minimap",{}))
	PerfProbeScript.end("ui.minimap",_pmm)
	var _ph:=PerfProbeScript.begin()
	_update_expedition_hud(product_hud,status)
	_update_nearby_npc_card(ui_observation.get("grid",{}),status,
		product_hud)
	PerfProbeScript.end("ui.hud_npc",_ph)
	var hero_position:=Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	var _pcam:=PerfProbeScript.begin()
	if product_hud:
		grid.set_hero_centered_view(hero_position,view_cell_count,int(status.protagonist_id),
			CONTINUOUS_CAMERA_SETTLE_MSEC if continuous_motion \
			else MANUAL_CAMERA_SETTLE_MSEC,view_dimensions.y)
	else:grid.set_view_window(15)
	grid.set_selection(selected_member_id,-1);grid.set_intent_overlays([])
	grid.set_speech_bubbles(session.world_speech_bubbles() \
		if session.has_method("world_speech_bubbles") else [])
	PerfProbeScript.end("ui.camera_speech",_pcam)
	var _prt:=PerfProbeScript.begin()
	var route_state:Dictionary=session.exploration_route_state()
	if bool(route_state.get("has_preview",false)) \
			and not bool(route_state.get("completed",false)) \
			and not bool(route_state.get("terminal",false)):
		route_preview=route_state.duplicate(true);_apply_route_state(route_state)
		_apply_companion_follow_plan(route_state)
	else:
		route_preview.clear();grid.clear_route_overlay();grid.clear_cursor_preview()
		_clear_companion_follow_plan()
	PerfProbeScript.end("ui.route",_prt)
	var grid_finished_usec:=Time.get_ticks_usec()
	var _ppc:=PerfProbeScript.begin()
	var party_rows:Array=session.party_cards()
	PerfProbeScript.end("ui.party_cards",_ppc)
	var _pcu:=PerfProbeScript.begin()
	_update_stable_party_cards(party_rows)
	PerfProbeScript.end("ui.cards_update",_pcu)
	var _plg:=PerfProbeScript.begin()
	var combat_history:Dictionary=session.combat_log(8,80)
	log_label.text=_combat_log_text(combat_history)
	_update_recent_event(combat_history,status)
	PerfProbeScript.end("ui.log",_plg)
	if product_hud:
		event_label.text=_compact_meaningful_event_text(combat_history,status)
		if not _product_transient_event_feedback.is_empty():
			event_label.text=_product_transient_event_feedback
			_product_transient_event_feedback=""
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
	if session.field_turns_active():
		_update_hero_skill_row(session.party_status())
		grid.set_intent_overlays(session.turn_intent_overlays())

func _update_stable_party_card(row:Dictionary)->void:
	var card:=cards.find_child("MemberCard%d"%int(row.get("entity_id",-1)),true,false)
	if card==null:return
	if card.get_script()==CompactPortraitScript:
		card.actor=row.duplicate(true)
		if _portrait_battle_controls_visible() or session.field_turns_active():
			card.actor["energy"]=session.sim.world.party_encounter.member(int(row.entity_id)).energy
		card.selected=int(row.get("entity_id",-1))==selected_member_id
		card.order_reserved=session.has_companion_order(int(row.get("entity_id",-1))) \
			or not session.individual_battle.queued(int(row.entity_id)).is_empty()
		card.queue_redraw()
		return
	var health:=card.find_child("MemberState",true,false)
	if health!=null and health.has_method("configure"):
		var current:=int(row.get("health",0));var maximum:=maxi(1,int(row.get("max_health",1)))
		health.call("configure_semantic","HP",current,maximum,10,
			AsciiFrameScript.RED if current*4<=maximum else AsciiFrameScript.GREEN)
	var stress:=card.find_child("StressState",true,false) as Label
	if stress!=null:_apply_stress_band_label(stress,row)
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
	var observation:Dictionary=session.observe_minimap()
	map_overlay.set_observation(observation)
	grid.cancel_pointer_gesture();grid.modal_open=true
	if map_nav_button!=null:map_nav_button.set_pressed_no_signal(true)
	map_overlay.open()
	_sync_product_zoom_controls(_is_solo_product_session())

func _on_map_overlay_closed(_reason:String)->void:
	if map_nav_button!=null:map_nav_button.set_pressed_no_signal(false)
	grid.modal_open=member_detail_modal.visible or record_modal.visible or base_modal.visible
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
	if base_modal.visible:_close_base_modal("HISTORY")
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
	grid.modal_open=member_detail_modal.visible or map_overlay.visible or base_modal.visible
	_sync_product_zoom_controls(_is_solo_product_session())
	route_paused_by_modal=false
	if auto_orchestration_enabled:_request_refresh()

func _on_record_backdrop_input(event:InputEvent)->void:
	if event is InputEventScreenTouch and event.pressed:_close_record_modal("OUTSIDE")
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index==MOUSE_BUTTON_LEFT:_close_record_modal("OUTSIDE")

func _open_base_modal()->void:
	if session==null or not session.has_method("base_overview"):return
	var overview:Dictionary=session.base_overview()
	if not bool(overview.get("enabled",false)):return
	_product_attack_targeting=false
	_cancel_product_auto_explore("auto_explore_modal",false)
	_cancel_route_for_user_interruption()
	if map_overlay.visible:map_overlay.close("BASE")
	if record_modal.visible:_close_record_modal("BASE")
	base_preview.present(overview,true,selected_base_building_id)
	grid.cancel_pointer_gesture();grid.modal_open=true;base_modal.visible=true
	_sync_product_zoom_controls(_is_solo_product_session())
	_layout_floating_surfaces()
	if base_close_button.is_inside_tree():base_close_button.grab_focus()

func _close_base_modal(_reason:String="API")->void:
	if base_modal==null or not base_modal.visible:return
	base_modal.visible=false
	grid.modal_open=member_detail_modal.visible or record_modal.visible or map_overlay.visible
	_sync_product_zoom_controls(_is_solo_product_session())
	route_paused_by_modal=false
	if auto_orchestration_enabled:_request_refresh()

func _on_base_preview_building_selected(building_id:String)->void:
	selected_base_building_id=building_id

func _on_base_backdrop_input(event:InputEvent)->void:
	if event is InputEventScreenTouch and event.pressed:_close_base_modal("OUTSIDE")
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index==MOUSE_BUTTON_LEFT:_close_base_modal("OUTSIDE")

func _on_base_return_requested()->void:
	if not session.has_method("base_return"):
		_show_product_command_feedback("이 위치에서는 귀환할 수 없습니다.");return
	var result:Dictionary=session.base_return()
	_show_product_command_feedback(str(result.get("message","안전하게 귀환했습니다." if bool(
		result.get("accepted",false)) else "이 위치에서는 귀환할 수 없습니다.")))
	if bool(result.get("accepted",false)):_close_base_modal("RETURN")
	_request_refresh()

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
	_shown_loot_battle_id=-1
	if battle_loot_panel!=null:battle_loot_panel.hide()
	if battle_drag!=null:battle_drag.clear()
	autonomous_battle_clock.reset()
	autonomous_battle_summary=""
	auto_generation+=1
	auto_deployment_pending=false;auto_deployment_fallback=false
	auto_deployment_signature="";auto_deployment_step_index=-1;auto_deployment_render_stage=0
	auto_combat_pending=false;auto_combat_fallback=false
	auto_combat_plan_hash="";auto_combat_step_index=-1;auto_combat_render_stage=0
	auto_override_edit=false;auto_phase="";exploration_follow_plan.clear()

func _battle_presentation_blocked()->bool:
	var blocked:bool=grid==null or grid.modal_open or _product_touch_index>=0 \
		or _party_command_targeting or not _battle_target_mode.is_empty() or auto_combat_pending
	blocked=blocked or (battle_drag!=null and (battle_drag.active or battle_drag.control_held))
	if grid!=null:blocked=blocked or bool(grid.pointer_gesture_state().get("active",false))
	if is_instance_valid(party_command_menu):blocked=blocked or party_command_menu.get_popup().visible
	var manual_actor_menu:=find_child("ManualActorSelector",true,false) as MenuButton
	var directive_menu:=find_child("ActorDirectiveMenu",true,false) as MenuButton
	if manual_actor_menu!=null:blocked=blocked or manual_actor_menu.get_popup().visible
	if directive_menu!=null:blocked=blocked or directive_menu.get_popup().visible
	if companion_order_editor!=null:blocked=blocked or companion_order_editor.visible
	return blocked

func _tick_autonomous_battle(delta:float)->void:
	if session!=null and session.field_turns_active():return
	if session==null or not session.is_duo_autobattle() or not auto_orchestration_enabled:return
	var was_in_battle:bool=battle_command_flow.in_battle
	if battle_command_flow.sync(self):
		_apply_product_zoom_surface();_request_refresh()
	if battle_command_flow.in_battle and not was_in_battle:_cancel_product_rest("rest_encounter")
	var state=session.sim.world.party_encounter
	if state.safe_phase!="ENGAGED":
		autonomous_battle_clock.cursor=-1.0;_hero_turn_released=false;_hero_turn_was_waiting=false
		_retreat_active=false;return
	if _retreat_active and _hero_turn_holds():_hero_turn_released=true
	var blocked:=_battle_presentation_blocked()
	var hold_at:=-1.0
	if _hero_turn_holds():hold_at=float(session.individual_battle.next_event().at)
	var at:float=autonomous_battle_clock.advance(delta,session.sim.world.world_time,blocked,
		HERO_TURN_UNITS_PER_SECOND if battle_mode=="HERO_TURN" else autonomous_battle_clock.WORLD_UNITS_PER_SECOND,
		hold_at)
	var changed:=false
	var started:=Time.get_ticks_usec()
	var hero_id:=int(state.protagonist_id)
	if not blocked and not autonomous_battle_clock.paused:
		# Equal-time events have no artificial delay; re-assess between actors.
		# A bounded drain also keeps input responsive on exceptionally large fights.
		for iteration in range(16):
			var next:Dictionary=session.individual_battle.next_event()
			if next.is_empty() or float(next.at)>at:break
			if _hero_turn_holds():break
			var result:Dictionary=session.individual_battle.commit()
			if not bool(result.get("accepted",false)):
				autonomous_battle_clock.paused=true
				_show_manual_battle_feedback("자동 행동 실패 · "+str(result.get("reason","")))
				_request_refresh();break
			if int(result.get("actor_id",-1))==hero_id:
				_hero_turn_released=false
				if _approach_step_pending:
					# [공격] is one step. If the cell got taken meanwhile, the standing
					# order would keep the hero waiting on it; settle it where the hero
					# stands (journaled) so the next turn is the player's again.
					_approach_step_pending=false
					var goal:Variant=session.individual_battle.movements.get(hero_id)
					var hero_position:Vector2i=session.sim.world.entities[hero_id].position
					if goal is Vector2i and goal!=hero_position:
						session.individual_battle.reserve_move(hero_id,hero_position)
			_record_result(result,true,"자동 전투 실행 불가",true,BATTLE_ACTOR_MOTION_MSEC);changed=true
			if battle_mode=="AUTO" and battle_command_flow.check_danger(self):break
			if not str(result.get("reservation_rejection","")).is_empty():
				_show_manual_battle_feedback(str(result.reservation_rejection))
			if Time.get_ticks_usec()-started>=8000:break
		var remaining_event:Dictionary=session.individual_battle.next_event()
		if not remaining_event.is_empty() and float(remaining_event.at)<at:
			at=float(remaining_event.at);autonomous_battle_clock.cursor=at
	var waiting:=hero_turn_waiting()
	if waiting!=_hero_turn_was_waiting:
		_hero_turn_was_waiting=waiting;changed=true
	if changed:
		if session.sim.world.party_encounter.safe_phase=="ENGAGED":_refresh_individual_battle_surface()
		else:_request_refresh()
	battle_command_flow.paint(self)

func _hero_turn_holds()->bool:
	# The clock stops at the protagonist's event while nothing has released it:
	# no accepted hero input this turn, no reserved skill, and no unfinished
	# position order (a standing walk keeps going until the hero arrives).
	if battle_mode!="HERO_TURN" or session==null or session.sim==null:return false
	if not session.individual_battle.hero_turn_pending() or _hero_turn_released:return false
	var hero_id:=int(session.sim.world.party_encounter.protagonist_id)
	if not session.individual_battle.queued(hero_id).is_empty():return false
	if session.individual_battle.hold_reserved(hero_id):return false
	var goal:Variant=session.individual_battle.movements.get(hero_id)
	if goal is Vector2i and goal!=session.sim.world.entities[hero_id].position:return false
	# Nothing to decide while no enemy that can still fight is in view (only
	# downed bodies, or hunters out of sight): let time run so the fight can
	# end (bleed-out, lost pursuit) instead of freezing on a turn prompt.
	var world=session.sim.world
	for id_value in session.party_status().get("enemies_in_view",[]):
		if world.is_autonomous_target(int(id_value)):return true
	return false

func hero_turn_waiting()->bool:
	return session!=null and session.is_duo_autobattle() and session.sim!=null \
		and session.sim.world.party_encounter.safe_phase=="ENGAGED" and _hero_turn_holds()

func _release_hero_turn(message:String="")->void:
	# Any accepted protagonist input lets the clock run to the next hero event.
	_hero_turn_released=true
	if not message.is_empty():_show_manual_battle_feedback(message)
	_refresh_battle_surface_lightly()

func _refresh_battle_surface_lightly()->void:
	# Combat taps happen every turn; a full shell rebuild (~50ms) for each one
	# is the stutter players feel. Refresh the live surface while engaged.
	if session!=null and session.sim!=null and session.is_duo_autobattle() \
			and session.sim.world.party_encounter.safe_phase=="ENGAGED":
		_refresh_individual_battle_surface()
	else:_request_refresh()

func _portrait_battle_controls_visible()->bool:
	return session!=null and session.is_duo_autobattle() and session.sim!=null \
		and not session.field_turns_active() \
		and session.sim.world.party_encounter.safe_phase=="ENGAGED"

func _enemy_strip_visible()->bool:
	# Enemy portraits follow visibility, not the encounter phase: an enemy in
	# view shows its portrait before, during and after a fight the same way.
	if session==null or session.sim==null or not session.is_duo_autobattle():return false
	var world=session.sim.world
	for id_value in session.party_status().get("enemies_in_view",[]):
		if world.is_autonomous_target(int(id_value)):return true
	return false

func _on_manual_actor_selected(actor_id:int)->void:
	if not _battle_target_mode.is_empty():return
	var detail:Dictionary=session.inspect_party_member(actor_id)
	selected_member_id=actor_id;selected_target_id=-1
	var actor_name:=str(detail.get("display_name","파티원"))
	_show_manual_battle_feedback("%s 선택 · 액티브 스킬 / %s 개인 지침"%[
		actor_name,actor_name])
	_request_refresh()

func _hero_skill_rows(status:Dictionary)->Array:
	# The hero's skills as the row shows them. Before contact the combat gate is
	# lifted whenever an enemy is in view: using a skill on it is a first strike.
	var hero_id:=int(status.get("protagonist_id",-1))
	if hero_id<0 or not session.has_method("active_skill_rows"):return []
	var rows:Array=[]
	var phase:=str(status.get("safe_phase",""))
	var enemy_visible:bool=not status.get("enemies_in_view",status.get("visible_enemy_ids",[])).is_empty()
	for row_value in session.active_skill_rows(hero_id):
		if not row_value is Dictionary:continue
		var row:Dictionary=row_value.duplicate(true)
		if phase=="GROUPED" and str(row.get("reason",""))=="active_skill_combat_required":
			if enemy_visible and session.is_duo_autobattle():
				row["can_select"]=true;row["reason"]="";row["message"]="적을 고르면 선공합니다."
			else:row["message"]="적이 보일 때 선공할 수 있습니다."
		rows.append(row)
	return rows

func _render_hero_skill_row(status:Dictionary,visible:bool)->void:
	if hero_skill_row==null:return
	_clear_container(hero_skill_row)
	hero_skill_row.visible=visible
	if not visible:return
	# Keep the 48px rail on defeat/completion; hide actions, not map geometry.
	if bool(status.get("terminal",false)) or str(status.get("safe_phase",""))=="PARTY_DEFEATED" \
			or bool(_current_run_progress().get("complete",false)):return
	if session.field_turns_active():
		var members:Array=session.party_cards()
		for member in members:
			var actor_id:int=member.entity_id
			if actor_id!=session.sim.world.party_control_actor_id():continue
			var skills=preload("res://playtest/portrait_skill_row.gd").new()
			skills.name="PortraitSkills%d"%actor_id
			skills.slot_count=3
			skills.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			skills.configure(actor_id,session.active_skill_rows(actor_id),_battle_target_actor_id,_battle_target_skill_id)
			skills.explicit_pointer_input=true
			skills.skill_selected.connect(_on_manual_skill_selected)
			for button in skills.get_children():
				if button is Button:button.gui_input.connect(_on_product_button_gui_input.bind(str(button.name)))
			hero_skill_row.add_child(skills)
		return
	var hero_id:=int(status.get("protagonist_id",-1))
	var rows:=_hero_skill_rows(status)
	if rows.is_empty():hero_skill_row.visible=false;return
	var skills=preload("res://playtest/portrait_skill_row.gd").new();skills.name="HeroSkills"
	skills.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	skills.configure(hero_id,rows,_battle_target_actor_id,_battle_target_skill_id)
	skills.skill_selected.connect(_on_manual_skill_selected)
	hero_skill_row.add_child(skills)

func _update_hero_skill_row(status:Dictionary)->void:
	if hero_skill_row==null or not hero_skill_row.visible:return
	if session.field_turns_active():
		for member in session.party_cards():
			var skills=hero_skill_row.get_node_or_null("PortraitSkills%d"%int(member.entity_id))
			if skills!=null:skills.update_rows(int(member.entity_id),session.active_skill_rows(int(member.entity_id)))
		return
	var skills:=hero_skill_row.get_node_or_null("HeroSkills")
	if skills==null:return
	skills.update_rows(int(status.get("protagonist_id",-1)),_hero_skill_rows(status))

func _on_manual_skill_selected(actor_id:int,skill_id:String,skill_label:String)->void:
	if not _battle_target_committing and _battle_target_mode=="ACTIVE_SKILL" \
			and _battle_target_actor_id==actor_id and _battle_target_skill_id==skill_id:
		_cancel_battle_targeting("대상 선택을 취소했습니다.");_request_refresh();return
	if _battle_target_committing or not _battle_target_mode.is_empty():return
	if str(session.individual_battle.queued(actor_id).get("skill_id",""))==skill_id:
		session.individual_battle.cancel(actor_id)
		_show_manual_battle_feedback("%s · 예약 취소"%skill_label);_request_refresh();return
	if not session.has_method("active_skill_rows") or not session.has_method("use_active_skill"):
		_show_manual_battle_feedback("액티브 스킬을 아직 사용할 수 없습니다.");return
	var selected_row:Dictionary={}
	var available_rows:Array=session.active_skill_rows(actor_id) if session.field_turns_active() else _hero_skill_rows(session.party_status())
	for row_value in available_rows:
		if row_value is Dictionary and str(row_value.get("skill_id",""))==skill_id:
			selected_row=row_value;break
	if selected_row.is_empty() or not bool(selected_row.get("can_select",false)):
		_show_manual_battle_feedback(str(selected_row.get("message",
			selected_row.get("reason","지금 사용할 수 없습니다."))));return
	if session.field_turns_active():
		_switch_field_member(actor_id)
		if session.sim.world.party_control_actor_id()!=actor_id:return
	_retreat_active=false
	_battle_target_mode="ACTIVE_SKILL";_battle_target_actor_id=actor_id
	_battle_target_skill_id=skill_id;_battle_target_skill_label=skill_label
	_battle_target_prior_paused=autonomous_battle_clock.paused
	autonomous_battle_clock.paused=true
	var reach:Dictionary=session.skill_reach_cells(actor_id,skill_id) \
		if session.has_method("skill_reach_cells") else {}
	grid.set_skill_reach_cells(reach.get("cells",[]),str(reach.get("target","ENEMY")))
	if str(reach.get("target",""))=="TILE":
		_battle_target_prompt=skill_label+" · 사거리 5칸 · 물이나 바닥을 누르세요"
		_show_manual_battle_feedback(_battle_target_prompt+" · 취소: 같은 기술 다시 선택 / Esc")
		_request_refresh();return
	_battle_target_prompt="%s · 붉은 칸의 %s을 고르세요"%[skill_label,
		"아군" if str(reach.get("target","ENEMY"))=="ALLY" else "적"]
	_show_manual_battle_feedback(_battle_target_prompt+" · 빈 칸을 누르면 취소")
	_request_refresh()

func _on_actor_directive_selected(actor_id:int,command_id:String)->void:
	if _battle_target_committing or not _battle_target_mode.is_empty():return
	if not session.has_method("issue_actor_command"):
		_show_manual_battle_feedback("개인 지침을 아직 변경할 수 없습니다.");return
	if command_id=="ATTACK_TARGET":
		_battle_target_mode="ACTOR_COMMAND";_battle_target_actor_id=actor_id
		_battle_target_skill_id="";_battle_target_skill_label=""
		_battle_target_prior_paused=autonomous_battle_clock.paused
		autonomous_battle_clock.paused=true
		_battle_target_prompt="%s 지침 · 추격할 적 선택"%_actor_display_name(actor_id)
		_show_manual_battle_feedback(_battle_target_prompt+" · 지속 지침")
		_request_refresh();return
	var assessment:Dictionary=session.actor_command_assessment(actor_id,command_id) \
		if session.has_method("actor_command_assessment") else {"accepted":true}
	if not bool(assessment.get("accepted",false)):
		_show_manual_battle_feedback(str(assessment.get("message",
			assessment.get("reason","지침을 적용할 수 없습니다."))));return
	var result:Dictionary=session.issue_actor_command(actor_id,command_id)
	if not bool(result.get("accepted",false)):
		_show_manual_battle_feedback(str(result.get("message",
			result.get("reason","지침을 적용할 수 없습니다."))))
		_request_refresh();return
	var message:=str(result.get("message",""))
	_show_manual_battle_feedback("%s 개인 지침 · %s%s"%[_actor_display_name(actor_id),
		_actor_directive_label(command_id),(" · "+message) if not message.is_empty() else ""])
	_request_refresh()

func _commit_battle_target(target_id:int)->void:
	if _battle_target_mode.is_empty() or _battle_target_committing:return
	_battle_target_committing=true
	var assessment:Dictionary={}
	var first_strike:bool=_battle_target_mode=="ACTIVE_SKILL" \
		and str(session.party_status().get("safe_phase",""))=="GROUPED"
	if session.field_turns_active() and _battle_target_mode=="ACTIVE_SKILL":
		assessment=session.FieldTurns.assess(session.sim,ActionScript.skill(
			_battle_target_actor_id,_battle_target_skill_id,target_id))
	elif first_strike:
		assessment={"accepted":target_id in session.party_status().get("enemies_in_view",[]),
			"message":"보이는 적을 고르세요."}
	elif _battle_target_mode=="ACTIVE_SKILL":
		assessment=session.individual_battle.assessment(_battle_target_actor_id,
			_battle_target_skill_id,target_id)
	else:
		assessment=session.actor_command_assessment(_battle_target_actor_id,
			"ATTACK_TARGET",target_id)
	if not bool(assessment.get("accepted",false)):
		_battle_target_committing=false
		_battle_target_prompt=str(assessment.get("message",
			assessment.get("reason","그 대상은 선택할 수 없습니다.")))
		_show_manual_battle_feedback(_battle_target_prompt)
		_request_refresh();return
	var caster_id:=_battle_target_actor_id
	var mode:=_battle_target_mode
	var skill_id:=_battle_target_skill_id
	var skill_label:=_battle_target_skill_label
	var prior_paused:=_battle_target_prior_paused
	# Clear first so a refresh or duplicate pointer packet cannot cast twice.
	_clear_battle_targeting_state()
	var result:Dictionary
	if session.field_turns_active() and mode=="ACTIVE_SKILL":result=session.use_active_skill(caster_id,skill_id,target_id)
	elif first_strike:result=session.strike_with_skill(skill_id,target_id)
	elif mode=="ACTIVE_SKILL":result=session.individual_battle.reserve(caster_id,skill_id,target_id)
	else:result=session.issue_actor_command(caster_id,"ATTACK_TARGET",target_id)
	autonomous_battle_clock.paused=prior_paused
	_battle_target_committing=false
	if bool(result.get("accepted",false)):
		if caster_id==int(session.party_status().get("protagonist_id",-1)):_hero_turn_released=true
		if mode=="ACTIVE_SKILL":_record_result(result,true,"액티브 스킬 실행 불가")
		var target_name:=_entity_display_name(target_id)
		var result_message:=str(result.get("message","적용됨"))
		_show_manual_battle_feedback("%s · %s → %s · %s"%[
			_actor_display_name(caster_id),skill_label if mode=="ACTIVE_SKILL" else "지속 지침: 표적 추격",
			target_name,result_message])
	else:
		_show_manual_battle_feedback(str(result.get("message",
			result.get("reason","실행할 수 없습니다."))))
	_request_refresh()

func _cancel_battle_targeting(message:String="")->void:
	if _battle_target_mode.is_empty():return
	var prior_paused:=_battle_target_prior_paused
	_clear_battle_targeting_state()
	autonomous_battle_clock.paused=prior_paused
	if not message.is_empty():_show_manual_battle_feedback(message)
	_request_refresh()

func _show_manual_battle_feedback(message:String)->void:
	_show_product_command_feedback(message)
	_product_transient_event_feedback=message

func _clear_battle_targeting_state()->void:
	if grid!=null:grid.clear_skill_reach_cells()
	_battle_target_mode="";_battle_target_actor_id=-1
	_battle_target_skill_id="";_battle_target_skill_label=""
	_battle_target_prompt="";_battle_target_prior_paused=false

func _validate_battle_targeting(status:Dictionary)->void:
	if _battle_target_mode.is_empty():return
	var valid_phase:=str(status.get("view_mode",""))=="COMBAT" \
		and str(status.get("safe_phase",""))=="ENGAGED" and not bool(status.get("terminal",false))
	if session.field_turns_active():
		valid_phase=str(status.get("view_mode","")) in ["EXPLORATION","COMBAT"] and not bool(status.get("terminal",false))
	var caster_alive:=false
	for row_value in session.party_cards():
		if row_value is Dictionary and int(row_value.get("entity_id",-1))==_battle_target_actor_id:
			caster_alive=bool(row_value.get("alive",true));break
	if not valid_phase or not caster_alive:_cancel_battle_targeting("")

func _actor_display_name(actor_id:int)->String:
	for row_value in session.party_cards():
		if row_value is Dictionary and int(row_value.get("entity_id",-1))==actor_id:
			return str(row_value.get("display_name","파티원"))
	return "파티원"

func _entity_display_name(entity_id:int)->String:
	var party_name:=_actor_display_name(entity_id)
	if party_name!="파티원":return party_name
	var enemy:Dictionary=session.inspect_enemy(entity_id)
	return str(enemy.get("display_name","대상"))

func _actor_directive_label(command_id:String)->String:
	return {"RETREAT":"후퇴","STOP_ATTACK":"공격 중지","HOLD_POSITION":"자리 지키기",
		"FOLLOW":"따라오기","ATTACK_TARGET":"표적 추격"}.get(command_id,command_id)

func _arm_pending_auto_after_tree_entry()->void:
	if not is_inside_tree():return
	if auto_deployment_pending and auto_deployment_render_stage==0:
		get_tree().process_frame.connect(_advance_auto_deployment_preview.bind(auto_generation),CONNECT_ONE_SHOT)
	elif auto_combat_pending and auto_combat_render_stage==0:
		_arm_auto_combat_preview(auto_generation)

func _orchestrate_auto_phase(status:Dictionary)->void:
	if member_detail_modal!=null and member_detail_modal.visible:return
	if companion_order_editor!=null and companion_order_editor.visible:return
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
				var result:Dictionary=session.settle_contact()
				_record_result(result,true,"조우 처리 불가")
				auto_phase=str(session.party_status().get("safe_phase",""))
			elif not auto_deployment_pending and not auto_deployment_fallback:
				_prepare_auto_deployment(status)
		"ENGAGED":
			if session.is_duo_autobattle():return
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
			# A defeated solo roster can be empty; keep its HUD allocation.
			"party_height":PRODUCT_PARTY_CARD_HEIGHT if _is_solo_product_session() else 0,"gap":0,"card_min_width":0,
			"portrait_min_size":[0,0],"portrait_removed":true,"font_size":FONT_AUX}.duplicate(true)
	var gap:=4
	var available_width:=maxi(44,int(floor(viewport_width))-12-gap*(effective_count-1))
	var card_min_width:=maxi(44,int(floor(float(available_width)/effective_count)))
	var spec:Dictionary={"layout_id":"COMPACT","requested_count":count,
		"effective_count":effective_count,"party_height":84,"gap":gap,
		"card_min_width":card_min_width,
		"portrait_min_size":[0,0],"portrait_removed":true,"font_size":FONT_AUX}
	if effective_count==1:
		spec.layout_id="SPOTLIGHT";spec.party_height=68
	elif effective_count==2:
		spec.layout_id="DUAL";spec.party_height=80
	if _is_solo_product_session():
		# The product strip sits where the D-pad used to be, so every card keeps
		# one fixed height with a typographic portrait beside its vitals. The
		# portrait narrows with the card so three Korean dossiers still fit 360px.
		spec.party_height=PRODUCT_PARTY_CARD_HEIGHT
		var portrait_height:=PRODUCT_PARTY_CARD_HEIGHT-2
		spec.portrait_min_size=[clampi(int(float(card_min_width)*0.42),44,portrait_height),
			portrait_height]
		spec.portrait_removed=false
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
			if _is_solo_product_session():
				var portrait:=cards.find_child("MemberCard%d"%int(row.entity_id),true,false)
				if portrait!=null:portrait.party_index=index

func _add_member_card(row:Dictionary,speech:Dictionary={},layout_spec:Dictionary={})->void:
	if _is_solo_product_session():
		var compact=CompactPortraitScript.new()
		var member_id:=int(row.entity_id)
		compact.name="MemberCard%d"%member_id;compact.actor=row.duplicate(true)
		if _portrait_battle_controls_visible() or session.field_turns_active():
			compact.actor["energy"]=session.sim.world.party_encounter.member(member_id).energy
		compact.selected=member_id==selected_member_id
		compact.order_reserved=session.has_companion_order(member_id)
		compact.order_reserved=compact.order_reserved or not session.individual_battle.queued(member_id).is_empty()
		compact.party_count=int(layout_spec.get("effective_count",1))
		compact.custom_minimum_size=Vector2(44,PRODUCT_PARTY_CARD_HEIGHT)
		compact.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		compact.tooltip_text="%s · 탭 또는 F1~F4: 조작 전환 / 길게 누르기: 상태창"%str(row.display_name)
		DarkPixelSkinScript.apply_action_button(compact,DarkPixelSkinScript.CYAN)
		compact.focus_mode=Control.FOCUS_NONE
		cards.add_child(compact)
		return
	var spec:=layout_spec if not layout_spec.is_empty() else party_card_layout_spec(
		SessionScript.ACTIVE_PARTY_LIMIT,size.x)
	var button:=Button.new(); var member_id:=int(row.entity_id); button.name="MemberCard%d"%member_id
	button.custom_minimum_size=Vector2(float(spec.get("card_min_width",44)),float(spec.get("party_height",160)))
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.size_flags_stretch_ratio=1.0
	button.text=""; button.clip_contents=true
	DarkPixelSkinScript.apply_action_button(button,DarkPixelSkinScript.CYAN)
	button.set_meta("pixel_material","PARTY_DOSSIER")
	var inset:=MarginContainer.new(); inset.name="CardContent"; inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for margin in ["margin_left","margin_right","margin_top","margin_bottom"]:
		var inset_amount:=0
		if _is_solo_product_session():
			# Three compact dossier rows naturally consume the whole 68px strip.
			# Keep horizontal breathing room without making the content 2px taller
			# than its touch/card surface.
			inset_amount=2 if margin in ["margin_left","margin_right"] else 1
		inset.add_theme_constant_override(margin,inset_amount)
	inset.mouse_filter=Control.MOUSE_FILTER_IGNORE
	# PartyCards is the single outer rail; per-member nested glyph frames consumed
	# most of the old tall strip and forced its measured content outside the button.
	button.add_child(inset)
	_add_compact_dossier_content(inset,row,speech,spec)
	button.gui_input.connect(_on_member_card_gui_input.bind(member_id,str(row.display_name),button))
	button.pressed.connect(_on_member_card_pressed.bind(member_id,str(row.display_name))); cards.add_child(button)

func _add_compact_dossier_content(inset:MarginContainer,row:Dictionary,speech:Dictionary,spec:Dictionary)->void:
	var root:=HBoxContainer.new();root.name="SpotlightDetails" if int(spec.get("effective_count",1))==1 else "CardIdentity"
	root.clip_contents=true
	root.add_theme_constant_override("separation",4);root.mouse_filter=Control.MOUSE_FILTER_IGNORE;inset.add_child(root)
	var count:=int(spec.get("effective_count",1));var seal_size:=44 if count==1 else (40 if count==2 else 34)
	if not bool(spec.get("portrait_removed",true)):
		root.add_child(_member_portrait(row,spec))
	else:
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
	# Two or more dossiers may also carry a one-line companion callout. Keep the
	# name at the 14 px mobile readability floor so the complete ledger remains
	# inside the fixed 68 px party rail.
	var name_label:=_card_label(display_name,"MemberName",FONT_BODY if count==1 else FONT_AUX)
	name_label.add_theme_font_override("font",DarkPixelSkinScript.PixelFont)
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
	# own line made a companion speech strip exceed the compact cards.
	var state_label:=_card_label("%s%s · %s"%[str(emotion.get("icon","")),str(emotion.get("label","평온")),readiness],"EmotionState",FONT_AUX)
	state_label.max_lines_visible=1;state_label.clip_text=true
	state_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	state_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(state_label)
	var ready_label:=_card_label(readiness,"Readiness",FONT_AUX);ready_label.visible=false;footer.add_child(ready_label)
	var stress_label:=_card_label("","StressState",FONT_AUX);_apply_stress_band_label(stress_label,row);footer.add_child(stress_label)
	if bool(progression.get("available",false)):
		var xp_gauge:Control=_gauge("CompactXPBar","XP",int(progression.get("xp_current",0)),maxi(1,int(progression.get("xp_required",1))),5,AsciiFrameScript.YELLOW)
		xp_gauge.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(xp_gauge)
	if str(row.get("role",""))=="COMPANION" and not speech.is_empty():_add_companion_speech_strip(stack,speech)

func _stress_band_color(band:String)->Color:
	match band:
		"PANIC":return AsciiFrameScript.RED
		"ANXIOUS":return Color("#ffae5f")
		"TENSE":return AsciiFrameScript.YELLOW
	return Color("#8fa5ae")

func _apply_stress_band_label(label:Label,row:Dictionary)->void:
	# Portraits show the band, not the number; the status folio keeps ST n/1000.
	var band:=str(row.get("stress_band","CALM"))
	label.text=str(row.get("stress_band_label","안정"))
	label.tooltip_text="스트레스 %d/1000"%int(row.get("stress",0))
	label.add_theme_color_override("font_color",_stress_band_color(band))

func _member_portrait(row:Dictionary,spec:Dictionary)->Control:
	var portrait_size:Array=spec.get("portrait_min_size",[52,54])
	var portrait_view=PortraitScript.new();portrait_view.name="Portrait"
	portrait_view.custom_minimum_size=Vector2(float(portrait_size[0]),float(portrait_size[1]))
	portrait_view.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	portrait_view.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var portrait_actor:Dictionary=row.duplicate(true)
	portrait_actor["is_protagonist"]=str(row.get("role",""))=="PROTAGONIST";portrait_actor["faction_id"]="party"
	portrait_actor["species_id"]=str(row.get("species_id","human"))
	portrait_actor["life_state"]="ACTIVE" if bool(row.get("alive",true)) else "DEAD"
	portrait_actor["status_ids"]=row.get("status_ids",[]).duplicate(true)
	portrait_view.set_actor(portrait_actor);return portrait_view

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
	name_label.add_theme_font_override("font",DarkPixelSkinScript.PixelFont)
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
	var stress_text:=_card_label("","StressState",FONT_AUX);_apply_stress_band_label(stress_text,row)
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
	var stress_bar:=_bar("StressBar",int(row.stress),1000,_stress_band_color(str(row.get("stress_band","CALM")))); stress_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL; bars.add_child(stress_bar)

func _add_companion_speech_strip(parent:VBoxContainer,speech:Dictionary)->void:
	var product_strip:=_is_solo_product_session()
	var strip:=PanelContainer.new();strip.name="CompanionSpeechStrip"
	strip.custom_minimum_size.y=16 if product_strip else 22
	strip.mouse_filter=Control.MOUSE_FILTER_IGNORE;strip.clip_contents=true
	strip.set_meta("actor_id",int(speech.get("actor_id",-1)))
	strip.set_meta("source",str(speech.get("source","SUGGESTED")))
	strip.set_meta("full_reason",str(speech.get("reason","")))
	var source:=str(speech.get("source","SUGGESTED"))
	strip.add_theme_stylebox_override("panel",DarkPixelSkinScript.panel_surface(
		DarkPixelSkinScript.SLOT_EMPTY,DarkPixelSkinScript.IRON_SHADOW,
		0 if product_strip else 2,1));parent.add_child(strip)
	strip.set_meta("visual_family",DarkPixelSkinScript.VISUAL_FAMILY)
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


func _town_deck(status:Dictionary)->void:
	if session.town_life_enabled():
		_town_life_deck(status);return
	var base_enabled:bool=session.has_method("base_overview") \
		and bool(session.base_overview().get("enabled",false))
	if town_facility_id.is_empty():
		town_facility_id="BASE" if base_enabled else ("GUILD" if session.allows_companions() else "GATE")
	if town_facility_id=="BASE" and not base_enabled:
		town_facility_id="GUILD" if session.allows_companions() else "GATE"
	if not session.allows_companions() and town_facility_id=="GUILD":town_facility_id="GATE"
	if base_enabled:
		if town_facility_id=="BASE":
			_town_base_panel()
		else:
			_add_notice(_town_summary_text(status),"TownGuildHallSummary",FONT_KEY)
			var back:=_add_button(deck,"← 거점 지도","TownBaseMapBack",
				_on_town_facility_selected.bind("BASE"))
			back.custom_minimum_size.y=48
			match town_facility_id:
				"CLINIC":_town_clinic_panel(status)
				"SHRINE":_town_shrine_panel(status)
				"MARKET":_town_market_panel()
				"ARMORY":_town_armory_panel()
				"GATE":_town_gate_panel()
				_:town_facility_id="BASE";_town_base_panel()
		_add_notice("마을에서는 이동 턴이 흐르지 않습니다. 준비가 끝난 뒤 원정을 시작합니다.",
			"TownPreparationRule",FONT_AUX)
		_selected_detail();return
	_add_notice(_town_summary_text(status),"TownGuildHallSummary",FONT_KEY)
	var stations:=GridContainer.new();stations.name="TownGuildHallStations"
	stations.columns=3;stations.add_theme_constant_override("h_separation",4)
	stations.add_theme_constant_override("v_separation",4);deck.add_child(stations)
	for row in [["BASE","거점"],["GUILD","길드"],["CLINIC","치유소"],["SHRINE","신전"],
			["MARKET","시장"],["ARMORY","장비"],["GATE","원정문"]]:
		if str(row[0])=="BASE" and not base_enabled:continue
		if str(row[0])=="GUILD" and not session.allows_companions():continue
		var button:=_add_button(stations,str(row[1]),"TownFacility%s"%str(row[0]),
			_on_town_facility_selected.bind(str(row[0])))
		button.custom_minimum_size.y=48
		button.toggle_mode=true;button.button_pressed=town_facility_id==str(row[0])
	match town_facility_id:
		"BASE":_town_base_panel()
		"CLINIC":_town_clinic_panel(status)
		"SHRINE":_town_shrine_panel(status)
		"MARKET":_town_market_panel()
		"ARMORY":_town_armory_panel()
		"GATE":_town_gate_panel()
		_:
			town_facility_id="GUILD";_add_recruitment_candidates()
	_add_notice("마을에서는 이동 턴이 흐르지 않습니다. 준비가 끝난 뒤 원정을 시작합니다.",
		"TownPreparationRule",FONT_AUX)
	_selected_detail()


func _town_life_deck(_status:Dictionary)->void:
	var life:Dictionary=session.town_life_overview()
	var widgets=preload("res://playtest/town_ui_widgets.gd")
	if town_facility_id not in ["","BASE"]:
		var back:=widgets.button(deck,"← 마을","TownLifeBack")
		back.pressed.connect(_on_town_facility_selected.bind("BASE"))
	if not notice_text.is_empty() and not notice_text.begins_with("여관방"):
		var feedback:=widgets.label(deck,notice_text,13,widgets.GOLD)
		feedback.name="TownActionFeedback"
	if town_facility_id in ["","BASE","INN","GUILD","SHRINE"]:
		var panel=preload("res://playtest/town_life_panel.gd").new()
		panel.name="TownLifePanel";panel.camera=base_map_camera
		panel.state=town_ui_state;panel.screen=town_facility_id
		panel.command_requested.connect(_on_town_life_command)
		panel.facility_requested.connect(_on_town_facility_selected)
		panel.resident_requested.connect(_open_member_detail)
		deck.add_child(panel);panel.present(life)
	elif town_facility_id=="HOUSE" and life.house_owned:
		_town_base_panel()
	else:
		var panel=preload("res://playtest/town_facility_panel.gd").new()
		panel.name="TownFacilityPanel";panel.session=session;panel.life=life
		panel.screen=town_facility_id;panel.state=town_ui_state
		panel.action_requested.connect(_on_town_service_action)
		panel.resident_requested.connect(_open_member_detail)
		deck.add_child(panel);panel.present()

func _on_town_service_action(operation:Dictionary)->void:
	match str(operation.action):
		"BUY":_on_town_market_buy(str(operation.definition_id))
		"SELL":_on_base_sell_requested(str(operation.resource_id),1)
		"TREAT":_on_town_clinic_treat(int(operation.entity_id))
		"EQUIP":_on_town_equip(int(operation.entity_id),str(operation.instance_id),str(operation.slot))
		"UNEQUIP":_on_town_unequip(int(operation.entity_id),str(operation.slot))
		"TRANSFER":_on_town_transfer(int(operation.entity_id),int(operation.target_id),str(operation.instance_id))
		"DEPART":_on_town_depart(int(operation.floor),str(operation.route))
		"ACQUIRE":_on_town_life_command({"action":"ACQUIRE"})
		"ROSTER":town_ui_state.filter="COMPANY";_on_town_facility_selected("INN")

func _on_town_life_command(operation:Dictionary)->void:
	var result:Dictionary
	if str(operation.get("action",""))=="GUILD_TUTORIAL":
		result=session.guild_tutorial_command({"action":str(operation.get("quest_action","")),
			"quest_id":str(operation.get("quest_id",""))})
	else:
		result=session.town_life_command(operation)
	notice_text=str(result.get("message","마을 행동을 완료하지 못했습니다."))
	if result.get("accepted",false) and operation.action=="ACQUIRE":town_facility_id="HOUSE"
	if result.get("accepted",false) and operation.action=="JOIN":
		town_ui_state.filter="COMPANY";town_ui_state.resident=int(operation.entity_id)
	_request_refresh()


func _town_base_panel()->void:
	if not session.has_method("base_overview"):
		_add_notice("거점 현황을 불러올 수 없습니다.","BaseUnavailable",FONT_BODY);return
	var panel=BaseProgressPanelScript.new();panel.name="TownBaseProgress"
	panel.configure_camera(base_map_camera)
	if session.has_method("base_build_assessment"):
		panel.configure_build_assessment(Callable(session,"base_build_assessment"))
	panel.upgrade_requested.connect(_on_base_upgrade_requested)
	panel.service_requested.connect(_on_base_service_requested)
	panel.sell_requested.connect(_on_base_sell_requested)
	panel.building_selected.connect(_on_base_building_selected)
	panel.resident_requested.connect(_open_member_detail)
	panel.construction_confirm_requested.connect(_on_base_construction_confirmed.bind(panel))
	panel.work_cancel_requested.connect(func():
		var result:Dictionary=session.base_work({"action":"CANCEL"})
		notice_text=str(result.get("message",""));_request_refresh())
	panel.production_requested.connect(func(action:String,recipe_id:String):
		var result:Dictionary=session.base_work({"action":action,"recipe_id":recipe_id})
		notice_text=str(result.get("message","작업할 수 없습니다."));_request_refresh())
	panel.rest_requested.connect(_on_town_shrine_rest)
	deck.add_child(panel);panel.present(session.base_overview(),false,selected_base_building_id)


func _on_base_building_selected(building_id:String)->void:
	selected_base_building_id=building_id
	if building_id in ["MARKET","ARMORY","GATE"]:
		_on_base_service_requested(building_id)


func _on_base_construction_confirmed(type_id:String,tile_origin:Vector2i,panel)->void:
	if not session.has_method("base_build"):
		notice_text="건설 기능을 사용할 수 없습니다.";return
	var result:Dictionary=session.base_work({"action":"BUILD","type_id":type_id,
		"tile_origin":[tile_origin.x,tile_origin.y]})
	if bool(result.get("accepted",false)):
		selected_base_building_id=type_id
		notice_text=str(result.get("message","%s 건설을 마쳤습니다."%_base_building_label(type_id)))
		action_feedback_text=notice_text;_request_refresh();return
	var message:=str(result.get("message","이 위치에는 건설할 수 없습니다."))
	notice_text=message;action_feedback_text=message
	if panel!=null and is_instance_valid(panel):
		panel.apply_placement_assessment(result)


func _base_building_label(type_id:String)->String:
	return {"CLINIC":"진료소","MARKET":"시장","ARMORY":"대장간"}.get(type_id,type_id)


func _on_base_upgrade_requested(facility_id:String)->void:
	if not session.has_method("base_upgrade"):
		notice_text="시설을 강화할 수 없습니다.";_request_refresh();return
	var result:Dictionary=session.base_work({"action":"UPGRADE","type_id":facility_id})
	notice_text=str(result.get("message","시설을 강화했습니다." if bool(
		result.get("accepted",false)) else "시설을 강화할 수 없습니다."))
	action_feedback_text=notice_text;_request_refresh()


func _on_base_service_requested(facility_id:String)->void:
	town_facility_id={"LODGE":"SHRINE","CLINIC":"CLINIC","MARKET":"MARKET",
		"ARMORY":"ARMORY","GATE":"GATE"}.get(
		facility_id, "BASE")
	notice_text="";action_feedback_text="";_request_refresh()


func _on_base_sell_requested(resource_id:String,amount:int)->void:
	if not session.has_method("base_sell"):
		notice_text="자원 교환을 사용할 수 없습니다.";_request_refresh();return
	var result:Dictionary=session.base_sell(resource_id,amount)
	notice_text=str(result.get("message","자원을 금화로 교환했습니다." if bool(
		result.get("accepted",false)) else "자원을 교환할 수 없습니다."))
	action_feedback_text=notice_text;_request_refresh()


func _town_summary_text(status:Dictionary)->String:
	var cycle:Dictionary=status.get("expedition_cycle",{}) \
		if status.get("expedition_cycle",{}) is Dictionary else {}
	var reason:="던전 폐쇄 시간이 되어 생존한 원정대가 귀환했습니다." \
		if str(cycle.get("return_reason",""))=="TIME_LIMIT" else "원정대가 마을에 머물고 있습니다."
	var gold:int=session.town_gold() if session!=null and session.has_method("town_gold") else 0
	return "마을 · 원정 %d 귀환 · %d층 · 금화 %d\n%s"%[
		int(cycle.get("expedition_index",0)),int(cycle.get("floor_index",1)),gold,reason]


func _town_clinic_panel(status:Dictionary)->void:
	var town:Dictionary=session.town_overview() if session.has_method("town_overview") else {}
	var clinic_cost:=int(town.get("clinic_cost",SessionScript.TOWN_CLINIC_COST))
	_add_notice("[치유소] 체력·출혈·일반 상처·기능 저하 회복 · 절단은 유지 · 1인 %d금화"%
		clinic_cost,"TownClinicTitle",FONT_BODY)
	var members:Variant=session.company_member_ids() if session.town_life_enabled() else status.get("party_member_ids",[])
	for entity_id_value in members:
		var entity_id:=int(entity_id_value)
		var detail:Dictionary=session.inspect_party_member(entity_id)
		if not bool(detail.get("accepted",false)):continue
		var body:Dictionary=detail.get("body_state",{}) \
			if detail.get("body_state",{}) is Dictionary else {}
		var assessment:Dictionary=session.town_clinic_assessment(entity_id)
		var severed:=0;var disabled:=0
		for part_value in body.get("parts",[]):
			if not part_value is Dictionary:continue
			if str(part_value.get("condition",""))=="SEVERED":severed+=1
			elif str(part_value.get("condition",""))=="DISABLED":disabled+=1
		var line:=HBoxContainer.new();line.name="TownClinicMember%d"%entity_id
		line.custom_minimum_size.y=TOUCH_TARGET;deck.add_child(line)
		var label:=Label.new();label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size",FONT_AUX)
		label.text="%s · HP %d/%d · 상처 %d · 기능저하 %d · 절단 %d"%[
			str(detail.get("display_name","파티원")),int(detail.get("health",0)),
			int(detail.get("max_health",0)),int(body.get("wound_count",0)),disabled,severed]
		label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;line.add_child(label)
		var treatment:=_add_button(line,"치료","TownClinicTreat%d"%entity_id,
			_on_town_clinic_treat.bind(entity_id))
		treatment.custom_minimum_size.x=72
		treatment.disabled=not bool(assessment.get("accepted",false))
		treatment.tooltip_text=str(assessment.get("message",""))


func _town_shrine_panel(status:Dictionary)->void:
	if session.scenario_id==SessionScript.DUO_SCENARIO_ID:
		selected_base_building_id="LODGE";_town_base_panel();return
	var town:Dictionary=session.town_overview() if session.has_method("town_overview") else {}
	var stress_recovery:=int(town.get("shrine_stress_reduction",
		SessionScript.TOWN_SHRINE_STRESS_REDUCTION))
	_add_notice("[신전] 한 번에 긴장 %d 회복 · 1인 %d금화"%[
		stress_recovery,SessionScript.TOWN_SHRINE_COST],
		"TownShrineTitle",FONT_BODY)
	var morale:Dictionary=session.party_morale_observation()
	for member_value in morale.get("members",[]):
		if not member_value is Dictionary:continue
		var member:Dictionary=member_value;var entity_id:=int(member.entity_id)
		var assessment:Dictionary=session.town_shrine_assessment(entity_id)
		var line:=HBoxContainer.new();line.name="TownShrineMember%d"%entity_id
		line.custom_minimum_size.y=TOUCH_TARGET;deck.add_child(line)
		var label:=Label.new();label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size",FONT_AUX)
		label.text="%s · 긴장 %d/1000 · %s"%[str(member.display_name),
			int(member.stress),str(member.mode_label)];line.add_child(label)
		var rest:=_add_button(line,"휴식","TownShrineRest%d"%entity_id,
			_on_town_shrine_rest.bind(entity_id))
		rest.custom_minimum_size.x=72;rest.disabled=not bool(assessment.get("accepted",false))
		rest.tooltip_text=str(assessment.get("message",""))


func _town_market_panel()->void:
	_add_notice("[시장] 귀환할 때마다 소모품과 기본 장비 재입고",
		"TownMarketTitle",FONT_BODY)
	for item_value in session.town_market_stock():
		if not item_value is Dictionary:continue
		var item:Dictionary=item_value
		var line:=HBoxContainer.new();line.name="TownMarket%s"%str(item.definition_id)
		line.custom_minimum_size.y=TOUCH_TARGET;deck.add_child(line)
		var label:=Label.new();label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size",FONT_AUX)
		label.text="%s · %d금화 · 재고 %d"%[
			str(item.label),int(item.price),int(item.remaining)];line.add_child(label)
		var buy:=_add_button(line,"구입","TownMarketBuy%s"%str(item.definition_id),
			_on_town_market_buy.bind(str(item.definition_id)))
		buy.custom_minimum_size.x=72;buy.disabled=not bool(item.can_buy)
		buy.tooltip_text=str(item.message)
	var sell_rows:Array[Dictionary]=session.town_market_sell_rows()
	if sell_rows.is_empty():return
	_add_notice("[매입] 원정에서 모은 마석을 금화로 바꿉니다",
		"TownMarketSellTitle",FONT_BODY)
	for sell_value in sell_rows:
		var line:=HBoxContainer.new();line.name="TownMarketSell%s"%str(sell_value.instance_id)
		line.custom_minimum_size.y=TOUCH_TARGET;deck.add_child(line)
		var label:=Label.new();label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size",FONT_AUX)
		label.text="%s ×%d · %d금화"%[str(sell_value.label),int(sell_value.quantity),
			int(sell_value.gold)];line.add_child(label)
		var sell:=_add_button(line,"판매","TownMarketSellButton%s"%str(sell_value.instance_id),
			_on_town_market_sell.bind(str(sell_value.instance_id)))
		sell.custom_minimum_size.x=72;sell.disabled=not bool(sell_value.can_sell)
		sell.tooltip_text=str(sell_value.message)


func _town_armory_panel()->void:
	_add_notice("[장비 보관소] 파티원이 가진 장비와 소모품을 서로 이전합니다. 장착품은 이전 시 해제됩니다.",
		"TownArmoryTitle",FONT_BODY)
	var owners:Array[Dictionary]=session.town_armory_rows()
	if owners.size()<2:
		_add_notice("동료가 합류하면 파티원 사이에서 아이템을 옮길 수 있습니다.",
			"TownArmorySolo",FONT_AUX);return
	for owner in owners:
		_add_notice("%s · 가방 %d/%d"%[str(owner.display_name),
			int(owner.used_backpack_slots),int(owner.capacity)],
			"TownArmoryOwner%d"%int(owner.entity_id),FONT_KEY)
		for item_value in owner.items:
			if not item_value is Dictionary:continue
			var item:Dictionary=item_value
			var line:=HBoxContainer.new();line.name="TownArmoryItem%s"%str(item.instance_id)
			line.custom_minimum_size.y=TOUCH_TARGET;deck.add_child(line)
			var label:=Label.new();label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			label.add_theme_font_size_override("font_size",FONT_AUX)
			label.text="%s%s"%[str(item.label)," · 장착" if bool(item.equipped) else ""]
			label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;line.add_child(label)
			if bool(item.equipped):
				var unequip:=_add_button(line,"해제",
					"TownUnequip%s"%str(item.instance_id),_on_town_unequip.bind(
						int(owner.entity_id),str(item.slot)))
				unequip.custom_minimum_size.x=58
				var unequip_assessment:Dictionary=session.town_unequip_assessment(
					int(owner.entity_id),str(item.slot))
				unequip.disabled=not bool(unequip_assessment.get("accepted",false))
				unequip.tooltip_text=str(unequip_assessment.get("message",""))
			elif item.get("equip_slots",[]) is Array \
					and not item.get("equip_slots",[]).is_empty():
				var equip_slot:=str(item.equip_slots[0])
				var equip:=_add_button(line,"장착","TownEquip%s"%str(item.instance_id),
					_on_town_equip.bind(int(owner.entity_id),str(item.instance_id),equip_slot))
				equip.custom_minimum_size.x=58
				var equip_assessment:Dictionary=session.town_equip_assessment(
					int(owner.entity_id),str(item.instance_id),equip_slot)
				equip.disabled=not bool(equip_assessment.get("accepted",false))
				equip.tooltip_text=str(equip_assessment.get("message",""))
			for target in owners:
				if int(target.entity_id)==int(owner.entity_id):continue
				var move:=_add_button(line,"→%s"%str(target.display_name),
					"TownTransfer%sTo%d"%[str(item.instance_id),int(target.entity_id)],
					_on_town_transfer.bind(int(owner.entity_id),int(target.entity_id),
						str(item.instance_id)))
				move.custom_minimum_size.x=68
				var assessment:Dictionary=session.town_transfer_assessment(
					int(owner.entity_id),int(target.entity_id),str(item.instance_id))
				move.disabled=not bool(assessment.get("accepted",false))
				move.tooltip_text=str(assessment.get("message",""))


func _town_gate_panel()->void:
	var assessment:Dictionary=session.town_departure_assessment()
	var active_floors:Array=assessment.get("available_portal_floors",[])
	var portal_text:="없음" if active_floors.is_empty() else ", ".join(
		active_floors.map(func(value):return "%d층"%int(value)))
	_add_notice("[원정문] 1층은 지상 입구로 출발합니다. 활성화한 층 거점 포탈: %s"%portal_text,
		"TownGateTitle",FONT_BODY)
	var depart:=_add_button(deck,"1층 지상 입구로 출발","TownDepart",
		_on_town_depart.bind(1,"SURFACE_ENTRANCE"))
	depart.disabled=not bool(assessment.get("accepted",false))
	depart.tooltip_text=str(assessment.get("message",""))
	for floor_value in active_floors:
		var floor_index:=int(floor_value)
		var portal_assessment:Dictionary=session.town_departure_assessment(
			floor_index,"ANCHOR_PORTAL")
		var portal_depart:=_add_button(deck,"%d층 거점 포탈로 출발"%floor_index,
			"TownDepartPortal%d"%floor_index,
			_on_town_depart.bind(floor_index,"ANCHOR_PORTAL"))
		portal_depart.disabled=not bool(portal_assessment.get("accepted",false))
		portal_depart.tooltip_text=str(portal_assessment.get("message",""))


func _on_town_facility_selected(facility_id:String)->void:
	town_facility_id=facility_id;notice_text="";action_feedback_text=""
	if info_scroll!=null:info_scroll.scroll_vertical=0
	_request_refresh()


func _on_town_clinic_treat(entity_id:int)->void:
	var result:Dictionary=session.treat_town_clinic(entity_id)
	if bool(result.get("accepted",false)):
		notice_text="치료를 마쳤습니다.%s"%(
			" 절단된 부위는 회복되지 않습니다." \
			if bool(result.get("severed_parts_remain",false)) else "")
	else:notice_text=str(result.get("message","치료할 수 없습니다."))
	action_feedback_text=notice_text;_request_refresh()


func _on_town_shrine_rest(entity_id:int)->void:
	if session.town_life_enabled() and town_facility_id!="HOUSE":
		_on_town_life_command({"action":"REST","entity_id":str(entity_id)});return
	if session.scenario_id==SessionScript.DUO_SCENARIO_ID:
		var ordered:Dictionary=session.base_work({"action":"REST","entity_id":str(entity_id)})
		notice_text=str(ordered.get("message","휴식할 수 없습니다."))
		if bool(ordered.get("accepted",false)):
			town_facility_id="HOUSE" if session.town_life_enabled() else "BASE";selected_base_building_id="LODGE"
		action_feedback_text=notice_text;_request_refresh();return
	var result:Dictionary=session.rest_at_town_shrine(entity_id)
	notice_text="긴장을 %d만큼 낮췄습니다."%(
		int(result.get("stress_before",0))-int(result.get("stress_after",0))) \
		if bool(result.get("accepted",false)) else str(result.get("message","휴식할 수 없습니다."))
	action_feedback_text=notice_text;_request_refresh()


func _on_town_market_buy(definition_id:String)->void:
	var result:Dictionary=session.purchase_town_item(definition_id)
	notice_text="물품을 구입해 주인공 가방에 넣었습니다." \
		if bool(result.get("accepted",false)) else str(result.get("message","구입할 수 없습니다."))
	action_feedback_text=notice_text;_request_refresh()


func _on_town_market_sell(instance_id:String)->void:
	var result:Dictionary=session.sell_town_item(instance_id)
	notice_text="%s ×%d을(를) %d금화에 팔았습니다."%[str(result.get("definition_id","")),
		int(result.get("quantity",0)),int(result.get("gold_earned",0))] \
		if bool(result.get("accepted",false)) else str(result.get("message","판매할 수 없습니다."))
	action_feedback_text=notice_text;_request_refresh()


func _on_town_transfer(from_entity_id:int,to_entity_id:int,instance_id:String)->void:
	var result:Dictionary=session.transfer_town_item(from_entity_id,to_entity_id,instance_id)
	notice_text="아이템을 파티원에게 이전했습니다." \
		if bool(result.get("accepted",false)) else str(result.get("message","이전할 수 없습니다."))
	action_feedback_text=notice_text;_request_refresh()


func _on_town_equip(entity_id:int,instance_id:String,slot:String)->void:
	var result:Dictionary=session.equip_town_item(entity_id,instance_id,slot)
	notice_text="장비를 장착했습니다." if bool(result.get("accepted",false)) \
		else str(result.get("message","장착할 수 없습니다."))
	action_feedback_text=notice_text;_request_refresh()


func _on_town_unequip(entity_id:int,slot:String)->void:
	var result:Dictionary=session.unequip_town_item(entity_id,slot)
	notice_text="장비를 해제했습니다." if bool(result.get("accepted",false)) \
		else str(result.get("message","해제할 수 없습니다."))
	action_feedback_text=notice_text;_request_refresh()


func _on_town_depart(floor_index:int=1,
		entry_mode:String="SURFACE_ENTRANCE")->void:
	var result:Dictionary=session.depart_town(floor_index,entry_mode)
	if bool(result.get("accepted",false)):
		town_facility_id="GUILD";notice_text="원정대가 %d층으로 다시 출발했습니다."%floor_index
	else:notice_text=str(result.get("message","출발할 수 없습니다."))
	action_feedback_text=notice_text;_request_refresh()

func _add_recruitment_candidates()->void:
	if session==null or not session.has_method("recruitable_companions"):return
	_add_legacy_guild_tutorial()
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
		# but dungeon controls only expose the relationship-gated rescue story. The
		# town guild deliberately uses direct AVAILABLE rows as its stagecoach board.
		if rescue_state=="AVAILABLE" and str(status.get("view_mode",""))!="TOWN":continue
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
			label.text="%s · %s · %s\n%s · %s · %s"%[
				str(row.get("display_name","동료")),str(row.get("species_label","미상")),
				str(row.get("role_hint","범용 전투")),str(row.get("weapon_label","맨손")),
				str(row.get("fixed_trait_label","종족 특성")),
				str(row.get("style_label","동료"))]
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

func _add_legacy_guild_tutorial()->void:
	if session==null or not session.has_method("guild_tutorial_overview"):return
	var tutorial:Dictionary=session.guild_tutorial_overview()
	if not bool(tutorial.get("available",false)):return
	_add_notice("길드 튜토리얼 · 선택형 의뢰", "LegacyGuildTutorialTitle", FONT_KEY)
	var board:=VBoxContainer.new();board.name="LegacyGuildTutorial";board.add_theme_constant_override("separation",4);deck.add_child(board)
	for value in tutorial.get("quests",[]):
		if not value is Dictionary:continue
		var row:Dictionary=value;var quest_id:=str(row.get("quest_id",""))
		var line:=HBoxContainer.new();line.name="LegacyGuildQuest%s"%quest_id;line.add_theme_constant_override("separation",6);board.add_child(line)
		var progress:Dictionary=row.get("progress",{}) if row.get("progress",{}) is Dictionary else {}
		var text:=Label.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		text.text="%s · %s\n%s · %s"%[str(row.get("title","의뢰")),str(row.get("status","AVAILABLE")),str(row.get("description","")),_legacy_guild_progress(row,progress)]
		line.add_child(text)
		if bool(row.get("can_accept",false)):
			var accept:=_add_button(line,"수락","LegacyGuildAccept%s"%quest_id,_on_legacy_guild_tutorial_command.bind("ACCEPT",quest_id))
			accept.custom_minimum_size=Vector2(80,TOUCH_TARGET)
		if quest_id=="GUILD_TUTORIAL_HEAL" and bool(row.get("accepted",false)) and not bool(row.get("completed",false)) and not bool(row.get("support_granted",false)):
			var support:=_add_button(line,"지원 물약","LegacyGuildSupport%s"%quest_id,_on_legacy_guild_tutorial_command.bind("SUPPORT",quest_id))
			support.custom_minimum_size=Vector2(96,TOUCH_TARGET)
		if bool(row.get("can_claim",false)):
			var claim:=_add_button(line,"보상","LegacyGuildClaim%s"%quest_id,_on_legacy_guild_tutorial_command.bind("CLAIM",quest_id))
			claim.custom_minimum_size=Vector2(80,TOUCH_TARGET)

func _legacy_guild_progress(row:Dictionary,progress:Dictionary)->String:
	var quest_id:=str(row.get("quest_id",""))
	if quest_id=="GUILD_TUTORIAL_MOVE":return "이동 %d/3 · 대각선 %s"%[int(progress.get("count",0)),"완료" if bool(progress.get("diagonal",false)) else "필요"]
	if quest_id=="GUILD_TUTORIAL_GUARD":return "방어 %s · 공격 %s"%["완료" if bool(progress.get("hold_done",false)) else "필요","완료" if bool(progress.get("attack_done",false)) else "필요"]
	return "진행 %d/1"%int(progress.get("count",0))

func _on_legacy_guild_tutorial_command(action:String,quest_id:String)->void:
	var result:Dictionary=session.guild_tutorial_command({"action":action,"quest_id":quest_id})
	notice_text=str(result.get("message","길드 의뢰를 처리하지 못했습니다."));action_feedback_text=notice_text;_request_refresh()

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
	DarkPixelSkinScript.apply_action_button(party_command_menu,DarkPixelSkinScript.CYAN)
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

func _product_controls_metrics(_party_count:int)->Dictionary:
	# Movement and pickup remain map touches. The dock keeps the four frequent
	# context commands visible under the portrait strip.
	var gap:=3 if size.x>=450.0 else 2
	return {"target":48,"gap":gap,"dock_height":48}.duplicate(true)

func _build_product_controls_dock(status:Dictionary)->void:
	if companion_order_editor!=null and companion_order_editor.visible:
		product_auto_button=null;product_interact_button=null;product_attack_button=null
		product_wait_guard_button=null;product_execute_button=null;product_bag_button=null
		product_rest_button=null;product_pickup_button=null;product_tactics_button=null
		action_feedback_label.visible=false
		combat_action_dock.visible=false;combat_action_area.visible=true
		return
	product_bag_button=null;product_rest_button=null;product_pickup_button=null;product_tactics_button=null
	product_auto_button=null;product_interact_button=null
	product_attack_button=null;product_wait_guard_button=null;product_execute_button=null
	combat_action_area.visible=true;action_feedback_label.visible=false
	combat_action_dock.visible=true;combat_action_area.add_theme_constant_override("separation",0)
	var members:Variant=status.get("party_member_ids",[])
	var party_count:int=members.size() if members is Array else 1
	var metrics:=_product_controls_metrics(party_count)
	var gap:=int(metrics.gap);var dock_height:=int(metrics.dock_height)
	combat_action_area.custom_minimum_size.y=dock_height
	combat_action_dock.custom_minimum_size.y=dock_height
	combat_action_dock.add_theme_constant_override("separation",gap)
	if bool(_current_run_progress().get("terminal",false)):
		product_execute_button=_add_product_context_button(combat_action_dock,
			"[RESTART]","ProductExecute",_on_product_execute,int(metrics.target))
		product_execute_button.disabled=false
		product_execute_button.tooltip_text="같은 원정을 처음부터 다시 시작"
		return
	# One fixed dock, the same in exploration and in a fight:
	# [공격] [대기] [휴식] [탐험] [줍기] [전술] [가방] + the contextual interaction.
	# Eight 44px+ touch targets must fit the narrowest phone width; the gap
	# shrinks before the targets do.
	if 8.0*44.0+float(gap)*7.0>size.x:gap=1;combat_action_dock.add_theme_constant_override("separation",gap)
	var target:=clampi(int(floor((size.x-float(gap)*7.0)/8.0)),44,int(metrics.target))
	product_attack_button=_add_product_context_button(combat_action_dock,"[공격]","ProductAttack",
		_on_product_attack_any,target)
	product_wait_guard_button=_add_product_context_button(combat_action_dock,"[대기]",
		"ProductWaitGuard",_on_product_wait_guard,target)
	product_rest_button=_add_product_context_button(combat_action_dock,"[휴식]","ProductRest",
		_on_product_rest,target)
	product_auto_button=_add_product_context_button(combat_action_dock,"[탐험]","ProductAuto",
		_on_product_auto,target)
	product_pickup_button=_add_product_context_button(combat_action_dock,"[줍기]","ProductPickup",
		_on_product_pickup,target)
	product_tactics_button=_add_product_context_button(combat_action_dock,"[전술]","ProductTactics",
		_on_product_tactics,target)
	product_bag_button=_add_product_context_button(combat_action_dock,"가방","ProductBag",
		_open_hero_detail_tab.bind("ITEM"),target)
	product_interact_button=_add_product_context_button(combat_action_dock,"[INTERACT]","ProductInteract",
		_on_product_interact,target)
	product_interact_button.tooltip_text="인접한 인물이나 사물과 상호작용합니다."
	_sync_product_control_state(status)

func _sync_product_control_state(status_override:Dictionary={}) -> void:
	if session==null:return
	var run_terminal:=bool(_current_run_progress().get("terminal",false))
	if product_auto_button==null or not is_instance_valid(product_auto_button):
		if run_terminal and product_execute_button!=null and is_instance_valid(product_execute_button):
			product_execute_button.text="[RESTART]";product_execute_button.disabled=false
		return
	var status:Dictionary=status_override if not status_override.is_empty() else session.party_status()
	var mode:=str(status.get("view_mode",""))
	var terminal:=bool(status.get("terminal",false)) or run_terminal
	if terminal:_product_attack_targeting=false
	var equipment:Dictionary=session.protagonist_equipment() \
		if session.has_method("protagonist_equipment") else {}
	var protagonist_id:=int(status.get("protagonist_id",-1))
	var duo_fight:bool=_portrait_battle_controls_visible()
	var world=session.sim.world
	var enemy_in_view:=false
	for id_value in status.get("enemies_in_view",status.get("visible_enemy_ids",[])):
		if world.is_autonomous_target(int(id_value)):enemy_in_view=true;break
	# [공격]: same button always; it explains itself when nothing is in reach.
	product_attack_button.disabled=terminal or mode=="TOWN"
	product_attack_button.tooltip_text="가장 가까운 적을 공격합니다. 사거리 밖이면 한 칸 다가갑니다." \
		if enemy_in_view else "시야 안에 적이 없습니다."
	# [대기]: one turn. In a fight it is a guard, otherwise a plain wait.
	product_wait_guard_button.disabled=terminal or mode=="TOWN"
	if duo_fight:product_wait_guard_button.tooltip_text="이번 차례는 자리를 지킵니다."
	elif mode=="COMBAT":
		var guard_actor:=selected_member_id if selected_member_id>0 else protagonist_id
		product_wait_guard_button.tooltip_text="200 시간 동안 물리 피해를 %d%% 줄입니다." \
			%_guard_percent_for_actor(guard_actor)
	else:product_wait_guard_button.tooltip_text="현재 위치에서 한 턴 대기합니다."
	# [휴식]: rest until full; refused with a reason while enemies are near.
	product_rest_button.text="[STOP]" if _product_rest_active else "[휴식]"
	product_rest_button.disabled=terminal or mode=="TOWN"
	product_rest_button.tooltip_text="휴식을 멈춥니다." if _product_rest_active \
		else "HP가 다 찰 때까지 쉽니다. 적이 보이거나 피해를 입으면 멈춥니다."
	# [줍기]: always in place, enabled when loot is underfoot.
	var loot_here:int=session.ground_items_at_protagonist().size() if mode!="TOWN" else 0
	product_pickup_button.disabled=terminal or loot_here==0
	product_pickup_button.tooltip_text="이 칸의 아이템 %d개를 모두 줍습니다."%loot_here if loot_here>0 \
		else "발밑에 주울 것이 없습니다."
	# [전술]: party directives (focus, retreat, hold, cease, free). Always in
	# place; the menu explains itself when there is no fight to direct.
	product_tactics_button.disabled=terminal or mode=="TOWN"
	var current_tactic:=str(PartyCommandScript.effective(world,world.party_encounter).get("command_id","FOLLOW")) \
		if duo_fight or session.field_turns_active() else "FOLLOW"
	product_tactics_button.text="[전술 · 후퇴]" if _retreat_active and duo_fight else "[전술]"
	product_tactics_button.tooltip_text="파티 전술: %s"%str({"ATTACK_TARGET":"집중 공격","RETREAT":"후퇴",
		"STOP_ATTACK":"공격 중지","HOLD_POSITION":"자리 지키기","FOLLOW":"따라오기"}.get(current_tactic,"따라오기"))
	# [탐험]: auto explore toggle; the opening event borrows it for the potion.
	var opening:Dictionary=session.opening_event_status() \
		if session.has_method("opening_event_status") else {}
	var opening_choice:=bool(opening.get("can_interact",false))
	var anchor_portal:Dictionary=session.dungeon_anchor_portal_status() \
		if session.has_method("dungeon_anchor_portal_status") else {}
	var portal_choice:=bool(anchor_portal.get("can_activate",false))
	var floor_transition:Dictionary=session.floor_transition_assessment() \
		if session.has_method("floor_transition_assessment") else {}
	var auto_state:Dictionary=session.auto_explore_state() if session.has_method("auto_explore_state") else {}
	if opening_choice:
		if event_label!=null:
			event_label.text=str(opening.get("scene_summary",
				"부상당한 여행자가 벽에 기대 숨을 몰아쉬고 있습니다."))
		product_auto_button.toggle_mode=false;product_auto_button.set_pressed_no_signal(false)
		product_auto_button.text="[물약 주기]"
		product_auto_button.disabled=not bool(opening.get("give_enabled",false))
		product_auto_button.tooltip_text="회복 물약 1개를 건네 실제 체력을 회복시킵니다."
	else:
		product_auto_button.toggle_mode=true
		product_auto_button.set_pressed_no_signal(bool(auto_state.get("running",false)))
		product_auto_button.text="[탐험 ■]" if bool(auto_state.get("running",false)) else "[탐험]"
		product_auto_button.disabled=terminal or mode=="TOWN" or not session.has_method("start_auto_explore")
		product_auto_button.tooltip_text="출구 쪽 미탐색 지역으로 자동 탐험" if not duo_fight \
			else "적이 보이는 동안은 자동 탐험이 멈춥니다."
	# Contextual interaction: only when there is one.
	product_interact_button.disabled=true;product_interact_button.text="[INTERACT]"
	if bool(floor_transition.get("accepted",false)):
		product_interact_button.text="[%d층 진입]"%int(floor_transition.get("to_floor_index",2))
		product_interact_button.disabled=false
		product_interact_button.tooltip_text="층간 포탈을 사용해 다음 층으로 이동합니다."
	elif portal_choice:
		product_interact_button.text="[PORTAL 활성화]"
		product_interact_button.disabled=false
		product_interact_button.tooltip_text="이 층의 거점 포탈을 마을과 연결합니다."
	elif opening_choice:
		product_interact_button.text="[돕지 않기]"
		product_interact_button.disabled=not bool(opening.get("pass_enabled",false))
		product_interact_button.tooltip_text="여행자를 돕지 않고 원정을 계속합니다."
	elif mode=="EXPLORATION" and not session.battle_loot().rows.is_empty():
		product_interact_button.text="전리품";product_interact_button.disabled=false
		product_interact_button.tooltip_text="지난 전투에서 남겨둔 전리품을 확인합니다."
	elif bool(equipment.get("reload_required",false)):
		product_interact_button.text="[RELOAD]"
		product_interact_button.disabled=terminal or not bool(equipment.get("can_reload",false))
		product_interact_button.tooltip_text="쇠뇌가 장전되어 있습니다." if bool(equipment.get("loaded",false)) \
			else "쇠뇌를 장전합니다. 볼트 %d개 · %d시간"%[int(equipment.get("bolts",0)),int(equipment.get("reload_time",0))]
	product_interact_button.visible=not (product_interact_button.disabled \
		and product_interact_button.text=="[INTERACT]")

func _add_product_context_button(parent:Control,label:String,node_name:String,
		_callback:Callable,target:int)->Button:
	var button:Button=preload("res://playtest/illustrated_action_button.gd").new();button.name=node_name;button.text=label
	button.custom_minimum_size=Vector2(target,target)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size",12)
	button.clip_text=true
	button.focus_mode=Control.FOCUS_NONE;button.set_meta("product_control",true)
	button.gui_input.connect(_on_product_button_gui_input.bind(node_name))
	var accent:Color={"ProductAttack":Color("#548bb0"),"ProductAuto":Color("#61914e"),
		"ProductWaitGuard":Color("#ba913d"),"ProductRest":Color("#5f8a66"),"ProductPickup":Color("#c6a34c"),"ProductBag":Color("#a64e49"),"ProductTactics":Color("#8a5f66")}.get(node_name,DarkPixelSkinScript.CYAN)
	DarkPixelSkinScript.apply_action_button(button,accent)
	parent.add_child(button)
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

func _reserve_battle_move(actor_id:int,goal:Vector2i)->void:
	# A companion fight keeps the shared exploration screen, so the hero stays
	# tap-movable: the tap becomes a journaled position order on the action
	# timeline (walk there, then hold) instead of an exploration step.
	if not str(session.party_status().get("safe_phase",""))=="ENGAGED":return
	var result:Dictionary=session.individual_battle.reserve_move(actor_id,goal)
	var message:=str(result.get("message","이동을 지정할 수 없습니다."))
	_show_manual_battle_feedback(message)
	if bool(result.get("accepted",false)):
		notice_text=message;action_feedback_text=message
		if actor_id==int(session.party_status().get("protagonist_id",-1)):_hero_turn_released=true
	_refresh_battle_surface_lightly()

func _on_product_direction(direction:Vector2i)->void:
	if session!=null and session.is_duo_autobattle() and str(session.party_status().get("safe_phase",""))=="ENGAGED":
		if direction!=Vector2i.ZERO:
			var engaged:Dictionary=session.party_status()
			_reserve_battle_move(int(engaged.protagonist_id),Vector2i(int(engaged.protagonist_position[0]),
				int(engaged.protagonist_position[1]))+direction)
		return
	var status:Dictionary=session.party_status()
	# Inspection selection is not the controllable actor in the automatic party UI.
	if auto_orchestration_enabled:selected_member_id=int(status.get("protagonist_id",-1))
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
				# Tab already resolved this to one adjacent step. Going through the
				# arbitrary map-cell route path previewed the same move twice.
				var origin:=Vector2i(int(status.protagonist_position[0]),
					int(status.protagonist_position[1]))
				_on_explore(destination-origin)
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
	pending_ground_pickup_id="";pending_ground_pickup_label=""
	_pickup_everything_here()
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
		if bool(choice_result.get("accepted",false)) \
				and bool(choice_result.get("immediate_recruitment",{}).get("joined",false)):
			_show_product_command_feedback("물약을 건넸습니다. 여행자가 바로 파티에 합류했습니다.")
		# Giving the potion is a complete one-shot interaction. The same control is
		# labelled AUTO after the HUD refresh, but this released touch must never be
		# reinterpreted as a request to begin walking.
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
			"auto_explore_no_frontier":"도달 가능한 미방문 안전 지점을 모두 탐험했습니다.",
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
	if member_detail_modal.visible:
		_schedule_product_auto_explore(Time.get_ticks_msec());return
	if record_modal.visible or map_overlay.visible \
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
	if product_interact_button!=null and product_interact_button.text=="전리품":
		_maybe_open_battle_loot(true);return
	var status:Dictionary=session.party_status()
	if session.has_method("floor_transition_assessment"):
		var floor_transition:Dictionary=session.floor_transition_assessment()
		if bool(floor_transition.get("accepted",false)):
			_cancel_product_auto_explore("auto_explore_floor_transition",false)
			var transition_result:Dictionary=session.advance_campaign_floor()
			_record_result(transition_result,true)
			_show_product_command_feedback("%d층에 진입했습니다."%int(
				floor_transition.get("to_floor_index",2)) if bool(
				transition_result.get("accepted",false)) else str(
				transition_result.get("message","다음 층으로 이동할 수 없습니다.")))
			_request_refresh();return
	if str(status.get("view_mode",""))=="COMBAT" \
			and session.has_method("protagonist_equipment"):
		var equipment:Dictionary=session.protagonist_equipment()
		if bool(equipment.get("reload_required",false)):
			var reload_result:Dictionary=session.reload_protagonist_weapon()
			var reload_feedback:="쇠뇌를 재장전했습니다." \
				if bool(reload_result.get("accepted",false)) \
				else str(reload_result.get("message","재장전할 수 없습니다."))
			var after_status:Dictionary=session.party_status()
			# Reload mutates only item runtime state. Keep the live solo-combat shell
			# instead of rebuilding and potentially replacing the active session UI.
			if _is_direct_solo_combat(status) and _is_direct_solo_combat(after_status):
				_refresh_direct_solo_combat_surface(after_status)
			else:
				_sync_product_control_state(after_status);_request_refresh()
			_show_product_command_feedback(reload_feedback);return
	if session.has_method("dungeon_anchor_portal_status"):
		var portal_status:Dictionary=session.dungeon_anchor_portal_status()
		if bool(portal_status.get("can_activate",false)):
			_cancel_product_auto_explore("auto_explore_interaction_discovered",false)
			var portal_result:Dictionary=session.activate_dungeon_anchor_portal()
			_record_result(portal_result,true)
			_show_product_command_feedback("%d층 거점 포탈을 활성화했습니다."%int(
				portal_status.get("floor_index",1)) if bool(portal_result.get(
					"accepted",false)) else str(portal_result.get("message",
					"포탈을 활성화할 수 없습니다.")))
			_request_refresh();return
	if session.has_method("opening_event_status") \
			and bool(session.opening_event_status().get("can_interact",false)):
		_cancel_product_auto_explore("auto_explore_interaction_discovered",false)
		var result:Dictionary=session.commit_opening_event_choice("PASS")
		_record_result(result,true)
		_show_product_command_feedback("여행자를 돕지 않기로 했습니다." \
			if bool(result.get("accepted",false)) else str(result.get("message","선택할 수 없습니다.")))
		_request_refresh();return

func _on_product_rest()->void:
	if _product_rest_active:_cancel_product_rest("rest_user_stop");return
	var status:Dictionary=session.party_status()
	if str(status.get("view_mode",""))!="EXPLORATION" or bool(status.get("terminal",false)):return
	if not _rest_needed():
		notice_text="이미 충분히 회복했습니다.";action_feedback_text=notice_text;_request_refresh();return
	_cancel_product_auto_explore("auto_explore_user_command",false)
	var active_route:Dictionary=session.exploration_route_state()
	if bool(active_route.get("active",false)) or bool(active_route.get("has_preview",false)):
		_cancel_active_route()
	_product_rest_active=true;_product_rest_generation+=1
	_product_rest_started_time=session.sim.world.world_time
	_product_rest_due_msec=Time.get_ticks_msec()
	_product_rest_last_health=_party_health_total();_product_rest_idle_waits=0
	notice_text="휴식 중 · 파티 HP·MP가 다 차면 멈춥니다";action_feedback_text=notice_text
	_request_refresh()

func _rest_needed()->bool:
	var world=session.sim.world
	for id in world.party_encounter.active_party_member_ids:
		var entity=world.entities.get(int(id))
		var member=world.party_encounter.member(int(id))
		if entity!=null and world.can_act(int(id),world.world_time) and member.presence=="DEPLOYED" \
				and (int(entity.health)<int(entity.max_health) or member.energy<member.max_energy):return true
	return false

func _party_health_total()->int:
	var total:=0;var world=session.sim.world
	for id in world.party_encounter.active_party_member_ids:
		var entity=world.entities.get(int(id))
		if entity!=null:total+=int(entity.health)
	return total

func _party_energy_total()->int:
	var total:=0
	for id in session.sim.world.party_encounter.active_party_member_ids:
		total+=int(session.sim.world.party_encounter.member(id).energy)
	return total

func _rest_block_detail()->String:
	var world=session.sim.world
	for id in world.party_encounter.active_party_member_ids:
		var member=world.party_encounter.member(id)
		if member.presence!="DEPLOYED" or not world.can_act(id,world.world_time):continue
		var exposure=session.sim.evaluate_exposure_for_entity(id,world.entities[id].position)
		if exposure!=null and exposure.evaluation!=null and exposure.evaluation.total_risk>0:
			var risks:Array[String]=[]
			if exposure.evaluation.fire_score>0:risks.append("불")
			if exposure.evaluation.water_score>0:risks.append("물·젖은 바닥")
			if exposure.evaluation.poison_score>0:risks.append("연기·가스")
			if exposure.evaluation.electric_score>0:risks.append("전기")
			return _entity_display_name(id)+" 주변 "+" / ".join(risks)+" · 파티 전원이 안전한 곳으로 이동하세요"
	return "경계 중인 적이나 상태이상을 확인하세요"

func _continue_product_rest(expected_generation:int)->void:
	if not _product_rest_active or expected_generation!=_product_rest_generation:return
	var status:Dictionary=session.party_status()
	var stop_reason:=""
	if not session.field_turns_active() and str(status.get("safe_phase","")) in ["CONTACT","ENGAGED"]:stop_reason="rest_encounter"
	elif str(status.get("view_mode",""))!="EXPLORATION" or bool(status.get("terminal",false)):stop_reason="rest_interrupted"
	elif not (status.get("visible_enemy_ids",[]) as Array).is_empty():stop_reason="rest_enemy_sighted"
	elif str(status.get("ration_band",""))=="STARVING":stop_reason="rest_starving"
	elif not _rest_needed():stop_reason="rest_complete"
	if stop_reason.is_empty():
		var before:int=_party_health_total()
		var energy_before:=_party_energy_total()
		var result:Dictionary=session.commit_exploration_direction(Vector2i.ZERO)
		if not bool(result.get("accepted",false)):
			_cancel_product_rest("rest_interrupted")
			notice_text="휴식 중단 · "+str(result.get("message",result.get("reason","행동 실패")))
			action_feedback_text=notice_text;_product_auto_stop_feedback=notice_text;_request_refresh();return
		else:
			_record_result(result,true)
			var after:int=_party_health_total()
			if after<before:stop_reason="rest_damaged"
			elif after>before or _party_energy_total()>energy_before:_product_rest_idle_waits=0
			else:
				# Safe recovery pauses while any enemy is alert or the tile is risky;
				# waiting forever there is not resting.
				_product_rest_idle_waits+=1
				if _product_rest_idle_waits>=PRODUCT_REST_IDLE_LIMIT:stop_reason="rest_no_progress"
	if not stop_reason.is_empty():
		_cancel_product_rest(stop_reason);return
	_product_rest_due_msec=Time.get_ticks_msec()+PRODUCT_REST_CADENCE_MSEC
	var world=session.sim.world;var hero=world.entities.get(int(status.protagonist_id))
	if hero!=null:
		var member=session.sim.world.party_encounter.member(int(status.protagonist_id))
		notice_text="휴식 %d시간 · HP %d/%d · MP %d/%d"%[world.world_time-_product_rest_started_time,int(hero.health),int(hero.max_health),member.energy,member.max_energy]
		action_feedback_text=notice_text
	_refresh_continuous_exploration_surface(session.party_status())

func _cancel_product_rest(reason:String)->void:
	if not _product_rest_active:return
	_product_rest_active=false;_product_rest_generation+=1;_product_rest_due_msec=-1
	notice_text={"rest_complete":"휴식 완료 · 파티 HP·MP가 다 찼습니다","rest_enemy_sighted":"적이 보여 휴식을 멈췄습니다",
		"rest_damaged":"피해를 입어 휴식을 멈췄습니다","rest_starving":"굶주려서 쉴 수 없습니다",
		"rest_no_progress":"휴식해도 회복되지 않습니다 · 경계 중인 적이 있거나 위험한 자리입니다",
		"rest_encounter":"적이 나타나 휴식을 멈췄습니다",
		"rest_user_stop":"휴식을 멈췄습니다"}.get(reason,"휴식을 멈췄습니다")
	if reason=="rest_no_progress":notice_text="HP·MP 회복 중단 · "+_rest_block_detail()
	action_feedback_text=notice_text
	_product_auto_stop_feedback=notice_text
	_request_refresh()

func _on_product_wait_guard()->void:
	var status:Dictionary=session.party_status()
	_retreat_active=false
	if str(status.get("view_mode",""))=="EXPLORATION":
		_cancel_product_auto_explore("auto_explore_user_command",false)
		var active_route:Dictionary=session.exploration_route_state()
		if bool(active_route.get("active",false)) or bool(active_route.get("has_preview",false)):
			_cancel_active_route()
		_on_explore(Vector2i.ZERO)
	elif _portrait_battle_controls_visible():
		var hero_id:=int(status.get("protagonist_id",-1))
		var held:Dictionary=session.individual_battle.reserve_hold(hero_id)
		if not bool(held.get("accepted",false)):
			_show_product_command_feedback(str(held.get("message","지금은 대기할 수 없습니다.")));return
		autonomous_battle_clock.paused=false
		_release_hero_turn("이번 차례 · 대기")
	elif str(status.get("view_mode",""))=="COMBAT":_on_actor_hold()

func _build_product_tactics_popup()->void:
	product_tactics_popup=PopupMenu.new();product_tactics_popup.name="ProductTacticsPopup"
	for row in [[0,"동료 · 공격 대상 지정"],[1,"동료 · 후퇴"],[2,"동료 · 자리 지키기"],[3,"동료 · 공격 중지"],[4,"동료 · 따라오기"]]:
		product_tactics_popup.add_item(str(row[1]),int(row[0]))
	for row in [[10,"탐험 대형 · 자유"],[11,"탐험 대형 · 종대"],[12,"탐험 대형 · 횡대"],[13,"탐험 대형 · 쐐기"]]:
		product_tactics_popup.add_item(str(row[1]),int(row[0]))
	product_tactics_popup.id_pressed.connect(_on_product_tactic_selected)
	add_child(product_tactics_popup)

func _on_product_tactics()->void:
	# [전술]: one menu for the party directives. Items that need a fight are
	# disabled outside one instead of the button changing.
	if product_tactics_popup==null or product_tactics_button==null:return
	var fighting:bool=session.field_turns_active() or _portrait_battle_controls_visible()
	var current:=str(PartyCommandScript.effective(session.sim.world,
		session.sim.world.party_encounter).get("command_id","FOLLOW")) if fighting else ""
	var ids:={0:"ATTACK_TARGET",1:"RETREAT",2:"HOLD_POSITION",3:"STOP_ATTACK",4:"FOLLOW"}
	for index in range(product_tactics_popup.item_count):
		var item_id:=product_tactics_popup.get_item_id(index)
		product_tactics_popup.set_item_disabled(index,not fighting)
		product_tactics_popup.set_item_as_checkable(index,true)
		product_tactics_popup.set_item_checked(index,fighting and str(ids.get(item_id,""))==current)
		if item_id>=10:
			product_tactics_popup.set_item_disabled(index,not session.field_turns_active())
			product_tactics_popup.set_item_checked(index,session.field_turns_active() and \
				str({10:"NONE",11:"COLUMN",12:"LINE",13:"WEDGE"}.get(item_id,""))==session.FieldRules.formation(session.sim.world))
	if not fighting:_show_product_command_feedback("쫓아오는 적이 없어 지금은 전술이 필요 없습니다.")
	var anchor:Rect2=product_tactics_button.get_global_rect()
	var popup_size:Vector2=product_tactics_popup.get_contents_minimum_size()
	product_tactics_popup.position=Vector2i(int(anchor.position.x),int(anchor.position.y-popup_size.y-4.0))
	product_tactics_popup.popup()

func _on_product_tactic_selected(item_id:int)->void:
	if session==null:return
	if item_id>=10:
		var formation:String=str({10:"NONE",11:"COLUMN",12:"LINE",13:"WEDGE"}.get(item_id,""))
		var result:Dictionary=session.set_exploration_formation(formation)
		_record_result(result,false,"대형 설정 불가")
		if result.accepted:_show_product_command_feedback("탐험 대형 · "+str(session.FieldRules.FORMATIONS[formation]))
		_request_refresh();return
	if not session.field_turns_active() and not _portrait_battle_controls_visible():return
	if item_id==0:
		_party_command_targeting=true
		_show_product_command_feedback("집중 공격할 적을 누르세요.");_request_refresh();return
	if item_id==1:_on_product_retreat();return
	var command_id:String=str({2:"HOLD_POSITION",3:"STOP_ATTACK",4:"FOLLOW"}.get(item_id,""))
	if command_id.is_empty():return
	_retreat_active=false;_party_command_targeting=false
	var result:Dictionary=session.issue_party_command(command_id)
	if not bool(result.get("accepted",false)):
		_show_product_command_feedback(str(result.get("message",result.get("reason","전술을 적용할 수 없습니다."))));return
	autonomous_battle_clock.paused=false
	_release_hero_turn("파티 전술 · %s"%str(result.get("command_label",command_id)))
	_request_refresh()

func _on_product_retreat()->void:
	if not session.field_turns_active() and not _portrait_battle_controls_visible():
		_show_product_command_feedback("전투 중에만 퇴각할 수 있습니다.");return
	var result:Dictionary=session.party_retreat()
	if not bool(result.get("accepted",false)):
		_show_product_command_feedback(str(result.get("message",result.get("reason","퇴각할 수 없습니다."))));return
	_retreat_active=true;autonomous_battle_clock.paused=false
	_cancel_battle_targeting()
	_release_hero_turn(str(result.get("message","퇴각")))
	_request_refresh()

func _on_product_attack_any()->void:
	# [공격], exploration or fight alike: attack the nearest visible enemy if
	# adjacent (a first strike before contact), otherwise take one step toward
	# it. Movement and the attack stay separate taps.
	var status:Dictionary=session.party_status()
	if bool(status.get("terminal",false)) or str(status.get("view_mode",""))=="TOWN":return
	if session.field_turns_active():_on_product_attack();return
	if not session.is_duo_autobattle():_on_product_attack();return
	var hero_id:=int(status.get("protagonist_id",-1))
	var hero_position:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
	var world=session.sim.world
	var nearest:=-1;var nearest_distance:=9999
	for id_value in status.get("enemies_in_view",status.get("visible_enemy_ids",[])):
		var id:=int(id_value)
		# Downed bodies are still "unresolved" but cannot be attacked; skip them.
		if not world.entities.has(id) or not world.is_autonomous_target(id):continue
		var enemy_position:Vector2i=world.entities[id].position
		var distance:=maxi(absi(enemy_position.x-hero_position.x),absi(enemy_position.y-hero_position.y))
		if distance<nearest_distance or distance==nearest_distance and id<nearest:
			nearest=id;nearest_distance=distance
	if nearest<0:_show_product_command_feedback("시야 안에 적이 없습니다.");return
	_retreat_active=false
	if nearest_distance<=1:_strike_visible_enemy(nearest);return
	# One step: the legal neighbour that gets closest to the enemy. The hero's
	# own cooldown may still be running, so this never goes through the
	# pathfinder's can_act gate; the movement assessment is the authority.
	var enemy_position:Vector2i=world.entities[nearest].position
	var best_step:=Vector2i(-1,-1);var best_score:=nearest_distance*10
	for direction in [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1)]:
		var cell:Vector2i=hero_position+direction
		if not world.in_bounds(cell):continue
		var assessment:Dictionary=session.individual_battle.movement_assessment(hero_id,cell) \
			if _portrait_battle_controls_visible() else session.preview_exploration(CommandScript.move_to(hero_id,cell))
		if not bool(assessment.get("accepted",false)):continue
		var score:int=maxi(absi(enemy_position.x-cell.x),absi(enemy_position.y-cell.y))*10 \
			+(1 if direction.x!=0 and direction.y!=0 else 0)
		if score<best_score:best_score=score;best_step=cell
	if best_step==Vector2i(-1,-1):
		_show_product_command_feedback("적에게 다가갈 길이 없습니다.");return
	if not _portrait_battle_controls_visible():
		# Exploration: one ordinary step toward the enemy.
		_cancel_product_auto_explore("auto_explore_user_command",false)
		var active_route:Dictionary=session.exploration_route_state()
		if bool(active_route.get("active",false)) or bool(active_route.get("has_preview",false)):
			_cancel_active_route()
		_on_explore(best_step-hero_position);return
	autonomous_battle_clock.paused=false
	_approach_step_pending=true
	_reserve_battle_move(hero_id,best_step)

func _strike_visible_enemy(entity_id:int)->void:
	# Map tap on an enemy: attack if adjacent (first strike before contact),
	# otherwise explain. Never walks for the player.
	_retreat_active=false;_approach_step_pending=false
	var result:Dictionary=session.strike_enemy(entity_id)
	if session.field_turns_active():
		_record_result(result,true,"공격할 수 없습니다.")
		_request_refresh();return
	if bool(result.get("accepted",false)):
		selected_target_id=entity_id
		autonomous_battle_clock.paused=false
		_hero_turn_released=true
		grid.set_selection(selected_member_id,entity_id);grid.set_actor_emphasis(entity_id,1400)
		_show_manual_battle_feedback(str(result.get("message","공격")))
		_request_refresh()
	else:
		var detail:=str(result.get("reason_details",{}).get("detail","")) \
			if result.get("reason_details",{}) is Dictionary else ""
		_show_manual_battle_feedback(str(result.get("message",result.get("reason","공격할 수 없습니다.")))
			+(" ("+detail+")" if not detail.is_empty() else ""))
		_request_refresh()

func _on_product_execute()->void:
	if session!=null and session.is_duo_autobattle() and str(session.party_status().get("safe_phase",""))=="ENGAGED":
		if battle_mode=="HERO_TURN":
			autonomous_battle_clock.paused=false
			_release_hero_turn("이번 차례 · 자동 행동");return
		autonomous_battle_clock.paused=not autonomous_battle_clock.paused
		if not autonomous_battle_clock.paused:battle_command_flow.resume()
		autonomous_battle_clock.remaining=autonomous_battle_clock.INTERVAL
		_request_refresh();return
	if bool(_current_run_progress().get("terminal",false)):
		_on_restart_same_run();return
	if session.has_method("floor_transition_assessment") \
			and bool(session.floor_transition_assessment().get("accepted",false)):
		_on_product_interact();return
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
	if session.field_turns_active():
		_switch_field_member(member_id);return
	var view_mode:=str(session.party_status().get("view_mode",""))
	selected_member_id=member_id;selected_target_id=-1;notice_text="%s 선택"%display_name
	action_feedback_text="판단 관찰 · 전투 입력은 주인공 행동으로 처리됩니다." \
		if auto_orchestration_enabled and view_mode=="COMBAT" \
			and member_id!=int(session.party_status().get("protagonist_id",-1)) \
		else "%s 선택 · 행동을 지정하세요."%display_name
	if view_mode=="COMBAT":_clear_move_preview()
	_request_refresh()

func _on_compact_member_card_pressed(member_id:int,_display_name:String)->void:
	if not _battle_target_mode.is_empty():
		_commit_battle_target(member_id)
		return
	if session.field_turns_active():
		_switch_field_member(member_id);return
	_open_member_detail(member_id)

func _switch_field_member(member_id:int)->void:
	_cancel_product_rest("rest_user_stop")
	_cancel_product_auto_explore("auto_explore_user_command",false)
	if bool(session.exploration_route_state().get("has_preview",false)):_cancel_active_route()
	var result:Dictionary=session.select_field_actor(member_id)
	_record_result(result,false,"조작 전환 불가")
	if result.accepted:
		selected_member_id=member_id;selected_target_id=-1
		_clear_move_preview()
		_show_product_command_feedback("직접 조작 · "+_entity_display_name(member_id))
	_request_refresh()

func _on_member_card_gui_input(event:InputEvent,member_id:int,_display_name:String,button:Button)->void:
	var pressed:=false;var native_double:=false;var local_position:=Vector2.ZERO
	if event is InputEventScreenTouch:
		pressed=event.pressed;native_double=event.double_tap;local_position=event.position
	elif event is InputEventMouseButton:
		if event.device==InputEvent.DEVICE_ID_EMULATION:
			button.accept_event();return
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
	if member_id==_direct_card_touch_id and Time.get_ticks_msec()-_direct_card_touch_msec \
			<=PRODUCT_EMULATED_MOUSE_SUPPRESS_MSEC:
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
	var talent:Dictionary=detail.get("personal_talent",{})
	if not talent.is_empty():
		var talent_label:=_card_label("재능 · %s\n%s"%[
			str(talent.label),str(talent.description)],"StatusPersonalTalent",FONT_AUX)
		talent_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		talent_label.add_theme_color_override("font_color",AsciiFrameScript.BRASS)
		member_status_window.add_child(talent_label)
	var progression:Dictionary=detail.get("progression",{}) if detail.get("progression",{}) is Dictionary else {}
	var vitals:=HBoxContainer.new();vitals.name="StatusVitals";vitals.custom_minimum_size.y=44
	vitals.add_theme_constant_override("separation",8);member_status_window.add_child(vitals)
	var health_bar:Control=_gauge("StatusHealthBar","HP",int(detail.get("health",0)),
		maxi(1,int(detail.get("max_health",1))),4,AsciiFrameScript.GREEN)
	health_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;vitals.add_child(health_bar)
	var stress:=int(detail.get("stress",0));var stress_band:=str(detail.get("stress_band","CALM"))
	var stress_bar:Control=_gauge("StatusStressBar","ST",stress,1000,4,_stress_band_color(stress_band))
	stress_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;vitals.add_child(stress_bar)
	var status_grid:=GridContainer.new();status_grid.name="StatusFolioGrid"
	status_grid.columns=2;status_grid.add_theme_constant_override("h_separation",10)
	status_grid.add_theme_constant_override("v_separation",8);member_status_window.add_child(status_grid)
	var emotion_cluster:=_add_status_pixel_section(status_grid,"EmotionSealCluster")
	var emotion_heading:=_card_label("감정 / 스트레스","EmotionSection",FONT_AUX)
	emotion_heading.add_theme_color_override("font_color",AsciiFrameScript.CYAN);emotion_cluster.add_child(emotion_heading)
	var emotion:Dictionary=detail.get("emotion",{}) if detail.get("emotion",{}) is Dictionary else {}
	var emotion_label:=_card_label("[%s%s]"%[str(emotion.get("icon","")),str(emotion.get("label","감정 정보 없음"))],"StatusEmotion",FONT_BODY)
	emotion_label.add_theme_color_override("font_color",AsciiFrameScript.INK);emotion_cluster.add_child(emotion_label)
	var reason:=str(emotion.get("reason","")).strip_edges()
	if not reason.is_empty() and reason!="이유 정보 없음":
		var reason_label:=_card_label(reason,"StatusEmotionReason",FONT_AUX);reason_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		reason_label.modulate=Color("#8fa5ae");emotion_cluster.add_child(reason_label)
	var stress_label:=_card_label("ST %d/1000 · %s"%[stress,str(detail.get("stress_band_label","안정"))],"StatusStress",FONT_AUX)
	stress_label.add_theme_color_override("font_color",_stress_band_color(stress_band));emotion_cluster.add_child(stress_label)
	if stress_band in ["ANXIOUS","PANIC"]:
		var stress_note:=_card_label("기술 사용 불가 · 물러나 진정시키세요" if stress_band=="ANXIOUS" \
			else "공황 · 후퇴를 우선한다","StatusStressNote",FONT_AUX)
		stress_note.add_theme_color_override("font_color",_stress_band_color(stress_band));emotion_cluster.add_child(stress_note)
	var combat_cluster:=_add_status_pixel_section(status_grid,"CombatSealCluster")
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
	var stats:Dictionary=detail.get("combat_stats",{}) \
		if detail.get("combat_stats",{}) is Dictionary else {}
	if stats.is_empty() and progression.get("combat_stats",{}) is Dictionary:
		stats=progression.get("combat_stats",{})
	if not stats.is_empty():
		var combat:=_card_label("공격 %d · 방어 %d\n회피 %s · 막기 %s"%[
			int(stats.get("attack_power",0)),int(stats.get("armor_flat",0)),
			_percent_milli_text(int(stats.get("evasion_milli",0))),
			_percent_milli_text(int(stats.get("parry_milli",0)))],"StatusCombatSummary",FONT_AUX)
		combat.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;combat_cluster.add_child(combat)
	var attribute_cluster:=_add_status_pixel_section(status_grid,"AttributeSealCluster")
	var attribute_heading:=_card_label("기본 능력","AttributeSection",FONT_AUX)
	attribute_heading.add_theme_color_override("font_color",AsciiFrameScript.CYAN)
	attribute_cluster.add_child(attribute_heading)
	var core_stats:Dictionary=detail.get("core_stats",{}) \
		if detail.get("core_stats",{}) is Dictionary else {}
	var attribute_text:=_card_label("근력 STR %d\n민첩 DEX %d\n지능 INT %d"%[
		int(core_stats.get("STR",0)),int(core_stats.get("DEX",0)),
		int(core_stats.get("INT",0))],"StatusCoreStats",FONT_AUX)
	attribute_cluster.add_child(attribute_text)
	var recovery:=preload("res://sim/party_recovery_rules.gd").stats(session.sim.world,int(detail.get("entity_id",member_detail_entity_id)))
	var recovery_text:=_card_label("HP 회복력 +%d\nMP 회복력 +%d\n안전 500 시간단위 후\n300 시간단위마다"%[
		int(recovery.hp_recovery),int(recovery.mp_recovery)],"StatusRecoveryStats",FONT_AUX)
	recovery_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;attribute_cluster.add_child(recovery_text)
	var body_cluster:=_add_status_pixel_section(status_grid,"BodySealCluster")
	var body_heading:=_card_label("육체 상태","BodyStateSection",FONT_AUX)
	body_heading.add_theme_color_override("font_color",AsciiFrameScript.CYAN)
	body_cluster.add_child(body_heading)
	var body:Dictionary=detail.get("body_state",{}) \
		if detail.get("body_state",{}) is Dictionary else {}
	var body_lines:Array[String]=[]
	if bool(body.get("available",false)):
		var blood_capacity:=maxi(1,int(body.get("blood_capacity",1)))
		body_lines.append("혈액 %d%% · 의식 %d%%"%[
			int(int(body.get("blood",0))*100/blood_capacity),
			int(int(body.get("consciousness",0))/10)])
		body_lines.append("충격 %d · 상처 %d"%[
			int(body.get("shock",0)),int(body.get("wound_count",0))])
		var part_states:Array[String]=[]
		for part_value in body.get("parts",[]):
			if not part_value is Dictionary:continue
			var part:Dictionary=part_value
			part_states.append("%s %s"%[_body_part_label(str(part.get("part_id",""))),
				_body_condition_label(str(part.get("condition","FUNCTIONAL")))])
		if not part_states.is_empty():body_lines.append(" · ".join(part_states))
	else:body_lines.append("육체 정보 없음")
	var body_text:=_card_label("\n".join(body_lines),"StatusBodyState",FONT_CAPTION)
	body_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body_cluster.add_child(body_text)
	if str(detail.get("role",""))!="PROTAGONIST":
		var equipment:Dictionary=detail.get("equipment_summary",{}) \
			if detail.get("equipment_summary",{}) is Dictionary else {}
		var equipment_heading:=_card_label("장비","StatusEquipmentSection",FONT_SECTION)
		equipment_heading.add_theme_color_override("font_color",AsciiFrameScript.CYAN)
		member_status_window.add_child(equipment_heading)
		var equipment_stats:Dictionary=equipment.get("combat_stats",{}) \
			if equipment.get("combat_stats",{}) is Dictionary else stats
		var equipment_text:=_card_label("무기 · %s%s\n보조 · %s / 방어구 · %s\n공격 %d · 방어 %d · 회피 %s · 막기 %s"%[
			str(equipment.get("weapon_label","없음")),
			" (기본)" if bool(equipment.get("natural_weapon",false)) else "",
			str(equipment.get("off_hand_label","없음")),
			str(equipment.get("armor_label","없음")),
			int(equipment_stats.get("attack_power",0)),int(equipment_stats.get("armor_flat",0)),
			_percent_milli_text(int(equipment_stats.get("evasion_milli",0))),
			_percent_milli_text(int(equipment_stats.get("parry_milli",0)))],
			"StatusEquipmentSummary",FONT_AUX)
		equipment_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		member_status_window.add_child(equipment_text)
	var dossier_heading:=_card_label("내성","StatusDossierSection",FONT_SECTION)
	dossier_heading.add_theme_color_override("font_color",AsciiFrameScript.CYAN);member_status_window.add_child(dossier_heading)

func _add_status_pixel_section(parent:GridContainer,node_name:String)->VBoxContainer:
	var panel:=PanelContainer.new();panel.name=node_name+"Panel"
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	DarkPixelSkinScript.apply_panel(panel,"SECTION");parent.add_child(panel)
	var cluster:=VBoxContainer.new();cluster.name=node_name
	cluster.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	cluster.add_theme_constant_override("separation",3);panel.add_child(cluster)
	return cluster

func _percent_milli_text(value:int)->String:
	var positive:=maxi(0,value);var whole:=int(positive/10);var tenth:=positive%10
	return "%d%%"%whole if tenth==0 else "%d.%d%%"%[whole,tenth]

func _body_part_label(part_id:String)->String:
	return {"HEAD":"머리","TORSO":"몸통","LEFT_ARM":"왼팔","RIGHT_ARM":"오른팔",
		"LEFT_LEG":"왼다리","RIGHT_LEG":"오른다리"}.get(part_id,part_id)

func _body_condition_label(condition:String)->String:
	return {"FUNCTIONAL":"정상","DISABLED":"기능 상실","SEVERED":"절단"}.get(condition,condition)

func _life_state_label(life_state:String)->String:
	match life_state:
		"DOWNED":return "쓰러짐"
		"DEAD":return "사망"
		_:return "생존"

func _status_label(status_id:String)->String:
	return {"BLEEDING":"출혈","POISONED":"중독","WET":"젖음","GUARDED":"방어 태세"}.get(status_id,status_id)

func _begin_companion_order_edit()->void:
	var id:=member_detail_entity_id
	_cancel_auto_pending(true)
	_cancel_product_auto_explore("auto_explore_user_command",false)
	_close_member_detail()
	companion_order_editor.begin(session,id)
	combat_action_dock.visible=false
	selected_member_id=int(session.party_status().protagonist_id)
	_request_refresh()

func _finish_companion_order_edit()->void:
	selected_member_id=int(session.party_status().protagonist_id)
	auto_override_edit=false
	_request_refresh()

func _open_member_detail(member_id:int,initial_tab:String="STATUS")->void:
	if auto_orchestration_enabled:_cancel_auto_pending(false)
	_product_attack_targeting=false
	# Character/item inspection is a pause, not a cancellation. Keeping the
	# canonical AUTO/route state lets travel resume after the modal closes.
	_reset_member_detail_pointer_state()
	var detail:Dictionary=session.inspect_party_member(member_id)
	if not bool(detail.get("accepted",false)):
		detail=session.inspect_enemy(member_id,true)
	if not bool(detail.get("accepted",false)):
		notice_text=str(detail.get("message","파티원 상세 정보를 불러올 수 없습니다."));_request_refresh();return
	var travel_state:Dictionary=session.exploration_route_state()
	route_paused_by_modal=bool(travel_state.get("active",false))
	member_detail_title.text=str(detail.get("display_name","파티원"))
	member_detail_glyph_seal.call("set_actor",detail)
	var detail_progression:Dictionary=detail.get("progression",{}) if detail.get("progression",{}) is Dictionary else {}
	var subtitle_parts:Array[String]=[_species(str(detail.get("species_id","default")))]
	subtitle_parts.append(str(detail.get("role_label",_role(str(detail.get("role",""))))))
	if bool(detail_progression.get("available",false)):subtitle_parts.append("LV%02d"%int(detail_progression.get("level",1)))
	subtitle_parts.append(_life_state_label(str(detail.get("life_state","ACTIVE"))))
	member_detail_subtitle.text=" / ".join(subtitle_parts)
	member_detail_body.text=_member_detail_text(detail)
	_update_member_status_window(detail)
	member_detail_entity_id=member_id
	member_ability_window.configure(member_id,session.active_skill_rows(member_id))
	var progression:Variant=detail.get("progression",{})
	member_detail_has_skills=progression is Dictionary and bool(progression.get("available",false))
	var skill_summary:Variant=detail.get("skill_summary",{})
	member_detail_has_skill_summary=skill_summary is Dictionary \
		and bool(skill_summary.get("available",false))
	member_detail_has_personality=bool(detail.get("personality_available",false))
	var relations:Variant=detail.get("relation_rows",[])
	var affinity:Variant=detail.get("affinity_toward_protagonist",{})
	member_detail_has_relationships=relations is Array \
		or affinity is Dictionary and not affinity.is_empty()
	member_personality_window.call("set_detail",detail)
	member_relationship_window.call("set_detail",detail)
	member_skill_window.call("set_detail",detail)
	member_detail_current_tab=initial_tab if initial_tab in ["STATUS","PERSONALITY","RELATIONSHIP","SKILL","ITEM"] \
		and (initial_tab=="STATUS" or initial_tab=="PERSONALITY" and member_detail_has_personality \
		or initial_tab=="RELATIONSHIP" and member_detail_has_relationships \
		or initial_tab=="SKILL" and (member_detail_has_skills or member_detail_has_skill_summary) \
		or initial_tab=="ITEM" and member_detail_has_skills) else "STATUS"
	_update_progression_window(progression)
	_update_item_window(progression.get("equipment",{}) if progression is Dictionary else {})
	var can_show_dismiss:=str(detail.get("role",""))=="COMPANION" \
		and bool(detail.get("active_party_member",false))
	if session.town_life_enabled():can_show_dismiss=false
	member_detail_dismiss_available=can_show_dismiss
	if can_show_dismiss:
		var assessment:Dictionary=session.roster_change_assessment("DISMISS",member_id)
		member_detail_dismiss.disabled=not bool(assessment.get("accepted",false))
		member_detail_dismiss.tooltip_text=str(assessment.get("message",""))
	var can_show_candidate:=bool(detail.get("recruitable_member",false))
	member_detail_candidate_available=can_show_candidate
	if can_show_candidate:
		_configure_candidate_detail_action(detail)
		var attack:Dictionary=detail.get("attack_assessment",{}) \
			if detail.get("attack_assessment",{}) is Dictionary else {}
		member_detail_attack_available=true
		member_detail_attack.disabled=not bool(attack.get("accepted",false))
		member_detail_attack.tooltip_text=str(attack.get("message","인접한 인물을 공격합니다."))
		if session.town_life_enabled():member_detail_attack_available=false
	else:member_detail_attack_available=false
	_apply_member_detail_tab()
	member_detail_scroll.scroll_vertical=0
	grid.cancel_pointer_gesture();member_detail_modal.visible=true;grid.modal_open=true
	_sync_product_zoom_controls(_is_solo_product_session())
	_layout_floating_surfaces();call_deferred("_measure_member_detail_body")
	if member_detail_close.is_inside_tree():member_detail_close.grab_focus()

func _close_member_detail()->void:
	if member_detail_modal==null or not member_detail_modal.visible:return
	_hide_item_popover()
	member_detail_modal.visible=false;member_detail_entity_id=-1;_product_attack_targeting=false
	_reset_member_detail_pointer_state()
	grid.modal_open=record_modal.visible or map_overlay.visible or base_modal.visible
	_sync_product_zoom_controls(_is_solo_product_session())
	route_paused_by_modal=false
	if session!=null:
		var travel_state:Dictionary=session.exploration_route_state()
		if bool(travel_state.get("active",false)) and not route_continue_pending:
			_schedule_route_continue(Time.get_ticks_msec())
		if session.has_method("auto_explore_state") \
				and bool(session.auto_explore_state().get("running",false)) \
				and not _product_auto_explore_pending:
			_schedule_product_auto_explore(Time.get_ticks_msec())
	if auto_orchestration_enabled:_request_refresh()

func _reset_member_detail_pointer_state()->void:
	_item_touch_index=-1;_item_touch_id="";_item_touch_slot="";_item_touch_action=""
	_item_touch_dragged=false
	_product_touch_index=-1;_product_touch_control="";_product_touch_dragged=false
	_product_touch_started_msec=-1;_product_immediate_touch_indices.clear();_product_mouse_control=""
	if grid!=null:grid.cancel_pointer_gesture()

func _select_member_detail_tab(tab_id:String)->void:
	if tab_id not in ["STATUS","PERSONALITY","RELATIONSHIP","SKILL","ITEM"] \
			or tab_id=="PERSONALITY" and not member_detail_has_personality \
			or tab_id=="RELATIONSHIP" and not member_detail_has_relationships \
			or tab_id=="SKILL" and not (member_detail_has_skills or member_detail_has_skill_summary) \
			or tab_id=="ITEM" and not member_detail_has_skills:return
	_hide_item_popover();member_detail_current_tab=tab_id;member_detail_scroll.scroll_vertical=0
	_apply_member_detail_tab();_reflow_member_detail_scroll()

func _apply_member_detail_tab()->void:
	var personality_selected:=member_detail_has_personality \
		and member_detail_current_tab=="PERSONALITY"
	var relationship_selected:=member_detail_has_relationships \
		and member_detail_current_tab=="RELATIONSHIP"
	var skill_selected:=(member_detail_has_skills or member_detail_has_skill_summary) \
		and member_detail_current_tab=="SKILL"
	var item_selected:=member_detail_has_skills and member_detail_current_tab=="ITEM"
	var status_selected:=not personality_selected and not relationship_selected \
		and not skill_selected and not item_selected
	member_detail_tab_row.visible=member_detail_has_skills or member_detail_has_skill_summary \
		or member_detail_has_personality \
		or member_detail_has_relationships
	member_detail_status_tab.set_pressed_no_signal(status_selected)
	member_detail_personality_tab.visible=member_detail_has_personality
	member_detail_personality_tab.set_pressed_no_signal(personality_selected)
	member_detail_relationship_tab.visible=member_detail_has_relationships
	member_detail_relationship_tab.set_pressed_no_signal(relationship_selected)
	member_detail_skill_tab.visible=member_detail_has_skills or member_detail_has_skill_summary
	member_detail_item_tab.visible=member_detail_has_skills
	member_detail_skill_tab.set_pressed_no_signal(skill_selected)
	member_detail_item_tab.set_pressed_no_signal(item_selected)
	member_detail_status_tab.text="[상태]" if status_selected else " 상태 "
	member_detail_personality_tab.text="[성격]" if personality_selected else " 성격 "
	member_detail_relationship_tab.text="[관계]" if relationship_selected else " 관계 "
	var skill_tab_label:="이능"
	member_detail_skill_tab.text="[%s]"%skill_tab_label if skill_selected else " %s "%skill_tab_label
	member_detail_skill_tab.tooltip_text="이능 6칸 장착 미리보기 · 전투 적용/저장 없음"
	member_detail_item_tab.text="[아이템]" if item_selected else " 아이템 "
	DarkPixelSkinScript.apply_tab_button(member_detail_status_tab,status_selected)
	DarkPixelSkinScript.apply_tab_button(member_detail_personality_tab,personality_selected)
	DarkPixelSkinScript.apply_tab_button(member_detail_relationship_tab,relationship_selected)
	DarkPixelSkinScript.apply_tab_button(member_detail_skill_tab,skill_selected)
	DarkPixelSkinScript.apply_tab_button(member_detail_item_tab,item_selected)
	member_status_window.visible=status_selected
	member_detail_body.visible=status_selected
	member_personality_window.visible=personality_selected
	member_relationship_window.visible=relationship_selected
	member_skill_window.visible=false
	member_ability_window.visible=skill_selected
	member_status_equipment_window.visible=member_detail_has_skills \
		and status_selected
	member_progression_window.visible=false
	member_item_window.visible=item_selected
	member_detail_dismiss.visible=status_selected and member_detail_dismiss_available
	member_detail_candidate_action.visible=status_selected and member_detail_candidate_available
	member_detail_attack.visible=status_selected and member_detail_attack_available
	var order_status:Dictionary=session.party_status()
	var can_order:bool=str(order_status.get("safe_phase",""))=="ENGAGED" \
		and member_detail_entity_id!=int(order_status.get("protagonist_id",-1)) \
		and member_detail_entity_id in order_status.get("party_member_ids",[])
	member_order_button.visible=status_selected and can_order
	member_order_cancel.visible=status_selected and can_order and session.has_companion_order(member_detail_entity_id)
	_sync_member_detail_scroll_children()
	_reflow_member_detail_scroll()

func _sync_member_detail_scroll_children()->void:
	if member_detail_scroll_content==null or member_detail_tab_stash==null:return
	var desired:Array[Control]=[]
	if member_ability_window.visible:
		desired=[member_ability_window]
	elif member_item_window.visible:
		desired=[member_item_window]
	elif member_progression_window.visible:
		desired=[member_progression_window]
	elif member_skill_window.visible:
		desired=[member_skill_window]
	elif member_personality_window.visible:
		desired=[member_personality_window]
	elif member_relationship_window.visible:
		desired=[member_relationship_window]
	else:
		desired=[member_status_window,member_detail_body]
		if member_status_equipment_window.visible:desired.append(member_status_equipment_window)
	var managed:Array[Control]=[member_ability_window,member_progression_window,member_item_window,member_skill_window,
		member_personality_window,member_relationship_window,member_status_window,member_detail_body,
		member_status_equipment_window]
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
	var tone:=DarkPixelSkinScript.BRASS if equipped or mode=="FOCUS" \
		else (DarkPixelSkinScript.BONE_DIM if mode=="OFF" else DarkPixelSkinScript.CYAN)
	mode_label.add_theme_color_override("font_color",tone)
	button.set_meta("no_button_chrome",true);button.set_meta("raw_training_weight",
		int(ProgressionRegistryScript.MODE_WEIGHTS.get(mode,0)))
	button.set_meta("equipped_proficiency",equipped)
	button.set_meta("training_paused",mode=="OFF")
	if name_label!=null:
		name_label.add_theme_color_override("font_color",DarkPixelSkinScript.BRASS if equipped \
			else (DarkPixelSkinScript.BONE_DIM if mode=="OFF" else DarkPixelSkinScript.BONE))
	if panel!=null:
		panel.add_theme_stylebox_override("panel",DarkPixelSkinScript.panel_surface(
			DarkPixelSkinScript.SLOT_EQUIPPED if equipped else DarkPixelSkinScript.SLOT_EMPTY,
			DarkPixelSkinScript.BRASS_DARK if equipped else DarkPixelSkinScript.IRON_SHADOW,2,1))

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
	if member_skill_window!=null:member_skill_window.update_minimum_size()
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
	var summary:Dictionary=equipment.get("combat_summary",{}) \
		if equipment.get("combat_summary",{}) is Dictionary else {}
	member_item_weapon_text.text="공격 %d · 방어 %d · 회피 %s · 막기 %s"%[
		int(summary.get("attack_power",equipment.get("raw_damage",0))),
		int(summary.get("armor_flat",0)),
		_percent_milli_text(int(summary.get("evasion_milli",0))),
		_percent_milli_text(int(summary.get("parry_milli",0)))]
	member_item_ammo_text.text="탄약 · 화살 %d · 볼트 %d"%[
		int(equipment.get("arrows",0)),int(equipment.get("bolts",0))]
	if bool(equipment.get("reload_required",false)):
		member_item_ammo_text.text+=" · %s"%(
			"장전됨" if bool(equipment.get("loaded",false)) else "미장전")
	member_item_reload_button.visible=bool(equipment.get("reload_required",false))
	member_item_reload_button.disabled=not bool(equipment.get("can_reload",false))
	member_item_reload_button.text="재장전 %d시간"%int(equipment.get("reload_time",0))
	_update_item_inventory_ledger()

func _update_item_inventory_ledger()->void:
	if member_item_equipment_rows==null:return
	# Detach old rows immediately so a just-rebuilt ledger has one input layer.
	# queue_free() alone leaves the outgoing buttons in hit-testing until the end
	# of the frame, directly on top of the fresh mobile actions.
	_detach_item_ledger_children(member_item_equipment_rows)
	_detach_item_ledger_children(member_item_equipment_grid)
	_detach_item_ledger_children(member_item_backpack_rows)
	var dto:Dictionary=session.protagonist_inventory()
	var slot_labels:={"MAIN_HAND":"주무기","OFF_HAND":"보조","ARMOR":"갑옷",
		"ACCESSORY_1":"장신구1","ACCESSORY_2":"장신구2"}
	var equipment_slots:Array=dto.get("equipment_slots",[])
	for index in range(equipment_slots.size()):
		var row:Dictionary=equipment_slots[index]
		var slot:=str(row.get("slot",""))
		_add_item_ledger_button(member_item_equipment_rows,row,
			"%-5s %s"%[str(slot_labels.get(slot,slot)),_item_row_text(row)],true)
		_add_item_grid_slot(member_item_equipment_grid,row,index,slot)
	var backpack:Array=dto.get("backpack_rows",[])
	var capacity:=int(dto.get("capacity",20))
	member_item_empty_text.text="가방 %d / %d"%[backpack.size(),capacity]
	for index in range(capacity):
		var row:Dictionary=backpack[index] if index<backpack.size() else {"empty":true}
		_add_item_grid_slot(member_item_backpack_rows,row,index,"")
	if member_item_popover!=null and member_item_popover.visible:
		var selected_row:=_selected_item_ledger_row(dto)
		if selected_row.is_empty():_hide_item_popover()
		else:_configure_item_popover(selected_row,dto)

func _detach_item_ledger_children(container:Control)->void:
	if container==null:return
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
	var lines:Array[String]=[]
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
		if str(row.get("definition_id",""))=="TORCH":
			parts.append("연료 %d/%d"%[int(row.get("fuel_remaining",0)),int(row.get("fuel_capacity",0))])
		lines.append("효과 없음" if parts.is_empty() else " · ".join(parts))
	var requirement:=str(row.get("requirement_text",""))
	if not requirement.is_empty():lines.append("요구 능력 · "+requirement)
	return "\n".join(lines)

func _item_description_text(row:Dictionary)->String:
	match str(row.get("category","")):
		"WEAPON":
			var ammo:=str(row.get("ammo_kind","NONE"))
			if ammo=="ARROW":return "화살을 사용하는 원거리 무기입니다. 거리를 두고 공격할 수 있습니다."
			if ammo=="BOLT":return "볼트를 사용하는 강력한 원거리 무기입니다. 사격 뒤 재장전이 필요합니다."
			return "주무기 슬롯에 장착하는 근접 무기입니다."
		"ARMOR":
			if str(row.get("definition_id",""))=="TORCH":
				return "보조 손에 장착해 주변을 밝히는 횃불입니다. 켜진 동안 게임 시간에 따라 연료가 줄어듭니다."
			return "몸을 보호하는 장비입니다. 대응하는 방어 슬롯에 장착됩니다."
		"ACCESSORY":return "능력을 보완하는 장신구입니다. 빈 장신구 슬롯을 우선 사용합니다."
		"CONSUMABLE":
			return "사용하면 체력을 회복합니다." if _is_healing_item_row(row) \
				else "한 번 사용하면 소모되는 아이템입니다."
		_:return "가방에 보관하는 아이템입니다."

func _add_item_ledger_button(parent:VBoxContainer,row:Dictionary,label:String,equipped:bool)->void:
	var button:=Button.new();button.custom_minimum_size.y=TOUCH_TARGET
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.focus_mode=Control.FOCUS_NONE
	button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.text=label
	button.add_theme_font_size_override("font_size",FONT_AUX)
	button.disabled=bool(row.get("empty",false))
	var instance_id:=str(row.get("instance_id",""));var slot:=str(row.get("slot","")) if equipped else ""
	button.set_meta("item_instance_id",instance_id);button.set_meta("item_slot",slot)
	button.pressed.connect(_on_item_row_selected.bind(instance_id,slot,button))
	parent.add_child(button);DarkPixelSkinScript.apply_tab_button(button,
		instance_id==member_item_selected_id and slot==member_item_selected_slot)

func _add_item_grid_slot(parent:GridContainer,row:Dictionary,index:int,
		equipment_slot:String)->void:
	var button=ItemSlotScript.new()
	button.name="EquipmentSlot%s"%equipment_slot if not equipment_slot.is_empty() \
		else "BackpackSlot%02d"%(index+1)
	button.custom_minimum_size=Vector2(ITEM_SLOT_MINIMUM,ITEM_SLOT_MINIMUM)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var instance_id:=str(row.get("instance_id",""))
	button.configure(row,index,equipment_slot,
		instance_id==member_item_selected_id and equipment_slot==member_item_selected_slot)
	button.pressed.connect(_on_item_row_selected.bind(instance_id,equipment_slot,button))
	parent.add_child(button)

func _on_item_row_selected(instance_id:String,slot:String,anchor:Control=null)->void:
	if instance_id.is_empty():return
	member_item_selected_id=instance_id;member_item_selected_slot=slot
	_sync_item_grid_selection()
	if anchor==null:anchor=_find_item_row_button(instance_id,slot)
	member_item_popover_anchor=anchor
	var dto:Dictionary=session.protagonist_inventory()
	var selected_row:=_selected_item_ledger_row(dto)
	if selected_row.is_empty():_hide_item_popover();return
	_configure_item_popover(selected_row,dto)
	member_item_popover.visible=true
	_position_item_popover(anchor)

func _find_item_row_button(instance_id:String,slot:String)->Button:
	var ledgers:Array=[member_item_equipment_grid,member_item_backpack_rows,
		member_item_equipment_rows] if member_detail_current_tab=="ITEM" else [
		member_item_equipment_rows,member_item_equipment_grid,member_item_backpack_rows]
	for ledger in ledgers:
		if ledger==null:continue
		for child in ledger.get_children():
			var button:=child as Button
			if button!=null and str(button.get_meta("item_instance_id",""))==instance_id \
					and str(button.get_meta("item_slot",""))==slot:return button
	return null

func _configure_item_popover(row:Dictionary,dto:Dictionary)->void:
	member_item_popover_title.text="%s  %s"%[str(row.get("glyph","*")),str(row.get("label","아이템"))]
	member_item_popover_body.text="%s\n%s"%[_item_description_text(row),_item_stats_text(row)]
	var selected_equipped:=not member_item_selected_slot.is_empty()
	var allowed_slots:Array=[]
	var allowed_value:Variant=row.get("equip_slots",[])
	if allowed_value is Array:allowed_slots=allowed_value
	var target_slot:=item_preferred_equip_slot(dto,allowed_slots)
	var compared_row:Dictionary={}
	if not selected_equipped and not target_slot.is_empty():
		for equipped_value in dto.get("equipment_slots",[]):
			if equipped_value is Dictionary and str(equipped_value.get("slot",""))==target_slot:
				compared_row=equipped_value;break
	member_item_popover_compare.text=_item_comparison_text(row,compared_row,target_slot)
	member_item_popover_compare.visible=not member_item_popover_compare.text.is_empty()
	member_item_equip_button.visible=not selected_equipped and not target_slot.is_empty()
	member_item_equip_button.disabled=false
	member_item_equip_button.set_meta("item_instance_id",str(row.get("instance_id","")))
	member_item_equip_button.set_meta("item_slot",target_slot)
	member_item_equip_button.text="[교체]" if not compared_row.is_empty() \
		and not bool(compared_row.get("empty",false)) else "[장착]"
	if member_item_equip_button.visible and not bool(row.get("requirements_met",true)):
		member_item_equip_button.text="[장착 불가]"
		member_item_equip_button.tooltip_text="필요 능력치가 부족합니다. 눌러서 이유를 확인하세요."
	else:member_item_equip_button.tooltip_text=""
	member_item_unequip_button.visible=selected_equipped
	member_item_unequip_button.disabled=not selected_equipped
	member_item_unequip_button.set_meta("item_instance_id",str(row.get("instance_id","")))
	member_item_unequip_button.set_meta("item_slot",member_item_selected_slot)
	var torch_row:=str(row.get("definition_id",""))=="TORCH"
	member_item_use_button.visible=(not selected_equipped and _is_healing_item_row(row)) \
		or (torch_row and selected_equipped)
	member_item_use_button.disabled=not member_item_use_button.visible \
		or not session.has_method("use_inventory_item")
	if torch_row and selected_equipped:
		member_item_use_button.disabled=false
		member_item_use_button.text="[소화]" if bool(row.get("torch_lit",false)) else "[점화]"
	else:
		member_item_use_button.text="사용"
	member_item_drop_button.visible=not selected_equipped
	member_item_drop_button.disabled=selected_equipped

func _item_comparison_text(row:Dictionary,equipped:Dictionary,slot:String)->String:
	if slot.is_empty():return ""
	var slot_label:=str({"MAIN_HAND":"주무기","OFF_HAND":"보조","ARMOR":"갑옷",
		"ACCESSORY_1":"장신구1","ACCESSORY_2":"장신구2"}.get(slot,slot))
	if equipped.is_empty() or bool(equipped.get("empty",false)):
		return "비교 · %s 비어 있음"%slot_label
	var parts:Array[String]=[]
	if str(row.get("category",""))=="WEAPON":
		parts.append("공격 %+d"%(int(row.get("raw_damage",0))-int(equipped.get("raw_damage",0))))
		parts.append("명중 %+.1f%%"%((int(row.get("hit_chance_milli",0))-
			int(equipped.get("hit_chance_milli",0)))/10.0))
		parts.append("관통 %+d"%(int(row.get("armor_penetration_flat",0))-
			int(equipped.get("armor_penetration_flat",0))))
	else:
		var new_bonuses:Dictionary=row.get("bonuses",{}) if row.get("bonuses",{}) is Dictionary else {}
		var old_bonuses:Dictionary=equipped.get("bonuses",{}) \
			if equipped.get("bonuses",{}) is Dictionary else {}
		for entry in [["armor_flat","방어"],["dodge_milli","회피"],["parry_milli","막기"]]:
			var difference:=int(new_bonuses.get(str(entry[0]),0))-int(old_bonuses.get(str(entry[0]),0))
			if difference!=0:parts.append("%s %+d"%[str(entry[1]),difference])
	if parts.is_empty():parts.append("주요 수치 변화 없음")
	return "현재 %s · %s\n교체 변화 · %s"%[
		slot_label,str(equipped.get("label","장비"))," · ".join(parts)]

func _position_item_popover(_anchor:Control=null)->void:
	if member_item_popover==null or not member_item_popover.visible:return
	var horizontal_margin:=16.0
	var popup_width:=minf(320.0,maxf(280.0,size.x-horizontal_margin*2.0))
	member_item_popover.custom_minimum_size.x=popup_width
	member_item_popover.reset_size()
	member_item_popover.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var popup_size:=member_item_popover.get_combined_minimum_size()
	popup_size.x=popup_width
	member_item_popover.size=popup_size
	member_item_popover.position=_fixed_item_popover_origin(popup_width)
	_settle_item_popover_size_after_layout(popup_width)

func _settle_item_popover_size_after_layout(popup_width:float)->void:
	if not is_inside_tree():return
	await get_tree().process_frame
	if member_item_popover==null or not member_item_popover.visible:return
	var popup_size:=member_item_popover.get_combined_minimum_size()
	popup_size.x=popup_width
	member_item_popover.size=popup_size
	member_item_popover.position=_fixed_item_popover_origin(popup_width)

func _fixed_item_popover_origin(popup_width:float)->Vector2:
	var horizontal_margin:=16.0
	var x:=clampf((size.x-popup_width)*0.5,horizontal_margin,
		maxf(horizontal_margin,size.x-popup_width-horizontal_margin))
	# The selected row, its content height, and the scroll offset never affect
	# placement. The popover always starts at the detail folio's content inset.
	var panel_top:=member_detail_panel.position.y if member_detail_panel!=null else 0.0
	return Vector2(x,maxf(16.0,panel_top+108.0))

func _hide_item_popover(clear_selection:bool=true)->void:
	if member_item_popover!=null:member_item_popover.visible=false
	member_item_popover_anchor=null
	if clear_selection:
		member_item_selected_id="";member_item_selected_slot=""
		_sync_item_grid_selection()

func _sync_item_grid_selection()->void:
	for grid_container in [member_item_equipment_grid,member_item_backpack_rows]:
		if grid_container==null:continue
		for child in grid_container.get_children():
			if child.has_method("set_selected"):
				child.set_selected(str(child.get_meta("item_instance_id","")) \
					==member_item_selected_id and str(child.get_meta("item_slot","")) \
					==member_item_selected_slot and not member_item_selected_id.is_empty())

func _on_item_equip_selected()->void:
	_cancel_navigation_for_item_operation()
	var dto:Dictionary=session.protagonist_inventory()
	var instance_id:=str(member_item_equip_button.get_meta(
		"item_instance_id",member_item_selected_id)) if member_item_equip_button!=null \
		else member_item_selected_id
	var slot:=str(member_item_equip_button.get_meta("item_slot","")) \
		if member_item_equip_button!=null else ""
	if slot.is_empty():
		var allowed_slots:Array=[]
		for row in dto.get("backpack_rows",[]):
			if str(row.get("instance_id",""))==instance_id:
				allowed_slots=row.get("equip_slots",[]);break
		slot=item_preferred_equip_slot(dto,allowed_slots)
	if slot.is_empty():
		notice_text="이 아이템은 장착할 수 없습니다."
		action_feedback_text=notice_text;_request_refresh();return
	_on_item_operation_result(session.equip_inventory_item(instance_id,slot))

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
	var slot:=str(member_item_unequip_button.get_meta(
		"item_slot",member_item_selected_slot)) if member_item_unequip_button!=null \
		else member_item_selected_slot
	if slot.is_empty() and not member_item_selected_id.is_empty():
		for row in session.protagonist_inventory().get("equipment_slots",[]):
			if str(row.get("instance_id",""))==member_item_selected_id:
				slot=str(row.get("slot",""));break
	_on_item_unequip_slot(slot)

func _on_item_unequip_slot(slot:String)->void:
	_cancel_navigation_for_item_operation()
	if slot.is_empty():
		notice_text="해제할 장비 슬롯을 선택하세요."
		action_feedback_text=notice_text;_request_refresh();return
	_on_item_operation_result(session.unequip_inventory_slot(slot))

func _on_item_drop_selected()->void:
	_cancel_navigation_for_item_operation()
	_on_item_operation_result(session.drop_inventory_item(member_item_selected_id))

func _on_item_use_selected()->void:
	_cancel_navigation_for_item_operation()
	if member_item_selected_id.is_empty() or not session.has_method("use_inventory_item"):
		notice_text="이 아이템은 지금 사용할 수 없습니다."
		action_feedback_text=notice_text;return
	var selected:=_selected_item_ledger_row(session.protagonist_inventory())
	var is_torch:=str(selected.get("definition_id",""))=="TORCH"
	if is_torch:
		var method_name:="extinguish_torch" if bool(selected.get("torch_lit",false)) else "ignite_torch"
		var torch_result:Dictionary=session.call(method_name,member_item_selected_id)
		if not bool(torch_result.get("accepted",false)):
			notice_text=str(torch_result.get("message","횃불을 사용할 수 없습니다."))
			action_feedback_text=notice_text;member_item_popover_compare.text=notice_text
			member_item_popover_compare.visible=true;_position_item_popover();return
		notice_text="횃불을 %s했습니다." % ("껐" if method_name=="extinguish_torch" else "켰")
		action_feedback_text=notice_text;_hide_item_popover();_record_result(torch_result,true);_refresh();return
	var result:Dictionary=session.call("use_inventory_item",member_item_selected_id)
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","물약을 사용할 수 없습니다."))
		action_feedback_text=notice_text
		member_item_popover_compare.text=notice_text
		member_item_popover_compare.visible=true
		_position_item_popover();return
	var healed:=int(result.get("healed_amount",0))
	notice_text="회복 물약 사용 · HP +%d"%healed
	action_feedback_text=notice_text
	_hide_item_popover()
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
		action_feedback_text=notice_text
		member_item_popover_compare.visible=true
		member_item_popover_compare.text="실패 · %s"%notice_text
		return
	var return_tab:=member_detail_current_tab
	notice_text="아이템 상태를 변경했습니다. (100시간)"
	_hide_item_popover()
	var detail:Dictionary=session.inspect_party_member(member_detail_entity_id)
	var progression:Dictionary=detail.get("progression",{}) if detail.get("progression",{}) is Dictionary else {}
	_update_item_window(progression.get("equipment",{}));member_detail_current_tab=return_tab
	_apply_member_detail_tab();action_feedback_text=notice_text;_reflow_member_detail_scroll()
	_request_refresh()

func _on_item_reload()->void:
	_cancel_navigation_for_item_operation()
	var result:Dictionary=session.reload_protagonist_weapon()
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","재장전할 수 없습니다."));return
	var detail:Dictionary=session.inspect_party_member(member_detail_entity_id)
	var progression:Dictionary=detail.get("progression",{}) if detail.get("progression",{}) is Dictionary else {}
	_update_item_window(progression.get("equipment",{}))
	member_detail_current_tab="ITEM";_apply_member_detail_tab()
	notice_text="쇠뇌를 재장전했습니다.";_request_refresh()

func _cancel_navigation_for_item_operation()->void:
	_cancel_product_auto_explore("auto_explore_user_command",false)
	var route_state:Dictionary=session.exploration_route_state() if session!=null else {}
	if bool(route_state.get("active",false)) or bool(route_state.get("has_preview",false)):
		_cancel_active_route()

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
	if session.town_life_enabled():
		var id:=int(detail.entity_id)
		if session.sim.world.party_encounter.expedition_cycle.phase=="DUNGEON":
			var visitor:Dictionary=preload("res://playtest/dungeon_visitors_service.gd").assess(session,id)
			member_detail_candidate_action.text="식량 1개 나누기" if visitor.get("needs_supplies",false) else "이야기 나누기"
			member_detail_candidate_action.disabled=not bool(visitor.get("can_aid" if visitor.get("needs_supplies",false) else "can_greet",false))
			member_detail_candidate_action.tooltip_text=str(visitor.get("message","이 층에 없는 인물입니다"))
		else:
			for resident in session.town_life_overview().residents:
				if int(resident.entity_id)!=id:continue
				member_detail_candidate_action.text="원정에 편성" if resident.joined else ("동행 제안" if resident.can_join else "이야기 나누기")
				member_detail_candidate_action.disabled=not bool(resident.can_assign if resident.joined else (resident.can_join or resident.can_talk))
		return
	var story_state:=str(detail.get("rescue_story_state",""))
	if story_state=="COLLAPSED_STORY":
		var rescue:Dictionary=detail.get("rescue_assessment",{}) if detail.get("rescue_assessment",{}) is Dictionary else {}
		member_detail_candidate_action.text="상처 안정화 · %d 시간"%int(rescue.get("time_cost",0))
		member_detail_candidate_action.disabled=not bool(rescue.get("accepted",false))
		member_detail_candidate_action.tooltip_text=str(rescue.get("message","쓰러진 인물 곁에서 도울 수 있습니다."));return
	var recruitment:Dictionary=detail.get("recruitment_assessment",{}) if detail.get("recruitment_assessment",{}) is Dictionary else {}
	if not recruitment.is_empty():
		var affinity:Dictionary=detail.get("affinity_toward_protagonist",{}) \
			if detail.get("affinity_toward_protagonist",{}) is Dictionary else {}
		var volunteers:=int(affinity.get("score",0))>=75 \
			and bool(recruitment.get("accepted",false)) \
			and bool(recruitment.get("would_accept",false))
		member_detail_candidate_action.text=("[동행 수락] 먼저 합류 제안" if volunteers \
			else "[J 영입 권유] 수락 %d%%"%int(recruitment.get("probability_percent",0)))
		member_detail_candidate_action.disabled=not bool(recruitment.get("accepted",false))
		member_detail_candidate_action.tooltip_text=_recruitment_reason_summary(recruitment);return
	member_detail_candidate_action.text="[J 영입 불가]"
	member_detail_candidate_action.disabled=true
	member_detail_candidate_action.tooltip_text="먼저 구조와 안정화를 완료해야 합니다."

func _on_member_detail_candidate_action()->void:
	if member_detail_entity_id<=0:return
	if session.town_life_enabled():
		var id:=member_detail_entity_id
		var response:Dictionary={}
		if session.sim.world.party_encounter.expedition_cycle.phase=="DUNGEON":
			var visitor:Dictionary=preload("res://playtest/dungeon_visitors_service.gd").assess(session,id)
			response=preload("res://playtest/dungeon_visitors_service.gd").interact(session,
				{"action":"AID" if visitor.get("needs_supplies",false) else "GREET","entity_id":str(id)})
		else:
			for resident in session.town_life_overview().residents:
				if int(resident.entity_id)==id:
					response=session.town_life_command({"action":"ASSIGN" if resident.joined else ("JOIN" if resident.can_join else "TALK"),"entity_id":str(id)})
		notice_text=str(response.get("message","지금은 상호작용할 수 없습니다"))
		_close_member_detail();_request_refresh();return
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

func _on_member_detail_attack()->void:
	if member_detail_entity_id>0:_attack_neutral_npc(member_detail_entity_id)

func _attack_neutral_npc(entity_id:int)->void:
	_cancel_product_auto_explore("auto_explore_user_command",false)
	_cancel_route_for_user_interruption()
	if auto_orchestration_enabled:_cancel_auto_pending(false)
	var result:Dictionary=session.assault_npc(entity_id)
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","이 인물을 공격할 수 없습니다."))
		action_feedback_text=notice_text
		if member_detail_modal.visible:
			var detail:Dictionary=session.inspect_party_member(entity_id)
			if bool(detail.get("accepted",false)):_open_member_detail(entity_id)
		_request_refresh();return
	if member_detail_modal.visible:_close_member_detail()
	notice_text="%s을(를) 공격했습니다. 이제 적대합니다."%str(result.get("target_name","NPC"))
	action_feedback_text=notice_text
	var status:Dictionary=session.party_status()
	if _is_solo_product_session():_submit_product_melee(entity_id,status)
	_request_refresh()

func _on_recruit_companion(entity_id:int)->void:
	var status:Dictionary=session.party_status()
	var direct_guild_candidate:bool=str(status.get("view_mode",""))=="TOWN" \
		and session.has_method("rescue_story_state") \
		and str(session.rescue_story_state(entity_id)).is_empty()
	var result:Dictionary=session.recruit_companion(entity_id) \
		if direct_guild_candidate else session.offer_recruitment(entity_id)
	if not bool(result.get("accepted",false)):
		notice_text=str(result.get("message","영입할 수 없습니다."));action_feedback_text=notice_text
	else:
		notice_text="길드 후보가 장비를 챙겨 파티에 합류했습니다." \
			if direct_guild_candidate else ("새 동료가 파티에 합류했습니다." if bool(result.get("joined",true)) \
			else "영입 제안을 거절했습니다. 판정과 이유를 사건 기록에 남겼습니다."
			)
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
	if companion_order_editor!=null and companion_order_editor.visible:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			companion_order_editor.close()
		get_viewport().set_input_as_handled();return
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
	_record_result(result,true)
	var status:Dictionary=session.party_status()
	# The product D-pad is a one-step hot path. Its shell already exists, so
	# rebuilding every card, dock and navigation button adds a visible dead frame.
	if _is_solo_product_session() and str(status.get("view_mode",""))=="EXPLORATION":
		_refresh_continuous_exploration_surface(status)
	else:_request_refresh()
func _on_restart_same_run()->void:
	if session==null or not session.has_method("restart_same_run"):
		notice_text="이 원정을 다시 시작할 수 없습니다.";_request_refresh();return
	var result:Variant=session.call("restart_same_run")
	if not result is Dictionary or not bool(result.get("accepted",false)):
		var message:="이 원정을 다시 시작할 수 없습니다." if not result is Dictionary \
			else str(result.get("message","이 원정을 다시 시작할 수 없습니다."))
		notice_text=message;action_feedback_text=message;_request_refresh();return
	_reset_run_ui_transients()
	if session.is_duo_autobattle():show_species_picker_for_new_run()
	else:_request_refresh()

func _on_restart_with_new_personality()->void:
	if session==null or not session.has_method("restart_with_personality_seed"):
		notice_text="새 성격으로 원정을 다시 시작할 수 없습니다.";_request_refresh();return
	var fresh_seed:=_issue_new_personality_seed(int(session.personality_seed))
	var result:Variant=session.call("restart_with_personality_seed",fresh_seed)
	if not result is Dictionary or not bool(result.get("accepted",false)):
		var message:="새 성격으로 원정을 다시 시작할 수 없습니다." if not result is Dictionary \
			else str(result.get("message","새 성격으로 원정을 다시 시작할 수 없습니다."))
		notice_text=message;action_feedback_text=message;_request_refresh();return
	_reset_run_ui_transients()
	if session.is_duo_autobattle():show_species_picker_for_new_run()
	else:_request_refresh()

func _reset_run_ui_transients()->void:
	portrait_gesture=preload("res://playtest/portrait_gesture.gd").new()
	if companion_order_editor!=null:
		companion_order_editor.visible=false;companion_order_editor.actor_id=-1
	_reset_auto_flow();route_generation+=1;_clear_route_continue_schedule()
	_product_auto_explore_generation+=1;_product_auto_explore_pending=false
	_product_auto_explore_due_frame=-1;_product_auto_explore_due_msec=-1
	_product_auto_explore_scheduled_generation=-1
	_product_auto_last_hop_started_msec=-1
	route_last_hop_started_msec=-1
	_product_auto_stop_feedback="";_product_transient_event_feedback=""
	_product_attack_targeting=false
	_clear_battle_targeting_state();_battle_target_committing=false
	_product_touch_index=-1;_product_touch_control="";_product_touch_dragged=false
	_product_touch_started_msec=-1;_product_immediate_touch_indices.clear()
	_product_mouse_control="";_product_ignore_mouse_until_msec=-1
	_reset_product_pinch_zoom()
	route_paused_by_modal=false;route_paused_by_pointer=false;route_preview.clear()
	_clear_move_preview();_clear_companion_follow_plan();_hide_tile_popover()
	selected_member_id=-1;selected_target_id=-1;notice_text="";action_feedback_text="";_action_feedback_phase=""
	selected_base_building_id="STORAGE";town_facility_id="";_last_view_mode=""
	town_ui_state={"filter":"ADVENTURERS","resident":-1,"trade":"BUY","owner":-1}
	_pending_card_pointer.clear();_last_card_tap_id=-1;_last_card_tap_msec=-1000
	_last_card_tap_position=Vector2(-10000,-10000);_direct_card_touch_id=-1;_direct_card_touch_msec=-1000
	_scroll_log_after_refresh=false;_run_locked_exit_feedback=false
	_reward_emphasis_pending=false;_run_progress_initialized=false;_observed_reward_granted=false
	_pending_visual_effect_rows.clear()
	if _reward_emphasis_tween!=null and _reward_emphasis_tween.is_valid():_reward_emphasis_tween.kill()
	if reward_badge!=null:reward_badge.modulate=Color.WHITE
	if member_detail_modal!=null:member_detail_modal.visible=false
	if base_modal!=null:base_modal.visible=false
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
	if session!=null and session.is_duo_autobattle():return
	var action_started:=Time.get_ticks_usec()
	var status:Dictionary=session.party_status();var protagonist_id:=int(status.get("protagonist_id",-1))
	# Companion selection is observation-only in the product party loop. Every
	# ordinary combat tap remains a protagonist action; individual override stays
	# available only through the internal session API and regression harnesses.
	if selected_member_id!=protagonist_id:
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
			_record_result(result,true,"자동 실행 불가",true,
				EXPLORATION_ACTOR_MOTION_MSEC if action_type=="MOVE" else -1)
			_clear_move_preview()
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
	if not _battle_target_mode.is_empty():
		if _battle_target_skill_id in preload("res://sim/abilities/active_skill_registry.gd").GROUND_SKILLS and session.field_turns_active():
			if _battle_target_committing:return
			_battle_target_committing=true
			var result:Dictionary=session.commit_field_action(ActionScript.skill_at(
				_battle_target_actor_id,_battle_target_skill_id,position))
			_battle_target_committing=false
			if result.get("accepted",false):
				_cancel_battle_targeting()
				_record_result(result,true,"환경 기술 실행 불가")
				_show_manual_battle_feedback("환경 기술 사용 · 물·얼음·수증기·전도 반응을 확인하세요.")
			else:_show_manual_battle_feedback(str(result.get("message",result.get("reason","사용 불가"))))
			_request_refresh();return
		_cancel_battle_targeting("대상 선택을 취소했습니다.");return
	_retreat_active=false
	if companion_order_editor!=null and companion_order_editor.visible:
		companion_order_editor.pick_cell(position);return
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
			# Adjacent taps need no macro-route snapshot/hash/path DTO. Let the canonical
			# one-cell commit perform its own action plan exactly once; doing a separate
			# preview here made Web touch movement plan the same step three times. A
			# rejected direct step still falls through to the route finder so an adjacent
			# destination can retain its established legal-detour behavior.
			var command=CommandScript.move_to(int(status.protagonist_id),position)
			var result:Dictionary=session.commit_exploration(command,true)
			if bool(result.get("accepted",false)):
				route_generation+=1;_clear_route_continue_schedule();route_preview.clear()
				_clear_move_preview();_clear_companion_follow_plan()
				_record_result(result,true,"%s 이동 불가"%_protagonist_name())
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
	if session.is_duo_autobattle():
		if battle_mode=="HERO_TURN" and position==Vector2i(int(status.protagonist_position[0]),
				int(status.protagonist_position[1])):
			_release_hero_turn("이번 차례 · 자동 행동");return
		_reserve_battle_move(int(status.protagonist_id),position);return
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
func _focus_battle_enemy(entity_id:int)->void:
	if session.field_turns_active():
		_on_actor(entity_id);return
	# Portrait tap: party focus during a fight; before contact it is the same as
	# tapping the enemy on the map (strike when adjacent, hint otherwise).
	if not _portrait_battle_controls_visible():_strike_visible_enemy(entity_id);return
	var result:Dictionary=session.issue_party_command("ATTACK_TARGET",entity_id)
	if result.get("accepted",false):
		selected_target_id=entity_id;_hero_turn_released=true
		grid.set_selection(selected_member_id,entity_id);grid.set_actor_emphasis(entity_id,1400)
		_show_manual_battle_feedback("집중공격 · %s"%_entity_display_name(entity_id))
	else:_show_manual_battle_feedback("공격 대상을 지정할 수 없습니다.")
	_refresh_battle_surface_lightly()

func _on_actor(entity_id:int)->void:
	if _battle_target_skill_id in preload("res://sim/abilities/active_skill_registry.gd").GROUND_SKILLS and session.sim.world.entities.has(entity_id):
		_on_cell(session.sim.world.entities[entity_id].position);return
	if not _battle_target_mode.is_empty():
		_commit_battle_target(entity_id);return
	if companion_order_editor!=null and companion_order_editor.visible:
		companion_order_editor.pick_actor(entity_id);return
	if _party_command_targeting and _portrait_battle_controls_visible():
		if entity_id not in session.party_status().get("visible_enemy_ids",[]):
			_show_product_command_feedback("보이는 적을 누르세요.");return
		_party_command_targeting=false;_retreat_active=false
		var focus:Dictionary=session.issue_party_command("ATTACK_TARGET",entity_id)
		if bool(focus.get("accepted",false)):
			selected_target_id=entity_id;autonomous_battle_clock.paused=false
			grid.set_selection(selected_member_id,entity_id);grid.set_actor_emphasis(entity_id,1400)
			_release_hero_turn("집중 공격 · %s"%_entity_display_name(entity_id))
		else:_show_product_command_feedback(str(focus.get("message",focus.get("reason","지정할 수 없습니다."))))
		_request_refresh();return
	if _portrait_battle_controls_visible() and entity_id in session.party_status().get("visible_enemy_ids",[]):
		_strike_visible_enemy(entity_id);return
	var status:Dictionary=session.party_status()
	_hide_tile_popover()
	if bool(_current_run_progress().get("terminal",false)):return
	if str(status.get("view_mode",""))=="EXPLORATION":
		_cancel_product_auto_explore("auto_explore_user_command",false)
		if bool(session.exploration_route_state().get("has_preview",false)):
			_cancel_active_route()
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
	if session.field_turns_active() and entity_id in status.party_member_ids:
		_switch_field_member(entity_id);return
	if status.view_mode=="EXPLORATION" \
			and session.has_method("is_opening_npc") \
			and bool(session.is_opening_npc(entity_id)):
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
			_pickup_everything_here();_request_refresh();return
		var hero_position:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
		if pending_move_mode=="EXPLORATION" and pending_exploration_wait:
			var result:Dictionary=session.commit_exploration(CommandScript.wait(entity_id)); _clear_move_preview(); _record_result(result,true)
		else:
			var preview:Dictionary=session.preview_exploration(CommandScript.wait(entity_id)); pending_move_mode="EXPLORATION"; pending_exploration_wait=true
			pending_move_actor_id=entity_id; pending_move_origin=hero_position; pending_move_destination=hero_position
			pending_move_valid=bool(preview.get("accepted",false)); pending_move_cost=int(preview.get("time_cost",0)); notice_text="현재 칸을 한 번 더 누르면 대기합니다."
			action_feedback_text="대기 미리보기 · 현재 칸을 한 번 더 누르세요." if pending_move_valid else str(preview.get("message","대기할 수 없습니다."))
		_request_refresh(); return
	if entity_id in status.visible_enemy_ids or entity_id in status.get("enemies_in_view",[]):
		selected_target_id=entity_id; _clear_move_preview()
		if session.is_duo_autobattle():_strike_visible_enemy(entity_id);return
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
	if session.field_turns_active():
		var result:Dictionary=session.strike_enemy(entity_id)
		_record_result(result,true,"공격할 수 없습니다.")
		if bool(result.get("accepted",false)):
			selected_target_id=entity_id
			grid.set_selection(selected_member_id,entity_id)
		_request_refresh()
		return bool(result.get("accepted",false))
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
	# Arriving on a cell with loot picks it all up (a bounded run of journaled
	# 100-time pickups), not just the item that was tapped. Only while nothing
	# hostile is in view; each pickup is still an ordinary canonical action.
	var status:Dictionary=session.party_status()
	if str(status.get("view_mode",""))!="EXPLORATION":return
	if session.ground_items_at_protagonist().is_empty():
		pending_ground_pickup_id="";pending_ground_pickup_label="";return
	pending_ground_pickup_id="";pending_ground_pickup_label=""
	_pickup_everything_here()

func _pickup_everything_here()->void:
	var status:Dictionary=session.party_status()
	if not (status.get("visible_enemy_ids",[]) as Array).is_empty():
		var single:Array=session.ground_items_at_protagonist()
		if single.is_empty():return
		var one:Dictionary=session.pickup_ground_item(str(single[0].instance_id))
		_record_result(one,true,"아이템을 주울 수 없습니다.")
		if bool(one.get("accepted",false)):
			notice_text="%s 가방에 주웠습니다 · 적이 보여 나머지는 남겼습니다"%str(single[0].label);action_feedback_text=notice_text
		return
	var taken:Array[String]=[];var failure:=""
	for _attempt in range(6):
		var rows:Array=session.ground_items_at_protagonist()
		if rows.is_empty():break
		var result:Dictionary=session.pickup_ground_item(str(rows[0].instance_id))
		_record_result(result,true,"아이템을 주울 수 없습니다.")
		if not bool(result.get("accepted",false)):
			failure=str(result.get("message","아이템을 주울 수 없습니다."));break
		taken.append(str(rows[0].label))
		if str(session.party_status().get("view_mode",""))!="EXPLORATION":break
	if taken.is_empty():
		if not failure.is_empty():notice_text=failure;action_feedback_text=notice_text
		return
	var remaining:int=session.ground_items_at_protagonist().size()
	notice_text="%s 가방에 주웠습니다 (%d시간)%s"%[", ".join(taken),taken.size()*100,
		"" if remaining==0 and failure.is_empty() else " · %s"%(failure if not failure.is_empty() else "%d개 남음"%remaining)]
	action_feedback_text=notice_text

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
	if expected_generation!=route_generation or route_paused_by_pointer:return
	if route_paused_by_modal or member_detail_modal.visible:
		route_paused_by_modal=true;return
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
	_cancel_product_rest("rest_user_stop")
	if grid!=null and grid.pointer_gesture_state().get("target_kind","")=="INSPECT":
		route_paused_by_pointer=true
		if auto_orchestration_enabled:_cancel_auto_pending(false)
		return
	_cancel_product_auto_explore("auto_explore_user_command",false)
	if grid!=null and grid.pinch_zoom_enabled:
		route_paused_by_pointer=true
	else:_cancel_route_for_user_interruption()
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
	if grid==null or not grid.pinch_zoom_enabled:route_paused_by_pointer=false

func _on_grid_pointer_finished(_outcome:String)->void:
	if _product_pinch_gesture_active:return
	route_paused_by_pointer=false
	_schedule_route_continue()
	if _refresh_after_pointer:
		_refresh_after_pointer=false
		_request_refresh()

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
		_maybe_open_battle_loot.call_deferred()
		# Only a committed live UI action may arm the reward highlight. A loaded
		# save or an arbitrary refresh synchronizes the badge without replaying it.
		if _run_progress_initialized and not _observed_reward_granted:
			var progress:=_current_run_progress()
			var reward:Dictionary=progress.get("reward",{}) if progress.get("reward",{}) is Dictionary else {}
			_reward_emphasis_pending=bool(reward.get("granted",false))
		if scroll_combat_log:_scroll_log_after_refresh=true
		var ground_item_notice:=str(result.get("ground_item_notice",""))
		if not ground_item_notice.is_empty():
			notice_text=ground_item_notice;action_feedback_text=ground_item_notice
			_product_transient_event_feedback=ground_item_notice
		else:
			notice_text="";action_feedback_text="턴이 처리되었습니다. 다음 행동을 지정하세요." if consume_effects else (
				"행동이 준비되었습니다." if auto_orchestration_enabled else "행동이 준비되었습니다. 지금 실행을 누르세요.")
		_settle_solo_product_contact()
		if not str(result.get("companion_order_notice","")).is_empty():
			notice_text=str(result.companion_order_notice);action_feedback_text=notice_text
			_product_transient_event_feedback=notice_text
	else:
		notice_text=str(result.get("message","행동을 처리할 수 없습니다."));_set_action_rejection(result,rejection_prefix)

func _maybe_open_battle_loot(force:bool=false)->void:
	if session==null or battle_loot_panel==null:return
	var loot:Dictionary=session.battle_loot()
	var battle_id:=int(loot.battle_id)
	if battle_id<=0 or (not force and battle_id==_shown_loot_battle_id):return
	if grid.modal_open and not battle_loot_panel.visible:return
	_shown_loot_battle_id=battle_id
	if loot.rows.is_empty():return
	_cancel_product_auto_explore("battle_loot",false)
	_cancel_active_route()
	grid.cancel_pointer_gesture();grid.modal_open=true
	battle_loot_panel.show()
	battle_loot_panel.configure(session.protagonist_inventory(),loot)

func _take_battle_loot(battle_id:int,instance_id:String)->void:
	var result:Dictionary=session.take_battle_loot(battle_id,instance_id)
	var message:="가방에 담았습니다." if result.get("accepted",false) else (
		"가방이 가득 찼습니다. 전리품은 바닥에 남아 있습니다." if str(result.get("reason","")).contains("full") \
		else "지금 가져올 수 없는 아이템입니다.")
	# Rebuild after the pressed button's input dispatch has completed.
	_refresh_battle_loot.call_deferred(message)
	_request_refresh()

func _refresh_battle_loot(message:String)->void:
	if battle_loot_panel!=null and battle_loot_panel.visible:
		battle_loot_panel.configure(session.protagonist_inventory(),session.battle_loot(),message)

func _close_battle_loot()->void:
	battle_loot_panel.hide()
	grid.modal_open=member_detail_modal.visible or record_modal.visible or base_modal.visible or map_overlay.visible
	route_paused_by_modal=false
	_request_refresh()

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
	var result:Dictionary=session.settle_contact()
	if not bool(result.get("accepted",false)):
		_set_action_rejection(result,"조우 처리 불가")
	auto_phase=str(session.party_status().get("safe_phase",""))

func _flush_pending_visual_effects()->int:
	var _pfp:=PerfProbeScript.begin()
	battle_command_flow.paint(self)
	PerfProbeScript.end("fx.paint",_pfp)
	var _pfs:=PerfProbeScript.begin()
	if battle_enemy_strip!=null:battle_enemy_strip.sync(self)
	PerfProbeScript.end("fx.enemy_strip",_pfs)
	var _pft:=PerfProbeScript.begin()
	PerfProbeScript.end("fx.timeline",_pft)
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
	var frame:=tile_popover.find_child("TileRiskPixelFrame",true,false) as MarginContainer
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
	var frame:=tile_popover.find_child("TileRiskPixelFrame",true,false) as MarginContainer
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
	var affinity:Dictionary=detail.get("species_affinity",{}) if detail.get("species_affinity",{}) is Dictionary else {}
	var affinity_values:=[int(affinity.get("fire_tolerance",0)),int(affinity.get("water_tolerance",0)),
		int(affinity.get("electric_tolerance",0)),int(affinity.get("poison_tolerance",0))]
	if affinity_values.any(func(value):return int(value)!=0):
		lines.append("원소 내성 · 불 %d · 물 %d · 전기 %d · 독 %d"%affinity_values)
	var action:Variant=detail.get("expected_action",null)
	if action is Dictionary:
		lines.append("행동 제안 · %s"%_compact_action(action))
		var action_reason:=str(action.get("reason","")).strip_edges()
		if not action_reason.is_empty() and action_reason!="-":lines.append("· "+action_reason)
		var original:Variant=action.get("automatic_suggestion",null)
		if original is Dictionary:lines.append("원래 자동 제안: %s"%_action_only(original))
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
	var groups:Variant=history.get("groups",[])
	var collected:Array[String]=[]
	if _product_rest_active:collected.append(notice_text)
	if groups is Array:
		for group_index in range(groups.size()-1,-1,-1):
			if collected.size()>=3:break
			var group:Variant=groups[group_index]
			if not group is Dictionary:continue
			var damage_lines:Array[String]=[];var other_lines:Array[String]=[]
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
			if damage_lines.is_empty() and other_lines.is_empty():continue
			# Damage wins only inside the newest meaningful turn. Older combat
			# damage must never pin the compact feed while newer loot/level/world
			# events are already visible in the full record.
			var lines:Array[String]=damage_lines.slice(0,mini(3,damage_lines.size()))
			for message in other_lines:
				if lines.size()>=3:break
				lines.append(message)
			# Newest turn first; older turns fill the remaining lines of the
			# three-line feed so the last few moments stay readable.
			for message in lines:
				if collected.size()>=3:break
				collected.append(message)
	return "\n".join(collected)

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
	var danger:=node_name in ["MemberDetailDismiss","MemberDetailAttack",
		"NearbyNpcAttack","RestartExpedition"]
	var accent:=DarkPixelSkinScript.BLOOD if danger else (DarkPixelSkinScript.BRASS \
		if node_name in ["TurnConfirm","AutoExecute","DeployConfirm"] else DarkPixelSkinScript.CYAN)
	DarkPixelSkinScript.apply_action_button(button,accent,danger);return button
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

func _current_grid_view_dimensions()->Vector2i:
	var base_count:=_current_grid_view_cell_count()
	if not _is_solo_product_session():return Vector2i(base_count,base_count)
	var status:Dictionary=session.party_status()
	var members:Variant=status.get("party_member_ids",[])
	var party_count:int=members.size() if members is Array else 1
	var party_height:=int(party_card_layout_spec(party_count,size.x).get(
		"party_height",PRODUCT_PARTY_CARD_HEIGHT))
	var separation:=4 if size.x>=450.0 else 0
	# HUD, map, event feed, hero skill row, party, command dock: the same stack in
	# exploration and in a fight, so the map never changes size on contact.
	# Projection must not depend on the previous refresh\'s skill visibility.
	var skill_row_height:int=48
	var map_extent:=Vector2(maxf(1.0,size.x),maxf(1.0,size.y
		-PRODUCT_TOP_HUD_HEIGHT-PRODUCT_EVENT_HEIGHT-skill_row_height-party_height-48
		-separation*5))
	var cell_size:=minf(map_extent.x,map_extent.y)/float(maxi(1,base_count))
	# Round the long axis outward: a sub-cell (at most one row/column) reduction
	# in sprite scale is preferable to leaving an otherwise useless black strip.
	var columns:=clampi(int(ceil(map_extent.x/cell_size-0.001)),1,63)
	var rows:=clampi(int(ceil(map_extent.y/cell_size-0.001)),1,63)
	# Odd dimensions keep the protagonist on a real center tile rather than on
	# the seam between two rows while still filling the long screen axis.
	if columns%2==0:columns=mini(63,columns+1)
	if rows%2==0:rows=mini(63,rows+1)
	return Vector2i(columns,rows)

func _sync_product_zoom_controls(product_hud:bool)->void:
	if grid_zoom_controls==null:return
	grid.pinch_zoom_enabled=product_hud
	var front_surface_open:bool=grid!=null and grid.modal_open \
		or member_detail_modal!=null and member_detail_modal.visible \
		or record_modal!=null and record_modal.visible \
		or map_overlay!=null and map_overlay.visible
	# Gesture-only zoom: compatibility nodes stay hidden and have no hit surface.
	grid_zoom_controls.visible=false
	if not product_hud or front_surface_open:_reset_product_pinch_zoom()
	var zoom_index:=PRODUCT_ZOOM_CELL_COUNTS.find(_product_zoom_cell_count)
	if zoom_index<0:
		_product_zoom_cell_count=PRODUCT_ZOOM_DEFAULT_CELL_COUNT
		zoom_index=PRODUCT_ZOOM_CELL_COUNTS.find(_product_zoom_cell_count)
	grid_zoom_out_button.disabled=zoom_index>=PRODUCT_ZOOM_CELL_COUNTS.size()-1
	grid_zoom_in_button.disabled=zoom_index<=0
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

func _product_zoom_control_has_point(_global_position:Vector2)->bool:
	return false

func _product_pinch_available()->bool:
	return _is_solo_product_session() and grid!=null and grid.visible \
		and not grid.modal_open \
		and (member_detail_modal==null or not member_detail_modal.visible) \
		and (record_modal==null or not record_modal.visible) \
		and (map_overlay==null or not map_overlay.visible)

func _product_pinch_point_allowed(position:Vector2)->bool:
	if not _product_pinch_available() or not grid.get_global_rect().has_point(position):
		return false
	return nearby_npc_panel==null or not nearby_npc_panel.is_visible_in_tree() \
		or not nearby_npc_panel.get_global_rect().has_point(position)

func _product_pinch_distance()->float:
	if _product_pinch_points.size()<2:return 0.0
	var indices:Array=_product_pinch_points.keys();indices.sort()
	return Vector2(_product_pinch_points[indices[0]]).distance_to(
		Vector2(_product_pinch_points[indices[1]]))

func _reset_product_pinch_zoom()->void:
	_product_pinch_points.clear();_product_pinch_last_distance=0.0
	_product_pinch_gesture_active=false;_product_magnify_accumulator=1.0

func _consume_product_pinch_event()->bool:
	get_viewport().set_input_as_handled();return true

func _apply_product_pinch_distance(current_distance:float)->void:
	if current_distance<=0.0:return
	if _product_pinch_last_distance<=0.0:
		_product_pinch_last_distance=current_distance;return
	var ratio:=current_distance/_product_pinch_last_distance
	if ratio>=PRODUCT_PINCH_STEP_RATIO:
		_on_product_zoom_step(-1);_product_pinch_last_distance=current_distance
	elif ratio<=1.0/PRODUCT_PINCH_STEP_RATIO:
		_on_product_zoom_step(1);_product_pinch_last_distance=current_distance

func _handle_product_pinch_zoom(event:InputEvent)->bool:
	if event is InputEventMagnifyGesture:
		if not _product_pinch_available() \
				or not grid.get_global_rect().has_point(event.position):return false
		_product_magnify_accumulator*=maxf(0.01,event.factor)
		if _product_magnify_accumulator>=PRODUCT_PINCH_STEP_RATIO:
			_on_product_zoom_step(-1);_product_magnify_accumulator=1.0
		elif _product_magnify_accumulator<=1.0/PRODUCT_PINCH_STEP_RATIO:
			_on_product_zoom_step(1);_product_magnify_accumulator=1.0
		return _consume_product_pinch_event()
	if not event is InputEventScreenTouch and not event is InputEventScreenDrag:return false
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _product_pinch_point_allowed(event.position):return false
			_product_pinch_points[event.index]=event.position
			if _product_pinch_points.size()<2:return false
			_product_pinch_gesture_active=true
			_product_pinch_last_distance=_product_pinch_distance()
			grid.cancel_pointer_gesture()
			return _consume_product_pinch_event()
		if not _product_pinch_points.has(event.index):return false
		var consumed:=_product_pinch_gesture_active
		_product_pinch_points.erase(event.index)
		if _product_pinch_points.is_empty():
			_reset_product_pinch_zoom();route_paused_by_pointer=false
			_schedule_route_continue()
		return _consume_product_pinch_event() if consumed else false
	if not _product_pinch_points.has(event.index):return false
	_product_pinch_points[event.index]=event.position
	if not _product_pinch_gesture_active:return false
	_apply_product_pinch_distance(_product_pinch_distance())
	return _consume_product_pinch_event()

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
	var view_dimensions:=_current_grid_view_dimensions()
	var ui_observation:Dictionary=session.observe_party_ui(view_dimensions.x,false,
		view_dimensions.y)
	grid.set_observation(ui_observation.get("grid",{}),[])
	var hero_position:=Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	grid.set_hero_centered_view(hero_position,view_dimensions.x,
		int(status.protagonist_id),MANUAL_CAMERA_SETTLE_MSEC,view_dimensions.y)

func _is_solo_product_session()->bool:
	return session!=null and session.has_method("is_solo_combat") \
		and bool(session.call("is_solo_combat"))

func _is_direct_solo_combat(status:Dictionary)->bool:
	if session!=null and session.is_duo_autobattle():return false
	var members:Variant=status.get("party_member_ids",[])
	return _is_solo_product_session() and auto_orchestration_enabled \
		and str(status.get("safe_phase",""))=="ENGAGED" \
		and str(status.get("view_mode",""))=="COMBAT" \
		and members is Array and members.size()==1 \
		and selected_member_id==int(status.get("protagonist_id",-1))
func _clear_container(container:Control)->void:
	for child in container.get_children():container.remove_child(child); child.free()
func _phase(value:String)->String:
	if value=="ENGAGED" and session!=null and session.is_duo_autobattle():return "자동 전투"
	if value=="ENGAGED" and _is_solo_product_session():return "단독 전투"
	return {"GROUPED":"탐험","CONTACT":"조우 배치","ENGAGED":"파티 전투","REGROUP_READY":"자동 재집결","GROUPED_COMPLETE":"탐험 재개","PARTY_DEFEATED":"패배"}.get(value,value)
func _presence(value:String)->String:return {"DEPLOYED":"배치","GROUPED":"동행","DORMANT":"전투 대기","RECRUITABLE":"영입 후보","EXILED":"추방됨","DEFEATED":"쓰러짐"}.get(value,value)
func _role(value:String)->String:return {"PROTAGONIST":"주인공","COMPANION":"동료"}.get(value,value)
func _species(value:String)->String:return {"human":"인간","elf":"엘프","dwarf":"드워프",
	"orc":"오크","beastkin":"수인","goblin":"고블린","default":"미상"}.get(value,value)
func _on_product_menu_id(item_id:int)->void:
	if session==null:return
	if item_id in [20,21,22,23]:
		var id:String={20:"TEST_WATER",21:"TEST_FROST",22:"TEST_SPARK",23:"FIREBALL"}[item_id]
		if _battle_target_skill_id!=id:_cancel_battle_targeting()
		_on_manual_skill_selected(session.sim.world.party_encounter.protagonist_id,id,
			str(preload("res://sim/abilities/active_skill_registry.gd").definition(id).name))
		return
	match item_id:
		0:
			if bool(_current_run_progress().get("terminal",false)):
				_on_restart_same_run();return
			if product_restart_confirm==null:
				product_restart_confirm=ConfirmationDialog.new()
				product_restart_confirm.name="ProductRestartConfirm"
				product_restart_confirm.title="다시 시작"
				product_restart_confirm.dialog_text="진행 중인 원정을 버리고 같은 원정을 처음부터 다시 시작할까요?"
				product_restart_confirm.ok_button_text="다시 시작"
				product_restart_confirm.cancel_button_text="취소"
				product_restart_confirm.confirmed.connect(_on_restart_same_run)
				add_child(product_restart_confirm)
			product_restart_confirm.popup_centered()
		1:
			var fresh_seed:=_issue_new_personality_seed(int(session.personality_seed))
			if session.reset_party(session.world_seed,fresh_seed,SessionScript.DUO_SCENARIO_ID,
					{},false,"human",true,true,true,false,false,true):
				show_species_picker_for_new_run()
			else:
				notice_text="새 게임을 시작하지 못했습니다.";_request_refresh()
		2:_open_hero_detail_tab("STATUS")
		3:_open_hero_detail_tab("SKILL")
		4:_open_hero_detail_tab("ITEM")
		5:_toggle_record_modal()
		6:_open_active_combat_lab()
		7:_open_base_modal()

func expedition_hud_spec(status:Dictionary={})->Dictionary:
	var cycle:Dictionary=session.expedition_cycle_status() \
		if session!=null and session.has_method("expedition_cycle_status") else {}
	var phase:=str(cycle.get("phase","UNAVAILABLE"))
	var remaining:=int(cycle.get("remaining_world_time",0))
	var band:=str(cycle.get("warning_band","UNAVAILABLE"))
	var tone:Color=AsciiFrameScript.INK
	if band=="CRITICAL" or band=="CLOSED":tone=AsciiFrameScript.DANGER
	elif band=="WARNING":tone=AsciiFrameScript.BRASS
	var floor_text:="F%d"%int(cycle.get("floor_index",1)) if phase=="DUNGEON" else ""
	var timer_text:=""
	if phase=="DUNGEON":
		timer_text="귀환" if remaining<=0 else "%s시간"%_grouped_number(remaining)
	# The per-hop callers already hold a party status; recomputing it here would
	# repeat the whole DTO (and its own cycle query) on every step.
	var party:Dictionary=status
	if party.is_empty():party=session.party_status() if session!=null else {}
	var ration_band:=str(party.get("ration_band","FED"))
	var ration_max:=maxi(1,int(party.get("ration_max",1)))
	var filled:=clampi(int(ceil(float(int(party.get("ration",0)))*4.0/float(ration_max))),0,4)
	# LivingWorldMonoKR contains U+25A0/U+25A1, while the previously used
	# U+25AE/U+25AF pair had no glyph and rendered as missing-character boxes.
	var ration_text:="굶주림" if ration_band=="STARVING" else "식량 "+"■".repeat(filled)+"□".repeat(4-filled)
	var ration_tone:Color=AsciiFrameScript.INK
	if ration_band=="STARVING":ration_tone=AsciiFrameScript.DANGER
	elif ration_band=="HUNGRY":ration_tone=AsciiFrameScript.BRASS
	return {"phase":phase,"floor_text":floor_text,"timer_text":timer_text,
		"warning_band":band,"remaining_world_time":remaining,"tone_hex":tone.to_html(false),
		"ration_text":ration_text,"ration_band":ration_band,
		"ration_tone_hex":ration_tone.to_html(false)}.duplicate(true)

func _grouped_number(value:int)->String:
	var digits:=str(absi(value));var grouped:=""
	for index in range(digits.length()):
		if index>0 and (digits.length()-index)%3==0:grouped+=","
		grouped+=digits[index]
	return ("-" if value<0 else "")+grouped

func _update_expedition_hud(product_hud:bool,status:Dictionary={})->void:
	if expedition_floor_label==null or return_timer_label==null:return
	if product_hud:phase_label.visible=false
	var spec:=expedition_hud_spec(status) if product_hud else {}
	var floor_text:=str(spec.get("floor_text",""));var timer_text:=str(spec.get("timer_text",""))
	expedition_floor_label.text=floor_text;expedition_floor_label.visible=product_hud and not floor_text.is_empty()
	return_timer_label.text=timer_text;return_timer_label.visible=product_hud and not timer_text.is_empty()
	return_timer_label.add_theme_color_override("font_color",Color(str(spec.get("tone_hex","c7c2b3"))))
	if ration_label!=null:
		var ration_text:=str(spec.get("ration_text",""))
		ration_label.text=ration_text
		ration_label.visible=product_hud and not ration_text.is_empty() \
			and str(spec.get("phase",""))=="DUNGEON"
		ration_label.add_theme_color_override("font_color",
			Color(str(spec.get("ration_tone_hex","c7c2b3"))))

func _apply_screen_budget(combat_active:bool,combat_actions_visible:bool,
		run_available:bool=false,run_terminal:bool=false,party_height:int=160,
		product_hud:bool=false)->void:
	var wide:=size.x>=450.0
	phase_panel.custom_minimum_size.y=PRODUCT_TOP_HUD_HEIGHT if product_hud else (52 if wide else 48)
	# Compact portrait has no gaps; desktop keeps a little rail separation while
	# the expanding map owns all remaining height.
	root_layout.add_theme_constant_override("separation",4 if wide else (0 if product_hud else 2))
	combat_action_area.custom_minimum_size.y=84 if combat_actions_visible else 0
	if product_hud:
		grid.custom_minimum_size=Vector2(size.x,1)
		grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.size_flags_vertical=Control.SIZE_EXPAND_FILL
		hud_bottom_flex.visible=false
		var status:Dictionary=session.party_status()
		var members:Variant=status.get("party_member_ids",[])
		var product_metrics:=_product_controls_metrics(members.size() if members is Array else 1)
		combat_action_area.custom_minimum_size.y=int(product_metrics.get("dock_height",124))
	elif wide:
		grid.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		grid.size_flags_vertical=Control.SIZE_FILL
		grid.custom_minimum_size=Vector2(405,405)
	elif combat_active:
		grid.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		grid.size_flags_vertical=Control.SIZE_FILL
		grid.custom_minimum_size=Vector2(248,248) if run_available else Vector2(300,300)
	else:
		grid.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		grid.size_flags_vertical=Control.SIZE_FILL
		grid.custom_minimum_size=Vector2(276,276) \
			if run_available and (run_terminal or _run_locked_exit_feedback) \
			else (Vector2(316,316) if run_available else Vector2(348,348))
	cards.custom_minimum_size.y=maxi(0,party_height)
	info_scroll.custom_minimum_size.y=30
	event_surface.custom_minimum_size.y=PRODUCT_EVENT_HEIGHT
	if hero_skill_row!=null:hero_skill_row.custom_minimum_size.y=48 if product_hud else 0
	bottom_navigation.custom_minimum_size.y=TOUCH_TARGET

func _apply_phase_banner(status:Dictionary,presentation:Dictionary)->void:
	var banner:Dictionary=presentation.get("banner",{})
	var tone:=str(banner.get("tone","CALM"))
	var situation:="조용함"
	if str(status.get("view_mode",""))=="TOWN":situation="마을"
	elif tone=="DEFEAT":situation="위험"
	elif tone=="VICTORY" or str(status.get("safe_phase",""))=="GROUPED_COMPLETE":situation="승리"
	elif str(status.get("safe_phase",""))=="ENGAGED":situation="전투"
	elif str(status.get("safe_phase",""))=="CONTACT" \
			or not status.get("visible_enemy_ids",[]).is_empty():situation="기척"
	var surface_color:=AsciiFrameScript.NAVY
	if situation=="마을":
		surface_color=Color("#25190f")
		phase_label.add_theme_font_size_override("font_size",FONT_KEY)
		phase_label.add_theme_color_override("font_color",AsciiFrameScript.BRASS)
		grid.set_combat_emphasis(false)
	elif situation=="전투":
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
	if situation=="마을" and session.town_life_enabled():phase_label.text="마을  ·  %d G"%session.town_gold()
	var phase_style:=DarkPixelSkinScript.panel_surface(DarkPixelSkinScript.FOLIO,
		DarkPixelSkinScript.IRON_EDGE,0,1)
	phase_panel.add_theme_stylebox_override("panel",phase_style)
	phase_panel.set_meta("visible_stylebox_border",true)
	phase_panel.set_meta("visual_family",DarkPixelSkinScript.VISUAL_FAMILY)
	if minimap_frame!=null:
		var glyph_tone:=DarkPixelSkinScript.CYAN
		if situation=="승리":glyph_tone=AsciiFrameScript.JADE
		elif situation in ["전투","위험"]:glyph_tone=DarkPixelSkinScript.BLOOD
		elif situation=="기척":glyph_tone=DarkPixelSkinScript.BRASS
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
