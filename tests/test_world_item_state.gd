extends "res://tests/test_case.gd"

const Inventory=preload("res://sim/inventory_state.gd")
const LegacyInventory=preload("res://sim/protagonist_inventory_state.gd")
const Ammo=preload("res://sim/ammo_pool_state.gd")
const Runtime=preload("res://sim/weapon_runtime_state.gd")
const Item=preload("res://sim/item_instance.gd")
const Ground=preload("res://sim/ground_item_state.gd")
const WorldItem=preload("res://sim/world_item_state.gd")

const CROSSBOW_ID:="ITEM_00000000000000000031"
const SPARE_CROSSBOW_ID:="ITEM_00000000000000000030"
const BOW_ID:="ITEM_00000000000000000003"
const POTION_ID:="ITEM_00000000000000000012"
const ARMOR_ID:="ITEM_00000000000000000007"


func test_general_inventory_keeps_protagonist_semantics_without_bootstrap_helpers()->bool:
	var rows:Array=[Item.new("SWORD","WEAPON_SHORT_SWORD"),Item.new("POTION","POTION_HEALING",3)]
	var general=Inventory.new(rows,{"MAIN_HAND":"SWORD"})
	var legacy=LegacyInventory.new(rows,{"MAIN_HAND":"SWORD"})
	check_eq(general.to_dict(),legacy.to_dict(),"generalized wire equals protagonist wire")
	check_eq(general.validation_error(),"","generalized inventory validates")
	check_eq(general.used_backpack_slots(),1,"equipped rows do not consume bag slots")
	check_eq(Inventory.from_dict(general.to_dict()).to_dict(),general.to_dict(),
		"inventory round trip is exact")
	check_eq(general.equipment_bonuses(),legacy.equipment_bonuses(),"shared equipment aggregate")
	check_eq(general.combat_modifier_dto(),legacy.combat_modifier_dto(),"shared combat handoff")
	var names:Array=[]
	for method in Inventory.new().get_method_list():names.append(str(method.name))
	check("with_legacy_weapon" not in names and "with_legacy_short_sword" not in names,
		"protagonist bootstrap helpers left the general state")
	check_eq(Inventory.BACKPACK_CAPACITY,12,"twelve slot capacity is shared")
	return finish()


func test_ammo_pool_and_weapon_runtime_states_round_trip_exactly()->bool:
	var pool=Ammo.new(12,6)
	check_eq(pool.to_dict(),{"schema_version":1,"ammo_pools":[
		{"ammo_kind":"ARROW","amount":12},{"ammo_kind":"BOLT","amount":6}]},
		"versioned ammo pool wire uses ordered rows")
	check_eq(Ammo.from_dict(pool.to_dict()).to_dict(),pool.to_dict(),"ammo pool round trip")
	check_eq([pool.amount("ARROW"),pool.amount("BOLT")],[12,6],"ammo pool reads by kind")
	check_eq(Ammo.new().to_dict(),{"schema_version":1,"ammo_pools":[
		{"ammo_kind":"ARROW","amount":0},{"ammo_kind":"BOLT","amount":0}]},
		"new entities start with no ammo")
	var missing_schema:Dictionary=pool.to_dict();missing_schema.erase("schema_version")
	check_eq(Ammo.wire_error(missing_schema),"invalid_ammo_pool_keys","exact ammo keys")
	var wrong_ammo_schema:Dictionary=pool.to_dict();wrong_ammo_schema.schema_version=2
	check_eq(Ammo.wire_error(wrong_ammo_schema),"unsupported_ammo_pool_schema",
		"wrong ammo schema rejected")
	var reversed:Dictionary=pool.to_dict();reversed.ammo_pools.reverse()
	check_eq(Ammo.wire_error(reversed),"noncanonical_ammo_pool_order",
		"ammo rows serialize in canonical order")
	var duplicate:Dictionary=pool.to_dict();duplicate.ammo_pools[1].ammo_kind="ARROW"
	check_eq(Ammo.wire_error(duplicate),"noncanonical_ammo_pool_order",
		"duplicate ammo kind rejected")
	var negative:Dictionary=pool.to_dict();negative.ammo_pools[0].amount=-1
	check_eq(Ammo.wire_error(negative),"invalid_ammo_pool_amount","negative ammo rejected")
	var fractional:Dictionary=pool.to_dict();fractional.ammo_pools[0].amount=1.5
	check_eq(Ammo.wire_error(fractional),"invalid_ammo_pool_amount","fractional ammo rejected")
	check(Ammo.from_dict(negative)==null,"from_dict cannot launder ammo")
	var runtime=Runtime.new("CROSSBOW_01",true)
	check_eq(runtime.to_dict(),{"schema_version":1,"instance_id":"CROSSBOW_01","loaded":true},
		"weapon runtime wire shape")
	check_eq(Runtime.from_dict(runtime.to_dict()).to_dict(),runtime.to_dict(),
		"weapon runtime round trip")
	var wrong_schema:Dictionary=runtime.to_dict();wrong_schema.schema_version=2
	check_eq(Runtime.wire_error(wrong_schema),"unsupported_weapon_runtime_schema",
		"wrong runtime schema rejected")
	check(Runtime.from_dict(wrong_schema)==null,"from_dict cannot launder runtime schema")
	var extra:Dictionary=runtime.to_dict();extra["reload_time"]=4
	check_eq(Runtime.wire_error(extra),"invalid_weapon_runtime_keys","extra runtime key rejected")
	var bad_loaded:Dictionary=runtime.to_dict();bad_loaded.loaded=1
	check_eq(Runtime.wire_error(bad_loaded),"invalid_weapon_runtime_shape",
		"loaded flag must be a bool")
	return finish()


