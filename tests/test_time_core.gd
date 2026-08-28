extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")


func test_action_costs_speed_tiers_and_step_time_are_distinct() -> bool:
	var cases := [
		[Command.wait(), 100, "NORMAL"],
		[Command.wait_for(1), 1, "FAST"],
		[Command.wait_for(101), 101, "SLOW"],
		[Command.ignite(Vector2i.ZERO), 120, "SLOW"],
		[Command.pour_water(Vector2i.ZERO), 80, "FAST"],
		[Command.discharge(Vector2i.ZERO), 160, "SLOW"],
	]
	for row in cases:
		var sim = Simulator.new(1, 1, 1)
		var preview = sim.preview(row[0])
		check(preview.accepted, "timed command accepted")
		check_eq(preview.time_cost, row[1], "preview cost")
		check_eq(preview.speed_tier, row[2], "preview tier")
		var result = sim.step(row[0])
		check_eq(sim.world.step_index, 1, "one decision")
		check_eq(sim.world.world_time, row[1], "elapsed world time")
		check_eq(result.processed_step_index, 1, "processed step")
		check(result.accepted == result.consumes_time, "accepted/time invariant")
		check_eq(result.end_time - result.start_time, result.time_cost, "elapsed result invariant")
	return finish()


func test_invalid_waits_and_t80_rejection_are_total_noops() -> bool:
	var sim = Simulator.new(2, 1, 5)
	sim.step(Command.pour_water(Vector2i.ZERO, 10))
	check_eq(sim.world.world_time, 80, "fast setup time")
	for command in [Command.wait_for(0), Command.wait_for(-1), Command.wait_for(10001),
		Command.wait_for(1.5), Command.from_dict({"type": 0.5}),
		Command.from_dict({"type": 0, "actor_id": 1.5}),
		Command.from_dict({"type": 1, "position": [0, 0], "power": 1.5}),
		Command.ignite(Vector2i(-1, 0), 50)]:
		var before: Dictionary = sim.snapshot()
		var result = sim.step(command)
		check(not result.accepted and not result.consumes_time, "invalid rejected")
		check_eq(result.processed_step_index, -1, "rejected step sentinel")
		check_eq(result.start_time, 80, "rejected start")
		check_eq(result.end_time, 80, "rejected end")
		check_eq(sim.snapshot(), before, "invalid at cadence edge is a no-op")
	check_eq(sim.world.scheduled_entries[0]["due_time"], 100, "cadence was not executed")
	return finish()


func test_valid_nonflammable_ignite_consumes_slow_time_and_explains_failure() -> bool:
	var sim = Simulator.new(1, 1, 2)
	var result = sim.step(Command.ignite(Vector2i.ZERO, 70))
	check(result.accepted and result.consumes_time, "valid attempt accepted")
	check_eq(result.time_cost, 120, "failed ignition cost")
	check_eq(result.speed_tier, "SLOW", "failed ignition tier")
	check_eq(sim.world.world_time, 120, "failed effect still advances world")
	check(find_event(result.events, "environment.ignition_failed") != null, "failure event")
	return finish()


func test_preview_is_pure_and_matches_actual_markers() -> bool:
	var sim = Simulator.new(2, 1, 7)
	sim.step(Command.pour_water(Vector2i.ZERO, 10))
	var before: Dictionary = sim.snapshot()
	var preview = sim.preview(Command.discharge(Vector2i.ZERO, 40))
	check_eq(sim.snapshot(), before, "preview full snapshot purity")
	check_eq(preview.processed_step_index, 2, "preview next step")
	check_eq(_marker_signature(preview.timeline), [
		["action.start", 80, -1], ["system.environment_tick", 100, 1],
		["system.actor_tick", 100, 2], ["system.environment_tick", 200, 1],
		["system.actor_tick", 200, 2], ["actor.ready", 240, -1]], "preview markers")
	var result = sim.step(Command.discharge(Vector2i.ZERO, 40))
	check_eq(result.time_cost, preview.time_cost, "preview cost parity")
	check_eq(result.start_time, preview.start_time, "preview start parity")
	check_eq(result.end_time, preview.end_time, "preview end parity")
	check_eq(_marker_signature(result.timeline), _marker_signature(preview.timeline), "marker parity")
	check_eq(result.timeline.back()["kind"], "actor.ready", "ready last")
	var after_step: Dictionary = sim.snapshot()
	result.timeline[0]["event_ids"].clear()
	result.timeline[0]["presentation_key"] = "mutated"
	check_eq(sim.snapshot(), after_step, "returned actual timeline is detached")
	return finish()


