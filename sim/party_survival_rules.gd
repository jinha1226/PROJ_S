extends RefCounted

const TAG:="party_survival_v1"
const BOOTSTRAP_TAG:="party_survival_bootstrap_v1"

static func enabled(world)->bool:
	return world.party_encounter!=null and TAG in world.entities[world.party_encounter.protagonist_id].tags

static func control_id(world,event_id:int=-1)->int:
	var party=world.party_encounter
	if party==null:return -1
	if not enabled(world):return int(party.protagonist_id)
	var ids:Array=party.active_party_member_ids if event_id<0 else world._party_active_ids_at_event(event_id)
	for id in ids:
		if event_id<0:
			if world.combatant_states[id].life_state=="ACTIVE":return int(id)
		else:
			var active:=true
			for event in world.events:
				if event.id>=event_id:break
				if event.target_id!=id:continue
				if event.type in ["entity.died","entity.downed"]:active=false
				elif event.type in ["health.restored","entity.recovered"]:active=true
			if active:return int(id)
	return int(party.protagonist_id)

static func defeated(world)->bool:
	if not enabled(world):return world.combatant_states[world.party_encounter.protagonist_id].life_state!="ACTIVE"
	for id in world.party_encounter.active_party_member_ids:
		if world.combatant_states[id].life_state=="ACTIVE":return false
	return true
