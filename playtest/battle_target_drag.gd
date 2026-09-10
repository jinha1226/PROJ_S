extends Control

## Input/presentation controller. Commands are assessed and committed only by
## the authoritative session API; this controller never edits world state.
var active:=false
var actor_id:=-1
var target_id:=-1
var pointer_index:=-1
var touch:=false
var portrait_origin:=false
var start:=Vector2.ZERO
var pointer:=Vector2.ZERO
var dragged:=false
var cancelled:=false
var ignore_mouse_until:=-1
var control_held:=false
var skill_id:=""
var skill_label:=""
var target_valid:=false
var target_message:=""
var host_ref:WeakRef
var _preview_key:=""
var move_goal:=Vector2i(-1,-1)
var move_valid:=false
var _move_key:=""

func handle_input(host,event:InputEvent)->bool:
	host_ref=weakref(host)
	# Field turns own portrait tap/hold and skill targeting, even when an old
	# encounter still carries ENGAGED. Do not steal their pointer-down event.
	if host.session!=null and host.session.field_turns_active():
		if active:clear()
		control_held=false;return false
	if active and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		clear();host.get_viewport().set_input_as_handled();return true
	if event is InputEventScreenTouch and event.pressed and not active:ignore_mouse_until=-1
	var mouse:=event is InputEventMouseButton or event is InputEventMouseMotion
	if mouse and Time.get_ticks_msec()<ignore_mouse_until:
		# A new press can precede its real touch packet. Let it start a new
		# gesture/native button click; only suppress the previous contact's tail.
		if event is InputEventMouseButton and event.pressed:ignore_mouse_until=-1
		else:host.get_viewport().set_input_as_handled();return true
	if not host._portrait_battle_controls_visible() or host.grid.modal_open:
		if active:clear()
		control_held=false;return false
	if not active and not host._product_pinch_points.is_empty():return false
	var pressed:bool=event is InputEventScreenTouch and event.pressed \
		or event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed
	var released:bool=event is InputEventScreenTouch and not event.pressed \
		or event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed
	if released:control_held=false
	if not active:
		if not pressed:return false
		for button in host.cards.find_children("*","Button",true,false):
			if str(button.name).begins_with("PortraitBattle") \
					and button.is_visible_in_tree() and button.get_global_rect().has_point(event.position):
				control_held=true;return false
		if not host._battle_target_mode.is_empty():return false
		var source:=_source_at(host,event.position)
		if source.is_empty():return false
		begin(int(source.actor_id),event.position,event is InputEventScreenTouch,
			int(event.index) if event is InputEventScreenTouch else -1,bool(source.portrait))
		skill_id=str(source.get("skill_id",""));skill_label=str(source.get("skill_label",""))
		host.grid.cancel_pointer_gesture()
	else:
		if touch:
			if mouse:host.get_viewport().set_input_as_handled();return true
			if event is InputEventScreenTouch and event.index!=pointer_index:
				if event.pressed:cancelled=true;_preview(host,-1);queue_redraw()
				host.get_viewport().set_input_as_handled();return true
			if event is InputEventScreenDrag and event.index!=pointer_index:
				host.get_viewport().set_input_as_handled();return true
		elif event is InputEventScreenTouch:
			# Godot may deliver the emulated mouse press before the real touch.
			# Adopt that same contact instead of treating it as a second finger.
			if event.pressed and not dragged and event.position.distance_to(start)<10.0:
				touch=true;pointer_index=event.index
			else:cancelled=true
			host.get_viewport().set_input_as_handled();return true
		if event is InputEventScreenDrag or event is InputEventMouseMotion or released:
			update_pointer(event.position,_target_at(host,event.position))
			_preview(host,target_id if dragged and not cancelled else -1)
			_preview_move(host,event.position)
		if released:
			var actor:=actor_id
			var target:=target_id
			var issue:=dragged and not cancelled and target>0 and target_valid
			var tap:=not dragged and not cancelled
			var portrait:=portrait_origin
			var selected_skill:=skill_id;var selected_label:=skill_label
			var rejection:=target_message
			var goal:=move_goal
			var issue_move:=dragged and not cancelled and skill_id.is_empty() and target<0 and move_valid
			if event is InputEventScreenTouch and event.canceled:issue=false;tap=false
			if event is InputEventScreenTouch and event.canceled:issue_move=false
			if touch:ignore_mouse_until=Time.get_ticks_msec()+350
			clear()
			host.selected_member_id=actor
			if issue:
				var result:Dictionary=host.session.individual_battle.reserve(actor,selected_skill,target) \
					if not selected_skill.is_empty() else host.session.issue_actor_command(actor,"ATTACK_TARGET",target)
				if result.get("accepted",false):
					host.selected_target_id=target
					host.grid.set_selection(actor,target);host.grid.set_actor_emphasis(target,1200)
					host._show_manual_battle_feedback("%s → %s · %s"%[
						host._actor_display_name(actor),host._entity_display_name(target),
						"공격" if selected_skill.is_empty() else selected_label+" 예약"])
				else:host._show_manual_battle_feedback("그 적은 지정할 수 없습니다.")
			elif issue_move:
				var result:Dictionary=host.session.individual_battle.reserve_move(actor,goal)
				host._show_manual_battle_feedback(str(result.get("message","이동 지시 실패")))
			elif tap:
				if not selected_skill.is_empty():host._on_manual_skill_selected(actor,selected_skill,selected_label)
				elif portrait:host._on_compact_member_card_pressed(actor,host._actor_display_name(actor))
				else:host._on_manual_actor_selected(actor)
			else:host._show_manual_battle_feedback(rejection if not rejection.is_empty() else "대상 지정을 취소했습니다.")
			host.autonomous_battle_clock.remaining=host.autonomous_battle_clock.INTERVAL
			host._request_refresh()
		elif not pressed and not event is InputEventScreenDrag and not event is InputEventMouseMotion:
			return false
	host.get_viewport().set_input_as_handled();return true

