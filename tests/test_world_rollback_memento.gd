extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")
const Session = preload("res://playtest/party_playtest_session.gd")


func test_memento_restores_every_tile_field_int64_and_mutable_world_surface() -> bool:
	var sim = Simulator.create(3, 2, 7000000007)
	var hero = sim.world.add_entity("hero", "복원 시험", Vector2i(0, 1), 120)
	check(hero != null, "memento fixture hero exists")
	check(sim.world.bootstrap_set_terrain(Vector2i(0, 0), "metal"),
		"terrain/base conductivity fixture")
	check(sim.world.bootstrap_set_terrain(Vector2i(1, 0), "wood_floor"),
		"flammability fixture")
	check(sim.world.bootstrap_set_fire(Vector2i(1, 0), 83) != null,
		"fire/source/eligibility fixture")
	check(sim.world.bootstrap_set_wetness(Vector2i(2, 0), 67) != null,
		"wetness/source fixture")
	# Exercise a signed 64-bit scalar without making the later bootstrap events
	# invalid (bootstrap_set_world_time intentionally rejects eventful worlds).
	sim.world.rng.state = 9007199254741000
	check_eq(sim.world.world_state_error(), "", "full fixture is canonical")
	var before: Dictionary = sim.snapshot()
	var retained_event = sim.world.events[0]
	var memento: Variant = sim.capture_rollback_memento()
	check(memento is Dictionary, "valid settled world captures memento")
	if not memento is Dictionary:
		return finish()
	check(memento.tile_terrain is PackedStringArray \
		and memento.tile_scalars is PackedInt64Array,
		"tiles use packed rollback storage")
	# Deliberately corrupt every tile field and representative scalar/object state.
	var tile = sim.world.tiles[0]
	tile.terrain = "floor"
	tile.flammability = 99
	tile.base_conductivity = 1
	tile.wetness = 55
	tile.fire = 44
	tile.fire_source_event_id = 9007199254741001
	tile.wetness_source_event_id = 9007199254741002
	tile.fire_damage_eligible_time = 9007199254741003
	sim.world.entities[hero.id].position = Vector2i(2, 1)
	sim.world.entities[hero.id].health = 3
	sim.world.world_time += 100
	sim.world.step_index += 1
	sim.world.rng.state = 1234567890123456
	sim.world._next_entity_id += 10
	sim.world._next_event_id += 10
	sim.world.next_schedule_id += 10
	sim.world.scheduled_entries.clear()
	check(sim.restore_rollback_memento(memento), "complete memento restores")
	check_eq(sim.snapshot(), before, "all canonical save surfaces restore exactly")
	check(sim.world.events[0] != retained_event \
		and sim.world.events[0].to_dict() == retained_event.to_dict(),
		"append-only event prefix restores as detached event objects")
	check_eq([sim.world.rng.state, sim.world.seed],
		[9007199254741000, 7000000007], "Int64 values survive in-memory restore")
	return finish()


func test_invalid_foreign_and_stale_mementos_fail_closed_without_a_turn() -> bool:
	var sim = Simulator.create(4, 4, 17)
	var hero = sim.world.add_entity("hero", "시험자", Vector2i(1, 1), 100)
	var valid: Dictionary = sim.capture_rollback_memento()
	var before: Dictionary = sim.snapshot()
	var malformed := valid.duplicate(true)
	var shortened: PackedInt64Array = malformed.tile_scalars.duplicate()
	shortened.resize(shortened.size() - 1)
	malformed.tile_scalars = shortened
	check(not sim.restore_rollback_memento(malformed), "bad packed tile shape is rejected")
	check_eq(sim.snapshot(), before, "invalid restore cannot mutate live world")
	var foreign = Simulator.create(4, 4, 17)
	foreign.world.add_entity("hero", "다른 세계", Vector2i(1, 1), 100)
	var foreign_memento: Dictionary = foreign.capture_rollback_memento()
	var foreign_result = sim.step(Command.wait(hero.id), foreign_memento)
	check_eq([foreign_result.accepted, foreign_result.consumes_time,
		foreign_result.reason], [false, false, "snapshot_unavailable"],
		"foreign world memento cannot authorize a step")
	check_eq(sim.snapshot(), before, "foreign memento rejection is a no-op")
	var first = sim.step(Command.wait(hero.id), valid)
	check(first.accepted, "fresh supplied memento authorizes exactly one step")
	var after_first: Dictionary = sim.snapshot()
	var stale = sim.step(Command.wait(hero.id), valid)
	check_eq([stale.accepted, stale.consumes_time, stale.reason],
		[false, false, "snapshot_unavailable"], "stale supplied memento fails closed")
	check_eq(sim.snapshot(), after_first, "stale rejection consumes no second turn")
	return finish()


