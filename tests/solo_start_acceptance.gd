extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func round_trip(session,label:String):
	var restored=Session.new()
	var result:Dictionary=restored.load_session_json(session.save_session_json())
	check(result.accepted,label+" loads: "+str(result.get("reason","")))
	if result.accepted:check(restored.sim.snapshot()==session.sim.snapshot(),label+" replay exact")
func run():
	root.size=Vector2i(390,800)
	var legacy=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(legacy.sim.world.party_encounter.active_party_member_ids.size()==2,"legacy fixtures retain companions")
	round_trip(legacy,"existing party save")
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(session.solo_start_enabled(),"solo bootstrap marker")
	check(session.sim.world.party_encounter.party_member_ids.size()==1,"no hidden starter companion")
	check(session.field_turns_active(),"shared field combat retained")
	var hero:int=session.sim.world.party_control_actor_id()
	check(session.commit_field_action(Action.hold(hero)).accepted,"solo turn advances")
	round_trip(session,"solo save after action")
	var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
	for i in range(3):await process_frame
	ui.show_species_picker_for_new_run()
	ui._commit_species_picker("human")
	for i in range(3):await process_frame
	check(session.solo_start_enabled(),"product species picker selects solo start")
	check(session.sim.world.party_encounter.active_party_member_ids.size()==1,"product new game deploys only hero")
	for id in session.sim.world.party_encounter.party_member_ids:
		if id!=session.sim.world.party_encounter.protagonist_id:
			check(session.sim.world.party_encounter.member(id).presence=="RECRUITABLE","guild residents stay unassigned")
	check(ui.cards.get_child_count()==1,"one portrait")
	check(session.sim.world.world_state_error().is_empty(),"new world valid")
	round_trip(session,"living solo save")
	var departure:Dictionary=session.depart_town()
	check(departure.accepted,"solo departure accepted: "+str(departure.get("reason","")))
	check(session.sim.world.party_encounter.active_party_member_ids.size()==1,"departure stays solo")
	check(session.field_turns_active(),"solo departure uses field turns")
	round_trip(session,"solo departure save")
	ui.queue_free();await process_frame
	print("SOLO START: ",failures)
	quit(0 if failures.is_empty() else 1)
