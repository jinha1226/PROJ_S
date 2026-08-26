class_name RoutineStep
extends RefCounted

var skill_id: StringName = &""
var job_id: StringName = &""
var target_id: StringName = &""
var order: int = 0
var enabled: bool = true
var blocked_reason: StringName = &""


func _init(
	p_skill_id: StringName = &"",
	p_job_id: StringName = &"",
	p_target_id: StringName = &"",
	p_order: int = 0
) -> void:
	skill_id = p_skill_id
	job_id = p_job_id
	target_id = p_target_id
	order = p_order


func to_dict() -> Dictionary:
	return {
		"skill_id": str(skill_id),
		"job_id": str(job_id),
		"target_id": str(target_id),
		"order": order,
		"enabled": enabled,
		"blocked_reason": str(blocked_reason),
	}


static func from_dict(data: Dictionary) -> RoutineStep:
	var step := RoutineStep.new(
		StringName(str(data.get("skill_id", ""))),
		StringName(str(data.get("job_id", ""))),
		StringName(str(data.get("target_id", ""))),
		int(data.get("order", 0))
	)
	step.enabled = bool(data.get("enabled", true))
	step.blocked_reason = StringName(str(data.get("blocked_reason", "")))
	return step


func clone_state() -> RoutineStep:
	return RoutineStep.from_dict(to_dict())