func _sample_state():
	var state=WorldItem.new()
	state.revision=14;state.next_item_instance_id=32
	state.inventory_rows[2]=Inventory.new([Item.new(CROSSBOW_ID,"WEAPON_CROSSBOW"),
		Item.new(POTION_ID,"POTION_HEALING",3)],{"MAIN_HAND":CROSSBOW_ID})
	state.inventory_rows[1]=Inventory.new([Item.new(BOW_ID,"WEAPON_BOW"),
		Item.new(SPARE_CROSSBOW_ID,"WEAPON_CROSSBOW")])
	state.ammo_pool_rows[2]=Ammo.new(12,6)
	state.ammo_pool_rows[1]=Ammo.new()
	state.weapon_runtime_rows[CROSSBOW_ID]=Runtime.new(CROSSBOW_ID,true)
	state.weapon_runtime_rows[SPARE_CROSSBOW_ID]=Runtime.new(SPARE_CROSSBOW_ID,false)
	state.ground_items=Ground.new([{"position":[3,4],
		"item":Item.new(ARMOR_ID,"ARMOR_LEATHER").to_dict()}])
	state.processed_drop_death_event_ids.assign([5,9])
	return state


func test_world_item_state_wire_round_trip_is_exact()->bool:
	var state=_sample_state()
	var wire:Dictionary=state.to_dict()
	var keys:Array=wire.keys();keys.sort()
	check_eq(keys,["ammo_pool_rows","ground_items","inventory_rows","next_item_instance_id",
		"processed_drop_death_event_ids","revision","schema_version","weapon_runtime_rows"],
		"world item wire v1 exact keys")
	check(wire.revision is String and wire.next_item_instance_id is String,
		"int64 scalars serialize as canonical strings")
	check_eq([wire.revision,wire.next_item_instance_id],["14","32"],"canonical int64 scalars")
	check_eq(wire.processed_drop_death_event_ids,["5","9"],"death event IDs are canonical strings")
	check_eq(wire.ammo_pool_rows,[{"entity_id":"1","ammo_pool":Ammo.new().to_dict()},
		{"entity_id":"2","ammo_pool":Ammo.new(12,6).to_dict()}],
		"ammo rows sort by entity ID and nest the versioned wire")
	check_eq([str(wire.inventory_rows[0].entity_id),str(wire.inventory_rows[1].entity_id)],
		["1","2"],"inventory rows sort by entity ID")
	check_eq(wire.inventory_rows[1].inventory,state.inventory(2).to_dict(),
		"inventory rows nest the full inventory wire")
	check_eq([str(wire.weapon_runtime_rows[0].instance_id),
		str(wire.weapon_runtime_rows[1].instance_id)],[SPARE_CROSSBOW_ID,CROSSBOW_ID],
		"weapon runtime rows sort by instance ID")
	check_eq(wire.ground_items,state.ground_items.to_dict(),"ground items nest verbatim")
	check_eq(WorldItem.wire_error(wire),"","sample world item state validates")
	check_eq(WorldItem.from_dict(wire).to_dict(),wire,"world item round trip is exact")
	var huge=_sample_state()
	huge.revision=9223372036854775806;huge.next_item_instance_id=9223372036854775807
	huge.processed_drop_death_event_ids.assign([9223372036854775806])
	var reparsed:Variant=JSON.parse_string(JSON.stringify(huge.to_dict()))
	check_eq([reparsed.revision,reparsed.next_item_instance_id,
		reparsed.processed_drop_death_event_ids],
		["9223372036854775806","9223372036854775807",["9223372036854775806"]],
		"int64 scalars survive JSON without precision loss")
	check_eq(WorldItem.from_dict(huge.to_dict()).to_dict(),huge.to_dict(),
		"int64 extremes round trip exactly")
	return finish()


