extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const Action=preload("res://sim/party_action_command.gd")
const Request=preload("res://sim/party_turn_request.gd")
const WeaponLoadout=preload("res://sim/weapon_loadout_state.gd")
const VisualMap=preload("res://playtest/party_visual_test_map.gd")

func test_companion_exile_and_distinct_recruitment_pool_are_authoritative_and_replay_exact() -> bool:
	# A full four-member party must still gate a fifth recruit without consuming
	# the deterministic social roll.
	var capped=Session.new(44,20260828,"SHOWCASE_V1")
	var capped_status:Dictionary=capped.party_status()
	var capped_borin:=int(capped_status.recruitable_member_ids[0])
	var capped_sera:=int(capped_status.rescue_candidate_ids[0])
	check(capped.recruit_companion(capped_borin).accepted,
		"third companion fills the fourth active slot")
	check_eq(capped.party_status().party_member_ids.size(),4,
		"four-member party reaches its active cap")
	check(capped.stabilize_recruit_candidate(capped_sera).accepted,
		"full-party rescue can still stabilize a world NPC")
	var capped_decision:=capped.recruitment_assessment(capped_sera)
	check(not capped_decision.accepted and capped_decision.reason=="party_full" \
		and int(capped_decision.probability_milli)>0 \
		and int(capped_decision.roll_milli)==-1 \
		and str(capped_decision.key_hash).is_empty(),
		"four-member cap blocks a fifth member without revealing the stable roll")

	var session=Session.new(44,20260828,"SHOWCASE_V1");var state=session.sim.world.party_encounter
	var hero:=int(state.protagonist_id);var narae:=int(state.party_member_ids[1]);var miru:=int(state.party_member_ids[2])
	var candidates:Array=session.party_status().recruitable_member_ids
	var rescue_candidates:Array=session.party_status().rescue_candidate_ids
	check_eq([candidates.size(),rescue_candidates.size()],[1,1],
		"showcase separates legacy fixture candidate from one world rescue NPC")
	var borin:=int(candidates[0]);var sera:=int(rescue_candidates[0])
	check(str(session.sim.world.entities[borin].display_name)!=str(session.sim.world.entities[sera].display_name) \
		and str(session.sim.world.entities[borin].species_id)!=str(session.sim.world.entities[sera].species_id),
		"candidate identities and species differ")
	check_eq(session.dismiss_companion(hero).reason,"protagonist_dismiss_forbidden","hero cannot be dismissed")
	var route:Dictionary=session.preview_exploration_route(Vector2i(9,7))
	check(route.has("accepted"),"route fixture produces a detached facade result")
	check(session.dismiss_companion(narae).accepted,"first companion dismissed")
	check_eq([session.party_cards().size(),state.active_party_member_ids,state.member(narae).presence],
		[2,[hero,miru],"EXILED"],"dismiss permanently exiles and removes active card")
	var observed_ids:Array=[]
	for cell in session.observe_party_world().cells:
		for actor in cell.actors:observed_ids.append(int(actor.entity_id))
	check(narae not in observed_ids and narae not in session.available_companion_ids(),
		"exiled member is absent from map followers and automatic companion pool")
	check(not bool(session.exploration_route_state().get("has_preview",false)),"dismiss clears stale route")
	var exile_before_refresh:Array=session.exile_story_records()
	session.inspect_party_member(narae);session.recruitable_companions();session.recent_event_log()
	check_eq(session.exile_story_records(),exile_before_refresh,"read-only refresh does not advance exile world")
	check(session.commit_exploration_direction(Vector2i.ZERO).accepted,"canonical wait advances offscreen exile")
	var advanced_record:Dictionary=session.exile_story_records()[0]
	check_eq([advanced_record.last_world_time,advanced_record.current_behavior,advanced_record.alive],
		["100","RECOVER",true],"healthy exile processes one canonical recovery/safety quantum")
	check(session.exile_encounter_evaluation(narae).reason=="exile_encounter_too_early",
		"encounter evaluator is gated until enough canonical steps pass")
	check_eq(session.recruit_companion(narae).reason,"companion_not_recruitable",
		"exiled companion can never return through recruitment")
	check(session.recruit_companion(borin).accepted,"distinct candidate recruited")
	check_eq([session.party_cards().size(),state.active_party_member_ids,state.member(borin).presence],
		[3,[hero,miru,borin],"GROUPED"],"candidate joins active party")
	check_eq(session.recruit_companion(sera).reason,"recruitment_offer_required",
		"direct recruit cannot bypass rescue judgment even while party is full")
	check_eq(session.sim.world.combatant_states[sera].life_state,"ACTIVE",
		"rescue story never weakens the canonical combat life invariant")
	var rescue_before:=session.rescue_assessment(sera)
	check(rescue_before.accepted and rescue_before.time_cost==100,
		"adjacent collapsed non-hostile NPC exposes one-turn stabilization")
	check(session.stabilize_recruit_candidate(sera).accepted,
		"help action advances canonical time and stabilizes candidate")
	check_eq(session.sim.world.combatant_states[sera].life_state,"ACTIVE",
		"stabilization changes story state without combat lifecycle mutation")
	var open_decision:=session.recruitment_assessment(sera)
	check(open_decision.accepted and open_decision.would_accept \
		and absi(int(open_decision.terms.species_prior)) \
			> absi(int(open_decision.terms.personality)),
		"fourth slot opens offer and species prior dominates personality input")
	var offered:=session.offer_recruitment(sera)
	check(offered.accepted and offered.joined,
		"rescued candidate accepts stable offer and fills the fourth slot")
	check_eq(session.party_cards().size(),4,
		"recruited third companion renders a four-member active party")
	check(session.dismiss_companion(miru).accepted,"active companion can be permanently exiled")
	check(session.dismiss_companion(borin).accepted,"recruited candidate can later be exiled")
	check(session.recruitable_companions().is_empty(),"candidate pool exhausts without recycling exiles")
	check_eq(session.recruit_companion(borin).reason,"companion_not_recruitable","candidate exile is permanent")
	var encoded:=session.save_session_json();var restored=Session.new(9,10)
	check(restored.load_session_json(encoded).accepted,"exile/recruit save-load journal replay accepted")
	check_eq(restored.sim.snapshot(),session.sim.snapshot(),"exile/recruit snapshot and replay exact")
	var legacy_wire:Dictionary=JSON.parse_string(Session.new().save_session_json())
	legacy_wire.snapshot.party_encounter.schema_version=1
	for member_row in legacy_wire.snapshot.party_encounter.member_rows:
		member_row.erase("mental_mode")
	for future_key in ["active_party_member_ids","exile_records",
			"patrol_reserved_positions","protagonist_progression","protagonist_loadout",
			"diagonal_gateway_positions","enemy_awareness_rows","protagonist_inventory",
			"ground_items","safe_recovery_turns","last_protagonist_damage_step"]:
		legacy_wire.snapshot.party_encounter.erase(future_key)
	var migrated=Session.new(5,6)
	var legacy_result:Dictionary=migrated.load_session_json(JSON.stringify(legacy_wire))
	check(not bool(legacy_result.get("accepted",false)) \
		and str(legacy_result.get("reason",""))=="unsupported_player_species_snapshot",
		"legacy party schema is rejected by the species hard cut")
	var unsafe=Session.new();var unsafe_state=unsafe.sim.world.party_encounter
	check(unsafe.commit_exploration(Command.wait(unsafe_state.protagonist_id)).accepted,"unsafe fixture reaches contact")
	check_eq(unsafe.dismiss_companion(int(unsafe_state.party_member_ids[1])).reason,
		"party_roster_unsafe_phase","contact rejects roster change")
	check("영구히 추방" in JSON.stringify(session.recent_event_log(12)) \
		and "새로 합류" in JSON.stringify(session.recent_event_log(12)),"roster event log states permanent/new semantics")
	return finish()


func test_downed_rescue_recruitment_refusal_is_visible_pure_stable_and_replay_exact() -> bool:
	# Seed six is the stable refusal fixture under the current canonical event
	# sequence. The test owns the outcome boundary; product recruitment remains a
	# deterministic keyed decision rather than being forced to reject.
	var session=Session.new(6,20260828,"SHOWCASE_V1")
	var state=session.sim.world.party_encounter
	var target:=int(session.party_status().rescue_candidate_ids[0])
	check_eq([session.sim.world.entities[target].health,
		session.sim.world.combatant_states[target].life_state,
		session.rescue_story_state(target)],[18,"ACTIVE","COLLAPSED_STORY"],
		"wounded non-hostile is an ACTIVE world NPC with event-derived collapsed pose")
	var observed:=false
	for cell in session.observe_party_world().cells:
		for actor in cell.actors:
			if int(actor.entity_id)==target:
				observed=str(actor.life_state)=="DOWNED" \
					and str(actor.authoritative_life_state)=="ACTIVE" and not bool(actor.is_enemy)
	check(observed,"visible FOV DTO exposes collapsed pose without lying about combat life")
	var pure_snapshot=session.sim.snapshot();var pure_journal=session.command_journal.duplicate(true)
	var first_rescue:=session.rescue_assessment(target)
	var second_rescue:=session.rescue_assessment(target)
	check_eq(first_rescue,second_rescue,"stabilization assessment is stable")
	check_eq([session.sim.snapshot(),session.command_journal],[pure_snapshot,pure_journal],
		"stabilization assessment is world/journal pure")
	var stabilized:=session.stabilize_recruit_candidate(target)
	check(stabilized.accepted and stabilized.consumes_time \
		and stabilized.start_time==0 and stabilized.end_time==100,
		"stabilization consumes one explicit deterministic turn")
	var relation:Dictionary=session.sim.relationships.effective_relation(target,state.protagonist_id)
	check_eq([relation.species_base.base_trust,relation.gratitude],[-30,70],
		"rescue records personal aid without erasing species prior")
	check(session.dismiss_companion(int(state.active_party_member_ids[1])).accepted,
		"vacancy opened through existing permanent exile path")
	var decision_a:=session.recruitment_assessment(target)
	var decision_b:=session.recruitment_assessment(target)
	check_eq(decision_a,decision_b,"recruit probability and keyed roll are stable")
	check(decision_a.accepted and not decision_a.would_accept \
		and int(decision_a.roll_milli)>=int(decision_a.probability_milli),
		"refusal fixture deterministically refuses")
	check(absi(int(decision_a.terms.species_prior))>absi(int(decision_a.terms.rescued)) \
		and absi(int(decision_a.terms.species_prior))>absi(int(decision_a.terms.personality)),
		"species prior is the dominant single score term")
	var offered:=session.offer_recruitment(target)
	check(offered.accepted and offered.resolved and not offered.joined,
		"refusal is a committed social outcome rather than a technical rejection")
	check_eq([state.active_party_member_ids.size(),state.member(target),
		session.rescue_story_state(target)],[2,null,"REJECTED"],
		"refused world NPC never enters the roster")
	check("영입 제안을 거절" in JSON.stringify(session.recent_event_log(16)),
		"Korean event log exposes actual refusal")
	var refused_snapshot=session.sim.snapshot();var refused_journal=session.command_journal.duplicate(true)
	check_eq(session.offer_recruitment(target).reason,"recruitment_already_resolved",
		"repeat tapping cannot reroll a refusal")
	check_eq([session.sim.snapshot(),session.command_journal],[refused_snapshot,refused_journal],
		"repeat offer after refusal is pure")
	var restored=Session.new(44,55,"SHOWCASE_V1")
	check(restored.load_session_json(session.save_session_json()).accepted,
		"rescue/refusal journal loads")
	check_eq(restored.sim.snapshot(),session.sim.snapshot(),
		"rescue/refusal save-load replay exact")
	return finish()

