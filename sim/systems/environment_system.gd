class_name EnvironmentSystem
extends RefCounted

const ENVIRONMENT_INTERVAL := 100
const CONDUCTION_THRESHOLD := 25
const ELECTRIC_POWER_LOSS_PER_TILE := 8
const EnvironmentRulesScript = preload("res://sim/environment_rules.gd")
const Config = preload("res://sim/environment_config.gd")
const Materials = preload("res://sim/material_registry.gd")
const Terrain = preload("res://sim/terrain_registry.gd")
const FIRE_DECAY_PER_ENVIRONMENT_TICK := EnvironmentRulesScript.FIRE_DECAY_PER_ENVIRONMENT_TICK
const WETNESS_DECAY_PER_ENVIRONMENT_TICK := EnvironmentRulesScript.WETNESS_DECAY_PER_ENVIRONMENT_TICK
const FIRE_DAMAGE_CAP_PER_ENVIRONMENT_TICK := EnvironmentRulesScript.FIRE_DAMAGE_CAP_PER_ENVIRONMENT_TICK

var world
var damage_system


func _init(p_world, p_damage_system) -> void:
	world = p_world
	damage_system = p_damage_system


func ignite(position: Vector2i, power: int, cause_id: int,
		processed_step_index: int) -> bool:
	if power < 1 or power > 100 or not _processed_step_matches(processed_step_index):
		return false
	return try_ignite(position, power, cause_id, processed_step_index,
		"environment.ignited")


func try_ignite(position: Vector2i, power: int, cause_id: int,
		processed_step_index: int,
		success_event_type: String = "environment.ignited",
		from_position: Vector2i = Vector2i(-1, -1)) -> bool:
	if success_event_type != "environment.ignited" \
			and success_event_type != "environment.fire_spread" \
			or not _processed_step_matches(processed_step_index):
		return false
	var tile = world.tile_at(position)
	var preview := _preview_ignite(tile, power)
	if preview["reason"] == "nonflammable" or preview["reason"] == "already_burning":
		world.emit_event(
			"environment.ignition_failed", -1, -1, position, power, cause_id,
			{"reason": preview["reason"], "from_position": [from_position.x, from_position.y]}
		)
		return false
	var evaporation = null
	var evaporated: int = preview["evaporated"]
	if evaporated > 0:
		tile.wetness -= evaporated
		if tile.surface_id == "WATER":
			tile.surface_amount = maxi(0, tile.surface_amount - evaporated * 10)
			if tile.surface_amount == 0: tile.surface_id = "NONE"
		evaporation = world.emit_event(
			"environment.wetness_evaporated", -1, -1, position, evaporated, cause_id,
			{"from_position": [from_position.x, from_position.y]}
		)
		if tile.wetness == 0:
			tile.wetness_source_event_id = -1
		world.track_dynamic_tile(position)
	if preview["reason"] == "wet":
		world.emit_event(
			"environment.ignition_failed", -1, -1, position, power, evaporation.id,
			{"reason": "wet", "from_position": [from_position.x, from_position.y]}
		)
		return false
	var fire_power: int = preview["resulting_fire"]
	var event = world.emit_event(
		success_event_type, -1, -1, position, fire_power, cause_id,
		{"from_position": [from_position.x, from_position.y]}
	)
	tile.fire = fire_power
	tile.fire_source_event_id = event.id
	assert(success_event_type != "environment.fire_spread"
		or world.world_time <= 9223372036854775807 - ENVIRONMENT_INTERVAL,
		"Fire eligibility time overflow")
	tile.fire_damage_eligible_time = (
		world.world_time + ENVIRONMENT_INTERVAL
		if success_event_type == "environment.fire_spread"
		else world.world_time
	)
	world.track_dynamic_tile(position)
	return true


