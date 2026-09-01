extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Inventory = preload("res://sim/inventory_state.gd")
const Item = preload("res://sim/item_instance.gd")
const ActorLoadouts = preload("res://sim/actor_loadout_registry.gd")
const SpeciesDrops = preload("res://sim/species_drop_registry.gd")
const CorpseLoot = preload("res://sim/systems/corpse_loot_system.gd")
const WorldItems = preload("res://sim/world_item_operations.gd")


func test_content_registries_validate_and_goblin_spawns_with_real_equipment() -> bool:
	check_eq(ActorLoadouts.registry_error(), "", "actor loadout content validates")
	check_eq(SpeciesDrops.registry_error(), "", "species drop content validates")
	var sim = Simulator.create(8, 8, 31)
	var goblin = sim.world.add_entity("melee_enemy", "장비 고블린", Vector2i(4, 4), 20,
		["enemy"], "goblin", "enemy", "GOBLIN_MELEE_V1")
	check(goblin != null, "the goblin loadout materializes during spawn")
	if goblin == null: return finish()
	var inventory = sim.world.inventory_of(goblin.id)
	var weapon = inventory.equipped_item("MAIN_HAND")
	var armor = inventory.equipped_item("ARMOR")
	check(weapon != null and weapon.definition_id == "WEAPON_SHORT_SWORD",
		"the living goblin owns and equips its actual weapon instance")
	check(armor != null and armor.definition_id == "ARMOR_PADDED",
		"the living goblin owns and equips its actual armor instance")
	check_eq(inventory.backpack.size(), 2, "loadout equipment remains in the ownership table")
	check_eq(sim.world.world_state_error(), "", "the loadout world validates")
	return finish()


func test_death_materializes_once_preserves_loadout_and_consumes_no_rng() -> bool:
	var seed := _seed_with_goblin_drop()
	var fixture := _goblin_fixture(seed, true)
	var sim = fixture.sim
	var goblin = fixture.goblin
	var before = sim.world.inventory_of(goblin.id)
	var weapon_id := str(before.equipped.MAIN_HAND)
	var armor_id := str(before.equipped.ARMOR)
	var carried_before := {}
	carried_before[weapon_id] = before.item(weapon_id).to_dict()
	carried_before[armor_id] = before.item(armor_id).to_dict()
	var rng_before := int(sim.world.rng.state)
	var death = _kill_with_damage(sim, goblin, "fire")
	check(death != null, "environment-compatible damage produces a death event")
	check_eq(int(sim.world.rng.state), rng_before, "keyed drop rolls consume no global RNG")
	var after = sim.world.inventory_of(goblin.id)
	check_eq(after.backpack.size(), 0, "a dead actor retains no item container contents")
	check_eq([str(after.equipped.MAIN_HAND), str(after.equipped.ARMOR)],
		["", ""], "death clears equipment slots with the inventory")
	for instance_id in [weapon_id, armor_id]:
		var dropped = sim.world.ground_item(instance_id)
		check(dropped != null and dropped.to_dict() == carried_before[instance_id],
			"carried instance identity and options survive the ground drop")
		check_eq(sim.world.item_state.ground_items.position_of(instance_id), goblin.position,
			"every carried item lands at the death position")
	var materialized = _materialized_for(sim.world, int(death.id))
	check(materialized != null and materialized.data.generated_items.size() == 1,
		"the goblin species roll is recorded once")
	if materialized != null and not materialized.data.generated_items.is_empty():
		var generated: Dictionary = materialized.data.generated_items[0]
		check_eq(str(generated.definition_id), "GOBLIN_EAR",
			"the real species material, not a placeholder, is generated")
		check_eq(str(generated.location), "GROUND",
			"species loot is materialized directly on the ground")
		check(sim.world.ground_item(str(generated.instance_id)) != null,
			"the generated instance is stored on the ground")
	var revision := int(sim.world.item_state.revision)
	var event_count: int = sim.world.events.size()
	var repeated: Dictionary = CorpseLoot.materialize_death_event(sim.world, death)
	check(bool(repeated.accepted) and bool(repeated.already_processed),
		"processing the same death again is an idempotent success")
	check_eq([sim.world.item_state.revision, sim.world.events.size()],
		[revision, event_count], "reprocessing changes neither items nor events")
	check_eq(sim.world.world_state_error(), "", "the materialized death-drop world validates")
	var restored = Simulator.from_snapshot(sim.snapshot())
	check(restored != null and restored.snapshot() == sim.snapshot(),
		"ground drops and the processed-death ledger round-trip exactly")
	return finish()


