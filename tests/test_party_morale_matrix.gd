extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Request = preload("res://sim/party_turn_request.gd")
const EnemyAwareness = preload("res://sim/enemy_awareness_state.gd")
const PartyMember = preload("res://sim/party_member_state.gd")
const HexacoProfile = preload("res://sim/dungeon_population/hexaco_profile.gd")

const CI_SEEDS := [1,2,3,4,5,6,7,8]
const MAX_COMBAT_TURNS := 60
const MAX_RECOVERY_TURNS := 30


func test_morale_seed_matrix_panics_changes_actions_recovers_and_restores() -> bool:
	var metrics := run_matrix(CI_SEEDS,MAX_COMBAT_TURNS,MAX_RECOVERY_TURNS)
	print("PARTY_MORALE_MATRIX_CI ",JSON.stringify(metrics))
	check_eq(metrics.setup_failures,0,"every morale fixture is valid")
	check_eq(metrics.rejected_steps,0,"morale never rejects an otherwise legal turn")
	check_eq(metrics.invalid_worlds,0,"morale leaves canonical worlds")
	check_eq(metrics.restore_failures,0,"every sampled morale state restores exactly")
	check_eq(metrics.terminal_encounters,metrics.encounters,
		"every morale encounter terminates without a combat stall")
	check(metrics.panic_entries>0,"combat pressure reaches persistent PANIC")
	check(metrics.contagion_rows>0,"real combat produces ally fear contagion")
	check(metrics.panic_decisions>0 and metrics.panic_legal_violations==0,
		"PANIC decisions use only RETREAT/HOLD")
	check(metrics.behavior_changes>0,
		"persisted PANIC changes at least one same-state companion choice")
	check(metrics.recovery_exits>0 and metrics.safe_recovery_rows>0,
		"safe turns return PANIC companions to NORMAL")
	return finish()


static func run_matrix(seeds:Array,max_combat_turns:int,
		max_recovery_turns:int)->Dictionary:
	var metrics := {"encounters":0,"terminal_encounters":0,"turns":0,
		"recovery_turns":0,"setup_failures":0,"rejected_steps":0,
		"invalid_worlds":0,"restore_failures":0,"panic_entries":0,
		"recovery_exits":0,"contagion_rows":0,"panic_decisions":0,
		"safe_recovery_rows":0,"panic_legal_violations":0,"behavior_changes":0}
	for seed_value in seeds:
		var seed := int(seed_value)
		var session = Session.new(seed,20260902)
		var state = session.sim.world.party_encounter
		var recruitable_id := _add_recruitable_companion(session,seed)
		if recruitable_id<=0 or not _spawn_reinforcements(session,3):
			metrics.setup_failures+=1
			continue
		if not session.recruit_companion(recruitable_id).accepted \
				or not session.commit_exploration(Command.wait(state.protagonist_id)).accepted:
			metrics.setup_failures+=1
			continue
		state=session.sim.world.party_encounter
		session.preview_deployment("WEDGE",session.available_companion_ids())
		if not session.commit_deployment().accepted:
			metrics.setup_failures+=1
			continue
		metrics.encounters+=1
		state=session.sim.world.party_encounter
		var panic_probe_id:=int(state.active_party_member_ids[1])
		# A canonical snapshot may start between thresholds without prior morale
		# history. The first public override supplies the authoritative source that
		# crosses 850; every later choice and recovery is fully autonomous.
		state.member(panic_probe_id).stress=840
		state.member(panic_probe_id).mental_mode="NORMAL"
		for _turn in range(max_combat_turns):
			state=session.sim.world.party_encounter
			if state.safe_phase!="ENGAGED":break
			var hero_leaf=session.sim.party_coordinator._suggest(
				state.protagonist_id,Action.hold(state.protagonist_id))
			var override_rows:Array=[]
			if _turn==0:
				override_rows.append({"actor_id":panic_probe_id,
					"action":Action.hold(panic_probe_id)})
			var request=Request.new(hero_leaf,override_rows)
			var explanation:Dictionary=session.sim.party_coordinator \
				.explain_companion_turn(request)
			var selected_by_actor:Dictionary={}
			for row in explanation.get("companions",[]):
				selected_by_actor[int(row.actor_id)]=str(row.selected_action_id)
				if str(row.mode)=="PANIC":
					metrics.panic_decisions+=1
					if str(row.selected_action_id) not in ["RETREAT","HOLD"]:
						metrics.panic_legal_violations+=1
			for member_id_value in state.active_party_member_ids:
				var member_id:=int(member_id_value)
				var member=state.member(member_id)
				if member==null or member.role!="COMPANION" \
						or member.mental_mode!="PANIC" \
						or not selected_by_actor.has(member_id):
					continue
				member.mental_mode="NORMAL"
				var counterfactual:Dictionary=session.sim.party_coordinator \
					.explain_companion_turn(request)
				member.mental_mode="PANIC"
				for row in counterfactual.get("companions",[]):
					if int(row.actor_id)==member_id \
							and str(row.selected_action_id)!=str(selected_by_actor[member_id]):
						metrics.behavior_changes+=1
						break
			var result=session.sim.step_party_turn(session.sim.preview_party_turn(request))
			metrics.turns+=1
			if not result.accepted:
				metrics.rejected_steps+=1
				break
			_count_morale_events(metrics,result.events)
			if not session.sim.world.world_state_error().is_empty():
				metrics.invalid_worlds+=1
				break
			if not _restores_exactly(session):
				metrics.restore_failures+=1
				break
		state=session.sim.world.party_encounter
		if state.safe_phase!="ENGAGED":metrics.terminal_encounters+=1
		if state.safe_phase not in ["GROUPED","GROUPED_COMPLETE"]:
			continue
		for _recovery_turn in range(max_recovery_turns):
			var has_panic:=false
			for member_id_value in state.active_party_member_ids:
				var member=state.member(int(member_id_value))
				if member!=null and member.mental_mode=="PANIC":has_panic=true
			if not has_panic:break
			var recovery=session.sim.step(Command.wait(state.protagonist_id))
			metrics.recovery_turns+=1
			if not recovery.accepted:
				metrics.rejected_steps+=1
				break
			_count_morale_events(metrics,recovery.events)
			if not session.sim.world.world_state_error().is_empty():
				metrics.invalid_worlds+=1
				break
			if not _restores_exactly(session):
				metrics.restore_failures+=1
				break
	return metrics


