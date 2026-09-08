extends "res://tests/battle_timeline_acceptance.gd"

func _run()->void:
	var session=_new_engaged_duo()
	if session==null:quit(1);return
	var world=session.sim.world;var party=world.party_encounter
	var founder:int=party.protagonist_id;var companion:int=party.active_party_member_ids[1]
	# Stand without attacking, through public commands, until real enemy damage
	# incapacitates the front actor. No HP/life/body/snapshot fixture mutation.
	_check(session.issue_actor_command(founder,"STOP_ATTACK").get("accepted",false),"founder waits")
	_check(session.issue_actor_command(companion,"STOP_ATTACK").get("accepted",false),"companion waits")
	for index in range(500):
		if world.combatant_states[founder].life_state!="ACTIVE":break
		var result:Dictionary=session.individual_battle.commit()
		if not result.get("accepted",false):_check(false,"battle step "+str(result));break
		if index%50==0:print("SURVIVOR_PROGRESS ",index," HP ",world.entities[founder].health," / ",world.entities[companion].health)
	_check(world.combatant_states[founder].life_state!="ACTIVE","real battle defeats founder")
	_check(world.combatant_states[companion].life_state=="ACTIVE","companion survives founder")
	print("SURVIVOR_BOUNDARY ",party.safe_phase," CONTROL ",world.party_control_actor_id()," WORLD ",world.world_state_error())
	_check(party.safe_phase!="PARTY_DEFEATED","one death does not end the run")
	_check_eq(world.party_control_actor_id(),companion,"living companion becomes exploration leader")
	_check_eq(party.protagonist_id,founder,"founder identity never reassigned")
	_check_eq(world.world_state_error(),"","survivor boundary canonical audit")
	var save:String=session.save_session_json()
	_check(not save.is_empty(),"survivor state can be saved")
	if not save.is_empty():
		var loaded=Session.new()
		var result:Dictionary=loaded.load_session_json(save)
		_check(result.get("accepted",false),"survivor save replays "+str(result.get("reason","")))
		if result.get("accepted",false):
			for i in range(300):
				if loaded.sim.world.party_encounter.safe_phase=="PARTY_DEFEATED":break
				var losing:Dictionary=loaded.individual_battle.commit()
				if not losing.get("accepted",false):_check(false,"defeat branch step: "+str(losing));break
			_check_eq(loaded.sim.world.party_encounter.safe_phase,"PARTY_DEFEATED","all incapacitated ends the battle")
			_check_eq(loaded.sim.world.world_state_error(),"","all-incapacitated state audits")
			var defeat_loaded=Session.new()
			_check(defeat_loaded.load_session_json(loaded.save_session_json()).get("accepted",false),"defeat state replays")
	_check(session.issue_actor_command(companion,"FOLLOW").get("accepted",false),"survivor accepts combat instructions")
	var active_steps:=0
	for index in range(180):
		var next:Dictionary=session.individual_battle.next_event()
		if next.is_empty():break
		if int(next.actor_id)==companion:
			if world.entities[companion].health<80 and session.individual_battle.assessment(companion,"MEND",companion).get("accepted",false):
				session.individual_battle.reserve(companion,"MEND",companion)
			else:
				for enemy in session.party_status().visible_enemy_ids:
					if session.individual_battle.assessment(companion,"FIREBOLT",int(enemy)).get("accepted",false):
						session.individual_battle.reserve(companion,"FIREBOLT",int(enemy));break
		var result:Dictionary=session.individual_battle.commit()
		_check(result.get("accepted",false),"survivor continues timed combat "+str(result.get("reason","")))
		if not result.get("accepted",false):break
		if int(next.actor_id)==companion:active_steps+=1
	_check(active_steps>0,"living companion actually takes turns after founder death")
	_check_eq(world.world_state_error(),"","continued combat canonical audit")
	if party.safe_phase=="PARTY_DEFEATED":
		_check(preload("res://sim/party_survival_rules.gd").defeated(world),"defeat requires every party member incapacitated")
	print("SURVIVOR_CONTINUED ",party.safe_phase," ACTIONS ",active_steps)
	if party.safe_phase in ["GROUPED","GROUPED_COMPLETE"]:
		var loot:Dictionary=session.battle_loot();var supply:Dictionary={}
		for row in loot.rows:
			if row.has("resource_cache_id"):supply=row;break
		_check(not supply.is_empty(),"cleared encounter drops building materials")
		if not supply.is_empty():
			var before_haul:Dictionary=session.base_overview().carried.duplicate()
			var slots:int=session.protagonist_inventory().used_backpack_slots
			var picked:Dictionary=session.take_battle_loot(int(loot.battle_id),str(supply.instance_id))
			_check(picked.get("accepted",false),"survivor takes building supplies: "+str(picked.get("reason","")))
			_check_eq(session.base_overview().carried[supply.resource_id],int(before_haul[supply.resource_id])+int(supply.quantity),"supplies enter finite haul ledger")
			_check_eq(session.protagonist_inventory().used_backpack_slots,slots,"supplies do not consume equipment slots")
			_check(not session.take_battle_loot(int(loot.battle_id),str(supply.instance_id)).get("accepted",false),"cannot duplicate salvage pickup")
		var path:Dictionary=session.find_exploration_path(companion,session._map_layout.entry_position)
		_check(path.get("found",false),"survivor can plan path back to entrance")
		if path.get("found",false):
			for position in path.path.slice(1):
				var move:Dictionary=session.commit_exploration(SimCommand.move_to(companion,position))
				_check(move.get("accepted",false),"survivor exploration move: "+str(move.get("reason","")))
				if not move.get("accepted",false) or party.safe_phase not in ["GROUPED","GROUPED_COMPLETE"]:break
		var returned:Dictionary=session.base_return()
		_check(returned.get("accepted",false),"survivor returns to base: "+str(returned.get("reason","")))
		_check_eq(world.world_state_error(),"","return after founder death canonical")
		if returned.get("accepted",false):
			var departed:Dictionary=session.depart_town()
			_check(departed.get("accepted",false),"survivor can depart on next expedition: "+str(departed.get("reason","")))
			_check_eq(world.world_state_error(),"","survivor next expedition canonical")
	var restored=Session.new()
	var restored_result:Dictionary=restored.load_session_json(session.save_session_json())
	_check(restored_result.get("accepted",false),"continued combat replays: "+str(restored_result.get("reason","")))
	for failure in failures:printerr("FAIL ",failure)
	print("SURVIVOR_ACCEPTANCE ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
