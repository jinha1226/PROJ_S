class_name PartyMemorySystem
extends RefCounted

const ModelScript = preload("res://sim/party_memory_model.gd")
const StateScript = preload("res://sim/party_memory_state.gd")


static func commit_batch(world, event_rows: Array) -> bool:
	if world == null or world.party_encounter == null:
		return true
	var source_ids := _source_event_ids(world, event_rows)
	if source_ids.is_empty():
		return true
	var projection: Dictionary = ModelScript.evaluate(world, event_rows)
	var source_wire: Array[String] = []
	for source_id in source_ids:
		source_wire.append(str(source_id))
	var changed := false
	for row in projection.member_rows:
		var member_id := int(row.entity_id)
		var member = world.party_encounter.member(member_id)
		if member == null or not world.entities.has(member_id) \
				or not StateScript.wire_error(row.state_before).is_empty() \
				or not StateScript.wire_error(row.state_after).is_empty():
			return false
		var magnitude := StateScript.transition_magnitude(
			row.state_before, row.state_after)
		var event = world.emit_event("party.memory_changed", member_id, -1,
			world.entities[member_id].position, magnitude, int(source_ids.back()), {
				"schema_version":1, "ruleset_id":ModelScript.RULESET_ID,
				"state_before":row.state_before.duplicate(true),
				"state_after":row.state_after.duplicate(true),
				"trigger_codes":row.trigger_codes.duplicate(),
				"source_event_ids":source_wire.duplicate(),
			})
		if event == null:
			return false
		member.memory_state = StateScript.from_dict(row.state_after)
		changed = true
	if changed:
		world.party_encounter.revision += 1
	return true


static func _source_event_ids(world, event_rows: Array) -> Array[int]:
	var result: Array[int] = []
	for event in event_rows:
		var event_type := str(event.get("type", "") if event is Dictionary else event.type)
		var actor_id := int(event.get("actor_id", -1) if event is Dictionary else event.actor_id)
		var target_id := int(event.get("target_id", -1) if event is Dictionary else event.target_id)
		var relevant := false
		if event_type in ["combat.physical_damage", "combat.downed_damage",
				"entity.downed", "entity.died", "health.restored"]:
			relevant = target_id in world.party_encounter.party_member_ids
		elif event_type == "party.override_committed":
			relevant = actor_id in world.party_encounter.party_member_ids
		if not relevant:
			continue
		var event_id := int(event.get("id", -1) if event is Dictionary else event.id)
		if event_id > 0 and event_id not in result:
			result.append(event_id)
	result.sort()
	return result
