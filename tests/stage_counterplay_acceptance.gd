extends "res://tests/first_floor_stages_acceptance.gd"
const Stage=preload("res://sim/stage_counterplay.gd")
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	check(walk(s,Vector2i(11,14)),"approach combat room")
	check(s.request_room_exit(hero,"F1_R4_R7",w.party_encounter.nine_room_floor.revision).accepted,"enter")
	var r:Dictionary=w.party_encounter.round_combat
	check(r.phase=="DEPLOYMENT","entry requires placement confirmation")
	var positions:Dictionary={};var hp:int=w.entities[hero].health;var time:int=w.world_time
	for id in Stage.enemies(w):positions[id]=w.entities[id].position
	check(not s.stage_round_action(Action.move_to(hero,Vector2i(11,21))).accepted,"deployment restricted to entrance")
	check(s.stage_round_action(Action.move_to(hero,Vector2i(10,17))).accepted,"place hero inside two-cell entrance zone")
	var confirm:Dictionary=s.confirm_round(r.round_id,r.plan_revision)
	check(confirm.accepted,"deployment confirmed "+str(confirm.get("reason")))
	r=w.party_encounter.round_combat
	check(r.phase=="PLANNING","enemy move then player planning")
	check(w.world_time==time and w.entities[hero].health==hp,"deployment and enemy setup do not inflict attacks or consume turn")
	check(positions.keys().any(func(id):return positions[id]!=w.entities[id].position),"enemies actually reposition before plan")
	var attacks:=0;var enemy_seen:=false
	for id in r.order:
		var p:Dictionary=r.plans[id]
		if w.party_encounter.member(int(id))==null:
			enemy_seen=true;check(p.path.is_empty(),"published enemies have attack-only plans")
			if p.action.type=="MELEE":attacks+=1
		else:check(not enemy_seen,"all allies execute before enemy attacks")
	check(attacks>0,"attack targets shown after enemy movement")
	if not w.world_state_error().is_empty():quit(1);return
	var before:Dictionary=s.sim.snapshot()
	var shadow=preload("res://sim/simulator.gd").from_snapshot(before)
	var announced:Dictionary={}
	for id in r.order:
		if w.party_encounter.member(int(id))==null and r.plans[id].action.type=="MELEE":announced=r.plans[id].duplicate(true);break
	if shadow!=null and not announced.is_empty():
		var old:Vector2i=shadow.world.entities[hero].position
		shadow.world.entities[hero].position=Vector2i(14,22);shadow.world.reindex_entity_occupancy(hero,old,Vector2i(14,22))
		var cancelled:Dictionary=preload("res://sim/systems/round_combat_system.gd").execute_slot(shadow,announced,shadow.world.step_index+1,true)
		check(cancelled.get("reason")=="target_cell_empty","enemy attacks announced tile instead of tracking moved target")
	for i in range(3):s.round_preview();s.observe_party_ui(8,true,8)
	check(s.sim.snapshot()==before,"preview does not move enemies or advance waves")
	check(w.world_state_error().is_empty(),"deployment world audit "+w.world_state_error())
	var clone=Session.new();var loaded:Dictionary=clone.load_session_json(s.save_session_json())
	check(loaded.accepted,"deployment replay "+str(loaded.get("reason")))
	if loaded.accepted:check(clone.sim.snapshot()==s.sim.snapshot(),"deployment replay exact")
	var result:Dictionary=s.confirm_round(r.round_id,r.plan_revision)
	check(result.accepted,"resolve ally response then enemy attacks "+str(result.get("reason")))
	check(Stage.current(w).turn==1,"one completed response advances wave counter once")
	check(w.world_state_error().is_empty(),"round audit "+w.world_state_error())
	var round_clone=Session.new();var round_loaded:Dictionary=round_clone.load_session_json(s.save_session_json())
	check(round_loaded.accepted,"completed response and next enemy movement replay")
	if round_loaded.accepted:check(round_clone.sim.snapshot()==s.sim.snapshot(),"response replay exact")
	# A bounded unit fixture advances only the reinforcement counter, not attacks.
	var count:int=w.party_encounter.enemy_ids.size()
	for i in range(4):check(Stage.finish_round(s.sim),"predeadline counter")
	check(w.party_encounter.enemy_ids.size()==count,"no early reinforcement")
	check(Stage.finish_round(s.sim),"deadline reinforcement")
	check(w.party_encounter.enemy_ids.size()==count+2,"two enemies arrive at six completed turns")
	check(Stage.current(w).waves==1,"one wave counted")
	check(w.world_state_error().is_empty(),"reinforcement world audit "+w.world_state_error())
	var wire:Dictionary=s.sim.snapshot();var restored=preload("res://sim/simulator.gd").from_snapshot(wire)
	check(restored!=null,"reinforcement snapshot restores")
	if restored!=null:check(restored.snapshot()==wire,"wave counter and spawned actors persist")
	var old_ids:Array=w.party_encounter.enemy_ids.duplicate()
	w.party_encounter.enemy_ids.clear();Stage.current(w).turn=11
	check(Stage.finish_round(s.sim),"clear-room deadline")
	check(Stage.current(w).waves==1,"no reinforcements after all enemies are gone")
	w.party_encounter.enemy_ids.assign(old_ids)
	print("STAGE_COUNTERPLAY ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
