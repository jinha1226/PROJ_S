extends "res://tests/test_case.gd"

const Registry=preload("res://sim/item_registry.gd")
const Item=preload("res://sim/item_instance.gd")
const Inventory=preload("res://sim/protagonist_inventory_state.gd")
const Ground=preload("res://sim/ground_item_state.gd")
const Operations=preload("res://sim/item_inventory_operations.gd")
const WeaponRegistry=preload("res://sim/weapon_registry.gd")
const PartyState=preload("res://sim/party_encounter_state.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")


func test_registry_bridges_existing_weapon_authority_without_copying_attack_values()->bool:
	check_eq(Registry.registry_error(),"","item registry validates")
	check_eq(Registry.weapon_definition_id("SHORT_SWORD"),"WEAPON_SHORT_SWORD",
		"legacy short sword bridge")
	var sword=Registry.definition("WEAPON_SHORT_SWORD")
	check(sword!=null and sword.weapon_id=="SHORT_SWORD" and sword.category=="WEAPON" \
			and sword.equip_slots==["MAIN_HAND"],"weapon item references registry authority")
	var keys:Array=sword.to_dict().keys();keys.sort()
	check("base_damage" not in keys and "accuracy_milli" not in keys \
			and "attack_time" not in keys,"item definition does not duplicate attack authority")
	var detached:=Registry.definition_dict("WEAPON_SHORT_SWORD");detached.label="변조"
	check_eq(Registry.definition("WEAPON_SHORT_SWORD").label,"단검",
		"registry definitions are detached immutable values")
	for weapon_id in WeaponRegistry.ids():
		if weapon_id=="UNARMED":continue
		var definition_id:=Registry.weapon_definition_id(weapon_id)
		check(not definition_id.is_empty() \
				and Registry.definition(definition_id).weapon_id==weapon_id,
			"every physical weapon has one item bridge: %s"%weapon_id)
	check(WeaponRegistry.definition("BOW").two_handed \
			and WeaponRegistry.definition("CROSSBOW").two_handed \
			and not WeaponRegistry.definition("SPEAR").two_handed,
		"WeaponRegistry alone owns hand metadata")
	var legacy=Inventory.with_legacy_short_sword()
	check_eq([legacy.equipped.MAIN_HAND,legacy.item("LEGACY_SHORT_SWORD").definition_id],
		["LEGACY_SHORT_SWORD","WEAPON_SHORT_SWORD"],"existing loadout bridge state")
	return finish()


func test_instances_are_canonical_and_rarity_bounds_affixes_at_two()->bool:
	var rare=Item.new("ITEM_003","ACCESSORY_UNSPECIFIED",1,"RARE",["GUARDED","NIMBLE"])
	check_eq(rare.validation_error(),"","rare item accepts two sorted known affixes")
	check_eq(Item.wire_error(rare.to_dict()),"","rare item wire round trip")
	check_eq(Item.from_dict(rare.to_dict()).to_dict(),rare.to_dict(),"deterministic item round trip")
	check_eq(Item.new("ITEM_003","ACCESSORY_UNSPECIFIED",1,"UNCOMMON",
		["GUARDED","NIMBLE"]).validation_error(),"too_many_item_affixes",
		"uncommon cannot carry rare affix count")
	check_eq(Item.new("ITEM_003","ACCESSORY_UNSPECIFIED",1,"RARE",
		["NIMBLE","GUARDED"]).validation_error(),"noncanonical_item_affixes",
		"affixes require deterministic ordering")
	check_eq(Item.new("ITEM_003","ACCESSORY_UNSPECIFIED",1,"RARE",
		["GUARDED","GUARDED"]).validation_error(),"duplicate_item_affix",
		"duplicate affix rejected")
	var wrong_schema:=rare.to_dict();wrong_schema.schema_version=2
	check_eq(Item.wire_error(wrong_schema),"unsupported_item_instance_schema",
		"wrong instance schema rejected")
	check(Item.from_dict(wrong_schema)==null,"from_dict cannot launder instance schema")
	for key in ["instance_id","definition_id","rarity"]:
		var malformed:=rare.to_dict();malformed[key]=7
		check_eq(Item.wire_error(malformed),"invalid_item_instance_string",
			"%s exact String type"%key)
	return finish()


