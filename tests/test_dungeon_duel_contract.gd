extends "res://tests/test_case.gd"

const SimulatorScript = preload("res://sim/dungeon_population/dungeon_population_simulator.gd")
const RegistryScript = preload("res://sim/dungeon_population/dungeon_action_registry.gd")
const DefinitionScript = preload("res://sim/dungeon_population/dungeon_action_definition.gd")


func test_seeded_scenario_and_directional_breakdowns_repeat_exactly_and_are_pure() -> bool:
	var first = SimulatorScript.new(22002)
	var second = SimulatorScript.new(22002)
	var initial: Dictionary = first.snapshot()
	check_eq(second.snapshot(), initial, "same seed creates exact same two-person scenario")
	var rows: Array = first.decision_breakdowns()
	check_eq(rows.size(), 2, "one independent breakdown per actor")
	if rows.size() == 2:
		check_eq([rows[0].actor_id, rows[1].actor_id], ["1", "2"],
			"directional breakdown order is canonical")
		check_eq(_candidate_ids(rows[0]), first.registry.action_ids(),
			"actor A evaluates the complete registered catalog")
		check_eq(_candidate_ids(rows[1]), first.registry.action_ids(),
			"actor B evaluates the complete registered catalog independently")
	check_eq(first.snapshot(), initial, "decision breakdown is snapshot-pure")
	var detached: Array = first.decision_breakdowns()
	if not detached.is_empty() and not detached[0].candidates.is_empty():
		detached[0].candidates[0].total = -999999
		check(first.decision_breakdowns()[0].candidates[0].total != -999999,
			"breakdown DTO is detached")
	var first_step: Dictionary = first.step()
	check(first_step.accepted, "seeded scenario advances")
	check(first.restart_same_scenario().accepted, "same-scenario restart accepted")
	check_eq(first.snapshot(), initial, "same-scenario restart restores exact identity and state")
	check(first.new_random_scenario(22003).accepted, "explicit new seeded scenario accepted")
	check(first.snapshot() != initial and str(first.snapshot().seed) == "22003",
		"different seed creates a distinct reproducible scenario")
	return finish()


func test_directional_relation_inputs_use_each_actors_own_memory() -> bool:
	var sim = SimulatorScript.new(41001)
	var actor_a = sim.state.actors[1]
	var actor_b = sim.state.actors[2]
	actor_a.species_id = "human"
	actor_b.species_id = "goblin"
	actor_a.memory_kind = "HELPED"
	actor_a.memory_modifier = 15
	actor_b.memory_kind = "HARMED"
	actor_b.memory_modifier = -35
	var before: Dictionary = sim.snapshot()
	var rows: Array = sim.decision_breakdowns()
	var engage_a: Dictionary = _candidate(rows, 1, "ENGAGE")
	var engage_b: Dictionary = _candidate(rows, 2, "ENGAGE")
	check_eq(_term_input(engage_a.get("relation_terms", []), "species_prior"), -75,
		"A toward B uses human-goblin species prior")
	check_eq(_term_input(engage_b.get("relation_terms", []), "species_prior"), -75,
		"B toward A independently uses the pair prior")
	check_eq(_term_input(engage_a.get("relation_terms", []), "memory_modifier"), 15,
		"A toward B uses A's HELPED memory")
	check_eq(_term_input(engage_b.get("relation_terms", []), "memory_modifier"), -35,
		"B toward A uses B's HARMED memory")
	check_eq(sim.snapshot(), before, "directional evaluation does not share or mutate memory")
	return finish()


