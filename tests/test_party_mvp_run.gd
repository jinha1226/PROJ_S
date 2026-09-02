extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const VisualMap = preload("res://playtest/party_visual_test_map.gd")
const AsciiStyle = preload("res://playtest/ascii_visual_style.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")


func test_run_manifest_and_progress_are_exact_pure_and_detached() -> bool:
	var manifest: Dictionary = VisualMap.run_manifest("SHOWCASE_V1")
	check_eq(_sorted_keys(manifest), ["entry", "exit", "objective_id", "reward",
		"scenario_id", "schema_version"], "run manifest exact keys")
	check_eq(manifest, {"schema_version":1, "scenario_id":"SHOWCASE_V1",
		"objective_id":"CLEAR_SINGLE_ENCOUNTER_AND_EXIT",
		"entry":{"position":[2,12], "feature_id":"run_entry"},
		"exit":{"position":[13,1], "locked_feature_id":"run_exit_locked",
			"open_feature_id":"run_exit_open"},
		"reward":{"reward_id":"SHOWCASE_VICTORY_TOKEN", "amount":1}},
		"run manifest exact value")
	check(VisualMap.run_manifest("REGRESSION_V1").is_empty(),
		"regression has no run manifest")
	check_eq(AsciiStyle.feature_spec("run_entry").glyph, "입",
		"entry has a visible feature glyph")
	check_eq(AsciiStyle.feature_spec("run_exit_locked").glyph, "닫",
		"locked exit uses the closed Hangul feature glyph")
	check_eq(AsciiStyle.feature_spec("run_exit_open").glyph, "출",
		"open exit has a visible feature glyph")
	check(not bool(AsciiStyle.feature_spec("unknown_feature").visible),
		"unknown feature does not draw")
	manifest.entry.position[0] = 99
	check_eq(VisualMap.run_manifest("SHOWCASE_V1").entry.position, [2,12],
		"manifest is deeply detached")

	var session = Session.new(44,20260828,"SHOWCASE_V1")
	var before := session.save_session_json()
	var progress: Dictionary = session.run_progress()
	check_eq(_sorted_keys(progress), ["available", "complete", "encounter_cleared",
		"entry_position", "exit", "exit_position", "objective_id", "reward",
		"run_state", "scenario_id", "schema_version", "terminal"],
		"run progress exact keys")
	check_eq(progress, {"schema_version":1, "available":true,
		"scenario_id":"SHOWCASE_V1",
		"objective_id":"CLEAR_SINGLE_ENCOUNTER_AND_EXIT", "run_state":"EXPLORE",
		"entry_position":[2,12], "exit_position":[13,1],
		"encounter_cleared":false,
		"reward":{"reward_id":"SHOWCASE_VICTORY_TOKEN", "amount":0,
			"granted":false},
		"exit":{"feature_id":"run_exit_locked", "open":false},
		"complete":false, "terminal":false}, "initial progress exact")
	progress.reward.amount = 99; progress.exit.feature_id = "corrupted"
	check_eq(session.run_progress().reward.amount, 0, "nested reward is detached")
	check_eq(session.run_progress().exit.feature_id, "run_exit_locked",
		"nested exit is detached")
	check_eq(session.save_session_json(), before, "run projection is pure")
	var wire: Dictionary = JSON.parse_string(before)
	check_eq([int(wire.session_format_version), int(wire.snapshot.snapshot_version)],
		[5,9], "session v5 and core snapshot v9 expose the stat hard cut")
	check(not _contains_run_key(wire.snapshot),
		"core snapshot contains no derived run/reward/exit key")
	return finish()


