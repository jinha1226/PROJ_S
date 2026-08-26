class_name JobDefinition
extends Resource

@export var id: StringName = &""
@export var display_name_key: StringName = &""
@export var enabled: bool = true
@export var required_skill_id: StringName = &""
@export var job_kind: StringName = &"PRODUCTION"
@export var allowed_target_tags: Array[StringName] = []
@export var base_duration_ticks: int = 10
@export var movement_duration_ticks: int = 5
@export var inputs: Dictionary = {}
@export var outputs: Dictionary = {}
@export var passive_xp: int = 1
@export var normal_coaching_progress_ratio: float = 0.15
@export var normal_coaching_xp: int = 1
@export var perfect_window_ticks: int = 8
@export var perfect_coaching_xp: int = 3
@export var min_duration_ticks: int = 15
