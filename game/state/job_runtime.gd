class_name JobRuntime
extends RefCounted

const IDLE := &"IDLE"
const MOVING := &"MOVING"
const WORKING := &"WORKING"
const BLOCKED := &"BLOCKED"
const BLOCKED_OUTPUT := &"BLOCKED_OUTPUT"

var slime_id: StringName = &""
var job_id: StringName = &""
var target_id: StringName = &""
var phase: StringName = IDLE
var cycle_id: int = 0
var elapsed_ticks: int = 0
var duration_ticks: int = 0
var movement_ticks: int = 0
var coaching_used: bool = false
var completion_requested: bool = false
var blocked_reason: StringName = &""
var reservation_id: StringName = &""


func _init(p_slime_id: StringName = &"") -> void:
	slime_id = p_slime_id


func to_dict() -> Dictionary:
	return {
		"slime_id": str(slime_id),
		"job_id": str(job_id),
		"target_id": str(target_id),
		"phase": str(phase),
		"cycle_id": cycle_id,
		"elapsed_ticks": elapsed_ticks,
		"duration_ticks": duration_ticks,
		"movement_ticks": movement_ticks,
		"coaching_used": coaching_used,
		"completion_requested": completion_requested,
		"blocked_reason": str(blocked_reason),
		"reservation_id": str(reservation_id),
	}


static func from_dict(data: Dictionary) -> JobRuntime:
	var runtime := JobRuntime.new(StringName(str(data.get("slime_id", ""))))
	runtime.job_id = StringName(str(data.get("job_id", "")))
	runtime.target_id = StringName(str(data.get("target_id", "")))
	runtime.phase = StringName(str(data.get("phase", "IDLE")))
	runtime.cycle_id = int(data.get("cycle_id", 0))
	runtime.elapsed_ticks = int(data.get("elapsed_ticks", 0))
	runtime.duration_ticks = int(data.get("duration_ticks", 0))
	runtime.movement_ticks = int(data.get("movement_ticks", 0))
	runtime.coaching_used = bool(data.get("coaching_used", false))
	runtime.completion_requested = bool(data.get("completion_requested", false))
	runtime.blocked_reason = StringName(str(data.get("blocked_reason", "")))
	runtime.reservation_id = StringName(str(data.get("reservation_id", "")))
	return runtime


func clone_state() -> JobRuntime:
	return JobRuntime.from_dict(to_dict())
