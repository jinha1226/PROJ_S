class_name NpcMemory
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")
const KINDS := ["conversation"]

var memory_id: int
var observer_id: int
var source_event_id: int
var kind: String
var observed_time: int
var subject_id: int
var target_id: int
var position: Vector2i
var salience: int
var confidence: int
var firsthand: bool


func _init(p_memory_id: int, p_observer_id: int, p_source_event_id: int,
		p_kind: String, p_observed_time: int, p_subject_id: int, p_target_id: int,
		p_position: Vector2i, p_salience: int = 50, p_confidence: int = 100,
		p_firsthand: bool = true) -> void:
	memory_id = p_memory_id
	observer_id = p_observer_id
	source_event_id = p_source_event_id
	kind = p_kind
	observed_time = p_observed_time
	subject_id = p_subject_id
	target_id = p_target_id
	position = p_position
	salience = p_salience
	confidence = p_confidence
	firsthand = p_firsthand


func to_dict() -> Dictionary:
	return {
		"memory_id": str(memory_id), "observer_id": str(observer_id),
		"source_event_id": str(source_event_id), "kind": kind,
		"observed_time": str(observed_time), "subject_id": str(subject_id),
		"target_id": str(target_id), "position": [position.x, position.y],
		"salience": salience, "confidence": confidence, "firsthand": firsthand,
	}


static func from_dict(row: Dictionary):
	var p: Array = row["position"]
	return load("res://sim/npc_memory.gd").new(
		Int64CodecScript.parse(row["memory_id"], "memory ID"),
		Int64CodecScript.parse(row["observer_id"], "memory observer ID"),
		Int64CodecScript.parse(row["source_event_id"], "memory source event ID"),
		str(row["kind"]), Int64CodecScript.parse(row["observed_time"], "memory time"),
		Int64CodecScript.parse(row["subject_id"], "memory subject ID"),
		Int64CodecScript.parse(row["target_id"], "memory target ID"),
		Vector2i(int(p[0]), int(p[1])), int(row["salience"]),
		int(row["confidence"]), bool(row["firsthand"]))
