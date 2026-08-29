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


func test_one_tap_move_auto_commits_once_and_companion_override_waits_for_hero() -> bool:
	var hero_sandbox=_auto_engaged_sandbox();var hero_session=hero_sandbox.session
	var hero_status:Dictionary=hero_session.party_status();var hero:=int(hero_status.protagonist_id)
	hero_sandbox.selected_member_id=hero
	var hero_destination:=_first_valid_move(hero_sandbox,hero)
	check(hero_destination!=Vector2i(-1,-1),"auto hero has a legal empty MOVE cell")
	var hero_before:Dictionary=hero_session.sim.snapshot();var hero_journal:int=hero_session.command_journal.size()
	hero_sandbox._on_cell(hero_destination)
	var hero_flow:Dictionary=hero_sandbox.auto_flow_state()
	var hero_planning:Dictionary=hero_session.auto_combat_planning_state()
	var hero_action:Dictionary={}
	for row in hero_planning.preview.actor_rows:
		if int(row.actor_id)==hero:hero_action=row.action
	check(hero_flow.combat_pending and hero_sandbox.pending_move_mode!="COMBAT",
		"one hero tile tap queues final auto plan without retap state")
	check_eq([hero_action.get("type",""),hero_action.get("destination",[])],
		["MOVE",[hero_destination.x,hero_destination.y]],"one-tap hero MOVE destination")
	check_eq([hero_session.sim.snapshot(),hero_session.command_journal.size()],
		[hero_before,hero_journal],"final MOVE render plan is mutation-free")
	hero_sandbox.flush_auto_flow_for_headless_test()
	check_eq(hero_session.sim.snapshot(),hero_before,"first MOVE render barrier is mutation-free")
	hero_sandbox.flush_auto_flow_for_headless_test()
	check_eq([hero_session.sim.world.step_index,hero_session.command_journal.size()],
		[int(hero_before.step_index)+1,hero_journal+1],"one-tap MOVE commits exactly once")
	var committed_step:=int(hero_session.sim.world.step_index)
	hero_sandbox.flush_auto_flow_for_headless_test()
	check_eq(hero_session.sim.world.step_index,committed_step,"one-tap MOVE cannot double commit")
	hero_sandbox.free()

	var companion_sandbox=_auto_engaged_sandbox();var companion_session=companion_sandbox.session
	var status:Dictionary=companion_session.party_status();hero=int(status.protagonist_id)
	var companion:=int(status.party_member_ids[1])
	companion_sandbox._select_member(companion,"동료")
	var companion_destination:=_first_valid_move(companion_sandbox,companion)
	check(companion_destination!=Vector2i(-1,-1),"auto companion has a legal empty MOVE cell")
	var companion_step:=int(companion_session.sim.world.step_index)
	companion_sandbox._on_cell(companion_destination)
	var planning:Dictionary=companion_session.auto_combat_planning_state()
	var companion_action:Dictionary={}
	for row in planning.preview.actor_rows:
		if int(row.actor_id)==companion:companion_action=row.action
	check(not companion_sandbox.auto_flow_state().combat_pending \
		and companion in planning.overridden_companion_ids,
		"one companion tile tap stores override but cannot commit turn")
	check_eq([companion_action.get("type",""),companion_action.get("destination",[])],
		["MOVE",[companion_destination.x,companion_destination.y]],"companion one-tap MOVE override")
	check_eq(companion_session.sim.world.step_index,companion_step,"companion override waits for hero")
	companion_sandbox._select_member(hero,"주인공");companion_sandbox._on_actor_hold()
	planning=companion_session.auto_combat_planning_state()
	check(companion in planning.overridden_companion_ids \
		and companion_sandbox.auto_flow_state().combat_pending,
		"hero action preserves one-tap companion MOVE and queues commit")
	companion_sandbox.flush_auto_flow_for_headless_test()
	companion_sandbox.flush_auto_flow_for_headless_test()
	check_eq(companion_session.sim.world.step_index,companion_step+1,
		"preserved companion MOVE plan commits with hero exactly once")
	companion_sandbox.free();return finish()


func test_pointer_invalidates_pending_combat_and_one_tap_route_follow_starts_once() -> bool:
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
		"one-tap route supplies detached grouped follow rows")
	check_eq(exploration_session.sim.world.step_index,int(before.step_index)+1,
		"one tap starts with exactly one route hop")
	check_eq(exploration_session.command_journal.size(),journal_before.size()+1,
		"one tap appends exactly one exploration command")
	var same_goal_step:=int(exploration_session.sim.world.step_index)
	exploration._on_cell(goal)
	check_eq(exploration_session.sim.world.step_index,same_goal_step,
		"active same-goal tap is a no-op instead of an extra hop")
	check("이동 중" in exploration.action_feedback_text,"active same-goal tap reports movement")
	exploration.free()
	return finish()


func test_exploration_follower_tap_routes_to_its_display_cell_once() -> bool:
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
	check_eq(session.sim.world.step_index,int(before.step_index)+1,
		"one follower glyph tap advances exactly one movement turn")
	check_eq(session.command_journal.size(),journal_before.size()+1,
		"follower display tap appends one protagonist route command")
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


func _first_valid_move(sandbox,actor_id:int)->Vector2i:
	var origin:=Vector2i(-1,-1)
	for card in sandbox.session.party_cards():
		if int(card.entity_id)==actor_id:
			origin=Vector2i(int(card.logical_position[0]),int(card.logical_position[1]));break
	for direction in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,
			Vector2i(1,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(-1,-1)]:
		var destination:Vector2i=origin+direction
		if sandbox.grid.actor_in_world_cell(destination)!=-1:continue
		var preview:Dictionary=sandbox.session.preview_actor_action(actor_id,"MOVE",
			[destination.x,destination.y])
		if bool(preview.get("accepted",false)):return destination
	return Vector2i(-1,-1)