func test_locked_exit_and_fov_feature_are_gated_without_mutation() -> bool:
	var session = Session.new(44,20260828,"SHOWCASE_V1")
	var initial_exit := _cell(session.observe_party_world(), VisualMap.EXIT_POSITION)
	check_eq([initial_exit.visibility_state, initial_exit.feature_id], ["UNSEEN", ""],
		"initial hidden exit leaks no feature")
	# The revised SHOWCASE intentionally reveals its monster near the entry. Move
	# this locked-exit-only fixture to a valid quiet vantage without consuming a
	# gameplay turn, so contact behavior is covered independently.
	var fixture_state=session.sim.world.party_encounter
	fixture_state.group_anchor=Vector2i(8,1)
	for member_id in fixture_state.active_party_member_ids:
		session.sim.world.entities[member_id].position=fixture_state.group_anchor
	check_eq(session.sim.world.world_state_error(),"","locked-exit vantage fixture remains valid")
	check_eq(session.party_status().safe_phase, "GROUPED", "vantage remains exploration")
	var visible_exit := _cell(session.observe_party_world(), VisualMap.EXIT_POSITION)
	check_eq([visible_exit.visibility_state, visible_exit.feature_id],
		["VISIBLE", "run_exit_locked"], "visible exit is locked")
	var hero := int(session.party_status().protagonist_id)
	var before := session.save_session_json()
	var route_before: Dictionary = session.exploration_route_state()
	var direct: Dictionary = session.preview_exploration(
		Command.move_to(hero, VisualMap.EXIT_POSITION))
	check_eq([direct.accepted, direct.reason], [false, "exit_locked"],
		"locked direct move is facade-gated")
	var route: Dictionary = session.preview_exploration_route(VisualMap.EXIT_POSITION)
	check_eq([route.accepted, route.reason], [false, "exit_locked"],
		"locked route goal is facade-gated")
	var start: Dictionary = session.start_exploration_route(VisualMap.EXIT_POSITION,"forged")
	check_eq([start.accepted, start.reason], [false, "exit_locked"],
		"locked route start is facade-gated")
	check_eq(session.save_session_json(), before,
		"locked exit attempts preserve snapshot and journal")
	check_eq(session.exploration_route_state(), route_before,
		"locked exit attempts preserve route state")
	return finish()


func test_showcase_entry_combat_reward_exit_complete_e2e() -> bool:
	var session = Session.new(44,20260828,"SHOWCASE_V1")
	check_eq(session.party_status().protagonist_position, [2,12], "run begins at entry")
	check(_clear_showcase_encounter(session), "showcase encounter clears within 32 turns")
	var open: Dictionary = session.run_progress()
	check_eq([open.run_state, open.encounter_cleared, open.reward.granted,
		open.reward.amount, open.exit.open, open.exit.feature_id, open.complete],
		["EXIT_OPEN", true, true, 1, true, "run_exit_open", false],
		"combat victory grants fixed reward and opens exit")
	var exit_result := _advance_to_complete(session, VisualMap.EXIT_POSITION, 32)
	check(bool(exit_result.get("ok",false)), "open exit route completes: %s" % exit_result)
	check_eq(int(exit_result.get("journal_delta",0)), 1,
		"final exit hop adds exactly one existing exploration row")
	var complete: Dictionary = session.run_progress()
	check_eq([complete.run_state, complete.complete, complete.terminal,
		complete.reward.amount, complete.exit.open],
		["COMPLETE", true, true, 1, true], "run becomes terminal COMPLETE")
	check_eq(session.party_status().protagonist_position, [13,1],
		"completion is derived from protagonist exit position")
	check(not session.exploration_route_state().get("has_preview",false),
		"completion clears route transient")

	var before := session.save_session_json()
	var status: Dictionary = session.party_status()
	var hero := int(status.protagonist_id)
	var companion := int(status.party_member_ids[1])
	var calls := [
		session.preview_exploration(Command.wait(hero)),
		session.commit_exploration(Command.wait(hero)),
		session.preview_exploration_route(Vector2i(12,1)),
		session.start_exploration_route(Vector2i(12,1),"forged"),
		session.continue_exploration_route(),
		session.preview_deployment("WEDGE",session.available_companion_ids()),
		session.commit_deployment(),
		session.begin_turn(Action.hold(hero)),
		session.prepare_auto_combat_plan(),
		session.replace_auto_combat_protagonist_action(Action.hold(hero)),
		session.override_companion(companion,Action.hold(companion)),
		session.commit_turn(),
	]
	for result in calls:
		check_eq([bool(result.get("accepted",false)),str(result.get("reason",""))],
			[false,"run_complete"], "complete gameplay facade is gated")
	check_eq(session.save_session_json(), before,
		"complete gameplay gates preserve snapshot and journal")
	check(session.inspect_tile(VisualMap.EXIT_POSITION).accepted,
		"terminal run still permits inspection")
	return finish()


