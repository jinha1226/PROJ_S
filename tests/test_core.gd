extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")


func test_same_seed_and_commands_produce_identical_worlds() -> bool:
	check_eq(_run_scenario(20260827).snapshot(), _run_scenario(20260827).snapshot(), "deterministic snapshot")
	return finish()


func test_rejected_commands_do_not_advance_any_world_state() -> bool:
	var sim = Simulator.new(3, 3, 1)
	var tile = sim.world.tile_at(Vector2i.ZERO)
	tile.flammability = 100
	sim.world.bootstrap_set_fire(Vector2i.ZERO, 50)
	var before: Dictionary = sim.snapshot()
	for command in [null, {}, Command.ignite(Vector2i(-1, 0), 50), Command.ignite(Vector2i.ZERO, 0), Command.ignite(Vector2i.ZERO, 101), Command.wait(99)]:
		var result = sim.step(command)
		check(not result.accepted, "invalid command should be rejected")
		check(not result.consumes_time, "invalid command must not consume time")
		check_eq(result.events.size(), 0, "rejection events")
		check_eq(sim.snapshot(), before, "rejected command state")
	return finish()


func test_command_serialization_round_trip() -> bool:
	var command = Command.discharge(Vector2i(2, 4), 67, 12)
	check_eq(Command.from_dict(command.to_dict()).to_dict(), command.to_dict(), "command round trip")
	var wait_command = Command.wait_for(250, 12)
	var json_wait = JSON.parse_string(JSON.stringify(wait_command.to_dict()))
	check_eq(Command.from_dict(json_wait).to_dict(), wait_command.to_dict(), "wait duration JSON round trip")
	var large_actor_command = Command.wait(9007199254740993)
	var large_actor_json = JSON.parse_string(JSON.stringify(large_actor_command.to_dict()))
	check_eq(Command.from_dict(large_actor_json).actor_id, 9007199254740993, "large actor ID exact")
	return finish()


func test_malformed_command_journal_returns_null_and_step_is_noop() -> bool:
	var sim = Simulator.new(1, 1, 2)
	var valid := Command.wait().to_dict()
	var malformed: Array = []
	for mutation in [
		func(row): row.type = 0.5,
		func(row): row.power = 0.5,
		func(row): row.wait_duration_time_units = 1.5,
		func(row): row.position = [0.5, 0],
		func(row): row.actor_id = 1,
	]:
		var row: Dictionary = valid.duplicate(true)
		mutation.call(row)
		malformed.append(row)
	for row in malformed:
		var before: Dictionary = sim.snapshot()
		var restored_command = Command.from_dict(row)
		check(restored_command == null, "malformed command returns null")
		var result = sim.step(restored_command)
		check(not result.accepted, "null restored command rejected")
		check_eq(sim.snapshot(), before, "malformed journal step no-op")
	return finish()


func test_unknown_dead_actor_and_defensive_power_are_rejected() -> bool:
	var sim = Simulator.new(2, 2, 3)
	var actor = sim.world.add_entity("goblin", "Dead", Vector2i.ZERO)
	actor.health = 0
	var unknown_wire := {
		"type": 999, "actor_id": "-1", "position": [0, 0], "power": 1,
		"wait_duration_time_units": 100,
	}
	check_eq(Command.command_wire_error(unknown_wire), "invalid_command_type",
		"canonical full wire row reaches unknown type validation")
	check(Command.from_dict(unknown_wire) == null, "unknown wire command is not decoded")
	var unknown = Command.new(999, -1, Vector2i.ZERO, 1, 100)
	for command in [unknown, Command.wait(actor.id), Command.wait(-2)]:
		var before: Dictionary = sim.snapshot()
		var result = sim.step(command)
		check(not result.accepted and not result.consumes_time, "command rejected")
		check_eq(sim.snapshot(), before, "rejected state remains exact")
	var root = sim.world.emit_event("test.root")
	var event_count: int = sim.world.events.size()
	check(not sim.environment.ignite(Vector2i.ZERO, 0, root.id), "execution layer rejects zero")
	check(not sim.environment.discharge(Vector2i.ZERO, 101, root.id), "execution layer rejects 101")
	check_eq(sim.world.events.size(), event_count, "defensive rejection creates no effects")
	return finish()


