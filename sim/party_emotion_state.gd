class_name PartyEmotionState
extends RefCounted

const SCHEMA_VERSION := 1
const EMOTION_IDS := ["FEAR", "ANGER", "SADNESS", "GUILT", "BOND", "RESOLVE"]
const CAUSE_CODES := ["NONE", "SELF_DAMAGE", "SELF_DOWNED", "ALLY_DOWNED",
	"ALLY_DIED", "ENEMY_DIED", "OVERRIDE_CONFLICT", "ALLY_AID",
	"SAFE_DECAY", "TOWN_REST"]
const Int64CodecScript = preload("res://sim/int64_codec.gd")
const MAX_WORLD_TIME := 9223372036854775707

var updated_at: int = 0
var channels: Dictionary = {}


func _init(p_updated_at: int = 0) -> void:
	updated_at = p_updated_at
	for emotion_id in EMOTION_IDS:
		channels[emotion_id] = _empty_channel(emotion_id)


func intensity(emotion_id: String) -> int:
	return int(channels.get(emotion_id, {}).get("intensity", 0))


func target_id(emotion_id: String) -> int:
	return int(channels.get(emotion_id, {}).get("target_id", -1))


func source_event_id(emotion_id: String) -> int:
	return int(channels.get(emotion_id, {}).get("source_event_id", -1))


func cause_code(emotion_id: String) -> String:
	return str(channels.get(emotion_id, {}).get("cause_code", "NONE"))


func set_channel(emotion_id: String, value: int, target: int = -1,
		source_event: int = -1, cause: String = "NONE") -> void:
	if emotion_id not in EMOTION_IDS:
		return
	var checked := clampi(value, 0, 1000)
	channels[emotion_id] = _empty_channel(emotion_id) if checked == 0 else {
		"emotion_id": emotion_id,
		"intensity": checked,
		"target_id": target,
		"source_event_id": source_event,
		"cause_code": cause,
	}


func dominant(limit: int = 2, minimum: int = 1) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for emotion_id in EMOTION_IDS:
		var row: Dictionary = channels[emotion_id]
		if int(row.intensity) >= minimum:
			rows.append(row.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.intensity) != int(b.intensity):
			return int(a.intensity) > int(b.intensity)
		return EMOTION_IDS.find(str(a.emotion_id)) < EMOTION_IDS.find(str(b.emotion_id)))
	return rows.slice(0, clampi(limit, 0, EMOTION_IDS.size()))


func to_dict() -> Dictionary:
	var rows: Array[Dictionary] = []
	for emotion_id in EMOTION_IDS:
		var channel: Dictionary = channels.get(emotion_id, _empty_channel(emotion_id))
		rows.append({"emotion_id":emotion_id, "intensity":int(channel.intensity),
			"target_id":str(int(channel.target_id)),
			"source_event_id":str(int(channel.source_event_id)),
			"cause_code":str(channel.cause_code)})
	return {"schema_version":SCHEMA_VERSION, "updated_at":str(updated_at),
		"channels":rows}


static func from_dict(row: Dictionary):
	var state = load("res://sim/party_emotion_state.gd").new(
		Int64CodecScript.parse(row.get("updated_at", "0"), "emotion updated time"))
	for channel_value in row.get("channels", []):
		var channel: Dictionary = channel_value
		state.set_channel(str(channel.emotion_id), int(channel.intensity),
			Int64CodecScript.parse(channel.target_id, "emotion target"),
			Int64CodecScript.parse(channel.source_event_id, "emotion source"),
			str(channel.cause_code))
	return state


static func wire_error(row: Variant) -> String:
	if not row is Dictionary:
		return "invalid_party_emotion_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["channels", "schema_version", "updated_at"] \
			or row.get("schema_version") != SCHEMA_VERSION \
			or not Int64CodecScript.is_canonical(row.get("updated_at")):
		return "invalid_party_emotion_header"
	var parsed_time := Int64CodecScript.parse(row.updated_at, "emotion updated time")
	if parsed_time < 0 or parsed_time > MAX_WORLD_TIME:
		return "invalid_party_emotion_time"
	if not row.get("channels") is Array or row.channels.size() != EMOTION_IDS.size():
		return "invalid_party_emotion_channels"
	for index in range(EMOTION_IDS.size()):
		var channel: Variant = row.channels[index]
		if not channel is Dictionary:
			return "invalid_party_emotion_channel"
		var channel_keys: Array = channel.keys(); channel_keys.sort()
		if channel_keys != ["cause_code", "emotion_id", "intensity",
				"source_event_id", "target_id"] \
				or channel.get("emotion_id") != EMOTION_IDS[index] \
				or not _integer(channel.get("intensity")) \
				or int(channel.intensity) < 0 or int(channel.intensity) > 1000 \
				or not Int64CodecScript.is_canonical(channel.get("target_id")) \
				or not Int64CodecScript.is_canonical(channel.get("source_event_id")) \
				or channel.get("cause_code") not in CAUSE_CODES:
			return "invalid_party_emotion_channel"
		var target := Int64CodecScript.parse(channel.target_id, "emotion target")
		var source := Int64CodecScript.parse(channel.source_event_id, "emotion source")
		if target < -1 or source < -1 \
				or (int(channel.intensity) == 0 and (target != -1 or source != -1 \
					or str(channel.cause_code) != "NONE")) \
				or (int(channel.intensity) > 0 and str(channel.cause_code) == "NONE"):
			return "invalid_party_emotion_channel"
	return ""


static func _empty_channel(emotion_id: String) -> Dictionary:
	return {"emotion_id":emotion_id, "intensity":0, "target_id":-1,
		"source_event_id":-1, "cause_code":"NONE"}


static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))
