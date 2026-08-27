class_name SimWorldState
extends RefCounted

const SNAPSHOT_VERSION := 3
const RULESET_VERSION := "phase2-move-exposure-v1"
const CALENDAR_RULESET_ID := "abstract-calendar-v1"
const TERRAIN_RULESET_ID := "terrain-registry-v1"
const HAZARD_AFFINITY_RULESET_ID := "hazard-affinity-v1"
const ENVIRONMENT_INTERVAL := 100
const MAX_WORLD_TIME := 9223372036854775707
const MAX_SAFE_JSON_INTEGER := 9007199254740991
const MAX_DIMENSION := 4096
const MAX_TILE_COUNT := 1000000
const MAX_SMALL_VALUE := 2147483647
const SimTileScript = preload("res://sim/sim_tile.gd")
const SimEntityScript = preload("res://sim/sim_entity.gd")
const SimEventScript = preload("res://sim/sim_event.gd")
const SpeciesRelationTableScript = preload("res://sim/species_relation_table.gd")
const PersonalRelationScript = preload("res://sim/personal_relation.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")

var width: int
var height: int
var step_index: int = 0
var world_time: int = 0
var seed: int
var rng: RandomNumberGenerator
var tiles: Array = []
var entities: Dictionary = {}
var events: Array = []
var species_relations
var personal_relations: Dictionary = {}
var scheduled_entries: Array[Dictionary] = []
var next_schedule_id: int = 1

var _next_entity_id: int = 1
var _next_event_id: int = 1
var _active_step_index: int = -1


func _init(p_width: int, p_height: int, p_seed: int = 1) -> void:
	width = p_width
	height = p_height
	seed = p_seed
	rng = RandomNumberGenerator.new()
	rng.seed = p_seed
	species_relations = SpeciesRelationTableScript.new()
	# Raw construction is an internal/prevalidated path. Keep an invalid object
	# inert rather than allocating an array that checked restore would reject.
	if not dimensions_error(width, height).is_empty():
		return
	for index in range(width * height):
		tiles.append(SimTileScript.new())
	schedule_entry("system.environment_tick", ENVIRONMENT_INTERVAL, 100, -1, -1, ENVIRONMENT_INTERVAL)


static func dimensions_error(p_width: int, p_height: int) -> String:
	if p_width < 1 or p_width > MAX_DIMENSION:
		return "invalid_width"
	if p_height < 1 or p_height > MAX_DIMENSION:
		return "invalid_height"
	if p_width > MAX_TILE_COUNT / p_height:
		return "world_dimensions_too_large"
	return ""


func in_bounds(position: Vector2i) -> bool:
	return position.x >= 0 and position.y >= 0 and position.x < width and position.y < height


func tile_at(position: Vector2i):
	assert(in_bounds(position), "Tile position is outside the world")
	return tiles[position.y * width + position.x]


