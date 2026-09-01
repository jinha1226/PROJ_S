class_name ActorLoadoutRegistry
extends RefCounted

const CONTENT_PATH := "res://data/content/actor_loadouts.json"
const RULESET_ID := "actor-loadouts-v1"
const ContentLoaderScript = preload("res://sim/json_content_loader.gd")
const ItemRegistryScript = preload("res://sim/item_registry.gd")
const ItemScript = preload("res://sim/item_instance.gd")
const InventoryOperationsScript = preload("res://sim/item_inventory_operations.gd")
const WorldItemOperationsScript = preload("res://sim/world_item_operations.gd")

static var _CONTENT: Dictionary = ContentLoaderScript.load_document(CONTENT_PATH)
static var _LOADOUTS: Dictionary = ContentLoaderScript.index_rows(
	_CONTENT.get("loadouts", []), "loadout_id")


static func has(loadout_id: String) -> bool:
	return _LOADOUTS.has(loadout_id) and _loadout_error(_LOADOUTS[loadout_id]).is_empty()


static func loadout(loadout_id: String) -> Dictionary:
	return _LOADOUTS[loadout_id].duplicate(true) if has(loadout_id) else {}


static func ids() -> Array[String]:
	var result: Array[String] = []
	for loadout_id in _LOADOUTS: result.append(str(loadout_id))
	result.sort()
	return result


static func registry_error() -> String:
	var document_error := ContentLoaderScript.document_error(_CONTENT, "ACTOR_LOADOUTS", [
		"content_schema_version", "content_version", "content_type", "ruleset_id", "loadouts"])
	if not document_error.is_empty(): return document_error
	if str(_CONTENT.get("ruleset_id", "")) != RULESET_ID: return "actor_loadout_ruleset_mismatch"
	var rows_error := ContentLoaderScript.rows_error(_CONTENT.get("loadouts", []), "loadout_id")
	if not rows_error.is_empty(): return rows_error
	var previous_id := ""
	for row in _CONTENT.loadouts:
		var loadout_id := str(row.get("loadout_id", ""))
		if not previous_id.is_empty() and loadout_id <= previous_id:
			return "duplicate_or_unsorted_actor_loadout"
		previous_id = loadout_id
		var error := _loadout_error(row)
		if not error.is_empty(): return error
	return ""


static func plan_apply(item_state, entity_id: int, loadout_id: String) -> Dictionary:
	if not registry_error().is_empty(): return _rejected("actor_loadout_registry_invalid")
	if item_state == null or item_state.inventory(entity_id) == null:
		return _rejected("actor_loadout_entity_missing")
	if not has(loadout_id): return _rejected("actor_loadout_missing")
	var next = item_state.clone()
	var instance_rows: Array[Dictionary] = []
	for entry in _LOADOUTS[loadout_id].items:
		var instance_id: String = next.instance_id_for(next.next_item_instance_id)
		next.next_item_instance_id += 1
		var item = ItemScript.new(instance_id, str(entry.definition_id), int(entry.quantity))
		var added := InventoryOperationsScript.commit_insert_instance(next.inventory(entity_id), item)
		if not bool(added.get("accepted", false)): return _rejected(str(added.reason))
		next.inventory_rows[entity_id] = added.inventory
		var slot := str(entry.equip_slot)
		if not slot.is_empty():
			var equipped := InventoryOperationsScript.commit_equip(
				next.inventory(entity_id), instance_id, slot)
			if not bool(equipped.get("accepted", false)): return _rejected(str(equipped.reason))
			next.inventory_rows[entity_id] = equipped.inventory
		instance_rows.append({"entry_id": str(entry.entry_id), "instance_id": instance_id,
			"definition_id": str(entry.definition_id), "equip_slot": slot})
	WorldItemOperationsScript.reconcile_weapon_runtime_rows(next)
	var error: String = next.validation_error()
	if not error.is_empty(): return _rejected(error)
	return {"accepted": true, "reason": "ok", "item_state": next,
		"loadout_id": loadout_id, "instance_rows": instance_rows.duplicate(true)}


static func _loadout_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_actor_loadout_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["items", "loadout_id"] or not row.get("loadout_id") is String \
			or str(row.loadout_id).is_empty() or not row.get("items") is Array \
			or row.items.is_empty() or row.items.size() > 17:
		return "invalid_actor_loadout_shape"
	var previous_entry := ""
	var occupied_slots: Dictionary = {}
	for entry in row.items:
		if not entry is Dictionary: return "invalid_actor_loadout_item_shape"
		var entry_keys: Array = entry.keys(); entry_keys.sort()
		if entry_keys != ["definition_id", "entry_id", "equip_slot", "quantity"] \
				or not entry.entry_id is String or str(entry.entry_id).is_empty() \
				or not entry.definition_id is String or not entry.equip_slot is String \
				or not entry.quantity is int:
			return "invalid_actor_loadout_item_shape"
		var entry_id := str(entry.entry_id)
		if not previous_entry.is_empty() and entry_id <= previous_entry:
			return "duplicate_or_unsorted_actor_loadout_item"
		previous_entry = entry_id
		var definition = ItemRegistryScript.definition(str(entry.definition_id))
		if definition == null or int(entry.quantity) < 1 \
				or int(entry.quantity) > int(definition.stack_limit):
			return "invalid_actor_loadout_item"
		var slot := str(entry.equip_slot)
		if not slot.is_empty():
			if slot not in definition.equip_slots: return "actor_loadout_wrong_equip_slot"
			if occupied_slots.has(slot): return "actor_loadout_duplicate_equip_slot"
			occupied_slots[slot] = true
	return ""


static func _rejected(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}
