extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Blackboard = preload("res://sim/enemy_squad_blackboard.gd")
const Awareness = preload("res://sim/enemy_awareness_state.gd")
const PartyMember = preload("res://sim/party_member_state.gd")
const HexacoProfile = preload("res://sim/dungeon_population/hexaco_profile.gd")

const CI_SEEDS := [21, 22, 23, 24, 25, 26, 27, 28]
const MAX_TURNS := 60


func test_enemy_tactics_seed_matrix_coordinates_without_stall_or_restore_drift() -> bool:
	var metrics := run_matrix(CI_SEEDS, MAX_TURNS)
	print("ENEMY_TACTICS_MATRIX_CI ", JSON.stringify(metrics))
	check_eq(metrics.setup_failures, 0, "every enemy tactics fixture is valid")
	check_eq(metrics.rejected_steps, 0, "enemy squad turns never reject as a batch")
	check_eq(metrics.invalid_worlds, 0, "enemy tactics leave canonical worlds")
	check_eq(metrics.restore_failures, 0, "every accepted turn snapshot restores exactly")
	check_eq(metrics.claim_mismatches, 0, "forecasts consume their shared claims")
	check_eq(metrics.terminal_encounters, metrics.encounters,
		"every multi-enemy encounter reaches a terminal phase")
	check(metrics.claim_decisions > 0 and metrics.focus_claims > 0,
		"matrix exercises shared claims and focus pressure")
	check(metrics.distributed_turns > 0,
		"claim cap distributes enemies across multiple party targets")
	check(metrics.enemy_actions > 0 and metrics.turns >= metrics.encounters,
		"matrix observes real enemy leaves without action stoppage")
	check(metrics.enemy_holds * 100 <= metrics.enemy_actions * 35,
		"enemy HOLD rate stays below the 35% anti-stall bound")
	return finish()


static func run_matrix(seeds: Array, max_turns: int) -> Dictionary:
	var metrics := {"encounters":0, "terminal_encounters":0, "turns":0,
		"setup_failures":0, "rejected_steps":0, "invalid_worlds":0,
		"restore_failures":0, "claim_decisions":0, "claim_mismatches":0,
		"focus_claims":0, "distributed_turns":0, "enemy_actions":0,
		"enemy_holds":0}
	for seed_value in seeds:
		var seed := int(seed_value)
		var session = Session.new(seed, 20260902)
		var state = session.sim.world.party_encounter
		var recruitable_id := _add_recruitable_companion(session, seed)
		if recruitable_id <= 0 or not _spawn_profiled_reinforcements(session, 3):
			metrics.setup_failures += 1
			continue
		var recruit: Dictionary = session.recruit_companion(recruitable_id)
		if not bool(recruit.get("accepted", false)) \
				or not session.commit_exploration(Command.wait(state.protagonist_id)).accepted:
			metrics.setup_failures += 1
			continue
		state = session.sim.world.party_encounter
		session.preview_deployment("WEDGE", session.available_companion_ids())
		if not session.commit_deployment().accepted:
			metrics.setup_failures += 1
			continue
		metrics.encounters += 1
		for _turn in range(max_turns):
			state = session.sim.world.party_encounter
			if state.safe_phase != "ENGAGED":
				break
			var board: Dictionary = Blackboard.build(session.sim.world)
			var distinct_targets := {}
			for enemy_id_value in board.claims:
				var enemy_id := int(enemy_id_value)
				var claimed_target_id := int(board.claims[enemy_id])
				metrics.claim_decisions += 1
				distinct_targets[claimed_target_id] = true
				if claimed_target_id == int(board.focus_target_id):
					metrics.focus_claims += 1
				var forecast: Dictionary = session.sim.party_coordinator \
					.forecast_enemy_action(enemy_id, board)
				if not bool(forecast.get("accepted", false)) \
						or int(forecast.get("target_id", -1)) != claimed_target_id:
					metrics.claim_mismatches += 1
			if distinct_targets.size() >= 2:
				metrics.distributed_turns += 1
			var hero_leaf = session.sim.party_coordinator._suggest(
				state.protagonist_id, Action.hold(state.protagonist_id))
			if not session.begin_turn(hero_leaf).accepted:
				metrics.rejected_steps += 1
				break
			var event_start: int = session.sim.world.events.size()
			var result: Dictionary = session.commit_turn()
			metrics.turns += 1
			if not bool(result.get("accepted", false)):
				metrics.rejected_steps += 1
				break
			state = session.sim.world.party_encounter
			for event_index in range(event_start, session.sim.world.events.size()):
				var event = session.sim.world.events[event_index]
				if int(event.actor_id) in state.enemy_ids \
						and event.type in ["action.move", "action.melee_attack", "action.hold"]:
					metrics.enemy_actions += 1
					if event.type == "action.hold":
						metrics.enemy_holds += 1
			if not session.sim.world.world_state_error().is_empty():
				metrics.invalid_worlds += 1
				break
			var snapshot = session.sim.snapshot()
			var restored = Simulator.from_snapshot(snapshot) \
				if snapshot is Dictionary else null
			if restored == null or restored.snapshot() != snapshot:
				metrics.restore_failures += 1
				break
		if session.sim.world.party_encounter.safe_phase != "ENGAGED":
			metrics.terminal_encounters += 1
	return metrics


static func _add_recruitable_companion(session, seed: int) -> int:
	var world = session.sim.world
	var state = world.party_encounter
	var spawn_position: Vector2i = state.group_anchor + Vector2i(-1, 1)
	var companion = world.add_entity("companion", "보린", spawn_position, 110,
		["party_member", "recruitable"], "dwarf", "party")
	if companion == null:
		return -1
	state.party_member_ids.append(companion.id)
	state.party_member_ids.sort()
	state.member_rows[companion.id] = PartyMember.new(companion.id, 3,
		"COMPANION", "RECRUITABLE", HexacoProfile.generated(seed, companion.id))
	return companion.id if world.world_state_error().is_empty() else -1


static func _spawn_profiled_reinforcements(session, count: int) -> bool:
	var world = session.sim.world
	var state = world.party_encounter
	var origin: Vector2i = state.group_anchor
	for existing_enemy_id in state.enemy_ids:
		var existing_awareness = state.enemy_awareness(existing_enemy_id)
		existing_awareness.awareness_state = "HUNTING"
		existing_awareness.suspicion = 1000
		existing_awareness.last_known_target_position = origin
	var spawned := 0
	for radius in range(3, 8):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				if maxi(absi(x - origin.x), absi(y - origin.y)) != radius:
					continue
				var position := Vector2i(x, y)
				if not world.in_bounds(position):
					continue
				var enemy = world.add_entity("melee_enemy",
					"전술 고블린 %d" % (spawned + 1), position, 60,
					["party_enemy"], "goblin", "enemy")
				if enemy == null:
					continue
				state.enemy_ids.append(enemy.id)
				state.enemy_ids.sort()
				state.enemy_busy_rows[enemy.id] = 0
				var awareness = Awareness.new(enemy.id, enemy.position)
				awareness.awareness_state = "HUNTING"
				awareness.suspicion = 1000
				awareness.last_known_target_position = origin
				state.enemy_awareness_rows[enemy.id] = awareness
				spawned += 1
				if spawned == count:
					return world.world_state_error().is_empty()
	return false
