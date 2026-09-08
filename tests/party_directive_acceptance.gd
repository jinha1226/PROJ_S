extends "res://tests/battle_timeline_acceptance.gd"

func _run()->void:
	var session=_new_engaged_duo()
	if session==null:quit(1);return
	_check(session.individual_battle.commit().get("accepted",false),"activate current combat rules")
	var world=session.sim.world;var party=world.party_encounter
	var id:int=party.active_party_member_ids[1];var target:int=party.contact_enemy_id
	_check(session.issue_actor_command(id,"ATTACK_TARGET",target).get("accepted",false),"issue focus")
	var member=party.member(id);var stress:int=member.stress
	member.stress=1000 # query-only panic probe, restored before save or actions
	var action=preload("res://sim/party_action_command.gd").hold(party.protagonist_id)
	var decision:Dictionary=session.sim.party_coordinator._companion_decision(id,action,{})
	_check_eq(decision.selected_action_id,"ENGAGE","explicit attack takes priority over fear")
	_check_eq(decision.reason_code,"party_command:ATTACK_TARGET","decision explains explicit directive")
	member.stress=stress
	_check(session.issue_actor_command(id,"RETREAT").get("accepted",false),"explicit retreat remains available")
	decision=session.sim.party_coordinator._companion_decision(id,action,{})
	_check_eq(decision.selected_action_id,"RETREAT","retreat instruction is still respected")
	_check(session.issue_actor_command(id,"FOLLOW").get("accepted",false),"clear instruction")
	member.stress=1000
	decision=session.sim.party_coordinator._companion_decision(id,action,{})
	_check(decision.selected_action_id!="RETREAT","healthy companion does not flee from stress alone")
	member.stress=stress
	_check_eq(world.world_state_error(),"","query probes leave canonical state intact")
	for failure in failures:printerr("FAIL ",failure)
	print("PARTY_DIRECTIVE_ACCEPTANCE ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
