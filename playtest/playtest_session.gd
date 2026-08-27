class_name PlaytestSession
extends RefCounted

const SimulatorScript = preload("res://sim/simulator.gd")
const CommandScript = preload("res://sim/sim_command.gd")
const StepResultScript = preload("res://sim/sim_step_result.gd")
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const ClockScript = preload("res://sim/world_clock.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")

const ARENA_WIDTH := 32
const ARENA_HEIGHT := 48
const DEFAULT_SEED := 7
const DEFAULT_SPECIES := "human"
const SAVE_PATH := "user://playtest_slot_v1.json"

var sim
var seed: int = DEFAULT_SEED
var species_id: String = DEFAULT_SPECIES
var selection_position: Vector2i = Vector2i.ZERO
var command_journal: Array[Dictionary] = []
var _player_id: int = -1
var _last_result = null
var _status_reason: String = "reset"


func _init(p_seed: int = DEFAULT_SEED, p_species_id: String = DEFAULT_SPECIES) -> void:
	reset(p_seed, p_species_id)


func reset(p_seed: int, p_species_id: String) -> bool:
	var checked_species := p_species_id.to_lower()
	if checked_species.is_empty():
		checked_species = DEFAULT_SPECIES
	var candidate = SimulatorScript.create(ARENA_WIDTH, ARENA_HEIGHT, p_seed)
	if candidate == null or not _bootstrap_arena(candidate, checked_species):
		_status_reason = "arena_bootstrap_failed"
		return false
	var player = _find_player_in(candidate)
	if player == null:
		_status_reason = "player_missing_after_bootstrap"
		return false
	sim = candidate
	seed = p_seed
	species_id = checked_species
	_player_id = player.id
	selection_position = player.position
	command_journal = []
	_last_result = null
	_status_reason = "reset"
	return true


func player_id() -> int:
	return _player_id


func player_state() -> Dictionary:
	if sim == null or not sim.world.entities.has(_player_id):
		return {}
	var player = sim.world.entities[_player_id]
	return {
		"id": player.id, "kind": player.kind, "display_name": player.display_name,
		"position": [player.position.x, player.position.y], "health": player.health,
		"max_health": player.max_health, "hp": player.health, "max_hp": player.max_health,
		"alive": player.is_alive(),
		"species_id": player.species_id, "faction_id": player.faction_id,
		"tags": player.tags.duplicate(),
	}


func world_status() -> Dictionary:
	if sim == null:
		return {"ok": false, "reason": "session_not_initialized"}
	var next_environment_time := -1
	for entry in sim.world.scheduled_entries:
		if entry["kind"] == "system.environment_tick":
			next_environment_time = int(entry["due_time"])
			break
	return {
		"ok": true, "reason": _status_reason, "seed": seed,
		"species_id": species_id, "width": sim.world.width, "height": sim.world.height,
		"step_index": sim.world.step_index, "world_time": sim.world.world_time,
		"next_environment_time": next_environment_time,
		"calendar": ClockScript.project(sim.world.world_time).duplicate(true),
		"command_count": command_journal.size(), "player": player_state(),
		"selection_position": [selection_position.x, selection_position.y],
	}


func select_position(position: Vector2i) -> bool:
	if sim == null or not sim.world.in_bounds(position):
		return false
	selection_position = position
	return true


func view_visible_cells(radius: int = 4) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if sim == null or radius < 0:
		return rows
	var checked_radius := mini(radius, 4)
	var player_data := player_state()
	if player_data.is_empty():
		return rows
	var player_position := Vector2i(player_data.position[0], player_data.position[1])
	var diameter := checked_radius * 2 + 1
	var minimum_center_x := mini(checked_radius, sim.world.width - 1)
	var maximum_center_x := maxi(minimum_center_x, sim.world.width - checked_radius - 1)
	var minimum_center_y := mini(checked_radius, sim.world.height - 1)
	var maximum_center_y := maxi(minimum_center_y, sim.world.height - checked_radius - 1)
	var center := Vector2i(
		clampi(player_position.x, minimum_center_x, maximum_center_x),
		clampi(player_position.y, minimum_center_y, maximum_center_y))
	var start := center - Vector2i(checked_radius, checked_radius)
	for local_y in range(diameter):
		for local_x in range(diameter):
			var position := start + Vector2i(local_x, local_y)
			if not sim.world.in_bounds(position):
				continue
			var tile = sim.world.tile_at(position)
			var terrain: Dictionary = TerrainRegistryScript.definition(tile.terrain)
			var entity_rows: Array[Dictionary] = []
			var entity_ids: Array = sim.world.entities.keys()
			entity_ids.sort()
			for entity_id in entity_ids:
				var entity = sim.world.entities[entity_id]
				if entity.position != position:
					continue
				entity_rows.append({
					"id": entity.id, "kind": entity.kind, "display_name": entity.display_name,
					"alive": entity.is_alive(), "health": entity.health,
					"species_id": entity.species_id, "is_player": entity.id == _player_id,
				})
			rows.append({
				"position": [position.x, position.y], "local_position": [local_x, local_y],
				"terrain_id": tile.terrain, "passable": terrain.get("passable", false),
				"move_time_cost": terrain.get("move_time_cost", 0),
				"terrain_water_exposure": terrain.get("terrain_water_exposure", 0),
				"fire": tile.fire, "wetness": tile.wetness,
				"conductivity": tile.effective_conductivity(), "entities": entity_rows,
				"selected": position == selection_position,
			})
	return rows