func test_twelve_row_capacity_and_stacking_are_deterministic()->bool:
	var inventory=Inventory.new([Item.new("MAT_01","MATERIAL_UNSPECIFIED",90)])
	var original:=inventory.to_dict()
	var preview:=Operations.preview_add(inventory,Item.new("MAT_02","MATERIAL_UNSPECIFIED",9))
	check(bool(preview.accepted) and preview.preview and preview.inventory.backpack.size()==1,
		"preview exposes one stacked canonical row")
	check_eq(inventory.to_dict(),original,"preview never mutates authority")
	var committed:=Operations.commit_add(inventory,Item.new("MAT_02","MATERIAL_UNSPECIFIED",9))
	check(bool(committed.accepted) and committed.inventory.backpack.size()==1 \
			and committed.inventory.backpack[0].quantity==99,
		"commit fills matching stack before consuming a slot")
	var full_rows:Array=[]
	for index in range(Inventory.BACKPACK_CAPACITY):
		full_rows.append(Item.new("FULL_%02d"%index,"MATERIAL_UNSPECIFIED",99))
	var full=Inventory.new(full_rows);var full_before:=full.to_dict()
	var rejected:=Operations.commit_add(full,Item.new("OVERFLOW","MATERIAL_UNSPECIFIED",1))
	check(not bool(rejected.accepted) and rejected.reason=="inventory_backpack_full",
		"thirteenth non-stackable row rejected")
	check_eq(full.to_dict(),full_before,"overflow failure is atomic")
	return finish()


func test_equipment_slots_two_handed_conflicts_and_defensive_aggregate()->bool:
	var inventory=Inventory.new([
		Item.new("ARMOR","ARMOR_LEATHER"),Item.new("BOW","WEAPON_BOW"),
		Item.new("SHIELD","SHIELD_WOOD"),
		Item.new("TRINKET","ACCESSORY_UNSPECIFIED",1,"RARE",["GUARDED","NIMBLE"])])
	var bow_result:=Operations.commit_equip(inventory,"BOW","MAIN_HAND")
	check(bool(bow_result.accepted),"two-handed bow equips to empty hands")
	var conflict:=Operations.commit_equip(bow_result.inventory,"SHIELD","OFF_HAND")
	check(not bool(conflict.accepted) and conflict.reason=="two_handed_offhand_conflict",
		"offhand is mutually exclusive with bow")
	check_eq(bow_result.inventory.equipped.OFF_HAND,"","failed shield equip is atomic")
	var armor_result:=Operations.commit_equip(bow_result.inventory,"ARMOR","ARMOR")
	var accessory_result:=Operations.commit_equip(armor_result.inventory,"TRINKET","ACCESSORY_1")
	var bonuses:Dictionary=accessory_result.inventory.equipment_bonuses()
	check_eq(bonuses,{"armor_flat":2,"parry_milli":0,"dodge_milli":50,
		"stealth":0,"affix_hook_ids":[]},"defensive-only equipment aggregate")
	check("attack" not in bonuses and "accuracy" not in bonuses \
			and "damage" not in bonuses,"aggregate cannot override weapon/proficiency authority")
	return finish()


