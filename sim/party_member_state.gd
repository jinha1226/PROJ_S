class_name PartyMemberState
extends RefCounted

const ROLES := ["PROTAGONIST", "COMPANION"]
const PRESENCES := ["DEPLOYED", "GROUPED", "DORMANT", "RECRUITABLE", "EXILED", "DEFEATED"]
const MENTAL_MODES := ["NORMAL", "PANIC"]
const Int64CodecScript = preload("res://sim/int64_codec.gd")
const PersonalityProfileScript = preload("res://sim/personality_profile.gd")
const HexacoProfileScript = preload("res://sim/dungeon_population/hexaco_profile.gd")
const EmotionStateScript = preload("res://sim/party_emotion_state.gd")
const MAX_WORLD_TIME := 9223372036854775707

var entity_id: int
var roster_slot: int
var role: String
var presence: String
var busy_until: int
var stress: int
var mental_mode: String
var personality_profile = null
var emotion_state

func _init(p_entity_id: int = -1, p_slot: int = -1, p_role: String = "COMPANION",
		p_presence: String = "GROUPED", p_profile = null) -> void:
	entity_id = p_entity_id
	roster_slot = p_slot
	role = p_role
	presence = p_presence
	personality_profile = p_profile
	busy_until = 0
	stress = 0
	mental_mode = "NORMAL"
	emotion_state = EmotionStateScript.new()

func to_dict(include_emotion_state: bool = true) -> Dictionary:
	var row := {"entity_id": str(entity_id), "roster_slot": roster_slot, "role": role,
		"presence": presence, "busy_until": str(busy_until), "stress": stress,
		"mental_mode": mental_mode,
		"personality_profile": null if personality_profile == null else personality_profile.to_dict()}
	if include_emotion_state:
		row["emotion_state"] = emotion_state.to_dict()
	return row

static func from_dict(row: Dictionary):
	var profile = null
	if row.personality_profile != null:
		profile = HexacoProfileScript.from_dict(row.personality_profile) \
			if HexacoProfileScript.wire_error(row.personality_profile).is_empty() \
			else PersonalityProfileScript.from_dict(row.personality_profile)
	var state = load("res://sim/party_member_state.gd").new(
		Int64CodecScript.parse(row.entity_id, "party member ID"), int(row.roster_slot),
		str(row.role), str(row.presence), profile)
	state.busy_until = Int64CodecScript.parse(row.busy_until, "party busy time")
	state.stress = int(row.stress)
	# v1-v13 had stress but no hysteresis memory. Their pre-P3 behavior entered
	# panic only at the upper threshold, so migration preserves that baseline.
	state.mental_mode = str(row.get("mental_mode",
		"PANIC" if state.stress >= 850 else "NORMAL"))
	state.emotion_state = EmotionStateScript.from_dict(row.emotion_state) \
		if row.get("emotion_state") is Dictionary else EmotionStateScript.new()
	return state

static func wire_error(row: Variant, require_mental_mode: bool = true,
		require_hexaco: bool = true, require_emotion_state: bool = true) -> String:
	if not row is Dictionary: return "invalid_party_member_shape"
	var keys: Array = row.keys(); keys.sort()
	var expected := ["busy_until", "entity_id", "mental_mode", "personality_profile",
		"presence", "role", "roster_slot", "stress"] if require_mental_mode else [
		"busy_until", "entity_id", "personality_profile", "presence", "role",
		"roster_slot", "stress"]
	if require_emotion_state:
		expected.append("emotion_state")
		expected.sort()
	if keys != expected:
		return "invalid_party_member_keys"
	if not Int64CodecScript.is_canonical(row.get("entity_id")) or Int64CodecScript.parse(row.entity_id, "member") <= 0:
		return "noncanonical_party_member_id"
	if not _integer(row.get("roster_slot")) or int(row.roster_slot) < 0 or int(row.roster_slot) > 63:
		return "invalid_roster_slot"
	if row.get("role") not in ROLES or row.get("presence") not in PRESENCES:
		return "unknown_party_member_enum"
	if not Int64CodecScript.is_canonical(row.get("busy_until")) or Int64CodecScript.parse(row.busy_until, "busy") < 0 \
			or Int64CodecScript.parse(row.busy_until, "busy") > MAX_WORLD_TIME:
		return "noncanonical_party_busy_until"
	if not _integer(row.get("stress")) or int(row.stress) < 0 or int(row.stress) > 1000:
		return "invalid_party_stress"
	if require_mental_mode and row.get("mental_mode") not in MENTAL_MODES:
		return "unknown_party_mental_mode"
	if require_emotion_state:
		var emotion_error := EmotionStateScript.wire_error(row.get("emotion_state"))
		if not emotion_error.is_empty():
			return emotion_error
	if row.role == "PROTAGONIST":
		if row.personality_profile != null: return "protagonist_personality_forbidden"
	else:
		var profile_error := HexacoProfileScript.wire_error(row.personality_profile) \
			if require_hexaco else _legacy_profile_wire_error(row.personality_profile)
		if not profile_error.is_empty(): return profile_error
	return ""

static func _legacy_profile_wire_error(row: Variant) -> String:
	if HexacoProfileScript.wire_error(row).is_empty():
		return ""
	return load("res://sim/personality_definition_registry.gd").profile_wire_error(row)

static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))
