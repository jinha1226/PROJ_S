extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Rules = preload("res://sim/guild_tutorial_rules.gd")
const Event = preload("res://sim/sim_event.gd")

func _event(id:int,type:String,actor_id:int,target_id:int=-1,data:Dictionary={},magnitude:int=0)->Object:
	return Event.new(id,0,id,type,actor_id,target_id,Vector2i(1,1),magnitude,-1,actor_id,data)

func test_town_board_accepts_without_time_and_is_idempotently_blocked()->bool:
	var session=Session.new(4401,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var started:Dictionary=session.town_life_command({"action":"START"})
	check(bool(started.get("accepted",false)),"single-player town can start the town-life route")
	var before_time:=int(session.sim.world.world_time)
	var overview:Dictionary=session.guild_tutorial_overview()
	check(bool(overview.get("available",false)),"guild tutorial is available in town")
	check_eq(overview.get("quests",[]).size(),5,"the board exposes five independent quests")
	var accepted:Dictionary=session.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_MOVE"})
	check(bool(accepted.get("accepted",false)),"a tutorial quest can be accepted")
	check_eq(int(session.sim.world.world_time),before_time,"town tutorial clicks consume no world time")
	var duplicate:Dictionary=session.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_MOVE"})
	check(not bool(duplicate.get("accepted",false)) and duplicate.reason=="guild_tutorial_already_accepted",
		"the same quest cannot be accepted twice")
	check(not session.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_GUARD","extra":true}).accepted,
		"unknown tutorial operation fields are rejected")
	check_eq(session.sim.world.world_state_error(),"","acceptance preserves canonical state")
	check_eq(session._journal_wire_error(session.command_journal),"","guild commands use strict replay wire rows")
	var restored=Session.new(1,2)
	var loaded:Dictionary=restored.load_session_json(session.save_session_json())
	check(bool(loaded.get("accepted",false)),"guild acceptance save can be loaded")
	if bool(loaded.get("accepted",false)):
		check_eq(restored.sim.snapshot(),session.sim.snapshot(),"guild acceptance replay restores the exact snapshot")
	return finish()

func test_support_never_duplicates_existing_potion()->bool:
	var session=Session.new(4402,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(session.town_life_command({"action":"START"}).accepted,"town starts for support test")
	check(session.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_HEAL"}).accepted,
		"heal tutorial can be accepted")
	var before:Dictionary=session.protagonist_inventory()
	var result:Dictionary=session.guild_tutorial_command({"action":"SUPPORT","quest_id":"GUILD_TUTORIAL_HEAL"})
	check(not bool(result.get("accepted",false)) and result.reason=="guild_tutorial_support_not_needed",
		"support is rejected when the protagonist already owns a healing potion")
	check_eq(session.protagonist_inventory(),before,"rejected support does not duplicate items")
	return finish()

func test_event_rules_require_canonical_floor_one_progress()->bool:
	var hero:=7
	var accepted_move=_event(1,Rules.EVENT_ACCEPTED,hero,-1,{"campaign_id":Rules.CAMPAIGN_ID,"quest_id":"GUILD_TUTORIAL_MOVE"})
	var move_events:Array=[accepted_move,
		_event(2,"action.move",hero,-1,{"from_position":[1,1],"to_position":[2,1]}),
		_event(3,"action.move",hero,-1,{"from_position":[2,1],"to_position":[3,1]}),
		_event(4,"action.move",hero,-1,{"from_position":[3,1],"to_position":[4,2]})]
	var move_state:Dictionary=Rules.state(move_events,hero,[])
	check(move_state.quests[0].completed,"three floor-one moves including a diagonal complete the move quest")
	var guard_events:Array=[_event(1,Rules.EVENT_ACCEPTED,hero,-1,{"campaign_id":Rules.CAMPAIGN_ID,"quest_id":"GUILD_TUTORIAL_GUARD"}),
		_event(2,"action.hold",hero),_event(3,"action.melee_attack",hero,99,{"outcome":"HIT"})]
	var guard_state:Dictionary=Rules.state(guard_events,hero,[99])
	check(guard_state.quests[1].completed,"guard requires both hold and a valid enemy hit")
	var return_events:Array=[_event(1,Rules.EVENT_ACCEPTED,hero,-1,{"campaign_id":Rules.CAMPAIGN_ID,"quest_id":"GUILD_TUTORIAL_RETURN"}),
		_event(2,"town.expedition_departed",hero,-1,{"expedition_index":4,"floor_index":1}),
		_event(3,"item.picked_up",hero,-1,{},1),
		_event(4,"dungeon.expedition_returned",hero,-1,{"expedition_index":4})]
	var return_state:Dictionary=Rules.state(return_events,hero,[])
	check(return_state.quests[4].completed,"return completes only after loot and an actual return in one expedition")
	return finish()
