extends "res://tests/first_floor_stages_acceptance.gd"
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).accepted,"solo start")
	check(s.town_life_command({"action":"START"}).accepted,"town start")
	check(s.depart_town().accepted,"departure")
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	check(walk(s,Vector2i(14,11)),"approach event room")
	check(s.request_room_exit(hero,"F1_R4_R5",w.party_encounter.nine_room_floor.revision).accepted,"enter event room")
	check(walk(s,Stages.npc_position()+Vector2i.LEFT),"approach survivor")
	var npc:int=int(Population.locations(w)[0].entity_id)
	var ui=Sandbox.new();ui.size=Vector2(390,844);ui.initialize_for_headless_test(s,true)
	root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	check(ui.nearby_npc_panel==null,"no automatic inspector near actual NPC")
	check(not ui.grid.monster_list_draw_spec().visible,"no automatic actor list")
	ui.grid.actor_inspect_requested.emit(npc)
	for i in range(2):await process_frame
	check(ui.member_detail_modal.visible and ui.member_detail_entity_id==npc,"explicit NPC detail still opens")
	check(not ui.member_detail_candidate_action.disabled,"aid action available in detail")
	ui._on_member_detail_candidate_action()
	for i in range(2):await process_frame
	check(Visitors.assess(s,npc).get("action","")=="ACCEPT","food aid advances to invitation")
	ui._on_member_detail_candidate_action()
	for i in range(2):await process_frame
	check(npc in w.party_encounter.active_party_member_ids,"detail action recruits survivor without corner card")
	ui._close_member_detail()
	check(not ui.grid.modal_open,"map input restored after detail closes")
	check(w.world_state_error().is_empty(),"world audit")
	ui.queue_free();await process_frame
	print("EVENT_NPC_WITHOUT_CORNER_UI ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
