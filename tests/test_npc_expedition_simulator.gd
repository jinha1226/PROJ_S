extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/npc_expedition/npc_expedition_simulator.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const DecisionRegistry = preload("res://sim/decision_ruleset_registry.gd")


func test_same_seed_replays_identical_decisions_and_world_state() -> bool:
	var first = Simulator.new(7711)
	var second = Simulator.new(7711)
	for _turn in range(24):
		check_eq(first.observation(), second.observation(), "same seed observation remains exact")
		check_eq(first.step(), second.step(), "same seed action remains exact")
	return finish()


func test_one_npc_completes_full_expedition_cycle_with_real_core_verbs() -> bool:
	var simulation = Simulator.new(22002, {"monster_count": 1,
		"monster_move_cost": 130, "monster_attack_cost": 140, "monster_health": 40})
	var seen_phases: Dictionary = {}
	var seen_actions: Dictionary = {}
	var completed := false
	for _turn in range(180):
		var before: Dictionary = simulation.observation()
		seen_phases[str(before.phase)] = true
		var result: Dictionary = simulation.step()
		check(bool(result.get("accepted", false)), "every autonomous action commits")
		seen_actions[str(result.get("action_id", ""))] = true
		if simulation.completed_cycles >= 1:
			completed = true
			break
	check(completed, "one expedition returns to town and finishes recovery")
	for phase in ["TOWN_PREPARE", "DUNGEON_ENTER", "DUNGEON_EXPLORE",
			"DUNGEON_COMBAT", "DUNGEON_LOOT", "DUNGEON_RETURN", "TOWN_RECOVER"]:
		check(seen_phases.has(phase), "cycle visits %s" % phase)
	for action in ["PREPARE", "ENTER", "APPROACH", "ATTACK", "LOOT", "RETURN", "RECOVER"]:
		check(seen_actions.has(action), "cycle executes %s" % action)
	check(simulation.kills >= 1 and simulation.loot_banked >= 1,
		"monster kill produces carried loot that is deposited in town")
	var core_types: Dictionary = {}
	for event in simulation.simulator.world.events:
		core_types[event.type] = true
	check(core_types.has("action.move"), "movement uses shared MovementSystem events")
	check(core_types.has("action.melee_attack"), "combat uses shared MeleeCombatSystem events")
	check(core_types.has("item.picked_up"),
		"loot acquisition uses the shared entity-addressed item transaction")
	return finish()


func test_observation_discloses_goal_personality_inventory_and_candidate_scores() -> bool:
	var simulation = Simulator.new(405)
	check_eq(DecisionRegistry.validation_error(), "", "shared utility registry validates expedition actions")
	var observation: Dictionary = simulation.observation()
	check_eq(observation.map_size, [15, 13], "observer gets exact dungeon bounds")
	check(str(observation.goal).length() > 0, "macro goal is visible")
	check(str(observation.npc.style.label).length() > 0, "HEXACO style summary is visible")
	check_eq(observation.npc.hexaco.keys().size(), 7, "all six HEXACO axes plus schema are exposed")
	check(observation.inventory_labels.has("회복 물약 ×2"),
		"actual inventory contents are visible")
	var decision: Dictionary = observation.decision
	check(str(decision.selected_reason).length() > 0, "selected action has a player-readable reason")
	check(not decision.candidates.is_empty(), "observer receives all candidate rows")
	for row in decision.candidates:
		check(row.has("legal") and row.has("score") and row.has("terms"),
			"candidate exposes legality, total, and contributing terms")
		if bool(row.legal):
			var disclosed_total := 0
			for term in row.terms:
				disclosed_total += int(term.get("value", 0))
			check_eq(disclosed_total, int(row.score),
				"every visible term sums exactly to the candidate score")
	check_eq(decision.ruleset_id, "npc-expedition-utility-v1",
		"observer identifies the shared expedition utility ruleset")
	return finish()


