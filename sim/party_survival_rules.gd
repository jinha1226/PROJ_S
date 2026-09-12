extends RefCounted

const TAG:="party_survival_v1"
const BOOTSTRAP_TAG:="party_survival_bootstrap_v1"

static func enabled(world)->bool:
	return world.party_encounter!=null and TAG in world.entities[world.party_encounter.protagonist_id].tags

static func control_id(world,event_id:int=-1)->int:
	var party=world.party_encounter
	if party==null:return -1
	if preload("res://sim/field_turn_rules.gd").enabled(world):
		var current=preload("res://sim/runtime_history_index.gd").sync(world).latest.get("party.field_control_selected") if event_id<0 else null
		if current!=null and int(current.target_id) in party.active_party_member_ids \
				and _active_at(world,int(current.target_id),-1):return int(current.target_id)
		# Historical validation still reconstructs the requested boundary; normal
		# visibility/item/path queries need only the latest control selection.
		for index in range(world.events.size()-1,-1,-1) if event_id>=0 else []:
			var event=world.events[index]
			if event_id>=0 and event.id>=event_id:continue
			if event.type!="party.field_control_selected":continue
			var selected:int=event.target_id
			var members:Array=party.active_party_member_ids if event_id<0 else world._party_active_ids_at_event(event_id)
			if selected in members and _active_at(world,selected,event_id):return selected
			break
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

static func _active_at(world,id:int,event_id:int)->bool:
	if event_id<0:return world.combatant_states.has(id) and world.combatant_states[id].life_state=="ACTIVE"
	var active:=true
	for event in world.events:
		if event.id>=event_id:break
		if event.target_id!=id:continue
		if event.type in ["entity.died","entity.downed"]:active=false
		elif event.type in ["health.restored","entity.recovered"]:active=true
	return active

static func defeated(world)->bool:
	if not enabled(world):return world.combatant_states[world.party_encounter.protagonist_id].life_state!="ACTIVE"
	for id in world.party_encounter.active_party_member_ids:
		if world.combatant_states[id].life_state=="ACTIVE":return false
	return true
