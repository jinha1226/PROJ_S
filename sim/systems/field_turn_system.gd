extends RefCounted

## Input owns the whole transaction. No render clock, contact, deployment,
## reservations, regroup or automatic protagonist action exists in this loop.
const Rules=preload("res://sim/field_turn_rules.gd")
const Action=preload("res://sim/party_action_command.gd")
const Result=preload("res://sim/sim_step_result.gd")
const Skills=preload("res://sim/abilities/party_active_skill_service.gd")
const Board=preload("res://sim/party_squad_blackboard.gd")
const Emotion=preload("res://sim/systems/party_emotion_system.gd")
const Memory=preload("res://sim/systems/party_memory_system.gd")
const Relationships=preload("res://sim/systems/party_relationship_system.gd")
const Morale=preload("res://sim/systems/party_morale_system.gd")
const Darkness=preload("res://sim/darkness_stress_rules.gd")

static func assess(sim,action)->Dictionary:
	var rejected:={"accepted":false,"reason":"field_action_unavailable","time_cost":0}
	if action==null or not Rules.active(sim.world) or not sim.world.is_settled():return rejected
	var world=sim.world
	if action.actor_id!=world.party_control_actor_id():return rejected
	if world.party_encounter.member(action.actor_id).busy_until>world.world_time:
		rejected.reason="field_actor_busy";return rejected
	if action.type in ["MELEE","SKILL"] and action.target_id in world.party_encounter.enemy_ids \
			and not Rules.visible(world,action.target_id):
		rejected.reason="field_target_unseen";return rejected
	if action.type=="SKILL":return Skills.assess(world,action.actor_id,action.skill_id,action.target_id,false,false,action.destination)
	var error:String=sim.party_coordinator._action_error(action)
	if not error.is_empty():rejected.reason=error;return rejected
	return {"accepted":true,"reason":"ok","time_cost":int(sim.party_coordinator._action_row(
		action,"DIRECT",0).time_cost)}

static func step(sim,action,wait_duration:int=100):
	var assessed:=assess(sim,action)
	if not assessed.accepted:return Result.new(false,false,str(assessed.reason))
	var world=sim.world;var party=world.party_encounter
	var cost:int=assessed.get("action_time",assessed.get("time_cost",100))
	if action.type=="HOLD":cost=wait_duration
	if cost<1 or cost>10000:return Result.new(false,false,"invalid_field_duration")
	if world.world_time>sim.MAX_WORLD_TIME-cost or world.step_index>=sim.MAX_INT64:
		return Result.new(false,false,"time_overflow")
	var rollback:Dictionary=world.rollback_memento(false)
	var start:int=world.world_time;var event_start:int=world.events.size()
	var step_index:int=world.step_index+1;var end:int=start+cost
	world.begin_step(step_index)
	var darkness_sample:=Darkness.begin_sample(world)
	var action_facing:=facing_for_action(world,action,party.facing)
	if action_facing!=party.facing:party.facing=action_facing
	var ok:=_commit_ally(sim,action,step_index,cost)
	if ok:
		party.group_anchor=world.entities[world.party_control_actor_id()].position
		# An actual attack wakes its target immediately; sight alone is handled
		# by the existing perception/suspicion system on the ordinary actor tick.
		if action.type in ["MELEE","SKILL"] and action.target_id in party.enemy_ids:
			var awareness=party.enemy_awareness(action.target_id)
			awareness.suspicion=1000
			ok=sim.party_coordinator._set_awareness_state(awareness,"HUNTING",
				world.entities[action.actor_id].position,str(awareness.awareness_state),action.actor_id)
	if ok:ok=_social(sim,event_start,false)
	Darkness.checkpoint(world,darkness_sample)
	var iterations:=0
	while ok:
		var next:=_next(sim,end)
		if next.is_empty():break
		iterations+=1
		if iterations>10000:ok=false;break
		world.world_time=int(next.at)
		var leaf_start:int=world.events.size()
		if int(next.id)==0:
			var entry:Dictionary=world.take_next_schedule()
			ok=sim._dispatch_schedule(entry,step_index,true,true)
			world.requeue_repeating(entry)
		elif party.member(int(next.id))!=null:
			var id:=int(next.id)
			var board:Dictionary=Board.build(world,action)
			var suggestion=sim.party_coordinator._suggest(id,action,board)
			if not sim.party_coordinator._action_error(suggestion).is_empty():suggestion=Action.hold(id)
			ok=_commit_ally(sim,suggestion,step_index)
		else:
			ok=_commit_enemy(sim,int(next.id),step_index)
		if ok:ok=sim.party_coordinator.reconcile_liveness()
		if ok:ok=_social(sim,leaf_start,int(next.id)==0)
		Darkness.checkpoint(world,darkness_sample)
	world.world_time=end
	party.group_anchor=world.entities[world.party_control_actor_id()].position
	var darkness_start:int=world.events.size()
	if ok:ok=Darkness.commit_boundary(world,start,end,darkness_sample)
	if ok:ok=Morale.commit_batch(world,Darkness.morale_sources(world,event_start,darkness_start),false)
	if ok:ok=sim.party_coordinator.reconcile_liveness()
	if ok:
		sim._reconcile_expedition_cycle()
		world.finish_step()
		ok=world.runtime_step_postcondition_error(event_start).is_empty()
	if not ok:
		sim.restore_rollback_memento(rollback)
		return Result.new(false,false,"field_turn_failed")
	return Result.new(true,true,"ok",world.events_since(event_start),{
		"processed_step_index":step_index,"start_time":start,"end_time":end,
		"time_cost":cost,"actor_id":action.actor_id})