func test_dead_monster_is_rewarded_once_at_step_boundary_even_after_external_transition() -> bool:
	var simulation = Simulator.new(91, {"monster_count": 1,
		"monster_move_cost": 130, "monster_attack_cost": 140, "monster_health": 30})
	_prepare_adjacent_combat(simulation)
	for _attempt in range(24):
		if simulation._life_state(simulation.monster_id) == "DEAD":
			break
		check(simulation._attack(simulation.npc_id, simulation.monster_id, "", "NPC", false),
			"fixture attack commits")
	check_eq(simulation._life_state(simulation.monster_id), "DEAD",
		"fixture reaches a canonical monster death")
	var direct_death_drop_count: int = \
		simulation.simulator.world.item_state.ground_items.rows.size()
	check(direct_death_drop_count >= 2,
		"canonical death already drops the monster's equipped loadout on the ground")
	check_eq(simulation.kills, 0, "attack helper no longer owns kill rewards")
	var result: Dictionary = simulation.step()
	check(str(result.action_id) not in ["ATTACK", "FINISH"],
		"reward is reconciled on a non-attack wrapper step")
	check_eq(simulation.kills, 1, "step-boundary death diff awards exactly one kill")
	check_eq(simulation.simulator.world.item_state.ground_items.rows.size(),
		direct_death_drop_count + 1,
		"the expedition reward is added beside the canonical death drops")
	simulation._reconcile_monster_deaths(0)
	check_eq(simulation.kills, 1, "replaying the same death evidence cannot duplicate rewards")
	check_eq(simulation.simulator.world.item_state.ground_items.rows.size(),
		direct_death_drop_count + 1,
		"reconciliation cannot duplicate loot")
	var property_names: Array[String] = []
	for row in simulation.get_property_list(): property_names.append(str(row.name))
	check("inventory" not in property_names and "ground" not in property_names,
		"the expedition wrapper keeps no second inventory or ground authority")
	check_eq(simulation.simulator.world.world_state_error(), "",
		"the shared item transaction leaves the observed world canonical")
	return finish()


func test_downed_target_is_finished_instead_of_abandoned() -> bool:
	var simulation = Simulator.new(92, {"monster_count": 1,
		"monster_move_cost": 130, "monster_attack_cost": 140, "monster_health": 30})
	_prepare_adjacent_combat(simulation)
	for _attempt in range(24):
		if simulation._life_state(simulation.monster_id) == "DOWNED":
			break
		check(simulation._attack(simulation.npc_id, simulation.monster_id, "", "NPC", false),
			"fixture attack commits")
	check_eq(simulation._life_state(simulation.monster_id), "DOWNED",
		"fixture leaves a finishable target")
	var decision: Dictionary = simulation.decision_breakdown()
	check_eq(decision.selected_action_id, "FINISH",
		"an adjacent downed target selects the explicit finisher")
	var finish_row := _candidate_row(decision, "FINISH")
	check(int(finish_row.score) > int(_candidate_row(decision, "RETURN").score),
		"finish opportunity visibly outweighs an empty-handed return")
	return finish()


func test_seeded_encounters_cover_one_to_three_monsters_and_bounded_speed_variants() -> bool:
	var counts: Dictionary = {}
	var move_costs: Dictionary = {}
	var attack_costs: Dictionary = {}
	for sampled_seed in range(1, 25):
		var simulation = Simulator.new(sampled_seed)
		counts[simulation.monster_ids.size()] = true
		for id in simulation.monster_ids:
			var traits: Dictionary = simulation.monster_traits[id]
			move_costs[int(traits.move_cost)] = true
			attack_costs[int(traits.attack_cost)] = true
			check(int(traits.move_cost) in Simulator.MONSTER_MOVE_COSTS,
				"movement cost stays in the allowed presets")
			check(int(traits.attack_cost) in Simulator.MONSTER_ATTACK_COSTS,
				"attack cost stays in the allowed presets")
	var sampled_counts: Array = counts.keys()
	sampled_counts.sort()
	check_eq(sampled_counts, [1, 2, 3], "seed sampling covers 1–3 monster encounters")
	check(move_costs.size() >= 2 and attack_costs.size() >= 2,
		"seed sampling produces distinct movement and attack speeds")
	return finish()