func test_equip_replaces_an_occupied_compatible_slot_atomically_and_replays()->bool:
	var inventory=Inventory.new([Item.new("SWORD","WEAPON_SHORT_SWORD"),
		Item.new("AXE","WEAPON_HAND_AXE")],{"MAIN_HAND":"SWORD"})
	var before:Dictionary=inventory.to_dict()
	var swapped:Dictionary=Operations.commit_equip(inventory,"AXE","MAIN_HAND")
	check(bool(swapped.accepted),"weapon replaces the occupied compatible slot")
	check_eq([swapped.inventory.equipped.MAIN_HAND,
		str(swapped.get("replaced_instance_id",""))],
		["AXE","SWORD"],"replacement reports both permanent item identities")
	check_eq(swapped.inventory.unequipped_items().map(func(item):return item.instance_id),
		["SWORD"],"displaced weapon returns to the backpack")
	check_eq(inventory.to_dict(),before,"equipment replacement leaves its input untouched")

	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new()
	check_eq(sandbox.item_preferred_equip_slot(session.protagonist_inventory(),
		["MAIN_HAND"]),"MAIN_HAND",
		"equipment UI chooses a compatible occupied slot when no empty slot exists")
	sandbox.free()
	var start_time:=int(session.sim.world.world_time)
	var result:Dictionary=session.equip_inventory_item("START_HAND_AXE_001","MAIN_HAND")
	check(bool(result.accepted),"session equips a carried weapon over the starter sword")
	var state=session.sim.world.party_encounter
	check_eq([state.protagonist_inventory.equipped.MAIN_HAND,
		state.protagonist_loadout.equipped_weapon_id,
		state.protagonist_inventory.unequipped_items().map(func(item):return item.instance_id).has(
			"LEGACY_MAIN_HAND"),int(session.sim.world.world_time)],
		["START_HAND_AXE_001","HAND_AXE",true,start_time+100],
		"session replacement updates item, combat loadout, backpack, and time together")
	var restored=Session.new(9,9,Session.SOLO_COMBAT_SCENARIO_ID)
	var loaded:Dictionary=restored.load_session_json(session.save_session_json())
	check(bool(loaded.accepted),"replacement equipment journal reloads: %s"%str(loaded))
	if bool(loaded.accepted):check_eq(restored.sim.snapshot(),session.sim.snapshot(),
		"replacement equipment replay is snapshot exact")
	return finish()


func test_pickup_drop_discard_and_pure_consumable_use_are_atomic()->bool:
	var potion=Item.new("POTION_01","POTION_UNSPECIFIED",2)
	var ground=Ground.new([{"position":[4,7],"item":potion}])
	var inventory=Inventory.new()
	var bounds:=Rect2i(Vector2i.ZERO,Vector2i(12,12))
	var picked:=Operations.commit_pickup(inventory,ground,"POTION_01",Vector2i(4,7),bounds)
	check(bool(picked.accepted) and picked.inventory.item("POTION_01")!=null \
			and picked.ground.item("POTION_01")==null,"pickup transfers one canonical instance")
	check(inventory.backpack.is_empty() and ground.item("POTION_01")!=null,
		"pickup leaves both inputs untouched")
	var before_use:Dictionary=picked.inventory.to_dict()
	var used:=Operations.commit_use(picked.inventory,"POTION_01")
	check(bool(used.accepted) and used.use_kind=="HEALING" \
			and used.inventory.item("POTION_01").quantity==1,
		"pure use consumes one unit and delegates the healing effect")
	check_eq(picked.inventory.to_dict(),before_use,"pure use leaves its input untouched")
	var dropped:=Operations.commit_drop(picked.inventory,picked.ground,"POTION_01",
		Vector2i(8,2),bounds)
	check(bool(dropped.accepted) and dropped.inventory.item("POTION_01")==null \
			and dropped.ground.position_of("POTION_01")==Vector2i(8,2),"drop transfer")
	var discarded:=Operations.commit_discard(picked.inventory,"POTION_01")
	check(bool(discarded.accepted) and discarded.inventory.backpack.is_empty(),"discard clone")
	return finish()


