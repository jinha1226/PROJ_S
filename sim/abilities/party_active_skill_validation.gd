extends RefCounted

## Saved campaign skill leaves are checked separately from UI/assessment.
const Registry = preload("res://sim/abilities/active_skill_registry.gd")
const Int64 = preload("res://sim/int64_codec.gd")
const Commands = preload("res://sim/party_exception_command.gd")
const RULESET_ID := "party-active-skills-v1"
const TIMES := {"STRIKE":100,"SHOVE":100,"FIREBOLT":120,"MEND":120}

static func event_error(world, event) -> String:
	match str(event.type):
		"action.skill": return _action_error(world,event)
		"party.actor_command_issued": return _command_error(world,event)
		"party.energy_refilled": return _refill_error(world,event)
		"party.energy_recovered":
			var keys:Array=event.data.keys();keys.sort()
			if world.party_encounter==null or world.party_encounter.member(event.actor_id)==null \
					or event.actor_id!=event.target_id or event.magnitude<=0 or event.cause_id!=-1 \
					or keys!=["energy_after","ruleset_id","schema_version"] \
					or not event.data.get("energy_after") is int \
					or event.data.get("schema_version")!=1 or event.data.get("ruleset_id")!="party-rest-recovery-v1" \
					or int(event.data.get("energy_after",-1)) not in range(1,Registry.MAX_ENERGY+1):return "energy_recovery_event_invalid"
		"party.expedition_auto_returned":
			if event.data!={"schema_version":1,"ruleset_id":RULESET_ID} \
					or world.party_encounter==null \
					or event.actor_id!=world.party_control_actor_id(event.id) \
					or event.target_id!=-1 or event.magnitude!=0 or event.cause_id!=-1:
				return "active_skill_auto_return_event_invalid"
		"health.restored":
			if event.data.get("kind")=="ACTIVE_SKILL": return healing_error(world,event)
		"action.move":
			var cause=world.event_by_id(event.cause_id)
			if cause!=null and cause.type=="action.skill":return forced_move_error(world,event)
	return ""

static func forced_move_error(world,event)->String:
	var source=world.event_by_id(event.cause_id)
	if source==null or source.type!="action.skill" or source.data.get("skill_id")!="SHOVE" \
			or not _action_error(world,source).is_empty() or source.target_id!=event.actor_id \
			or source.step_index!=event.step_index or source.world_time!=event.world_time \
			or source.instigator_id!=event.instigator_id or event.target_id!=-1 \
			or event.magnitude!=1 or event.data.get("move_time_cost")!=1 \
			or event.data.get("from_position")!=[source.position.x,source.position.y] \
			or event.data.get("to_position")!=source.data.destination \
			or event.position!=Vector2i(source.data.destination[0],source.data.destination[1]):
		return "active_skill_forced_move_invalid"
	return ""

static func _action_error(world,event)->String:
	var data:Dictionary=event.data
	var keys:Array=data.keys();keys.sort()
	if keys!=["action_time","cost","damage","destination","healing",
			"ruleset_id","schema_version","skill_id"] \
			or data.get("schema_version")!=1 or data.get("ruleset_id")!=RULESET_ID \
			or data.get("skill_id") not in TIMES or event.cause_id!=-1 \
			or not world.entities.has(event.actor_id) or not world.entities.has(event.target_id) \
			or world.party_encounter==null \
			or not world.party_encounter.member_rows.has(event.actor_id):
		return "active_skill_event_invalid"
	var definition:Dictionary=Registry.definition(str(data.skill_id))
	for key in ["action_time","cost","damage","healing"]:
		if not data.get(key) is int or int(data[key])<0:return "active_skill_event_invalid"
	if int(data.cost)!=int(definition.cost) or int(data.action_time)!=preload("res://sim/field_action_timing.gd").duration(
			world,event.actor_id,str(data.skill_id),int(TIMES[data.skill_id])) \
			or not data.destination is Array or data.destination.size()!=2 \
			or not data.destination[0] is int or not data.destination[1] is int \
			or event.magnitude!=maxi(int(data.damage),int(data.healing)) or event.magnitude<=0:
		return "active_skill_event_invalid"
	var landing:=Vector2i(data.destination[0],data.destination[1])
	if not Rect2i(Vector2i.ZERO,Vector2i(world.width,world.height)).has_point(landing):
		return "active_skill_destination_invalid"
	if data.skill_id=="MEND":
		if int(data.damage)!=0 or int(data.healing)<=0:return "active_skill_effect_invalid"
	elif int(data.damage)<=0 or int(data.healing)!=0:return "active_skill_effect_invalid"
	if data.skill_id!="SHOVE" and landing!=event.position:return "active_skill_destination_invalid"
	if data.skill_id=="SHOVE" and maxi(absi(landing.x-event.position.x),
			absi(landing.y-event.position.y))!=1:return "active_skill_destination_invalid"
	return ""

