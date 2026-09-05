extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Model = preload("res://sim/party_relationship_model.gd")
const System = preload("res://sim/systems/party_relationship_system.gd")
const Registry = preload("res://sim/decision_ruleset_registry.gd")
const WorldState = preload("res://sim/world_state.gd")


func test_personality_modulates_harm_and_aid_is_directional() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var companion_id := int(state.active_party_member_ids[1])
	var enemy_id := int(state.enemy_ids[0])
	var member = state.member(companion_id)
	var relation_count: int = world.personal_relations.size()
	_set_facet(member.personality_profile, "E", 1000)
	_set_facet(member.personality_profile, "A", 0)
	var reactive: Dictionary = Model.evaluate(world, [{"id":9001,
		"type":"combat.physical_damage", "actor_id":-1,
		"target_id":companion_id, "instigator_id":enemy_id, "magnitude":12}])
	_set_facet(member.personality_profile, "E", 0)
	_set_facet(member.personality_profile, "A", 1000)
	var forgiving: Dictionary = Model.evaluate(world, [{"id":9001,
		"type":"combat.physical_damage", "actor_id":-1,
		"target_id":companion_id, "instigator_id":enemy_id, "magnitude":12}])
	check(int(_reaction(reactive, companion_id, enemy_id).get("magnitude", 0)) \
		> int(_reaction(forgiving, companion_id, enemy_id).get("magnitude", 0)),
		"high emotionality and low agreeableness amplify grievance")
	var hero_id := int(state.protagonist_id)
	var aid: Dictionary = Model.evaluate(world, [{"id":9002,
		"type":"health.restored", "actor_id":hero_id,
		"target_id":companion_id, "instigator_id":hero_id, "magnitude":10}])
	var aid_row := _reaction(aid, companion_id, hero_id)
	check_eq(str(aid_row.get("reaction_kind", aid_row.get("metadata", {}).get(
		"reaction_kind", ""))), "AID_RECEIVED", "receiver appreciates helper")
	check(_reaction(aid, hero_id, companion_id).is_empty(),
		"help does not invent a reverse relationship change")
	check_eq(world.personal_relations.size(), relation_count,
		"pure appraisal does not mutate relationship authority")
	return finish()


func test_override_commits_once_saves_and_explains_the_reason() -> bool:
	var session = _engaged()
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	var companion_id := int(state.active_party_member_ids[1])
	check(session.begin_turn(Action.hold(hero_id)).accepted, "turn begins")
	check(session.override_companion(companion_id,
		Action.hold(companion_id)).accepted, "companion is overridden")
	var event_start: int = session.sim.world.events.size()
	var committed: Dictionary = session.commit_turn()
	check(committed.accepted, "overridden turn commits")
	var reaction_events: Array = session.sim.world.events_since(event_start).filter(
		func(event): return event.type == "relationship.harm_recorded" \
			and event.actor_id == companion_id and event.target_id == hero_id \
			and event.data.get("party_reaction", {}).get("reaction_kind") \
			== "COMMAND_CONFLICT")
	check_eq(reaction_events.size(), 1,
		"one forced order creates one directional grievance reaction")
	var relation = session.sim.world.personal_relations.get(
		"%d:%d" % [companion_id, hero_id])
	check(relation != null and relation.grievance > 0 \
		and relation.personal_trust_delta < 0,
		"the reaction lowers trust and stores grievance")
	if reaction_events.size() == 1:
		var before_repeat: int = session.sim.world.events.size()
		check(System.commit_batch(session.sim.world, [session.sim.world.event_by_id(
			reaction_events[0].cause_id)]), "reprocessing is an accepted no-op")
		check_eq(session.sim.world.events.size(), before_repeat,
			"the source ledger prevents duplicate reactions")
	var observation: Dictionary = session.party_relationship_observation()
	var presented := _presented_relation(observation, companion_id, hero_id)
	check_eq(str(presented.get("recent_reaction", {}).get("label", "")),
		"원치 않는 지시에 반발함", "UI presents the concrete relationship cause")
	check_eq(session.sim.world.world_state_error(), "",
		"automatic relationship history passes full validation")
	var restored = Session.new(9, 9)
	var loaded: Dictionary = restored.load_session_json(session.save_session_json())
	check(loaded.accepted, "relationship save replays: %s" % str(loaded.get("reason")))
	if loaded.accepted:
		check_eq(restored.sim.snapshot(), session.sim.snapshot(),
			"relationship state and reactions replay exactly")
	var tampered: Dictionary = session.sim.snapshot().duplicate(true)
	for event in tampered.events:
		if event.type == "relationship.harm_recorded" \
				and event.data.has("party_reaction"):
			event.data.party_reaction.ruleset_id = "forged-relationship"
			break
	check_eq(WorldState.snapshot_restore_error(tampered),
		"invalid_party_relationship_metadata",
		"forged automatic relationship metadata is rejected")
	return finish()


