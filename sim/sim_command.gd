class_name SimCommand
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")

enum Type {
	WAIT,
	IGNITE,
	POUR_WATER,
	DISCHARGE,
	MOVE,
}

var type: Variant
var actor_id: Variant
var position: Vector2i
var power: Variant
var wait_duration_time_units: Variant


func _init(
		p_type: Variant,
		p_actor_id: Variant = -1,
		p_position: Vector2i = Vector2i.ZERO,
		p_power: Variant = 0,
		p_wait_duration_time_units: Variant = 100
	) -> void:
	type = p_type
	actor_id = p_actor_id
	position = p_position
	power = p_power
	wait_duration_time_units = p_wait_duration_time_units


static func wait(p_actor_id: int = -1) -> SimCommand:
	return SimCommand.new(Type.WAIT, p_actor_id)


static func wait_for(duration_time_units: Variant, p_actor_id: int = -1) -> SimCommand:
	return SimCommand.new(Type.WAIT, p_actor_id, Vector2i.ZERO, 0, duration_time_units)


static func ignite(p_position: Vector2i, p_power: int = 70, p_actor_id: int = -1) -> SimCommand:
	return SimCommand.new(Type.IGNITE, p_actor_id, p_position, p_power)


static func pour_water(p_position: Vector2i, p_amount: int = 60, p_actor_id: int = -1) -> SimCommand:
	return SimCommand.new(Type.POUR_WATER, p_actor_id, p_position, p_amount)


static func discharge(p_position: Vector2i, p_power: int = 40, p_actor_id: int = -1) -> SimCommand:
	return SimCommand.new(Type.DISCHARGE, p_actor_id, p_position, p_power)


static func move_to(p_actor_id: int, destination: Vector2i) -> SimCommand:
	return SimCommand.new(Type.MOVE, p_actor_id, destination, 0, 100)


func to_dict() -> Dictionary:
	return {
		"type": int(type),
		"actor_id": str(actor_id),
		"position": [position.x, position.y],
		"power": power,
		"wait_duration_time_units": wait_duration_time_units,
	}


static func from_dict(data: Dictionary) -> SimCommand:
	if not command_wire_error(data).is_empty():
		return null
	var position_data: Array = data["position"]
	return SimCommand.new(
		int(data["type"]),
		Int64CodecScript.parse(data["actor_id"], "command actor ID"),
		Vector2i(int(position_data[0]), int(position_data[1])),
		int(data["power"]),
		int(data["wait_duration_time_units"])
	)


static func command_wire_error(data: Dictionary) -> String:
	if not _is_small_int(data.get("type"), int(Type.WAIT), int(Type.MOVE)):
		return "invalid_command_type"
	if not Int64CodecScript.is_canonical(data.get("actor_id")):
		return "noncanonical_actor_id"
	var restored_actor: int = Int64CodecScript.parse(data["actor_id"], "command actor ID")
	if restored_actor < -1 or restored_actor == 0:
		return "invalid_actor_id"
	if not (data.get("position") is Array) or data["position"].size() != 2:
		return "invalid_position_shape"
	for coordinate in data["position"]:
		if not _is_small_int(coordinate, -2147483648, 2147483647):
			return "invalid_position_coordinate"
	if not _is_small_int(data.get("power"), 0, 100):
		return "invalid_power"
	if not _is_small_int(data.get("wait_duration_time_units"), 1, 10000):
		return "invalid_wait_duration"
	var command_type := int(data["type"])
	var power_value := int(data["power"])
	if command_type == int(Type.WAIT) and power_value != 0:
		return "wait_power_must_be_zero"
	if command_type == int(Type.MOVE):
		if restored_actor < 1:
			return "move_requires_actor"
		if power_value != 0:
			return "move_power_must_be_zero"
	elif command_type != int(Type.WAIT) and power_value < 1:
		return "action_power_out_of_range"
	return ""


static func _is_small_int(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or (value is float and value == floor(value))) \
		and value >= minimum and value <= maximum
