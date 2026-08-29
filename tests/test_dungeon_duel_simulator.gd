extends "res://tests/test_case.gd"

const Simulator=preload("res://sim/dungeon_population/dungeon_population_simulator.gd")
const Hexaco=preload("res://sim/dungeon_population/hexaco_profile.gd")

func test_seeded_five_actor_scenario_is_exact_unique_and_directional()->bool:
	var first=Simulator.new(83);var second=Simulator.new(83)
	check_eq(first.snapshot(),second.snapshot(),"same seed creates the exact five-actor scenario")
	var observation:Dictionary=first.observation()
	check_eq([observation.actors.size(),observation.map_size,observation.phase],
		[5,[21,21],"ACTIVE"],"five actors inhabit the 21 by 21 encounter map")
	var positions:Dictionary={};var relation_count:=0
	for actor in observation.actors:
		positions[JSON.stringify(actor.position)]=true;relation_count+=actor.relations.size()
		check_eq(actor.hexaco,Hexaco.generated(83,int(actor.id)).to_dict(),
			"each actor keeps exact seed-generated HEXACO")
		check(not actor.hexaco.has("archetype_id"),"fixed personality archetypes are absent")
	check_eq(positions.size(),5,"active actor positions are unique")
	check_eq(relation_count,20,"all twenty directed actor-to-actor relations are observable")
	return finish()

func test_each_actor_scores_target_specific_candidates_without_self_targeting()->bool:
	var sim=Simulator.new(3)
	var before:Dictionary=sim.snapshot();var rows:Array=sim.decision_breakdowns()
	check_eq(sim.snapshot(),before,"decision preview is authoritative-state pure")
	check_eq(rows.size(),5,"all active actors decide independently")
	for row in rows:
		var actor_id:=int(row.actor_id);var selected_count:=0
		for candidate in row.candidates:
			var target_id:=int(candidate.target_id)
			if candidate.target_role=="OTHER":
				check(target_id>=1 and target_id<=5 and target_id!=actor_id,
					"target action names a perceived non-self actor")
			elif candidate.target_role=="SELF":check_eq(target_id,actor_id,"self action targets self")
			else:check_eq(target_id,-1,"targetless action uses the canonical sentinel")
			var computed:=int(candidate.base)+int(candidate.jitter)
			for bucket in [candidate.hexaco_terms,candidate.state_terms,
					candidate.relation_terms,candidate.context_terms]:
				for term in bucket:computed+=int(term.contribution)
			check_eq(candidate.total,computed,"candidate total is an auditable term sum")
			check(int(candidate.jitter)>=-15 and int(candidate.jitter)<=15,
				"episode jitter appears once and is bounded")
			if candidate.selected:selected_count+=1
		check_eq(selected_count,1,"exactly one legal actor-target candidate is selected")
		check(_selected_target_is_valid(row),"selected action preserves its target role")
	var detached:Array=sim.decision_breakdowns();detached[0].candidates[0].total=999999
	check(sim.decision_breakdowns()[0].candidates[0].total!=999999,"decision DTO is detached")
	return finish()

func test_many_to_one_attacks_resolve_from_turn_start_without_order_bias()->bool:
	var first=Simulator.new(100);_prepare_many_to_one(first)
	var second=Simulator.new(100);_prepare_many_to_one(second)
	var hp_before:Dictionary={1:int(first.state.actors[1].hp),3:int(first.state.actors[3].hp)}
	check(first.step().accepted and second.step().accepted,"simultaneous melee turn resolves")
	check_eq(first.snapshot(),second.snapshot(),"same simultaneous fixture has exact resolution")
	var damage_to_three:=0;var attackers:Dictionary={}
	for event in first.state.events:
		if event.type=="DAMAGE" and int(event.target_id)==3:
			damage_to_three+=int(event.magnitude);attackers[int(event.actor_id)]=true
	check_eq(attackers.size(),2,"two different actors can damage one target in one turn")
	check_eq(first.state.actors[3].hp,hp_before[3]-damage_to_three,
		"many-to-one damage is aggregated exactly once")
	check(first.state.actors[1].hp<hp_before[1],
		"the target's counterattack also uses the turn-start adjacency state")
	check_eq(first.state.actors[3].memory_for(1).kind,"HARMED","first attack updates one direction")
	check_eq(first.state.actors[3].memory_for(2).kind,"HARMED","second attack updates one direction")
	return finish()

