class_name PartyMoraleSystem
extends RefCounted

const ModelScript = preload("res://sim/party_morale_model.gd")


static func commit_batch(world, event_rows: Array, allow_idle_recovery: bool = true) -> bool:
	if world == null or world.party_encounter == null:
		return true
	var source_ids := _source_event_ids(world, event_rows)
	# Environment/actor cadence may run back-to-back at the same timestamp. An
	# empty cadence is not another morale recovery turn; the owning player action
	# is the sole idle-recovery boundary.
	if source_ids.is_empty() and not allow_idle_recovery:
		return true
	var previous_modes := {}
	for member_id in world.party_encounter.active_party_member_ids:
		var member = world.party_encounter.member(int(member_id))
		if member != null:
			previous_modes[int(member_id)] = str(member.mental_mode)
	var projection: Dictionary = ModelScript.evaluate(world, event_rows, previous_modes)
	var cause_id := int(source_ids.back()) if not source_ids.is_empty() else -1
	var source_wire: Array[String] = []
	for source_id in source_ids:
		source_wire.append(str(source_id))
	var changed := false
	for row in projection.member_rows:
		var member_id := int(row.entity_id)
		var member = world.party_encounter.member(member_id)
		if member == null or not world.entities.has(member_id):
			return false
		if int(row.stress_before) == int(row.stress_after) \
				and str(row.mode_before) == str(row.mode_after):
			continue
		var event = world.emit_event("party.morale_changed", member_id, -1,
			world.entities[member_id].position,
			absi(int(row.stress_after) - int(row.stress_before)), cause_id, {
				"schema_version":1, "ruleset_id":ModelScript.RULESET_ID,
				"stress_before":int(row.stress_before),
				"direct_delta":int(row.direct_delta),
				"contagion_delta":int(row.contagion_delta),
				"recovery_delta":int(row.recovery_delta),
				"stress_after":int(row.stress_after),
				"mode_before":str(row.mode_before),
				"mode_after":str(row.mode_after),
				"trigger_codes":row.trigger_codes.duplicate(),
				"source_event_ids":source_wire.duplicate(),
			})
		if event == null:
			return false
		member.stress = int(row.stress_after)
		member.mental_mode = str(row.mode_after)
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
		var relevant: bool = event_type in ["combat.physical_damage", "combat.downed_damage"] \
			and target_id in world.party_encounter.party_member_ids
		if event_type == "party.override_committed":
			relevant = actor_id in world.party_encounter.party_member_ids
		if event_type == "entity.downed":
			relevant = target_id in world.party_encounter.party_member_ids
		elif event_type == "entity.died":
			relevant = target_id in world.party_encounter.party_member_ids \
				or target_id in world.party_encounter.enemy_ids
		if not relevant:
			continue
		var event_id := int(event.get("id", -1) if event is Dictionary else event.id)
		if event_id > 0 and event_id not in result:
			result.append(event_id)
	result.sort()
	return result
