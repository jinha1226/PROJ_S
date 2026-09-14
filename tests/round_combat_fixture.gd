extends RefCounted
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/round_combat_rules.gd")
const Field=preload("res://sim/field_turn_rules.gd")
const Plans=preload("res://sim/round_plan_service.gd")
const Members=preload("res://sim/party_member_state.gd")
const Awareness=preload("res://sim/enemy_awareness_state.gd")

static func create(shove_slot:int=-1):
	var s=Session.new(44,20260828,Session.REGRESSION_SCENARIO_ID)
	if s.sim==null:return null
	var w=s.sim.world;var party=w.party_encounter
	if shove_slot>=0:
		# Legacy SHOVE has no current monster-meat item. Seed its canonical
		# acquisition history in this regression fixture, never bypass assessment.
		var actor:int=party.party_member_ids[shove_slot]
		party.member(actor).bound_ability_ids.append("SHOVE")
		w.emit_event("party.ability_bound",actor,actor,w.entities[actor].position,1,-1,{
			"schema_version":1,"ruleset_id":"ability-binding-v1",
			"ability_id":"SHOVE","instance_id":"ROUND_LEGACY_SHOVE",
			"slot_index":0})
	w.entities[party.protagonist_id].tags.append(Field.TAG)
	w.entities[party.protagonist_id].tags.append(Rules.TAG)
	for id in party.party_member_ids:
		party.member(id).presence="DEPLOYED"
		if id not in party.active_party_member_ids:party.active_party_member_ids.append(id)
	var positions:Array=[Vector2i(5,5),Vector2i(4,5),Vector2i(4,6)]
	for i in range(party.active_party_member_ids.size()):relocate(w,party.active_party_member_ids[i],positions[i])
	var id:int=party.enemy_ids[0]
	relocate(w,id,Vector2i(6,5))
	party.enemy_awareness(id).awareness_state="HUNTING";party.enemy_awareness(id).suspicion=1000
	party.enemy_busy_rows[id]=w.world_time
	party.group_anchor=w.entities[party.protagonist_id].position
	s._round_edit_actor_id=party.protagonist_id
	Plans.begin(s.sim)
	return s

static func relocate(w,id:int,cell:Vector2i)->void:
	var before:Vector2i=w.entities[id].position
	w.entities[id].position=cell;w.reindex_entity_occupancy(id,before,cell)
