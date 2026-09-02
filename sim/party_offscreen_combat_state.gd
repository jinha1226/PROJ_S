class_name PartyOffscreenCombatState
extends RefCounted

const ModelScript = preload("res://sim/party_offscreen_combat_model.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")

const SCHEMA_VERSION := 1
const RULESET_ID := "party-offscreen-authority-v1"
const MAX_EVENT_ROWS := 100000
const TOP_LEVEL_KEYS := ["current_world_time", "damage_remainder_rows",
	"encounter_id", "encounter_phase", "event_rows", "next_event_id",
	"next_round_at", "observed_by_player", "pending_player_choice",
	"protagonist_participates", "round_index", "ruleset_id", "schema_version",
	"side_rows", "state_hash", "within_detailed_radius"]
const EVENT_KEYS := ["cause_id", "data", "event_id", "magnitude", "round_index",
	"target_id", "type", "world_time"]
const EVENT_TYPES := ["offscreen.damage_resolved", "offscreen.entity_downed",
	"offscreen.entity_died", "offscreen.round_resolved",
	"offscreen.encounter_resolved"]

var encounter_id: int = -1
var encounter_phase := "ENGAGED"
var current_world_time: int = 0
var next_round_at: int = 0
var round_index: int = 0
var protagonist_participates := false
var observed_by_player := false
var within_detailed_radius := false
var pending_player_choice := false
var side_rows: Array = []
var damage_remainders: Dictionary = {}
var event_rows: Array = []
var next_event_id: int = 1


static func create(input_value: Variant) -> Dictionary:
	var input_error := ModelScript.data_error(input_value)
	if not input_error.is_empty():
		return {"accepted":false, "reason_code":input_error, "state":null}
	var assessment: Dictionary = ModelScript.assess(input_value)
	if not bool(assessment.eligible):
		return {"accepted":false, "reason_code":str(assessment.reason_code),
			"state":null}
	var input: Dictionary = input_value
	var state = load("res://sim/party_offscreen_combat_state.gd").new()
	state.encounter_id = int(input.encounter_id)
	state.encounter_phase = str(input.encounter_phase)
	state.current_world_time = int(input.world_time)
	state.next_round_at = int(input.world_time)
	state.round_index = int(input.round_index)
	state.protagonist_participates = bool(input.protagonist_participates)
	state.observed_by_player = bool(input.observed_by_player)
	state.within_detailed_radius = bool(input.within_detailed_radius)
	state.pending_player_choice = bool(input.pending_player_choice)
	state.side_rows = _canonical_sides(input.side_rows)
	for side in state.side_rows:
		for member in side.member_rows:
			state.damage_remainders[int(member.entity_id)] = 0
	var state_error: String = state.validation_error()
	return {"accepted":state_error.is_empty(),
		"reason_code":"ok" if state_error.is_empty() else state_error,
		"state":state if state_error.is_empty() else null}


func clone():
	return get_script().from_dict(to_dict())


func model_input(at_world_time: int = -1) -> Dictionary:
	return {
		"schema_version":ModelScript.SCHEMA_VERSION,
		"encounter_id":encounter_id,
		"encounter_phase":encounter_phase,
		"world_time":current_world_time if at_world_time < 0 else at_world_time,
		"round_index":round_index,
		"protagonist_participates":protagonist_participates,
		"observed_by_player":observed_by_player,
		"within_detailed_radius":within_detailed_radius,
		"pending_player_choice":pending_player_choice,
		"side_rows":_canonical_sides(side_rows),
	}


func to_dict() -> Dictionary:
	var core := _wire_without_hash()
	core["state_hash"] = JSON.stringify(core).sha256_text()
	return core