func test_new_expedition_personality_seed_profiles_replay_refresh_and_restart_are_deterministic() -> bool:
	var seed:=Session.new_expedition_personality_seed(123456)
	check_eq(seed,Session.new_expedition_personality_seed(123456),"entropy normalization deterministic")
	var session=Session.new(44,seed,"SHOWCASE_V1")
	var summary:Dictionary=session.party_personality_summary()
	check_eq(summary.companion_rows.size(),4,"active companions and two candidates have personality rows")
	var distance:=0
	for index in range(6):
		var first:int=int(summary.companion_rows[0].facet_rows[index].base_value)
		var second:int=int(summary.companion_rows[1].facet_rows[index].base_value)
		check(first>=Session.NEW_EXPEDITION_FACET_MIN and first<=Session.NEW_EXPEDITION_FACET_MAX,
			"first companion facet bounded")
		check(second>=Session.NEW_EXPEDITION_FACET_MIN and second<=Session.NEW_EXPEDITION_FACET_MAX,
			"second companion facet bounded")
		distance+=absi(first-second)
	check(distance>=Session.NEW_EXPEDITION_MIN_PROFILE_DISTANCE,"companion profile distance guaranteed")
	var before:=session.save_session_json()
	for iteration in range(8):
		var detached:Dictionary=session.party_personality_summary();detached.companion_rows[0].facet_rows[0].base_value=9999
		session.inspect_party_member(int(summary.companion_rows[0].actor_id))
	check_eq(session.save_session_json(),before,"summary/inspect refresh path never rerolls or mutates")

	check(session.commit_exploration_direction(Vector2i.ZERO).accepted,"journal fixture advances deterministically")
	var encoded:=session.save_session_json();var restored=Session.new(1,2)
	check(restored.load_session_json(encoded).accepted,"seed/profile save-load command replay accepted")
	check_eq([restored.personality_seed,restored.party_personality_summary()],
		[seed,session.party_personality_summary()],"seed and actual profiles survive replay exactly")

	var reroll_seed:=Session.new_expedition_personality_seed(654321,seed)
	check(reroll_seed!=seed,"avoid seed guarantees a different new expedition")
	session.sim.world.party_encounter.safe_phase="PARTY_DEFEATED"
	var restarted:Dictionary=session.restart_with_personality_seed(reroll_seed)
	check(restarted.accepted,"explicit boundary seed restarts terminal run")
	var expected=Session.new(44,reroll_seed,"SHOWCASE_V1")
	check_eq(session.sim.snapshot(),expected.sim.snapshot(),"reroll restart rebuilds exact explicit-seed snapshot")
	check(session.command_journal.is_empty(),"reroll restart clears prior command journal")
	check_eq(session.personality_seed,reroll_seed,"reroll restart stores issued seed")
	return finish()

func test_32_new_expedition_seeds_cover_styles_and_only_legal_personality_actions() -> bool:
	var action_counts:={"HOLD":0,"MOVE":0,"MELEE":0};var style_labels:Dictionary={}
	for entropy_seed in range(1,33):
		var seed:=Session.new_expedition_personality_seed(entropy_seed)
		var session=Session.new(44,seed);var state=session.sim.world.party_encounter
		for row in session.party_personality_summary().companion_rows:
			style_labels[str(row.style_label)]=true
		check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
			"seed %d reaches contact"%entropy_seed)
		check(session.preview_deployment("WEDGE",session.available_companion_ids()).accepted,
			"seed %d has legal wedge"%entropy_seed)
		check(session.commit_deployment().accepted,"seed %d engages"%entropy_seed)
		var distant=session.sim.preview_party_turn(Request.new(Action.hold(state.protagonist_id),[])).to_dict()
		for row in distant.actor_rows:
			if int(row.actor_id)==int(state.protagonist_id):continue
			var action_type:=str(row.action.type);check(action_type in ["HOLD","MOVE"],
				"distant suggestion remains legal HOLD/MOVE")
			action_counts[action_type]+=1
		var companion:=int(state.party_member_ids[1]);var enemy:=int(state.enemy_ids[0])
		check(_relocate_with_move_events(session.sim,enemy,
			session.sim.world.entities[companion].position+Vector2i.RIGHT),
			"seed %d creates legal adjacent fixture"%entropy_seed)
		var adjacent=session.sim.preview_party_turn(Request.new(Action.hold(state.protagonist_id),[])).to_dict()
		for row in adjacent.actor_rows:
			if int(row.actor_id)!=companion:continue
			var action_type:=str(row.action.type);check(action_type in ["HOLD","MELEE"],
				"adjacent suggestion cannot invent an illegal move")
			action_counts[action_type]+=1
	# The default calm fixtures intentionally exercise approach and adjacent attack.
	# HOLD/PROTECT/RETREAT receive explicit state fixtures in the party-AI seed probe.
	check(action_counts.MOVE>0 and action_counts.MELEE>0,
		"32 seeds cover legal approach/melee distance fixtures: %s"%str(action_counts))
	check(style_labels.size()>=4,"32 seeds cover multiple derived styles: %s"%str(style_labels.keys()))
	return finish()

func test_facade_dtos_are_detached_and_save_load_preserves_contact() -> bool:
	var session=Session.new(); var status=session.party_status(); status.safe_phase="CORRUPTED"
	var cards=session.party_cards(); cards[0].element_exposure.total_risk=999
	check_eq(session.party_status().safe_phase,"GROUPED","status detached")
	check_eq(session.party_status().session_format_version,5,"session v5 surface")
	check_eq(session.party_status().scenario_id,"REGRESSION_V1","default regression scenario surface")
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
	check(not "계획을 바꿨다" in text,"routine override bookkeeping stays out of important log")
	return finish()

func test_preview_preserves_other_overrides_and_override_keeps_original_suggestion() -> bool:
	var session=Session.new(); var state=session.sim.world.party_encounter; var hero=state.protagonist_id
	session.commit_exploration(Command.wait(hero)); session.preview_deployment("LINE",state.party_member_ids.slice(1)); session.commit_deployment()
	check(session.begin_turn(Action.hold(hero)).accepted,"direct draft")
	var first=state.party_member_ids[1]; var second=state.party_member_ids[2]
	check(session.override_companion(first,Action.hold(first)).accepted,"first override")
	var candidate=session.preview_actor_action(second,"HOLD")
	var sources:Dictionary={}
	for row in candidate.actor_rows:sources[int(row.actor_id)]=str(row.source)
	check_eq(sources[first],"OVERRIDE","candidate preview retains existing companion override")
	check_eq(sources[second],"OVERRIDE","candidate preview includes selected companion override")
	check(session.override_companion(second,Action.hold(second)).accepted,"second override")
	var overridden:Dictionary;var second_position:Array=[];var second_name:=""
	for card in session.party_cards():
		if int(card.entity_id)==second:
			overridden=card.expected_action;second_position=card.logical_position;second_name=str(card.display_name)
	check(overridden.automatic_suggestion is Dictionary,"override DTO preserves original automatic suggestion")
	var original=overridden.automatic_suggestion.duplicate(true)
	var overlay:Dictionary
	for row in session.turn_intent_overlays():
		if int(row.actor_id)==second:overlay=row;break
	check_eq(overlay.source,"OVERRIDE","actual overlay remains override")
	check_eq(overlay.line_style,"SOLID_THICK","override overlay is solid and thick")
	check_eq(overlay.marker_style,"SQUARE","override overlay uses square marker")
	check(overlay.automatic_suggestion is Dictionary,"overlay carries detached original suggestion")
	check_eq(overlay.automatic_suggestion.source,"SUGGESTED","secondary overlay source is suggested")
	check_eq(overlay.automatic_suggestion.line_style,"DASHED_THIN","original suggestion is thin dashed")
	check_eq(overlay.automatic_suggestion.marker_style,"CIRCLE","original suggestion uses circle marker")
	check_eq(overlay.automatic_suggestion.from_position,second_position,"secondary overlay has complete origin")
	var summary:="\n".join(session.turn_summary_lines())
	check("개별 덮어쓰기" in summary and "원래 제안" in summary,"turn summary renders override and original simultaneously")
	var detached=session.turn_intent_overlays();var detached_index:=-1
	for index in range(detached.size()):if int(detached[index].actor_id)==second:detached_index=index
	detached[detached_index].automatic_suggestion.from_position[0]=999
	check(session.turn_intent_overlays()[detached_index].automatic_suggestion.from_position[0]!=999,"nested secondary overlay is detached")
	check(session.clear_companion_override(second).accepted,"clear override")
	for card in session.party_cards():
		if int(card.entity_id)==second:
			check_eq(card.expected_action.source,"SUGGESTED","clear restores suggested source")
			check_eq(card.expected_action.type,original.type,"clear restores original suggested action")
	var cleared_overlay:Dictionary
	for row in session.turn_intent_overlays():if int(row.actor_id)==second:cleared_overlay=row
	check(cleared_overlay.get("automatic_suggestion",null)==null,"clear removes dual overlay")
	var cleared_line:=""
	for line in session.turn_summary_lines():if line.begins_with(second_name+" ·"):cleared_line=line
	check(not "원래 제안" in cleared_line,"clear leaves one automatic suggestion line for cleared actor")
	return finish()

func test_companion_speech_bubbles_are_pure_detached_and_refresh_each_plan() -> bool:
	var session=Session.new();var state=session.sim.world.party_encounter
	var hero=int(state.protagonist_id);var companions:Array=state.party_member_ids.slice(1)
	check(session.commit_exploration(Command.wait(hero)).accepted,"speech fixture contact")
	check(session.preview_deployment("LINE",companions).accepted,"speech fixture deployment preview")
	check(session.commit_deployment().accepted,"speech fixture engaged")
	var wire_before:=session.save_session_json()
	var planning:Dictionary=session.prepare_auto_combat_plan()
	check(planning.active and planning.placeholder,"placeholder planning is active")
	var bubbles:Array=session.companion_speech_bubbles()
	check_eq(bubbles.size(),2,"placeholder immediately exposes two companion speeches")
	for bubble in bubbles:
		check_eq(bubble.role,"COMPANION","only companion roles speak")
		check(int(bubble.actor_id)!=hero,"protagonist never gains a companion bubble")
		check_eq(bubble.source,"SUGGESTED","initial speech follows automatic suggestion")
		check(not str(bubble.reason).is_empty(),"speech retains a Korean action reason")
		var expected_headline:String={"MELEE":"공격할게.","MOVE":"이동할게.",
			"HOLD":"방어할게."}.get(str(bubble.action_type),"방어할게.")
		check_eq(bubble.headline,expected_headline,"suggested action headline is fixed")
		check_eq(bubble.reason_summary,{"MELEE":"적이 가까워서","MOVE":"길이 열려서",
			"HOLD":"피해를 줄이려고"}.get(str(bubble.action_type),"피해를 줄이려고"),
			"card speech receives a meaning-preserving short reason")
		check(str(bubble.reason_summary).length()<=14,"card reason summary stays one-line compact")
	check_eq(session.save_session_json(),wire_before,
		"speech and placeholder projections never enter session save state")
	var first_id:=int(bubbles[0].actor_id)
	var original_reason:=str(bubbles[0].reason)
	bubbles[0].from_position[0]=99;bubbles[0].reason="변조"
	var fresh:Array=session.companion_speech_bubbles()
	check(fresh[0].from_position[0]!=99 and str(fresh[0].reason)==original_reason,
		"speech DTO and nested position are detached")
	check(session.override_companion(first_id,Action.hold(first_id)).accepted,
		"companion hold override accepted")
	var overridden:Dictionary={}
	for bubble in session.companion_speech_bubbles():
		if int(bubble.actor_id)==first_id:overridden=bubble;break
	check_eq([overridden.source,overridden.action_type,overridden.headline],
		["OVERRIDE","HOLD","방어할게."],"override updates primary speech immediately")
	check("개별 지시" in str(overridden.reason),"override keeps its action-reason meaning")
	check_eq(overridden.reason_summary,"지시를 따라서","override reason is compact on the card")
	check(session.clear_companion_override(first_id).accepted,"speech override clears")
	var restored:Dictionary={}
	for bubble in session.companion_speech_bubbles():
		if int(bubble.actor_id)==first_id:restored=bubble;break
	check_eq(restored.source,"SUGGESTED","clear immediately restores suggested speech")
	check_eq(restored.headline,{"MELEE":"공격할게.","MOVE":"이동할게.",
		"HOLD":"방어할게."}.get(str(restored.action_type),"방어할게."),
		"clear restores suggested headline")
	check(session.replace_auto_combat_protagonist_action(Action.hold(hero)).accepted,
		"hero finalizes current plan")
	check(session.commit_turn().accepted,"speech fixture commits one turn")
	check(session.companion_speech_bubbles().is_empty(),
		"committed draft leaves no stale speech")
	check_eq(session.party_status().safe_phase,"ENGAGED","fixture has a following combat turn")
	check(session.prepare_auto_combat_plan().active,"next placeholder plan is prepared")
	check_eq(session.companion_speech_bubbles().size(),2,
		"next turn immediately publishes refreshed companion speeches")
	return finish()

