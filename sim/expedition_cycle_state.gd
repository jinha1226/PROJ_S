class_name ExpeditionCycleState
extends RefCounted

const SCHEMA_VERSION := 1
const RULESET_ID := "town-dungeon-cycle-v1"
const PHASES := ["TOWN", "DUNGEON"]
const RETURN_REASONS := ["NONE", "TIME_LIMIT"]
const MAX_WORLD_TIME := 9223372036854775707
const MAX_FLOOR_INDEX := 15
const Int64CodecScript = preload("res://sim/int64_codec.gd")

var schema_version := SCHEMA_VERSION
var phase := "TOWN"
var expedition_index := 0
var floor_index := 1
var opened_at_world_time := 0
var closes_at_world_time := 0
var returned_at_world_time := 0
var return_reason := "NONE"


static func active(floor: int, opened_at: int, duration: int,
		expedition_number: int = 1):
	var state = load("res://sim/expedition_cycle_state.gd").new()
	if floor < 1 or floor > MAX_FLOOR_INDEX or opened_at < 0 \
			or duration < 1 or opened_at > MAX_WORLD_TIME - duration \
			or expedition_number < 1:
		return null
	state.phase = "DUNGEON"
	state.expedition_index = expedition_number
	state.floor_index = floor
	state.opened_at_world_time = opened_at
	state.closes_at_world_time = opened_at + duration
	state.returned_at_world_time = -1
	state.return_reason = "NONE"
	return state


static func legacy_active():
	# Pre-cycle snapshots represent an expedition already in progress. Give them
	# effectively unlimited remaining time so loading an old save never forces an
	# unexplained immediate return to town.
	return active(1, 0, MAX_WORLD_TIME, 1)


func auto_return_if_due(now: int) -> bool:
	if phase != "DUNGEON" or now < closes_at_world_time:
		return false
	phase = "TOWN"
	returned_at_world_time = now
	return_reason = "TIME_LIMIT"
	return true


func status(now: int) -> Dictionary:
	var duration := maxi(0, closes_at_world_time - opened_at_world_time)
	var remaining := maxi(0, closes_at_world_time - now) if phase == "DUNGEON" else 0
	var warning_band := "TOWN"
	if phase == "DUNGEON":
		warning_band = "CLOSED" if remaining <= 0 else "OPEN"
		if remaining > 0 and remaining * 10 <= duration:
			warning_band = "CRITICAL"
		elif remaining > 0 and remaining * 4 <= duration:
			warning_band = "WARNING"
	return {"schema_version":SCHEMA_VERSION,"ruleset_id":RULESET_ID,
		"phase":phase,"expedition_index":expedition_index,
		"floor_index":floor_index,"opened_at_world_time":opened_at_world_time,
		"closes_at_world_time":closes_at_world_time,
		"returned_at_world_time":returned_at_world_time,
		"return_reason":return_reason,"duration":duration,
		"remaining_world_time":remaining,"warning_band":warning_band}.duplicate(true)


func to_dict() -> Dictionary:
	return {"schema_version":schema_version,"ruleset_id":RULESET_ID,
		"phase":phase,"expedition_index":expedition_index,
		"floor_index":floor_index,
		"opened_at_world_time":str(opened_at_world_time),
		"closes_at_world_time":str(closes_at_world_time),
		"returned_at_world_time":str(returned_at_world_time),
		"return_reason":return_reason}.duplicate(true)


static func from_dict(row: Dictionary):
	if not wire_error(row).is_empty(): return null
	var state = load("res://sim/expedition_cycle_state.gd").new()
	state.schema_version = int(row.schema_version)
	state.phase = str(row.phase)
	state.expedition_index = int(row.expedition_index)
	state.floor_index = int(row.floor_index)
	state.opened_at_world_time = Int64CodecScript.parse(
		row.opened_at_world_time, "expedition opened time")
	state.closes_at_world_time = Int64CodecScript.parse(
		row.closes_at_world_time, "expedition close time")
	state.returned_at_world_time = Int64CodecScript.parse(
		row.returned_at_world_time, "expedition return time")
	state.return_reason = str(row.return_reason)
	return state


static func wire_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_expedition_cycle_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["closes_at_world_time", "expedition_index", "floor_index",
			"opened_at_world_time", "phase", "return_reason",
			"returned_at_world_time", "ruleset_id", "schema_version"]:
		return "invalid_expedition_cycle_keys"
	if not _integer(row.get("schema_version")) \
			or int(row.schema_version) != SCHEMA_VERSION:
		return "unsupported_expedition_cycle_schema"
	if row.get("ruleset_id") != RULESET_ID or row.get("phase") not in PHASES \
			or row.get("return_reason") not in RETURN_REASONS:
		return "unknown_expedition_cycle_enum"
	if not _integer(row.get("expedition_index")) \
			or not _integer(row.get("floor_index")):
		return "invalid_expedition_cycle_scalar"
	for key in ["opened_at_world_time", "closes_at_world_time",
			"returned_at_world_time"]:
		if not Int64CodecScript.is_canonical(row.get(key)):
			return "noncanonical_expedition_cycle_time"
	var expedition_number := int(row.expedition_index)
	var floor := int(row.floor_index)
	var opened := Int64CodecScript.parse(row.opened_at_world_time,
		"expedition opened time")
	var closes := Int64CodecScript.parse(row.closes_at_world_time,
		"expedition close time")
	var returned := Int64CodecScript.parse(row.returned_at_world_time,
		"expedition return time")
	if floor < 1 or floor > MAX_FLOOR_INDEX or expedition_number < 0 \
			or opened < 0 or closes < 0 or closes > MAX_WORLD_TIME \
			or returned < -1 or returned > MAX_WORLD_TIME:
		return "invalid_expedition_cycle_scalar"
	if row.phase == "DUNGEON":
		if expedition_number < 1 or closes <= opened or returned != -1 \
				or row.return_reason != "NONE":
			return "invalid_active_expedition_cycle"
	elif expedition_number == 0:
		if opened != 0 or closes != 0 or returned != 0 \
				or row.return_reason != "NONE":
			return "invalid_initial_town_cycle"
	elif closes <= opened or returned < closes or row.return_reason != "TIME_LIMIT":
		return "invalid_returned_expedition_cycle"
	return ""


static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))