func test_preview_replans_after_time_changes_and_nested_dto_is_detached() -> bool:
	var sim = Simulator.new(1, 1, 11)
	var stale = sim.preview(Command.wait_for(100))
	var before: Dictionary = sim.snapshot()
	stale.timeline[0]["event_ids"].append(999)
	stale.timeline[0]["presentation_key"] = "corrupt"
	stale.calendar_end["hour_of_day"] = 99
	check_eq(sim.snapshot(), before, "nested preview mutation cannot reach world")
	sim.step(Command.wait_for(80))
	var result = sim.step(Command.wait_for(100))
	check_eq(stale.start_time, 0, "old preview stays an old DTO")
	check_eq(result.start_time, 80, "step replans at current time")
	check_eq(result.end_time, 180, "replanned end")
	return finish()


func test_wait_boundaries_and_due_at_end_precedes_ready() -> bool:
	for duration in [1, 99, 100, 101, 199, 200, 250, 10000]:
		var sim = Simulator.new(1, 1, duration)
		var result = sim.step(Command.wait_for(duration))
		var environment_count := 0
		var actor_count := 0
		for marker in result.timeline:
			if marker["kind"] == "system.environment_tick":
				environment_count += 1
			elif marker["kind"] == "system.actor_tick": actor_count += 1
		check_eq(environment_count, duration / 100, "environment count for %d" % duration)
		check_eq(actor_count, duration / 100, "actor count for %d" % duration)
		check_eq(result.timeline.back()["at_time"], duration, "ready time")
		if duration % 100 == 0:
			check_eq(result.timeline[-3]["kind"], "system.environment_tick", "environment before actor")
			check_eq(result.timeline[-2]["kind"], "system.actor_tick", "actor due before ready")
			check_eq(result.timeline[-2]["at_time"], duration, "due at exact end")
	return finish()


func test_same_time_schedules_use_priority_then_schedule_id() -> bool:
	var sim = Simulator.new(1, 1, 3)
	var early_id: int = sim.world._schedule_fixture_entry("system.environment_tick", 100, 50)
	var late_id: int = sim.world._schedule_fixture_entry("system.environment_tick", 100, 150)
	var command = Command.wait()
	var plan: Dictionary = sim._plan_action(command)
	var processed_step_index: int = int(plan.processed_step_index)
	check(plan.accepted and processed_step_index == 1, "fixture outer plan accepted")
	sim.world.begin_step(processed_step_index)
	check(sim._resolve_command(command, plan, processed_step_index) != null, "fixture root commits")
	var ids: Array = []
	for occurrence in plan._occurrences:
		var entry: Dictionary = sim.world.take_next_schedule()
		check_eq([entry.kind, entry.due_time, entry.schedule_id],
			[occurrence.kind, occurrence.due_time, occurrence.schedule_id],
			"planned occurrence dispatches exactly")
		sim.world.world_time = int(entry.due_time)
		check(sim._dispatch_schedule(entry, processed_step_index), "scheduled handler accepts explicit step")
		if entry.kind == "system.environment_tick": ids.append(entry.schedule_id)
		if int(entry.repeat_interval) > 0: sim.world.requeue_repeating(entry)
	sim.world.world_time = int(plan.end_time)
	sim.world.finish_step()
	check_eq(ids, [early_id, 1, late_id], "same-time stable order")
	check_eq(sim.world.scheduled_entries.size(), 2, "one-shots removed; canonical repeats remain")
	check_eq(sim.world.scheduled_entries[0]["due_time"], 200, "repeat drift-free")
	check_eq(sim.world.scheduled_entries[1]["due_time"], 200, "actor repeat drift-free")
	return finish()


func test_schedule_budget_is_preflight_rejection_without_partial_progress() -> bool:
	var sim = Simulator.new(1, 1, 4)
	for index in range(1025):
		sim.world._schedule_fixture_entry("system.environment_tick", 1, index)
	var schedules_before: Array = sim.world.scheduled_entries.duplicate(true)
	var next_id_before: int = sim.world.next_schedule_id
	var result = sim.step(Command.wait_for(1))
	check(not result.accepted, "oversized occurrence plan rejected")
	check_eq(result.reason, "schedule_budget_exceeded", "budget reason")
	check_eq(sim.world.world_time, 0, "budget rejection time")
	check_eq(sim.world.step_index, 0, "budget rejection step")
	check_eq(sim.world.events.size(), 0, "budget rejection events")
	check_eq(sim.world.scheduled_entries, schedules_before, "budget rejection queue")
	check_eq(sim.world.next_schedule_id, next_id_before, "budget rejection ID")
	return finish()