func test_full_exploration_deployment_turn_regroup_journal_replays_exactly() -> bool:
	var session = Session.new(333,444); var journey_ok := _play_full_journey(session, "COLUMN")
	check(journey_ok, "full canonical journey reached grouped complete")
	check_eq(session.party_status().safe_phase, "GROUPED_COMPLETE", "journey regrouped")
	var move = session.commit_exploration_direction(Vector2i.LEFT); check(move.accepted, "post-regroup move journaled")
	var encoded := session.save_session_json(); var decoded = JSON.parse_string(encoded)
	check_eq(decoded.keys().size(), 7, "exact session top key count")
	check_eq(decoded.scenario_id, "REGRESSION_V1", "journal replay scenario identity")
	check(decoded.journal.size() >= 4, "journal includes exploration/deployment/turns without separate regroup")
	for row in decoded.journal: check(str(row.kind)!="regroup","automatic regroup adds no journal command")
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


func test_movement_rejection_feedback_is_structured_korean_and_pure() -> bool:
	var wall = Session.new(); var wall_state = wall.sim.world.party_encounter; var hero = wall_state.protagonist_id
	check(wall.sim.world.bootstrap_set_terrain(Vector2i(6,7), "wall"), "wall fixture")
	_check_rejection_noop(wall, func(): return wall.preview_exploration(Command.move_to(hero,Vector2i(6,7))),
		"move_terrain_blocked", "벽", "wall")
	_check_rejection_noop(wall, func(): return wall.preview_exploration(Command.move_to(hero,Vector2i(4,7))),
		"move_not_adjacent", "한 칸", "not adjacent")

	var occupied = Session.new(); var occupied_state = occupied.sim.world.party_encounter
	var enemy = occupied_state.enemy_ids[0]; occupied.sim.world.entities[enemy].position = Vector2i(6,7)
	var occupied_result = _check_rejection_noop(occupied,
		func(): return occupied.preview_exploration(Command.move_to(occupied_state.protagonist_id,Vector2i(6,7))),
		"move_destination_occupied", "점유", "occupied")
	check_eq(occupied_result.reason_details.blocking_entity_ids,[enemy],"occupied blocker ID preserved")
	check_eq(occupied_result.reason_details.blocking_entity_names,["고블린"],"occupied blocker name projected")

	var bounds = Session.new(); var bounds_state = bounds.sim.world.party_encounter
	bounds_state.group_anchor = Vector2i(0,7)
	for member_id in bounds_state.party_member_ids: bounds.sim.world.entities[member_id].position = bounds_state.group_anchor
	_check_rejection_noop(bounds,
		func(): return bounds.preview_exploration(Command.move_to(bounds_state.protagonist_id,Vector2i(-1,7))),
		"move_out_of_bounds", "지도 밖", "out of bounds")

	var corner_wall = Session.new(); var corner_state = corner_wall.sim.world.party_encounter
	check(corner_wall.sim.world.bootstrap_set_terrain(Vector2i(6,7),"wall"),"corner wall fixture")
	_check_rejection_noop(corner_wall,
		func(): return corner_wall.preview_exploration(Command.move_to(corner_state.protagonist_id,Vector2i(6,6))),
		"move_diagonal_flank_blocked", "벽 모서리", "diagonal wall")

	var corner_actor = Session.new(); var corner_actor_state = corner_actor.sim.world.party_encounter
	corner_actor.sim.world.entities[corner_actor_state.enemy_ids[0]].position = Vector2i(6,7)
	check(corner_actor.preview_exploration(Command.move_to(
		corner_actor_state.protagonist_id,Vector2i(6,6))).accepted,
		"an NPC beside the route does not block a diagonal destination")
	return finish()


func test_open_door_gateway_allows_only_the_matching_diagonal_across_one_wall_flank() -> bool:
	var session=Session.new();var state=session.sim.world.party_encounter
	var hero:=int(state.protagonist_id);var origin:=Vector2i(7,7)
	var gateway:=Vector2i(7,6);var destination:=Vector2i(6,6)
	session.sim.world.entities[state.enemy_ids[0]].position=Vector2i(14,14)
	check(session.sim.world.bootstrap_set_terrain(Vector2i(6,7),"wall"),
		"door corner has one solid flank")
	state.diagonal_gateway_positions.append(gateway)
	var preview:Dictionary=session.preview_exploration(Command.move_to(hero,destination))
	check(preview.accepted,"open passable doorway permits diagonal across its threshold")
	var path:Dictionary=session.find_exploration_path(hero,destination)
	check(path.found and path.path==[origin,destination],
		"exploration pathfinder uses the same direct doorway diagonal")
	var route:Dictionary=session.preview_exploration_route(destination)
	check(route.accepted and route.path==[[7,7],[6,6]],
		"long-route preview uses the same direct doorway diagonal")
	var snapshot:Dictionary=session._auto_explore_fog_snapshot()
	check(bool(snapshot.cells["7:6"].diagonal_gateway),
		"fog-safe AUTO snapshot identifies only the already known gateway cell")
	check(session._auto_explore._known_step_is_safe(origin,destination,snapshot.cells),
		"AUTO accepts the same doorway diagonal")
	var committed:Dictionary=session.commit_exploration(Command.move_to(hero,destination))
	check(committed.accepted and session.sim.world.entities[hero].position==destination,
		"canonical commit advances exactly one doorway diagonal")

	var leaving=Session.new();var leaving_state=leaving.sim.world.party_encounter
	var leaving_origin:=Vector2i(7,7);var leaving_destination:=Vector2i(6,6)
	leaving.sim.world.entities[leaving_state.enemy_ids[0]].position=Vector2i(14,14)
	leaving.sim.world.bootstrap_set_terrain(Vector2i(6,7),"wall")
	leaving_state.diagonal_gateway_positions.append(leaving_origin)
	var leaving_preview:Dictionary=leaving.preview_exploration(Command.move_to(
		leaving_state.protagonist_id,leaving_destination))
	check(leaving_preview.accepted,
		"actor standing in an open doorway may leave diagonally past one wall flank")
	check(leaving.find_exploration_path(leaving_state.protagonist_id,
		leaving_destination).path==[leaving_origin,leaving_destination],
		"pathfinder matches the from-door diagonal")
	var leaving_route:Dictionary=leaving.preview_exploration_route(leaving_destination)
	check(leaving_route.accepted and leaving_route.path==[[7,7],[6,6]],
		"route preview matches the from-door diagonal")
	var leaving_snapshot:Dictionary=leaving._auto_explore_fog_snapshot()
	check(leaving._auto_explore._known_step_is_safe(leaving_origin,
		leaving_destination,leaving_snapshot.cells),
		"AUTO matches the from-door diagonal without unseen topology")
	check(leaving.commit_exploration(Command.move_to(leaving_state.protagonist_id,
		leaving_destination)).accepted,"from-door canonical commit advances exactly once")

	var closed=Session.new();var closed_state=closed.sim.world.party_encounter
	closed.sim.world.entities[closed_state.enemy_ids[0]].position=Vector2i(14,14)
	closed.sim.world.bootstrap_set_terrain(Vector2i(6,7),"wall")
	closed.sim.world.bootstrap_set_terrain(Vector2i(7,6),"wall")
	closed_state.diagonal_gateway_positions.append(Vector2i(7,6))
	check_eq(closed.preview_exploration(Command.move_to(closed_state.protagonist_id,
		destination)).reason,"move_diagonal_flank_blocked",
		"closed/non-passable gateway never permits corner cutting")

	var occupied=Session.new();var occupied_state=occupied.sim.world.party_encounter
	occupied.sim.world.bootstrap_set_terrain(Vector2i(6,7),"wall")
	occupied_state.diagonal_gateway_positions.append(gateway)
	occupied.sim.world.entities[occupied_state.enemy_ids[0]].position=gateway
	check(occupied.preview_exploration(Command.move_to(
		occupied_state.protagonist_id,destination)).accepted,
		"an actor beside an open doorway no longer becomes an invisible corner wall")
	check(occupied.find_exploration_path(occupied_state.protagonist_id,destination).path \
		==[origin,destination],"pathfinder matches the occupied-flank doorway rule")

	var ordinary=Session.new();var ordinary_state=ordinary.sim.world.party_encounter
	ordinary.sim.world.entities[ordinary_state.enemy_ids[0]].position=Vector2i(14,14)
	ordinary.sim.world.bootstrap_set_terrain(Vector2i(6,7),"wall")
	check_eq(ordinary.preview_exploration(Command.move_to(
		ordinary_state.protagonist_id,destination)).reason,
		"move_diagonal_flank_blocked","ordinary floor beside a wall remains a solid corner")
	check(not ordinary.find_exploration_path(ordinary_state.protagonist_id,destination).path \
		==[origin,destination],"pathfinder cannot cut an ordinary wall corner")

	# The campaign's open forest intentionally has no doors.  Keep the doorway
	# persistence contract on the last authored dungeon layout that owns them.
	var product=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	check(product.reset_party(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID,
		VisualMap.previous_product_dungeon(44),false),
		"doorway persistence fixture initializes from the authored dungeon")
	var gateways:Array[Vector2i]=product.sim.world.party_encounter.diagonal_gateway_positions
	check(not gateways.is_empty(),"authored dungeon doors publish canonical gateway cells")
	var restored=Session.new(1,2)
	check(restored.load_session_json(product.save_session_json()).accepted,
		"gateway state survives strict save and journal replay")
	check_eq(restored.sim.snapshot(),product.sim.snapshot(),
		"gateway save/replay snapshot is exact")
	var legacy_product=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	check(legacy_product.reset_party(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID,
		product._map_layout,false),"v5 product baseline excludes future opening state")
	var legacy_v5:Dictionary=JSON.parse_string(legacy_product.save_session_json())
	legacy_v5.snapshot.party_encounter.schema_version=5
	for member_row in legacy_v5.snapshot.party_encounter.member_rows:
		member_row.erase("mental_mode")
	for future_key in ["diagonal_gateway_positions","enemy_awareness_rows",
			"protagonist_inventory","ground_items","safe_recovery_turns",
			"last_protagonist_damage_step","opening_event","protagonist_growth"]:
		legacy_v5.snapshot.party_encounter.erase(future_key)
	# A v5 row owned protagonist_loadout; v13 removed that duplicate weapon
	# authority, so the historical field is restated here.
	legacy_v5.snapshot.party_encounter.protagonist_loadout= \
		WeaponLoadout.new("SHORT_SWORD",12,6).to_dict()
	var migrated=Session.new(3,4)
	var legacy_result:Dictionary=migrated.load_session_json(JSON.stringify(legacy_v5))
	check(not bool(legacy_result.get("accepted",false)) \
		and str(legacy_result.get("reason",""))=="unsupported_player_species_snapshot",
		"v5 product save is rejected by the species hard cut")
	return finish()


