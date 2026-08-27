class_name ActivityTimingTable
extends RefCounted

const RULESET_ID := "activity-timing-v1"
const COSTS := {"WORK": 100, "EAT": 300, "REST": 300, "SOCIALIZE": 100, "IDLE": 100}


static func cost(activity: String) -> int:
	return int(COSTS.get(activity, 0))
