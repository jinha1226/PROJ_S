extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const Action=preload("res://sim/party_action_command.gd")
const Request=preload("res://sim/party_turn_request.gd")

func test_facade_dtos_are_detached_and_save_load_preserves_contact() -> bool:
	var session=Session.new(); var status=session.party_status(); status.safe_phase="CORRUPTED"
	var cards=session.party_cards(); cards[0].element_exposure.total_risk=999
	check_eq(session.party_status().safe_phase,"GROUPED","status detached")
	check(session.party_cards()[0].element_exposure.total_risk!=999,"nested cards detached")
	var hero=session.sim.world.party_encounter.protagonist_id; session.commit_exploration(Command.wait(hero))
	var encoded=session.save_session_json(); var restored=Session.new(1,2); var loaded=restored.load_session_json(encoded)
	check(loaded.accepted,"load accepted: %s" % str(loaded)); check_eq(restored.sim.snapshot(),session.sim.snapshot(),"save load exact")
	check_eq(restored.party_status().safe_phase,"CONTACT","contact phase preserved")
	return finish()

func test_override_clear_is_per_companion_and_logs_are_korean_narrative() -> bool:
	var session=Session.new(); var state=session.sim.world.party_encounter; var hero=state.protagonist_id
	session.commit_exploration(Command.wait(hero)); session.preview_deployment("LINE",state.party_member_ids.slice(1)); session.commit_deployment()
	session.begin_turn(Action.hold(hero)); var a=state.party_member_ids[1]; var b=state.party_member_ids[2]
	session.override_companion(a,Action.hold(a)); session.override_companion(b,Action.hold(b)); session.clear_companion_override(a)
	var preview=session.current_turn_preview(); var sources:Dictionary={}
	for row in preview.actor_rows:sources[int(row.actor_id)]=str(row.source)
	check_eq(sources[a],"SUGGESTED","first cleared"); check_eq(sources[b],"OVERRIDE","second retained")
	session.commit_turn(); var text:=JSON.stringify(session.recent_event_log(24))
	check(not "ENGAGED" in text and not "party.override_committed" in text and not "MELEE" in text,"raw enums absent")
	check("계획을 바꿨다" in text,"override narrative")
	return finish()

func test_full_exploration_deployment_turn_regroup_journal_replays_exactly() -> bool:
	var session = Session.new(333,444); var journey_ok := _play_full_journey(session, "COLUMN")
	check(journey_ok, "full canonical journey reached grouped complete")
	check_eq(session.party_status().safe_phase, "GROUPED_COMPLETE", "journey regrouped")
	var move = session.commit_exploration_direction(Vector2i.LEFT); check(move.accepted, "post-regroup move journaled")
	var encoded := session.save_session_json(); var decoded = JSON.parse_string(encoded)
	check_eq(decoded.keys().size(), 5, "exact session top key count")
	check(decoded.journal.size() >= 5, "journal includes exploration/deployment/turns/regroup")
	var restored = Session.new(1,2); var loaded = restored.load_session_json(encoded)
	check(bool(loaded.accepted), "full load accepted: %s" % str(loaded))
	check_eq(restored.sim.snapshot(), session.sim.snapshot(), "full journal snapshot exact")
	check_eq(restored.recent_event_log(100), session.recent_event_log(100), "full journal narrative exact")
	check_eq(restored.party_status().anchor, session.party_status().anchor, "post-regroup replay anchor exact")
	return finish()

