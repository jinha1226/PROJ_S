class_name CorpseLootSystem
extends RefCounted

const ItemScript = preload("res://sim/item_instance.gd")
const InventoryOperationsScript = preload("res://sim/item_inventory_operations.gd")
const WorldItemOperationsScript = preload("res://sim/world_item_operations.gd")
const SpeciesDropRegistryScript = preload("res://sim/species_drop_registry.gd")


static func materialize_death_event(world, death_event) -> Dictionary:
	if world == null or world.item_state == null or death_event == null \
			or death_event.type != "entity.died" \
			or world.event_by_id(int(death_event.id)) != death_event:
		return _rejected("invalid_drop_death_event")
	var corpse_id := int(death_event.target_id)
	var corpse = world.entities.get(corpse_id)
	if corpse == null or world.item_state.inventory(corpse_id) == null \
			or death_event.position != corpse.position:
		return _rejected("drop_corpse_missing")
	if int(death_event.id) in world.item_state.processed_drop_death_event_ids:
		return {"accepted": true, "reason": "already_processed", "already_processed": true,
			"event_id": -1, "generated_items": []}
	if not SpeciesDropRegistryScript.registry_error().is_empty():
		return _rejected("species_drop_registry_invalid")
	var next = world.item_state.clone()
	var generated_rows: Array[Dictionary] = []
	var rolls := SpeciesDropRegistryScript.rolls_for(world.seed, int(death_event.id),
		str(corpse.species_id))
	for roll in rolls:
		var instance_id: String = next.instance_id_for(next.next_item_instance_id)
		next.next_item_instance_id += 1
		var item = ItemScript.new(instance_id, str(roll.definition_id), int(roll.quantity))
		var added := InventoryOperationsScript.commit_insert_instance(
			next.inventory(corpse_id), item)
		var location := "CORPSE"
		if bool(added.get("accepted", false)):
			next.inventory_rows[corpse_id] = added.inventory
		elif str(added.get("reason", "")) == "inventory_backpack_full":
			location = "GROUND"
			next.ground_items.rows.append({"position": corpse.position, "item": item})
			next.ground_items._sort_rows()
		else:
			return _rejected(str(added.get("reason", "drop_insert_failed")))
		generated_rows.append({"instance_id": instance_id,
			"definition_id": str(roll.definition_id), "quantity": int(roll.quantity),
			"location": location, "roll_id": str(roll.roll_id)})
	next.processed_drop_death_event_ids.append(int(death_event.id))
	next.processed_drop_death_event_ids.sort()
	WorldItemOperationsScript.reconcile_weapon_runtime_rows(next)
	var error: String = next.validation_error(world.width, world.height)
	if error.is_empty():
		var death_ids: Array = []
		for event in world.events:
			if event.type == "entity.died": death_ids.append(int(event.id))
		error = next.world_membership_error(world.combatant_states.keys(), death_ids)
	if not error.is_empty(): return _rejected(error)
	next.revision = int(world.item_state.revision) + 1
	var total_quantity := 0
	for row in generated_rows: total_quantity += int(row.quantity)
	var materialized = world.emit_event("corpse.loot_materialized", corpse_id, corpse_id,
		corpse.position, total_quantity, int(death_event.id), {"schema_version": 1,
			"ruleset_id": SpeciesDropRegistryScript.RULESET_ID,
			"source_death_event_id": str(death_event.id),
			"generated_items": generated_rows})
	if materialized == null: return _rejected("corpse_drop_event_failed")
	world.item_state = next
	return {"accepted": true, "reason": "ok", "already_processed": false,
		"event_id": int(materialized.id), "generated_items": generated_rows.duplicate(true),
		"revision": int(next.revision)}


static func _rejected(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "already_processed": false,
		"event_id": -1, "generated_items": []}
