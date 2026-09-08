extends "res://tests/battle_timeline_acceptance.gd"

const Work=preload("res://sim/base_work_rules.gd")
const BasePanel=preload("res://playtest/base_progress_panel.gd")

func _run()->void:
	var session=_new_engaged_duo()
	if session==null:quit(1);return
	for i in range(180):
		if session.individual_battle.next_event().is_empty():break
		var result:Dictionary=session.individual_battle.commit()
		_check(result.get("accepted",false),"real combat progresses")
		if not result.get("accepted",false):break
	var world=session.sim.world;var party=world.party_encounter
	_check(party.safe_phase in ["GROUPED","GROUPED_COMPLETE"],"fight clears")
	var leader:int=world.party_control_actor_id()
	var path:Dictionary=session.find_exploration_path(leader,session._map_layout.entry_position)
	_check(path.get("found",false),"path home")
	if path.get("found",false):
		for p in path.path.slice(1):
			_check(session.commit_exploration(SimCommand.move_to(leader,p)).get("accepted",false),"walk home")
	_check(session.base_return().get("accepted",false),"return after combat")
	var target:=-1;var stress:=-1
	for row in session.base_overview().rest:
		if bool(row.can_rest) and int(row.stress)>stress:target=int(row.entity_id);stress=int(row.stress)
	print("REST_AFTER_COMBAT ",session.base_overview().rest)
	_check(target>0,"actual combat leaves a resident needing rest")
	if target<=0:
		for failure in failures:printerr("FAIL ",failure)
		quit(1);return
	var request:={"action":"REST","entity_id":str(target)}
	var gold:int=session.town_gold();var hp:int=world.entities[target].health
	var emotional_before:Dictionary=party.member(target).emotion_state.to_dict()
	var expected_emotions:Dictionary=preload("res://sim/party_emotion_model.gd").town_rest_projection(
		party.member(target).emotion_state,world.world_time).after
	_check(not Work.operation_error({"action":"REST","entity_id":target}).is_empty(),"wire IDs must be canonical strings")
	_check(not session.base_work({"action":"REST","entity_id":"99999"}).get("accepted",false),"reject foreign resident")
	_check(session.base_work(request).get("accepted",false),"order selected resident to rest")
	_check_eq(int(Work.current(world.events).worker_id),target,"chosen resident walks, not first worker")
	_check_eq(session.town_gold(),gold-session.TOWN_SHRINE_COST,"reserve fee once")
	_check_eq(party.member(target).stress,stress,"ordering is not instant recovery")
	_check(not session.base_work(request).get("accepted",false),"duplicate order rejected")
	_check(session.base_work({"action":"TICK"}).get("accepted",false),"resident approaches lodge")
	var saved:String=session.save_session_json();var loaded=Session.new()
	_check(loaded.load_session_json(saved).get("accepted",false),"pending rest replays")
	_check_eq(Work.current(loaded.sim.world.events),Work.current(world.events),"rest route and fee reservation restore")
	_check(session.base_work({"action":"CANCEL"}).get("accepted",false),"cancel rest")
	_check_eq(session.town_gold(),gold,"refund exact fee")
	_check_eq(party.member(target).stress,stress,"cancel grants no recovery")
	_check_eq(party.member(target).emotion_state.to_dict(),emotional_before,"cancel grants no emotion effect")
	_check(not session.base_work({"action":"CANCEL"}).get("accepted",false),"no double refund")
	_check(session.base_work(request).get("accepted",false),"order again")
	var rest_job:Dictionary=Work.current(world.events)
	var last:Array=rest_job.route.back()
	_check(Rect2i(Vector2i(rest_job.tile_origin[0],rest_job.tile_origin[1]),Vector2i(rest_job.footprint[0],rest_job.footprint[1])).has_point(Vector2i(last[0],last[1])),"resident reaches bed inside lodge")
	for i in range(50):
		if Work.current(world.events).is_empty():break
		var result:Dictionary=session.base_work({"action":"TICK"})
		_check(result.get("accepted",false),"rest completion: "+str(result))
		if not result.get("accepted",false):break
	_check(Work.current(world.events).is_empty(),"rest completes")
	_check_eq(party.member(target).stress,maxi(0,stress-session._base_lodge_recovery()),"existing lodge recovery applies")
	_check_eq(session.town_gold(),gold-session.TOWN_SHRINE_COST,"completion does not double charge")
	_check_eq(world.entities[target].health,hp,"rest is not free physical treatment")
	for emotion_id in expected_emotions:
		_check_eq(party.member(target).emotion_state.intensity(emotion_id),expected_emotions[emotion_id],
			"emotion recovery matches preview including pending natural decay: "+str(emotion_id))
	_check_eq(world.world_state_error(),"","morale and emotion canonical audit")
	_check(loaded.load_session_json(session.save_session_json()).get("accepted",false),"completed rest replays")
	_check(not session.base_work({"action":"TICK"}).get("accepted",false),"no repeated completion")
	root.size=Vector2i(360,800)
	var panel=BasePanel.new();root.add_child(panel);panel.size=Vector2(360,800)
	panel.present(session.base_overview(),false,"LODGE");await process_frame;await process_frame
	var button:=panel.find_child("BaseRest%d"%target,true,false) as Button
	_check(button!=null and button.size.y>=48,"mobile resident rest control exists")
	_check(panel.find_child("BaseFacilityServiceLODGE",true,false)==null,"no redundant lodge service screen button")
	var can_rest_again:=false
	for row in session.base_overview().rest:
		if int(row.entity_id)==target:can_rest_again=bool(row.can_rest)
	_check_eq(button.disabled,not can_rest_again,"rest button follows both stress and emotional need")
	panel.free()
	for failure in failures:printerr("FAIL ",failure)
	print("BASE_REST_ACCEPTANCE ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
