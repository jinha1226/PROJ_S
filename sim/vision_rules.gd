class_name VisionRules
extends RefCounted

const RULESET_ID := "shared-vision-v1"
const Profiles = preload("res://sim/vision_profile_registry.gd")
const Terrain = preload("res://sim/terrain_registry.gd")

const BRIGHT_THRESHOLD := 700
const DIM_THRESHOLD := 300
const DEFAULT_AMBIENT := 900
const DARK_AMBIENT := 120
const MAX_LIGHT := 1000
const LIGHT_SOURCE_KEYS := ["position", "brightness", "radius"]
const LIGHTING_TEST_SCENARIO_ID := "VISION_TEST_LIGHTING_V1"
const TorchRulesScript = preload("res://sim/torch_rules.gd")


static func observe(world, observer_position: Vector2i, target_position: Vector2i,
		observer_facing: Vector2i, profile: Dictionary,
		lighting: Dictionary = {}) -> Dictionary:
	var rejected := {"visible": false, "identified": false, "reason": "invalid_vision_input"}
	if world == null or not world.in_bounds(observer_position) \
			or not world.in_bounds(target_position) or profile.is_empty():
		return rejected
	var distance := _distance(observer_position, target_position)
	var observer_light := illumination(world, observer_position, lighting)
	var target_light := illumination(world, target_position, lighting)
	var los := _has_line_of_sight(world, observer_position, target_position)
	var direction := _direction(observer_position, target_position)
	var bright_observer := observer_light >= BRIGHT_THRESHOLD
	var bright_target := target_light >= BRIGHT_THRESHOLD
	var range_milli := _effective_range_milli(profile, maxi(observer_light, target_light))
	var in_range := distance * 1000 <= range_milli
	var directional := bright_observer or bright_target \
		or distance == 0 or _within_front_cone(observer_facing, direction,
			int(profile.dark_front_angle))
	var allowed_distance := int(profile.peripheral_range) if not directional else \
		maxi(int(profile.peripheral_range), int(profile.base_sight_range) \
			* maxi(int(profile.dark_vision_milli), _light_factor(observer_light)) / 1000)
	var visible := los and in_range and (directional or distance <= allowed_distance)
	var strength := _identification_strength(profile, observer_light, target_light,
		distance, directional, los)
	var identified := visible and strength >= 500
	return {"visible": visible, "identified": identified,
		"reason": "" if visible else ("blocked" if not los else "out_of_view"),
		"distance": distance, "direction": [direction.x, direction.y],
		"observer_illumination": observer_light, "target_illumination": target_light,
		"observer_light_band": light_band(observer_light),
		"target_light_band": light_band(target_light),
		"directional": directional, "identification_strength": strength}.duplicate(true)


static func visible_cells(world, observer_position: Vector2i, observer_facing: Vector2i,
		profile: Dictionary, lighting: Dictionary = {}) -> Dictionary:
	var cells: Dictionary = {}
	if world == null or profile.is_empty() or not world.in_bounds(observer_position):
		return cells
	var range := int(profile.base_sight_range)
	for y in range(maxi(0, observer_position.y - range),
			mini(world.height, observer_position.y + range + 1)):
		for x in range(maxi(0, observer_position.x - range),
				mini(world.width, observer_position.x + range + 1)):
			var target := Vector2i(x, y)
			var result := observe(world, observer_position, target, observer_facing,
				profile, lighting)
			if bool(result.visible):
				cells["%d:%d" % [x, y]] = true
	return cells


static func has_line_of_sight(world, origin: Vector2i, target: Vector2i) -> bool:
	return world != null and world.in_bounds(origin) and world.in_bounds(target) \
		and _has_line_of_sight(world, origin, target)


static func profile_for_entity(entity) -> Dictionary:
	return Profiles.profile_for_entity(entity)


static func profile_for(species_id: String, monster_type: String = "") -> Dictionary:
	return Profiles.profile_for(species_id, monster_type)


static func illumination(world, position: Vector2i, lighting: Dictionary = {}) -> int:
	if world == null or not world.in_bounds(position):
		return 0
	var ambient := clampi(int(lighting.get("ambient_level", DEFAULT_AMBIENT)), 0, MAX_LIGHT)
	var result := ambient
	for source_value in lighting.get("sources", []):
		if not source_value is Dictionary:
			continue
		var source: Dictionary = source_value
		var source_position := _position(source.get("position", []))
		if source_position == Vector2i(-1, -1) or not world.in_bounds(source_position):
			continue
		var radius := maxi(1, int(source.get("radius", 4)))
		var distance := _distance(source_position, position)
		if distance > radius or not _has_line_of_sight(world, source_position, position):
			continue
		var brightness := clampi(int(source.get("brightness", MAX_LIGHT)), 0, MAX_LIGHT)
		result = maxi(result, brightness * (radius - distance + 1) / (radius + 1))
	if world.tile_at(position).fire > 0:
		result = maxi(result, clampi(600 + int(world.tile_at(position).fire) * 4, 0, MAX_LIGHT))
	return clampi(result, 0, MAX_LIGHT)


