extends RefCounted

const Safety=preload("res://sim/exploration_recovery_rules.gd")
const Stats=preload("res://sim/actor_stat_rules.gd")
const START_TIME:=500
const INTERVAL:=300
const TAG:="field_party_care_v1"

static func enabled(world)->bool:
	return world!=null and world.party_encounter!=null and TAG in world.entities[world.party_encounter.protagonist_id].tags

static func stats(world,id:int)->Dictionary:
	if load("res://sim/nine_room_care_rules.gd").enabled(world):
		var rates:Dictionary=load("res://sim/nine_room_care_rules.gd").profile(world,id)
		return {"hp_recovery":float(rates.hp_milli)/1000.0,"mp_recovery":float(rates.mp_milli)/1000.0,"recovery_milli":preload("res://sim/body_penalty_rules.gd").current(world,id).recovery_milli,"interval":100,"safe_delay":0}
	var core:=Stats.for_entity(world,id)
	return {"hp_recovery":1+maxi(0,int(core.get("STR",5)))/20,
		"mp_recovery":1+maxi(0,int(core.get("INT",5)))/20,
		"recovery_milli":preload("res://sim/body_penalty_rules.gd").current(world,id).recovery_milli,
		"interval":INTERVAL,"safe_delay":START_TIME}

static func apply(session,event_start:int,elapsed:int)->Dictionary:
	var world=session.sim.world;var party=world.party_encounter
	if load("res://sim/nine_room_care_rules.gd").enabled(world):return {"accepted":true,"events":[]}
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
		needs=needs or entity.health<entity.max_health or member.energy<member.max_energy \
			or preload("res://sim/body_penalty_rules.gd").enabled(world) and preload("res://sim/body_penalty_rules.gd").needs_recovery(world.body_states.get(id))
	if damaged or not needs:
		party.safe_recovery_turns=0;return result
	var before:int=party.safe_recovery_turns
	party.safe_recovery_turns+=maxi(0,elapsed);party.revision+=1
	var pulses:=_pulses(party.safe_recovery_turns)-_pulses(before)
	if pulses<=0:return result
	for id in ids:
		var entity=world.entities[id];var member=party.member(id);var rates:=stats(world,id)
		var hp_total:int=int(rates.hp_recovery)*_pulses(party.safe_recovery_turns)*int(rates.recovery_milli)/1000
		var hp_before:int=int(rates.hp_recovery)*_pulses(before)*int(rates.recovery_milli)/1000
		var hp:=mini(int(entity.max_health)-int(entity.health),hp_total-hp_before)
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
		if preload("res://sim/body_penalty_rules.gd").enabled(world):
			var changes:Array=preload("res://sim/body_penalty_rules.gd").heal_layers(world.body_states.get(id),pulses)
			if not changes.is_empty():
				var healed=world.emit_event("body.rest_recovered",id,id,entity.position,0,-1,{"pulses":pulses,"changes":changes})
				if healed==null or not preload("res://sim/body_penalty_rules.gd").record(world,id,healed.id):return {"accepted":false,"reason":"body_recovery_event_failed"}
				result.events.append(healed)
	return result

static func _pulses(time:int)->int:
	return 0 if time<START_TIME else 1+(time-START_TIME)/INTERVAL
