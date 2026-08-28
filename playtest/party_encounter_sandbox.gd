class_name PartyEncounterSandbox
extends Control

const SessionScript=preload("res://playtest/party_playtest_session.gd")
const GridScript=preload("res://playtest/party_grid_view.gd")
const CommandScript=preload("res://sim/sim_command.gd")
const KoreanFont:FontFile=preload("res://assets/fonts/NanumSquareR.ttf")
const FONT_AUX:=16
const FONT_BODY:=18
const FONT_KEY:=22
const TOUCH_TARGET:=44

var session
var grid
var root_layout:VBoxContainer
var phase_panel:PanelContainer
var phase_label:Label
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

func _ready()->void:
	_build_ui()
	if session==null: session=SessionScript.new()
	_refresh()
func initialize_for_headless_test(custom_session=null)->void:
	if grid==null: _build_ui()
	session=custom_session if custom_session!=null else SessionScript.new(); _refresh()

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
	grid=GridScript.new(); grid.name="PartyGrid"; grid.custom_minimum_size=Vector2(348,348); grid.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	grid.world_cell_pressed.connect(_on_cell); grid.actor_pressed.connect(_on_actor); root_layout.add_child(grid)
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

func _refresh()->void:
	if session==null:return
	var status:Dictionary=session.party_status()
	if not bool(status.get("ok",false)):return
	var safe_phase:=str(status.safe_phase)
	if _action_feedback_phase!=safe_phase:
		action_feedback_text="";_action_feedback_phase=safe_phase
	var presentation:Dictionary=session.presentation_state()
	var combat_zoomed:=str(status.view_mode)=="COMBAT"
	var combat_actions_visible:=safe_phase=="ENGAGED" and not bool(status.terminal)
	_apply_portrait_budget(combat_zoomed,combat_actions_visible)
	if selected_member_id not in status.party_member_ids:selected_member_id=int(status.protagonist_id)
	if selected_target_id not in status.visible_enemy_ids:selected_target_id=-1
	if not pending_move_mode.is_empty() and pending_move_mode!=str(status.view_mode):_clear_move_preview()
	_apply_phase_banner(status,presentation)
	var deployment:Dictionary=session.deployment_draft(); var ghosts:Array=deployment.placements if str(status.view_mode)=="ENCOUNTER_PREVIEW" else []
	var observation:Dictionary=session.observe_party_world()
	var intent_overlays:Array=session.turn_intent_overlays() if combat_zoomed else []
	grid.set_observation(observation,ghosts)
	grid.set_view_window(9 if combat_zoomed else 15,_camera_focus_points(observation,intent_overlays),
		_camera_priority_points(observation))
	grid.set_presentation_style(presentation.get("grid_style",{}))
	grid.set_selection(selected_member_id,selected_target_id)
	grid.set_intent_overlays(intent_overlays)
	if pending_move_actor_id>0:grid.set_cursor_preview(pending_move_actor_id,pending_move_origin,pending_move_destination,pending_move_valid)
	else:grid.clear_cursor_preview()
	_clear_container(cards)
	for row in session.party_cards():_add_member_card(row)
	_clear_container(deck)
	_clear_container(combat_action_dock);combat_action_dock.visible=false
	combat_action_area.visible=combat_actions_visible;_update_action_feedback(status)
	match str(status.view_mode):
		"EXPLORATION":_exploration_deck()
		"ENCOUNTER_PREVIEW":_deployment_deck(deployment)
		"COMBAT":_combat_deck(status,session.current_turn_preview())
		"REGROUP":_legacy_regroup_notice()
	var logs:Array=session.recent_event_log(2)
	log_label.text="\n".join(logs.map(func(row):return str(row.message))) if not logs.is_empty() else "방향을 골라 세계를 탐험하세요."

