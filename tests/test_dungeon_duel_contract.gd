extends "res://tests/test_case.gd"

const Simulator=preload("res://sim/dungeon_population/dungeon_population_simulator.gd")
const Registry=preload("res://sim/dungeon_population/dungeon_action_registry.gd")
const Definition=preload("res://sim/dungeon_population/dungeon_action_definition.gd")

func test_registry_has_only_five_actions_and_generic_extension_executes()->bool:
	var registry=Registry.new()
	check_eq(registry.action_ids(),["APPROACH","ENGAGE","FLEE","HOLD","SELF_TREAT"],
		"product registry exposes only five implemented actions")
	var listen=_listen_definition(2000)
	check(registry.register_definition(listen).accepted,"valid targetless WAIT action registers")
	listen.action_id="MUTATED";listen.score_terms.clear()
	check(registry.action_ids().has("LISTEN") and not registry.action_ids().has("MUTATED") \
		and not registry.definition("LISTEN").score_terms.is_empty(),
		"registry freezes the caller-owned definition")
	var sim=Simulator.new(9,registry);var decisions:Array=sim.decision_breakdowns()
	for row in decisions:check_eq(row.selected_action_id,"LISTEN",
		"generic selector evaluates the added action without central action-id changes")
	check(sim.step().accepted,"generic WAIT execution resolves")
	for action in sim.state.last_resolution.action_rows:
		check_eq([action.action_id,action.target_id],["LISTEN","-1"],
			"generic targetless action reaches canonical resolution")
	return finish()

func test_registry_rejects_unknown_input_and_semantic_noop_definitions()->bool:
	var registry=Registry.new()
	var typo=Definition.new("TYPO_WAIT","WAIT","NONE","NONE",100,[],[
		{"category":"CONTEXT","input_id":"typo","weight_milli":1000}])
	check(not registry.register_definition(typo).accepted,"unknown data input is rejected")
	var no_target=Definition.new("BAD_MELEE","MELEE","NONE","NONE",100,[],[
		{"category":"HEXACO","input_id":"X","weight_milli":100}])
	check(not registry.register_definition(no_target).accepted,"targetless melee no-op is rejected")
	var no_score=Definition.new("BAD_WAIT","WAIT","NONE","NONE",100,[],[])
	check(not registry.register_definition(no_score).accepted,"definition without score semantics is rejected")
	return finish()

func test_registry_manifest_blocks_same_ids_with_changed_weights_mutation_pure()->bool:
	var registry_a=Registry.new();var registry_b=Registry.new()
	check(registry_a.register_definition(_listen_definition(2000)).accepted,"ruleset A registers")
	check(registry_b.register_definition(_listen_definition(1999)).accepted,"ruleset B registers")
	var source=Simulator.new(55,registry_a);check(source.step().accepted,"source advances")
	var target=Simulator.new(777,registry_b);var before:Dictionary=target.snapshot()
	var result:Dictionary=target.load_json(source.save_json())
	check(not result.accepted and result.reason=="duel_registry_ruleset_mismatch",
		"same action ids with different scoring rules are rejected")
	check_eq(target.snapshot(),before,"ruleset mismatch is mutation-pure")
	return finish()

func test_strict_v3_wire_rejects_self_memory_and_colliding_positions()->bool:
	var source=Simulator.new(61);check(source.step().accepted,"source produces a canonical session")
	var memory_tamper=JSON.parse_string(source.save_json())
	memory_tamper.snapshot.actors[0].memories=[{"target_id":"1","kind":"HARMED","modifier":-35}]
	var target=Simulator.new(700);var before:Dictionary=target.snapshot()
	check(not target.load_json(JSON.stringify(memory_tamper)).accepted,
		"directed memory may never target self")
	check_eq(target.snapshot(),before,"memory tamper leaves target untouched")
	var collision=JSON.parse_string(source.save_json())
	collision.snapshot.actors[1].position=collision.snapshot.actors[0].position.duplicate()
	check(not target.load_json(JSON.stringify(collision)).accepted,"active position collision is rejected")
	check_eq(target.snapshot(),before,"position tamper leaves target untouched")
	return finish()

func test_species_prior_stays_dominant_over_one_helped_memory()->bool:
	var sim=Simulator.new(71);var actor=sim.state.actors[1];var target=sim.state.actors[2]
	actor.species_id="human";target.species_id="goblin";actor.set_memory(2,"HELPED")
	var assessment:Dictionary=sim.relation_assessment(1,2)
	check_eq([assessment.species_prior,assessment.memory_modifier],[-75,15],
		"species prior and personal event remain separately auditable")
	check(int(assessment.effective)<0,"one helpful event cannot erase a strongly hostile species prior")
	check_eq(sim.relation_assessment(2,1).memory_kind,"NONE",
		"the opposite direction does not inherit the memory")
	return finish()

func test_terminal_encounter_has_one_or_fewer_active_and_step_is_noop()->bool:
	var sim=Simulator.new(73)
	for actor_id in [2,3,4,5]:sim.state.actors[actor_id].presence="ESCAPED"
	check(sim.step().accepted,"canonical turn projects terminal phase from active population")
	check_eq(sim.state.phase,"COMPLETE","one remaining active actor completes the encounter")
	var before:Dictionary=sim.snapshot();var journal_before:int=sim.command_journal.size()
	check(not sim.step().accepted,"completed encounter rejects later gameplay")
	check_eq(sim.snapshot(),before,"terminal rejection is authoritative-state pure")
	check_eq(sim.command_journal.size(),journal_before,"terminal rejection is journal-pure")
	return finish()

func _listen_definition(weight:int):
	return Definition.new("LISTEN","WAIT","NONE","NONE",1000,[],[
		{"category":"CONTEXT","input_id":"uncertainty","weight_milli":weight},
		{"category":"HEXACO","input_id":"O","weight_milli":2000},
		{"category":"HEXACO","input_id":"C","weight_milli":2000}])
