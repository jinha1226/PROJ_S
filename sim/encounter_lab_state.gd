class_name EncounterLabState
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")
const PHASES := ["ARMED", "ACTIVE", "COMPLETE"]
var personality_seed: int = 1
var phase := "ARMED"
var activation_time: int = 100
var threat_profile_id := "lab-melee-threat-v1"
var appearance_event_ids: Array[int] = [-1, -1, -1, -1]

func _init(p_seed: int = 1) -> void: personality_seed = p_seed

func to_dict() -> Dictionary:
	var ids: Array[String] = []
	for id in appearance_event_ids: ids.append(str(id))
	return {"personality_seed": str(personality_seed), "phase": phase,
		"activation_time": str(activation_time), "threat_profile_id": threat_profile_id,
		"appearance_event_ids": ids}

static func from_dict(row: Dictionary):
	var state = load("res://sim/encounter_lab_state.gd").new(Int64CodecScript.parse(row.personality_seed, "personality seed"))
	state.phase = str(row.phase); state.activation_time = Int64CodecScript.parse(row.activation_time, "activation time")
	state.threat_profile_id = str(row.threat_profile_id); state.appearance_event_ids.clear()
	for id in row.appearance_event_ids: state.appearance_event_ids.append(Int64CodecScript.parse(id, "appearance event id"))
	return state
