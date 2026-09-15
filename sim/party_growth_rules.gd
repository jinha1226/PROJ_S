extends RefCounted
const Growth=preload("res://sim/growth_build_state.gd")

static func for_actor(w,id:int):
	if w.party_encounter==null:return null
	if id==w.party_encounter.protagonist_id:return w.party_encounter.protagonist_growth
	var member=w.party_encounter.member(id)
	if member==null:return null
	var species:String=str(w.entities[id].species_id)
	# Old fixtures/non-playable NPC species have no player growth tree. Their
	# actual species combat stats stay on Entity; this object supplies XP/mastery.
	var result=Growth.new(species if Growth.RegistryScript.has_species(species) else "human")
	result.xp_total=member.growth_xp;result.mastery_ranks=member.mastery_ranks.duplicate()
	return result

static func award_companions(w,death)->bool:
	for id in w.party_encounter.active_party_member_ids:
		if id==w.party_encounter.protagonist_id or not w.occupies_tile(id):continue
		if not award_actor(w,id,death):return false
	return true

static func award_actor(w,id:int,death)->bool:
	var member=w.party_encounter.member(id)
	if member==null or not w.occupies_tile(id):return true
	for index in range(w.events.size()-1,-1,-1):
		var prior=w.events[index]
		if prior.id<death.id:break
		if prior.type=="npc.growth_reward" and prior.actor_id==id and prior.cause_id==death.id:return true
	var award:int=preload("res://sim/progression_registry.gd").ENEMY_KILL_CHARACTER_XP
	var result:Dictionary=for_actor(w,id).commit_award_xp(award)
	if not result.get("accepted",false):return false
	member.growth_xp=result.state.xp_total
	return w.emit_event("npc.growth_reward",id,death.target_id,death.position,award,death.id,{"schema_version":1})!=null

static func validation_error(w)->String:
	var ledgers:Dictionary={};var rewards:Dictionary={}
	for id in w.party_encounter.member_rows:
		if id==w.party_encounter.protagonist_id:continue
		var growth=for_actor(w,id)
		if not growth.validation_error().is_empty():return "npc_growth_invalid"
		ledgers[id]={"MELEE":0,"RANGED":0,"MAGIC":0,"DEFENSE":0}
	for event in w.events:
		if event.type=="npc.mastery_spent":
			var axis:String=str(event.data.get("target_id",""))
			if not ledgers.has(event.actor_id) or axis not in ledgers[event.actor_id] or event.actor_id!=event.target_id or event.magnitude!=1:return "npc_mastery_event_invalid"
			ledgers[event.actor_id][axis]+=1
		elif event.type=="npc.growth_reward":
			var source=w.event_by_id(event.cause_id);var key:String="%d/%d"%[event.actor_id,event.cause_id]
			if not ledgers.has(event.actor_id) or source==null or source.type!="entity.died" or source.target_id!=event.target_id or rewards.has(key) or event.magnitude!=preload("res://sim/progression_registry.gd").ENEMY_KILL_CHARACTER_XP:return "npc_growth_reward_invalid"
			rewards[key]=true
	for id in ledgers:
		if ledgers[id]!=w.party_encounter.member(id).mastery_ranks:return "npc_mastery_ledger_mismatch"
	return ""
