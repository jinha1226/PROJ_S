class_name RelationshipSystem
extends RefCounted

const PersonalRelationScript = preload("res://sim/personal_relation.gd")
const TRUST_DELTA_LIMIT := 40
const FEAR_DELTA_LIMIT := 30

var world


func _init(p_world) -> void:
	world = p_world


func record_aid(observer_id: int, helper_id: int, source_event_id: int, magnitude: int) -> bool:
	if not _valid_interaction(observer_id, helper_id, source_event_id) or magnitude <= 0:
		return false
	var relation = _get_or_create(observer_id, helper_id)
	if relation.has_processed(source_event_id):
		return false
	relation.processed_source_event_ids.append(source_event_id)
	var amount := clampi(magnitude, 1, 100)
	relation.gratitude = clampi(relation.gratitude + amount, 0, 100)
	relation.personal_trust_delta = clampi(
		relation.personal_trust_delta + ceili(float(amount) / 10.0),
		-TRUST_DELTA_LIMIT, TRUST_DELTA_LIMIT
	)
	relation.personal_fear_delta = clampi(
		relation.personal_fear_delta - floori(float(amount) / 20.0),
		-FEAR_DELTA_LIMIT, FEAR_DELTA_LIMIT
	)
	world.emit_event(
		"relationship.aid_recorded", observer_id, helper_id,
		world.entities[observer_id].position, amount, source_event_id,
		{"gratitude": relation.gratitude, "personal_trust_delta": relation.personal_trust_delta}
	)
	return true


func record_harm(observer_id: int, attacker_id: int, source_event_id: int, magnitude: int) -> bool:
	if not _valid_interaction(observer_id, attacker_id, source_event_id) or magnitude <= 0:
		return false
	var relation = _get_or_create(observer_id, attacker_id)
	if relation.has_processed(source_event_id):
		return false
	relation.processed_source_event_ids.append(source_event_id)
	var amount := clampi(magnitude, 1, 100)
	relation.grievance = clampi(relation.grievance + amount, 0, 100)
	relation.personal_trust_delta = clampi(
		relation.personal_trust_delta - ceili(float(amount) / 5.0),
		-TRUST_DELTA_LIMIT, TRUST_DELTA_LIMIT
	)
	relation.personal_fear_delta = clampi(
		relation.personal_fear_delta + ceili(float(amount) / 4.0),
		-FEAR_DELTA_LIMIT, FEAR_DELTA_LIMIT
	)
	world.emit_event(
		"relationship.harm_recorded", observer_id, attacker_id,
		world.entities[observer_id].position, amount, source_event_id,
		{"grievance": relation.grievance, "personal_trust_delta": relation.personal_trust_delta}
	)
	return true


func effective_relation(observer_id: int, subject_id: int) -> Dictionary:
	if not world.entities.has(observer_id) or not world.entities.has(subject_id):
		return {}
	var observer = world.entities[observer_id]
	var subject = world.entities[subject_id]
	var base: Dictionary = world.species_relations.get_relation(observer.species_id, subject.species_id)
	var relation = world.personal_relations.get(_key(observer_id, subject_id), null)
	var trust_delta := 0
	var fear_delta := 0
	var gratitude := 0
	var grievance := 0
	if relation != null:
		trust_delta = clampi(relation.personal_trust_delta, -TRUST_DELTA_LIMIT, TRUST_DELTA_LIMIT)
		fear_delta = clampi(relation.personal_fear_delta, -FEAR_DELTA_LIMIT, FEAR_DELTA_LIMIT)
		gratitude = relation.gratitude
		grievance = relation.grievance
	var trust := clampi(int(base["base_trust"]) + trust_delta, -100, 100)
	var fear := clampi(int(base["base_fear"]) + fear_delta, 0, 100)
	var hostility := clampi(
		int(base["base_hostility"]) + floori(float(grievance) / 5.0) - floori(float(gratitude) / 10.0),
		0, 100
	)
	return {
		"trust": trust,
		"fear": fear,
		"hostility": hostility,
		"gratitude": gratitude,
		"grievance": grievance,
		"disposition": _disposition(trust, fear, hostility),
	}


func _valid_interaction(observer_id: int, subject_id: int, source_event_id: int) -> bool:
	return (observer_id != subject_id and world.entities.has(observer_id)
		and world.entities.has(subject_id) and world.event_by_id(source_event_id) != null)


func _get_or_create(observer_id: int, subject_id: int):
	var key := _key(observer_id, subject_id)
	if not world.personal_relations.has(key):
		world.personal_relations[key] = PersonalRelationScript.new(observer_id, subject_id)
	return world.personal_relations[key]


func _key(observer_id: int, subject_id: int) -> String:
	return "%d:%d" % [observer_id, subject_id]


func _disposition(trust: int, fear: int, hostility: int) -> String:
	if hostility >= 60:
		return "HOSTILE"
	if trust <= -25 or fear >= 50:
		return "WARY"
	if trust >= 40 and hostility <= 25:
		return "TRUSTING"
	if trust >= 15 and hostility <= 35:
		return "FRIENDLY"
	return "NEUTRAL"
