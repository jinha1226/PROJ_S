class_name OpeningEventState
extends RefCounted

const SCHEMA_VERSION := 1
const CHOICES := ["PENDING", "GAVE_POTION", "PASSED"]
const BEHAVIORS := ["WAITING", "TRAVEL"]
const Int64CodecScript = preload("res://sim/int64_codec.gd")
const HexacoScript = preload("res://sim/dungeon_population/hexaco_profile.gd")

var schema_version: int = SCHEMA_VERSION
var npc_entity_id: int = -1
var choice: String = "PENDING"
var hexaco_profile = HexacoScript.new()
var spawn_position: Vector2i = Vector2i(-1, -1)
var convergence_band: Array[Vector2i] = []
var convergence_goal: Vector2i = Vector2i(-1, -1)
var current_behavior: String = "WAITING"
var choice_event_id: int = -1
var reencounter_event_id: int = -1


func _init(p_npc_entity_id: int = -1, p_profile = null,
		p_spawn_position: Vector2i = Vector2i(-1, -1),
		p_convergence_band: Array = [],
		p_convergence_goal: Vector2i = Vector2i(-1, -1)) -> void:
	npc_entity_id = p_npc_entity_id
	hexaco_profile = p_profile if p_profile != null else HexacoScript.new()
	spawn_position = p_spawn_position
	for position in p_convergence_band:
		if position is Vector2i: convergence_band.append(position)
	convergence_goal = p_convergence_goal


func to_dict() -> Dictionary:
	var band_rows: Array = []
	for position in convergence_band: band_rows.append([position.x, position.y])
	return {
		"schema_version": schema_version,
		"npc_entity_id": str(npc_entity_id),
		"choice": choice,
		"hexaco_profile": hexaco_profile.to_dict(),
		"spawn_position": [spawn_position.x, spawn_position.y],
		"convergence_band": band_rows,
		"convergence_goal": [convergence_goal.x, convergence_goal.y],
		"current_behavior": current_behavior,
		"choice_event_id": str(choice_event_id),
		"reencounter_event_id": str(reencounter_event_id),
	}


static func from_dict(row: Dictionary):
	var band: Array[Vector2i] = []
	for position in row.get("convergence_band", []):
		band.append(Vector2i(int(position[0]), int(position[1])))
	var state = load("res://sim/opening_event_state.gd").new(
		Int64CodecScript.parse(row.get("npc_entity_id", "-1"), "opening NPC ID"),
		HexacoScript.from_dict(row.get("hexaco_profile", {})),
		Vector2i(int(row.get("spawn_position", [-1, -1])[0]),
			int(row.get("spawn_position", [-1, -1])[1])),
		band,
		Vector2i(int(row.get("convergence_goal", [-1, -1])[0]),
			int(row.get("convergence_goal", [-1, -1])[1])))
	state.schema_version = int(row.get("schema_version", -1))
	state.choice = str(row.get("choice", ""))
	state.current_behavior = str(row.get("current_behavior", ""))
	state.choice_event_id = Int64CodecScript.parse(
		row.get("choice_event_id", "-1"), "opening choice event ID")
	state.reencounter_event_id = Int64CodecScript.parse(
		row.get("reencounter_event_id", "-1"), "opening reencounter event ID")
	return state


static func wire_error(row: Variant, width: int, height: int) -> String:
	if not row is Dictionary: return "invalid_opening_event_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["choice", "choice_event_id", "convergence_band", "convergence_goal",
			"current_behavior", "hexaco_profile", "npc_entity_id", "reencounter_event_id",
			"schema_version", "spawn_position"]:
		return "invalid_opening_event_keys"
	if not _integer(row.get("schema_version")) \
			or int(row.schema_version) != SCHEMA_VERSION:
		return "unsupported_opening_event_schema"
	if not Int64CodecScript.is_canonical(row.get("npc_entity_id")) \
			or Int64CodecScript.parse(row.npc_entity_id, "opening NPC ID") <= 0:
		return "invalid_opening_npc_id"
	for key in ["choice_event_id", "reencounter_event_id"]:
		if not Int64CodecScript.is_canonical(row.get(key)) \
				or Int64CodecScript.parse(row[key], key) < -1:
			return "invalid_opening_event_id"
	if row.get("choice") not in CHOICES \
			or row.get("current_behavior") not in BEHAVIORS:
		return "invalid_opening_event_enum"
	if (row.choice == "PENDING") != (row.current_behavior == "WAITING") \
			or (row.choice == "PENDING") != (
			Int64CodecScript.parse(row.choice_event_id, "opening choice event ID") == -1):
		return "invalid_opening_choice_state"
	var hexaco_error := HexacoScript.wire_error(row.get("hexaco_profile"))
	if not hexaco_error.is_empty(): return hexaco_error
	if not _position(row.get("spawn_position"), width, height) \
			or not _position(row.get("convergence_goal"), width, height):
		return "invalid_opening_anchor"
	if not row.get("convergence_band") is Array \
			or row.convergence_band.is_empty() or row.convergence_band.size() > 256:
		return "invalid_opening_convergence_band"
	var seen: Dictionary = {}
	for position in row.convergence_band:
		if not _position(position, width, height): return "invalid_opening_convergence_band"
		var key := "%d:%d" % [int(position[0]), int(position[1])]
		if seen.has(key): return "duplicate_opening_convergence_cell"
		seen[key] = true
	var goal_key := "%d:%d" % [int(row.convergence_goal[0]), int(row.convergence_goal[1])]
	if not seen.has(goal_key): return "opening_goal_outside_convergence_band"
	if Int64CodecScript.parse(row.reencounter_event_id,
			"opening reencounter event ID") > 0 and row.choice == "PENDING":
		return "opening_reencounter_before_choice"
	return ""


static func _position(value: Variant, width: int, height: int) -> bool:
	return value is Array and value.size() == 2 \
		and _integer(value[0]) and _integer(value[1]) \
		and int(value[0]) >= 0 and int(value[1]) >= 0 \
		and int(value[0]) < width and int(value[1]) < height


static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))
