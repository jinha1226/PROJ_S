extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const OpeningTests=preload("res://tests/test_opening_fixed_event.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:int=0
func check(value:bool,message:String)->void:
	if not value:failures+=1;printerr(message)
func _init()->void:call_deferred("run")
func run()->void:
	var helper=OpeningTests.new()
	var seed:int=helper._opening_personality_seed(true)
	var session=Session.new(44,seed,Session.SOLO_EXPLORATION_SCENARIO_ID)
	check(session.sim!=null,"solo world starts")
	var state=session.sim.world.party_encounter
	check(state.party_member_ids.size()==1,"starts with one hero")
	check(not session.allows_companions(),"solo policy enabled")
	var npc_id:int=state.opening_event.npc_entity_id
	var gratitude_before:int=session.sim.relationships.effective_relation(npc_id,state.protagonist_id).gratitude
	check(helper._approach_opening(session),"can approach NPC")
	var aid:Dictionary=session.commit_opening_event_choice("GIVE_POTION")
	check(aid.get("accepted",false),"can still help NPC")
	check(session.sim.world.party_encounter.party_member_ids.size()==1,"help never recruits")
	check(session.sim.relationships.effective_relation(npc_id,state.protagonist_id).gratitude>gratitude_before,"help preserves gratitude effects")
	check(not session.offer_recruitment(npc_id).accepted,"offer blocked")
	check(not session.recruit_companion(npc_id).accepted,"direct recruitment blocked")
	check(session.recruitable_companions().is_empty(),"no guild candidates")
	var loaded=Session.new(1,2,Session.SOLO_FIXTURE_SCENARIO_ID)
	var restored:Dictionary=loaded.load_session_json(session.save_session_json())
	check(restored.accepted,"solo save replays")
	check(loaded.sim.snapshot()==session.sim.snapshot(),"solo snapshot identical")
	check(not loaded.allows_companions(),"loaded policy retained")
	var ui=Sandbox.new();ui.initialize_for_headless_test(session,true);root.add_child(ui)
	await process_frame
	check(ui.find_child("ActiveCombatLabStart",true,false)==null,"no party test on start screen")
	ui._town_deck(session.party_status())
	check(ui.find_child("TownFacilityGUILD",true,false)==null,"no guild recruitment menu")
	ui.queue_free();await process_frame
	var legacy=Session.new(44,seed,Session.SOLO_COMBAT_SCENARIO_ID)
	check(legacy.allows_companions(),"legacy scenario preserved")
	print("Solo exploration: %d failures"%failures);quit(0 if failures==0 else 1)
