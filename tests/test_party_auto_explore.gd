extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const TerrainRegistry = preload("res://sim/terrain_registry.gd")


func test_auto_explore_is_deterministic_and_commits_at_most_one_canonical_hop_per_call() -> bool:
	var first = _safe_product_session(44)
	var second = _safe_product_session(44)
	var first_start: Dictionary = first.start_auto_explore()
	var second_start: Dictionary = second.start_auto_explore()
	check(first_start.running and first_start.advanced,
		"start immediately commits one safe frontier hop")
	check_eq([first.sim.world.step_index, first.command_journal.size()], [1, 1],
		"start uses one canonical exploration journal primitive")
	check_eq([first_start.target, first_start.next_position],
		[second_start.target, second_start.next_position],
		"same canonical state has deterministic frontier and first hop")
	check_eq(first.command_journal, second.command_journal,
		"deterministic tie break produces the same canonical journal")
	var guard := 0
	var stopped: Dictionary = first_start
	while bool(stopped.get("running", false)) and guard < 32:
		var journal_before: int = first.command_journal.size()
		var step_before: int = first.sim.world.step_index
		stopped = first.continue_auto_explore()
		var journal_delta: int = first.command_journal.size() - journal_before
		var step_delta: int = first.sim.world.step_index - step_before
		check(journal_delta in [0, 1] and step_delta == journal_delta,
			"continue call commits zero or one canonical hop, never more")
		if bool(stopped.get("advanced", false)):
			check_eq(journal_delta, 1,
				"advanced DTO corresponds to exactly one journal row")
		guard += 1
	check(guard < 32, "product auto explore reaches an explicit safety stop")
	check_eq(stopped.stop_reason, "auto_explore_hazard_discovered",
		"new affinity-unsafe visible hazard stops immediately after reveal")
	check(stopped.advanced and int(stopped.steps_committed) == first.command_journal.size(),
		"post-hop safety stop preserves the final committed-hop signal")
	return finish()


func test_auto_explore_never_projects_hidden_hazard_or_actor_into_frontier_choice() -> bool:
	var baseline = _safe_product_session(51)
	var hazardous = _safe_product_session(51)
	var hidden := _hidden_passable_cell(hazardous)
	check(hidden != Vector2i(-1, -1), "hidden passable hazard fixture exists")
	check(hazardous.sim.world.bootstrap_set_fire(hidden, 100) != null,
		"hidden fire fixture is canonical world state")
	var hidden_key := _key(hidden)
	var safe_snapshot: Dictionary = hazardous._auto_explore_fog_snapshot()
	check(not safe_snapshot.cells.has(hidden_key) and not safe_snapshot.hazards.has(hidden_key),
		"fog snapshot omits hidden terrain row and live hazard")
	var baseline_result: Dictionary = baseline.start_auto_explore()
	var hazardous_result: Dictionary = hazardous.start_auto_explore()
	check_eq([hazardous_result.target, hazardous_result.next_position],
		[baseline_result.target, baseline_result.next_position],
		"hidden hazard cannot alter deterministic frontier or next hop")
	check_eq(hazardous.command_journal, baseline.command_journal,
		"hidden hazard cannot alter canonical first move")
	return finish()


