extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")
const Materials = preload("res://sim/material_registry.gd")
const Config = preload("res://sim/environment_config.gd")
const Style = preload("res://playtest/ascii_visual_style.gd")
const Perception = preload("res://sim/enemy_perception_registry.gd")
const VisualMap = preload("res://playtest/party_visual_test_map.gd")
const EnvironmentArmor = preload("res://sim/environment_armor_registry.gd")
const BodyCombatRules = preload("res://sim/body_combat_rules.gd")


func test_material_registry_covers_terrain_and_armor_substrates() -> bool:
	for material_id in ["STONE", "WOOD", "IRON", "RUBBER", "LEATHER", "TEXTILE"]:
		var row: Dictionary = Materials.definition(material_id)
		check(not row.is_empty(), "%s exists" % material_id)
		for key in ["thermal_conductivity", "heat_capacity", "electric_conductivity",
				"flammability", "ignition_temperature", "combustion_heat",
				"initial_fuel", "mechanical_resistance"]:
			check(row.get(key) is int, "%s.%s integer" % [material_id, key])
	check_eq(Materials.material_for_terrain("metal"), "IRON", "metal mapping")
	check_eq(Materials.material_for_terrain("wood_floor"), "WOOD", "wood mapping")
	return finish()


func test_phase_change_respects_destination_capacity_without_mass_loss() -> bool:
	var evaporation=Simulator.new(1,1,117)
	check(evaporation.world.bootstrap_set_surface(Vector2i.ZERO,"WATER",100)!=null,
		"evaporation water")
	check(evaporation.world.bootstrap_set_atmosphere(Vector2i.ZERO,0,0,950,0,true),
		"nearly full steam destination")
	check(evaporation.world.bootstrap_set_temperature(Vector2i.ZERO,1200),
		"boiling temperature")
	var evaporation_before:int=evaporation.world.tile_at(Vector2i.ZERO).surface_amount \
		+evaporation.world.tile_at(Vector2i.ZERO).steam_amount
	var evaporation_result=evaporation.step(Command.wait())
	var evaporated=find_event(evaporation_result.events,"environment.water_evaporated")
	check(evaporated!=null and evaporated.magnitude==50,
		"evaporation stops at steam capacity")
	check_eq(evaporation.world.tile_at(Vector2i.ZERO).surface_amount \
		+evaporation.world.tile_at(Vector2i.ZERO).steam_amount,evaporation_before,
		"capacity-limited evaporation conserves represented water")

	var condensation=Simulator.new(1,1,118)
	check(condensation.world.bootstrap_set_surface(Vector2i.ZERO,"WATER",950)!=null,
		"nearly full surface destination")
	check(condensation.world.bootstrap_set_atmosphere(Vector2i.ZERO,0,0,100,0,true),
		"condensing steam")
	check(condensation.world.bootstrap_set_temperature(Vector2i.ZERO,200),
		"condensation temperature")
	var condensation_before:int=condensation.world.tile_at(Vector2i.ZERO).surface_amount \
		+condensation.world.tile_at(Vector2i.ZERO).steam_amount
	var condensation_result=condensation.step(Command.wait())
	var condensed=find_event(condensation_result.events,"environment.steam_condensed")
	check(condensed!=null and condensed.magnitude==50,
		"condensation stops at surface capacity")
	check_eq(condensation.world.tile_at(Vector2i.ZERO).surface_amount \
		+condensation.world.tile_at(Vector2i.ZERO).steam_amount,condensation_before,
		"capacity-limited condensation conserves represented water")
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
	check_eq(tile.surface_amount + tile.steam_amount, 500,
		"ignition moves water into steam instead of deleting it")
	check(tile.steam_amount > 0, "ignition produces steam")
	tile.temperature = 1200; sim.world.track_dynamic_tile(Vector2i.ZERO)
	var before_mass: int = tile.surface_amount + tile.steam_amount
	sim.step(Command.wait())
	check_eq(tile.surface_amount + tile.steam_amount, before_mass,
		"evaporation does not duplicate water")
	# Conducted/high ambient heat now ignites wood too. Cool through burnout,
	# rather than expecting cold condensate to survive an active flame.
	for i in range(20):
		tile.temperature = -100; sim.world.track_dynamic_tile(Vector2i.ZERO)
		check(sim.step(Command.wait()).accepted, "cooling tick accepted")
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


