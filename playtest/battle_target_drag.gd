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

func handle_input(host,event:InputEvent)->bool:
	if event is InputEventScreenTouch and event.pressed and not active:ignore_mouse_until=-1
	var mouse:=event is InputEventMouseButton or event is InputEventMouseMotion
	if mouse and Time.get_ticks_msec()<ignore_mouse_until:
		host.get_viewport().set_input_as_handled();return true
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
			if (str(button.name).begins_with("ActorSkill_") or str(button.name).begins_with("PortraitBattle")) \
					and button.is_visible_in_tree() and button.get_global_rect().has_point(event.position):
				control_held=true;return false
		if not host._battle_target_mode.is_empty():return false
		var source:=_source_at(host,event.position)
		if source.is_empty():return false
		begin(int(source.actor_id),event.position,event is InputEventScreenTouch,
			int(event.index) if event is InputEventScreenTouch else -1,bool(source.portrait))
		host.grid.cancel_pointer_gesture()
	else:
		if touch:
			if mouse:host.get_viewport().set_input_as_handled();return true
			if event is InputEventScreenTouch and event.index!=pointer_index:
				if event.pressed:cancelled=true;queue_redraw()
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
			update_pointer(event.position,_enemy_at(host,event.position))
		if released:
			var actor:=actor_id
			var target:=target_id
			var issue:=dragged and not cancelled and target>0
			var tap:=not dragged and not cancelled
			var portrait:=portrait_origin
			if event is InputEventScreenTouch and event.canceled:issue=false;tap=false
			if touch:ignore_mouse_until=Time.get_ticks_msec()+350
			clear()
			host.selected_member_id=actor
			if issue:
				var result:Dictionary=host.session.issue_actor_command(actor,"ATTACK_TARGET",target)
				if result.get("accepted",false):
					host.selected_target_id=target
					host._show_manual_battle_feedback("%s → %s 공격"%[
						host._actor_display_name(actor),host._entity_display_name(target)])
				else:host._show_manual_battle_feedback("그 적은 지정할 수 없습니다.")
			elif tap:
				if portrait:host._on_compact_member_card_pressed(actor,host._actor_display_name(actor))
				else:host._on_manual_actor_selected(actor)
			else:host._show_manual_battle_feedback("공격 지정을 취소했습니다.")
			host.autonomous_battle_clock.remaining=host.autonomous_battle_clock.INTERVAL
			host._request_refresh()
		elif not pressed and not event is InputEventScreenDrag and not event is InputEventMouseMotion:
			return false
	host.get_viewport().set_input_as_handled();return true

func _source_at(host,position:Vector2)->Dictionary:
	var state=host.session.sim.world.party_encounter
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

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=100

func begin(actor:int,position:Vector2,is_touch:bool,index:int,from_portrait:bool)->void:
	active=true;actor_id=actor;target_id=-1;pointer=position;start=position
	touch=is_touch;pointer_index=index;portrait_origin=from_portrait
	dragged=false;cancelled=false;queue_redraw()

func update_pointer(position:Vector2,target:int)->void:
	pointer=position;target_id=target
	dragged=dragged or pointer.distance_to(start)>=10.0
	queue_redraw()

func clear()->void:
	active=false;actor_id=-1;target_id=-1;pointer_index=-1
	dragged=false;cancelled=false;queue_redraw()

func _draw()->void:
	if not active or not dragged or cancelled:return
	var inverse:=get_global_transform_with_canvas().affine_inverse()
	var origin:Vector2=inverse*start
	var end:Vector2=inverse*pointer
	var color:=Color("#e4bb67") if target_id>0 else Color("#a5b8c6")
	draw_line(origin,end,Color(0,0,0,0.65),6,true)
	draw_line(origin,end,color,3,true)
	draw_circle(origin,5,color)
	draw_arc(end,17,0,TAU,32,color,2,true)
	var direction:Vector2=(end-origin).normalized()
	draw_colored_polygon(PackedVector2Array([end,end-direction.rotated(0.5)*14,
		end-direction.rotated(-0.5)*14]),color)
