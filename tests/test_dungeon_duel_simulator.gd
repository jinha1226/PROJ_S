extends "res://tests/test_case.gd"

const Simulator=preload("res://sim/dungeon_population/dungeon_population_simulator.gd")
const State=preload("res://sim/dungeon_population/dungeon_population_state.gd")
const Registry=preload("res://sim/dungeon_population/dungeon_action_registry.gd")
const Definition=preload("res://sim/dungeon_population/dungeon_action_definition.gd")

func test_seeded_two_actor_scenario_and_full_decision_breakdown_are_pure()->bool:
	var first=Simulator.new(77);var second=Simulator.new(77)
	check_eq(first.snapshot(),second.snapshot(),"same seed creates exact scenario")
	var observation:Dictionary=first.observation()
	check_eq([observation.actors.size(),observation.map_size,observation.phase],[2,[15,15],"ACTIVE"],
		"product observation is exactly a two actor scenario")
	var has_facets:=true
	for facet in ["H","E","X","A","C","O"]:
		if not observation.actors[0].hexaco.has(facet):has_facets=false
	check(has_facets,"actor exposes continuous HEXACO axes")
	check(not observation.actors[0].hexaco.has("archetype_id"),"fixed archetype is absent")
	var before:Dictionary=first.snapshot();var decisions:Array=first.decision_breakdowns()
	check_eq(first.snapshot(),before,"decision preview is authoritative-state pure")
	check_eq(decisions.size(),2,"both actors evaluate independently")
	for actor_row in decisions:
		check_eq(actor_row.candidates.size(),5,"five executable MVP candidates")
		var selected_count:=0
		for candidate in actor_row.candidates:
			var computed:int=int(candidate.base)+int(candidate.jitter)
			for bucket in [candidate.hexaco_terms,candidate.state_terms,
					candidate.relation_terms,candidate.context_terms]:
				for term in bucket:computed+=int(term.contribution)
			check_eq(candidate.total,computed,"candidate total is an auditable term sum")
			check(int(candidate.jitter)>=-15 and int(candidate.jitter)<=15,"jitter appears once and is bounded")
			if candidate.selected:
				selected_count+=1;check(candidate.legal,"illegal action is never selected")
			elif not candidate.legal:check(not str(candidate.rejection_reason).is_empty(),"illegal action explains rejection")
		check_eq(selected_count,1,"one selected candidate per living actor")
		check("판단" in str(actor_row.selected_reason_ko),"selected reason is concise Korean")
	var detached:Array=first.decision_breakdowns();detached[0].candidates[0].total=999999
	check(first.decision_breakdowns()[0].candidates[0].total!=999999,"nested decision DTO is detached")
	return finish()

func test_simultaneous_attack_flee_approach_hold_and_status_resolution_update_world()->bool:
	var mutual=Simulator.new(168);var mutual_choices:=mutual.decision_breakdowns()
	check_eq([mutual_choices[0].selected_action_id,mutual_choices[1].selected_action_id],
		["ENGAGE","ENGAGE"],"mutual attack fixture")
	var hp_before:=[mutual.state.actors[1].hp,mutual.state.actors[2].hp]
	check(mutual.step().accepted,"mutual attack resolves")
	check(mutual.state.actors[1].hp<hp_before[0] and mutual.state.actors[2].hp<hp_before[1],
		"both attacks use the same pre-resolution state")
	check_eq([mutual.state.actors[1].memory_kind,mutual.state.actors[2].memory_kind],
		["HARMED","HARMED"],"both recipients remember the attack")

	var attack_flee=Simulator.new(24);var distance_before:int=attack_flee.state.distance
	check_eq([attack_flee.decision_breakdowns()[0].selected_action_id,
		attack_flee.decision_breakdowns()[1].selected_action_id],["ENGAGE","FLEE"],"attack/flee fixture")
	var fleeing_hp:int=attack_flee.state.actors[2].hp
	check(attack_flee.step().accepted,"attack/flee resolves")
	check(attack_flee.state.actors[2].hp<fleeing_hp,"fleeing actor can still take simultaneous adjacent attack")
	check(attack_flee.state.distance>distance_before or not attack_flee.state.actors[2].alive,
		"surviving flee increases distance")

	var approach_hold=Simulator.new(48);var approach_distance:int=approach_hold.state.distance
	check_eq([approach_hold.decision_breakdowns()[0].selected_action_id,
		approach_hold.decision_breakdowns()[1].selected_action_id],["APPROACH","HOLD"],"approach/hold fixture")
	check(approach_hold.step().accepted and approach_hold.state.distance==approach_distance-1,
		"approach moves one unit while hold preserves position")

	var treatment=Simulator.new(77);var treatment_actor=treatment.state.actors[1]
	var supplies_before:int=treatment_actor.supplies;var status_before:Dictionary=treatment_actor.status_effect.duplicate(true)
	check_eq(treatment.decision_breakdowns()[0].selected_action_id,"SELF_TREAT","treatment fixture")
	check(treatment.step().accepted,"self treatment resolves")
	check_eq(treatment_actor.supplies,supplies_before-1,"self treatment consumes one item")
	check(status_before.is_empty() or treatment_actor.status_effect.is_empty() \
		or int(treatment_actor.status_effect.remaining_quanta)<int(status_before.remaining_quanta),
		"self treatment reduces DOT duration before canonical DOT tick")
	return finish()