func _preview_ignite(tile, power: int) -> Dictionary:
	var effective_flammability: int = maxi(tile.flammability,
		90 if tile.surface_id == "OIL" and tile.surface_amount > 0 else 0)
	if tile.flammable_gas_amount >= Config.FLAMMABLE_GAS_IGNITION:
		effective_flammability = maxi(effective_flammability, 100)
	var combustible: bool = effective_flammability > 0 and (tile.fuel_amount > 0 \
		or Materials.initial_fuel(tile.material_id) == 0) \
		or tile.surface_id == "OIL" and tile.surface_amount > 0 \
		or tile.flammable_gas_amount >= Config.FLAMMABLE_GAS_IGNITION
	if not combustible:
		return {"reason": "nonflammable", "evaporated": 0, "resulting_fire": 0}
	if tile.fire > 0:
		return {"reason": "already_burning", "evaporated": 0, "resulting_fire": 0}
	var applied_power := clampi(power, 1, 100)
	var evaporated := mini(applied_power, tile.wetness)
	var remaining_power := applied_power - evaporated
	if remaining_power <= 0:
		return {"reason": "wet", "evaporated": evaporated, "resulting_fire": 0}
	return {"reason": "", "evaporated": evaporated,
		"resulting_fire": mini(remaining_power, effective_flammability)}


func apply_water(position: Vector2i, amount: int, cause_id: int,
		processed_step_index: int) -> bool:
	if amount < 1 or amount > 100 or not _processed_step_matches(processed_step_index):
		return false
	var tile = world.tile_at(position)
	var actual_increase := mini(amount, 100 - tile.wetness)
	var water_event = world.emit_event(
		"environment.water_applied", -1, -1, position, actual_increase, cause_id,
		{"requested_amount": amount}
	)
	if actual_increase > 0:
		tile.wetness += actual_increase
		tile.wetness_source_event_id = water_event.id
	world.track_dynamic_tile(position)
	return true


func discharge(position: Vector2i, power: int, cause_id: int,
		processed_step_index: int) -> bool:
	if power < 1 or power > 100 or not _processed_step_matches(processed_step_index):
		return false
	var queue: Array[Dictionary] = [{
		"position": position, "distance": 0, "parent_id": cause_id,
		"from_position": Vector2i(-1, -1),
	}]
	var visited: Dictionary = {}
	var damage_requests: Array[Dictionary] = []
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		var current: Vector2i = item["position"]
		if visited.has(current):
			continue
		visited[current] = true
		var distance: int = item["distance"]
		var remaining_power := power - distance * ELECTRIC_POWER_LOSS_PER_TILE
		if remaining_power <= 0:
			continue
		var from_position: Vector2i = item["from_position"]
		var arc_event = world.emit_event(
			"environment.electric_arc", -1, -1, current, remaining_power,
			int(item["parent_id"]),
			{"distance": distance, "from_position": [from_position.x, from_position.y]}
		)
		for entity in world.exposed_entities_at(current):
			damage_requests.append({"entity": entity, "amount": remaining_power,
				"damage_type": "electric", "cause_id": arc_event.id})
		for neighbor in world.cardinal_neighbors(current):
			if not visited.has(neighbor) and world.tile_at(neighbor).effective_conductivity() >= CONDUCTION_THRESHOLD:
				queue.append({"position": neighbor, "distance": distance + 1,
					"parent_id": arc_event.id, "from_position": current})
	_apply_damage_requests(damage_requests, processed_step_index)
	return true


func process_tick(processed_step_index: int) -> bool:
	if processed_step_index <= 0 or world._active_step_index != processed_step_index:
		return false
	_process_passive_environment(processed_step_index)
	var burning_positions: Array[Vector2i] = []
	for position in world.dynamic_tile_positions():
		if world.tile_at(position).fire > 0: burning_positions.append(position)
	for position in burning_positions:
		_tick_existing_fire(position)
	_apply_spread_candidates(_collect_spread_candidates(burning_positions), processed_step_index)
	var fire_damage_requests: Array[Dictionary] = []
	for position in world.dynamic_tile_positions():
		var tile = world.tile_at(position)
		if tile.fire <= 0 or tile.fire_damage_eligible_time < 0 \
				or world.world_time < tile.fire_damage_eligible_time:
			continue
		for entity in world.exposed_entities_at(position):
			fire_damage_requests.append({"entity": entity,
				"amount": mini(FIRE_DAMAGE_CAP_PER_ENVIRONMENT_TICK, tile.fire),
				"damage_type": "fire", "cause_id": tile.fire_source_event_id})
	_apply_damage_requests(fire_damage_requests, processed_step_index)
	_decay_wetness()
	return true


