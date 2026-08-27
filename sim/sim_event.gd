class_name SimEvent
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")

var id: int
var step_index: int
var world_time: int
var type: String
var actor_id: int
var target_id: int
var position: Vector2i
var magnitude: int
var cause_id: int
var instigator_id: int
var data: Dictionary


func _init(
		p_id: int,
		p_step_index: int,
		p_world_time: int,
		p_type: String,
		p_actor_id: int = -1,
		p_target_id: int = -1,
		p_position: Vector2i = Vector2i(-1, -1),
		p_magnitude: int = 0,
		p_cause_id: int = -1,
		p_instigator_id: int = -1,
		p_data: Dictionary = {}
	) -> void:
	id = p_id
	step_index = p_step_index
	world_time = p_world_time
	type = p_type
	actor_id = p_actor_id
	target_id = p_target_id
	position = p_position
	magnitude = p_magnitude
	cause_id = p_cause_id
	instigator_id = p_instigator_id
	data = p_data.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"id": str(id),
		"step_index": str(step_index),
		"world_time": str(world_time),
		"type": type,
		"actor_id": str(actor_id),
		"target_id": str(target_id),
		"position": [position.x, position.y],
		"magnitude": magnitude,
		"cause_id": str(cause_id),
		"instigator_id": str(instigator_id),
		"data": data.duplicate(true),
	}


func detached_copy() -> SimEvent:
	return SimEvent.new(
		id, step_index, world_time, type, actor_id, target_id, position,
		magnitude, cause_id, instigator_id, data.duplicate(true))


static func from_dict(row: Dictionary) -> SimEvent:
	var position_data: Array = row.get("position", [-1, -1])
	return SimEvent.new(
		_parse_canonical_int(row["id"], "event id"),
		_parse_canonical_int(row["step_index"], "event step index"),
		_parse_canonical_int(row["world_time"], "event world time"), str(row["type"]),
		_parse_canonical_int(row.get("actor_id", "-1"), "event actor ID"),
		_parse_canonical_int(row.get("target_id", "-1"), "event target ID"),
		Vector2i(int(position_data[0]), int(position_data[1])),
		int(row.get("magnitude", 0)), _parse_canonical_int(row.get("cause_id", "-1"), "event cause id"),
		_parse_canonical_int(row.get("instigator_id", row.get("actor_id", "-1")), "event instigator ID"),
		_restore_json_types(row.get("data", {}))
	)


static func _parse_canonical_int(value: Variant, label: String) -> int:
	return Int64CodecScript.parse(value, label)


static func _restore_json_types(value: Variant) -> Variant:
	# Godot's JSON parser represents every JSON number as float. Event metadata
	# is restricted to integers, strings, booleans and containers; ratios use
	# fixed-point integers. Non-integral values remain floats so validation can
	# reject the malformed snapshot instead of silently rounding it.
	match typeof(value):
		TYPE_FLOAT:
			return int(value) if value == floor(value) else value
		TYPE_ARRAY:
			var restored_array: Array = []
			for item in value:
				restored_array.append(_restore_json_types(item))
			return restored_array
		TYPE_DICTIONARY:
			var restored_dictionary: Dictionary = {}
			for key in value:
				restored_dictionary[key] = _restore_json_types(value[key])
			return restored_dictionary
		_:
			return value


func describe() -> String:
	return "S%03d @%06d #%03d %-30s pos=(%d,%d) actor=%d instigator=%d target=%d value=%d cause=#%d" % [
		step_index,
		world_time,
		id,
		type,
		position.x,
		position.y,
		actor_id,
		instigator_id,
		target_id,
		magnitude,
		cause_id,
	]