func test_remembered_aggressor_death_creates_avenger_gratitude() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var hero_id := int(state.protagonist_id)
	var observer_id := int(state.active_party_member_ids[1])
	var enemy_id := int(state.enemy_ids[0])
	check(state.member(observer_id).memory_state.remember("SELF_HARM", 8001,
		0, enemy_id, enemy_id, 900), "a salient aggressor is remembered")
	var projected: Dictionary = Model.evaluate(world, [{"id":9001,
		"type":"entity.died", "actor_id":-1, "target_id":enemy_id,
		"instigator_id":hero_id, "magnitude":0}])
	var reaction := _reaction(projected, observer_id, hero_id)
	check_eq(str(reaction.get("metadata", {}).get("reaction_kind", "")),
		"AVENGED_HARM", "the remembered aggressor links gratitude to the avenger")
	check_eq(int(reaction.get("metadata", {}).get("evidence_source_event_id", -1)),
		8001, "reaction retains its factual memory evidence")
	return finish()


func test_protagonist_trust_changes_companion_utility_scores() -> bool:
	var low_inputs := _neutral_inputs()
	var high_inputs := _neutral_inputs()
	low_inputs["relation.protagonist_trust"] = 0
	high_inputs["relation.protagonist_trust"] = 1000
	var engage_low: Dictionary = Registry.evaluate(
		Registry.party_action("ENGAGE"), low_inputs)
	var engage_high: Dictionary = Registry.evaluate(
		Registry.party_action("ENGAGE"), high_inputs)
	var retreat_low: Dictionary = Registry.evaluate(
		Registry.party_action("RETREAT"), low_inputs)
	var retreat_high: Dictionary = Registry.evaluate(
		Registry.party_action("RETREAT"), high_inputs)
	check_eq(int(engage_high.score) - int(engage_low.score), 80,
		"trusted leadership raises engagement utility by its declared weight")
	check_eq(int(retreat_low.score) - int(retreat_high.score), 60,
		"distrusted leadership raises retreat utility by its declared weight")
	return finish()


func _engaged():
	var session = Session.new()
	var state = session.sim.world.party_encounter
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
		"relationship fixture reaches contact")
	session.preview_deployment("WEDGE", session.available_companion_ids())
	check(session.commit_deployment().accepted, "relationship fixture deploys")
	return session


func _reaction(projection: Dictionary, observer_id: int,
		subject_id: int) -> Dictionary:
	for row_value in projection.get("reaction_rows", []):
		var row: Dictionary = row_value
		if int(row.observer_id) == observer_id and int(row.subject_id) == subject_id:
			return row
	return {}


func _presented_relation(observation: Dictionary, observer_id: int,
		subject_id: int) -> Dictionary:
	for row_value in observation.get("relations", []):
		var row: Dictionary = row_value
		if int(row.observer_id) == observer_id and int(row.subject_id) == subject_id:
			return row
	return {}


func _neutral_inputs() -> Dictionary:
	var result: Dictionary = {}
	for input_id in Registry.party_inputs():
		result[input_id] = 500
	return result


func _set_facet(profile, facet_id: String, value: int) -> void:
	profile.values[facet_id] = value
