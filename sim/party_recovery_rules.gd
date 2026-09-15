extends RefCounted

const Safety=preload("res://sim/exploration_recovery_rules.gd")
const Stats=preload("res://sim/actor_stat_rules.gd")
const START_TIME:=500
const INTERVAL:=300
const TAG:="field_party_care_v1"

static func enabled(world)->bool:
	return world!=null and world.party_encounter!=null and TAG in world.entities[world.party_encounter.protagonist_id].tags

static func stats(world,id:int)->Dictionary:
	var core:=Stats.for_entity(world,id)
	return {"hp_recovery":1+maxi(0,int(core.get("STR",5)))/20,
		"mp_recovery":1+maxi(0,int(core.get("INT",5)))/20,
		"interval":INTERVAL,"safe_delay":START_TIME}

static func apply(session,event_start:int,elapsed:int)->Dictionary:
	var world=session.sim.world;var party=world.party_encounter
	var result:={"accepted":true,"events":[]}
	var damaged:=false
	for event in world.events.slice(event_start):
		if event.target_id in party.active_party_member_ids and event.magnitude>0 \
				and str(event.type).begins_with("combat.") and str(event.type).ends_with("_damage"):damaged=true
	var ids:Array=[]
	var needs:=false
	for id in party.active_party_member_ids:
		var member=party.member(id);var entity=world.entities[id]
		if member.presence!="DEPLOYED" or not world.can_act(id,world.world_time):continue
		var risk:=0
		if world.is_environment_exposed(id):
			var exposure=session.sim.evaluate_exposure_for_entity(id,entity.position)
			if exposure!=null and exposure.evaluation!=null:risk=int(exposure.evaluation.total_risk)
		if not Safety.is_safe_to_recover(world,party,entity,world.combatant_states[id],risk,true):
			party.safe_recovery_turns=0;return result
		ids.append(id)
		needs=needs or entity.health<entity.max_health or member.energy<member.max_energy
	if damaged or not needs:
		party.safe_recovery_turns=0;return result
	var before:int=party.safe_recovery_turns
	party.safe_recovery_turns+=maxi(0,elapsed);party.revision+=1
	var pulses:=_pulses(party.safe_recovery_turns)-_pulses(before)
	if pulses<=0:return result
	for id in ids:
		var entity=world.entities[id];var member=party.member(id);var rates:=stats(world,id)
		var hp:=mini(int(entity.max_health)-int(entity.health),int(rates.hp_recovery)*pulses)
		var mp:=mini(member.max_energy-member.energy,int(rates.mp_recovery)*pulses)
		if hp>0:
			entity.health+=hp
			var event=world.emit_event("health.restored",id,id,entity.position,hp,-1,
				{"schema_version":1,"ruleset_id":Safety.RULESET_ID,"kind":"AUTO",
				"safe_turn_count":party.safe_recovery_turns,"health_after":entity.health})
			if event==null:return {"accepted":false,"reason":"party_recovery_event_failed"}
			result.events.append(event)
		if mp>0:
			member.energy+=mp
			var event=world.emit_event("party.energy_recovered",id,id,entity.position,mp,-1,
				{"schema_version":1,"ruleset_id":"party-rest-recovery-v1","energy_after":member.energy})
			if event==null:return {"accepted":false,"reason":"party_recovery_event_failed"}
			result.events.append(event)
	return result

static func _pulses(time:int)->int:
	return 0 if time<START_TIME else 1+(time-START_TIME)/INTERVAL
