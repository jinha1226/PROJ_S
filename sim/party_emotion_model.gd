class_name PartyEmotionModel
extends RefCounted

const RULESET_ID := "party-emotion-appraisal-v1"
const DECAY_QUANTUM := 100
const TARGETED_ANGER_THRESHOLD := 600
const EmotionStateScript = preload("res://sim/party_emotion_state.gd")
const FixedPointScript = preload("res://sim/fixed_point.gd")
const RelationshipSystemScript = preload("res://sim/systems/relationship_system.gd")

const DECAY_PER_QUANTUM := {
	"FEAR":18, "ANGER":10, "SADNESS":5, "GUILT":4, "BOND":3, "RESOLVE":12,
}


static func evaluate(world, event_rows: Array) -> Dictionary:
	var rows: Array[Dictionary] = []
	var events: Array = event_rows.duplicate()
	events.sort_custom(func(a, b): return _event_id(a) < _event_id(b))
	for member_id in _eligible_members(world):
		var member = world.party_encounter.member(member_id)
		var before: Dictionary = member.emotion_state.to_dict()
		var projected = EmotionStateScript.from_dict(before)
		var triggers: Array[String] = []
		_apply_decay(projected, int(world.world_time), triggers)
		for event in events:
			_appraise_event(world, member_id, member.personality_profile,
				projected, event, triggers)
		var after: Dictionary = projected.to_dict()
		if after != before:
			projected.updated_at = int(world.world_time)
			after = projected.to_dict()
		triggers.sort()
		rows.append({"entity_id":member_id, "state_before":before,
			"state_after":after, "trigger_codes":triggers})
	return {"schema_version":1, "ruleset_id":RULESET_ID,
		"member_rows":rows}.duplicate(true)


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
	if event_type in ["combat.physical_damage", "combat.downed_damage"] \
			and target_id == observer_id:
		var remembered_harm := _remembered_aggressor_salience(world, observer_id,
			instigator_id)
		_add(state, "FEAR", _fear_delta(profile, mini(360,
			35 + magnitude * 7 + FixedPointScript.trunc_div(remembered_harm, 10))),
			instigator_id, source_id, "SELF_DAMAGE")
		_append_trigger(triggers, "SELF_DAMAGE")
		if instigator_id in enemy_ids:
			_add(state, "ANGER", _anger_delta(profile, mini(300,
				20 + magnitude * 4 + FixedPointScript.trunc_div(remembered_harm, 8))),
				instigator_id, source_id, "SELF_DAMAGE")
	elif event_type == "entity.downed" and target_id in party_ids:
		if target_id == observer_id:
			_add(state, "FEAR", _fear_delta(profile, 180), instigator_id,
				source_id, "SELF_DOWNED")
			_append_trigger(triggers, "SELF_DOWNED")
		else:
			_add(state, "FEAR", _fear_delta(profile, 90), instigator_id,
				source_id, "ALLY_DOWNED")
			_add(state, "GUILT", _guilt_delta(profile, 55), target_id,
				source_id, "ALLY_DOWNED")
			_append_trigger(triggers, "ALLY_DOWNED")
	elif event_type == "entity.died":
		if target_id in party_ids and target_id != observer_id:
			var bond := _positive_bond(world, observer_id, target_id)
			var remembered_harm := _remembered_aggressor_salience(world,
				observer_id, instigator_id)
			_add(state, "SADNESS", _sadness_delta(profile, 230 + bond), target_id,
				source_id, "ALLY_DIED")
			_add(state, "GUILT", _guilt_delta(profile, 75 + int(bond / 3)), target_id,
				source_id, "ALLY_DIED")
			if instigator_id in enemy_ids:
				_add(state, "ANGER", _anger_delta(profile, 210 + int(bond / 2)
					+ FixedPointScript.trunc_div(remembered_harm, 8)),
					instigator_id, source_id, "ALLY_DIED")
			_append_trigger(triggers, "ALLY_DIED")
		elif target_id in enemy_ids:
			_add(state, "RESOLVE", _resolve_delta(profile, 140), target_id,
				source_id, "ENEMY_DIED")
			_append_trigger(triggers, "ENEMY_DIED")
	elif event_type == "party.override_committed" and actor_id == observer_id:
		var hero_id := int(world.party_encounter.protagonist_id)
		var trust := _trust(world, observer_id, hero_id)
		var base := 45 + int(magnitude / 2) + maxi(0, -trust)
		_add(state, "ANGER", _anger_delta(profile, base), hero_id,
			source_id, "OVERRIDE_CONFLICT")
		_append_trigger(triggers, "OVERRIDE_CONFLICT")
	elif event_type == "health.restored" and target_id == observer_id \
			and actor_id > 0 and actor_id != observer_id and actor_id in party_ids:
		var remembered_aid := _remembered_aid_salience(world, observer_id, actor_id)
		_add(state, "BOND", _bond_delta(profile, mini(300, 60 + magnitude * 3
			+ FixedPointScript.trunc_div(remembered_aid, 10))),
			actor_id, source_id, "ALLY_AID")
		_append_trigger(triggers, "ALLY_AID")
	elif event_type == "town.shrine_service" and target_id == observer_id:
		_reduce(state, "FEAR", 300)
		_reduce(state, "ANGER", 150)
		_reduce(state, "SADNESS", 120)
		_reduce(state, "GUILT", 100)
		_append_trigger(triggers, "TOWN_REST")