func _add_member_card(row:Dictionary)->void:
	var button:=Button.new(); var member_id:=int(row.entity_id); button.name="MemberCard%d"%member_id
	button.custom_minimum_size=Vector2(44,160); button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.size_flags_stretch_ratio=1.0
	button.text=""; button.clip_contents=true
	var portrait:=AtlasTexture.new(); portrait.atlas=GridScript.CHARACTER_ATLAS; var frame:=0 if str(row.role)=="PROTAGONIST" else 4
	var frame_origin:=Vector2((frame%GridScript.CHARACTER_ATLAS_COLUMNS)*GridScript.CHARACTER_FRAME_SIZE.x,floori(float(frame)/GridScript.CHARACTER_ATLAS_COLUMNS)*GridScript.CHARACTER_FRAME_SIZE.y)
	portrait.region=Rect2(frame_origin+Vector2(4,0),Vector2(28,32))
	button.modulate=Color("#d8f3ff") if member_id==selected_member_id else Color.WHITE
	var inset:=MarginContainer.new(); inset.name="CardContent"; inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for margin in ["margin_left","margin_right"]:inset.add_theme_constant_override(margin,3)
	for margin in ["margin_top","margin_bottom"]:inset.add_theme_constant_override(margin,2)
	inset.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(inset)
	var stack:=VBoxContainer.new(); stack.name="CardStack"; stack.add_theme_constant_override("separation",0); stack.mouse_filter=Control.MOUSE_FILTER_IGNORE; inset.add_child(stack)
	var heading:=HBoxContainer.new(); heading.name="CardHeading"; heading.alignment=BoxContainer.ALIGNMENT_CENTER; heading.mouse_filter=Control.MOUSE_FILTER_IGNORE; stack.add_child(heading)
	var portrait_view:=TextureRect.new(); portrait_view.name="Portrait"; portrait_view.texture=portrait; portrait_view.custom_minimum_size=Vector2(52,54)
	portrait_view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; portrait_view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; portrait_view.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; portrait_view.mouse_filter=Control.MOUSE_FILTER_IGNORE; heading.add_child(portrait_view)
	var name_label:=_card_label(("▶" if member_id==selected_member_id else "")+str(row.display_name),"MemberName",FONT_BODY); name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; stack.add_child(name_label)
	stack.add_child(_card_label("HP %d/%d"%[int(row.health),int(row.max_health)],"MemberState",FONT_AUX))
	stack.add_child(_card_label("ST %d"%int(row.stress),"StressState",FONT_AUX))
	var bars:=HBoxContainer.new(); bars.name="VitalsBars"; bars.add_theme_constant_override("separation",3); stack.add_child(bars)
	var health_bar:=_bar("HealthBar",int(row.health),int(row.max_health),Color("#62d98b")); health_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL; bars.add_child(health_bar)
	var stress_bar:=_bar("StressBar",int(row.stress),1000,Color("#ffae5f")); stress_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL; bars.add_child(stress_bar)
	var state_row:=HBoxContainer.new(); state_row.name="StateRow"; state_row.add_theme_constant_override("separation",2); stack.add_child(state_row)
	var ready_label:=_card_label("준비" if str(row.readiness)=="행동 준비" else "행동중","Readiness",FONT_AUX); ready_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; state_row.add_child(ready_label)
	state_row.add_child(_card_label("%s%s"%[str(row.emotion.icon),str(row.emotion.label)],"EmotionState",FONT_AUX))
	button.pressed.connect(_select_member.bind(member_id,str(row.display_name))); cards.add_child(button)

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
	_add_notice(notice_text if not notice_text.is_empty() else "탐험: 인접한 빈 칸을 눌러 이동을 미리보세요.")
	if pending_move_mode=="EXPLORATION":
		var actor_name:=_protagonist_name(); var summary:=""
		if pending_exploration_wait:
			summary="대표 대기: %s (%d,%d)\n현재 칸을 한 번 더 누르면 대기합니다."%[actor_name,pending_move_origin.x,pending_move_origin.y]
		else:
			summary="대표 이동: %s (%d,%d) → (%d,%d) · 비용 %d"%[actor_name,pending_move_origin.x,pending_move_origin.y,pending_move_destination.x,pending_move_destination.y,pending_move_cost]
			summary+="\n한 번 더 눌러 이동합니다." if pending_move_valid else "\n"+notice_text
		_add_notice(summary,"MovePreviewSummary",FONT_KEY)
	_selected_detail()