func test_same_seed_and_death_id_produce_the_same_drop_without_global_rng() -> bool:
	var seed := _seed_with_goblin_drop()
	var first := _goblin_fixture(seed, false)
	var second := _goblin_fixture(seed, false)
	var first_rng := int(first.sim.world.rng.state)
	var second_rng := int(second.sim.world.rng.state)
	var first_death = _kill_with_damage(first.sim, first.goblin, "electric")
	var second_death = _kill_with_damage(second.sim, second.goblin, "electric")
	var first_event = _materialized_for(first.sim.world, int(first_death.id))
	var second_event = _materialized_for(second.sim.world, int(second_death.id))
	check_eq(first_event.data.generated_items, second_event.data.generated_items,
		"same seed, source event and allocator state produce exact item rows")
	check_eq([int(first.sim.world.rng.state), int(second.sim.world.rng.state)],
		[first_rng, second_rng], "neither identical roll advances its world RNG")
	return finish()


func test_dropped_equipment_uses_the_existing_ground_pickup_path() -> bool:
	var sim = Simulator.create(7, 7, _seed_with_goblin_drop())
	var hero = sim.world.add_entity("other", "회수자", Vector2i(2, 3), 20,
		[], "human", "player")
	var goblin = sim.world.add_entity("melee_enemy", "고블린", Vector2i(3, 3), 10,
		[], "goblin", "enemy", "GOBLIN_MELEE_V1")
	var weapon_id := str(sim.world.inventory_of(goblin.id).equipped.MAIN_HAND)
	_kill_with_damage(sim, goblin, "fire")
	var pickup := WorldItems.commit_pickup(sim.world, hero.id, weapon_id,
		goblin.position)
	check(bool(pickup.accepted), "ordinary ground pickup accepts dropped equipment")
	check(sim.world.inventory_of(hero.id).item(weapon_id) != null,
		"pickup transfers the exact weapon instance to the living actor")
	check_eq(str(sim.world.inventory_of(hero.id).equipped.MAIN_HAND), "",
		"picked-up equipment is not auto-equipped")
	check(sim.world.ground_item(weapon_id) == null,
		"the picked-up instance no longer remains on the ground")
	check_eq(sim.world.world_state_error(), "", "pickup after a death drop validates")
	return finish()


func test_species_without_a_table_records_one_empty_materialization() -> bool:
	var sim = Simulator.create(6, 6, 72)
	var human = sim.world.add_entity("other", "사람", Vector2i(3, 3), 8,
		[], "human", "neutral")
	var death = _kill_with_damage(sim, human, "fire")
	var event = _materialized_for(sim.world, int(death.id))
	check(event != null, "a tableless species still records completed processing")
	check_eq(event.data.generated_items, [], "a tableless species creates no extra item")
	check_eq(event.magnitude, 0, "an empty materialization has zero quantity")
	check_eq(sim.world.item_state.processed_drop_death_event_ids, [int(death.id)],
		"the empty result is distinguishable from an unprocessed death")
	check_eq(sim.world.world_state_error(), "", "empty materialization remains canonical")
	return finish()


func test_full_inventory_drops_every_item_and_species_roll_to_the_same_position() -> bool:
	var seed := _seed_with_goblin_drop()
	var sim = Simulator.create(7, 7, seed)
	var goblin = sim.world.add_entity("melee_enemy", "짐꾼 고블린", Vector2i(3, 3), 10,
		[], "goblin", "enemy")
	var full_rows: Array = []
	for index in range(Inventory.BACKPACK_CAPACITY):
		full_rows.append(Item.new("FULL_%02d" % index, "MATERIAL_UNSPECIFIED", 1))
	sim.world.item_state.inventory_rows[goblin.id] = Inventory.new(full_rows)
	var death = _kill_with_damage(sim, goblin, "fire")
	var event = _materialized_for(sim.world, int(death.id))
	check(event != null and event.data.generated_items.size() == 1,
		"the successful roll is still recorded for a full inventory")
	if event != null and not event.data.generated_items.is_empty():
		var generated: Dictionary = event.data.generated_items[0]
		check_eq(str(generated.location), "GROUND", "species loot always targets the ground")
		check(sim.world.ground_item(str(generated.instance_id)) != null,
			"the generated item is not deleted")
		check_eq(sim.world.item_state.ground_items.position_of(str(generated.instance_id)),
			goblin.position, "species loot lands at the death position")
	check_eq(sim.world.inventory_of(goblin.id).backpack.size(), 0,
		"the dead actor inventory is empty")
	check_eq(_ground_item_ids_at(sim.world, goblin.position).size(),
		Inventory.BACKPACK_CAPACITY + 1,
		"all carried rows and the generated row coexist on one tile")
	for index in range(Inventory.BACKPACK_CAPACITY):
		check(sim.world.ground_item("FULL_%02d" % index) != null,
			"every pre-existing inventory instance is preserved")
	check_eq(sim.world.world_state_error(), "", "direct ground drops preserve all invariants")
	return finish()


