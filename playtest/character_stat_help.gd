extends Node
## One gesture owner for the status sheet: drag scroll wins over hold-to-inspect.
var host:Control
var timer:Timer
var popup:AcceptDialog
var origin:=Vector2.ZERO
var last:=Vector2.ZERO
var tracking:=false
var dragging:=false
var pointer_id:=-1
var candidate:Control
var ignore_mouse_until:=0
func _ready()->void:
	timer=Timer.new();timer.one_shot=true;timer.wait_time=0.55
	add_child(timer);timer.timeout.connect(_show_help)
	popup=AcceptDialog.new();popup.title="수치 설명";popup.ok_button_text="닫기"
	popup.dialog_autowrap=true;popup.theme=host.theme;popup.exclusive=true
	add_child(popup)
	host.member_detail_modal.visibility_changed.connect(func():
		if not host.member_detail_modal.visible:popup.hide();_cancel())
func _exit_tree()->void:
	if is_instance_valid(popup):popup.queue_free()
func _cancel()->void:
	tracking=false;candidate=null;timer.stop()
func _pick(node:Node,point:Vector2)->Control:
	if node is Control and (not node.is_visible_in_tree() or not node.get_global_rect().has_point(point)):return null
	for child in node.get_children():
		var found:=_pick(child,point)
		if found!=null:return found
	return node as Control if node is Control and node.has_meta("stat_help") else null
func _show_help()->void:
	if not tracking or dragging or not is_instance_valid(candidate):return
	if not host.member_detail_modal.visible or host.member_detail_current_tab!="STATUS":return
	popup.title=str(candidate.get_meta("stat_title","수치 설명"))
	popup.dialog_text=str(candidate.get_meta("stat_help",""))
	popup.popup_centered(Vector2i(int(minf(host.size.x-28,360)),240))
	_cancel()
func _input(event:InputEvent)->void:
	if not host.member_detail_modal.visible or host.member_detail_current_tab!="STATUS":
		_cancel();return
	if popup.visible:return
	var touch:=event is InputEventScreenTouch or event is InputEventScreenDrag
	var mouse:=event is InputEventMouseButton or event is InputEventMouseMotion
	if not touch and not mouse:return
	if mouse and (event.device==InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec()<ignore_mouse_until):return
	var pressed:bool=(event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed)
	var released:bool=(event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed)
	if pressed:
		if not host.member_detail_scroll.get_global_rect().has_point(event.position):return
		var bar:VScrollBar=host.member_detail_scroll.get_v_scroll_bar()
		if bar.is_visible_in_tree() and bar.get_global_rect().has_point(event.position):return
		tracking=true;dragging=false;origin=event.position;last=origin
		pointer_id=int(event.index) if touch else -1
		if touch:ignore_mouse_until=Time.get_ticks_msec()+1000
		candidate=_pick(host.member_status_window,origin)
		if candidate!=null:timer.start()
		# This sheet has inspect-only controls, so own its entire drag sequence.
		get_viewport().set_input_as_handled();return
	if not tracking:return
	if touch and int(event.index)!=pointer_id:return
	if mouse and pointer_id!=-1:return
	if event.position.distance_to(origin)>10:
		dragging=true;timer.stop()
	if dragging:
		host.member_detail_scroll.scroll_vertical-=roundi(event.position.y-last.y)
	last=event.position
	if released:_cancel()
	get_viewport().set_input_as_handled()

static func make_scroll_transparent(node:Node)->void:
	if node is Control:node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():make_scroll_transparent(child)
