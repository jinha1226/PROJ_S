class_name InventoryState
extends RefCounted

var owner_id: StringName = &""
var amounts: Dictionary = {}
var capacities: Dictionary = {}
var reservations: Dictionary = {}


func _init(p_owner_id: StringName = &"") -> void:
	owner_id = p_owner_id


func to_dict() -> Dictionary:
	return {
		"owner_id": str(owner_id),
		"amounts": amounts.duplicate(true),
		"capacities": capacities.duplicate(true),
		"reservations": reservations.duplicate(true),
	}


static func from_dict(data: Dictionary) -> InventoryState:
	var state := InventoryState.new(StringName(str(data.get("owner_id", ""))))
	state.amounts = _string_keyed_int_dictionary(data.get("amounts", {}))
	state.capacities = _string_keyed_int_dictionary(data.get("capacities", {}))
	state.reservations = Dictionary(data.get("reservations", {})).duplicate(true)
	return state


func clone_state() -> InventoryState:
	return InventoryState.from_dict(to_dict())


func validate(_content_registry: Variant = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if owner_id == &"":
		errors.append("InventoryState.owner_id is empty")

	for resource_key: Variant in amounts.keys():
		var amount: Variant = amounts[resource_key]
		if typeof(amount) != TYPE_INT or int(amount) < 0:
			errors.append("Inventory amount %s must be a non-negative integer" % str(resource_key))

	for resource_key: Variant in capacities.keys():
		var capacity: Variant = capacities[resource_key]
		if typeof(capacity) != TYPE_INT or int(capacity) < 0:
			errors.append("Inventory capacity %s must be a non-negative integer" % str(resource_key))

	for reservation_key: Variant in reservations.keys():
		var reserved: Variant = reservations[reservation_key]
		if typeof(reserved) != TYPE_DICTIONARY:
			errors.append("Inventory reservation %s must be a Dictionary" % str(reservation_key))
			continue
		for resource_key: Variant in reserved.keys():
			var amount: Variant = reserved[resource_key]
			if typeof(amount) != TYPE_INT or int(amount) < 0:
				errors.append("Reserved amount %s/%s must be a non-negative integer" % [str(reservation_key), str(resource_key)])
	return errors


static func _string_keyed_int_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key: Variant in value.keys():
		result[str(key)] = int(value[key])
	return result