func _deployment_deck(deployment:Dictionary)->void:
	var preset_label:String={"WEDGE":"쐐기","LINE":"횡대","COLUMN":"종대","NONE":"미선택"}.get(str(deployment.preset_id),"미선택")
	_add_notice(notice_text if not notice_text.is_empty() else "배치 대형: %s · %s"%[preset_label,str(deployment.message)])
	var controls:=HBoxContainer.new(); controls.name="FormationControls"; deck.add_child(controls)
	for preset in ["WEDGE","LINE","COLUMN"]:
		var button:=_add_button(controls,{"WEDGE":"쐐기","LINE":"횡대","COLUMN":"종대"}[preset],"Preset%s"%preset,_on_preset.bind(preset)); button.toggle_mode=true; button.button_pressed=str(deployment.preset_id)==preset
	var confirm:=_add_button(deck,"배치 확정","DeployConfirm",_on_deploy_confirm); confirm.disabled=not bool(deployment.accepted)
	_selected_detail()
func _combat_deck(status:Dictionary,preview:Dictionary)->void:
	if bool(status.terminal):_add_notice("파티가 패배했습니다. 주인공이 쓰러져 더 행동할 수 없습니다.","TerminalOverlay",FONT_KEY); return
	var actor_name:=_selected_name(); var instruction:="%s 선택 · 빈 칸은 이동, 적은 공격"%actor_name
	if not notice_text.is_empty():instruction=notice_text
	elif not bool(preview.get("accepted",false)):instruction+=" · "+str(preview.get("message","주인공 행동을 먼저 지정하세요."))
	_add_notice(instruction)
	if pending_move_actor_id>0:
		var summary:="이동 예정: %s (%d,%d) → (%d,%d)"%[actor_name,pending_move_origin.x,pending_move_origin.y,pending_move_destination.x,pending_move_destination.y]
		summary+="\n같은 칸을 한 번 더 누르면 행동 선택이 확정됩니다." if pending_move_valid else "\n이 칸으로 이동할 수 없습니다. "+notice_text
		_add_notice(summary,"MovePreviewSummary",FONT_KEY)
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
	if not action_feedback_text.is_empty():action_feedback_label.text=action_feedback_text
	elif bool(preview.get("accepted",false)):action_feedback_label.text="행동 준비 완료 · 필요하면 수정한 뒤 턴을 확정하세요."
	else:action_feedback_label.text="행동 지정 → 턴 확정\n빈 칸 이동 · 적 공격 · 선택 대기"
	var hold:=_add_button(combat_action_dock,"선택 대기","ActorHold",_on_actor_hold)
	hold.size_flags_stretch_ratio=1.0
	var clear:=_add_button(combat_action_dock,"자동 제안 복원","OverrideClear",_on_override_clear)
	clear.size_flags_stretch_ratio=1.35;clear.disabled=selected_member_id==int(status.protagonist_id)
	var confirm:=_add_button(combat_action_dock,"턴 확정","TurnConfirm",_on_turn_confirm)
	confirm.size_flags_stretch_ratio=0.9;confirm.disabled=not bool(preview.get("accepted",false))

func _selected_detail()->void:
	for row in session.party_cards():
		if int(row.entity_id)!=selected_member_id:continue
		_add_notice("선택 상세 · %s · %s · %s"%[str(row.display_name),str(row.readiness),str(row.emotion.reason)],"SelectedMemberDetail",FONT_AUX)
		_add_notice("원소 위험: 불%d 물%d 전%d 독%d"%[int(row.element_exposure.fire_score),int(row.element_exposure.water_score),int(row.element_exposure.electric_score),int(row.element_exposure.poison_score)],"MemberElements",FONT_AUX)
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
	selected_member_id=member_id;selected_target_id=-1;notice_text="%s 선택"%display_name
	action_feedback_text="%s 선택 · 행동을 지정하세요."%display_name
	_clear_move_preview();_request_refresh()