func test_duplicate_instance_ids_across_inventories_and_ground_are_rejected()->bool:
	var shared_bags=_sample_state()
	shared_bags.inventory_rows[1]=Inventory.new([Item.new(CROSSBOW_ID,"WEAPON_SHORT_SWORD")])
	check_eq(shared_bags.validation_error(),"duplicate_world_item_instance",
		"one instance cannot live in two bags")
	var ground_clash=_sample_state()
	ground_clash.ground_items=Ground.new([{"position":[3,4],
		"item":Item.new(CROSSBOW_ID,"WEAPON_CROSSBOW").to_dict()}])
	check_eq(ground_clash.validation_error(),"duplicate_world_item_instance",
		"one instance cannot be carried and lie on the ground")
	check_eq(WorldItem.wire_error(ground_clash.to_dict()),"duplicate_world_item_instance",
		"wire refuses the duplicate before object construction")
	check(WorldItem.from_dict(ground_clash.to_dict())==null,
		"from_dict cannot launder a duplicate instance")
	return finish()


func test_malformed_unsorted_extra_key_and_missing_row_wire_is_rejected()->bool:
	check_eq(WorldItem.wire_error(7),"invalid_world_item_shape","non dictionary rejected")
	var extra:Dictionary=_sample_state().to_dict();extra["corpse_rows"]=[]
	check_eq(WorldItem.wire_error(extra),"invalid_world_item_keys","extra key rejected")
	var missing:Dictionary=_sample_state().to_dict();missing.erase("ammo_pool_rows")
	check_eq(WorldItem.wire_error(missing),"invalid_world_item_keys","missing row set rejected")
	var wrong_schema:Dictionary=_sample_state().to_dict();wrong_schema.schema_version=2
	check_eq(WorldItem.wire_error(wrong_schema),"unsupported_world_item_schema",
		"unsupported schema rejected")
	check(WorldItem.from_dict(wrong_schema)==null,"from_dict cannot launder the schema")
	var numeric:Dictionary=_sample_state().to_dict();numeric.revision=14
	check_eq(WorldItem.wire_error(numeric),"noncanonical_world_item_revision",
		"numeric revision rejected")
	var padded:Dictionary=_sample_state().to_dict();padded.revision="014"
	check_eq(WorldItem.wire_error(padded),"noncanonical_world_item_revision",
		"leading zero revision rejected")
	var spaced:Dictionary=_sample_state().to_dict();spaced.next_item_instance_id=" 32"
	check_eq(WorldItem.wire_error(spaced),"noncanonical_world_item_next_item_instance_id",
		"whitespace allocator rejected")
	var negative:Dictionary=_sample_state().to_dict();negative.revision="-1"
	check_eq(WorldItem.wire_error(negative),"invalid_world_item_scalar","negative revision rejected")
	var unsorted:Dictionary=_sample_state().to_dict()
	var swapped:Array=[unsorted.inventory_rows[1],unsorted.inventory_rows[0]]
	unsorted.inventory_rows=swapped
	check_eq(WorldItem.wire_error(unsorted),"noncanonical_world_item_entity_order",
		"unsorted inventory rows rejected")
	var duplicated:Dictionary=_sample_state().to_dict()
	duplicated.inventory_rows=[duplicated.inventory_rows[0],duplicated.inventory_rows[0]]
	check_eq(WorldItem.wire_error(duplicated),"duplicate_world_item_entity_row",
		"duplicate entity row rejected")
	var missing_ammo:Dictionary=_sample_state().to_dict()
	missing_ammo.ammo_pool_rows=[missing_ammo.ammo_pool_rows[1]]
	check_eq(WorldItem.wire_error(missing_ammo),"","item state alone cannot judge world parity")
	var numeric_entity:Dictionary=_sample_state().to_dict()
	numeric_entity.inventory_rows[0]={"entity_id":1,
		"inventory":numeric_entity.inventory_rows[0].inventory}
	check_eq(WorldItem.wire_error(numeric_entity),"noncanonical_world_item_entity_id",
		"numeric entity ID rejected")
	var bad_row:Dictionary=_sample_state().to_dict()
	bad_row.inventory_rows[0]={"entity_id":"1"}
	check_eq(WorldItem.wire_error(bad_row),"invalid_world_item_inventory_row",
		"inventory row without its inventory rejected")
	var unsorted_runtime:Dictionary=_sample_state().to_dict()
	unsorted_runtime.weapon_runtime_rows=[unsorted_runtime.weapon_runtime_rows[1],
		unsorted_runtime.weapon_runtime_rows[0]]
	check_eq(WorldItem.wire_error(unsorted_runtime),"noncanonical_weapon_runtime_order",
		"unsorted weapon runtime rows rejected")
	var unknown_runtime:Dictionary=_sample_state().to_dict()
	unknown_runtime.weapon_runtime_rows=[{"schema_version":1,
		"instance_id":"ITEM_00000000000000000099","loaded":false}]
	check_eq(WorldItem.wire_error(unknown_runtime),"unknown_weapon_runtime_instance",
		"weapon runtime must reference a live instance")
	var armor_runtime:Dictionary=_sample_state().to_dict()
	armor_runtime.weapon_runtime_rows=[{"schema_version":1,"instance_id":ARMOR_ID,
		"loaded":false}]
	check_eq(WorldItem.wire_error(armor_runtime),"weapon_runtime_not_a_weapon",
		"weapon runtime cannot describe armor")
	var bow_runtime:Dictionary=_sample_state().to_dict()
	bow_runtime.weapon_runtime_rows.insert(0,{"schema_version":1,"instance_id":BOW_ID,
		"loaded":false})
	check_eq(WorldItem.wire_error(bow_runtime),"weapon_runtime_reload_mismatch",
		"non-reloading weapons cannot own a runtime row")
	var missing_runtime:Dictionary=_sample_state().to_dict()
	missing_runtime.weapon_runtime_rows.remove_at(0)
	check_eq(WorldItem.wire_error(missing_runtime),"missing_weapon_runtime_row",
		"every reloading weapon owns exactly one runtime row")
	var reversed_deaths:Dictionary=_sample_state().to_dict()
	reversed_deaths.processed_drop_death_event_ids=["9","5"]
	check_eq(WorldItem.wire_error(reversed_deaths),"noncanonical_processed_death_event_order",
		"reversed death event IDs rejected")
	var repeated_deaths:Dictionary=_sample_state().to_dict()
	repeated_deaths.processed_drop_death_event_ids=["5","5"]
	check_eq(WorldItem.wire_error(repeated_deaths),"duplicate_processed_death_event",
		"repeated death event ID rejected")
	var exhausted:Dictionary=_sample_state().to_dict();exhausted.next_item_instance_id="31"
	check_eq(WorldItem.wire_error(exhausted),"invalid_world_item_allocator",
		"allocator must lead every assigned runtime instance ID")
	check_eq(_sample_state().validation_error(2,2),"ground_item_out_of_bounds",
		"ground rows stay inside world bounds")
	return finish()


