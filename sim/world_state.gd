class_name SimWorldState
extends RefCounted

const SNAPSHOT_VERSION := 9
const RULESET_VERSION := "phase5-combat-status-lifecycle-v1"
const CALENDAR_RULESET_ID := "abstract-calendar-v1"
const TERRAIN_RULESET_ID := "terrain-registry-v1"
const HAZARD_AFFINITY_RULESET_ID := "hazard-affinity-v1"
const PERSONALITY_SCHEMA_ID := "personality-facets-v1"
const PERSONALITY_GENERATOR_RULESET_ID := "personality-lab-latin-hypercube-v1"
const KEYED_HASH_RULESET_ID := "sha256-u31-v1"
const DECISION_RULESET_ID := "dungeon-hierarchical-utility-v1"
const SCORE_COMBINER_ID := "weighted-sum-v1"
const COMBAT_RULESET_ID := "deterministic-melee-resolution-v1"
const COMBAT_PROFILE_RULESET_ID := "combat-profile-registry-v1"
const COMBATANT_SCHEMA_ID := "combatant-state-v1"
const AGENT_STATE_SCHEMA_ID := "agent-state-v2"
const LIFE_RULESET_ID := "active-downed-dead-v1"
const STATUS_RULESET_ID := "bounded-status-lifecycle-v1"
const PARTY_MEMBER_SCHEMA_ID := "party-member-v2"
const ENVIRONMENT_INTERVAL := 100
const ACTOR_INTERVAL := 100
const MAX_WORLD_TIME := 9223372036854775707
const MAX_SAFE_JSON_INTEGER := 9007199254740991
const MAX_DIMENSION := 4096
const MAX_TILE_COUNT := 1000000
const MAX_SMALL_VALUE := 2147483647
const ROLLBACK_MEMENTO_VERSION := 3
# Packed rollback dynamic rows are [tile_index, wetness, fire,
# fire_source_event_id, wetness_source_event_id, fire_damage_eligible_time].
# Terrain/flam/conductivity are bootstrap-static and are reconstructed from the
# terrain registry on the rare restore path.
const ROLLBACK_TILE_DYNAMIC_SCALAR_STRIDE := 6
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
const WorldItemStateScript = preload("res://sim/world_item_state.gd")
const WorldItemOperationsScript = preload("res://sim/world_item_operations.gd")
const ActorLoadoutRegistryScript = preload("res://sim/actor_loadout_registry.gd")
const SpeciesDropRegistryScript = preload("res://sim/species_drop_registry.gd")
const CorpseLootSystemScript = preload("res://sim/systems/corpse_loot_system.gd")
const ItemRegistryScript = preload("res://sim/item_registry.gd")
const InventoryStateScript = preload("res://sim/inventory_state.gd")
const AmmoPoolStateScript = preload("res://sim/ammo_pool_state.gd")
const WeaponRuntimeStateScript = preload("res://sim/weapon_runtime_state.gd")
const GroundItemStateScript = preload("res://sim/ground_item_state.gd")
const PartyMemberStateScript = preload("res://sim/party_member_state.gd")
const FixedPointScript = preload("res://sim/fixed_point.gd")
const CombatantStateScript = preload("res://sim/combatant_state.gd")
const CombatProfileRegistryScript = preload("res://sim/combat_profile_registry.gd")
const StatusRegistryScript = preload("res://sim/status_registry.gd")
const MeleeCombatSystemScript = preload("res://sim/systems/melee_combat_system.gd")
const EnvironmentRulesScript = preload("res://sim/environment_rules.gd")
const ProgressionRegistryScript=preload("res://sim/progression_registry.gd")
const WeaponRegistryScript=preload("res://sim/weapon_registry.gd")
const WeaponAttackRulesScript=preload("res://sim/weapon_attack_rules.gd")
const ActorStatRulesScript=preload("res://sim/actor_stat_rules.gd")
const CombatDefenseRulesScript=preload("res://sim/combat_defense_rules.gd")
const PartyMoraleModelScript=preload("res://sim/party_morale_model.gd")
const PartyPerceptionRegistryScript=preload("res://sim/party_perception_registry.gd")
const PartyCommandScript=preload("res://sim/party_exception_command.gd")

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
var combatant_states: Dictionary = {}
var encounter_lab = null
var party_encounter = null
# Canonical owner of every entity inventory, ammo pool, weapon runtime row and
# ground item. PartyEncounterState never duplicates this authority.
var item_state = WorldItemStateScript.new()
var scheduled_entries: Array[Dictionary] = []
var next_schedule_id: int = 1

var _next_entity_id: int = 1
var _next_event_id: int = 1
var _active_step_index: int = -1
# Terrain definitions and their two registry-derived static scalars are
# bootstrap-only.  Rollback still records every dynamic tile scalar, but keeps
# this immutable portion in a packed copy-on-write template so a 96x96 turn
# does not rebuild the dungeon topology merely to establish an atomic boundary.
var _rollback_tile_terrain_cache := PackedStringArray()
# Fire/wetness occupy only a handful of cells in the product dungeon. Keep a
# canonical sparse index after the audited bootstrap/restore boundary so live
# turns and rollback capture do not rescan every one of the 96x96 tiles.
var _dynamic_tile_indices: Dictionary = {}
var _dynamic_tile_index_ready := false
# Occupancy is a positional question, but the roster is keyed by entity id.
# Pathfinding asks it once per neighbour, so keep a canonical position -> id
# index instead of sorting and scanning the whole roster on every lookup.
# The index holds every entity on a cell; the live occupancy filters still run
# on that short candidate list, so results stay byte-identical.
var _occupancy_indices: Dictionary = {}
var _occupancy_index_ready := false


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


func is_diagonal_gateway(position: Vector2i) -> bool:
	if party_encounter == null or position not in party_encounter.diagonal_gateway_positions \
			or not in_bounds(position):
		return false
	var definition: Dictionary = TerrainRegistryScript.definition_view(tile_at(position).terrain)
	return not definition.is_empty() and bool(definition.get("passable", false)) \
		and int(definition.get("occupancy_capacity", 0)) > 0


func diagonal_step_terrain_allowed(from: Vector2i, to: Vector2i) -> bool:
	var delta := to - from
	if delta.x == 0 or delta.y == 0:
		return true
	var passable_flanks: Array[Vector2i] = []
	for flank in [from + Vector2i(delta.x, 0), from + Vector2i(0, delta.y)]:
		if not in_bounds(flank):
			continue
		var definition: Dictionary = TerrainRegistryScript.definition_view(tile_at(flank).terrain)
		if not definition.is_empty() and bool(definition.get("passable", false)) \
				and int(definition.get("occupancy_capacity", 0)) > 0:
			passable_flanks.append(flank)
	if passable_flanks.size() == 2:
		return true
	if passable_flanks.size() != 1:
		return false
	# A single solid flank remains a blocked corner unless the diagonal enters
	# an open doorway or crosses the doorway's passable threshold cell.
	return is_diagonal_gateway(from) or is_diagonal_gateway(to) \
		or is_diagonal_gateway(passable_flanks[0])


func add_entity(kind: String, display_name: String, position: Vector2i,
		max_health: int = 100, tags: Array = [], species_id: String = "",
		faction_id: String = "", loadout_id: String = ""):
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
	var combatant = CombatantStateScript.new(entity.id,
		CombatProfileRegistryScript.profile_id_for_kind(kind))
	# entities, combatant_states, inventory_rows and ammo_pool_rows are created all
	# or none. Everything that can refuse is checked before the first write.
	if item_state == null or item_state.inventory_rows.has(entity.id) \
			or item_state.ammo_pool_rows.has(entity.id) \
			or entities.has(entity.id) or combatant_states.has(entity.id):
		return null
	var inventory = InventoryStateScript.new()
	var ammo_pool = AmmoPoolStateScript.new()
	var next_items = item_state.clone()
	next_items.inventory_rows[entity.id] = inventory
	next_items.ammo_pool_rows[entity.id] = ammo_pool
	if not loadout_id.is_empty():
		var loadout_plan: Dictionary = ActorLoadoutRegistryScript.plan_apply(
			next_items, entity.id, loadout_id)
		if not bool(loadout_plan.get("accepted", false)): return null
		next_items = loadout_plan.item_state
	var item_error: String = next_items.validation_error(width, height)
	if not item_error.is_empty(): return null
	entities[entity.id] = entity
	combatant_states[entity.id] = combatant
	item_state = next_items
	_register_occupancy(entity.id, position)
	_next_entity_id += 1
	return entity


# Guide 5.3 read facade. Everything here is detached: gameplay and UI can never
# reach the canonical rows through a returned object. Mutation goes exclusively
# through WorldItemOperations.
func inventory_of(entity_id: int):
	var row = _inventory_ref(entity_id)
	return InventoryStateScript._from_valid_dict(row.to_dict()) if row != null else null


func equipped_item(entity_id: int, slot: String):
	var row = _inventory_ref(entity_id)
	return row.equipped_item(slot) if row != null else null


func equipment_modifiers(entity_id: int) -> Dictionary:
	var row = _inventory_ref(entity_id)
	return row.combat_modifier_dto() if row != null else {}


func ground_item(instance_id: String):
	return item_state.ground_items.item(instance_id) if item_state != null else null


func item_owner(instance_id: String) -> Dictionary:
	var result := {"kind": "NONE", "entity_id": -1, "slot": "", "position": [-1, -1]}
	if item_state == null or instance_id.is_empty(): return result
	var entity_ids: Array = item_state.inventory_rows.keys(); entity_ids.sort()
	for entity_id in entity_ids:
		var row = item_state.inventory_rows[entity_id]
		if row._item_ref(instance_id) == null: continue
		result.kind = "ENTITY"; result.entity_id = int(entity_id)
		for slot in row.equipped:
			if str(row.equipped[slot]) == instance_id: result.slot = str(slot)
		var owner_entity = entities.get(entity_id)
		if owner_entity != null:
			result.position = [owner_entity.position.x, owner_entity.position.y]
		return result
	var ground_position: Vector2i = item_state.ground_items.position_of(instance_id)
	if ground_position != Vector2i(-1, -1):
		result.kind = "GROUND"; result.position = [ground_position.x, ground_position.y]
	return result


func _inventory_ref(entity_id: int):
	# Read-only kernel fast path. Callers must never mutate the returned row.
	return item_state.inventory_rows.get(entity_id) if item_state != null else null


func _ammo_pool_ref(entity_id: int):
	return item_state.ammo_pool_rows.get(entity_id) if item_state != null else null


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
	for entity_id in _entity_ids_at(position):
		var entity = entities[entity_id]
		var state = agent_states.get(entity_id)
		var party_state = party_member_state(entity_id)
		var party_occupies: bool = party_state == null or party_state.presence == "DEPLOYED"
		if entity.position == position and occupies_tile(entity_id) and party_occupies \
				and (state == null or state.encounter_status == "ACTIVE"):
			result.append(entity)
	return result


func reindex_entity_occupancy(entity_id: int, previous: Vector2i,
		current: Vector2i) -> void:
	# SimEntity calls this from its own position setter, so the index follows
	# every write - runtime seam, bootstrap fixture or test - without asking
	# call sites to remember a second step.
	if not _occupancy_index_ready: return
	_unregister_occupancy(entity_id, previous)
	_append_occupancy(entity_id, current)


func _entity_ids_at(position: Vector2i) -> Array:
	_ensure_occupancy_index()
	return _occupancy_indices.get(position.y * width + position.x, [])


func _ensure_occupancy_index() -> void:
	if _occupancy_index_ready: return
	_occupancy_indices.clear()
	var ids: Array = entities.keys()
	ids.sort()
	for entity_id in ids:
		var entity = entities[entity_id]
		entity.occupancy_observer = weakref(self)
		_append_occupancy(int(entity_id), entity.position)
	_occupancy_index_ready = true


func _register_occupancy(entity_id: int, position: Vector2i) -> void:
	if not _occupancy_index_ready: return
	entities[entity_id].occupancy_observer = weakref(self)
	_append_occupancy(entity_id, position)


func _append_occupancy(entity_id: int, position: Vector2i) -> void:
	if not in_bounds(position): return
	var key := position.y * width + position.x
	var ids: Array = _occupancy_indices.get(key, [])
	# Candidate lists stay in ascending entity id order, which is the order
	# occupancy scans have always reported.
	var insert_at := ids.size()
	for index in range(ids.size()):
		if int(ids[index]) > entity_id:
			insert_at = index
			break
	ids.insert(insert_at, entity_id)
	_occupancy_indices[key] = ids


func _unregister_occupancy(entity_id: int, position: Vector2i) -> void:
	if not _occupancy_index_ready or not in_bounds(position): return
	var key := position.y * width + position.x
	var ids: Array = _occupancy_indices.get(key, [])
	ids.erase(entity_id)
	if ids.is_empty(): _occupancy_indices.erase(key)
	else: _occupancy_indices[key] = ids


func exposed_entities_at(position: Vector2i) -> Array:
	var result: Array = []
	var ids: Array = entities.keys(); ids.sort()
	for entity_id in ids:
		var entity = entities[entity_id]
		if not is_environment_exposed(entity_id): continue
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


func can_act(entity_id: int, at_time: int) -> bool:
	var state = combatant_states.get(entity_id)
	return state != null and state.life_state == "ACTIVE" and at_time >= state.recovery_lock_until \
		and not _party_member_is_detached(entity_id)


func occupies_tile(entity_id: int) -> bool:
	var state = combatant_states.get(entity_id)
	return state != null and state.life_state != "DEAD" and not _party_member_is_detached(entity_id)


func is_environment_exposed(entity_id: int) -> bool:
	var state = combatant_states.get(entity_id)
	return state != null and state.life_state in ["ACTIVE", "DOWNED"] \
		and not _party_member_is_detached(entity_id)


func is_explicit_melee_target(entity_id: int) -> bool:
	var state = combatant_states.get(entity_id)
	return state != null and state.life_state in ["ACTIVE", "DOWNED"] \
		and not _party_member_is_detached(entity_id)


func is_autonomous_target(entity_id: int) -> bool:
	var state = combatant_states.get(entity_id)
	return state != null and state.life_state == "ACTIVE" and not _party_member_is_detached(entity_id)


func _party_member_is_detached(entity_id: int) -> bool:
	var member = party_member_state(entity_id)
	return member != null and member.presence in ["RECRUITABLE", "EXILED"]


func is_unresolved_enemy(entity_id: int) -> bool:
	var state = combatant_states.get(entity_id)
	return state != null and state.life_state != "DEAD"


# Compatibility seam for pre-Phase-5 bootstrap fixtures. It is deliberately
# unavailable after any operation has begun and is never called by production
# runtime or snapshot decoding. The HP and life authorities move atomically.
func bootstrap_set_combatant_life_state(entity_id: int, life_state: String) -> bool:
	if _active_step_index != -1 or step_index != 0 or world_time != 0 \
			or encounter_lab != null or party_encounter != null \
			or not events.is_empty() or life_state != "DEAD" \
			or not entities.has(entity_id) or not combatant_states.has(entity_id):
		return false
	entities[entity_id].health = 0
	var state = combatant_states[entity_id]
	state.life_state = "DEAD"
	state.guarded_until = 0; state.guard_source_event_id = -1
	state.downed_at = -1; state.downed_resolve_at = -1; state.downed_source_event_id = -1
	state.recovery_lock_until = 0; state.recovery_source_event_id = -1
	state.status_rows.clear()
	return true


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
	_rollback_tile_terrain_cache = PackedStringArray()
	track_dynamic_tile(position)
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
	track_dynamic_tile(position)
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
	track_dynamic_tile(position)
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
	if type == "entity.died":
		# Death is the sole C1 input, independent of whether it came from a direct
		# hit, finisher, status tick or environment. Materialization itself emits a
		# derived event; a failed transaction retracts this source event so callers
		# can roll the enclosing step back without a half-processed corpse.
		var materialized: Dictionary = CorpseLootSystemScript.materialize_death_event(self, event)
		if not bool(materialized.get("accepted", false)):
			events.pop_back()
			_next_event_id -= 1
			return null
	# Canonical environment producers emit their source leaf immediately before
	# mutating the referenced tile. Mark that position up front so the sparse
	# runtime index also covers low-level fixtures using the same producer seam.
	if _dynamic_tile_index_ready and type in ["environment.ignited",
			"environment.fire_spread","environment.water_applied"] \
			and in_bounds(position):
		_dynamic_tile_indices[position.y * width + position.x] = true
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
	for event_index in range(events.size()):
		var event = events[event_index]
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
	var combatant_rows: Array = []
	var combatant_ids: Array = combatant_states.keys(); combatant_ids.sort()
	for entity_id in combatant_ids: combatant_rows.append(combatant_states[entity_id].to_dict())
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
		"combat_profile_ruleset_id": COMBAT_PROFILE_RULESET_ID,
		"combatant_schema_id": COMBATANT_SCHEMA_ID,
		"agent_state_schema_id": AGENT_STATE_SCHEMA_ID,
		"life_ruleset_id": LIFE_RULESET_ID,
		"status_ruleset_id": STATUS_RULESET_ID,
		"party_member_schema_id": PARTY_MEMBER_SCHEMA_ID,
		"width": width, "height": height,
		"step_index": str(step_index), "world_time": str(world_time), "seed": str(seed),
		"rng_state": str(rng.state),
		"next_entity_id": str(_next_entity_id), "next_event_id": str(_next_event_id),
		"next_schedule_id": str(next_schedule_id), "scheduled_entries": schedule_rows,
		"agent_states": agent_rows, "combatant_states": combatant_rows,
		"encounter_lab": null if encounter_lab == null else encounter_lab.to_dict(),
		"party_encounter": null if party_encounter == null else party_encounter.to_dict(),
		"item_state": item_state.to_dict(),
		"tiles": tile_rows, "entities": entity_rows, "events": event_rows,
		"species_relations": species_relations.to_dict(), "personal_relations": relation_rows,
	}


# In-memory rollback is deliberately separate from the public save snapshot.
# Save/replay keeps its exact JSON-safe wire format above. A turn memento uses
# packed tile scalars and an append-only event prefix so a 96x96 map does not
# allocate 9,216 tile dictionaries (or re-encode the whole event ledger) merely
# to make an operation atomic.
func rollback_memento(validate_state: bool = true) -> Variant:
	# Most callers require snapshot()'s pre-operation validity gate. The session's
	# one-hop exploration transaction defers it to its mandatory post-commit
	# validator, preserving the same accepted-state boundary without a duplicate
	# full-ledger scan.
	if not is_settled():
		return null
	if validate_state and not world_state_error().is_empty():return null
	_ensure_rollback_tile_static_cache()
	# Terrain is immutable after bootstrap. Dynamic tile fields are sparse in a
	# dungeon turn (normally no burning/wet tiles), so retain only non-default
	# rows instead of allocating a 7×map-size scalar buffer on every hop.
	var tile_terrain := _rollback_tile_terrain_cache
	_ensure_dynamic_tile_index()
	var tile_scalars := PackedInt64Array([tiles.size(), 0])
	var dynamic_row_count := 0
	var dynamic_indices: Array = _dynamic_tile_indices.keys()
	dynamic_indices.sort()
	for tile_index_value in dynamic_indices:
		var tile_index := int(tile_index_value)
		var tile = tiles[tile_index]
		tile_scalars.append(tile_index)
		tile_scalars.append(int(tile.wetness))
		tile_scalars.append(int(tile.fire))
		tile_scalars.append(int(tile.fire_source_event_id))
		tile_scalars.append(int(tile.wetness_source_event_id))
		tile_scalars.append(int(tile.fire_damage_eligible_time))
		dynamic_row_count += 1
	tile_scalars[1] = dynamic_row_count
	var entity_rows: Array = []
	var entity_ids: Array = entities.keys(); entity_ids.sort()
	for entity_id in entity_ids: entity_rows.append(entities[entity_id].to_dict())
	var relation_rows: Array = []
	var relation_keys: Array = personal_relations.keys(); relation_keys.sort()
	for key in relation_keys: relation_rows.append(personal_relations[key].to_dict())
	var agent_rows: Array = []
	var agent_ids: Array = agent_states.keys(); agent_ids.sort()
	for entity_id in agent_ids: agent_rows.append(agent_states[entity_id].to_dict())
	var combatant_rows: Array = []
	var combatant_ids: Array = combatant_states.keys(); combatant_ids.sort()
	for entity_id in combatant_ids: combatant_rows.append(combatant_states[entity_id].to_dict())
	var schedule_rows: Array = []
	for entry in scheduled_entries: schedule_rows.append(_schedule_to_dict(entry))
	var memento:={
		"schema_version": ROLLBACK_MEMENTO_VERSION,
		"source_instance_id": get_instance_id(),
		"width": width, "height": height, "seed": seed,
		"step_index": step_index, "world_time": world_time,
		"rng_state": rng.state,
		"next_entity_id": _next_entity_id, "next_event_id": _next_event_id,
		"next_schedule_id": next_schedule_id,
		"active_step_index": _active_step_index,
		"tile_terrain": tile_terrain,
		"tile_scalars": tile_scalars,
		"entity_rows": entity_rows,
		# SimEvent is an immutable canonical ledger entry after append. Duplicating
		# this Array therefore provides copy-on-write history without O(history)
		# dictionary serialization. Restore detaches every retained event.
		"event_prefix": events.duplicate(),
		"species_relations": species_relations.to_dict(),
		"personal_relation_rows": relation_rows,
		"agent_rows": agent_rows,
		"combatant_rows": combatant_rows,
		"encounter_lab": null if encounter_lab == null else encounter_lab.to_dict(),
		"party_encounter": null if party_encounter == null else party_encounter.to_dict(),
		"schedule_rows": schedule_rows,
	}
	memento.merge(_rollback_item_rows())
	return memento


func _rollback_item_rows() -> Dictionary:
	# Inventories are as sparse as dynamic tiles: a product dungeon roster of ~14
	# entities normally has exactly one owner. Serialize only the rows that hold
	# something so memento capture scales with owners, never with the roster.
	var inventory_rows: Array = []
	var entity_ids: Array = item_state.inventory_rows.keys(); entity_ids.sort()
	for entity_id in entity_ids:
		var row = item_state.inventory_rows[entity_id]
		if row.backpack.is_empty(): continue
		inventory_rows.append([int(entity_id), row.to_dict()])
	var ammo_rows: Array = []
	var ammo_ids: Array = item_state.ammo_pool_rows.keys(); ammo_ids.sort()
	for entity_id in ammo_ids:
		var row = item_state.ammo_pool_rows[entity_id]
		if row.amount("ARROW") == 0 and row.amount("BOLT") == 0: continue
		ammo_rows.append([int(entity_id), row.to_dict()])
	var runtime_rows: Array = []
	var runtime_ids: Array = item_state.weapon_runtime_rows.keys(); runtime_ids.sort()
	for instance_id in runtime_ids:
		runtime_rows.append(item_state.weapon_runtime_rows[instance_id].to_dict())
	return {"item_revision": item_state.revision,
		"item_next_instance_id": item_state.next_item_instance_id,
		"item_inventory_rows": inventory_rows, "item_ammo_rows": ammo_rows,
		"item_weapon_runtime_rows": runtime_rows,
		"item_ground": item_state.ground_items.to_dict(),
		"item_processed_death_ids": item_state.processed_drop_death_event_ids.duplicate()}


func _restore_item_rows(value: Dictionary) -> bool:
	for key in ["item_inventory_rows", "item_ammo_rows", "item_weapon_runtime_rows",
			"item_processed_death_ids"]:
		if not value.get(key) is Array: return false
	if not value.get("item_ground") is Dictionary: return false
	item_state = WorldItemStateScript.new()
	item_state.revision = int(value.get("item_revision", -1))
	item_state.next_item_instance_id = int(value.get("item_next_instance_id", 0))
	# Every combatant owns a row by contract, so the sparse capture only has to
	# restore the rows that differ from that empty default.
	for entity_id in combatant_states:
		item_state.inventory_rows[int(entity_id)] = InventoryStateScript.new()
		item_state.ammo_pool_rows[int(entity_id)] = AmmoPoolStateScript.new()
	for row in value.item_inventory_rows:
		if not row is Array or row.size() != 2 \
				or not item_state.inventory_rows.has(int(row[0])): return false
		item_state.inventory_rows[int(row[0])] = InventoryStateScript._from_valid_dict(row[1])
	for row in value.item_ammo_rows:
		if not row is Array or row.size() != 2 \
				or not item_state.ammo_pool_rows.has(int(row[0])): return false
		item_state.ammo_pool_rows[int(row[0])] = AmmoPoolStateScript._from_valid_dict(row[1])
	for row in value.item_weapon_runtime_rows:
		var runtime = WeaponRuntimeStateScript._from_valid_dict(row)
		item_state.weapon_runtime_rows[runtime.instance_id] = runtime
	item_state.ground_items = GroundItemStateScript._from_valid_dict(value.item_ground)
	for death_event_id in value.item_processed_death_ids:
		item_state.processed_drop_death_event_ids.append(int(death_event_id))
	return true