func test_snapshot_resume_matches_uninterrupted_execution() -> bool:
	var continuous = _prepared_sim(91)
	continuous.step(Command.ignite(Vector2i(1, 1), 80))
	continuous.step(Command.pour_water(Vector2i(2, 1), 30))
	var resumed = Simulator.from_snapshot(continuous.snapshot())
	for command in [Command.wait(), Command.discharge(Vector2i(2, 1), 50), Command.wait()]:
		continuous.step(command)
		resumed.step(Command.from_dict(command.to_dict()))
	check_eq(resumed.snapshot(), continuous.snapshot(), "resumed world")
	return finish()


func test_json_snapshot_resume_preserves_rng_and_future_world() -> bool:
	var continuous = _prepared_sim(4142397736433585562)
	continuous.step(Command.ignite(Vector2i(1, 1), 95))
	continuous.step(Command.wait())
	var snapshot: Dictionary = continuous.snapshot()
	check_eq(typeof(snapshot["seed"]), TYPE_STRING, "seed uses JSON-safe string")
	check_eq(typeof(snapshot["rng_state"]), TYPE_STRING, "RNG state uses JSON-safe string")
	var encoded: String = JSON.stringify(snapshot)
	var parsed = JSON.parse_string(encoded)
	check(parsed is Dictionary, "snapshot JSON parses as a dictionary")
	var resumed = Simulator.from_snapshot(parsed)
	for command in [Command.wait(), Command.pour_water(Vector2i(2, 1), 25), Command.wait(), Command.discharge(Vector2i(1, 1), 70)]:
		continuous.step(command)
		resumed.step(Command.from_dict(command.to_dict()))
	check_eq(resumed.snapshot(), continuous.snapshot(), "JSON-resumed future world")
	check_eq(resumed.world.rng.state, continuous.world.rng.state, "JSON-resumed RNG state")
	return finish()


func test_snapshot_64bit_fields_require_canonical_strings() -> bool:
	var codec = load("res://sim/int64_codec.gd")
	check(codec.is_canonical("44"), "canonical seed")
	check(codec.is_canonical("-1797858827748764843"), "canonical signed RNG")
	check(not codec.is_canonical(44), "numeric seed rejected")
	check(not codec.is_canonical(44.0), "JSON numeric seed rejected")
	return finish()


func test_restored_ids_continue_without_duplicates() -> bool:
	var sim = Simulator.new(2, 2, 4)
	var first = sim.world.add_entity("goblin", "One", Vector2i.ZERO)
	sim.step(Command.wait())
	var restored = Simulator.from_snapshot(sim.snapshot())
	var second = restored.world.add_entity("human", "Two", Vector2i.ONE)
	var result = restored.step(Command.wait(second.id))
	check_eq(second.id, first.id + 1, "entity id")
	check_eq(result.events[0].id, 2, "event id")
	return finish()


func test_all_derived_causes_exist_and_are_older() -> bool:
	var sim = _run_scenario(33)
	for event in sim.world.events:
		if event.cause_id != -1:
			check(sim.world.event_by_id(event.cause_id) != null, "cause exists")
			check(event.cause_id < event.id, "cause is older")
	return finish()


func test_instigator_is_inherited_through_effect_chain() -> bool:
	var sim = Simulator.new(1, 1, 2)
	var actor = sim.world.add_entity("mage", "Caster", Vector2i.ZERO)
	sim.world.tile_at(Vector2i.ZERO).flammability = 100
	var result = sim.step(Command.ignite(Vector2i.ZERO, 50, actor.id))
	var action = find_event(result.events, "action.ignite")
	var ignition = find_event(result.events, "environment.ignited")
	var damage = find_event(result.events, "combat.fire_damage")
	check_eq(action.instigator_id, actor.id, "root instigator")
	check_eq(ignition.instigator_id, actor.id, "ignition instigator")
	check_eq(damage.instigator_id, actor.id, "damage instigator")
	return finish()


func _prepared_sim(seed: int):
	var sim = Simulator.new(5, 3, seed)
	for x in range(1, 5):
		var tile = sim.world.tile_at(Vector2i(x, 1))
		tile.flammability = 80
		tile.base_conductivity = 30
	sim.world.add_entity("goblin", "Seed Goblin", Vector2i(4, 1), 100)
	return sim


func _run_scenario(seed: int):
	var sim = _prepared_sim(seed)
	sim.step(Command.ignite(Vector2i(1, 1), 80))
	sim.step(Command.wait())
	sim.step(Command.pour_water(Vector2i(2, 1), 70))
	sim.step(Command.discharge(Vector2i(2, 1), 50))
	return sim
