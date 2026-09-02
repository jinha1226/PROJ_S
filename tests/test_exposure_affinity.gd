extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")
const WorldState = preload("res://sim/world_state.gd")
const AffinityRegistry = preload("res://sim/species_hazard_affinity_registry.gd")
const Evaluation = preload("res://sim/exposure_evaluation.gd")


func test_fire_and_wetness_sources_have_strict_semantics() -> bool:
	var producer = Simulator.new(1, 1, 20)
	producer.world.tile_at(Vector2i.ZERO).flammability = 100
	var producer_root = producer.world.emit_event("test.ignite_attempt")
	var producer_before: Dictionary = producer.snapshot()
	var producer_event_id: int = producer.world._next_event_id
	producer.world.begin_step(1)
	check(not producer.environment.try_ignite(
		Vector2i.ZERO, 70, producer_root.id, 1, "test.fire"),
		"unknown fire producer type rejected")
	producer.world.finish_step()
	var expected_after_rejection: Dictionary = producer_before.duplicate(true)
	expected_after_rejection.step_index = "1"
	check_eq(producer.snapshot(), expected_after_rejection, "unknown fire type mutates only outer step")
	check_eq(producer.world._next_event_id, producer_event_id,
		"unknown fire type consumes no event ID")

	var sim = Simulator.new(2, 1, 21)
	sim.world.bootstrap_set_fire(Vector2i.ZERO, 60)
	sim.world.bootstrap_set_wetness(Vector2i(1, 0), 40)
	var direct: Dictionary = sim.snapshot()
	check(direct != null, "valid direct fire/wetness snapshot")
	check_eq(WorldState.snapshot_restore_error(direct), "", "valid sources restore")

	var bad_fire_type: Dictionary = direct.duplicate(true)
	bad_fire_type.events[0].type = "test.fire"
	check_eq(WorldState.snapshot_restore_error(bad_fire_type), "fire_source_type_invalid",
		"fire source type")
	var bad_fire_position: Dictionary = direct.duplicate(true)
	bad_fire_position.events[0].position = [1, 0]
	check_eq(WorldState.snapshot_restore_error(bad_fire_position), "fire_source_position_mismatch",
		"fire source position")
	var bad_direct_eligibility: Dictionary = direct.duplicate(true)
	bad_direct_eligibility.tiles[0].fire_damage_eligible_time = "100"
	check_eq(WorldState.snapshot_restore_error(bad_direct_eligibility),
		"fire_eligibility_source_mismatch", "direct eligibility exact")
	var bad_water_type: Dictionary = direct.duplicate(true)
	bad_water_type.events[1].type = "test.water"
	check_eq(WorldState.snapshot_restore_error(bad_water_type),
		"wetness_source_semantic_invalid", "wetness source type")
	var bad_water_position: Dictionary = direct.duplicate(true)
	bad_water_position.events[1].position = [0, 0]
	check_eq(WorldState.snapshot_restore_error(bad_water_position),
		"wetness_source_semantic_invalid", "wetness source position")
	var bad_water_magnitude: Dictionary = direct.duplicate(true)
	bad_water_magnitude.events[1].magnitude = 0
	check_eq(WorldState.snapshot_restore_error(bad_water_magnitude),
		"wetness_source_semantic_invalid", "wetness source positive magnitude")
	var missing_water: Dictionary = direct.duplicate(true)
	missing_water.tiles[1].wetness_source_event_id = "-1"
	check_eq(WorldState.snapshot_restore_error(missing_water),
		"wetness_source_sentinel_mismatch", "wetness source sentinel")

	var spread = Simulator.new(1, 1, 22)
	spread.world.bootstrap_set_fire(Vector2i.ZERO, 70, "environment.fire_spread")
	var spread_snapshot: Dictionary = spread.snapshot()
	check_eq(spread_snapshot.tiles[0].fire_damage_eligible_time, "100", "spread eligibility")
	check_eq(WorldState.snapshot_restore_error(spread_snapshot), "", "valid spread source")
	var bad_spread: Dictionary = spread_snapshot.duplicate(true)
	bad_spread.tiles[0].fire_damage_eligible_time = "0"
	check_eq(WorldState.snapshot_restore_error(bad_spread),
		"fire_eligibility_source_mismatch", "spread eligibility exact")
	for corrupted in [bad_fire_type, bad_fire_position, bad_direct_eligibility,
		bad_water_type, bad_water_position, bad_water_magnitude, missing_water, bad_spread]:
		check(Simulator.from_snapshot(corrupted) == null, "semantic corruption null restore")
	return finish()


