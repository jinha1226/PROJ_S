extends "res://tests/test_case.gd"

const Simulator=preload("res://sim/simulator.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Ops=preload("res://sim/world_item_operations.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Ammo=preload("res://sim/ammo_pool_state.gd")
const Runtime=preload("res://sim/weapon_runtime_state.gd")
const Ground=preload("res://sim/ground_item_state.gd")
const Item=preload("res://sim/item_instance.gd")

const SWORD_ID:="ITEM_00000000000000000001"
const ARMOR_ID:="ITEM_00000000000000000007"
const POTION_ID:="ITEM_00000000000000000012"
const CROSSBOW_ID:="ITEM_00000000000000000031"
const HERO_POSITION:=Vector2i(3,3)


func _fixture()->Dictionary:
	var sim=Simulator.create(12,12,17)
	var hero=sim.world.add_entity("hero","가방 주인",HERO_POSITION,100)
	var mate=sim.world.add_entity("hero","동료",Vector2i(4,3),100)
	var state=sim.world.item_state
	state.next_item_instance_id=64
	state.inventory_rows[hero.id]=Inventory.new([
		Item.new(SWORD_ID,"WEAPON_SHORT_SWORD"),
		Item.new(CROSSBOW_ID,"WEAPON_CROSSBOW"),
		Item.new(POTION_ID,"POTION_HEALING",3)],{"MAIN_HAND":SWORD_ID})
	state.ammo_pool_rows[hero.id]=Ammo.new(12,6)
	state.weapon_runtime_rows[CROSSBOW_ID]=Runtime.new(CROSSBOW_ID,false)
	state.ground_items=Ground.new([{"position":[HERO_POSITION.x,HERO_POSITION.y],
		"item":Item.new(ARMOR_ID,"ARMOR_LEATHER").to_dict()}])
	return {"sim":sim,"hero":int(hero.id),"mate":int(mate.id)}


func test_species_natural_weapon_and_atomic_item_requirements_are_authoritative()->bool:
	var sim=Simulator.create(12,12,91)
	var human=sim.world.add_entity("hero","인간",Vector2i(2,2),120,[],"human")
	var beastkin=sim.world.add_entity("hero","수인",Vector2i(3,2),120,[],"beastkin")
	var elf=sim.world.add_entity("hero","엘프",Vector2i(4,2),120,[],"elf")
	check_eq([Ops.equipped_weapon_id(sim.world,human.id),
		Ops.equipped_weapon_id(sim.world,beastkin.id)],
		["UNARMED_STRIKE","NATURAL_CLAW"],"empty hand resolves exactly one species weapon")
	check_eq([sim.world.inventory_of(human.id).backpack.size(),
		sim.world.inventory_of(beastkin.id).backpack.size()],[0,0],
		"natural weapons require no inventory instance")
	var axe_id:="ITEM_00000000000000000501"
	sim.world.item_state.next_item_instance_id=503
	sim.world.item_state.inventory_rows[elf.id]=Inventory.new([
		Item.new(axe_id,"WEAPON_HAND_AXE")])
	var before:Dictionary=sim.world.item_state.to_dict()
	var rejected:=Ops.commit_equip(sim.world,elf.id,axe_id,"MAIN_HAND",elf.position,0)
	check(not bool(rejected.accepted) and rejected.reason=="item_requirements_not_met",
		"underqualified equip has a stable rejection")
	check_eq(sim.world.item_state.to_dict(),before,"requirement rejection is an atomic no-op")
	# An elf is qualified for the starter sword (DEX 6) but not the STR 5 axe.
	var sword_id:="ITEM_00000000000000000502"
	sim.world.item_state.inventory_rows[elf.id]=Inventory.new([
		Item.new(axe_id,"WEAPON_HAND_AXE"),Item.new(sword_id,"WEAPON_SHORT_SWORD")])
	check(bool(Ops.commit_equip(sim.world,elf.id,sword_id,"MAIN_HAND",elf.position,0).accepted),
		"qualified equip succeeds")
	# Forging the underqualified axe into the slot is rejected by world validation.
	sim.world.item_state.inventory_rows[elf.id].equipped.MAIN_HAND=axe_id
	check_eq(sim.world.world_state_error(),"item_requirements_not_met",
		"snapshot/world validation rejects forged equipment")
	return finish()


func test_every_accepted_transaction_raises_the_item_revision_by_exactly_one()->bool:
	var fixture:=_fixture()
	var world=fixture.sim.world
	var hero:int=fixture.hero
	var mate:int=fixture.mate
	check_eq(world.world_state_error(),"","operation fixture world validates")
	var revision:int=world.item_state.revision
	var event_count:int=world.events.size()
	var accepted:Array=[]
	accepted.append(Ops.commit_pickup(world,hero,ARMOR_ID,HERO_POSITION,50))
	check_eq(world.item_state.revision,revision+1,"pickup raises the revision by one")
	accepted.append(Ops.commit_equip(world,hero,ARMOR_ID,"ARMOR",HERO_POSITION,50))
	check_eq(world.item_state.revision,revision+2,"equip raises the revision by one")
	accepted.append(Ops.commit_unequip(world,hero,"ARMOR",HERO_POSITION,50))
	check_eq(world.item_state.revision,revision+3,"unequip raises the revision by one")
	accepted.append(Ops.commit_drop(world,hero,ARMOR_ID,HERO_POSITION,50))
	check_eq(world.item_state.revision,revision+4,"drop raises the revision by one")
	accepted.append(Ops.commit_transfer(world,hero,mate,POTION_ID,HERO_POSITION,50))
	check_eq(world.item_state.revision,revision+5,"transfer raises the revision by one")
	accepted.append(Ops.commit_use(world,mate,POTION_ID,Vector2i(4,3),50))
	check_eq(world.item_state.revision,revision+6,"use raises the revision by one")
	for result in accepted:
		check(bool(result.get("accepted",false)),"accepted transaction: %s"%result)
	check_eq(world.events.size(),event_count+6,
		"each accepted transaction writes exactly one item event")
	check_eq(world.world_state_error(),"","the world stays valid after every transaction")
	check_eq(world.inventory_of(mate).item(POTION_ID).quantity,2,
		"the transferred potion stack lands on the new owner and loses one unit")
	check(world.inventory_of(hero).item(POTION_ID)==null,
		"the transferred instance leaves the source bag")
	return finish()


func test_pickup_and_transfer_preserve_stack_identity_without_implicit_merge()->bool:
	var fixture:=_fixture()
	var world=fixture.sim.world
	var hero:int=fixture.hero
	var mate:int=fixture.mate
	const MATE_POTION_ID:="ITEM_00000000000000000041"
	const GROUND_POTION_ID:="ITEM_00000000000000000042"
	world.item_state.inventory_rows[mate]=Inventory.new([
		Item.new(MATE_POTION_ID,"POTION_HEALING",2)])
	world.item_state.ground_items=Ground.new([
		{"position":[4,3],"item":Item.new(
			GROUND_POTION_ID,"POTION_HEALING",1).to_dict()}])
	var transfer:=Ops.commit_transfer(world,hero,mate,POTION_ID,HERO_POSITION,50)
	check(bool(transfer.get("accepted",false)),"matching destination stack accepts transfer")
	check(world.inventory_of(hero).item(POTION_ID)==null,
		"the exact source stack leaves its former owner")
	check_eq([world.inventory_of(mate).item(POTION_ID).quantity,
		world.inventory_of(mate).item(MATE_POTION_ID).quantity],[3,2],
		"transfer keeps both stack ids and quantities instead of merging them")
	var pickup:=Ops.commit_pickup(world,mate,GROUND_POTION_ID,Vector2i(4,3),50)
	check(bool(pickup.get("accepted",false)),"matching carried stacks do not block pickup")
	check_eq([world.inventory_of(mate).item(GROUND_POTION_ID).quantity,
		world.inventory_of(mate).item(POTION_ID).quantity,
		world.inventory_of(mate).item(MATE_POTION_ID).quantity],[1,3,2],
		"pickup preserves the ground instance beside both matching stacks")
	check(world.ground_item(GROUND_POTION_ID)==null,
		"the preserved pickup instance has exactly one world owner")
	check_eq(world.world_state_error(),"","identity-preserving movement keeps world invariants")
	return finish()


func test_identity_preserving_transfer_rejects_a_full_destination_atomically()->bool:
	var fixture:=_fixture()
	var world=fixture.sim.world
	var hero:int=fixture.hero
	var mate:int=fixture.mate
	var full_rows:Array=[]
	for index in range(Inventory.BACKPACK_CAPACITY):
		full_rows.append(Item.new("FULL_POTION_%02d"%index,
			"POTION_HEALING",1))
	world.item_state.inventory_rows[mate]=Inventory.new(full_rows)
	var before:Dictionary=fixture.sim.snapshot()
	var revision:int=world.item_state.revision
	var event_count:int=world.events.size()
	var rejected:=Ops.commit_transfer(world,hero,mate,POTION_ID,HERO_POSITION,50)
	check(not bool(rejected.get("accepted",true)) \
		and str(rejected.get("reason",""))=="inventory_backpack_full",
		"a merge-compatible full bag still rejects an identity-preserving move")
	check_eq([world.item_state.revision,world.events.size()],[revision,event_count],
		"rejected transfer changes neither revision nor event history")
	check_eq(fixture.sim.snapshot(),before,
		"rejected transfer preserves source, destination and equipment byte-exactly")
	return finish()


func test_rejected_preview_and_commit_change_nothing_at_all()->bool:
	var fixture:=_fixture()
	var world=fixture.sim.world
	var hero:int=fixture.hero
	var mate:int=fixture.mate
	var before:Dictionary=fixture.sim.snapshot()
	var revision:int=world.item_state.revision
	var event_count:int=world.events.size()
	var rejections:Array=[
		Ops.preview_pickup(world,hero,"ITEM_00000000000000000099",HERO_POSITION),
		Ops.commit_pickup(world,hero,"ITEM_00000000000000000099",HERO_POSITION,50),
		Ops.commit_pickup(world,mate,ARMOR_ID,Vector2i(4,3),50),
		Ops.preview_drop(world,hero,SWORD_ID,HERO_POSITION),
		Ops.commit_drop(world,hero,SWORD_ID,HERO_POSITION,50),
		Ops.commit_equip(world,hero,POTION_ID,"ARMOR",HERO_POSITION,50),
		Ops.commit_unequip(world,hero,"OFF_HAND",HERO_POSITION,50),
		Ops.commit_transfer(world,hero,9999,POTION_ID,HERO_POSITION,50),
		Ops.commit_transfer(world,hero,hero,POTION_ID,HERO_POSITION,50),
		Ops.commit_use(world,hero,SWORD_ID,HERO_POSITION,50),
		Ops.commit_reload(world,hero),
	]
	for result in rejections:
		check(not bool(result.get("accepted",true)),"rejected transaction: %s"%result)
		check(not str(result.get("reason","")).is_empty(),"rejection names a reason")
	check_eq(world.item_state.revision,revision,
		"a rejected preview or commit never moves the revision")
	check_eq(world.events.size(),event_count,"a rejected transaction writes no event")
	check_eq(fixture.sim.snapshot(),before,
		"a rejected transaction leaves the whole world byte identical")
	return finish()


func test_read_facade_hands_out_detached_state_only()->bool:
	var fixture:=_fixture()
	var world=fixture.sim.world
	var hero:int=fixture.hero
	var names:Array=[]
	for method in world.get_method_list():names.append(str(method.name))
	check("inventory_row" not in names and "ammo_pool_row" not in names \
		and "set_inventory_row" not in names,
		"the A2 live-row accessors are gone from the public world surface")
	var inventory=world.inventory_of(hero)
	inventory.backpack.clear();inventory.equipped.MAIN_HAND=""
	check_eq(world.inventory_of(hero).backpack.size(),3,
		"mutating a returned inventory cannot reach the canonical row")
	check_eq(str(world.inventory_of(hero).equipped.MAIN_HAND),SWORD_ID,
		"mutating a returned equipment table cannot reach the canonical row")
	var equipped=world.equipped_item(hero,"MAIN_HAND")
	check_eq(str(equipped.instance_id),SWORD_ID,"the main hand item reads back by slot")
	equipped.quantity=99
	check_eq(int(world.equipped_item(hero,"MAIN_HAND").quantity),1,
		"mutating a returned item cannot reach the canonical row")
	check(world.equipped_item(hero,"ARMOR")==null,"an empty slot reads as null")
	var modifiers:Dictionary=world.equipment_modifiers(hero)
	modifiers.totals.armor_flat=999
	check_eq(int(world.equipment_modifiers(hero).totals.armor_flat),0,
		"mutating a returned modifier DTO cannot reach the canonical row")
	var ground=world.ground_item(ARMOR_ID)
	check_eq(str(ground.definition_id),"ARMOR_LEATHER","a ground instance reads back by id")
	ground.quantity=42
	check_eq(int(world.ground_item(ARMOR_ID).quantity),1,
		"mutating a returned ground item cannot reach the canonical row")
	check(world.ground_item(SWORD_ID)==null,"a carried instance is not a ground item")
	check_eq(world.item_owner(SWORD_ID),{"kind":"ENTITY","entity_id":hero,
		"slot":"MAIN_HAND","position":[HERO_POSITION.x,HERO_POSITION.y]},
		"an equipped instance reports its owner and slot")
	check_eq(world.item_owner(POTION_ID),{"kind":"ENTITY","entity_id":hero,
		"slot":"","position":[HERO_POSITION.x,HERO_POSITION.y]},
		"a backpack instance reports its owner without a slot")
	check_eq(world.item_owner(ARMOR_ID),{"kind":"GROUND","entity_id":-1,
		"slot":"","position":[HERO_POSITION.x,HERO_POSITION.y]},
		"a ground instance reports its position")
	check_eq(world.item_owner("ITEM_00000000000000000099"),{"kind":"NONE",
		"entity_id":-1,"slot":"","position":[-1,-1]},"an unknown instance has no owner")
	return finish()


func test_a_loaded_crossbow_keeps_its_load_while_the_instance_moves()->bool:
	var fixture:=_fixture()
	var world=fixture.sim.world
	var hero:int=fixture.hero
	var mate:int=fixture.mate
	check(Ops.commit_unequip(world,hero,"MAIN_HAND",HERO_POSITION,50).accepted,
		"the starting sword unequips")
	check(Ops.commit_equip(world,hero,CROSSBOW_ID,"MAIN_HAND",HERO_POSITION,50).accepted,
		"the crossbow equips")
	check_eq(Ops.attack_error(world,hero),"reload_required",
		"an unloaded crossbow blocks the attack through the world authority")
	check(Ops.commit_reload(world,hero).accepted,"the crossbow reloads")
	check(world.item_state.weapon_runtime(CROSSBOW_ID).loaded,"the instance row holds the load")
	check_eq(Ops.attack_error(world,hero),"","a loaded crossbow may attack")
	check(Ops.commit_unequip(world,hero,"MAIN_HAND",HERO_POSITION,50).accepted,
		"the loaded crossbow unequips")
	check(Ops.commit_drop(world,hero,CROSSBOW_ID,HERO_POSITION,50).accepted,
		"the loaded crossbow drops")
	check(world.item_state.weapon_runtime(CROSSBOW_ID).loaded,
		"a dropped crossbow keeps its load")
	check(Ops.commit_pickup(world,hero,CROSSBOW_ID,HERO_POSITION,50).accepted,
		"the loaded crossbow is picked back up")
	check(Ops.commit_transfer(world,hero,mate,CROSSBOW_ID,HERO_POSITION,50).accepted,
		"the loaded crossbow transfers to another entity")
	check(world.item_state.weapon_runtime(CROSSBOW_ID).loaded,
		"the reload state follows the instance to a new owner")
	check_eq(world.world_state_error(),"","every move keeps the runtime row invariant")
	var round_trip=Simulator.from_snapshot(fixture.sim.snapshot())
	check(round_trip!=null and round_trip.world.item_state.weapon_runtime(CROSSBOW_ID).loaded,
		"the load survives a snapshot round trip")
	check(Ops.commit_discard(world,mate,CROSSBOW_ID,Vector2i(4,3),50).accepted,
		"the crossbow is destroyed")
	check(world.item_state.weapon_runtime(CROSSBOW_ID)==null,
		"destroying the instance removes its runtime row")
	check_eq(world.world_state_error(),"","a destroyed weapon leaves no orphan runtime row")
	return finish()


func test_protagonist_weapon_authority_is_the_equipped_main_hand_item()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	check(session.sim!=null,"solo session initializes")
	if session.sim==null:return finish()
	var world=session.sim.world
	var names:Array=[]
	for property in world.party_encounter.get_property_list():names.append(str(property.name))
	check("protagonist_loadout" not in names,
		"the duplicate weapon authority is gone from the party state")
	check("protagonist_loadout" not in world.party_encounter.to_dict(),
		"the party wire no longer carries a loadout row")
	var equipment:Dictionary=session.protagonist_equipment()
	check_eq([str(equipment.weapon_id),int(equipment.arrows),int(equipment.bolts)],
		["SHORT_SWORD",12,6],"the world rows reproduce the starting weapon and ammo")
	check(session.unequip_inventory_slot("MAIN_HAND").accepted,"the sword unequips")
	check_eq(str(session.protagonist_equipment().weapon_id),"UNARMED_STRIKE",
		"an empty main hand reads as unarmed")
	check(session.equip_inventory_item("START_CROSSBOW_001","MAIN_HAND").accepted,
		"the crossbow equips through the item facade")
	check_eq(str(session.protagonist_equipment().weapon_id),"CROSSBOW",
		"the equipped instance definition is the weapon authority")
	check_eq(str(session.protagonist_equipment().attack_block_reason),"reload_required",
		"the crossbow blocks until the instance runtime row is loaded")
	check(session.reload_protagonist_weapon().accepted,"the crossbow reloads")
	check(bool(session.protagonist_equipment().loaded),
		"the equipment DTO reads the load from the instance runtime row")
	check_eq(session.sim.world.world_state_error(),"",
		"the world stays valid without a loadout bridge")
	return finish()