func apply_heat(position: Vector2i, amount: int, cause_id: int,
		processed_step_index: int) -> bool:
	if not world.in_bounds(position) or amount <= 0 \
			or not _processed_step_matches(processed_step_index): return false
	var tile = world.tile_at(position)
	var applied := mini(amount, Config.MAX_TEMPERATURE - tile.temperature)
	var event = world.emit_event("environment.heat_applied", -1, -1, position,
		applied, cause_id)
	if event == null: return false
	tile.temperature += applied
	world.track_dynamic_tile(position)
	if tile.fire == 0:
		var material: Dictionary = Materials.definition(tile.material_id)
		if tile.temperature >= int(material.get("ignition_temperature", Config.MAX_TEMPERATURE)) \
				or tile.surface_id == "OIL" and tile.temperature >= 500:
			try_ignite(position, mini(100, maxi(1, amount / 10)), event.id,
				processed_step_index)
	return true


func explode(position: Vector2i, power: int, cause_id: int,
		processed_step_index: int, explosion_kind: String = "combustion") -> bool:
	if not world.in_bounds(position) or power < 1 or power > 100 \
			or explosion_kind not in ["combustion", "rupture"] \
			or not _processed_step_matches(processed_step_index): return false
	var root = world.emit_event("environment.explosion", -1, -1, position, power,
		cause_id, {"kind": explosion_kind})
	if root == null: return false
	var queue: Array[Dictionary] = [{"position": position, "power": power,
		"distance": 0, "parent_id": root.id}]
	var best_power: Dictionary = {}
	var processed := 0
	while not queue.is_empty() and processed < Config.MAX_EXPLOSION_CHAIN:
		var row: Dictionary = queue.pop_front()
		var current: Vector2i = row.position
		var remaining: int = row.power
		if remaining <= int(best_power.get(current, 0)): continue
		best_power[current] = remaining; processed += 1
		var wave = world.emit_event("environment.explosion_wave", -1, -1,
			current, remaining, int(row.parent_id), {"kind": explosion_kind,
				"distance": int(row.distance)})
		if wave == null: return false
		var tile = world.tile_at(current)
		tile.temperature = mini(Config.MAX_TEMPERATURE,
			tile.temperature + remaining * (2 if explosion_kind == "combustion" else 1))
		world.track_dynamic_tile(current)
		if explosion_kind == "combustion":
			for entity in world.exposed_entities_at(current):
				damage_system.apply_damage(entity,
					mini(FIRE_DAMAGE_CAP_PER_ENVIRONMENT_TICK, remaining), "fire",
					wave.id, current, processed_step_index)
		for neighbor in world.cardinal_neighbors(current):
			var terrain: Dictionary = Terrain.definition(world.tile_at(neighbor).terrain)
			var cover_loss := Config.COVER_POWER_LOSS if not bool(terrain.get("passable", false)) else 0
			var next_power := remaining - Config.EXPLOSION_POWER_LOSS_PER_TILE - cover_loss
			if next_power > int(best_power.get(neighbor, 0)):
				queue.append({"position": neighbor, "power": next_power,
					"distance": int(row.distance) + 1, "parent_id": wave.id})
	if processed >= Config.MAX_EXPLOSION_CHAIN and not queue.is_empty():
		world.emit_event("environment.explosion_chain_stopped", -1, -1,
			position, processed, root.id)
	return true