func test_malformed_wire_duplicate_overflow_and_equipped_drop_are_rejected()->bool:
	var legacy=Inventory.with_legacy_short_sword();var wire:Dictionary=legacy.to_dict()
	check_eq(Inventory.wire_error(wire),"","inventory wire validates")
	var extra:Dictionary=wire.duplicate(true);extra["forged"]=true
	check_eq(Inventory.wire_error(extra),"invalid_inventory_keys","unknown inventory key")
	var duplicate:Dictionary=wire.duplicate(true);duplicate.backpack.append(
		duplicate.backpack[0].duplicate(true))
	check_eq(Inventory.wire_error(duplicate),"duplicate_inventory_instance","duplicate item ID")
	var reversed:=Inventory.new([Item.new("A","MATERIAL_UNSPECIFIED"),
		Item.new("B","MATERIAL_UNSPECIFIED")]).to_dict();reversed.backpack.reverse()
	check_eq(Inventory.wire_error(reversed),"noncanonical_inventory_order",
		"wire order is canonical")
	var ground=Ground.new()
	var bounds:=Rect2i(Vector2i.ZERO,Vector2i(15,15))
	var locked:=Operations.commit_drop(legacy,ground,"LEGACY_SHORT_SWORD",Vector2i.ONE,bounds)
	check(not bool(locked.accepted) and locked.reason=="equipped_item_locked" \
			and legacy.equipped.MAIN_HAND=="LEGACY_SHORT_SWORD",
		"equipped drop fails without mutation")
	var invalid_drop:=Operations.commit_drop(Inventory.new([
		Item.new("DROP_ME","MATERIAL_UNSPECIFIED")]),Ground.new(),"DROP_ME",
		Vector2i(15,1),bounds)
	check(not bool(invalid_drop.accepted) and invalid_drop.reason=="invalid_item_world_context",
		"drop requires an in-bounds actor context")
	var duplicate_world:=Operations.combined_state_error(Inventory.new([
		Item.new("GLOBAL","MATERIAL_UNSPECIFIED")]),Ground.new([{
		"position":[2,2],"item":Item.new("GLOBAL","MATERIAL_UNSPECIFIED")}]),bounds)
	check_eq(duplicate_world,"duplicate_world_item_instance",
		"inventory and ground share one global instance namespace")
	var bad_inventory:Dictionary=legacy.to_dict();bad_inventory.schema_version=99
	check(Inventory.from_dict(bad_inventory)==null,"inventory clone cannot launder schema")
	var bad_ground:Dictionary=ground.to_dict();bad_ground.schema_version=99
	check(Ground.from_dict(bad_ground)==null,"ground clone cannot launder schema")
	var detached_item=legacy.item("LEGACY_SHORT_SWORD");detached_item.quantity=7
	check_eq(legacy.item("LEGACY_SHORT_SWORD").quantity,1,
		"item lookup returns a detached instance")
	var product=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var wall_position:=Vector2i(-1,-1)
	for y in range(product.sim.world.height):
		for x in range(product.sim.world.width):
			if product.sim.world.tile_at(Vector2i(x,y)).terrain=="wall":
				wall_position=Vector2i(x,y);break
		if wall_position!=Vector2i(-1,-1):break
	product.sim.world.party_encounter.ground_items.rows[0].position=wall_position
	product.sim.world.party_encounter.ground_items._sort_rows()
	check_eq(product.sim.world.world_state_error(),"ground_item_on_impassable_tile",
		"world authority rejects a ground item on impassable terrain")
	return finish()