static func from_dict(value: Variant):
	if not value is Dictionary:
		return null
	var row: Dictionary = value
	var keys: Array = row.keys(); keys.sort()
	if keys != TOP_LEVEL_KEYS or row.get("schema_version") != SCHEMA_VERSION \
			or row.get("ruleset_id") != RULESET_ID:
		return null
	for key in ["encounter_id", "current_world_time", "next_round_at",
			"round_index", "next_event_id"]:
		if not Int64CodecScript.is_canonical(row.get(key)):
			return null
	for key in ["protagonist_participates", "observed_by_player",
			"within_detailed_radius", "pending_player_choice"]:
		if not row.get(key) is bool:
			return null
	if not row.get("encounter_phase") is String \
			or not row.get("side_rows") is Array \
			or not row.get("damage_remainder_rows") is Array \
			or not row.get("event_rows") is Array \
			or not row.get("state_hash") is String:
		return null
	var state = load("res://sim/party_offscreen_combat_state.gd").new()
	state.encounter_id = Int64CodecScript.parse(row.encounter_id, "offscreen encounter ID")
	state.encounter_phase = str(row.encounter_phase)
	state.current_world_time = Int64CodecScript.parse(
		row.current_world_time, "offscreen current time")
	state.next_round_at = Int64CodecScript.parse(row.next_round_at, "offscreen next round")
	state.round_index = Int64CodecScript.parse(row.round_index, "offscreen round")
	state.next_event_id = Int64CodecScript.parse(row.next_event_id, "offscreen next event")
	state.protagonist_participates = bool(row.protagonist_participates)
	state.observed_by_player = bool(row.observed_by_player)
	state.within_detailed_radius = bool(row.within_detailed_radius)
	state.pending_player_choice = bool(row.pending_player_choice)
	state.side_rows = _sides_from_wire(row.side_rows)
	if state.side_rows.is_empty():
		return null
	var previous_entity_id := -1
	for remainder_value in row.damage_remainder_rows:
		if not remainder_value is Dictionary:
			return null
		var remainder: Dictionary = remainder_value
		var remainder_keys: Array = remainder.keys(); remainder_keys.sort()
		if remainder_keys != ["entity_id", "remainder_milli"] \
				or not Int64CodecScript.is_canonical(remainder.get("entity_id")) \
				or not _integer_value(remainder.get("remainder_milli")):
			return null
		var entity_id := Int64CodecScript.parse(remainder.entity_id,
			"offscreen remainder entity")
		if entity_id <= previous_entity_id:
			return null
		previous_entity_id = entity_id
		state.damage_remainders[entity_id] = int(remainder.remainder_milli)
	for event_value in row.event_rows:
		var event := _event_from_wire(event_value)
		if event.is_empty():
			return null
		state.event_rows.append(event)
	var validation: String = state.validation_error()
	if not validation.is_empty():
		return null
	var canonical: Dictionary = state.to_dict()
	if str(row.state_hash) != str(canonical.state_hash):
		return null
	return state


func validation_error() -> String:
	if encounter_id <= 0 or current_world_time < 0 or round_index < 0 \
			or next_event_id <= 0 or encounter_phase not in ["ENGAGED", "TERMINAL"]:
		return "invalid_offscreen_authority_scalar"
	if encounter_phase == "ENGAGED":
		if next_round_at < current_world_time:
			return "invalid_offscreen_next_round"
	elif next_round_at != -1:
		return "terminal_offscreen_round_scheduled"
	var input_error := ModelScript.data_error(model_input(
		current_world_time if next_round_at < 0 else next_round_at))
	if not input_error.is_empty():
		return input_error
	var member_ids: Array[int] = []
	for side in side_rows:
		for member in side.member_rows:
			member_ids.append(int(member.entity_id))
	member_ids.sort()
	if damage_remainders.size() != member_ids.size():
		return "offscreen_remainder_set_mismatch"
	for entity_id in member_ids:
		if not damage_remainders.has(entity_id) \
				or int(damage_remainders[entity_id]) < 0 \
				or int(damage_remainders[entity_id]) > 999:
			return "invalid_offscreen_remainder"
	if event_rows.size() > MAX_EVENT_ROWS or next_event_id != event_rows.size() + 1:
		return "invalid_offscreen_event_sequence"
	var prior_events: Dictionary = {}
	var previous_time := -1
	var previous_round := -1
	for index in range(event_rows.size()):
		var event: Dictionary = event_rows[index]
		if int(event.get("event_id", -1)) != index + 1 \
				or int(event.get("world_time", -1)) < previous_time \
				or int(event.get("world_time", -1)) > current_world_time \
				or int(event.get("round_index", -1)) < previous_round \
				or int(event.get("round_index", -1)) >= round_index:
			return "invalid_offscreen_event_sequence"
		var event_error := _event_error(event, member_ids, prior_events)
		if not event_error.is_empty():
			return event_error
		previous_time = int(event.world_time)
		previous_round = int(event.round_index)
		prior_events[int(event.event_id)] = event
	return ""


func member_ref(entity_id: int) -> Dictionary:
	for side in side_rows:
		for member in side.member_rows:
			if int(member.entity_id) == entity_id:
				return member
	return {}


func side_id_for(entity_id: int) -> String:
	for side in side_rows:
		for member in side.member_rows:
			if int(member.entity_id) == entity_id:
				return str(side.side_id)
	return ""