static func _count_morale_events(metrics:Dictionary,events:Array)->void:
	for event in events:
		if event.type!="party.morale_changed":continue
		if event.data.mode_before=="NORMAL" and event.data.mode_after=="PANIC":
			metrics.panic_entries+=1
		if event.data.mode_before=="PANIC" and event.data.mode_after=="NORMAL":
			metrics.recovery_exits+=1
		if "ALLY_FEAR_CONTAGION" in event.data.trigger_codes:
			metrics.contagion_rows+=1
		if "SAFE_RECOVERY" in event.data.trigger_codes:
			metrics.safe_recovery_rows+=1


static func _restores_exactly(session)->bool:
	var snapshot=session.sim.snapshot()
	var restored=Simulator.from_snapshot(snapshot)
	return restored!=null and restored.snapshot()==snapshot


static func _add_recruitable_companion(session,seed:int)->int:
	var world=session.sim.world
	var state=world.party_encounter
	var companion=world.add_entity("companion","보린",
		state.group_anchor+Vector2i(-1,1),110,["party_member","recruitable"],
		"dwarf","party")
	if companion==null:return -1
	state.party_member_ids.append(companion.id)
	state.party_member_ids.sort()
	state.member_rows[companion.id]=PartyMember.new(companion.id,3,"COMPANION",
		"RECRUITABLE",HexacoProfile.generated(seed,companion.id))
	return companion.id if world.world_state_error().is_empty() else -1


static func _spawn_reinforcements(session,count:int)->bool:
	var world=session.sim.world
	var state=world.party_encounter
	var origin:Vector2i=state.group_anchor
	for existing_enemy_id in state.enemy_ids:
		world.entities[existing_enemy_id].species_id="human"
		var existing_awareness=state.enemy_awareness(existing_enemy_id)
		existing_awareness.awareness_state="HUNTING"
		existing_awareness.suspicion=1000
		existing_awareness.last_known_target_position=origin
	var spawned:=0
	for radius in range(3,8):
		for y in range(origin.y-radius,origin.y+radius+1):
			for x in range(origin.x-radius,origin.x+radius+1):
				if maxi(absi(x-origin.x),absi(y-origin.y))!=radius:continue
				var position:=Vector2i(x,y)
				if not world.in_bounds(position):continue
				var enemy=world.add_entity("melee_enemy",
					"사기 고블린 %d"%(spawned+1),position,60,["party_enemy"],
					"human","enemy")
				if enemy==null:continue
				state.enemy_ids.append(enemy.id)
				state.enemy_ids.sort()
				state.enemy_busy_rows[enemy.id]=0
				var awareness=EnemyAwareness.new(enemy.id,enemy.position)
				awareness.awareness_state="HUNTING"
				awareness.suspicion=1000
				awareness.last_known_target_position=origin
				state.enemy_awareness_rows[enemy.id]=awareness
				spawned+=1
				if spawned==count:return world.world_state_error().is_empty()
	return false
