extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")
const Materials = preload("res://sim/material_registry.gd")
const Config = preload("res://sim/environment_config.gd")
const Style = preload("res://playtest/ascii_visual_style.gd")


func test_material_registry_is_gameplay_data_and_covers_four_substrates() -> bool:
	for material_id in ["STONE", "WOOD", "IRON", "RUBBER"]:
		var row: Dictionary = Materials.definition(material_id)
		check(not row.is_empty(), "%s exists" % material_id)
		for key in ["thermal_conductivity", "heat_capacity", "electric_conductivity",
				"flammability", "ignition_temperature", "combustion_heat",
				"initial_fuel", "mechanical_resistance"]:
			check(row.get(key) is int, "%s.%s integer" % [material_id, key])
	check_eq(Materials.material_for_terrain("metal"), "IRON", "metal mapping")
	check_eq(Materials.material_for_terrain("wood_floor"), "WOOD", "wood mapping")
	return finish()


func test_oil_on_stone_burns_surface_without_creating_stone_fuel() -> bool:
	var sim = Simulator.new(1, 1, 101)
	check(sim.world.bootstrap_set_terrain(Vector2i.ZERO, "stone_floor"), "stone")
	check(sim.world.bootstrap_set_surface(Vector2i.ZERO, "OIL", 300) != null, "oil")
	var tile = sim.world.tile_at(Vector2i.ZERO)
	check_eq(tile.fuel_amount, 0, "stone starts without fuel")
	check(sim.step(Command.ignite(Vector2i.ZERO, 80)).accepted, "ignite command")
	var oil_before: int = tile.surface_amount
	check(sim.step(Command.wait()).accepted, "burn tick")
	check(tile.surface_amount < oil_before, "oil consumed")
	check_eq(tile.fuel_amount, 0, "stone never becomes substrate fuel")
	return finish()


func test_wet_wood_delays_ignition_and_water_mass_changes_phase_once() -> bool:
	var sim = Simulator.new(1, 1, 102)
	check(sim.world.bootstrap_set_terrain(Vector2i.ZERO, "wood_floor"), "wood")
	check(sim.world.bootstrap_set_surface(Vector2i.ZERO, "WATER", 500) != null, "water")
	check(sim.world.bootstrap_set_atmosphere(Vector2i.ZERO, 500, 0, 0, 0, true),
		"sealed phase fixture")
	var tile = sim.world.tile_at(Vector2i.ZERO)
	sim.step(Command.ignite(Vector2i.ZERO, 40))
	check_eq(tile.fire, 0, "wet wood ignition delayed")
	check_eq(tile.surface_amount, 100, "ignition energy removes one water amount")
	tile.temperature = 1200; sim.world.track_dynamic_tile(Vector2i.ZERO)
	var before_mass: int = tile.surface_amount + tile.steam_amount
	sim.step(Command.wait())
	check_eq(tile.surface_amount + tile.steam_amount, before_mass,
		"evaporation does not duplicate water")
	tile.temperature = -100; sim.world.track_dynamic_tile(Vector2i.ZERO)
	sim.step(Command.wait())
	check_eq(tile.surface_amount + tile.steam_amount, before_mass,
		"condensation/freezing conserves represented water")
	check(tile.surface_id in ["WATER", "ICE"], "condensed water has one phase")
	return finish()


func test_smoke_respects_wall_then_moves_through_open_door() -> bool:
	var sim = Simulator.new(3, 1, 103)
	check(sim.world.bootstrap_set_terrain(Vector2i(1, 0), "door_closed"), "closed door")
	check(sim.world.bootstrap_set_atmosphere(Vector2i.ZERO, 500, 400, 0, 0), "smoke")
	sim.step(Command.wait())
	check_eq(sim.world.tile_at(Vector2i(2, 0)).smoke_amount, 0, "closed door blocks")
	var door = sim.world.tile_at(Vector2i(1, 0))
	door.terrain = "door_open"; door.material_id = "WOOD"
	sim.world.track_dynamic_tile(Vector2i(1, 0))
	for index in range(3): sim.step(Command.wait())
	check(sim.world.tile_at(Vector2i(2, 0)).smoke_amount > 0, "open door passes smoke")
	return finish()


