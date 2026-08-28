class_name CombatantState
extends RefCounted

const SCHEMA_VERSION := 1
const LIFE_STATES := ["ACTIVE", "DOWNED", "DEAD"]
const Int64CodecScript = preload("res://sim/int64_codec.gd")
const CombatStatusRowScript = preload("res://sim/combat_status_row.gd")
const ProfileRegistryScript = preload("res://sim/combat_profile_registry.gd")
const KEYS := ["combat_profile_id", "downed_at", "downed_resolve_at", "downed_source_event_id",
	"entity_id", "guard_source_event_id", "guarded_until", "life_state", "recovery_lock_until",
	"recovery_source_event_id", "schema_version", "status_rows"]
const MAX_WORLD_TIME := 9223372036854775707

var entity_id: int
var life_state := "ACTIVE"
var combat_profile_id: String
var guarded_until: int = 0
var guard_source_event_id: int = -1
var downed_at: int = -1
var downed_resolve_at: int = -1
var downed_source_event_id: int = -1
var recovery_lock_until: int = 0
var recovery_source_event_id: int = -1
var status_rows: Array = []

func _init(p_entity_id: int = -1, p_profile_id: String = "combatant-default-v1") -> void:
	entity_id = p_entity_id; combat_profile_id = p_profile_id

func to_dict() -> Dictionary:
	var rows: Array = []
	for status in status_rows: rows.append(status.to_dict())
	return {"schema_version":SCHEMA_VERSION, "entity_id":str(entity_id), "life_state":life_state,
		"combat_profile_id":combat_profile_id, "guarded_until":str(guarded_until),
		"guard_source_event_id":str(guard_source_event_id), "downed_at":str(downed_at),
		"downed_resolve_at":str(downed_resolve_at), "downed_source_event_id":str(downed_source_event_id),
		"recovery_lock_until":str(recovery_lock_until), "recovery_source_event_id":str(recovery_source_event_id),
		"status_rows":rows}

static func from_dict(row: Dictionary):
	var state = load("res://sim/combatant_state.gd").new(
		Int64CodecScript.parse(row.entity_id, "combatant ID"), str(row.combat_profile_id))
	state.life_state = str(row.life_state)
	for key in ["guarded_until", "guard_source_event_id", "downed_at", "downed_resolve_at",
			"downed_source_event_id", "recovery_lock_until", "recovery_source_event_id"]:
		state.set(key, Int64CodecScript.parse(row[key], key))
	for status_row in row.status_rows: state.status_rows.append(CombatStatusRowScript.from_dict(status_row))
	return state

static func wire_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_combatant_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != KEYS: return "invalid_combatant_keys"
	if row.get("schema_version") != SCHEMA_VERSION: return "unsupported_combatant_schema"
	if not Int64CodecScript.is_canonical(row.get("entity_id")) \
			or Int64CodecScript.parse(row.entity_id, "combatant ID") <= 0:
		return "noncanonical_combatant_id"
	if row.get("life_state") not in LIFE_STATES: return "unknown_life_state"
	if not row.get("combat_profile_id") is String or not ProfileRegistryScript.has(str(row.combat_profile_id)):
		return "unknown_combat_profile_id"
	for key in ["guarded_until", "guard_source_event_id", "downed_at", "downed_resolve_at",
			"downed_source_event_id", "recovery_lock_until", "recovery_source_event_id"]:
		if not Int64CodecScript.is_canonical(row.get(key)): return "noncanonical_combatant_%s" % key
	if not row.get("status_rows") is Array or row.status_rows.size() > 8: return "invalid_status_rows"
	var previous := ""
	for status_row in row.status_rows:
		var error := CombatStatusRowScript.wire_error(status_row)
		if not error.is_empty(): return error
		var status_id := str(status_row.status_id)
		if not previous.is_empty() and status_id <= previous: return "duplicate_or_unsorted_status_rows"
		previous = status_id
	return ""