func test_species_prior_dominates_single_help_memory_and_harm_updates_directionally()->bool:
	var fixture=null
	for seed in range(1,4000):
		var candidate=Simulator.new(seed);var first=candidate.state.actors[1];var second=candidate.state.actors[2]
		var species_pair:=[first.species_id,second.species_id];species_pair.sort()
		if species_pair==["goblin","human"] and first.memory_kind=="HELPED":fixture=candidate;break
	check(fixture!=null,"found deterministic human/goblin helped fixture")
	if fixture!=null:
		var relation:Dictionary=fixture.relation_assessment(1)
		check_eq(relation.species_prior,-75,"human/goblin species prior")
		check_eq(relation.memory_modifier,15,"one helped event is bounded")
		check(int(relation.effective)<0,"single help cannot erase dominant hostile species prior")
	var harmed=Simulator.new(24);var other_memory_before:=str(harmed.state.actors[1].memory_kind)
	harmed.step()
	check_eq(harmed.state.actors[2].memory_kind,"HARMED","attacked actor changes directed memory")
	check_eq(harmed.state.actors[1].memory_kind,other_memory_before,
		"attacker's opposite-direction memory does not change spuriously")
	return finish()

func test_registry_extension_is_frozen_generic_and_rejects_noop_or_unknown_inputs()->bool:
	var registry=Registry.new()
	var typo=Definition.new("TYPO_WAIT","WAIT","NONE","NONE",100,[],[
		{"category":"CONTEXT","input_id":"typo","weight_milli":1000}])
	check(not registry.register_definition(typo).accepted,"unknown input placeholder rejected")
	var no_target=Definition.new("BAD_MELEE","MELEE","NONE","NONE",100,[],[
		{"category":"HEXACO","input_id":"X","weight_milli":100}])
	check(not registry.register_definition(no_target).accepted,"targetless melee placeholder rejected")
	var listen=Definition.new("LISTEN","WAIT","NONE","NONE",1000,[],[
		{"category":"CONTEXT","input_id":"uncertainty","weight_milli":2000}])
	check(registry.register_definition(listen).accepted,"valid generic WAIT definition registered")
	listen.action_id="MUTATED";listen.score_terms.clear()
	check(registry.action_ids().has("LISTEN") and not registry.action_ids().has("MUTATED") \
		and not registry.definition("LISTEN").score_terms.is_empty(),"registry freezes caller-owned definition")
	var sim=Simulator.new(9,registry);var decisions:=sim.decision_breakdowns()
	check_eq([decisions[0].selected_action_id,decisions[1].selected_action_id],["LISTEN","LISTEN"],
		"new definition flows through unchanged generic selector")
	check(sim.step().accepted,"new WAIT definition flows through generic simultaneous executor")
	check("LISTEN" in JSON.stringify(sim.recent_logs()),"new action reaches canonical events")
	var restored=Simulator.new(1,registry)
	check(restored.load_json(sim.save_json()).accepted and restored.snapshot()==sim.snapshot(),
		"custom definition survives generic snapshot journal replay")
	return finish()

