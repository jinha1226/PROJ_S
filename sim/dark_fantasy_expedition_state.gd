class_name DarkFantasyExpeditionState
extends RefCounted

## State owned by the short, three-room Dark Fantasy Expedition slice.
## Existing campaign modes leave this field null, so their rules and saves keep
## their current meaning.
const SCHEMA_VERSION := 1
const RULESET_ID := "dark-fantasy-expedition-slice-v1"
const PHASES := ["ACTIVE", "CAMP", "COMPLETE", "EXTRACTED", "FAILED"]
const ROOM_COUNT := 3
const CAMP_CP_MAX := 4
const RESCUE_SUPPLIES_MAX := 2

var schema_version := SCHEMA_VERSION
var ruleset_id := RULESET_ID
var expedition_id := ""
var phase := "ACTIVE"
var room_index := 0
var completed_rooms: Array[int] = []
var completed_stage_keys: Array[String] = []
var camp_available := false
var camp_cp := 0
var rescue_supplies := RESCUE_SUPPLIES_MAX
var earned_gold := 0
var preserved_gold := 0
var settlement_state := "UNSETTLED"
var member_rows: Dictionary = {}
var processed_event_ids: Array[String] = []

static func start(id: String, gold: int = 0, member_ids: Array = []):
	if id.is_empty() or gold < 0:
		return null
	var state = load("res://sim/dark_fantasy_expedition_state.gd").new()
	state.expedition_id = id
	state.earned_gold = gold
	for raw_id in member_ids:
		var entity_id := int(raw_id)
		if entity_id <= 0:
			return null
		state.member_rows[str(entity_id)] = {"death_tokens": 0, "injury_ids": [], "stress": 0}
	return state

func ensure_member(entity_id: int) -> void:
	var key := str(entity_id)
	if not member_rows.has(key):
		member_rows[key] = {"death_tokens": 0, "injury_ids": [], "stress": 0}

func member(entity_id: int) -> Dictionary:
	ensure_member(entity_id)
	return member_rows[str(entity_id)]

func complete_room(index: int) -> bool:
	if phase != "ACTIVE" or index != room_index or index in completed_rooms:
		return false
	completed_rooms.append(index)
	completed_rooms.sort()
	if index == 0:
		camp_available = true
		camp_cp = CAMP_CP_MAX
	if completed_rooms.size() >= ROOM_COUNT:
		phase = "COMPLETE"
		settlement_state = "PENDING"
	room_index = index + 1
	return true

func enter_camp() -> bool:
	if phase != "ACTIVE" or not camp_available or room_index != 1:
		return false
	phase = "CAMP"
	return true

func leave_camp() -> bool:
	if phase != "CAMP":
		return false
	camp_available = false
	phase = "ACTIVE"
	return true

func settle(kind: String) -> bool:
	if kind not in ["COMPLETE", "SAFE_RETREAT", "EMERGENCY_RETREAT", "FAILURE"]:
		return false
	if settlement_state == "SETTLED":
		return false
	if kind == "COMPLETE":
		phase = "COMPLETE"
		preserved_gold = earned_gold
	elif kind in ["SAFE_RETREAT", "EMERGENCY_RETREAT"]:
		phase = "EXTRACTED"
		preserved_gold = floori(earned_gold / 2)
	else:
		phase = "FAILED"
		preserved_gold = 0
	settlement_state = "SETTLED"
	return true

func to_dict() -> Dictionary:
	var rows: Array = []
	var ids: Array = member_rows.keys(); ids.sort()
	for key in ids:
		var row: Dictionary = member_rows[key]
		rows.append({"entity_id": str(key), "death_tokens": int(row.get("death_tokens", 0)),
			"injury_ids": row.get("injury_ids", []).duplicate(), "stress": int(row.get("stress", 0))})
	return {"schema_version": SCHEMA_VERSION, "ruleset_id": RULESET_ID,
		"expedition_id": expedition_id, "phase": phase, "room_index": room_index,
		"completed_rooms": completed_rooms.duplicate(), "camp_available": camp_available,
		"completed_stage_keys": completed_stage_keys.duplicate(),
		"camp_cp": camp_cp, "rescue_supplies": rescue_supplies,
		"earned_gold": earned_gold, "preserved_gold": preserved_gold,
		"settlement_state": settlement_state, "member_rows": rows,
		"processed_event_ids": processed_event_ids.duplicate()}

