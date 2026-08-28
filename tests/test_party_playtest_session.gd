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