func test_party_schema8_new_game_items_and_session_operations_replay_exact()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var state=session.sim.world.party_encounter
	check_eq(state.schema_version,PartyState.SCHEMA_VERSION,"party state uses current schema")
	check_eq(state.protagonist_inventory.equipped.MAIN_HAND,"LEGACY_MAIN_HAND",
		"new game equips legacy short sword item bridge")
	check_eq(state.protagonist_inventory.unequipped_items().map(func(item):return item.instance_id),
		["START_BOW_001","START_CROSSBOW_001","START_HAND_AXE_001","START_MACE_001",
		"START_POTION_001","START_SPEAR_001"],
		"new game carries the deterministic weapon sampler and healing potion stack")
	check_eq(state.protagonist_inventory.item("START_POTION_001").quantity,3,
		"new game starts with the three-use healing potion stack")
	check_eq(state.ground_items.rows.size(),2,"product start room has shield and padded armor")
	check_eq(PartyState.wire_error(state.to_dict(),session.sim.world.width,
		session.sim.world.height),"","schema8 party wire validates")
	var observation:Dictionary=session.observe_party_world();var visible_item_ids:Array=[]
	for cell in observation.cells:
		if str(cell.visibility_state)=="VISIBLE":
			for row in cell.get("ground_items",[]):visible_item_ids.append(str(row.instance_id))
	check(not visible_item_ids.is_empty(),"visible ground items enter rich observation")
	var start_time:=int(session.sim.world.world_time)
	var start_events:int=session.sim.world.events.size()
	var start_journal:int=session.command_journal.size()
	var dropped:Dictionary=session.drop_inventory_item("START_POTION_001")
	check(bool(dropped.accepted) and int(session.sim.world.world_time)==start_time+100,
		"drop is canonical and consumes 100 time")
	check_eq(session.command_journal.size(),start_journal+1,"drop appends exactly one journal row")
	var drop_event_count:=0
	for event in session.sim.world.events.slice(start_events):
		if event.type=="item.dropped":drop_event_count+=1
	check_eq(drop_event_count,1,"drop emits exactly one canonical item event")
	var picked:Dictionary=session.pickup_ground_item("START_POTION_001")
	check(bool(picked.accepted) and int(session.sim.world.world_time)==start_time+200,
		"pickup returns the same instance and consumes 100 time")
	var restored=Session.new(9,9,Session.SOLO_COMBAT_SCENARIO_ID)
	var loaded:Dictionary=restored.load_session_json(session.save_session_json())
	check(bool(loaded.accepted),"item journal restores")
	if bool(loaded.accepted):check_eq(restored.sim.snapshot(),session.sim.snapshot(),
		"item journal replay is snapshot exact")
	return finish()


func test_equipped_items_do_not_consume_or_duplicate_backpack_slots()->bool:
	var rows:Array=[Item.new("SWORD","WEAPON_SHORT_SWORD")]
	for index in range(Inventory.BACKPACK_CAPACITY):
		rows.append(Item.new("BAG_%02d"%index,"ACCESSORY_UNSPECIFIED"))
	var inventory=Inventory.new(rows,{"MAIN_HAND":"SWORD"})
	check_eq(inventory.used_backpack_slots(),12,"equipped main hand is outside 12 bag slots")
	check_eq(inventory.validation_error(),"","12 bag rows plus equipped ownership is valid")
	var unequip:=Operations.commit_unequip(inventory,"MAIN_HAND")
	check(not bool(unequip.accepted) and unequip.reason=="inventory_backpack_full",
		"unequip cannot overflow the separated bag")
	var added:=Operations.commit_add(inventory,Item.new("BAG_OVER","ACCESSORY_UNSPECIFIED"))
	check(not bool(added.accepted) and added.reason=="inventory_backpack_full",
		"pickup/add capacity counts only unequipped rows")
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var dto:Dictionary=session.protagonist_inventory()
	check_eq([dto.used_backpack_slots,dto.backpack_rows.size()],[6,6],
		"product DTO shows five spare weapons and the potion, excluding equipped sword")
	check_eq(dto.equipment_slots[0].instance_id,"LEGACY_MAIN_HAND",
		"the same sword instance remains visible in its equipment slot")
	return finish()


