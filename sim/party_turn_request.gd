class_name PartyTurnRequest
extends RefCounted

const ActionScript = preload("res://sim/party_action_command.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")

var protagonist_action
var overrides: Array = []

func _init(p_action = null, p_overrides: Array = []) -> void:
	protagonist_action = _canonical_action_copy(p_action)
	for row in p_overrides:
		if not row is Dictionary:
			overrides.append({"actor_id":-1,"action":null})
			continue
		overrides.append({"actor_id": int(row.get("actor_id", -1)),
			"action": _canonical_action_copy(row.get("action"))})
	overrides.sort_custom(func(a, b): return int(a.actor_id) < int(b.actor_id))

func to_dict() -> Dictionary:
	var rows: Array = []
	for row in overrides: rows.append({"actor_id": str(row.actor_id), "action": row.action.to_dict()})
	return {"protagonist_action": protagonist_action.to_dict(), "overrides": rows}

static func from_dict(row: Variant):
	if not wire_error(row).is_empty():
		return null
	var direct = ActionScript.from_dict(row.protagonist_action)
	var parsed_overrides: Array = []
	for override_row in row.overrides:
		parsed_overrides.append({
			"actor_id": Int64CodecScript.parse(override_row.actor_id, "party override actor"),
			"action": ActionScript.from_dict(override_row.action),
		})
	return load("res://sim/party_turn_request.gd").new(direct, parsed_overrides)

static func wire_error(row: Variant) -> String:
	if not row is Dictionary:
		return "invalid_party_request_shape"
	var keys: Array = row.keys()
	keys.sort()
	if keys != ["overrides", "protagonist_action"]:
		return "invalid_party_request_keys"
	var direct_error := ActionScript.wire_error(row.get("protagonist_action"))
	if not direct_error.is_empty():
		return direct_error
	if not row.get("overrides") is Array or row.overrides.size() > 63:
		return "invalid_party_overrides_shape"
	var previous_id := 0
	for override_row in row.overrides:
		if not override_row is Dictionary:
			return "invalid_party_override_shape"
		var override_keys: Array = override_row.keys()
		override_keys.sort()
		if override_keys != ["action", "actor_id"]:
			return "invalid_party_override_keys"
		if not Int64CodecScript.is_canonical(override_row.get("actor_id")):
			return "noncanonical_party_override_actor"
		var actor_id := Int64CodecScript.parse(override_row.actor_id, "party override actor")
		if actor_id <= previous_id:
			return "duplicate_or_unsorted_override"
		var action_error := ActionScript.wire_error(override_row.get("action"))
		if not action_error.is_empty():
			return action_error
		if override_row.action.actor_id != override_row.actor_id:
			return "override_actor_mismatch"
		previous_id = actor_id
	return ""

static func _canonical_action_copy(action: Variant):
	if action == null or not action is PartyActionCommand: return null
	return ActionScript.from_dict(action.to_dict())
