class_name EnemySquadBlackboard
extends RefCounted

const FixedPointScript = preload("res://sim/fixed_point.gd")
const PerceptionRegistryScript = preload("res://sim/enemy_perception_registry.gd")
const CLAIM_CAP := 2


static func build(world) -> Dictionary:
	var state = world.party_encounter
	var enemies := _active_enemies(world, state)
	var party := deployed_party_ids(world)
	var visible_targets := {}
	var target_pressure := {}
	for target_id in party:
		target_pressure[target_id] = {
			"adjacent_enemy_ids": [],
			"visible_enemy_ids": [],
			"hp_milli": _hp_milli(world, target_id),
		}
	for enemy_id in enemies:
		var visible: Array[int] = []
		var profile: Dictionary = PerceptionRegistryScript.profile(
			str(world.entities[enemy_id].species_id))
		if not profile.is_empty():
			for target_id in party:
				var distance := _distance(world.entities[enemy_id].position,
					world.entities[target_id].position)
				if distance <= int(profile.sight_range) and PerceptionRegistryScript \
						.has_line_of_sight(world, world.entities[enemy_id].position,
							world.entities[target_id].position):
					visible.append(target_id)
					target_pressure[target_id].visible_enemy_ids.append(enemy_id)
				if distance <= 1:
					target_pressure[target_id].adjacent_enemy_ids.append(enemy_id)
		visible_targets[enemy_id] = visible
	var focus := _focus_target(state, party, target_pressure)
	var claims := _claims(world, enemies, party, visible_targets, target_pressure, focus)
	return {
		"schema_version": 1,
		"active_enemy_ids": enemies,
		"deployed_party_ids": party,
		"visible_targets": visible_targets,
		"target_pressure": target_pressure,
		"focus_target_id": focus,
		"claims": claims,
	}


static func deployed_party_ids(world) -> Array[int]:
	var result: Array[int] = []
	if world == null or world.party_encounter == null:
		return result
	var state = world.party_encounter
	for entity_id_value in state.active_party_member_ids:
		var entity_id := int(entity_id_value)
		var member = state.member(entity_id)
		if member != null and member.presence == "DEPLOYED" \
				and world.entities.has(entity_id) and world.is_autonomous_target(entity_id):
			result.append(entity_id)
	result.sort_custom(func(a: int, b: int):
		var a_slot := int(state.member(a).roster_slot)
		var b_slot := int(state.member(b).roster_slot)
		return a_slot < b_slot if a_slot != b_slot else a < b)
	return result


static func visible_party_ids(world, enemy_id: int) -> Array[int]:
	var result: Array[int] = []
	if world == null or world.party_encounter == null \
			or not world.entities.has(enemy_id):
		return result
	var enemy = world.entities[enemy_id]
	var profile: Dictionary = PerceptionRegistryScript.profile(str(enemy.species_id))
	if profile.is_empty():
		return result
	for target_id in deployed_party_ids(world):
		if _distance(enemy.position, world.entities[target_id].position) \
				<= int(profile.sight_range) and PerceptionRegistryScript.has_line_of_sight(
					world, enemy.position, world.entities[target_id].position):
			result.append(target_id)
	result.sort_custom(func(a: int, b: int):
		var a_distance := _distance(enemy.position, world.entities[a].position)
		var b_distance := _distance(enemy.position, world.entities[b].position)
		if a_distance != b_distance:
			return a_distance < b_distance
		var a_hp := _hp_milli(world, a)
		var b_hp := _hp_milli(world, b)
		return a_hp < b_hp if a_hp != b_hp else a < b)
	return result


static func nearest_deployed_party(world, position: Vector2i):
	var party := deployed_party_ids(world)
	party.sort_custom(func(a: int, b: int):
		var a_distance := _distance(position, world.entities[a].position)
		var b_distance := _distance(position, world.entities[b].position)
		if a_distance != b_distance:
			return a_distance < b_distance
		var a_hp := _hp_milli(world, a)
		var b_hp := _hp_milli(world, b)
		return a_hp < b_hp if a_hp != b_hp else a < b)
	return null if party.is_empty() else world.entities[party[0]]


