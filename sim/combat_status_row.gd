class_name CombatStatusRow
extends RefCounted

const SCHEMA_VERSION := 1
const Int64CodecScript = preload("res://sim/int64_codec.gd")
const StatusRegistryScript = preload("res://sim/status_registry.gd")
const KEYS := ["applied_at", "expires_at", "next_tick_at", "refreshed_at", "schema_version", "source_event_id", "status_id"]
const MAX_WORLD_TIME := 9223372036854775707

var status_id := "BLEEDING"
var applied_at: int = 0
var refreshed_at: int = 0
var next_tick_at: int = 100
var expires_at: int = 300
var source_event_id: int = -1

func _init(p_status_id: String = "BLEEDING") -> void: status_id = p_status_id

func to_dict() -> Dictionary:
	return {"schema_version":SCHEMA_VERSION, "status_id":status_id,
		"applied_at":str(applied_at), "refreshed_at":str(refreshed_at),
		"next_tick_at":str(next_tick_at), "expires_at":str(expires_at),
		"source_event_id":str(source_event_id)}

static func from_dict(row: Dictionary):
	var state = load("res://sim/combat_status_row.gd").new(str(row.status_id))
	for key in ["applied_at", "refreshed_at", "next_tick_at", "expires_at", "source_event_id"]:
		state.set(key, Int64CodecScript.parse(row[key], key))
	return state

static func wire_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_combat_status_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != KEYS: return "invalid_combat_status_keys"
	if row.get("schema_version") != SCHEMA_VERSION: return "unsupported_combat_status_schema"
	if not row.get("status_id") is String or not StatusRegistryScript.has(str(row.status_id)):
		return "unknown_status_id"
	for key in ["applied_at", "refreshed_at", "next_tick_at", "expires_at", "source_event_id"]:
		if not Int64CodecScript.is_canonical(row.get(key)): return "noncanonical_status_%s" % key
	var applied := Int64CodecScript.parse(row.applied_at, "applied at")
	var refreshed := Int64CodecScript.parse(row.refreshed_at, "refreshed at")
	var next_tick := Int64CodecScript.parse(row.next_tick_at, "next tick")
	var expires := Int64CodecScript.parse(row.expires_at, "expires")
	var source := Int64CodecScript.parse(row.source_event_id, "status source")
	if applied < 0 or refreshed < applied or refreshed > MAX_WORLD_TIME \
			or next_tick <= refreshed or next_tick > MAX_WORLD_TIME \
			or expires < next_tick or expires > MAX_WORLD_TIME or source <= 0:
		return "invalid_combat_status_time_or_source"
	if next_tick % 100 != 0 or expires % 100 != 0 or (expires - next_tick) % 100 != 0:
		return "invalid_combat_status_cadence"
	return ""
