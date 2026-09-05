class_name PartyMemoryPresenter
extends RefCounted

const ModelScript = preload("res://sim/party_memory_model.gd")
const StateScript = preload("res://sim/party_memory_state.gd")
const PRESENTATION := {
	"SELF_HARM":{"label":"나를 해침", "behavior":"그 가해자를 더 위험하고 공격할 대상으로 판단"},
	"ALLY_DOWNED":{"label":"동료를 쓰러뜨림", "behavior":"가해자를 경계하고 쓰러진 동료를 보호"},
	"ALLY_LOST":{"label":"동료를 잃음", "behavior":"가해자를 오래 기억하고 우선 공격할 수 있음"},
	"AID_RECEIVED":{"label":"도움을 받음", "behavior":"도움을 준 동료가 위험하면 보호를 선호"},
	"COMMAND_CONFLICT":{"label":"원치 않는 지시", "behavior":"주인공과의 갈등 판단에 남음"},
}


static func observation(world) -> Dictionary:
	var empty := {"schema_version":1, "ruleset_id":ModelScript.RULESET_ID,
		"available":false, "capacity":StateScript.MAX_RECORDS,
		"sampled_step_index":-1, "sampled_world_time":-1, "members":[]}
	if world == null or world.party_encounter == null:
		return empty.duplicate(true)
	var state = world.party_encounter
	var member_ids: Array = state.active_party_member_ids.duplicate()
	member_ids.sort_custom(func(a,b):
		var member_a=state.member(int(a));var member_b=state.member(int(b))
		return int(member_a.roster_slot)<int(member_b.roster_slot) \
			if int(member_a.roster_slot)!=int(member_b.roster_slot) else int(a)<int(b))
	var members: Array[Dictionary] = []
	for member_id_value in member_ids:
		var member_id := int(member_id_value)
		var member = state.member(member_id)
		var entity = world.entities.get(member_id)
		if member == null or entity == null or member.memory_state == null:
			continue
		var presentation := member_summary(world, member)
		members.append({"entity_id":member_id,
			"display_name":str(entity.display_name), "role":str(member.role),
			"summary_label":str(presentation.summary_label),
			"summary_reason":str(presentation.summary_reason),
			"retained_count":int(presentation.retained_count),
			"memories":presentation.memories.duplicate(true)})
	return {"schema_version":1, "ruleset_id":ModelScript.RULESET_ID,
		"available":true, "capacity":StateScript.MAX_RECORDS,
		"sampled_step_index":int(world.step_index),
		"sampled_world_time":int(world.world_time),
		"members":members}.duplicate(true)


static func member_summary(world, member) -> Dictionary:
	if member == null or member.memory_state == null \
			or member.memory_state.records.is_empty():
		return {"summary_label":"남은 기억 없음",
			"summary_reason":"행동에 영향을 줄 만큼 중요한 사건이 아직 없습니다.",
			"retained_count":0, "memories":[]}
	var records: Array = member.memory_state.records.duplicate(true)
	records.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.salience) != int(b.salience):
			return int(a.salience) > int(b.salience)
		if int(a.observed_time) != int(b.observed_time):
			return int(a.observed_time) > int(b.observed_time)
		return int(a.source_event_id) > int(b.source_event_id))
	var rows: Array[Dictionary] = []
	for record_value in records.slice(0, 3):
		var record: Dictionary = record_value
		var kind := str(record.kind)
		var spec: Dictionary = PRESENTATION.get(kind,
			{"label":"과거 사건", "behavior":"현재 판단에 영향을 줌"})
		var subject_id := int(record.subject_id)
		var instigator_id := int(record.instigator_id)
		rows.append({"kind":kind, "label":str(spec.label),
			"salience":int(record.salience),
			"salience_band":_intensity_band(int(record.salience)),
			"subject_id":subject_id,
			"subject_name":_entity_name(world, subject_id),
			"instigator_id":instigator_id,
			"instigator_name":_entity_name(world, instigator_id),
			"source_event_id":int(record.source_event_id),
			"observed_world_time":int(record.observed_time),
			"behavior_hint":str(spec.behavior)})
	var strongest: Dictionary = rows[0]
	var reason := str(strongest.label)
	if not str(strongest.subject_name).is_empty():
		reason += " · %s" % str(strongest.subject_name)
	return {"summary_label":str(strongest.label),
		"summary_reason":"%s (%s)" % [reason, str(strongest.salience_band)],
		"retained_count":records.size(), "memories":rows}.duplicate(true)


static func _entity_name(world, entity_id: int) -> String:
	return str(world.entities[entity_id].display_name) \
		if world != null and entity_id > 0 and world.entities.has(entity_id) else ""


static func _intensity_band(value: int) -> String:
	if value >= 800: return "압도적"
	if value >= 600: return "강함"
	if value >= 400: return "뚜렷함"
	if value >= 200: return "약함"
	return "미약함"