static func lighting_for_scenario(scenario_id: String) -> Dictionary:
	if scenario_id == LIGHTING_TEST_SCENARIO_ID:
		return {"ambient_level": DARK_AMBIENT, "sources": [
			{"position": [4, 2], "brightness": 1000, "radius": 3},
		]}.duplicate(true)
	return {"ambient_level": DEFAULT_AMBIENT, "sources": []}


static func lighting_for_world(world, scenario_id: String = "") -> Dictionary:
	var resolved := scenario_id
	if resolved.is_empty() and world != null:
		resolved = str(world.vision_scenario_id)
	var result := lighting_for_scenario(resolved)
	if world != null:
		result["sources"] = TorchRulesScript.active_light_sources(world)
	return result.duplicate(true)


static func light_band(value: int) -> String:
	return "BRIGHT" if value >= BRIGHT_THRESHOLD else ("DIM" if value >= DIM_THRESHOLD else "DARK")


static func facing_for_entity(world, entity_id: int, fallback: Vector2i = Vector2i.RIGHT) -> Vector2i:
	if world == null or not world.entities.has(entity_id):
		return fallback if fallback != Vector2i.ZERO else Vector2i.RIGHT
	for index in range(world.events.size() - 1, -1, -1):
		var event = world.events[index]
		if int(event.actor_id) != entity_id or event.type != "action.move":
			continue
		var from := _position(event.data.get("from_position", []))
		var to := _position(event.data.get("to_position", []))
		var delta := to - from
		if delta != Vector2i.ZERO:
			return Vector2i(signi(delta.x), signi(delta.y))
	return fallback if fallback != Vector2i.ZERO else Vector2i.RIGHT


static func _effective_range_milli(profile: Dictionary, light: int) -> int:
	if light >= BRIGHT_THRESHOLD:
		return int(profile.base_sight_range) * 1000
	var factor := maxi(int(profile.dark_vision_milli), _light_factor(light))
	return maxi(int(profile.peripheral_range) * 1000,
		int(profile.base_sight_range) * factor)


static func _light_factor(light: int) -> int:
	return clampi(light * 1000 / BRIGHT_THRESHOLD, 0, 1000)


static func _identification_strength(profile: Dictionary, observer_light: int,
		target_light: int, distance: int, directional: bool, los: bool) -> int:
	if not los:
		return 0
	var distance_factor := maxi(0, 1000 - distance * 1000 / maxi(1, int(profile.base_sight_range)))
	var light_factor := maxi(_light_factor(observer_light), _light_factor(target_light))
	var direction_factor := 1000 if directional else int(profile.detection_sensitivity_milli) / 2
	return clampi(distance_factor * maxi(light_factor, int(profile.detection_sensitivity_milli)) \
		* direction_factor / 1000000, 0, 1000)


static func _within_front_cone(facing: Vector2i, direction: Vector2i, angle: int) -> bool:
	if direction == Vector2i.ZERO:
		return true
	if facing == Vector2i.ZERO:
		facing = Vector2i.RIGHT
	var dot := facing.x * direction.x + facing.y * direction.y
	var facing_length := maxi(1, maxi(absi(facing.x), absi(facing.y)))
	var direction_length := maxi(1, maxi(absi(direction.x), absi(direction.y)))
	var cosine_milli := dot * 1000 / (facing_length * direction_length)
	var threshold := 1000 if angle >= 180 else (707 if angle >= 45 else 0)
	if angle >= 135:
		threshold = -707
	elif angle >= 90:
		threshold = 0
	elif angle >= 45:
		threshold = 707
	return cosine_milli >= threshold


static func _has_line_of_sight(world, origin: Vector2i, target: Vector2i) -> bool:
	if origin == target:
		return true
	var x0 := origin.x
	var y0 := origin.y
	var dx := absi(target.x - x0)
	var sx := 1 if x0 < target.x else -1
	var dy := -absi(target.y - y0)
	var sy := 1 if y0 < target.y else -1
	var error := dx + dy
	while x0 != target.x or y0 != target.y:
		var doubled := 2 * error
		if doubled >= dy:
			error += dy; x0 += sx
		if doubled <= dx:
			error += dx; y0 += sy
		var position := Vector2i(x0, y0)
		if position == target:
			return true
		if int(world.tile_at(position).smoke_amount) >= 600:
			return false
		var terrain := Terrain.definition_view(str(world.tile_at(position).terrain))
		if terrain.is_empty() or not bool(terrain.get("passable", false)):
			return false
	return true


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func _direction(a: Vector2i, b: Vector2i) -> Vector2i:
	var delta := b - a
	return Vector2i(signi(delta.x), signi(delta.y))


static func _position(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)