func test_scheduled_handler_failure_restores_exact_snapshot_with_memento() -> bool:
	var session = Session.new()
	var preview: Dictionary = session.preview_exploration_route(Vector2i(10, 7))
	check(bool(preview.get("accepted", false)), "failure route previews")
	session.sim.party_coordinator.fail_point = "contact_event"
	var before: Dictionary = session.sim.snapshot()
	var journal_before: Array = session.command_journal.duplicate(true)
	var failed: Dictionary = session.start_exploration_route(Vector2i(10, 7),
		str(preview.get("plan_hash", "")))
	check_eq([failed.accepted, failed.reason], [false, "actor_tick_failed"],
		"scheduled contact failure propagates")
	check_eq(session.sim.snapshot(), before,
		"time, RNG, IDs, schedules, tiles, entities and events roll back exactly")
	check_eq(session.command_journal, journal_before, "failed outer transaction has no journal row")
	return finish()


func test_direct_solo_party_leaf_failure_restores_exact_shared_memento() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_FIXTURE_SCENARIO_ID)
	check(session.commit_exploration_direction(Vector2i.RIGHT).accepted,
		"solo rollback fixture reaches contact")
	check(session.enter_solo_combat().accepted, "solo rollback fixture enters combat")
	var hero_id := int(session.sim.world.party_encounter.protagonist_id)
	var before: Dictionary = session.sim.snapshot()
	var journal_before: Array = session.command_journal.duplicate(true)
	session.sim.party_coordinator.fail_point = "party_leaf"
	var failed: Dictionary = session.commit_direct_solo_action(hero_id, "HOLD")
	check_eq([failed.accepted, failed.reason], [false, "party_turn_failed"],
		"direct solo leaf fault propagates through the canonical result")
	check_eq(session.sim.snapshot(), before,
		"direct solo outer transaction restores the shared memento exactly")
	check_eq(session.command_journal, journal_before,
		"failed direct solo action appends no replay authority")
	return finish()


func test_save_replay_wire_stays_canonical_and_contains_no_memento() -> bool:
	var session = Session.new(44, 20260831, Session.SOLO_FIXTURE_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	var result: Dictionary = session.commit_exploration(
		Command.move_to(hero_id, Vector2i(3, 12)))
	check(bool(result.get("accepted", false)), "ordinary exploration commits")
	var encoded := session.save_session_json()
	check("tile_scalars" not in encoded and "event_prefix" not in encoded \
		and "source_instance_id" not in encoded,
		"private rollback representation never enters save wire")
	var restored = Session.new(1, 2, Session.SOLO_FIXTURE_SCENARIO_ID)
	var loaded: Dictionary = restored.load_session_json(encoded)
	check(bool(loaded.get("accepted", false)), "save/load/replay still accepts")
	if bool(loaded.get("accepted", false)):
		check_eq(JSON.parse_string(restored.save_session_json()), JSON.parse_string(encoded),
			"canonical snapshot and journal wire remain semantically identical")
	return finish()


func test_96x96_memento_is_faster_than_one_full_save_snapshot() -> bool:
	var session = Session.new(44, 20260831, Session.SOLO_COMBAT_SCENARIO_ID)
	check_eq(session.sim.world.tiles.size(), 96 * 96, "performance fixture is 96x96")
	# Warm parser/caches, then alternate operations to reduce ordering bias.
	session.sim.snapshot()
	session.sim.capture_rollback_memento()
	var snapshot_samples: Array[int] = []
	var memento_samples: Array[int] = []
	for _sample in range(7):
		var started := Time.get_ticks_usec()
		session.sim.snapshot()
		snapshot_samples.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		session.sim.capture_rollback_memento()
		memento_samples.append(Time.get_ticks_usec() - started)
	snapshot_samples.sort()
	memento_samples.sort()
	var snapshot_median := snapshot_samples[3]
	var memento_median := memento_samples[3]
	print("PERF rollback 96x96 snapshot_median_us=%d memento_median_us=%d ratio_milli=%d" % [
		snapshot_median, memento_median,
		int(memento_median * 1000 / maxi(1, snapshot_median))])
	check(memento_median < snapshot_median,
		"packed memento beats even one full save snapshot; product path previously took two-plus")
	return finish()
