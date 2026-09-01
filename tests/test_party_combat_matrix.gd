extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Request = preload("res://sim/party_turn_request.gd")
const EnemyAwareness = preload("res://sim/enemy_awareness_state.gd")
const PartyMember = preload("res://sim/party_member_state.gd")
const PersonalityRegistry = preload("res://sim/personality_definition_registry.gd")

const CI_SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
const MAX_TURNS := 60


func test_seed_matrix_companions_fight_protect_and_retreat_without_stalling() -> bool:
	var metrics := run_matrix(CI_SEEDS, MAX_TURNS)
	print("PARTY_MATRIX_CI ", JSON.stringify(metrics))
	check_eq(metrics.rejected_steps, 0, "every autonomous party turn commits")
	check_eq(metrics.invalid_worlds, 0, "world stays canonical after every turn")
	check_eq(metrics.disengagements, 0,
		"P1 matrix cannot count perception-driven disengagement as a win")
	check_eq(metrics.setup_failures, 0, "every four-person multi-enemy fixture is valid")
	check_eq(metrics.four_member_encounters, metrics.encounters,
		"every matrix encounter deploys four party members")
	check_eq(metrics.multi_enemy_encounters, metrics.encounters,
		"every matrix encounter contains multiple enemies")
	check(metrics.action_counts.get("HOLD", 0) * 100 \
		<= metrics.companion_decisions * 35,
		"HOLD <= 35% of companion decisions")
	for action_id in ["ENGAGE", "PROTECT", "RETREAT"]:
		check(int(metrics.action_counts.get(action_id, 0)) >= 1,
			"%s occurs in the matrix" % action_id)
	check(metrics.wins * 100 >= metrics.encounters * 40 \
		and metrics.wins * 100 <= metrics.encounters * 90,
		"win rate 40..90%%: %d/%d" % [metrics.wins, metrics.encounters])
	check(metrics.personality_flips * 100 >= metrics.companion_decisions * 3,
		"personality changes >= 3% of decisions")
	return finish()


static func run_matrix(seeds: Array, max_turns: int) -> Dictionary:
	var metrics := {
		"encounters": 0,
		"wins": 0,
		"disengagements": 0,
		"party_deaths": 0,
		"rejected_steps": 0,
		"rejection_reasons": {},
		"rejection_details": [],
		"invalid_worlds": 0,
		"setup_failures": 0,
		"setup_reasons": {},
		"four_member_encounters": 0,
		"multi_enemy_encounters": 0,
		"companion_decisions": 0,
		"personality_flips": 0,
		"action_counts": {},
		"turns": 0,
	}
	for seed in seeds:
		var session = Session.new(int(seed), 20260901)
		var state = session.sim.world.party_encounter
		var recruitable_id := _add_recruitable_companion(session)
		if recruitable_id <= 0:
			_record_setup_failure(metrics, "recruitable_fixture")
			continue
		if not _spawn_reinforcements(session, 3):
			_record_setup_failure(metrics, "reinforcement_fixture")
			continue
		var recruit_result: Dictionary = session.recruit_companion(recruitable_id)
		if not bool(recruit_result.accepted):
			_record_setup_failure(metrics, "recruit:%s" % str(recruit_result.reason))
			continue
		if not session.commit_exploration(Command.wait(state.protagonist_id)).accepted:
			_record_setup_failure(metrics, "contact_wait")
			continue
		state = session.sim.world.party_encounter
		if state.safe_phase != "CONTACT":
			_record_setup_failure(metrics, "contact_phase:%s" % state.safe_phase)
			continue
		session.preview_deployment("WEDGE", session.available_companion_ids())
		if not session.commit_deployment().accepted:
			_record_setup_failure(metrics, "deployment")
			continue
		metrics.encounters += 1
		state = session.sim.world.party_encounter
		if state.active_party_member_ids.size() == 4:
			metrics.four_member_encounters += 1
		if state.enemy_ids.size() > 1:
			metrics.multi_enemy_encounters += 1
		for _turn in range(max_turns):
			state = session.sim.world.party_encounter
			if state.safe_phase != "ENGAGED":
				break
			var hero_leaf = session.sim.party_coordinator._suggest(
				state.protagonist_id, Action.hold(state.protagonist_id))
			var request = Request.new(hero_leaf, [])
			var explanation: Dictionary = session.sim.party_coordinator \
				.explain_companion_turn(request)
			for row in explanation.get("companions", []):
				metrics.companion_decisions += 1
				var action_id := str(row.selected_action_id)
				metrics.action_counts[action_id] = int(
					metrics.action_counts.get(action_id, 0)) + 1
				if _flips_without_personality(row):
					metrics.personality_flips += 1
			var plan = session.sim.preview_party_turn(request)
			var result = session.sim.step_party_turn(plan)
			metrics.turns += 1
			if not bool(result.accepted):
				metrics.rejected_steps += 1
				var reason := str(result.reason)
				metrics.rejection_reasons[reason] = int(
					metrics.rejection_reasons.get(reason, 0)) + 1
				metrics.rejection_details.append({
					"seed": int(seed),
					"turn": _turn,
					"reason": reason,
					"request": request.to_dict(),
					"plan": plan.to_dict(),
				})
				break
			if not session.sim.world.world_state_error().is_empty():
				metrics.invalid_worlds += 1
				break
		state = session.sim.world.party_encounter
		if state.safe_phase in ["GROUPED", "GROUPED_COMPLETE"]:
			var unresolved := false
			for enemy_id in state.enemy_ids:
				if session.sim.world.is_unresolved_enemy(enemy_id):
					unresolved = true
					break
			if unresolved:
				metrics.disengagements += 1
			else:
				metrics.wins += 1
		if state.safe_phase == "PARTY_DEFEATED":
			metrics.party_deaths += 1
	return metrics


