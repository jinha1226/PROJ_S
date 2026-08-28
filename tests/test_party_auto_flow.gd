extends "res://tests/test_case.gd"

const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")
const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Portrait = preload("res://playtest/ascii_actor_portrait.gd")


func test_auto_contact_previews_first_formation_then_enters_placeholder_combat() -> bool:
	var session = _contact_session()
	var before: Dictionary = session.sim.snapshot()
	var journal_before: Array = session.command_journal.duplicate(true)
	var sandbox = Sandbox.new()
	sandbox.size = Vector2(450,800)
	sandbox.initialize_for_headless_test(session,true)
	var flow: Dictionary = sandbox.auto_flow_state()
	check(flow.enabled and flow.deployment_pending,"auto CONTACT queues deployment")
	check_eq(session.deployment_draft().preset_id,"WEDGE","first accepted preset is WEDGE")
	check_eq(session.sim.snapshot(),before,"deployment ghost preview is pure")
	check_eq(session.command_journal,journal_before,"deployment preview does not journal")
	check(sandbox.find_child("DeployConfirm",true,false)==null,
		"automatic ghost preview omits manual deploy control")
	sandbox.flush_auto_flow_for_headless_test()
	check(sandbox.auto_flow_state().deployment_pending,"first render barrier keeps deployment pending")
	check_eq(session.party_status().safe_phase,"CONTACT","first render barrier cannot deploy")
	check_eq(session.sim.snapshot(),before,"first rendered ghost frame is mutation-free")
	check_eq(session.command_journal,journal_before,"first rendered ghost frame is journal-free")
	sandbox.flush_auto_flow_for_headless_test()
	check_eq(session.party_status().safe_phase,"ENGAGED","auto deployment commits")
	var planning: Dictionary = session.auto_combat_planning_state()
	check(planning.active and planning.accepted and planning.placeholder,
		"ENGAGED immediately prepares placeholder suggestions")
	check(not planning.commit_ready,"placeholder can never commit")
	check_eq(session.turn_intent_overlays().size(),2,"placeholder exposes both companion suggestions before hero action")
	check(sandbox.find_child("TurnConfirm",true,false)==null,"auto combat never creates TurnConfirm")
	for card in sandbox.cards.get_children():
		check(card.find_child("Portrait",true,false) is Portrait,"cards use ASCII actor portraits")
	sandbox.free()
	return finish()


func test_auto_hero_action_shows_final_plan_then_commits_exactly_once() -> bool:
	var sandbox = _auto_engaged_sandbox()
	var session = sandbox.session
	var hero := int(session.party_status().protagonist_id)
	sandbox.selected_member_id = hero
	var step_before := int(session.sim.world.step_index)
	var journal_before: int = session.command_journal.size()
	var world_before: Dictionary = session.sim.snapshot()
	sandbox._on_actor_hold()
	var flow: Dictionary = sandbox.auto_flow_state()
	check(flow.combat_pending and not str(flow.plan_hash).is_empty(),
		"final hero HOLD queues a hash-bound commit")
	check_eq(session.sim.snapshot(),world_before,"final plan remains visible before mutation")
	check_eq(session.command_journal.size(),journal_before,"pending plan does not journal")
	check(sandbox.find_child("TurnConfirm",true,false)==null,"normal auto flow has no confirm")
	sandbox.flush_auto_flow_for_headless_test()
	check(sandbox.auto_flow_state().combat_pending,"first render barrier keeps combat pending")
	check_eq(session.sim.snapshot(),world_before,"first final-plan frame is mutation-free")
	check_eq(session.command_journal.size(),journal_before,"first final-plan frame is journal-free")
	sandbox.flush_auto_flow_for_headless_test()
	check_eq(session.sim.world.step_index,step_before+1,"pending callback commits one turn")
	check_eq(session.command_journal.size(),journal_before+1,"one party turn journaled")
	var committed_step := int(session.sim.world.step_index)
	sandbox.flush_auto_flow_for_headless_test()
	check_eq(session.sim.world.step_index,committed_step,"duplicate flush cannot commit twice")
	sandbox.free()
	return finish()


func test_companion_override_waits_for_hero_then_survives_automatic_commit() -> bool:
	var sandbox = _auto_engaged_sandbox()
	var session = sandbox.session
	var status: Dictionary = session.party_status()
	var hero := int(status.protagonist_id)
	var companion := int(status.party_member_ids[1])
	sandbox._select_member(companion,"동료")
	sandbox._on_actor_hold()
	check(sandbox.auto_flow_state().override_edit,"companion instruction enters explicit edit mode")
	sandbox._select_member(hero,"주인공")
	sandbox._on_actor_hold()
	var planning: Dictionary = session.auto_combat_planning_state()
	check(planning.commit_ready and companion in planning.overridden_companion_ids,
		"hero replacement preserves the companion override")
	check(sandbox.auto_flow_state().combat_pending,"hero action ends editing and queues auto commit")
	check(sandbox.find_child("AutoExecute",true,false)==null,"normal override flow needs no execute button")
	var step_before := int(session.sim.world.step_index)
	sandbox.flush_auto_flow_for_headless_test()
	check_eq(session.sim.world.step_index,step_before,"first final-plan frame cannot commit override")
	sandbox.flush_auto_flow_for_headless_test()
	check_eq(session.sim.world.step_index,step_before+1,"override plan commits once after hero action")
	sandbox.free()
	return finish()


