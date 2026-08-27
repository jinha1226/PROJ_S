extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")


func test_water_fire_reaction_occurs_exactly_once() -> bool:
	var sim = Simulator.new(3, 3, 7)
	var position := Vector2i(1, 1)
	var tile = sim.world.tile_at(position)
	tile.flammability = 100
	check(sim.world.bootstrap_set_fire(position, 30) != null, "valid fire fixture")
	sim.step(Command.wait_for(20))
	var result = sim.step(Command.pour_water(position, 10))
	check_eq(tile.fire, 15, "30 fire - 10 suppression - 5 natural decay")
	check_eq(count_events(result.events, "environment.fire_weakened"), 1, "single reaction event")
	check_eq(count_events(result.events, "environment.fire_extinguished"), 0, "no false extinguish")
	var water = find_event(result.events, "environment.water_applied")
	var weakened = find_event(result.events, "environment.fire_weakened")
	check_eq(weakened.cause_id, water.id, "suppression caused by applied water")
	_check_snapshot_round_trip(sim, "water/fire reaction")
	return finish()


func test_wetness_decay_and_zero_boundary() -> bool:
	var sim = Simulator.new(2, 2, 2)
	var tile = sim.world.tile_at(Vector2i.ZERO)
	sim.step(Command.pour_water(Vector2i.ZERO, 5))
	check_eq(tile.wetness, 5, "fast application does not cross cadence")
	sim.step(Command.wait_for(20))
	check_eq(tile.wetness, 3, "wetness after first environment tick")
	sim.step(Command.wait())
	check_eq(tile.wetness, 1, "wetness second environment tick")
	sim.step(Command.wait())
	check_eq(tile.wetness, 0, "wetness zero clamp")
	check_eq(tile.wetness_source_event_id, -1, "wetness source cleared")
	return finish()


func test_saturated_water_does_not_steal_wetness_source() -> bool:
	var sim = Simulator.new(1, 1, 9)
	var tile = sim.world.tile_at(Vector2i.ZERO)
	var original_source = sim.world.bootstrap_set_wetness(Vector2i.ZERO, 100)
	check(original_source != null, "valid saturated water fixture")
	var result = sim.step(Command.pour_water(Vector2i.ZERO, 1))
	var applied = find_event(result.events, "environment.water_applied")
	check_eq(applied.magnitude, 0, "actual saturated increase")
	check_eq(applied.data["requested_amount"], 1, "requested amount retained")
	check_eq(tile.wetness, 100, "fast action has no hidden decay")
	sim.step(Command.wait_for(20))
	check_eq(tile.wetness, 98, "next cadence applies natural decay")
	check_eq(tile.wetness_source_event_id, original_source.id, "zero contribution keeps prior source")
	_check_snapshot_round_trip(sim, "saturated water")
	return finish()


func test_direct_and_spread_ignition_share_wetness_rule() -> bool:
	var sim = Simulator.new(3, 1, 3)
	for x in [0, 2]:
		var tile = sim.world.tile_at(Vector2i(x, 0))
		tile.flammability = 100
		check(sim.world.bootstrap_set_wetness(Vector2i(x, 0), 50) != null,
			"valid wet fixture")
	var root = sim.world.emit_event("test.ignition_source")
	check(not sim.environment.try_ignite(Vector2i(0, 0), 40, root.id, "environment.ignited"), "direct blocked")
	check(not sim.environment.try_ignite(Vector2i(2, 0), 40, root.id, "environment.fire_spread", Vector2i(1, 0)), "spread blocked")
	check_eq([sim.world.tile_at(Vector2i(0, 0)).fire,
		sim.world.tile_at(Vector2i(0, 0)).wetness],
		[sim.world.tile_at(Vector2i(2, 0)).fire,
		sim.world.tile_at(Vector2i(2, 0)).wetness], "same wet ignition state")
	check(sim.snapshot() != null, "blocked direct/spread fixture remains saveable")
	var actual = Simulator.new(2, 1, 7)
	actual.world.tile_at(Vector2i.ZERO).flammability = 100
	actual.world.tile_at(Vector2i(1, 0)).flammability = 100
	check(actual.world.bootstrap_set_wetness(Vector2i(1, 0), 100) != null,
		"valid target wetness")
	check(actual.world.bootstrap_set_fire(Vector2i.ZERO, 100) != null,
		"valid source fire")
	var spread_result = actual.step(Command.wait())
	check_eq(actual.world.tile_at(Vector2i(1, 0)).fire, 0, "actual spread remains blocked")
	check_eq(actual.world.tile_at(Vector2i(1, 0)).wetness, 3, "actual spread uses common evaporation then decay")
	check(find_event(spread_result.events, "environment.ignition_failed") != null, "actual blocked spread is explained")
	_check_snapshot_round_trip(actual, "blocked spread")
	return finish()