func _on_explore(direction:Vector2i)->void:_record_result(session.commit_exploration_direction(direction),true); _request_refresh()
func _on_preset(preset:String)->void:
	var result:Dictionary=session.preview_deployment(preset,session.available_companion_ids()); notice_text="%s 대형: %s"%[{"WEDGE":"쐐기","LINE":"횡대","COLUMN":"종대"}[preset],str(result.message)]
	action_feedback_text="대형 미리보기 완료 · 배치 확정을 누르세요." if bool(result.get("accepted",false)) else str(result.get("message","배치할 수 없습니다."));_request_refresh()
func _on_deploy_confirm()->void:
	var draft:Dictionary=session.deployment_draft()
	if not bool(draft.accepted):notice_text=str(draft.message);_set_action_rejection(draft,"배치 확정 불가")
	else:_record_result(session.commit_deployment(),true)
	_request_refresh()
func _on_actor_hold()->void:
	_clear_move_preview();_record_result(session.set_actor_action(selected_member_id,"HOLD"),false,"%s 대기 불가"%_selected_name());_request_refresh()
func _on_override_clear()->void:
	_clear_move_preview();_record_result(session.clear_companion_override(selected_member_id),false,"%s 자동 제안 복원 불가"%_selected_name());_request_refresh()
func _on_turn_confirm()->void:
	var current:Dictionary=session.current_turn_preview()
	if not bool(current.get("accepted",false)):_record_result(current,false,"턴 확정 불가")
	else:
		_record_result(session.commit_turn(),true); _clear_move_preview()
		if session.party_status().safe_phase=="GROUPED_COMPLETE":notice_text="승리! 파티가 자동으로 재집결해 탐험을 다시 시작합니다."
	_request_refresh()
func _on_cell(position:Vector2i)->void:
	var status:Dictionary=session.party_status()
	if bool(status.terminal):return
	if status.view_mode=="EXPLORATION":
		var hero:=int(status.protagonist_id); var origin:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
		var preview:Dictionary=session.preview_exploration(CommandScript.move_to(hero,position))
		var same:=pending_move_mode=="EXPLORATION" and not pending_exploration_wait and pending_move_destination==position
		if same and pending_move_valid:
			var result:Dictionary=session.commit_exploration(CommandScript.move_to(hero,position)); _clear_move_preview(); _record_result(result,true)
		else:
			pending_move_mode="EXPLORATION"; pending_exploration_wait=false; pending_move_actor_id=hero
			pending_move_origin=origin; pending_move_destination=position; pending_move_valid=bool(preview.get("accepted",false)); pending_move_cost=int(preview.get("time_cost",0))
			if pending_move_valid:notice_text="이동할 칸을 한 번 더 누르세요."
			elif maxi(absi(position.x-origin.x),absi(position.y-origin.y))>1:
				notice_text="장거리 이동은 아직 지원하지 않습니다. "+str(preview.get("message","인접한 칸을 선택하세요."))
			else:notice_text=str(preview.get("message","이 칸으로 이동할 수 없습니다."))
			if pending_move_valid:action_feedback_text="이동 미리보기 · 같은 칸을 한 번 더 누르세요."
			else:_set_action_rejection(preview,"%s 이동 불가"%_protagonist_name())
		_request_refresh(); return
	if status.view_mode!="COMBAT":return
	selected_target_id=-1
	var preview:Dictionary=session.preview_actor_action(selected_member_id,"MOVE",[position.x,position.y])
	var same:=pending_move_mode=="COMBAT" and pending_move_actor_id==selected_member_id and pending_move_destination==position
	if same and pending_move_valid:_record_result(session.set_actor_action(selected_member_id,"MOVE",[position.x,position.y]),false,"%s 이동 불가"%_selected_name()); _clear_move_preview()
	else:
		pending_move_mode="COMBAT"; pending_exploration_wait=false
		pending_move_actor_id=selected_member_id; pending_move_origin=_selected_position(); pending_move_destination=position
		pending_move_valid=bool(preview.get("accepted",false)); pending_move_cost=int(preview.get("total_time_cost",0))
		if pending_move_valid:
			notice_text="";action_feedback_text="%s 이동 미리보기 · 같은 칸을 한 번 더 누르세요."%_selected_name()
		else:
			notice_text=str(preview.get("message","이 칸으로 이동할 수 없습니다."));_set_action_rejection(preview,"%s 이동 불가"%_selected_name())
	_request_refresh()