static func _active_enemies(world, state) -> Array[int]:
	var result: Array[int] = []
	for entity_id_value in state.enemy_ids:
		var entity_id := int(entity_id_value)
		if world.entities.has(entity_id) and world.is_autonomous_target(entity_id):
			result.append(entity_id)
	result.sort()
	return result


static func _focus_target(state, party: Array[int], pressure: Dictionary) -> int:
	var candidates: Array[int] = []
	for target_id in party:
		if not pressure[target_id].visible_enemy_ids.is_empty():
			candidates.append(target_id)
	if candidates.is_empty():
		return -1
	candidates.sort_custom(func(a: int, b: int):
		var a_row: Dictionary = pressure[a]
		var b_row: Dictionary = pressure[b]
		if a_row.adjacent_enemy_ids.size() != b_row.adjacent_enemy_ids.size():
			return a_row.adjacent_enemy_ids.size() > b_row.adjacent_enemy_ids.size()
		if int(a_row.hp_milli) != int(b_row.hp_milli):
			return int(a_row.hp_milli) < int(b_row.hp_milli)
		if a_row.visible_enemy_ids.size() != b_row.visible_enemy_ids.size():
			return a_row.visible_enemy_ids.size() > b_row.visible_enemy_ids.size()
		var a_slot := int(state.member(a).roster_slot)
		var b_slot := int(state.member(b).roster_slot)
		return a_slot < b_slot if a_slot != b_slot else a < b)
	return candidates[0]


static func _claims(world, enemies: Array[int], party: Array[int], visible: Dictionary,
		pressure: Dictionary, focus: int) -> Dictionary:
	var claims := {}
	var shared_targets: Array[int] = []
	for target_id in party:
		if not pressure[target_id].visible_enemy_ids.is_empty():
			shared_targets.append(target_id)
	if shared_targets.is_empty():
		return claims
	var coverage := {}
	for target_id in shared_targets:
		coverage[target_id] = 0
	for enemy_id in enemies:
		if not _can_share_claim(world, enemy_id, party):
			continue
		var ranked: Array[int] = shared_targets.duplicate()
		ranked.sort_custom(func(a: int, b: int):
			var a_focus := 0 if a == focus else 1
			var b_focus := 0 if b == focus else 1
			if a_focus != b_focus:
				return a_focus < b_focus
			var a_distance := _distance(world.entities[enemy_id].position,
				world.entities[a].position)
			var b_distance := _distance(world.entities[enemy_id].position,
				world.entities[b].position)
			return a_distance < b_distance if a_distance != b_distance else a < b)
		var chosen := -1
		for target_id in ranked:
			if shared_targets.size() == 1 or int(coverage[target_id]) < CLAIM_CAP:
				chosen = target_id
				break
		if chosen < 0:
			chosen = ranked[0]
		coverage[chosen] = int(coverage[chosen]) + 1
		claims[enemy_id] = chosen
	return claims


static func _can_share_claim(world, enemy_id: int, party: Array[int]) -> bool:
	var awareness = world.party_encounter.enemy_awareness(enemy_id)
	if awareness == null or awareness.awareness_state not in ["ALERT", "HUNTING"]:
		return false
	for target_id in party:
		if _distance(world.entities[enemy_id].position,
				world.entities[target_id].position) <= PerceptionRegistryScript.ACTIVE_COMBAT_RANGE:
			return true
	return false


static func _hp_milli(world, entity_id: int) -> int:
	var entity = world.entities[entity_id]
	return clampi(FixedPointScript.trunc_div(int(entity.health) * 1000,
		maxi(1, int(entity.max_health))), 0, 1000)


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
