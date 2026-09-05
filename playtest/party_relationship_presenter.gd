class_name PartyRelationshipPresenter
extends RefCounted

const ModelScript = preload("res://sim/party_relationship_model.gd")
const RelationshipSystemScript = preload("res://sim/systems/relationship_system.gd")
const LABELS := {
	"AID_RECEIVED":"도움에 감사함",
	"DIRECT_HARM":"피해를 원망함",
	"ALLY_DOWNED":"동료를 해친 적을 원망함",
	"ALLY_LOST":"동료를 죽인 적을 증오함",
	"AVENGED_HARM":"원한을 갚아 준 일에 감사함",
	"COMMAND_CONFLICT":"원치 않는 지시에 반발함",
}


static func observation(world) -> Dictionary:
	var empty := {"schema_version":1, "ruleset_id":ModelScript.RULESET_ID,
		"available":false, "sampled_step_index":-1,
		"sampled_world_time":-1, "relations":[]}
	if world == null or world.party_encounter == null:
		return empty.duplicate(true)
	var ids: Array = world.party_encounter.active_party_member_ids.duplicate()
	ids.sort()
	var rows: Array[Dictionary] = []
	for observer_id_value in ids:
		var observer_id := int(observer_id_value)
		for subject_id_value in ids:
			var subject_id := int(subject_id_value)
			if observer_id != subject_id:
				rows.append(relation_row(world, observer_id, subject_id))
	return {"schema_version":1, "ruleset_id":ModelScript.RULESET_ID,
		"available":true, "sampled_step_index":int(world.step_index),
		"sampled_world_time":int(world.world_time),
		"relations":rows}.duplicate(true)


static func relation_row(world, observer_id: int, subject_id: int) -> Dictionary:
	if world == null or not world.entities.has(observer_id) \
			or not world.entities.has(subject_id):
		return {}
	var relation: Dictionary = RelationshipSystemScript.new(world).effective_relation(
		observer_id, subject_id)
	var recent := recent_reaction(world, observer_id, subject_id)
	return {"observer_id":observer_id, "subject_id":subject_id,
		"subject_name":str(world.entities[subject_id].display_name),
		"subject_species_id":str(world.entities[subject_id].species_id),
		"trust":int(relation.get("trust", 0)),
		"fear":int(relation.get("fear", 0)),
		"hostility":int(relation.get("hostility", 0)),
		"gratitude":int(relation.get("gratitude", 0)),
		"grievance":int(relation.get("grievance", 0)),
		"disposition":str(relation.get("disposition", "NEUTRAL")),
		"species_base":relation.get("species_base", {}).duplicate(true),
		"personal":relation.get("personal", {}).duplicate(true),
		"recent_reaction":recent}.duplicate(true)


static func recent_reaction(world, observer_id: int, subject_id: int) -> Dictionary:
	if world == null:
		return {}
	for index in range(world.events.size() - 1, -1, -1):
		var event = world.events[index]
		if event.actor_id != observer_id or event.target_id != subject_id \
				or event.type not in ["relationship.aid_recorded",
					"relationship.harm_recorded"] \
				or not event.data.has("party_reaction"):
			continue
		var metadata: Dictionary = event.data.party_reaction
		var kind := str(metadata.get("reaction_kind", ""))
		return {"reaction_kind":kind,
			"label":str(LABELS.get(kind, "관계가 변함")),
			"reason":_reason(world, observer_id, subject_id, kind),
			"magnitude":int(event.magnitude),
			"source_event_id":int(event.cause_id),
			"relationship_event_id":int(event.id)}
	return {}


static func event_text(world, event) -> String:
	if event == null or not event.data.has("party_reaction"):
		return ""
	var actor_name := _name(world, int(event.actor_id))
	var subject_name := _name(world, int(event.target_id))
	var kind := str(event.data.party_reaction.get("reaction_kind", ""))
	match kind:
		"AID_RECEIVED":
			return "%s %s의 도움을 고맙게 여겼다." % [actor_name, subject_name]
		"DIRECT_HARM":
			return "%s 자신을 해친 %s에게 원한을 품었다." % [actor_name, subject_name]
		"ALLY_DOWNED":
			return "%s 동료를 쓰러뜨린 %s을 원망했다." % [actor_name, subject_name]
		"ALLY_LOST":
			return "%s 동료를 죽인 %s을 증오하게 됐다." % [actor_name, subject_name]
		"AVENGED_HARM":
			return "%s 원한을 갚아 준 %s에게 감사했다." % [actor_name, subject_name]
		"COMMAND_CONFLICT":
			return "%s %s의 원치 않는 지시에 반발했다." % [actor_name, subject_name]
	return ""


static func _reason(world, observer_id: int, subject_id: int, kind: String) -> String:
	var subject_name := _name(world, subject_id)
	match kind:
		"AID_RECEIVED": return "%s에게 직접 치료받았습니다." % subject_name
		"DIRECT_HARM": return "%s에게 직접 피해를 입었습니다." % subject_name
		"ALLY_DOWNED": return "%s이 동료를 쓰러뜨렸습니다." % subject_name
		"ALLY_LOST": return "%s이 동료를 죽였습니다." % subject_name
		"AVENGED_HARM": return "%s이 기억 속 가해자를 쓰러뜨렸습니다." % subject_name
		"COMMAND_CONFLICT": return "%s이 원치 않는 행동을 강제로 지시했습니다." % subject_name
	return "과거 사건이 현재 관계에 영향을 주고 있습니다."


static func _name(world, entity_id: int) -> String:
	return str(world.entities[entity_id].display_name) \
		if world != null and world.entities.has(entity_id) else "상대"
