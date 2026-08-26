class_name SkillDefinition
extends Resource

@export var id: StringName = &""
@export var display_name_key: StringName = &""
@export var enabled: bool = true
@export var level_xp_requirements: Array[int] = [20, 40, 80, 160]
@export var level_speed_multipliers: Array[float] = [1.0, 1.1, 1.25, 1.45, 1.7]
@export var bonus_every_n_cycles: int = 0
@export var animation_key: StringName = &""