func _process_passive_environment(processed_step_index: int) -> void:
	var positions: Array[Vector2i] = world.dynamic_tile_positions()
	var included: Dictionary = {}
	for position in positions:
		included[position] = true
		for neighbor in world.cardinal_neighbors(position): included[neighbor] = true
	positions.assign(included.keys())
	positions.sort_custom(func(a: Vector2i, b: Vector2i):
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var temperature_delta: Dictionary = {}
	var gas_deltas: Dictionary = {}
	for position in positions:
		temperature_delta[position] = 0
		gas_deltas[position] = [0, 0, 0, 0]
	for position in positions:
		var tile = world.tile_at(position)
		for neighbor in [position + Vector2i.RIGHT, position + Vector2i.DOWN]:
			if not world.in_bounds(neighbor) or not included.has(neighbor): continue
			var other = world.tile_at(neighbor)
			var a_material: Dictionary = Materials.definition(tile.material_id)
			var b_material: Dictionary = Materials.definition(other.material_id)
			var conductivity := mini(int(a_material.thermal_conductivity),
				int(b_material.thermal_conductivity))
			var energy: int = (tile.temperature - other.temperature) * conductivity \
				/ Config.HEAT_FLOW_DIVISOR
			temperature_delta[position] -= energy / maxi(1, int(a_material.heat_capacity))
			temperature_delta[neighbor] += energy / maxi(1, int(b_material.heat_capacity))
			if _gas_connection_open(position, neighbor):
				for component in range(4):
					var difference := _gas_component(tile, component) \
						- _gas_component(other, component)
					var transfer := difference / Config.FLOW_DIVISOR
					gas_deltas[position][component] -= transfer
					gas_deltas[neighbor][component] += transfer
	for position in positions:
		var tile = world.tile_at(position)
		tile.temperature = clampi(tile.temperature + int(temperature_delta[position]),
			-1000, Config.MAX_TEMPERATURE)
		var delta: Array = gas_deltas[position]
		tile.gas_amount = clampi(tile.gas_amount + int(delta[0]), 0, Config.MAX_MASS)
		tile.smoke_amount = clampi(tile.smoke_amount + int(delta[1]), 0, Config.MAX_MASS)
		tile.steam_amount = clampi(tile.steam_amount + int(delta[2]), 0, Config.MAX_MASS)
		tile.flammable_gas_amount = clampi(tile.flammable_gas_amount + int(delta[3]), 0, Config.MAX_MASS)
		_apply_open_boundary_loss(position, tile)
		_apply_phase_change(position, tile)
		_apply_combustion(position, tile)
		if tile.sealed and tile.pressure() > Config.RUPTURE_PRESSURE:
			var rupture = world.emit_event("environment.container_ruptured", -1, -1,
				position, mini(100, tile.pressure() / 20), -1,
				{"pressure": tile.pressure()})
			tile.sealed = false
			explode(position, mini(100, maxi(1, tile.pressure() / 20)),
				rupture.id, processed_step_index, "rupture")
		if tile.fire > 0 and tile.flammable_gas_amount >= Config.FLAMMABLE_GAS_IGNITION:
			var consumed := mini(tile.flammable_gas_amount, tile.fire * 4)
			tile.flammable_gas_amount -= consumed
			explode(position, mini(100, maxi(1, consumed / 4)),
				tile.fire_source_event_id, processed_step_index, "combustion")
		world.track_dynamic_tile(position)


func _apply_phase_change(position: Vector2i, tile) -> void:
	if tile.surface_id == "WATER" and tile.temperature <= Config.FREEZING_TEMPERATURE:
		tile.surface_id = "ICE"; tile.wetness = 0; tile.wetness_source_event_id = -1
		world.emit_event("environment.water_frozen", -1, -1, position,
			tile.surface_amount, -1)
	elif tile.surface_id == "ICE" and tile.temperature >= Config.MELTING_TEMPERATURE:
		tile.surface_id = "WATER"; tile.wetness = mini(100, tile.surface_amount / 10)
		var event = world.emit_event("environment.ice_melted", -1, -1, position,
			tile.surface_amount, -1)
		tile.wetness_source_event_id = event.id if tile.wetness > 0 else -1
	if tile.surface_id == "WATER" and tile.temperature >= Config.BOILING_TEMPERATURE:
		var amount := mini(Config.PHASE_CHANGE_RATE, tile.surface_amount)
		tile.surface_amount -= amount; tile.steam_amount = mini(Config.MAX_MASS,
			tile.steam_amount + amount)
		tile.wetness = mini(100, tile.surface_amount / 10)
		if tile.surface_amount == 0:
			tile.surface_id = "NONE"; tile.wetness_source_event_id = -1
		world.emit_event("environment.water_evaporated", -1, -1, position, amount, -1)
	elif tile.steam_amount > 0 and tile.temperature <= Config.CONDENSATION_TEMPERATURE \
			and tile.surface_id in ["NONE", "WATER"]:
		var amount := mini(Config.PHASE_CHANGE_RATE, tile.steam_amount)
		tile.steam_amount -= amount; tile.surface_id = "WATER"
		tile.surface_amount = mini(Config.MAX_MASS, tile.surface_amount + amount)
		tile.wetness = mini(100, tile.surface_amount / 10)
		var event = world.emit_event("environment.steam_condensed", -1, -1,
			position, amount, -1)
		tile.wetness_source_event_id = event.id if tile.wetness > 0 else -1


func _apply_combustion(position: Vector2i, tile) -> void:
	if tile.fire <= 0: return
	var consumed := 0
	var fuel_kind: String = tile.material_id
	if tile.surface_id == "OIL":
		fuel_kind = "OIL"
		consumed = mini(Config.OIL_BURN_RATE, tile.surface_amount)
		tile.surface_amount -= consumed
		if tile.surface_amount == 0: tile.surface_id = "NONE"
	elif tile.fuel_amount > 0:
		consumed = mini(tile.fuel_amount,
			maxi(1, tile.fire / Config.FIRE_FUEL_USE_DIVISOR))
		tile.fuel_amount -= consumed
	if consumed > 0:
		tile.temperature = mini(Config.MAX_TEMPERATURE,
			tile.temperature + tile.fire * Config.FIRE_HEAT_PER_INTENSITY)
		tile.smoke_amount = mini(Config.MAX_MASS,
			tile.smoke_amount + consumed * Config.SMOKE_PER_FUEL)
		world.emit_event("environment.fuel_consumed", -1, -1, position,
			consumed, tile.fire_source_event_id,
			{"fuel_kind": fuel_kind})


func _gas_connection_open(a: Vector2i, b: Vector2i) -> bool:
	var first = world.tile_at(a); var second = world.tile_at(b)
	if first.sealed or second.sealed: return false
	return first.terrain not in ["wall", "door_closed"] \
		and second.terrain not in ["wall", "door_closed"]


func _gas_component(tile, component: int) -> int:
	return [tile.gas_amount, tile.smoke_amount, tile.steam_amount,
		tile.flammable_gas_amount][component]


func _apply_open_boundary_loss(position: Vector2i, tile) -> void:
	if tile.sealed or tile.terrain in ["wall", "door_closed"]: return
	if position.x > 0 and position.y > 0 and position.x < world.width - 1 \
			and position.y < world.height - 1: return
	for property in ["smoke_amount", "steam_amount", "flammable_gas_amount"]:
		var amount: int = tile.get(property)
		tile.set(property, maxi(0, amount - mini(Config.GAS_LOSS_AT_OPEN_EDGE,
			maxi(1, amount / Config.FLOW_DIVISOR))))
	tile.gas_amount += (Config.DEFAULT_GAS_AMOUNT - tile.gas_amount) / Config.FLOW_DIVISOR
	tile.temperature += (Config.AMBIENT_TEMPERATURE - tile.temperature) \
		/ Config.HEAT_LOSS_AT_OPEN_EDGE


func _tick_existing_fire(position: Vector2i) -> void:
	var tile = world.tile_at(position)
	if tile.fire <= 0:
		return
	var projection: Dictionary = EnvironmentRulesScript.project_existing_fire_tick(
		tile.fire, tile.wetness, tile.fire_damage_eligible_time, world.world_time)
	var suppression: int = projection["suppression"]
	if suppression > 0:
		tile.fire = projection["fire_after_suppression"]
		tile.wetness = projection["wetness_after_suppression"]
		if tile.surface_id == "WATER":
			tile.surface_amount = maxi(0, tile.surface_amount - suppression * 10)
			if tile.surface_amount == 0: tile.surface_id = "NONE"
		var event_type := "environment.fire_extinguished" if tile.fire == 0 else "environment.fire_weakened"
		world.emit_event(event_type, -1, -1, position, suppression, tile.wetness_source_event_id)
		if tile.wetness == 0:
			tile.wetness_source_event_id = -1
		if tile.fire == 0:
			_clear_fire(tile)
			world.track_dynamic_tile(position)
			return
	tile.fire = projection["fire_after_decay"]
	if tile.fire == 0:
		world.emit_event("environment.fire_burned_out", -1, -1, position, 0, tile.fire_source_event_id)
		_clear_fire(tile)
	world.track_dynamic_tile(position)


func _clear_fire(tile) -> void:
	tile.fire = 0
	tile.fire_source_event_id = -1
	tile.fire_damage_eligible_time = -1


func _collect_spread_candidates(burning_positions: Array[Vector2i]) -> Dictionary:
	var by_target: Dictionary = {}
	for source in burning_positions:
		var source_tile = world.tile_at(source)
		if source_tile.fire <= 0:
			continue
		for target in world.cardinal_neighbors(source):
			var target_tile = world.tile_at(target)
			if target_tile.fire > 0 or target_tile.flammability <= 0:
				continue
			var ignition_preview := _preview_ignite(target_tile, source_tile.fire)
			var chance := clampi(source_tile.fire * target_tile.flammability / 100, 0, 95)
			if not by_target.has(target):
				by_target[target] = []
			by_target[target].append({"source": source, "power": source_tile.fire,
				"resulting_fire": ignition_preview["resulting_fire"], "chance": chance,
				"cause_id": source_tile.fire_source_event_id})
	return by_target


func _apply_spread_candidates(by_target: Dictionary, processed_step_index: int) -> void:
	var targets: Array = by_target.keys()
	targets.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for target in targets:
		var candidates: Array = by_target[target]
		candidates.sort_custom(func(a: Dictionary, b: Dictionary):
			if a["resulting_fire"] != b["resulting_fire"]:
				return a["resulting_fire"] > b["resulting_fire"]
			if a["power"] != b["power"]:
				return a["power"] > b["power"]
			var ap: Vector2i = a["source"]
			var bp: Vector2i = b["source"]
			return ap.y < bp.y or (ap.y == bp.y and ap.x < bp.x))
		var winner: Dictionary = candidates[0]
		if world.rng.randi_range(1, 100) <= int(winner["chance"]):
			try_ignite(target, int(winner["power"]), int(winner["cause_id"]),
				processed_step_index, "environment.fire_spread", winner["source"])


func _apply_damage_requests(requests: Array[Dictionary], processed_step_index: int) -> void:
	for request in requests:
		damage_system.apply_damage(request["entity"], int(request["amount"]),
			str(request["damage_type"]), int(request["cause_id"]),
			request["entity"].position, processed_step_index)


func _processed_step_matches(processed_step_index: int) -> bool:
	return processed_step_index > 0 and processed_step_index == world._active_step_index


func _decay_wetness() -> void:
	for position in world.dynamic_tile_positions():
		var tile = world.tile_at(position)
		if tile.wetness <= 0:
			continue
		if tile.surface_id == "WATER" and tile.surface_amount > 0:
			tile.wetness = mini(100, tile.surface_amount / 10)
			if tile.wetness == 0: tile.wetness_source_event_id = -1
			world.track_dynamic_tile(position)
			continue
		tile.wetness = maxi(0, tile.wetness - WETNESS_DECAY_PER_ENVIRONMENT_TICK)
		if tile.wetness == 0:
			tile.wetness_source_event_id = -1
		world.track_dynamic_tile(position)