func test_solo_fixture_contract_replays_completes_and_restarts_exactly() -> bool:
	var manifest:Dictionary=VisualMap.run_manifest(Session.SOLO_FIXTURE_SCENARIO_ID)
	check_eq([manifest.scenario_id,manifest.reward.reward_id],
		["SOLO_FIXTURE_V1","SOLO_COMBAT_VICTORY_TOKEN"],"solo fixture manifest identity")
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var state=session.sim.world.party_encounter;var hero:=int(state.protagonist_id)
	check(session.is_solo_combat(),"solo session capability explicit")
	check_eq([state.party_member_ids,state.active_party_member_ids,state.member_rows.keys()],
		[[hero],[hero],[hero]],"solo authoritative roster contains only protagonist")
	check_eq(session.sim.world.entities.size(),2,"solo bootstrap creates only hero and enemy")
	check_eq([session.party_cards().size(),session.available_companion_ids(),
		session.rescue_candidate_ids(),session.recruitable_companions()],
		[1,[],[],[]],"companion rescue and roster surfaces are empty")
	var observed_actor_ids:Array=[]
	for cell in session.observe_party_world().cells:
		for actor in cell.actors:observed_actor_ids.append(int(actor.entity_id))
	observed_actor_ids.sort()
	check_eq(observed_actor_ids,[hero,int(state.enemy_ids[0])],
		"visible solo world contains hero and enemy only")
	var route:Dictionary=session.preview_exploration_route(Vector2i(9,6))
	var follow:Dictionary=session.exploration_companion_follow_plan(route)
	check(route.accepted and follow.accepted and follow.companion_rows.is_empty(),
		"solo route has no hidden follower projection")
	check(_advance_route(session,Vector2i(9,6),32),"solo reaches contact canonically")
	check_eq(session.party_status().safe_phase,"CONTACT","solo contact is explicit before facade entry")
	var deployment:Dictionary=session.enter_solo_combat()
	check(deployment.accepted,"solo canonical zero-companion deployment commits")
	check_eq([session.party_status().safe_phase,session.party_status().formation_id],
		["ENGAGED","LINE"],"solo deployment enters combat without relaxing formation invariant")
	var deployed_members:=0;var completed_event=null
	for event_id in deployment.event_ids:
		var event=session.sim.world.event_by_id(int(event_id))
		if event==null:continue
		if str(event.type)=="party.member_deployed":deployed_members+=1
		if str(event.type)=="party.deployment_completed":completed_event=event
	check_eq(deployed_members,0,"solo deployment emits no companion member event")
	check(completed_event!=null and completed_event.data.companion_ids==[],
		"deployment completion records canonical empty companion set")
	var journal_after_deploy:Array=session.command_journal.duplicate(true)
	var repeat:Dictionary=session.enter_solo_combat()
	check(not repeat.accepted,"repeated solo deployment rejects")
	check_eq(session.command_journal,journal_after_deploy,"repeated refresh/deploy cannot duplicate journal")
	var planning:Dictionary=session.prepare_auto_combat_plan()
	check(planning.active and planning.placeholder \
		and planning.preview.actor_rows.size()==1 \
		and int(planning.preview.actor_rows[0].actor_id)==hero,
		"solo placeholder evaluates exactly one protagonist row")
	check(session.companion_speech_bubbles().is_empty() \
		and session.turn_intent_overlays().is_empty(),
		"solo placeholder exposes no autonomous companion action or speech")
	var forecasts:Array=session.enemy_intent_forecasts()
	check_eq(forecasts.size(),1,"solo visible enemy exposes one forecast")
	if not forecasts.is_empty():check_eq(int(forecasts[0].target_id),hero,
		"enemy forecast can target only protagonist")
	check(_round_trip_matches(session),"solo ENGAGED save load replay exact")
	var tampered:Dictionary=JSON.parse_string(session.save_session_json())
	tampered.scenario_id=Session.SHOWCASE_SCENARIO_ID
	var tamper_target=Session.new(9,10,Session.SOLO_FIXTURE_SCENARIO_ID)
	var tamper_before:String=tamper_target.save_session_json()
	var tamper_result:Dictionary=tamper_target.load_session_json(JSON.stringify(tampered))
	check(not tamper_result.accepted,"known scenario swap rejects solo snapshot")
	check_eq(tamper_target.save_session_json(),tamper_before,"solo scenario tamper is transactional")
	check(_resolve_engaged_encounter(session,32),"solo encounter clears within turn limit")
	check_eq([session.run_progress().run_state,session.run_progress().reward.granted,
		session.run_progress().exit.open],["EXIT_OPEN",true,true],
		"solo victory grants reward and opens exit")
	var party_actor_ids:Dictionary={hero:true}
	for event in session.sim.world.events:
		if int(event.actor_id)>0 and session.sim.world.entities.has(int(event.actor_id)) \
				and str(session.sim.world.entities[int(event.actor_id)].faction_id)=="party":
			party_actor_ids[int(event.actor_id)]=true
	check_eq(party_actor_ids.keys(),[hero],"solo history contains no hidden companion actor")
	check(bool(_advance_to_complete(session,VisualMap.EXIT_POSITION,32).get("ok",false)),
		"solo reaches open exit")
	check_eq(session.run_progress().run_state,"COMPLETE","solo run complete")
	check(_round_trip_matches(session),"solo COMPLETE save load replay exact")
	var expected=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var restarted:Dictionary=session.restart_same_run()
	check(restarted.accepted,"solo complete run restarts")
	check_eq([session.world_seed,session.personality_seed,session.scenario_id],
		[44,20260828,"SOLO_FIXTURE_V1"],"solo fixture restart preserves exact identity")
	check_eq(session.sim.snapshot(),expected.sim.snapshot(),"solo restart rebuilds exact initial snapshot")
	check(session.command_journal.is_empty(),"solo restart clears journal")
	return finish()


