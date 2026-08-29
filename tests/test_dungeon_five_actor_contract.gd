extends "res://tests/test_case.gd"

const Simulator=preload("res://sim/dungeon_population/dungeon_population_simulator.gd")

func test_flee_moves_away_from_the_perceived_threat_set()->bool:
	var sim=Simulator.new(801)
	var positions:Dictionary={1:Vector2i(10,10),2:Vector2i(12,10),3:Vector2i(10,12),
		4:Vector2i(0,0),5:Vector2i(20,20)}
	for actor_id in range(1,6):sim.state.actors[actor_id].position=positions[actor_id]
	var actor=sim.state.actors[1]
	for target_id in [2,3]:
		sim.state.actors[target_id].species_id="goblin"
		sim.state.actors[target_id].power=100
		actor.set_memory(target_id,"HARMED")
	var occupied:Dictionary={}
	for actor_id in sim._active_ids():
		occupied[sim._position_key(sim.state.actors[actor_id].position)]=actor_id
	var destination:Vector2i=sim._flee_destination(actor,2,occupied)
	check_eq(destination,Vector2i(9,9),
		"flee uses the deterministic direction away from both perceived threats")
	for target_id in [2,3]:
		var target:Vector2i=sim.state.actors[target_id].position
		check(destination.distance_squared_to(target)>actor.position.distance_squared_to(target),
			"flee increases distance from every threat in this two-threat fixture")
	return finish()

func test_cross_species_help_can_create_directional_shared_threat_pressure()->bool:
	var sim=Simulator.new(802)
	for actor_id in range(1,6):sim.state.actors[actor_id].position=Vector2i(7+actor_id,10)
	sim.state.actors[1].species_id="human"
	sim.state.actors[2].species_id="dwarf"
	sim.state.actors[3].species_id="goblin"
	sim.state.actors[1].set_memory(2,"HELPED")
	sim.state.turn_index=1;sim.state.world_time=100
	sim._emit("DAMAGE",3,2,"ENGAGE",7,sim.state.actors[2].position)
	check(int(sim.relation_assessment(1,2).effective)>=25,
		"cross-species trust is sufficient to notice a shared threat")
	check_eq(sim._shared_threat(1,3),1000,
		"harm to the trusted other species creates temporary support pressure")
	check_eq(sim._shared_threat(2,3),0,
		"the pressure remains directional instead of becoming a hard team")
	check(not sim.observation().actors[0].has("team_id"),
		"the observation does not expose an inferred faction membership")
	return finish()

func test_escaped_target_interrupts_target_commitment()->bool:
	var sim=Simulator.new(803)
	var positions:Dictionary={1:Vector2i(5,10),2:Vector2i(10,10),3:Vector2i(18,2),
		4:Vector2i(18,18),5:Vector2i(2,18)}
	for actor_id in range(1,6):sim.state.actors[actor_id].position=positions[actor_id]
	var actor=sim.state.actors[1]
	actor.current_intent_id="APPROACH";actor.intent_target_id=2
	actor.intent_started_turn=sim.state.turn_index;actor.commitment_until_turn=10
	actor.decision_episode_id=1;actor.intent_interrupt_version=actor.decision_interrupt_version
	sim.state.actors[2].presence="ESCAPED"
	var row:Dictionary=sim.decision_breakdowns()[0]
	check(not bool(row.continued),"escaped target cannot retain the old commitment")
	check_eq(row.switch_reason_code,"ILLEGAL","lost escaped target reports the canonical interrupt")
	check(int(str(row.selected_target_id))!=2,"replanning cannot select the escaped target")
	return finish()
