class_name SimWorldState
extends RefCounted

const SNAPSHOT_VERSION := 5
const RULESET_VERSION := "phase4-party-encounter-v1"
const CALENDAR_RULESET_ID := "abstract-calendar-v1"
const TERRAIN_RULESET_ID := "terrain-registry-v1"
const HAZARD_AFFINITY_RULESET_ID := "hazard-affinity-v1"
const PERSONALITY_SCHEMA_ID := "personality-facets-v1"
const PERSONALITY_GENERATOR_RULESET_ID := "personality-lab-latin-hypercube-v1"
const KEYED_HASH_RULESET_ID := "sha256-u31-v1"
const DECISION_RULESET_ID := "dungeon-hierarchical-utility-v1"
const SCORE_COMBINER_ID := "weighted-sum-v1"
const COMBAT_RULESET_ID := "fixed-melee-v1"
const ENVIRONMENT_INTERVAL := 100
const ACTOR_INTERVAL := 100
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
const AgentStateScript = preload("res://sim/agent_state.gd")
const PersonalityRegistryScript = preload("res://sim/personality_definition_registry.gd")
const DecisionRegistryScript = preload("res://sim/decision_ruleset_registry.gd")
const EncounterLabStateScript = preload("res://sim/encounter_lab_state.gd")
const PartyEncounterStateScript = preload("res://sim/party_encounter_state.gd")
const PartyMemberStateScript = preload("res://sim/party_member_state.gd")
const FixedPointScript = preload("res://sim/fixed_point.gd")

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
var agent_states: Dictionary = {}
var encounter_lab = null
var party_encounter = null
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
	_insert_schedule_entry("system.environment_tick", ENVIRONMENT_INTERVAL, 100, -1, -1, ENVIRONMENT_INTERVAL, {})
	_insert_schedule_entry("system.actor_tick", ACTOR_INTERVAL, 200, -1, -1, ACTOR_INTERVAL, {})


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