func test_exit_open_and_complete_save_load_replay_exactly() -> bool:
	var source = Session.new(44,20260828,"SHOWCASE_V1")
	check(_clear_showcase_encounter(source), "save fixture reaches EXIT_OPEN")
	check_eq(source.run_progress().run_state, "EXIT_OPEN", "source exit-open state")
	check(_round_trip_matches(source), "EXIT_OPEN save/load/replay exact")
	var completed := _advance_to_complete(source, VisualMap.EXIT_POSITION, 32)
	check(bool(completed.get("ok",false)), "save fixture reaches COMPLETE")
	check(_round_trip_matches(source), "COMPLETE save/load/replay exact")
	var wire: Dictionary = JSON.parse_string(source.save_session_json())
	check(_event_type_contains(wire.snapshot,"progression.enemy_reward"),
		"each defeated enemy records its canonical progression reward event")
	return finish()


func test_run_wire_tamper_is_transactional() -> bool:
	var source = Session.new(44,20260828,"SHOWCASE_V1")
	var canonical: Dictionary = JSON.parse_string(source.save_session_json())
	var target = Session.new(55,66,"SHOWCASE_V1")
	var before := target.save_session_json()
	var extra := canonical.duplicate(true); extra["run_progress"] = {"complete":true}
	var extra_result: Dictionary = target.load_session_json(JSON.stringify(extra))
	check_eq([extra_result.accepted, extra_result.reason],
		[false,"invalid_party_session_wire"], "derived run key is rejected")
	check_eq(target.save_session_json(), before, "extra run key rejection is transactional")
	var swapped := canonical.duplicate(true); swapped.scenario_id = "REGRESSION_V1"
	var swapped_result: Dictionary = target.load_session_json(JSON.stringify(swapped))
	check_eq([swapped_result.accepted, swapped_result.reason],
		[false,"party_journal_snapshot_mismatch"],
		"known scenario swap rejects by replay equality")
	check_eq(target.save_session_json(), before,
		"known scenario swap rejection is transactional")
	return finish()


