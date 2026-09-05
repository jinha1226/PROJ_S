extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Request = preload("res://sim/party_turn_request.gd")
const Blackboard = preload("res://sim/party_squad_blackboard.gd")
const Model = preload("res://sim/party_memory_model.gd")
const EmotionModel = preload("res://sim/party_emotion_model.gd")
const State = preload("res://sim/party_memory_state.gd")
const PartyState = preload("res://sim/party_encounter_state.gd")
const WorldState = preload("res://sim/world_state.gd")


func test_memory_wire_is_bounded_canonical_and_keeps_stronger_events() -> bool:
	var state = State.new()
	for index in range(10):
		check(state.remember("SELF_HARM", index + 1, index * 100,
			100 + index, 100 + index, 100 + index * 50),
			"stronger event %d enters the bounded ledger" % index)
	var wire: Dictionary = state.to_dict()
	check_eq(State.wire_error(wire), "", "bounded memory wire validates")
	check_eq(wire.records.size(), State.MAX_RECORDS, "only eight memories remain")
	check_eq(wire.records[0].source_event_id, "3",
		"the two weakest memories are evicted first")
	check_eq(State.from_dict(wire).to_dict(), wire, "memory state restores exactly")
	var weak_inserted := state.remember("SELF_HARM", 20, 2000, 120, 120, 10)
	check(not weak_inserted and state.to_dict() == wire,
		"a trivial new event cannot evict a stronger old memory")
	var malformed := wire.duplicate(true)
	malformed.records[0].salience = 1001
	check_eq(State.wire_error(malformed), "invalid_party_memory_record",
		"invalid salience cannot enter a save")
	return finish()


func test_personality_changes_memory_salience_without_mutating_world() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var observer_id := int(state.active_party_member_ids[1])
	var enemy_id := int(state.enemy_ids[0])
	var member = state.member(observer_id)
	var before: Dictionary = member.memory_state.to_dict()
	_set_facet(member.personality_profile, "E", 1000)
	_set_facet(member.personality_profile, "C", 0)
	var sensitive: Dictionary = Model.evaluate(world, [{"id":9001,
		"type":"combat.physical_damage", "actor_id":-1,
		"target_id":observer_id, "instigator_id":enemy_id, "magnitude":20}])
	_set_facet(member.personality_profile, "E", 0)
	_set_facet(member.personality_profile, "C", 1000)
	var steady: Dictionary = Model.evaluate(world, [{"id":9001,
		"type":"combat.physical_damage", "actor_id":-1,
		"target_id":observer_id, "instigator_id":enemy_id, "magnitude":20}])
	check(_salience(_row(sensitive, observer_id).state_after) \
		> _salience(_row(steady, observer_id).state_after),
		"high E and low C retain the same harm more strongly")
	check_eq(member.memory_state.to_dict(), before,
		"pure memory appraisal never commits its projection")
	return finish()


func test_persistent_harm_memory_changes_score_and_target_after_anger_is_gone() -> bool:
	var session = _engaged()
	var sim = session.sim
	var state = sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	var companion_id := int(state.active_party_member_ids[1])
	var remembered_enemy := int(state.enemy_ids[-1])
	var request = Request.new(Action.hold(hero_id), [])
	var calm: Dictionary = sim.party_coordinator.explain_companion_turn(request)
	var calm_score := _candidate_score(calm, companion_id, "ENGAGE")
	var member = state.member(companion_id)
	member.emotion_state.set_channel("ANGER", 0)
	check(member.memory_state.remember("SELF_HARM", 1, 0, remembered_enemy,
		remembered_enemy, 900), "strong factual harm memory is installed")
	var remembered: Dictionary = sim.party_coordinator.explain_companion_turn(request)
	check(_candidate_score(remembered, companion_id, "ENGAGE") >= calm_score + 150,
		"remembered harm materially raises engagement utility")
	var board: Dictionary = Blackboard.build(sim.world, Action.hold(hero_id))
	var leaf: Dictionary = sim.party_coordinator._engage_leaf(companion_id, board)
	check_eq(int(leaf.target_id), remembered_enemy,
		"long-term memory can select the remembered aggressor without current anger")
	return finish()


func test_past_harm_changes_the_next_emotional_appraisal() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var observer_id := int(state.active_party_member_ids[1])
	var enemy_id := int(state.enemy_ids[0])
	var event := {"id":9001, "type":"combat.physical_damage", "actor_id":-1,
		"target_id":observer_id, "instigator_id":enemy_id, "magnitude":10}
	var first: Dictionary = EmotionModel.evaluate(world, [event])
	check(state.member(observer_id).memory_state.remember("SELF_HARM", 1, 0,
		enemy_id, enemy_id, 900), "past harm memory is installed")
	var repeated: Dictionary = EmotionModel.evaluate(world, [event])
	check(_emotion_intensity(_row(repeated, observer_id).state_after, "ANGER") \
		> _emotion_intensity(_row(first, observer_id).state_after, "ANGER"),
		"the same aggressor evokes more anger when a salient memory already exists")
	check(_emotion_intensity(_row(repeated, observer_id).state_after, "FEAR") \
		> _emotion_intensity(_row(first, observer_id).state_after, "FEAR"),
		"past harm also raises the repeated threat appraisal")
	return finish()


