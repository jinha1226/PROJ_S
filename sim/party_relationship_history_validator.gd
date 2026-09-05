class_name PartyRelationshipHistoryValidator
extends RefCounted

const ModelScript = preload("res://sim/party_relationship_model.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")


static func error(world) -> String:
	var latest_relation_event: Dictionary = {}
	for event in world.events:
		if event.type in ["relationship.aid_recorded",
				"relationship.gratitude_recorded", "relationship.harm_recorded"]:
			latest_relation_event["%d:%d" % [event.actor_id, event.target_id]] = event
		if event.type not in ["relationship.aid_recorded",
				"relationship.harm_recorded"] \
				or not event.data.has("party_reaction"):
			continue
		var event_error := _event_error(world, event)
		if not event_error.is_empty():
			return event_error
	for pair in latest_relation_event:
		var event = latest_relation_event[pair]
		if not event.data.has("party_reaction"):
			continue
		var relation = world.personal_relations.get(pair)
		if relation == null or not relation.has_processed(event.cause_id):
			return "party_relationship_state_source_missing"
		if event.type == "relationship.aid_recorded" \
				and (relation.gratitude != int(event.data.get("gratitude", -1)) \
				or relation.personal_trust_delta \
				!= int(event.data.get("personal_trust_delta", -1000))):
			return "party_relationship_state_projection_mismatch"
		if event.type == "relationship.harm_recorded" \
				and (relation.grievance != int(event.data.get("grievance", -1)) \
				or relation.personal_trust_delta \
				!= int(event.data.get("personal_trust_delta", -1000))):
			return "party_relationship_state_projection_mismatch"
	return ""


static func _event_error(world, event) -> String:
	var metadata: Variant = event.data.get("party_reaction")
	var metadata_error := ModelScript.metadata_error(metadata, event.magnitude)
	if not metadata_error.is_empty():
		return metadata_error
	var reaction_kind := str(metadata.reaction_kind)
	var expected_event_type := "relationship.aid_recorded" \
		if reaction_kind in ModelScript.AID_KINDS else "relationship.harm_recorded"
	var expected_data_keys := ["gratitude", "party_reaction",
		"personal_trust_delta"] if expected_event_type \
		== "relationship.aid_recorded" else ["grievance", "party_reaction",
			"personal_trust_delta"]
	var actual_data_keys: Array = event.data.keys(); actual_data_keys.sort()
	var source = world.event_by_id(event.cause_id)
	var historical_position: Dictionary = world._entity_position_at_event(
		event.actor_id, event.id)
	if actual_data_keys != expected_data_keys \
			or not event.data.get("personal_trust_delta") is int \
			or expected_event_type == "relationship.aid_recorded" \
			and not event.data.get("gratitude") is int \
			or expected_event_type == "relationship.harm_recorded" \
			and not event.data.get("grievance") is int \
			or event.type != expected_event_type or event.actor_id == event.target_id \
			or event.actor_id not in world._party_active_ids_at_event(event.id) \
			or source == null or source.id >= event.id \
			or source.step_index != event.step_index \
			or source.world_time != event.world_time \
			or not bool(historical_position.get("ok", false)) \
			or event.position != historical_position.position:
		return "party_relationship_event_envelope_invalid"
	var member = world.party_encounter.member(event.actor_id)
	if member == null or int(metadata.personality_multiplier_milli) \
			!= ModelScript.multiplier_for(member.personality_profile, reaction_kind):
		return "party_relationship_personality_mismatch"
	var expected_base := _expected_base(world, event, source, metadata)
	if expected_base <= 0 or int(metadata.base_magnitude) != expected_base:
		return "party_relationship_source_mismatch"
	var relation = world.personal_relations.get(
		"%d:%d" % [event.actor_id, event.target_id])
	if relation == null or not relation.has_processed(source.id):
		return "party_relationship_state_source_missing"
	return ""


static func _expected_base(world, event, source, metadata: Dictionary) -> int:
	var observer_id := int(event.actor_id)
	var subject_id := int(event.target_id)
	match str(metadata.reaction_kind):
		"AID_RECEIVED":
			if source.type == "health.restored" and source.target_id == observer_id \
					and source.actor_id == subject_id \
					and subject_id in world._party_active_ids_at_event(source.id):
				return clampi(8 + source.magnitude * 2, 8, 45)
		"DIRECT_HARM":
			if source.type in ["combat.physical_damage", "combat.downed_damage"] \
					and source.target_id == observer_id \
					and source.instigator_id == subject_id \
					and subject_id in world.party_encounter.enemy_ids:
				return clampi(3 + source.magnitude, 3, 20)
		"ALLY_DOWNED", "ALLY_LOST":
			var source_type := "entity.died" \
				if str(metadata.reaction_kind) == "ALLY_LOST" else "entity.downed"
			if source.type == source_type and source.target_id != observer_id \
					and source.target_id in world._party_active_ids_at_event(source.id) \
					and source.instigator_id == subject_id \
					and subject_id in world.party_encounter.enemy_ids:
				return 35 if source_type == "entity.died" else 18
		"AVENGED_HARM":
			if source.type == "entity.died" \
					and source.target_id in world.party_encounter.enemy_ids \
					and source.instigator_id == subject_id \
					and subject_id in world._party_active_ids_at_event(source.id) \
					and observer_id != subject_id \
					and _evidence_is_recorded(world, observer_id, event.id,
						int(metadata.evidence_source_event_id),
						int(metadata.evidence_salience), source.target_id, source.id):
				return clampi(8 + int(metadata.evidence_salience) / 50, 8, 28)
		"COMMAND_CONFLICT":
			if source.type == "party.override_committed" \
					and source.actor_id == observer_id \
					and subject_id == world.party_encounter.protagonist_id:
				return clampi(8 + source.magnitude / 3, 8, 30)
	return -1


static func _evidence_is_recorded(world, observer_id: int,
		reaction_event_id: int, evidence_source_id: int, evidence_salience: int,
		enemy_id: int, avenged_source_id: int) -> bool:
	if evidence_source_id <= 0 or evidence_source_id >= avenged_source_id \
			or avenged_source_id >= reaction_event_id:
		return false
	var latest: Dictionary = {}
	for event in world.events:
		if event.id >= reaction_event_id:
			break
		if event.type != "party.memory_changed" or event.actor_id != observer_id:
			continue
		for record_value in event.data.get("state_after", {}).get("records", []):
			var record: Dictionary = record_value
			if Int64CodecScript.is_canonical(record.get("source_event_id")) \
					and Int64CodecScript.parse(record.source_event_id,
						"relationship evidence") == evidence_source_id:
				latest = record
	if latest.is_empty() or str(latest.get("kind", "")) \
			not in ["SELF_HARM", "ALLY_DOWNED", "ALLY_LOST"] \
			or int(latest.get("salience", 0)) != evidence_salience \
			or not Int64CodecScript.is_canonical(latest.get("instigator_id")) \
			or Int64CodecScript.parse(latest.instigator_id,
				"relationship evidence instigator") != enemy_id:
		return false
	return true