func test_wait_250_matches_segmented_physics_rng_and_cadence() -> bool:
	var long_wait = _burning_sim(13)
	var split_wait = _burning_sim(13)
	long_wait.step(Command.wait_for(250))
	for duration in [80, 70, 100]:
		split_wait.step(Command.wait_for(duration))
	check_eq(_physical_state(long_wait), _physical_state(split_wait), "physical equivalence")
	check_eq(long_wait.world.rng.state, split_wait.world.rng.state, "RNG equivalence")
	check_eq(long_wait.world.scheduled_entries, split_wait.world.scheduled_entries, "cadence equivalence")
	check_eq(long_wait.world.step_index, 1, "long wait is one decision")
	check_eq(split_wait.world.step_index, 3, "split waits are three decisions")
	var long_snapshot = long_wait.snapshot()
	check(long_snapshot != null, "long burning fixture remains saveable")
	if long_snapshot != null:
		var restored = Simulator.from_snapshot(JSON.parse_string(JSON.stringify(long_snapshot)))
		check(restored != null, "long burning fixture restores")
		if restored != null:
			check_eq(restored.snapshot(), long_snapshot, "long burning fixture exact round trip")
	return finish()


func test_action_marker_owns_all_immediate_events_and_every_event_once() -> bool:
	var sim = Simulator.new(2, 1, 17)
	for tile in sim.world.tiles:
		tile.base_conductivity = 30
	var target = sim.world.add_entity("goblin", "Target", Vector2i(1, 0))
	var result = sim.step(Command.discharge(Vector2i.ZERO, 40, target.id))
	check_eq(result.timeline[0]["event_ids"][0], result.root_event_id, "root first")
	check(result.timeline[0]["event_ids"].size() >= 4, "arcs and immediate damage grouped at action")
	var ownership: Dictionary = {}
	for marker in result.timeline:
		for event_id in marker["event_ids"]:
			ownership[event_id] = int(ownership.get(event_id, 0)) + 1
	for event in result.events:
		check_eq(ownership.get(event.id, 0), 1, "event has exactly one marker")
		check_eq(event.step_index, 1, "first step event context")
	check_eq(sim.world._active_step_index, -1, "active context settled")
	var authoritative: Dictionary = sim.snapshot()
	result.events[0].id = 999
	result.events[0].type = "mutated"
	result.events[0].data["nested"] = ["mutation"]
	check_eq(sim.snapshot(), authoritative, "result events are detached from authoritative log")
	return finish()


func test_same_seed_commands_produce_identical_timeline_and_snapshot() -> bool:
	var a = Simulator.new(2, 1, 99)
	var b = Simulator.new(2, 1, 99)
	var commands := [Command.wait_for(80), Command.discharge(Vector2i.ZERO, 30), Command.wait_for(250)]
	for command in commands:
		var ar = a.step(command)
		var br = b.step(Command.from_dict(command.to_dict()))
		check_eq(ar.timeline, br.timeline, "timeline deterministic")
	check_eq(a.snapshot(), b.snapshot(), "snapshot deterministic")
	return finish()


func _marker_signature(timeline: Array) -> Array:
	var result: Array = []
	for marker in timeline:
		result.append([marker["kind"], marker["at_time"], marker["schedule_id"]])
	return result


func _burning_sim(seed: int):
	var sim = Simulator.new(2, 1, seed)
	for tile in sim.world.tiles:
		tile.flammability = 100
	sim.world.bootstrap_set_fire(Vector2i.ZERO, 100)
	return sim


func _physical_state(sim) -> Dictionary:
	var tiles: Array = []
	for tile in sim.world.tiles:
		tiles.append({"fire": tile.fire, "wetness": tile.wetness,
			"eligible": tile.fire_damage_eligible_time})
	var health: Array = []
	var ids: Array = sim.world.entities.keys()
	ids.sort()
	for id in ids:
		health.append(sim.world.entities[id].health)
	return {"world_time": sim.world.world_time, "tiles": tiles, "health": health}