func test_party_schema_one_through_seven_migrate_to_exact_item_bridge()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var current:Dictionary=session.sim.world.party_encounter.to_dict()
	for version in range(7,0,-1):
		var row:Dictionary=current.duplicate(true);row.schema_version=version
		if version<PartyState.GROWTH_BUILD_SCHEMA_VERSION:row.erase("protagonist_growth")
		if version<PartyState.OPENING_EVENT_SCHEMA_VERSION:row.erase("opening_event")
		if version<PartyState.RECOVERY_SCHEMA_VERSION:
			row.erase("safe_recovery_turns");row.erase("last_protagonist_damage_step")
		row.erase("protagonist_inventory");row.erase("ground_items")
		if version<7:row.erase("enemy_awareness_rows")
		if version<6:row.erase("diagonal_gateway_positions")
		if version<5:row.erase("protagonist_loadout")
		if version<4:row.erase("protagonist_progression")
		if version<3:row.erase("patrol_reserved_positions")
		if version<2:
			row.erase("active_party_member_ids");row.erase("exile_records")
		var error:=PartyState.wire_error(row,session.sim.world.width,session.sim.world.height)
		check_eq(error,"","legacy schema %d remains valid"%version)
		if error.is_empty():
			var migrated=PartyState.from_dict(row)
			var main=migrated.protagonist_inventory.equipped_item("MAIN_HAND")
			check(migrated.schema_version==PartyState.SCHEMA_VERSION \
					and migrated.ground_items.rows.is_empty() \
					and main!=null and Registry.definition(main.definition_id).weapon_id \
					==migrated.protagonist_loadout.equipped_weapon_id,
				"legacy schema %d gets exact loadout item bridge"%version)
	return finish()


func test_all_equipment_slots_publish_one_detached_combat_modifier_dto()->bool:
	var inventory=Inventory.new([
		Item.new("SWORD","WEAPON_SHORT_SWORD"),Item.new("SHIELD","SHIELD_WOOD"),
		Item.new("ARMOR","ARMOR_LEATHER"),
		Item.new("CHARM_A","ACCESSORY_BRASS_CHARM",1,"RARE",["GUARDED","NIMBLE"]),
		Item.new("CHARM_B","ACCESSORY_BRASS_CHARM")])
	var result:=Operations.commit_equip(inventory,"SWORD","MAIN_HAND")
	result=Operations.commit_equip(result.inventory,"SHIELD","OFF_HAND")
	result=Operations.commit_equip(result.inventory,"ARMOR","ARMOR")
	result=Operations.commit_equip(result.inventory,"CHARM_A","ACCESSORY_1")
	result=Operations.commit_equip(result.inventory,"CHARM_B","ACCESSORY_2")
	check(bool(result.accepted),"main/offhand/armor/two accessories equip through one operation")
	var dto:Dictionary=result.inventory.combat_modifier_dto()
	check_eq(dto.sources.map(func(row):return row.slot),
		["MAIN_HAND","OFF_HAND","ARMOR","ACCESSORY_1","ACCESSORY_2"],
		"modifier sources retain canonical slot order")
	check_eq(dto.totals,{"armor_flat":2,"parry_milli":100,"dodge_milli":100,
		"stealth":0,"affix_hook_ids":[]},"modifier totals freeze every equipped family")
	check_eq(dto.sources[3].bonuses,{"armor_flat":1,"parry_milli":0,
		"dodge_milli":75,"stealth":0},
		"source bonuses include the exact equipped item contribution")
	var detached:Dictionary=dto.duplicate(true)
	detached.totals.armor_flat=999;detached.sources[3].bonuses.dodge_milli=999
	var fresh:Dictionary=result.inventory.combat_modifier_dto()
	check_eq([fresh.totals.armor_flat,fresh.sources[3].bonuses.dodge_milli],[2,75],
		"combat modifier DTO cannot alias inventory or registry authority")
	return finish()


