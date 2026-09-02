extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Request = preload("res://sim/party_turn_request.gd")
const Blackboard = preload("res://sim/party_squad_blackboard.gd")
const PartyScene = preload("res://playtest/party_encounter_sandbox.tscn")


func _engaged():
	var session=Session.new(73,20260902)
	var state=session.sim.world.party_encounter
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
		"fixture contact")
	session.preview_deployment("WEDGE",state.party_member_ids.slice(1))
	check(session.commit_deployment().accepted,"fixture deployment")
	return session


func test_attack_target_is_authoritative_focus_without_individual_orders()->bool:
	var session=_engaged()
	var world=session.sim.world
	var state=world.party_encounter
	var enemy:=int(state.enemy_ids[0])
	var result:Dictionary=session.issue_party_command("ATTACK_TARGET",enemy)
	check(bool(result.accepted),"attack-target command commits")
	check_eq(session.party_status().party_command.command_id,"ATTACK_TARGET",
		"status exposes the effective exceptional command")
	var board:Dictionary=Blackboard.build(world,Action.hold(state.protagonist_id))
	check_eq(int(board.focus_target_id),enemy,
		"all companions derive one focus target from the party command")
	check_eq(world.world_state_error(),"","command event remains canonical")
	return finish()


func test_retreat_stop_hold_and_follow_change_automatic_companion_actions()->bool:
	var session=_engaged()
	var state=session.sim.world.party_encounter
	var hero:=int(state.protagonist_id)
	check(session.issue_party_command("RETREAT").accepted,"retreat command commits")
	var retreat:Dictionary=session.sim.party_coordinator.explain_companion_turn(
		Request.new(Action.hold(hero),[]))
	for row in retreat.companions:
		check_eq(str(row.command_id),"RETREAT","retreat reaches every companion")
		check_eq(str(row.selected_action_id),"RETREAT","retreat suppresses attack utility")
	check(session.issue_party_command("STOP_ATTACK").accepted,"stop-attack commits")
	var stopped=session.sim.preview_party_turn(Request.new(Action.hold(hero),[])).to_dict()
	for row in stopped.actor_rows:
		if str(row.source)=="SUGGESTED":
			check(str(row.action.type) in ["MOVE","HOLD"],
				"stop-attack permits following but never a companion attack")
	check(session.issue_party_command("HOLD_POSITION").accepted,"hold-position commits")
	var held=session.sim.preview_party_turn(Request.new(Action.hold(hero),[])).to_dict()
	for row in held.actor_rows:
		if str(row.source)=="SUGGESTED":
			check(str(row.action.type) in ["MELEE","HOLD"],
				"hold-position permits defense but never companion movement")
	check(session.issue_party_command("FOLLOW").accepted,"follow command commits")
	check_eq(session.party_status().party_command.command_id,"FOLLOW",
		"follow restores the normal autonomous loop")
	return finish()


func test_command_invalidates_stale_plan_and_save_replay_is_exact()->bool:
	var session=_engaged()
	var state=session.sim.world.party_encounter
	var request=Request.new(Action.hold(state.protagonist_id),[])
	var stale_plan=session.sim.preview_party_turn(request)
	check(session.issue_party_command("RETREAT").accepted,"retreat command commits")
	var stale_result=session.sim.step_party_turn(stale_plan)
	check(not stale_result.accepted and str(stale_result.reason)=="stale_party_plan",
		"a new command invalidates an already frozen party plan")
	check(session.issue_party_command("STOP_ATTACK").accepted,"stop command commits")
	check(session.issue_party_command("FOLLOW").accepted,"follow command commits")
	var encoded:=session.save_session_json()
	var restored=Session.new(1,1)
	var load_result:Dictionary=restored.load_session_json(encoded)
	check(bool(load_result.accepted),"command journal save loads through replay")
	check_eq(restored.sim.snapshot(),session.sim.snapshot(),
		"command events and effective state replay byte-exactly")
	var restored_commands:Array=restored.command_journal.filter(func(row):
		return str(row.get("kind",""))=="party_command")
	var source_commands:Array=session.command_journal.filter(func(row):
		return str(row.get("kind",""))=="party_command")
	check_eq(restored_commands,source_commands,
		"party command journal rows are preserved exactly")
	return finish()


func test_compact_menu_exposes_five_commands_and_targeting_uses_enemy_tap()->bool:
	var session=_engaged()
	var sandbox=PartyScene.instantiate()
	sandbox.initialize_for_headless_test(session,true)
	check(sandbox.party_command_menu!=null,"party combat creates one compact command menu")
	check_eq(sandbox.party_command_menu.get_popup().item_count,5,
		"menu exposes only the five exceptional commands")
	check_eq(sandbox.party_command_menu.custom_minimum_size.y,44.0,
		"exception menu keeps a mobile touch target")
	sandbox._on_party_command_menu_id(1)
	check_eq(session.party_status().party_command.command_id,"RETREAT",
		"retreat menu item reaches the authoritative session")
	var enemy:=int(session.sim.world.party_encounter.enemy_ids[0])
	sandbox._on_party_command_menu_id(0)
	check(sandbox._party_command_targeting,"attack-target item enters enemy selection")
	sandbox._on_actor(enemy)
	check_eq(session.party_status().party_command.command_id,"ATTACK_TARGET",
		"the next enemy tap becomes the shared focus command")
	var companion:=int(session.sim.world.party_encounter.active_party_member_ids[1])
	sandbox._select_member(companion,"나래")
	sandbox._refresh()
	check(sandbox.find_child("OverrideClear",true,false)==null,
		"automatic party UI exposes no individual-override control")
	var individual_labels:Array[String]=[]
	for button in sandbox.find_children("*","Button",true,false):
		if "개별" in str(button.get("text")):
			individual_labels.append(str(button.get("text")))
	check(individual_labels.is_empty(),
		"automatic party UI contains no individual-order wording")
	sandbox._stage_auto_combat_action("HOLD")
	check_eq(sandbox.selected_member_id,
		int(session.sim.world.party_encounter.protagonist_id),
		"ordinary input after companion inspection is reassigned to the protagonist")
	check_eq(session.current_turn_preview().get("canonical_request",{}).get("overrides",[]),[],
		"product party input never creates an individual override")
	sandbox.free()
	return finish()
