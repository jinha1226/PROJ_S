extends RefCounted

## Event-driven combat. Rendering advances a continuous cursor, but only this
## transaction changes canonical time. Existing batch APIs remain for old saves.
const Result=preload("res://sim/sim_step_result.gd")
const Action=preload("res://sim/party_action_command.gd")
const Skills=preload("res://sim/abilities/party_active_skill_service.gd")
const Blackboard=preload("res://sim/party_squad_blackboard.gd")
const EnemyBoard=preload("res://sim/enemy_squad_blackboard.gd")
const Perception=preload("res://sim/enemy_perception_registry.gd")
const Emotion=preload("res://sim/systems/party_emotion_system.gd")
const Memory=preload("res://sim/systems/party_memory_system.gd")
const Relationships=preload("res://sim/systems/party_relationship_system.gd")
const Morale=preload("res://sim/systems/party_morale_system.gd")

static func next_event(sim)->Dictionary:
	var world=sim.world;var party=world.party_encounter
	if party==null or party.safe_phase!="ENGAGED" or not world.is_settled():return {}
	var best:Dictionary={}
	if not world.scheduled_entries.is_empty():
		best={"at":int(world.scheduled_entries[0].due_time),"actor_id":0}
	for id in party.active_party_member_ids:
		var member=party.member(id)
		if member==null or member.presence!="DEPLOYED" or not world.can_act(id,world.world_time):continue
		best=_earlier(best,maxi(world.world_time,member.busy_until),id)
	for id in sim.party_coordinator._stream_enemy_ids():
		var awareness=party.enemy_awareness(id)
		if awareness==null or awareness.awareness_state not in ["ALERT","HUNTING"] \
				or not world.can_act(id,world.world_time):continue
		var nearest=EnemyBoard.nearest_deployed_party(world,world.entities[id].position)
		if nearest==null or sim.party_coordinator._distance(world.entities[id].position,
			nearest.position)>Perception.ACTIVE_COMBAT_RANGE:continue
		best=_earlier(best,maxi(world.world_time,int(party.enemy_busy_rows.get(id,0))),id)
	return best

static func _earlier(best:Dictionary,at:int,id:int)->Dictionary:
	# Environment/status work wins exact ties, then stable entity order. No RNG
	# draws or party-wide turn: later equal-time actors re-assess the new world.
	if best.is_empty() or at<int(best.at) or at==int(best.at) and id<int(best.actor_id):
		return {"at":at,"actor_id":id}
	return best