func test_direct_solo_atomic_action_matches_ordinary_preview_commit_and_replay()->bool:
	var ordinary=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var atomic=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	for candidate in [ordinary,atomic]:
		check(candidate.commit_exploration_direction(Vector2i.RIGHT).accepted,
			"atomic comparison reaches contact")
		check(candidate.enter_solo_combat().accepted,"atomic comparison enters combat")
	var status:Dictionary=ordinary.party_status();var hero:=int(status.protagonist_id)
	var origin:Vector2i=ordinary.sim.world.entities[hero].position
	var destination_value:=Vector2i(-1,-1)
	for direction in ordinary.sim.movement.MOVE_DIRECTIONS_8:
		var destination_candidate:Vector2i=origin+Vector2i(direction)
		if bool(ordinary.preview_actor_action(hero,"MOVE",[destination_candidate.x,
				destination_candidate.y]).get("accepted",false)):
			destination_value=destination_candidate;break
	check(destination_value!=Vector2i(-1,-1),"atomic comparison has a legal move")
	if destination_value==Vector2i(-1,-1):return finish()
	check(ordinary.set_actor_action(hero,"MOVE",[destination_value.x,
		destination_value.y]).accepted,"ordinary solo draft accepted")
	var ordinary_result:Dictionary=ordinary.commit_turn()
	var atomic_result:Dictionary=atomic.commit_direct_solo_action(hero,"MOVE",
		[destination_value.x,destination_value.y])
	check(ordinary_result.accepted and atomic_result.accepted,"both solo commits accepted")
	check_eq(atomic.sim.snapshot(),ordinary.sim.snapshot(),
		"atomic direct action preserves exact authoritative state")
	check_eq(atomic.command_journal,ordinary.command_journal,
		"atomic direct action preserves exact replay journal")
	var restored=Session.new(1,2)
	check(restored.load_session_json(atomic.save_session_json()).accepted,
		"atomic direct action save replays")
	check_eq(restored.sim.snapshot(),atomic.sim.snapshot(),"atomic replay remains exact")
	return finish()


func test_party_rejection_feedback_preserves_draft_busy_dormant_and_conflict_details() -> bool:
	var draft = _engaged_with_companions([]); var draft_state = draft.sim.world.party_encounter
	var dormant = draft_state.party_member_ids[1]
	_check_rejection_noop(draft, func(): return draft.preview_actor_action(dormant,"HOLD"),
		"turn_draft_required", "동료를 지시하려면 먼저 주인공 행동을 선택하세요.", "draft")
	check(draft.begin_turn(Action.hold(draft_state.protagonist_id)).accepted,"solo hero draft")
	var dormant_before: Dictionary = draft.current_turn_preview()
	var dormant_result = draft.set_actor_action(dormant,"HOLD")
	check_eq(dormant_result.reason,"override_actor_not_deployed","dormant exact reason")
	check_eq(dormant_result.reason_code,"override_actor_not_deployed","dormant reason code")
	check("예비 동료" in dormant_result.message and not "override_actor_not_deployed" in dormant_result.message,
		"dormant Korean hides raw token")
	check_eq(dormant_result.reason_details.actor_id,dormant,"dormant actor detail")
	check_eq(dormant_result.reason_details.presence,"DORMANT","dormant presence detail")
	check_eq(draft.current_turn_preview().canonical_request,dormant_before.canonical_request,"dormant rejection restores overrides")

	var busy = _engaged_with_companions([1]); var busy_state = busy.sim.world.party_encounter
	var busy_actor = busy_state.party_member_ids[1]
	busy_state.member(busy_actor).busy_until = busy.sim.world.world_time + 37
	check(busy.begin_turn(Action.hold(busy_state.protagonist_id)).accepted,"busy hero draft")
	var busy_result = busy.set_actor_action(busy_actor,"HOLD")
	check_eq(busy_result.reason,"party_actor_busy","busy exact reason")
	check_eq(busy_result.reason_details.remaining_time,37,"busy remaining time")
	check("37 시간 남음" in busy_result.message,"busy Korean remaining time")
	check(busy_result.visual_effects.is_empty(),"busy rejection has no effects")

	var conflict = _engaged_with_companions([1]); var conflict_state = conflict.sim.world.party_encounter
	var companion = conflict_state.party_member_ids[1]; conflict.sim.world.entities[companion].position = Vector2i(9,7)
	check(conflict.begin_turn(Action.move_to(conflict_state.protagonist_id,Vector2i(8,7))).accepted,"conflict hero move")
	var before_conflict := JSON.stringify(conflict.sim.snapshot())
	var conflict_result = conflict.set_actor_action(companion,"MOVE",[8,7])
	check_eq(conflict_result.reason,"destination_conflict","conflict exact reason")
	check_eq(conflict_result.reason_details.conflict_destination,[8,7],"conflict destination detail")
	check_eq(conflict_result.reason_details.conflicting_actor_ids,
		[conflict_state.protagonist_id,companion],"conflict actor IDs")
	check("같은 칸" in conflict_result.message and not "destination_conflict" in conflict_result.message,
		"conflict Korean hides raw token")
	check_eq(JSON.stringify(conflict.sim.snapshot()),before_conflict,"conflict preview world no-op")
	return finish()


func test_committed_results_project_detached_visual_effects_only_from_events() -> bool:
	var session = _engaged_with_companions([], 2); var state = session.sim.world.party_encounter
	var hero = state.protagonist_id; var enemy = state.enemy_ids[0]
	check(_relocate_with_move_events(session.sim,enemy,
		session.sim.world.entities[hero].position+Vector2i.RIGHT),"effect enemy canonical relocation")
	var preview = session.begin_turn(Action.melee(hero,enemy))
	check(preview.accepted and preview.visual_effects.is_empty(),"preview never predicts visual effects")
	var committed = session.commit_turn(); check(committed.accepted,"damage turn committed: %s" % str(committed))
	if not committed.accepted:
		return finish()
	var hero_effects: Array = committed.visual_effects.filter(func(row):return int(row.instigator_id)==hero)
	var all_orders: Array = committed.visual_effects.map(func(row):return int(row.order))
	check_eq(all_orders,range(committed.visual_effects.size()),"all effects retain committed event traversal order")
	var previous_event_index := -1
	for effect in committed.visual_effects:
		var event_index: int = committed.event_ids.find(int(effect.event_id))
		check(event_index >= previous_event_index,"effect events follow result event order")
		previous_event_index = event_index
	check_eq(hero_effects.map(func(row):return row.kind),
		["MELEE_VFX","FLOATING_AMOUNT"],"nonlethal event effects exact order")
	check(hero_effects[0].order < hero_effects[1].order,
		"effect order stable")
	check_eq(hero_effects[1].cause_id,hero_effects[0].event_id,"damage cites melee action")
	check_eq(hero_effects[1].text,"-22","floating applied amount")
	check_eq(hero_effects[1].world_position,
		[session.sim.world.entities[enemy].position.x,session.sim.world.entities[enemy].position.y],"hit world position")
	check_eq(hero_effects[0].target_grid_pos,hero_effects[1].world_position,
		"melee overlay and damage amount share the exact canonical target")
	var effect_ids: Array = committed.visual_effects.map(func(row):return row.effect_id)
	var unique_ids: Dictionary = {}; for effect_id in effect_ids: unique_ids[effect_id]=true
	check_eq(unique_ids.size(),effect_ids.size(),"effect IDs dedupe-safe")
	var snapshot_after: Dictionary = session.sim.snapshot(); var first_event_id := int(hero_effects[0].event_id)
	hero_effects[0].attacker_grid_pos[0] = 999
	check_eq(session.sim.snapshot(),snapshot_after,"effect DTO mutation cannot touch core")
	check(session.sim.world.event_by_id(first_event_id).position.x != 999,"effect DTO has no event reference")
	check(session.commit_turn().visual_effects.is_empty(),"rejected commit has no effects")

	var lethal = _engaged_with_companions([], 44); var lethal_state = lethal.sim.world.party_encounter
	var lethal_hero = lethal_state.protagonist_id; var lethal_enemy = lethal_state.enemy_ids[0]
	check(_relocate_with_move_events(lethal.sim,lethal_enemy,
		lethal.sim.world.entities[lethal_hero].position+Vector2i.RIGHT),"lethal enemy canonical relocation")
	lethal.sim.world.entities[lethal_enemy].health = 20
	check(lethal.begin_turn(Action.melee(lethal_hero,lethal_enemy)).accepted,"lethal preview")
	var lethal_result = lethal.commit_turn(); check(lethal_result.accepted,"lethal commit")
	check_eq(lethal_result.visual_effects.map(func(row):return row.kind),
		["MELEE_VFX","FLOATING_AMOUNT","HIT_FLASH","FLOATING_AMOUNT","DEATH"],
		"BLEEDOUT death projects once after physical and downed-pressure effects")
	var death_effect:Dictionary=lethal_result.visual_effects[-1]
	var death_cell:Dictionary={}
	for cell in lethal.observe_party_world().cells:
		if cell.position==death_effect.world_position:death_cell=cell;break
	check(not death_cell.is_empty() and str(death_cell.ground_mark_id)=="blood_pool",
		"a killed monster leaves a persistent blood pool in world observation")
	return finish()