func test_sealed_heating_raises_pressure_and_rupture_is_not_combustion() -> bool:
	var sim = Simulator.new(1, 1, 104)
	check(sim.world.bootstrap_set_atmosphere(Vector2i.ZERO, 1000, 500, 500, 500, true),
		"sealed atmosphere")
	check(sim.world.bootstrap_set_temperature(Vector2i.ZERO, 3000), "heated")
	var pressure_before: int = sim.world.tile_at(Vector2i.ZERO).pressure()
	var result = sim.step(Command.wait())
	check(pressure_before > Config.RUPTURE_PRESSURE, "fixture starts over rupture threshold")
	check(find_event(result.events, "environment.container_ruptured") != null, "rupture event")
	var explosion = find_event(result.events, "environment.explosion")
	check(explosion != null and explosion.data.kind == "rupture", "rupture kind distinct")
	return finish()


func test_v12_snapshot_roundtrip_and_preview_are_exact_and_pure() -> bool:
	var sim = Simulator.new(2, 1, 105)
	check(sim.world.bootstrap_set_surface(Vector2i.ZERO, "ICE", 250) != null, "ice")
	check(sim.world.bootstrap_set_atmosphere(Vector2i.ZERO, 700, 100, 80, 60, false),
		"atmosphere")
	check(sim.world.bootstrap_set_temperature(Vector2i.ZERO, -50), "temperature")
	var before: Dictionary = sim.snapshot()
	check_eq(before.snapshot_version, 12, "snapshot v12")
	check_eq(before.environment_ruleset_id, Config.RULESET_ID, "environment header")
	var sample_a: Dictionary = sim.sample_exposure(Vector2i.ZERO).to_dict()
	var sample_b: Dictionary = sim.sample_exposure(Vector2i.ZERO).to_dict()
	check_eq(sample_a, sample_b, "repeat preview")
	check_eq(sim.snapshot(), before, "preview does not mutate")
	var restored = Simulator.from_snapshot(JSON.parse_string(JSON.stringify(before)))
	check(restored != null, "restore")
	if restored != null: check_eq(restored.snapshot(), before, "exact roundtrip")
	return finish()


func test_same_seed_environment_command_replay_is_exact() -> bool:
	var a = Simulator.new(2, 2, 106)
	var b = Simulator.new(2, 2, 106)
	for sim in [a, b]:
		sim.world.bootstrap_set_terrain(Vector2i.ZERO, "wood_floor")
		sim.world.bootstrap_set_atmosphere(Vector2i.ZERO, 500, 0, 0, 180, false)
	var commands := [Command.ignite(Vector2i.ZERO, 80), Command.wait(), Command.wait()]
	for command in commands:
		a.step(command)
		b.step(Command.from_dict(command.to_dict()))
	check_eq(a.snapshot(), b.snapshot(), "same seed and commands")
	return finish()


func test_environment_overlays_are_visible_only_for_current_observation() -> bool:
	var visible: Dictionary = Style.hazard_spec({"visibility_state":"VISIBLE",
		"surface_id":"OIL","surface_amount":400,"temperature":900,
		"smoke_amount":200,"flammable_gas_amount":180})
	check_eq(visible.cues.map(func(row): return row.kind),
		["OIL", "HEAT", "SMOKE", "GAS"], "environment cue set")
	var memory: Dictionary = Style.hazard_spec({"visibility_state":"MEMORY",
		"surface_id":"OIL","surface_amount":400,"temperature":900,
		"smoke_amount":200,"flammable_gas_amount":180})
	check(memory.cues.is_empty(), "memory hides live environment")
	return finish()


