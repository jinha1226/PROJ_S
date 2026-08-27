class_name SimActionPreview
extends RefCounted

var accepted: bool
var reason: String
var processed_step_index: int
var start_time: int
var end_time: int
var time_cost: int
var speed_tier: String
var calendar_start: Dictionary
var calendar_end: Dictionary
var timeline: Array


func _init(p_data: Dictionary) -> void:
	accepted = p_data.get("accepted", false)
	reason = p_data.get("reason", "")
	processed_step_index = p_data.get("processed_step_index", -1)
	start_time = p_data.get("start_time", 0)
	end_time = p_data.get("end_time", start_time)
	time_cost = p_data.get("time_cost", 0)
	speed_tier = p_data.get("speed_tier", "")
	calendar_start = p_data.get("calendar_start", {}).duplicate(true)
	calendar_end = p_data.get("calendar_end", {}).duplicate(true)
	timeline = p_data.get("timeline", []).duplicate(true)


func to_dict() -> Dictionary:
	return {
		"accepted": accepted,
		"reason": reason,
		"processed_step_index": processed_step_index,
		"start_time": start_time,
		"end_time": end_time,
		"time_cost": time_cost,
		"speed_tier": speed_tier,
		"calendar_start": calendar_start.duplicate(true),
		"calendar_end": calendar_end.duplicate(true),
		"timeline": timeline.duplicate(true),
	}
