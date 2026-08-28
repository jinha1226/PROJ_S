class_name AgentState
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")
const PersonalityProfileScript = preload("res://sim/personality_profile.gd")
const CONTROLLERS := ["LEAD", "PASSIVE_ALLY", "MELEE_THREAT"]
const ACTIVITIES := ["MOVE", "MELEE_ATTACK", "HOLD", "FREEZE", "ESCAPE", "IDLE"]
const REACTIONS := ["NONE", "ENGAGE", "PROTECT", "FLEE", "TAKE_COVER", "HOLD", "FREEZE"]
const MODES := ["NORMAL", "PANIC"]
const ENCOUNTER_STATUSES := ["ACTIVE", "ESCAPED"]

var entity_id: int
var controller_kind: String
var trial_slot: int
var encounter_status := "ACTIVE"
var busy_until: int = 0
var current_activity := "IDLE"
var current_reaction := "NONE"
var intent_target_entity_id: int = -1
var intent_target_position := Vector2i(-1, -1)
var intent_started_time: int = 0
var personality_profile = null
var fear: int = 0
var anger: int = 0
var emotion_updated_time: int = 0
var mental_mode := "NORMAL"
var mental_mode_since: int = 0
var active_threat_id: int = -1
var threat_notice_event_id: int = -1
var last_seen_position := Vector2i(-1, -1)
var last_seen_time: int = -1
var commitment_until: int = 0
var action_history_rows: Array[Dictionary] = []
var last_decision_time: int = -1
var last_decision_event_id: int = -1

func _init(p_entity_id: int, p_controller_kind: String, p_trial_slot: int = 0) -> void:
	entity_id = p_entity_id
	controller_kind = p_controller_kind
	trial_slot = p_trial_slot

func history(action_id: String) -> Dictionary:
	for row in action_history_rows:
		if row.action_id == action_id: return row
	return {"action_id": action_id, "cooldown_until": 0, "last_committed_time": -1, "consecutive_commit_count": 0}

func set_history(row: Dictionary) -> void:
	for index in range(action_history_rows.size()):
		if action_history_rows[index].action_id == row.action_id:
			action_history_rows[index] = row.duplicate(true)
			return
	if action_history_rows.size() < 8:
		action_history_rows.append(row.duplicate(true))
		action_history_rows.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.action_id) < str(b.action_id))

func to_dict() -> Dictionary:
	var row := {"entity_id": str(entity_id), "controller_kind": controller_kind, "trial_slot": trial_slot,
		"encounter_status": encounter_status, "busy_until": str(busy_until), "current_activity": current_activity,
		"current_reaction": current_reaction, "intent_target_entity_id": str(intent_target_entity_id),
		"intent_target_position": [intent_target_position.x, intent_target_position.y],
		"intent_started_time": str(intent_started_time), "fear": fear, "anger": anger,
		"emotion_updated_time": str(emotion_updated_time), "mental_mode": mental_mode,
		"mental_mode_since": str(mental_mode_since), "active_threat_id": str(active_threat_id),
		"threat_notice_event_id": str(threat_notice_event_id),
		"last_seen_position": [last_seen_position.x, last_seen_position.y],
		"last_seen_time": str(last_seen_time),
		"commitment_until": str(commitment_until), "action_history_rows": [],
		"last_decision_time": str(last_decision_time), "last_decision_event_id": str(last_decision_event_id)}
	for history_row in action_history_rows:
		row.action_history_rows.append({"action_id": history_row.action_id,
			"cooldown_until": str(history_row.cooldown_until),
			"last_committed_time": str(history_row.last_committed_time),
			"consecutive_commit_count": int(history_row.consecutive_commit_count)})
	if controller_kind == "LEAD": row["personality_profile"] = personality_profile.to_dict()
	return row

static func from_dict(row: Dictionary):
	var state = load("res://sim/agent_state.gd").new(Int64CodecScript.parse(row.entity_id, "actor entity ID"), str(row.controller_kind), int(row.trial_slot))
	state.encounter_status = str(row.encounter_status)
	for field in ["busy_until", "intent_target_entity_id", "intent_started_time", "emotion_updated_time", "mental_mode_since", "active_threat_id", "threat_notice_event_id", "last_seen_time", "commitment_until", "last_decision_time", "last_decision_event_id"]:
		state.set(field, Int64CodecScript.parse(row[field], field))
	state.current_activity = str(row.current_activity); state.current_reaction = str(row.current_reaction)
	state.fear = int(row.fear); state.anger = int(row.anger); state.mental_mode = str(row.mental_mode)
	var target: Array = row.intent_target_position; state.intent_target_position = Vector2i(int(target[0]), int(target[1]))
	var seen: Array = row.last_seen_position; state.last_seen_position = Vector2i(int(seen[0]), int(seen[1]))
	if state.controller_kind == "LEAD": state.personality_profile = PersonalityProfileScript.from_dict(row.personality_profile)
	for history_row in row.action_history_rows:
		state.action_history_rows.append({"action_id": str(history_row.action_id),
			"cooldown_until": Int64CodecScript.parse(history_row.cooldown_until, "cooldown until"),
			"last_committed_time": Int64CodecScript.parse(history_row.last_committed_time, "last committed time"),
			"consecutive_commit_count": int(history_row.consecutive_commit_count)})
	return state
