class_name SimStepResult
extends RefCounted

var accepted: bool
var consumes_time: bool
var reason: String
var events: Array
var timeline: Array
var processed_step_index: int
var start_time: int
var end_time: int
var time_cost: int
var speed_tier: String
var root_event_id: int


func _init(
		p_accepted: bool,
		p_consumes_time: bool,
		p_reason: String = "",
		p_events: Array = [],
		p_data: Dictionary = {}
	) -> void:
	accepted = p_accepted
	consumes_time = p_consumes_time
	reason = p_reason
	events = []
	for event in p_events:
		events.append(event.detached_copy())
	timeline = p_data.get("timeline", []).duplicate(true)
	processed_step_index = p_data.get("processed_step_index", 0)
	start_time = p_data.get("start_time", 0)
	end_time = p_data.get("end_time", start_time)
	time_cost = p_data.get("time_cost", 0)
	speed_tier = p_data.get("speed_tier", "")
	root_event_id = p_data.get("root_event_id", -1)
