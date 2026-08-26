class_name InventorySystem
extends RefCounted

var state: GameState


func _init(p_state: GameState = null) -> void:
	state = p_state


func set_state(p_state: GameState) -> void:
	state = p_state


func get_amount(inventory_id: StringName, resource_id: StringName) -> int:
	var inventory := _get_inventory(inventory_id)
	if inventory == null:
		return 0
	return int(inventory.amounts.get(str(resource_id), 0))


func can_add(inventory_id: StringName, amounts: Dictionary) -> bool:
	var inventory := _get_inventory(inventory_id)
	if inventory == null:
		return false
	for resource_key: Variant in amounts.keys():
		var amount: Variant = amounts[resource_key]
		if typeof(amount) != TYPE_INT or int(amount) < 0:
			return false
		var resource_id := str(resource_key)
		var current := int(inventory.amounts.get(resource_id, 0))
		var capacity := int(inventory.capacities.get(resource_id, 0))
		if current + int(amount) > capacity:
			return false
	return true


func try_add(inventory_id: StringName, amounts: Dictionary) -> CommandResult:
	var inventory := _get_inventory(inventory_id)
	if inventory == null:
		return CommandResult.failure(&"INVENTORY_NOT_FOUND")
	if not can_add(inventory_id, amounts):
		return CommandResult.failure(&"INVENTORY_FULL")

	var changes: Array[Dictionary] = []
	for resource_key: Variant in amounts.keys():
		var amount := int(amounts[resource_key])
		if amount == 0:
			continue
		var resource_id := str(resource_key)
		var old_amount := int(inventory.amounts.get(resource_id, 0))
		var new_amount := old_amount + amount
		inventory.amounts[resource_id] = new_amount
		changes.append({
			"inventory_id": str(inventory_id),
			"resource_id": resource_id,
			"old_amount": old_amount,
			"new_amount": new_amount,
		})
	return CommandResult.success({"changes": changes})


func _get_inventory(inventory_id: StringName) -> InventoryState:
	if state == null:
		return null
	return state.inventories.get(inventory_id) as InventoryState