func test_session_and_journal_wire_tampering_is_transactional_and_never_asserts() -> bool:
	var source = Session.new(); var source_state = source.sim.world.party_encounter
	source.commit_exploration(Command.wait(source_state.protagonist_id)); source.preview_deployment("WEDGE", source.available_companion_ids())
	var canonical = JSON.parse_string(source.save_session_json()); var cases: Array = []
	var extra = canonical.duplicate(true); extra["extra"] = true; cases.append(extra)
	var fractional = canonical.duplicate(true); fractional.session_format_version = 1.5; cases.append(fractional)
	var numeric_seed = canonical.duplicate(true); numeric_seed.world_seed = 44; cases.append(numeric_seed)
	var unknown = canonical.duplicate(true); unknown.journal[0].kind = "unknown"; cases.append(unknown)
	var extra_journal = canonical.duplicate(true); extra_journal.journal[0]["extra"] = 1; cases.append(extra_journal)
	var noncanonical_actor = canonical.duplicate(true); noncanonical_actor.journal[0].command.actor_id = "01"; cases.append(noncanonical_actor)
	var malformed_turn = canonical.duplicate(true); malformed_turn.journal.append({"kind":"party_turn", "request":{"overrides":[], "protagonist_action":{"type":"HOLD"}}}); cases.append(malformed_turn)
	var bad_snapshot = canonical.duplicate(true); bad_snapshot.snapshot.party_encounter.enemy_busy_rows[0].busy_until = "-1"; cases.append(bad_snapshot)

	var target = Session.new(55,66); var target_state = target.sim.world.party_encounter
	target.commit_exploration(Command.wait(target_state.protagonist_id)); target.preview_deployment("LINE", target.available_companion_ids())
	var before_snapshot = target.sim.snapshot(); var before_journal = target.command_journal.duplicate(true); var before_draft = target.deployment_draft()
	for tampered in cases:
		var result = target.load_session_json(JSON.stringify(tampered))
		check(not bool(result.accepted), "tampered session rejected")
		check_eq(target.sim.snapshot(), before_snapshot, "invalid load snapshot transactional")
		check_eq(target.command_journal, before_journal, "invalid load journal transactional")
		check_eq(target.deployment_draft(), before_draft, "invalid load UI draft transactional")
	return finish()

func test_deployment_turn_target_and_action_dtos_are_deep_detached() -> bool:
	var session = Session.new(); var state = session.sim.world.party_encounter
	session.commit_exploration(Command.wait(state.protagonist_id))
	var preview = session.preview_deployment("LINE", session.available_companion_ids()); preview.placements[1].position = [99,99]
	var draft = session.deployment_draft(); check(draft.placements[1].position != [99,99], "deployment ghost detached")
	check(session.commit_deployment().accepted, "detached deployment mutation cannot poison commit")
	var hero = session.party_status().protagonist_id; var turn = session.set_actor_action(hero, "HOLD")
	turn.actor_rows[0].time_cost = 1; turn.actor_rows[0].action.type = "MELEE"
	var fresh = session.current_turn_preview(); check_eq(fresh.actor_rows[0].time_cost, 100, "turn cost detached")
	check_eq(fresh.actor_rows[0].action.type, "HOLD", "turn action detached")
	var targets = session.enemy_targets(); targets[0].position = [88,88]
	check(session.enemy_targets()[0].position != [88,88], "target DTO detached")
	return finish()

