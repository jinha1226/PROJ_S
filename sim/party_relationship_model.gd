class_name PartyRelationshipModel
extends RefCounted

const RULESET_ID := "party-relationship-appraisal-v1"
const REACTION_KINDS := ["AID_RECEIVED", "DIRECT_HARM", "ALLY_DOWNED",
	"ALLY_LOST", "AVENGED_HARM", "COMMAND_CONFLICT"]
const AID_KINDS := ["AID_RECEIVED", "AVENGED_HARM"]
const HARM_KINDS := ["DIRECT_HARM", "ALLY_DOWNED", "ALLY_LOST",
	"COMMAND_CONFLICT"]
const FixedPointScript = preload("res://sim/fixed_point.gd")


static func evaluate(world, event_rows: Array) -> Dictionary:
	var result: Array[Dictionary] = []
	if world == null or world.party_encounter == null:
		return {"schema_version":1, "ruleset_id":RULESET_ID,
			"reaction_rows":result}
	var eligible := _eligible_members(world)
	var events: Array = event_rows.duplicate()
	events.sort_custom(func(a, b): return _event_id(a) < _event_id(b))
	var seen: Dictionary = {}
	for event in events:
		for row in _reactions_for_event(world, event, eligible):
			var key := "%d:%d:%d" % [int(row.observer_id), int(row.subject_id),
				int(row.source_event_id)]
			if seen.has(key) or _already_processed(world, int(row.observer_id),
					int(row.subject_id), int(row.source_event_id)):
				continue
			seen[key] = true
			result.append(row)
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.source_event_id) != int(b.source_event_id):
			return int(a.source_event_id) < int(b.source_event_id)
		if int(a.observer_id) != int(b.observer_id):
			return int(a.observer_id) < int(b.observer_id)
		return int(a.subject_id) < int(b.subject_id))
	return {"schema_version":1, "ruleset_id":RULESET_ID,
		"reaction_rows":result}.duplicate(true)


static func multiplier_for(profile, reaction_kind: String) -> int:
	match reaction_kind:
		"AID_RECEIVED":
			return 500 + FixedPointScript.trunc_div(_facet(profile, "H"), 3) \
				+ FixedPointScript.trunc_div(_facet(profile, "A"), 3)
		"DIRECT_HARM":
			return 550 + FixedPointScript.trunc_div(_facet(profile, "E"), 3) \
				+ FixedPointScript.trunc_div(1000 - _facet(profile, "A"), 4)
		"ALLY_DOWNED", "ALLY_LOST":
			return 500 + FixedPointScript.trunc_div(_facet(profile, "E"), 3) \
				+ FixedPointScript.trunc_div(_facet(profile, "H"), 4)
		"AVENGED_HARM":
			return 550 + FixedPointScript.trunc_div(_facet(profile, "H"), 4) \
				+ FixedPointScript.trunc_div(_facet(profile, "A"), 4)
		"COMMAND_CONFLICT":
			return 550 + FixedPointScript.trunc_div(1000 - _facet(profile, "A"), 3) \
				+ FixedPointScript.trunc_div(1000 - _facet(profile, "C"), 6)
	return 1000


static func reaction_magnitude(base_magnitude: int,
		personality_multiplier_milli: int) -> int:
	return clampi(FixedPointScript.trunc_div(
		base_magnitude * personality_multiplier_milli + 500, 1000), 1, 100)


static func metadata_error(value: Variant, magnitude: int = -1) -> String:
	if not value is Dictionary:
		return "invalid_party_relationship_metadata"
	var keys: Array = value.keys(); keys.sort()
	if keys != ["base_magnitude", "evidence_salience", "evidence_source_event_id",
			"personality_multiplier_milli", "reaction_kind", "ruleset_id",
			"schema_version"] \
			or value.get("schema_version") != 1 \
			or value.get("ruleset_id") != RULESET_ID \
			or value.get("reaction_kind") not in REACTION_KINDS \
			or not value.get("base_magnitude") is int \
			or int(value.base_magnitude) < 1 or int(value.base_magnitude) > 100 \
			or not value.get("personality_multiplier_milli") is int \
			or int(value.personality_multiplier_milli) < 500 \
			or int(value.personality_multiplier_milli) > 1200 \
			or not value.get("evidence_source_event_id") is int \
			or int(value.evidence_source_event_id) < -1 \
			or not value.get("evidence_salience") is int \
			or int(value.evidence_salience) < 0 \
			or int(value.evidence_salience) > 1000:
		return "invalid_party_relationship_metadata"
	var avenged := str(value.reaction_kind) == "AVENGED_HARM"
	if avenged != (int(value.evidence_source_event_id) > 0) \
			or avenged != (int(value.evidence_salience) > 0):
		return "invalid_party_relationship_evidence"
	if magnitude >= 0 and magnitude != reaction_magnitude(
			int(value.base_magnitude), int(value.personality_multiplier_milli)):
		return "party_relationship_magnitude_mismatch"
	return ""


