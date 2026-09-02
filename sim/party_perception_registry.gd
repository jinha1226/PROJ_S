class_name PartyPerceptionRegistry
extends RefCounted

const EnemyPerceptionRegistryScript = preload("res://sim/enemy_perception_registry.gd")

const RULESET_ID := "party-shared-perception-v1"
const SIGHT_TAG_BONUSES := {
	"keen_sight": 2,
	"scout_sight": 3,
}


static func sight_range(world, state, member_id: int) -> int:
	if world == null or state == null or not world.entities.has(member_id):
		return 0
	var result := clampi(int(state.party_detection_radius), 0, 15)
	for tag in world.entities[member_id].tags:
		result = maxi(result, clampi(int(state.party_detection_radius) \
			+ int(SIGHT_TAG_BONUSES.get(str(tag), 0)), 0, 15))
	return result


static func visible_party_members(world, state, target_position: Vector2i) -> Array[int]:
	var rows: Array[Dictionary] = []
	for member_id_value in state.active_party_member_ids:
		var member_id := int(member_id_value)
		var member = state.member(member_id)
		if member == null or member.presence not in ["GROUPED", "DEPLOYED"] \
				or not world.entities.has(member_id) \
				or not world.can_act(member_id, world.world_time):
			continue
		var origin: Vector2i = state.group_anchor if member.presence == "GROUPED" \
			else world.entities[member_id].position
		var distance := _distance(origin, target_position)
		var member_range := sight_range(world, state, member_id)
		if distance > member_range or not EnemyPerceptionRegistryScript.has_line_of_sight(
				world, origin, target_position):
			continue
		rows.append({"entity_id": member_id, "distance": distance,
			"sight_range": member_range, "roster_slot": int(member.roster_slot)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_hero: bool = int(a.entity_id) == int(state.protagonist_id)
		var b_hero: bool = int(b.entity_id) == int(state.protagonist_id)
		if a_hero != b_hero:
			return a_hero
		if int(a.distance) != int(b.distance):
			return int(a.distance) < int(b.distance)
		if int(a.roster_slot) != int(b.roster_slot):
			return int(a.roster_slot) < int(b.roster_slot)
		return int(a.entity_id) < int(b.entity_id))
	var result: Array[int] = []
	for row in rows:
		result.append(int(row.entity_id))
	return result


static func maximum_sight_range(world, state) -> int:
	var result := clampi(int(state.party_detection_radius), 0, 15)
	for member_id_value in state.active_party_member_ids:
		result = maxi(result, sight_range(world, state, int(member_id_value)))
	return result


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
