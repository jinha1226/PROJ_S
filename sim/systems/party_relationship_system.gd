class_name PartyRelationshipSystem
extends RefCounted

const ModelScript = preload("res://sim/party_relationship_model.gd")
const RelationshipSystemScript = preload("res://sim/systems/relationship_system.gd")


static func commit_batch(world, event_rows: Array) -> bool:
	if world == null or world.party_encounter == null:
		return true
	var projection: Dictionary = ModelScript.evaluate(world, event_rows)
	var relationships = RelationshipSystemScript.new(world)
	var changed := false
	for row_value in projection.reaction_rows:
		var row: Dictionary = row_value
		var accepted := relationships.record_aid(int(row.observer_id),
			int(row.subject_id), int(row.source_event_id), int(row.magnitude),
			row.metadata) if str(row.channel) == "AID" else \
			relationships.record_harm(int(row.observer_id), int(row.subject_id),
				int(row.source_event_id), int(row.magnitude), row.metadata)
		if not accepted:
			return false
		changed = true
	if changed:
		world.party_encounter.revision += 1
	return true