static func step(sim,reservation:Dictionary={},movement_goal:Vector2i=Vector2i(-1,-1),survival_rules:bool=true):
	var next:=next_event(sim)
	if next.is_empty():return Result.new(false,false,"individual_battle_not_engaged")
	var world=sim.world;var party=world.party_encounter
	var rollback:Dictionary=world.rollback_memento(false)
	if survival_rules and not preload("res://sim/party_survival_rules.gd").enabled(world):
		world.entities[party.protagonist_id].tags.append(preload("res://sim/party_survival_rules.gd").TAG)
	var start:int=world.world_time;var event_start:int=world.events.size()
	var step_index:int=world.step_index+1;var actor_id:int=next.actor_id
	if step_index>=sim.MAX_INT64 or int(next.at)>sim.MAX_WORLD_TIME:
		return Result.new(false,false,"time_overflow")
	world.begin_step(step_index)
	world.world_time=int(next.at)
	var skill:Dictionary={};var row:Dictionary={};var skill_rejection:=""
	if actor_id>0 and party.member(actor_id)!=null:
		if not reservation.is_empty():
			skill=Skills.assess(world,actor_id,str(reservation.skill_id),int(reservation.target_id),false,true)
			if not bool(skill.get("accepted",false)):
				skill_rejection=str(skill.get("reason","active_skill_rejected"));skill.clear()
		if skill.is_empty():row=_ally_row(sim,actor_id,step_index,movement_goal)
	var accepted:=true
	if actor_id==0:
		# Both canonical ticks may share a timestamp; settle all of them before
		# returning. Status/environment still run, enemy actions do not run here.
		while not world.scheduled_entries.is_empty() and int(world.scheduled_entries[0].due_time)<=world.world_time:
			var entry:Dictionary=world.take_next_schedule()
			accepted=sim._dispatch_schedule(entry,step_index,true,true)
			world.requeue_repeating(entry)
			if not accepted:break
	elif party.member(actor_id)!=null:
		var cost:=int(skill.get("action_time",row.get("time_cost",0)))
		accepted=cost>0 and world.world_time<=sim.MAX_WORLD_TIME-cost
		if accepted:
			accepted=sim._commit_skill_effect(actor_id,str(reservation.get("skill_id","")),
				int(reservation.get("target_id",-1)),skill,step_index)!=null if not skill.is_empty() \
				else not row.is_empty() and sim._commit_active_ready_allies([row],step_index,world.world_time)
	else:
		accepted=sim.party_coordinator._enemy_batch(step_index,step_index,world.world_time,{actor_id:true})
	if accepted:
		accepted=sim.party_coordinator.reconcile_liveness() \
			and sim.party_coordinator.finalize_automatic_regroup()
		if accepted and party.safe_phase=="ENGAGED" and sim.party_coordinator._has_alive_enemy() \
				and not sim.party_coordinator._has_active_combat_enemy():
			accepted=sim.party_coordinator._disengage_to_exploration()
	if accepted:
		accepted=Emotion.commit_batch(world,world.events_since(event_start),actor_id==0) \
			and Memory.commit_batch(world,world.events_since(event_start)) \
			and Relationships.commit_batch(world,world.events_since(event_start)) \
			and Morale.commit_batch(world,world.events_since(event_start),actor_id==0)
	if accepted:
		sim._refill_energy_after_combat_transition(event_start)
		sim._reconcile_expedition_cycle()
		world.finish_step()
		accepted=world.runtime_step_postcondition_error(event_start).is_empty()
	if not accepted:
		sim.restore_rollback_memento(rollback)
		return Result.new(false,false,"individual_battle_step_failed")
	return Result.new(true,true,"ok",world.events_since(event_start),{
		"processed_step_index":step_index,"start_time":start,"end_time":world.world_time,
		"time_cost":world.world_time-start,"actor_id":actor_id,"skill_rejection":skill_rejection})

static func _ally_row(sim,id:int,step_index:int,movement_goal:Vector2i=Vector2i(-1,-1))->Dictionary:
	var coordinator=sim.party_coordinator;var world=sim.world;var party=world.party_encounter
	var seed=Action.hold(party.protagonist_id)
	var board:Dictionary=Blackboard.build(world,seed)
	if int(board.focus_target_id)>0:board.claims[party.protagonist_id]=int(board.focus_target_id)
	var action=coordinator._suggest(id,seed,board)
	if movement_goal!=Vector2i(-1,-1):
		action=preload("res://sim/systems/battle_position_order.gd").action(sim,id,movement_goal,action)
	if not coordinator._action_error(action).is_empty():action=Action.hold(id)
	var row:Dictionary=coordinator._action_row(action,"SUGGESTED",party.member(id).roster_slot)
	if action.type=="MELEE":
		var weapon_id:String=preload("res://sim/world_item_operations.gd").equipped_weapon_id(world,id) \
			if coordinator._uses_weapon_combat(id) else ""
		row.combat_assessment=sim.melee.assess_attack(id,action.target_id,"SUGGESTED",step_index,
			world.world_time,"PARTY_TURN/%d"%step_index,0,weapon_id,
			coordinator._weapon_occupants(id,action.target_id) if not weapon_id.is_empty() else {})
		if row.combat_assessment.is_empty():return {}
	return row