func test_exposure_sample_is_pure_complete_and_uses_shared_fire_projection() -> bool:
	var sim = Simulator.new(1, 1, 23)
	sim.world.bootstrap_set_terrain(Vector2i.ZERO, "shallow_water")
	sim.world.bootstrap_set_fire(Vector2i.ZERO, 50)
	sim.world.bootstrap_set_wetness(Vector2i.ZERO, 20)
	var actor = sim.world.add_entity("human", "Observer", Vector2i.ZERO)
	var before: Dictionary = sim.snapshot()
	var rng_before: int = sim.world.rng.state
	var entity_id_before: int = sim.world._next_entity_id
	var event_id_before: int = sim.world._next_event_id
	var schedule_id_before: int = sim.world.next_schedule_id
	var sample = sim.sample_exposure(Vector2i.ZERO)
	check(sample != null, "sample available at settled boundary")
	check_eq([sample.position, sample.sampled_step_index, sample.sampled_world_time,
		sample.after_event_id, sample.next_environment_time],
		[Vector2i.ZERO, 0, 0, 2, 100], "sample provenance")
	check_eq([sample.terrain_id, sample.passable, sample.move_time_cost],
		["shallow_water", true, 130], "terrain sample")
	check_eq([sample.fire_intensity, sample.known_fire_damage_at_next_tick,
		sample.terrain_water_exposure, sample.wetness, sample.water_exposure,
		sample.conductivity], [50, 20, 80, 20, 80, 80], "exposure values")
	check_eq([sample.electric_risk, sample.electric_certainty, sample.poison_intensity],
		[0, "NONE", 0], "nonpersistent hazards")
	check_eq(sample.source_event_ids, [1, 2], "source IDs sorted unique")
	check_eq(sim.snapshot(), before, "sample snapshot purity")
	check_eq([sim.world.rng.state, sim.world._next_entity_id, sim.world._next_event_id,
		sim.world.next_schedule_id], [rng_before, entity_id_before, event_id_before,
		schedule_id_before], "sample consumes nothing")
	check_eq(typeof(sample.to_dict().sampled_world_time), TYPE_STRING, "sample time canonical")

	var expected_damage: int = sample.known_fire_damage_at_next_tick
	sim.step(Command.wait(actor.id))
	check_eq(actor.health, 100 - expected_damage, "actual tick matches shared projected damage")
	return finish()


func test_exposure_out_of_bounds_active_and_returned_dto_are_detached() -> bool:
	var sim = Simulator.new(1, 1, 24)
	var actor = sim.world.add_entity("human", "Observer", Vector2i.ZERO)
	check(sim.sample_exposure(Vector2i(-1, 0)) == null, "out of bounds sample null")
	sim.world._active_step_index = 1
	check(sim.sample_exposure(Vector2i.ZERO) == null, "partial step sample null")
	sim.world._active_step_index = -1
	var before: Dictionary = sim.snapshot()
	var evaluated = sim.evaluate_exposure_for_entity(actor.id, Vector2i.ZERO)
	var sample = evaluated.sample
	sample.source_event_ids.append(999)
	sample.fire_intensity = 99
	evaluated.affinity.fire_tolerance = -100
	evaluated.evaluation.total_risk = 999
	check_eq(sim.snapshot(), before, "mutated DTO cannot reach world")
	var fresh = sim.evaluate_exposure_for_entity(actor.id, Vector2i.ZERO)
	check_eq([fresh.sample.fire_intensity, fresh.affinity.fire_tolerance,
		fresh.evaluation.total_risk], [0, 20, 0], "fresh detached values")
	check(sim.world.bootstrap_set_combatant_life_state(actor.id, "DEAD"), "dead exposure fixture")
	check(sim.evaluate_exposure_for_entity(actor.id, Vector2i.ZERO) == null,
		"dead entity evaluation null")
	check(sim.evaluate_exposure_for_entity(999, Vector2i.ZERO) == null,
		"missing entity evaluation null")
	return finish()


func test_affinity_registry_profiles_ceil_boundaries_and_species_differences() -> bool:
	var human = AffinityRegistry.affinity_for("human")
	var elf = AffinityRegistry.affinity_for("elf")
	var dwarf = AffinityRegistry.affinity_for("dwarf")
	check_eq(human.to_dict(), {"species_id": "human", "fire_tolerance": 20,
		"water_tolerance": 25, "electric_tolerance": 10, "poison_tolerance": 10},
		"human profile")
	check_eq(elf.to_dict(), {"species_id":"elf","fire_tolerance":20,
		"water_tolerance":25,"electric_tolerance":10,"poison_tolerance":10},
		"new species use the human baseline")
	check_eq(dwarf.to_dict(), {"species_id": "dwarf", "fire_tolerance": 40,
		"water_tolerance": -25, "electric_tolerance": 20, "poison_tolerance": 20},
		"dwarf profile")
	check_eq([Evaluation.component(1, -100), Evaluation.component(1, 0),
		Evaluation.component(1, 50), Evaluation.component(100, 100)], [2, 1, 1, 0],
		"ceil component boundaries")
	check_eq([Evaluation.component(80, 25), Evaluation.component(80, 100),
		Evaluation.component(80, -25)], [60, 0, 100], "water species scores")
	check_eq([Evaluation.component(80, 20), Evaluation.component(80, -25)], [64, 100],
		"fire species scores")
	check_eq(AffinityRegistry.affinity_for("unknown").to_dict(),
		AffinityRegistry.affinity_for("").to_dict(), "unknown and empty use default")
	human.fire_tolerance = -100
	check_eq(AffinityRegistry.affinity_for("human").fire_tolerance, 20,
		"registry affinity detached")
	return finish()


