extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")


func test_directional_species_baseline_and_neutral_default() -> bool:
	var sim = _relation_sim()
	var goblin = sim.world.entities[1]
	var human = sim.world.entities[2]
	var gh = sim.relationships.effective_relation(goblin.id, human.id)
	var hg = sim.relationships.effective_relation(human.id, goblin.id)
	check_eq(gh.trust, -70, "goblin to human trust")
	check_eq(gh.hostility, 75, "goblin to human hostility")
	check_eq(hg.trust, 5, "directional reverse trust")
	var unknown = sim.world.species_relations.get_relation("elf", "moth")
	check_eq(unknown, {"base_trust": 0, "base_fear": 0, "base_hostility": 0}, "neutral unknown")
	return finish()


func test_one_rescue_creates_gratitude_but_not_trust() -> bool:
	var sim = _relation_sim()
	var source = sim.world.emit_event("social.rescue", 2, 1, Vector2i.ZERO, 50)
	check(sim.relationships.record_aid(1, 2, source.id, 50), "aid accepted")
	var relation = sim.relationships.effective_relation(1, 2)
	check_eq(relation.gratitude, 50, "gratitude")
	check_eq(relation.trust, -65, "small personal trust change")
	check_eq(relation.fear, 33, "small fear relief")
	check_eq(relation.hostility, 70, "conservative gratitude relief")
	check(relation.disposition == "HOSTILE" or relation.disposition == "WARY", "not friendly after one rescue")
	return finish()


func test_effective_lookup_is_sparse_and_personal_direction_is_one_way() -> bool:
	var sim = _relation_sim()
	sim.relationships.effective_relation(1, 2)
	check_eq(sim.world.personal_relations.size(), 0, "read-only lookup creates no personal state")
	var source = sim.world.emit_event("social.rescue", 2, 1, Vector2i.ZERO, 20)
	sim.relationships.record_aid(1, 2, source.id, 20)
	check(sim.world.personal_relations.has("1:2"), "observer to helper relation exists")
	check(not sim.world.personal_relations.has("2:1"), "reverse relation remains absent")
	check_eq(sim.world.personal_relations.size(), 1, "only interacted direction is stored")
	return finish()


func test_repeated_aid_is_bounded_and_duplicate_source_is_ignored() -> bool:
	var sim = _relation_sim()
	var first = sim.world.emit_event("social.rescue", 2, 1, Vector2i.ZERO, 100)
	check(sim.relationships.record_aid(1, 2, first.id, 100), "first aid")
	var event_count: int = sim.world.events.size()
	check(not sim.relationships.record_aid(1, 2, first.id, 100), "duplicate aid rejected")
	check_eq(sim.world.events.size(), event_count, "no duplicate relationship event")
	for index in range(5):
		var source = sim.world.emit_event("social.rescue", 2, 1, Vector2i.ZERO, 100)
		sim.relationships.record_aid(1, 2, source.id, 100)
	var state = sim.world.personal_relations["1:2"]
	check_eq(state.personal_trust_delta, 40, "trust delta upper bound")
	check_eq(sim.relationships.effective_relation(1, 2).trust, -30, "species prior remains dominant")
	return finish()


func test_relation_snapshot_round_trip() -> bool:
	var sim = _relation_sim()
	var aid = sim.world.emit_event("social.rescue", 2, 1, Vector2i.ZERO, 60)
	sim.relationships.record_aid(1, 2, aid.id, 60)
	var harm = sim.world.emit_event("social.attack", 2, 1, Vector2i.ZERO, 20)
	sim.relationships.record_harm(1, 2, harm.id, 20)
	var restored = Simulator.from_snapshot(sim.snapshot())
	check_eq(restored.snapshot(), sim.snapshot(), "relationship snapshot")
	check_eq(restored.relationships.effective_relation(1, 2), sim.relationships.effective_relation(1, 2), "effective relation")
	check(not restored.relationships.record_aid(1, 2, aid.id, 60), "processed ids restored")
	return finish()


func _relation_sim():
	var sim = Simulator.new(2, 1, 19)
	var no_tags: Array[String] = []
	sim.world.add_entity("villager", "Gob", Vector2i.ZERO, 100, no_tags, "goblin")
	sim.world.add_entity("hero", "Human", Vector2i(1, 0), 100, no_tags, "human")
	sim.world.species_relations.set_relation("goblin", "human", -70, 35, 75)
	sim.world.species_relations.set_relation("human", "goblin", 5, 10, 20)
	return sim