func test_explosion_knockback_and_destruction_are_single_ordered_and_restorable() -> bool:
	var sim=Simulator.new(6,3,113)
	check(sim.world.bootstrap_set_terrain(Vector2i(1,2),"door_closed"),"door fixture")
	var target=sim.world.add_entity("goblin","밀쳐질 대상",Vector2i(2,1))
	var before=sim.capture_rollback_memento()
	var root=sim.world.emit_event("test.explosion_source")
	sim.world.begin_step(1)
	check(sim.environment.explode(Vector2i(1,1),100,root.id,1,"combustion"),"explosion")
	sim.world.finish_step()
	check_eq(target.position,Vector2i(3,1),"target is pushed exactly one cell")
	check_eq(sim.world.tile_at(Vector2i(1,2)).terrain,"rubble","weak closed door is destroyed")
	check_eq(sim.world.events.filter(func(event):return event.type=="environment.knockback").size(),
		1,"one knockback event per original occupant")
	check_eq(sim.world.events.filter(func(event):return event.type=="environment.terrain_destroyed").size(),
		1,"one destruction event per tile")
	check_eq(sim.world.events.filter(func(event):return event.type=="environment.explosion_impact").size(),
		1,"one mechanical impact per original occupant")
	check_eq(sim.world.events.filter(func(event):return event.type=="combat.physical_damage").size(),
		1,"explosion impact uses the physical damage and body path")
	check_eq(sim.world.world_state_error(),"","post-explosion state validates")
	var snapshot:Dictionary=sim.snapshot()
	var restored=Simulator.from_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
	check(restored!=null,"dynamic terrain and knockback restore")
	if restored!=null:check_eq(restored.snapshot(),snapshot,"explosion round trip is exact")
	check(sim.restore_rollback_memento(before),"pre-explosion rollback restores")
	check_eq([sim.world.entities[target.id].position,
		sim.world.tile_at(Vector2i(1,2)).terrain],[Vector2i(2,1),"door_closed"],
		"rollback restores position and topology")
	return finish()


func test_rupture_explosion_applies_impact_without_combustion_damage() -> bool:
	var sim=Simulator.new(4,1,117)
	var target=sim.world.add_entity("goblin","파열 충격 대상",Vector2i(1,0))
	var root=sim.world.emit_event("test.rupture_source")
	sim.world.begin_step(1)
	check(sim.environment.explode(Vector2i.ZERO,80,root.id,1,"rupture"),
		"rupture explosion")
	sim.world.finish_step()
	check(target.health<100,"rupture wave applies mechanical damage")
	check_eq(sim.world.events.filter(func(event):return event.type=="combat.fire_damage").size(),
		0,"rupture does not invent combustion damage")
	check_eq(sim.world.events.filter(func(event):return event.type=="combat.physical_damage").size(),
		1,"rupture uses the physical damage path once")
	check_eq(sim.world.world_state_error(),"","rupture impact state validates")
	return finish()


func test_environment_armor_coverage_material_and_wetness_apply_once() -> bool:
	check_eq(EnvironmentArmor.registry_error(),"","environment armor registry")
	var uncovered=_armor_probe("ARMOR_PADDED","fire",80,"HEAD",0)
	var covered=_armor_probe("ARMOR_PADDED","fire",80,"TORSO",0)
	check_eq([uncovered.final_damage,covered.final_damage],[80,44],
		"coverage gates the padded material reduction")
	var padded_dry:=_environment_damage_with_armor("ARMOR_PADDED",0)
	var leather_dry:=_environment_damage_with_armor("ARMOR_LEATHER",0)
	var padded_wet:=_environment_damage_with_armor("ARMOR_PADDED",100)
	check_eq([padded_dry,leather_dry,padded_wet],[36,56,69],
		"material differs, wet insulation weakens, and reduction is applied once")
	return finish()


func test_dense_smoke_blocks_shared_los_without_hiding_its_own_cell() -> bool:
	var sim=Simulator.new(5,1,114)
	check(sim.world.bootstrap_set_atmosphere(Vector2i(2,0),500,
		Config.SMOKE_LOS_BLOCK_AMOUNT,0,0),"middle smoke")
	check(not Perception.has_line_of_sight(sim.world,Vector2i.ZERO,Vector2i(4,0)),
		"dense intermediate smoke blocks authoritative LOS")
	check(Perception.has_line_of_sight(sim.world,Vector2i.ZERO,Vector2i(2,0)),
		"the smoke tile itself remains observable")
	var visible:Dictionary=VisualMap.visible_cells(sim.world,Vector2i.ZERO,
		VisualMap.SHOWCASE_SCENARIO_ID)
	check(not visible.has("4:0") and visible.has("2:0"),
		"presentation FOV uses the same smoke rule")
	return finish()


func _armor_probe(definition_id:String,damage_type:String,damage:int,
		part_id:String,wetness:int)->Dictionary:
	var sim=Simulator.new(1,1,115)
	var target=sim.world.add_entity("goblin","방어구 probe",Vector2i.ZERO,100,[],
		"goblin","","GOBLIN_MELEE_V1")
	var inventory=sim.world.item_state.inventory(target.id)
	for item in inventory.backpack:
		if item.definition_id=="ARMOR_PADDED":item.definition_id=definition_id
	return EnvironmentArmor.assess(sim.world,target.id,damage_type,damage,part_id,wetness)


