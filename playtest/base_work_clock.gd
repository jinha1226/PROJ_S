extends RefCounted
var elapsed:=0.0
var completion_refresh_pending:=false
func tick(ui,delta:float)->void:
	if not preload("res://playtest/product_features.gd").SETTLEMENT_ENABLED:return
	if ui.session==null or ui.session.sim==null or ui.session.sim.world.party_encounter.expedition_cycle.phase!="TOWN":elapsed=0;return
	if not ui.session.private_home_available() or not ui.get_window().has_focus():elapsed=0;return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):return
	var panel=ui.find_child("TownBaseProgress",true,false)
	var safe_refresh:bool=(ui.grid==null or not ui.grid.modal_open) and ui._product_touch_index<0
	if panel!=null:safe_refresh=safe_refresh and not panel._placement_active and panel._map_camera.contacts.is_empty()
	if completion_refresh_pending and safe_refresh:
		completion_refresh_pending=false;ui._request_refresh()
	elapsed+=minf(delta,0.1)
	if elapsed<0.5:return
	elapsed=0
	var result:Dictionary=preload("res://playtest/settlement_work_service.gd").automatic_tick(ui.session)
	if not bool(result.get("accepted",false)):return
	if bool(result.get("idle",false)):return
	if panel!=null:panel.update_work(ui.session.base_overview())
	if bool(result.get("completed",false)):
		ui.notice_text=str(result.message);completion_refresh_pending=true
