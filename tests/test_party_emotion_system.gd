extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Request = preload("res://sim/party_turn_request.gd")
const Blackboard = preload("res://sim/party_squad_blackboard.gd")
const Model = preload("res://sim/party_emotion_model.gd")
const State = preload("res://sim/party_emotion_state.gd")
const PartyState = preload("res://sim/party_encounter_state.gd")


func test_six_channel_wire_is_exact_bounded_and_rejects_malformed_rows() -> bool:
	var state = State.new(200)
	state.set_channel("ANGER", 700, 9, 12, "ALLY_DIED")
	var wire: Dictionary = state.to_dict()
	check_eq(State.wire_error(wire), "", "six-channel emotion wire validates")
	check_eq(wire.channels.map(func(row): return str(row.emotion_id)),
		["FEAR", "ANGER", "SADNESS", "GUILT", "BOND", "RESOLVE"],
		"channel order is canonical")
	check_eq(State.from_dict(wire).to_dict(), wire, "emotion state restores exactly")
	var malformed := wire.duplicate(true)
	malformed.channels[0].intensity = 1001
	check_eq(State.wire_error(malformed), "invalid_party_emotion_channel",
		"out-of-range emotion cannot enter a save")
	return finish()


func test_personality_changes_appraisal_and_loss_keeps_targeted_memory() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var observer_id := int(state.active_party_member_ids[1])
	var deceased_id := int(state.active_party_member_ids[2])
	var enemy_id := int(state.enemy_ids[0])
	var profile = state.member(observer_id).personality_profile
	_set_facet(profile, "E", 1000); _set_facet(profile, "C", 0)
	var sensitive: Dictionary = Model.evaluate(world, [{"id":9001,
		"type":"combat.physical_damage", "actor_id":-1,
		"target_id":observer_id, "instigator_id":enemy_id, "magnitude":20}])
	_set_facet(profile, "E", 0); _set_facet(profile, "C", 1000)
	var steady: Dictionary = Model.evaluate(world, [{"id":9001,
		"type":"combat.physical_damage", "actor_id":-1,
		"target_id":observer_id, "instigator_id":enemy_id, "magnitude":20}])
	check(_intensity(_row(sensitive, observer_id).state_after, "FEAR") \
		> _intensity(_row(steady, observer_id).state_after, "FEAR"),
		"high E and low C appraises the same damage as more frightening")
	var loss: Dictionary = Model.evaluate(world, [{"id":9002,
		"type":"entity.died", "actor_id":-1, "target_id":deceased_id,
		"instigator_id":enemy_id, "magnitude":0}])
	var loss_state: Dictionary = _row(loss, observer_id).state_after
	check(_intensity(loss_state, "SADNESS") > 0 \
		and _intensity(loss_state, "GUILT") > 0 \
		and _intensity(loss_state, "ANGER") > 0,
		"an ally death produces loss, self-evaluation and aggression channels")
	check_eq(_channel(loss_state, "ANGER").target_id, str(enemy_id),
		"anger remembers the responsible enemy instead of becoming a global buff")
	if state.enemy_ids.size() >= 2:
		state.member(observer_id).emotion_state = State.from_dict(loss_state)
		var weak_followup: Dictionary = Model.evaluate(world, [{"id":9003,
			"type":"combat.physical_damage", "actor_id":-1,
			"target_id":observer_id, "instigator_id":int(state.enemy_ids[1]),
			"magnitude":1}])
		check_eq(_channel(_row(weak_followup, observer_id).state_after,
			"ANGER").target_id, str(enemy_id),
			"a minor new hit does not overwrite the stronger loss memory")
	return finish()


func test_emotions_decay_deterministically_without_mutating_the_world() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var member_id := int(world.party_encounter.active_party_member_ids[1])
	var member = world.party_encounter.member(member_id)
	member.emotion_state.updated_at = int(world.world_time)
	member.emotion_state.set_channel("FEAR", 500, int(world.party_encounter.enemy_ids[0]),
		1, "SELF_DAMAGE")
	var before: Dictionary = member.emotion_state.to_dict()
	world.world_time += 500
	var first: Dictionary = Model.evaluate(world, [])
	var second: Dictionary = Model.evaluate(world, [])
	check_eq(first, second, "decay is deterministic")
	check_eq(_intensity(_row(first, member_id).state_after, "FEAR"), 410,
		"fear decays by five fixed world-time quanta")
	check_eq(member.emotion_state.to_dict(), before,
		"pure appraisal never commits its projection")
	return finish()


func test_emotion_inputs_change_scores_and_targeted_anger_changes_target() -> bool:
	var session = _engaged()
	var sim = session.sim
	var state = sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	var companion_id := int(state.active_party_member_ids[1])
	var request = Request.new(Action.hold(hero_id), [])
	var calm: Dictionary = sim.party_coordinator.explain_companion_turn(request)
	var calm_gap := _candidate_score(calm, companion_id, "RETREAT") \
		- _candidate_score(calm, companion_id, "ENGAGE")
	var emotion_state = state.member(companion_id).emotion_state
	emotion_state.set_channel("FEAR", 1000, int(state.enemy_ids[0]), 1, "SELF_DAMAGE")
	var afraid: Dictionary = sim.party_coordinator.explain_companion_turn(request)
	var afraid_gap := _candidate_score(afraid, companion_id, "RETREAT") \
		- _candidate_score(afraid, companion_id, "ENGAGE")
	check(afraid_gap >= calm_gap + 500,
		"fear materially shifts the retreat-versus-engage boundary")
	if state.enemy_ids.size() >= 2:
		var board: Dictionary = Blackboard.build(sim.world, Action.hold(hero_id))
		var remembered_enemy := int(state.enemy_ids[-1])
		emotion_state.set_channel("ANGER", 800, remembered_enemy, 2, "ALLY_DIED")
		var leaf: Dictionary = sim.party_coordinator._engage_leaf(companion_id, board)
		check_eq(int(leaf.target_id), remembered_enemy,
			"strong anger makes the companion pursue the remembered aggressor")
	return finish()


