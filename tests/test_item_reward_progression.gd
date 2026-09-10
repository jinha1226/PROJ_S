extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Inventory = preload("res://sim/inventory_state.gd")
const Item = preload("res://sim/item_instance.gd")
const ItemRegistry = preload("res://sim/item_registry.gd")
const ItemCatalog = preload("res://sim/item_catalog_registry.gd")
const ItemRewardRules = preload("res://sim/item_reward_rules.gd")
const SpeciesDrops = preload("res://sim/species_drop_registry.gd")
const WeaponRegistry = preload("res://sim/weapon_registry.gd")
const WeaponRecraftRegistry = preload("res://sim/weapon_recraft_registry.gd")
const WorldItems = preload("res://sim/world_item_operations.gd")


func test_reward_and_recraft_registries_validate() -> bool:
	check_eq(ItemRegistry.registry_error(), "", "item content validates")
	check_eq(ItemCatalog.registry_error(), "", "item catalog validates")
	check_eq(WeaponRegistry.registry_error(), "", "weapon content validates")
	check_eq(SpeciesDrops.registry_error(), "", "species reward content validates")
	check_eq(WeaponRecraftRegistry.registry_error(), "", "recraft recipes validate")
	check_eq(ItemRewardRules.family_for_item("MATERIAL_IRON_INGOT"),
		"WEAPON_MATERIAL", "iron is a weapon material")
	check_eq(ItemRewardRules.family_for_item("MAGIC_STONE"),
		"CURRENCY", "magic stone is currency")
	check_eq(ItemRewardRules.family_for_item("ESSENCE_FIRE_BOLT"),
		"MONSTER_ABILITY", "ability essence is a distinct acquisition item")
	check_eq(ItemRewardRules.ability_for_item("ESSENCE_FIRE_BOLT"),
		"FIREBOLT", "ability essence points to a real skill")
	return finish()


func test_goblin_rewards_are_keyed_and_have_no_duplicate_reward_ids() -> bool:
	var first := SpeciesDrops.rewards_for(4417, 9, "goblin")
	var second := SpeciesDrops.rewards_for(4417, 9, "goblin")
	check_eq(first, second, "same seed and death id replay the same reward rows")
	check_eq(first.size(), 1, "the representative goblin has one currently authored reward")
	var ids:Dictionary = {}
	var families:Dictionary = {}
	for row in first:
		ids[str(row.reward_id)] = true
		families[str(row.reward_family)] = true
	check_eq(ids.size(), first.size(), "reward ids are unique")
	check(families.has("CURRENCY"), "goblin rewards include currency")
	check(not families.has("MONSTER_ABILITY"),
		"an ability is not generated without a monster source that uses it")
	return finish()


func test_recraft_preserves_identity_affixes_and_equipment_atomically() -> bool:
	var sim = Simulator.create(7, 7, 90210)
	var hero = sim.world.add_entity("other", "재제작자", Vector2i(3, 3), 20,
		[], "human", "player")
	if hero == null:
		check(false, "recraft fixture hero spawned")
		return finish()
	var sword := Item.new("SWORD_01", "WEAPON_SHORT_SWORD", 1, "RARE", ["NIMBLE"])
	var ingot := Item.new("INGOT_01", "MATERIAL_IRON_INGOT", 2)
	sim.world.item_state.inventory_rows[hero.id] = Inventory.new(
		[sword, ingot], {"MAIN_HAND":"SWORD_01"})
	var before:Dictionary = sim.world.inventory_of(hero.id).to_dict()
	var preview := WorldItems.preview_recraft(sim.world, hero.id, "SWORD_01")
	check(bool(preview.accepted), "recraft preview accepts a valid recipe")
	var result := WorldItems.commit_recraft(sim.world, hero.id, "SWORD_01", hero.position)
	check(bool(result.accepted), "recraft commit accepts a valid recipe")
	var after:Variant = sim.world.inventory_of(hero.id)
	check(after != null, "recraft leaves an inventory projection")
	if after != null:
		var upgraded = after.item("SWORD_01")
		check(upgraded != null and upgraded.definition_id == "WEAPON_SHORT_SWORD_IRON",
			"recraft changes only the weapon definition")
		check_eq(upgraded.affix_ids, ["NIMBLE"], "recraft preserves affixes")
		check_eq(str(after.equipped.MAIN_HAND), "SWORD_01", "recraft preserves equipment")
		check(after.item("INGOT_01") != null and after.item("INGOT_01").quantity == 1,
			"recraft consumes exactly one material")
	check_eq(sim.world.item_state.revision, 1, "recraft is one atomic item revision")
	check_eq(count_events(sim.world.events, "weapon.recrafted"), 1,
		"recraft writes one canonical event")
	var rejected := WorldItems.commit_recraft(sim.world, hero.id, "SWORD_01", hero.position)
	check(not bool(rejected.accepted), "the next tier requires its own material")
	check_eq(rejected.reason, "recraft_material_insufficient", "iron to steel cannot skip its material cost")
	return finish()


