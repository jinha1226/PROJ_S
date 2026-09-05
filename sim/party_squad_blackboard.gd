class_name PartySquadBlackboard
extends RefCounted

const FixedPointScript = preload("res://sim/fixed_point.gd")
const PartyCommandScript = preload("res://sim/party_exception_command.gd")
const CampaignEncounterStreamScript=preload("res://sim/campaign_encounter_stream.gd")
const CLAIM_CAP := 2


static func build(world, protagonist_action) -> Dictionary:
	var state = world.party_encounter
	var deployed: Array[int] = []
	for entity_id in state.active_party_member_ids:
		var member = state.member(entity_id)
		if member != null and member.presence == "DEPLOYED" and world.entities.has(entity_id):
			deployed.append(int(entity_id))
	var enemies: Array[int] = []
	for entity_id in CampaignEncounterStreamScript.active_enemy_ids(world):
		if world.entities.has(entity_id) and world.is_autonomous_target(entity_id):
			enemies.append(int(entity_id))
	enemies.sort()
	var threat_table := {}
	var ally_pressure := {}
	for member_id in deployed:
		ally_pressure[member_id] = {
			"adjacent_enemy_ids": [],
			"hp_milli": _hp_milli(world, member_id),
		}
	var protagonist_position: Vector2i = world.entities[state.protagonist_id].position
	for enemy_id in enemies:
		var adjacent: Array[int] = []
		for member_id in deployed:
			if _distance(world.entities[enemy_id].position,
					world.entities[member_id].position) <= 1:
				adjacent.append(member_id)
				ally_pressure[member_id].adjacent_enemy_ids.append(enemy_id)
		threat_table[enemy_id] = {
			"hp_milli": _hp_milli(world, enemy_id),
			"adjacent_party_ids": adjacent,
			"distance_to_protagonist": _distance(
				world.entities[enemy_id].position, protagonist_position),
		}
	var focus := _focus_target(world, state, protagonist_action, enemies, threat_table)
	var threatened := _most_threatened_ally(state, deployed, ally_pressure)
	var claims := _claims(state, deployed, enemies, focus)
	var party_command: Dictionary = PartyCommandScript.effective(world, state)
	return {
		"schema_version": 1,
		"deployed_ids": deployed,
		"active_enemy_ids": enemies,
		"threat_table": threat_table,
		"ally_pressure": ally_pressure,
		"focus_target_id": focus,
		"most_threatened_ally_id": threatened,
		"claims": claims,
		"party_command": party_command,
	}


static func _focus_target(world, state, action, enemies: Array[int],
		threat_table: Dictionary) -> int:
	if enemies.is_empty():
		return -1
	if action != null and action.type == "MELEE" and int(action.target_id) in enemies:
		return int(action.target_id)
	# The protagonist's last committed attack is an implicit party order. Keep it
	# sticky across MOVE/HOLD turns until that target is no longer active, matching
	# the zero-input ally loop: acting on a foe means "focus this foe" without a
	# separate command every round.
	var implicit_focus := _last_committed_protagonist_target(world, state, enemies)
	if implicit_focus > 0:
		return implicit_focus
	var engaged: Array[int] = []
	for enemy_id in enemies:
		if not threat_table[enemy_id].adjacent_party_ids.is_empty():
			engaged.append(enemy_id)
	if not engaged.is_empty():
		engaged.sort_custom(func(a, b):
			var a_hp: int = threat_table[a].hp_milli
			var b_hp: int = threat_table[b].hp_milli
			return a_hp < b_hp if a_hp != b_hp else a < b)
		return engaged[0]
	var anchor: Vector2i = world.entities[state.protagonist_id].position
	if action != null and action.type == "MOVE":
		anchor = action.destination
	var ranked: Array[int] = enemies.duplicate()
	ranked.sort_custom(func(a, b):
		var a_distance := _distance(anchor, world.entities[a].position)
		var b_distance := _distance(anchor, world.entities[b].position)
		return a_distance < b_distance if a_distance != b_distance else a < b)
	return ranked[0]


static func _last_committed_protagonist_target(world, state,
		enemies: Array[int]) -> int:
	for event_index in range(world.events.size() - 1, -1, -1):
		var event = world.events[event_index]
		if event.type == "party.regroup_completed":
			break
		if event.type == "party.command_issued":
			if str(event.data.get("command_id", "")) == "ATTACK_TARGET":
				var commanded_target := int(str(event.data.get("target_id", "-1")))
				return commanded_target if commanded_target in enemies else -1
			# Any later exceptional command intentionally clears an older implicit
			# attack focus. FOLLOW returns control to fresh autonomous selection.
			return -1
		if event.type == "action.melee_attack" \
				and int(event.actor_id) == int(state.protagonist_id):
			# Only the latest protagonist attack is an order. If its target has
			# become invalid, clear the focus instead of resurrecting an older one.
			return int(event.target_id) if int(event.target_id) in enemies else -1
	return -1


static func _most_threatened_ally(state, deployed: Array[int], pressure: Dictionary) -> int:
	var best := -1
	for entity_id in deployed:
		if best < 0:
			best = entity_id
			continue
		var candidate: Dictionary = pressure[entity_id]
		var incumbent: Dictionary = pressure[best]
		var candidate_count: int = candidate.adjacent_enemy_ids.size()
		var incumbent_count: int = incumbent.adjacent_enemy_ids.size()
		if candidate_count != incumbent_count:
			if candidate_count > incumbent_count:
				best = entity_id
		elif int(candidate.hp_milli) != int(incumbent.hp_milli):
			if int(candidate.hp_milli) < int(incumbent.hp_milli):
				best = entity_id
		elif state.member(entity_id).roster_slot < state.member(best).roster_slot:
			best = entity_id
	return best


static func _claims(state, deployed: Array[int], enemies: Array[int], focus: int) -> Dictionary:
	var claims := {}
	if enemies.is_empty():
		return claims
	var coverage := {}
	for enemy_id in enemies:
		coverage[enemy_id] = 0
	var companions: Array[int] = []
	for entity_id in deployed:
		if entity_id != state.protagonist_id:
			companions.append(entity_id)
	companions.sort_custom(func(a, b):
		var a_slot: int = state.member(a).roster_slot
		var b_slot: int = state.member(b).roster_slot
		return a_slot < b_slot if a_slot != b_slot else a < b)
	var order: Array[int] = [focus]
	for enemy_id in enemies:
		if enemy_id != focus:
			order.append(enemy_id)
	for companion_id in companions:
		var chosen := -1
		for enemy_id in order:
			if enemies.size() == 1 or int(coverage[enemy_id]) < CLAIM_CAP:
				chosen = enemy_id
				break
		if chosen < 0:
			chosen = order[0]
		coverage[chosen] = int(coverage[chosen]) + 1
		claims[companion_id] = chosen
	return claims


static func _hp_milli(world, entity_id: int) -> int:
	var entity = world.entities[entity_id]
	return clampi(FixedPointScript.trunc_div(int(entity.health) * 1000,
		maxi(1, int(entity.max_health))), 0, 1000)


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