func test_restart_reuses_exact_identity_and_resets_run() -> bool:
	var session = Session.new(44,20260828,"SHOWCASE_V1")
	check(_clear_showcase_encounter(session), "restart fixture clears encounter")
	check(bool(_advance_to_complete(session,VisualMap.EXIT_POSITION,32).get("ok",false)),
		"restart fixture completes run")
	var expected = Session.new(44,20260828,"SHOWCASE_V1")
	var expected_wire: Dictionary = JSON.parse_string(expected.save_session_json())
	var restarted: Dictionary = session.restart_same_run()
	check(bool(restarted.accepted), "complete run restarts")
	var actual_wire: Dictionary = JSON.parse_string(session.save_session_json())
	check_eq([session.world_seed,session.personality_seed,session.scenario_id],
		[44,20260828,"SHOWCASE_V1"], "restart preserves exact run identity")
	check_eq(actual_wire.snapshot, expected_wire.snapshot,
		"restart rebuilds exact fresh initial snapshot")
	check_eq(actual_wire.journal, [], "restart clears journal")
	check_eq(session.run_progress(), expected.run_progress(),
		"restart restores initial EXPLORE progress")
	check_eq([session.party_status().step_index, session.run_progress().run_state],
		[0,"EXPLORE"], "restart returns to step zero exploration")
	return finish()


func _clear_showcase_encounter(session) -> bool:
	if not _advance_route(session,Vector2i(9,6),32): return false
	if session.party_status().safe_phase != "CONTACT": return false
	var deployed := false
	for preset in ["WEDGE","LINE","COLUMN"]:
		var preview: Dictionary = session.preview_deployment(preset,
			session.available_companion_ids())
		if not bool(preview.get("accepted",false)): continue
		deployed = bool(session.commit_deployment().get("accepted",false))
		break
	if not deployed: return false
	return _resolve_engaged_encounter(session,32)


func _resolve_engaged_encounter(session,turn_limit:int) -> bool:
	for _turn in range(turn_limit):
		var status: Dictionary = session.party_status()
		if status.safe_phase == "GROUPED_COMPLETE": return true
		if status.safe_phase != "ENGAGED": return false
		var hero := int(status.protagonist_id)
		var hero_position := _party_position(session,hero)
		var targets: Array = session.enemy_targets()
		if targets.is_empty(): return false
		var enemy: Dictionary = targets[0]
		var enemy_position := Vector2i(int(enemy.position[0]),int(enemy.position[1]))
		var preview: Dictionary = {"accepted":false}
		if maxi(absi(hero_position.x-enemy_position.x),
				absi(hero_position.y-enemy_position.y)) == 1:
			preview = session.set_actor_action(hero,"MELEE",[],int(enemy.entity_id))
		else:
			for direction in [Vector2i(signi(enemy_position.x-hero_position.x),
					signi(enemy_position.y-hero_position.y)),
					Vector2i(signi(enemy_position.x-hero_position.x),0),
					Vector2i(0,signi(enemy_position.y-hero_position.y))]:
				if direction == Vector2i.ZERO: continue
				preview = session.set_actor_action(hero,"MOVE",
					[hero_position.x+direction.x,hero_position.y+direction.y])
				if bool(preview.get("accepted",false)): break
			if not bool(preview.get("accepted",false)):
				preview = session.set_actor_action(hero,"HOLD")
		if not bool(preview.get("accepted",false)) \
				or not bool(session.commit_turn().get("accepted",false)):
			return false
	return session.party_status().safe_phase == "GROUPED_COMPLETE"