func test_static_water_species_scores_electric_zero_and_json_restore_exact() -> bool:
	var sim = Simulator.new(2, 1, 25)
	sim.world.bootstrap_set_terrain(Vector2i(1, 0), "shallow_water")
	var human = sim.world.add_entity("human", "Human", Vector2i.ZERO, 100, [], "human")
	var sample = sim.sample_exposure(Vector2i(1, 0))
	var human_eval = Evaluation.evaluate(sample, AffinityRegistry.affinity_for("human"))
	var elf_eval = Evaluation.evaluate(sample, AffinityRegistry.affinity_for("elf"))
	var dwarf_eval = Evaluation.evaluate(sample, AffinityRegistry.affinity_for("dwarf"))
	check_eq([human_eval.water_score, elf_eval.water_score, dwarf_eval.water_score],
		[60, 60, 100], "new species use human water affinity while dwarf stays distinct")
	check_eq([human_eval.electric_score, sample.electric_risk, sample.conductivity],
		[0, 0, 60], "conductivity is not persistent electric risk")

	var destination = sim.assess_destination(human.id, Vector2i(1, 0))
	check(destination.traversal.accepted, "destination traversal accepted")
	check_eq([destination.move_time_cost, destination.speed_tier,
		destination.evaluation.water_score], [130, "SLOW", 60],
		"destination combines authoritative timing and hazard")
	var before: Dictionary = sim.snapshot()
	destination.traversal.blocking_entity_ids.append(999)
	destination.sample.water_exposure = 0
	destination.affinity.water_tolerance = -100
	destination.evaluation.total_risk = 999
	check_eq(sim.snapshot(), before, "destination DTO detached")
	check_eq(sim.assess_destination(human.id, Vector2i(1, 0)).move_time_cost, 130,
		"hazard mutation cannot change MOVE cost")

	var restored = Simulator.from_snapshot(JSON.parse_string(JSON.stringify(before)))
	check_eq(restored.sample_exposure(Vector2i(1, 0)).to_dict(), sample.to_dict(),
		"sample exact after JSON restore")
	check_eq(restored.assess_destination(human.id, Vector2i(1, 0)).evaluation.to_dict(),
		human_eval.to_dict(), "evaluation exact after JSON restore")
	return finish()


func test_fire_80_species_scores_and_destination_risk_never_changes_legality() -> bool:
	var human_sim = Simulator.new(2, 1, 26)
	human_sim.world.bootstrap_set_fire(Vector2i(1, 0), 80)
	var human = human_sim.world.add_entity("human", "Human", Vector2i.ZERO, 100, [], "human")
	var human_destination = human_sim.assess_destination(human.id, Vector2i(1, 0))
	check_eq(human_destination.evaluation.fire_score, 64, "human fire 80")
	check(human_destination.traversal.accepted, "hazardous fire remains legal")
	check_eq(human_destination.move_time_cost, 100, "hazard does not change cost")

	var orc_sim = Simulator.new(2, 1, 26)
	orc_sim.world.bootstrap_set_fire(Vector2i(1, 0), 80)
	var orc = orc_sim.world.add_entity("orc","Orc",Vector2i.ZERO,100,[],"orc")
	var orc_destination = orc_sim.assess_destination(orc.id, Vector2i(1, 0))
	check_eq(orc_destination.evaluation.fire_score,64,"orc uses human fire baseline")
	check(orc_destination.traversal.accepted,"hazard does not block MOVE")
	check_eq(orc_destination.move_time_cost,100,"hazard does not change MOVE cost")
	return finish()


func test_destination_inspection_reports_terrain_cost_even_when_not_adjacent() -> bool:
	var sim = Simulator.new(3, 1, 27)
	sim.world.bootstrap_set_terrain(Vector2i(2, 0), "shallow_water")
	var actor = sim.world.add_entity("human", "Inspector", Vector2i.ZERO, 100, [], "human")
	var distant = sim.assess_destination(actor.id, Vector2i(2, 0))
	check(not distant.traversal.accepted, "distant destination is not a legal one-step MOVE")
	check_eq(distant.traversal.reason, "move_not_adjacent", "distant reason")
	check_eq([distant.sample.move_time_cost, distant.move_time_cost, distant.speed_tier],
		[130, 130, "SLOW"], "inspection still reports authoritative terrain timing")
	var current = sim.assess_destination(actor.id, Vector2i.ZERO)
	check_eq([current.traversal.accepted, current.move_time_cost, current.speed_tier],
		[false, 100, "NORMAL"], "current tile inspection has terrain timing")
	return finish()
