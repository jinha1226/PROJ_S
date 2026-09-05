extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")
const VisualMap = preload("res://playtest/party_visual_test_map.gd")


func test_tab_assessment_is_pure_and_attack_button_approaches_one_step()->bool:
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	check(session.reset_party(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID,
		VisualMap.previous_product_dungeon(44),false),
		"visible product enemy fixture initializes")
	var state=session.sim.world.party_encounter
	var hero_id:=int(state.protagonist_id)
	var before:=session.save_session_json()
	var assessment:Dictionary=session.tab_attack_assessment()
	check(bool(assessment.accepted) and assessment.tab_action=="APPROACH",
		"visible non-adjacent monster produces a DCSS-style approach action")
	check_eq(session.save_session_json(),before,"Tab assessment never mutates authority")
	var destination:=Vector2i(int(assessment.destination[0]),int(assessment.destination[1]))
	var origin:Vector2i=session.sim.world.entities[hero_id].position
	check(maxi(absi(destination.x-origin.x),absi(destination.y-origin.y))==1,
		"Tab approach proposes exactly one adjacent movement action")
	var journal_before:int=session.command_journal.size()
	var time_before:=int(session.sim.world.world_time)
	var sandbox=Sandbox.new();sandbox.initialize_for_headless_test(session,true)
	sandbox._on_product_attack()
	var new_rows:Array=session.command_journal.slice(journal_before)
	var timed_rows:=0
	for row in new_rows:
		if str(row.get("kind","")) in ["exploration","party_turn"]:timed_rows+=1
	check_eq([session.sim.world.world_time,session.sim.world.entities[hero_id].position,
		timed_rows],[time_before+100,destination,1],
		"one attack-button activation commits one proposed approach turn")
	check(new_rows.size()<=2,"contact may add only its zero-time deployment journal row")
	sandbox.free()
	return finish()


func test_repeated_tab_actions_enter_combat_approach_and_reach_melee()->bool:
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var state=session.sim.world.party_encounter
	var hero_id:=int(state.protagonist_id)
	check(session.commit_exploration(
		load("res://sim/sim_command.gd").wait(hero_id)).accepted,
		"solo fixture reaches canonical contact")
	var contact:Dictionary=session.tab_attack_assessment()
	check(bool(contact.accepted) and contact.tab_action=="ENTER_COMBAT",
		"Tab converts internal contact into the ordinary solo combat surface")
	check(session.enter_solo_combat().accepted,"solo combat deployment commits")
	var reached_melee:=false
	for _turn in range(12):
		var before:=session.save_session_json()
		var assessment:Dictionary=session.tab_attack_assessment()
		check_eq(session.save_session_json(),before,
			"each combat Tab assessment remains pure")
		if not bool(assessment.get("accepted",false)):break
		var result:Dictionary
		if str(assessment.tab_action)=="ATTACK":
			reached_melee=true
			result=session.commit_direct_solo_action(hero_id,"MELEE",[],
				int(assessment.target_id))
		elif str(assessment.tab_action)=="APPROACH":
			result=session.commit_direct_solo_action(hero_id,"MOVE",
				assessment.destination)
		else:break
		check(bool(result.accepted),"proposed Tab action commits through normal authority")
		if not bool(result.accepted) or reached_melee:break
	check(reached_melee,"repeated attack actions eventually select adjacent melee")
	return finish()
