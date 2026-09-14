extends "res://tests/first_floor_stages_acceptance.gd"
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Enemy=preload("res://sim/stage_enemy_rules.gd")
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	var ui=Sandbox.new();ui.initialize_for_headless_test(s,true)
	root.add_child(ui);ui.set_process(false)
	check(walk(s,Vector2i(10,11)),"walk onto starting shield")
	ui._request_refresh()
	for i in range(4):await process_frame
	check(s.ground_item_count_at_protagonist()>0,"item under hero")
	check(ui.stage_context_bar.get_node_or_null("StagePickup")!=null,"reachable pickup button")
	var count:int=s.ground_item_count_at_protagonist()
	ui.grid._stage_motion_until=0
	ui._on_actor(hero)
	check(s.ground_item_count_at_protagonist()==count-1,"hero touch picks up instead of field selection")
	check(walk(s,Vector2i(11,14)),"walk to south entry")
	check(s.request_room_exit(hero,"F1_R4_R7",s.room_status().revision).accepted,"enter first combat")
	check(preload("res://sim/stage_counterplay.gd").enemies(w).size()==1,"solo opening has one enemy")
	ui._request_refresh()
	for i in range(4):await process_frame
	var original:Vector2i=w.entities[hero].position;var time:int=w.world_time
	ui.grid._stage_motion_until=0
	ui._on_cell(Vector2i(10,17))
	check(w.entities[hero].position==original and w.world_time==time,"placement does not move authority or time")
	check(s.round_overlays().is_empty(),"no walking arrows during placement")
	ui._on_cell(original)
	check(w.party_encounter.round_combat.plans[str(hero)].destination==[original.x,original.y],"can place back on original tile")
	ui._on_cell(Vector2i(10,17))
	ui._on_product_execute()
	check(w.entities[hero].position==Vector2i(10,17) and w.world_time==time,"confirm is zero-time placement")
	check(not ui.grid._actor_motion_requests.has(hero),"placement does not arm hero walking animation")
	var p:Dictionary={"min":2,"max":4}
	check(not Enemy.aimable(w,Vector2i(9,19),Vector2i(11,21),p),"diagonal shot forbidden")
	check(Enemy.aimable(w,Vector2i(9,19),Vector2i(12,19),p),"cardinal shot allowed")
	check(not Enemy.aimable(w,Vector2i(9,18),Vector2i(12,18),p),"wall blocks cardinal shot")
	var weapons=preload("res://sim/weapon_attack_rules.gd")
	check(weapons.targeting_error(Vector2i(1,1),Vector2i(3,3),"BOW")=="ranged_target_not_in_line","player bow rejects diagonal")
	check(weapons.targeting_error(Vector2i(1,1),Vector2i(1,4),"BOW").is_empty(),"player bow allows cardinal")
	check(not s.sim.movement.assess_move(hero,Vector2i(10,18)).accepted,"pillar is impassable")
	check(w.world_state_error().is_empty(),"world valid")
	ui.queue_free();await process_frame
	print("STAGE_INPUT_REGRESSION ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