func test_spread_collision_uses_stronger_source() -> bool:
	var sim = Simulator.new(3, 1, 7)
	for x in range(3):
		sim.world.tile_at(Vector2i(x, 0)).flammability = 100
	check(sim.world.bootstrap_set_fire(Vector2i(0, 0), 100) != null, "left fire")
	check(sim.world.bootstrap_set_fire(Vector2i(2, 0), 70) != null, "right fire")
	var result = sim.step(Command.wait())
	var spread = find_event(result.events, "environment.fire_spread")
	check(spread != null, "spread should succeed for fixed seed")
	if spread != null:
		check_eq(spread.data["from_position"], [0, 0], "strong source wins")
		check_eq(spread.magnitude, 95, "post-decay winning power")
	_check_snapshot_round_trip(sim, "spread collision")
	return finish()


func test_spread_preview_matches_wetness_then_flammability_formula() -> bool:
	var sim = Simulator.new(2, 1, 17)
	var source_position := Vector2i.ZERO
	var target_position := Vector2i(1, 0)
	var source = sim.world.bootstrap_set_fire(source_position, 100)
	check(source != null, "valid source fire")
	var target = sim.world.tile_at(target_position)
	target.flammability = 30
	check(sim.world.bootstrap_set_wetness(target_position, 20) != null,
		"valid target wetness")
	var burning_positions: Array[Vector2i] = [source_position]
	var candidates: Dictionary = sim.environment._collect_spread_candidates(burning_positions)
	check_eq(candidates[target_position][0]["resulting_fire"], 30,
		"min(max(100 - 20, 0), 30) preview")
	check(sim.environment.try_ignite(target_position, 100, source.id, "environment.fire_spread", source_position),
		"matching actual ignition succeeds")
	check_eq(target.fire, 30, "actual ignition uses the same formula")
	_check_snapshot_round_trip(sim, "spread preview fixture")
	return finish()


func test_blocked_collision_prefers_strong_raw_power_when_mirrored() -> bool:
	var normal = _blocked_collision(7, false)
	var mirrored = _blocked_collision(7, true)
	var target_position := Vector2i(1, 0)
	check_eq(normal.world.tile_at(target_position).fire, 0, "normal target remains blocked")
	check_eq(mirrored.world.tile_at(target_position).fire, 0, "mirrored target remains blocked")
	check_eq(normal.world.tile_at(target_position).wetness, 3, "strong 95 power evaporates wetness")
	check_eq(mirrored.world.tile_at(target_position).wetness, 3, "mirrored strong source evaporates equally")
	var normal_failure = null
	var mirrored_failure = null
	for event in normal.world.events:
		if event.type == "environment.ignition_failed":
			normal_failure = event
	for event in mirrored.world.events:
		if event.type == "environment.ignition_failed":
			mirrored_failure = event
	check_eq(normal_failure.data["from_position"], [2, 0], "normal strong source selected")
	check_eq(mirrored_failure.data["from_position"], [0, 0], "mirrored strong source selected")
	_check_snapshot_round_trip(normal, "blocked collision normal")
	_check_snapshot_round_trip(mirrored, "blocked collision mirrored")
	return finish()


func test_mirrored_spread_has_same_outcome() -> bool:
	var a = _single_spread(13, 0, 1)
	var b = _single_spread(13, 2, 1)
	check_eq(a.world.tile_at(Vector2i(1, 0)).fire, b.world.tile_at(Vector2i(1, 0)).fire, "mirrored fire")
	check_eq(count_events(a.world.events, "environment.fire_spread"), count_events(b.world.events, "environment.fire_spread"), "mirrored event count")
	_check_snapshot_round_trip(a, "single spread normal")
	_check_snapshot_round_trip(b, "single spread mirrored")
	return finish()


func test_newly_spread_fire_has_one_turn_before_damage() -> bool:
	var sim = Simulator.new(2, 1, 7)
	for x in range(2):
		sim.world.tile_at(Vector2i(x, 0)).flammability = 100
	var target = sim.world.add_entity("goblin", "Reaction Window", Vector2i(1, 0))
	check(sim.world.bootstrap_set_fire(Vector2i.ZERO, 100) != null,
		"valid source fire")
	var spread_step = sim.step(Command.wait())
	check(find_event(spread_step.events, "environment.fire_spread") != null, "fire spreads on fixed seed")
	check_eq(target.health, 100, "new spread does not damage on creation tick")
	var next_step = sim.step(Command.wait())
	check_eq(target.health, 80, "spread fire damages on following environment tick")
	check(find_event(next_step.events, "combat.fire_damage") != null, "following-tick fire damage event")
	_check_snapshot_round_trip(sim, "spread reaction window")
	return finish()