func cardinal_neighbors(position: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var candidate: Vector2i = position + direction
		if in_bounds(candidate):
			result.append(candidate)
	return result


func add_entity(kind: String, display_name: String, position: Vector2i,
		max_health: int = 100, tags: Array = [], species_id: String = "",
		faction_id: String = ""):
	if not in_bounds(position) or not _terrain_is_passable(position) \
			or blocking_entity_at(position) != null \
			or max_health < 1 or max_health > MAX_SMALL_VALUE \
			or _next_entity_id <= 0 or _next_entity_id >= 9223372036854775807:
		return null
	for tag in tags:
		if not (tag is String):
			return null
	var checked_tags: Array[String] = []
	for tag in tags:
		checked_tags.append(tag)
	var entity = SimEntityScript.new(
		_next_entity_id, kind, display_name, position, max_health, checked_tags,
		species_id, faction_id
	)
	entities[entity.id] = entity
	_next_entity_id += 1
	return entity


func entities_at(position: Vector2i) -> Array:
	var result: Array = []
	var ids: Array = entities.keys()
	ids.sort()
	for entity_id in ids:
		var entity = entities[entity_id]
		if entity.position == position and entity.is_alive():
			result.append(entity)
	return result


func blocking_entity_at(position: Vector2i, except_entity_id: int = -1):
	for entity in entities_at(position):
		if entity.id != except_entity_id:
			return entity
	return null


func bootstrap_set_terrain(position: Vector2i, terrain_id: String) -> bool:
	if _active_step_index != -1 or step_index != 0 or world_time != 0 \
			or not events.is_empty() or not in_bounds(position) \
			or not TerrainRegistryScript.has(terrain_id) \
			or blocking_entity_at(position) != null:
		return false
	var definition: Dictionary = TerrainRegistryScript.definition(terrain_id)
	var tile = tile_at(position)
	tile.terrain = terrain_id
	tile.flammability = definition["default_flammability"]
	tile.base_conductivity = definition["default_base_conductivity"]
	tile.wetness = 0
	tile.fire = 0
	tile.fire_source_event_id = -1
	tile.wetness_source_event_id = -1
	tile.fire_damage_eligible_time = -1
	return true


func bootstrap_set_fire(position: Vector2i, intensity: int,
		source_type: String = "environment.ignited"):
	if _active_step_index != -1 or step_index != 0 or world_time != 0 \
			or not in_bounds(position) or intensity < 1 or intensity > 100 \
			or (source_type != "environment.ignited" \
				and source_type != "environment.fire_spread"):
		return null
	var event = emit_event(source_type, -1, -1, position, intensity)
	if event == null:
		return null
	var tile = tile_at(position)
	tile.fire = intensity
	tile.fire_source_event_id = event.id
	tile.fire_damage_eligible_time = (
		world_time + ENVIRONMENT_INTERVAL
		if source_type == "environment.fire_spread" else world_time)
	return event


func bootstrap_set_wetness(position: Vector2i, amount: int):
	if _active_step_index != -1 or step_index != 0 or world_time != 0 \
			or not in_bounds(position) or amount < 1 or amount > 100:
		return null
	var event = emit_event(
		"environment.water_applied", -1, -1, position, amount, -1,
		{"requested_amount": amount})
	if event == null:
		return null
	var tile = tile_at(position)
	tile.wetness = amount
	tile.wetness_source_event_id = event.id
	return event


func begin_step(p_step_index: int) -> void:
	assert(_active_step_index == -1, "A step is already being processed")
	assert(p_step_index == step_index + 1, "Processed step index must be the next decision")
	assert_settled()
	_active_step_index = p_step_index


func finish_step() -> void:
	assert(_active_step_index == step_index + 1, "No valid step is being processed")
	step_index = _active_step_index
	_active_step_index = -1
	assert_settled()


func emit_event(type: String, actor_id: int = -1, target_id: int = -1,
		position: Vector2i = Vector2i(-1, -1), magnitude: int = 0,
		cause_id: int = -1, data: Dictionary = {}):
	if type.is_empty() or magnitude < 0 or magnitude > MAX_SMALL_VALUE \
			or not _runtime_position_is_valid(position, true) \
			or not _entity_reference_is_valid(actor_id) \
			or not _entity_reference_is_valid(target_id) \
			or _next_event_id <= 0 or _next_event_id >= 9223372036854775807 \
			or not _is_valid_event_data(data):
		return null
	var instigator_id := actor_id
	if cause_id != -1:
		var cause = event_by_id(cause_id)
		if cause == null or cause.id >= _next_event_id or cause.world_time > world_time:
			return null
		instigator_id = cause.instigator_id
	var event_step := _active_step_index if _active_step_index != -1 else step_index
	var event = SimEventScript.new(
		_next_event_id, event_step, world_time, type, actor_id, target_id, position,
		magnitude, cause_id, instigator_id, data
	)
	events.append(event)
	_next_event_id += 1
	return event


func event_by_id(event_id: int):
	if event_id <= 0 or event_id >= _next_event_id:
		return null
	var event = events[event_id - 1]
	return event if event.id == event_id else null


func events_since(index: int) -> Array:
	return events.slice(index)


func has_event_id_headroom(maximum_new_events: int) -> bool:
	return maximum_new_events >= 0 and _next_event_id > 0 \
		and _next_event_id <= 9223372036854775807 - maximum_new_events


func schedule_entry(kind: String, due_time: int, priority: int = 100,
		owner_id: int = -1, source_event_id: int = -1, repeat_interval: int = 0,
		payload: Dictionary = {}) -> int:
	# The stable state has exactly one canonical environment cadence. The public
	# producer cannot create a state that the current snapshot contract refuses.
	if not scheduled_entries.is_empty() or next_schedule_id != 1 or world_time != 0 \
			or kind != "system.environment_tick" or due_time != ENVIRONMENT_INTERVAL \
			or priority != 100 or owner_id != -1 or source_event_id != -1 \
			or repeat_interval != ENVIRONMENT_INTERVAL or not payload.is_empty():
		return -1
	return _insert_schedule_entry(
		kind, due_time, priority, owner_id, source_event_id, repeat_interval, payload)


# Test-only escape hatch for occurrence ordering/budget fixtures. A queue made
# through this helper is intentionally unsettled and must be consumed before a
# snapshot boundary; production callers use schedule_entry().
func _schedule_fixture_entry(kind: String, due_time: int, priority: int = 100,
		owner_id: int = -1, source_event_id: int = -1, repeat_interval: int = 0,
		payload: Dictionary = {}) -> int:
	return _insert_schedule_entry(
		kind, due_time, priority, owner_id, source_event_id, repeat_interval, payload)


func _insert_schedule_entry(kind: String, due_time: int, priority: int,
		owner_id: int, source_event_id: int, repeat_interval: int,
		payload: Dictionary) -> int:
	if kind != "system.environment_tick" or due_time <= world_time \
			or due_time > MAX_WORLD_TIME or repeat_interval < 0 \
			or repeat_interval > MAX_WORLD_TIME \
			or (repeat_interval > 0 \
				and due_time > 9223372036854775807 - repeat_interval) \
			or priority < -MAX_SMALL_VALUE or priority > MAX_SMALL_VALUE \
			or not _entity_reference_is_valid(owner_id) \
			or (source_event_id != -1 and event_by_id(source_event_id) == null) \
			or not _is_valid_event_data(payload) or next_schedule_id <= 0 \
			or next_schedule_id >= 9223372036854775807:
		return -1
	var schedule_id := next_schedule_id
	next_schedule_id += 1
	scheduled_entries.append({
		"schedule_id": schedule_id, "due_time": due_time, "priority": priority,
		"kind": kind, "owner_id": owner_id, "source_event_id": source_event_id,
		"repeat_interval": repeat_interval, "payload": payload.duplicate(true),
	})
	_sort_schedules()
	return schedule_id


func take_next_schedule() -> Dictionary:
	assert(not scheduled_entries.is_empty(), "No schedule to take")
	return scheduled_entries.pop_front()


func requeue_repeating(entry: Dictionary) -> void:
	assert(int(entry["repeat_interval"]) > 0, "Only repeating schedules can be requeued")
	assert(int(entry["due_time"]) <= 9223372036854775807 - int(entry["repeat_interval"]),
		"Repeating schedule time overflow")
	entry["due_time"] = int(entry["due_time"]) + int(entry["repeat_interval"])
	assert(int(entry["due_time"]) > world_time, "Repeating schedule must move into the future")
	scheduled_entries.append(entry)
	_sort_schedules()


func assert_settled() -> void:
	assert(_active_step_index == -1, "World is not at a player decision boundary")
	for entry in scheduled_entries:
		assert(int(entry["due_time"]) > world_time, "Overdue schedule at decision boundary")


func is_settled() -> bool:
	if _active_step_index != -1:
		return false
	for entry in scheduled_entries:
		if int(entry["due_time"]) <= world_time:
			return false
	return true


func snapshot() -> Variant:
	if not world_state_error().is_empty():
		return null
	var tile_rows: Array = []
	for tile_index in range(tiles.size()):
		var tile = tiles[tile_index]
		tile_rows.append(tile.to_dict())
	var entity_rows: Array = []
	var entity_ids: Array = entities.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		entity_rows.append(entities[entity_id].to_dict())
	var event_rows: Array = []
	for event in events:
		event_rows.append(event.to_dict())
	var relation_rows: Array = []
	var relation_keys: Array = personal_relations.keys()
	relation_keys.sort()
	for key in relation_keys:
		relation_rows.append(personal_relations[key].to_dict())
	var schedule_rows: Array = []
	for entry in scheduled_entries:
		schedule_rows.append(_schedule_to_dict(entry))
	return {
		"snapshot_version": SNAPSHOT_VERSION,
		"ruleset_version": RULESET_VERSION,
		"calendar_ruleset_id": CALENDAR_RULESET_ID,
		"terrain_ruleset_id": TERRAIN_RULESET_ID,
		"hazard_affinity_ruleset_id": HAZARD_AFFINITY_RULESET_ID,
		"width": width, "height": height,
		"step_index": str(step_index), "world_time": str(world_time), "seed": str(seed),
		"rng_state": str(rng.state),
		"next_entity_id": str(_next_entity_id), "next_event_id": str(_next_event_id),
		"next_schedule_id": str(next_schedule_id), "scheduled_entries": schedule_rows,
		"tiles": tile_rows, "entities": entity_rows, "events": event_rows,
		"species_relations": species_relations.to_dict(), "personal_relations": relation_rows,
	}


static func from_snapshot(data: Dictionary) -> SimWorldState:
	var decoded := checked_decode_snapshot(data)
	return decoded["world"] if decoded["error"].is_empty() else null


static func snapshot_restore_error(data: Dictionary) -> String:
	return checked_decode_snapshot(data)["error"]


static func checked_decode_snapshot(data: Dictionary) -> Dictionary:
	var wire_error := snapshot_wire_error(data)
	if not wire_error.is_empty():
		return {"error": wire_error, "world": null}
	var restored := _restore_unchecked(data)
	if restored == null:
		return {"error": "restore_construction_failed", "world": null}
	var semantic_error := restored._restored_state_error()
	if not semantic_error.is_empty():
		return {"error": semantic_error, "world": null}
	return {"error": "", "world": restored}


static func _restore_unchecked(data: Dictionary) -> SimWorldState:
	var restored_seed := parse_canonical_int64(data["seed"], "seed")
	var restored := SimWorldState.new(int(data["width"]), int(data["height"]), restored_seed)
	restored.step_index = parse_canonical_int64(data["step_index"], "step index")
	restored.world_time = parse_canonical_int64(data["world_time"], "world time")
	restored.rng.state = parse_canonical_int64(data["rng_state"], "RNG state")
	restored._next_entity_id = parse_canonical_int64(data["next_entity_id"], "next entity ID")
	restored._next_event_id = parse_canonical_int64(data["next_event_id"], "next event ID")
	restored.next_schedule_id = parse_canonical_int64(data["next_schedule_id"], "next schedule ID")
	restored.tiles.clear()
	for row in data["tiles"]:
		restored.tiles.append(SimTileScript.from_dict(row))
	restored.entities.clear()
	for row in data["entities"]:
		var entity = SimEntityScript.from_dict(row)
		restored.entities[entity.id] = entity
	restored.events.clear()
	for row in data["events"]:
		restored.events.append(SimEventScript.from_dict(row))
	restored.species_relations = SpeciesRelationTableScript.from_dict(data.get("species_relations", {}))
	restored.personal_relations.clear()
	for row in data.get("personal_relations", []):
		var relation = PersonalRelationScript.from_dict(row)
		var relation_key := "%d:%d" % [relation.observer_id, relation.subject_id]
		restored.personal_relations[relation_key] = relation
	restored.scheduled_entries.clear()
	for row in data.get("scheduled_entries", []):
		restored.scheduled_entries.append(_schedule_from_dict(row))
	restored._sort_schedules()
	return restored


static func snapshot_header_error(data: Dictionary) -> String:
	var raw_version: Variant = data.get("snapshot_version", -1)
	if not _is_small_int(raw_version, 0, MAX_SMALL_VALUE):
		return "snapshot_version_not_integer"
	if int(raw_version) != SNAPSHOT_VERSION:
		return "unsupported_snapshot_version"
	if not (data.get("ruleset_version") is String) or data["ruleset_version"] != RULESET_VERSION:
		return "unsupported_ruleset_version"
	if not (data.get("calendar_ruleset_id") is String) or data["calendar_ruleset_id"] != CALENDAR_RULESET_ID:
		return "unsupported_calendar_ruleset"
	if not (data.get("terrain_ruleset_id") is String) \
			or data["terrain_ruleset_id"] != TERRAIN_RULESET_ID:
		return "unsupported_terrain_ruleset"
	if not (data.get("hazard_affinity_ruleset_id") is String) \
			or data["hazard_affinity_ruleset_id"] != HAZARD_AFFINITY_RULESET_ID:
		return "unsupported_hazard_affinity_ruleset"
	return ""


static func snapshot_wire_error(data: Dictionary) -> String:
	var header_error := snapshot_header_error(data)
	if not header_error.is_empty():
		return header_error
	if not _is_small_int(data.get("width"), 1, MAX_DIMENSION):
		return "invalid_width"
	if not _is_small_int(data.get("height"), 1, MAX_DIMENSION):
		return "invalid_height"
	var restored_width := int(data["width"])
	var restored_height := int(data["height"])
	var dimensions_validation := dimensions_error(restored_width, restored_height)
	if not dimensions_validation.is_empty():
		return dimensions_validation
	for key in ["step_index", "world_time", "seed", "rng_state", "next_entity_id",
		"next_event_id", "next_schedule_id"]:
		if not Int64CodecScript.is_canonical(data.get(key)):
			return "noncanonical_%s" % key
	var parsed_step: int = Int64CodecScript.parse(data["step_index"], "step index")
	var parsed_time: int = Int64CodecScript.parse(data["world_time"], "world time")
	if parsed_step < 0:
		return "negative_step_index"
	if parsed_time < 0 or parsed_time > MAX_WORLD_TIME:
		return "world_time_out_of_range"
	for key in ["next_entity_id", "next_event_id", "next_schedule_id"]:
		if Int64CodecScript.parse(data[key], key) <= 0:
			return "nonpositive_%s" % key
	if not (data.get("tiles") is Array) or data["tiles"].size() != restored_width * restored_height:
		return "invalid_tiles_shape"
	for row in data["tiles"]:
		if not (row is Dictionary) or not (row.get("terrain") is String):
			return "invalid_tile_shape"
		if not TerrainRegistryScript.has(row["terrain"]):
			return "unknown_terrain_id"
		for key in ["flammability", "base_conductivity", "wetness", "fire"]:
			if not _is_small_int(row.get(key), 0, 100):
				return "invalid_tile_%s" % key
		for key in ["fire_source_event_id", "wetness_source_event_id", "fire_damage_eligible_time"]:
			if not Int64CodecScript.is_canonical(row.get(key)):
				return "noncanonical_tile_%s" % key
	if not (data.get("entities") is Array):
		return "invalid_entities_shape"
	var entity_ids: Dictionary = {}
	for row in data["entities"]:
		if not (row is Dictionary):
			return "invalid_entity_shape"
		if not Int64CodecScript.is_canonical(row.get("id")):
			return "noncanonical_entity_id"
		var entity_id: int = Int64CodecScript.parse(row["id"], "entity ID")
		if entity_id <= 0 or entity_ids.has(entity_id):
			return "invalid_or_duplicate_entity_id"
		entity_ids[entity_id] = true
		for key in ["kind", "display_name", "species_id", "faction_id"]:
			if not (row.get(key) is String):
				return "invalid_entity_%s" % key
		if not _is_position(row.get("position"), restored_width, restored_height, false):
			return "invalid_entity_position"
		if not _is_small_int(row.get("max_health"), 1, MAX_SMALL_VALUE):
			return "invalid_entity_max_health"
		if not _is_small_int(row.get("health"), 0, int(row["max_health"])):
			return "invalid_entity_health"
		if not (row.get("tags") is Array):
			return "invalid_entity_tags"
		for tag in row["tags"]:
			if not (tag is String):
				return "invalid_entity_tag"
	if not (data.get("events") is Array):
		return "invalid_events_shape"
	for row in data["events"]:
		if not (row is Dictionary) or not (row.get("type") is String) \
				or row["type"].is_empty():
			return "invalid_event_shape"
		for key in ["id", "step_index", "world_time", "actor_id", "target_id", "cause_id", "instigator_id"]:
			if not Int64CodecScript.is_canonical(row.get(key)):
				return "noncanonical_event_%s" % key
		if not _is_position(row.get("position"), restored_width, restored_height, true):
			return "invalid_event_position"
		if not _is_small_int(row.get("magnitude"), 0, MAX_SMALL_VALUE):
			return "invalid_event_magnitude"
		if not _is_json_safe_metadata(row.get("data")):
			return "invalid_event_data"
	if not (data.get("species_relations") is Dictionary) \
			or not (data["species_relations"].get("rows") is Array):
		return "invalid_species_relations_shape"
	var species_pairs: Dictionary = {}
	for row in data["species_relations"]["rows"]:
		if not (row is Dictionary) or not (row.get("observer_species_id") is String) \
				or not (row.get("subject_species_id") is String):
			return "invalid_species_relation_shape"
		if not _is_small_int(row.get("base_trust"), -100, 100) \
				or not _is_small_int(row.get("base_fear"), 0, 100) \
				or not _is_small_int(row.get("base_hostility"), 0, 100):
			return "invalid_species_relation_value"
		var observer_species: String = row["observer_species_id"]
		var subject_species: String = row["subject_species_id"]
		var subjects_seen: Dictionary = species_pairs.get(observer_species, {})
		if subjects_seen.has(subject_species):
			return "duplicate_species_relation"
		subjects_seen[subject_species] = true
		species_pairs[observer_species] = subjects_seen
	if not (data.get("personal_relations") is Array):
		return "invalid_personal_relations_shape"
	var relation_pairs: Dictionary = {}
	for row in data["personal_relations"]:
		if not (row is Dictionary):
			return "invalid_personal_relation_shape"
		for key in ["observer_id", "subject_id"]:
			if not Int64CodecScript.is_canonical(row.get(key)):
				return "noncanonical_relation_%s" % key
		var pair := "%s:%s" % [row["observer_id"], row["subject_id"]]
		if relation_pairs.has(pair):
			return "duplicate_personal_relation"
		relation_pairs[pair] = true
		if not _is_small_int(row.get("personal_trust_delta"), -40, 40) \
				or not _is_small_int(row.get("personal_fear_delta"), -30, 30) \
				or not _is_small_int(row.get("gratitude"), 0, 100) \
				or not _is_small_int(row.get("grievance"), 0, 100):
			return "invalid_personal_relation_value"
		if not (row.get("processed_source_event_ids") is Array):
			return "invalid_relation_sources_shape"
		for value in row["processed_source_event_ids"]:
			if not Int64CodecScript.is_canonical(value):
				return "noncanonical_relation_source"
	if not (data.get("scheduled_entries") is Array):
		return "invalid_schedules_shape"
	var schedules: Array = data["scheduled_entries"]
	if schedules.size() != 1:
		return "invalid_environment_schedule_count"
	if not (schedules[0] is Dictionary):
		return "invalid_schedule_shape"
	var schedule: Dictionary = schedules[0]
	for key in ["schedule_id", "due_time", "owner_id", "source_event_id", "repeat_interval"]:
		if not Int64CodecScript.is_canonical(schedule.get(key)):
			return "noncanonical_schedule_%s" % key
	if schedule.get("kind") != "system.environment_tick" \
			or not _is_small_int(schedule.get("priority"), 100, 100):
		return "invalid_environment_schedule_kind_or_priority"
	if schedule.get("repeat_interval") != "100" or schedule.get("owner_id") != "-1" \
			or schedule.get("source_event_id") != "-1" or not (schedule.get("payload") is Dictionary) \
			or not schedule["payload"].is_empty():
		return "invalid_environment_schedule_contract"
	if not _is_json_safe_metadata(schedule["payload"]):
		return "invalid_schedule_payload"
	var expected_due := parsed_time - (parsed_time % ENVIRONMENT_INTERVAL) + ENVIRONMENT_INTERVAL
	if Int64CodecScript.parse(schedule["due_time"], "schedule due") != expected_due:
		return "invalid_environment_schedule_cadence"
	return ""


static func _is_small_int(value: Variant, minimum: int, maximum: int) -> bool:
	var valid_type: bool = value is int or (value is float and value == floor(value))
	return valid_type and value >= minimum and value <= maximum


static func _is_position(value: Variant, p_width: int, p_height: int, allow_sentinel: bool) -> bool:
	if not (value is Array) or value.size() != 2:
		return false
	if not _is_small_int(value[0], -2147483648, 2147483647) \
			or not _is_small_int(value[1], -2147483648, 2147483647):
		return false
	var x := int(value[0])
	var y := int(value[1])
	return (allow_sentinel and x == -1 and y == -1) \
		or (x >= 0 and y >= 0 and x < p_width and y < p_height)


static func _is_json_safe_metadata(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT:
			return value >= -MAX_SAFE_JSON_INTEGER and value <= MAX_SAFE_JSON_INTEGER
		TYPE_FLOAT:
			return value == floor(value) and abs(value) <= MAX_SAFE_JSON_INTEGER
		TYPE_STRING, TYPE_BOOL:
			return true
		TYPE_ARRAY:
			for item in value:
				if not _is_json_safe_metadata(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not (key is String) or not _is_json_safe_metadata(value[key]):
					return false
			return true
		_:
			return false


static func parse_canonical_int64(value: Variant, label: String) -> int:
	return Int64CodecScript.parse(value, label)


func _validate_restored_state() -> void:
	var error := world_state_error()
	assert(error.is_empty(), error)


func world_state_error() -> String:
	return _restored_state_error()


func _restored_state_error() -> String:
	if _active_step_index != -1:
		return "active_step_context_not_settled"
	var dimension_validation := dimensions_error(width, height)
	if not dimension_validation.is_empty():
		return dimension_validation
	if tiles.size() != width * height:
		return "snapshot_tile_count_mismatch"
	for tile in tiles:
		if not (tile.terrain is String) or not TerrainRegistryScript.has(tile.terrain):
			return "unknown_terrain_id"
		if tile.flammability < 0 or tile.flammability > 100 \
				or tile.base_conductivity < 0 or tile.base_conductivity > 100 \
				or tile.wetness < 0 or tile.wetness > 100 \
				or tile.fire < 0 or tile.fire > 100:
			return "tile_scalar_invalid"
	if step_index < 0:
		return "negative_step_index"
	if world_time < 0 or world_time > MAX_WORLD_TIME:
		return "world_time_out_of_range"
	if _next_entity_id <= 0:
		return "nonpositive_next_entity_id"
	var maximum_entity_id := 0
	var live_occupancy: Dictionary = {}
	for entity_id in entities:
		if not (entity_id is int) or entity_id <= 0:
			return "invalid_entity_id"
		var entity = entities[entity_id]
		if entity.id != entity_id or not in_bounds(entity.position):
			return "entity_identity_or_position_invalid"
		if entity.is_alive():
			if not _terrain_is_passable(entity.position):
				return "live_entity_on_impassable_terrain"
			var occupancy_key := "%d:%d" % [entity.position.x, entity.position.y]
			if live_occupancy.has(occupancy_key):
				return "live_occupancy_capacity_exceeded"
			live_occupancy[occupancy_key] = entity.id
		if not (entity.kind is String) or not (entity.display_name is String) \
				or not (entity.species_id is String) or not (entity.faction_id is String):
			return "entity_string_invalid"
		if entity.max_health <= 0 or entity.max_health > MAX_SMALL_VALUE \
				or entity.health < 0 or entity.health > entity.max_health:
			return "entity_health_invalid"
		if not (entity.tags is Array):
			return "entity_tags_invalid"
		for tag in entity.tags:
			if not (tag is String):
				return "entity_tag_invalid"
		maximum_entity_id = maxi(maximum_entity_id, entity_id)
	if _next_entity_id <= maximum_entity_id:
		return "next_entity_id_collision"
	if _next_event_id <= 0 or events.size() != _next_event_id - 1:
		return "event_id_sequence_mismatch"
	var previous_step := -1
	var previous_time := -1
	for index in range(events.size()):
		var event = events[index]
		if event.id != index + 1:
			return "event_ids_not_contiguous"
		if event.step_index < 0 or event.step_index > step_index or event.step_index < previous_step:
			return "event_step_not_monotonic"
		if event.world_time < 0 or event.world_time > world_time or event.world_time < previous_time:
			return "event_time_not_monotonic"
		previous_step = event.step_index
		previous_time = event.world_time
		if not (event.type is String) or event.type.is_empty():
			return "event_type_invalid"
		if event.magnitude < 0 or event.magnitude > MAX_SMALL_VALUE:
			return "event_magnitude_invalid"
		if not _runtime_position_is_valid(event.position, true):
			return "event_position_invalid"
		if not _is_valid_event_data(event.data):
			return "event_data_invalid"
		if event.cause_id == -1:
			if event.instigator_id != event.actor_id:
				return "root_instigator_mismatch"
		else:
			if event.cause_id <= 0 or event.cause_id >= event.id:
				return "event_cause_not_older"
			var cause = event_by_id(event.cause_id)
			if cause == null or event.world_time < cause.world_time:
				return "event_cause_time_invalid"
			if event.instigator_id != cause.instigator_id:
				return "derived_instigator_mismatch"
		for reference_id in [event.actor_id, event.target_id, event.instigator_id]:
			if reference_id != -1 and (reference_id <= 0 or not entities.has(reference_id)):
				return "event_entity_reference_invalid"
	for tile_index in range(tiles.size()):
		var tile = tiles[tile_index]
		if (tile.fire == 0) != (tile.fire_source_event_id == -1):
			return "fire_source_sentinel_mismatch"
		if (tile.fire == 0) != (tile.fire_damage_eligible_time == -1):
			return "fire_eligibility_sentinel_mismatch"
		if (tile.wetness == 0) != (tile.wetness_source_event_id == -1):
			return "wetness_source_sentinel_mismatch"
		var tile_position := Vector2i(tile_index % width, int(tile_index / width))
		if tile.fire > 0:
			var fire_source = event_by_id(tile.fire_source_event_id)
			if fire_source == null or fire_source.world_time > world_time:
				return "fire_source_missing_or_future"
			if fire_source.position != tile_position:
				return "fire_source_position_mismatch"
			if fire_source.type != "environment.ignited" \
					and fire_source.type != "environment.fire_spread":
				return "fire_source_type_invalid"
			var expected_eligibility: int = fire_source.world_time
			if fire_source.type == "environment.fire_spread":
				if fire_source.world_time > 9223372036854775807 - ENVIRONMENT_INTERVAL:
					return "fire_eligibility_overflow"
				expected_eligibility += ENVIRONMENT_INTERVAL
			if tile.fire_damage_eligible_time != expected_eligibility:
				return "fire_eligibility_source_mismatch"
		if tile.wetness > 0:
			var wetness_source = event_by_id(tile.wetness_source_event_id)
			if wetness_source == null or wetness_source.world_time > world_time:
				return "wetness_source_missing_or_future"
			if wetness_source.type != "environment.water_applied" \
					or wetness_source.position != tile_position \
					or wetness_source.magnitude <= 0:
				return "wetness_source_semantic_invalid"
	for relation_key in personal_relations:
		var relation = personal_relations[relation_key]
		if relation.observer_id == relation.subject_id:
			return "self_relation_invalid"
		if not entities.has(relation.observer_id) or not entities.has(relation.subject_id):
			return "relation_entity_missing"
		if relation_key != "%d:%d" % [relation.observer_id, relation.subject_id]:
			return "relation_key_mismatch"
		if relation.personal_trust_delta < -40 or relation.personal_trust_delta > 40 \
				or relation.personal_fear_delta < -30 or relation.personal_fear_delta > 30 \
				or relation.gratitude < 0 or relation.gratitude > 100 \
				or relation.grievance < 0 or relation.grievance > 100:
			return "relation_value_invalid"
		var unique_sources: Dictionary = {}
		for source_id in relation.processed_source_event_ids:
			if source_id <= 0 or event_by_id(source_id) == null:
				return "relationship_source_missing"
			if unique_sources.has(source_id):
				return "relationship_source_duplicated"
			unique_sources[source_id] = true
	if next_schedule_id <= 0:
		return "nonpositive_next_schedule_id"
	var schedule_ids: Dictionary = {}
	var max_schedule_id := 0
	var prior_key: Array = [-1, -2147483648, -1]
	for entry in scheduled_entries:
		if not (entry is Dictionary) or not entry.has_all([
				"schedule_id", "due_time", "priority", "kind", "owner_id",
				"source_event_id", "repeat_interval", "payload"]):
			return "schedule_shape_invalid"
		if not (entry["schedule_id"] is int) or not (entry["due_time"] is int) \
				or not (entry["repeat_interval"] is int) \
				or not (entry["priority"] is int) or not (entry["kind"] is String) \
				or not (entry["owner_id"] is int) or not (entry["source_event_id"] is int) \
				or not (entry["payload"] is Dictionary):
			return "schedule_scalar_type_invalid"
		var schedule_id: int = entry["schedule_id"]
		if schedule_id <= 0 or schedule_ids.has(schedule_id):
			return "duplicate_or_invalid_schedule_id"
		schedule_ids[schedule_id] = true
		max_schedule_id = maxi(max_schedule_id, schedule_id)
		if int(entry["due_time"]) <= world_time or int(entry["due_time"]) > MAX_WORLD_TIME \
				or int(entry["repeat_interval"]) < 0 \
				or int(entry["repeat_interval"]) > MAX_WORLD_TIME \
				or int(entry["priority"]) < -MAX_SMALL_VALUE \
				or int(entry["priority"]) > MAX_SMALL_VALUE:
			return "schedule_time_invalid"
		if entry["kind"] != "system.environment_tick" \
				or not _entity_reference_is_valid(entry["owner_id"]) \
				or (entry["source_event_id"] != -1 \
					and event_by_id(entry["source_event_id"]) == null):
			return "schedule_reference_or_kind_invalid"
		if not _is_valid_event_data(entry["payload"]):
			return "schedule_payload_invalid"
		var key: Array = [entry["due_time"], entry["priority"], schedule_id]
		if not _lexicographic_not_less(key, prior_key):
			return "schedules_not_sorted"
		prior_key = key
	if next_schedule_id <= max_schedule_id:
		return "next_schedule_id_collision"
	if scheduled_entries.size() != 1:
		return "invalid_environment_schedule_count"
	var environment_entry: Dictionary = scheduled_entries[0]
	if environment_entry["kind"] != "system.environment_tick" \
			or environment_entry["priority"] != 100 \
			or environment_entry["repeat_interval"] != ENVIRONMENT_INTERVAL:
		return "invalid_environment_schedule_rules"
	if environment_entry["owner_id"] != -1 or environment_entry["source_event_id"] != -1 \
			or not environment_entry["payload"].is_empty():
		return "invalid_environment_schedule_contract"
	var next_cadence := world_time - (world_time % ENVIRONMENT_INTERVAL) + ENVIRONMENT_INTERVAL
	if environment_entry["due_time"] != next_cadence:
		return "invalid_environment_schedule_cadence"
	return ""


func _runtime_position_is_valid(position: Vector2i, allow_sentinel: bool) -> bool:
	return (allow_sentinel and position == Vector2i(-1, -1)) or in_bounds(position)


func _terrain_is_passable(position: Vector2i) -> bool:
	if not in_bounds(position):
		return false
	var definition: Dictionary = TerrainRegistryScript.definition(tile_at(position).terrain)
	return not definition.is_empty() and bool(definition["passable"]) \
		and int(definition["occupancy_capacity"]) >= 1


func _entity_reference_is_valid(entity_id: int) -> bool:
	return entity_id == -1 or (entity_id > 0 and entities.has(entity_id))


func _sort_schedules() -> void:
	scheduled_entries.sort_custom(func(a: Dictionary, b: Dictionary):
		if a["due_time"] != b["due_time"]:
			return a["due_time"] < b["due_time"]
		if a["priority"] != b["priority"]:
			return a["priority"] < b["priority"]
		return a["schedule_id"] < b["schedule_id"]
	)


static func _schedule_to_dict(entry: Dictionary) -> Dictionary:
	return {
		"schedule_id": str(entry["schedule_id"]), "due_time": str(entry["due_time"]),
		"priority": entry["priority"], "kind": entry["kind"], "owner_id": str(entry["owner_id"]),
		"source_event_id": str(entry["source_event_id"]),
		"repeat_interval": str(entry["repeat_interval"]), "payload": entry["payload"].duplicate(true),
	}


static func _schedule_from_dict(row: Dictionary) -> Dictionary:
	return {
		"schedule_id": parse_canonical_int64(row["schedule_id"], "schedule ID"),
		"due_time": parse_canonical_int64(row["due_time"], "schedule due time"),
		"priority": int(row["priority"]), "kind": str(row["kind"]),
		"owner_id": parse_canonical_int64(row.get("owner_id", "-1"), "schedule owner ID"),
		"source_event_id": parse_canonical_int64(row.get("source_event_id", "-1"), "schedule source event ID"),
		"repeat_interval": parse_canonical_int64(row.get("repeat_interval", "0"), "schedule repeat interval"),
		"payload": SimEventScript._restore_json_types(row.get("payload", {})),
	}


static func _lexicographic_not_less(a: Array, b: Array) -> bool:
	for index in range(mini(a.size(), b.size())):
		if a[index] > b[index]:
			return true
		if a[index] < b[index]:
			return false
	return a.size() >= b.size()


static func _is_valid_event_data(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT:
			return value >= -MAX_SAFE_JSON_INTEGER and value <= MAX_SAFE_JSON_INTEGER
		TYPE_STRING, TYPE_BOOL:
			return true
		TYPE_ARRAY:
			for item in value:
				if not _is_valid_event_data(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not (key is String) or not _is_valid_event_data(value[key]):
					return false
			return true
		_:
			return false
