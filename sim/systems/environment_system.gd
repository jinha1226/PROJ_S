class_name EnvironmentSystem
extends RefCounted

const ENVIRONMENT_INTERVAL := 100
const CONDUCTION_THRESHOLD := 25
const ELECTRIC_POWER_LOSS_PER_TILE := 8
const EnvironmentRulesScript = preload("res://sim/environment_rules.gd")
const FIRE_DECAY_PER_ENVIRONMENT_TICK := EnvironmentRulesScript.FIRE_DECAY_PER_ENVIRONMENT_TICK
const WETNESS_DECAY_PER_ENVIRONMENT_TICK := EnvironmentRulesScript.WETNESS_DECAY_PER_ENVIRONMENT_TICK
const FIRE_DAMAGE_CAP_PER_ENVIRONMENT_TICK := EnvironmentRulesScript.FIRE_DAMAGE_CAP_PER_ENVIRONMENT_TICK

var world
var damage_system


func _init(p_world, p_damage_system) -> void:
	world = p_world
	damage_system = p_damage_system


func ignite(position: Vector2i, power: int, cause_id: int) -> bool:
	if power < 1 or power > 100:
		return false
	return try_ignite(position, power, cause_id, "environment.ignited")


func try_ignite(position: Vector2i, power: int, cause_id: int,
		success_event_type: String = "environment.ignited",
		from_position: Vector2i = Vector2i(-1, -1)) -> bool:
	if success_event_type != "environment.ignited" \
			and success_event_type != "environment.fire_spread":
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
		evaporation = world.emit_event(
			"environment.wetness_evaporated", -1, -1, position, evaporated, cause_id,
			{"from_position": [from_position.x, from_position.y]}
		)
		if tile.wetness == 0:
			tile.wetness_source_event_id = -1
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
	return true


func _preview_ignite(tile, power: int) -> Dictionary:
	if tile.flammability <= 0:
		return {"reason": "nonflammable", "evaporated": 0, "resulting_fire": 0}
	if tile.fire > 0:
		return {"reason": "already_burning", "evaporated": 0, "resulting_fire": 0}
	var applied_power := clampi(power, 1, 100)
	var evaporated := mini(applied_power, tile.wetness)
	var remaining_power := applied_power - evaporated
	if remaining_power <= 0:
		return {"reason": "wet", "evaporated": evaporated, "resulting_fire": 0}
	return {"reason": "", "evaporated": evaporated,
		"resulting_fire": mini(remaining_power, tile.flammability)}


func apply_water(position: Vector2i, amount: int, cause_id: int) -> bool:
	if amount < 1 or amount > 100:
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
	return true


func discharge(position: Vector2i, power: int, cause_id: int) -> bool:
	if power < 1 or power > 100:
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
		for entity in world.entities_at(current):
			damage_requests.append({"entity": entity, "amount": remaining_power,
				"damage_type": "electric", "cause_id": arc_event.id})
		for neighbor in world.cardinal_neighbors(current):
			if not visited.has(neighbor) and world.tile_at(neighbor).effective_conductivity() >= CONDUCTION_THRESHOLD:
				queue.append({"position": neighbor, "distance": distance + 1,
					"parent_id": arc_event.id, "from_position": current})
	_apply_damage_requests(damage_requests)
	return true


func process_tick() -> void:
	var burning_positions: Array[Vector2i] = []
	for y in range(world.height):
		for x in range(world.width):
			var position := Vector2i(x, y)
			if world.tile_at(position).fire > 0:
				burning_positions.append(position)
	for position in burning_positions:
		_tick_existing_fire(position)
	_apply_spread_candidates(_collect_spread_candidates(burning_positions))
	var fire_damage_requests: Array[Dictionary] = []
	for y in range(world.height):
		for x in range(world.width):
			var position := Vector2i(x, y)
			var tile = world.tile_at(position)
			if tile.fire <= 0 or tile.fire_damage_eligible_time < 0 \
					or world.world_time < tile.fire_damage_eligible_time:
				continue
			for entity in world.entities_at(position):
				fire_damage_requests.append({"entity": entity,
					"amount": mini(FIRE_DAMAGE_CAP_PER_ENVIRONMENT_TICK, tile.fire),
					"damage_type": "fire", "cause_id": tile.fire_source_event_id})
	_apply_damage_requests(fire_damage_requests)
	_decay_wetness()


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
		var event_type := "environment.fire_extinguished" if tile.fire == 0 else "environment.fire_weakened"
		world.emit_event(event_type, -1, -1, position, suppression, tile.wetness_source_event_id)
		if tile.wetness == 0:
			tile.wetness_source_event_id = -1
		if tile.fire == 0:
			_clear_fire(tile)
			return
	tile.fire = projection["fire_after_decay"]
	if tile.fire == 0:
		world.emit_event("environment.fire_burned_out", -1, -1, position, 0, tile.fire_source_event_id)
		_clear_fire(tile)


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


func _apply_spread_candidates(by_target: Dictionary) -> void:
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
				"environment.fire_spread", winner["source"])


func _apply_damage_requests(requests: Array[Dictionary]) -> void:
	for request in requests:
		damage_system.apply_damage(request["entity"], int(request["amount"]),
			str(request["damage_type"]), int(request["cause_id"]))


func _decay_wetness() -> void:
	for tile in world.tiles:
		if tile.wetness <= 0:
			continue
		tile.wetness = maxi(0, tile.wetness - WETNESS_DECAY_PER_ENVIRONMENT_TICK)
		if tile.wetness == 0:
			tile.wetness_source_event_id = -1