func _source_at(host,position:Vector2)->Dictionary:
	var state=host.session.sim.world.party_encounter
	for button in host.cards.find_children("ActorSkill_*","Button",true,false):
		if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(position):
			return {"actor_id":int(button.get_meta("actor_id")),"portrait":true,
				"skill_id":str(button.get_meta("skill_id")),"skill_label":str(button.get_meta("skill_label"))}
	for id in state.active_party_member_ids:
		if not host.session.sim.world.can_act(id,host.session.sim.world.world_time):continue
		var portrait:=host.cards.find_child("MemberCard%d"%int(id),true,false) as Control
		if portrait!=null and portrait.is_visible_in_tree() and portrait.get_global_rect().has_point(position):
			return {"actor_id":int(id),"portrait":true}
	if host.grid.get_global_rect().has_point(position):
		var local:Vector2=host.grid.get_global_transform_with_canvas().affine_inverse()*position
		var id:int=host.grid.actor_at_pointer(local)
		if id in state.active_party_member_ids and host.session.sim.world.can_act(id,host.session.sim.world.world_time):
			return {"actor_id":id,"portrait":false}
	return {}

func _enemy_at(host,position:Vector2)->int:
	if host.battle_enemy_strip!=null:
		var portrait_id:int=host.battle_enemy_strip.target_at(position)
		if portrait_id>0:return portrait_id
	if not host.grid.get_global_rect().has_point(position):return -1
	var local:Vector2=host.grid.get_global_transform_with_canvas().affine_inverse()*position
	var nearest:=-1
	var distance:=24.0
	for id in host.session.sim.world.party_encounter.enemy_ids:
		if not host.session.sim.world.is_unresolved_enemy(id):continue
		var center:Vector2=host.grid.actor_visual_center(id)
		if center.x<0 or center.y<0:continue
		var candidate:float=center.distance_to(local)
		if candidate<distance:distance=candidate;nearest=int(id)
	return nearest

func _target_at(host,position:Vector2)->int:
	var enemy:=_enemy_at(host,position)
	if enemy>0 or skill_id.is_empty():return enemy
	for id in host.session.sim.world.party_encounter.active_party_member_ids:
		var portrait:=host.cards.find_child("MemberCard%d"%int(id),true,false) as Control
		if portrait!=null and portrait.is_visible_in_tree() and portrait.get_global_rect().has_point(position):return int(id)
	if host.grid.get_global_rect().has_point(position):
		var local:Vector2=host.grid.get_global_transform_with_canvas().affine_inverse()*position
		return host.grid.actor_at_pointer(local)
	return -1

