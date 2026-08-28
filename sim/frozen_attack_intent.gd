class_name FrozenAttackIntent
extends RefCounted

# Transient commit-only value object. It deliberately has no snapshot codec.
var assessment: Dictionary
var target_health_at_batch_start: int
var original_action_order: int
var world_seed: int
var protagonist_terminal_if_lethal: bool


func _init(p_assessment: Dictionary, p_target_health_at_batch_start: int,
		p_original_action_order: int, p_world_seed: int = 0,
		p_protagonist_terminal_if_lethal: bool = false) -> void:
	assessment = p_assessment.duplicate(true)
	target_health_at_batch_start = p_target_health_at_batch_start
	original_action_order = p_original_action_order
	world_seed = p_world_seed
	protagonist_terminal_if_lethal = p_protagonist_terminal_if_lethal


func detached_copy():
	return load("res://sim/frozen_attack_intent.gd").new(
		assessment, target_health_at_batch_start, original_action_order, world_seed,
		protagonist_terminal_if_lethal)