func test_emotion_observation_uses_composite_player_facing_language() -> bool:
	var session = _engaged()
	var state = session.sim.world.party_encounter
	var companion_id := int(state.active_party_member_ids[1])
	var enemy_id := int(state.enemy_ids[0])
	var emotion = state.member(companion_id).emotion_state
	emotion.set_channel("ANGER", 800, enemy_id, 2, "ALLY_DIED")
	emotion.set_channel("SADNESS", 700, int(state.active_party_member_ids[2]),
		2, "ALLY_DIED")
	var observation: Dictionary = session.party_emotion_observation()
	var row: Dictionary = {}
	for member_row in observation.members:
		if int(member_row.entity_id) == companion_id:
			row = member_row
	check_eq(str(row.get("summary_label", "")), "복수심",
		"anger plus loss is translated into a composite state")
	check_eq(row.get("dominant_channels", []).size(), 2,
		"the UI shows only the two emotions that matter most")
	if not row.get("dominant_channels", []).is_empty():
		check(not str(row.dominant_channels[0].behavior_hint).is_empty() \
			and not str(row.dominant_channels[0].cause_label).is_empty(),
			"the emotion explains both its remembered cause and behavior effect")
	return finish()


func test_authoritative_emotion_event_saves_replays_and_matches_member_state() -> bool:
	var session = _engaged()
	var state = session.sim.world.party_encounter
	var companion_id := int(state.active_party_member_ids[1])
	check(session.begin_turn(Action.hold(state.protagonist_id)).accepted,
		"emotion replay fixture begins a turn")
	check(session.override_companion(companion_id, Action.hold(companion_id)).accepted,
		"emotion replay fixture records an unwanted order")
	var event_start: int = session.sim.world.events.size()
	var committed: Dictionary = session.commit_turn()
	check(committed.accepted, "emotion-producing turn commits")
	var changes: Array = session.sim.world.events_since(event_start).filter(func(event):
		return event.type == "party.emotion_changed" and event.actor_id == companion_id)
	check_eq(changes.size(), 1, "one batch emits one emotion transition per member")
	if changes.size() == 1:
		check(_intensity(changes[0].data.state_after, "ANGER") > 0,
			"the override creates a persisted conflict emotion")
		check_eq(state.member(companion_id).emotion_state.to_dict(),
			changes[0].data.state_after, "event projection and member authority agree")
	check_eq(session.sim.world.world_state_error(), "",
		"emotion history passes the full causal validator")
	var restored = Session.new(9, 9)
	var loaded: Dictionary = restored.load_session_json(session.save_session_json())
	check(loaded.accepted, "emotion save replay is accepted: %s" % str(loaded.get("reason")))
	if loaded.accepted:
		check_eq(restored.sim.snapshot(), session.sim.snapshot(),
			"emotion state and source memory replay snapshot-exactly")
	return finish()


func test_schema_nineteen_save_migrates_to_neutral_emotions() -> bool:
	var source = Session.new()
	var encoded: Dictionary = JSON.parse_string(source.save_session_json())
	encoded.snapshot.party_encounter.schema_version = \
		PartyState.ANCHOR_PORTAL_SCHEMA_VERSION
	for member_row in encoded.snapshot.party_encounter.member_rows:
		member_row.erase("emotion_state")
	var restored = Session.new(1, 2)
	var loaded: Dictionary = restored.load_session_json(JSON.stringify(encoded))
	check(loaded.accepted, "v19 save gains neutral emotion state: %s" \
		% str(loaded.get("reason")))
	if loaded.accepted:
		for member_id in restored.sim.world.party_encounter.party_member_ids:
			check(restored.sim.world.party_encounter.member(member_id).emotion_state \
				.dominant().is_empty(), "migration invents no emotional history")
		check_eq(restored.sim.world.party_encounter.schema_version,
			PartyState.SCHEMA_VERSION, "migrated save writes the current schema")
	return finish()


func _engaged():
	var session = Session.new()
	var state = session.sim.world.party_encounter
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
		"emotion fixture reaches contact")
	session.preview_deployment("WEDGE", session.available_companion_ids())
	check(session.commit_deployment().accepted, "emotion fixture deploys")
	return session


func _row(projection: Dictionary, entity_id: int) -> Dictionary:
	for row in projection.member_rows:
		if int(row.entity_id) == entity_id:
			return row
	return {}


func _channel(state_wire: Dictionary, emotion_id: String) -> Dictionary:
	for row in state_wire.channels:
		if str(row.emotion_id) == emotion_id:
			return row
	return {}


func _intensity(state_wire: Dictionary, emotion_id: String) -> int:
	return int(_channel(state_wire, emotion_id).get("intensity", 0))


func _candidate_score(explanation: Dictionary, actor_id: int, action_id: String) -> int:
	for companion in explanation.get("companions", []):
		if int(companion.actor_id) != actor_id:
			continue
		for candidate in companion.candidates:
			if str(candidate.action_id) == action_id:
				return int(candidate.score)
	return -1000000


func _set_facet(profile, facet_id: String, value: int) -> void:
	profile.values[facet_id] = value