func test_hexaco_monotonicity_and_additive_breakdown_contract() -> bool:
	var sim = SimulatorScript.new(42002)
	var actor = sim.state.actors[1]
	actor.hp = 55
	actor.supplies = 1
	actor.status_effect = {"status_id":"BLEEDING", "remaining_quanta":3, "tick_damage":3}
	actor.memory_kind = "HARMED"
	actor.memory_modifier = -35
	actor.profile.values["E"] = 100
	var flee_low_e := _candidate_for(sim, 1, "FLEE")
	actor.profile.values["E"] = 900
	var flee_high_e := _candidate_for(sim, 1, "FLEE")
	check(int(flee_high_e.total) >= int(flee_low_e.total),
		"higher E never lowers FLEE utility under the same danger")
	check_eq(int(flee_high_e.total) - int(flee_low_e.total), 208,
		"E contribution is linear rather than a profile-combination branch")

	actor.profile.values["A"] = 900
	var engage_high_a := _candidate_for(sim, 1, "ENGAGE")
	actor.profile.values["A"] = 100
	var engage_low_a := _candidate_for(sim, 1, "ENGAGE")
	check(int(engage_low_a.total) >= int(engage_high_a.total),
		"lower A never lowers ENGAGE utility after grievance")
	check_eq(int(engage_low_a.total) - int(engage_high_a.total), 192,
		"A contribution is independently additive")

	actor.profile.values["C"] = 100
	var treat_low_c := _candidate_for(sim, 1, "SELF_TREAT")
	actor.profile.values["C"] = 900
	var treat_high_c := _candidate_for(sim, 1, "SELF_TREAT")
	check(bool(treat_low_c.legal) and bool(treat_high_c.legal), "treatment fixture is legal")
	check(int(treat_high_c.total) >= int(treat_low_c.total),
		"higher C never lowers SELF_TREAT utility when treatment is possible")
	check_eq(int(treat_high_c.total) - int(treat_low_c.total), 176,
		"C contribution is independently additive")

	for row in sim.decision_breakdowns():
		for candidate in row.candidates:
			var rebuilt := int(candidate.base) + int(candidate.jitter)
			for bucket_name in ["hexaco_terms", "state_terms", "relation_terms", "context_terms"]:
				for term in candidate[bucket_name]:
					rebuilt += int(term.contribution)
			check_eq(int(candidate.total), rebuilt,
				"%s jitter is applied once after additive terms" % candidate.action_id)
	return finish()


func test_low_hp_and_dot_raise_survival_action_pressure() -> bool:
	var sim = SimulatorScript.new(43003)
	var actor = sim.state.actors[1]
	actor.supplies = 1
	actor.status_effect = {}
	actor.hp = 100
	var flee_healthy := _candidate_for(sim, 1, "FLEE")
	var treat_healthy := _candidate_for(sim, 1, "SELF_TREAT")
	check(not bool(treat_healthy.legal), "healthy actor cannot select unnecessary treatment")
	actor.hp = 30
	var flee_injured := _candidate_for(sim, 1, "FLEE")
	check(int(flee_injured.total) > int(flee_healthy.total), "low HP raises FLEE utility")
	actor.hp = 100
	actor.status_effect = {"status_id":"POISONED", "remaining_quanta":4, "tick_damage":3}
	var treat_dot := _candidate_for(sim, 1, "SELF_TREAT")
	check(bool(treat_dot.legal), "DOT makes SELF_TREAT legal with supplies")
	check(int(treat_dot.total) > int(treat_healthy.total), "DOT raises SELF_TREAT utility")
	return finish()


func test_species_prior_remains_dominant_over_one_helped_memory() -> bool:
	var sim = SimulatorScript.new(44004)
	var actor = sim.state.actors[1]
	var other = sim.state.actors[2]
	actor.species_id = "human"
	other.species_id = "goblin"
	actor.memory_kind = "HELPED"
	actor.memory_modifier = 15
	var assessment: Dictionary = sim.relation_assessment(1)
	check(assessment.accepted, "directional relation assessment accepted")
	check_eq(assessment.species_prior, -75, "hostile interspecies prior is authoritative")
	check_eq(assessment.memory_modifier, 15, "one helped memory is retained")
	check_eq(assessment.effective, -60, "help does not immediately erase species distrust")
	check(absi(int(assessment.species_prior)) > absi(int(assessment.memory_modifier)),
		"species prior is numerically dominant")
	return finish()