func movement_neighbors(position: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in [Vector2i.UP, Vector2i(1, -1), Vector2i.RIGHT, Vector2i(1, 1),
			Vector2i.DOWN, Vector2i(-1, 1), Vector2i.LEFT, Vector2i(-1, -1)]:
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


func add_lab_actor(controller_kind: String, trial_slot: int, position: Vector2i,
		display_name: String, species_id: String, max_health: int = 100):
	if not AgentStateScript.CONTROLLERS.has(controller_kind) or trial_slot < 0 or trial_slot > 3:
		return null
	var entity = add_entity(controller_kind.to_lower(), display_name, position, max_health,
		["lab_actor", controller_kind.to_lower()], species_id, "lab")
	if entity == null:
		return null
	var state = AgentStateScript.new(entity.id, controller_kind, trial_slot)
	state.busy_until = world_time
	state.intent_started_time = world_time
	state.emotion_updated_time = world_time
	agent_states[entity.id] = state
	return entity


func bootstrap_set_world_time(p_world_time: int) -> bool:
	if _active_step_index != -1 or step_index != 0 or not events.is_empty() \
			or p_world_time < 0 or p_world_time > MAX_WORLD_TIME - ENVIRONMENT_INTERVAL:
		return false
	world_time = p_world_time
	var next_boundary: int = (world_time / ENVIRONMENT_INTERVAL + 1) * ENVIRONMENT_INTERVAL
	for entry in scheduled_entries:
		entry["due_time"] = next_boundary
	_sort_schedules()
	for state in agent_states.values():
		state.emotion_updated_time = world_time
		state.busy_until = world_time
		state.intent_started_time = world_time
	return true


func entities_at(position: Vector2i) -> Array:
	return occupying_entities_at(position)


func occupying_entities_at(position: Vector2i) -> Array:
	var result: Array = []
	var ids: Array = entities.keys()
	ids.sort()
	for entity_id in ids:
		var entity = entities[entity_id]
		var state = agent_states.get(entity_id)
		var party_state = party_member_state(entity_id)
		var party_occupies: bool = party_state == null or party_state.presence == "DEPLOYED"
		if entity.position == position and entity.is_alive() and party_occupies \
				and (state == null or state.encounter_status == "ACTIVE"):
			result.append(entity)
	return result


func exposed_entities_at(position: Vector2i) -> Array:
	var result: Array = []
	var ids: Array = entities.keys(); ids.sort()
	for entity_id in ids:
		var entity = entities[entity_id]
		if not entity.is_alive(): continue
		var party_state = party_member_state(entity_id)
		if party_state != null:
			if party_state.presence == "DEPLOYED" and entity.position == position:
				result.append(entity)
			elif party_state.presence == "GROUPED" and party_encounter.group_anchor == position:
				result.append(entity)
			continue
		var state = agent_states.get(entity_id)
		if entity.position == position and (state == null or state.encounter_status == "ACTIVE"):
			result.append(entity)
	return result


func party_member_state(entity_id: int):
	return null if party_encounter == null else party_encounter.member(entity_id)


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
	var low := 0
	var high := events.size() - 1
	while low <= high:
		var midpoint: int = low + (high - low) / 2
		var event = events[midpoint]
		if event.id == event_id: return event
		if event.id < event_id: low = midpoint + 1
		else: high = midpoint - 1
	return null


func events_since(index: int) -> Array:
	return events.slice(index)


func has_event_id_headroom(maximum_new_events: int) -> bool:
	return maximum_new_events >= 0 and _next_event_id > 0 \
		and _next_event_id <= 9223372036854775807 - maximum_new_events


func schedule_entry(kind: String, due_time: int, priority: int = 100,
		owner_id: int = -1, source_event_id: int = -1, repeat_interval: int = 0,
		payload: Dictionary = {}) -> int:
	# Canonical schedules are installed atomically by construction/bootstrap.
	# Runtime producers cannot add logical cadence IDs.
	return -1


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
	if not ["system.environment_tick", "system.actor_tick"].has(kind) or due_time <= world_time \
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
	var agent_rows: Array = []
	var agent_ids: Array = agent_states.keys()
	agent_ids.sort()
	for entity_id in agent_ids:
		agent_rows.append(agent_states[entity_id].to_dict())
	return {
		"snapshot_version": SNAPSHOT_VERSION,
		"ruleset_version": RULESET_VERSION,
		"calendar_ruleset_id": CALENDAR_RULESET_ID,
		"terrain_ruleset_id": TERRAIN_RULESET_ID,
		"hazard_affinity_ruleset_id": HAZARD_AFFINITY_RULESET_ID,
		"personality_schema_id": PERSONALITY_SCHEMA_ID,
		"personality_generator_ruleset_id": PERSONALITY_GENERATOR_RULESET_ID,
		"keyed_hash_ruleset_id": KEYED_HASH_RULESET_ID,
		"decision_ruleset_id": DECISION_RULESET_ID,
		"score_combiner_id": SCORE_COMBINER_ID,
		"combat_ruleset_id": COMBAT_RULESET_ID,
		"width": width, "height": height,
		"step_index": str(step_index), "world_time": str(world_time), "seed": str(seed),
		"rng_state": str(rng.state),
		"next_entity_id": str(_next_entity_id), "next_event_id": str(_next_event_id),
		"next_schedule_id": str(next_schedule_id), "scheduled_entries": schedule_rows,
		"agent_states": agent_rows,
		"encounter_lab": null if encounter_lab == null else encounter_lab.to_dict(),
		"party_encounter": null if party_encounter == null else party_encounter.to_dict(),
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
	restored.agent_states.clear()
	for row in data.get("agent_states", []):
		var state = AgentStateScript.from_dict(row)
		restored.agent_states[state.entity_id] = state
	restored.encounter_lab = null if data.get("encounter_lab") == null else EncounterLabStateScript.from_dict(data.encounter_lab)
	restored.party_encounter = null if data.get("party_encounter") == null else PartyEncounterStateScript.from_dict(data.party_encounter)
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
	for pair in [["personality_schema_id", PERSONALITY_SCHEMA_ID],
			["personality_generator_ruleset_id", PERSONALITY_GENERATOR_RULESET_ID],
			["keyed_hash_ruleset_id", KEYED_HASH_RULESET_ID], ["decision_ruleset_id", DECISION_RULESET_ID],
			["score_combiner_id", SCORE_COMBINER_ID], ["combat_ruleset_id", COMBAT_RULESET_ID]]:
		if not (data.get(pair[0]) is String) or data.get(pair[0]) != pair[1]: return "unsupported_%s" % pair[0]
	return ""


static func snapshot_wire_error(data: Dictionary) -> String:
	var header_error := snapshot_header_error(data)
	if not header_error.is_empty():
		return header_error
	var top_keys: Array = data.keys(); top_keys.sort()
	if top_keys != ["agent_states", "calendar_ruleset_id", "combat_ruleset_id", "decision_ruleset_id",
			"encounter_lab", "entities", "events", "hazard_affinity_ruleset_id", "height",
			"keyed_hash_ruleset_id", "next_entity_id", "next_event_id", "next_schedule_id",
			"party_encounter", "personal_relations", "personality_generator_ruleset_id",
			"personality_schema_id", "rng_state", "ruleset_version", "scheduled_entries",
			"score_combiner_id", "seed", "snapshot_version", "species_relations", "step_index",
			"terrain_ruleset_id", "tiles", "width", "world_time"]:
		return "invalid_snapshot_top_level_keys"
	if not data.has("encounter_lab") or not data.has("party_encounter"):
		return "missing_encounter_mode_key"
	if data.get("encounter_lab") != null and data.get("party_encounter") != null:
		return "encounter_mode_conflict"
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
		if row.get("type") == "ai.decision_selected":
			var trace_error := _decision_trace_wire_error(row.get("data"))
			if not trace_error.is_empty(): return trace_error
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
		var relation_keys: Array = row.keys(); relation_keys.sort()
		if relation_keys != ["gratitude", "grievance", "observer_id", "personal_fear_delta",
				"personal_trust_delta", "processed_source_event_ids", "subject_id"]:
			return "invalid_personal_relation_keys"
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
	if not (data.get("agent_states") is Array):
		return "invalid_agent_states_shape"
	var agent_ids: Dictionary = {}
	for row in data["agent_states"]:
		if not (row is Dictionary) or not Int64CodecScript.is_canonical(row.get("entity_id")) \
				or not (row.get("controller_kind") is String) or not AgentStateScript.CONTROLLERS.has(row.controller_kind):
			return "invalid_agent_state_shape"
		var agent_id := Int64CodecScript.parse(row["entity_id"], "agent ID")
		if not entity_ids.has(agent_id) or agent_ids.has(agent_id):
			return "invalid_or_duplicate_agent_entity"
		agent_ids[agent_id] = true
		if not _is_small_int(row.get("trial_slot"), 0, 3) or row.get("encounter_status") not in AgentStateScript.ENCOUNTER_STATUSES:
			return "invalid_agent_trial_or_status"
		for key in ["busy_until", "intent_target_entity_id", "intent_started_time", "emotion_updated_time",
				"mental_mode_since", "active_threat_id", "threat_notice_event_id", "last_seen_time",
				"guarded_until", "commitment_until", "last_decision_time", "last_decision_event_id"]:
			if not Int64CodecScript.is_canonical(row.get(key)):
				return "noncanonical_agent_%s" % key
		if row.get("current_activity") not in AgentStateScript.ACTIVITIES or row.get("current_reaction") not in AgentStateScript.REACTIONS \
				or row.get("mental_mode") not in AgentStateScript.MODES:
			return "unknown_agent_activity_or_mode"
		if not _is_position(row.get("intent_target_position"), restored_width, restored_height, true):
			return "invalid_agent_target_position"
		if not _is_position(row.get("last_seen_position"), restored_width, restored_height, true) \
				or not _is_small_int(row.get("fear"), 0, 2000) or not _is_small_int(row.get("anger"), 0, 2000):
			return "invalid_agent_affect"
		if row.controller_kind == "LEAD":
			var profile_error := PersonalityRegistryScript.profile_wire_error(row.get("personality_profile"))
			if not profile_error.is_empty(): return profile_error
		elif row.has("personality_profile"):
			return "personality_forbidden_for_controller"
		if not (row.get("action_history_rows") is Array) or row.action_history_rows.size() > 8:
			return "invalid_action_history_shape"
		var previous_action := ""
		for history in row.action_history_rows:
			if not (history is Dictionary) or history.get("action_id") not in DecisionRegistryScript.ACTION_IDS \
					or (not previous_action.is_empty() and str(history.action_id) <= previous_action): return "invalid_action_history"
			for key in ["cooldown_until", "last_committed_time"]:
				if not Int64CodecScript.is_canonical(history.get(key)): return "noncanonical_action_history"
			if not _is_small_int(history.get("consecutive_commit_count"), 0, MAX_SMALL_VALUE): return "invalid_action_repeat_count"
			previous_action = str(history.action_id)
	if data.get("encounter_lab") != null:
		var lab = data.encounter_lab
		if not (lab is Dictionary) or not Int64CodecScript.is_canonical(lab.get("personality_seed")) \
				or lab.get("phase") not in EncounterLabStateScript.PHASES or not Int64CodecScript.is_canonical(lab.get("activation_time")) \
				or lab.get("threat_profile_id") != "lab-melee-threat-v1" or not (lab.get("appearance_event_ids") is Array) \
				or lab.appearance_event_ids.size() != 4: return "invalid_encounter_lab"
		for id in lab.appearance_event_ids:
			if not Int64CodecScript.is_canonical(id): return "noncanonical_appearance_event"
	if data.get("encounter_lab") != null and data.get("party_encounter") != null:
		return "encounter_mode_conflict"
	if data.get("party_encounter") != null:
		var party_error := PartyEncounterStateScript.wire_error(data.party_encounter, restored_width, restored_height)
		if not party_error.is_empty(): return party_error
	if not (data.get("scheduled_entries") is Array):
		return "invalid_schedules_shape"
	var schedules: Array = data["scheduled_entries"]
	if schedules.size() != 2:
		return "invalid_canonical_schedule_count"
	var expected_due := parsed_time - (parsed_time % ENVIRONMENT_INTERVAL) + ENVIRONMENT_INTERVAL
	for index in range(2):
		if not (schedules[index] is Dictionary):
			return "invalid_schedule_shape"
		var schedule: Dictionary = schedules[index]
		for key in ["schedule_id", "due_time", "owner_id", "source_event_id", "repeat_interval"]:
			if not Int64CodecScript.is_canonical(schedule.get(key)):
				return "noncanonical_schedule_%s" % key
		var expected_kind := "system.environment_tick" if index == 0 else "system.actor_tick"
		var expected_priority := 100 if index == 0 else 200
		if schedule.get("kind") != expected_kind or not _is_small_int(schedule.get("priority"), expected_priority, expected_priority):
			return "invalid_canonical_schedule_kind_or_priority"
		if schedule.get("repeat_interval") != "100" or schedule.get("owner_id") != "-1" \
				or schedule.get("source_event_id") != "-1" or not (schedule.get("payload") is Dictionary) \
				or not schedule["payload"].is_empty() or not _is_json_safe_metadata(schedule["payload"]):
			return "invalid_canonical_schedule_contract"
		if Int64CodecScript.parse(schedule["due_time"], "schedule due") != expected_due:
			return "invalid_canonical_schedule_cadence"
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
	if encounter_lab != null and party_encounter != null:
		return "encounter_mode_conflict"
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
		var actor_state = agent_states.get(entity_id)
		var party_state = party_member_state(entity_id)
		if entity.is_alive() and (party_state == null or party_state.presence == "DEPLOYED") \
				and (actor_state == null or actor_state.encounter_status == "ACTIVE"):
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
		if event.type == "ai.decision_selected":
			var trace_error := _decision_trace_wire_error(event.data)
			if not trace_error.is_empty(): return trace_error
			if not agent_states.has(event.actor_id) or int(event.data.get("trial_slot", -1)) != agent_states[event.actor_id].trial_slot:
				return "decision_trace_actor_slot_mismatch"
			var decision_state = agent_states[event.actor_id]
			if decision_state.controller_kind != "LEAD" or event.data.mental_mode not in AgentStateScript.MODES:
				return "decision_trace_actor_invalid"
			var profile_wire := {"profile_schema_version": 1,
				"generation_ruleset_id": PERSONALITY_GENERATOR_RULESET_ID,
				"facet_rows": event.data.personality_facet_rows}
			if not PersonalityRegistryScript.profile_wire_error(profile_wire).is_empty() \
					or event.data.personality_facet_rows != decision_state.personality_profile.facet_rows:
				return "decision_trace_personality_invalid"
			var mode_evidence: Dictionary = event.data.mode_transition_evidence
			var mode_source_id := Int64CodecScript.parse(mode_evidence.source_event_id, "mode evidence source")
			var mode_source = event_by_id(mode_source_id)
			if mode_source == null or mode_source.type != "perception.threat_noticed" \
					or mode_source.actor_id != event.actor_id or mode_source.id >= event.id:
				return "mode_transition_source_invalid"
			if bool(mode_evidence.transitioned):
				var transition_event = event_by_id(event.cause_id)
				if transition_event == null or transition_event.type != "ai.mental_mode_changed" \
						or transition_event.actor_id != event.actor_id \
						or transition_event.cause_id != mode_source_id \
						or transition_event.data.get("from_mode") != mode_evidence.from_mode \
						or transition_event.data.get("to_mode") != mode_evidence.to_mode \
						or transition_event.data.get("panic_pressure") != mode_evidence.panic_pressure \
						or event.data.mental_mode != mode_evidence.to_mode:
					return "mode_transition_evidence_mismatch"
			elif mode_evidence.from_mode != mode_evidence.to_mode \
					or mode_evidence.to_mode != event.data.mental_mode or event.cause_id != mode_source_id:
				return "mode_transition_evidence_mismatch"
			var seen_candidate_ids: Dictionary = {}
			for candidate in event.data.candidates:
				if seen_candidate_ids.has(candidate.reaction_id): return "decision_trace_candidate_duplicate"
				seen_candidate_ids[candidate.reaction_id] = true
				var definition = DecisionRegistryScript.action(candidate.reaction_id)
				if definition == null or candidate.base_score != definition.base_score \
						or candidate.considerations.size() != definition.considerations.size() \
						or candidate.gates.size() != definition.gates.size():
					return "decision_trace_definition_mismatch"
				var trace_target_id := Int64CodecScript.parse(candidate.target_entity_id, "trace target")
				if trace_target_id > 0 and (not agent_states.has(trace_target_id) \
						or agent_states[trace_target_id].trial_slot != agent_states[event.actor_id].trial_slot):
					return "decision_trace_cross_chamber_target"
				var trace_position := Vector2i(int(candidate.target_position[0]), int(candidate.target_position[1]))
				if trace_position != Vector2i(-1, -1) and (not in_bounds(trace_position) \
						or _trial_slot_for_position(trace_position) != decision_state.trial_slot):
					return "decision_trace_cross_chamber_position"
				var expected_considerations: Dictionary = {}
				for definition_row in definition.considerations:
					expected_considerations[definition_row.consideration_id] = definition_row
				var seen_considerations: Dictionary = {}
				var recomputed_score: int = candidate.base_score
				for consideration in candidate.considerations:
					var expected = expected_considerations.get(consideration.consideration_id)
					if expected == null or seen_considerations.has(consideration.consideration_id) \
							or consideration.input_id != expected.input_id \
							or consideration.curve_id != expected.curve_id \
							or consideration.signed_weight_milli != expected.signed_weight_milli \
							or consideration.raw_input != consideration.normalized_input \
							or consideration.curve_output != DecisionRegistryScript.evaluate_curve(consideration.curve_id, consideration.normalized_input) \
							or consideration.contribution != FixedPointScript.weighted_contribution(consideration.curve_output, consideration.signed_weight_milli):
						return "decision_trace_consideration_definition_mismatch"
					seen_considerations[consideration.consideration_id] = true
					recomputed_score = clampi(recomputed_score + int(consideration.contribution), -1000000, 1000000)
					for evidence_wire in consideration.evidence_ids:
						var evidence_id := Int64CodecScript.parse(evidence_wire, "trace evidence")
						var evidence_event = event_by_id(evidence_id)
						if evidence_event == null: return "decision_trace_evidence_missing"
						if evidence_event.id >= event.id or evidence_event.world_time > event.world_time:
							return "decision_trace_evidence_not_older"
						if evidence_event.type != "perception.threat_noticed" \
								or evidence_event.actor_id != event.actor_id \
								or not agent_states.has(evidence_event.target_id) \
								or agent_states[evidence_event.target_id].trial_slot != decision_state.trial_slot:
							return "decision_trace_evidence_actor_mismatch"
				var seen_gate_ids: Dictionary = {}
				for gate in candidate.gates:
					var matching_gate := false
					for gate_definition in definition.gates:
						if gate.gate_id == gate_definition.gate_id: matching_gate = true; break
					if not matching_gate or seen_gate_ids.has(gate.gate_id): return "decision_trace_gate_definition_mismatch"
					seen_gate_ids[gate.gate_id] = true
					for evidence_wire in gate.evidence_ids:
						var evidence_id := Int64CodecScript.parse(evidence_wire, "trace evidence")
						var evidence_event = event_by_id(evidence_id)
						if evidence_event == null: return "decision_trace_evidence_missing"
						if evidence_event.id >= event.id or evidence_event.world_time > event.world_time:
							return "decision_trace_evidence_not_older"
						if evidence_event.type != "perception.threat_noticed" \
								or evidence_event.actor_id != event.actor_id \
								or not agent_states.has(evidence_event.target_id) \
								or agent_states[evidence_event.target_id].trial_slot != decision_state.trial_slot:
							return "decision_trace_evidence_actor_mismatch"
				for gate_definition in definition.gates:
					if not seen_gate_ids.has(gate_definition.gate_id): return "decision_trace_gate_definition_mismatch"
				var any_veto := false
				var expected_rejection_reason := ""
				for gate in candidate.gates:
					if gate.veto:
						any_veto = true
						if expected_rejection_reason.is_empty(): expected_rejection_reason = gate.reason
				if candidate.legal == any_veto or candidate.rejection_reason != expected_rejection_reason:
					return "decision_trace_legality_mismatch"
				if recomputed_score != candidate.score: return "decision_trace_score_mismatch"
			var expected_candidates = DecisionRegistryScript.mode(event.data.mental_mode).candidate_action_ids
			if seen_candidate_ids.size() != expected_candidates.size(): return "decision_trace_mode_candidates_incomplete"
			for expected_action_id in expected_candidates:
				if not seen_candidate_ids.has(expected_action_id): return "decision_trace_mode_candidates_incomplete"
			var switch_evidence: Dictionary = event.data.switch_evidence
			if switch_evidence.selected_reaction != event.data.reaction_id \
					or switch_evidence.retained != event.data.retained:
				return "switch_evidence_selected_mismatch"
			var challenger_found := false
			for candidate in event.data.candidates:
				if candidate.reaction_id == switch_evidence.challenger_reaction:
					challenger_found = true
					if candidate.score != switch_evidence.challenger_score: return "switch_evidence_score_mismatch"
			if not challenger_found: return "switch_evidence_challenger_missing"
			var previous_reaction: String = str(switch_evidence.previous_reaction)
			var switch_reason: String = str(switch_evidence.reason_code)
			var parsed_commitment := Int64CodecScript.parse(switch_evidence.commitment_until, "trace commitment")
			var parsed_cooldown := Int64CodecScript.parse(switch_evidence.challenger_cooldown_until, "trace cooldown")
			if parsed_commitment < 0 or parsed_commitment > MAX_WORLD_TIME \
					or parsed_cooldown < 0 or parsed_cooldown > MAX_WORLD_TIME:
				return "switch_evidence_time_invalid"
			if previous_reaction == "NONE":
				if switch_reason != "entered" or switch_evidence.retained: return "switch_evidence_reason_invalid"
			elif switch_reason == "mode_transition_reset":
				if not bool(mode_evidence.transitioned) or switch_evidence.retained: return "switch_evidence_reason_invalid"
			else:
				var previous_definition = DecisionRegistryScript.action(previous_reaction)
				if previous_definition == null or switch_evidence.switch_margin != previous_definition.switch_margin:
					return "switch_evidence_margin_invalid"
				if switch_evidence.retained != (switch_reason in ["continued_best", "retained_commitment", "retained_margin"]) \
						or (switch_evidence.retained and switch_evidence.selected_reaction != previous_reaction) \
						or (not switch_evidence.retained and switch_evidence.selected_reaction == previous_reaction):
					return "switch_evidence_reason_invalid"
			if not seen_candidate_ids.has(event.data.reaction_id): return "decision_trace_selected_candidate_missing"
			for candidate in event.data.candidates:
				if candidate.reaction_id == event.data.reaction_id:
					if not candidate.legal or candidate.score != event.data.selected_score:
						return "decision_trace_selected_score_mismatch"
					if Int64CodecScript.parse(candidate.target_entity_id, "selected target") != event.target_id:
						return "decision_trace_selected_target_mismatch"
					var selected_position := Vector2i(int(candidate.target_position[0]), int(candidate.target_position[1]))
					if event.data.semantic_target != _lab_semantic_name(decision_state.trial_slot, selected_position):
						return "decision_trace_semantic_target_mismatch"
			if event.target_id > 0 and (not agent_states.has(event.target_id) \
					or agent_states[event.target_id].trial_slot != decision_state.trial_slot):
				return "decision_event_cross_chamber_target"
			var decision_cause = event_by_id(event.cause_id)
			if decision_cause == null: return "decision_event_cause_missing"
			if decision_cause.type == "ai.mental_mode_changed":
				if decision_cause.actor_id != event.actor_id: return "decision_event_mode_cause_actor_mismatch"
				decision_cause = event_by_id(decision_cause.cause_id)
			if decision_cause == null or decision_cause.type != "perception.threat_noticed" \
					or decision_cause.actor_id != event.actor_id:
				return "decision_event_perception_cause_invalid"
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
		if encounter_lab != null:
			var event_actor_state = agent_states.get(event.actor_id)
			if event.type in ["action.move", "action.melee_attack", "action.hold", "action.freeze", "encounter.actor_escaped"] \
					and event_actor_state != null and event_actor_state.controller_kind == "LEAD":
				var leaf_cause = event_by_id(event.cause_id)
				if leaf_cause == null or leaf_cause.type != "ai.decision_selected" \
						or leaf_cause.actor_id != event.actor_id or leaf_cause.world_time != event.world_time:
					return "lead_leaf_decision_cause_invalid"
				var allowed_leaf_types: Dictionary = {
					"ENGAGE": ["action.move", "action.melee_attack"],
					"PROTECT": ["action.move", "action.melee_attack"],
					"FLEE": ["action.move", "encounter.actor_escaped"],
					"TAKE_COVER": ["action.move", "action.hold"],
					"HOLD": ["action.hold"], "FREEZE": ["action.freeze"],
				}
				var leaf_reaction: String = str(leaf_cause.data.get("reaction_id", ""))
				if not allowed_leaf_types.has(leaf_reaction) or event.type not in allowed_leaf_types[leaf_reaction]:
					return "reaction_leaf_mapping_invalid"
				var semantic_position := Vector2i(-1, -1)
				for candidate in leaf_cause.data.candidates:
					if candidate.reaction_id == leaf_reaction:
						semantic_position = Vector2i(int(candidate.target_position[0]), int(candidate.target_position[1]))
						break
				if semantic_position == Vector2i(-1, -1): return "reaction_leaf_target_missing"
				if event.type in ["action.hold", "action.freeze", "encounter.actor_escaped"] \
						and event.position != semantic_position:
					return "reaction_leaf_semantic_position_invalid"
			if event.type == "action.move":
				var move_keys: Array = event.data.keys(); move_keys.sort()
				if move_keys != ["from_position", "move_time_cost", "terrain_id", "to_position"] \
						or not _is_position(event.data.get("from_position"), width, height, false) \
						or not _is_position(event.data.get("to_position"), width, height, false) \
						or not (event.data.get("terrain_id") is String) \
						or not (event.data.get("move_time_cost") is int):
					return "move_event_payload_invalid"
				var move_from := Vector2i(int(event.data.from_position[0]), int(event.data.from_position[1]))
				var move_to := Vector2i(int(event.data.to_position[0]), int(event.data.to_position[1]))
				var move_definition: Dictionary = TerrainRegistryScript.definition(str(event.data.terrain_id))
				if event_actor_state == null or _trial_slot_for_position(move_from) != event_actor_state.trial_slot \
						or _trial_slot_for_position(move_to) != event_actor_state.trial_slot \
						or maxi(absi(move_to.x - move_from.x), absi(move_to.y - move_from.y)) != 1 \
						or event.position != move_to or tile_at(move_to).terrain != event.data.terrain_id \
						or move_definition.is_empty() or not bool(move_definition.passable) \
						or event.data.move_time_cost != move_definition.move_time_cost \
						or event.magnitude != event.data.move_time_cost:
					return "move_event_semantic_invalid"
			if event.type == "action.melee_attack":
				var melee_target_state = agent_states.get(event.target_id)
				if event_actor_state == null or melee_target_state == null \
						or event_actor_state.trial_slot != melee_target_state.trial_slot \
						or _trial_slot_for_position(event.position) != event_actor_state.trial_slot \
						or event.data != {"combat_ruleset_id": "fixed-melee-v1"} \
						or event.magnitude != (22 if event_actor_state.controller_kind == "LEAD" else 18):
					return "melee_event_semantic_invalid"
			if event.type == "action.hold" and (event.target_id != -1 or event.magnitude != 1 or not event.data.is_empty()):
				return "hold_event_semantic_invalid"
			if event.type == "action.freeze" and (event.target_id != -1 or event.magnitude < 1 \
					or event.magnitude > 4 or not event.data.is_empty()):
				return "freeze_event_semantic_invalid"
			if event.type == "encounter.actor_escaped" and (event.target_id != -1 \
					or event.magnitude != 1 or not event.data.is_empty()):
				return "escape_event_semantic_invalid"
			if event.type == "combat.physical_damage":
				var attack_cause = event_by_id(event.cause_id)
				if event.actor_id != -1 or attack_cause == null or attack_cause.type != "action.melee_attack" \
						or attack_cause.target_id != event.target_id or attack_cause.position != event.position \
						or event.data != {"damage_type": "physical"} \
						or event.magnitude <= 0 or event.magnitude > attack_cause.magnitude:
					return "physical_damage_chain_invalid"
			if event.type == "entity.died" and str(event.data.get("damage_type", "")) == "physical":
				var damage_cause = event_by_id(event.cause_id)
				if event.actor_id != -1 or event.magnitude != 0 \
						or event.data != {"damage_type": "physical"} \
						or damage_cause == null or damage_cause.type != "combat.physical_damage" \
						or damage_cause.target_id != event.target_id or damage_cause.position != event.position:
					return "physical_death_chain_invalid"
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
		var relation_observer_state = agent_states.get(relation.observer_id)
		var relation_subject_state = agent_states.get(relation.subject_id)
		if relation_observer_state != null and relation_subject_state != null \
				and entities[relation.observer_id].tags.has("lab_actor") \
				and entities[relation.subject_id].tags.has("lab_actor") \
				and relation_observer_state.trial_slot != relation_subject_state.trial_slot:
			return "cross_chamber_relation_invalid"
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
	for entity_id in agent_states:
		var state = agent_states[entity_id]
		if not entities.has(entity_id) or state.entity_id != entity_id \
				or not entities[entity_id].tags.has("lab_actor") or not AgentStateScript.CONTROLLERS.has(state.controller_kind):
			return "agent_entity_or_controller_invalid"
		if state.trial_slot < 0 or state.trial_slot > 3 or state.encounter_status not in AgentStateScript.ENCOUNTER_STATUSES \
				or state.fear < 0 or state.fear > 2000 or state.anger < 0 or state.anger > 2000 \
				or state.emotion_updated_time < 0 or state.emotion_updated_time > world_time \
				or state.busy_until < 0 or state.busy_until > MAX_WORLD_TIME \
				or state.intent_started_time < 0 or state.intent_started_time > world_time \
				or state.mental_mode_since < 0 or state.mental_mode_since > world_time \
				or state.guarded_until < 0 or state.guarded_until > MAX_WORLD_TIME \
				or state.commitment_until < 0 or state.commitment_until > MAX_WORLD_TIME \
				or state.last_seen_time < -1 or state.last_seen_time > world_time \
				or state.last_decision_time < -1 or state.last_decision_time > world_time \
				or state.current_activity not in AgentStateScript.ACTIVITIES \
				or state.current_reaction not in AgentStateScript.REACTIONS or state.mental_mode not in AgentStateScript.MODES:
			return "agent_state_invalid"
		if state.controller_kind == "LEAD":
			var profile_error := PersonalityRegistryScript.profile_error(state.personality_profile)
			if not profile_error.is_empty(): return profile_error
		elif state.personality_profile != null: return "personality_forbidden_for_controller"
		if state.intent_target_entity_id != -1 and not entities.has(state.intent_target_entity_id):
			return "agent_intent_target_missing"
		if state.intent_target_position != Vector2i(-1, -1) and not in_bounds(state.intent_target_position):
			return "agent_intent_position_invalid"
		if state.intent_target_position != Vector2i(-1, -1) \
				and _trial_slot_for_position(state.intent_target_position) != state.trial_slot:
			return "agent_intent_position_cross_chamber"
		if state.last_decision_event_id != -1:
			var decision = event_by_id(state.last_decision_event_id)
			if decision == null or decision.type != "ai.decision_selected" or decision.actor_id != entity_id \
					or decision.world_time != state.last_decision_time:
				return "last_decision_event_invalid"
			if state.current_reaction != "NONE" and decision.data.reaction_id != state.current_reaction:
				return "last_decision_reaction_mismatch"
			var committed_leaf_events := events.filter(func(event):
				return event.cause_id == decision.id and event.actor_id == entity_id \
					and event.type in ["action.move", "action.melee_attack", "action.hold", "action.freeze", "encounter.actor_escaped"])
			if committed_leaf_events.size() != 1: return "last_decision_leaf_missing"
			var expected_activity: Dictionary = {"action.move": "MOVE", "action.melee_attack": "MELEE_ATTACK",
				"action.hold": "HOLD", "action.freeze": "FREEZE", "encounter.actor_escaped": "ESCAPE"}
			if state.current_activity != expected_activity[committed_leaf_events[0].type]:
				return "last_decision_activity_mismatch"
		var previous_action := ""
		for history in state.action_history_rows:
			if history.action_id not in DecisionRegistryScript.ACTION_IDS or (not previous_action.is_empty() and history.action_id <= previous_action) \
					or history.cooldown_until < 0 or history.cooldown_until > MAX_WORLD_TIME \
					or history.last_committed_time < -1 or history.last_committed_time > world_time \
					or history.consecutive_commit_count < 0: return "action_history_invalid"
			previous_action = history.action_id
		if state.current_reaction != "NONE":
			var current_history: Dictionary = state.history(state.current_reaction)
			if int(current_history.last_committed_time) < 0 \
					or int(current_history.last_committed_time) != state.last_decision_time \
					or int(current_history.consecutive_commit_count) <= 0:
				return "current_reaction_history_invalid"
	if encounter_lab != null:
		if width != 15 or height != 15 or entities.size() != 12:
			return "lab_fixture_dimensions_or_entity_count_invalid"
		for y in range(15):
			for x in range(15):
				var fixture_position := Vector2i(x, y)
				var fixture_wall: bool = x in [0, 7, 14] or y in [0, 7, 14] \
						or fixture_position in [Vector2i(3, 3), Vector2i(10, 3), Vector2i(3, 10), Vector2i(10, 10)]
				var expected_terrain := "wall" if fixture_wall else "floor"
				if tile_at(fixture_position).terrain != expected_terrain:
					return "lab_fixture_terrain_invalid"
		if encounter_lab.phase not in EncounterLabStateScript.PHASES or encounter_lab.activation_time != 100 \
				or encounter_lab.appearance_event_ids.size() != 4: return "encounter_lab_invalid"
		var fixture_actors: Dictionary = {}
		for slot in range(4): fixture_actors[slot] = {}
		for entity_id in agent_states:
			var state = agent_states[entity_id]
			var slot_rows: Dictionary = fixture_actors[state.trial_slot]
			if slot_rows.has(state.controller_kind): return "duplicate_lab_controller_slot"
			slot_rows[state.controller_kind] = entity_id
			fixture_actors[state.trial_slot] = slot_rows
		if agent_states.size() != 12: return "invalid_lab_actor_count"
		for slot in range(4):
			if not fixture_actors[slot].has_all(["LEAD", "PASSIVE_ALLY", "MELEE_THREAT"]):
				return "missing_lab_controller_slot"
			var controller_order := ["LEAD", "PASSIVE_ALLY", "MELEE_THREAT"]
			for role_index in range(controller_order.size()):
				var controller_kind: String = controller_order[role_index]
				var fixture_id: int = fixture_actors[slot][controller_kind]
				var fixture_entity = entities[fixture_id]
				var expected_kind := controller_kind.to_lower()
				var expected_species := "goblin" if controller_kind == "MELEE_THREAT" else "human"
				var expected_max_health := 90 if controller_kind == "MELEE_THREAT" else 100
				var expected_name := ("Lead" if controller_kind == "LEAD" else ("Ally" if controller_kind == "PASSIVE_ALLY" else "Threat")) \
						+ " %d" % (slot + 1)
				if fixture_id != slot * 3 + role_index + 1 or fixture_entity.kind != expected_kind \
						or fixture_entity.display_name != expected_name or fixture_entity.species_id != expected_species \
						or fixture_entity.faction_id != "lab" or fixture_entity.max_health != expected_max_health \
						or fixture_entity.tags != ["lab_actor", expected_kind]:
					return "lab_fixture_actor_identity_invalid"
		var appearance_ids_seen: Dictionary = {}
		for slot in range(4):
			var appearance_id: int = encounter_lab.appearance_event_ids[slot]
			if encounter_lab.phase == "ARMED" and appearance_id != -1: return "armed_appearance_forbidden"
			if encounter_lab.phase != "ARMED" and appearance_id == -1: return "active_appearance_missing"
			if appearance_id != -1:
				if appearance_ids_seen.has(appearance_id): return "appearance_event_duplicate"
				appearance_ids_seen[appearance_id] = true
				var event = event_by_id(appearance_id)
				if event == null or event.type != "encounter.threat_appeared" \
						or int(event.data.get("trial_slot", -1)) != slot \
						or event.actor_id != fixture_actors[slot].MELEE_THREAT \
						or event.target_id != fixture_actors[slot].LEAD \
						or event.position != _lab_semantic_position(slot, "threat"):
					return "appearance_event_invalid"
		for slot in range(4):
			var lead_id: int = fixture_actors[slot].LEAD
			var ally_id: int = fixture_actors[slot].PASSIVE_ALLY
			var threat_id: int = fixture_actors[slot].MELEE_THREAT
			var lead_state = agent_states[lead_id]
			var ally_state = agent_states[ally_id]
			var threat_state = agent_states[threat_id]
			if ally_state.encounter_status != "ACTIVE" or threat_state.encounter_status != "ACTIVE":
				return "non_lead_escape_invalid"
			if lead_state.encounter_status == "ESCAPED":
				if not entities[lead_id].is_alive() or lead_state.current_activity != "ESCAPE" \
						or lead_state.last_decision_event_id <= 0:
					return "escaped_lead_state_invalid"
				var escape_events := events.filter(func(event):
					return event.type == "encounter.actor_escaped" and event.actor_id == lead_id)
				if escape_events.size() != 1 or escape_events[0].cause_id != lead_state.last_decision_event_id \
						or escape_events[0].position != entities[lead_id].position:
					return "escaped_lead_event_invalid"
			if encounter_lab.phase == "ARMED":
				if lead_state.active_threat_id != -1 or lead_state.threat_notice_event_id != -1:
					return "armed_perception_forbidden"
				if lead_state.last_seen_position != Vector2i(-1, -1) or lead_state.last_seen_time != -1:
					return "armed_last_seen_forbidden"
				if entities[lead_id].position != _lab_semantic_position(slot, "lead") \
						or entities[ally_id].position != _lab_semantic_position(slot, "ally") \
						or entities[threat_id].position != _lab_semantic_position(slot, "threat"):
					return "armed_fixture_position_invalid"
			else:
				if lead_state.active_threat_id != threat_id: return "active_threat_slot_invalid"
				var notice = event_by_id(lead_state.threat_notice_event_id)
				if notice == null or notice.type != "perception.threat_noticed" \
						or notice.actor_id != lead_id or notice.target_id != threat_id \
						or notice.cause_id != encounter_lab.appearance_event_ids[slot] \
						or int(notice.data.get("trial_slot", -1)) != slot \
						or notice.position != event_by_id(encounter_lab.appearance_event_ids[slot]).position \
						or _trial_slot_for_position(notice.position) != slot:
					return "threat_notice_event_invalid"
				if lead_state.last_seen_position != notice.position \
						or lead_state.last_seen_time != notice.world_time:
					return "last_seen_perception_mismatch"
			if threat_state.intent_target_entity_id != -1:
				var threat_target_state = agent_states.get(threat_state.intent_target_entity_id)
				if threat_target_state == null or threat_target_state.trial_slot != slot \
						or threat_target_state.controller_kind not in ["PASSIVE_ALLY", "LEAD"]:
					return "threat_intent_target_invalid"
			for actor_id in [lead_id, ally_id, threat_id]:
				var actor_state = agent_states[actor_id]
				if actor_state.intent_target_entity_id != -1:
					var intent_target_state = agent_states.get(actor_state.intent_target_entity_id)
					if intent_target_state == null or intent_target_state.trial_slot != slot:
						return "actor_intent_cross_chamber"
		var active_lead_count := 0
		for slot in range(4):
			var lead_id: int = fixture_actors[slot].LEAD
			if entities[lead_id].is_alive() and agent_states[lead_id].encounter_status == "ACTIVE": active_lead_count += 1
		if encounter_lab.phase == "COMPLETE" and active_lead_count != 0: return "complete_with_active_lead"
		if encounter_lab.phase == "ACTIVE" and active_lead_count == 0: return "active_without_live_lead"
	if party_encounter != null:
		var party_error := _party_runtime_error()
		if not party_error.is_empty(): return party_error
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
		if not ["system.environment_tick", "system.actor_tick"].has(entry["kind"]) \
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
	if scheduled_entries.size() != 2:
		return "invalid_canonical_schedule_count"
	var environment_entry: Dictionary = scheduled_entries[0]
	var actor_entry: Dictionary = scheduled_entries[1]
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
	if actor_entry["kind"] != "system.actor_tick" or actor_entry["priority"] != 200 \
			or actor_entry["repeat_interval"] != ACTOR_INTERVAL or actor_entry["due_time"] != next_cadence \
			or actor_entry["owner_id"] != -1 or actor_entry["source_event_id"] != -1 \
			or not actor_entry["payload"].is_empty():
		return "invalid_actor_schedule_contract"
	return ""


func _party_runtime_error() -> String:
	if width != 15 or height != 15: return "party_fixture_dimensions_invalid"
	if party_encounter.safe_phase not in PartyEncounterStateScript.PHASES: return "unknown_party_phase"
	if party_encounter.protagonist_id <= 0 or not entities.has(party_encounter.protagonist_id): return "party_protagonist_missing"
	if party_encounter.party_member_ids.size() < 1 or party_encounter.party_member_ids.size() > 64: return "party_roster_size_invalid"
	if party_encounter.enemy_ids.is_empty() or party_encounter.enemy_ids.size() > 64: return "party_enemy_size_invalid"
	var previous_id := 0
	var deployed := 0
	var slots: Array[int] = []
	var deployed_cells: Dictionary = {}
	var party_ids: Dictionary = {}
	for roster_index in range(party_encounter.party_member_ids.size()):
		var member_id: int = party_encounter.party_member_ids[roster_index]
		if member_id <= previous_id or not entities.has(member_id) or not party_encounter.member_rows.has(member_id): return "party_member_reference_invalid"
		previous_id = member_id
		party_ids[member_id] = true
		var member = party_encounter.member_rows[member_id]
		if member.entity_id != member_id or member.roster_slot != roster_index or member.roster_slot in slots \
				or not PartyMemberStateScript.wire_error(member.to_dict()).is_empty() \
				or member.busy_until < 0 or member.busy_until > MAX_WORLD_TIME:
			return "party_member_state_invalid"
		slots.append(member.roster_slot)
		if member.presence == "DEPLOYED":
			deployed += 1
			if not entities[member_id].is_alive() or not _terrain_is_passable(entities[member_id].position):
				return "deployed_party_position_invalid"
			var deployed_key := "%d:%d" % [entities[member_id].position.x, entities[member_id].position.y]
			if deployed_cells.has(deployed_key): return "duplicate_deployed_party_position"
			deployed_cells[deployed_key] = member_id
		if (entities[member_id].health == 0) != (member.presence == "DEFEATED"): return "party_health_presence_mismatch"
		if member.presence == "GROUPED" and entities[member_id].position != party_encounter.group_anchor: return "grouped_position_mismatch"
	slots.sort()
	for slot in range(slots.size()):
		if slots[slot] != slot: return "party_roster_slots_not_continuous"
	if party_encounter.party_member_ids[0] != party_encounter.protagonist_id or party_encounter.member_rows[party_encounter.protagonist_id].roster_slot != 0:
		return "party_protagonist_roster_invalid"
	for member_id in party_encounter.party_member_ids:
		var expected_role := "PROTAGONIST" if member_id == party_encounter.protagonist_id else "COMPANION"
		if party_encounter.member_rows[member_id].role != expected_role: return "party_role_invalid"
	if deployed > 3: return "too_many_deployed_party"
	var alive_enemies := 0; previous_id = 0
	for enemy_id in party_encounter.enemy_ids:
		if enemy_id <= previous_id or party_ids.has(enemy_id) or not entities.has(enemy_id) \
				or not party_encounter.enemy_busy_rows.has(enemy_id): return "party_enemy_reference_invalid"
		previous_id = enemy_id
		var enemy_busy: int = party_encounter.enemy_busy_rows[enemy_id]
		if enemy_busy < 0 or enemy_busy > MAX_WORLD_TIME: return "party_enemy_busy_invalid"
		if entities[enemy_id].is_alive(): alive_enemies += 1
	if party_encounter.enemy_busy_rows.size() != party_encounter.enemy_ids.size(): return "party_enemy_busy_set_mismatch"
	if not in_bounds(party_encounter.group_anchor) or party_encounter.facing not in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		return "party_anchor_or_facing_invalid"
	var hero = entities[party_encounter.protagonist_id]
	var hero_member = party_encounter.member_rows[party_encounter.protagonist_id]
	if party_encounter.safe_phase in ["GROUPED", "GROUPED_COMPLETE", "CONTACT"] \
			and hero.position != party_encounter.group_anchor:
		return "party_protagonist_anchor_mismatch"
	if (party_encounter.contact_kind == "NONE") != (party_encounter.contact_enemy_id == -1): return "party_contact_identity_invalid"
	if party_encounter.contact_enemy_id != -1 and party_encounter.contact_enemy_id not in party_encounter.enemy_ids:
		return "party_contact_enemy_invalid"
	match party_encounter.safe_phase:
		"GROUPED":
			if not hero.is_alive() or hero_member.presence != "DEPLOYED" or deployed != 1 or alive_enemies == 0 \
					or party_encounter.contact_kind != "NONE" or party_encounter.formation_id != "NONE":
				return "grouped_phase_invalid"
			for member_id in party_encounter.party_member_ids:
				if member_id != hero.id and entities[member_id].is_alive() \
						and party_encounter.member_rows[member_id].presence != "GROUPED": return "grouped_companion_presence_invalid"
		"GROUPED_COMPLETE":
			if not hero.is_alive() or hero_member.presence != "DEPLOYED" or deployed != 1 or alive_enemies != 0 \
					or party_encounter.contact_kind != "NONE" or party_encounter.contact_enemy_id != -1 \
					or party_encounter.formation_id != "NONE": return "grouped_complete_phase_invalid"
			for member_id in party_encounter.party_member_ids:
				if member_id != hero.id and entities[member_id].is_alive() \
						and party_encounter.member_rows[member_id].presence != "GROUPED": return "grouped_companion_presence_invalid"
		"CONTACT":
			if not hero.is_alive() or hero_member.presence != "DEPLOYED" or deployed != 1 \
					or party_encounter.contact_kind == "NONE" or party_encounter.formation_id != "NONE" \
					or not entities[party_encounter.contact_enemy_id].is_alive(): return "contact_phase_invalid"
			for member_id in party_encounter.party_member_ids:
				if member_id != hero.id and entities[member_id].is_alive() \
						and party_encounter.member_rows[member_id].presence != "GROUPED": return "contact_companion_presence_invalid"
		"ENGAGED":
			if not hero.is_alive() or hero_member.presence != "DEPLOYED" or deployed < 1 or alive_enemies == 0 \
					or party_encounter.contact_kind == "NONE" or party_encounter.formation_id == "NONE":
				return "engaged_phase_invalid"
			for member_id in party_encounter.party_member_ids:
				if party_encounter.member_rows[member_id].presence == "GROUPED": return "engaged_grouped_member_invalid"
		"REGROUP_READY":
			if not hero.is_alive() or hero_member.presence != "DEPLOYED" or deployed < 1 or alive_enemies != 0 \
					or party_encounter.contact_kind == "NONE" or party_encounter.formation_id == "NONE": return "regroup_ready_phase_invalid"
		"PARTY_DEFEATED":
			if hero.is_alive() or hero_member.presence != "DEFEATED": return "party_defeated_phase_invalid"
			if party_encounter.formation_id != "NONE" and party_encounter.contact_kind == "NONE": return "party_defeated_formation_invalid"
	if party_encounter.safe_phase == "PARTY_DEFEATED":
		var protagonist_death_found := false
		for event in events:
			if event.type == "entity.died" and event.target_id == hero.id:
				protagonist_death_found = true; break
		if not protagonist_death_found: return "party_defeat_event_missing"
	return _party_event_correlation_error()


func _party_event_correlation_error() -> String:
	var hero_id: int = party_encounter.protagonist_id
	var contact_types := ["encounter.detected", "encounter.party_ambush", "encounter.enemy_ambush"]
	var contact_events: Array = []
	for event in events:
		if event.type in contact_types: contact_events.append(event)
	var contact = null
	if contact_events.size() > 1: return "party_contact_event_count_invalid"
	var contact_required: bool = party_encounter.contact_kind != "NONE" \
		or party_encounter.safe_phase == "GROUPED_COMPLETE"
	if contact_events.is_empty():
		if contact_required: return "party_contact_event_missing"
	else:
		contact = contact_events[0]
		var contact_keys: Array = contact.data.keys(); contact_keys.sort()
		if contact_keys != ["contact_kind", "enemy_id", "enemy_position", "facing"] \
				or contact.data.get("contact_kind") not in ["DETECTED", "PARTY_AMBUSH", "ENEMY_AMBUSH"] \
				or not Int64CodecScript.is_canonical(contact.data.get("enemy_id")) \
				or not _party_metadata_position(contact.data.get("enemy_position")) \
				or not _party_metadata_facing(contact.data.get("facing")):
			return "party_contact_event_data_mismatch"
		var contact_kind: String = str(contact.data.contact_kind)
		var contact_enemy_id := Int64CodecScript.parse(contact.data.enemy_id, "contact enemy")
		var contact_enemy_position := Vector2i(int(contact.data.enemy_position[0]), int(contact.data.enemy_position[1]))
		var contact_facing := Vector2i(int(contact.data.facing[0]), int(contact.data.facing[1]))
		if contact_enemy_id not in party_encounter.enemy_ids:
			return "party_contact_enemy_invalid"
		var hero_history: Dictionary = _party_entity_position_at_event(hero_id, contact.id)
		var enemy_history: Dictionary = _party_entity_position_at_event(contact_enemy_id, contact.id)
		if not bool(hero_history.ok) or not bool(enemy_history.ok) \
				or hero_history.position != contact.position \
				or enemy_history.position != contact_enemy_position:
			return "party_contact_position_history_mismatch"
		if party_encounter.safe_phase == "CONTACT" and entities[contact_enemy_id].position != contact_enemy_position:
			return "party_contact_live_enemy_position_mismatch"
		var nearest_rows: Array = []
		for enemy_id in party_encounter.enemy_ids:
			if not _party_alive_at_event(enemy_id, contact.id): continue
			var history: Dictionary = _party_entity_position_at_event(enemy_id, contact.id)
			if not bool(history.ok): return "party_contact_enemy_history_invalid"
			nearest_rows.append({"entity_id":enemy_id, "position":history.position,
				"distance":_party_distance(contact.position, history.position)})
		nearest_rows.sort_custom(func(a:Dictionary,b:Dictionary):
			return int(a.distance) < int(b.distance) if int(a.distance) != int(b.distance) \
				else int(a.entity_id) < int(b.entity_id))
		if nearest_rows.is_empty() or int(nearest_rows[0].entity_id) != contact_enemy_id \
				or nearest_rows[0].position != contact_enemy_position:
			return "party_contact_nearest_enemy_mismatch"
		var distance: int = int(nearest_rows[0].distance)
		var party_detects: bool = distance <= party_encounter.party_detection_radius
		var enemy_detects: bool = distance <= party_encounter.enemy_detection_radius
		var derived_kind := "DETECTED" if party_detects and enemy_detects \
			else ("PARTY_AMBUSH" if party_detects else ("ENEMY_AMBUSH" if enemy_detects else "NONE"))
		var derived_facing := _party_cardinal_facing(contact_enemy_position - contact.position)
		var derived_type: String = {"DETECTED":"encounter.detected", "PARTY_AMBUSH":"encounter.party_ambush",
			"ENEMY_AMBUSH":"encounter.enemy_ambush"}.get(derived_kind, "")
		var expected_actor: int = contact_enemy_id if derived_kind == "ENEMY_AMBUSH" else hero_id
		var expected_target: int = hero_id if derived_kind == "ENEMY_AMBUSH" else contact_enemy_id
		if derived_kind == "NONE" or contact_kind != derived_kind or contact_facing != derived_facing \
				or contact.type != derived_type or contact.actor_id != expected_actor or contact.target_id != expected_target \
				or contact.cause_id != -1 or contact.magnitude != 0:
			return "party_contact_event_semantic_mismatch"
		if party_encounter.facing != derived_facing:
			return "party_contact_state_facing_mismatch"
		if party_encounter.contact_kind != "NONE" and (party_encounter.contact_kind != derived_kind \
				or party_encounter.contact_enemy_id != contact_enemy_id \
				or party_encounter.group_anchor != contact.position):
			return "party_contact_state_mismatch"
		var root_rows: Array = []
		for event in events:
			if event.id >= contact.id: break
			if event.step_index == contact.step_index and event.actor_id == hero_id \
					and event.type in ["action.wait", "action.move"]: root_rows.append(event)
		if root_rows.size() > 1: return "party_contact_root_count_invalid"
		if not root_rows.is_empty():
			var root = root_rows[0]
			if root.type == "action.move":
				if not _party_move_event_is_canonical(root) or root.position != contact.position:
					return "party_contact_move_root_mismatch"
			else:
				var root_history: Dictionary = _party_entity_position_at_event(hero_id, root.id)
				if root.target_id != -1 or root.position != contact.position or root.cause_id != -1 \
						or root.magnitude != 0 or not root.data.is_empty() or not bool(root_history.ok) \
						or root_history.position != contact.position:
					return "party_contact_wait_root_mismatch"

	var completed_rows: Array = []; var member_events: Array = []
	for event in events:
		if event.type == "party.deployment_completed": completed_rows.append(event)
		elif event.type == "party.member_deployed": member_events.append(event)
	if completed_rows.size() > 1: return "party_deployment_completed_count_invalid"
	var deployment_completed = null
	var historical_formation := "NONE"
	var selected_companions: Array[int] = []
	if completed_rows.is_empty():
		if not member_events.is_empty() or party_encounter.formation_id != "NONE" \
				or party_encounter.safe_phase in ["ENGAGED", "REGROUP_READY", "GROUPED_COMPLETE"]:
			return "party_deployment_history_missing"
	else:
		if contact == null: return "party_deployment_contact_missing"
		deployment_completed = completed_rows[0]
		var completed_keys: Array = deployment_completed.data.keys(); completed_keys.sort()
		if completed_keys != ["companion_ids", "formation_id"] \
				or deployment_completed.data.get("formation_id") not in ["WEDGE", "LINE", "COLUMN"] \
				or not deployment_completed.data.get("companion_ids") is Array \
				or deployment_completed.data.companion_ids.size() > 2:
			return "party_deployment_completed_data_invalid"
		historical_formation = str(deployment_completed.data.formation_id)
		var previous_id := 0
		for wire in deployment_completed.data.companion_ids:
			if not Int64CodecScript.is_canonical(wire): return "party_deployment_companion_id_invalid"
			var companion_id := Int64CodecScript.parse(wire, "deployment companion")
			if companion_id <= previous_id or companion_id == hero_id \
					or companion_id not in party_encounter.party_member_ids:
				return "party_deployment_companion_id_invalid"
			selected_companions.append(companion_id); previous_id = companion_id
		if deployment_completed.actor_id != hero_id or deployment_completed.target_id != -1 \
				or deployment_completed.position != contact.position \
				or deployment_completed.cause_id != contact.id or deployment_completed.id <= contact.id \
				or deployment_completed.magnitude != 0:
			return "party_deployment_completed_semantic_mismatch"
		if party_encounter.formation_id != "NONE" and party_encounter.formation_id != historical_formation:
			return "party_deployment_state_formation_mismatch"
		if member_events.size() != selected_companions.size(): return "party_member_deployed_set_mismatch"
		var completed_index := _event_index(deployment_completed.id)
		if completed_index < member_events.size(): return "party_deployment_event_order_invalid"
		var reserved := {_party_position_key(contact.position):hero_id}
		for offset in range(member_events.size()):
			var event = member_events[offset]; var companion_id := selected_companions[offset]
			if events[completed_index-member_events.size()+offset].id != event.id \
					or event.actor_id != companion_id or event.target_id != -1 or event.cause_id != contact.id \
					or event.magnitude != 0 or event.id <= contact.id:
				return "party_deployment_event_order_invalid"
			var member = party_encounter.member(companion_id)
			var preset_position: Vector2i = contact.position + _party_formation_offset(historical_formation, offset,
				Vector2i(int(contact.data.facing[0]), int(contact.data.facing[1])))
			var event_keys: Array = event.data.keys(); event_keys.sort()
			if member == null or member.roster_slot <= 0 or party_encounter.party_member_ids[member.roster_slot] != companion_id \
					or event_keys != ["formation_id", "formation_index", "placement", "preset_position", "roster_slot"] \
					or event.data != {"formation_id":historical_formation, "formation_index":offset,
						"placement":str(event.data.get("placement", "")),
						"preset_position":[preset_position.x,preset_position.y], "roster_slot":member.roster_slot} \
					or event.data.placement not in ["preset", "fallback"] \
					or not in_bounds(event.position) or not _terrain_is_passable(event.position):
				return "party_member_deployed_semantic_mismatch"
			var preset_valid := _party_historical_deployment_cell_valid(preset_position, reserved, contact.position, contact.id)
			var expected_position: Variant = preset_position if preset_valid \
				else _party_historical_fallback(contact.position, reserved, contact.id)
			var expected_placement := "preset" if preset_valid else "fallback"
			if expected_position == null or event.position != expected_position \
					or str(event.data.placement) != expected_placement:
				return "party_member_deployed_geometry_mismatch"
			var chain_error := _party_deployment_move_chain_error(companion_id, event.id, event.position)
			if not chain_error.is_empty(): return chain_error
			reserved[_party_position_key(event.position)] = companion_id
		if party_encounter.safe_phase not in ["GROUPED_COMPLETE"] \
				and not (party_encounter.safe_phase == "PARTY_DEFEATED" and party_encounter.formation_id == "NONE"):
			for member_id in party_encounter.party_member_ids:
				if member_id == hero_id: continue
				var member = party_encounter.member(member_id)
				var was_selected: bool = member_id in selected_companions
				if entities[member_id].is_alive() and ((was_selected and member.presence != "DEPLOYED") \
						or (not was_selected and member.presence != "DORMANT")):
					return "party_member_deployed_set_mismatch"

	var victory = null; var victory_rows: Array = []
	var starts: Array = []; var completions: Array = []; var regroup_members: Array = []
	for event in events:
		if event.type == "party.victory": victory_rows.append(event)
		elif event.type == "party.regroup_started": starts.append(event)
		elif event.type == "party.member_regrouped": regroup_members.append(event)
		elif event.type == "party.regroup_completed": completions.append(event)
	if victory_rows.size() > 1: return "party_victory_event_count_invalid"
	var victory_required: bool = party_encounter.safe_phase in ["REGROUP_READY", "GROUPED_COMPLETE"] \
		or not starts.is_empty() or not completions.is_empty()
	if victory_rows.is_empty():
		if victory_required: return "party_victory_event_count_invalid"
	else:
		victory = victory_rows[0]
		var latest_enemy_death_id := -1
		for event in events:
			if event.id >= victory.id: break
			if event.type == "entity.died" and event.target_id in party_encounter.enemy_ids:
				latest_enemy_death_id = event.id
		var victory_cause = event_by_id(victory.cause_id)
		var victory_history: Dictionary = _party_entity_position_at_event(hero_id, victory.id)
		if victory.actor_id != hero_id or victory.target_id != -1 or victory.magnitude != 0 \
				or not victory.data.is_empty() or latest_enemy_death_id <= 0 \
				or victory.cause_id != latest_enemy_death_id or victory_cause == null \
				or victory_cause.type != "entity.died" or victory_cause.target_id not in party_encounter.enemy_ids \
				or not bool(victory_history.ok) or victory.position != victory_history.position:
			return "party_victory_event_semantic_mismatch"
		for enemy_id in party_encounter.enemy_ids:
			if _party_alive_at_event(enemy_id, victory.id): return "party_victory_before_last_enemy_death"

	var has_regroup_history := not starts.is_empty() or not completions.is_empty() or not regroup_members.is_empty()
	if party_encounter.safe_phase == "GROUPED_COMPLETE" and not has_regroup_history:
		return "party_regroup_event_count_invalid"
	if has_regroup_history:
		if starts.size() != 1 or completions.size() != 1 or victory == null:
			return "party_regroup_event_count_invalid"
		var root = starts[0]; var completed = completions[0]
		var root_history: Dictionary = _party_entity_position_at_event(hero_id, root.id)
		if root.actor_id != hero_id or root.target_id != -1 or root.cause_id != -1 or root.magnitude != 0 \
				or not root.data.is_empty() or root.position != victory.position or not bool(root_history.ok) \
				or root_history.position != victory.position or root.id <= victory.id \
				or completed.actor_id != hero_id or completed.target_id != -1 or completed.cause_id != root.id \
				or completed.position != victory.position or completed.magnitude != 0 \
				or not completed.data.is_empty() or completed.id <= root.id:
			return "party_regroup_root_or_completed_mismatch"
		var root_index := _event_index(root.id); var completed_index := _event_index(completed.id)
		if completed_index-root_index-1 != regroup_members.size(): return "party_regroup_event_order_invalid"
		var seen_regrouped: Dictionary = {}; var previous_slot := 0
		for offset in range(regroup_members.size()):
			var event = regroup_members[offset]
			if events[root_index+1+offset].id != event.id or event.actor_id == hero_id \
					or event.actor_id not in party_encounter.party_member_ids or seen_regrouped.has(event.actor_id):
				return "party_member_regrouped_order_invalid"
			var member = party_encounter.member(event.actor_id)
			if member == null or member.roster_slot <= previous_slot or event.target_id != hero_id \
					or event.position != victory.position or event.cause_id != root.id \
					or event.magnitude != 0 or not event.data.is_empty():
				return "party_member_regrouped_semantic_mismatch"
			seen_regrouped[event.actor_id] = true; previous_slot = member.roster_slot
		for member_id in party_encounter.party_member_ids:
			if member_id == hero_id: continue
			if _party_alive_at_event(member_id, root.id) != seen_regrouped.has(member_id):
				return "party_member_regrouped_set_mismatch"
	if party_encounter.safe_phase == "PARTY_DEFEATED" and party_encounter.contact_kind == "NONE" \
			and contact != null and not has_regroup_history:
		return "party_cleared_contact_without_regroup_history"
	return ""


func _event_index(event_id: int) -> int:
	for index in range(events.size()):
		if events[index].id == event_id: return index
	return -1


func _first_death_event(entity_id: int):
	for event in events:
		if event.type == "entity.died" and event.target_id == entity_id: return event
	return null


func _party_alive_at_event(entity_id: int, event_id: int) -> bool:
	var death = _first_death_event(entity_id)
	return death == null or death.id > event_id


func _party_entity_position_at_event(entity_id: int, event_id: int) -> Dictionary:
	if not entities.has(entity_id): return {"ok":false,"position":Vector2i(-1,-1)}
	var cursor: Vector2i = entities[entity_id].position
	for index in range(events.size()-1, -1, -1):
		var event = events[index]
		if event.id <= event_id: break
		if event.type != "action.move" or event.actor_id != entity_id: continue
		if not _party_move_event_is_canonical(event) \
				or Vector2i(int(event.data.to_position[0]),int(event.data.to_position[1])) != cursor:
			return {"ok":false,"position":Vector2i(-1,-1)}
		cursor = Vector2i(int(event.data.from_position[0]),int(event.data.from_position[1]))
	return {"ok":true,"position":cursor}


func _party_deployment_move_chain_error(entity_id: int, event_id: int, initial_position: Vector2i) -> String:
	var cursor := initial_position
	for event in events:
		if event.id <= event_id or event.actor_id != entity_id: continue
		if event.type == "party.member_regrouped": return ""
		if event.type != "action.move": continue
		if not _party_move_event_is_canonical(event) \
				or event.data.from_position != [cursor.x,cursor.y]:
			return "party_member_move_history_mismatch"
		cursor = event.position
	return "" if entities.has(entity_id) and entities[entity_id].position == cursor \
		else "party_member_deployed_position_mismatch"


func _party_move_event_is_canonical(event) -> bool:
	var keys: Array = event.data.keys(); keys.sort()
	if keys != ["from_position", "move_time_cost", "terrain_id", "to_position"] \
			or not _party_metadata_position(event.data.get("from_position")) \
			or not _party_metadata_position(event.data.get("to_position")) \
			or not event.data.get("terrain_id") is String or not event.data.get("move_time_cost") is int:
		return false
	var from_position := Vector2i(int(event.data.from_position[0]),int(event.data.from_position[1]))
	var to_position := Vector2i(int(event.data.to_position[0]),int(event.data.to_position[1]))
	var definition: Dictionary = TerrainRegistryScript.definition(str(event.data.terrain_id))
	return event.target_id == -1 and event.cause_id == -1 and event.position == to_position \
		and _party_distance(from_position,to_position) == 1 and not definition.is_empty() \
		and bool(definition.get("passable",false)) and tile_at(to_position).terrain == event.data.terrain_id \
		and int(event.data.move_time_cost) == int(definition.move_time_cost) \
		and event.magnitude == int(event.data.move_time_cost)


func _party_historical_deployment_cell_valid(position: Vector2i, reserved: Dictionary,
		anchor: Vector2i, contact_event_id: int) -> bool:
	if not in_bounds(position) or reserved.has(_party_position_key(position)) \
			or not _terrain_is_passable(position) \
			or _party_historical_blocker_at(position, contact_event_id) != -1:
		return false
	var delta := position-anchor
	if absi(delta.x) == 1 and absi(delta.y) == 1:
		for flank in [anchor+Vector2i(delta.x,0),anchor+Vector2i(0,delta.y)]:
			if not in_bounds(flank) or not _terrain_is_passable(flank) \
					or reserved.has(_party_position_key(flank)) \
					or _party_historical_blocker_at(flank, contact_event_id) != -1:
				return false
	return true


func _party_historical_fallback(anchor: Vector2i, reserved: Dictionary, contact_event_id: int):
	var candidates: Array = []
	for radius in [1,2]:
		for y in range(anchor.y-radius,anchor.y+radius+1):
			for x in range(anchor.x-radius,anchor.x+radius+1):
				var position := Vector2i(x,y)
				if _party_distance(anchor,position) == radius \
						and _party_historical_deployment_cell_valid(position,reserved,anchor,contact_event_id):
					candidates.append(position)
		if not candidates.is_empty(): break
	candidates.sort_custom(func(a:Vector2i,b:Vector2i):
		var am:=absi(a.x-anchor.x)+absi(a.y-anchor.y); var bm:=absi(b.x-anchor.x)+absi(b.y-anchor.y)
		return am < bm if am != bm else (a.y < b.y if a.y != b.y else a.x < b.x))
	return null if candidates.is_empty() else candidates[0]


func _party_historical_blocker_at(position: Vector2i, contact_event_id: int) -> int:
	var ids: Array = entities.keys(); ids.sort()
	for entity_id in ids:
		if entity_id in party_encounter.party_member_ids and entity_id != party_encounter.protagonist_id: continue
		if not _party_alive_at_event(entity_id,contact_event_id): continue
		var history: Dictionary = _party_entity_position_at_event(entity_id,contact_event_id)
		if not bool(history.ok): return -2
		if history.position == position: return entity_id
	return -1


func _party_formation_offset(formation_id: String, index: int, facing: Vector2i) -> Vector2i:
	var back := -facing; var right := Vector2i(-facing.y,facing.x); var left := -right
	if formation_id == "WEDGE": return back+(left if index == 0 else right)
	if formation_id == "LINE": return left if index == 0 else right
	return back*(index+1)


func _party_cardinal_facing(delta: Vector2i) -> Vector2i:
	return Vector2i(0,signi(delta.y)) if absi(delta.y) >= absi(delta.x) \
		else Vector2i(signi(delta.x),0)


func _party_metadata_position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value[0] is int and value[1] is int \
		and in_bounds(Vector2i(int(value[0]),int(value[1])))


func _party_metadata_facing(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value[0] is int and value[1] is int \
		and Vector2i(int(value[0]),int(value[1])) in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]


func _party_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))