func test_combat_preview_guard_enemy_forecast_and_miss_feedback_are_pure_and_authoritative() -> bool:
	var session=_engaged_with_companions([],44);var state=session.sim.world.party_encounter
	var hero:=int(state.protagonist_id);var enemy:=int(state.enemy_ids[0])
	check(_relocate_with_move_events(session.sim,enemy,
		session.sim.world.entities[hero].position+Vector2i.RIGHT),"preview enemy adjacent")
	var wire_before:String=session.save_session_json();var journal_before:Array=session.command_journal.duplicate(true)
	var preview:Dictionary=session.preview_actor_action(hero,"MELEE",[],enemy)
	check(preview.accepted,"adjacent melee preview accepted")
	var selected:Variant=preview.get("selected_action_preview",null)
	check(selected is Dictionary and selected.get("attack_preview",null) is Dictionary,
		"selected attack preview DTO is exposed")
	if selected is Dictionary and selected.get("attack_preview",null) is Dictionary:
		var attack_preview:Dictionary=selected.attack_preview
		check_eq([attack_preview.hit_chance_percent,attack_preview.damage_on_hit,
			attack_preview.bleed_chance_percent],[95,22,60],
			"preview reuses canonical hit and damage assessment")
		check(not attack_preview.has("hit_roll_milli") and not attack_preview.has("bleed_roll_milli"),
			"preview never resolves or exposes deterministic RNG rolls")
	check_eq([session.save_session_json(),session.command_journal],[wire_before,journal_before],
		"attack preview is snapshot journal and RNG pure")
	check(session.begin_turn(Action.melee(hero,enemy)).accepted,"melee draft accepted")
	check("명중 95%" in "\n".join(session.turn_summary_lines()) \
		and "적중 시 22 피해" in "\n".join(session.turn_summary_lines()),
		"mobile turn summary exposes hit chance and on-hit damage")
	var forecast_wire:String=session.save_session_json();var forecasts:Array=session.enemy_intent_forecasts()
	check_eq(forecasts.size(),1,"one visible enemy exposes one current forecast")
	if not forecasts.is_empty():
		var forecast:Dictionary=forecasts[0]
		var authority:Dictionary=session.sim.party_coordinator.forecast_enemy_action(enemy)
		check_eq([forecast.type,forecast.target_id,forecast.destination],
			[authority.action_type,authority.target_id,authority.destination],
			"enemy presentation consumes the canonical shared selector")
		check_eq([forecast.type,forecast.target_id],["MELEE",hero],
			"adjacent enemy forecast names its melee target")
		check("공격 범위" in str(forecast.reason),"enemy forecast gives a short Korean reason")
		forecast.destination[0]=999;forecast.reason="변조"
		check(session.enemy_intent_forecasts()[0].destination[0]!=999 \
			and session.enemy_intent_forecasts()[0].reason!="변조",
			"enemy forecast DTO is detached")
	check_eq(session.save_session_json(),forecast_wire,"enemy forecast is world journal and RNG pure")
	check(session.begin_turn(Action.hold(hero)).accepted,"HOLD wire remains a legal canonical draft")
	var hold:Variant=session.party_cards()[0].expected_action
	check(hold is Dictionary and hold.type=="HOLD" and hold.type_label=="방어",
		"internal HOLD is presented as defense")
	check("25%" in str(hold.reason) and "200 시간" in str(hold.reason),
		"defense preview exposes effect and duration")
	check_eq(session.current_turn_preview().canonical_request.protagonist_action.type,"HOLD",
		"presentation rename does not alter action wire")
	var guarded_result:Dictionary=session.commit_turn()
	check(guarded_result.accepted,"defense turn commits")
	var hero_hold_event=null;var resolved_enemy_action=null
	for event_id in guarded_result.event_ids:
		var event=session.sim.world.event_by_id(int(event_id))
		if event==null:continue
		if str(event.type)=="action.hold" and int(event.actor_id)==hero:hero_hold_event=event
		if str(event.type)=="action.melee_attack" and int(event.actor_id)==enemy:
			resolved_enemy_action=event
	check(hero_hold_event!=null,"HOLD still commits the canonical guard event")
	check(resolved_enemy_action!=null and int(resolved_enemy_action.target_id)==hero,
		"unchanged state resolves the forecast enemy action and target")
	if resolved_enemy_action!=null:
		check(bool(resolved_enemy_action.data.get("guarded",false)) \
			and int(resolved_enemy_action.data.get("guard_reduction",0))==3,
			"enemy resolution consumes the existing 25 percent guard authority")

	var missed=_engaged_with_companions([],20);var missed_state=missed.sim.world.party_encounter
	var missed_hero:=int(missed_state.protagonist_id);var missed_enemy:=int(missed_state.enemy_ids[0])
	check(_relocate_with_move_events(missed.sim,missed_enemy,
		missed.sim.world.entities[missed_hero].position+Vector2i.RIGHT),"miss enemy adjacent")
	check(missed.begin_turn(Action.melee(missed_hero,missed_enemy)).accepted,"fixed miss draft")
	var committed:Dictionary=missed.commit_turn();check(committed.accepted,"fixed miss commit")
	var miss_effects:Array=committed.visual_effects.filter(func(row):
		return str(row.get("kind",""))=="MISS")
	check_eq(miss_effects.size(),1,"committed MISS projects exactly one visual cue")
	if not miss_effects.is_empty():check_eq(miss_effects[0].text,"빗나감","MISS cue is Korean")
	var log_text:=JSON.stringify(missed.combat_log(2,40))
	check("빗나갔다" in log_text and missed.sim.world.entities[missed_hero].display_name in log_text,
		"MISS combat log is Korean and attributes the attack through its cause")
	return finish()


func test_phase_presentation_state_is_detached_persistent_and_defeat_derived() -> bool:
	var initial = Session.new(); var initial_snapshot = initial.sim.snapshot()
	check_eq(initial.presentation_state().mode,"EXPLORATION","initial presentation mode")
	check_eq(initial.sim.snapshot(),initial_snapshot,"presentation projection pure")
	var engaged = _engaged_with_companions([]); var combat = engaged.presentation_state()
	check_eq(combat.mode,"COMBAT","engaged presentation mode")
	check(combat.combat_style_active and combat.banner.title=="전투 중","persistent combat banner/style")
	combat.banner.title="CORRUPTED"; combat.grid_style.tint_hex="#000000"
	check_eq(engaged.presentation_state().banner.title,"전투 중","presentation banner detached")
	check(engaged.presentation_state().grid_style.tint_hex!="#000000","presentation style detached")
	var victory=Session.new();check(_play_full_journey(victory,"WEDGE"),"victory presentation journey")
	var victory_presentation:Dictionary=victory.presentation_state()
	check_eq(victory_presentation.phase_id,"GROUPED_COMPLETE","victory presentation derives from persistent phase")
	check_eq(victory_presentation.banner.title,"승리 · 자동 재집결","persistent victory title")
	check_eq(victory_presentation.banner.tone,"VICTORY","persistent victory tone")
	check_eq(victory_presentation.grid_style.style_id,"VICTORY","persistent victory grid style")
	check_eq(victory_presentation.grid_style.border_hex,"#62d98b","persistent victory green border")
	var restored_victory=Session.new(1,2);var loaded_victory:Dictionary=restored_victory.load_session_json(victory.save_session_json())
	check(bool(loaded_victory.accepted),"victory session restores")
	check_eq(restored_victory.presentation_state(),victory_presentation,"restored victory presentation is exact and history-independent")

	var defeated = Session.new(); var defeated_state = defeated.sim.world.party_encounter
	defeated.sim.world.entities[defeated_state.protagonist_id].health=5
	check(defeated.sim.world.bootstrap_set_fire(defeated_state.group_anchor,100)!=null,"defeat fire fixture")
	check(defeated.commit_exploration(Command.wait(defeated_state.protagonist_id)).accepted,"defeat settles")
	var defeat = defeated.presentation_state()
	check_eq(defeat.mode,"DEFEAT","defeat derives from safe phase")
	check(defeat.terminal and defeat.combat_style_active and defeat.banner.title=="패배","defeat banner/style persistent")
	check_eq(defeat.banner.tone,"DEFEAT","defeat presentation tone")
	check_eq(defeat.grid_style.style_id,"DEFEAT","defeat grid style")
	check_eq(defeat.grid_style.border_hex,"#8f5367","defeat presentation border")
	return finish()


func test_exploration_route_is_exact_shortest_until_visible_hazard_requires_bounded_risk() -> bool:
	var session=Session.new();var state=session.sim.world.party_encounter
	var hero:=int(state.protagonist_id);session.sim.world.entities[state.enemy_ids[0]].position=Vector2i(14,14)
	var goal:=Vector2i(9,7)
	var shortest:Dictionary=session.find_exploration_path(hero,goal)
	check(shortest.found,"shortest route exists")
	check_eq(shortest.routing_policy,"SHORTEST_HAZARD_FREE","zero-visible-risk keeps shortest policy")
	check_eq([shortest.steps,shortest.total_cost,shortest.total_risk],[2,200,0],
		"open route keeps exact shortest/fastest totals")
	check_eq(session.find_exploration_path(hero,goal).path,shortest.path,
		"zero-risk shortest tie break is deterministic")
	var shortest_hop:Vector2i=shortest.path[1]
	check(session.sim.world.bootstrap_set_fire(shortest_hop,100)!=null,
		"visible route hazard fixture")
	var visible_risk_rows:Array=session.exploration_route_risk_rows(shortest_hop)
	var visible_party_max:=0
	for row in visible_risk_rows:visible_party_max=maxi(visible_party_max,int(row.total))
	check(visible_party_max>0,"visible fire produces positive party-max route risk: %s"%str(visible_risk_rows))
	var avoided:Dictionary=session.find_exploration_path(hero,goal)
	check(avoided.found and avoided.risk_weighted,"visible hazard enables affinity risk pass")
	check_eq(avoided.routing_policy,"VISIBLE_AFFINITY_RISK_WEIGHTED",
		"visible hazard policy is explicit")
	check(shortest_hop not in avoided.path,"visible high-risk cell is avoided")
	check(avoided.hazard_free and int(avoided.max_total_risk)==0,
		"available safe alternative has zero party-max exposure")
	check(int(avoided.steps)<=int(avoided.detour_limit_steps) \
			and int(avoided.detour_limit_steps)<=int(shortest.steps)+Session.MAX_VISIBLE_HAZARD_DETOUR_STEPS,
		"risk route detour has a hard bound")
	return finish()


func test_exploration_route_never_reads_unseen_live_hazards() -> bool:
	var session=Session.new(44,20260828,"SHOWCASE_V1")
	var state=session.sim.world.party_encounter;var hero:=int(state.protagonist_id)
	session.sim.world.entities[state.enemy_ids[0]].position=Vector2i(1,1)
	var hidden_goal:=Vector2i(13,13)
	var before:Dictionary=session.find_exploration_path(hero,hidden_goal)
	check(before.found,"hidden-cell route fixture exists")
	check(session.sim.world.bootstrap_set_fire(hidden_goal,100)!=null,"hidden fire fixture")
	var after:Dictionary=session.find_exploration_path(hero,hidden_goal)
	check_eq(after.path,before.path,"unseen live fire cannot influence selected path")
	check_eq([after.total_risk,after.max_total_risk,after.routing_policy],
		[before.total_risk,before.max_total_risk,before.routing_policy],
		"unseen live fire cannot influence risk metadata")
	for row in session.exploration_route_risk_rows(hidden_goal):
		check_eq(row.total,0,"unseen route ceiling exposes no hidden affinity risk")
	return finish()


func test_select_movement_destination_is_one_mutating_facade_in_both_modes() -> bool:
	var exploration=Session.new();var exploration_state=exploration.sim.world.party_encounter
	var hero:=int(exploration_state.protagonist_id)
	exploration.sim.world.entities[exploration_state.enemy_ids[0]].position=Vector2i(14,14)
	var route_before:Dictionary=exploration.find_exploration_path(hero,Vector2i(9,7))
	var selected:Dictionary=exploration.select_movement_destination(hero,[9,7])
	check(selected.accepted,"exploration cell selection starts canonical route")
	check_eq([exploration.sim.world.step_index,exploration.command_journal.size()],[1,1],
		"exploration selection commits exactly one existing move primitive")
	check_eq(exploration.sim.world.entities[hero].position,route_before.path[1],
		"exploration selection advances exactly the first deterministic hop")

	var combat=_engaged_with_companions([1]);var combat_state=combat.sim.world.party_encounter
	var combat_hero:=int(combat_state.protagonist_id)
	var origin:Vector2i=combat.sim.world.entities[combat_hero].position
	var destination:=Vector2i(-1,-1)
	for direction in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,
			Vector2i(1,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(-1,-1)]:
		var candidate:Vector2i=origin+direction
		if bool(combat.preview_actor_action(combat_hero,"MOVE",[candidate.x,candidate.y]).get("accepted",false)):
			destination=candidate;break
	check(destination!=Vector2i(-1,-1),"combat direct-move fixture has a legal adjacent cell")
	var before_snapshot=combat.sim.snapshot();var before_steps:int=combat.sim.world.step_index
	var combat_selected:Dictionary=combat.select_movement_destination(combat_hero,destination)
	check(combat_selected.accepted,"combat cell selection directly replaces pending action")
	check_eq(combat.sim.snapshot(),before_snapshot,"combat selection stages action without a placement mutation")
	check_eq(combat.current_turn_preview().canonical_request.protagonist_action.type,"MOVE",
		"combat selection stores the one direct MOVE draft")
	var move_projection:=false
	for row in combat.turn_intent_overlays():
		if int(row.actor_id)==combat_hero and str(row.type)=="MOVE":move_projection=true
	check(move_projection,"joined-party planning projection remains available")
	check(combat.commit_turn().accepted,"direct combat MOVE draft resolves through existing turn commit")
	check_eq(combat.sim.world.step_index,before_steps+1,"combat move resolves in one canonical batch")
	return finish()