func test_conflicting_move_destinations_choose_one_deterministic_winner()->bool:
	var first=Simulator.new(104);_prepare_move_conflict(first)
	var second=Simulator.new(104);_prepare_move_conflict(second)
	check(first.step().accepted and second.step().accepted,"movement conflict resolves")
	check_eq(first.snapshot(),second.snapshot(),"movement conflict winner is seed deterministic")
	var at_destination:=0
	for actor_id in [1,2]:
		if first.state.actors[actor_id].position==Vector2i(9,9):at_destination+=1
	check_eq(at_destination,1,"only one actor wins the contested destination")
	check_eq(_unique_active_positions(first),first._active_ids().size(),
		"movement never creates active occupancy overlap")
	return finish()

func test_shared_threat_is_directional_support_pressure_not_a_hard_team()->bool:
	var sim=Simulator.new(3)
	for actor_id in range(1,6):sim.state.actors[actor_id].position=Vector2i(7+actor_id,10)
	sim.state.actors[1].species_id="human";sim.state.actors[2].species_id="human"
	sim.state.actors[4].species_id="goblin";sim.state.actors[1].set_memory(2,"HELPED")
	sim.state.turn_index=1;sim.state.world_time=100
	sim._emit("DAMAGE",3,2,"ENGAGE",7,sim.state.actors[2].position)
	var actor_one:Dictionary=sim._decision_breakdown(sim.state.actors[1])
	var shared:Dictionary=_candidate(actor_one,"ENGAGE",3)
	check(_term_input(shared.relation_terms,"shared_threat")==1000,
		"attacking a trusted actor creates shared-threat support pressure")
	check(int(sim.relation_assessment(1,2).effective)>int(sim.relation_assessment(2,1).effective),
		"help memory remains directional even between the same species")
	check(not sim.observation().actors[0].has("team_id"),"same species does not create a hard team")
	return finish()

func test_self_treatment_and_boundary_flee_produce_real_world_events()->bool:
	var treatment=Simulator.new(110);_spread_bystanders(treatment)
	var actor=treatment.state.actors[1];actor.hp=35;actor.supplies=2
	actor.status_effect={"status_id":"BLEEDING","remaining_quanta":3,"tick_damage":3}
	_set_intent(treatment,1,"SELF_TREAT",1);_hold_others(treatment,[1])
	var hp_before:int=actor.hp;var supplies_before:int=actor.supplies
	check(treatment.step().accepted,"self treatment turn resolves")
	check(actor.hp>hp_before and actor.supplies==supplies_before-1,
		"treatment consumes a supply and improves health despite the following DOT tick")
	check(_has_event(treatment,"HEAL",1,1),"treatment emits an exact self-target event")

	var escape=Simulator.new(111);_spread_bystanders(escape)
	escape.state.actors[1].position=Vector2i(1,10);escape.state.actors[2].position=Vector2i(2,10)
	escape.state.actors[1].set_memory(2,"HARMED")
	_set_intent(escape,1,"FLEE",2);_hold_others(escape,[1])
	check(escape.step().accepted,"boundary flee turn resolves")
	check_eq(escape.state.actors[1].presence,"ESCAPED","only a boundary-reaching flee exits the encounter")
	check(_has_event(escape,"ESCAPED",1,2),"escape event keeps the exact pursued threat target")
	return finish()

func test_target_commitment_retains_episode_then_replans_when_target_dies()->bool:
	var sim=Simulator.new(116);_spread_bystanders(sim)
	sim.state.actors[1].position=Vector2i(5,10);sim.state.actors[2].position=Vector2i(10,10)
	_set_intent(sim,1,"APPROACH",2);_hold_others(sim,[1])
	var first:Dictionary=sim.decision_breakdowns()[0]
	check_eq([first.selected_action_id,first.selected_target_id],["APPROACH","2"],
		"target-bound approach begins")
	var first_jitter:=int(_candidate(first,"APPROACH",2).jitter)
	check(sim.step().accepted,"committed approach advances")
	var retained:Dictionary=sim.decision_breakdowns()[0]
	check(bool(retained.continued) and retained.selected_target_id=="2",
		"legal target remains attached to the retained intent")
	check_eq(int(_candidate(retained,"APPROACH",2).jitter),first_jitter,
		"retained episode does not reroll jitter")
	sim.state.actors[2].hp=0;sim.state.actors[2].alive=false;sim.state.actors[2].presence="DEAD"
	var replanned:Dictionary=sim.decision_breakdowns()[0]
	check(not bool(replanned.continued) and replanned.selected_target_id!="2",
		"dead target invalidates commitment and causes target-aware replanning")
	return finish()