func test_registry_extension_is_generic_detached_and_rejects_placeholders() -> bool:
	var registry = RegistryScript.new()
	var original_ids: Array = registry.action_ids()
	var typo_placeholder = DefinitionScript.new("TYPO_WAIT", "WAIT", "NONE", "NONE", 999, [], [
		{"category":"CONTEXT", "input_id":"not_a_real_input", "weight_milli":1000}])
	var typo_result: Dictionary = registry.register_definition(typo_placeholder)
	check(not typo_result.accepted and registry.action_ids() == original_ids,
		"unknown-input placeholder is rejected without catalog mutation")
	var targetless_melee = DefinitionScript.new("TARGETLESS", "MELEE", "SELF", "NONE", 100, [], [
		{"category":"HEXACO", "input_id":"X", "weight_milli":100}])
	check(not registry.register_definition(targetless_melee).accepted,
		"atomic semantic placeholder is rejected")

	var fixture = DefinitionScript.new("FIXTURE_RETREAT", "MOVE", "OTHER", "AWAY", 1000, [], [
		{"category":"CONTEXT", "input_id":"uncertainty", "weight_milli":2000}])
	check(registry.register_definition(fixture).accepted, "fixture action registers through public registry API")
	fixture.action_id = "MUTATED_AFTER_REGISTER"
	fixture.score_terms[0].weight_milli = 0
	check(registry.action_ids().has("FIXTURE_RETREAT") \
		and not registry.action_ids().has("MUTATED_AFTER_REGISTER"), "registry stores a detached definition")
	check_eq(registry.definition("FIXTURE_RETREAT").score_terms[0].weight_milli, 2000,
		"registered score terms are detached from caller mutation")

	var sim = SimulatorScript.new(45005, registry)
	_prepare_neutral_movement_fixture(sim)
	var before_positions := [sim.state.actors[1].position, sim.state.actors[2].position]
	var rows: Array = sim.decision_breakdowns()
	check_eq([rows[0].selected_action_id, rows[1].selected_action_id],
		["FIXTURE_RETREAT", "FIXTURE_RETREAT"],
		"new definition participates in the unchanged central selector")
	var result: Dictionary = sim.step()
	check(result.accepted, "registered fixture resolves through generic atomic executor")
	check(sim.state.actors[1].position.x < before_positions[0].x \
		and sim.state.actors[2].position.x > before_positions[1].x,
		"fixture MOVE resolves for both directions without scheduler-specific code")
	check_eq(sim.state.distance, 7, "simultaneous fixture movement updates canonical distance")
	# Direct state shaping above is intentionally not journaled. Use a fresh seeded
	# instance to prove the same generic definition also participates in replay.
	var replayable = SimulatorScript.new(45005, registry)
	var replay_rows: Array = replayable.decision_breakdowns()
	check_eq([replay_rows[0].selected_action_id, replay_rows[1].selected_action_id],
		["FIXTURE_RETREAT", "FIXTURE_RETREAT"], "fixture wins an unmodified seeded scenario")
	check(replayable.step().accepted, "unmodified custom-registry turn resolves")
	var encoded: String = replayable.save_json()
	var restored = SimulatorScript.new(1, registry)
	check(restored.load_json(encoded).accepted, "custom registered action survives save/replay")
	check_eq(restored.snapshot(), replayable.snapshot(), "custom registry continuation restores exactly")
	return finish()


func test_illegal_candidates_never_win_and_explain_rejection() -> bool:
	var sim = SimulatorScript.new(46006)
	var actor = sim.state.actors[1]
	actor.armed = false
	actor.weapon_id = "NONE"
	actor.supplies = 0
	actor.hp = 20
	actor.status_effect = {"status_id":"BLEEDING", "remaining_quanta":3, "tick_damage":3}
	sim.state.distance = 1
	sim.state.actors[1].position = Vector2i(6, 7)
	sim.state.actors[2].position = Vector2i(7, 7)
	var row: Dictionary = sim.decision_breakdowns()[0]
	for action_id in ["APPROACH", "ENGAGE", "SELF_TREAT"]:
		var candidate := _candidate([row], 1, action_id)
		check(not bool(candidate.legal), "%s is illegal in the fixture" % action_id)
		check(not bool(candidate.selected) and not str(candidate.rejection_reason).is_empty(),
			"%s cannot win and explains why" % action_id)
	var selected_count := 0
	for candidate in row.candidates:
		if bool(candidate.selected):
			selected_count += 1
			check(bool(candidate.legal), "selected action is legal")
	check_eq(selected_count, 1, "exactly one legal action is selected")
	return finish()