func test_long_route_preview_is_pure_detached_and_each_call_commits_one_existing_move() -> bool:
	var session=Session.new();var state=session.sim.world.party_encounter;var hero=state.protagonist_id
	session.sim.world.entities[state.enemy_ids[0]].position=Vector2i(14,14)
	var before=session.sim.snapshot();var journal_before=session.command_journal.duplicate(true)
	var preview=session.preview_exploration_route(Vector2i(9,7))
	check(preview.accepted,"route preview accepted: %s"%str(preview))
	check_eq(session.sim.snapshot(),before,"route preview world/RNG pure")
	check_eq(session.command_journal,journal_before,"route preview journal pure")
	var authoritative=session.sim.find_path(hero,Vector2i(9,7));var authoritative_wire:Array=[]
	for position in authoritative.path:authoritative_wire.append([position.x,position.y])
	check_eq(preview.path,authoritative_wire,"weighted path exact")
	check_eq(preview.total_steps,2,"route total steps")
	check_eq(preview.total_cost,200,"route total cost")
	check_eq(preview.steps[0].member_risk_ceilings.size(),3,"all living grouped travellers have ceilings")
	var hash:=str(preview.plan_hash);preview.path[1][0]=99
	preview.steps[0].member_risk_ceilings[0].total=999
	var fresh=session.exploration_route_draft()
	check_eq(fresh.path[1],authoritative_wire[1],"route nested path detached")
	check(fresh.steps[0].member_risk_ceilings[0].total!=999,"route nested risks detached")
	var started=session.start_exploration_route(Vector2i(9,7),hash)
	check(started.accepted and started.active and not started.terminal,"start advances one and remains active")
	check_eq(session.sim.world.entities[hero].position,
		Vector2i(int(authoritative_wire[1][0]),int(authoritative_wire[1][1])),"start exactly one cell")
	check_eq(session.sim.world.step_index,1,"start exactly one core step")
	check_eq(session.sim.world.world_time,100,"start exact first cost")
	check_eq(session.command_journal.size(),1,"start one existing journal row")
	check_eq(session.command_journal[0].kind,"exploration","no route journal kind")
	check_eq(int(session.command_journal[0].command.type),int(Command.Type.MOVE),"journal primitive move")
	check_eq(started.completed_steps,1,"started cursor")
	var event_moves:=0
	for event in session.sim.world.events:
		if event.type=="action.move" and event.actor_id==hero:event_moves+=1
	check_eq(event_moves,1,"one action.move after one facade call")
	started.path[0][0]=999
	check(session.exploration_route_state().path[0][0]!=999,"active route result detached")
	var completed=session.continue_exploration_route()
	check(completed.accepted and completed.completed and completed.terminal,"second call completes")
	check_eq(session.sim.world.entities[hero].position,Vector2i(9,7),"continue exactly next cell")
	check_eq(session.sim.world.step_index,2,"continue exactly one more core step")
	check_eq(session.sim.world.world_time,200,"route exact accumulated timing")
	check_eq(session.command_journal.size(),2,"one journal row per hop")
	check_eq(session.continue_exploration_route().stop_reason,"route_completed","terminal state stable")
	return finish()


func test_long_route_stops_on_contact_blocker_risk_stale_death_and_combat() -> bool:
	var contact=Session.new();var contact_state=contact.sim.world.party_encounter
	var contact_preview=contact.preview_exploration_route(Vector2i(10,7))
	var contact_result=contact.start_exploration_route(Vector2i(10,7),str(contact_preview.plan_hash))
	check(contact_result.accepted and contact_result.terminal,"contact hop stays accepted")
	check_eq(contact_result.stop_reason,"route_contact","contact exact stop")
	check_eq(contact.party_status().safe_phase,"CONTACT","contact authoritative phase")
	check_eq(contact.command_journal.size(),1,"contact keeps accepted partial hop")

	var blocked=Session.new();var blocked_state=blocked.sim.world.party_encounter
	var blocked_enemy=blocked_state.enemy_ids[0];blocked.sim.world.entities[blocked_enemy].position=Vector2i(14,14)
	var blocked_preview=blocked.preview_exploration_route(Vector2i(10,7))
	check(blocked.start_exploration_route(Vector2i(10,7),str(blocked_preview.plan_hash)).active,"block fixture first hop")
	var blocked_route=blocked.exploration_route_state();var blocked_next:Array=blocked_route.path[2]
	blocked.sim.world.entities[blocked_enemy].position=Vector2i(int(blocked_next[0]),int(blocked_next[1]))
	var before_blocked=blocked.sim.snapshot();var blocker_result=blocked.continue_exploration_route()
	check_eq(blocker_result.reason,"move_destination_occupied","new blocker exact authority reason")
	check(not blocker_result.accepted and blocker_result.terminal,"blocker stops before failing hop")
	check_eq(blocked.sim.snapshot(),before_blocked,"blocked failing hop exact no-op")
	check_eq(blocked.command_journal.size(),1,"blocker preserves only accepted prefix")

	var risky=Session.new();var risky_state=risky.sim.world.party_encounter
	risky.sim.world.entities[risky_state.enemy_ids[0]].position=Vector2i(14,14)
	var risky_preview=risky.preview_exploration_route(Vector2i(10,7))
	check(risky.start_exploration_route(Vector2i(10,7),str(risky_preview.plan_hash)).active,"risk fixture first hop")
	var risky_route=risky.exploration_route_state();var risky_next:Array=risky_route.path[2]
	var next_tile=risky.sim.world.tile_at(Vector2i(int(risky_next[0]),int(risky_next[1])));next_tile.fire=100
	var before_risk=risky.sim.snapshot();var risk_result=risky.continue_exploration_route()
	check_eq(risk_result.reason,"route_hazard_increased","risk ceiling exact stop")
	check_eq(risky.sim.snapshot(),before_risk,"risk stop exact no-op")
	check_eq(risky.command_journal.size(),1,"risk preserves accepted prefix")

	# A first hop may itself spread an element onto the following cell. That
	# changed world is already represented by the post-hop resume fingerprint, so
	# the immediate frozen step must still be compared before a fingerprint fast
	# path accepts it.
	var spread=Session.new();var spread_state=spread.sim.world.party_encounter
	spread.sim.world.entities[spread_state.enemy_ids[0]].position=Vector2i(14,14)
	var spread_preview=spread.preview_exploration_route(Vector2i(10,7))
	check(spread.start_exploration_route(Vector2i(10,7),str(spread_preview.plan_hash)).active,
		"post-hop spread fixture first hop")
	var spread_route=spread.exploration_route_state();var spread_next:Array=spread_route.path[2]
	spread.sim.world.tile_at(Vector2i(int(spread_next[0]),int(spread_next[1]))).fire=100
	spread._exploration_route._active["resume_fingerprint"]=JSON.stringify(
		spread.sim.snapshot()).sha256_text()
	var spread_before=spread.sim.snapshot();var spread_result=spread.continue_exploration_route()
	check_eq(spread_result.reason,"route_hazard_increased",
		"post-hop spread cannot be hidden by the new resume fingerprint")
	check_eq(spread.sim.snapshot(),spread_before,"post-hop spread stop exact no-op")

	var stale=Session.new();var stale_state=stale.sim.world.party_encounter
	stale.sim.world.entities[stale_state.enemy_ids[0]].position=Vector2i(14,14)
	var stale_preview=stale.preview_exploration_route(Vector2i(9,7))
	stale_state.member(stale_state.party_member_ids[1]).stress=1
	var before_stale=stale.sim.snapshot();var stale_result=stale.start_exploration_route(Vector2i(9,7),str(stale_preview.plan_hash))
	check_eq(stale_result.reason,"route_stale","unrelated world mutation stales plan")
	check_eq(stale.sim.snapshot(),before_stale,"stale start no-op")
	check(stale.command_journal.is_empty(),"stale start no journal")

	var defeated=Session.new();var defeated_state=defeated.sim.world.party_encounter
	defeated.sim.world.entities[defeated_state.protagonist_id].health=5
	var lethal_cell:=Vector2i(8,7)
	check(defeated.sim.world.bootstrap_set_fire(lethal_cell,100)!=null,"route defeat fire")
	var defeat_preview=defeated.preview_exploration_route(lethal_cell)
	var defeat_result=defeated.start_exploration_route(lethal_cell,str(defeat_preview.plan_hash))
	check(defeat_result.accepted and defeat_result.terminal,"lethal accepted hop terminal")
	check_eq(defeat_result.stop_reason,"route_party_defeated","death exact stop")
	check_eq(defeated.party_status().safe_phase,"PARTY_DEFEATED","death authoritative phase")

	var combat=_engaged_with_companions([]);var combat_before=combat.sim.snapshot()
	var combat_route=combat.preview_exploration_route(Vector2i(1,1))
	check_eq(combat_route.reason,"route_exploration_phase_required","combat long route rejected")
	check_eq(combat.sim.snapshot(),combat_before,"combat route rejection no-op")

	var diagonal=Session.new();var diagonal_state=diagonal.sim.world.party_encounter
	diagonal.sim.world.entities[diagonal_state.enemy_ids[0]].position=Vector2i(14,14)
	var diagonal_preview=diagonal.preview_exploration_route(Vector2i(9,5))
	var diagonal_first:=Vector2i(int(diagonal_preview.path[1][0]),int(diagonal_preview.path[1][1]))
	check(absi(diagonal_first.x-7)==1 and absi(diagonal_first.y-7)==1,"diagonal fixture first edge")
	var flank:=Vector2i(diagonal_first.x,7)
	check(diagonal.sim.world.bootstrap_set_terrain(flank,"wall"),"new diagonal flank wall")
	var diagonal_before=diagonal.sim.snapshot()
	var diagonal_result=diagonal.start_exploration_route(Vector2i(9,5),str(diagonal_preview.plan_hash))
	check_eq(diagonal_result.reason,"move_diagonal_flank_blocked","diagonal blockage exact stop")
	check_eq(diagonal.sim.snapshot(),diagonal_before,"diagonal failing hop no-op")

	var failed=Session.new();var failed_state=failed.sim.world.party_encounter
	var failed_preview=failed.preview_exploration_route(Vector2i(10,7))
	failed.sim.party_coordinator.fail_point="contact_event"
	var failed_before=failed.sim.snapshot();var failed_result=failed.start_exploration_route(
		Vector2i(10,7),str(failed_preview.plan_hash))
	check(not failed_result.accepted,"route cadence failure rejected")
	check_eq(failed_result.reason,"actor_tick_failed","route preserves atomic core failure")
	check_eq(failed.sim.snapshot(),failed_before,"failed hop full rollback")
	check(failed.command_journal.is_empty(),"failed hop no journal")
	return finish()


func test_long_route_ephemeral_state_load_and_direct_command_contracts() -> bool:
	var source=Session.new();check(_play_full_journey(source,"WEDGE"),"route load canonical journey")
	var hero=source.sim.world.party_encounter.protagonist_id
	var origin:Vector2i=source.sim.world.entities[hero].position
	var goal:=origin+Vector2i(2,0)
	if goal.x>=source.sim.world.width:goal=origin-Vector2i(2,0)
	var preview=source.preview_exploration_route(goal)
	check(preview.accepted,"post-regroup route preview")
	var partial=source.start_exploration_route(goal,str(preview.plan_hash))
	check(partial.accepted and partial.active,"post-regroup one-hop partial")
	var restored=Session.new(1,2);var loaded=restored.load_session_json(source.save_session_json())
	check(loaded.accepted,"partial route save load accepted")
	check_eq(restored.sim.snapshot(),source.sim.snapshot(),"accepted hop journal replays exactly")
	check_eq(restored.exploration_route_state().reason,"route_preview_required","valid load clears ephemeral route")

	var target=Session.new();target.sim.world.entities[target.sim.world.party_encounter.enemy_ids[0]].position=Vector2i(14,14)
	var target_preview=target.preview_exploration_route(Vector2i(10,7))
	check(target.start_exploration_route(Vector2i(10,7),str(target_preview.plan_hash)).active,"invalid load target active")
	var route_before=target.exploration_route_state();var world_before=target.sim.snapshot()
	var malformed=JSON.parse_string(source.save_session_json());malformed["extra"]=true
	check(not target.load_session_json(JSON.stringify(malformed)).accepted,"invalid load rejected")
	check_eq(target.sim.snapshot(),world_before,"invalid load preserves active world")
	check_eq(target.exploration_route_state(),route_before,"invalid load preserves ephemeral route transactionally")
	var direct=target.commit_exploration(Command.wait(target.sim.world.party_encounter.protagonist_id))
	check(direct.accepted,"direct command remains supported")
	check_eq(target.exploration_route_state().reason,"route_preview_required","direct command cancels route")
	return finish()


