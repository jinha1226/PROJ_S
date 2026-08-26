class_name FacilityDefinition
extends Resource

@export var id: StringName = &""
@export var display_name_key: StringName = &""
@export var enabled: bool = true
@export var tags: Array[StringName] = []
@export var worker_slots_by_tier: Array[int] = [1]
@export var work_speed_multipliers: Array[float] = [1.0]


func worker_slots_for_tier(tier: int) -> int:
	if worker_slots_by_tier.is_empty():
		return 0
	return worker_slots_by_tier[clampi(tier, 0, worker_slots_by_tier.size() - 1)]


func speed_multiplier_for_tier(tier: int) -> float:
	if work_speed_multipliers.is_empty():
		return 1.0
	return work_speed_multipliers[clampi(tier, 0, work_speed_multipliers.size() - 1)]
