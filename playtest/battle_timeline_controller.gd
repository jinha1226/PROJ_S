extends Control

const Bar=preload("res://playtest/battle_timeline_bar.gd")
const UiSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
var host
var bar
var pointer_held:=false
var group_open:=false
var group_layer:Control
var pending_actors:Dictionary={}
var _bound_sim
var _last_state:Dictionary={}
var _last_recorded_event_id:=-1

func setup(owner_ui,timeline_bar)->void:
	host=owner_ui;bar=timeline_bar
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);z_index=90
	bar.pointer_held.connect(_on_pointer_held)
	bar.entry_tapped.connect(_on_tapped)

func _on_pointer_held(held:bool)->void:
	pointer_held=held
	bar.set_presentation_blocked(host._battle_presentation_blocked() or host.autonomous_battle_clock.paused)

func sync()->void:
	if host.session==null:return
	if _bound_sim!=host.session.sim:
		_bound_sim=host.session.sim;pending_actors.clear();_last_state.clear()
		_last_recorded_event_id=-1
		host.autonomous_battle_clock.cursor=-1.0
		bar.clear_presentation();close_group()
	bar.visible=host._timeline_visible()
	if not bar.visible:
		bar.clear_presentation();close_group();pending_actors.clear();_last_state.clear();return
	bar.set_taps_enabled(host._battle_target_mode.is_empty())
	bar.set_presentation_blocked(host._battle_presentation_blocked() or host.autonomous_battle_clock.paused)
	var state:Dictionary=host.session.battle_timeline_state()
	if state!=_last_state:
		bar.set_state(state);_last_state=state
	bar.set_display_time(host.autonomous_battle_clock.cursor)
	for entry in state.entries:
		if pending_actors.has(int(entry.entity_id)):bar.flash_actor(int(entry.entity_id))
	pending_actors.clear()

func record_result(result:Dictionary)->void:
	if not result.get("accepted",false):return
	for id in result.get("event_ids",[]):
		if int(id)<=_last_recorded_event_id:continue
		_last_recorded_event_id=int(id)
		var event=host.session.sim.world.event_by_id(int(id))
		if event==null or event.type not in ["action.skill","action.move","action.melee_attack","action.hold","action.wait"]:continue
		var cause=host.session.sim.world.event_by_id(int(event.cause_id))
		if event.type=="action.move" and cause!=null and cause.type=="action.skill":continue
		pending_actors[int(event.actor_id)]=true

func handle_group_input(event:InputEvent)->bool:
	if not group_open:return false
	if event.is_action_pressed("ui_cancel"):
		close_group();get_viewport().set_input_as_handled()
	elif event is InputEventKey:get_viewport().set_input_as_handled()
	# Do not run the sandbox's global map/drag handlers. GUI dispatch continues
	# into the full-screen modal layer, including native mouse-from-touch buttons.
	return true

func _notification(what:int)->void:
	if what==NOTIFICATION_WM_GO_BACK_REQUEST and group_open:close_group()

func _on_tapped(ids:Array)->void:
	if not host._battle_target_mode.is_empty():return
	if ids.size()==1:_emphasize(int(ids[0]));return
	close_group()
	group_open=true
	group_layer=Control.new();group_layer.name="TimelineGroupList"
	group_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	group_layer.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(group_layer)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);group_layer.add_child(shade)
	shade.gui_input.connect(func(event:InputEvent):
		if event is InputEventScreenTouch and not event.pressed:close_group.call_deferred()
		elif event is InputEventMouseButton and not event.pressed:close_group.call_deferred())
	var panel:=PanelContainer.new();panel.name="TimelineGroupPanel"
	UiSkin.apply_panel(panel,"FOLIO");group_layer.add_child(panel)
	var width:=minf(300,host.size.x-20)
	panel.position=Vector2((host.size.x-width)*0.5,100);panel.custom_minimum_size.x=width
	var stack:=VBoxContainer.new();panel.add_child(stack)
	for id in ids:
		var entry:=_entry(int(id))
		if entry.is_empty():continue
		var button:=Button.new();button.name="TimelineMember%d"%int(id)
		button.text="%s · %s"%[entry.display_name,_status(entry)]
		button.custom_minimum_size=Vector2(width,48)
		UiSkin.apply_action_button(button,UiSkin.BRASS)
		button.pressed.connect(_choose.bind(int(id)));stack.add_child(button)
	var close:=Button.new();close.name="TimelineGroupClose";close.text="닫기";close.custom_minimum_size.y=48
	close.pressed.connect(close_group);stack.add_child(close)

func close_group()->void:
	group_open=false
	if is_instance_valid(group_layer):group_layer.hide();group_layer.queue_free()
	group_layer=null

func _choose(id:int)->void:
	_emphasize(id);close_group()

func _entry(id:int)->Dictionary:
	for entry in _last_state.get("entries",[]):
		if int(entry.entity_id)==id:return entry
	return {}

func _status(entry:Dictionary)->String:
	if entry.status=="UNAVAILABLE":return "행동 불가"
	if entry.get("ready_at")==null:return "시점 미정"
	var remaining:=maxi(0,int(entry.ready_at)-int(_last_state.world_time))
	return "준비" if remaining==0 else "회복 중 +%d"%remaining

func _emphasize(id:int)->void:
	var entry:=_entry(id)
	if entry.is_empty():return
	host.grid.set_actor_emphasis(id,800)
	var portrait=host.cards.find_child("MemberCard%d"%id,true,false)
	if portrait!=null:
		portrait.emphasized_until_msec=Time.get_ticks_msec()+800;portrait.queue_redraw()
	host.event_label.text="%s · %s"%[entry.display_name,_status(entry)]