func _on_actor(entity_id:int)->void:
	var status:Dictionary=session.party_status()
	if status.view_mode=="EXPLORATION" and entity_id==int(status.protagonist_id):
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
		if status.view_mode=="COMBAT" and not bool(status.terminal):_record_result(session.set_actor_action(selected_member_id,"MELEE",[],entity_id),false,"%s 공격 불가"%_selected_name())
		_request_refresh(); return
	if entity_id in status.party_member_ids:
		selected_member_id=entity_id;selected_target_id=-1;notice_text="파티원을 선택했습니다."
		action_feedback_text="%s 선택 · 행동을 지정하세요."%_selected_name();_clear_move_preview();_request_refresh()

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
func _clear_move_preview()->void:
	pending_move_actor_id=-1; pending_move_origin=Vector2i(-1,-1); pending_move_destination=Vector2i(-1,-1); pending_move_valid=false
	pending_move_mode=""; pending_move_cost=0; pending_exploration_wait=false
	if grid!=null:grid.clear_cursor_preview()
func _request_refresh()->void:call_deferred("_refresh")
func _record_result(result:Dictionary,consume_effects:bool=false,rejection_prefix:String="")->void:
	if consume_effects and bool(result.get("accepted",false)) and result.get("visual_effects",[]) is Array:
		grid.play_effects(result.get("visual_effects",[]))
	if bool(result.get("accepted",false)):
		notice_text="";action_feedback_text="턴이 처리되었습니다. 다음 행동을 지정하세요." if consume_effects else "행동이 준비되었습니다. 턴 확정을 누르세요."
	else:
		notice_text=str(result.get("message","행동을 처리할 수 없습니다."));_set_action_rejection(result,rejection_prefix)

func _set_action_rejection(result:Dictionary,prefix:String)->void:
	var message:=str(result.get("message","행동을 처리할 수 없습니다."))
	action_feedback_text=message if prefix.is_empty() else "%s: %s"%[prefix,message]

func _update_action_feedback(status:Dictionary)->void:
	if not action_feedback_text.is_empty():action_feedback_label.text=action_feedback_text;return
	match str(status.safe_phase):
		"CONTACT":action_feedback_label.text="대형 선택 → 배치 확정"
		"GROUPED_COMPLETE":action_feedback_label.text="승리 · 자동 재집결 완료 · 탐험 이동을 선택하세요."
		_:
			if str(status.view_mode)=="EXPLORATION":action_feedback_label.text="인접 칸 미리보기 → 같은 칸을 한 번 더 눌러 이동"
			elif str(status.view_mode)=="COMBAT":action_feedback_label.text="행동 지정 → 턴 확정"
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
func _apply_portrait_budget(combat_zoomed:bool,combat_actions_visible:bool)->void:
	var wide:=size.x>=450.0; phase_panel.custom_minimum_size.y=52 if wide else 48
	root_layout.add_theme_constant_override("separation",4 if wide else 2)
	combat_action_area.custom_minimum_size.y=84 if combat_actions_visible else 0
	if combat_zoomed:grid.custom_minimum_size=Vector2(360,360) if wide else Vector2(300,300)
	else:grid.custom_minimum_size=Vector2(405,405) if wide else Vector2(348,348)
	cards.custom_minimum_size.y=160; info_scroll.custom_minimum_size.y=30

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
		phase_label.text="⚔ %s · 행동 지정 → 턴 확정\n시간 %d · %s"%[title,int(status.world_time),contact_text]
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