static func from_dict(row: Dictionary):
	if not wire_error(row).is_empty():
		return null
	var state = load("res://sim/dark_fantasy_expedition_state.gd").new()
	state.expedition_id = str(row.expedition_id)
	state.phase = str(row.phase)
	state.room_index = int(row.room_index)
	state.completed_rooms.assign(row.completed_rooms)
	state.completed_stage_keys.assign(row.get("completed_stage_keys",[]))
	state.camp_available = bool(row.camp_available)
	state.camp_cp = int(row.camp_cp)
	state.rescue_supplies = int(row.rescue_supplies)
	state.earned_gold = int(row.earned_gold)
	state.preserved_gold = int(row.preserved_gold)
	state.settlement_state = str(row.settlement_state)
	state.processed_event_ids.assign(row.processed_event_ids)
	for member_row in row.member_rows:
		state.member_rows[str(member_row.entity_id)] = {
			"death_tokens": int(member_row.death_tokens),
			"injury_ids": member_row.injury_ids.duplicate(), "stress": int(member_row.stress)}
	return state

static func wire_error(row: Variant) -> String:
	if row == null:
		return ""
	if not (row is Dictionary):
		return "dark_expedition_shape"
	var keys: Array = row.keys(); keys.sort()
	var expected := ["camp_available", "camp_cp", "completed_rooms", "earned_gold",
		"expedition_id", "member_rows", "phase", "preserved_gold", "processed_event_ids",
		"rescue_supplies", "room_index", "ruleset_id", "schema_version", "settlement_state"]
	expected.sort()
	if row.has("completed_stage_keys"):
		expected.append("completed_stage_keys");expected.sort()
		if not row.completed_stage_keys is Array:return "dark_expedition_stage_keys"
		for key in row.completed_stage_keys:
			if not key is String:return "dark_expedition_stage_keys"
	if keys != expected or row.schema_version != SCHEMA_VERSION \
			or row.ruleset_id != RULESET_ID:
		return "dark_expedition_header"
	if typeof(row.expedition_id) != TYPE_STRING or row.expedition_id.is_empty() \
			or row.phase not in PHASES or row.settlement_state not in ["UNSETTLED", "PENDING", "SETTLED"]:
		return "dark_expedition_enum"
	if not integer(row.room_index) or row.room_index < 0 or row.room_index > ROOM_COUNT \
			or not integer(row.camp_cp) or row.camp_cp < 0 or row.camp_cp > CAMP_CP_MAX \
			or not integer(row.rescue_supplies) or row.rescue_supplies < 0 or row.rescue_supplies > RESCUE_SUPPLIES_MAX \
			or not integer(row.earned_gold) or row.earned_gold < 0 \
			or not integer(row.preserved_gold) or row.preserved_gold < 0:
		return "dark_expedition_scalar"
	if typeof(row.completed_rooms) != TYPE_ARRAY or row.completed_rooms.size() > ROOM_COUNT:
		return "dark_expedition_rooms"
	var previous := -1
	for index in row.completed_rooms:
		if not integer(index) or index <= previous or index < 0 or index >= ROOM_COUNT:
			return "dark_expedition_rooms"
		previous = index
	if typeof(row.member_rows) != TYPE_ARRAY or typeof(row.processed_event_ids) != TYPE_ARRAY:
		return "dark_expedition_rows"
	var seen: Dictionary = {}
	for member_row in row.member_rows:
		if typeof(member_row) != TYPE_DICTIONARY or member_row.keys().size() != 4 \
				or not member_row.has("entity_id") or not member_row.has("death_tokens") \
				or not member_row.has("injury_ids") or not member_row.has("stress"):
			return "dark_expedition_member"
		if typeof(member_row.entity_id) != TYPE_STRING or int(member_row.entity_id) <= 0 \
				or seen.has(member_row.entity_id) or not integer(member_row.death_tokens) \
				or member_row.death_tokens < 0 or member_row.death_tokens > 3 \
				or typeof(member_row.injury_ids) != TYPE_ARRAY or not integer(member_row.stress) \
				or member_row.stress < 0 or member_row.stress > 100:
			return "dark_expedition_member"
		seen[member_row.entity_id] = true
	for event_id in row.processed_event_ids:
		if typeof(event_id) != TYPE_STRING or int(event_id) <= 0:
			return "dark_expedition_event_ids"
	return ""

static func integer(value: Variant) -> bool:
	return value is int or value is float and is_finite(value) and value == floor(value)