func test_submitted_action_values_and_party_plan_storage_are_canonical_copies() -> bool:
	var session = Session.new(); var state = session.sim.world.party_encounter
	session.commit_exploration(Command.wait(state.protagonist_id)); session.preview_deployment("WEDGE", session.available_companion_ids())
	check(session.commit_deployment().accepted, "copy fixture deployed")
	state = session.sim.world.party_encounter; var hero = state.protagonist_id; var companion = state.party_member_ids[1]
	var caller_hero = Action.hold(hero); check(session.begin_turn(caller_hero).accepted, "hero draft accepted")
	caller_hero.type = "MELEE"; caller_hero.target_id = state.enemy_ids[0]
	var after_hero_mutation: Dictionary = session.current_turn_preview()
	check_eq(after_hero_mutation.actor_rows[0].action.type, "HOLD", "hero caller mutation cannot change stored draft")
	var caller_companion = Action.hold(companion); check(session.override_companion(companion, caller_companion).accepted, "companion override accepted")
	caller_companion.type = "MOVE"; caller_companion.destination = Vector2i(99,99)
	var after_companion_mutation: Dictionary = session.current_turn_preview(); var companion_row: Dictionary
	for row in after_companion_mutation.actor_rows:
		if int(row.actor_id) == companion: companion_row = row; break
	check_eq(companion_row.action.type, "HOLD", "override caller mutation cannot change stored draft")
	var plan = session.sim.preview_party_turn(load("res://sim/party_turn_request.gd").new(Action.hold(hero), []))
	var detached_plan: Dictionary = plan.to_dict(); detached_plan.actor_rows[0].time_cost = 1
	check_eq(plan.to_dict().actor_rows[0].time_cost, 100, "plan storage is hidden behind deep copies")
	var detached_rows: Array = plan.get_value("actor_rows", [])
	detached_rows[0].action.type = "MELEE"; detached_rows[0].action.target_id = str(state.enemy_ids[0])
	check_eq(plan.get_value("actor_rows", [])[0].action.type, "HOLD", "plan get_value deeply detaches nested action")
	var detached_request: Dictionary = plan.get_value("canonical_request", {})
	detached_request.protagonist_action.type = "MELEE"
	check_eq(plan.get_value("canonical_request", {}).protagonist_action.type, "HOLD", "plan get_value detaches nested request")

	var request_direct = Action.hold(hero); var request_override = Action.hold(companion)
	var caller_rows := [{"actor_id":companion, "action":request_override}]
	var value_request = Request.new(request_direct, caller_rows)
	request_direct.type = "MELEE"; request_direct.target_id = state.enemy_ids[0]
	request_override.type = "MOVE"; request_override.destination = Vector2i(99,99)
	caller_rows[0].actor_id = 999; caller_rows[0].action = Action.hold(999)
	var stored_request: Dictionary = value_request.to_dict()
	check_eq(stored_request.protagonist_action.type, "HOLD", "request constructor copies protagonist action")
	check_eq(stored_request.overrides[0].actor_id, str(companion), "request constructor copies override row")
	check_eq(stored_request.overrides[0].action.type, "HOLD", "request constructor copies override action")
	return finish()

func _play_full_journey(session, formation: String) -> bool:
	var status: Dictionary = session.party_status()
	if not session.commit_exploration_direction(Vector2i.ZERO).accepted: return false
	if not session.preview_deployment(formation, session.available_companion_ids()).accepted: return false
	if not session.commit_deployment().accepted: return false
	for index in range(20):
		status = session.party_status()
		if status.safe_phase == "REGROUP_READY": break
		if status.safe_phase != "ENGAGED": return false
		var hero_id := int(status.protagonist_id); var hero_position := Vector2i.ZERO
		for card in session.party_cards():
			if int(card.entity_id) == hero_id: hero_position = Vector2i(int(card.logical_position[0]), int(card.logical_position[1])); break
		var targets = session.enemy_targets(); if targets.is_empty(): return false
		var enemy = targets[0]; var enemy_position := Vector2i(int(enemy.position[0]), int(enemy.position[1]))
		var distance := maxi(absi(hero_position.x-enemy_position.x), absi(hero_position.y-enemy_position.y))
		var preview: Dictionary
		if distance == 1:
			preview = session.set_actor_action(hero_id, "MELEE", [], int(enemy.entity_id))
		else:
			var directions := [Vector2i(signi(enemy_position.x-hero_position.x), signi(enemy_position.y-hero_position.y)),
				Vector2i(signi(enemy_position.x-hero_position.x),0), Vector2i(0,signi(enemy_position.y-hero_position.y))]
			preview = {"accepted":false}
			for direction in directions:
				if direction == Vector2i.ZERO: continue
				preview = session.set_actor_action(hero_id, "MOVE", [hero_position.x+direction.x,hero_position.y+direction.y])
				if bool(preview.accepted): break
			if not bool(preview.get("accepted",false)): preview = session.set_actor_action(hero_id, "HOLD")
		if not bool(preview.get("accepted",false)) or not session.commit_turn().accepted: return false
	if session.party_status().safe_phase != "REGROUP_READY": return false
	return bool(session.regroup().accepted)