func _wire_without_hash() -> Dictionary:
	var remainder_rows: Array = []
	var remainder_ids: Array = damage_remainders.keys(); remainder_ids.sort()
	for entity_id_value in remainder_ids:
		var entity_id := int(entity_id_value)
		remainder_rows.append({"entity_id":str(entity_id),
			"remainder_milli":int(damage_remainders[entity_id])})
	var events_wire: Array = []
	for event in event_rows:
		events_wire.append(_event_to_wire(event))
	return {
		"schema_version":SCHEMA_VERSION,
		"ruleset_id":RULESET_ID,
		"encounter_id":str(encounter_id),
		"encounter_phase":encounter_phase,
		"current_world_time":str(current_world_time),
		"next_round_at":str(next_round_at),
		"round_index":str(round_index),
		"protagonist_participates":protagonist_participates,
		"observed_by_player":observed_by_player,
		"within_detailed_radius":within_detailed_radius,
		"pending_player_choice":pending_player_choice,
		"side_rows":_sides_to_wire(side_rows),
		"damage_remainder_rows":remainder_rows,
		"event_rows":events_wire,
		"next_event_id":str(next_event_id),
	}


static func _event_error(event: Dictionary, member_ids: Array[int],
		prior_events: Dictionary) -> String:
	var keys: Array = event.keys(); keys.sort()
	if keys != EVENT_KEYS or str(event.get("type", "")) not in EVENT_TYPES \
			or not event.get("magnitude") is int or int(event.magnitude) < 0:
		return "invalid_offscreen_event"
	var event_id := int(event.event_id)
	var cause_id := int(event.cause_id)
	var target_id := int(event.target_id)
	if cause_id != -1 and (cause_id <= 0 or cause_id >= event_id \
			or not prior_events.has(cause_id)):
		return "invalid_offscreen_event_cause"
	var data: Variant = event.get("data")
	if not data is Dictionary:
		return "invalid_offscreen_event_data"
	var data_keys: Array = data.keys(); data_keys.sort()
	match str(event.type):
		"offscreen.damage_resolved":
			if target_id not in member_ids or data_keys != ["health_after",
					"health_before", "projected_damage_milli", "remainder_after",
					"remainder_before", "source_actor_ids", "source_side_id"] \
					or not data.source_actor_ids is Array \
					or not data.source_side_id is String:
				return "invalid_offscreen_damage_event"
			for key in ["health_before", "health_after", "projected_damage_milli",
					"remainder_before", "remainder_after"]:
				if not data.get(key) is int:
					return "invalid_offscreen_damage_event"
			if int(data.projected_damage_milli) <= 0 \
					or int(data.remainder_before) < 0 \
					or int(data.remainder_before) > 999 \
					or int(data.remainder_after) < 0 \
					or int(data.remainder_after) > 999 \
					or int(data.health_before) < int(data.health_after) \
					or int(event.magnitude) != int(data.health_before) \
						- int(data.health_after):
				return "invalid_offscreen_damage_event"
			var previous_actor := -1
			for actor_id_value in data.source_actor_ids:
				if not actor_id_value is int or int(actor_id_value) <= previous_actor \
						or int(actor_id_value) not in member_ids:
					return "invalid_offscreen_damage_event"
				previous_actor = int(actor_id_value)
		"offscreen.entity_downed":
			if target_id not in member_ids or int(event.magnitude) != 0 \
					or data != {"previous_life_state":"ACTIVE"} \
					or cause_id == -1 \
					or prior_events[cause_id].type != "offscreen.damage_resolved" \
					or int(prior_events[cause_id].target_id) != target_id:
				return "invalid_offscreen_downed_event"
		"offscreen.entity_died":
			if target_id not in member_ids or int(event.magnitude) != 0 \
					or data != {"previous_life_state":"DOWNED",
						"reason":"EXPECTED_DAMAGE"} \
					or cause_id == -1 \
					or prior_events[cause_id].type != "offscreen.entity_downed" \
					or int(prior_events[cause_id].target_id) != target_id:
				return "invalid_offscreen_death_event"
		"offscreen.round_resolved":
			if target_id != -1 or data_keys != ["active_side_ids",
					"damage_event_count", "impact_count", "ruleset_id"] \
					or data.ruleset_id != ModelScript.RULESET_ID \
					or not data.active_side_ids is Array \
					or not data.damage_event_count is int \
					or not data.impact_count is int:
				return "invalid_offscreen_round_event"
		"offscreen.encounter_resolved":
			if target_id != -1 or cause_id == -1 \
					or prior_events[cause_id].type != "offscreen.round_resolved" \
					or data_keys != ["active_side_ids", "outcome"] \
					or not data.active_side_ids is Array \
					or data.outcome not in ["SIDE_VICTORY", "MUTUAL_DEFEAT"]:
				return "invalid_offscreen_resolved_event"
	return ""


