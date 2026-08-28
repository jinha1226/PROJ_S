extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const Action=preload("res://sim/party_action_command.gd")
const Request=preload("res://sim/party_turn_request.gd")

func test_facade_dtos_are_detached_and_save_load_preserves_contact() -> bool:
	var session=Session.new(); var status=session.party_status(); status.safe_phase="CORRUPTED"
	var cards=session.party_cards(); cards[0].element_exposure.total_risk=999
	check_eq(session.party_status().safe_phase,"GROUPED","status detached")
	check_eq(session.party_status().session_format_version,2,"session v2 surface")
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

func test_full_exploration_deployment_turn_regroup_journal_replays_exactly() -> bool:
	var session = Session.new(333,444); var journey_ok := _play_full_journey(session, "COLUMN")
	check(journey_ok, "full canonical journey reached grouped complete")
	check_eq(session.party_status().safe_phase, "GROUPED_COMPLETE", "journey regrouped")
	var move = session.commit_exploration_direction(Vector2i.LEFT); check(move.accepted, "post-regroup move journaled")
	var encoded := session.save_session_json(); var decoded = JSON.parse_string(encoded)
	check_eq(decoded.keys().size(), 5, "exact session top key count")
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
	_check_rejection_noop(corner_actor,
		func(): return corner_actor.preview_exploration(Command.move_to(corner_actor_state.protagonist_id,Vector2i(6,6))),
		"move_diagonal_flank_occupied", "막은 모서리", "diagonal actor")
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
	var session = _engaged_with_companions([]); var state = session.sim.world.party_encounter
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
		["SLASH","HIT_FLASH","FLOATING_AMOUNT"],"nonlethal event effects exact order")
	check(hero_effects[0].order < hero_effects[1].order and hero_effects[1].order < hero_effects[2].order,
		"effect order stable")
	check_eq(hero_effects[1].event_id,hero_effects[2].event_id,"damage effects share event")
	check_eq(hero_effects[1].cause_id,hero_effects[0].event_id,"damage cites slash action")
	check_eq(hero_effects[2].text,"-22","floating applied amount")
	check_eq(hero_effects[1].world_position,
		[session.sim.world.entities[enemy].position.x,session.sim.world.entities[enemy].position.y],"hit world position")
	var effect_ids: Array = committed.visual_effects.map(func(row):return row.effect_id)
	var unique_ids: Dictionary = {}; for effect_id in effect_ids: unique_ids[effect_id]=true
	check_eq(unique_ids.size(),effect_ids.size(),"effect IDs dedupe-safe")
	var snapshot_after: Dictionary = session.sim.snapshot(); var first_event_id := int(hero_effects[0].event_id)
	hero_effects[0].world_position[0] = 999
	check_eq(session.sim.snapshot(),snapshot_after,"effect DTO mutation cannot touch core")
	check(session.sim.world.event_by_id(first_event_id).position.x != 999,"effect DTO has no event reference")
	check(session.commit_turn().visual_effects.is_empty(),"rejected commit has no effects")

	var lethal = _engaged_with_companions([]); var lethal_state = lethal.sim.world.party_encounter
	var lethal_hero = lethal_state.protagonist_id; var lethal_enemy = lethal_state.enemy_ids[0]
	check(_relocate_with_move_events(lethal.sim,lethal_enemy,
		lethal.sim.world.entities[lethal_hero].position+Vector2i.RIGHT),"lethal enemy canonical relocation")
	lethal.sim.world.entities[lethal_enemy].health = 20
	check(lethal.begin_turn(Action.melee(lethal_hero,lethal_enemy)).accepted,"lethal preview")
	var lethal_result = lethal.commit_turn(); check(lethal_result.accepted,"lethal commit")
	check_eq(lethal_result.visual_effects.map(func(row):return row.kind),
		["SLASH","HIT_FLASH","FLOATING_AMOUNT","DEATH"],"death projects once after damage")
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
	var lethal_path:Dictionary=defeated.sim.find_path(defeated_state.protagonist_id,Vector2i(9,7))
	var lethal_cell:Vector2i=lethal_path.path[1]
	check(defeated.sim.world.bootstrap_set_fire(lethal_cell,100)!=null,"route defeat fire")
	var defeat_preview=defeated.preview_exploration_route(Vector2i(9,7))
	var defeat_result=defeated.start_exploration_route(Vector2i(9,7),str(defeat_preview.plan_hash))
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
	var session=Session.new();var state=session.sim.world.party_encounter;var hero=state.protagonist_id
	check(session.commit_exploration(Command.wait(hero)).accepted,"log contact")
	check(session.preview_deployment("LINE",[state.party_member_ids[1]]).accepted,"log deploy preview")
	check(session.commit_deployment().accepted,"log deploy")
	state=session.sim.world.party_encounter;var companion=state.party_member_ids[1]
	for turn in range(12):
		if session.party_status().safe_phase!="ENGAGED":break
		check(session.begin_turn(Action.hold(hero)).accepted,"automatic combat draft %d"%turn)
		check(session.commit_turn().accepted,"automatic combat commit %d"%turn)
	check_eq(session.party_status().safe_phase,"GROUPED_COMPLETE","automatic companion fixture wins")
	var log=session.combat_log(8,80)
	check(log.groups is Array and log.row_count>0,"grouped combat log populated")
	var rows:Array=[]
	for group in log.groups:rows.append_array(group.rows)
	var companion_melee:Dictionary={};var attributed_damage:Dictionary={};var attributed_death:Dictionary={}
	for row in rows:
		if row.type=="action.melee_attack" and int(row.actor_id)==companion:companion_melee=row
		if str(row.type).begins_with("combat.") and int(row.instigator_id)==companion:attributed_damage=row
		if row.type=="entity.died" and int(row.instigator_id)==companion:attributed_death=row
	check(not companion_melee.is_empty(),"automatic companion melee retained")
	check(not attributed_damage.is_empty(),"automatic companion damage attributed")
	check_eq(int(attributed_damage.cause_id),int(companion_melee.event_id),"damage exact melee cause")
	check("나래의 공격으로" in str(attributed_damage.message),"Korean damage attribution")
	check(not attributed_death.is_empty(),"companion death attribution retained through regroup")
	check_eq(int(attributed_death.cause_id),int(attributed_damage.event_id),"death exact damage cause")
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
		if str(row.type).begins_with("combat.") and int(row.target_id)==overkill_enemy:damage_count+=1
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
	var companion=session.inspect_party_member(state.party_member_ids[1])
	check(companion.accepted,"companion inspection")
	check_eq(companion.personality_facets.size(),4,"all personality facets")
	check_eq(companion.species_affinity.species_id,"human","species affinity")
	check_eq(companion.relation_rows.size(),2,"effective relation to other party members")
	check(companion.current_exposure.applicable,"current full exposure")
	companion.personality_facets[0].value=9999;companion.relation_rows[0].personal.gratitude=999
	var companion_fresh=session.inspect_party_member(state.party_member_ids[1])
	check(companion_fresh.personality_facets[0].value!=9999,"member personality detached")
	check(companion_fresh.relation_rows[0].personal.gratitude!=999,"member relation detached")
	check_eq(session.sim.snapshot(),before,"member inspectors snapshot/RNG pure")
	check_eq(session.command_journal,journal_before,"member inspectors journal pure")
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


func _engaged_with_companions(roster_slots: Array):
	var session = Session.new(); var state = session.sim.world.party_encounter
	var selected: Array = []
	for slot in roster_slots:
		selected.append(state.party_member_ids[int(slot)])
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,"engaged helper contact")
	check(session.preview_deployment("LINE",selected).accepted,"engaged helper deployment preview")
	check(session.commit_deployment().accepted,"engaged helper deployment commit")
	return session


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