func test_multiple_deaths_allocate_unique_instances() -> bool:
	var seed := _seed_with_goblin_drop_for_first_two_deaths()
	var sim = Simulator.create(9, 9, seed)
	var first = sim.world.add_entity("melee_enemy", "첫 고블린", Vector2i(3, 3), 9,
		[], "goblin", "enemy", "GOBLIN_MELEE_V1")
	var second = sim.world.add_entity("melee_enemy", "둘째 고블린", Vector2i(5, 5), 9,
		[], "goblin", "enemy", "GOBLIN_MELEE_V1")
	var first_death = _kill_with_damage(sim, first, "fire")
	var second_death = _kill_with_damage(sim, second, "electric")
	var first_rows: Array = _materialized_for(sim.world, int(first_death.id)).data.generated_items
	var second_rows: Array = _materialized_for(sim.world, int(second_death.id)).data.generated_items
	check_eq([first_rows.size(), second_rows.size()], [1, 1],
		"the chosen seed exercises both independent drop rolls")
	if not first_rows.is_empty() and not second_rows.is_empty():
		check(str(first_rows[0].instance_id) != str(second_rows[0].instance_id),
			"two deaths never receive the same allocated instance")
	var all_ids: Dictionary = {}
	for entity_id in sim.world.item_state.inventory_rows:
		for item in sim.world.item_state.inventory_rows[entity_id].backpack:
			check(not all_ids.has(item.instance_id), "every owned instance is globally unique")
			all_ids[item.instance_id] = true
	for row in sim.world.item_state.ground_items.rows:
		check(not all_ids.has(row.item.instance_id), "every ground instance is globally unique")
		all_ids[row.item.instance_id] = true
	check_eq([sim.world.inventory_of(first.id).backpack.size(),
		sim.world.inventory_of(second.id).backpack.size()], [0, 0],
		"both dead actors leave empty inventories")
	check_eq(sim.world.world_state_error(), "", "multiple materialized deaths validate")
	return finish()


func test_lethal_damage_reserves_the_materialization_event_before_mutating() -> bool:
	var sim = Simulator.create(5, 5, 91)
	var target = sim.world.add_entity("other", "경계값 대상", Vector2i(2, 2), 7,
		[], "human", "neutral")
	sim.world.begin_step(1)
	var source = sim.world.emit_event("environment.ignited", -1, -1,
		target.position, 100)
	check(source != null, "the overflow fixture has a valid damage source")
	if source == null: return finish()
	# Three IDs are required: damage, death and corpse.loot_materialized.
	sim.world._next_event_id = 9223372036854775805
	var hp_before := int(target.health)
	var events_before: Array = sim.world.events.duplicate()
	var items_before: Dictionary = sim.world.item_state.to_dict()
	var applied: int = sim.damage.apply_damage(target, hp_before, "fire",
		int(source.id), target.position, 1)
	check_eq(applied, 0, "insufficient derived-event headroom rejects before damage")
	check_eq(target.health, hp_before, "rejected lethal damage preserves health")
	check_eq(sim.world.events, events_before, "rejected lethal damage appends no event")
	check_eq(sim.world.item_state.to_dict(), items_before,
		"rejected lethal damage cannot partially materialize corpse items")
	return finish()


func _goblin_fixture(seed: int, with_loadout: bool) -> Dictionary:
	var sim = Simulator.create(7, 7, seed)
	var goblin = sim.world.add_entity("melee_enemy", "고블린", Vector2i(3, 3), 10,
		[], "goblin", "enemy", "GOBLIN_MELEE_V1" if with_loadout else "")
	return {"sim": sim, "goblin": goblin}


func _kill_with_damage(sim, entity, damage_type: String):
	var processed_step := int(sim.world.step_index) + 1
	sim.world.begin_step(processed_step)
	var event_start: int = sim.world.events.size()
	var source = sim.world.emit_event("environment.ignited" if damage_type == "fire" \
		else "environment.electric_arc", -1, -1, entity.position,
		100 if damage_type == "fire" else int(entity.health), -1,
		{} if damage_type == "fire" else {"distance": 0, "from_position": [-1, -1]})
	var applied: int = sim.damage.apply_damage(entity, int(entity.health), damage_type,
		int(source.id),
		entity.position, processed_step)
	var death = null
	for event in sim.world.events_since(event_start):
		if event.type == "entity.died": death = event
	sim.world.finish_step()
	check_eq(applied, int(entity.max_health), "fixture damage is lethal")
	return death


func _materialized_for(world, death_event_id: int):
	for event in world.events:
		if event.type == "corpse.loot_materialized" and event.cause_id == death_event_id:
			return event
	return null


func _ground_item_ids_at(world, position: Vector2i) -> Array[String]:
	var result: Array[String] = []
	for row in world.item_state.ground_items.rows:
		if row.position == position: result.append(str(row.item.instance_id))
	result.sort()
	return result


func _seed_with_goblin_drop() -> int:
	for candidate in range(1, 5000):
		# Environment source + damage precede death, so the source death ID is 3.
		if not SpeciesDrops.rolls_for(candidate, 3, "goblin").is_empty(): return candidate
	return -1


func _seed_with_goblin_drop_for_first_two_deaths() -> int:
	for candidate in range(1, 5000):
		# Each death emits source, damage, death and materialization: IDs 3 and 7.
		if not SpeciesDrops.rolls_for(candidate, 3, "goblin").is_empty() \
				and not SpeciesDrops.rolls_for(candidate, 7, "goblin").is_empty():
			return candidate
	return -1
