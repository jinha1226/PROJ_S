extends "res://tests/first_floor_stages_acceptance.gd"
const Roles=preload("res://sim/stage_enemy_rules.gd")
const Stage=preload("res://sim/stage_counterplay.gd")
const Rules=preload("res://sim/round_combat_rules.gd")
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	check(walk(s,Vector2i(11,14)),"approach")
	check(s.request_room_exit(hero,"F1_R4_R7",w.party_encounter.nine_room_floor.revision).accepted,"enter")
	var id:int=Stage.enemies(w)[0];var entity=w.entities[id];var species:String=entity.species_id
	# Pure rule probes; restore species before executing/auditing the run.
	entity.species_id="dcss_rat";check(Rules.move_budget(w,id)==4,"runner moves four")
	entity.species_id="goblin";check(Rules.move_budget(w,id)==2,"warrior moves two")
	entity.species_id="kobold"
	check(Roles.aimable(w,Vector2i(11,21),Vector2i(14,21),Roles.profile(w,id)),"ranged aim at distance three")
	check(not Roles.aimable(w,Vector2i(11,21),Vector2i(12,21),Roles.profile(w,id)),"archer minimum range")
	check(not Roles.line(w,Vector2i(9,18),Vector2i(11,18)),"walls stop line of fire")
	entity.species_id="dcss_hobgoblin"
	check(Rules.move_budget(w,id)==1,"heavy moves one")
	check(Roles.cells(w,id,Vector2i(11,21),Vector2i(12,21)).size()==3,"sweep covers three front cells")
	entity.species_id="dcss_frilled_lizard"
	check(Roles.cells(w,id,Vector2i(11,20),Vector2i(13,20)).size()==5,"cross covers five cells")
	entity.species_id=species
	check(s.stage_round_action(Action.move_to(hero,Vector2i(10,17))).accepted,"place")
	var r:Dictionary=w.party_encounter.round_combat
	check(s.confirm_round(r.round_id,r.plan_revision).accepted,"deploy")
	# Isolated spatial fixture tests actual multi-target dispatch. Relocation is
	# test-only; full history/replay checks below use the untouched live session.
	var shadow=preload("res://sim/simulator.gd").from_snapshot(s.sim.snapshot())
	check(shadow!=null,"snapshot clone before area fixture")
	if shadow!=null:
		var sw=shadow.world;var enemies:=Stage.enemies(sw)
		var heavy:int=enemies[1]
		var relocate=preload("res://tests/round_combat_fixture.gd")
		relocate.relocate(sw,heavy,Vector2i(11,21))
		relocate.relocate(sw,hero,Vector2i(12,21))
		relocate.relocate(sw,enemies[0],Vector2i(12,20))
		relocate.relocate(sw,enemies[2],Vector2i(12,22))
		var plan:=preload("res://sim/round_plan_service.gd").pack(sw,Action.melee(heavy,hero),"AI")
		var start:int=sw.events.size();var step:int=sw.step_index+1;sw.begin_step(step)
		var hit:Dictionary=preload("res://sim/systems/round_combat_system.gd").execute_slot(shadow,plan,step)
		check(hit.accepted,"sweep dispatch executes: "+str(hit)+" / "+preload("res://sim/systems/round_combat_system.gd").last_execution_error)
		var victims:Array=[];var contexts:Array=[]
		for event in sw.events_since(start):
			if event.type=="action.melee_attack" and event.actor_id==heavy:victims.append(event.target_id);contexts.append(event.data.batch_context)
		check(victims.size()==3 and hero in victims and enemies[0] in victims and enemies[2] in victims,"sweep hits each occupied tile including enemies")
		check(contexts.size()==3 and contexts[0]!=contexts[1] and contexts[1]!=contexts[2],"area strikes have distinct deterministic commitments")
		sw.finish_step()
	var effects_seen:=false
	for i in range(4):
		if not s.round_active() or not w.can_act(hero,w.world_time):break
		r=w.party_encounter.round_combat
		for row in s.round_overlays():
			if row.role=="ENEMY" and row.type=="MELEE":
				var p:Dictionary=r.plans[str(row.actor_id)]
				check(row.attack_cells==Roles.cells(w,row.actor_id,Vector2i(p.origin[0],p.origin[1]),Vector2i(p.target_cell[0],p.target_cell[1])).map(func(cell):return [cell.x,cell.y]),"render and damage share footprint")
		var result:Dictionary=s.confirm_round(r.round_id,r.plan_revision)
		check(result.accepted,"role round executes")
		if not result.accepted:break
		effects_seen=effects_seen or not result.visual_effects.is_empty()
		check(w.world_state_error().is_empty(),"role attacks preserve canonical audit: "+w.world_state_error())
	check(effects_seen,"round combat emits hit or miss presentation")
	print("STAGE_ROLES ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
