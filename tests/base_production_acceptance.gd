extends SceneTree

const Session=preload("res://playtest/party_playtest_session.gd")
const Work=preload("res://sim/base_work_rules.gd")
const Production=preload("res://sim/base_production_rules.gd")
const Items=preload("res://sim/world_item_operations.gd")
const BasePanel=preload("res://playtest/base_progress_panel.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)

func finish_work(session)->void:
	for i in range(50):
		if Work.current(session.sim.world.events).is_empty():return
		var result:Dictionary=session.base_work({"action":"TICK"})
		check(result.get("accepted",false),"work tick: "+str(result))
		if not result.get("accepted",false):return
	check(false,"work finishes within bounded route")

func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var produce:={"action":"PRODUCE","recipe_id":"HEALING_POTION"}
	var claim:={"action":"CLAIM","recipe_id":"HEALING_POTION"}
	check(not session.base_work(produce).get("accepted",false),"cannot manufacture in dungeon")
	check(not Work.operation_error({"action":"PRODUCE","recipe_id":"UNKNOWN"}).is_empty(),"reject unknown recipe")
	check(not Work.operation_error({"action":"CLAIM","recipe_id":"HEALING_POTION","quantity":99}).is_empty(),"reject custom output count")
	var helper=preload("res://tests/base_progression_acceptance.gd").new()
	var herbs:Dictionary={}
	for row in helper._safe_cache_rows(session,helper._expected_cache_rows(session,1)):
		if row.resource_id=="HERBS":herbs=row;break
	check(not herbs.is_empty(),"real dungeon has safely reachable herbs")
	if herbs.is_empty():quit(1);return
	check(helper._walk_to_position(session,helper._row_position(herbs)),"walk to herbs")
	check(session.base_gather().get("accepted",false),"gather herbs")
	check(helper._walk_to_position(session,helper._entry_position(session)),"walk to entry")
	check(session.base_return().get("accepted",false),"bank herbs")
	check(not session.base_work(produce).get("accepted",false),"clinic is required")
	var position:=Vector2i(-1,-1)
	for y in range(16):
		for x in range(16):
			if session.base_build_assessment("CLINIC",Vector2i(x,y)).get("accepted",false):position=Vector2i(x,y);break
		if position.x>=0:break
	check(position.x>=0,"clinic site available")
	check(session.base_work({"action":"BUILD","type_id":"CLINIC","tile_origin":[position.x,position.y]}).get("accepted",false),"build clinic")
	finish_work(session)
	var stock:Dictionary=session.base_overview().stock.duplicate()
	check(int(stock.HERBS)>=2,"herbs remain after clinic construction")
	check(session.base_work(produce).get("accepted",false),"order potion")
	check(not session.base_work(produce).get("accepted",false),"one shared job slot")
	check(session.base_work({"action":"TICK"}).get("accepted",false),"worker moves to clinic")
	var loaded=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(loaded.load_session_json(session.save_session_json()).get("accepted",false),"pending production replays")
	check(session.base_work({"action":"CANCEL"}).get("accepted",false),"cancel production")
	check(session.base_overview().stock==stock,"cancel refunds herbs")
	check(Production.ready_stock(session.sim.world.events).HEALING_POTION==0,"cancel produces nothing")
	check(session.base_work(produce).get("accepted",false),"reorder")
	finish_work(session)
	check(Production.ready_stock(session.sim.world.events).HEALING_POTION==1,"one completed potion stored at clinic")
	check(int(session.base_overview().stock.HERBS)==int(stock.HERBS)-2,"herbs charged once")
	check(not session.base_work({"action":"TICK"}).get("accepted",false),"cannot complete twice")
	var ready_save:String=session.save_session_json()
	check(loaded.load_session_json(ready_save).get("accepted",false),"finished stock replays")
	check(loaded.depart_town().get("accepted",false),"depart with finished goods stored at base")
	check(Production.ready_stock(loaded.sim.world.events).HEALING_POTION==1,"expedition preserves stored goods")
	check(not loaded.base_work(claim).get("accepted",false),"cannot claim remotely in dungeon")
	check(loaded.base_return().get("accepted",false),"return for stored goods")
	check(Production.ready_stock(loaded.sim.world.events).HEALING_POTION==1,"return preserves stored goods")
	check(loaded.load_session_json(ready_save).get("accepted",false),"restore ready-goods branch")
	root.size=Vector2i(360,800)
	var ready_panel=BasePanel.new();root.add_child(ready_panel);ready_panel.size=Vector2(360,800)
	ready_panel.present(session.base_overview(),false,"CLINIC")
	await process_frame;await process_frame
	var requested:Array=[]
	ready_panel.production_requested.connect(func(action,recipe):requested.append([action,recipe]))
	var claim_button:=ready_panel.find_child("BaseClaimHEALING_POTION",true,false) as Button
	check(claim_button!=null and not claim_button.disabled,"ready goods expose claim button")
	if claim_button!=null:
		var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT
		press.pressed=true;press.position=claim_button.get_global_rect().get_center()
		root.push_input(press,true);await process_frame
		var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT
		release.pressed=false;release.position=press.position
		root.push_input(release,true);await process_frame
	check(requested==[["CLAIM","HEALING_POTION"]],"mobile claim control emits one precise request")
	ready_panel.free()
	# Isolated full-bag probe uses ordinary item grants; rejected claim must not
	# change the world, consume output, or journal anything.
	var id:int=loaded.sim.world.party_control_actor_id()
	for i in range(40):
		if not Items.commit_grant(loaded.sim.world,id,"POTION_HEALING",1,
			loaded.sim.world.entities[id].position,"TEST_CAPACITY").get("accepted",false):break
	var before:String=JSON.stringify(loaded.sim.snapshot())
	check(not loaded.base_work(claim).get("accepted",false),"full bag refuses claim")
	check(JSON.stringify(loaded.sim.snapshot())==before,"full bag preserves goods and world")
	var count_before:=potions(session)
	check(session.base_work(claim).get("accepted",false),"claim into actual inventory")
	check(potions(session)==count_before+1,"usable potion quantity increased")
	check(not session.base_work(claim).get("accepted",false),"no duplicate claim")
	check(loaded.load_session_json(session.save_session_json()).get("accepted",false),"claimed inventory replays")
	check(loaded.sim.world.world_state_error().is_empty(),"canonical production world valid")
	# Mobile panel exposes one produce button and one claim button for the
	# selected clinic; manufacture is disabled when there are no herbs left.
	root.size=Vector2i(360,800)
	var panel=BasePanel.new();root.add_child(panel);panel.size=Vector2(360,800)
	panel.present(session.base_overview(),false,"CLINIC");await process_frame
	var button:=panel.find_child("BaseProduceHEALING_POTION",true,false) as Button
	check(button!=null and button.disabled and button.size.y>=48,"mobile production button shows insufficient materials")
	panel.free()
	print("BASE_PRODUCTION_ACCEPTANCE ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)

func potions(session)->int:
	var total:=0
	var inventory=session.sim.world.item_state.inventory(session.sim.world.party_control_actor_id())
	for item in inventory.backpack:
		if item.definition_id=="POTION_HEALING":total+=int(item.quantity)
	return total