func test_save_load_and_command_replay_are_exact_mid_commitment()->bool:
	var sim=Simulator.new(123)
	for _turn in range(3):
		if sim.state.phase=="ACTIVE":check(sim.step().accepted,"source step commits")
	var encoded:String=sim.save_json();var restored=Simulator.new(999)
	check(restored.load_json(encoded).accepted,"strict v3 session loads")
	check_eq(restored.snapshot(),sim.snapshot(),"loaded snapshot is exact")
	check_eq(restored.decision_breakdowns(),sim.decision_breakdowns(),
		"mid-intent episode and target survive save/load")
	if sim.state.phase=="ACTIVE":
		check(sim.step().accepted and restored.step().accepted,"both copies advance")
		check_eq(restored.snapshot(),sim.snapshot(),"command replay remains exact after load")
	var tampered=JSON.parse_string(encoded);tampered.snapshot.schema_version=2
	var target=Simulator.new(321);var before:Dictionary=target.snapshot()
	check(not target.load_json(JSON.stringify(tampered)).accepted,"obsolete/corrupt v2 lab state is rejected")
	check_eq(target.snapshot(),before,"failed load is mutation-pure")
	return finish()

func _prepare_many_to_one(sim)->void:
	var positions:Dictionary={1:Vector2i(9,10),2:Vector2i(10,9),3:Vector2i(10,10),
		4:Vector2i(3,3),5:Vector2i(17,17)}
	for actor_id in range(1,6):
		sim.state.actors[actor_id].position=positions[actor_id]
		sim.state.actors[actor_id].hp=100;sim.state.actors[actor_id].alive=true
		sim.state.actors[actor_id].presence="ACTIVE";sim.state.actors[actor_id].armed=true
		sim.state.actors[actor_id].weapon_id="SWORD"
	_set_intent(sim,1,"ENGAGE",3);_set_intent(sim,2,"ENGAGE",3);_set_intent(sim,3,"ENGAGE",1)
	_hold_others(sim,[1,2,3])

func _prepare_move_conflict(sim)->void:
	var positions:Dictionary={1:Vector2i(8,8),2:Vector2i(10,8),3:Vector2i(10,10),
		4:Vector2i(8,10),5:Vector2i(17,17)}
	for actor_id in range(1,6):sim.state.actors[actor_id].position=positions[actor_id]
	_set_intent(sim,1,"APPROACH",3);_set_intent(sim,2,"APPROACH",4)
	_hold_others(sim,[1,2])

func _spread_bystanders(sim)->void:
	var positions:Dictionary={1:Vector2i(5,10),2:Vector2i(10,10),3:Vector2i(18,2),
		4:Vector2i(18,18),5:Vector2i(2,18)}
	for actor_id in range(1,6):sim.state.actors[actor_id].position=positions[actor_id]

func _hold_others(sim,excluded:Array)->void:
	for actor_id in range(1,6):
		if actor_id not in excluded:_set_intent(sim,actor_id,"HOLD",-1)

func _set_intent(sim,actor_id:int,action_id:String,target_id:int)->void:
	var actor=sim.state.actors[actor_id]
	actor.current_intent_id=action_id;actor.intent_started_turn=sim.state.turn_index
	actor.commitment_until_turn=sim.state.turn_index+10;actor.intent_target_id=target_id
	actor.decision_episode_id=1;actor.intent_interrupt_version=actor.decision_interrupt_version
	actor.intent_reason_code="NEW"

func _candidate(row:Dictionary,action_id:String,target_id:int)->Dictionary:
	for candidate in row.candidates:
		if candidate.action_id==action_id and int(candidate.target_id)==target_id:return candidate
	return {}

func _selected_target_is_valid(row:Dictionary)->bool:
	for candidate in row.candidates:
		if candidate.selected:
			var actor_id:=int(row.actor_id);var target_id:=int(candidate.target_id)
			if candidate.target_role=="OTHER":return target_id>=1 and target_id<=5 and target_id!=actor_id
			if candidate.target_role=="SELF":return target_id==actor_id
			return target_id==-1
	return false

func _term_input(terms:Array,input_id:String)->int:
	for term in terms:
		if term.input_id==input_id:return int(term.input_value)
	return -1

func _unique_active_positions(sim)->int:
	var positions:Dictionary={}
	for actor_id in sim._active_ids():positions[JSON.stringify(sim.state.actors[actor_id].position)]=true
	return positions.size()

func _has_event(sim,type:String,actor_id:int,target_id:int)->bool:
	for event in sim.state.events:
		if event.type==type and int(event.actor_id)==actor_id and int(event.target_id)==target_id:return true
	return false