static func _record_setup_failure(metrics: Dictionary, reason: String) -> void:
	metrics.setup_failures += 1
	metrics.setup_reasons[reason] = int(metrics.setup_reasons.get(reason, 0)) + 1


static func _add_recruitable_companion(session) -> int:
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
		"COMPANION", "RECRUITABLE", PersonalityRegistry.generate(20260901, 2))
	return companion.id if world.world_state_error().is_empty() else -1


static func _spawn_reinforcements(session, count: int) -> bool:
	var world = session.sim.world
	var state = world.party_encounter
	var origin: Vector2i = state.group_anchor
	# P1 intentionally holds enemy perception constant. A species without a P2
	# perception profile preserves HUNTING while retaining the melee-enemy combat
	# profile, so this matrix cannot silently turn into a disengagement test.
	for existing_enemy_id in state.enemy_ids:
		world.entities[existing_enemy_id].species_id = "human"
		var existing_awareness = state.enemy_awareness(existing_enemy_id)
		existing_awareness.awareness_state = "HUNTING"
		existing_awareness.suspicion = 1000
		existing_awareness.last_known_target_position = origin
	var spawned := 0
	# Stable row-major scan keeps the fixture deterministic while letting the
	# showcase terrain decide which nearby cells can actually host an enemy.
	for radius in range(3, 8):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				if maxi(absi(x - origin.x), absi(y - origin.y)) != radius:
					continue
				var position := Vector2i(x, y)
				if not world.in_bounds(position):
					continue
				var enemy = world.add_entity("melee_enemy",
					"고블린 증원 %d" % (spawned + 1), position, 60,
					["party_enemy"], "human", "enemy")
				if enemy == null:
					continue
				state.enemy_ids.append(enemy.id)
				state.enemy_ids.sort()
				state.enemy_busy_rows[enemy.id] = 0
				var awareness = EnemyAwareness.new(enemy.id, enemy.position)
				awareness.awareness_state = "HUNTING"
				awareness.suspicion = 1000
				awareness.last_known_target_position = origin
				state.enemy_awareness_rows[enemy.id] = awareness
				spawned += 1
				if spawned == count:
					return world.world_state_error().is_empty()
	return false


static func _flips_without_personality(row: Dictionary) -> bool:
	var best := ""
	var best_score := -1000000
	var neutral_best := ""
	var neutral_score := -1000000
	for candidate in row.candidates:
		if not bool(candidate.legal):
			continue
		var without_facets := int(candidate.score)
		for term in candidate.considerations:
			if str(term.input_id).begins_with("facet."):
				without_facets -= int(term.contribution)
		if int(candidate.score) > best_score:
			best_score = int(candidate.score)
			best = str(candidate.action_id)
		if without_facets > neutral_score:
			neutral_score = without_facets
			neutral_best = str(candidate.action_id)
	return best != neutral_best