func test_personality_and_group_threat_change_the_choice_in_the_same_geometry() -> bool:
	var bold = Simulator.new(301, {"monster_count": 1,
		"monster_move_cost": 130, "monster_attack_cost": 140})
	_prepare_adjacent_combat(bold)
	bold.profile = Hexaco.new({"H": 300, "E": 0, "X": 900, "A": 0, "C": 500, "O": 900})
	check_eq(bold.decision_breakdown().selected_action_id, "ATTACK",
		"a bold profile fights one slow adjacent monster")

	var cautious = Simulator.new(301, {"monster_count": 1,
		"monster_move_cost": 130, "monster_attack_cost": 140})
	_prepare_adjacent_combat(cautious)
	cautious.profile = Hexaco.new({"H": 700, "E": 1000, "X": 100, "A": 1000,
		"C": 700, "O": 100})
	check_eq(cautious.decision_breakdown().selected_action_id, "ATTACK",
		"personality does not override a clearly favorable single-enemy outlook")

	var surrounded = Simulator.new(301, {"monster_count": 3,
		"monster_move_cost": 70, "monster_attack_cost": 80})
	_prepare_group_combat(surrounded)
	surrounded.profile = bold.profile
	var group_decision: Dictionary = surrounded.decision_breakdown()
	check_eq(group_decision.selected_action_id, "RETURN",
		"even the bold profile retreats from three fast simultaneous threats")
	check(int(surrounded.observation().threat_milli) > int(bold.observation().threat_milli),
		"number and speed increase the disclosed threat value")
	var surrounded_terminal := ""
	for _turn in range(40):
		surrounded.step()
		if surrounded.phase == "DEAD":
			surrounded_terminal = "DEAD"
			break
		if surrounded.location == "TOWN":
			surrounded_terminal = "TOWN"
			break
	check_eq(surrounded_terminal, "DEAD",
		"three fast adjacent pursuers can kill the NPC during a retreat")
	return finish()


func test_combat_outlook_uses_real_enemy_health_and_escape_geometry() -> bool:
	var bold_profile = Hexaco.new({"H": 300, "E": 0, "X": 900, "A": 0, "C": 500, "O": 900})
	var wounded_pair = Simulator.new(611, {"monster_count": 2,
		"monster_move_cost": 130, "monster_attack_cost": 140, "monster_health": 60})
	_prepare_group_combat(wounded_pair)
	wounded_pair.profile = bold_profile
	wounded_pair._npc().health = 85
	for id in wounded_pair.monster_ids:
		wounded_pair.simulator.world.entities[id].health = 5
	check_eq(wounded_pair.decision_breakdown().selected_action_id, "ATTACK",
		"a bold NPC keeps fighting two slow, heavily wounded adjacent enemies")

	var finishing = Simulator.new(612, {"monster_count": 1,
		"monster_move_cost": 130, "monster_attack_cost": 140, "monster_health": 60})
	_prepare_adjacent_combat(finishing, 85)
	finishing.profile = bold_profile
	finishing._monster().health = 1
	var finish_decision: Dictionary = finishing.decision_breakdown()
	check_eq(finish_decision.selected_action_id, "ATTACK",
		"an injured NPC attacks an adjacent active target with one HP")
	check(int(_candidate_row(finish_decision, "ATTACK").score)
		> int(_candidate_row(finish_decision, "RETURN").score),
		"the visible finish window outweighs retreat for the one-HP target")

	var long_escape = Simulator.new(613, {"monster_count": 1,
		"monster_move_cost": 70, "monster_attack_cost": 80, "monster_health": 40})
	_prepare_adjacent_combat(long_escape)
	long_escape.profile = bold_profile
	long_escape._npc().position = Vector2i(12, 10)
	long_escape._monster().position = Vector2i(11, 10)
	long_escape._refresh_target()
	var escape_decision: Dictionary = long_escape.decision_breakdown()
	check_eq(escape_decision.selected_action_id, "ATTACK",
		"a long exit route with a fast adjacent pursuer can make fighting safer than fleeing")
	check(int(_candidate_row(escape_decision, "ATTACK").score)
		> int(_candidate_row(escape_decision, "RETURN").score),
		"actual route-based escape outlook is disclosed through the candidate totals")
	return finish()


