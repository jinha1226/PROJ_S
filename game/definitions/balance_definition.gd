class_name BalanceDefinition
extends Resource

@export var id: StringName = &"default_balance"
@export var display_name_key: StringName = &"balance.default"
@export var enabled: bool = true
@export var division_base_cycles: int = 24
@export var division_per_extra_skill_cycles: int = 12


func division_requirement(skill_count: int) -> int:
	return division_base_cycles + division_per_extra_skill_cycles * maxi(0, skill_count - 1)
