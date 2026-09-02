class_name PartyCompanionAppraisal
extends RefCounted

const FixedPointScript = preload("res://sim/fixed_point.gd")
const RelationshipSystemScript = preload("res://sim/systems/relationship_system.gd")
const THREAT_POWER_NORM := 760


static func appraise(world, actor_id: int, board: Dictionary) -> Dictionary:
	var state = world.party_encounter
	var member = state.member(actor_id)
	var actor = world.entities[actor_id]
	var relationships = RelationshipSystemScript.new(world)
	var profile = member.personality_profile
	var emotionality := _facet(profile, "E")
	var agreeableness := _facet(profile, "A")
	var conscientiousness := _facet(profile, "C")
	var stress: int = clampi(int(member.stress), 0, 1000)
	var pressure: Dictionary = board.ally_pressure.get(actor_id,
		{"adjacent_enemy_ids": [], "hp_milli": 1000})
	var threat_id := _threat_id(world, actor, pressure, board.active_enemy_ids)
	var has_threat := threat_id > 0
	var distance: int = _distance(actor.position, world.entities[threat_id].position) \
		if has_threat else 99
	var distance_pressure: int = clampi(1000 - maxi(0, distance - 1) * 160, 0, 1000) \
		if has_threat else 0
	var objective: int = FixedPointScript.trunc_div(
		2 * THREAT_POWER_NORM + distance_pressure, 3) if has_threat else 0
	var hp_loss: int = FixedPointScript.trunc_div(
		(int(actor.max_health) - int(actor.health)) * 1000, maxi(1, int(actor.max_health)))
	var relation: Dictionary = relationships.effective_relation(actor_id, threat_id) \
		if has_threat else {}
	var relation_fear: int = int(relation.get("fear", 0)) * 10
	var hostility: int = int(relation.get("hostility", 0)) * 10
	var perceived: int = clampi(objective + FixedPointScript.trunc_div(relation_fear, 2) \
		+ FixedPointScript.trunc_div(hp_loss, 2) + FixedPointScript.trunc_div(emotionality, 3) \
		- 167 \
		+ FixedPointScript.trunc_div(stress, 2), 0, 2000) if has_threat else 0
	var attack_drive: int = clampi(hostility \
		+ FixedPointScript.trunc_div(1000 - emotionality, 4) \
		+ FixedPointScript.trunc_div(1000 - agreeableness, 4), 0, 2000)
	var panic: int = clampi(stress + FixedPointScript.trunc_div(hp_loss, 2) \
		+ FixedPointScript.trunc_div(emotionality, 3) \
		- FixedPointScript.trunc_div(conscientiousness, 2), 0, 2000)
	var adjacent_count: int = pressure.adjacent_enemy_ids.size()
	var engaged_enemies: int = 1000 if adjacent_count >= 3 else int([0, 400, 700][adjacent_count])
	var outnumbered: int = clampi(
		(board.active_enemy_ids.size() - board.deployed_ids.size()) * 250 + 500, 0, 1000)
	var ally_id: int = int(board.most_threatened_ally_id)
	var ally_targeted: bool = ally_id > 0 and ally_id != actor_id \
		and board.ally_pressure.has(ally_id) \
		and not board.ally_pressure[ally_id].adjacent_enemy_ids.is_empty()
	var ally_hp_loss: int = 1000 - int(board.ally_pressure[ally_id].hp_milli) \
		if ally_targeted else 0
	var ally_trust: int = _trust_milli(relationships, actor_id, ally_id) \
		if ally_targeted else 500
	var protagonist_trust: int = _trust_milli(relationships, actor_id, state.protagonist_id)
	return {
		"threat_id": threat_id,
		"distance": distance,
		"distance_pressure": distance_pressure,
		"objective_danger": objective,
		"perceived_threat": perceived,
		"attack_drive": attack_drive,
		"panic_pressure": panic,
		"hp_loss": hp_loss,
		"engaged_enemies": engaged_enemies,
		"outnumbered": outnumbered,
		"ally_targeted": 1000 if ally_targeted else 0,
		"ally_id": ally_id if ally_targeted else -1,
		"ally_hp_loss": ally_hp_loss,
		"ally_trust": ally_trust,
		"protagonist_trust": protagonist_trust,
		"stress": stress,
		# Stress pressure still scores actions, while the legal action set follows
		# the authoritative hysteresis mode persisted by PartyMoraleSystem.
		"mode": str(member.mental_mode),
	}


static func inputs_for(appraisal: Dictionary, profile, candidate_target_id: int,
		board: Dictionary, actor_id: int) -> Dictionary:
	return {
		"facet.H": _facet(profile, "H"),
		"facet.E": _facet(profile, "E"),
		"facet.X": _facet(profile, "X"),
		"facet.A": _facet(profile, "A"),
		"facet.C": _facet(profile, "C"),
		"facet.O": _facet(profile, "O"),
		"appraisal.attack_drive": clampi(
			FixedPointScript.trunc_div(int(appraisal.attack_drive), 2), 0, 1000),
		"appraisal.perceived_threat": clampi(
			FixedPointScript.trunc_div(int(appraisal.perceived_threat), 2), 0, 1000),
		"appraisal.panic_pressure": clampi(
			FixedPointScript.trunc_div(int(appraisal.panic_pressure), 2), 0, 1000),
		"context.hp_loss": int(appraisal.hp_loss),
		"context.ally_targeted": int(appraisal.ally_targeted),
		"context.ally_hp_loss": int(appraisal.ally_hp_loss),
		"context.engaged_enemies": int(appraisal.engaged_enemies),
		"context.outnumbered": int(appraisal.outnumbered),
		"context.claim_alignment": 1000 if candidate_target_id > 0 \
			and int(board.claims.get(actor_id, -1)) == candidate_target_id else 0,
		"context.focus_alignment": 1000 if candidate_target_id > 0 \
			and int(board.focus_target_id) == candidate_target_id else 0,
		"relation.ally_trust": int(appraisal.ally_trust),
		"relation.protagonist_trust": int(appraisal.protagonist_trust),
		"affect.stress": int(appraisal.stress),
	}


static func _threat_id(world, actor, pressure: Dictionary, enemies: Array) -> int:
	var adjacent: Array = pressure.adjacent_enemy_ids.duplicate()
	if not adjacent.is_empty():
		adjacent.sort_custom(func(a, b):
			var a_health: int = world.entities[a].health
			var b_health: int = world.entities[b].health
			return a_health > b_health if a_health != b_health else int(a) < int(b))
		return int(adjacent[0])
	var best := -1
	var best_distance := 999
	for enemy_id in enemies:
		var distance := _distance(actor.position, world.entities[enemy_id].position)
		if distance < best_distance or (distance == best_distance and int(enemy_id) < best):
			best = int(enemy_id)
			best_distance = distance
	return best


static func _trust_milli(relationships, observer: int, subject: int) -> int:
	if observer <= 0 or subject <= 0 or observer == subject:
		return 500
	var relation: Dictionary = relationships.effective_relation(observer, subject)
	return clampi(FixedPointScript.trunc_div(
		int(relation.get("trust", 0)) * 10 + 1000, 2), 0, 1000)


static func _facet(profile, facet_id: String) -> int:
	if profile == null:
		return 500
	var value: int = profile.value(facet_id)
	return clampi(value, 0, 1000) if value >= 0 else 500


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
