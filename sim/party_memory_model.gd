class_name PartyMemoryModel
extends RefCounted

const RULESET_ID := "party-memory-appraisal-v1"
const StateScript = preload("res://sim/party_memory_state.gd")
const FixedPointScript = preload("res://sim/fixed_point.gd")
const RelationshipSystemScript = preload("res://sim/systems/relationship_system.gd")


static func evaluate(world, event_rows: Array) -> Dictionary:
	var projected_rows: Array[Dictionary] = []
	var events: Array = event_rows.duplicate()
	events.sort_custom(func(a, b): return _event_id(a) < _event_id(b))
	for member_id in _eligible_members(world):
		var member = world.party_encounter.member(member_id)
		var before: Dictionary = member.memory_state.to_dict()
		var projected = StateScript.from_dict(before)
		var trigger_codes: Array[String] = []
		for event in events:
			_appraise_event(world, member_id, member.personality_profile,
				projected, event, trigger_codes)
		var after: Dictionary = projected.to_dict()
		if after != before:
			trigger_codes.sort()
			projected_rows.append({"entity_id":member_id, "state_before":before,
				"state_after":after, "trigger_codes":trigger_codes})
	return {"schema_version":1, "ruleset_id":RULESET_ID,
		"member_rows":projected_rows}.duplicate(true)


static func _appraise_event(world, observer_id: int, profile, state, event,
		triggers: Array[String]) -> void:
	var event_type := _event_type(event)
	var actor_id := _event_actor(event)
	var target_id := _event_target(event)
	var source_id := _event_id(event)
	var instigator_id := _event_instigator(event)
	var magnitude := maxi(0, _event_magnitude(event))
	var party_ids: Array = world.party_encounter.party_member_ids
	var enemy_ids: Array = world.party_encounter.enemy_ids
	var kind := ""
	var subject_id := -1
	var remembered_instigator := -1
	var salience := 0
	if event_type in ["combat.physical_damage", "combat.downed_damage"] \
			and target_id == observer_id and instigator_id in enemy_ids:
		kind = "SELF_HARM"; subject_id = instigator_id
		remembered_instigator = instigator_id
		salience = _negative_salience(profile, mini(700, 160 + magnitude * 12))
	elif event_type == "entity.downed" and target_id in party_ids \
			and target_id != observer_id:
		kind = "ALLY_DOWNED"; subject_id = target_id
		remembered_instigator = instigator_id if instigator_id in enemy_ids else -1
		salience = _social_salience(world, observer_id, target_id, profile, 420)
	elif event_type == "entity.died" and target_id in party_ids \
			and target_id != observer_id:
		kind = "ALLY_LOST"; subject_id = target_id
		remembered_instigator = instigator_id if instigator_id in enemy_ids else -1
		salience = _social_salience(world, observer_id, target_id, profile, 780)
	elif event_type == "health.restored" and target_id == observer_id \
			and actor_id > 0 and actor_id != observer_id and actor_id in party_ids:
		kind = "AID_RECEIVED"; subject_id = actor_id; remembered_instigator = actor_id
		salience = _positive_salience(profile, mini(650, 180 + magnitude * 8))
	elif event_type == "party.override_committed" and actor_id == observer_id:
		kind = "COMMAND_CONFLICT"
		subject_id = int(world.party_encounter.protagonist_id)
		remembered_instigator = subject_id
		salience = _conflict_salience(profile, mini(600, 180 + magnitude * 5))
	if kind.is_empty() or not state.remember(kind, source_id, int(world.world_time),
			subject_id, remembered_instigator, salience):
		return
	if kind not in triggers:
		triggers.append(kind)


static func _negative_salience(profile, base: int) -> int:
	var multiplier := 650 + FixedPointScript.trunc_div(_facet(profile, "E"), 2) \
		+ FixedPointScript.trunc_div(1000 - _facet(profile, "C"), 4)
	return clampi(FixedPointScript.trunc_div(base * multiplier, 1000), 1, 1000)


static func _social_salience(world, observer_id: int, subject_id: int,
		profile, base: int) -> int:
	var relation := RelationshipSystemScript.new(world).effective_relation(
		observer_id, subject_id)
	var trust := maxi(0, int(relation.get("trust", 0))) * 3
	var multiplier := 650 + FixedPointScript.trunc_div(_facet(profile, "E"), 3) \
		+ FixedPointScript.trunc_div(_facet(profile, "H"), 5)
	return clampi(FixedPointScript.trunc_div((base + trust) * multiplier, 1000),
		1, 1000)


static func _positive_salience(profile, base: int) -> int:
	var multiplier := 600 + FixedPointScript.trunc_div(_facet(profile, "H"), 3) \
		+ FixedPointScript.trunc_div(_facet(profile, "A"), 4)
	return clampi(FixedPointScript.trunc_div(base * multiplier, 1000), 1, 1000)


static func _conflict_salience(profile, base: int) -> int:
	var multiplier := 600 + FixedPointScript.trunc_div(1000 - _facet(profile, "A"), 3) \
		+ FixedPointScript.trunc_div(_facet(profile, "H"), 5)
	return clampi(FixedPointScript.trunc_div(base * multiplier, 1000), 1, 1000)


static func _eligible_members(world) -> Array[int]:
	var result: Array[int] = []
	if world == null or world.party_encounter == null:
		return result
	for member_id_value in world.party_encounter.active_party_member_ids:
		var member_id := int(member_id_value)
		var member = world.party_encounter.member(member_id)
		var combatant = world.combatant_states.get(member_id)
		if member != null and member.presence in ["DEPLOYED", "GROUPED"] \
				and combatant != null and combatant.life_state != "DEAD" \
				and world.entities.has(member_id):
			result.append(member_id)
	result.sort_custom(func(a: int, b: int):
		var a_slot := int(world.party_encounter.member(a).roster_slot)
		var b_slot := int(world.party_encounter.member(b).roster_slot)
		return a_slot < b_slot if a_slot != b_slot else a < b)
	return result


static func _facet(profile, facet_id: String) -> int:
	if profile == null:
		return 500
	var value := int(profile.value(facet_id))
	return clampi(value, 0, 1000) if value >= 0 else 500


static func _event_id(event) -> int:
	return int(event.get("id", -1) if event is Dictionary else event.id)

static func _event_type(event) -> String:
	return str(event.get("type", "") if event is Dictionary else event.type)

static func _event_actor(event) -> int:
	return int(event.get("actor_id", -1) if event is Dictionary else event.actor_id)

static func _event_target(event) -> int:
	return int(event.get("target_id", -1) if event is Dictionary else event.target_id)

static func _event_instigator(event) -> int:
	return int(event.get("instigator_id", _event_actor(event)) \
		if event is Dictionary else event.instigator_id)

static func _event_magnitude(event) -> int:
	return int(event.get("magnitude", 0) if event is Dictionary else event.magnitude)