func _party_position_key(position: Vector2i) -> String:
	return "%d:%d"%[position.x,position.y]


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


static func _trial_slot_for_position(position: Vector2i) -> int:
	if position.x >= 1 and position.x <= 6 and position.y >= 1 and position.y <= 6: return 0
	if position.x >= 8 and position.x <= 13 and position.y >= 1 and position.y <= 6: return 1
	if position.x >= 1 and position.x <= 6 and position.y >= 8 and position.y <= 13: return 2
	if position.x >= 8 and position.x <= 13 and position.y >= 8 and position.y <= 13: return 3
	return -1


static func _lab_semantic_position(slot: int, semantic_name: String) -> Vector2i:
	var origin := Vector2i(1 if slot % 2 == 0 else 8, 1 if slot < 2 else 8)
	var local: Vector2i = {"threat": Vector2i(3, 1), "cover": Vector2i(1, 3),
		"intercept": Vector2i(3, 3), "lead": Vector2i(2, 4),
		"ally": Vector2i(3, 4), "retreat": Vector2i(1, 5)}.get(semantic_name, Vector2i(-100, -100))
	return origin + local


static func _lab_semantic_name(slot: int, position: Vector2i) -> String:
	for semantic_name in ["threat", "cover", "intercept", "lead", "ally", "retreat"]:
		if _lab_semantic_position(slot, semantic_name) == position: return semantic_name
	var origin := Vector2i(1 if slot % 2 == 0 else 8, 1 if slot < 2 else 8)
	return "tile.%d.%d" % [position.x - origin.x, position.y - origin.y]


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