func test_committed_counter_moves_run_five_turns_without_ping_pong_or_jitter_reroll()->bool:
	var sim=Simulator.new(6);var action_sets:={1:{},2:{}};var first_jitter:={};var episodes:={}
	for turn in range(5):
		var rows:Array=sim.decision_breakdowns()
		for actor_id in [1,2]:
			var row:Dictionary=rows[actor_id-1];var action_id:=str(row.selected_action_id)
			action_sets[actor_id][action_id]=true
			var candidate:Dictionary=_candidate(row,action_id)
			if turn==0:
				first_jitter[actor_id]=int(candidate.jitter)
				episodes[actor_id]=str(row.decision_episode_id)
			else:
				check(bool(row.continued),"counter-move intent is retained on turn %d actor %d"%[turn,actor_id])
				check_eq(int(candidate.jitter),first_jitter[actor_id],"retained episode never rerolls jitter")
				check_eq(str(row.decision_episode_id),episodes[actor_id],"retained episode id is stable")
		check(sim.step().accepted,"counter-move turn %d commits"%turn)
	check_eq(action_sets[1].keys(),["APPROACH"],"approacher does not oscillate to flee")
	check_eq(action_sets[2].keys(),["FLEE"],"fleeing actor does not oscillate to approach")
	return finish()

func test_material_damage_interrupt_can_switch_a_committed_intent()->bool:
	var sim=Simulator.new(901)
	_prepare_committed_melee_fixture(sim)
	check_eq([sim.decision_breakdowns()[0].selected_action_id,
		sim.decision_breakdowns()[1].selected_action_id],["ENGAGE","ENGAGE"],
		"both actors begin with committed melee")
	check(sim.step().accepted,"material damage fixture resolves")
	var actor_row:Dictionary=sim.decision_breakdowns()[0]
	check_eq(actor_row.switch_reason_code,"INTERRUPT","damage opens an immediate re-evaluation")
	check_eq(actor_row.selected_action_id,"FLEE","injured weaker actor can switch to survival")
	check(not bool(actor_row.continued),"interrupt switch starts a new decision episode")
	return finish()

func test_completed_and_illegal_intents_replan_without_action_id_branches()->bool:
	var completed=Simulator.new(902)
	completed.state.distance=1;completed.state.actors[1].position=Vector2i(6,7)
	completed.state.actors[2].position=Vector2i(7,7)
	_set_committed_intent(completed,1,"APPROACH")
	var completed_row:Dictionary=completed.decision_breakdowns()[0]
	check_eq(completed_row.switch_reason_code,"GOAL_COMPLETE","adjacency completes declarative approach goal")
	check(completed_row.selected_action_id!="APPROACH","completed approach is not retained")

	var illegal=Simulator.new(903)
	illegal.state.distance=1;illegal.state.actors[1].position=Vector2i(6,7)
	illegal.state.actors[2].position=Vector2i(7,7)
	illegal.state.actors[1].armed=false;illegal.state.actors[1].weapon_id="NONE"
	_set_committed_intent(illegal,1,"ENGAGE")
	var illegal_row:Dictionary=illegal.decision_breakdowns()[0]
	check_eq(illegal_row.switch_reason_code,"ILLEGAL","unarmed melee replans immediately")
	check(illegal_row.selected_action_id!="ENGAGE","illegal current intent is never retained")
	return finish()

func test_flee_reaches_a_canonical_escaped_terminal_once()->bool:
	var sim=Simulator.new(6);var steps:=0
	while sim.state.phase=="ACTIVE" and steps<12:
		check(sim.step().accepted,"flee turn %d resolves"%steps);steps+=1
	check_eq(sim.state.phase,"ESCAPED","sustained flee closes the encounter")
	check(sim.state.actors[1].alive and sim.state.actors[2].alive,"escape is distinct from death")
	var escape_events:Array=[]
	for event in sim.state.events:
		if event.type=="ESCAPED":escape_events.append(event)
	check_eq(escape_events.size(),1,"one fleeing actor emits one canonical escape event")
	check_eq(escape_events[0].actor_id,"2","the actor moving away owns the escape event")
	var terminal:Dictionary=sim.snapshot()
	check(not sim.step().accepted and sim.snapshot()==terminal,"escaped encounter rejects later turns purely")
	return finish()