static func facing_for_action(world,action,fallback:Vector2i)->Vector2i:
	var delta:=Vector2i.ZERO
	if action.type=="MOVE":
		delta=action.destination-world.entities[action.actor_id].position
	elif action.type in ["MELEE","SKILL"] and world.entities.has(action.target_id):
		delta=world.entities[action.target_id].position-world.entities[action.actor_id].position
	elif action.type=="SKILL" and action.destination!=Vector2i(-1,-1):
		delta=action.destination-world.entities[action.actor_id].position
	if delta==Vector2i.ZERO:return fallback
	return Vector2i(signi(delta.x),signi(delta.y))

static func _social(sim,event_start:int,decay:bool)->bool:
	var world=sim.world
	return Emotion.commit_batch(world,world.events_since(event_start),decay) \
		and Memory.commit_batch(world,world.events_since(event_start)) \
		and Relationships.commit_batch(world,world.events_since(event_start)) \
		and Morale.commit_batch(world,world.events_since(event_start),decay)

static func _next(sim,end:int)->Dictionary:
	var world=sim.world;var party=world.party_encounter
	var best:Dictionary={}
	if not world.scheduled_entries.is_empty() and int(world.scheduled_entries[0].due_time)<=end:
		best={"at":int(world.scheduled_entries[0].due_time),"id":0}
	if party.safe_phase=="PARTY_DEFEATED":return best
	for id in party.active_party_member_ids:
		if id==world.party_control_actor_id() or party.member(id).presence!="DEPLOYED" \
			or not world.can_act(id,world.world_time):continue
		best=_earlier(best,maxi(world.world_time,party.member(id).busy_until),id,end)
	for id in sim.party_coordinator._stream_enemy_ids():
		if not world.can_act(id,world.world_time):continue
		best=_earlier(best,maxi(world.world_time,int(party.enemy_busy_rows[id])),id,end)
	return best

static func _earlier(best:Dictionary,at:int,id:int,end:int)->Dictionary:
	# The player's next input wins actor ties at the end of this action. Cadence
	# at that boundary is still settled, as in the core simulator's time contract.
	if at>=end:return best
	if best.is_empty() or at<int(best.at) or at==int(best.at) and id<int(best.id):
		return {"at":at,"id":id}
	return best

static func _commit_ally(sim,action,step_index:int,cost_override:int=0)->bool:
	var world=sim.world;var coordinator=sim.party_coordinator
	if action.type=="SKILL":
		var skill:Dictionary=Skills.assess(world,action.actor_id,action.skill_id,action.target_id,false,true,action.destination)
		return bool(skill.get("accepted",false)) and sim._commit_skill_effect(
			action.actor_id,action.skill_id,action.target_id,skill,step_index)!=null
	var row:Dictionary=coordinator._action_row(action,"DIRECT" if action.actor_id==world.party_control_actor_id()
		else "SUGGESTED",world.party_encounter.member(action.actor_id).roster_slot)
	if cost_override>0:row.time_cost=cost_override
	if action.type=="MELEE":
		var weapon_id:String=preload("res://sim/world_item_operations.gd").equipped_weapon_id(world,action.actor_id) \
			if coordinator._uses_weapon_combat(action.actor_id) else ""
		row.combat_assessment=sim.melee.assess_attack(action.actor_id,action.target_id,str(row.source),step_index,
			world.world_time,"FIELD_ACTOR/%d/%d/%d"%[step_index,action.actor_id,world.world_time],0,weapon_id,
			coordinator._weapon_occupants(action.actor_id,action.target_id) if not weapon_id.is_empty() else {})
		if row.combat_assessment.is_empty():return false
	return sim._commit_active_ready_allies([row],step_index,world.world_time)

static func _commit_enemy(sim,id:int,step_index:int)->bool:
	var world=sim.world;var party=world.party_encounter;var coordinator=sim.party_coordinator
	var awareness=party.enemy_awareness(id)
	if awareness!=null and awareness.awareness_state in ["ALERT","HUNTING"]:
		var ok:bool=coordinator._enemy_batch(step_index,step_index,world.world_time,{id:true},false)
		if int(party.enemy_busy_rows[id])<=world.world_time:
			party.enemy_busy_rows[id]=world.world_time+100
		return ok
	var forecast:Dictionary=coordinator.forecast_exploration_patrol(id,step_index,step_index,world.world_time)
	if not bool(forecast.get("accepted",false)):return false
	var cost:int=forecast.time_cost
	var event=null
	if str(forecast.action_type)=="MOVE":
		var destination:=Vector2i(int(forecast.destination[0]),int(forecast.destination[1]))
		event=sim.movement.commit_preflighted_move(id,destination,str(forecast.terrain_id),cost)
	else:event=coordinator._commit_hold(id,cost)
	party.enemy_busy_rows[id]=world.world_time+cost
	return event!=null