func warm_rollback_memento_static_tiles() -> void:
	# Map/bootstrap construction can pay this one-time immutable topology cost
	# before the first input-driven turn. It does not capture mutable state or
	# relax any rollback validation boundary.
	_ensure_rollback_tile_static_cache()
	_ensure_dynamic_tile_index()


func dynamic_tile_positions() -> Array[Vector2i]:
	_ensure_dynamic_tile_index()
	var indices: Array = _dynamic_tile_indices.keys()
	indices.sort()
	var positions: Array[Vector2i] = []
	for index_value in indices:
		var index := int(index_value)
		positions.append(Vector2i(index % width, index / width))
	return positions


func track_dynamic_tile(position: Vector2i) -> void:
	if not _dynamic_tile_index_ready or not in_bounds(position): return
	var index := position.y * width + position.x
	if _tile_has_dynamic_state(tiles[index]): _dynamic_tile_indices[index] = true
	else: _dynamic_tile_indices.erase(index)


func runtime_dynamic_tiles_error() -> String:
	_ensure_dynamic_tile_index()
	for index_value in _dynamic_tile_indices:
		var tile = tiles[int(index_value)]
		if tile.wetness < 0 or tile.wetness > 100 or tile.fire < 0 or tile.fire > 100:
			return "tile_scalar_invalid"
		if (tile.fire == 0) != (tile.fire_source_event_id == -1) \
				or (tile.fire == 0) != (tile.fire_damage_eligible_time == -1) \
				or (tile.wetness == 0) != (tile.wetness_source_event_id == -1):
			return "runtime_tile_source_sentinel_invalid"
	return ""


func _ensure_dynamic_tile_index() -> void:
	if _dynamic_tile_index_ready: return
	_dynamic_tile_indices.clear()
	for tile_index in range(tiles.size()):
		if _tile_has_dynamic_state(tiles[tile_index]):
			_dynamic_tile_indices[tile_index] = true
	_dynamic_tile_index_ready = true


func _tile_has_dynamic_state(tile) -> bool:
	return tile.wetness != 0 or tile.fire != 0 \
		or tile.fire_source_event_id != -1 or tile.wetness_source_event_id != -1 \
		or tile.fire_damage_eligible_time != -1


func _ensure_rollback_tile_static_cache() -> void:
	if _rollback_tile_terrain_cache.size() == tiles.size():
		return
	_rollback_tile_terrain_cache.resize(tiles.size())
	for tile_index in range(tiles.size()):
		var tile = tiles[tile_index]
		_rollback_tile_terrain_cache[tile_index] = str(tile.terrain)


func rollback_memento_is_current(value: Variant) -> bool:
	if not value is Dictionary or int(value.get("schema_version", -1)) \
			!= ROLLBACK_MEMENTO_VERSION:
		return false
	var prefix: Variant = value.get("event_prefix")
	return value.get("source_instance_id") is int \
		and int(value.source_instance_id) == get_instance_id() \
		and int(value.get("width", -1)) == width \
		and int(value.get("height", -1)) == height \
		and int(value.get("seed", 0)) == seed \
		and int(value.get("step_index", -1)) == step_index \
		and int(value.get("world_time", -1)) == world_time \
		and int(value.get("rng_state", 0)) == rng.state \
		and int(value.get("next_entity_id", -1)) == _next_entity_id \
		and int(value.get("next_event_id", -1)) == _next_event_id \
		and int(value.get("next_schedule_id", -1)) == next_schedule_id \
		and int(value.get("active_step_index", -2)) == _active_step_index \
		and int(value.get("item_revision", -1)) == item_state.revision \
		and prefix is Array and prefix.size() == events.size() \
		and (events.is_empty() or prefix[-1] == events[-1])


static func from_rollback_memento(value: Variant) -> SimWorldState:
	if not value is Dictionary or int(value.get("schema_version", -1)) \
			!= ROLLBACK_MEMENTO_VERSION:
		return null
	var restored_width := int(value.get("width", 0))
	var restored_height := int(value.get("height", 0))
	if not dimensions_error(restored_width, restored_height).is_empty() \
			or int(value.get("active_step_index", -2)) != -1:
		return null
	var terrain_values: Variant = value.get("tile_terrain")
	var scalar_values: Variant = value.get("tile_scalars")
	var tile_count := restored_width * restored_height
	if not terrain_values is PackedStringArray or terrain_values.size() != tile_count \
			or not scalar_values is PackedInt64Array or scalar_values.size() < 2 \
			or int(scalar_values[0]) != tile_count \
			or int(scalar_values[1]) < 0 \
			or scalar_values.size() != 2 + int(scalar_values[1]) \
				* ROLLBACK_TILE_DYNAMIC_SCALAR_STRIDE:
		return null
	for key in ["entity_rows", "event_prefix", "personal_relation_rows", "agent_rows",
			"combatant_rows", "schedule_rows"]:
		if not value.get(key) is Array: return null
	if not value.get("species_relations") is Dictionary:
		return null
	var restored := SimWorldState.new(restored_width, restored_height,
		int(value.get("seed", 1)))
	restored.step_index = int(value.get("step_index", -1))
	restored.world_time = int(value.get("world_time", -1))
	restored.rng.state = int(value.get("rng_state", 0))
	restored._next_entity_id = int(value.get("next_entity_id", -1))
	restored._next_event_id = int(value.get("next_event_id", -1))
	restored.next_schedule_id = int(value.get("next_schedule_id", -1))
	restored._active_step_index = -1
	for tile_index in range(tile_count):
		var tile = restored.tiles[tile_index]
		tile.terrain = str(terrain_values[tile_index])
		var terrain_definition: Dictionary = TerrainRegistryScript.definition(tile.terrain)
		if terrain_definition.is_empty(): return null
		tile.flammability = int(terrain_definition.default_flammability)
		tile.base_conductivity = int(terrain_definition.default_base_conductivity)
		tile.wetness = 0; tile.fire = 0
		tile.fire_source_event_id = -1; tile.wetness_source_event_id = -1
		tile.fire_damage_eligible_time = -1
	var previous_dynamic_tile := -1
	for row_index in range(int(scalar_values[1])):
		var offset := 2 + row_index * ROLLBACK_TILE_DYNAMIC_SCALAR_STRIDE
		var tile_index := int(scalar_values[offset])
		if tile_index <= previous_dynamic_tile or tile_index < 0 or tile_index >= tile_count:
			return null
		previous_dynamic_tile = tile_index
		var tile = restored.tiles[tile_index]
		tile.wetness = int(scalar_values[offset + 1])
		tile.fire = int(scalar_values[offset + 2])
		tile.fire_source_event_id = int(scalar_values[offset + 3])
		tile.wetness_source_event_id = int(scalar_values[offset + 4])
		tile.fire_damage_eligible_time = int(scalar_values[offset + 5])
		restored._dynamic_tile_indices[tile_index] = true
	restored._dynamic_tile_index_ready = true
	restored.entities.clear()
	for row in value.entity_rows:
		if not row is Dictionary: return null
		var entity = SimEntityScript.from_dict(row)
		restored.entities[entity.id] = entity
	restored.events.clear()
	for event in value.event_prefix:
		if event == null or not event is SimEvent: return null
		restored.events.append(event.detached_copy())
	restored.species_relations = SpeciesRelationTableScript.from_dict(value.species_relations)
	restored.personal_relations.clear()
	for row in value.personal_relation_rows:
		if not row is Dictionary: return null
		var relation = PersonalRelationScript.from_dict(row)
		restored.personal_relations["%d:%d" % [relation.observer_id, relation.subject_id]] = relation
	restored.agent_states.clear()
	for row in value.agent_rows:
		if not row is Dictionary: return null
		var state = AgentStateScript.from_dict(row)
		restored.agent_states[state.entity_id] = state
	restored.combatant_states.clear()
	for row in value.combatant_rows:
		if not row is Dictionary: return null
		var combatant = CombatantStateScript.from_dict(row)
		restored.combatant_states[combatant.entity_id] = combatant
	if not restored._restore_item_rows(value): return null
	restored.encounter_lab = null if value.get("encounter_lab") == null \
		else EncounterLabStateScript.from_dict(value.encounter_lab)
	restored.party_encounter = null if value.get("party_encounter") == null \
		else PartyEncounterStateScript.from_dict(value.party_encounter)
	restored.scheduled_entries.clear()
	for row in value.schedule_rows:
		if not row is Dictionary: return null
		restored.scheduled_entries.append(_schedule_from_dict(row))
	restored._sort_schedules()
	# Restore is a rare failure path, so pay the complete canonical validation
	# cost here before exposing the replacement world.
	return restored if restored._restored_state_error().is_empty() else null


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
	restored.combatant_states.clear()
	for row in data.get("combatant_states", []):
		var combatant = CombatantStateScript.from_dict(row)
		restored.combatant_states[combatant.entity_id] = combatant
	# The wire was fully validated above, so skip the duplicate re-validation that
	# the public WorldItemState.from_dict() front door performs.
	restored.item_state = WorldItemStateScript._from_valid_dict(data.item_state)
	restored.encounter_lab = null if data.get("encounter_lab") == null else EncounterLabStateScript.from_dict(data.encounter_lab)
	restored.party_encounter = null if data.get("party_encounter") == null else PartyEncounterStateScript.from_dict(data.party_encounter)
	if restored.party_encounter!=null:
		var progression_row:Variant=data.party_encounter.get("protagonist_progression")
		if not progression_row is Dictionary \
				or int(progression_row.get("schema_version",0))<ProgressionRegistryScript.SCHEMA_VERSION:
			# Older saves used party.victory as their reward source. Rebuild their
			# historical ledger once, then new kills use source death ids.
			restored._rebuild_progression_from_events(not progression_row is Dictionary)
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
			["score_combiner_id", SCORE_COMBINER_ID], ["combat_ruleset_id", COMBAT_RULESET_ID],
			["combat_profile_ruleset_id", COMBAT_PROFILE_RULESET_ID],
			["combatant_schema_id", COMBATANT_SCHEMA_ID], ["agent_state_schema_id", AGENT_STATE_SCHEMA_ID],
			["life_ruleset_id", LIFE_RULESET_ID], ["status_ruleset_id", STATUS_RULESET_ID],
			["party_member_schema_id", PARTY_MEMBER_SCHEMA_ID]]:
		if not (data.get(pair[0]) is String) or data.get(pair[0]) != pair[1]: return "unsupported_%s" % pair[0]
	return ""