func test_six_item_families_publish_tier_depth_trade_and_effect_contracts() -> bool:
	for family in ItemCatalog.FAMILIES:
		check(not ItemCatalog.ids_for_family(family).is_empty(), "%s has active definitions" % family)
	check_eq(ItemCatalog.healing_amount("POTION_HEALING_MINOR"), 20, "minor potion heals its own amount")
	check_eq(ItemCatalog.healing_amount("POTION_HEALING"), 35, "standard potion keeps legacy balance")
	check_eq(ItemCatalog.healing_amount("POTION_HEALING_GREATER"), 60, "greater potion heals its own amount")
	check_eq(ItemCatalog.nutrition_milli("FOOD_HARDTACK"), 120000, "hardtack has compact nutrition")
	check_eq(ItemCatalog.nutrition_milli("FOOD_DRIED_MEAT"), 200000, "dried meat has medium nutrition")
	check_eq(ItemCatalog.nutrition_milli("FOOD_RATION"), 300000, "ration keeps legacy nutrition")
	check_eq([ItemCatalog.sell_price("MAGIC_STONE_FRAGMENT"),
		ItemCatalog.sell_price("MAGIC_STONE"),ItemCatalog.sell_price("MAGIC_STONE_REFINED")],
		[2,8,30], "magic stone grades have one authoritative sell price")
	check(not ItemCatalog.available_at_depth("ARMOR_PLATE",3), "plate is withheld before depth four")
	check(ItemCatalog.available_at_depth("ARMOR_PLATE",4), "plate unlocks at its authored depth")
	return finish()


func test_recraft_rejection_does_not_mutate_the_live_inventory() -> bool:
	var sim = Simulator.create(7, 7, 90211)
	var hero = sim.world.add_entity("other", "재료 없는 재제작자", Vector2i(3, 3), 20,
		[], "human", "player")
	if hero == null:
		check(false, "recraft rejection fixture hero spawned")
		return finish()
	sim.world.item_state.inventory_rows[hero.id] = Inventory.new([
		Item.new("SWORD_02", "WEAPON_SHORT_SWORD", 1)], {"MAIN_HAND":"SWORD_02"})
	var before:Dictionary = sim.world.inventory_of(hero.id).to_dict()
	var revision:int = sim.world.item_state.revision
	var result := WorldItems.commit_recraft(sim.world, hero.id, "SWORD_02", hero.position)
	check(not bool(result.accepted), "missing material rejects recraft")
	check_eq(result.reason, "recraft_material_insufficient", "recraft reports missing material")
	check_eq(sim.world.inventory_of(hero.id).to_dict(), before,
		"recraft rejection preserves the complete inventory")
	check_eq(sim.world.item_state.revision, revision, "recraft rejection does not bump revision")
	check_eq(sim.world.events.size(), 0, "recraft rejection emits no event")
	return finish()
