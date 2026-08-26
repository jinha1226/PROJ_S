class_name FacilityState
extends RefCounted

var id: StringName = &""
var definition_id: StringName = &""
var tier: int = 0
var enabled: bool = true
var locked: bool = false
var worker_slots: int = 1
var active_worker_ids: Array[StringName] = []
var population_capacity: int = 0
var repair_enabled: bool = false


func _init(p_id: StringName = &"") -> void:
	id = p_id
	definition_id = p_id


func has_open_worker_slot() -> bool:
	return active_worker_ids.size() < worker_slots


func to_dict() -> Dictionary:
	var workers: Array[String] = []
	for worker_id: StringName in active_worker_ids:
		workers.append(str(worker_id))
	return {
		"id": str(id),
		"definition_id": str(definition_id),
		"tier": tier,
		"enabled": enabled,
		"locked": locked,
		"worker_slots": worker_slots,
		"active_worker_ids": workers,
		"population_capacity": population_capacity,
		"repair_enabled": repair_enabled,
	}


static func from_dict(data: Dictionary) -> FacilityState:
	var state := FacilityState.new(StringName(str(data.get("id", data.get("definition_id", "")))))
	state.definition_id = StringName(str(data.get("definition_id", state.id)))
	state.tier = int(data.get("tier", 0))
	state.enabled = bool(data.get("enabled", true))
	state.locked = bool(data.get("locked", false))
	state.worker_slots = int(data.get("worker_slots", 1))
	state.population_capacity = int(data.get("population_capacity", 0))
	state.repair_enabled = bool(data.get("repair_enabled", false))
	var raw_workers: Variant = data.get("active_worker_ids", [])
	if typeof(raw_workers) == TYPE_ARRAY:
		for worker_id: Variant in raw_workers:
			state.active_worker_ids.append(StringName(str(worker_id)))
	return state


func clone_state() -> FacilityState:
	return FacilityState.from_dict(to_dict())


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("FacilityState.id is empty")
	if tier < 0:
		errors.append("FacilityState.tier must not be negative")
	if worker_slots < 0:
		errors.append("FacilityState.worker_slots must not be negative")
	if active_worker_ids.size() > worker_slots:
		errors.append("FacilityState active workers exceed slots")
	return errors
