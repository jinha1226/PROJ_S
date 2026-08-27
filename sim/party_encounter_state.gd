class_name PartyEncounterState
extends RefCounted

const SCHEMA_VERSION := 1
const PHASES := ["GROUPED", "CONTACT", "ENGAGED", "REGROUP_READY", "GROUPED_COMPLETE", "PARTY_DEFEATED"]
const CONTACT_KINDS := ["NONE", "DETECTED", "PARTY_AMBUSH", "ENEMY_AMBUSH"]
const FORMATIONS := ["NONE", "WEDGE", "LINE", "COLUMN"]
const MAX_WORLD_TIME := 9223372036854775707
const MemberScript = preload("res://sim/party_member_state.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")

var schema_version := SCHEMA_VERSION
var encounter_id: int = 1
var safe_phase := "GROUPED"
var revision: int = 0
var protagonist_id: int = -1
var party_member_ids: Array[int] = []
var enemy_ids: Array[int] = []
var group_anchor := Vector2i.ZERO
var facing := Vector2i.RIGHT
var contact_kind := "NONE"
var contact_enemy_id: int = -1
var party_detection_radius := 4
var enemy_detection_radius := 3
var formation_id := "NONE"
var member_rows: Dictionary = {}
var enemy_busy_rows: Dictionary = {}

func member(entity_id: int): return member_rows.get(entity_id)

func to_dict() -> Dictionary:
	var members: Array = []
	for entity_id in party_member_ids: members.append(member_rows[entity_id].to_dict())
	var busy_rows: Array = []
	var ids: Array = enemy_busy_rows.keys(); ids.sort()
	for entity_id in ids: busy_rows.append({"entity_id": str(entity_id), "busy_until": str(enemy_busy_rows[entity_id])})
	return {"schema_version": schema_version, "encounter_id": str(encounter_id), "safe_phase": safe_phase,
		"revision": str(revision), "protagonist_id": str(protagonist_id),
		"party_member_ids": party_member_ids.map(func(id): return str(id)),
		"enemy_ids": enemy_ids.map(func(id): return str(id)), "group_anchor": [group_anchor.x, group_anchor.y],
		"facing": [facing.x, facing.y], "contact_kind": contact_kind,
		"contact_enemy_id": str(contact_enemy_id), "party_detection_radius": party_detection_radius,
		"enemy_detection_radius": enemy_detection_radius, "formation_id": formation_id,
		"member_rows": members, "enemy_busy_rows": busy_rows}

static func from_dict(row: Dictionary):
	var state = load("res://sim/party_encounter_state.gd").new()
	state.encounter_id = Int64CodecScript.parse(row.encounter_id, "encounter ID")
	state.safe_phase = str(row.safe_phase); state.revision = Int64CodecScript.parse(row.revision, "revision")
	state.protagonist_id = Int64CodecScript.parse(row.protagonist_id, "protagonist ID")
	state.party_member_ids.clear(); for value in row.party_member_ids: state.party_member_ids.append(Int64CodecScript.parse(value, "party ID"))
	state.enemy_ids.clear(); for value in row.enemy_ids: state.enemy_ids.append(Int64CodecScript.parse(value, "enemy ID"))
	state.group_anchor = Vector2i(int(row.group_anchor[0]), int(row.group_anchor[1])); state.facing = Vector2i(int(row.facing[0]), int(row.facing[1]))
	state.contact_kind = str(row.contact_kind); state.contact_enemy_id = Int64CodecScript.parse(row.contact_enemy_id, "contact enemy")
	state.party_detection_radius = int(row.party_detection_radius); state.enemy_detection_radius = int(row.enemy_detection_radius)
	state.formation_id = str(row.formation_id); state.member_rows.clear()
	for member_row in row.member_rows:
		var member = MemberScript.from_dict(member_row); state.member_rows[member.entity_id] = member
	state.enemy_busy_rows.clear(); for busy_row in row.enemy_busy_rows: state.enemy_busy_rows[Int64CodecScript.parse(busy_row.entity_id, "enemy ID")] = Int64CodecScript.parse(busy_row.busy_until, "enemy busy")
	return state

