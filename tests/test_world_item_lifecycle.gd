extends "res://tests/test_case.gd"

const Simulator=preload("res://sim/simulator.gd")
const WorldState=preload("res://sim/world_state.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const AmmoPool=preload("res://sim/ammo_pool_state.gd")
const ItemScript=preload("res://sim/item_instance.gd")
const WorldItemOperations=preload("res://sim/world_item_operations.gd")
const PartyState=preload("res://sim/party_encounter_state.gd")


func test_every_added_entity_owns_an_empty_twelve_slot_inventory_and_ammo_row()->bool:
	var sim=Simulator.create(8,8,31)
	var hero=sim.world.add_entity("hero","가방 계약",Vector2i(1,1),100)
	check(hero!=null,"fixture hero exists")
	var inventory=sim.world.item_state.inventory(hero.id)
	var ammo=sim.world.item_state.ammo_pool(hero.id)
	check(inventory!=null and ammo!=null,"add_entity creates both item rows")
	if inventory==null or ammo==null:return finish()
	check_eq([inventory.backpack.size(),inventory.used_backpack_slots(),
		Inventory.BACKPACK_CAPACITY],[0,0,12],"new entity starts with an empty 12 slot bag")
	check_eq([ammo.amount("ARROW"),ammo.amount("BOLT")],[0,0],"new entity starts with no ammo")
	var lab=Simulator.create(8,8,31)
	var actor=lab.world.add_lab_actor("MELEE_THREAT",0,Vector2i(2,2),"실험 배우","human")
	check(actor!=null,"lab actor exists")
	check(lab.world.item_state.inventory(actor.id)!=null \
		and lab.world.item_state.ammo_pool(actor.id)!=null,
		"add_lab_actor inherits the same inventory contract through add_entity")
	check_eq(lab.world.world_state_error(),"","lab world with item rows validates")
	return finish()


func test_rejected_add_entity_leaves_no_partial_entity_or_item_state()->bool:
	var sim=Simulator.create(6,6,7)
	var hero=sim.world.add_entity("hero","선점",Vector2i(2,2),100)
	check(hero!=null,"blocking entity exists")
	var before:={"entities":sim.world.entities.size(),
		"combatants":sim.world.combatant_states.size(),
		"inventories":sim.world.item_state.inventory_rows.size(),
		"ammo":sim.world.item_state.ammo_pool_rows.size(),
		"next_entity_id":sim.world._next_entity_id}
	check(sim.world.add_entity("goblin","겹침",Vector2i(2,2),100)==null,
		"occupied tile rejects the spawn")
	check(sim.world.add_entity("goblin","체력 없음",Vector2i(3,3),0)==null,
		"invalid max health rejects the spawn")
	check_eq({"entities":sim.world.entities.size(),
		"combatants":sim.world.combatant_states.size(),
		"inventories":sim.world.item_state.inventory_rows.size(),
		"ammo":sim.world.item_state.ammo_pool_rows.size(),
		"next_entity_id":sim.world._next_entity_id},before,
		"rejected spawns leave entity, combatant and item rows untouched")
	# A pre-existing row for the next id must fail before any of the four rows is
	# written, otherwise add_entity could half-adopt a foreign inventory.
	sim.world.item_state.inventory_rows[sim.world._next_entity_id]=Inventory.new()
	check(sim.world.add_entity("goblin","중복 행",Vector2i(4,4),100)==null,
		"an already occupied inventory row rejects the spawn")
	check_eq([sim.world.entities.size(),sim.world.combatant_states.size(),
		sim.world.item_state.ammo_pool_rows.size()],
		[before.entities,before.combatants,before.ammo],
		"the rejected duplicate row spawn creates no entity, combatant or ammo row")
	return finish()


func test_world_state_error_reports_item_row_membership_and_content()->bool:
	var sim=Simulator.create(6,6,7)
	var hero=sim.world.add_entity("hero","불변식",Vector2i(2,2),100)
	check_eq(sim.world.world_state_error(),"","baseline item state validates")
	sim.world.item_state.inventory_rows.erase(hero.id)
	check_eq(sim.world.world_state_error(),"inventory_row_entity_mismatch",
		"a missing inventory row is a world invariant failure")
	check(sim.world.snapshot()==null,"an invalid item membership cannot be saved")
	sim.world.item_state.inventory_rows[hero.id]=Inventory.new()
	sim.world.item_state.ammo_pool_rows.erase(hero.id)
	check_eq(sim.world.world_state_error(),"ammo_pool_row_entity_mismatch",
		"a missing ammo row is a world invariant failure")
	sim.world.item_state.ammo_pool_rows[hero.id]=AmmoPool.new()
	sim.world.item_state.processed_drop_death_event_ids.append(99)
	check_eq(sim.world.world_state_error(),"unknown_processed_death_event",
		"processed death ids must reference real death events")
	sim.world.item_state.processed_drop_death_event_ids.clear()
	sim.world.item_state.revision=-1
	check_eq(sim.world.world_state_error(),"invalid_world_item_scalar",
		"world validation chains the item state's own validator once")
	return finish()


func test_snapshot_v10_round_trips_item_and_body_state_and_rejects_v9_in_header()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var snapshot:Dictionary=session.sim.snapshot()
	check_eq(int(snapshot.snapshot_version),11,"world snapshot is v11")
	var top_keys:Array=snapshot.keys();top_keys.sort()
	check(top_keys.has("item_state") and top_keys.has("body_states"),
		"item and body authority are in the exact v11 top level key set")
	check(not snapshot.party_encounter.has("protagonist_inventory") \
		and not snapshot.party_encounter.has("ground_items"),
		"party state no longer duplicates inventory or ground authority")
	var restored=Simulator.from_snapshot(snapshot)
	check(restored!=null,"v10 snapshot restores")
	if restored!=null:
		check_eq(restored.snapshot(),snapshot,"v10 save and restore is exact")
	var legacy:Dictionary=snapshot.duplicate(true)
	legacy.snapshot_version=9
	check_eq(WorldState.snapshot_restore_error(legacy),"unsupported_snapshot_version",
		"v9 world snapshots are refused in the header")
	check(Simulator.from_snapshot(legacy)==null,"a v9 snapshot builds no object")
	var missing:Dictionary=snapshot.duplicate(true)
	missing.erase("item_state")
	check_eq(WorldState.snapshot_restore_error(missing),"invalid_snapshot_top_level_keys",
		"a v10 snapshot without item_state is rejected")
	var json_round_trip:Variant=JSON.parse_string(JSON.stringify(snapshot))
	check(json_round_trip is Dictionary,"v10 snapshot encodes as JSON")
	check_eq(WorldState.snapshot_restore_error(json_round_trip),"",
		"the v10 item state survives the JSON integer transport like every other row")
	var orphan:Dictionary=snapshot.duplicate(true)
	orphan.item_state.inventory_rows.pop_back()
	check(WorldState.snapshot_restore_error(orphan)!="",
		"an inventory row set that differs from the combatant set is rejected")
	return finish()


func test_rollback_memento_restores_item_state_and_revision_exactly()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var world=session.sim.world
	var hero_id:int=world.party_encounter.protagonist_id
	world.item_state.revision=41
	var before:Dictionary=session.sim.snapshot()
	var memento:Variant=session.sim.capture_rollback_memento()
	check(memento is Dictionary,"settled world captures a memento")
	if not memento is Dictionary:return finish()
	world.item_state.revision=999
	world.item_state.inventory_rows[hero_id].backpack.clear()
	world.item_state.inventory_rows[hero_id].equipped.MAIN_HAND=""
	world.item_state.ammo_pool_rows[hero_id]=AmmoPool.new(1,2)
	world.item_state.ground_items.rows.clear()
	world.item_state.next_item_instance_id=777
	check(session.sim.restore_rollback_memento(memento),"item state memento restores")
	check_eq(session.sim.snapshot(),before,
		"inventory, ammo, ground, allocator and revision restore exactly")
	check_eq(session.sim.world.item_state.revision,41,"item revision restores exactly")
	return finish()


func test_rollback_memento_captures_only_non_empty_item_rows()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var world=session.sim.world
	var memento:Variant=session.sim.capture_rollback_memento()
	check(memento is Dictionary,"product world captures a memento")
	if not memento is Dictionary:return finish()
	check(world.combatant_states.size()>=4,
		"product dungeon fixture holds a multi-entity roster for the sparse-row guard")
	var owners:=0
	for entity_id in world.item_state.inventory_rows:
		if not world.item_state.inventory_rows[entity_id].backpack.is_empty():owners+=1
	for entity_id in world.item_state.ammo_pool_rows:
		var ammo=world.item_state.ammo_pool_rows[entity_id]
		if ammo.amount("ARROW")>0 or ammo.amount("BOLT")>0:owners+=1
	check_eq([memento.item_inventory_rows.size()+memento.item_ammo_rows.size(),owners],
		[owners,owners],"memento serializes only the rows that actually hold something")
	check(memento.item_inventory_rows.size()<world.combatant_states.size(),
		"memento never serializes one inventory row per entity")
	# Empty rows must stay cheap. Calibrate against the full serialization this
	# guard exists to keep out, so no magic microsecond constant can rot.
	var roster=Simulator.create(20,20,5)
	for index in range(40):roster.world.add_entity("goblin","다수%d"%index,
		Vector2i(index%20,index/20),50)
	roster.world._rollback_item_rows();_full_item_row_serialization(roster.world)
	var sparse_samples:Array[int]=[];var full_samples:Array[int]=[]
	for _sample in range(7):
		var started:=Time.get_ticks_usec()
		roster.world._rollback_item_rows()
		sparse_samples.append(Time.get_ticks_usec()-started)
		started=Time.get_ticks_usec()
		_full_item_row_serialization(roster.world)
		full_samples.append(Time.get_ticks_usec()-started)
	sparse_samples.sort();full_samples.sort()
	print("PERF item memento rows sparse_us=%d full_scan_us=%d"%[sparse_samples[3],
		full_samples[3]])
	check(sparse_samples[3]*3<full_samples[3],
		"capturing 40 empty rows must stay far below serializing all 40")
	return finish()


func _full_item_row_serialization(world)->Array:
	# The regression this guards against: writing every entity's item rows into the
	# memento on every hop.
	var rows:Array=[]
	var entity_ids:Array=world.item_state.inventory_rows.keys();entity_ids.sort()
	for entity_id in entity_ids:
		rows.append([int(entity_id),world.item_state.inventory_rows[entity_id].to_dict()])
	var ammo_ids:Array=world.item_state.ammo_pool_rows.keys();ammo_ids.sort()
	for entity_id in ammo_ids:
		rows.append([int(entity_id),world.item_state.ammo_pool_rows[entity_id].to_dict()])
	return rows


func test_protagonist_start_loadout_moved_into_world_item_state_unchanged()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var world=session.sim.world
	var hero_id:int=world.party_encounter.protagonist_id
	var inventory=world.item_state.inventory(hero_id)
	check(inventory!=null,"the protagonist owns a world inventory row")
	if inventory==null:return finish()
	check_eq(inventory.equipped.MAIN_HAND,"LEGACY_MAIN_HAND",
		"the same starting main hand instance stays equipped")
	check_eq(inventory.unequipped_items().map(func(item):return item.instance_id),
		["START_BOW_001","START_CROSSBOW_001","START_HAND_AXE_001","START_MACE_001",
		"START_POTION_001","START_SPEAR_001"],
		"the same starting backpack instances move over unchanged")
	check_eq(int(inventory.item("START_POTION_001").quantity),3,
		"the healing potion stack keeps its quantity")
	var ammo=world.item_state.ammo_pool(hero_id)
	check_eq([ammo.amount("ARROW"),ammo.amount("BOLT")],[12,6],
		"the starting ammo counts move into the world ammo row")
	var runtime=world.item_state.weapon_runtime("START_CROSSBOW_001")
	check(runtime!=null and not runtime.loaded,
		"the starting crossbow instance owns exactly one unloaded runtime row")
	var ground_ids:Array=[]
	for row in world.item_state.ground_items.rows:ground_ids.append(str(row.item.instance_id))
	ground_ids.sort()
	check_eq(ground_ids,["GROUND_START_PADDED","GROUND_START_SHIELD"],
		"the product start room ground items move over with the same instance ids")
	var dto:Dictionary=session.protagonist_inventory()
	check_eq(int(dto.used_backpack_slots),6,"the protagonist UI still reports the same bag")
	check_eq(WorldItemOperations.equipped_weapon_id(world,hero_id),"SHORT_SWORD",
		"the equipped MAIN_HAND instance is the combat weapon authority")
	return finish()


func test_the_duplicate_weapon_authority_and_its_bridge_invariant_are_gone()->bool:
	# A2 held protagonist_loadout and the equipped MAIN_HAND instance together with
	# inventory_loadout_bridge_mismatch. A3 deletes the duplicate field, so the
	# bridge has nothing left to hold and goes with it.
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var world=session.sim.world
	var hero_id:int=world.party_encounter.protagonist_id
	check_eq(world.world_state_error(),"","the starting world validates")
	var party_names:Array=[]
	for property in world.party_encounter.get_property_list():
		party_names.append(str(property.name))
	check("protagonist_loadout" not in party_names,
		"the party state no longer stores a second weapon authority")
	var world_names:Array=[]
	for method in world.get_method_list():world_names.append(str(method.name))
	check("_inventory_loadout_bridge_error" not in world_names,
		"the bridge invariant is deleted with the field it held together")
	check_eq(int(world.party_encounter.schema_version),PartyState.SCHEMA_VERSION,
		"the party uses the current persisted schema")
	check("protagonist_loadout" not in world.party_encounter.to_dict(),
		"the party wire no longer carries a loadout row")
	# Changing the equipped instance changes the weapon with nothing to disagree.
	check(session.unequip_inventory_slot("MAIN_HAND").accepted,"the sword unequips")
	check_eq(WorldItemOperations.equipped_weapon_id(world,hero_id),"UNARMED_STRIKE",
		"an empty main hand reads as unarmed")
	check_eq(world.world_state_error(),"","an unarmed protagonist is a valid world")
	check_eq(world.runtime_step_postcondition_error(world.events.size()),"",
		"the incremental step postcondition also has no bridge left to check")
	return finish()