func test_potion_is_selected_then_combat_is_reevaluated_without_rng_consumption() -> bool:
	var simulation = Simulator.new(614, {"monster_count": 1,
		"monster_move_cost": 130, "monster_attack_cost": 140, "monster_health": 40})
	_prepare_adjacent_combat(simulation, 50)
	simulation.profile = Hexaco.new({"H": 300, "E": 0, "X": 900, "A": 0, "C": 700, "O": 900})
	var before: Dictionary = simulation.observation()
	var first: Dictionary = simulation.decision_breakdown()
	var second: Dictionary = simulation.decision_breakdown()
	check_eq(first, second, "repeated decision inspection is deterministic and side-effect free")
	check_eq(before, simulation.observation(), "decision inspection does not consume world state or RNG")
	check_eq(first.selected_action_id, "USE_ITEM", "a seriously injured NPC uses a potion before committing")
	var result: Dictionary = simulation.step()
	check_eq(result.action_id, "USE_ITEM", "the chosen potion action commits through the real simulator")
	check_eq(simulation.decision_breakdown().selected_action_id, "ATTACK",
		"after healing, the same geometry is reevaluated as a viable fight")
	return finish()


func test_hexaco_changes_a_boundary_choice_without_overriding_clear_wins() -> bool:
	var bold = Simulator.new(615, {"monster_count": 1,
		"monster_move_cost": 130, "monster_attack_cost": 140, "monster_health": 40})
	_prepare_adjacent_combat(bold, 64)
	bold.profile = Hexaco.new({"H": 300, "E": 0, "X": 900, "A": 0, "C": 0, "O": 900})
	var cautious = Simulator.new(615, {"monster_count": 1,
		"monster_move_cost": 130, "monster_attack_cost": 140, "monster_health": 40})
	_prepare_adjacent_combat(cautious, 64)
	cautious.profile = Hexaco.new({"H": 700, "E": 1000, "X": 100, "A": 1000, "C": 1000, "O": 100})
	check_eq(bold.decision_breakdown().selected_action_id, "ATTACK",
		"a bold profile takes the boundary fight")
	check_eq(cautious.decision_breakdown().selected_action_id, "USE_ITEM",
		"high conscientiousness raises medicine pressure only when injury exists")
	return finish()