func test_auto_explore_stops_for_enemy_health_cancel_and_no_frontier_without_extra_turn() -> bool:
	var enemy_visible = Session.new(44, 20260828, "SOLO_COMBAT_V1")
	var enemy_before: int = enemy_visible.sim.world.step_index
	var enemy_stop: Dictionary = enemy_visible.start_auto_explore()
	check_eq([enemy_stop.running, enemy_stop.stop_reason,
		enemy_visible.sim.world.step_index - enemy_before],
		[false, "auto_explore_enemy_visible", 0],
		"visible enemy blocks AUTO EXPLORE before any turn")

	var injured = _safe_product_session(44)
	check(injured.start_auto_explore().running, "health-stop fixture starts")
	var injured_state = injured.sim.world.party_encounter
	var hero_id := int(injured_state.protagonist_id)
	injured.sim.world.entities[hero_id].health -= 1
	var injury_before: int = injured.sim.world.step_index
	var injury_stop: Dictionary = injured.continue_auto_explore()
	check_eq([injury_stop.running, injury_stop.stop_reason,
		injured.sim.world.step_index - injury_before],
		[false, "auto_explore_health_changed", 0],
		"health change stops before another turn")

	var cancelled = _safe_product_session(44)
	check(cancelled.start_auto_explore().running, "cancel fixture starts")
	var cancel_before: int = cancelled.sim.world.step_index
	var cancel_state: Dictionary = cancelled.cancel_auto_explore("auto_explore_modal")
	check_eq([cancel_state.running, cancel_state.stop_reason,
		cancelled.sim.world.step_index - cancel_before],
		[false, "auto_explore_modal", 0],
		"modal/user cancellation is immediate and turn-free")

	var full_visibility = Session.new()
	var no_frontier: Dictionary = full_visibility.start_auto_explore()
	check_eq([no_frontier.running, no_frontier.stop_reason,
		full_visibility.command_journal.size()],
		[false, "auto_explore_no_frontier", 0],
		"fully known map stops without inventing a destination")
	return finish()


func test_auto_explore_state_is_detached_ephemeral_and_cleared_by_load_reset() -> bool:
	var session = _safe_product_session(44)
	var started: Dictionary = session.start_auto_explore()
	check(started.running, "ephemeral fixture is active")
	started["target"] = [999, 999]
	check(session.auto_explore_state().target != [999, 999],
		"public state DTO is detached")
	var encoded: String = session.save_session_json()
	check("auto_explore" not in encoded,
		"macro state is absent from authoritative save wire")
	var canonical = Session.new()
	var loaded: Dictionary = session.load_session_json(canonical.save_session_json())
	check(loaded.accepted, "loading a canonical save succeeds over active macro")
	check_eq([session.auto_explore_state().running,
		session.auto_explore_state().stop_reason],
		[false, "auto_explore_idle"], "load clears ephemeral macro state")
	var restarted = _safe_product_session(44)
	check(restarted.start_auto_explore().running, "reset fixture is active")
	check(restarted.reset_party(44, 20260828, "SOLO_COMBAT_V1"),
		"canonical reset succeeds")
	check_eq([restarted.auto_explore_state().running,
		restarted.auto_explore_state().stop_reason],
		[false, "auto_explore_idle"], "reset clears ephemeral macro state")
	return finish()


