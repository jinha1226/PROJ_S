extends SceneTree

## Product exploration: the three-line event feed, the [REST] macro that waits
## until HP is full, and picking up every item on the cell you arrive at.

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const SimCommand=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]
var ui;var session

func _init()->void:call_deferred("run")
func _check(value:bool,message:String)->void:
	if not value:failures.append(message);printerr("FAIL ",message)
func _pump(seconds:float)->void:
	var t:=0.0
	while t<seconds:ui._tick_autonomous_battle(0.05);t+=0.05

func run()->void:
	session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	session.town_life_command({"action":"START"});session.depart_town()
	ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true)
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);ui.size=Vector2(390,800);root.add_child(ui);ui.set_process(false)
	for i in range(3):await process_frame
	var world=session.sim.world;var hero:int=int(world.party_encounter.protagonist_id)
	_check(ui.event_label.max_lines_visible==3,"event feed shows three lines")
	_check(ui.product_wait_guard_button!=null and ui.product_wait_guard_button.text=="[휴식]","[휴식] sits in the wait slot of the action dock")
	# Fight once so there is loot on the ground (and usually some damage).
	var fought:=false
	for round in range(700):
		var phase:=str(session.party_status().get("safe_phase",""))
		if phase=="ENGAGED":
			# [공격]: attack the nearest enemy when adjacent, otherwise one step closer.
			if ui.hero_turn_waiting():ui._on_product_auto();await process_frame
			_pump(0.5)
			if str(session.party_status().get("safe_phase",""))!="ENGAGED":fought=true;break
			continue
		if phase in ["CONTACT","REGROUP_READY"]:
			for i in range(6):await process_frame
			ui.flush_auto_flow_for_headless_test();await process_frame;continue
		# Walk toward the nearest enemy by straight-line distance (one pathfinder
		# call per hop); once adjacent, strike first or wait for it to notice.
		var hp:Vector2i=world.entities[hero].position
		var target_enemy:=-1;var target_distance:=9999
		for id in world.party_encounter.enemy_ids:
			if not world.is_autonomous_target(int(id)):continue
			var ep:Vector2i=world.entities[int(id)].position
			var d:int=maxi(absi(ep.x-hp.x),absi(ep.y-hp.y))
			if d<target_distance:target_distance=d;target_enemy=int(id)
		if target_enemy<0:break
		if target_distance<=1:
			ui.grid.actor_pressed.emit(target_enemy)
		else:
			var ep:Vector2i=world.entities[target_enemy].position
			var raw:Dictionary=session.sim.pathfinder.find_path(hero,ep+Vector2i(signi(hp.x-ep.x),signi(hp.y-ep.y)))
			if bool(raw.get("found",false)) and raw.path.size()>=2:ui.grid.world_cell_pressed.emit(raw.path[1])
			else:ui._on_explore(Vector2i.ZERO)
		await process_frame;await process_frame
	_check(fought,"fixture wins one fight")
	# Pick up everything on the richest loot cell within reach.
	var cells:Dictionary={}
	for row in world.item_state.ground_items.rows:
		var key:=str(row.position);cells[key]=int(cells.get(key,0))+1
	var target:=Vector2i(-1,-1);var most:=0
	for row in world.item_state.ground_items.rows:
		var count:int=int(cells.get(str(row.position),0))
		if count>most and bool(session.sim.pathfinder.find_path(hero,row.position).get("found",false)):most=count;target=row.position
	if target!=Vector2i(-1,-1):
		var bag_before:int=int(session.protagonist_inventory().get("used_backpack_slots",0))
		for step in range(40):
			if world.entities[hero].position==target:break
			ui.grid.world_cell_pressed.emit(target);await process_frame;await process_frame
			for i in range(40):
				if not bool(session.exploration_route_state().get("active",false)):break
				ui._continue_route_on_cadence(ui.route_generation)
		_check(world.entities[hero].position==target,"hero reaches the loot cell")
		var left:=0
		for row in world.item_state.ground_items.rows:
			if row.position==target:left+=1
		_check(left==0 or int(session.protagonist_inventory().get("used_backpack_slots",0))>=int(session.protagonist_inventory().get("capacity",0)),
			"arriving picks up every item on the cell (%d of %d left)"%[left,most])
		_check(int(session.protagonist_inventory().get("used_backpack_slots",0))>bag_before,"bag gained the loot")
		_check("주웠습니다" in str(ui.notice_text),"pickup feedback names what was taken")
	# A nearby group may have noticed the hero on the way to the loot; finish
	# that fight the same way before resting.
	for round in range(400):
		var phase:=str(session.party_status().get("safe_phase",""))
		if phase=="ENGAGED":
			if ui.hero_turn_waiting():ui._on_product_auto();await process_frame
			_pump(0.5);continue
		if phase in ["CONTACT","REGROUP_READY"]:
			for i in range(6):await process_frame
			ui.flush_auto_flow_for_headless_test();await process_frame;continue
		break
	_check(str(session.party_status().get("view_mode",""))=="EXPLORATION","exploration resumes before resting (phase %s)"%str(session.party_status().get("safe_phase","")))
	# Rest until full.
	var hero_entity=world.entities[hero]
	if int(hero_entity.health)<int(hero_entity.max_health):
		ui._on_product_rest();await process_frame
		_check(ui._product_rest_active,"[REST] starts resting")
		var guard:=0
		while ui._product_rest_active and guard<400:
			ui._product_rest_due_msec=0;ui._continue_product_rest(ui._product_rest_generation);guard+=1
		_check(not ui._product_rest_active,"rest stops on its own")
		_check(int(hero_entity.health)==int(hero_entity.max_health) or "적이" in str(ui.notice_text) or "피해" in str(ui.notice_text) or "굶주" in str(ui.notice_text),
			"rest ends with full HP or a stated interruption (%s)"%str(ui.notice_text))
		_check("휴식" in str(ui.notice_text),"rest feedback is shown")
	else:
		ui._on_product_rest();await process_frame
		_check(not ui._product_rest_active and "회복" in str(ui.notice_text),"rest at full HP explains it is not needed")
	var saved:String=session.save_session_json();var loaded=Session.new()
	var load_result:Dictionary=loaded.load_session_json(saved)
	_check(bool(load_result.get("accepted",false)),"session with pickups and rest waits reloads")
	if bool(load_result.get("accepted",false)):_check(loaded.sim.snapshot()==session.sim.snapshot(),"pickups and rest waits replay exactly")
	if failures.is_empty():print("PASS rest and pickup");quit(0)
	else:printerr("FAIL rest and pickup: %d failures"%failures.size());quit(1)