func test_pointer_invalidates_pending_combat_and_route_follow_preview_is_pure() -> bool:
	var combat = _auto_engaged_sandbox()
	var combat_step := int(combat.session.sim.world.step_index)
	combat.selected_member_id = int(combat.session.party_status().protagonist_id)
	combat._on_actor_hold()
	check(combat.auto_flow_state().combat_pending,"combat fixture queued")
	combat._on_grid_pointer_started()
	combat.flush_auto_flow_for_headless_test()
	check_eq(combat.session.sim.world.step_index,combat_step,"new pointer cancels stale auto commit")
	combat.free()

	var exploration_session = Session.new()
	var exploration = Sandbox.new()
	exploration.size = Vector2(360,640)
	exploration.initialize_for_headless_test(exploration_session,true)
	var anchor_raw: Array = exploration_session.party_status().anchor
	var goal := Vector2i(int(anchor_raw[0])-3,int(anchor_raw[1]))
	var before: Dictionary = exploration_session.sim.snapshot()
	var journal_before: Array = exploration_session.command_journal.duplicate(true)
	exploration._on_cell(goal);exploration._refresh()
	var follow: Dictionary = exploration.auto_flow_state().follow_plan
	check(follow.get("accepted",false) and follow.get("companion_rows",[]).size()==2,
		"first route preview supplies detached grouped follow rows")
	check_eq(exploration_session.sim.snapshot(),before,"follow preview is world-pure")
	check_eq(exploration_session.command_journal,journal_before,"follow preview is journal-pure")
	exploration._on_cell(goal)
	check_eq(exploration_session.sim.world.step_index,int(before.step_index)+1,
		"same-goal second tap still commits exactly one route hop")
	exploration.free()
	return finish()


func test_exploration_follower_tap_routes_to_its_display_cell_twice() -> bool:
	var session=Session.new(44,20260828,Session.SHOWCASE_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.size=Vector2(450,800)
	sandbox.initialize_for_headless_test(session,true)
	var status:Dictionary=session.party_status();var hero:=int(status.protagonist_id)
	var follower_id:=int(status.party_member_ids[1]);var follower_cell:=Vector2i(-1,-1)
	for cell in session.observe_party_world().cells:
		for actor in cell.actors:
			if int(actor.entity_id)==follower_id and str(actor.display_role)=="FOLLOWER":
				follower_cell=Vector2i(int(actor.display_position[0]),int(actor.display_position[1]))
	check(follower_cell!=Vector2i(-1,-1),"fixture follower has a visible display cell")
	var before:Dictionary=session.sim.snapshot();var journal_before:Array=session.command_journal.duplicate(true)
	sandbox._on_actor(follower_id)
	check_eq([sandbox.pending_move_mode,sandbox.pending_move_actor_id,
		sandbox.pending_move_destination,sandbox.selected_member_id],
		["EXPLORATION",hero,follower_cell,hero],
		"first follower glyph tap becomes protagonist route preview")
	check_eq([session.sim.snapshot(),session.command_journal],[before,journal_before],
		"first follower tap remains preview-only")
	sandbox._on_actor(follower_id)
	check_eq(session.sim.world.step_index,int(before.step_index)+1,
		"second follower glyph tap advances exactly one movement turn")
	check_eq(session.sim.world.entities[hero].position,follower_cell,
		"hero moves to the tapped presentation cell")
	sandbox.free();return finish()


func test_contact_pointer_cancel_is_pure_and_refreshes_manual_fallback_controls() -> bool:
	var session=_contact_session();var sandbox=Sandbox.new();sandbox.size=Vector2(450,800)
	sandbox.initialize_for_headless_test(session,true)
	check(sandbox.auto_flow_state().deployment_pending,"contact begins with pending auto deployment")
	var before:Dictionary=session.sim.snapshot();var journal_before:Array=session.command_journal.duplicate(true)
	sandbox._on_grid_pointer_started()
	var flow:Dictionary=sandbox.auto_flow_state()
	check(not bool(flow.deployment_pending) and bool(flow.deployment_fallback),
		"pointer cancels pending deployment into explicit manual fallback")
	check_eq([session.sim.snapshot(),session.command_journal],[before,journal_before],
		"contact pointer cancellation never mutates authoritative state")
	# Execute the requested deferred render synchronously for this RefCounted UI test.
	sandbox._refresh()
	check(sandbox.find_child("FormationControls",true,false)!=null \
		and sandbox.find_child("DeployConfirm",true,false)!=null,
		"fallback refresh replaces stale auto-preview deck with manual controls")
	check(sandbox.find_child("AutoDeploymentPreview",true,false)==null,
		"stale auto-preview notice is removed")
	check("대형 선택" in sandbox.action_feedback_label.text,
		"fixed feedback dock reflects manual fallback immediately")
	sandbox.free();return finish()


func _contact_session():
	var session = Session.new()
	var hero := int(session.party_status().protagonist_id)
	var result: Dictionary = session.commit_exploration(Command.wait(hero))
	if not bool(result.get("accepted",false)):
		return null
	return session


func _auto_engaged_sandbox():
	var sandbox = Sandbox.new()
	sandbox.size = Vector2(450,800)
	sandbox.initialize_for_headless_test(_contact_session(),true)
	sandbox.flush_auto_flow_for_headless_test()
	sandbox.flush_auto_flow_for_headless_test()
	return sandbox