func test_auto_explore_route_contact_terminal_interaction_and_objective_gates_are_turn_free() -> bool:
	var route_rejected = _safe_product_session(44)
	check(route_rejected.start_auto_explore().running, "route rejection fixture starts")
	var route_state = route_rejected.sim.world.party_encounter
	var route_hero := int(route_state.protagonist_id)
	route_rejected.sim.world.combatant_states[route_hero].recovery_lock_until = \
		int(route_rejected.sim.world.world_time) + 1000
	var route_before: int = route_rejected.sim.world.step_index
	var rejected: Dictionary = route_rejected.continue_auto_explore()
	check_eq([rejected.running, rejected.stop_reason,
		route_rejected.sim.world.step_index - route_before],
		[false, "auto_explore_route_rejected", 0],
		"canonical route rejection stops without a fallback move")

	var contacted = _safe_product_session(44)
	check(contacted.start_auto_explore().running, "contact fixture starts")
	contacted.sim.world.party_encounter.safe_phase = "CONTACT"
	var contact_before: int = contacted.sim.world.step_index
	var contact_stop: Dictionary = contacted.continue_auto_explore()
	check_eq([contact_stop.stop_reason,
		contacted.sim.world.step_index - contact_before],
		["auto_explore_combat_contact", 0],
		"contact/combat phase transition stops before another hop")

	var terminal = _safe_product_session(44)
	check(terminal.start_auto_explore().running, "terminal fixture starts")
	terminal.sim.world.party_encounter.safe_phase = "PARTY_DEFEATED"
	var terminal_before: int = terminal.sim.world.step_index
	var terminal_stop: Dictionary = terminal.continue_auto_explore()
	check_eq([terminal_stop.stop_reason,
		terminal.sim.world.step_index - terminal_before],
		["auto_explore_terminal", 0], "terminal/death is turn-free")

	var interaction = _safe_product_session(44)
	check(interaction.start_auto_explore().running, "interaction fixture starts")
	var interaction_snapshot: Dictionary = interaction._auto_explore_fog_snapshot()
	var actor_position := _visible_empty_cell(interaction, interaction_snapshot)
	check(actor_position != Vector2i(-1, -1), "visible interaction fixture cell exists")
	var npc = interaction.sim.world.add_entity("neutral", "발견 대상", actor_position,
		20, ["interactable"], "human", "neutral")
	check(npc != null, "new visible interaction actor fixture exists")
	var interaction_before: int = interaction.sim.world.step_index
	var interaction_stop: Dictionary = interaction.continue_auto_explore()
	check_eq([interaction_stop.stop_reason,
		interaction.sim.world.step_index - interaction_before],
		["auto_explore_interaction_discovered", 0],
		"new interaction discovery stops before another hop")

	var objective = _safe_product_session(44)
	check(objective.start_auto_explore().running, "objective fixture starts")
	objective.sim.world.party_encounter.safe_phase = "GROUPED_COMPLETE"
	var objective_before: int = objective.sim.world.step_index
	var objective_stop: Dictionary = objective.continue_auto_explore()
	check_eq([objective_stop.stop_reason,
		objective.sim.world.step_index - objective_before],
		["auto_explore_objective_discovered", 0],
		"objective/exit state discovery stops before another hop")
	return finish()


func test_auto_explore_canonical_move_round_trips_through_existing_replay() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_FIXTURE_SCENARIO_ID)
	check(_advance_manual_route(session, Vector2i(9, 6), 32),
		"canonical solo fixture reaches contact")
	check(session.enter_solo_combat().accepted,
		"canonical solo fixture enters combat")
	check(_resolve_solo_encounter(session, 32),
		"canonical solo fixture clears encounter")
	var journal_before: int = session.command_journal.size()
	var auto_result: Dictionary = session.start_auto_explore()
	check(auto_result.advanced and session.command_journal.size() == journal_before + 1,
		"AUTO EXPLORE adds exactly one ordinary exploration row after victory")
	var encoded: String = session.save_session_json()
	var restored = Session.new(9, 10, Session.SOLO_FIXTURE_SCENARIO_ID)
	var loaded: Dictionary = restored.load_session_json(encoded)
	check(loaded.accepted, "existing journal replay accepts AUTO EXPLORE move")
	var source_wire: Dictionary = JSON.parse_string(encoded)
	var restored_wire: Dictionary = JSON.parse_string(restored.save_session_json())
	check_eq([restored_wire.snapshot, restored_wire.journal],
		[source_wire.snapshot, source_wire.journal],
		"AUTO EXPLORE adds no replay-specific authority")
	check_eq([restored.auto_explore_state().running,
		restored.auto_explore_state().stop_reason],
		[false, "auto_explore_idle"], "round trip restores no macro transient")
	return finish()


func _safe_product_session(seed: int):
	var session = Session.new(seed, 20260828, "SOLO_COMBAT_V1")
	var state = session.sim.world.party_encounter
	var enemy_id := int(state.enemy_ids[0])
	var hidden := _hidden_passable_cell(session, enemy_id)
	if hidden != Vector2i(-1, -1):
		session.sim.world.entities[enemy_id].position = hidden
	state.enemy_busy_rows[enemy_id] = 1000000000
	return session