func test_organic_seed_matrix_progresses_without_empty_return_bias() -> bool:
	var initial = Simulator.new(701, {"monster_count": 1,
		"monster_move_cost": 130, "monster_attack_cost": 140, "monster_health": 40})
	# PREPARE, PREPARE, ENTER: no teleporting or awareness override.
	initial.step()
	initial.step()
	initial.step()
	var fresh: Dictionary = initial.observation()
	check_eq(int(fresh.npc.hp), int(fresh.npc.max_hp), "organic entry starts at full HP")
	check_eq(int(fresh.threat_milli), 0, "unalerted opening has no perceived threat")
	check_eq(int(fresh.npc.carried_loot), 0, "organic entry carries no loot")
	check(fresh.decision.selected_action_id != "RETURN",
		"a full-health, threat-free, empty-handed expedition does not return")

	var attacks := 0
	var kills := 0
	var loot_returns := 0
	var empty_returns := 0
	var deaths := 0
	var empty_seed_rows: Array[String] = []
	# Fast CI probe; the release/manual probe uses the same accounting over
	# seeds 1..40 and 400 turns per seed.
	for sampled_seed in range(1, 13):
		var simulation = Simulator.new(sampled_seed)
		var terminal := false
		for _turn in range(180):
			var result: Dictionary = simulation.step()
			check(bool(result.accepted) or simulation.phase == "DEAD",
				"organic seed %d never leaves a rejected autonomous step" % sampled_seed)
			check_eq(simulation.simulator.world.world_state_error(), "",
				"organic seed %d keeps the shared world canonical after every step" % sampled_seed)
			if str(result.action_id) in ["ATTACK", "FINISH"]:
				attacks += 1
			if simulation.phase == "DEAD":
				deaths += 1
				terminal = true
				break
			if simulation.completed_cycles >= 1:
				if simulation.loot_banked > 0:
					loot_returns += 1
				else:
					empty_returns += 1
					empty_seed_rows.append("%d:m%d:k%d" % [sampled_seed,
						simulation.monster_ids.size(), simulation.kills])
				terminal = true
				break
		kills += simulation.kills
		check(terminal, "organic seed %d reaches a first expedition outcome" % sampled_seed)
	print("NPC_ORGANIC_CI seeds=12 attacks=%d kills=%d loot_returns=%d empty_returns=%d deaths=%d" % [
		attacks, kills, loot_returns, empty_returns, deaths])
	print("NPC_ORGANIC_CI empty_seeds=%s" % [",".join(empty_seed_rows)])
	check(attacks > 0 and kills > 0, "organic matrix contains real fights and kills")
	check(loot_returns > 0, "at least one organic expedition returns with loot")
	check(deaths > 0, "at least one organic expedition dies to real danger")
	check(empty_returns <= 2, "empty returns are bounded and cannot dominate the CI probe")
	return finish()


func test_movement_and_attack_costs_create_distinct_pursuit_and_combat_cadence() -> bool:
	var fast_move = Simulator.new(401, {"monster_count": 1,
		"monster_move_cost": 70, "monster_attack_cost": 140})
	var slow_move = Simulator.new(401, {"monster_count": 1,
		"monster_move_cost": 130, "monster_attack_cost": 140})
	_prepare_pursuit(fast_move)
	_prepare_pursuit(slow_move)
	for _turn in range(4):
		fast_move._monster_response()
		slow_move._monster_response()
	var fast_moves := _actor_event_count(fast_move, "action.move", fast_move.monster_id)
	var slow_moves := _actor_event_count(slow_move, "action.move", slow_move.monster_id)
	check(fast_moves > slow_moves, "fast movement closes more tiles over equal response windows")

	var fast_attack = Simulator.new(402, {"monster_count": 1,
		"monster_move_cost": 100, "monster_attack_cost": 80})
	var slow_attack = Simulator.new(402, {"monster_count": 1,
		"monster_move_cost": 100, "monster_attack_cost": 140})
	_prepare_adjacent_combat(fast_attack, 500)
	_prepare_adjacent_combat(slow_attack, 500)
	for _turn in range(4):
		fast_attack._monster_response()
		slow_attack._monster_response()
	var fast_attacks := _actor_event_count(fast_attack, "action.melee_attack", fast_attack.monster_id)
	var slow_attacks := _actor_event_count(slow_attack, "action.melee_attack", slow_attack.monster_id)
	check(fast_attacks > slow_attacks, "fast attacks resolve more often over equal response windows")
	return finish()


