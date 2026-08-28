class_name CombatStatusRegistry
extends RefCounted

const RULESET_ID := "bounded-status-lifecycle-v1"
const STATUS_KEYS := ["stacking", "status_id", "tick_count_after_apply_or_refresh", "tick_damage", "tick_interval"]
const STATUSES := {
	"BLEEDING": {"status_id":"BLEEDING", "tick_interval":100, "tick_damage":3,
		"tick_count_after_apply_or_refresh":3, "stacking":"NONE"},
}

static func has(status_id: String) -> bool:
	return STATUSES.has(status_id) and status_error(STATUSES[status_id]).is_empty()

static func definition(status_id: String) -> Dictionary:
	return STATUSES[status_id].duplicate(true) if has(status_id) else {}

static func registry_error() -> String:
	for status_id in STATUSES:
		if str(STATUSES[status_id].get("status_id", "")) != status_id: return "status_registry_key_mismatch"
		var error := status_error(STATUSES[status_id])
		if not error.is_empty(): return error
	return ""

static func status_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_status_definition_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != STATUS_KEYS: return "invalid_status_definition_keys"
	if row.status_id != "BLEEDING" or row.stacking != "NONE" \
			or row.tick_interval != 100 or row.tick_damage != 3 \
			or row.tick_count_after_apply_or_refresh != 3:
		return "invalid_status_definition"
	return ""