func test_loaded_crossbow_runtime_travels_with_the_weapon_instance()->bool:
	var state=_sample_state()
	check(state.weapon_runtime(CROSSBOW_ID).loaded,"crossbow starts loaded")
	var looted=WorldItem.from_dict(state.to_dict())
	var crossbow=looted.inventory(2).item(CROSSBOW_ID)
	var spare_crossbow=looted.inventory(1).item(SPARE_CROSSBOW_ID)
	looted.inventory_rows[2]=Inventory.new([Item.new(POTION_ID,"POTION_HEALING",3)])
	looted.inventory_rows[1]=Inventory.new([Item.new(BOW_ID,"WEAPON_BOW"),spare_crossbow,
		crossbow])
	check_eq(looted.validation_error(),"","looted crossbow keeps the world consistent")
	check(looted.weapon_runtime(CROSSBOW_ID).loaded,
		"reload state follows the instance to a new owner")
	var dropped=WorldItem.from_dict(looted.to_dict())
	dropped.inventory_rows[1]=Inventory.new([Item.new(BOW_ID,"WEAPON_BOW"),spare_crossbow])
	dropped.ground_items=Ground.new([{"position":[3,4],"item":crossbow.to_dict()},
		{"position":[3,4],"item":Item.new(ARMOR_ID,"ARMOR_LEATHER").to_dict()}])
	check_eq(dropped.validation_error(),"","dropped crossbow keeps the world consistent")
	check(dropped.weapon_runtime(CROSSBOW_ID).loaded,
		"reload state survives a drop to the ground")
	check_eq(dropped.to_dict().weapon_runtime_rows,state.to_dict().weapon_runtime_rows,
		"moving ownership never rewrites runtime rows")
	return finish()


func test_world_membership_seam_reports_entity_and_death_event_parity()->bool:
	var state=_sample_state()
	check_eq(state.world_membership_error([1,2],[5,9]),"","matching world sets pass")
	check_eq(state.world_membership_error([1,2,3],[5,9]),"inventory_row_entity_mismatch",
		"a combatant without an inventory row is rejected")
	check_eq(state.world_membership_error([1,2],[5]),"unknown_processed_death_event",
		"processed death IDs must be real death events")
	var missing_ammo=_sample_state();missing_ammo.ammo_pool_rows.erase(1)
	check_eq(missing_ammo.world_membership_error([1,2],[5,9]),"ammo_pool_row_entity_mismatch",
		"a combatant without an ammo row is rejected")
	check_eq(missing_ammo.validation_error(),"",
		"item-only validation never invents the world entity set")
	return finish()