func _hidden_passable_cell(session, ignored_actor_id: int = -1) -> Vector2i:
	var snapshot: Dictionary = session._auto_explore_fog_snapshot()
	for y in range(session.sim.world.height - 1, -1, -1):
		for x in range(session.sim.world.width - 1, -1, -1):
			var position := Vector2i(x, y)
			if snapshot.visible.has(_key(position)):
				continue
			var definition: Dictionary = TerrainRegistry.definition(
				str(session.sim.world.tile_at(position).terrain))
			if bool(definition.get("passable", false)) \
					and session.sim.world.blocking_entity_at(position,
					ignored_actor_id) == null:
				return position
	return Vector2i(-1, -1)


func _visible_empty_cell(session, snapshot: Dictionary) -> Vector2i:
	var hero_position := Vector2i(int(snapshot.hero_position[0]),
		int(snapshot.hero_position[1]))
	for key_value in snapshot.cells:
		var cell: Dictionary = snapshot.cells[key_value]
		var position := Vector2i(int(cell.position[0]), int(cell.position[1]))
		if position != hero_position and str(cell.visibility_state) == "VISIBLE" \
				and bool(cell.passable) and not bool(cell.occupied) \
				and session.sim.world.blocking_entity_at(position) == null:
			return position
	return Vector2i(-1, -1)


func _advance_manual_route(session, goal: Vector2i, limit: int) -> bool:
	var preview: Dictionary = session.preview_exploration_route(goal)
	if not bool(preview.get("accepted", false)):
		return false
	var result: Dictionary = session.start_exploration_route(goal,
		str(preview.get("plan_hash", "")))
	if not bool(result.get("accepted", false)):
		return false
	for _step in range(limit):
		if str(session.party_status().safe_phase) == "CONTACT":
			return true
		var route: Dictionary = session.exploration_route_state()
		if not bool(route.get("active", false)):
			return false
		result = session.continue_exploration_route()
		if not bool(result.get("accepted", false)):
			return false
	return false


func _resolve_solo_encounter(session, limit: int) -> bool:
	for _turn in range(limit):
		var status: Dictionary = session.party_status()
		if str(status.safe_phase) == "GROUPED_COMPLETE":
			return true
		if str(status.safe_phase) != "ENGAGED":
			return false
		var hero_id := int(status.protagonist_id)
		var hero_position := Vector2i(int(status.protagonist_position[0]),
			int(status.protagonist_position[1]))
		var targets: Array = session.enemy_targets()
		if targets.is_empty():
			return false
		var enemy: Dictionary = targets[0]
		var enemy_position := Vector2i(int(enemy.position[0]), int(enemy.position[1]))
		var preview: Dictionary = {"accepted":false}
		if maxi(absi(hero_position.x - enemy_position.x),
				absi(hero_position.y - enemy_position.y)) == 1:
			preview = session.set_actor_action(hero_id, "MELEE", [],
				int(enemy.entity_id))
		else:
			for direction in [Vector2i(signi(enemy_position.x - hero_position.x),
					signi(enemy_position.y - hero_position.y)),
					Vector2i(signi(enemy_position.x - hero_position.x), 0),
					Vector2i(0, signi(enemy_position.y - hero_position.y))]:
				if direction == Vector2i.ZERO:
					continue
				preview = session.set_actor_action(hero_id, "MOVE",
					[hero_position.x + direction.x, hero_position.y + direction.y])
				if bool(preview.get("accepted", false)):
					break
			if not bool(preview.get("accepted", false)):
				preview = session.set_actor_action(hero_id, "HOLD")
		if not bool(preview.get("accepted", false)) \
				or not bool(session.commit_turn().get("accepted", false)):
			return false
	return str(session.party_status().safe_phase) == "GROUPED_COMPLETE"


func _key(position: Vector2i) -> String:
	return "%d:%d" % [position.x, position.y]