func test_structured_combat_log_keeps_companion_cause_attribution_and_replays() -> bool:
	var session=Session.new(1);var state=session.sim.world.party_encounter;var hero=state.protagonist_id
	check(session.commit_exploration(Command.wait(hero)).accepted,"log contact")
	check(session.preview_deployment("LINE",[state.party_member_ids[1]]).accepted,"log deploy preview")
	check(session.commit_deployment().accepted,"log deploy")
	state=session.sim.world.party_encounter;var companion=state.party_member_ids[1]
	var enemy_id: int = state.enemy_ids[0]
	var finisher_previewed := false; var finisher_committed := false
	var finisher_commit_event_ids: Array = []
	for turn in range(20):
		if session.party_status().safe_phase!="ENGAGED":break
		var enemy_downed: bool = session.sim.world.combatant_states[enemy_id].life_state == "DOWNED"
		var hero_position: Vector2i = session.sim.world.entities[hero].position
		var enemy_position: Vector2i = session.sim.world.entities[enemy_id].position
		var distance := maxi(absi(hero_position.x-enemy_position.x),
			absi(hero_position.y-enemy_position.y))
		var preview: Dictionary = {"accepted":false}
		var finisher_this_turn := false
		if enemy_downed and distance == 1:
			preview = session.set_actor_action(hero,"MELEE",[],enemy_id)
			check(bool(preview.get("accepted",false)),"fresh explicit finisher preview %d"%turn)
			var hero_row: Dictionary = {}
			var autonomous_companion_melee: Array = []
			for row in preview.get("actor_rows",[]):
				if int(row.get("actor_id",-1)) == hero: hero_row = row
				if int(row.get("actor_id",-1)) == companion \
						and str(row.get("action",{}).get("type","")) == "MELEE":
					autonomous_companion_melee.append(row)
			check(not hero_row.is_empty() and str(hero_row.get("action",{}).get("type","")) == "MELEE" \
				and int(str(hero_row.get("action",{}).get("target_id","-1"))) == enemy_id,
				"facade exposes fresh hero target action")
			var combat_assessment: Variant = hero_row.get("combat_assessment")
			check(combat_assessment is Dictionary \
				and str(combat_assessment.get("intent_mode","")) == "FINISHER" \
				and str(combat_assessment.get("target_life_state","")) == "DOWNED",
				"facade exposes explicit FINISHER assessment")
			check(autonomous_companion_melee.is_empty(),
				"autonomous companion does not select DOWNED target")
			finisher_this_turn = bool(preview.get("accepted",false))
			finisher_previewed = finisher_previewed or finisher_this_turn
		elif enemy_downed and distance > 1:
			var ranked_paths: Array = []
			for direction in [Vector2i.UP,Vector2i(1,-1),Vector2i.RIGHT,
					Vector2i(1,1),Vector2i.DOWN,Vector2i(-1,1),Vector2i.LEFT,
					Vector2i(-1,-1)]:
				var adjacent: Vector2i = enemy_position + direction
				if not session.sim.world.in_bounds(adjacent) \
						or session.sim.world.blocking_entity_at(adjacent,hero) != null:
					continue
				var candidate: Dictionary = session.sim.find_path(hero,adjacent)
				if bool(candidate.get("found",false)) and candidate.get("path",[]).size()>1:
					ranked_paths.append({"path":candidate.path,
						"cost":int(candidate.total_cost),"steps":int(candidate.steps),
						"goal":adjacent})
			ranked_paths.sort_custom(func(a:Dictionary,b:Dictionary):
				if int(a.cost)!=int(b.cost):return int(a.cost)<int(b.cost)
				if int(a.steps)!=int(b.steps):return int(a.steps)<int(b.steps)
				var ag:Vector2i=a.goal;var bg:Vector2i=b.goal
				return ag.y<bg.y if ag.y!=bg.y else ag.x<bg.x)
			check(not ranked_paths.is_empty(),"DOWNED target has a reachable adjacent cell")
			if not ranked_paths.is_empty():
				var destination: Vector2i = ranked_paths[0].path[1]
				preview = session.begin_turn(Action.move_to(hero,destination))
			check(bool(preview.get("accepted",false)),
				"hero facade approach MOVE preview %d"%turn)
			var approach_row: Dictionary = {}
			var downed_companion_melee: Array = []
			for row in preview.get("actor_rows",[]):
				if int(row.get("actor_id",-1)) == hero: approach_row = row
				if enemy_downed and int(row.get("actor_id",-1)) == companion \
						and str(row.get("action",{}).get("type","")) == "MELEE":
					downed_companion_melee.append(row)
			check(not approach_row.is_empty() \
				and str(approach_row.get("action",{}).get("type","")) == "MOVE",
				"hero approaches through exact facade MOVE row")
			if enemy_downed:
				check(downed_companion_melee.is_empty(),
					"autonomous companion excludes DOWNED target during hero approach")
		else:
			preview = session.begin_turn(Action.hold(hero))
			check(bool(preview.get("accepted",false)),"automatic combat draft %d"%turn)
		# This test owns cause attribution, not a promise that a frightened companion
		# will always choose aggression. When adjacent, explicitly commit that attack
		# through the public override facade so P3 panic behavior remains free to
		# retreat in autonomous turns.
		if not enemy_downed and session.sim.melee.can_attack(companion,enemy_id):
			var companion_override: Dictionary = session.override_companion(
				companion,Action.melee(companion,enemy_id))
			check(bool(companion_override.get("accepted",false)),
				"companion attribution override %d"%turn)
		elif not enemy_downed:
			var companion_paths: Array = []
			for direction in [Vector2i.UP,Vector2i(1,-1),Vector2i.RIGHT,
					Vector2i(1,1),Vector2i.DOWN,Vector2i(-1,1),Vector2i.LEFT,
					Vector2i(-1,-1)]:
				var adjacent: Vector2i = enemy_position + direction
				if not session.sim.world.in_bounds(adjacent) \
						or session.sim.world.blocking_entity_at(adjacent,companion) != null:
					continue
				var candidate: Dictionary = session.sim.find_path(companion,adjacent)
				if bool(candidate.get("found",false)) and candidate.get("path",[]).size()>1:
					companion_paths.append({"path":candidate.path,
						"cost":int(candidate.total_cost),"steps":int(candidate.steps),
						"goal":adjacent})
			companion_paths.sort_custom(func(a:Dictionary,b:Dictionary):
				if int(a.cost)!=int(b.cost):return int(a.cost)<int(b.cost)
				if int(a.steps)!=int(b.steps):return int(a.steps)<int(b.steps)
				var ag:Vector2i=a.goal;var bg:Vector2i=b.goal
				return ag.y<bg.y if ag.y!=bg.y else ag.x<bg.x)
			check(not companion_paths.is_empty(),"live target has a companion approach path")
			if not companion_paths.is_empty():
				var destination: Vector2i = companion_paths[0].path[1]
				var companion_override: Dictionary = session.override_companion(
					companion,Action.move_to(companion,destination))
				check(bool(companion_override.get("accepted",false)),
					"companion attribution approach override %d"%turn)
		var committed: Dictionary = session.commit_turn()
		check(bool(committed.get("accepted",false)),"automatic combat commit %d"%turn)
		if enemy_downed and bool(committed.get("accepted",false)):
			for event_id in committed.get("event_ids",[]):
				var event = session.sim.world.event_by_id(int(event_id))
				check(event == null or event.actor_id != enemy_id \
					or not event.type.begins_with("action."),
					"DOWNED enemy emits no autonomous action during fresh hero resolution")
		if finisher_this_turn and bool(committed.get("accepted",false)):
			finisher_committed = true
			finisher_commit_event_ids = committed.get("event_ids",[]).duplicate()
	check_eq(session.party_status().safe_phase,"GROUPED_COMPLETE","structured log fixture wins")
	check(finisher_previewed and finisher_committed,
		"DOWNED enemy is finished through a fresh facade turn")
	var log=session.combat_log(8,80)
	check(log.groups is Array and log.row_count>0,"grouped combat log populated")
	var rows:Array=[]
	for group in log.groups:rows.append_array(group.rows)
	check_eq(int(log.row_count),rows.size(),"important log row_count matches retained rows")
	check_eq(int(log.group_count),log.groups.size(),"important log group_count matches nonempty steps")
	for row in rows:
		check(str(row.type) not in ["action.move","action.wait","action.hold"],
			"routine movement/wait/hold is absent from log DTO")
		check(str(row.message)!="세계에 변화가 일어났다.",
			"unknown fallback copy is absent from log DTO")
	var companion_melee:Dictionary={};var attributed_damage:Dictionary={}
	var finisher_melee:Dictionary={};var finisher_pressure:Dictionary={};var attributed_death:Dictionary={}
	for row in rows:
		if row.type=="action.melee_attack" and int(row.actor_id)==companion:companion_melee=row
		if str(row.type).begins_with("combat.") and int(row.instigator_id)==companion:attributed_damage=row
		if row.type=="action.melee_attack" and int(row.actor_id)==hero \
				and str(row.data.get("outcome",""))=="FINISHER":finisher_melee=row
		if row.type=="combat.downed_damage" and int(row.instigator_id)==hero:finisher_pressure=row
		if row.type=="entity.died" and int(row.target_id)==enemy_id:attributed_death=row
	check(not companion_melee.is_empty(),"companion melee retained")
	check(not attributed_damage.is_empty(),"companion damage attributed")
	if not attributed_damage.is_empty() and not companion_melee.is_empty():
		check_eq(int(attributed_damage.cause_id),int(companion_melee.event_id),"damage exact melee cause")
		check("나래의 공격으로" in str(attributed_damage.message),"Korean damage attribution")
	check(not finisher_melee.is_empty() and int(finisher_melee.event_id) in finisher_commit_event_ids,
		"committed facade turn exposes explicit FINISHER event")
	check(not finisher_pressure.is_empty(),"hero finisher pressure attribution retained")
	if not finisher_pressure.is_empty() and not finisher_melee.is_empty():
		check_eq(int(finisher_pressure.cause_id),int(finisher_melee.event_id),
			"finisher pressure exact melee cause")
	check(not attributed_death.is_empty(),"explicit finisher death retained through regroup")
	if not attributed_death.is_empty() and not finisher_pressure.is_empty():
		check_eq(int(attributed_death.cause_id),int(finisher_pressure.event_id),
			"death exact finisher pressure cause")
		check_eq(int(attributed_death.instigator_id),hero,"final death attribution is hero finisher")
	check_eq(session.combat_log(0,80).groups,[],"zero turns returns zero groups")
	var detached=session.combat_log();detached.groups[0].rows[0].data["corrupted"]=true
	check(not session.combat_log().groups[0].rows[0].data.has("corrupted"),"combat log nested DTO detached")
	var restored=Session.new(1,2);check(restored.load_session_json(session.save_session_json()).accepted,"combat log load")
	check_eq(restored.combat_log(8,80),log,"combat log/cause/order exact after replay")

	var overkill=_engaged_with_companions([1]);var overkill_state=overkill.sim.world.party_encounter
	var overkill_enemy=overkill_state.enemy_ids[0];var overkill_hero=overkill_state.protagonist_id
	var overkill_companion=overkill_state.party_member_ids[1]
	check(_relocate_with_move_events(overkill.sim,overkill_enemy,
		overkill.sim.world.entities[overkill_hero].position+Vector2i.RIGHT),"overkill canonical enemy relocation")
	overkill.sim.world.entities[overkill_enemy].health=10
	check(overkill.begin_turn(Action.melee(overkill_hero,overkill_enemy)).accepted,"overkill automatic draft")
	var overkill_result=overkill.commit_turn()
	check(overkill_result.accepted,"overkill automatic commit: %s"%str(overkill_result))
	var overkill_rows:Array=[]
	for group in overkill.combat_log(1,80).groups:overkill_rows.append_array(group.rows)
	var melee_count:=0;var companion_intent_count:=0;var damage_count:=0;var death_count:=0
	for row in overkill_rows:
		if row.type=="action.melee_attack" and int(row.actor_id) in [overkill_hero,overkill_companion]:melee_count+=1
		if row.type=="action.melee_attack" and int(row.actor_id)==overkill_companion:companion_intent_count+=1
		if row.type=="combat.physical_damage" and int(row.target_id)==overkill_enemy:damage_count+=1
		if row.type=="entity.died" and int(row.target_id)==overkill_enemy:death_count+=1
	check_eq(melee_count,2,"both simultaneous hero/companion intents logged")
	check_eq(companion_intent_count,1,"automatic companion overkill intent retained")
	check_eq(damage_count,1,"overkill emits/logs actual damage once")
	check_eq(death_count,1,"overkill death logged once")
	return finish()


