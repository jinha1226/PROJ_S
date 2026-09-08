extends RefCounted

var elapsed:=0.0
var _world_id:=-1
var _event_count:=-1
var _job:Dictionary={}

func tick(ui,delta:float)->void:
	if ui.session==null or ui.session.sim==null \
			or ui.session.sim.world.party_encounter.expedition_cycle.phase!="TOWN":elapsed=0;return
	var world=ui.session.sim.world
	if _world_id!=world.get_instance_id() or _event_count!=world.events.size():
		_world_id=world.get_instance_id();_event_count=world.events.size()
		_job=preload("res://sim/base_work_rules.gd").current(world.events)
	if _job.is_empty():elapsed=0;return
	# No catch-up while the app is suspended, and no rebuild during a pointer
	# gesture. A work tick is a small, journalled operation, not a dungeon turn.
	if not ui.get_window().has_focus() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):return
	elapsed+=minf(delta,0.1)
	if elapsed<0.5:return
	elapsed=0
	var result:Dictionary=ui.session.base_work({"action":"TICK"})
	if not bool(result.get("accepted",false)):return
	if bool(result.get("completed",false)):
		ui.notice_text=str(result.message);ui._request_refresh()
	else:
		var panel=ui.find_child("TownBaseProgress",true,false)
		if panel!=null:panel.update_work(ui.session.base_overview())