func _preview(host,id:int)->void:
	var world=host.session.sim.world
	var key:="%d/%d/%d/%d/%s/%d"%[world.get_instance_id(),world.step_index,
		world.party_encounter.revision,actor_id,skill_id,id]
	if key==_preview_key:return
	_preview_key=key
	target_valid=false;target_message=""
	if id>0:
		var assessment:Dictionary=host.session.individual_battle.assessment(actor_id,skill_id,id) \
			if not skill_id.is_empty() else host.session.actor_command_assessment(actor_id,"ATTACK_TARGET",id)
		target_valid=bool(assessment.get("accepted",false))
		target_message=str(assessment.get("message",assessment.get("reason","지정 불가"))) if not target_valid else ""
		host.event_label.text=host._entity_display_name(id) if target_valid else target_message
	host.grid.set_target_preview(id,target_valid)
	if host.battle_enemy_strip!=null:host.battle_enemy_strip.set_hover(id,target_valid)

func _preview_move(host,position:Vector2)->void:
	move_goal=Vector2i(-1,-1);move_valid=false
	if dragged and not cancelled and skill_id.is_empty() and target_id<0 \
			and host.grid.get_global_rect().has_point(position):
		var local:Vector2=host.grid.get_global_transform_with_canvas().affine_inverse()*position
		move_goal=host.grid.pixel_to_world_cell(local)
		if not host.grid.is_world_cell_visible(move_goal):move_goal=Vector2i(-1,-1)
	var key:="%d/%s/%d"%[actor_id,str(move_goal),host.session.sim.world.step_index]
	if key!=_move_key:
		_move_key=key
		if move_goal!=Vector2i(-1,-1):
			var assessment:Dictionary=host.session.individual_battle.movement_assessment(actor_id,move_goal)
			host.grid.move_preview_valid=bool(assessment.get("accepted",false))
			target_message=str(assessment.get("message",""))
		else:host.grid.move_preview_valid=false
	move_valid=host.grid.move_preview_valid
	host.grid.move_preview_position=move_goal;host.grid.queue_redraw()

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=100

func begin(actor:int,position:Vector2,is_touch:bool,index:int,from_portrait:bool)->void:
	_preview_key=""
	_move_key="";move_goal=Vector2i(-1,-1);move_valid=false
	active=true;actor_id=actor;target_id=-1;pointer=position;start=position
	touch=is_touch;pointer_index=index;portrait_origin=from_portrait
	dragged=false;cancelled=false;queue_redraw()

func update_pointer(position:Vector2,target:int)->void:
	pointer=position;target_id=target
	dragged=dragged or pointer.distance_to(start)>=10.0
	queue_redraw()

func clear()->void:
	var host=host_ref.get_ref() if host_ref!=null else null
	if host!=null:_preview(host,-1)
	if host!=null:
		host.grid.move_preview_position=Vector2i(-1,-1);host.grid.move_preview_valid=false;host.grid.queue_redraw()
	move_goal=Vector2i(-1,-1);move_valid=false;_move_key=""
	active=false;actor_id=-1;target_id=-1;pointer_index=-1
	skill_id="";skill_label="";target_valid=false;target_message=""
	dragged=false;cancelled=false;queue_redraw()

func _draw()->void:
	if not active or not dragged or cancelled:return
	var inverse:=get_global_transform_with_canvas().affine_inverse()
	var origin:Vector2=inverse*start
	var end:Vector2=inverse*pointer
	var color:=(Color("#e4bb67") if target_valid else Color("#ff6363")) if target_id>0 else Color("#a5b8c6")
	if move_goal!=Vector2i(-1,-1):color=Color("#87dfcb") if move_valid else Color("#ff6363")
	draw_line(origin,end,Color(0,0,0,0.65),6,true)
	draw_line(origin,end,color,3,true)
	draw_circle(origin,5,color)
	draw_arc(end,17,0,TAU,32,color,2,true)
	if target_id>0:
		var host=host_ref.get_ref() if host_ref!=null else null
		var label:=str(host._entity_display_name(target_id)) if target_valid and host!=null else target_message
		var label_pos:=Vector2(clampf(end.x-90,4,maxf(4,size.x-224)),maxf(16,end.y-29))
		draw_style_box(preload("res://playtest/dark_pixel_ui_skin.gd").panel_surface(Color("#10171d"),color,0,1),Rect2(label_pos-Vector2(4,15),Vector2(220,22)))
		draw_string(get_theme_font("font"),label_pos,label,HORIZONTAL_ALIGNMENT_LEFT,212,12,color)
	var direction:Vector2=(end-origin).normalized()
	draw_colored_polygon(PackedVector2Array([end,end-direction.rotated(0.5)*14,
		end-direction.rotated(-0.5)*14]),color)