func test_tile_and_member_inspectors_are_authoritative_pure_and_deep_detached() -> bool:
	var session=Session.new();var state=session.sim.world.party_encounter
	var before=session.sim.snapshot();var journal_before=session.command_journal.duplicate(true)
	var tile=session.inspect_tile(Vector2i(0,0),state.party_member_ids[2])
	check(tile.accepted,"distant tile inspection accepted")
	check_eq(tile.position,[0,0],"tile exact position")
	check_eq(tile.terrain_id,"floor","tile terrain")
	check_eq(tile.move_time_cost,100,"tile cost")
	check_eq(tile.traversal.reason,"move_not_adjacent","distant traversal authority retained")
	check_eq(tile.viewer.species_id,"goblin","viewer species")
	check_eq(tile.affinity.species_id,"goblin","viewer affinity")
	check(tile.sample is Dictionary and tile.provenance is Dictionary,"raw sample provenance exposed")
	check_eq(session.sim.snapshot(),before,"tile inspection snapshot/RNG pure")
	check_eq(session.command_journal,journal_before,"tile inspection journal pure")
	tile.sample.source_event_ids.append("999");tile.risk.total=999
	var tile_fresh=session.inspect_tile(Vector2i(0,0),state.party_member_ids[2])
	check(not tile_fresh.sample.source_event_ids.has("999") and tile_fresh.risk.total!=999,"tile nested detached")
	var invalid_before=session.sim.snapshot();var invalid=session.inspect_tile(Vector2i(-1,0))
	check_eq(invalid.reason,"inspect_tile_out_of_bounds","tile OOB total rejection")
	check_eq(session.sim.snapshot(),invalid_before,"tile OOB no-op")

	var hero=session.inspect_party_member(state.protagonist_id)
	check(hero.accepted and hero.personality_profile==null,"protagonist null personality explicit")
	check(not hero.personality_available and not hero.personality_note.is_empty(),"protagonist null profile explained")
	check_eq(hero.core_stats.keys().size(),3,"protagonist inspection exposes three core stats")
	check(hero.combat_stats.has("attack_power") and hero.combat_stats.has("evasion_milli"),
		"protagonist inspection exposes readable combat totals")
	check(hero.body_state.available and hero.body_state.parts.size()==6,
		"protagonist inspection exposes systemic and six-part body condition")
	var companion=session.inspect_party_member(state.party_member_ids[1])
	check(companion.accepted,"companion inspection")
	check_eq(companion.personality_facets.size(),6,"all HEXACO facets")
	check_eq(companion.species_affinity.species_id,"human","species affinity")
	check_eq(companion.relation_rows.size(),2,"effective relation to other party members")
	check(companion.affinity_toward_protagonist.has("score") \
		and companion.affinity_toward_protagonist.has("label"),
		"companion inspection exposes affinity toward protagonist")
	check(companion.current_exposure.applicable,"current full exposure")
	companion.personality_facets[0].value=9999;companion.relation_rows[0].personal.gratitude=999
	var companion_fresh=session.inspect_party_member(state.party_member_ids[1])
	check(companion_fresh.personality_facets[0].value!=9999,"member personality detached")
	check(companion_fresh.relation_rows[0].personal.gratitude!=999,"member relation detached")
	check_eq(session.sim.snapshot(),before,"member inspectors snapshot/RNG pure")
	check_eq(session.command_journal,journal_before,"member inspectors journal pure")
	return finish()


func test_fov_memory_is_reconstructed_purely_from_hero_move_history_and_replays() -> bool:
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var initial:Dictionary=session.observe_party_world()
	check(bool(initial.visibility.memory_supported),"fixed solo fixture advertises terrain memory")
	check(session.commit_exploration_direction(Vector2i.RIGHT).accepted,
		"memory fixture reaches solo contact")
	check(session.enter_solo_combat().accepted,"memory fixture enters solo combat")
	check(_resolve_solo_encounter(session,32),"memory fixture clears roaming monster")
	for index in range(5):
		var moved:Dictionary=session.commit_exploration_direction(Vector2i.UP)
		check(bool(moved.get("accepted",false)),"memory fixture move %d accepted"%index)
		if not bool(moved.get("accepted",false)):break
	var snapshot_before:Dictionary=session.sim.snapshot()
	var journal_before:Array=session.command_journal.duplicate(true)
	var observed:Dictionary=session.observe_party_world()
	check_eq(session.sim.snapshot(),snapshot_before,"observe does not mutate world authority")
	check_eq(session.command_journal,journal_before,"observe does not mutate canonical journal")
	var memory_rows:Array=[];var unseen_rows:Array=[]
	for cell in observed.cells:
		if str(cell.visibility_state)=="MEMORY":memory_rows.append(cell)
		elif str(cell.visibility_state)=="UNSEEN":unseen_rows.append(cell)
	check(not memory_rows.is_empty(),"terrain leaves dim memory after moving out of FOV")
	check(not unseen_rows.is_empty(),"never-seen terrain remains unknown")
	for cell in memory_rows:
		check(str(cell.terrain_id)!="unknown" and cell.actors.is_empty(),
			"memory keeps terrain but no actors")
		check_eq([cell.feature_id,cell.fire_intensity,cell.wetness,
			cell.effective_conductivity],["",0,0,0],
			"memory leaks no feature, live hazard, or conductivity cue")
	for cell in unseen_rows:
		check_eq([cell.terrain_id,cell.feature_id,cell.actors],["unknown","",[]],
			"unseen remains identity-free")
	var second:Dictionary=session.observe_party_world()
	check_eq(second,observed,"repeated observation is exactly stable")
	var restored=Session.new(1,2)
	check(restored.load_session_json(session.save_session_json()).accepted,
		"memory fixture save loads through journal replay")
	check_eq(restored.observe_party_world(),observed,
		"save/load and journal replay reconstruct identical memory")
	return finish()


func _check_rejection_noop(session, producer: Callable, expected_reason: String,
		korean_fragment: String, label: String) -> Dictionary:
	var snapshot_before = session.sim.snapshot()
	var journal_before: Array = session.command_journal.duplicate(true)
	var result: Dictionary = producer.call()
	check(not bool(result.get("accepted",true)), "%s rejected" % label)
	check_eq(result.get("reason"),expected_reason,"%s original reason" % label)
	check_eq(result.get("reason_code"),expected_reason,"%s reason code" % label)
	check(korean_fragment in str(result.get("message","")),"%s Korean feedback" % label)
	check(not expected_reason in str(result.get("message","")),"%s raw token hidden" % label)
	check(result.get("reason_details") is Dictionary,"%s structured details" % label)
	check(result.get("visual_effects",[]).is_empty(),"%s rejection has no effects" % label)
	check_eq(session.sim.snapshot(),snapshot_before,"%s snapshot/RNG/world no-op" % label)
	check_eq(session.command_journal,journal_before,"%s journal no-op" % label)
	return result


func _engaged_with_companions(roster_slots: Array, world_seed: int = 44):
	var session = Session.new(world_seed); var state = session.sim.world.party_encounter
	var selected: Array = []
	for slot in roster_slots:
		selected.append(state.party_member_ids[int(slot)])
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,"engaged helper contact")
	check(session.preview_deployment("LINE",selected).accepted,"engaged helper deployment preview")
	check(session.commit_deployment().accepted,"engaged helper deployment commit")
	return session


func _resolve_solo_encounter(session,turn_limit:int)->bool:
	for _turn in range(turn_limit):
		var status:Dictionary=session.party_status()
		if str(status.safe_phase)=="GROUPED_COMPLETE":return true
		if str(status.safe_phase)!="ENGAGED":return false
		var hero:=int(status.protagonist_id);var hero_position:=Vector2i(-1,-1)
		for card in session.party_cards():
			if int(card.entity_id)==hero:
				hero_position=Vector2i(int(card.logical_position[0]),int(card.logical_position[1]));break
		var targets:Array=session.enemy_targets()
		if targets.is_empty():return false
		var enemy:Dictionary=targets[0]
		var enemy_position:=Vector2i(int(enemy.position[0]),int(enemy.position[1]))
		var preview:Dictionary={"accepted":false}
		if maxi(absi(hero_position.x-enemy_position.x),absi(hero_position.y-enemy_position.y))==1:
			preview=session.set_actor_action(hero,"MELEE",[],int(enemy.entity_id))
		else:
			for direction in [Vector2i(signi(enemy_position.x-hero_position.x),
					signi(enemy_position.y-hero_position.y)),
					Vector2i(signi(enemy_position.x-hero_position.x),0),
					Vector2i(0,signi(enemy_position.y-hero_position.y))]:
				if direction==Vector2i.ZERO:continue
				preview=session.set_actor_action(hero,"MOVE",
					[hero_position.x+direction.x,hero_position.y+direction.y])
				if bool(preview.get("accepted",false)):break
			if not bool(preview.get("accepted",false)):
				preview=session.set_actor_action(hero,"HOLD")
		if not bool(preview.get("accepted",false)) or not session.commit_turn().accepted:
			return false
	return str(session.party_status().safe_phase)=="GROUPED_COMPLETE"


func _relocate_with_move_events(sim, entity_id: int, target: Vector2i) -> bool:
	for attempt in range(64):
		var current: Vector2i = sim.world.entities[entity_id].position
		if current == target:
			return true
		var delta := target-current
		var direction := Vector2i(signi(delta.x),signi(delta.y))
		var destination := current+direction
		var assessment = sim.movement.assess_move(entity_id,destination)
		if not assessment.accepted:
			return false
		if sim.movement.commit_preflighted_move(entity_id,destination,str(assessment.terrain_id),100)==null:
			return false
	return false

func _play_full_journey(session, formation: String) -> bool:
	var status: Dictionary = session.party_status()
	if not session.commit_exploration_direction(Vector2i.ZERO).accepted: return false
	if not session.preview_deployment(formation, session.available_companion_ids()).accepted: return false
	if not session.commit_deployment().accepted: return false
	for index in range(20):
		status = session.party_status()
		if status.safe_phase == "GROUPED_COMPLETE": break
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
	return session.party_status().safe_phase == "GROUPED_COMPLETE"