static func _command_error(world,event)->String:
	if not Commands.actor_data_error(event.data).is_empty() \
			or event.actor_id<=0 or str(event.actor_id)!=str(event.data.get("actor_id","")) \
			or str(event.target_id)!=str(event.data.get("target_id","")) \
			or event.magnitude!=0 or event.cause_id!=-1 or world.party_encounter==null \
			or not world.party_encounter.member_rows.has(event.actor_id):
		return "actor_command_event_invalid"
	return ""

static func _refill_error(world,event)->String:
	var keys:Array=event.data.keys();keys.sort()
	var cause=world.event_by_id(event.cause_id)
	if keys!=["member_ids","reason","ruleset_id","schema_version"] \
			or event.data.get("schema_version")!=1 or event.data.get("ruleset_id")!=RULESET_ID \
			or event.data.get("reason") not in ["COMBAT_COMPLETE","TOWN_RETURN"] \
			or not event.data.get("member_ids") is Array or event.data.member_ids.is_empty() \
			or event.magnitude!=event.data.member_ids.size() or cause==null \
			or world.party_encounter==null or event.actor_id!=world.party_control_actor_id(event.id) \
			or event.target_id!=-1 or cause.step_index!=event.step_index \
			or cause.world_time!=event.world_time:
		return "energy_refill_event_invalid"
	if event.data.reason=="COMBAT_COMPLETE" and cause.type not in ["party.victory","party.regroup_completed"]:
		return "energy_refill_event_invalid"
	if event.data.reason=="TOWN_RETURN" and cause.type not in [
			"dungeon.expedition_returned","party.expedition_auto_returned"]:
		return "energy_refill_event_invalid"
	var seen:Dictionary={}
	for wire in event.data.member_ids:
		if not Int64.is_canonical(wire):return "energy_refill_event_invalid"
		var member_id:int=Int64.parse(wire,"energy refill member")
		if seen.has(member_id) or not world.party_encounter.member_rows.has(member_id):
			return "energy_refill_event_invalid"
		seen[member_id]=true
	return ""

static func healing_error(world,event)->String:
	var keys:Array=event.data.keys();keys.sort()
	var source=world.event_by_id(event.cause_id)
	if keys!=["health_after","kind","ruleset_id","schema_version"] \
			or event.data.get("schema_version")!=1 or event.data.get("ruleset_id")!=RULESET_ID \
			or not event.data.get("health_after") is int or event.actor_id!=event.target_id \
			or source==null or source.type!="action.skill" or source.data.get("skill_id")!="MEND" \
			or source.target_id!=event.target_id or source.position!=event.position \
			or source.step_index!=event.step_index or source.world_time!=event.world_time \
			or source.instigator_id!=event.instigator_id or event.magnitude<=0 \
			or int(source.data.get("healing",0))!=event.magnitude \
			or not world.entities.has(event.target_id):
		return "party_active_skill_restoration_cause_invalid"
	if int(event.data.health_after)<event.magnitude \
			or int(event.data.health_after)>int(world.entities[event.target_id].max_health):
		return "party_active_skill_restoration_amount_invalid"
	return ""