func _advance_route(session, goal: Vector2i, limit: int) -> bool:
	var preview: Dictionary = session.preview_exploration_route(goal)
	if not bool(preview.get("accepted",false)): return false
	var result: Dictionary = session.start_exploration_route(goal,str(preview.plan_hash))
	if not bool(result.get("accepted",false)): return false
	for _step in range(limit):
		if session.party_status().safe_phase == "CONTACT": return true
		var route: Dictionary = session.exploration_route_state()
		if bool(route.get("completed",false)): return true
		if not bool(route.get("active",false)): return false
		result = session.continue_exploration_route()
		if not bool(result.get("accepted",false)): return false
	return false


func _advance_to_complete(session, goal: Vector2i, limit: int) -> Dictionary:
	var preview: Dictionary = session.preview_exploration_route(goal)
	if not bool(preview.get("accepted",false)):
		return {"ok":false,"reason":preview.get("reason","")}
	var journal_before := _journal_size(session)
	var result: Dictionary = session.start_exploration_route(goal,str(preview.plan_hash))
	if not bool(result.get("accepted",false)):
		return {"ok":false,"reason":result.get("reason","")}
	if session.run_progress().complete:
		return {"ok":true,"journal_delta":_journal_size(session)-journal_before}
	for _step in range(limit):
		var before_hop := _journal_size(session)
		result = session.continue_exploration_route()
		if not bool(result.get("accepted",false)):
			return {"ok":false,"reason":result.get("reason","")}
		if session.run_progress().complete:
			return {"ok":true,"journal_delta":_journal_size(session)-before_hop}
	return {"ok":false,"reason":"route_limit"}


func _round_trip_matches(source) -> bool:
	var encoded: String = source.save_session_json()
	var restored = Session.new(1,2,"REGRESSION_V1")
	var loaded: Dictionary = restored.load_session_json(encoded)
	if not bool(loaded.get("accepted",false)): return false
	var source_wire: Dictionary = JSON.parse_string(encoded)
	var restored_wire: Dictionary = JSON.parse_string(restored.save_session_json())
	return restored_wire.snapshot == source_wire.snapshot \
		and restored_wire.journal == source_wire.journal \
		and restored.run_progress() == source.run_progress()


func _party_position(session, entity_id: int) -> Vector2i:
	for card in session.party_cards():
		if int(card.entity_id) == entity_id:
			return Vector2i(int(card.logical_position[0]),int(card.logical_position[1]))
	return Vector2i(-1,-1)


func _journal_size(session) -> int:
	return JSON.parse_string(session.save_session_json()).journal.size()


func _cell(observation: Dictionary, position: Vector2i) -> Dictionary:
	for row in observation.get("cells",[]):
		if row is Dictionary and row.get("position",[]) == [position.x,position.y]:
			return row
	return {}


func _sorted_keys(value: Dictionary) -> Array:
	var keys: Array = value.keys(); keys.sort(); return keys


func _contains_run_key(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if str(key) in ["run_progress","run_state","reward","exit","complete"]:
				return true
			if _contains_run_key(value[key]): return true
	elif value is Array:
		for row in value:
			if _contains_run_key(row): return true
	return false


func _event_type_contains(snapshot: Dictionary, fragment: String) -> bool:
	for event in snapshot.get("events",[]):
		if event is Dictionary and fragment in str(event.get("type","")):
			return true
	return false