static func _decision_trace_wire_error(data: Variant) -> String:
	if not (data is Dictionary): return "invalid_decision_trace_shape"
	var trace_keys: Array = data.keys(); trace_keys.sort()
	if trace_keys != ["appraisal", "candidates", "conflict_lost", "mental_mode",
			"mode_transition_evidence", "personality_facet_rows", "reaction_id", "retained",
			"selected_score", "semantic_target", "switch_evidence", "trace_schema_version", "trial_slot"] \
			or data.get("trace_schema_version") != 1 \
			or not _is_small_int(data.get("trial_slot"), 0, 3) \
			or not (data.get("reaction_id") is String) or data.reaction_id not in DecisionRegistryScript.ACTION_IDS \
			or data.get("mental_mode") not in AgentStateScript.MODES \
			or not (data.get("candidates") is Array) or data.candidates.size() > 6 \
			or not _is_small_int(data.get("selected_score"), -1000000, 1000000) \
			or not (data.get("retained") is bool) or not (data.get("conflict_lost") is bool) \
			or not (data.get("semantic_target") is String) or not _stable_id(data.semantic_target, 64) \
			or not (data.get("appraisal") is Dictionary) or not (data.get("personality_facet_rows") is Array):
		return "invalid_decision_trace_shape"
	var mode_evidence = data.get("mode_transition_evidence")
	if not (mode_evidence is Dictionary): return "invalid_mode_transition_evidence"
	var mode_keys: Array = mode_evidence.keys(); mode_keys.sort()
	if mode_keys != ["enter_threshold", "exit_threshold", "from_mode", "panic_pressure", "policy_id",
			"source_event_id", "to_mode", "transitioned"] \
			or not (mode_evidence.get("transitioned") is bool) \
			or mode_evidence.get("policy_id") != "panic-hysteresis-v1" \
			or mode_evidence.get("from_mode") not in AgentStateScript.MODES \
			or mode_evidence.get("to_mode") not in AgentStateScript.MODES \
			or not _is_small_int(mode_evidence.get("panic_pressure"), 0, 2000) \
			or mode_evidence.get("enter_threshold") != 850 or mode_evidence.get("exit_threshold") != 500 \
			or not Int64CodecScript.is_canonical(mode_evidence.get("source_event_id")):
		return "invalid_mode_transition_evidence"
	var switch_evidence = data.get("switch_evidence")
	if not (switch_evidence is Dictionary): return "invalid_switch_evidence"
	var switch_keys: Array = switch_evidence.keys(); switch_keys.sort()
	if switch_keys != ["challenger_cooldown_until", "challenger_reaction", "challenger_score",
			"commitment_until", "current_score", "previous_reaction", "reason_code", "retained",
			"selected_reaction", "switch_margin"] \
			or switch_evidence.get("previous_reaction") not in AgentStateScript.REACTIONS \
			or switch_evidence.get("challenger_reaction") not in DecisionRegistryScript.ACTION_IDS \
			or switch_evidence.get("selected_reaction") not in DecisionRegistryScript.ACTION_IDS \
			or not _is_small_int(switch_evidence.get("current_score"), -1000000, 1000000) \
			or not _is_small_int(switch_evidence.get("challenger_score"), -1000000, 1000000) \
			or not _is_small_int(switch_evidence.get("switch_margin"), 0, 10000) \
			or not Int64CodecScript.is_canonical(switch_evidence.get("commitment_until")) \
			or not Int64CodecScript.is_canonical(switch_evidence.get("challenger_cooldown_until")) \
			or not (switch_evidence.get("retained") is bool) \
			or switch_evidence.get("reason_code") not in ["entered", "continued_best", "retained_commitment",
				"retained_margin", "switched", "switched_illegal", "mode_transition_reset"]:
		return "invalid_switch_evidence"
	if JSON.stringify(data).to_utf8_buffer().size() > 32768:
		return "oversized_decision_trace"
	for candidate in data.candidates:
		if not (candidate is Dictionary): return "invalid_decision_trace_candidate"
		var candidate_keys: Array = candidate.keys(); candidate_keys.sort()
		if candidate_keys != ["base_score", "considerations", "gates", "legal", "reaction_id",
				"rejection_reason", "score", "target_entity_id", "target_position"] \
				or candidate.get("reaction_id") not in DecisionRegistryScript.ACTION_IDS \
				or not (candidate.get("legal") is bool) or not (candidate.get("rejection_reason") is String) \
				or not _ascii_reason(candidate.rejection_reason, 96) \
				or not _is_small_int(candidate.get("score"), -1000000, 1000000) \
				or not _is_small_int(candidate.get("base_score"), -10000, 10000) \
				or not Int64CodecScript.is_canonical(candidate.get("target_entity_id")) \
				or not (candidate.get("target_position") is Array) or candidate.target_position.size() != 2 \
				or not _is_small_int(candidate.target_position[0], -1, MAX_DIMENSION - 1) \
				or not _is_small_int(candidate.target_position[1], -1, MAX_DIMENSION - 1) \
				or not (candidate.get("gates") is Array) or candidate.gates.size() > 8 \
				or not (candidate.get("considerations") is Array) or candidate.considerations.size() > 12:
			return "invalid_decision_trace_candidate"
		for gate in candidate.gates:
			if not (gate is Dictionary): return "invalid_decision_trace_gate"
			var gate_keys: Array = gate.keys(); gate_keys.sort()
			if gate_keys != ["evidence_ids", "gate_id", "reason", "veto"] \
					or not _stable_id(gate.get("gate_id"), 64) \
					or not (gate.get("veto") is bool) or not (gate.get("reason") is String) \
					or not _ascii_reason(gate.reason, 96) or not (gate.get("evidence_ids") is Array) \
					or gate.evidence_ids.size() > 4: return "invalid_decision_trace_gate"
			for evidence_id in gate.evidence_ids:
				if not Int64CodecScript.is_canonical(evidence_id): return "invalid_decision_trace_evidence"
		for consideration in candidate.considerations:
			if not (consideration is Dictionary): return "invalid_decision_trace_consideration"
			var consideration_keys: Array = consideration.keys(); consideration_keys.sort()
			if consideration_keys != ["consideration_id", "contribution", "curve_id", "curve_output",
					"evidence_ids", "input_id", "normalized_input", "raw_input", "reason",
					"signed_weight_milli", "veto"] \
					or not _stable_id(consideration.get("consideration_id"), 64) \
					or not _stable_id(consideration.get("input_id"), 64) \
					or not _stable_id(consideration.get("curve_id"), 64) \
					or not _is_small_int(consideration.get("raw_input"), 0, 1000) \
					or not _is_small_int(consideration.get("normalized_input"), 0, 1000) \
					or not _is_small_int(consideration.get("curve_output"), 0, 1000) \
					or not _is_small_int(consideration.get("signed_weight_milli"), -2000, 2000) \
					or not _is_small_int(consideration.get("contribution"), -2000, 2000) \
					or not (consideration.get("veto") is bool) or not _ascii_reason(consideration.get("reason"), 96) \
					or not (consideration.get("evidence_ids") is Array) or consideration.evidence_ids.size() > 4:
				return "invalid_decision_trace_consideration"
			for evidence_id in consideration.evidence_ids:
				if not Int64CodecScript.is_canonical(evidence_id): return "invalid_decision_trace_evidence"
	return ""


static func _stable_id(value: Variant, maximum_bytes: int) -> bool:
	if not (value is String) or value.is_empty() or value.to_utf8_buffer().size() > maximum_bytes: return false
	for code in value.to_ascii_buffer():
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code in [46, 95, 45]): return false
	return true


static func _ascii_reason(value: Variant, maximum_bytes: int) -> bool:
	if not (value is String) or value.to_utf8_buffer().size() > maximum_bytes: return false
	for code in value.to_ascii_buffer():
		if code < 32 or code > 126: return false
	return true
