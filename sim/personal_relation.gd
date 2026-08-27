class_name PersonalRelation
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")

var observer_id: int
var subject_id: int
var personal_trust_delta: int = 0
var personal_fear_delta: int = 0
var gratitude: int = 0
var grievance: int = 0
var processed_source_event_ids: Array[int] = []


func _init(p_observer_id: int, p_subject_id: int) -> void:
	observer_id = p_observer_id
	subject_id = p_subject_id


func has_processed(event_id: int) -> bool:
	return processed_source_event_ids.has(event_id)


func to_dict() -> Dictionary:
	return {
		"observer_id": str(observer_id),
		"subject_id": str(subject_id),
		"personal_trust_delta": personal_trust_delta,
		"personal_fear_delta": personal_fear_delta,
		"gratitude": gratitude,
		"grievance": grievance,
		"processed_source_event_ids": processed_source_event_ids.map(func(value: int): return str(value)),
	}


static func from_dict(row: Dictionary):
	var relation = load("res://sim/personal_relation.gd").new(
		Int64CodecScript.parse(row["observer_id"], "relation observer ID"),
		Int64CodecScript.parse(row["subject_id"], "relation subject ID"))
	relation.personal_trust_delta = int(row.get("personal_trust_delta", 0))
	relation.personal_fear_delta = int(row.get("personal_fear_delta", 0))
	relation.gratitude = int(row.get("gratitude", 0))
	relation.grievance = int(row.get("grievance", 0))
	for event_id in row.get("processed_source_event_ids", []):
		relation.processed_source_event_ids.append(Int64CodecScript.parse(event_id, "processed event ID"))
	return relation