static func healing_history_error(world)->String:
	# Only actors actually healed by this feature need the additional ledger.
	var ledgers:Dictionary={}
	for event in world.events:
		if event.type=="health.restored" and event.data.get("kind")=="ACTIVE_SKILL":
			if not world.entities.has(event.target_id):return "active_heal_actor_missing"
			ledgers[event.target_id]={"hp":int(world.entities[event.target_id].max_health),
				"credit":0,"remainder":0}
	if ledgers.is_empty():return ""
	for event in world.events:
		if not ledgers.has(event.target_id):continue
		var row:Dictionary=ledgers[event.target_id]
		var maximum:int=world.entities[event.target_id].max_health
		if event.type=="opening.npc_discovered":row.hp=maxi(1,(maximum+4)/5)
		elif event.type in ["combat.physical_damage","combat.fire_damage","combat.electric_damage"]:
			var applied:int=int(event.data.get("applied_health_damage",event.magnitude))
			row.hp=maxi(0,int(row.hp)-applied)
			var numerator:int=int(row.remainder)+applied
			row.credit=int(row.credit)+numerator/2;row.remainder=numerator%2
		elif event.type=="combat.starvation_damage":row.hp=maxi(0,int(row.hp)-event.magnitude)
		elif event.type in ["entity.downed","entity.died"]:row.hp=0
		elif event.type=="entity.recovered":
			row.hp=int(event.data.get("recovered_health",0));row.credit=0;row.remainder=0
		elif event.type in ["health.restored","opening.health_restored"]:
			if event.data.get("kind")=="ACTIVE_SKILL":
				var error:=healing_error(world,event)
				if not error.is_empty():return error
				if event.magnitude>int(row.credit) or int(row.hp)<=0 \
						or event.magnitude>maximum-int(row.hp):return "active_heal_credit_exceeded"
			row.hp=mini(maximum,int(row.hp)+event.magnitude)
			row.credit=maxi(0,int(row.credit)-event.magnitude)
			if int(event.data.get("health_after",-1))!=int(row.hp):
				return "active_heal_health_projection_mismatch"
		elif event.type=="town.body_restored":row.credit=0;row.remainder=0
	for entity_id in ledgers:
		if int(ledgers[entity_id].hp)!=int(world.entities[entity_id].health):
			return "active_heal_health_projection_mismatch"
	return ""

static func energy_history_error(world)->String:
	if world.party_encounter==null:return ""
	var projected:Dictionary={}
	for member_id in world.party_encounter.member_rows:
		projected[member_id]=int(Registry.MAX_ENERGY)
	for event in world.events:
		if event.type=="action.skill":
			if not projected.has(event.actor_id):return "active_skill_actor_missing"
			projected[event.actor_id]-=int(event.data.get("cost",0))
			if int(projected[event.actor_id])<0:return "active_skill_energy_overdrawn"
		elif event.type=="party.energy_refilled":
			for wire in event.data.get("member_ids",[]):
				var member_id:int=Int64.parse(wire,"refilled member")
				if not projected.has(member_id):return "active_skill_actor_missing"
				projected[member_id]=int(Registry.MAX_ENERGY)
		elif event.type=="party.energy_recovered":
			if not projected.has(event.actor_id):return "active_skill_actor_missing"
			projected[event.actor_id]+=event.magnitude
			if int(projected[event.actor_id])>Registry.MAX_ENERGY \
					or int(projected[event.actor_id])!=int(event.data.get("energy_after",-1)):return "energy_recovery_projection_mismatch"
	for member_id in projected:
		if int(world.party_encounter.member_rows[member_id].energy)!=int(projected[member_id]):
			return "active_skill_energy_projection_mismatch"
	return ""
