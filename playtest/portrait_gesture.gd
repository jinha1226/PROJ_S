extends RefCounted

# Portraits are tap/inspect controls, never drag-command sources. Keep gesture
# ownership outside transient HUD Buttons and outside the field/combat mode.
const HOLD_MSEC:=600
const SLOP:=24.0
var actor_id:=-1
var touch_index:=-1
var is_touch:=false
var origin:=Vector2.ZERO
var started:=-1
var consumed:=false
var ignore_mouse_until:=-1

func _blocked(host)->bool:
	if host.session==null or host.cards==null:return true
	if host.get_node_or_null("ActiveCombatLab")!=null:return true
	for panel in [host.member_detail_modal,host.record_modal,host.map_overlay,
			host.base_modal,host.species_picker_modal,host.companion_order_editor]:
		if panel!=null and panel.visible:return true
	return host.grid!=null and host.grid.modal_open

func handle(host,event:InputEvent)->bool:
	var touch:=event is InputEventScreenTouch or event is InputEventScreenDrag
	var mouse:=event is InputEventMouseButton or event is InputEventMouseMotion
	if not touch and not mouse:return false
	if mouse and (event.device==InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec()<ignore_mouse_until):
		if actor_id>=0 or Time.get_ticks_msec()<ignore_mouse_until:
			host.get_viewport().set_input_as_handled();return true
		return false
	var pressed:bool=event is InputEventScreenTouch and event.pressed \
		or event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed
	var released:bool=event is InputEventScreenTouch and not event.pressed \
		or event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed
	if actor_id<0:
		if not pressed or _blocked(host):return false
		for card in host.cards.find_children("MemberCard*","Button",true,false):
			if card.is_visible_in_tree() and card.get_global_rect().has_point(event.position):
				actor_id=int(str(card.name).trim_prefix("MemberCard"));break
		if actor_id<0:return false
		origin=event.position;started=Time.get_ticks_msec();consumed=false
		is_touch=touch;touch_index=int(event.index) if touch else -1
		host.grid.cancel_pointer_gesture()
	else:
		if is_touch and mouse:
			host.get_viewport().set_input_as_handled();return true
		if is_touch and int(event.index)!=touch_index:return false
		if not is_touch and touch:return false
		if event.position.distance_to(origin)>SLOP:consumed=true
		if released:
			var id:=actor_id
			var activate:=not consumed and not _blocked(host)
			if event is InputEventScreenTouch and event.canceled:activate=false
			var held:=Time.get_ticks_msec()-started>=HOLD_MSEC
			actor_id=-1
			if is_touch:ignore_mouse_until=Time.get_ticks_msec()+500
			if activate:
				if held:host._open_member_detail(id)
				else:host._on_compact_member_card_pressed(id,"")
	host.get_viewport().set_input_as_handled();return true

func tick(host)->void:
	if actor_id<0 or consumed:return
	if _blocked(host):actor_id=-1;return
	if Time.get_ticks_msec()-started>=HOLD_MSEC:
		consumed=true
		host._open_member_detail(actor_id)