func _environment_damage_with_armor(definition_id:String,wetness:int)->int:
	var sim=Simulator.new(1,1,116)
	var target=sim.world.add_entity("goblin","환경 피격",Vector2i.ZERO,100,[],
		"goblin","","GOBLIN_MELEE_V1")
	var inventory=sim.world.item_state.inventory(target.id)
	for item in inventory.backpack:
		if item.definition_id=="ARMOR_PADDED":item.definition_id=definition_id
	if wetness>0:sim.world.bootstrap_set_surface(Vector2i.ZERO,"WATER",wetness*10)
	sim.world.begin_step(1)
	var next_id:int=sim.world._next_event_id
	while BodyCombatRules.select_part(sim.world.body_states[target.id],
			("environment-armor-v1|%d|%d|%d|electric"%[
			next_id,target.id,sim.world.world_time]).sha256_text(),target.id)=="HEAD":
		sim.world.emit_event("test.armor_part_padding")
		next_id=sim.world._next_event_id
	var arc=sim.world.emit_event("environment.electric_arc",-1,-1,Vector2i.ZERO,80,-1,
		{"distance":0,"from_position":[-1,-1]})
	var applied:int=sim.damage.apply_damage(target,80,"electric",arc.id,
		Vector2i.ZERO,1)
	sim.world.finish_step()
	check_eq(sim.world.world_state_error(),"","armored environment damage validates")
	return applied


func test_small_water_remainders_do_not_block_turns_or_restore() -> bool:
	for mass in range(81, 90):
		var sim = Simulator.new(1, 1, 201)
		sim.world.bootstrap_set_surface(Vector2i.ZERO, "WATER", mass)
		sim.world.bootstrap_set_atmosphere(Vector2i.ZERO, 0, 0, 0, 0, true)
		sim.world.bootstrap_set_temperature(Vector2i.ZERO, 1200)
		check(sim.step(Command.wait()).accepted, "evaporation accepted %d" % mass)
		var tile = sim.world.tile_at(Vector2i.ZERO)
		check_eq(tile.surface_amount, mass - 80, "small remainder retained")
		check_eq(tile.wetness_source_event_id, -1, "zero wetness clears source")
		var restored = Simulator.from_snapshot(sim.snapshot())
		check(restored != null, "remainder snapshot restores")
		check(sim.step(Command.wait()).accepted, "next turn accepted")
		if restored != null:
			check(restored.step(Command.wait()).accepted, "restored next turn accepted")
			check_eq(restored.snapshot(), sim.snapshot(), "midpoint replay exact")
	return finish()


func test_conducted_heat_ignites_wood_and_fire_spreads_to_oil() -> bool:
	var heat = Simulator.new(2, 1, 202)
	heat.world.bootstrap_set_terrain(Vector2i.RIGHT, "wood_floor")
	for pos in [Vector2i.ZERO, Vector2i.RIGHT]:
		heat.world.bootstrap_set_atmosphere(pos, 500, 0, 0, 0, true)
	heat.world.bootstrap_set_temperature(Vector2i.ZERO, 4000)
	heat.world.bootstrap_set_temperature(Vector2i.RIGHT, 649)
	check(heat.step(Command.wait()).accepted, "conducted heat tick accepted")
	check(heat.world.tile_at(Vector2i.RIGHT).fire > 0, "crossing ignition point ignites wood")
	check_eq(heat.world.world_state_error(), "", "thermal ignition source validates")
	var oil = Simulator.new(2, 1, 101)
	oil.world.bootstrap_set_terrain(Vector2i.ZERO, "wood_floor")
	oil.world.bootstrap_set_surface(Vector2i.RIGHT, "OIL", 300)
	check(oil.step(Command.ignite(Vector2i.ZERO, 100)).accepted, "source ignites")
	for i in range(10): check(oil.step(Command.wait()).accepted, "spread tick")
	check(oil.world.tile_at(Vector2i.RIGHT).surface_amount < 300,
		"adjacent oil on nonflammable stone catches and burns")
	return finish()


