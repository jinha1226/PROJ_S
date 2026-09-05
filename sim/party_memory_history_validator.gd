class_name PartyMemoryHistoryValidator
extends RefCounted

const ModelScript = preload("res://sim/party_memory_model.gd")
const StateScript = preload("res://sim/party_memory_state.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")
const SOURCE_TYPES := ["combat.physical_damage", "combat.downed_damage",
	"entity.downed", "entity.died", "health.restored", "party.override_committed"]


static func error(world) -> String:
	var latest_by_actor: Dictionary = {}
	var previous_after_by_actor: Dictionary = {}
	for event in world.events:
		if event.type != "party.memory_changed":
			continue
		var event_error := _event_error(world, event, previous_after_by_actor)
		if not event_error.is_empty():
			return event_error
		previous_after_by_actor[event.actor_id] = event.data.state_after.duplicate(true)
		latest_by_actor[event.actor_id] = event
	for member_id in world.party_encounter.active_party_member_ids:
		if not latest_by_actor.has(member_id):
			continue
		var member = world.party_encounter.member(member_id)
		if member == null or member.memory_state.to_dict() \
				!= latest_by_actor[member_id].data.state_after:
			return "party_memory_state_projection_mismatch"
	return ""


static func _event_error(world, event,
		previous_after_by_actor: Dictionary) -> String:
	if event.actor_id not in world._party_active_ids_at_event(event.id) \
			or event.target_id != -1:
		return "party_memory_actor_invalid"
	var historical_position: Dictionary = world._entity_position_at_event(
		event.actor_id, event.id)
	if not bool(historical_position.get("ok", false)) \
			or event.position != historical_position.position:
		return "party_memory_position_invalid"
	var keys := ["ruleset_id", "schema_version", "source_event_ids",
		"state_after", "state_before", "trigger_codes"]
	if not _exact_keys(event.data, keys) \
			or event.data.get("schema_version") != 1 \
			or event.data.get("ruleset_id") != ModelScript.RULESET_ID \
			or not StateScript.wire_error(event.data.get("state_before")).is_empty() \
			or not StateScript.wire_error(event.data.get("state_after")).is_empty():
		return "party_memory_data_invalid"
	var before: Dictionary = event.data.state_before
	var after: Dictionary = event.data.state_after
	if previous_after_by_actor.has(event.actor_id) \
			and before != previous_after_by_actor[event.actor_id]:
		return "party_memory_chain_invalid"
	if event.magnitude != StateScript.transition_magnitude(before, after):
		return "party_memory_projection_invalid"
	var trigger_error := _trigger_error(event.data.get("trigger_codes"))
	if not trigger_error.is_empty():
		return trigger_error
	var source_error := _source_error(world, event)
	if not source_error.is_empty():
		return source_error
	for record_value in after.records:
		var record_error := _record_error(world, event.actor_id, event.id,
			record_value)
		if not record_error.is_empty():
			return record_error
	return ""


static func _trigger_error(value: Variant) -> String:
	if not value is Array or value.is_empty():
		return "party_memory_trigger_invalid"
	var previous := ""
	for trigger in value:
		if not trigger is String or trigger not in StateScript.KINDS \
				or str(trigger) <= previous:
			return "party_memory_trigger_invalid"
		previous = str(trigger)
	return ""


static func _source_error(world, event) -> String:
	var rows: Variant = event.data.get("source_event_ids")
	if not rows is Array or rows.is_empty() or rows.size() > 128:
		return "party_memory_source_invalid"
	var previous := -1
	for source_wire in rows:
		if not Int64CodecScript.is_canonical(source_wire):
			return "party_memory_source_invalid"
		var source_id := Int64CodecScript.parse(source_wire, "memory source")
		var source = world.event_by_id(source_id)
		if source_id <= previous or source_id >= event.id or source == null \
				or source.step_index != event.step_index or source.type not in SOURCE_TYPES:
			return "party_memory_source_invalid"
		previous = source_id
	return "" if event.cause_id == previous else "party_memory_source_invalid"


static func _record_error(world, observer_id: int, memory_event_id: int,
		record_value: Variant) -> String:
	var record: Dictionary = record_value
	var source_id := Int64CodecScript.parse(record.source_event_id,
		"memory record source")
	var source = world.event_by_id(source_id)
	var subject_id := Int64CodecScript.parse(record.subject_id, "memory subject")
	var instigator_id := Int64CodecScript.parse(record.instigator_id,
		"memory instigator")
	if source == null or source_id >= memory_event_id \
			or not world.entities.has(subject_id) \
			or instigator_id > 0 and not world.entities.has(instigator_id) \
			or Int64CodecScript.parse(record.observed_time, "memory time") \
			!= source.world_time \
			or not _record_matches_source(world, observer_id, record, source):
		return "party_memory_record_invalid"
	return ""


static func _record_matches_source(world, observer_id: int,
		record: Dictionary, source) -> bool:
	var kind := str(record.kind)
	var subject_id := Int64CodecScript.parse(record.subject_id, "memory subject")
	var instigator_id := Int64CodecScript.parse(record.instigator_id,
		"memory instigator")
	match kind:
		"SELF_HARM":
			return source.type in ["combat.physical_damage", "combat.downed_damage"] \
				and source.target_id == observer_id and subject_id == source.instigator_id \
				and instigator_id == source.instigator_id
		"ALLY_DOWNED":
			return source.type == "entity.downed" and source.target_id == subject_id \
				and subject_id != observer_id \
				and instigator_id == (source.instigator_id \
					if source.instigator_id in world.party_encounter.enemy_ids else -1)
		"ALLY_LOST":
			return source.type == "entity.died" and source.target_id == subject_id \
				and subject_id != observer_id \
				and instigator_id == (source.instigator_id \
					if source.instigator_id in world.party_encounter.enemy_ids else -1)
		"AID_RECEIVED":
			return source.type == "health.restored" and source.target_id == observer_id \
				and source.actor_id == subject_id and instigator_id == source.actor_id
		"COMMAND_CONFLICT":
			return source.type == "party.override_committed" \
				and source.actor_id == observer_id \
				and subject_id == world.party_encounter.protagonist_id \
				and instigator_id == world.party_encounter.protagonist_id
	return false


static func _exact_keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary:
		return false
	var actual_keys: Array = value.keys(); actual_keys.sort()
	var expected_keys: Array = expected.duplicate(); expected_keys.sort()
	return actual_keys == expected_keys