func test_simultaneous_melee_preserves_both_intents_and_canonical_event_order() -> bool:
	var sim = SimulatorScript.new(47007)
	_prepare_mutual_lethal_fixture(sim)
	var decisions: Array = sim.decision_breakdowns()
	check_eq([decisions[0].selected_action_id, decisions[1].selected_action_id],
		["ENGAGE", "ENGAGE"], "both actors freeze an ENGAGE intent from the same pre-state")
	var result: Dictionary = sim.step()
	check(result.accepted, "simultaneous lethal turn resolves")
	check_eq([sim.state.actors[1].hp, sim.state.actors[2].hp], [0, 0],
		"first resolved death cannot erase the other's frozen attack")
	check_eq([sim.state.actors[1].memory_kind, sim.state.actors[2].memory_kind],
		["HARMED", "HARMED"], "both directional grievance memories update")
	check_eq(sim.state.phase, "COMPLETE", "mutual lethal result closes the duel")
	var types: Array = []
	for event in sim.state.events: types.append(str(event.type))
	check_eq(types, ["ACTION", "ACTION", "DAMAGE", "DAMAGE", "MEMORY", "MEMORY", "DEATH", "DEATH"],
		"simultaneous event order is canonical and actor-order independent of death")
	check_eq(sim.state.last_resolution.action_rows,
		[{"actor_id":"1", "action_id":"ENGAGE"}, {"actor_id":"2", "action_id":"ENGAGE"}],
		"resolution stores both frozen actions")
	return finish()


func test_snapshot_save_load_replay_and_tamper_rejection_are_exact() -> bool:
	var original = SimulatorScript.new(48008)
	var initial: Dictionary = original.snapshot()
	var detached: Dictionary = original.snapshot()
	detached.actors[0].hp = 1
	check_eq(original.snapshot(), initial, "snapshot DTO is detached")
	var accepted_steps := 0
	for _index in range(3):
		if original.state.phase != "ACTIVE": break
		var result: Dictionary = original.resolve_turn()
		check(result.accepted, "replay fixture step accepted")
		accepted_steps += 1
	var encoded: String = original.save_json()
	var loaded = SimulatorScript.new(999)
	check(loaded.load_json(encoded).accepted, "canonical session loads")
	check_eq(loaded.snapshot(), original.snapshot(), "save/load restores exact snapshot")
	var replay = SimulatorScript.new(48008)
	for _index in range(accepted_steps): check(replay.step().accepted, "journal replay step accepted")
	check_eq(replay.snapshot(), original.snapshot(), "same seed plus STEP journal replays exactly")
	if original.state.phase == "ACTIVE":
		var original_next: Dictionary = original.step()
		var loaded_next: Dictionary = loaded.step()
		check_eq(loaded_next, original_next, "loaded continuation result is exact")
		check_eq(loaded.snapshot(), original.snapshot(), "loaded continuation snapshot is exact")
	var before_reject: Dictionary = loaded.snapshot()
	var tampered: Dictionary = JSON.parse_string(encoded)
	tampered["unexpected"] = true
	var rejection: Dictionary = loaded.load_json(JSON.stringify(tampered))
	check(not rejection.accepted, "unknown session field is rejected")
	check_eq(loaded.snapshot(), before_reject, "tampered load is mutation-pure")
	return finish()