func test_poured_water_enters_freezing_and_boiling_paths() -> bool:
	for temperature in [-100, 1200]:
		var sim = Simulator.new(1, 1, 203)
		sim.world.bootstrap_set_temperature(Vector2i.ZERO, temperature)
		sim.world.bootstrap_set_atmosphere(Vector2i.ZERO, 500, 0, 0, 0, true)
		check(sim.step(Command.pour_water(Vector2i.ZERO, 60)).accepted, "pour accepted")
		check(sim.step(Command.wait()).accepted, "phase cadence accepted")
		var tile = sim.world.tile_at(Vector2i.ZERO)
		check_eq(tile.surface_amount + tile.steam_amount, 600, "poured mass exists")
		if temperature < 0:
			check_eq(tile.surface_id, "ICE", "poured water freezes")
		else:
			check(tile.steam_amount > 0, "poured water boils")
		check(Simulator.from_snapshot(sim.snapshot()) != null, "poured phase restores")
	return finish()


func test_saturated_steam_preserves_water_during_ignition_and_suppression() -> bool:
	for burning in [false, true]:
		var sim = Simulator.new(1, 1, 204)
		sim.world.bootstrap_set_terrain(Vector2i.ZERO, "wood_floor")
		sim.world.bootstrap_set_surface(Vector2i.ZERO, "WATER", 500)
		sim.world.bootstrap_set_atmosphere(Vector2i.ZERO, 0, 0, 1000, 0, true)
		if burning:
			check(sim.world.bootstrap_set_fire(Vector2i.ZERO, 80) != null,
				"valid existing fire fixture")
		var result = sim.step(Command.wait() if burning else Command.ignite(Vector2i.ZERO, 80))
		check(result.accepted, "saturated reaction accepted")
		var tile = sim.world.tile_at(Vector2i.ZERO)
		check_eq(tile.surface_amount + tile.steam_amount, 1500, "represented water conserved")
		check_eq(sim.world.world_state_error(), "", "saturated wetness source valid")
	return finish()


func test_resting_water_and_consumed_fuel_skip_flux_but_survive_rollback() -> bool:
	var sim = Simulator.new(2, 1, 205)
	sim.world.bootstrap_set_surface(Vector2i.ZERO, "WATER", 500)
	sim.world.bootstrap_set_terrain(Vector2i.RIGHT, "wood_floor")
	var wood = sim.world.tile_at(Vector2i.RIGHT)
	wood.fuel_amount = 0; sim.world.track_dynamic_tile(Vector2i.RIGHT)
	check(not sim.environment._needs_passive_tick(wood), "spent fuel needs no flux")
	check(not sim.environment._needs_passive_tick(sim.world.tile_at(Vector2i.ZERO)),
		"resting water needs no flux")
	var before: Dictionary = sim.snapshot()
	var memento = sim.capture_rollback_memento()
	for i in range(100): check(sim.step(Command.wait()).accepted, "resting tick")
	check_eq(sim.world.tile_at(Vector2i.ZERO).surface_amount, 500, "resting water retained")
	check_eq(wood.fuel_amount, 0, "spent fuel never resets")
	check(sim.restore_rollback_memento(memento), "resting state rollback")
	check_eq(sim.snapshot(), before, "persistent sparse state retained exactly")
	return finish()


func test_resting_water_wakes_from_neighbor_heat_and_equilibrium_snaps() -> bool:
	var sim = Simulator.new(2, 1, 206)
	sim.world.bootstrap_set_surface(Vector2i.ZERO, "WATER", 500)
	for pos in [Vector2i.ZERO, Vector2i.RIGHT]:
		sim.world.bootstrap_set_atmosphere(pos, 500, 0, 0, 0, true)
	sim.world.bootstrap_set_temperature(Vector2i.RIGHT, 4000)
	check(not sim.environment._needs_passive_tick(sim.world.tile_at(Vector2i.ZERO)),
		"water starts resting")
	check(sim.step(Command.wait()).accepted, "neighbor heat tick accepted")
	check(sim.world.tile_at(Vector2i.ZERO).temperature > Config.AMBIENT_TEMPERATURE,
		"resting water participates in neighbor flux")
	var equilibrium = Simulator.new(1, 1, 207)
	equilibrium.world.bootstrap_set_temperature(Vector2i.ZERO, Config.AMBIENT_TEMPERATURE + 2)
	equilibrium.world.bootstrap_set_atmosphere(Vector2i.ZERO, 500, 0, 0, 0, true)
	check(equilibrium.step(Command.wait()).accepted, "equilibrium tick accepted")
	check_eq(equilibrium.world.tile_at(Vector2i.ZERO).temperature, Config.AMBIENT_TEMPERATURE,
		"epsilon residual settles")
	check(not equilibrium.environment._needs_passive_tick(equilibrium.world.tile_at(Vector2i.ZERO)),
		"settled temperature stops flux work")
	return finish()


func _atmosphere_total(sim) -> int:
	var total := 0
	for tile in sim.world.tiles:
		total += tile.gas_amount + tile.smoke_amount + tile.steam_amount \
			+ tile.flammable_gas_amount
	return total
