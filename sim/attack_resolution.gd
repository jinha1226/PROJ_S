class_name AttackResolution
extends RefCounted

# Detached kernel result. Event IDs are attached later by the coordinator.
var outcome: String
var hit_roll_milli: int
var bleed_roll_milli: int
var parry_roll_milli: int
var parry_succeeded: bool
var bleed_proc_succeeded: bool
var final_damage: int
var action_data: Dictionary
var target_health_before: int
var target_life_before: String
var target_health_after: int
var target_life_after: String
var terminal_immediate: bool


func _init(data: Dictionary = {}) -> void:
	outcome = str(data.get("outcome", ""))
	hit_roll_milli = int(data.get("hit_roll_milli", -1))
	bleed_roll_milli = int(data.get("bleed_roll_milli", -1))
	parry_roll_milli = int(data.get("parry_roll_milli", -1))
	parry_succeeded = bool(data.get("parry_succeeded", false))
	bleed_proc_succeeded = bool(data.get("bleed_proc_succeeded", false))
	final_damage = int(data.get("final_damage", 0))
	action_data = data.get("action_data", {}).duplicate(true)
	target_health_before = int(data.get("target_health_before", -1))
	target_life_before = str(data.get("target_life_before", ""))
	target_health_after = int(data.get("target_health_after", -1))
	target_life_after = str(data.get("target_life_after", ""))
	terminal_immediate = bool(data.get("terminal_immediate", false))


func detached_copy():
	return load("res://sim/attack_resolution.gd").new({
		"outcome": outcome,
		"hit_roll_milli": hit_roll_milli,
		"bleed_roll_milli": bleed_roll_milli,
		"parry_roll_milli": parry_roll_milli,
		"parry_succeeded": parry_succeeded,
		"bleed_proc_succeeded": bleed_proc_succeeded,
		"final_damage": final_damage,
		"action_data": action_data,
		"target_health_before": target_health_before,
		"target_life_before": target_life_before,
		"target_health_after": target_health_after,
		"target_life_after": target_life_after,
		"terminal_immediate": terminal_immediate,
	})
