extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func hold_round(s):
	var r:Dictionary=s.sim.world.party_encounter.round_combat
	var hero:int=s.sim.world.party_encounter.protagonist_id
	var position:Vector2i=s.sim.world.entities[hero].position
	var path:Array=[[position.x,position.y+1],[position.x,position.y]]
	var edited:Dictionary=s.edit_round_plan(hero,{"action":Action.hold(hero).to_dict(),"path":path},int(r.plan_revision))
	check(edited.accepted,"hold plan "+str(edited.get("reason","")))
	var result:Dictionary=s.confirm_round(int(r.round_id),int(r.plan_revision))
	check(result.accepted,"hold round "+str(result.get("reason","")))
func run():
	# Preserve an existing nine-room v1 save's old food policy and journal.
	var old=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	old.sim.world.party_encounter.nine_room_floor.erase("care")
	old.sim.world.party_encounter.nine_room_floor.schema_version=1
	var hero:int=old.sim.world.party_encounter.protagonist_id
	var food:int=old.sim.world.party_encounter.ration_milli
	for index in range(3):check(old.commit_field_action(Action.hold(hero)).accepted,"legacy wait")
	check(old.sim.world.party_encounter.ration_milli<food,"legacy food drain preserved")
	var saved:String=old.save_session_json();var clone=Session.new()
	var loaded:Dictionary=clone.load_session_json(saved)
	check(loaded.accepted and not clone.personal_rest_enabled(),"legacy save keeps care disabled "+str(loaded.get("reason","")))
	if loaded.accepted:check(clone.sim.snapshot()==old.sim.snapshot(),"legacy nine-room replay exact")
	# A real player command sequence, without injected positions or resources.
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;hero=w.party_encounter.protagonist_id;food=w.party_encounter.ration_milli
	for index in range(3):check(s.commit_field_action(Action.move_to(hero,w.entities[hero].position+Vector2i.DOWN)).accepted,"walk to first combat entrance")
	check(s.request_room_exit(hero,"F1_R4_R7",int(w.party_encounter.nine_room_floor.revision)).accepted,"enter combat")
	for index in range(7):
		if w.entities[hero].health<w.entities[hero].max_health-1:break
		hold_round(s)
	check(s.request_room_exit(hero,"F1_R4_R7",int(w.party_encounter.nine_room_floor.revision)).accepted,"retreat to center")
	for iteration in range(8):
		if w.entities[hero].position==Vector2i(14,11):break
		var route:Dictionary=s.sim.pathfinder.find_path_to_any(hero,[Vector2i(14,11)])
		check(route.get("found",false),"escape route exists")
		if not route.get("found",false):break
		if s.round_active():
			var r:Dictionary=w.party_encounter.round_combat
			var path:Array=[]
			for cell in route.path.slice(1,1+int(r.plans[str(hero)].move_budget)):path.append([cell.x,cell.y])
			check(s.edit_round_plan(hero,{"action":Action.hold(hero).to_dict(),"path":path},int(r.plan_revision)).accepted,"multi-tile escape plan")
			var before:int=w.world_time
			check(s.confirm_round(int(r.round_id),int(r.plan_revision)).accepted,"escape round")
			check(w.world_time==before+100,"multi-tile movement one boundary")
		else:check(s.commit_field_action(Action.move_to(hero,route.path[1])).accepted,"escape walk")
	check(s.request_room_exit(hero,"F1_R4_R5",int(w.party_encounter.nine_room_floor.revision)).accepted,"escape to safe neighbor")
	for index in range(4):
		if w.combatant_states[hero].status_rows.is_empty():break
		check(s.commit_field_action(Action.hold(hero)).accepted,"settle separate status effect")
	var offer:Dictionary=s.personal_rest_preview()
	check(w.events.any(func(event):return event.type=="combat.physical_damage" and event.target_id==hero),"real enemy damage is journalled")
	check(w.entities[hero].health<w.entities[hero].max_health or load("res://sim/body_penalty_rules.gd").needs_recovery(w.body_states[hero]),"real encounter leaves a correctable deficit")
	var pursuit_here:bool=w.party_encounter.nine_room_floor.pending_pursuit.any(func(row):return row.floor_index==w.party_encounter.nine_room_floor.floor_index and row.target_room==w.party_encounter.nine_room_floor.active_room_id)
	if pursuit_here:
		# Full-room aggro can now send a pursuer down this fixed escape route.
		# A room with incoming pursuit is not a safe-rest fixture.
		check(not offer.accepted and offer.reason=="추격 또는 방 이동 중입니다","incoming pursuit blocks rest")
		var rest_before:Dictionary=s.sim.snapshot()
		var care:Dictionary=w.party_encounter.nine_room_floor.care
		check(not s.request_personal_rest(int(care.revision),int(care.request_serial)+1).accepted,"unsafe rest commit rejected")
		check(rest_before==s.sim.snapshot(),"unsafe rest costs nothing")
		var pursuit_clone=Session.new();var pursuit_loaded:Dictionary=pursuit_clone.load_session_json(s.save_session_json())
		check(pursuit_loaded.accepted,"pursuit journal replay")
		if pursuit_loaded.accepted:check(pursuit_clone.sim.snapshot()==s.sim.snapshot(),"pursuit replay exact")
	else:check(offer.accepted,"rest available after safe escape "+str(offer.reason))
	check(w.party_encounter.ration_milli==food,"walking battle retreat no food drain")
	if offer.accepted:
		var ui=Sandbox.new();ui.initialize_for_headless_test(s,true);root.size=Vector2i(360,800);root.add_child(ui);ui.set_process(false)
		for index in range(4):await process_frame
		var before:Dictionary=s.sim.snapshot()
		ui._on_product_rest()
		for index in range(2):await process_frame
		check(ui._personal_rest_dialog!=null and ui._personal_rest_dialog.visible,"rest preview dialog shown")
		check(ui._personal_rest_dialog.dialog_text.contains("파티 식량 10") and ui._personal_rest_dialog.dialog_text.contains("HP +") and ui._personal_rest_dialog.dialog_text.contains("MP +"),"common cost and personal resources visible")
		check(s.sim.snapshot()==before,"opening UI does not rest")
		ui._personal_rest_dialog.hide();ui._commit_personal_rest_offer()
		check(w.party_encounter.ration_milli==food-10000,"UI rest costs party once")
		ui.queue_free();await process_frame
		saved=s.save_session_json();clone=Session.new();loaded=clone.load_session_json(saved)
		check(loaded.accepted,"rest journal loads "+str(loaded.get("reason","")))
		if loaded.accepted:check(clone.sim.snapshot()==s.sim.snapshot(),"rest journal snapshot exact")
	print("NINE_ROOM_CARE_REPLAY ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
