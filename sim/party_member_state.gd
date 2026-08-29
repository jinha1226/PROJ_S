class_name PartyMemberState
extends RefCounted

const ROLES := ["PROTAGONIST", "COMPANION"]
const PRESENCES := ["DEPLOYED", "GROUPED", "DORMANT", "RECRUITABLE", "EXILED", "DEFEATED"]
const Int64CodecScript = preload("res://sim/int64_codec.gd")
const PersonalityRegistryScript = preload("res://sim/personality_definition_registry.gd")
const PersonalityProfileScript = preload("res://sim/personality_profile.gd")
const MAX_WORLD_TIME := 9223372036854775707

var entity_id: int
var roster_slot: int
var role: String
var presence: String
var busy_until: int
var stress: int
var personality_profile = null

func _init(p_entity_id: int = -1, p_slot: int = -1, p_role: String = "COMPANION",
		p_presence: String = "GROUPED", p_profile = null) -> void:
	entity_id = p_entity_id
	roster_slot = p_slot
	role = p_role
	presence = p_presence
	personality_profile = p_profile
	busy_until = 0
	stress = 0

func to_dict() -> Dictionary:
	return {"entity_id": str(entity_id), "roster_slot": roster_slot, "role": role,
		"presence": presence, "busy_until": str(busy_until), "stress": stress,
		"personality_profile": null if personality_profile == null else personality_profile.to_dict()}

static func from_dict(row: Dictionary):
	var profile = null if row.personality_profile == null else PersonalityProfileScript.from_dict(row.personality_profile)
	var state = load("res://sim/party_member_state.gd").new(
		Int64CodecScript.parse(row.entity_id, "party member ID"), int(row.roster_slot),
		str(row.role), str(row.presence), profile)
	state.busy_until = Int64CodecScript.parse(row.busy_until, "party busy time")
	state.stress = int(row.stress)
	return state

static func wire_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_party_member_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["busy_until", "entity_id", "personality_profile", "presence", "role", "roster_slot", "stress"]:
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
	if row.role == "PROTAGONIST":
		if row.personality_profile != null: return "protagonist_personality_forbidden"
	else:
		var profile_error := PersonalityRegistryScript.profile_wire_error(row.personality_profile)
		if not profile_error.is_empty(): return profile_error
	return ""

static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))