static func snapshot_wire_error(data: Dictionary) -> String:
	var header_error := snapshot_header_error(data)
	if not header_error.is_empty():
		return header_error
	var top_keys: Array = data.keys(); top_keys.sort()
	if top_keys != ["agent_state_schema_id", "agent_states", "calendar_ruleset_id", "combat_profile_ruleset_id",
			"combat_ruleset_id", "combatant_schema_id", "combatant_states", "decision_ruleset_id",
			"encounter_lab", "entities", "events", "hazard_affinity_ruleset_id", "height",
			"item_state", "keyed_hash_ruleset_id", "life_ruleset_id", "next_entity_id", "next_event_id",
			"next_schedule_id",
			"party_encounter", "party_member_schema_id", "personal_relations", "personality_generator_ruleset_id",
			"personality_schema_id", "rng_state", "ruleset_version", "scheduled_entries",
			"score_combiner_id", "seed", "snapshot_version", "species_relations", "status_ruleset_id", "step_index",
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
		if not (row is Dictionary) or not _exact_keys(row, ["base_conductivity",
				"fire", "fire_damage_eligible_time", "fire_source_event_id", "flammability",
				"terrain", "wetness", "wetness_source_event_id"]) \
				or not (row.get("terrain") is String):
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
		if not (row is Dictionary) or not _exact_keys(row, ["display_name", "faction_id",
				"health", "id", "kind", "max_health", "position", "species_id", "tags"]):
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
	if not data.get("combatant_states") is Array: return "invalid_combatant_states_shape"
	var combatant_ids: Dictionary = {}
	var previous_combatant_id := 0
	for row in data.combatant_states:
		var combatant_error := CombatantStateScript.wire_error(row)
		if not combatant_error.is_empty(): return combatant_error
		var combatant_id := Int64CodecScript.parse(row.entity_id, "combatant ID")
		if combatant_id <= previous_combatant_id or combatant_ids.has(combatant_id):
			return "duplicate_or_unsorted_combatant_states"
		if not entity_ids.has(combatant_id): return "orphan_combatant_state"
		combatant_ids[combatant_id] = true; previous_combatant_id = combatant_id
	if combatant_ids.size() != entity_ids.size(): return "combatant_entity_set_mismatch"
	var item_error := WorldItemStateScript.wire_error(data.get("item_state"),
		restored_width, restored_height)
	if not item_error.is_empty(): return item_error
	var expected_item_ids: Array = combatant_ids.keys(); expected_item_ids.sort()
	for pair in [["inventory_rows", "inventory_row_entity_mismatch"],
			["ammo_pool_rows", "ammo_pool_row_entity_mismatch"]]:
		var wire_ids: Array = []
		for row in data.item_state[pair[0]]:
			wire_ids.append(Int64CodecScript.parse(row.entity_id, "item row entity ID"))
		if wire_ids != expected_item_ids: return pair[1]
	if not (data.get("events") is Array):
		return "invalid_events_shape"
	for row in data["events"]:
		if not (row is Dictionary) or not _exact_keys(row, ["actor_id", "cause_id", "data",
				"id", "instigator_id", "magnitude", "position", "step_index", "target_id", "type",
				"world_time"]) or not (row.get("type") is String) \
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
		var agent_keys: Array = row.keys(); agent_keys.sort()
		var expected_agent_keys := ["action_history_rows", "active_threat_id", "anger", "busy_until",
			"commitment_until", "controller_kind", "current_activity", "current_reaction", "emotion_updated_time",
			"encounter_status", "entity_id", "fear", "intent_started_time", "intent_target_entity_id",
			"intent_target_position", "last_decision_event_id", "last_decision_time", "last_seen_position",
			"last_seen_time", "mental_mode", "mental_mode_since", "threat_notice_event_id", "trial_slot"]
		if row.controller_kind == "LEAD": expected_agent_keys.append("personality_profile"); expected_agent_keys.sort()
		if agent_keys != expected_agent_keys: return "invalid_agent_state_keys"
		if not _is_small_int(row.get("trial_slot"), 0, 3) or row.get("encounter_status") not in AgentStateScript.ENCOUNTER_STATUSES:
			return "invalid_agent_trial_or_status"
		for key in ["busy_until", "intent_target_entity_id", "intent_started_time", "emotion_updated_time",
				"mental_mode_since", "active_threat_id", "threat_notice_event_id", "last_seen_time",
				"commitment_until", "last_decision_time", "last_decision_event_id"]:
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
		if not _exact_keys(schedule, ["due_time", "kind", "owner_id", "payload", "priority",
				"repeat_interval", "schedule_id", "source_event_id"]):
			return "invalid_schedule_shape"
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


func _item_state_error() -> String:
	# Invariants 1, 2 and 11 need world sets, so the world supplies them once here
	# instead of letting the item state guess them.
	if item_state == null: return "missing_world_item_state"
	var error: String = item_state.validation_error(width, height)
	if not error.is_empty(): return error
	error=item_state.world_membership_error(combatant_states.keys(), _death_event_ids())
	if not error.is_empty():return error
	return WorldItemOperationsScript.equipped_requirements_error(self,item_state)


func _death_event_ids() -> Array:
	# Only a processed drop ledger can reference death events, and A2 never fills
	# it, so the history scan stays off the ordinary validation path.
	if item_state == null or item_state.processed_drop_death_event_ids.is_empty():
		return []
	var ids: Array = []
	for event in events:
		if event.type == "entity.died": ids.append(int(event.id))
	return ids


func _corpse_drop_history_error() -> String:
	var processed: Dictionary = {}
	for death_event_id in item_state.processed_drop_death_event_ids:
		processed[int(death_event_id)] = true
	var materialized_by_death: Dictionary = {}
	for event in events:
		if event.type != "corpse.loot_materialized": continue
		var keys: Array = event.data.keys(); keys.sort()
		if keys != ["generated_items", "ruleset_id", "schema_version",
				"source_death_event_id"] or event.data.get("schema_version") != 1 \
				or event.data.get("ruleset_id") != SpeciesDropRegistryScript.RULESET_ID \
				or not Int64CodecScript.is_canonical(event.data.get("source_death_event_id")) \
				or not event.data.get("generated_items") is Array:
			return "corpse_drop_event_shape_invalid"
		var death_id := Int64CodecScript.parse(event.data.source_death_event_id,
			"corpse drop death event")
		var death = event_by_id(death_id)
		if death == null or death.type != "entity.died" or event.cause_id != death_id \
				or event.id != death_id + 1 or event.actor_id != death.target_id \
				or event.target_id != death.target_id or event.position != death.position \
				or event.step_index != death.step_index or event.world_time != death.world_time \
				or materialized_by_death.has(death_id):
			return "corpse_drop_event_source_invalid"
		var corpse = entities.get(death.target_id)
		if corpse == null: return "corpse_drop_event_source_invalid"
		var expected_rolls := SpeciesDropRegistryScript.rolls_for(seed, death_id,
			str(corpse.species_id))
		var actual_rolls: Array = []
		var previous_instance_id := ""
		var total_quantity := 0
		for generated in event.data.generated_items:
			if not generated is Dictionary: return "corpse_drop_item_shape_invalid"
			var generated_keys: Array = generated.keys(); generated_keys.sort()
			if generated_keys != ["definition_id", "instance_id", "location", "quantity", "roll_id"] \
					or not generated.instance_id is String \
					or not generated.definition_id is String or not generated.roll_id is String \
					or not generated.location is String or generated.location not in ["CORPSE", "GROUND"] \
					or not generated.quantity is int or int(generated.quantity) < 1:
				return "corpse_drop_item_shape_invalid"
			var instance_id := str(generated.instance_id)
			if not previous_instance_id.is_empty() and instance_id <= previous_instance_id:
				return "corpse_drop_item_order_invalid"
			previous_instance_id = instance_id
			actual_rolls.append({"roll_id": str(generated.roll_id),
				"definition_id": str(generated.definition_id),
				"quantity": int(generated.quantity)})
			total_quantity += int(generated.quantity)
		if actual_rolls != expected_rolls or event.magnitude != total_quantity:
			return "corpse_drop_roll_mismatch"
		materialized_by_death[death_id] = true
	for event in events:
		if event.type != "entity.died": continue
		if not processed.has(int(event.id)) or not materialized_by_death.has(int(event.id)):
			return "corpse_drop_death_unprocessed"
	if processed.size() != materialized_by_death.size():
		return "corpse_drop_processed_event_mismatch"
	return ""


func runtime_step_postcondition_error(event_start: int) -> String:
	# A live world begins at a fully-audited reset/load/restore boundary. During a
	# normal step, all mutation goes through checked systems and emit_event();
	# rescanning the entire append-only history after every hop made AUTO slower
	# as the run grew. Validate the newly appended causal tail plus the mutable
	# surfaces touched by a step here. Public save/replay and rollback restore
	# deliberately keep the exhaustive world_state_error() audit.
	if not is_settled(): return "runtime_step_not_settled"
	if event_start < 0 or event_start > events.size(): return "runtime_event_start_invalid"
	if _next_event_id <= 0 or events.size() != _next_event_id - 1:
		return "event_id_sequence_mismatch"
	if _next_entity_id <= 0 or combatant_states.size() != entities.size() \
			or item_state == null or item_state.inventory_rows.size() != entities.size() \
			or item_state.ammo_pool_rows.size() != entities.size():
		return "runtime_entity_surface_invalid"
	if scheduled_entries.size() != 2: return "invalid_canonical_schedule_count"
	var previous_schedule: Dictionary = {}
	for entry_value in scheduled_entries:
		if not entry_value is Dictionary: return "invalid_schedule_shape"
		var entry: Dictionary = entry_value
		if int(entry.get("due_time", -1)) <= world_time \
				or int(entry.get("repeat_interval", 0)) != ENVIRONMENT_INTERVAL \
				or str(entry.get("kind", "")) not in ["system.environment_tick", "system.actor_tick"]:
			return "runtime_schedule_invalid"
		if not previous_schedule.is_empty() and (
				int(previous_schedule.due_time) > int(entry.due_time) \
				or int(previous_schedule.due_time) == int(entry.due_time) \
				and int(previous_schedule.priority) > int(entry.priority)):
			return "runtime_schedule_order_invalid"
		previous_schedule = entry
	var dynamic_tile_error := runtime_dynamic_tiles_error()
	if not dynamic_tile_error.is_empty(): return dynamic_tile_error
	for entity_id_value in entities:
		var entity_id := int(entity_id_value)
		var entity = entities[entity_id]
		var combatant = combatant_states.get(entity_id)
		if entity_id <= 0 or entity.id != entity_id or combatant == null \
				or combatant.entity_id != entity_id or not in_bounds(entity.position) \
				or entity.max_health <= 0 or entity.health < 0 \
				or entity.health > entity.max_health:
			return "runtime_entity_projection_invalid"
		if combatant.life_state == "ACTIVE" and entity.health < 1:
			return "active_health_invariant"
		if combatant.life_state in ["DOWNED", "DEAD"] and entity.health != 0:
			return "runtime_life_health_mismatch"
	for index in range(event_start, events.size()):
		var event = events[index]
		if event == null or event.id != index + 1 or event.step_index != step_index \
				or event.world_time < 0 or event.world_time > world_time \
				or not (event.type is String) or event.type.is_empty() \
				or event.magnitude < 0 or event.magnitude > MAX_SMALL_VALUE \
				or not _runtime_position_is_valid(event.position, true) \
				or not _is_valid_event_data(event.data) \
				or not _entity_reference_is_valid(event.actor_id) \
				or not _entity_reference_is_valid(event.target_id) \
				or not _entity_reference_is_valid(event.instigator_id):
			return "runtime_event_tail_invalid"
		if event.cause_id == -1:
			if event.instigator_id != event.actor_id: return "root_instigator_mismatch"
		else:
			var cause = event_by_id(event.cause_id)
			if cause == null or cause.id >= event.id or cause.world_time > event.world_time \
					or event.instigator_id != cause.instigator_id:
				return "runtime_event_cause_invalid"
	if party_encounter != null:
		var party_error := PartyEncounterStateScript.wire_error(party_encounter.to_dict(), width, height)
		if not party_error.is_empty(): return party_error
		# HP is the one mutable party projection whose authority spans historical
		# damage/restoration leaves. Keep that ledger check in the incremental seam
		# so an out-of-band health write cannot be laundered by the next AUTO hop.
		var party_health_error := _party_health_restoration_error()
		if not party_health_error.is_empty(): return party_health_error
	return ""


func runtime_party_health_error() -> String:
	# AUTO skips a redundant whole-ledger memento audit, but must still reject an
	# externally-corrupted protagonist projection before it captures a rollback
	# image that could not safely restore. The authoritative health ledger is
	# shared with the incremental postcondition above.
	return _party_health_restoration_error() if party_encounter != null else ""


func _restored_state_error() -> String:
	if _active_step_index != -1:
		return "active_step_context_not_settled"
	var dimension_validation := dimensions_error(width, height)
	if not dimension_validation.is_empty():
		return dimension_validation
	if encounter_lab != null and party_encounter != null:
		return "encounter_mode_conflict"
	var profile_registry_error := CombatProfileRegistryScript.registry_error()
	if not profile_registry_error.is_empty(): return profile_registry_error
	var status_registry_error := StatusRegistryScript.registry_error()
	if not status_registry_error.is_empty(): return status_registry_error
	var actor_loadout_registry_error := ActorLoadoutRegistryScript.registry_error()
	if not actor_loadout_registry_error.is_empty(): return actor_loadout_registry_error
	var species_drop_registry_error := SpeciesDropRegistryScript.registry_error()
	if not species_drop_registry_error.is_empty(): return species_drop_registry_error
	if combatant_states.size() != entities.size(): return "combatant_entity_set_mismatch"
	var item_state_error := _item_state_error()
	if not item_state_error.is_empty(): return item_state_error
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
		var combatant = combatant_states.get(entity_id)
		if combatant == null or combatant.entity_id != entity_id: return "combatant_entity_set_mismatch"
		if combatant.combat_profile_id != CombatProfileRegistryScript.profile_id_for_kind(entity.kind) \
				or not CombatProfileRegistryScript.has(combatant.combat_profile_id):
			return "combatant_profile_kind_mismatch"
		if combatant.life_state == "ACTIVE":
			if entity.health < 1 or entity.health > entity.max_health: return "active_health_invariant"
			if combatant.guarded_until < 0 or combatant.guarded_until > MAX_WORLD_TIME \
					or combatant.downed_at != -1 or combatant.downed_resolve_at != -1 \
					or combatant.downed_source_event_id != -1 \
					or combatant.recovery_lock_until < 0 or combatant.recovery_lock_until > MAX_WORLD_TIME:
				return "active_combatant_sentinel_invalid"
			if (combatant.guarded_until == 0 and combatant.guard_source_event_id != -1) \
					or (combatant.guarded_until > 0 and combatant.guard_source_event_id <= 0):
				return "guard_source_sentinel_invalid"
			if (combatant.recovery_lock_until == 0 and combatant.recovery_source_event_id != -1) \
					or (combatant.recovery_lock_until > 0 and combatant.recovery_source_event_id <= 0):
				return "recovery_source_sentinel_invalid"
			if combatant.guard_source_event_id > 0:
				var guard_source = event_by_id(combatant.guard_source_event_id)
				if guard_source == null or guard_source.type != "action.hold" \
						or guard_source.actor_id != entity_id or guard_source.world_time > world_time \
						or guard_source.world_time > MAX_WORLD_TIME - 200 \
						or combatant.guarded_until != guard_source.world_time + 200:
					return "guard_source_event_invalid"
			if combatant.recovery_source_event_id > 0:
				var recovery_source = event_by_id(combatant.recovery_source_event_id)
				if recovery_source == null or recovery_source.type != "entity.recovered" \
						or recovery_source.target_id != entity_id or recovery_source.world_time > world_time \
						or recovery_source.world_time > MAX_WORLD_TIME - 100 \
						or combatant.recovery_lock_until != recovery_source.world_time + 100:
					return "recovery_source_event_invalid"
		elif combatant.life_state == "DOWNED":
			if entity.health != 0: return "downed_health_invariant"
			if combatant.guarded_until != 0 or combatant.guard_source_event_id != -1 \
					or combatant.downed_at < 0 or combatant.downed_at > world_time \
					or combatant.downed_source_event_id <= 0 \
					or combatant.recovery_lock_until != 0 or combatant.recovery_source_event_id != -1:
				return "downed_combatant_sentinel_invalid"
			if combatant.downed_resolve_at <= world_time or combatant.downed_resolve_at > MAX_WORLD_TIME:
				return "downed_resolve_time_invalid"
			if combatant.downed_at > MAX_WORLD_TIME - 200: return "downed_resolve_time_invalid"
			var expected_downed_resolve: int = (combatant.downed_at / 100 + 1) * 100 + 100
			if combatant.downed_resolve_at != expected_downed_resolve: return "downed_resolve_time_invalid"
			var downed_source = event_by_id(combatant.downed_source_event_id)
			if downed_source == null or downed_source.type != "entity.downed" \
					or downed_source.target_id != entity_id or downed_source.world_time != combatant.downed_at:
				return "downed_source_event_invalid"
		else:
			if combatant.life_state != "DEAD" or entity.health != 0: return "dead_health_invariant"
			if combatant.guarded_until != 0 or combatant.guard_source_event_id != -1 \
					or combatant.downed_at != -1 or combatant.downed_resolve_at != -1 \
					or combatant.downed_source_event_id != -1 or combatant.recovery_lock_until != 0 \
					or combatant.recovery_source_event_id != -1 or not combatant.status_rows.is_empty():
				return "dead_combatant_sentinel_invalid"
		if combatant.status_rows.size() > 1: return "runtime_status_bound_exceeded"
		var previous_status := ""
		for status in combatant.status_rows:
			if not StatusRegistryScript.has(status.status_id) or (not previous_status.is_empty() and status.status_id <= previous_status):
				return "unknown_duplicate_or_unsorted_status"
			previous_status = status.status_id
			if status.status_id != "BLEEDING" or status.applied_at < 0 or status.applied_at > status.refreshed_at \
					or status.refreshed_at > world_time or status.next_tick_at <= world_time \
					or status.next_tick_at % ACTOR_INTERVAL != 0 \
					or status.expires_at < status.next_tick_at \
					or status.expires_at % ACTOR_INTERVAL != 0 or status.source_event_id <= 0:
				return "combat_status_semantic_invalid"
			if combatant.life_state == "DOWNED" and status.next_tick_at > combatant.downed_resolve_at:
				return "downed_status_after_lifecycle_deadline"
		if entity.id != entity_id or not in_bounds(entity.position):
			return "entity_identity_or_position_invalid"
		var actor_state = agent_states.get(entity_id)
		var party_state = party_member_state(entity_id)
		if combatant.life_state != "DEAD" and (party_state == null or party_state.presence == "DEPLOYED") \
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
		if event.type == "action.melee_attack":
			var action_semantic_error := _melee_action_event_error(event)
			if not action_semantic_error.is_empty(): return action_semantic_error
		if event.type == "action.hold":
			var hold_semantic_error := _hold_event_error(event)
			if not hold_semantic_error.is_empty(): return hold_semantic_error
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
				var canonical_melee: bool = event.data.get("schema_version") in [1, 3] \
					and event.data.get("combat_ruleset_id") == COMBAT_RULESET_ID
				if event_actor_state == null or melee_target_state == null \
						or event_actor_state.trial_slot != melee_target_state.trial_slot \
						or _trial_slot_for_position(event.position) != event_actor_state.trial_slot \
						or not canonical_melee:
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
			var physical_cause = event_by_id(event.cause_id)
			var valid_physical_source: bool = physical_cause != null \
					and physical_cause.type in ["action.melee_attack", "status.tick"]
			var cause_is_canonical: bool = physical_cause != null \
					and physical_cause.data.get("schema_version") in [1, 3]
			var expected_requested: int = physical_cause.magnitude if physical_cause != null else 0
			if physical_cause != null and physical_cause.type == "action.melee_attack" \
					and cause_is_canonical:
				expected_requested = int(physical_cause.data.get("final_damage", 0))
			var valid_physical_data: bool = cause_is_canonical \
				and _canonical_damage_data_error(
					event, "physical", expected_requested).is_empty()
			if event.actor_id != -1 or not valid_physical_source \
					or physical_cause.target_id != event.target_id or physical_cause.position != event.position \
					or physical_cause.step_index != event.step_index \
					or physical_cause.world_time != event.world_time or not valid_physical_data \
					or event.magnitude <= 0 or event.magnitude > physical_cause.magnitude:
				return "physical_damage_chain_invalid"
		if event.type in ["combat.fire_damage", "combat.electric_damage"]:
			var typed_damage_type: String = str(event.type).trim_prefix("combat.") \
				.trim_suffix("_damage")
			var typed_damage_error := ""
			if event.data.get("schema_version") == 1:
				typed_damage_error = _canonical_typed_damage_event_error(event)
			elif event.data == {"damage_type": typed_damage_type}:
				typed_damage_error = _legacy_typed_damage_event_error(event, typed_damage_type)
			else:
				typed_damage_error = "typed_damage_schema_invalid"
			if not typed_damage_error.is_empty(): return typed_damage_error
		if event.type == "entity.died" and event.data.get("schema_version") != 1:
			var legacy_death_error := _legacy_death_event_error(event)
			if not legacy_death_error.is_empty(): return legacy_death_error
		for reference_id in [event.actor_id, event.target_id, event.instigator_id]:
			if reference_id != -1 and (reference_id <= 0 or not entities.has(reference_id)):
				return "event_entity_reference_invalid"
	var corpse_drop_history_error := _corpse_drop_history_error()
	if not corpse_drop_history_error.is_empty(): return corpse_drop_history_error
	var miss_history_error := _canonical_miss_history_error()
	if not miss_history_error.is_empty(): return miss_history_error
	var hit_history_error := _canonical_hit_history_error()
	if not hit_history_error.is_empty(): return hit_history_error
	var parry_history_error := _canonical_parry_history_error()
	if not parry_history_error.is_empty(): return parry_history_error
	var overkill_history_error := _canonical_overkill_history_error()
	if not overkill_history_error.is_empty(): return overkill_history_error
	var status_history_error := _status_history_error()
	if not status_history_error.is_empty(): return status_history_error
	var lifecycle_history_error := _lifecycle_history_error()
	if not lifecycle_history_error.is_empty(): return lifecycle_history_error
	var guard_history_error := _guard_history_error()
	if not guard_history_error.is_empty(): return guard_history_error
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
				if combatant_states[lead_id].life_state != "ACTIVE" or lead_state.current_activity != "ESCAPE" \
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
			if combatant_states[lead_id].life_state == "ACTIVE" and agent_states[lead_id].encounter_status == "ACTIVE": active_lead_count += 1
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


func _melee_action_event_error(event) -> String:
	if event.actor_id <= 0 or event.target_id <= 0 or event.actor_id == event.target_id \
			or not entities.has(event.actor_id) or not entities.has(event.target_id) \
			or event.position == Vector2i(-1, -1):
		return "melee_event_envelope_invalid"
	if event.data.get("schema_version") == 3:
		return _melee_defense_action_event_error(event)
	var attacker_state = combatant_states[event.actor_id]
	var target_state = combatant_states[event.target_id]
	var attacker_profile: Dictionary = CombatProfileRegistryScript.profile(attacker_state.combat_profile_id)
	var target_profile: Dictionary = CombatProfileRegistryScript.profile(target_state.combat_profile_id)
	var base_damage: int = int(attacker_profile.get("power", 0))
	var weapon_enabled:bool = party_encounter != null \
		and event.actor_id == party_encounter.protagonist_id \
		and "weapon_loadout" in entities[event.actor_id].tags
	var weapon_spec: Dictionary = {}
	if weapon_enabled:
		var weapon_id := WorldItemOperationsScript.equipped_weapon_id(self, event.actor_id)
		var weapon = WeaponRegistryScript.definition(weapon_id)
		if weapon == null: return "canonical_weapon_missing"
		var weapon_rank := _progression_rank_before(weapon.proficiency_id, event.id)
		weapon_spec = WeaponAttackRulesScript.build_attack_spec(weapon_id, weapon_rank,
			int(attacker_profile.power), int(attacker_profile.accuracy_milli),
			int(target_profile.evasion_milli), int(target_profile.armor_flat),
			ActorStatRulesScript.for_entity(self,event.actor_id))
		if weapon_spec.is_empty(): return "canonical_weapon_formula_invalid"
		base_damage = int(weapon_spec.raw_damage)
	elif party_encounter!=null and event.actor_id==party_encounter.protagonist_id:
		base_damage+=ProgressionRegistryScript.melee_power_bonus(
			_progression_melee_rank_before(event.id))
	var armor_reduction: int = int(weapon_spec.armor_reduction) if weapon_enabled \
		else mini(int(target_profile.get("armor_flat", 0)), maxi(0, base_damage - 1))
	var after_armor: int = base_damage - armor_reduction
	var action_keys := ["armor_flat", "armor_reduction", "attack_start_world_time", "attacker_profile_id",
		"base_damage", "batch_context", "bleed_chance_milli", "bleed_proc_succeeded",
		"bleed_roll_milli", "combat_ruleset_id", "commitment_hash", "final_damage",
		"frozen_guarded_until", "guard_reduction", "guard_source_event_id", "guarded",
		"hit_chance_milli", "hit_roll_milli", "intent_mode", "intent_ordinal", "outcome",
		"processed_step_index", "schema_version", "target_evasion_milli", "target_life_at_batch_start",
		"target_profile_id"]
	if not _exact_keys(event.data, action_keys) or event.data.get("schema_version") != 1 \
			or event.data.get("combat_ruleset_id") != COMBAT_RULESET_ID:
		return "canonical_melee_event_data_invalid"
	for key in ["processed_step_index", "attack_start_world_time", "frozen_guarded_until",
			"guard_source_event_id"]:
		if not Int64CodecScript.is_canonical(event.data.get(key)):
			return "canonical_melee_event_int64_invalid"
	for key in ["intent_ordinal", "hit_chance_milli", "hit_roll_milli", "bleed_chance_milli",
			"bleed_roll_milli", "base_damage", "target_evasion_milli", "armor_flat",
			"armor_reduction", "guard_reduction", "final_damage"]:
		if not event.data.get(key) is int:
			return "canonical_melee_event_scalar_invalid"
	if not event.data.get("guarded") is bool or not event.data.get("bleed_proc_succeeded") is bool \
			or not event.data.get("batch_context") is String \
			or not event.data.get("commitment_hash") is String:
		return "canonical_melee_event_scalar_invalid"
	var processed_step: int = Int64CodecScript.parse(event.data.processed_step_index, "action processed step")
	var attack_start: int = Int64CodecScript.parse(event.data.attack_start_world_time, "action start")
	var frozen_guarded_until: int = Int64CodecScript.parse(event.data.frozen_guarded_until, "frozen guard")
	var guard_source_id: int = Int64CodecScript.parse(event.data.guard_source_event_id, "frozen guard source")
	if processed_step != event.step_index or attack_start != event.world_time \
			or frozen_guarded_until < 0 or frozen_guarded_until > MAX_WORLD_TIME \
			or (frozen_guarded_until == 0) != (guard_source_id == -1) \
			or (frozen_guarded_until > 0 and guard_source_id <= 0) \
			or not _combat_batch_context_valid(str(event.data.batch_context), processed_step, attack_start):
		return "canonical_melee_event_context_invalid"
	if guard_source_id > 0:
		var frozen_guard_source = event_by_id(guard_source_id)
		if frozen_guard_source == null or frozen_guard_source.type != "action.hold" \
				or frozen_guard_source.actor_id != event.target_id or frozen_guard_source.id >= event.id \
				or frozen_guard_source.world_time + 200 != frozen_guarded_until:
			return "canonical_melee_guard_source_invalid"
	if event.data.attacker_profile_id != attacker_state.combat_profile_id \
			or event.data.target_profile_id != target_state.combat_profile_id \
			or event.data.target_evasion_milli != int(target_profile.evasion_milli) \
			or event.data.armor_flat != int(target_profile.armor_flat) \
			or event.data.base_damage != base_damage or event.data.armor_reduction != armor_reduction \
			or event.magnitude != base_damage:
		return "canonical_melee_profile_formula_invalid"
	var hit_chance: int = int(weapon_spec.hit_chance_milli) if weapon_enabled \
		else clampi(500 + int(attacker_profile.accuracy_milli) \
		- int(target_profile.evasion_milli), 50, 950)
	var bleed_chance: int = clampi(int(attacker_profile.bleed_proc_milli) \
		- int(target_profile.bleed_resist_milli), 0, 1000)
	var target_life: String = str(event.data.target_life_at_batch_start)
	var intent_mode: String = str(event.data.intent_mode)
	var outcome: String = str(event.data.outcome)
	if target_life not in ["ACTIVE", "DOWNED"] or intent_mode not in ["STRIKE", "FINISHER"] \
			or outcome not in ["HIT", "MISS", "OVERKILL_SKIP", "FINISHER"] \
			or int(event.data.intent_ordinal) < 0:
		return "canonical_melee_intent_invalid"
	var key: String = WeaponAttackRulesScript.commitment_key(seed, processed_step, attack_start,
		str(event.data.batch_context), int(event.data.intent_ordinal), event.actor_id, event.target_id,
		str(weapon_spec.weapon_id), int(weapon_spec.proficiency_rank)) if weapon_enabled \
		else MeleeCombatSystemScript.commitment_key(seed, processed_step, attack_start,
		str(event.data.batch_context), int(event.data.intent_ordinal), event.actor_id, event.target_id)
	var hit_roll: int = WeaponAttackRulesScript.lane_roll_milli(key, "HIT") if weapon_enabled \
		else MeleeCombatSystemScript.lane_roll_milli(key, "HIT")
	var bleed_roll: int = WeaponAttackRulesScript.lane_roll_milli(key, "BLEED") if weapon_enabled \
		else MeleeCombatSystemScript.lane_roll_milli(key, "BLEED")
	if event.data.commitment_hash != MeleeCombatSystemScript.commitment_hash(key) \
			or event.data.hit_roll_milli != hit_roll or event.data.bleed_roll_milli != bleed_roll:
		return "canonical_melee_commitment_invalid"
	if target_life == "DOWNED":
		if intent_mode != "FINISHER" or outcome not in ["FINISHER", "OVERKILL_SKIP"] \
				or event.data.hit_chance_milli != 1000 or event.data.bleed_chance_milli != 0 \
				or event.data.guarded or event.data.guard_reduction != 0 \
				or event.data.final_damage != 0 or event.data.bleed_proc_succeeded:
			return "canonical_melee_finisher_formula_invalid"
		return ""
	var expected_guarded: bool = attack_start < frozen_guarded_until
	var guard_rank:=_progression_rank_before("GUARD",event.id) \
		if party_encounter!=null and event.target_id==party_encounter.protagonist_id else 0
	var guard_rate_milli:=ProgressionRegistryScript.guard_reduction_milli(guard_rank)
	var expected_guard_reduction: int = int(after_armor * guard_rate_milli / 1000) if expected_guarded else 0
	var normal_damage: int = maxi(1, after_armor - expected_guard_reduction)
	if intent_mode != "STRIKE" or event.data.hit_chance_milli != hit_chance \
			or event.data.bleed_chance_milli != bleed_chance \
			or event.data.guarded != expected_guarded \
			or event.data.guard_reduction != expected_guard_reduction:
		return "canonical_melee_strike_formula_invalid"
	var roll_hits: bool = hit_roll < hit_chance
	if outcome == "HIT":
		if not roll_hits or event.data.final_damage != normal_damage \
				or event.data.bleed_proc_succeeded != (bleed_roll < bleed_chance):
			return "canonical_melee_hit_outcome_invalid"
	elif outcome == "MISS":
		if roll_hits or event.data.final_damage != 0 or event.data.bleed_proc_succeeded:
			return "canonical_melee_miss_outcome_invalid"
	elif outcome == "OVERKILL_SKIP":
		if event.data.final_damage != 0 or event.data.bleed_proc_succeeded:
			return "canonical_melee_overkill_outcome_invalid"
	else:
		return "canonical_melee_strike_outcome_invalid"
	return ""


# Schema 3 freezes only the active protagonist's equipment-defense snapshot.
# Inventory can legitimately change later, so replay validates the frozen
# snapshot and its commitment rather than reading the current loadout.
# TODO(v4): item event rows currently preserve instance/slot but not a complete
# historical item-definition+affix projection; add that provenance before
# reconstructing and comparing past equipped totals at every action boundary.
func _melee_defense_action_event_error(event) -> String:
	if party_encounter == null or event.target_id != party_encounter.protagonist_id \
			or event.actor_id == party_encounter.protagonist_id:
		return "canonical_defense_target_invalid"
	var attacker_state = combatant_states[event.actor_id]
	var target_state = combatant_states[event.target_id]
	var attacker_profile: Dictionary = CombatProfileRegistryScript.profile(attacker_state.combat_profile_id)
	var target_profile: Dictionary = CombatProfileRegistryScript.profile(target_state.combat_profile_id)
	if attacker_profile.is_empty() or target_profile.is_empty():
		return "canonical_defense_profile_missing"
	var action_keys := ["armor_flat", "armor_reduction", "attack_start_world_time",
		"attacker_profile_id", "base_damage", "batch_context", "bleed_chance_milli",
		"bleed_proc_succeeded", "bleed_roll_milli", "combat_ruleset_id", "commitment_hash",
		"defense_ruleset_id", "equipment_armor_flat", "equipment_dodge_milli",
		"equipment_parry_milli", "final_damage", "frozen_guarded_until", "guard_reduction",
		"guard_source_event_id", "guarded", "hit_chance_milli", "hit_roll_milli",
		"intent_mode", "intent_ordinal", "outcome", "parry_roll_milli", "parry_succeeded",
		"processed_step_index", "schema_version", "target_base_armor_flat",
		"target_base_evasion_milli", "target_evasion_milli", "target_life_at_batch_start",
		"target_profile_id"]
	if not _exact_keys(event.data, action_keys) \
			or event.data.get("combat_ruleset_id") != COMBAT_RULESET_ID \
			or event.data.get("defense_ruleset_id") != CombatDefenseRulesScript.RULESET_ID:
		return "canonical_defense_event_data_invalid"
	for key in ["processed_step_index", "attack_start_world_time", "frozen_guarded_until",
			"guard_source_event_id"]:
		if not Int64CodecScript.is_canonical(event.data.get(key)):
			return "canonical_defense_event_int64_invalid"
	for key in ["intent_ordinal", "hit_chance_milli", "hit_roll_milli", "bleed_chance_milli",
			"bleed_roll_milli", "parry_roll_milli", "base_damage", "target_evasion_milli",
			"armor_flat", "armor_reduction", "guard_reduction", "final_damage",
			"target_base_evasion_milli", "target_base_armor_flat", "equipment_dodge_milli",
			"equipment_armor_flat", "equipment_parry_milli"]:
		if not event.data.get(key) is int:
			return "canonical_defense_event_scalar_invalid"
	if not event.data.get("guarded") is bool or not event.data.get("bleed_proc_succeeded") is bool \
			or not event.data.get("parry_succeeded") is bool \
			or not event.data.get("batch_context") is String \
			or not event.data.get("commitment_hash") is String:
		return "canonical_defense_event_scalar_invalid"
	var processed_step: int = Int64CodecScript.parse(event.data.processed_step_index, "action processed step")
	var attack_start: int = Int64CodecScript.parse(event.data.attack_start_world_time, "action start")
	var frozen_guarded_until: int = Int64CodecScript.parse(event.data.frozen_guarded_until, "frozen guard")
	var guard_source_id: int = Int64CodecScript.parse(event.data.guard_source_event_id, "frozen guard source")
	if processed_step != event.step_index or attack_start != event.world_time \
			or frozen_guarded_until < 0 or frozen_guarded_until > MAX_WORLD_TIME \
			or (frozen_guarded_until == 0) != (guard_source_id == -1) \
			or (frozen_guarded_until > 0 and guard_source_id <= 0) \
			or not _combat_batch_context_valid(str(event.data.batch_context), processed_step, attack_start):
		return "canonical_defense_event_context_invalid"
	if guard_source_id > 0:
		var frozen_guard_source = event_by_id(guard_source_id)
		if frozen_guard_source == null or frozen_guard_source.type != "action.hold" \
				or frozen_guard_source.actor_id != event.target_id or frozen_guard_source.id >= event.id \
				or frozen_guard_source.world_time + 200 != frozen_guarded_until:
			return "canonical_defense_guard_source_invalid"
	var snapshot := CombatDefenseRulesScript.build_snapshot(
		int(event.data.target_base_evasion_milli), int(event.data.target_base_armor_flat), {
			"armor_flat": int(event.data.equipment_armor_flat),
			"dodge_milli": int(event.data.equipment_dodge_milli),
			"parry_milli": int(event.data.equipment_parry_milli),
		})
	if snapshot.is_empty() or event.data.attacker_profile_id != attacker_state.combat_profile_id \
			or event.data.target_profile_id != target_state.combat_profile_id \
			or event.data.target_base_evasion_milli != int(target_profile.evasion_milli) \
			or event.data.target_base_armor_flat != int(target_profile.armor_flat) \
			or event.data.target_evasion_milli != int(snapshot.effective_evasion_milli) \
			or event.data.armor_flat != int(snapshot.effective_armor_flat):
		return "canonical_defense_snapshot_invalid"
	var base_damage: int = int(attacker_profile.power)
	var armor_reduction: int = CombatDefenseRulesScript.armor_reduction(base_damage, 0, snapshot)
	if armor_reduction < 0 or event.data.base_damage != base_damage \
			or event.data.armor_reduction != armor_reduction or event.magnitude != base_damage:
		return "canonical_defense_armor_formula_invalid"
	var hit_chance: int = clampi(500 + int(attacker_profile.accuracy_milli) \
		- int(snapshot.effective_evasion_milli), 50, 950)
	var bleed_chance: int = clampi(int(attacker_profile.bleed_proc_milli) \
		- int(target_profile.bleed_resist_milli), 0, 1000)
	var target_life: String = str(event.data.target_life_at_batch_start)
	var intent_mode: String = str(event.data.intent_mode)
	var outcome: String = str(event.data.outcome)
	if target_life != "ACTIVE" or intent_mode != "STRIKE" \
			or outcome not in ["HIT", "MISS", "PARRIED", "OVERKILL_SKIP"] \
			or int(event.data.intent_ordinal) < 0:
		return "canonical_defense_intent_invalid"
	var key := MeleeCombatSystemScript.commitment_key(seed, processed_step, attack_start,
		str(event.data.batch_context), int(event.data.intent_ordinal), event.actor_id, event.target_id,
		CombatDefenseRulesScript.commitment_fragment(snapshot))
	var hit_roll := MeleeCombatSystemScript.lane_roll_milli(key, "HIT")
	var bleed_roll := MeleeCombatSystemScript.lane_roll_milli(key, "BLEED")
	var parry_roll := CombatDefenseRulesScript.parry_roll_milli(key)
	if event.data.commitment_hash != MeleeCombatSystemScript.commitment_hash(key) \
			or event.data.hit_roll_milli != hit_roll or event.data.bleed_roll_milli != bleed_roll \
			or event.data.parry_roll_milli != parry_roll:
		return "canonical_defense_commitment_invalid"
	var expected_guarded: bool = attack_start < frozen_guarded_until
	var guard_rank := _progression_rank_before("GUARD", event.id)
	var guard_reduction: int = int((base_damage - armor_reduction) \
		* ProgressionRegistryScript.guard_reduction_milli(guard_rank) / 1000) if expected_guarded else 0
	var normal_damage := maxi(1, base_damage - armor_reduction - guard_reduction)
	if event.data.hit_chance_milli != hit_chance or event.data.bleed_chance_milli != bleed_chance \
			or event.data.guarded != expected_guarded or event.data.guard_reduction != guard_reduction:
		return "canonical_defense_strike_formula_invalid"
	var roll_hits: bool = hit_roll < hit_chance
	var parried: bool = roll_hits and CombatDefenseRulesScript.parry_succeeds(parry_roll, snapshot)
	if outcome == "HIT":
		if not roll_hits or parried or event.data.parry_succeeded \
				or event.data.final_damage != normal_damage \
				or event.data.bleed_proc_succeeded != (bleed_roll < bleed_chance):
			return "canonical_defense_hit_outcome_invalid"
	elif outcome == "MISS":
		if roll_hits or event.data.parry_succeeded or event.data.final_damage != 0 \
				or event.data.bleed_proc_succeeded:
			return "canonical_defense_miss_outcome_invalid"
	elif outcome == "PARRIED":
		if not parried or not event.data.parry_succeeded or event.data.final_damage != 0 \
				or event.data.bleed_proc_succeeded:
			return "canonical_defense_parry_outcome_invalid"
	else:
		# A lower-id attacker may already have killed the protagonist in the same
		# frozen enemy batch. The later intent keeps its committed rolls/defense
		# snapshot but owns no result child and cannot apply damage.
		if event.data.parry_succeeded != parried or event.data.final_damage != 0 \
				or event.data.bleed_proc_succeeded:
			return "canonical_defense_overkill_outcome_invalid"
	return ""


func _canonical_miss_history_error() -> String:
	var consumed_miss_ids: Dictionary = {}
	for action in events:
		if action.type != "action.melee_attack" \
				or action.data.get("schema_version") not in [1, 3] \
				or action.data.get("outcome") != "MISS":
			continue
		var direct_children: Array = []
		for candidate in events:
			if candidate.cause_id == action.id and candidate.type in [
					"combat.attack_missed", "combat.attack_parried", "combat.physical_damage", "combat.downed_damage"]:
				direct_children.append(candidate)
		if direct_children.size() != 1:
			return "canonical_miss_result_cardinality_invalid"
		var miss = direct_children[0]
		if miss.type != "combat.attack_missed" \
				or miss.actor_id != -1 or miss.target_id != action.target_id \
				or miss.position != action.position or miss.magnitude != 0 \
				or miss.cause_id != action.id or miss.instigator_id != action.instigator_id \
				or miss.step_index != action.step_index or miss.world_time != action.world_time \
				or not _exact_keys(miss.data, ["combat_ruleset_id", "outcome", "schema_version"]) \
				or miss.data.get("schema_version") != 1 \
				or miss.data.get("combat_ruleset_id") != COMBAT_RULESET_ID \
				or miss.data.get("outcome") != "MISS":
			return "canonical_attack_missed_invalid"
		if consumed_miss_ids.has(miss.id):
			return "canonical_attack_missed_consumed_twice"
		consumed_miss_ids[miss.id] = true
	for event in events:
		if event.type == "combat.attack_missed" \
				and (event.data.get("schema_version") != 1 \
				or not consumed_miss_ids.has(event.id)):
			return "canonical_attack_missed_unconsumed"
	return ""


func _canonical_hit_history_error() -> String:
	var consumed_physical_ids: Dictionary = {}
	for action in events:
		if action.type != "action.melee_attack" \
				or action.data.get("schema_version") not in [1, 3] \
				or action.data.get("outcome") != "HIT":
			continue
		var direct_children: Array = []
		for candidate in events:
			if candidate.cause_id == action.id and candidate.type in [
					"combat.attack_missed", "combat.attack_parried", "combat.physical_damage", "combat.downed_damage"]:
				direct_children.append(candidate)
		if direct_children.size() != 1:
			return "canonical_hit_result_cardinality_invalid"
		var damage = direct_children[0]
		var requested_damage: int = int(action.data.get("final_damage", 0))
		if damage.type != "combat.physical_damage" \
				or damage.actor_id != -1 or damage.target_id != action.target_id \
				or damage.position != action.position or damage.magnitude <= 0 \
				or damage.magnitude > requested_damage or damage.cause_id != action.id \
				or damage.instigator_id != action.instigator_id \
				or damage.step_index != action.step_index or damage.world_time != action.world_time \
				or not _canonical_damage_data_error(
					damage, "physical", requested_damage).is_empty():
			return "canonical_hit_physical_child_invalid"
		if consumed_physical_ids.has(damage.id):
			return "canonical_hit_physical_consumed_twice"
		consumed_physical_ids[damage.id] = true
	for event in events:
		if event.type != "combat.physical_damage" \
				or event.data.get("schema_version") != 1:
			continue
		var source = event_by_id(event.cause_id)
		if source != null and source.type == "action.melee_attack" \
				and source.data.get("schema_version") in [1, 3] \
				and source.data.get("outcome") == "HIT" \
				and not consumed_physical_ids.has(event.id):
			return "canonical_hit_physical_unconsumed"
	return ""


func _canonical_parry_history_error() -> String:
	var consumed_parry_ids: Dictionary = {}
	for action in events:
		if action.type != "action.melee_attack" \
				or action.data.get("schema_version") != 3 \
				or action.data.get("outcome") != "PARRIED":
			continue
		var direct_children: Array = []
		for candidate in events:
			if candidate.cause_id == action.id and candidate.type in [
					"combat.attack_missed", "combat.attack_parried", "combat.physical_damage", "combat.downed_damage"]:
				direct_children.append(candidate)
		if direct_children.size() != 1:
			return "canonical_parry_result_cardinality_invalid"
		var parry = direct_children[0]
		if parry.type != "combat.attack_parried" \
				or parry.actor_id != -1 or parry.target_id != action.target_id \
				or parry.position != action.position or parry.magnitude != 0 \
				or parry.cause_id != action.id or parry.instigator_id != action.instigator_id \
				or parry.step_index != action.step_index or parry.world_time != action.world_time \
				or not _exact_keys(parry.data, ["combat_ruleset_id", "outcome", "schema_version"]) \
				or parry.data.get("schema_version") != 1 \
				or parry.data.get("combat_ruleset_id") != COMBAT_RULESET_ID \
				or parry.data.get("outcome") != "PARRIED":
			return "canonical_attack_parried_invalid"
		if consumed_parry_ids.has(parry.id):
			return "canonical_attack_parried_consumed_twice"
		consumed_parry_ids[parry.id] = true
	for event in events:
		if event.type == "combat.attack_parried" \
				and (event.data.get("schema_version") != 1 \
				or not consumed_parry_ids.has(event.id)):
			return "canonical_attack_parried_unconsumed"
	return ""


func _canonical_overkill_history_error() -> String:
	var batch_groups: Dictionary = {}
	for action in events:
		if action.type != "action.melee_attack" \
				or action.data.get("schema_version") not in [1, 3]:
			continue
		var group_key := "%d|%d|%s" % [action.step_index, action.world_time,
			str(action.data.get("batch_context", ""))]
		var group_actions: Array = batch_groups.get(group_key, [])
		group_actions.append(action)
		batch_groups[group_key] = group_actions
	for group_key in batch_groups:
		var group_actions: Array = batch_groups[group_key]
		var first_action_id: int = int(group_actions[0].id)
		var seen_actor_ids: Dictionary = {}
		for action in group_actions:
			first_action_id = mini(first_action_id, int(action.id))
			if seen_actor_ids.has(action.actor_id):
				return "canonical_melee_batch_actor_duplicate"
			seen_actor_ids[action.actor_id] = true
		var canonical_order: Array = group_actions.duplicate()
		canonical_order.sort_custom(func(a, b):
			if a.target_id != b.target_id: return a.target_id < b.target_id
			return a.actor_id < b.actor_id)
		for expected_ordinal in range(canonical_order.size()):
			if int(canonical_order[expected_ordinal].data.get("intent_ordinal", -1)) \
					!= expected_ordinal:
				return "canonical_melee_batch_sort_invalid"
		var frozen_positions: Dictionary = {}
		for action in group_actions:
			for entity_id in [action.actor_id, action.target_id]:
				if frozen_positions.has(entity_id):
					continue
				var projection := _canonical_batch_start_position(entity_id, first_action_id,
					int(action.step_index), int(action.world_time))
				if not bool(projection.ok):
					return "canonical_melee_batch_position_history_invalid"
				frozen_positions[entity_id] = projection.position
			var attacker_position: Vector2i = frozen_positions[action.actor_id]
			var target_position: Vector2i = frozen_positions[action.target_id]
			if action.position != target_position \
					or maxi(absi(attacker_position.x - target_position.x),
						absi(attacker_position.y - target_position.y)) != 1:
				return "canonical_melee_batch_frozen_position_invalid"
		var frozen_life: Dictionary = {}
		for action in group_actions:
			for entity_id in [action.actor_id, action.target_id]:
				if frozen_life.has(entity_id):
					continue
				var projection := _canonical_life_at_event(entity_id, first_action_id)
				if not bool(projection.ok):
					return "canonical_melee_batch_life_history_invalid"
				frozen_life[entity_id] = projection
			var attacker_life: Dictionary = frozen_life[action.actor_id]
			var target_life: Dictionary = frozen_life[action.target_id]
			if str(target_life.life_state) != str(action.data.target_life_at_batch_start):
				return "canonical_melee_batch_target_life_invalid"
			if str(attacker_life.life_state) != "ACTIVE" \
					or int(action.world_time) < int(attacker_life.recovery_lock_until):
				return "canonical_melee_batch_attacker_cannot_act"
		var frozen_guards: Dictionary = {}
		for action in group_actions:
			if not frozen_guards.has(action.target_id):
				var projection := _canonical_guard_at_event(action.target_id, first_action_id,
					int(action.step_index), int(action.world_time))
				if not bool(projection.ok):
					return "canonical_melee_batch_guard_history_invalid"
				frozen_guards[action.target_id] = projection
			var expected_guard: Dictionary = frozen_guards[action.target_id]
			if Int64CodecScript.parse(action.data.frozen_guarded_until,
					"frozen guard time") != int(expected_guard.guarded_until) \
					or Int64CodecScript.parse(action.data.guard_source_event_id,
						"frozen guard source") != int(expected_guard.source_event_id):
				return "canonical_melee_batch_guard_projection_invalid"
		var seen_ordinals: Dictionary = {}
		for action in group_actions:
			var ordinal: int = int(action.data.get("intent_ordinal", -1))
			if ordinal < 0 or seen_ordinals.has(ordinal):
				return "canonical_melee_batch_ordinal_invalid"
			seen_ordinals[ordinal] = true
		for expected_ordinal in range(group_actions.size()):
			if not seen_ordinals.has(expected_ordinal):
				return "canonical_melee_batch_ordinal_invalid"
		var prefix_max_id := first_action_id
		for action in group_actions:
			prefix_max_id = maxi(prefix_max_id, int(action.id))
			for candidate in events:
				if candidate.cause_id == action.id \
						and candidate.type == "party.override_committed":
					prefix_max_id = maxi(prefix_max_id, int(candidate.id))
		var result_drivers: Array = []
		for action in group_actions:
			var outcome: String = str(action.data.get("outcome", ""))
			var expected_driver_type: String = {
				"MISS": "combat.attack_missed",
				"PARRIED": "combat.attack_parried",
				"HIT": "combat.physical_damage",
				"FINISHER": "combat.downed_damage",
			}.get(outcome, "")
			var direct_drivers: Array = []
			for candidate in events:
				if candidate.cause_id == action.id and candidate.type in [
						"combat.attack_missed", "combat.attack_parried", "combat.physical_damage", "combat.downed_damage"]:
					direct_drivers.append(candidate)
			if outcome == "OVERKILL_SKIP":
				if not direct_drivers.is_empty():
					return "canonical_overkill_result_child_invalid"
				continue
			if expected_driver_type.is_empty() or direct_drivers.size() != 1 \
					or direct_drivers[0].type != expected_driver_type:
				return "canonical_melee_result_driver_invalid"
			var driver = direct_drivers[0]
			if driver.id <= prefix_max_id:
				return "canonical_melee_result_before_action_prefix"
			result_drivers.append({"ordinal":int(action.data.intent_ordinal), "id":driver.id,
				"step_index":driver.step_index, "world_time":driver.world_time})
		result_drivers.sort_custom(func(a: Dictionary, b: Dictionary):
			return int(a.ordinal) < int(b.ordinal))
		var previous_driver_id := -1
		for driver in result_drivers:
			if int(driver.id) <= previous_driver_id:
				return "canonical_melee_result_driver_order_invalid"
			previous_driver_id = int(driver.id)
		for driver_index in range(result_drivers.size() - 1):
			var driver: Dictionary = result_drivers[driver_index]
			var next_driver: Dictionary = result_drivers[driver_index + 1]
			var tail_max_id := _canonical_melee_result_tail_max_id(int(driver.id),
				int(driver.step_index), int(driver.world_time))
			if tail_max_id >= int(next_driver.id):
				return "canonical_melee_result_tail_order_invalid"
		for action in group_actions:
			if action.data.get("outcome") != "OVERKILL_SKIP":
				continue
			for candidate in events:
				if candidate.cause_id == action.id and candidate.type in [
						"combat.attack_missed", "combat.attack_parried", "combat.physical_damage", "combat.downed_damage"]:
					return "canonical_overkill_result_child_invalid"
			var transition_proven := false
			var overkill_ordinal: int = int(action.data.intent_ordinal)
			for earlier_action in group_actions:
				if int(earlier_action.data.intent_ordinal) >= overkill_ordinal \
						or earlier_action.target_id != action.target_id:
					continue
				var earlier_outcome: String = str(earlier_action.data.get("outcome", ""))
				if earlier_outcome == "HIT":
					var hit_damage = null
					for candidate in events:
						if candidate.cause_id == earlier_action.id \
								and candidate.type == "combat.physical_damage" \
								and candidate.data.get("schema_version") == 1:
							hit_damage = candidate
							break
					if hit_damage == null:
						continue
					for candidate in events:
						if candidate.cause_id == hit_damage.id \
								and candidate.type == "entity.downed" \
								and candidate.data.get("schema_version") == 1 \
								and candidate.target_id == action.target_id:
							transition_proven = true
							break
				elif earlier_outcome == "FINISHER":
					var result_children: Array = []
					for candidate in events:
						if candidate.cause_id == earlier_action.id and candidate.type in [
								"combat.attack_missed", "combat.attack_parried", "combat.physical_damage", "combat.downed_damage"]:
							result_children.append(candidate)
					if result_children.size() != 1:
						continue
					var pressure = result_children[0]
					if pressure.type != "combat.downed_damage" \
							or pressure.data.get("schema_version") != 1 \
							or pressure.data.get("reason") != "FINISHER" \
							or pressure.target_id != action.target_id:
						continue
					var death_children: Array = []
					for candidate in events:
						if candidate.cause_id == pressure.id and candidate.type == "entity.died":
							death_children.append(candidate)
					if death_children.size() == 1:
						var death = death_children[0]
						transition_proven = death.data.get("schema_version") == 1 \
								and death.data.get("reason") == "FINISHER" \
								and death.target_id == action.target_id
				if transition_proven:
					break
			if not transition_proven:
				return "canonical_overkill_transition_missing"
	return ""


func _canonical_melee_result_tail_max_id(driver_id: int, processed_step: int,
		attack_time: int) -> int:
	var owned_ids := {driver_id:true}
	var tail_max_id := driver_id
	var resolution_types := ["combat.attack_missed", "combat.attack_parried", "combat.physical_damage",
		"combat.downed_damage", "entity.downed", "entity.recovered", "entity.died",
		"status.applied", "status.refreshed", "status.expired"]
	for event in events:
		if event.id <= driver_id or event.step_index != processed_step \
				or event.world_time != attack_time or not owned_ids.has(event.cause_id) \
				or event.type not in resolution_types \
				or event.data.get("schema_version") != 1:
			continue
		owned_ids[event.id] = true
		tail_max_id = maxi(tail_max_id, event.id)
	return tail_max_id


func _canonical_batch_start_position(entity_id: int, first_action_id: int,
		processed_step: int, attack_time: int) -> Dictionary:
	var boundary_projection: Dictionary = _entity_position_at_event(entity_id, first_action_id)
	if not bool(boundary_projection.ok):
		return {"ok":false, "position":Vector2i(-1, -1)}
	var boundary_position: Vector2i = boundary_projection.position
	var frozen_position := boundary_position
	for index in range(_event_index(first_action_id) - 1, -1, -1):
		var event = events[index]
		if event.step_index != processed_step or event.world_time != attack_time \
				or event.type != "action.move" or event.actor_id != entity_id:
			continue
		var move_positions := _canonical_move_positions(event)
		if not bool(move_positions.ok) or move_positions.to != frozen_position:
			return {"ok":false, "position":Vector2i(-1, -1)}
		frozen_position = move_positions.from
	var final_projection := boundary_position
	var grouped_with_protagonist := false
	for event in events:
		if event.id < first_action_id:
			continue
		if event.type == "party.member_regrouped" and event.actor_id == entity_id:
			final_projection = event.position
			grouped_with_protagonist = true
			continue
		if grouped_with_protagonist and party_encounter != null \
				and event.type == "action.move" \
				and event.actor_id == party_encounter.protagonist_id:
			var grouped_move := _canonical_move_positions(event)
			if not bool(grouped_move.ok) or grouped_move.from != final_projection:
				return {"ok":false, "position":Vector2i(-1, -1)}
			final_projection = grouped_move.to
			continue
		if event.actor_id != entity_id:
			continue
		if event.type == "action.move":
			var move_positions := _canonical_move_positions(event)
			if not bool(move_positions.ok) or move_positions.from != final_projection:
				return {"ok":false, "position":Vector2i(-1, -1)}
			final_projection = move_positions.to
		elif event.type in ["party.member_deployed", "party.deployment_completed"]:
			final_projection = event.position
			if event.type == "party.member_deployed":
				grouped_with_protagonist = false
	if not entities.has(entity_id) or entities[entity_id].position != final_projection:
		return {"ok":false, "position":Vector2i(-1, -1)}
	return {"ok":true, "position":frozen_position}


func _canonical_life_at_event(entity_id: int, event_boundary_id: int) -> Dictionary:
	if not entities.has(entity_id):
		return {"ok":false}
	var life_state := "ACTIVE"
	var recovery_lock_until := 0
	for event in events:
		if event.id >= event_boundary_id:
			break
		if event.target_id != entity_id:
			continue
		if event.type == "entity.downed":
			if event.data.get("schema_version") != 1 or life_state != "ACTIVE" \
					or not _exact_keys(event.data, ["downed_resolve_at", "life_ruleset_id",
						"previous_life_state", "schema_version", "terminal_immediate"]) \
					or event.data.get("life_ruleset_id") != LIFE_RULESET_ID \
					or event.data.get("previous_life_state") != "ACTIVE" \
					or not Int64CodecScript.is_canonical(event.data.get("downed_resolve_at")) \
					or not event.data.get("terminal_immediate") is bool:
				return {"ok":false}
			life_state = "DOWNED"
			recovery_lock_until = 0
		elif event.type == "entity.recovered":
			if event.data.get("schema_version") != 1 or life_state != "DOWNED" \
					or not _exact_keys(event.data, ["life_ruleset_id", "recovered_health",
						"recovery_lock_until", "schema_version"]) \
					or event.data.get("life_ruleset_id") != LIFE_RULESET_ID \
					or not Int64CodecScript.is_canonical(event.data.get("recovery_lock_until")):
				return {"ok":false}
			life_state = "ACTIVE"
			recovery_lock_until = Int64CodecScript.parse(
				event.data.recovery_lock_until, "historical recovery lock")
		elif event.type == "entity.died":
			if event.data.get("schema_version") == 1:
				if not _exact_keys(event.data, ["damage_type", "life_ruleset_id",
						"previous_life_state", "reason", "schema_version"]) \
						or event.data.get("life_ruleset_id") != LIFE_RULESET_ID \
						or event.data.get("previous_life_state") != life_state:
					return {"ok":false}
			elif not _legacy_death_event_error(event).is_empty():
				return {"ok":false}
			life_state = "DEAD"
			recovery_lock_until = 0
	return {"ok":true, "life_state":life_state,
		"recovery_lock_until":recovery_lock_until}


func _canonical_guard_at_event(entity_id: int, event_boundary_id: int,
		processed_step: int, attack_time: int) -> Dictionary:
	if not entities.has(entity_id):
		return {"ok":false}
	var guarded_until := 0
	var source_event_id := -1
	for event in events:
		if event.id >= event_boundary_id:
			break
		if event.type == "action.hold" and event.actor_id == entity_id:
			if event.step_index == processed_step and event.world_time == attack_time:
				continue
			if event.world_time > MAX_WORLD_TIME - 200:
				return {"ok":false}
			var candidate: int = event.world_time + 200
			if candidate > guarded_until:
				guarded_until = candidate
				source_event_id = event.id
		elif event.type in ["entity.downed", "entity.recovered", "entity.died"] \
				and event.target_id == entity_id:
			guarded_until = 0
			source_event_id = -1
	return {"ok":true, "guarded_until":guarded_until,
		"source_event_id":source_event_id}


func _canonical_move_positions(event) -> Dictionary:
	if not _exact_keys(event.data, ["from_position", "move_time_cost", "terrain_id", "to_position"]) \
			or not _is_position(event.data.get("from_position"), width, height, false) \
			or not _is_position(event.data.get("to_position"), width, height, false) \
			or not event.data.get("move_time_cost") is int \
			or not event.data.get("terrain_id") is String:
		return {"ok":false}
	var from_position := Vector2i(int(event.data.from_position[0]), int(event.data.from_position[1]))
	var to_position := Vector2i(int(event.data.to_position[0]), int(event.data.to_position[1]))
	if event.position != to_position:
		return {"ok":false}
	return {"ok":true, "from":from_position, "to":to_position}


func _hold_event_error(event) -> String:
	if event.actor_id <= 0 or not entities.has(event.actor_id) or event.target_id != -1 \
			or event.position == Vector2i(-1, -1) or not event.data.is_empty():
		return "hold_event_envelope_invalid"
	var position_history: Dictionary = _entity_position_at_event(event.actor_id, event.id)
	if not bool(position_history.ok) or event.position != position_history.position:
		return "hold_event_actor_position_invalid"
	var expected_magnitude: int = 1 if agent_states.has(event.actor_id) else 100
	if event.magnitude != expected_magnitude:
		return "hold_event_magnitude_invalid"
	if event.cause_id != -1:
		var source = event_by_id(event.cause_id)
		if source == null or source.step_index != event.step_index or source.world_time != event.world_time \
				or (agent_states.has(event.actor_id) \
					and (source.type != "ai.decision_selected" or source.actor_id != event.actor_id)) \
				or (not agent_states.has(event.actor_id) and source.type != "encounter.enemy_ambush"):
			return "hold_event_cause_invalid"
	return ""


func _canonical_damage_data_error(event, damage_type: String, expected_requested: int) -> String:
	if not _exact_keys(event.data, ["applied_health_damage", "combat_ruleset_id", "damage_type",
			"requested_damage", "schema_version"]) or event.data.get("schema_version") != 1 \
			or event.data.get("combat_ruleset_id") != COMBAT_RULESET_ID \
			or event.data.get("damage_type") != damage_type \
			or not event.data.get("requested_damage") is int \
			or not event.data.get("applied_health_damage") is int \
			or int(event.data.requested_damage) <= 0 \
			or int(event.data.applied_health_damage) != event.magnitude \
			or (expected_requested > 0 and int(event.data.requested_damage) != expected_requested):
		return "canonical_damage_data_invalid"
	return ""


func _canonical_typed_damage_event_error(event) -> String:
	var damage_type: String = str(event.type).trim_prefix("combat.").trim_suffix("_damage")
	if damage_type not in ["fire", "electric"] or event.actor_id != -1 \
			or event.target_id <= 0 or not entities.has(event.target_id) \
			or event.magnitude <= 0 \
			or not _canonical_damage_data_error(event, damage_type, 0).is_empty():
		return "canonical_typed_damage_envelope_or_data_invalid"
	var requested_damage: int = int(event.data.requested_damage)
	if event.magnitude > requested_damage:
		return "canonical_typed_damage_applied_exceeds_requested"
	return _canonical_environment_damage_source_error(
		event, damage_type, requested_damage, false)


func _legacy_typed_damage_event_error(event, damage_type: String) -> String:
	if damage_type not in ["fire", "electric"] or event.actor_id != -1 \
			or event.target_id <= 0 or not entities.has(event.target_id) \
			or event.magnitude <= 0 or event.data != {"damage_type": damage_type}:
		return "legacy_typed_damage_envelope_or_data_invalid"
	return _canonical_environment_damage_source_error(
		event, damage_type, event.magnitude, true)


func _canonical_environment_damage_source_error(event, damage_type: String,
		requested_damage: int, allow_clamped_pressure: bool) -> String:
	var source = event_by_id(event.cause_id)
	if source == null or source.actor_id != -1 or source.target_id != -1 \
			or source.position != event.position or source.magnitude <= 0 or source.magnitude > 100 \
			or source.instigator_id != event.instigator_id:
		return "canonical_typed_damage_source_envelope_invalid"
	if damage_type == "fire":
		if source.type not in ["environment.ignited", "environment.fire_spread"] \
				or source.step_index > event.step_index or source.world_time > event.world_time \
				or requested_damage > mini(
					EnvironmentRulesScript.FIRE_DAMAGE_CAP_PER_ENVIRONMENT_TICK,
					source.magnitude):
			return "canonical_fire_damage_source_invalid"
		if not source.data.is_empty():
			if not _exact_keys(source.data, ["from_position"]) \
					or not _is_position(source.data.get("from_position"), width, height, true):
				return "canonical_fire_damage_source_data_invalid"
			var from_position := Vector2i(
				int(source.data.from_position[0]), int(source.data.from_position[1]))
			if source.type == "environment.ignited" and from_position != Vector2i(-1, -1):
				return "canonical_fire_damage_source_data_invalid"
			if source.type == "environment.fire_spread" \
					and (from_position == Vector2i(-1, -1) \
					or absi(from_position.x - source.position.x) \
						+ absi(from_position.y - source.position.y) != 1):
				return "canonical_fire_damage_source_data_invalid"
		return ""
	if source.type != "environment.electric_arc" \
			or source.step_index != event.step_index or source.world_time != event.world_time \
			or (requested_damage > source.magnitude if allow_clamped_pressure \
				else requested_damage != source.magnitude) \
			or not _exact_keys(source.data, ["distance", "from_position"]) \
			or not source.data.get("distance") is int or int(source.data.distance) < 0 \
			or not _is_position(source.data.get("from_position"), width, height, true):
		return "canonical_electric_damage_source_invalid"
	var arc_distance: int = int(source.data.distance)
	var arc_from := Vector2i(int(source.data.from_position[0]), int(source.data.from_position[1]))
	if (arc_distance == 0) != (arc_from == Vector2i(-1, -1)) \
			or (arc_distance > 0 and absi(arc_from.x - source.position.x) \
				+ absi(arc_from.y - source.position.y) != 1):
		return "canonical_electric_damage_source_data_invalid"
	return ""


func _legacy_death_event_error(event) -> String:
	if event.actor_id != -1 or event.target_id <= 0 or not entities.has(event.target_id) \
			or event.magnitude != 0 or not _exact_keys(event.data, ["damage_type"]):
		return "legacy_death_event_envelope_invalid"
	var damage_type: String = str(event.data.get("damage_type", ""))
	if damage_type not in ["physical", "fire", "electric"]:
		return "legacy_death_damage_type_invalid"
	var damage_driver = event_by_id(event.cause_id)
	if damage_driver == null or damage_driver.type != "combat.%s_damage" % damage_type \
			or damage_driver.actor_id != -1 or damage_driver.target_id != event.target_id \
			or damage_driver.position != event.position or damage_driver.magnitude <= 0 \
			or damage_driver.step_index != event.step_index \
			or damage_driver.world_time != event.world_time \
			or damage_driver.data != {"damage_type": damage_type}:
		return "legacy_death_damage_driver_invalid"
	return ""


static func _combat_batch_context_valid(context: String, processed_step: int,
		attack_start: int) -> bool:
	var parts: PackedStringArray = context.split("/")
	if parts.size() == 2 and parts[0] == "PARTY_TURN":
		return Int64CodecScript.is_canonical(parts[1]) \
			and Int64CodecScript.parse(parts[1], "party context step") == processed_step
	if parts.size() != 3 or parts[0] not in ["PARTY_ENEMY", "PARTY_AMBUSH", "PHASE3_ACTOR"] \
			or not Int64CodecScript.is_canonical(parts[1]) \
			or not Int64CodecScript.is_canonical(parts[2]):
		return false
	var schedule_id: int = Int64CodecScript.parse(parts[1], "combat context schedule")
	return schedule_id >= (-1 if parts[0] == "PARTY_AMBUSH" else 1) \
		and Int64CodecScript.parse(parts[2], "combat context time") == attack_start


func _status_history_error() -> String:
	var projected: Dictionary = {}
	var last_tick_ids: Dictionary = {}
	var projected_life: Dictionary = {}
	for entity_id in entities: projected_life[entity_id] = "ACTIVE"
	var definition: Dictionary = StatusRegistryScript.definition("BLEEDING")
	var interval: int = int(definition.get("tick_interval", 0))
	var tick_damage: int = int(definition.get("tick_damage", 0))
	var extension: int = interval * (int(definition.get("tick_count_after_apply_or_refresh", 0)) - 1)
	if interval != ACTOR_INTERVAL or tick_damage <= 0 or extension != 200:
		return "status_registry_runtime_mismatch"
	for event_index in range(events.size()):
		var event = events[event_index]
		if event.type == "entity.downed" and event.data.get("schema_version") == 1:
			projected_life[event.target_id] = "DOWNED"
		elif event.type == "entity.recovered" and event.data.get("schema_version") == 1:
			projected_life[event.target_id] = "ACTIVE"
		elif event.type == "entity.died":
			projected_life[event.target_id] = "DEAD"
		if event.type not in ["status.applied", "status.refreshed", "status.tick", "status.expired"]:
			continue
		if event.actor_id != -1 or not entities.has(event.target_id):
			return "status_event_envelope_invalid"
		var owner_id: int = event.target_id
		var status_key := "%d:BLEEDING" % owner_id
		match event.type:
			"status.applied", "status.refreshed":
				if str(projected_life.get(owner_id, "DEAD")) == "DEAD":
					return "status_apply_owner_life_invalid"
				if event.magnitude != 0 or not _exact_keys(event.data, ["expires_at", "next_tick_at",
						"schema_version", "status_id", "status_ruleset_id", "tick_damage"]) \
						or event.data.get("schema_version") != 1 \
						or event.data.get("status_ruleset_id") != STATUS_RULESET_ID \
						or event.data.get("status_id") != "BLEEDING" \
						or event.data.get("tick_damage") != tick_damage \
						or not Int64CodecScript.is_canonical(event.data.get("next_tick_at")) \
						or not Int64CodecScript.is_canonical(event.data.get("expires_at")):
					return "status_apply_or_refresh_data_invalid"
				var damage_source = event_by_id(event.cause_id)
				var damage_driver = event_by_id(damage_source.cause_id) if damage_source != null else null
				if damage_source == null or damage_source.type != "combat.physical_damage" \
						or not _canonical_damage_data_error(damage_source, "physical",
							int(damage_driver.data.get("final_damage", 0)) if damage_driver != null else 0).is_empty() \
						or damage_driver == null or damage_driver.type != "action.melee_attack" \
						or damage_driver.data.get("schema_version") not in [1, 3] \
						or damage_driver.data.get("outcome") != "HIT" \
						or damage_driver.data.get("bleed_proc_succeeded") != true \
						or damage_source.target_id != owner_id or damage_source.position != event.position \
						or damage_source.step_index != event.step_index \
						or damage_source.world_time != event.world_time:
					return "status_apply_or_refresh_cause_invalid"
				if event.world_time > MAX_WORLD_TIME - interval - extension:
					return "status_apply_or_refresh_time_overflow"
				var strict_boundary: int = _strict_next_actor_boundary(event.world_time)
				var expected_next: int = strict_boundary
				var expected_expires: int = strict_boundary + extension
				var applied_at: int = event.world_time
				if event.type == "status.applied":
					if projected.has(status_key): return "duplicate_status_apply"
				else:
					if not projected.has(status_key): return "status_refresh_without_apply"
					var old_row: Dictionary = projected[status_key]
					applied_at = int(old_row.applied_at)
					expected_next = int(old_row.next_tick_at)
					expected_expires = maxi(int(old_row.expires_at), strict_boundary + extension)
				var encoded_next: int = Int64CodecScript.parse(event.data.next_tick_at, "status next tick")
				var encoded_expires: int = Int64CodecScript.parse(event.data.expires_at, "status expiry")
				if encoded_next != expected_next or encoded_expires != expected_expires:
					return "status_apply_or_refresh_cadence_invalid"
				projected[status_key] = {"status_id": "BLEEDING", "applied_at": applied_at,
					"refreshed_at": event.world_time, "next_tick_at": expected_next,
					"expires_at": expected_expires, "source_event_id": event.id}
				last_tick_ids.erase(status_key)
			"status.tick":
				if event.magnitude != tick_damage or not projected.has(status_key) \
						or not _exact_keys(event.data, ["scheduled_tick_at", "schema_version", "status_id",
							"status_ruleset_id", "tick_damage"]) \
						or event.data.get("schema_version") != 1 \
						or event.data.get("status_ruleset_id") != STATUS_RULESET_ID \
						or event.data.get("status_id") != "BLEEDING" \
						or event.data.get("tick_damage") != tick_damage \
						or not Int64CodecScript.is_canonical(event.data.get("scheduled_tick_at")):
					return "status_tick_data_invalid"
				var tick_row: Dictionary = projected[status_key]
				var owner_position: Dictionary = _entity_position_at_event(owner_id, event.id)
				if not bool(owner_position.ok) or event.position != owner_position.position:
					return "status_tick_owner_position_invalid"
				var scheduled_tick: int = Int64CodecScript.parse(event.data.scheduled_tick_at, "scheduled status tick")
				if scheduled_tick != int(tick_row.next_tick_at) or event.world_time != scheduled_tick \
						or scheduled_tick > int(tick_row.expires_at) \
						or event.cause_id != int(tick_row.source_event_id):
					return "status_tick_cadence_or_source_invalid"
				if event_index + 1 >= events.size(): return "status_tick_damage_child_missing"
				var tick_child = events[event_index + 1]
				var owner_life: String = str(projected_life.get(owner_id, "DEAD"))
				var expected_child_type := "combat.physical_damage" if owner_life == "ACTIVE" \
					else ("combat.downed_damage" if owner_life == "DOWNED" else "")
				if expected_child_type.is_empty() or tick_child.type != expected_child_type:
					return "status_tick_life_child_invalid"
				if tick_child.cause_id != event.id or tick_child.target_id != owner_id \
						or tick_child.position != event.position or tick_child.step_index != event.step_index \
						or tick_child.world_time != event.world_time:
					return "status_tick_damage_child_invalid"
				if tick_child.type == "combat.physical_damage" \
						and not _canonical_damage_data_error(tick_child, "physical", tick_damage).is_empty():
					return "status_tick_damage_child_invalid"
				if tick_child.type == "combat.downed_damage" \
						and (tick_child.actor_id != -1 or tick_child.magnitude != tick_damage \
						or not _exact_keys(tick_child.data, ["applied_health_damage", "combat_ruleset_id",
							"damage_type", "reason", "requested_damage", "schema_version"]) \
						or tick_child.data.get("schema_version") != 1 \
						or tick_child.data.get("combat_ruleset_id") != COMBAT_RULESET_ID \
						or tick_child.data.get("damage_type") != "physical" \
						or tick_child.data.get("requested_damage") != tick_damage \
						or tick_child.data.get("applied_health_damage") != 0 \
						or tick_child.data.get("reason") != "BLEEDOUT"):
					return "status_tick_downed_damage_child_invalid"
				if int(tick_row.next_tick_at) > MAX_WORLD_TIME - interval:
					return "status_tick_time_overflow"
				tick_row.next_tick_at = int(tick_row.next_tick_at) + interval
				projected[status_key] = tick_row
				last_tick_ids[status_key] = event.id
			"status.expired":
				if event.magnitude != 0 or not projected.has(status_key) \
						or not _exact_keys(event.data, ["reason", "schema_version", "status_id", "status_ruleset_id"]) \
						or event.data.get("schema_version") != 1 \
						or event.data.get("status_ruleset_id") != STATUS_RULESET_ID \
						or event.data.get("status_id") != "BLEEDING" \
						or event.data.get("reason") not in ["NATURAL", "OWNER_DIED"]:
					return "status_expire_data_invalid"
				var expiring_row: Dictionary = projected[status_key]
				if event.data.reason == "NATURAL":
					if not last_tick_ids.has(status_key) or event.cause_id != int(last_tick_ids[status_key]) \
							or event.world_time != int(expiring_row.expires_at) \
							or int(expiring_row.next_tick_at) <= int(expiring_row.expires_at):
						return "natural_status_expire_cause_invalid"
					var natural_tick = event_by_id(event.cause_id)
					if natural_tick == null or natural_tick.step_index != event.step_index \
							or natural_tick.world_time != event.world_time or natural_tick.position != event.position:
						return "natural_status_expire_envelope_invalid"
				else:
					var death_driver = event_by_id(event.cause_id)
					if death_driver == null or death_driver.type not in ["combat.downed_damage", "entity.downed"] \
							or death_driver.target_id != owner_id or death_driver.position != event.position \
							or death_driver.step_index != event.step_index \
							or death_driver.world_time != event.world_time:
						return "owner_death_status_expire_cause_invalid"
					if death_driver.type == "entity.downed" \
							and (party_encounter == null \
							or party_encounter.protagonist_id != owner_id \
							or death_driver.actor_id != -1 or death_driver.magnitude != 0 \
							or not _exact_keys(death_driver.data, ["downed_resolve_at", "life_ruleset_id",
								"previous_life_state", "schema_version", "terminal_immediate"]) \
							or death_driver.data.get("schema_version") != 1 \
							or death_driver.data.get("life_ruleset_id") != LIFE_RULESET_ID \
							or death_driver.data.get("previous_life_state") != "ACTIVE" \
							or not Int64CodecScript.is_canonical(
								death_driver.data.get("downed_resolve_at")) \
							or Int64CodecScript.parse(death_driver.data.downed_resolve_at,
								"terminal downed resolve") != -1 \
							or death_driver.data.get("terminal_immediate") != true):
						return "owner_death_status_expire_downed_driver_invalid"
				projected.erase(status_key)
				last_tick_ids.erase(status_key)
	for entity_id in entities:
		var final_key := "%d:BLEEDING" % int(entity_id)
		var actual_rows: Array = combatant_states[entity_id].status_rows
		var party_member = party_member_state(int(entity_id))
		if party_member != null and party_member.presence in ["RECRUITABLE", "EXILED"]:
			if not actual_rows.is_empty(): return "inactive_party_status_row_present"
			continue
		if projected.has(final_key):
			if actual_rows.size() != 1: return "status_projection_row_missing"
			var expected_row: Dictionary = projected[final_key]
			var actual = actual_rows[0]
			if actual.status_id != expected_row.status_id \
					or actual.applied_at != int(expected_row.applied_at) \
					or actual.refreshed_at != int(expected_row.refreshed_at) \
					or actual.next_tick_at != int(expected_row.next_tick_at) \
					or actual.expires_at != int(expected_row.expires_at) \
					or actual.source_event_id != int(expected_row.source_event_id):
				return "status_projection_row_mismatch"
		elif not actual_rows.is_empty():
			return "status_row_without_event_history"
	return ""


# Checkpoint-A accepts canonical lifecycle history before the runtime transition
# machinery lands. Start with the fresh FINISHER chain and validate every link
# without relying on encounter mode or the final row as provenance.
func _lifecycle_history_error() -> String:
	var projected_life: Dictionary = {}
	var projected_downed: Dictionary = {}
	var projected_recovery: Dictionary = {}
	var lifecycle_touched: Dictionary = {}
	var active_bleed_owners: Dictionary = {}
	var consumed_canonical_lifecycle_ids: Dictionary = {}
	for entity_id in entities:
		projected_life[entity_id] = "ACTIVE"
	for event_index in range(events.size()):
		var event = events[event_index]
		if event.type in ["status.applied", "status.refreshed"]:
			active_bleed_owners[event.target_id] = true
			continue
		if event.type == "status.expired":
			active_bleed_owners.erase(event.target_id)
			continue
		if event.type == "entity.died" and event.data.get("schema_version") != 1:
			var terminal_error := _legacy_death_event_error(event)
			if not terminal_error.is_empty(): return terminal_error
			if projected_life[event.target_id] != "ACTIVE":
				return "legacy_death_life_projection_invalid"
			projected_life[event.target_id] = "DEAD"
			projected_downed.erase(event.target_id)
			projected_recovery.erase(event.target_id)
			lifecycle_touched[event.target_id] = true
			continue
		if event.type == "entity.downed" and event.data.get("schema_version") == 1:
			if event.actor_id != -1 or event.target_id <= 0 or not entities.has(event.target_id) \
					or event.magnitude != 0 \
					or projected_life[event.target_id] != "ACTIVE" \
					or not _exact_keys(event.data, ["downed_resolve_at", "life_ruleset_id",
						"previous_life_state", "schema_version", "terminal_immediate"]) \
					or event.data.get("life_ruleset_id") != LIFE_RULESET_ID \
					or event.data.get("previous_life_state") != "ACTIVE" \
					or not Int64CodecScript.is_canonical(event.data.get("downed_resolve_at")) \
					or not event.data.get("terminal_immediate") is bool:
				return "canonical_downed_event_invalid"
			var damage_driver = event_by_id(event.cause_id)
			if damage_driver == null or damage_driver.type not in ["combat.physical_damage",
					"combat.fire_damage", "combat.electric_damage"] \
					or damage_driver.data.get("schema_version") not in [1, 3] \
					or damage_driver.target_id != event.target_id \
					or damage_driver.position != event.position \
					or damage_driver.step_index != event.step_index \
					or damage_driver.world_time != event.world_time or damage_driver.magnitude <= 0:
				return "canonical_downed_damage_driver_invalid"
			var protagonist: bool = party_encounter != null \
					and party_encounter.protagonist_id == event.target_id
			var encoded_deadline: int = Int64CodecScript.parse(
				event.data.downed_resolve_at, "downed resolve time")
			if protagonist:
				if encoded_deadline != -1 or event.data.terminal_immediate != true:
					return "canonical_downed_terminal_mismatch"
				var party_death_index: int = event_index + 1
				if active_bleed_owners.has(event.target_id):
					if party_death_index >= events.size():
						return "canonical_party_defeat_expiry_missing"
					var party_owner_expiry = events[party_death_index]
					if party_owner_expiry.type != "status.expired" \
							or party_owner_expiry.actor_id != -1 \
							or party_owner_expiry.target_id != event.target_id \
							or party_owner_expiry.position != event.position \
							or party_owner_expiry.magnitude != 0 \
							or party_owner_expiry.cause_id != event.id \
							or party_owner_expiry.instigator_id != event.instigator_id \
							or party_owner_expiry.step_index != event.step_index \
							or party_owner_expiry.world_time != event.world_time \
							or not _exact_keys(party_owner_expiry.data, ["reason", "schema_version",
								"status_id", "status_ruleset_id"]) \
							or party_owner_expiry.data.get("schema_version") != 1 \
							or party_owner_expiry.data.get("status_ruleset_id") != STATUS_RULESET_ID \
							or party_owner_expiry.data.get("status_id") != "BLEEDING" \
							or party_owner_expiry.data.get("reason") != "OWNER_DIED":
						return "canonical_party_defeat_expiry_invalid"
					party_death_index += 1
				if party_death_index >= events.size():
					return "canonical_party_defeat_death_missing"
				var party_death = events[party_death_index]
				var party_damage_type: String = str(damage_driver.data.get("damage_type", ""))
				if party_damage_type not in ["physical", "fire", "electric"] \
						or party_death.type != "entity.died" or party_death.actor_id != -1 \
						or party_death.target_id != event.target_id \
						or party_death.position != event.position or party_death.magnitude != 0 \
						or party_death.cause_id != event.id \
						or party_death.instigator_id != event.instigator_id \
						or party_death.step_index != event.step_index \
						or party_death.world_time != event.world_time \
						or not _exact_keys(party_death.data, ["damage_type", "life_ruleset_id",
							"previous_life_state", "reason", "schema_version"]) \
						or party_death.data.get("schema_version") != 1 \
						or party_death.data.get("life_ruleset_id") != LIFE_RULESET_ID \
						or party_death.data.get("previous_life_state") != "DOWNED" \
						or party_death.data.get("reason") != "PARTY_DEFEAT" \
						or party_death.data.get("damage_type") != party_damage_type:
					return "canonical_party_defeat_death_invalid"
				var party_final_state = combatant_states[event.target_id]
				if party_final_state.life_state != "DEAD" or entities[event.target_id].health != 0:
					return "canonical_party_defeat_projection_mismatch"
				consumed_canonical_lifecycle_ids[event.id] = true
				if consumed_canonical_lifecycle_ids.has(party_death.id):
					return "canonical_lifecycle_event_consumed_twice"
				consumed_canonical_lifecycle_ids[party_death.id] = true
				projected_life[event.target_id] = "DEAD"
				projected_downed.erase(event.target_id)
				projected_recovery.erase(event.target_id)
				lifecycle_touched[event.target_id] = true
				continue
			else:
				if event.world_time > MAX_WORLD_TIME - 200 \
						or encoded_deadline != _strict_next_actor_boundary(event.world_time) + 100 \
						or event.data.terminal_immediate != false:
					return "canonical_downed_deadline_mismatch"
			consumed_canonical_lifecycle_ids[event.id] = true
			projected_life[event.target_id] = "DOWNED"
			projected_downed[event.target_id] = {"event_id": event.id,
				"downed_at": event.world_time, "resolve_at": encoded_deadline}
			projected_recovery.erase(event.target_id)
			lifecycle_touched[event.target_id] = true
			continue
		if event.type == "entity.recovered" and event.data.get("schema_version") == 1:
			if event.actor_id != -1 or event.target_id <= 0 or not entities.has(event.target_id) \
					or projected_life[event.target_id] != "DOWNED" \
					or not projected_downed.has(event.target_id) \
					or active_bleed_owners.has(event.target_id) \
					or not _exact_keys(event.data, ["life_ruleset_id", "recovered_health",
						"recovery_lock_until", "schema_version"]) \
					or event.data.get("life_ruleset_id") != LIFE_RULESET_ID \
					or not event.data.get("recovered_health") is int \
					or not Int64CodecScript.is_canonical(event.data.get("recovery_lock_until")):
				return "canonical_recovery_event_invalid"
			var downed_projection: Dictionary = projected_downed[event.target_id]
			var downed_source = event_by_id(int(downed_projection.event_id))
			var expected_health: int = maxi(1, int((entities[event.target_id].max_health + 9) / 10))
			var encoded_lock: int = Int64CodecScript.parse(
				event.data.recovery_lock_until, "recovery lock time")
			var position_history: Dictionary = _entity_position_at_event(event.target_id, event.id)
			if downed_source == null or event.cause_id != downed_source.id \
					or event.world_time != int(downed_projection.resolve_at) \
					or event.step_index < downed_source.step_index \
					or event.world_time <= downed_source.world_time \
					or not bool(position_history.ok) or event.position != position_history.position \
					or event.magnitude != expected_health \
					or event.data.recovered_health != expected_health \
					or event.world_time > MAX_WORLD_TIME - 100 \
					or encoded_lock != event.world_time + 100:
				return "canonical_recovery_projection_invalid"
			consumed_canonical_lifecycle_ids[event.id] = true
			projected_life[event.target_id] = "ACTIVE"
			projected_downed.erase(event.target_id)
			projected_recovery[event.target_id] = {"event_id": event.id,
				"health": expected_health, "lock_until": encoded_lock}
			lifecycle_touched[event.target_id] = true
			continue
		if event.type == "health.restored" and event.data.get("schema_version") == 1 \
				and projected_recovery.has(event.target_id) \
				and projected_life.get(event.target_id) == "ACTIVE":
			# Post-recovery healing (potion, town care, safe-exploration pulse) is a
			# canonical ledger leaf: the projected HP rises by exactly the magnitude
			# and the leaf must disclose the resulting HP so replay stays exact.
			var restored_health: Dictionary = projected_recovery[event.target_id]
			var restored_after: int = int(restored_health.health) + event.magnitude
			if event.actor_id != event.target_id or event.magnitude <= 0 \
					or restored_after > int(entities[event.target_id].max_health) \
					or not event.data.get("health_after") is int \
					or int(event.data.get("health_after")) != restored_after:
				return "post_recovery_restoration_projection_invalid"
			restored_health.health = restored_after
			projected_recovery[event.target_id] = restored_health
			continue
		if event.type in ["combat.physical_damage", "combat.fire_damage",
				"combat.electric_damage"] and projected_recovery.has(event.target_id) \
				and projected_life.get(event.target_id) == "ACTIVE":
			var projected_damage_type: String = str(event.type).trim_prefix("combat.").trim_suffix("_damage")
			var canonical_damage: bool = event.data.get("schema_version") == 1
			var valid_damage_data: bool = _canonical_damage_data_error(
				event, projected_damage_type, 0).is_empty() if canonical_damage \
				else event.data == {"damage_type": projected_damage_type}
			var recovery_health: Dictionary = projected_recovery[event.target_id]
			if event.actor_id != -1 or event.magnitude <= 0 or not valid_damage_data \
					or event.magnitude > int(recovery_health.health):
				return "post_recovery_damage_projection_invalid"
			recovery_health.health = int(recovery_health.health) - event.magnitude
			projected_recovery[event.target_id] = recovery_health
		if event.type != "combat.downed_damage" or event.data.get("schema_version") != 1:
			continue
		if event.data.get("reason") == "BLEEDOUT":
			if event.actor_id != -1 or event.target_id <= 0 or not entities.has(event.target_id) \
					or event.magnitude <= 0 or projected_life[event.target_id] != "DOWNED" \
					or not _exact_keys(event.data, ["applied_health_damage", "combat_ruleset_id",
						"damage_type", "reason", "requested_damage", "schema_version"]) \
					or event.data.get("combat_ruleset_id") != COMBAT_RULESET_ID \
					or event.data.get("damage_type") != "physical" \
					or event.data.get("requested_damage") != event.magnitude \
					or event.data.get("applied_health_damage") != 0:
				return "canonical_bleedout_damage_invalid"
			var bleed_tick = event_by_id(event.cause_id)
			if bleed_tick == null or bleed_tick.type != "status.tick" \
					or bleed_tick.actor_id != -1 or bleed_tick.target_id != event.target_id \
					or bleed_tick.position != event.position or bleed_tick.magnitude != event.magnitude \
					or bleed_tick.step_index != event.step_index \
					or bleed_tick.world_time != event.world_time \
					or bleed_tick.instigator_id != event.instigator_id \
					or not _exact_keys(bleed_tick.data, ["scheduled_tick_at", "schema_version",
						"status_id", "status_ruleset_id", "tick_damage"]) \
					or bleed_tick.data.get("schema_version") != 1 \
					or bleed_tick.data.get("status_ruleset_id") != STATUS_RULESET_ID \
					or bleed_tick.data.get("status_id") != "BLEEDING" \
					or bleed_tick.data.get("tick_damage") != event.magnitude \
					or not Int64CodecScript.is_canonical(bleed_tick.data.get("scheduled_tick_at")) \
					or Int64CodecScript.parse(bleed_tick.data.scheduled_tick_at,
						"bleedout scheduled tick") != event.world_time:
				return "canonical_bleedout_source_invalid"
			var expiry_index: int = event_index + 1
			if expiry_index >= events.size(): return "canonical_bleedout_expiry_missing"
			var owner_expiry = events[expiry_index]
			if owner_expiry.type != "status.expired" or owner_expiry.actor_id != -1 \
					or owner_expiry.target_id != event.target_id \
					or owner_expiry.position != event.position or owner_expiry.magnitude != 0 \
					or owner_expiry.cause_id != event.id or owner_expiry.instigator_id != event.instigator_id \
					or owner_expiry.step_index != event.step_index \
					or owner_expiry.world_time != event.world_time \
					or not _exact_keys(owner_expiry.data, ["reason", "schema_version", "status_id",
						"status_ruleset_id"]) or owner_expiry.data.get("schema_version") != 1 \
					or owner_expiry.data.get("status_ruleset_id") != STATUS_RULESET_ID \
					or owner_expiry.data.get("status_id") != "BLEEDING" \
					or owner_expiry.data.get("reason") != "OWNER_DIED":
				return "canonical_bleedout_expiry_invalid"
			var bleedout_death_index: int = expiry_index + 1
			if bleedout_death_index >= events.size(): return "canonical_bleedout_death_missing"
			var bleedout_death = events[bleedout_death_index]
			if bleedout_death.type != "entity.died" or bleedout_death.actor_id != -1 \
					or bleedout_death.target_id != event.target_id \
					or bleedout_death.position != event.position or bleedout_death.magnitude != 0 \
					or bleedout_death.cause_id != event.id \
					or bleedout_death.instigator_id != event.instigator_id \
					or bleedout_death.step_index != event.step_index \
					or bleedout_death.world_time != event.world_time \
					or not _exact_keys(bleedout_death.data, ["damage_type", "life_ruleset_id",
						"previous_life_state", "reason", "schema_version"]) \
					or bleedout_death.data.get("schema_version") != 1 \
					or bleedout_death.data.get("life_ruleset_id") != LIFE_RULESET_ID \
					or bleedout_death.data.get("previous_life_state") != "DOWNED" \
					or bleedout_death.data.get("reason") != "BLEEDOUT" \
					or bleedout_death.data.get("damage_type") != "physical":
				return "canonical_bleedout_death_invalid"
			var bleedout_final_state = combatant_states[event.target_id]
			if bleedout_final_state.life_state != "DEAD" or entities[event.target_id].health != 0:
				return "canonical_bleedout_projection_mismatch"
			consumed_canonical_lifecycle_ids[event.id] = true
			if consumed_canonical_lifecycle_ids.has(bleedout_death.id):
				return "canonical_lifecycle_event_consumed_twice"
			consumed_canonical_lifecycle_ids[bleedout_death.id] = true
			projected_life[event.target_id] = "DEAD"
			projected_downed.erase(event.target_id)
			projected_recovery.erase(event.target_id)
			lifecycle_touched[event.target_id] = true
			continue
		if event.data.get("reason") == "HAZARD":
			var hazard_damage_type: String = str(event.data.get("damage_type", ""))
			if event.actor_id != -1 or event.target_id <= 0 or not entities.has(event.target_id) \
					or event.magnitude <= 0 or projected_life[event.target_id] != "DOWNED" \
					or hazard_damage_type not in ["fire", "electric"] \
					or not _exact_keys(event.data, ["applied_health_damage", "combat_ruleset_id",
						"damage_type", "reason", "requested_damage", "schema_version"]) \
					or event.data.get("combat_ruleset_id") != COMBAT_RULESET_ID \
					or event.data.get("requested_damage") != event.magnitude \
					or event.data.get("applied_health_damage") != 0:
				return "canonical_hazard_damage_invalid"
			var hazard_source_error := _canonical_environment_damage_source_error(
				event, hazard_damage_type, event.magnitude, false)
			if not hazard_source_error.is_empty(): return "canonical_hazard_source_invalid"
			var hazard_death_index: int = event_index + 1
			if hazard_death_index >= events.size(): return "canonical_hazard_death_missing"
			var hazard_death = events[hazard_death_index]
			if hazard_death.type != "entity.died" or hazard_death.actor_id != -1 \
					or hazard_death.target_id != event.target_id \
					or hazard_death.position != event.position or hazard_death.magnitude != 0 \
					or hazard_death.cause_id != event.id \
					or hazard_death.instigator_id != event.instigator_id \
					or hazard_death.step_index != event.step_index \
					or hazard_death.world_time != event.world_time \
					or not _exact_keys(hazard_death.data, ["damage_type", "life_ruleset_id",
						"previous_life_state", "reason", "schema_version"]) \
					or hazard_death.data.get("schema_version") != 1 \
					or hazard_death.data.get("life_ruleset_id") != LIFE_RULESET_ID \
					or hazard_death.data.get("previous_life_state") != "DOWNED" \
					or hazard_death.data.get("reason") != "HAZARD" \
					or hazard_death.data.get("damage_type") != hazard_damage_type:
				return "canonical_hazard_death_invalid"
			var hazard_final_state = combatant_states[event.target_id]
			if hazard_final_state.life_state != "DEAD" or entities[event.target_id].health != 0:
				return "canonical_hazard_projection_mismatch"
			consumed_canonical_lifecycle_ids[event.id] = true
			if consumed_canonical_lifecycle_ids.has(hazard_death.id):
				return "canonical_lifecycle_event_consumed_twice"
			consumed_canonical_lifecycle_ids[hazard_death.id] = true
			projected_life[event.target_id] = "DEAD"
			projected_downed.erase(event.target_id)
			projected_recovery.erase(event.target_id)
			lifecycle_touched[event.target_id] = true
			continue
		if event.actor_id != -1 or event.target_id <= 0 or not entities.has(event.target_id) \
				or event.magnitude <= 0 \
				or projected_life[event.target_id] != "DOWNED" \
				or not _exact_keys(event.data, ["applied_health_damage", "combat_ruleset_id",
					"damage_type", "reason", "requested_damage", "schema_version"]) \
				or event.data.get("combat_ruleset_id") != COMBAT_RULESET_ID \
				or event.data.get("damage_type") != "physical" \
				or event.data.get("reason") != "FINISHER" \
				or event.data.get("requested_damage") != event.magnitude \
				or event.data.get("applied_health_damage") != 0:
			return "canonical_finisher_damage_invalid"
		var action = event_by_id(event.cause_id)
		if action == null or action.type != "action.melee_attack" \
				or action.data.get("schema_version") != 1 \
				or action.data.get("intent_mode") != "FINISHER" \
				or action.data.get("outcome") != "FINISHER" \
				or action.data.get("target_life_at_batch_start") != "DOWNED" \
				or action.target_id != event.target_id or action.position != event.position \
				or action.step_index != event.step_index or action.world_time != event.world_time \
				or event.magnitude != int(action.data.get("base_damage", 0)) \
					- int(action.data.get("armor_reduction", 0)):
			return "canonical_finisher_source_invalid"
		var death_index := event_index + 1
		while death_index < events.size() and events[death_index].type == "status.expired" \
				and events[death_index].cause_id == event.id:
			death_index += 1
		if death_index >= events.size(): return "canonical_finisher_death_missing"
		var death = events[death_index]
		if death.type != "entity.died" or death.actor_id != -1 \
				or death.target_id != event.target_id or death.position != event.position \
				or death.magnitude != 0 or death.cause_id != event.id \
				or death.step_index != event.step_index or death.world_time != event.world_time \
				or not _exact_keys(death.data, ["damage_type", "life_ruleset_id",
					"previous_life_state", "reason", "schema_version"]) \
				or death.data.get("schema_version") != 1 \
				or death.data.get("life_ruleset_id") != LIFE_RULESET_ID \
				or death.data.get("previous_life_state") != "DOWNED" \
				or death.data.get("reason") != "FINISHER" \
				or death.data.get("damage_type") != "physical":
			return "canonical_finisher_death_invalid"
		var final_state = combatant_states[event.target_id]
		if final_state.life_state != "DEAD" or entities[event.target_id].health != 0:
			return "canonical_finisher_projection_mismatch"
		consumed_canonical_lifecycle_ids[event.id] = true
		if consumed_canonical_lifecycle_ids.has(death.id):
			return "canonical_lifecycle_event_consumed_twice"
		consumed_canonical_lifecycle_ids[death.id] = true
		projected_life[event.target_id] = "DEAD"
		projected_downed.erase(event.target_id)
		projected_recovery.erase(event.target_id)
		lifecycle_touched[event.target_id] = true
	for action in events:
		if action.type != "action.melee_attack" \
				or action.data.get("schema_version") != 1 \
				or action.data.get("outcome") != "FINISHER":
			continue
		var result_children: Array = []
		for candidate in events:
			if candidate.cause_id == action.id and candidate.type in [
					"combat.attack_missed", "combat.physical_damage", "combat.downed_damage"]:
				result_children.append(candidate)
		if result_children.size() != 1:
			return "canonical_finisher_result_cardinality_invalid"
		var pressure = result_children[0]
		if pressure.type != "combat.downed_damage" \
				or pressure.data.get("schema_version") != 1 \
				or pressure.data.get("reason") != "FINISHER" \
				or not consumed_canonical_lifecycle_ids.has(pressure.id):
			return "canonical_finisher_result_child_invalid"
	var reserved_lifecycle_types := ["entity.downed", "entity.recovered", "entity.died",
		"combat.downed_damage"]
	for reserved_event in events:
		if reserved_event.type not in reserved_lifecycle_types:
			continue
		if reserved_event.data.get("schema_version") == 1:
			if not consumed_canonical_lifecycle_ids.has(reserved_event.id):
				return "canonical_lifecycle_event_unconsumed"
		elif reserved_event.type != "entity.died":
			return "reserved_lifecycle_schema_invalid"
	var pristine_bootstrap: bool = step_index == 0 and world_time == 0 \
			and events.is_empty() and encounter_lab == null and party_encounter == null
	for entity_id in combatant_states:
		if combatant_states[entity_id].life_state == "DEAD" \
				and not lifecycle_touched.has(entity_id) and not pristine_bootstrap:
			return "dead_without_pristine_bootstrap"
	for entity_id in lifecycle_touched:
		var final_state = combatant_states[entity_id]
		match str(projected_life[entity_id]):
			"DOWNED":
				var expected_downed: Dictionary = projected_downed[entity_id]
				if final_state.life_state != "DOWNED" or entities[entity_id].health != 0 \
						or final_state.downed_at != int(expected_downed.downed_at) \
						or final_state.downed_resolve_at != int(expected_downed.resolve_at) \
						or final_state.downed_source_event_id != int(expected_downed.event_id):
					return "canonical_downed_projection_mismatch"
			"ACTIVE":
				if not projected_recovery.has(entity_id):
					return "canonical_lifecycle_projection_mismatch"
				var expected_recovery: Dictionary = projected_recovery[entity_id]
				if final_state.life_state != "ACTIVE" \
						or entities[entity_id].health != int(expected_recovery.health) \
						or final_state.downed_at != -1 or final_state.downed_resolve_at != -1 \
						or final_state.downed_source_event_id != -1 \
						or final_state.recovery_lock_until != int(expected_recovery.lock_until) \
						or final_state.recovery_source_event_id != int(expected_recovery.event_id):
					return "canonical_recovery_final_state_mismatch"
			"DEAD":
				if final_state.life_state != "DEAD" or entities[entity_id].health != 0:
					return "canonical_death_projection_mismatch"
	return ""


func _guard_history_error() -> String:
	var projected: Dictionary = {}
	for entity_id in entities:
		projected[entity_id] = {"guarded_until": 0, "source_event_id": -1}
	for event in events:
		if event.type == "action.hold":
			if event.world_time > MAX_WORLD_TIME - 200:
				return "guard_projection_time_overflow"
			var candidate: int = event.world_time + 200
			var row: Dictionary = projected[event.actor_id]
			if candidate > int(row.guarded_until):
				row.guarded_until = candidate
				row.source_event_id = event.id
				projected[event.actor_id] = row
		elif event.type in ["entity.downed", "entity.recovered", "entity.died"] \
				and event.target_id > 0 and projected.has(event.target_id):
			projected[event.target_id] = {"guarded_until": 0, "source_event_id": -1}
	for entity_id in entities:
		var combatant = combatant_states[entity_id]
		if combatant.life_state != "ACTIVE":
			continue
		var expected: Dictionary = projected[entity_id]
		if combatant.guarded_until != int(expected.guarded_until) \
				or combatant.guard_source_event_id != int(expected.source_event_id):
			return "guard_projection_mismatch"
	return ""


static func _strict_next_actor_boundary(value: int) -> int:
	return (value / ACTOR_INTERVAL + 1) * ACTOR_INTERVAL


static func _exact_keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary: return false
	var actual_keys: Array = value.keys(); actual_keys.sort()
	var expected_keys: Array = expected.duplicate(); expected_keys.sort()
	return actual_keys == expected_keys


func _party_runtime_error() -> String:
	# The camera remains a 15x15 window, but product party worlds may be larger.
	# Retain the legacy minimum so old fixture assumptions are never squeezed.
	if width < 15 or height < 15: return "party_fixture_dimensions_invalid"
	var encounter_wire_error:=PartyEncounterStateScript.wire_error(party_encounter.to_dict(),width,height)
	if not encounter_wire_error.is_empty():return encounter_wire_error
	for ground_row in item_state.ground_items.rows:
		var ground_terrain:Dictionary=TerrainRegistryScript.definition(
			str(tile_at(ground_row.position).terrain))
		if ground_terrain.is_empty() or not bool(ground_terrain.get("passable",false)):
			return "ground_item_on_impassable_tile"
	for gateway_position in party_encounter.diagonal_gateway_positions:
		if not is_diagonal_gateway(gateway_position):return "party_diagonal_gateway_not_passable"
	if party_encounter.safe_phase not in PartyEncounterStateScript.PHASES: return "unknown_party_phase"
	if party_encounter.protagonist_id <= 0 or not entities.has(party_encounter.protagonist_id): return "party_protagonist_missing"
	if party_encounter.party_member_ids.size() < 1 or party_encounter.party_member_ids.size() > 64 \
			or party_encounter.active_party_member_ids.is_empty() \
			or party_encounter.active_party_member_ids.size() \
				> PartyEncounterStateScript.MAX_ACTIVE_PARTY_SIZE:
		return "party_roster_size_invalid"
	if party_encounter.enemy_ids.is_empty() or party_encounter.enemy_ids.size() > 64: return "party_enemy_size_invalid"
	var previous_id := 0
	var deployed := 0
	var slots: Array[int] = []
	var deployed_cells: Dictionary = {}
	var party_ids: Dictionary = {}
	var active_ids: Dictionary = {}
	for member_id_value in party_encounter.active_party_member_ids: active_ids[int(member_id_value)] = true
	if active_ids.size() != party_encounter.active_party_member_ids.size(): return "active_party_member_reference_invalid"
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
		if not active_ids.has(member_id) and (member.role != "COMPANION" \
				or member.presence not in ["RECRUITABLE", "EXILED"] \
				or combatant_states[member_id].life_state != "ACTIVE" \
				or not combatant_states[member_id].status_rows.is_empty()):
			return "party_inactive_member_state_invalid"
		slots.append(member.roster_slot)
		if member.presence == "DEPLOYED":
			deployed += 1
			if combatant_states[member_id].life_state == "DEAD" or not _terrain_is_passable(entities[member_id].position):
				return "deployed_party_position_invalid"
			var deployed_key := "%d:%d" % [entities[member_id].position.x, entities[member_id].position.y]
			if deployed_cells.has(deployed_key): return "duplicate_deployed_party_position"
			deployed_cells[deployed_key] = member_id
		if (combatant_states[member_id].life_state == "DEAD") != (member.presence == "DEFEATED"): return "party_life_presence_mismatch"
		if member.presence == "GROUPED" and entities[member_id].position != party_encounter.group_anchor: return "grouped_position_mismatch"
	slots.sort()
	for slot in range(slots.size()):
		if slots[slot] != slot: return "party_roster_slots_not_continuous"
	if party_encounter.party_member_ids[0] != party_encounter.protagonist_id or party_encounter.member_rows[party_encounter.protagonist_id].roster_slot != 0:
		return "party_protagonist_roster_invalid"
	if party_encounter.active_party_member_ids[0] != party_encounter.protagonist_id:
		return "party_protagonist_roster_invalid"
	for member_id in party_encounter.party_member_ids:
		var expected_role := "PROTAGONIST" if member_id == party_encounter.protagonist_id else "COMPANION"
		if party_encounter.member_rows[member_id].role != expected_role: return "party_role_invalid"
	if deployed > PartyEncounterStateScript.MAX_ACTIVE_PARTY_SIZE:
		return "too_many_deployed_party"
	var alive_enemies := 0; previous_id = 0
	for enemy_id in party_encounter.enemy_ids:
		if enemy_id <= previous_id or party_ids.has(enemy_id) or not entities.has(enemy_id) \
				or not party_encounter.enemy_busy_rows.has(enemy_id) \
				or not party_encounter.enemy_awareness_rows.has(enemy_id):
			return "party_enemy_reference_invalid"
		previous_id = enemy_id
		var enemy_busy: int = party_encounter.enemy_busy_rows[enemy_id]
		if enemy_busy < 0 or enemy_busy > MAX_WORLD_TIME: return "party_enemy_busy_invalid"
		var awareness=party_encounter.enemy_awareness_rows[enemy_id]
		if awareness.enemy_id!=enemy_id or not _terrain_is_passable(awareness.home_position):
			return "party_enemy_awareness_invalid"
		if combatant_states[enemy_id].life_state != "DEAD": alive_enemies += 1
	if party_encounter.enemy_busy_rows.size() != party_encounter.enemy_ids.size(): return "party_enemy_busy_set_mismatch"
	if party_encounter.enemy_awareness_rows.size()!=party_encounter.enemy_ids.size():
		return "party_enemy_awareness_set_mismatch"
	if not in_bounds(party_encounter.group_anchor) or party_encounter.facing not in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		return "party_anchor_or_facing_invalid"
	var hero = entities[party_encounter.protagonist_id]
	var hero_member = party_encounter.member_rows[party_encounter.protagonist_id]
	var growth_error:=_party_growth_build_error(hero)
	if not growth_error.is_empty():return growth_error
	if party_encounter.safe_phase in ["GROUPED", "GROUPED_COMPLETE", "CONTACT"] \
			and hero.position != party_encounter.group_anchor:
		return "party_protagonist_anchor_mismatch"
	if (party_encounter.contact_kind == "NONE") != (party_encounter.contact_enemy_id == -1): return "party_contact_identity_invalid"
	if party_encounter.contact_enemy_id != -1 and party_encounter.contact_enemy_id not in party_encounter.enemy_ids:
		return "party_contact_enemy_invalid"
	match party_encounter.safe_phase:
		"GROUPED":
			if combatant_states[hero.id].life_state != "ACTIVE" or hero_member.presence != "DEPLOYED" or deployed != 1 or alive_enemies == 0 \
					or party_encounter.contact_kind != "NONE" or party_encounter.formation_id != "NONE":
				return "grouped_phase_invalid"
			for member_id in party_encounter.active_party_member_ids:
				if member_id != hero.id and combatant_states[member_id].life_state != "DEAD" \
						and party_encounter.member_rows[member_id].presence != "GROUPED": return "grouped_companion_presence_invalid"
		"GROUPED_COMPLETE":
			if combatant_states[hero.id].life_state != "ACTIVE" or hero_member.presence != "DEPLOYED" or deployed != 1 or alive_enemies != 0 \
					or party_encounter.contact_kind != "NONE" or party_encounter.contact_enemy_id != -1 \
					or party_encounter.formation_id != "NONE": return "grouped_complete_phase_invalid"
			for member_id in party_encounter.active_party_member_ids:
				if member_id != hero.id and combatant_states[member_id].life_state != "DEAD" \
						and party_encounter.member_rows[member_id].presence != "GROUPED": return "grouped_companion_presence_invalid"
		"CONTACT":
			if combatant_states[hero.id].life_state != "ACTIVE" or hero_member.presence != "DEPLOYED" or deployed != 1 \
					or party_encounter.contact_kind == "NONE" or party_encounter.formation_id != "NONE" \
					or combatant_states[party_encounter.contact_enemy_id].life_state == "DEAD": return "contact_phase_invalid"
			for member_id in party_encounter.active_party_member_ids:
				if member_id != hero.id and combatant_states[member_id].life_state != "DEAD" \
						and party_encounter.member_rows[member_id].presence != "GROUPED": return "contact_companion_presence_invalid"
		"ENGAGED":
			if combatant_states[hero.id].life_state != "ACTIVE" or hero_member.presence != "DEPLOYED" or deployed < 1 or alive_enemies == 0 \
					or party_encounter.contact_kind == "NONE" or party_encounter.formation_id == "NONE":
				return "engaged_phase_invalid"
			for member_id in party_encounter.active_party_member_ids:
				if party_encounter.member_rows[member_id].presence == "GROUPED": return "engaged_grouped_member_invalid"
		"REGROUP_READY":
			# v2 publishes victory only after the zero-time automatic finalizer.
			# REGROUP_READY is an active-step implementation state and is never a
			# valid decision-boundary snapshot.
			return "regroup_ready_not_settled"
		"PARTY_DEFEATED":
			if combatant_states[hero.id].life_state != "DEAD" or hero_member.presence != "DEFEATED": return "party_defeated_phase_invalid"
			if party_encounter.formation_id != "NONE" and party_encounter.contact_kind == "NONE": return "party_defeated_formation_invalid"
	if party_encounter.safe_phase == "PARTY_DEFEATED":
		var protagonist_death_found := false
		for event in events:
			if event.type == "entity.died" and event.target_id == hero.id:
				protagonist_death_found = true; break
		if not protagonist_death_found: return "party_defeat_event_missing"
	var opening_error := _party_opening_event_error(party_ids)
	if not opening_error.is_empty(): return opening_error
	var progression_error:=_party_progression_error()
	if not progression_error.is_empty():return progression_error
	var restoration_error:=_party_health_restoration_error()
	if not restoration_error.is_empty():return restoration_error
	return _party_event_correlation_error()


func _party_growth_build_error(hero) -> String:
	var growth=party_encounter.protagonist_growth
	if growth==null or not growth.validation_error().is_empty():
		return "party_growth_state_invalid"
	if str(growth.species_id)!=str(hero.species_id):
		return "party_growth_species_mismatch"
	var Registry=preload("res://sim/growth_build_registry.gd")
	var processed_families:Dictionary={}
	for death_event_id in growth.processed_mutation_death_event_ids:
		var source=event_by_id(int(death_event_id))
		if source==null or source.type!="entity.died" \
				or source.target_id not in party_encounter.enemy_ids \
				or not entities.has(source.target_id):
			return "party_growth_mutation_source_invalid"
		var family_id:=Registry.monster_family_for_species(
			str(entities[source.target_id].species_id))
		if family_id.is_empty():return "party_growth_mutation_source_invalid"
		processed_families[family_id]=true
	for mutation_id in growth.unlocked_mutation_ids:
		var definition:Dictionary=Registry.mutation_definition(mutation_id)
		if not processed_families.has(str(definition.get("monster_family_id",""))):
			return "party_growth_unlock_source_missing"
	return ""


func _party_opening_event_error(party_ids: Dictionary) -> String:
	var opening = party_encounter.opening_event
	if opening == null: return ""
	var npc_id := int(opening.npc_entity_id)
	if npc_id <= 0 or party_ids.has(npc_id) or npc_id in party_encounter.enemy_ids \
			or not entities.has(npc_id) or not combatant_states.has(npc_id):
		return "opening_npc_reference_invalid"
	for party_id in party_encounter.party_member_ids:
		if npc_id <= int(party_id): return "opening_npc_not_spawned_last"
	for enemy_id in party_encounter.enemy_ids:
		if npc_id <= int(enemy_id): return "opening_npc_not_spawned_last"
	var npc = entities[npc_id]
	var life = combatant_states[npc_id]
	if npc.kind != "companion" or npc.species_id != "elf" \
			or npc.faction_id != "neutral" or npc.tags != ["opening_event_npc"] \
			or not _terrain_is_passable(opening.spawn_position) \
			or not _terrain_is_passable(opening.convergence_goal):
		return "opening_npc_identity_invalid"
	for band_position in opening.convergence_band:
		if not _terrain_is_passable(band_position):
			return "opening_convergence_cell_blocked"
	var discovery_rows: Array = []
	var choice_rows: Array = []
	var potion_rows: Array = []
	var restoration_rows: Array = []
	var gratitude_rows: Array = []
	var reencounter_rows: Array = []
	var cursor: Vector2i = opening.spawn_position
	var projected_health := maxi(1, int((npc.max_health + 4) / 5))
	for event in events:
		if event.type == "opening.npc_discovered" and event.target_id == npc_id:
			discovery_rows.append(event)
		elif event.type == "opening.choice_committed" and event.target_id == npc_id:
			choice_rows.append(event)
		elif event.type == "opening.potion_given" and event.target_id == npc_id:
			potion_rows.append(event)
		elif event.type == "opening.health_restored" and event.target_id == npc_id:
			restoration_rows.append(event)
		elif event.type == "relationship.gratitude_recorded" \
				and event.actor_id == npc_id:
			gratitude_rows.append(event)
		elif event.type == "opening.reencountered" and event.target_id == npc_id:
			reencounter_rows.append(event)
		if event.type == "action.move" and event.actor_id == npc_id:
			if not _party_move_event_is_canonical(event) \
					or Vector2i(int(event.data.from_position[0]),
						int(event.data.from_position[1])) != cursor \
					or event.id <= opening.choice_event_id:
				return "opening_npc_move_history_invalid"
			cursor = event.position
		if event.target_id != npc_id: continue
		var event_type := str(event.type)
		if event_type.begins_with("combat.") and event_type.ends_with("_damage"):
			projected_health = maxi(0, projected_health - int(event.magnitude))
		elif event_type in ["entity.downed", "entity.died"]:
			projected_health = 0
		elif event_type == "entity.recovered":
			projected_health = int(event.data.get("recovered_health", 0))
		elif event_type == "opening.health_restored":
			var restore_keys: Array = event.data.keys(); restore_keys.sort()
			if restore_keys != ["health_after", "ruleset_id", "schema_version"] \
					or event.data.get("schema_version") != 1 \
					or event.data.get("ruleset_id") != "opening-healing-potion-v1" \
					or event.actor_id != party_encounter.protagonist_id \
					or event.magnitude <= 0:
				return "opening_health_restoration_invalid"
			projected_health = mini(npc.max_health,
				projected_health + int(event.magnitude))
			if int(event.data.health_after) != projected_health:
				return "opening_health_restoration_projection_invalid"
	if discovery_rows.size() != 1:
		return "opening_discovery_event_count_invalid"
	var discovery = discovery_rows[0]
	if discovery.actor_id != -1 or discovery.position != opening.spawn_position \
			or discovery.data.get("schema_version") != 1 \
			or discovery.data.get("state") != "WOUNDED" \
			or discovery.data.get("non_hostile") != true \
			or discovery.data.get("position") != [opening.spawn_position.x,
				opening.spawn_position.y] \
			or discovery.data.get("hexaco_profile") != opening.hexaco_profile.to_dict() \
			or discovery.data.get("convergence_goal") != [opening.convergence_goal.x,
				opening.convergence_goal.y]:
		return "opening_discovery_event_invalid"
	if cursor != npc.position: return "opening_npc_position_projection_mismatch"
	if projected_health != npc.health: return "opening_npc_health_projection_mismatch"
	if (life.life_state == "ACTIVE") != (npc.health > 0):
		return "opening_npc_life_projection_mismatch"
	if opening.choice == "PENDING":
		if not choice_rows.is_empty() or not potion_rows.is_empty() \
				or not restoration_rows.is_empty() or not gratitude_rows.is_empty() \
				or not reencounter_rows.is_empty() or cursor != opening.spawn_position:
			return "opening_pending_history_invalid"
		return ""
	if choice_rows.size() != 1: return "opening_choice_event_count_invalid"
	var choice_event = choice_rows[0]
	if choice_event.id != opening.choice_event_id \
			or choice_event.actor_id != party_encounter.protagonist_id \
			or choice_event.cause_id != -1 or choice_event.data != {
				"schema_version":1, "choice":opening.choice}:
		return "opening_choice_event_invalid"
	var relation_key := "%d:%d" % [npc_id, party_encounter.protagonist_id]
	var relation = personal_relations.get(relation_key)
	if opening.choice == "PASSED":
		if not potion_rows.is_empty() or not restoration_rows.is_empty() \
				or not gratitude_rows.is_empty() or relation != null:
			return "opening_pass_mutated_authority"
	else:
		if potion_rows.size() != 1 or restoration_rows.size() != 1 \
				or gratitude_rows.size() != 1 or relation == null:
			return "opening_give_event_chain_missing"
		var given = potion_rows[0]
		var restored = restoration_rows[0]
		var gratitude = gratitude_rows[0]
		if given.actor_id != party_encounter.protagonist_id \
				or given.cause_id != choice_event.id or given.magnitude != 1 \
				or given.data.get("schema_version") != 1 \
				or given.data.get("definition_id") != "POTION_HEALING" \
				or restored.cause_id != given.id \
				or gratitude.cause_id != restored.id \
				or gratitude.target_id != party_encounter.protagonist_id \
				or gratitude.magnitude != 60 \
				or relation.gratitude != 60 \
				or relation.personal_trust_delta != 0 \
				or relation.personal_fear_delta != 0 \
				or relation.processed_source_event_ids != [restored.id]:
			return "opening_give_event_chain_invalid"
	if reencounter_rows.size() > 1: return "opening_reencounter_event_count_invalid"
	if opening.reencounter_event_id == -1:
		if not reencounter_rows.is_empty(): return "opening_reencounter_projection_mismatch"
	elif reencounter_rows.size() != 1:
		return "opening_reencounter_projection_mismatch"
	else:
		var reencounter = reencounter_rows[0]
		if reencounter.id != opening.reencounter_event_id \
				or reencounter.actor_id != party_encounter.protagonist_id \
				or reencounter.cause_id != opening.choice_event_id \
				or reencounter.position not in opening.convergence_band \
				or reencounter.data.get("schema_version") != 1 \
				or reencounter.data.get("choice") != opening.choice:
			return "opening_reencounter_event_invalid"
	return ""


func _rebuild_progression_from_events(use_all_normal_baseline:bool=false)->void:
	if party_encounter==null:return
	var historical_modes:Dictionary=_legacy_party_training_modes() if use_all_normal_baseline \
		else party_encounter.protagonist_progression.training_modes.duplicate(true)
	var progression=load("res://sim/protagonist_progression.gd").new()
	# Preserve whichever v1-v3 focus/mode baseline was actually serialized. Only
	# snapshots predating progression entirely use the historical all-normal base.
	progression.training_modes=historical_modes
	progression.legacy_reward_origin=true
	for event in events:
		if event.type=="progression.focus_changed" and event.actor_id==party_encounter.protagonist_id:
			var modes:=_training_modes_from_event(event)
			if not modes.is_empty():progression.training_modes=modes
		elif event.type=="party.victory":progression.award_legacy_victory(event.id)
	party_encounter.protagonist_progression=progression


func _party_progression_error()->String:
	if party_encounter.protagonist_progression==null:return "party_progression_missing"
	var expected=load("res://sim/protagonist_progression.gd").new()
	expected.legacy_reward_origin=party_encounter.protagonist_progression.legacy_reward_origin
	expected.training_modes=party_encounter.protagonist_progression.training_modes.duplicate(true) \
		if party_encounter.protagonist_progression.legacy_reward_origin \
		else _initial_party_training_modes()
	for event in events:
		if event.type=="progression.focus_changed":
			if event.actor_id!=party_encounter.protagonist_id or event.target_id!=-1 \
					or event.cause_id!=-1 or event.instigator_id!=party_encounter.protagonist_id \
					or event.magnitude!=0 \
					or not in_bounds(event.position):
				return "progression_focus_event_envelope_invalid"
			var modes:=_training_modes_from_event(event)
			if modes.is_empty():return "progression_focus_event_data_invalid"
			var skill_id:=str(event.data.get("skill_id",""))
			var expected_mode:=str(event.data.get("mode","FOCUS"))
			if modes==expected.training_modes or modes.get(skill_id)!=expected_mode:
				return "progression_focus_event_transition_invalid"
			for proficiency_id in ProgressionRegistryScript.SKILL_IDS:
				if proficiency_id!=skill_id \
						and modes[proficiency_id]!=expected.training_modes[proficiency_id] \
						and int(event.data.get("schema_version",0))==2:
					return "progression_focus_event_transition_invalid"
			expected.training_modes=modes
		elif event.type=="entity.died" and event.target_id in party_encounter.enemy_ids:
			if event.id in party_encounter.protagonist_progression.processed_source_death_event_ids:
				if not expected.award_enemy_death(event.id):return "progression_enemy_death_award_invalid"
				var reward_rows:Array=[]
				for candidate in events:
					if candidate.type=="progression.enemy_reward" and candidate.cause_id==event.id:
						reward_rows.append(candidate)
				if reward_rows.size()!=1:return "progression_enemy_reward_event_count_invalid"
				var reward=reward_rows[0];var reward_keys:Array=reward.data.keys();reward_keys.sort()
				if reward_keys!=["character_xp","mastery_pool","ruleset_id","schema_version"] \
						or reward.actor_id!=party_encounter.protagonist_id \
						or reward.target_id!=event.target_id or reward.position!=event.position \
						or reward.magnitude!=ProgressionRegistryScript.ENEMY_KILL_CHARACTER_XP \
						or reward.data.schema_version!=1 \
						or reward.data.character_xp!=ProgressionRegistryScript.ENEMY_KILL_CHARACTER_XP \
						or reward.data.mastery_pool!=ProgressionRegistryScript.ENEMY_KILL_MASTERY_POOL \
						or reward.data.ruleset_id!=ProgressionRegistryScript.RULESET_ID:
						return "progression_enemy_reward_event_invalid"
		elif event.type=="party.victory" \
				and event.id in party_encounter.protagonist_progression.legacy_processed_victory_event_ids:
			if not expected.award_legacy_victory(event.id):return "progression_legacy_victory_award_invalid"
	if not party_encounter.protagonist_progression.legacy_reward_origin:
		for event in events:
			if event.type=="entity.died" and event.target_id in party_encounter.enemy_ids \
					and event.id not in party_encounter.protagonist_progression.processed_source_death_event_ids:
				return "progression_enemy_death_award_missing"
		for reward in events:
			if reward.type!="progression.enemy_reward":continue
			var source=event_by_id(reward.cause_id)
			if source==null or source.type!="entity.died" \
					or source.id not in party_encounter.protagonist_progression.processed_source_death_event_ids:
				return "progression_enemy_reward_source_invalid"
	if expected.to_dict()!=party_encounter.protagonist_progression.to_dict():
		return "party_progression_projection_mismatch"
	return ""


func _progression_melee_rank_before(event_id:int)->int:
	return _progression_rank_before("MELEE",event_id)


func _progression_rank_before(skill_id:String,event_id:int)->int:
	if skill_id not in ProgressionRegistryScript.SKILL_IDS:return 0
	var modes:Dictionary=_legacy_party_training_modes() \
		if party_encounter.protagonist_progression.legacy_reward_origin \
		else _initial_party_training_modes()
	var training:=0
	for historical in events:
		if historical.id>=event_id:break
		if historical.type=="progression.focus_changed":
			var parsed:=_training_modes_from_event(historical)
			if not parsed.is_empty():modes=parsed
		elif historical.type=="entity.died" and historical.target_id in party_encounter.enemy_ids \
				and historical.id in party_encounter.protagonist_progression.processed_source_death_event_ids:
			training+=int(ProgressionRegistryScript.enemy_kill_mastery_allocation(modes)[skill_id])
		elif historical.type=="party.victory" \
				and historical.id in party_encounter.protagonist_progression.legacy_processed_victory_event_ids:
			training+=int(ProgressionRegistryScript.enemy_kill_mastery_allocation(modes)[skill_id])
	return ProgressionRegistryScript.skill_rank(training)


func _initial_party_training_modes()->Dictionary:
	# This is the expedition baseline, not a live loadout projection. Equipment
	# may change through canonical item events while the player's independently
	# selected training modes remain intact; replay therefore must not derive the
	# opening focus from whichever weapon is currently equipped.
	return ProgressionRegistryScript.initial_training_modes("SWORD")


func _legacy_party_training_modes()->Dictionary:
	return {"SWORD":"NORMAL","AXE":"NORMAL","BLUNT":"NORMAL",
		"SPEAR":"NORMAL","RANGED":"NORMAL","UNARMED":"NORMAL"}


func _party_health_restoration_error()->String:
	if party_encounter==null:return ""
	var hero_id:int=party_encounter.protagonist_id
	if not entities.has(hero_id) or not combatant_states.has(hero_id):return "party_recovery_hero_missing"
	# The party protagonist is spawned at max health. From there, canonical
	# damage/lifecycle leaves and our restoration event form a replayable HP ledger.
	var projected:=int(entities[hero_id].max_health)
	for event in events:
		if event.target_id!=hero_id:continue
		var event_type:=str(event.type)
		if event_type.begins_with("combat.") and event_type.ends_with("_damage"):
			projected=maxi(0,projected-int(event.magnitude))
		elif event_type=="entity.downed":
			projected=0
		elif event_type=="entity.recovered":
			projected=int(event.data.get("recovered_health",0))
		elif event_type=="entity.died":
			projected=0
		elif event_type=="health.restored":
			var data_keys:Array=event.data.keys();data_keys.sort()
			var restoration_kind:=str(event.data.get("kind",""))
			var expected_keys:Array=["health_after","kind","ruleset_id","schema_version"] \
				if restoration_kind=="POTION" else ["health_after","kind","ruleset_id","safe_turn_count","schema_version"]
			if data_keys!=expected_keys or event.data.get("schema_version")!=1 or event.actor_id!=hero_id \
					or event.instigator_id!=hero_id or event.magnitude<=0 \
					or int(event.data.get("health_after",-1))<1 \
					or int(event.data.get("health_after",-1))>int(entities[hero_id].max_health):
				return "party_health_restoration_event_invalid"
			var expected_after:=mini(int(entities[hero_id].max_health),projected+int(event.magnitude))
			if int(event.data.health_after)!=expected_after:return "party_health_restoration_amount_invalid"
			if restoration_kind=="POTION":
				var source=event_by_id(event.cause_id)
				if source==null or source.type!="item.used" or source.actor_id!=hero_id \
						or source.target_id!=hero_id or source.id>=event.id \
						or source.data.get("use_kind")!="HEALING" \
						or event.data.ruleset_id!="healing-potion-v1":
					return "party_potion_restoration_cause_invalid"
			elif restoration_kind=="AUTO":
				if event.cause_id!=-1 or event.data.ruleset_id!="safe-exploration-recovery-v1" \
						or int(event.data.get("safe_turn_count",0))<1:
					return "party_auto_restoration_cause_invalid"
			else:return "party_health_restoration_kind_invalid"
			projected=expected_after
	if int(entities[hero_id].health)!=projected:return "party_health_restoration_projection_mismatch"
	return ""


func _focus_from_event(event)->Dictionary:
	if not event.data is Dictionary:return {}
	var data_keys:Array=event.data.keys();data_keys.sort()
	if data_keys!=["focus","schema_version","skill_id"] or event.data.schema_version!=1 \
			or event.data.skill_id not in ProgressionRegistryScript.SKILL_IDS \
			or not event.data.focus is Array \
			or event.data.focus.size()!=ProgressionRegistryScript.SKILL_IDS.size():return {}
	var focus:={}
	for index in range(ProgressionRegistryScript.SKILL_IDS.size()):
		var row:Variant=event.data.focus[index]
		var skill_id:String=ProgressionRegistryScript.SKILL_IDS[index]
		if not row is Dictionary or row.keys().size()!=2 or not row.has_all(["skill_id","weight"]) \
				or str(row.skill_id)!=skill_id or not row.weight is int:return {}
		focus[skill_id]=int(row.weight)
	return focus if ProgressionRegistryScript.focus_error(focus).is_empty() else {}


func _training_modes_from_event(event)->Dictionary:
	if not event.data is Dictionary:return {}
	if int(event.data.get("schema_version",0))==1:
		var legacy_focus:=_focus_from_event(event)
		return ProgressionRegistryScript.modes_from_legacy_focus(legacy_focus) \
			if not legacy_focus.is_empty() else {}
	var data_keys:Array=event.data.keys();data_keys.sort()
	if data_keys!=["mode","schema_version","skill_id","training_modes"] \
			or event.data.schema_version!=2 \
			or event.data.skill_id not in ProgressionRegistryScript.SKILL_IDS \
			or event.data.mode not in ProgressionRegistryScript.TRAINING_MODES \
			or not event.data.training_modes is Array \
			or event.data.training_modes.size()!=ProgressionRegistryScript.SKILL_IDS.size():return {}
	var modes:={}
	for index in range(ProgressionRegistryScript.SKILL_IDS.size()):
		var row:Variant=event.data.training_modes[index]
		var skill_id:String=ProgressionRegistryScript.SKILL_IDS[index]
		if not row is Dictionary or row.keys().size()!=2 \
				or not row.has_all(["skill_id","mode"]) \
				or str(row.skill_id)!=skill_id \
				or row.mode not in ProgressionRegistryScript.TRAINING_MODES:return {}
		modes[skill_id]=str(row.mode)
	return modes if ProgressionRegistryScript.training_modes_error(modes).is_empty() else {}


func _party_event_correlation_error() -> String:
	var hero_id: int = party_encounter.protagonist_id
	var contact_types := ["encounter.detected", "encounter.party_ambush", "encounter.enemy_ambush"]
	var contact_events: Array = []
	for event in events:
		if event.type in contact_types: contact_events.append(event)
	var contact = null
	var contact_required: bool = party_encounter.contact_kind != "NONE" \
		or party_encounter.safe_phase == "GROUPED_COMPLETE"
	if contact_events.is_empty():
		if contact_required: return "party_contact_event_missing"
	else:
		# A floor may contain several independent encounter groups. Validate the
		# latest contact segment against live state; older segments remain guarded
		# by their immutable action/damage leaves and cause-id deployment chains.
		contact = contact_events.back()
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
		var contact_reports: Array = []
		for event in events:
			if event.type == "party.contact_reported" and event.cause_id == contact.id:
				contact_reports.append(event)
		if contact_reports.size() > 1:
			return "party_contact_report_count_invalid"
		var companion_reported := false
		if not contact_reports.is_empty():
			var report = contact_reports[0]
			var report_keys: Array = report.data.keys(); report_keys.sort()
			var expected_report_keys := ["direction","distance","enemy_id",
				"observed_position","ruleset_id","schema_version","sight_range",
				"spotter_id"]
			if report_keys != expected_report_keys \
					or int(report.data.get("schema_version",0)) != 1 \
					or str(report.data.get("ruleset_id","")) \
						!= PartyPerceptionRegistryScript.RULESET_ID \
					or not Int64CodecScript.is_canonical(report.data.get("spotter_id")) \
					or not Int64CodecScript.is_canonical(report.data.get("enemy_id")):
				return "party_contact_report_data_mismatch"
			var spotter_id := Int64CodecScript.parse(report.data.spotter_id,
				"contact report spotter")
			var reported_enemy_id := Int64CodecScript.parse(report.data.enemy_id,
				"contact report enemy")
			var sight_range := PartyPerceptionRegistryScript.sight_range(
				self, party_encounter, spotter_id)
			if spotter_id == hero_id or spotter_id not in party_encounter.party_member_ids \
					or not _party_alive_at_event(spotter_id, report.id) \
					or reported_enemy_id != contact_enemy_id \
					or report.actor_id != spotter_id or report.target_id != contact_enemy_id \
					or report.position != contact.position or report.magnitude != 0 \
					or report.instigator_id != contact.instigator_id \
					or not _party_metadata_position(report.data.get("observed_position")) \
					or Vector2i(int(report.data.observed_position[0]),
						int(report.data.observed_position[1])) != contact_enemy_position \
					or not _party_metadata_facing(report.data.get("direction")) \
					or Vector2i(int(report.data.direction[0]),int(report.data.direction[1])) \
						!= contact_facing \
					or int(report.data.get("distance",-1)) != distance \
					or int(report.data.get("sight_range",-1)) != sight_range \
					or distance > sight_range:
				return "party_contact_report_semantic_mismatch"
			companion_reported = true
		var hero_detects: bool = distance <= party_encounter.party_detection_radius
		if hero_detects and companion_reported \
				or not hero_detects and companion_reported == false \
					and contact_kind in ["DETECTED","PARTY_AMBUSH"]:
			return "party_contact_report_presence_mismatch"
		var party_detects: bool = hero_detects or companion_reported
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
		if contact==null or event.cause_id!=contact.id:continue
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
				or deployment_completed.data.companion_ids.size() \
					> PartyEncounterStateScript.MAX_ACTIVE_PARTY_SIZE-1:
			return "party_deployment_completed_data_invalid"
		historical_formation = str(deployment_completed.data.formation_id)
		var previous_id := 0
		for wire in deployment_completed.data.companion_ids:
			if not Int64CodecScript.is_canonical(wire): return "party_deployment_companion_id_invalid"
			var companion_id := Int64CodecScript.parse(wire, "deployment companion")
			if companion_id <= previous_id or companion_id == hero_id \
					or not party_encounter.member_rows.has(companion_id) \
					or companion_id not in _party_active_ids_at_event(deployment_completed.id):
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
			if member == null or member.roster_slot <= 0 \
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
			for member_id in party_encounter.active_party_member_ids:
				if member_id == hero_id: continue
				var member = party_encounter.member(member_id)
				var was_selected: bool = member_id in selected_companions
				if combatant_states[member_id].life_state != "DEAD" and ((was_selected and member.presence != "DEPLOYED") \
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
		if root.actor_id != hero_id or root.target_id != -1 or root.cause_id != victory.id or root.magnitude != 0 \
				or not root.data.is_empty() or root.position != victory.position or not bool(root_history.ok) \
				or root_history.position != victory.position or root.id <= victory.id \
				or root.step_index != victory.step_index \
				or completed.actor_id != hero_id or completed.target_id != -1 or completed.cause_id != root.id \
				or completed.position != victory.position or completed.magnitude != 0 \
				or not completed.data.is_empty() or completed.id <= root.id \
				or completed.step_index != victory.step_index or completed.world_time != root.world_time:
			return "party_regroup_root_or_completed_mismatch"
		var root_index := _event_index(root.id); var completed_index := _event_index(completed.id)
		if completed_index-root_index-1 != regroup_members.size(): return "party_regroup_event_order_invalid"
		var seen_regrouped: Dictionary = {}; var previous_slot := 0
		var active_at_regroup: Array = _party_active_ids_at_event(root.id)
		for offset in range(regroup_members.size()):
			var event = regroup_members[offset]
			if events[root_index+1+offset].id != event.id or event.actor_id == hero_id \
					or event.actor_id not in active_at_regroup or seen_regrouped.has(event.actor_id):
				return "party_member_regrouped_order_invalid"
			var member = party_encounter.member(event.actor_id)
			if member == null or member.roster_slot <= previous_slot or event.target_id != hero_id \
					or event.position != victory.position or event.cause_id != root.id \
					or event.magnitude != 0 or not event.data.is_empty():
				return "party_member_regrouped_semantic_mismatch"
			seen_regrouped[event.actor_id] = true; previous_slot = member.roster_slot
		for member_id in active_at_regroup:
			if member_id == hero_id: continue
			if _party_alive_at_event(member_id, root.id) != seen_regrouped.has(member_id):
				return "party_member_regrouped_set_mismatch"
	if party_encounter.safe_phase == "PARTY_DEFEATED" and party_encounter.contact_kind == "NONE" \
			and contact != null and not has_regroup_history:
		return "party_cleared_contact_without_regroup_history"
	var roster_error := _party_roster_history_error()
	if not roster_error.is_empty(): return roster_error
	var patrol_error := _party_patrol_history_error()
	if not patrol_error.is_empty(): return patrol_error
	var override_error := _party_override_history_error()
	if not override_error.is_empty(): return override_error
	var command_error := _party_command_history_error()
	if not command_error.is_empty(): return command_error
	var morale_error := _party_morale_history_error()
	if not morale_error.is_empty(): return morale_error
	return ""


func _party_command_history_error()->String:
	var hero_id:=int(party_encounter.protagonist_id)
	var engaged:=false
	for event in events:
		if event.type=="party.deployment_completed":
			engaged=true
		elif event.type in ["party.victory","party.regroup_started",
				"party.regroup_completed"]:
			engaged=false
		if event.type!="party.command_issued":continue
		var data_error:=PartyCommandScript.data_error(event.data)
		if not data_error.is_empty():return data_error
		var hero_history:Dictionary=_party_entity_position_at_event(hero_id,event.id)
		var command_id:=str(event.data.command_id)
		var target_id:=Int64CodecScript.parse(event.data.target_id,
			"party command target")
		if not engaged or event.actor_id!=hero_id or event.target_id!=target_id \
				or event.position!=hero_history.get("position",Vector2i(-1,-1)) \
				or not bool(hero_history.get("ok",false)) or event.magnitude!=0 \
				or event.cause_id!=-1 or event.instigator_id!=hero_id:
			return "party_command_event_semantic_mismatch"
		if command_id=="ATTACK_TARGET" and (target_id not in party_encounter.enemy_ids \
				or not _party_alive_at_event(target_id,event.id)):
			return "party_command_target_history_mismatch"
	return ""


func _party_patrol_history_error()->String:
	# Exploration patrol leaves only the existing canonical MOVE/HOLD leaves.
	# Correlate every pre-contact enemy leaf here so a forged snapshot cannot use
	# that intentionally small surface to smuggle an impossible position.
	var contact_id:=9223372036854775807
	for event in events:
		if event.type in ["encounter.detected","encounter.party_ambush",
				"encounter.enemy_ambush"]:
			contact_id=mini(contact_id,event.id)
	var occupied_cadences:Dictionary={}
	for event in events:
		if event.id>=contact_id:break
		if event.actor_id not in party_encounter.enemy_ids:continue
		if event.type not in ["action.move","action.hold"]:
			continue
		var cadence_key:="%d:%d:%d"%[event.step_index,event.world_time,event.actor_id]
		if occupied_cadences.has(cadence_key):return "party_patrol_duplicate_action"
		occupied_cadences[cadence_key]=true
		if event.type=="action.move":
			if not _party_move_event_is_canonical(event):
				return "party_patrol_move_invalid"
			var destination:=Vector2i(int(event.data.to_position[0]),
				int(event.data.to_position[1]))
			if destination in party_encounter.patrol_reserved_positions:
				return "party_patrol_reserved_destination"
			var before:=_party_entity_position_at_event(event.actor_id,event.id-1)
			if not bool(before.ok) or before.position!=Vector2i(
					int(event.data.from_position[0]),int(event.data.from_position[1])):
				return "party_patrol_move_history_invalid"
	return ""


func _party_override_history_error() -> String:
	var hero_id: int = party_encounter.protagonist_id
	var consumed_leaf_ids: Dictionary = {}
	var leaf_types := ["action.move", "action.hold", "action.melee_attack"]
	var result_types := ["combat.attack_missed", "combat.physical_damage", "combat.downed_damage"]
	for override_index in range(events.size()):
		var override = events[override_index]
		if override.type != "party.override_committed": continue
		if override.actor_id == hero_id or not party_encounter.member_rows.has(override.actor_id) \
				or override.actor_id not in _party_active_ids_at_event(override.id):
			return "party_override_actor_invalid"
		var member = party_encounter.member(override.actor_id)
		if member == null or member.role != "COMPANION" or member.personality_profile == null:
			return "party_override_actor_invalid"
		if override.target_id != -1 or not override.data.is_empty():
			return "party_override_envelope_invalid"
		var leaf = event_by_id(override.cause_id)
		if leaf == null or leaf.type not in leaf_types or leaf.actor_id != override.actor_id \
				or leaf.step_index != override.step_index or leaf.world_time != override.world_time:
			return "party_override_leaf_invalid"
		var nearest_leaf = null
		for prior_index in range(override_index - 1, -1, -1):
			if events[prior_index].type in leaf_types:
				nearest_leaf = events[prior_index]
				break
		if nearest_leaf == null or nearest_leaf.id != leaf.id:
			return "party_override_leaf_invalid"
		if consumed_leaf_ids.has(leaf.id):
			return "party_override_duplicate"
		consumed_leaf_ids[leaf.id] = true
		var historical_position: Dictionary = _entity_position_at_event(override.actor_id, override.id)
		if not bool(historical_position.get("ok", false)) \
				or override.position != historical_position.position:
			return "party_override_position_invalid"
		var personal = personal_relations.get("%d:%d" % [override.actor_id, hero_id])
		if party_encounter.schema_version < PartyEncounterStateScript.HEXACO_SCHEMA_VERSION:
			var composure: int = member.personality_profile.value("composure")
			var legacy_magnitude: int = 20 + int((999 - composure) / 20) \
				+ (int(personal.grievance / 5) if personal != null else 0) \
				- (int(personal.gratitude / 10) if personal != null else 0)
			if override.magnitude != maxi(1, legacy_magnitude):
				return "party_override_magnitude_invalid"
		else:
			var emotionality: int = member.personality_profile.value("E")
			var conscientiousness: int = member.personality_profile.value("C")
			var resilience: int = FixedPointScript.trunc_div(
				conscientiousness + 1000 - emotionality, 2)
			var expected_magnitude: int = 20 + int((1000 - resilience) / 20) \
				+ (int(personal.grievance / 5) if personal != null else 0) \
				- (int(personal.gratitude / 10) if personal != null else 0)
			expected_magnitude = maxi(1, expected_magnitude)
			if override.magnitude != expected_magnitude \
					and not (party_encounter.legacy_journal_origin \
					and override.magnitude >= 1 and override.magnitude <= 200):
				return "party_override_magnitude_invalid"
		var canonical_leaf: bool = leaf.type != "action.melee_attack" \
				or leaf.data.get("schema_version") == 1
		if canonical_leaf:
			var leaf_index: int = _event_index(leaf.id)
			if leaf_index < 0 or override_index != leaf_index + 1 \
					or override.id != leaf.id + 1:
				return "party_override_leaf_invalid"
		if leaf.type == "action.melee_attack" and leaf.data.get("schema_version") == 1:
			for candidate in events:
				if candidate.cause_id == leaf.id and candidate.type in result_types \
						and candidate.id < override.id:
					return "party_override_order_invalid"
	return ""


func _party_morale_history_error() -> String:
	var latest_by_actor: Dictionary = {}
	var previous_by_actor: Dictionary = {}
	var allowed_triggers := ["ALLY_DIED", "ALLY_DOWNED", "ALLY_FEAR_CONTAGION",
		"ENEMY_DIED", "OVERRIDE_STRESS", "SAFE_RECOVERY", "SELF_DAMAGE",
		"SELF_DOWNED"]
	for event in events:
		if event.type != "party.morale_changed":
			continue
		if event.actor_id not in party_encounter.active_party_member_ids \
				or event.target_id != -1:
			return "party_morale_actor_invalid"
		var historical_position: Dictionary = _entity_position_at_event(
			event.actor_id, event.id)
		if not bool(historical_position.get("ok", false)) \
				or event.position != historical_position.position:
			return "party_morale_position_invalid"
		var keys := ["contagion_delta", "direct_delta", "mode_after", "mode_before",
			"recovery_delta", "ruleset_id", "schema_version", "source_event_ids",
			"stress_after", "stress_before", "trigger_codes"]
		var accepted_rulesets := [PartyMoraleModelScript.RULESET_ID]
		if party_encounter.legacy_journal_origin:
			accepted_rulesets.append("party-morale-contagion-v1")
		if not _exact_keys(event.data, keys) or event.data.get("schema_version") != 1 \
				or event.data.get("ruleset_id") not in accepted_rulesets:
			return "party_morale_data_invalid"
		for key in ["stress_before", "direct_delta", "contagion_delta",
				"recovery_delta", "stress_after"]:
			if not event.data.get(key) is int:
				return "party_morale_scalar_invalid"
		var stress_before := int(event.data.stress_before)
		var stress_after := int(event.data.stress_after)
		var direct_delta := int(event.data.direct_delta)
		var contagion_delta := int(event.data.contagion_delta)
		var recovery_delta := int(event.data.recovery_delta)
		if stress_before < 0 or stress_before > 1000 or stress_after < 0 \
				or stress_after > 1000 or contagion_delta < 0 \
				or contagion_delta > PartyMoraleModelScript.MAX_CONTAGION \
				or recovery_delta not in [0, PartyMoraleModelScript.RECOVERY_DELTA] \
				or stress_after != clampi(stress_before + direct_delta \
					+ contagion_delta + recovery_delta, 0, 1000) \
				or event.magnitude != absi(stress_after - stress_before):
			return "party_morale_projection_invalid"
		var mode_before := str(event.data.mode_before)
		var mode_after := str(event.data.mode_after)
		if mode_before not in PartyMemberStateScript.MENTAL_MODES \
				or mode_after != PartyMoraleModelScript.next_mode(mode_before, stress_after):
			return "party_morale_mode_invalid"
		if previous_by_actor.has(event.actor_id):
			var previous: Dictionary = previous_by_actor[event.actor_id]
			if stress_before != int(previous.stress_after) \
					or mode_before != str(previous.mode_after):
				return "party_morale_chain_invalid"
		var trigger_codes: Variant = event.data.get("trigger_codes")
		if not trigger_codes is Array:
			return "party_morale_trigger_invalid"
		var previous_trigger := ""
		for trigger in trigger_codes:
			if not trigger is String or trigger not in allowed_triggers \
					or str(trigger) < previous_trigger:
				return "party_morale_trigger_invalid"
			previous_trigger = str(trigger)
		var source_rows: Variant = event.data.get("source_event_ids")
		if not source_rows is Array or source_rows.size() > 128:
			return "party_morale_source_invalid"
		var previous_source := -1
		for source_wire in source_rows:
			if not Int64CodecScript.is_canonical(source_wire):
				return "party_morale_source_invalid"
			var source_id := Int64CodecScript.parse(source_wire, "morale source")
			var source = event_by_id(source_id)
			if source_id <= previous_source or source_id >= event.id or source == null \
					or source.step_index != event.step_index \
					or source.type not in ["combat.physical_damage", "combat.downed_damage",
						"entity.downed", "entity.died", "party.override_committed"]:
				return "party_morale_source_invalid"
			previous_source = source_id
		if (source_rows.is_empty() and event.cause_id != -1) \
				or (not source_rows.is_empty() and event.cause_id != previous_source):
			return "party_morale_source_invalid"
		previous_by_actor[event.actor_id] = {
			"stress_after":stress_after, "mode_after":mode_after}
		latest_by_actor[event.actor_id] = event
	for member_id in party_encounter.active_party_member_ids:
		if not latest_by_actor.has(member_id):
			continue
		var latest = latest_by_actor[member_id]
		var member = party_encounter.member(member_id)
		if member == null or member.stress != int(latest.data.stress_after) \
				or member.mental_mode != str(latest.data.mode_after):
			return "party_morale_state_projection_mismatch"
	return ""


func _party_active_ids_at_event(event_id: int) -> Array:
	var active: Array = party_encounter.party_member_ids.slice(0,
		mini(3, party_encounter.party_member_ids.size()))
	for event in events:
		if event.id >= event_id: break
		if event.type == "party.companion_dismissed": active.erase(event.target_id)
		elif event.type == "party.companion_recruited" and event.target_id not in active:
			active.append(event.target_id); active.sort()
	return active


func _party_roster_history_error() -> String:
	var hero_id: int = party_encounter.protagonist_id
	var active: Array = party_encounter.party_member_ids.slice(0,
		mini(3, party_encounter.party_member_ids.size()))
	var recruitable: Array = party_encounter.party_member_ids.slice(active.size())
	var exiled: Array = []
	var contact_id := 9223372036854775807
	var regroup_complete_id := -1
	for event in events:
		if event.type in ["encounter.detected", "encounter.party_ambush", "encounter.enemy_ambush"]:
			contact_id = mini(contact_id, event.id)
		elif event.type == "party.regroup_completed":
			regroup_complete_id = event.id
		if event.type not in ["party.companion_dismissed", "party.companion_recruited"]: continue
		var operation := "DISMISS" if event.type == "party.companion_dismissed" else "RECRUIT"
		var hero_history: Dictionary = _party_entity_position_at_event(hero_id, event.id)
		var member = party_encounter.member(event.target_id)
		var event_data_valid:bool=event.data=={"operation":"RECRUIT"} if operation=="RECRUIT" \
			else (_exact_keys(event.data,["condition_band","operation","resentment_delta"]) \
				and event.data.get("operation")=="DISMISS" \
				and event.data.get("condition_band") in ["HEALTHY","STRAINED","ENDANGERED"] \
				and event.data.get("resentment_delta") is int \
				and int(event.data.get("resentment_delta"))>=10 \
				and int(event.data.get("resentment_delta"))<=100)
		if event.actor_id != hero_id or member == null or member.role != "COMPANION" \
				or event.target_id == hero_id or event.position != hero_history.get("position", Vector2i(-1,-1)) \
				or not bool(hero_history.get("ok", false)) or event.magnitude != 0 or event.cause_id != -1 \
				or not event_data_valid:
			return "party_roster_event_semantic_mismatch"
		if event.id >= contact_id and (regroup_complete_id < 0 or event.id <= regroup_complete_id):
			return "party_roster_event_unsafe_phase"
		if operation == "DISMISS":
			if event.target_id not in active or active.size() <= 1: return "party_roster_event_transition_invalid"
			active.erase(event.target_id); exiled.append(event.target_id); exiled.sort()
		else:
			if event.target_id not in recruitable \
					or active.size() >= PartyEncounterStateScript.MAX_ACTIVE_PARTY_SIZE:
				return "party_roster_event_transition_invalid"
			recruitable.erase(event.target_id); active.append(event.target_id); active.sort()
	var expected_recruitable: Array = []
	var expected_exiled: Array = []
	for member_id in party_encounter.party_member_ids:
		var presence: String = str(party_encounter.member(member_id).presence)
		if presence == "RECRUITABLE": expected_recruitable.append(member_id)
		elif presence == "EXILED": expected_exiled.append(member_id)
	if active != party_encounter.active_party_member_ids \
			or recruitable != expected_recruitable or exiled != expected_exiled:
		return "party_roster_history_mismatch"
	if party_encounter.exile_records.size()!=exiled.size():return "party_exile_record_count_mismatch"
	var recorded_ids:Dictionary={}
	for record in party_encounter.exile_records:
		var former_id:=Int64CodecScript.parse(record.former_member_id,"former member")
		if former_id not in exiled or recorded_ids.has(former_id):return "party_exile_record_identity_mismatch"
		recorded_ids[former_id]=true
		var dismissal=event_by_id(Int64CodecScript.parse(record.dismissal_event_id,"dismissal event"))
		if dismissal==null or dismissal.type!="party.companion_dismissed" \
				or dismissal.target_id!=former_id or dismissal.actor_id!=hero_id \
				or dismissal.world_time!=Int64CodecScript.parse(record.dismissed_world_time,"dismissed time") \
				or dismissal.step_index!=Int64CodecScript.parse(record.dismissed_step_index,"dismissed step") \
				or dismissal.data.get("condition_band")!=record.condition_snapshot.condition_band \
				or dismissal.data.get("resentment_delta")!=record.emotion_modifiers.resentment_delta \
				or Int64CodecScript.parse(record.encounter_eligible_after_step,"eligible step")!=dismissal.step_index+5:
			return "party_exile_record_dismissal_mismatch"
		var entity=entities[former_id];var member=party_encounter.member(former_id)
		if record.display_name!=entity.display_name or record.species_id!=entity.species_id \
				or record.personality_summary.profile_hash \
				!=JSON.stringify(member.personality_profile.to_dict()).sha256_text():
			return "party_exile_record_identity_summary_mismatch"
		var harm=event_by_id(dismissal.id+1)
		if harm==null or harm.type!="relationship.harm_recorded" or harm.cause_id!=dismissal.id \
				or harm.actor_id!=former_id or harm.target_id!=hero_id \
				or harm.magnitude!=int(record.emotion_modifiers.resentment_delta) \
				or harm.data.get("grievance")!=record.relationship_snapshot.grievance:
			return "party_exile_resentment_event_mismatch"
		var tick_rows:Array=[];var death_rows:Array=[]
		for candidate in events:
			if candidate.target_id!=former_id:continue
			if candidate.type=="party.exile_world_tick":tick_rows.append(candidate)
			elif candidate.type=="party.exile_died":death_rows.append(candidate)
		var expected_hp:=int(record.condition_snapshot.hp)
		var expected_statuses:Array=record.initial_status_effects.duplicate(true)
		var expected_safety:=int(record.initial_safety)
		var expected_time:int=dismissal.world_time
		var last_tick_step:int=dismissal.step_index
		for tick in tick_rows:
			expected_time+=100
			if tick.actor_id!=-1 or tick.cause_id!=dismissal.id or tick.magnitude<0 \
					or not _exact_keys(tick.data,["alive","behavior","expired_status_ids","hp_after",
						"hp_before","safety_after","scheduled_world_time","status_effects_after"]) \
					or not Int64CodecScript.is_canonical(tick.data.get("scheduled_world_time")) \
					or Int64CodecScript.parse(tick.data.scheduled_world_time,"exile tick")!=expected_time \
					or tick.data.get("hp_before")!=expected_hp \
					or not tick.data.get("status_effects_after") is Array:
				return "party_exile_tick_event_mismatch"
			expected_hp=int(tick.data.hp_after);expected_statuses=tick.data.status_effects_after.duplicate(true)
			expected_safety=int(tick.data.safety_after);last_tick_step=tick.step_index
		if expected_hp!=int(record.current_hp) or expected_statuses!=record.status_effects \
				or expected_safety!=int(record.safety) \
				or Int64CodecScript.parse(record.last_world_time,"last world time")!=expected_time \
				or Int64CodecScript.parse(record.last_world_step,"last world step")!=last_tick_step:
			return "party_exile_tick_projection_mismatch"
		if bool(record.alive):
			if not death_rows.is_empty():return "party_exile_alive_has_death_event"
		elif death_rows.size()!=1:return "party_exile_death_event_count_mismatch"
		else:
			var death=death_rows[0]
			if tick_rows.is_empty() or death.actor_id!=-1 or death.cause_id!=tick_rows[-1].id \
					or death.data!={"reason":"OFFSCREEN_CONDITION"}:
				return "party_exile_death_event_mismatch"
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


func _entity_position_at_event(entity_id: int, event_id: int) -> Dictionary:
	if not entities.has(entity_id): return {"ok":false,"position":Vector2i(-1,-1)}
	# Prefer a historical actor-position anchor and replay forward. Party
	# deployment/regroup/roster events are explicit teleport boundaries. A grouped
	# companion then shares the protagonist's move history until the next deploy,
	# so status events remain verifiable while the party explores as one token.
	var anchored := false
	var historical_cursor := Vector2i(-1, -1)
	var actor_position_types := ["action.freeze", "action.wait", "encounter.actor_escaped"]
	var protagonist_id := int(party_encounter.protagonist_id) \
		if party_encounter != null else -1
	var tracks_grouped_protagonist: bool = protagonist_id > 0 and entity_id != protagonist_id \
		and party_encounter.member_rows.has(entity_id)
	var grouped_with_protagonist := false
	for event in events:
		if event.id >= event_id: break
		if tracks_grouped_protagonist and event.target_id == entity_id \
				and event.type in ["party.companion_recruited", "party.companion_dismissed"]:
			if event.type == "party.companion_recruited":
				historical_cursor = event.position
				anchored = true
				grouped_with_protagonist = true
			else:
				grouped_with_protagonist = false
			continue
		if grouped_with_protagonist and event.type == "action.move" \
				and event.actor_id == protagonist_id:
			var grouped_move := _canonical_move_positions(event)
			if not bool(grouped_move.get("ok", false)) \
					or (anchored and historical_cursor != grouped_move.from):
				return {"ok":false,"position":Vector2i(-1,-1)}
			historical_cursor = grouped_move.to
			anchored = true
			continue
		if event.actor_id != entity_id: continue
		if event.type == "action.move":
			if not _exact_keys(event.data, ["from_position", "move_time_cost", "terrain_id", "to_position"]) \
					or not _is_position(event.data.get("from_position"), width, height, false) \
					or not _is_position(event.data.get("to_position"), width, height, false):
				return {"ok":false,"position":Vector2i(-1,-1)}
			var from_position := Vector2i(int(event.data.from_position[0]), int(event.data.from_position[1]))
			var to_position := Vector2i(int(event.data.to_position[0]), int(event.data.to_position[1]))
			if event.position != to_position or (anchored and historical_cursor != from_position):
				return {"ok":false,"position":Vector2i(-1,-1)}
			historical_cursor = to_position
			anchored = true
		elif event.type in ["party.member_deployed", "party.member_regrouped",
				"party.deployment_completed"]:
			historical_cursor = event.position
			anchored = true
			if tracks_grouped_protagonist:
				grouped_with_protagonist = event.type == "party.member_regrouped"
		elif event.type in actor_position_types:
			if anchored and historical_cursor != event.position:
				return {"ok":false,"position":Vector2i(-1,-1)}
			historical_cursor = event.position
			anchored = true
	if anchored:
		return {"ok":true,"position":historical_cursor}
	var cursor: Vector2i = entities[entity_id].position
	for index in range(events.size() - 1, -1, -1):
		var event = events[index]
		if event.id <= event_id: break
		if event.type != "action.move" or event.actor_id != entity_id: continue
		if not _exact_keys(event.data, ["from_position", "move_time_cost", "terrain_id", "to_position"]) \
				or not _is_position(event.data.get("from_position"), width, height, false) \
				or not _is_position(event.data.get("to_position"), width, height, false):
			return {"ok":false,"position":Vector2i(-1,-1)}
		var from_position := Vector2i(int(event.data.from_position[0]), int(event.data.from_position[1]))
		var to_position := Vector2i(int(event.data.to_position[0]), int(event.data.to_position[1]))
		if event.position != to_position or to_position != cursor:
			return {"ok":false,"position":Vector2i(-1,-1)}
		cursor = from_position
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
	if formation_id == "WEDGE":
		return back+left if index == 0 else (back+right if index == 1 else back*index)
	if formation_id == "LINE":
		return left if index == 0 else (right if index == 1 else back*(index-1))
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