static func _reactions_for_event(world, event, eligible: Array[int]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var event_type := _event_type(event)
	var source_id := _event_id(event)
	var actor_id := _event_actor(event)
	var target_id := _event_target(event)
	var instigator_id := _event_instigator(event)
	var magnitude := maxi(0, _event_magnitude(event))
	var active_ids: Array = world.party_encounter.active_party_member_ids
	var enemy_ids: Array = world.party_encounter.enemy_ids
	if source_id <= 0:
		return rows
	if event_type == "health.restored" and target_id in eligible \
			and actor_id in active_ids and actor_id != target_id:
		rows.append(_row(world, target_id, actor_id, source_id,
			"AID_RECEIVED", clampi(8 + magnitude * 2, 8, 45)))
	elif event_type in ["combat.physical_damage", "combat.downed_damage"] \
			and target_id in eligible and instigator_id in enemy_ids:
		rows.append(_row(world, target_id, instigator_id, source_id,
			"DIRECT_HARM", clampi(3 + magnitude, 3, 20)))
	elif event_type in ["entity.downed", "entity.died"] \
			and target_id in active_ids and instigator_id in enemy_ids:
		var kind := "ALLY_LOST" if event_type == "entity.died" else "ALLY_DOWNED"
		var base := 35 if kind == "ALLY_LOST" else 18
		for observer_id in eligible:
			if observer_id != target_id:
				rows.append(_row(world, observer_id, instigator_id, source_id,
					kind, base))
	elif event_type == "entity.died" and target_id in enemy_ids \
			and instigator_id in active_ids:
		for observer_id in eligible:
			if observer_id == instigator_id:
				continue
			var evidence := _avenging_evidence(world, observer_id, target_id)
			if evidence.is_empty():
				continue
			rows.append(_row(world, observer_id, instigator_id, source_id,
				"AVENGED_HARM", clampi(8 + int(evidence.salience) / 50, 8, 28),
				int(evidence.source_event_id), int(evidence.salience)))
	elif event_type == "party.override_committed" and actor_id in eligible:
		var hero_id := int(world.party_encounter.protagonist_id)
		if actor_id != hero_id:
			rows.append(_row(world, actor_id, hero_id, source_id,
				"COMMAND_CONFLICT", clampi(8 + magnitude / 3, 8, 30)))
	return rows


static func _row(world, observer_id: int, subject_id: int, source_event_id: int,
		reaction_kind: String, base_magnitude: int, evidence_source_event_id: int = -1,
		evidence_salience: int = 0) -> Dictionary:
	var member = world.party_encounter.member(observer_id)
	var multiplier := multiplier_for(
		member.personality_profile if member != null else null, reaction_kind)
	return {"observer_id":observer_id, "subject_id":subject_id,
		"source_event_id":source_event_id,
		"channel":"AID" if reaction_kind in AID_KINDS else "HARM",
		"magnitude":reaction_magnitude(base_magnitude, multiplier),
		"metadata":{"schema_version":1, "ruleset_id":RULESET_ID,
			"reaction_kind":reaction_kind, "base_magnitude":base_magnitude,
			"personality_multiplier_milli":multiplier,
			"evidence_source_event_id":evidence_source_event_id,
			"evidence_salience":evidence_salience}}


static func _avenging_evidence(world, observer_id: int, enemy_id: int) -> Dictionary:
	var member = world.party_encounter.member(observer_id)
	if member == null or member.memory_state == null:
		return {}
	var best: Dictionary = {}
	for record_value in member.memory_state.records:
		var record: Dictionary = record_value
		if str(record.kind) not in ["SELF_HARM", "ALLY_DOWNED", "ALLY_LOST"] \
				or int(record.instigator_id) != enemy_id:
			continue
		if best.is_empty() or int(record.salience) > int(best.salience) \
				or int(record.salience) == int(best.salience) \
				and int(record.source_event_id) > int(best.source_event_id):
			best = record
	return best.duplicate(true)


static func _eligible_members(world) -> Array[int]:
	var result: Array[int] = []
	for member_id_value in world.party_encounter.active_party_member_ids:
		var member_id := int(member_id_value)
		var member = world.party_encounter.member(member_id)
		var combatant = world.combatant_states.get(member_id)
		if member != null and member.presence in ["DEPLOYED", "GROUPED"] \
				and combatant != null and combatant.life_state != "DEAD" \
				and world.entities.has(member_id):
			result.append(member_id)
	result.sort()
	return result


static func _already_processed(world, observer_id: int, subject_id: int,
		source_event_id: int) -> bool:
	var relation = world.personal_relations.get("%d:%d" % [observer_id, subject_id])
	return relation != null and relation.has_processed(source_event_id)


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