func test_rubber_blocks_dry_electric_path_but_surface_water_conducts() -> bool:
	var dry = Simulator.new(3, 1, 107)
	dry.world.tile_at(Vector2i(1, 0)).material_id = "RUBBER"
	dry.world.tile_at(Vector2i(1, 0)).base_conductivity = 100
	dry.world.bootstrap_set_terrain(Vector2i(2, 0), "metal")
	var dry_target = dry.world.add_entity("goblin", "Dry", Vector2i(2, 0))
	dry.step(Command.discharge(Vector2i.ZERO, 40))
	check_eq(dry_target.health, 100, "dry rubber blocks")

	var wet = Simulator.new(3, 1, 108)
	wet.world.tile_at(Vector2i(1, 0)).material_id = "RUBBER"
	wet.world.tile_at(Vector2i(1, 0)).base_conductivity = 100
	wet.world.bootstrap_set_terrain(Vector2i(2, 0), "metal")
	wet.world.bootstrap_set_surface(Vector2i(1, 0), "WATER", 300)
	var wet_target = wet.world.add_entity("goblin", "Wet", Vector2i(2, 0))
	var wet_result = wet.step(Command.discharge(Vector2i.ZERO, 40))
	check(wet_result.accepted, "wet discharge accepted: %s / %s" % [
		wet_result.reason, wet.world.world_state_error()])
	check(wet_target.health < 100, "surface water bridges insulation")
	return finish()


func test_combustion_explosion_damage_and_cover_attenuation_are_bounded() -> bool:
	var sim = Simulator.new(5, 1, 109)
	for x in range(5): sim.world.bootstrap_set_terrain(Vector2i(x, 0), "metal")
	var target = sim.world.add_entity("goblin", "Blast target", Vector2i(1, 0))
	sim.world.bootstrap_set_atmosphere(Vector2i.ZERO, 500, 0, 0, 400, true)
	sim.world.bootstrap_set_fire(Vector2i.ZERO, 80)
	var result = sim.step(Command.wait())
	var explosion = find_event(result.events, "environment.explosion")
	check(explosion != null and explosion.data.kind == "combustion", "combustion event")
	check(target.health < 100, "nearby target receives shared fire/body damage path")
	var waves: Array = result.events.filter(
		func(event): return event.type == "environment.explosion_wave")
	check(waves.size() <= Config.MAX_EXPLOSION_CHAIN, "chain is bounded")
	var previous := 101
	for wave in waves:
		check(wave.magnitude < previous, "distance attenuation")
		previous = wave.magnitude
	return finish()


func test_heat_capacity_conduction_and_internal_gas_flux_are_simultaneous() -> bool:
	var iron = Simulator.new(2, 1, 110)
	var rubber = Simulator.new(2, 1, 110)
	for sim in [iron, rubber]:
		sim.world.bootstrap_set_terrain(Vector2i.ZERO, "metal")
		sim.world.bootstrap_set_temperature(Vector2i.ZERO, 1200)
	iron.world.bootstrap_set_terrain(Vector2i(1, 0), "metal")
	rubber.world.bootstrap_set_terrain(Vector2i(1, 0), "rubber_floor")
	iron.step(Command.wait()); rubber.step(Command.wait())
	check(iron.world.tile_at(Vector2i(1, 0)).temperature \
		> rubber.world.tile_at(Vector2i(1, 0)).temperature,
		"iron transfers more heat than rubber")

	var gas = Simulator.new(5, 5, 111)
	gas.world.bootstrap_set_atmosphere(Vector2i(2, 2), 500, 800, 0, 0)
	var before := _atmosphere_total(gas)
	gas.step(Command.wait())
	check_eq(_atmosphere_total(gas), before, "interior diffusion conserves gas mass")
	return finish()


func test_environment_fields_survive_sparse_rollback() -> bool:
	var sim = Simulator.new(2, 2, 112)
	sim.world.bootstrap_set_terrain(Vector2i.ZERO, "wood_floor")
	sim.world.bootstrap_set_surface(Vector2i.ZERO, "OIL", 333)
	sim.world.bootstrap_set_atmosphere(Vector2i.ZERO, 700, 111, 222, 123, true)
	sim.world.bootstrap_set_temperature(Vector2i.ZERO, 777)
	var before: Dictionary = sim.snapshot()
	var memento = sim.capture_rollback_memento()
	check(memento is Dictionary, "memento captured")
	sim.step(Command.ignite(Vector2i.ZERO, 70))
	check(sim.restore_rollback_memento(memento), "memento restored")
	check_eq(sim.snapshot(), before, "all environment scalars restored")
	return finish()


func _atmosphere_total(sim) -> int:
	var total := 0
	for tile in sim.world.tiles:
		total += tile.gas_amount + tile.smoke_amount + tile.steam_amount \
			+ tile.flammable_gas_amount
	return total