func test_save_mid_commit_preserves_episode_breakdown_and_continuation_exactly()->bool:
	var original=Simulator.new(6)
	check(original.step().accepted and original.state.phase=="ACTIVE","fixture reaches mid-commit state")
	var before_rows:Array=original.decision_breakdowns();var encoded:=original.save_json()
	var loaded=Simulator.new(999)
	check(loaded.load_json(encoded).accepted,"mid-commit session loads")
	check_eq(loaded.snapshot(),original.snapshot(),"intent authority survives save/load")
	check_eq(loaded.decision_breakdowns(),before_rows,"retained reason and episode replay exactly")
	check(original.step().accepted and loaded.step().accepted,"both continuations resolve")
	check_eq(loaded.snapshot(),original.snapshot(),"mid-commit continuation remains exact")
	var tampered:Dictionary=JSON.parse_string(encoded);tampered.snapshot.actors[0].decision_episode_id="01"
	var target=Simulator.new(1000);var target_before:Dictionary=target.snapshot()
	check(not target.load_json(JSON.stringify(tampered)).accepted,"noncanonical intent episode is rejected")
	check_eq(target.snapshot(),target_before,"intent tamper rejection is mutation-pure")
	return finish()

func test_save_load_replay_tamper_and_refresh_are_exact()->bool:
	var sim=Simulator.new(77);var initial:Dictionary=sim.snapshot()
	for index in range(5):sim.observation();sim.decision_breakdowns();sim.recent_logs()
	check_eq(sim.snapshot(),initial,"all refresh DTO paths are pure")
	for index in range(3):check(sim.step().accepted,"canonical step %d accepted"%index)
	check(State.wire_error(sim.snapshot(),sim.registry.action_ids()).is_empty(),"live snapshot validates")
	var restored=Simulator.new(2)
	check(restored.load_json(sim.save_json()).accepted,"session load replays journal")
	check_eq(restored.snapshot(),sim.snapshot(),"save/load/replay exact")
	var tampered:Dictionary=JSON.parse_string(sim.save_json())
	tampered.snapshot.actors[0].entity_id="01"
	var target=Simulator.new(2);var before:Dictionary=target.snapshot()
	check(not target.load_json(JSON.stringify(tampered)).accepted,"noncanonical actor id tamper rejected")
	check_eq(target.snapshot(),before,"failed load is transactional")
	return finish()

func _candidate(row:Dictionary,action_id:String)->Dictionary:
	for value in row.get("candidates",[]):
		if value is Dictionary and str(value.get("action_id",""))==action_id:return value
	return {}

func _set_committed_intent(sim,actor_id:int,action_id:String)->void:
	var actor=sim.state.actors[actor_id];var policy:Dictionary=sim.registry.intent_policy(action_id)
	var execution:Dictionary=sim.registry.execution(action_id);var target_id:=-1
	if execution.target_role=="OTHER":target_id=3-actor_id
	elif execution.target_role=="SELF":target_id=actor_id
	actor.current_intent_id=action_id;actor.intent_started_turn=sim.state.turn_index
	actor.commitment_until_turn=sim.state.turn_index+int(policy.commitment_turns)
	actor.intent_target_id=target_id;actor.decision_episode_id=1
	actor.intent_interrupt_version=actor.decision_interrupt_version;actor.intent_reason_code="NEW"

func _prepare_committed_melee_fixture(sim)->void:
	sim.state.distance=1
	for actor_id in [1,2]:
		var actor=sim.state.actors[actor_id]
		actor.position=Vector2i(6 if actor_id==1 else 7,7);actor.hp=40 if actor_id==1 else 100
		actor.alive=true;actor.armed=true;actor.weapon_id="SWORD";actor.supplies=0
		actor.status_effect={};actor.memory_kind="HARMED";actor.memory_modifier=-35
		actor.species_id="human" if actor_id==1 else "goblin"
		actor.power=20 if actor_id==1 else 100
		for facet in ["H","E","X","A","C","O"]:actor.profile.values[facet]=0
		if actor_id==1:
			actor.profile.values["E"]=1000;actor.profile.values["A"]=1000
		_set_committed_intent(sim,actor_id,"ENGAGE")