static func _event_to_wire(event: Dictionary) -> Dictionary:
	var data: Dictionary = event.data.duplicate(true)
	if str(event.type) == "offscreen.damage_resolved":
		var encoded_actor_ids: Array = []
		for actor_id in data.source_actor_ids:
			encoded_actor_ids.append(str(int(actor_id)))
		data.source_actor_ids = encoded_actor_ids
	return {"event_id":str(int(event.event_id)),
		"world_time":str(int(event.world_time)),
		"round_index":str(int(event.round_index)),
		"type":str(event.type), "target_id":str(int(event.target_id)),
		"magnitude":int(event.magnitude), "cause_id":str(int(event.cause_id)),
		"data":data}


static func _event_from_wire(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var row: Dictionary = value
	var keys: Array = row.keys(); keys.sort()
	if keys != EVENT_KEYS or not row.get("type") is String \
			or not _integer_value(row.get("magnitude")) \
			or not row.get("data") is Dictionary:
		return {}
	for key in ["event_id", "world_time", "round_index", "target_id", "cause_id"]:
		if not Int64CodecScript.is_canonical(row.get(key)):
			return {}
	var data: Dictionary = row.data.duplicate(true)
	if str(row.type) == "offscreen.damage_resolved":
		if not data.get("source_actor_ids") is Array:
			return {}
		var decoded_actor_ids: Array[int] = []
		for actor_id in data.source_actor_ids:
			if not Int64CodecScript.is_canonical(actor_id):
				return {}
			decoded_actor_ids.append(Int64CodecScript.parse(actor_id,
				"offscreen source actor"))
		data.source_actor_ids = decoded_actor_ids
	for key in ["health_before", "health_after", "projected_damage_milli",
			"remainder_before", "remainder_after", "damage_event_count",
			"impact_count"]:
		if data.has(key):
			if not _integer_value(data[key]):
				return {}
			data[key] = int(data[key])
	return {"event_id":Int64CodecScript.parse(row.event_id, "offscreen event ID"),
		"world_time":Int64CodecScript.parse(row.world_time, "offscreen event time"),
		"round_index":Int64CodecScript.parse(row.round_index, "offscreen event round"),
		"type":str(row.type),
		"target_id":Int64CodecScript.parse(row.target_id, "offscreen event target"),
		"magnitude":int(row.magnitude),
		"cause_id":Int64CodecScript.parse(row.cause_id, "offscreen event cause"),
		"data":data}


static func _canonical_sides(values: Array) -> Array:
	var sides: Array = values.duplicate(true)
	sides.sort_custom(func(a: Dictionary, b: Dictionary):
		return str(a.side_id) < str(b.side_id))
	for side in sides:
		side.member_rows.sort_custom(func(a: Dictionary, b: Dictionary):
			return int(a.entity_id) < int(b.entity_id))
	return sides


static func _sides_to_wire(values: Array) -> Array:
	var result: Array = []
	for side in _canonical_sides(values):
		var members: Array = []
		for member_value in side.member_rows:
			var member: Dictionary = member_value.duplicate(true)
			member.entity_id = str(int(member.entity_id))
			members.append(member)
		result.append({"side_id":str(side.side_id),
			"command_id":str(side.command_id), "target_id":str(int(side.target_id)),
			"member_rows":members})
	return result


static func _sides_from_wire(values: Array) -> Array:
	var result: Array = []
	for side_value in values:
		if not side_value is Dictionary:
			return []
		var side: Dictionary = side_value
		var keys: Array = side.keys(); keys.sort()
		if keys != ModelScript.SIDE_KEYS or not side.get("side_id") is String \
				or not side.get("command_id") is String \
				or not Int64CodecScript.is_canonical(side.get("target_id")) \
				or not side.get("member_rows") is Array:
			return []
		var members: Array = []
		for member_value in side.member_rows:
			if not member_value is Dictionary:
				return []
			var member: Dictionary = member_value.duplicate(true)
			if not Int64CodecScript.is_canonical(member.get("entity_id")):
				return []
			member.entity_id = Int64CodecScript.parse(member.entity_id,
				"offscreen member ID")
			for scalar_key in ["health", "max_health", "power", "armor_flat",
					"accuracy_milli", "evasion_milli", "attack_time", "stress_milli"]:
				if not _integer_value(member.get(scalar_key)):
					return []
				member[scalar_key] = int(member[scalar_key])
			if not member.get("hexaco") is Dictionary:
				return []
			for axis in ModelScript.HEXACO_KEYS:
				if not _integer_value(member.hexaco.get(axis)):
					return []
				member.hexaco[axis] = int(member.hexaco[axis])
			members.append(member)
		result.append({"side_id":str(side.side_id),
			"command_id":str(side.command_id),
			"target_id":Int64CodecScript.parse(side.target_id,
				"offscreen command target"), "member_rows":members})
	return _canonical_sides(result)


static func _integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) \
		and value == floor(value) and absf(value) <= 9007199254740991.0)
