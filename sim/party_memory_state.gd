class_name PartyMemoryState
extends RefCounted

const SCHEMA_VERSION := 1
const MAX_RECORDS := 8
const KINDS := ["SELF_HARM", "ALLY_DOWNED", "ALLY_LOST", "AID_RECEIVED",
	"COMMAND_CONFLICT"]
const Int64CodecScript = preload("res://sim/int64_codec.gd")
const MAX_WORLD_TIME := 9223372036854775707

var records: Array[Dictionary] = []


func remember(kind: String, source_event_id: int, observed_time: int,
		subject_id: int, instigator_id: int, salience: int) -> bool:
	if kind not in KINDS or source_event_id <= 0 or observed_time < 0 \
			or subject_id <= 0 or instigator_id < -1 or salience < 1:
		return false
	for row in records:
		if int(row.source_event_id) == source_event_id:
			return false
	var candidate := {"kind":kind, "source_event_id":source_event_id,
		"observed_time":observed_time, "subject_id":subject_id,
		"instigator_id":instigator_id, "salience":clampi(salience, 1, 1000)}
	if records.size() >= MAX_RECORDS:
		var weakest_index := _weakest_index()
		var weakest: Dictionary = records[weakest_index]
		if not _is_more_retained(candidate, weakest):
			return false
		records.remove_at(weakest_index)
	records.append(candidate)
	_sort_records()
	return true


func strongest(kinds: Array, subject_id: int = -1,
		instigator_id: int = -1) -> Dictionary:
	var best: Dictionary = {}
	for row in records:
		if str(row.kind) not in kinds \
				or subject_id > 0 and int(row.subject_id) != subject_id \
				or instigator_id > 0 and int(row.instigator_id) != instigator_id:
			continue
		if best.is_empty() or _is_more_retained(row, best):
			best = row
	return best.duplicate(true)


func salience_for_subject(subject_id: int, kinds: Array) -> int:
	var row := strongest(kinds, subject_id)
	return int(row.get("salience", 0))


func salience_for_instigator(instigator_id: int, kinds: Array) -> int:
	var row := strongest(kinds, -1, instigator_id)
	return int(row.get("salience", 0))


func to_dict() -> Dictionary:
	var rows: Array[Dictionary] = []
	for record in records:
		rows.append({"kind":str(record.kind),
			"source_event_id":str(int(record.source_event_id)),
			"observed_time":str(int(record.observed_time)),
			"subject_id":str(int(record.subject_id)),
			"instigator_id":str(int(record.instigator_id)),
			"salience":int(record.salience)})
	return {"schema_version":SCHEMA_VERSION, "records":rows}


static func from_dict(row: Dictionary):
	var state = load("res://sim/party_memory_state.gd").new()
	for record_value in row.get("records", []):
		var record: Dictionary = record_value
		state.records.append({"kind":str(record.kind),
			"source_event_id":Int64CodecScript.parse(record.source_event_id,
				"party memory source"),
			"observed_time":Int64CodecScript.parse(record.observed_time,
				"party memory time"),
			"subject_id":Int64CodecScript.parse(record.subject_id,
				"party memory subject"),
			"instigator_id":Int64CodecScript.parse(record.instigator_id,
				"party memory instigator"),
			"salience":int(record.salience)})
	return state


static func wire_error(row: Variant) -> String:
	if not row is Dictionary:
		return "invalid_party_memory_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["records", "schema_version"] \
			or row.get("schema_version") != SCHEMA_VERSION \
			or not row.get("records") is Array \
			or row.records.size() > MAX_RECORDS:
		return "invalid_party_memory_header"
	var previous_time := -1
	var previous_source := -1
	var seen_sources: Dictionary = {}
	for record_value in row.records:
		if not record_value is Dictionary:
			return "invalid_party_memory_record"
		var record: Dictionary = record_value
		var record_keys: Array = record.keys(); record_keys.sort()
		if record_keys != ["instigator_id", "kind", "observed_time", "salience",
				"source_event_id", "subject_id"] \
				or record.get("kind") not in KINDS \
				or not Int64CodecScript.is_canonical(record.get("source_event_id")) \
				or not Int64CodecScript.is_canonical(record.get("observed_time")) \
				or not Int64CodecScript.is_canonical(record.get("subject_id")) \
				or not Int64CodecScript.is_canonical(record.get("instigator_id")) \
				or not _integer(record.get("salience")) \
				or int(record.salience) < 1 or int(record.salience) > 1000:
			return "invalid_party_memory_record"
		var source := Int64CodecScript.parse(record.source_event_id, "memory source")
		var time := Int64CodecScript.parse(record.observed_time, "memory time")
		var subject := Int64CodecScript.parse(record.subject_id, "memory subject")
		var instigator := Int64CodecScript.parse(record.instigator_id,
			"memory instigator")
		if source <= 0 or time < 0 or time > MAX_WORLD_TIME or subject <= 0 \
				or instigator < -1 or seen_sources.has(source) \
				or time < previous_time \
				or time == previous_time and source <= previous_source:
			return "invalid_party_memory_record"
		seen_sources[source] = true
		previous_time = time
		previous_source = source
	return ""


static func transition_magnitude(before: Dictionary, after: Dictionary) -> int:
	var before_rows: Dictionary = {}
	for row in before.records:
		before_rows[str(row.source_event_id)] = int(row.salience)
	var after_rows: Dictionary = {}
	for row in after.records:
		after_rows[str(row.source_event_id)] = int(row.salience)
	var source_ids: Array = before_rows.keys()
	for source_id in after_rows:
		if source_id not in source_ids:
			source_ids.append(source_id)
	var total := 0
	for source_id in source_ids:
		total += absi(int(after_rows.get(source_id, 0)) \
			- int(before_rows.get(source_id, 0)))
	return maxi(1, total)


func _weakest_index() -> int:
	var weakest := 0
	for index in range(1, records.size()):
		if _is_more_retained(records[weakest], records[index]):
			weakest = index
	return weakest


func _sort_records() -> void:
	records.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.observed_time) != int(b.observed_time):
			return int(a.observed_time) < int(b.observed_time)
		return int(a.source_event_id) < int(b.source_event_id))


static func _is_more_retained(a: Dictionary, b: Dictionary) -> bool:
	if int(a.salience) != int(b.salience):
		return int(a.salience) > int(b.salience)
	if int(a.observed_time) != int(b.observed_time):
		return int(a.observed_time) > int(b.observed_time)
	return int(a.source_event_id) > int(b.source_event_id)


static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))