static func wire_error(row: Variant, width: int, height: int) -> String:
	if not row is Dictionary: return "invalid_party_encounter_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["contact_enemy_id", "contact_kind", "encounter_id", "enemy_busy_rows", "enemy_detection_radius", "enemy_ids", "facing", "formation_id", "group_anchor", "member_rows", "party_detection_radius", "party_member_ids", "protagonist_id", "revision", "safe_phase", "schema_version"]:
		return "invalid_party_encounter_keys"
	if row.schema_version != SCHEMA_VERSION: return "unsupported_party_schema"
	for key in ["encounter_id", "protagonist_id", "revision", "contact_enemy_id"]:
		if not Int64CodecScript.is_canonical(row.get(key)): return "noncanonical_party_%s" % key
	if Int64CodecScript.parse(row.encounter_id, "encounter") <= 0 or Int64CodecScript.parse(row.protagonist_id, "protagonist") <= 0 or Int64CodecScript.parse(row.revision, "revision") < 0:
		return "invalid_party_scalar"
	if row.safe_phase not in PHASES or row.contact_kind not in CONTACT_KINDS or row.formation_id not in FORMATIONS:
		return "unknown_party_enum"
	if not _position(row.group_anchor, width, height) or not _facing(row.facing):
		return "invalid_party_position_or_facing"
	if not _integer(row.party_detection_radius) or not _integer(row.enemy_detection_radius) or row.party_detection_radius < 0 or row.party_detection_radius > 15 or row.enemy_detection_radius < 0 or row.enemy_detection_radius > 15:
		return "invalid_detection_radius"
	for list_key in ["party_member_ids", "enemy_ids"]:
		if not row.get(list_key) is Array or row[list_key].is_empty() or row[list_key].size() > 64: return "invalid_%s" % list_key
		var previous := -1
		for value in row[list_key]:
			if not Int64CodecScript.is_canonical(value): return "noncanonical_%s" % list_key
			var parsed := Int64CodecScript.parse(value, list_key)
			if parsed <= previous: return "duplicate_or_unsorted_%s" % list_key
			previous = parsed
	var party_set: Dictionary = {}
	for value in row.party_member_ids: party_set[value] = true
	for value in row.enemy_ids:
		if party_set.has(value): return "party_enemy_id_overlap"
	if not row.member_rows is Array or row.member_rows.size() != row.party_member_ids.size(): return "invalid_party_member_rows"
	for index in range(row.member_rows.size()):
		var error := MemberScript.wire_error(row.member_rows[index]); if not error.is_empty(): return error
		if row.member_rows[index].entity_id != row.party_member_ids[index]: return "party_member_order_mismatch"
		if int(row.member_rows[index].roster_slot) != index: return "party_roster_slot_order_mismatch"
	if not row.enemy_busy_rows is Array or row.enemy_busy_rows.size() != row.enemy_ids.size(): return "invalid_enemy_busy_rows"
	for index in range(row.enemy_busy_rows.size()):
		var busy = row.enemy_busy_rows[index]
		if not busy is Dictionary: return "invalid_enemy_busy_row"
		var busy_keys: Array = busy.keys(); busy_keys.sort()
		if busy_keys != ["busy_until", "entity_id"]: return "invalid_enemy_busy_row"
		if busy.entity_id != row.enemy_ids[index] or not Int64CodecScript.is_canonical(busy.busy_until): return "enemy_busy_order_mismatch"
		var busy_until := Int64CodecScript.parse(busy.busy_until, "enemy busy")
		if busy_until < 0 or busy_until > MAX_WORLD_TIME: return "enemy_busy_out_of_range"
	var contact_id := Int64CodecScript.parse(row.contact_enemy_id, "contact enemy")
	if (row.contact_kind == "NONE") != (contact_id == -1): return "contact_identity_mismatch"
	if contact_id != -1 and not row.enemy_ids.has(str(contact_id)): return "contact_enemy_not_in_encounter"
	if row.safe_phase in ["GROUPED", "GROUPED_COMPLETE"] and (row.contact_kind != "NONE" or row.formation_id != "NONE"):
		return "grouped_contact_or_formation_invalid"
	if row.safe_phase == "CONTACT" and (row.contact_kind == "NONE" or row.formation_id != "NONE"):
		return "contact_phase_formation_invalid"
	if row.safe_phase in ["ENGAGED", "REGROUP_READY"] and (row.contact_kind == "NONE" or row.formation_id == "NONE"):
		return "engaged_contact_or_formation_invalid"
	return ""

static func _position(value: Variant, width: int, height: int) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1]) and value[0] >= 0 and value[1] >= 0 and value[0] < width and value[1] < height

static func _facing(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1]) \
		and Vector2i(int(value[0]), int(value[1])) in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))