func test_save_rejects_same_action_ids_with_a_different_registry_ruleset() -> bool:
	var registry_a = RegistryScript.new()
	var registry_b = RegistryScript.new()
	var definition_a = DefinitionScript.new("RULESET_PROBE", "WAIT", "NONE", "NONE", 1000, [], [
		{"category":"CONTEXT", "input_id":"uncertainty", "weight_milli":2000}])
	var definition_b = DefinitionScript.new("RULESET_PROBE", "WAIT", "NONE", "NONE", 1000, [], [
		{"category":"CONTEXT", "input_id":"uncertainty", "weight_milli":1999}])
	check(registry_a.register_definition(definition_a).accepted \
		and registry_b.register_definition(definition_b).accepted,
		"same action identity can represent two deliberately distinct test rulesets")
	var source = SimulatorScript.new(49009, registry_a)
	var source_rows: Array = source.decision_breakdowns()
	check_eq([source_rows[0].selected_action_id, source_rows[1].selected_action_id],
		["RULESET_PROBE", "RULESET_PROBE"], "ruleset probe owns the saved turn")
	check(source.step().accepted, "ruleset probe turn saves")
	var target = SimulatorScript.new(123, registry_b)
	var target_before: Dictionary = target.snapshot()
	var load_result: Dictionary = target.load_json(source.save_json())
	check(not load_result.accepted,
		"save is rejected when action IDs match but authoritative definition weights differ")
	check_eq(target.snapshot(), target_before, "ruleset mismatch rejection is mutation-pure")
	return finish()


func _candidate_for(sim, actor_id: int, action_id: String) -> Dictionary:
	return _candidate(sim.decision_breakdowns(), actor_id, action_id)


func _candidate(rows: Array, actor_id: int, action_id: String) -> Dictionary:
	for row in rows:
		if int(str(row.get("actor_id", "-1"))) != actor_id: continue
		for candidate in row.get("candidates", []):
			if str(candidate.get("action_id", "")) == action_id: return candidate
	return {}


func _candidate_ids(row: Dictionary) -> Array:
	var result: Array = []
	for candidate in row.get("candidates", []): result.append(str(candidate.action_id))
	return result


func _term_input(rows: Array, input_id: String) -> int:
	for row in rows:
		if str(row.get("input_id", "")) == input_id: return int(row.input_value)
	return -999999


func _prepare_neutral_movement_fixture(sim) -> void:
	sim.state.distance = 5
	for entity_id in [1, 2]:
		var actor = sim.state.actors[entity_id]
		actor.position = Vector2i(4 if entity_id == 1 else 9, 7)
		actor.species_id = "human"
		actor.hp = 100
		actor.alive = true
		actor.power = 50
		actor.supplies = 0
		actor.status_effect = {}
		actor.memory_kind = "NONE"
		actor.memory_modifier = 0
		for facet in ["H", "E", "X", "A", "C", "O"]: actor.profile.values[facet] = 0


func _prepare_mutual_lethal_fixture(sim) -> void:
	sim.state.distance = 1
	for entity_id in [1, 2]:
		var actor = sim.state.actors[entity_id]
		actor.position = Vector2i(6 if entity_id == 1 else 7, 7)
		actor.species_id = "human" if entity_id == 1 else "goblin"
		actor.hp = 12
		actor.alive = true
		actor.armed = true
		actor.weapon_id = "SWORD"
		actor.power = 100
		actor.supplies = 0
		actor.status_effect = {}
		actor.memory_kind = "HARMED"
		actor.memory_modifier = -35
		for facet in ["H", "E", "X", "A", "C", "O"]: actor.profile.values[facet] = 0
		actor.current_intent_id = "ENGAGE"
		actor.intent_started_turn = sim.state.turn_index
		actor.commitment_until_turn = sim.state.turn_index + int(sim.registry.intent_policy("ENGAGE").commitment_turns)
		actor.intent_target_id = 3 - entity_id
		actor.decision_episode_id = 1
		actor.intent_interrupt_version = actor.decision_interrupt_version
		actor.intent_reason_code = "NEW"
		actor.profile.values["X"] = 1000