func test_direct_ignition_damages_now_but_burnout_reignition_waits() -> bool:
	var direct = Simulator.new(1, 1, 3)
	direct.world.tile_at(Vector2i.ZERO).flammability = 100
	var direct_target = direct.world.add_entity("goblin", "Direct", Vector2i.ZERO)
	direct.step(Command.ignite(Vector2i.ZERO, 50))
	check_eq(direct_target.health, 80, "direct ignition damages at first due environment tick")

	var reignite = Simulator.new(2, 1, 7)
	for x in range(2):
		reignite.world.tile_at(Vector2i(x, 0)).flammability = 100
	var target = reignite.world.add_entity("goblin", "Reignited", Vector2i.ZERO)
	check(reignite.world.bootstrap_set_fire(Vector2i.ZERO, 5) != null,
		"valid expiring fire")
	check(reignite.world.bootstrap_set_fire(Vector2i(1, 0), 100) != null,
		"valid strong fire")
	var reignition_step = reignite.step(Command.wait())
	check(find_event(reignition_step.events, "environment.fire_burned_out") != null, "weak fire burns out")
	check(find_event(reignition_step.events, "environment.fire_spread") != null, "tile is re-ignited")
	check_eq(target.health, 100, "same-phase re-ignition receives reaction window")
	reignite.step(Command.wait())
	check_eq(target.health, 80, "re-ignited fire damages at next environment tick")
	_check_snapshot_round_trip(reignite, "burnout reignition")
	return finish()


func test_conduction_threshold_24_and_25() -> bool:
	var blocked = Simulator.new(2, 1, 1)
	var blocked_target = blocked.world.add_entity("goblin", "Blocked", Vector2i(1, 0))
	blocked.world.tile_at(Vector2i(1, 0)).terrain = "metal"
	blocked.world.tile_at(Vector2i(1, 0)).base_conductivity = 24
	blocked.step(Command.discharge(Vector2i.ZERO, 40))
	check_eq(blocked_target.health, 100, "conductivity 24")
	var conducted = Simulator.new(2, 1, 1)
	var target = conducted.world.add_entity("goblin", "Conducted", Vector2i(1, 0))
	conducted.world.tile_at(Vector2i(1, 0)).terrain = "metal"
	conducted.world.tile_at(Vector2i(1, 0)).base_conductivity = 25
	conducted.step(Command.discharge(Vector2i.ZERO, 40))
	check_eq(target.health, 68, "conductivity 25 and distance loss")
	return finish()


func test_electric_distance_parent_arcs_and_cycle_single_damage() -> bool:
	var sim = Simulator.new(3, 3, 8)
	for tile in sim.world.tiles:
		tile.base_conductivity = 30
	var near = sim.world.add_entity("goblin", "Near", Vector2i(1, 0))
	var far = sim.world.add_entity("goblin", "Far", Vector2i(2, 0))
	var result = sim.step(Command.discharge(Vector2i.ZERO, 40))
	check_eq(near.health, 68, "distance one damage")
	check_eq(far.health, 76, "distance two damage")
	check_eq(count_events(result.events, "combat.electric_damage"), 2, "one damage per entity")
	var far_damage = null
	for event in result.events:
		if event.type == "combat.electric_damage" and event.target_id == far.id:
			far_damage = event
	var far_arc = sim.world.event_by_id(far_damage.cause_id)
	var parent_arc = sim.world.event_by_id(far_arc.cause_id)
	check_eq(parent_arc.type, "environment.electric_arc", "arc points to parent arc")
	check_eq(far_arc.data["from_position"], [1, 0], "arc from position")
	return finish()


func test_fire_and_electric_damage_use_common_damage_system() -> bool:
	var sim = Simulator.new(2, 1, 5)
	var fire_target = sim.world.add_entity("goblin", "Burning", Vector2i.ZERO)
	var electric_target = sim.world.add_entity("goblin", "Shocked", Vector2i(1, 0))
	var tile = sim.world.tile_at(Vector2i.ZERO)
	check(sim.world.bootstrap_set_fire(Vector2i.ZERO, 50) != null, "valid fire")
	sim.world.tile_at(Vector2i(1, 0)).base_conductivity = 30
	var wait_result = sim.step(Command.wait())
	var shock_result = sim.step(Command.discharge(Vector2i.ZERO, 20))
	check_eq(fire_target.health, 40, "fire plus discharge damage use one health path")
	check_eq(electric_target.health, 88, "electric common damage")
	check(find_event(wait_result.events, "combat.fire_damage") != null, "fire damage event")
	check(find_event(shock_result.events, "combat.electric_damage") != null, "electric damage event")
	_check_snapshot_round_trip(sim, "shared damage fixture")
	return finish()