func test_committed_memory_event_saves_replays_and_has_player_facing_text() -> bool:
	var session = _engaged()
	var state = session.sim.world.party_encounter
	var companion_id := int(state.active_party_member_ids[1])
	check(session.begin_turn(Action.hold(state.protagonist_id)).accepted,
		"memory fixture begins a turn")
	check(session.override_companion(companion_id, Action.hold(companion_id)).accepted,
		"memory fixture records an unwanted order")
	var event_start: int = session.sim.world.events.size()
	var committed: Dictionary = session.commit_turn()
	check(committed.accepted, "memory-producing turn commits")
	var changes: Array = session.sim.world.events_since(event_start).filter(func(event):
		return event.type == "party.memory_changed" and event.actor_id == companion_id)
	check_eq(changes.size(), 1, "one batch emits one memory transition per member")
	if changes.size() == 1:
		check_eq(changes[0].data.state_after.records[-1].kind, "COMMAND_CONFLICT",
			"the unwanted order is retained as a factual memory")
		check_eq(state.member(companion_id).memory_state.to_dict(),
			changes[0].data.state_after, "event and member memory authority agree")
	var observation: Dictionary = session.party_memory_observation()
	var observer_row := _observation_row(observation, companion_id)
	check_eq(str(observer_row.get("summary_label", "")), "원치 않는 지시",
		"the UI explains the strongest memory in player-facing language")
	check_eq(session.sim.world.world_state_error(), "",
		"memory history passes the full causal validator")
	var restored = Session.new(9, 9)
	var loaded: Dictionary = restored.load_session_json(session.save_session_json())
	check(loaded.accepted, "memory save replay is accepted: %s" \
		% str(loaded.get("reason")))
	if loaded.accepted:
		check_eq(restored.sim.snapshot(), session.sim.snapshot(),
			"memory state and source event replay exactly")
	var tampered: Dictionary = session.sim.snapshot().duplicate(true)
	for event_row in tampered.events:
		if str(event_row.type) == "party.memory_changed" \
				and str(event_row.actor_id) == str(companion_id):
			event_row.data.state_after.records[-1].subject_id = \
				str(state.enemy_ids[0])
			break
	check_eq(WorldState.snapshot_restore_error(tampered),
		"party_memory_record_invalid",
		"a memory whose subject no longer matches its source event is rejected")
	return finish()


func test_schema_twenty_save_migrates_to_empty_memory() -> bool:
	var source = Session.new()
	var encoded: Dictionary = JSON.parse_string(source.save_session_json())
	encoded.snapshot.party_encounter.schema_version = \
		PartyState.EMOTION_STATE_SCHEMA_VERSION
	for member_row in encoded.snapshot.party_encounter.member_rows:
		member_row.erase("memory_state")
	var restored = Session.new(1, 2)
	var loaded: Dictionary = restored.load_session_json(JSON.stringify(encoded))
	check(loaded.accepted, "v20 save gains an empty memory ledger: %s" \
		% str(loaded.get("reason")))
	if loaded.accepted:
		for member_id in restored.sim.world.party_encounter.party_member_ids:
			check(restored.sim.world.party_encounter.member(member_id).memory_state \
				.records.is_empty(), "migration invents no past events")
		check_eq(restored.sim.world.party_encounter.schema_version,
			PartyState.SCHEMA_VERSION, "migrated save writes current schema")
	return finish()


func _engaged():
	var session = Session.new()
	var state = session.sim.world.party_encounter
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
		"memory fixture reaches contact")
	session.preview_deployment("WEDGE", session.available_companion_ids())
	check(session.commit_deployment().accepted, "memory fixture deploys")
	return session


func _row(projection: Dictionary, entity_id: int) -> Dictionary:
	for row in projection.member_rows:
		if int(row.entity_id) == entity_id:
			return row
	return {}


func _salience(memory_wire: Dictionary) -> int:
	return int(memory_wire.records[0].salience) if not memory_wire.records.is_empty() else 0


func _emotion_intensity(emotion_wire: Dictionary, emotion_id: String) -> int:
	for channel in emotion_wire.channels:
		if str(channel.emotion_id) == emotion_id:
			return int(channel.intensity)
	return 0


func _candidate_score(explanation: Dictionary, actor_id: int, action_id: String) -> int:
	for companion in explanation.get("companions", []):
		if int(companion.actor_id) != actor_id:
			continue
		for candidate in companion.candidates:
			if str(candidate.action_id) == action_id:
				return int(candidate.score)
	return -1000000


func _observation_row(observation: Dictionary, entity_id: int) -> Dictionary:
	for row in observation.get("members", []):
		if int(row.entity_id) == entity_id:
			return row
	return {}


func _set_facet(profile, facet_id: String, value: int) -> void:
	profile.values[facet_id] = value