func inspect_destination(position: Vector2i):
	if sim == null:
		return null
	return sim.assess_destination(_player_id, position)


func preview_move(position: Vector2i):
	if sim == null:
		return null
	return sim.preview(CommandScript.move_to(_player_id, position))


func commit_move(position: Vector2i):
	return _commit(CommandScript.move_to(_player_id, position))


func commit_wait():
	return _commit(CommandScript.wait(_player_id))


func commit_ignite(position: Vector2i):
	return _commit(CommandScript.ignite(position, 70, _player_id))


func commit_water(position: Vector2i):
	return _commit(CommandScript.pour_water(position, 60, _player_id))


func commit_discharge(position: Vector2i):
	return _commit(CommandScript.discharge(position, 40, _player_id))


func save_slot() -> Dictionary:
	if sim == null:
		return {"ok": false, "reason": "session_not_initialized"}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "save_open_failed"}
	file.store_string(_session_json())
	_status_reason = "save_ok"
	return {"ok": true, "reason": "ok"}


func load_slot() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"ok": false, "reason": "save_slot_missing"}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "load_open_failed"}
	return load_session_json(file.get_as_text())


func load_session_json(encoded: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(encoded) != OK:
		return {"ok": false, "reason": "invalid_session_json"}
	var parsed: Variant = parser.data
	if not (parsed is Dictionary) \
			or typeof(parsed.get("session_format_version")) not in [TYPE_INT, TYPE_FLOAT] \
			or float(parsed.get("session_format_version")) != 1.0:
		return {"ok": false, "reason": "invalid_session_json"}
	if not Int64CodecScript.is_canonical(parsed.get("seed")) \
			or not (parsed.get("species_id") is String) \
			or not (parsed.get("snapshot") is Dictionary) \
			or not (parsed.get("command_journal") is Array):
		return {"ok": false, "reason": "invalid_session_shape"}
	var candidate = SimulatorScript.from_snapshot(parsed["snapshot"])
	if candidate == null:
		return {"ok": false, "reason": "invalid_snapshot"}
	if candidate.world.width != ARENA_WIDTH or candidate.world.height != ARENA_HEIGHT:
		return {"ok": false, "reason": "arena_shape_mismatch"}
	var candidate_players: Array = _player_entities_in(candidate)
	if candidate_players.size() != 1:
		return {"ok": false, "reason": "player_count_invalid"}
	var candidate_player = candidate_players[0]
	var parsed_seed: int = Int64CodecScript.parse(parsed["seed"], "playtest seed")
	if candidate.world.seed != parsed_seed \
			or candidate_player.species_id != parsed["species_id"]:
		return {"ok": false, "reason": "session_metadata_mismatch"}
	var checked_journal: Array[Dictionary] = []
	var decoded_journal: Array = []
	for row in parsed["command_journal"]:
		if not (row is Dictionary):
			return {"ok": false, "reason": "invalid_command_journal"}
		var decoded_command = CommandScript.from_dict(row)
		if decoded_command == null:
			return {"ok": false, "reason": "invalid_command_journal"}
		checked_journal.append(decoded_command.to_dict())
		decoded_journal.append(decoded_command)
	var replay = SimulatorScript.create(ARENA_WIDTH, ARENA_HEIGHT, parsed_seed)
	if replay == null or not _bootstrap_arena(replay, str(parsed["species_id"])):
		return {"ok": false, "reason": "journal_replay_bootstrap_failed"}
	for replay_command in decoded_journal:
		var replay_result = replay.step(replay_command)
		if not replay_result.accepted:
			return {"ok": false, "reason": "journal_replay_rejected"}
	if replay.snapshot() != candidate.snapshot():
		return {"ok": false, "reason": "journal_snapshot_mismatch"}
	sim = candidate
	seed = parsed_seed
	species_id = str(parsed["species_id"])
	_player_id = candidate_player.id
	selection_position = candidate_player.position
	command_journal = checked_journal
	_last_result = null
	_status_reason = "load_ok"
	return {"ok": true, "reason": "ok"}


func snapshot_json() -> String:
	return JSON.stringify(sim.snapshot()) if sim != null else ""


func command_journal_json() -> String:
	return JSON.stringify(command_journal)


func journal_json() -> String:
	return command_journal_json()


func recent_events(limit: int = 10) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if sim == null or limit <= 0:
		return rows
	var first := maxi(0, sim.world.events.size() - limit)
	for index in range(first, sim.world.events.size()):
		rows.append(sim.world.events[index].to_dict())
	return rows


func last_result_summary() -> Dictionary:
	if _last_result == null:
		return {"available": false, "reason": _status_reason, "events": [], "timeline": []}
	var event_rows: Array[Dictionary] = []
	for event in _last_result.events:
		event_rows.append(event.to_dict())
	return {
		"available": true, "accepted": _last_result.accepted,
		"consumes_time": _last_result.consumes_time, "reason": _last_result.reason,
		"processed_step_index": _last_result.processed_step_index,
		"start_time": _last_result.start_time, "end_time": _last_result.end_time,
		"time_cost": _last_result.time_cost, "speed_tier": _last_result.speed_tier,
		"root_event_id": _last_result.root_event_id, "events": event_rows,
		"timeline": _last_result.timeline.duplicate(true),
	}


func _commit(command):
	if sim == null:
		return null
	var result = sim.step(command)
	_last_result = StepResultScript.new(
		result.accepted, result.consumes_time, result.reason, result.events,
		{"processed_step_index": result.processed_step_index,
			"start_time": result.start_time, "end_time": result.end_time,
			"time_cost": result.time_cost, "speed_tier": result.speed_tier,
			"timeline": result.timeline, "root_event_id": result.root_event_id})
	_status_reason = result.reason
	if result.accepted:
		command_journal.append(command.to_dict().duplicate(true))
	var player = sim.world.entities.get(_player_id)
	if player != null:
		selection_position = player.position
	return result


func _session_json() -> String:
	return JSON.stringify({
		"session_format_version": 1, "seed": str(seed), "species_id": species_id,
		"snapshot": sim.snapshot(), "command_journal": command_journal.duplicate(true),
	})


func _bootstrap_arena(candidate, checked_species: String) -> bool:
	for x in range(ARENA_WIDTH):
		if not candidate.world.bootstrap_set_terrain(Vector2i(x, 0), "wall") \
				or not candidate.world.bootstrap_set_terrain(Vector2i(x, ARENA_HEIGHT - 1), "wall"):
			return false
	for y in range(1, ARENA_HEIGHT - 1):
		if not candidate.world.bootstrap_set_terrain(Vector2i(0, y), "wall") \
				or not candidate.world.bootstrap_set_terrain(Vector2i(ARENA_WIDTH - 1, y), "wall"):
			return false
	for x in range(8, 13):
		for y in range(8, 11):
			if not candidate.world.bootstrap_set_terrain(Vector2i(x, y), "shallow_water"):
				return false
	for x in range(15, 20):
		for y in range(12, 15):
			if not candidate.world.bootstrap_set_terrain(Vector2i(x, y), "rubble"):
				return false
	for x in range(5, 11):
		if not candidate.world.bootstrap_set_terrain(Vector2i(x, 20), "wood_floor"):
			return false
	for y in range(24, 31):
		if not candidate.world.bootstrap_set_terrain(Vector2i(22, y), "metal"):
			return false
	for y in range(4, 18):
		if y != 10 and not candidate.world.bootstrap_set_terrain(Vector2i(14, y), "wall"):
			return false
	var player = candidate.world.add_entity(
		"player", checked_species.capitalize(), Vector2i(4, 4), 100, ["player"],
		checked_species, "party")
	if player == null:
		return false
	if candidate.world.add_entity(
			"goblin", "Arena Goblin", Vector2i(10, 18), 100, ["arena_npc"],
			"goblin", "arena") == null:
		return false
	candidate.world.tile_at(Vector2i(6, 4)).flammability = 100
	return candidate.world.bootstrap_set_fire(Vector2i(6, 4), 60) != null


func _find_player_in(candidate):
	var players: Array = _player_entities_in(candidate)
	return players[0] if not players.is_empty() else null


func _player_entities_in(candidate) -> Array:
	var players: Array = []
	var ids: Array = candidate.world.entities.keys()
	ids.sort()
	for entity_id in ids:
		var entity = candidate.world.entities[entity_id]
		if entity.tags.has("player"):
			players.append(entity)
	return players