func test_damage_and_death_are_emitted_once() -> bool:
	var sim = Simulator.new(1, 1, 6)
	var target = sim.world.add_entity("goblin", "Fragile", Vector2i.ZERO, 10)
	var source = sim.world.emit_event("test.attack")
	check_eq(sim.damage.apply_damage(target, 50, "fire", source.id), 10, "normalized lethal damage")
	check_eq(sim.damage.apply_damage(target, 50, "electric", source.id), 0, "dead target ignored")
	check_eq(count_events(sim.world.events, "entity.died"), 1, "single death event")
	check_eq(count_events(sim.world.events, "combat.fire_damage"), 1, "single damage event")
	return finish()


func test_two_environment_ticks_apply_two_fire_and_wetness_steps() -> bool:
	var sim = Simulator.new(1, 1, 21)
	var target = sim.world.add_entity("goblin", "Burning", Vector2i.ZERO)
	var tile = sim.world.tile_at(Vector2i.ZERO)
	tile.flammability = 100
	check(sim.world.bootstrap_set_fire(Vector2i.ZERO, 50) != null, "valid fire")
	check(sim.world.bootstrap_set_wetness(Vector2i.ZERO, 4) != null, "valid wetness")
	var result = sim.step(Command.wait_for(250))
	check_eq(tile.fire, 36, "two suppression/decay ticks")
	check_eq(tile.wetness, 0, "wetness processed across ticks")
	check_eq(target.health, 60, "two fire damage applications")
	check_eq(count_events(result.events, "combat.fire_damage"), 2, "two damage events")
	_check_snapshot_round_trip(sim, "two environment ticks")
	return finish()


func test_spread_eligibility_survives_json_and_slow_action_damage_occurs_before_ready() -> bool:
	var sim = Simulator.new(2, 1, 7)
	for tile in sim.world.tiles:
		tile.flammability = 100
	var target = sim.world.add_entity("goblin", "Reaction Window", Vector2i(1, 0))
	sim.world.bootstrap_set_fire(Vector2i.ZERO, 100)
	sim.step(Command.wait())
	var spread_tile = sim.world.tile_at(Vector2i(1, 0))
	check_eq(spread_tile.fire_damage_eligible_time, 200, "spread eligibility")
	check_eq(target.health, 100, "no creation-tick damage")
	var restored = Simulator.from_snapshot(JSON.parse_string(JSON.stringify(sim.snapshot())))
	var continuous_result = sim.step(Command.discharge(Vector2i.ZERO, 10))
	var restored_result = restored.step(Command.discharge(Vector2i.ZERO, 10))
	check_eq(target.health, 80, "T+100 damage occurs inside slow action")
	check(find_event(continuous_result.events, "combat.fire_damage") != null, "damage before ready")
	check_eq(restored_result.timeline, continuous_result.timeline, "restored timeline")
	check_eq(restored.snapshot(), sim.snapshot(), "eligibility/cause resume exact")
	return finish()


func _single_spread(seed: int, source_x: int, target_x: int):
	var sim = Simulator.new(3, 1, seed)
	for x in range(3):
		sim.world.tile_at(Vector2i(x, 0)).flammability = 100
	sim.world.bootstrap_set_fire(Vector2i(source_x, 0), 100)
	sim.step(Command.wait())
	return sim


func _blocked_collision(seed: int, mirrored: bool):
	var sim = Simulator.new(3, 1, seed)
	for x in range(3):
		sim.world.tile_at(Vector2i(x, 0)).flammability = 100
	var weak_x := 2 if mirrored else 0
	var strong_x := 0 if mirrored else 2
	sim.world.bootstrap_set_fire(Vector2i(weak_x, 0), 6)
	sim.world.bootstrap_set_fire(Vector2i(strong_x, 0), 100)
	sim.world.bootstrap_set_wetness(Vector2i(1, 0), 100)
	sim.step(Command.wait())
	return sim


func _check_snapshot_round_trip(sim, label: String) -> void:
	var snapshot = sim.snapshot()
	check(snapshot != null, "%s settled snapshot" % label)
	if snapshot == null:
		return
	var restored = Simulator.from_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
	check(restored != null, "%s checked restore" % label)
	if restored != null:
		check_eq(restored.snapshot(), snapshot, "%s exact round trip" % label)