func test_shared_line_of_sight_blocks_wall_detection_and_downed_log_is_edge_triggered() -> bool:
	var simulation = Simulator.new(501, {"monster_count": 1})
	simulation.location = "DUNGEON"
	simulation.phase = "DUNGEON_EXPLORE"
	var npc = simulation._npc()
	var monster = simulation._monster()
	npc.position = Vector2i(7, 2)
	monster.position = Vector2i(5, 2)
	simulation._update_monster_awareness(simulation.monster_id)
	check_eq(simulation.monster_awareness[simulation.monster_id].awareness_state, "UNAWARE",
		"the wall at (6,2) blocks perception through the shared LOS rule")
	var before_logs: int = simulation.logs.size()
	npc.health = 0
	simulation.simulator.world.combatant_states[simulation.npc_id].life_state = "DOWNED"
	simulation._reconcile_life()
	simulation._reconcile_life()
	var downed_logs := 0
	for row in simulation.logs.slice(before_logs):
		if str(row.kind) == "DOWNED":
			downed_logs += 1
	check_eq(downed_logs, 1, "DOWNED is logged only on the life-state edge")
	return finish()


func test_seed_matrix_reaches_terminal_outcomes_and_exercises_fight_and_flight() -> bool:
	var high_threat_returns := 0
	var attacks := 0
	for sampled_seed in range(1, 25):
		var simulation = Simulator.new(sampled_seed)
		var terminal := false
		for _turn in range(180):
			var before: Dictionary = simulation.observation()
			if int(before.threat_milli) >= 700 \
					and str(before.decision.selected_action_id) == "RETURN":
				high_threat_returns += 1
			var result: Dictionary = simulation.step()
			check(bool(result.get("accepted", false)), "seed %d autonomous step commits" % sampled_seed)
			if str(result.get("action_id", "")) in ["ATTACK", "FINISH"]:
				attacks += 1
			if simulation.phase == "DEAD":
				terminal = true
				break
			if simulation.completed_cycles >= 1:
				terminal = true
				break
		check(terminal, "seed %d reaches town-cycle completion or death without oscillation" % sampled_seed)
	check(high_threat_returns > 0, "seed matrix contains high-threat retreats")
	check(attacks > 0, "seed matrix still contains committed fights")
	return finish()


func _prepare_adjacent_combat(simulation, npc_health: int = 100) -> void:
	simulation.location = "DUNGEON"
	simulation.phase = "DUNGEON_COMBAT"
	var npc = simulation._npc()
	var monster = simulation._monster()
	npc.max_health = maxi(npc.max_health, npc_health)
	npc.health = npc_health
	npc.position = Vector2i(2, 11)
	monster.position = Vector2i(3, 11)
	var awareness = simulation.monster_awareness[simulation.monster_id]
	awareness.awareness_state = "HUNTING"
	awareness.suspicion = 1000
	simulation._refresh_target()


func _prepare_group_combat(simulation) -> void:
	simulation.location = "DUNGEON"
	simulation.phase = "DUNGEON_COMBAT"
	var npc = simulation._npc()
	npc.position = Vector2i(8, 8)
	var positions := [Vector2i(7, 8), Vector2i(8, 7), Vector2i(9, 8)]
	for index in range(simulation.monster_ids.size()):
		var id: int = int(simulation.monster_ids[index])
		simulation.simulator.world.entities[id].position = positions[index]
		var awareness = simulation.monster_awareness[id]
		awareness.awareness_state = "HUNTING"
		awareness.suspicion = 1000
	simulation._refresh_target()


func _prepare_pursuit(simulation) -> void:
	simulation.location = "DUNGEON"
	simulation.phase = "DUNGEON_RETURN"
	var npc = simulation._npc()
	var monster = simulation._monster()
	npc.position = Vector2i(2, 11)
	monster.position = Vector2i(10, 10)
	var awareness = simulation.monster_awareness[simulation.monster_id]
	awareness.awareness_state = "HUNTING"
	awareness.suspicion = 1000


func _candidate_row(decision: Dictionary, action_id: String) -> Dictionary:
	for row in decision.candidates:
		if str(row.action_id) == action_id:
			return row
	return {}


func _actor_event_count(simulation, event_type: String, actor_id: int) -> int:
	var count := 0
	for event in simulation.simulator.world.events:
		if event.type == event_type and int(event.actor_id) == actor_id:
			count += 1
	return count
