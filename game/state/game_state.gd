class_name GameState
extends RefCounted

const MAX_ACTIVE_SLIMES := 12

var schema_version: int = 1
var content_version: int = 1
var region_id: StringName = &"first_clearing"
var simulation_tick: int = 0
var next_entity_number: int = 1
var slimes: Dictionary = {}
var facilities: Dictionary = {}
var inventories: Dictionary = {}
var unlocked_content_ids: Dictionary = {}
var goal_states: Dictionary = {}
var last_saved_unix: int = 0


func allocate_slime_id() -> StringName:
	var allocated := StringName("slime_%06d" % next_entity_number)
	next_entity_number += 1
	return allocated


func get_population() -> int:
	return slimes.size()


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"content_version": content_version,
		"region_id": str(region_id),
		"simulation_tick": simulation_tick,
		"next_entity_number": next_entity_number,
		"slimes": _serialize_state_dictionary(slimes),
		"facilities": _serialize_state_dictionary(facilities),
		"inventories": _serialize_state_dictionary(inventories),
		"unlocked_content_ids": _deep_string_key_copy(unlocked_content_ids),
		"goal_states": _deep_string_key_copy(goal_states),
		"last_saved_unix": last_saved_unix,
	}


static func from_dict(data: Dictionary) -> GameState:
	var state := GameState.new()
	state.schema_version = int(data.get("schema_version", 0))
	state.content_version = int(data.get("content_version", 0))
	state.region_id = StringName(str(data.get("region_id", "")))
	state.simulation_tick = int(data.get("simulation_tick", 0))
	state.next_entity_number = int(data.get("next_entity_number", 1))
	state.last_saved_unix = int(data.get("last_saved_unix", data.get("saved_at_unix", 0)))

	var raw_slimes: Variant = data.get("slimes", {})
	if typeof(raw_slimes) == TYPE_DICTIONARY:
		for slime_key: Variant in raw_slimes.keys():
			var slime_data: Variant = raw_slimes[slime_key]
			if typeof(slime_data) != TYPE_DICTIONARY:
				continue
			var normalized: Dictionary = slime_data.duplicate(true)
			normalized["id"] = str(normalized.get("id", slime_key))
			state.slimes[StringName(str(slime_key))] = SlimeState.from_dict(normalized)

	var raw_inventories: Variant = data.get("inventories", {})
	if typeof(raw_inventories) == TYPE_DICTIONARY:
		for inventory_key: Variant in raw_inventories.keys():
			var inventory_data: Variant = raw_inventories[inventory_key]
			if typeof(inventory_data) != TYPE_DICTIONARY:
				continue
			var normalized: Dictionary = inventory_data.duplicate(true)
			normalized["owner_id"] = str(normalized.get("owner_id", inventory_key))
			state.inventories[StringName(str(inventory_key))] = InventoryState.from_dict(normalized)

	var raw_facilities: Variant = data.get("facilities", {})
	if typeof(raw_facilities) == TYPE_DICTIONARY:
		for facility_key: Variant in raw_facilities.keys():
			var facility_data: Variant = raw_facilities[facility_key]
			if typeof(facility_data) != TYPE_DICTIONARY:
				continue
			var normalized: Dictionary = facility_data.duplicate(true)
			normalized["id"] = str(normalized.get("id", facility_key))
			state.facilities[StringName(str(facility_key))] = FacilityState.from_dict(normalized)
	state.goal_states = _variant_to_dictionary(data.get("goal_states", data.get("goals", {})))
	state.unlocked_content_ids = _normalize_unlocks(data.get("unlocked_content_ids", data.get("unlocks", {})))
	return state


func clone_state() -> GameState:
	return GameState.from_dict(to_dict())


func validate(content_registry: Variant = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version < 1:
		errors.append("GameState.schema_version must be at least 1")
	if content_version < 1:
		errors.append("GameState.content_version must be at least 1")
	if region_id == &"":
		errors.append("GameState.region_id is empty")
	if simulation_tick < 0:
		errors.append("GameState.simulation_tick must not be negative")
	if next_entity_number < 1:
		errors.append("GameState.next_entity_number must be at least 1")
	if get_population() > MAX_ACTIVE_SLIMES:
		errors.append("GameState population exceeds the global maximum")

	for slime_key: Variant in slimes.keys():
		var slime: Variant = slimes[slime_key]
		if not slime is SlimeState:
			errors.append("GameState slime %s is not SlimeState" % str(slime_key))
			continue
		if slime.id != StringName(str(slime_key)):
			errors.append("GameState slime key does not match SlimeState.id")
		for error: String in slime.validate(content_registry):
			errors.append(error)

	for inventory_key: Variant in inventories.keys():
		var inventory: Variant = inventories[inventory_key]
		if not inventory is InventoryState:
			errors.append("GameState inventory %s is not InventoryState" % str(inventory_key))
			continue
		if inventory.owner_id != StringName(str(inventory_key)):
			errors.append("GameState inventory key does not match InventoryState.owner_id")
		for error: String in inventory.validate(content_registry):
			errors.append(error)

	for facility_key: Variant in facilities.keys():
		var facility: Variant = facilities[facility_key]
		if not facility is FacilityState:
			errors.append("GameState facility %s is not FacilityState" % str(facility_key))
			continue
		if facility.id != StringName(str(facility_key)):
			errors.append("GameState facility key does not match FacilityState.id")
		for error: String in facility.validate():
			errors.append(error)

	if typeof(content_registry) == TYPE_OBJECT and content_registry != null and content_registry.has_method("validate_state_content"):
		var content_errors: Variant = content_registry.validate_state_content(self)
		if content_errors is PackedStringArray:
			errors.append_array(content_errors)
	return errors


func canonical_json() -> String:
	return JSON.stringify(_canonicalize(to_dict()))


func canonical_hash() -> String:
	return canonical_json().sha256_text()


static func _serialize_state_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source.keys():
		var value: Variant = source[key]
		if typeof(value) == TYPE_OBJECT and value != null and value.has_method("to_dict"):
			result[str(key)] = value.to_dict()
		elif typeof(value) == TYPE_DICTIONARY:
			result[str(key)] = _deep_string_key_copy(value)
	return result


static func _deep_string_key_copy(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source.keys():
		result[str(key)] = _copy_serializable(source[key])
	return result


static func _copy_serializable(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		return _deep_string_key_copy(value)
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item: Variant in value:
			result.append(_copy_serializable(item))
		return result
	if typeof(value) == TYPE_STRING_NAME:
		return str(value)
	return value


static func _canonicalize(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var source: Dictionary = value
		var sorted_keys: Array[String] = []
		for key: Variant in source.keys():
			sorted_keys.append(str(key))
		sorted_keys.sort()
		var result: Dictionary = {}
		for key_string: String in sorted_keys:
			result[key_string] = _canonicalize(_dictionary_value_by_string(source, key_string))
		return result
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonicalize(item))
		return result
	if typeof(value) == TYPE_STRING_NAME:
		return str(value)
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floor(float(value)):
		return int(value)
	return value


static func _dictionary_value_by_string(source: Dictionary, key_string: String) -> Variant:
	for key: Variant in source.keys():
		if str(key) == key_string:
			return source[key]
	return null


static func _variant_to_dictionary(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return _deep_string_key_copy(value)


static func _normalize_unlocks(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) == TYPE_ARRAY:
		for content_id: Variant in value:
			result[str(content_id)] = true
	elif typeof(value) == TYPE_DICTIONARY:
		for content_id: Variant in value.keys():
			result[str(content_id)] = bool(value[content_id])
	return result