func test_healing_potion_session_use_is_timed_consumed_logged_and_replay_exact()->bool:
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var state=session.sim.world.party_encounter
	var hero_id:=int(state.protagonist_id)
	check(session.commit_exploration(Command.wait(hero_id)).accepted \
		and session.enter_solo_combat().accepted,"potion fixture enters canonical combat")
	for _turn in range(12):
		if int(session.sim.world.entities[hero_id].health) \
				<int(session.sim.world.entities[hero_id].max_health):break
		if not session.commit_direct_solo_action(hero_id,"HOLD").accepted:break
	var hero=session.sim.world.entities[hero_id]
	check(int(hero.health)<int(hero.max_health),"canonical enemy damage makes potion usable")
	var start_health:=int(hero.health);var start_time:=int(session.sim.world.world_time)
	var used:Dictionary=session.use_inventory_item("START_POTION_001")
	check(bool(used.accepted) and int(used.healed_amount)>0 \
			and int(used.healed_amount)<=Registry.HEALING_POTION_RESTORE \
			and int(session.sim.world.entities[hero_id].health)>start_health,
		"session applies one clamped registry healing effect after hostile time")
	check_eq(session.sim.world.world_time,start_time+100,"potion use consumes one canonical turn")
	check_eq(state.protagonist_inventory.item("START_POTION_001").quantity,2,
		"one potion leaves the remaining stack in the same instance")
	var event_types:Array=[]
	for event in session.sim.world.events:event_types.append(str(event.type))
	check("item.used" in event_types and "health.restored" in event_types,
		"potion use emits item and healing provenance")
	var equipment:Dictionary=session.protagonist_equipment()
	check(equipment.get("combat_modifiers",{})==state.protagonist_inventory.combat_modifier_dto(),
		"canonical equipment facade carries the detached combat modifier handoff")
	var restored=Session.new(9,9,Session.SOLO_COMBAT_SCENARIO_ID)
	var loaded:Dictionary=restored.load_session_json(session.save_session_json())
	check(bool(loaded.accepted),"potion journal reloads")
	if bool(loaded.accepted):check_eq(restored.sim.snapshot(),session.sim.snapshot(),
		"potion use and healing replay exactly")
	return finish()


func test_failed_session_item_operation_is_atomic_and_combat_item_action_advances_time()->bool:
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var before:=session.save_session_json();var rejected:=session.drop_inventory_item("LEGACY_MAIN_HAND")
	check(not bool(rejected.accepted) and rejected.reason=="equipped_item_locked",
		"invalid equipped drop rejects")
	check_eq(session.save_session_json(),before,"failed session item action changes nothing")
	var hero_id:=int(session.sim.world.party_encounter.protagonist_id)
	check(session.commit_exploration(Command.wait(hero_id)).accepted,
		"fixture reaches silent contact boundary")
	check_eq(session.party_status().safe_phase,"CONTACT","fixture exposes internal contact")
	var contact_time:=int(session.sim.world.world_time)
	var contact_drop:Dictionary=session.drop_inventory_item("START_POTION_001")
	check(bool(contact_drop.accepted) and int(session.sim.world.world_time)==contact_time+100,
		"internal contact does not reject a 100-time item action: %s"%contact_drop)
	var contact_pickup:Dictionary=session.pickup_ground_item("START_POTION_001")
	check(contact_pickup.accepted,"contact floor item can be picked up again: %s"%contact_pickup)
	var hostile_ready:bool=session.party_status().safe_phase=="ENGAGED"
	check(hostile_ready,"contact item action silently prepares hostile time flow")
	if hostile_ready:
		var start_time:=int(session.sim.world.world_time)
		var combat_drop:Dictionary=session.drop_inventory_item("START_POTION_001")
		check(bool(combat_drop.accepted) and int(session.sim.world.world_time)==start_time+100,
			"item action remains available and advances enemy time in hostile state: %s"%combat_drop)
		var replay=Session.new(1,2,Session.SOLO_FIXTURE_SCENARIO_ID)
		var replayed:Dictionary=replay.load_session_json(session.save_session_json())
		check(bool(replayed.accepted),"contact/hostile item journal replays")
		if bool(replayed.accepted):check_eq(replay.sim.snapshot(),session.sim.snapshot(),
			"silent hostile item time flow is replay exact")
	return finish()
