extends SceneTree

const Session=preload("res://playtest/party_playtest_session.gd")
const Work=preload("res://sim/base_work_rules.gd")
const View=preload("res://playtest/base_settlement_view.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("run")

func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)

func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(session.sim.world.party_encounter.opening_event==null,"production duo has no floor-one traveler")
	check(session.base_return().get("accepted",false),"return to base")
	var initial:Dictionary=session.base_overview().stock.duplicate()
	var tile:=Vector2i(-1,-1)
	for y in range(16):
		for x in range(16):
			if session.base_build_assessment("CLINIC",Vector2i(x,y)).get("accepted",false):tile=Vector2i(x,y);break
		if tile.x>=0:break
	check(tile.x>=0,"reachable construction footprint")
	if tile.x<0:quit(1);return
	var op:={"action":"BUILD","type_id":"CLINIC","tile_origin":[tile.x,tile.y]}
	var ordered:Dictionary=session.base_work(op)
	check(ordered.get("accepted",false),"order accepted: "+str(ordered))
	check(not session._base_building_built("CLINIC"),"blueprint does not unlock service")
	check(not session.base_work(op).get("accepted",false),"duplicate order rejected")
	check(not session.base_build("CLINIC",tile).get("accepted",false),"legacy instant build cannot bypass pending work")
	check(session.base_work({"action":"TICK"}).get("accepted",false),"worker takes canonical step")
	var saved:String=session.save_session_json()
	check(not saved.is_empty(),"save pending construction")
	var loaded=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var load_result:Dictionary=loaded.load_session_json(saved)
	check(load_result.get("accepted",false),"restore pending work: "+str(load_result))
	if load_result.get("accepted",false):check(Work.current(loaded.sim.world.events)==Work.current(session.sim.world.events),"exact work progress restored")
	check(session.base_work({"action":"CANCEL"}).get("accepted",false),"cancel work")
	check(session.base_overview().stock==initial,"cancellation refunds reserved materials")
	check(not session.base_work({"action":"CANCEL"}).get("accepted",false),"no double refund")
	check(session.base_work(op).get("accepted",false),"reorder construction")
	for i in range(40):
		if Work.current(session.sim.world.events).is_empty():break
		var tick:Dictionary=session.base_work({"action":"TICK"})
		check(tick.get("accepted",false),"progress "+str(tick))
		if not tick.get("accepted",false):break
	check(session._base_building_built("CLINIC"),"completed construction unlocks clinic")
	check(session.base_overview().stock=={"TIMBER":1,"STONE":0,"HERBS":0},"cost charged exactly once")
	check(session.sim.world.world_state_error().is_empty(),"canonical world valid")
	load_result=loaded.load_session_json(session.save_session_json())
	check(load_result.get("accepted",false),"completed work save replay: "+str(load_result))
	root.size=Vector2i(360,640)
	var view=View.new();root.add_child(view);view.size=Vector2(360,320)
	view.present(session.base_overview());await process_frame
	var original:float=view._cell_size()
	view.camera.zoom_at(view,2.0,Vector2(180,160))
	check(is_equal_approx(view._cell_size(),original*2),"base zoom scales cells and hit targets")
	var rect:Rect2=view.building_rect("CLINIC")
	check(rect.size.x>0,"building remains selectable after zoom")
	view.camera.zoom_at(view,0.1,Vector2(180,160))
	check(is_equal_approx(view.camera.zoom,1.0),"base minimum zoom")
	var selected:Array=[]
	view.building_selected.connect(func(id):selected.append(id))
	for id in [0,1]:
		var touch:=InputEventScreenTouch.new();touch.index=id;touch.pressed=true
		touch.position=Vector2(100+130*id,130)
		root.push_input(touch,true);await process_frame
	var drag:=InputEventScreenDrag.new();drag.index=1;drag.position=Vector2(280,130)
	root.push_input(drag,true);await process_frame
	check(view.camera.zoom>1.25,"real two-finger input zooms the base map")
	for id in [0,1]:
		var touch:=InputEventScreenTouch.new();touch.index=id;touch.pressed=false
		touch.position=Vector2(100 if id==0 else 280,130)
		root.push_input(touch,true);await process_frame
	check(selected.is_empty(),"pinch release does not select a building")
	view.free()
	_upgrade_after_gathering()
	print("BASE_WORK_ACCEPTANCE ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)

func _upgrade_after_gathering()->void:
	var helper=preload("res://tests/base_progression_acceptance.gd").new()
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var caches:Array=helper._safe_cache_rows(session,helper._expected_cache_rows(session,1))
	var timber:Array=[];var stone:Array=[]
	for row in caches:
		if row.resource_id=="TIMBER":timber.append(row)
		elif row.resource_id=="STONE":stone.append(row)
	check(timber.size()>=2 and not stone.is_empty(),"upgrade has accessible dungeon materials")
	if timber.size()<2 or stone.is_empty():return
	for row in [timber[0],stone[0],timber[1]]:
		check(helper._walk_to_position(session,helper._row_position(row)),"walk to upgrade materials")
		check(session.base_gather().get("accepted",false),"gather upgrade materials")
	check(helper._walk_to_position(session,helper._entry_position(session)),"walk home with upgrade materials")
	check(session.base_return().get("accepted",false),"bank upgrade materials")
	var stock:Dictionary=session.base_overview().stock.duplicate()
	var ordered:Dictionary=session.base_work({"action":"UPGRADE","type_id":"STORAGE"})
	check(ordered.get("accepted",false),"order queued upgrade: "+str(ordered))
	if not ordered.get("accepted",false):return
	var cost:Dictionary=Work.current(session.sim.world.events).cost
	check(int(session.base_overview().capacity)==8,"unfinished upgrade does not increase capacity")
	for i in range(40):
		if Work.current(session.sim.world.events).is_empty():break
		check(session.base_work({"action":"TICK"}).get("accepted",false),"advance upgrade work")
	check(int(session.base_overview().capacity)==12,"finished upgrade increases capacity")
	for resource in stock:
		check(int(session.base_overview().stock[resource])==int(stock[resource])-int(cost.get(resource,0)),"upgrade cost charged once: "+str(resource))
	var loaded=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(loaded.load_session_json(session.save_session_json()).get("accepted",false),"gather-return-upgrade replays exactly")
