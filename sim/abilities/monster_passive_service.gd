extends RefCounted

## React only to this action's original hits, never to derived damage.
const POWER:=6
const Affinities=preload("res://sim/species_hazard_affinity_registry.gd")

static func resisted(power:int,species:String)->int:
	var resistance:int=clampi(int(Affinities.affinity_for(species).fire_tolerance),-25,75)
	return maxi(1,roundi(power*(1.0-resistance/100.0)))

static func commit(sim,event_start:int)->bool:
	var world=sim.world
	if world.party_encounter==null:return true
	var original_end:int=world.events.size()
	for index in range(event_start,original_end):
		var hit=world.events[index]
		if hit.type!="combat.physical_damage" or hit.magnitude<=0:continue
		var attack=world.event_by_id(hit.cause_id)
		if attack==null or attack.type!="action.melee_attack":continue
		var member=world.party_encounter.member(attack.actor_id)
		if member==null or "FIREBOLT" not in member.bound_ability_ids:continue
		var target=world.entities.get(hit.target_id)
		if target==null or world.combatant_states[target.id].life_state!="ACTIVE":continue
		var power:=POWER
		if member.entity_id==world.party_encounter.protagonist_id and world.party_encounter.protagonist_growth!=null:
			power=world.party_encounter.protagonist_growth.mastery_scale("MAGIC",power)
		power=resisted(power,str(target.species_id))
		var source=world.emit_event("ability.passive_triggered",attack.actor_id,target.id,target.position,power,hit.id,
			{"schema_version":1,"ability_id":"FIREBOLT","damage":power})
		if source==null:return false
		var final_damage:int=sim.damage._element_armor_context(target,"fire",power,source.id,target.position).get("final_damage",power)
		var terminal:bool=final_damage>=target.health and (world.lifecycle_succumbs(target.id) or target.id==world.party_encounter.protagonist_id)
		var result:Dictionary=sim.damage.apply_canonical_active_damage(target,power,"fire",source.id,target.position,world._active_step_index,target.health,terminal,false)
		if not result.get("accepted",false):return false
	return true

static func event_error(world,event,historical:bool=false)->String:
	if event.type!="ability.passive_triggered":return ""
	var keys:Array=event.data.keys();keys.sort()
	var hit=world.event_by_id(event.cause_id)
	var attack=world.event_by_id(hit.cause_id) if hit!=null else null
	if keys!=["ability_id","damage","schema_version"] or event.data.get("schema_version")!=1 \
			or event.data.get("ability_id")!="FIREBOLT" or not event.data.get("damage") is int \
			or event.magnitude!=int(event.data.damage) or event.magnitude<1 \
			or hit==null or hit.type!="combat.physical_damage" or hit.magnitude<=0 \
			or attack==null or attack.type!="action.melee_attack" or attack.actor_id!=event.actor_id \
			or hit.target_id!=event.target_id or hit.position!=event.position \
			or hit.step_index!=event.step_index or hit.world_time!=event.world_time:
		return "monster_passive_event_invalid"
	if historical:
		var bound:=false;var passive:=false;var magic_rank:=0
		for prior in world.events:
			if prior.id>=event.id:break
			if prior.actor_id==event.actor_id and prior.type=="growth.mastery_spent" and prior.data.get("target_id")=="MAGIC":magic_rank+=1
			if prior.type=="ability.passive_triggered" and prior.cause_id==event.cause_id:return "monster_passive_duplicate"
			if prior.actor_id!=event.actor_id or prior.data.get("ability_id")!="FIREBOLT":continue
			if prior.type=="party.ability_bound":bound=true
			elif prior.type=="party.ability_mode_changed":passive=prior.data.get("mode")=="PASSIVE"
		if not bound:return "monster_passive_not_equipped"
		var per_rank:int=preload("res://game/rebuilt/progression.gd").DATA.attack_per_rank_milli
		var expected:int=(POWER*(1000+magic_rank*per_rank)+500)/1000
		expected=resisted(expected,str(world.entities[event.target_id].species_id))
		if event.magnitude!=expected:return "monster_passive_power_invalid"
	return ""
