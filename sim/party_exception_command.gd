class_name PartyExceptionCommand
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")

const RULESET_ID := "party-exception-command-v1"
const COMMAND_IDS := ["ATTACK_TARGET", "RETREAT", "STOP_ATTACK",
	"HOLD_POSITION", "FOLLOW"]


static func event_data(command_id: String, target_id: int) -> Dictionary:
	return {
		"schema_version": 1,
		"ruleset_id": RULESET_ID,
		"command_id": command_id,
		"target_id": str(target_id),
	}


static func data_error(value: Variant) -> String:
	if not value is Dictionary:
		return "invalid_party_command_data"
	var keys: Array = value.keys(); keys.sort()
	if keys != ["command_id", "ruleset_id", "schema_version", "target_id"] \
			or value.get("schema_version") != 1 \
			or value.get("ruleset_id") != RULESET_ID \
			or value.get("command_id") not in COMMAND_IDS \
			or not Int64CodecScript.is_canonical(value.get("target_id")):
		return "invalid_party_command_data"
	var target_id := Int64CodecScript.parse(value.target_id, "party command target")
	if (str(value.command_id) == "ATTACK_TARGET" and target_id <= 0) \
			or (str(value.command_id) != "ATTACK_TARGET" and target_id != -1):
		return "invalid_party_command_target"
	return ""


static func effective(world, state) -> Dictionary:
	var fallback := {
		"command_id": "FOLLOW",
		"target_id": -1,
		"anchor": [world.entities[state.protagonist_id].position.x,
			world.entities[state.protagonist_id].position.y],
		"explicit": false,
		"event_id": -1,
	}
	for event_index in range(world.events.size() - 1, -1, -1):
		var event = world.events[event_index]
		if event.type == "party.regroup_completed":
			break
		if event.type != "party.command_issued" \
				or not data_error(event.data).is_empty():
			continue
		var command_id := str(event.data.command_id)
		var target_id := Int64CodecScript.parse(event.data.target_id,
			"party command target")
		if command_id == "ATTACK_TARGET" \
				and (not world.entities.has(target_id) \
				or not world.is_autonomous_target(target_id)):
			return fallback
		return {
			"command_id": command_id,
			"target_id": target_id,
			"anchor": [event.position.x, event.position.y],
			"explicit": true,
			"event_id": int(event.id),
		}
	return fallback


static func label_ko(command_id: String) -> String:
	return {
		"ATTACK_TARGET": "공격 대상 지정",
		"RETREAT": "후퇴",
		"STOP_ATTACK": "공격 중지",
		"HOLD_POSITION": "자리 지키기",
		"FOLLOW": "따라오기",
	}.get(command_id, command_id)