static func _apply_decay(state, world_time: int, triggers: Array[String]) -> void:
	var elapsed := maxi(0, world_time - int(state.updated_at))
	var quanta := int(elapsed / DECAY_QUANTUM)
	if quanta <= 0:
		return
	var changed := false
	for emotion_id in EmotionStateScript.EMOTION_IDS:
		var before: int = state.intensity(emotion_id)
		if before <= 0:
			continue
		var after := maxi(0, before - int(DECAY_PER_QUANTUM[emotion_id]) * quanta)
		if after != before:
			state.set_channel(emotion_id, after, state.target_id(emotion_id),
				state.source_event_id(emotion_id), state.cause_code(emotion_id))
			changed = true
	if changed:
		_append_trigger(triggers, "SAFE_DECAY")


static func _add(state, emotion_id: String, delta: int, target_id: int,
		source_event_id: int, cause_code: String) -> void:
	if delta <= 0:
		return
	var existing: int = state.intensity(emotion_id)
	var replace_memory: bool = existing == 0 or delta >= existing \
		or state.target_id(emotion_id) <= 0 and target_id > 0
	state.set_channel(emotion_id, state.intensity(emotion_id) + delta,
		(target_id if target_id > 0 else -1) if replace_memory \
			else state.target_id(emotion_id),
		source_event_id if replace_memory else state.source_event_id(emotion_id),
		cause_code if replace_memory else state.cause_code(emotion_id))


static func _reduce(state, emotion_id: String, amount: int) -> void:
	var before: int = state.intensity(emotion_id)
	if before <= 0 or amount <= 0:
		return
	state.set_channel(emotion_id, maxi(0, before - amount),
		state.target_id(emotion_id), state.source_event_id(emotion_id),
		state.cause_code(emotion_id))


static func _fear_delta(profile, base: int) -> int:
	var multiplier := 700 + FixedPointScript.trunc_div(_facet(profile, "E"), 2) \
		+ FixedPointScript.trunc_div(1000 - _facet(profile, "C"), 4)
	return clampi(FixedPointScript.trunc_div(base * multiplier, 1000), 1, 500)


static func _anger_delta(profile, base: int) -> int:
	var multiplier := 650 + FixedPointScript.trunc_div(1000 - _facet(profile, "A"), 2) \
		+ FixedPointScript.trunc_div(_facet(profile, "X"), 4)
	return clampi(FixedPointScript.trunc_div(base * multiplier, 1000), 1, 500)


static func _sadness_delta(profile, base: int) -> int:
	var multiplier := 700 + FixedPointScript.trunc_div(_facet(profile, "E"), 2)
	return clampi(FixedPointScript.trunc_div(base * multiplier, 1000), 1, 600)


static func _guilt_delta(profile, base: int) -> int:
	var multiplier := 550 + FixedPointScript.trunc_div(_facet(profile, "H"), 3) \
		+ FixedPointScript.trunc_div(_facet(profile, "C"), 3)
	return clampi(FixedPointScript.trunc_div(base * multiplier, 1000), 1, 450)


static func _bond_delta(profile, base: int) -> int:
	var multiplier := 600 + FixedPointScript.trunc_div(_facet(profile, "H"), 4) \
		+ FixedPointScript.trunc_div(_facet(profile, "A"), 3)
	return clampi(FixedPointScript.trunc_div(base * multiplier, 1000), 1, 450)


static func _resolve_delta(profile, base: int) -> int:
	var multiplier := 600 + FixedPointScript.trunc_div(_facet(profile, "C"), 3) \
		+ FixedPointScript.trunc_div(_facet(profile, "X"), 3) \
		- FixedPointScript.trunc_div(_facet(profile, "E"), 6)
	return clampi(FixedPointScript.trunc_div(base * clampi(multiplier, 300, 1300),
		1000), 1, 450)


static func _positive_bond(world, observer_id: int, subject_id: int) -> int:
	var relation := RelationshipSystemScript.new(world).effective_relation(
		observer_id, subject_id)
	return clampi(maxi(0, int(relation.get("trust", 0))) \
		+ FixedPointScript.trunc_div(int(relation.get("gratitude", 0)), 2), 0, 150)


static func _trust(world, observer_id: int, subject_id: int) -> int:
	return clampi(int(RelationshipSystemScript.new(world).effective_relation(
		observer_id, subject_id).get("trust", 0)), -100, 100)


static func _remembered_aggressor_salience(world, observer_id: int,
		aggressor_id: int) -> int:
	var member = world.party_encounter.member(observer_id)
	if member == null or member.memory_state == null or aggressor_id <= 0:
		return 0
	return maxi(member.memory_state.salience_for_subject(aggressor_id,
		["SELF_HARM"]), member.memory_state.salience_for_instigator(aggressor_id,
		["ALLY_DOWNED", "ALLY_LOST"]))


static func _remembered_aid_salience(world, observer_id: int,
		helper_id: int) -> int:
	var member = world.party_encounter.member(observer_id)
	return member.memory_state.salience_for_subject(helper_id, ["AID_RECEIVED"]) \
		if member != null and member.memory_state != null and helper_id > 0 else 0


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


static func _append_trigger(triggers: Array[String], code: String) -> void:
	if code not in triggers:
		triggers.append(code)


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
