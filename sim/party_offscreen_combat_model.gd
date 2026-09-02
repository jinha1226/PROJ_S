class_name PartyOffscreenCombatModel
extends RefCounted

const FixedPointScript = preload("res://sim/fixed_point.gd")
const PartyCommandScript = preload("res://sim/party_exception_command.gd")

const RULESET_ID := "party-offscreen-combat-v1"
const SCHEMA_VERSION := 1
const ROUND_TIME := 100
const COMMAND_IDS := PartyCommandScript.COMMAND_IDS
const LIFE_STATES := ["ACTIVE", "DOWNED", "DEAD"]
const MENTAL_MODES := ["NORMAL", "PANIC"]
const TOP_LEVEL_KEYS := ["encounter_id", "encounter_phase", "observed_by_player",
	"pending_player_choice", "protagonist_participates", "round_index",
	"schema_version", "side_rows", "within_detailed_radius", "world_time"]
const SIDE_KEYS := ["command_id", "member_rows", "side_id", "target_id"]
const MEMBER_KEYS := ["accuracy_milli", "armor_flat", "attack_time", "entity_id",
	"evasion_milli", "health", "hexaco", "life_state", "max_health",
	"mental_mode", "power", "status_ids", "stress_milli"]
const HEXACO_KEYS := ["A", "C", "E", "H", "O", "X"]


static func assess(value: Variant) -> Dictionary:
	var error := data_error(value)
	if not error.is_empty():
		return _assessment(false, false, error, -1, -1, -1, {})
	var input: Dictionary = value
	var active_counts: Dictionary = {}
	var sorted_sides := _sorted_sides(input.side_rows)
	for side in sorted_sides:
		active_counts[str(side.side_id)] = _active_members(side).size()
	if str(input.encounter_phase) != "ENGAGED":
		return _assessment(true, false, "encounter_not_engaged",
			int(input.encounter_id), int(input.world_time), int(input.round_index), active_counts)
	if bool(input.protagonist_participates):
		return _assessment(true, false, "protagonist_participates",
			int(input.encounter_id), int(input.world_time), int(input.round_index), active_counts)
	if bool(input.observed_by_player):
		return _assessment(true, false, "player_observes_encounter",
			int(input.encounter_id), int(input.world_time), int(input.round_index), active_counts)
	if bool(input.within_detailed_radius):
		return _assessment(true, false, "inside_detailed_radius",
			int(input.encounter_id), int(input.world_time), int(input.round_index), active_counts)
	if bool(input.pending_player_choice):
		return _assessment(true, false, "pending_player_choice",
			int(input.encounter_id), int(input.world_time), int(input.round_index), active_counts)
	for side in sorted_sides:
		for member in side.member_rows:
			if not member.status_ids.is_empty():
				return _assessment(true, false, "unsupported_status",
					int(input.encounter_id), int(input.world_time), int(input.round_index),
					active_counts)
	for side_id in active_counts:
		if int(active_counts[side_id]) == 0:
			return _assessment(true, false, "encounter_terminal",
				int(input.encounter_id), int(input.world_time), int(input.round_index),
				active_counts)
	return _assessment(true, true, "eligible_offscreen", int(input.encounter_id),
		int(input.world_time), int(input.round_index), active_counts)


static func forecast_round(value: Variant) -> Dictionary:
	var assessment := assess(value)
	var result := {
		"schema_version": SCHEMA_VERSION,
		"ruleset_id": RULESET_ID,
		"accepted": bool(assessment.eligible),
		"reason_code": "ok" if bool(assessment.eligible) else str(assessment.reason_code),
		"encounter_id": int(assessment.encounter_id),
		"world_time": int(assessment.world_time),
		"round_index": int(assessment.round_index),
		"assessment": assessment.duplicate(true),
		"side_rows": [],
		"impact_rows": [],
		"trace_rows": [],
	}
	if not bool(assessment.eligible):
		return result.duplicate(true)
	var input: Dictionary = value
	var source_sides := _sorted_sides(input.side_rows)
	var profiles: Dictionary = {}
	for side in source_sides:
		profiles[str(side.side_id)] = _side_profile(side)
	var side_ids: Array = profiles.keys(); side_ids.sort()
	for side_id_value in side_ids:
		var side_id := str(side_id_value)
		var other_id := _other_side_id(side_ids, side_id)
		profiles[side_id].target_side_id = other_id
	var impact_rows: Array = []
	var trace_rows: Array = []
	for source_side in source_sides:
		var source_id := str(source_side.side_id)
		var target_id := str(profiles[source_id].target_side_id)
		var target_side: Dictionary = _side_by_id(source_sides, target_id)
		var source_profile: Dictionary = profiles[source_id]
		var target_profile: Dictionary = profiles[target_id]
		trace_rows.append({"side_id":source_id, "actor_id":-1,
			"code":"side_stance:%s" % str(source_profile.stance)})
		if int(source_profile.attack_scale_milli) == 0:
			continue
		for member in _active_members(source_side):
			if str(member.mental_mode) == "PANIC" \
					and str(source_side.command_id) != "HOLD_POSITION":
				trace_rows.append({"side_id":source_id, "actor_id":int(member.entity_id),
					"code":"panic_withheld_attack"})
				continue
			var target_entity_id := int(source_side.target_id) \
				if str(source_side.command_id) == "ATTACK_TARGET" \
				else _select_target_id(target_side)
			var target_member := _member_by_id(target_side, target_entity_id)
			if target_member.is_empty():
				continue
			impact_rows.append(_impact(member, target_member, source_id, target_id,
				int(source_profile.attack_scale_milli), int(target_profile.guard_milli)))
	impact_rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if str(a.source_side_id) != str(b.source_side_id):
			return str(a.source_side_id) < str(b.source_side_id)
		if int(a.actor_id) != int(b.actor_id):
			return int(a.actor_id) < int(b.actor_id)
		return int(a.target_id) < int(b.target_id))
	trace_rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if str(a.side_id) != str(b.side_id):
			return str(a.side_id) < str(b.side_id)
		if int(a.actor_id) != int(b.actor_id):
			return int(a.actor_id) < int(b.actor_id)
		return str(a.code) < str(b.code))
	for impact in impact_rows:
		profiles[str(impact.source_side_id)].total_projected_damage_milli += \
			int(impact.projected_damage_milli)
	var output_sides: Array = []
	for side_id_value in side_ids:
		var side_id := str(side_id_value)
		var profile: Dictionary = profiles[side_id]
		profile.erase("attack_scale_milli")
		output_sides.append(profile.duplicate(true))
	result.side_rows = output_sides
	result.impact_rows = impact_rows
	result.trace_rows = trace_rows
	return result.duplicate(true)


static func data_error(value: Variant) -> String:
	if not value is Dictionary:
		return "invalid_offscreen_input_shape"
	var input: Dictionary = value
	var keys: Array = input.keys(); keys.sort()
	if keys != TOP_LEVEL_KEYS:
		return "invalid_offscreen_input_keys"
	if input.schema_version != SCHEMA_VERSION:
		return "unsupported_offscreen_schema"
	if not input.encounter_phase is String \
			or str(input.encounter_phase) not in ["CONTACT", "ENGAGED", "TERMINAL"]:
		return "invalid_offscreen_phase"
	for key in ["encounter_id", "world_time", "round_index"]:
		if not input[key] is int:
			return "invalid_offscreen_integer"
	if int(input.encounter_id) <= 0 or int(input.world_time) < 0 \
			or int(input.round_index) < 0:
		return "invalid_offscreen_integer"
	for key in ["protagonist_participates", "observed_by_player",
			"within_detailed_radius", "pending_player_choice"]:
		if not input[key] is bool:
			return "invalid_offscreen_flag"
	if not input.side_rows is Array or input.side_rows.size() != 2:
		return "invalid_offscreen_side_count"
	var seen_sides: Dictionary = {}
	var seen_entities: Dictionary = {}
	for side_value in input.side_rows:
		if not side_value is Dictionary:
			return "invalid_offscreen_side_shape"
		var side: Dictionary = side_value
		var side_keys: Array = side.keys(); side_keys.sort()
		if side_keys != SIDE_KEYS:
			return "invalid_offscreen_side_keys"
		if not side.side_id is String or not _stable_id(str(side.side_id)) \
				or seen_sides.has(str(side.side_id)):
			return "invalid_offscreen_side_id"
		seen_sides[str(side.side_id)] = true
		if not side.command_id is String or str(side.command_id) not in COMMAND_IDS:
			return "invalid_offscreen_command"
		if not side.target_id is int:
			return "invalid_offscreen_target"
		if (str(side.command_id) == "ATTACK_TARGET" and int(side.target_id) <= 0) \
				or (str(side.command_id) != "ATTACK_TARGET" and int(side.target_id) != -1):
			return "invalid_offscreen_target"
		if not side.member_rows is Array or side.member_rows.is_empty():
			return "invalid_offscreen_members"
		for member_value in side.member_rows:
			var member_error := _member_error(member_value)
			if not member_error.is_empty():
				return member_error
			var entity_id := int(member_value.entity_id)
			if seen_entities.has(entity_id):
				return "duplicate_offscreen_entity"
			seen_entities[entity_id] = str(side.side_id)
	var sides: Array = input.side_rows
	for side in sides:
		if str(side.command_id) != "ATTACK_TARGET":
			continue
		var target_id := int(side.target_id)
		if not seen_entities.has(target_id) or str(seen_entities[target_id]) == str(side.side_id):
			return "invalid_offscreen_target"
		var target_side := _side_by_id(sides, str(seen_entities[target_id]))
		var target_member := _member_by_id(target_side, target_id)
		if target_member.is_empty() or str(target_member.life_state) != "ACTIVE":
			return "invalid_offscreen_target"
	return ""


static func _member_error(value: Variant) -> String:
	if not value is Dictionary:
		return "invalid_offscreen_member_shape"
	var member: Dictionary = value
	var keys: Array = member.keys(); keys.sort()
	if keys != MEMBER_KEYS:
		return "invalid_offscreen_member_keys"
	for key in ["entity_id", "health", "max_health", "power", "armor_flat",
			"accuracy_milli", "evasion_milli", "attack_time", "stress_milli"]:
		if not member[key] is int:
			return "invalid_offscreen_member_integer"
	if int(member.entity_id) <= 0 or int(member.max_health) <= 0 \
			or int(member.health) < 0 or int(member.health) > int(member.max_health) \
			or int(member.power) < 1 or int(member.power) > 1000000 \
			or int(member.armor_flat) < 0 or int(member.armor_flat) > 1000000 \
			or int(member.accuracy_milli) < 0 or int(member.accuracy_milli) > 1000 \
			or int(member.evasion_milli) < 0 or int(member.evasion_milli) > 1000 \
			or int(member.attack_time) < 1 or int(member.attack_time) > 1000000 \
			or int(member.stress_milli) < 0 or int(member.stress_milli) > 1000:
		return "invalid_offscreen_member_integer"
	if not member.life_state is String or str(member.life_state) not in LIFE_STATES:
		return "invalid_offscreen_life_state"
	if (str(member.life_state) == "ACTIVE" and int(member.health) <= 0) \
			or (str(member.life_state) != "ACTIVE" and int(member.health) != 0):
		return "invalid_offscreen_life_health"
	if not member.mental_mode is String or str(member.mental_mode) not in MENTAL_MODES:
		return "invalid_offscreen_mental_mode"
	if not member.status_ids is Array:
		return "invalid_offscreen_status_ids"
	var seen_statuses: Dictionary = {}
	for status_value in member.status_ids:
		if not status_value is String or not _stable_id(str(status_value)) \
				or seen_statuses.has(str(status_value)):
			return "invalid_offscreen_status_ids"
		seen_statuses[str(status_value)] = true
	if not member.hexaco is Dictionary:
		return "invalid_offscreen_hexaco"
	var hexaco_keys: Array = member.hexaco.keys(); hexaco_keys.sort()
	if hexaco_keys != HEXACO_KEYS:
		return "invalid_offscreen_hexaco"
	for axis in HEXACO_KEYS:
		if not member.hexaco[axis] is int or int(member.hexaco[axis]) < 0 \
				or int(member.hexaco[axis]) > 1000:
			return "invalid_offscreen_hexaco"
	return ""


static func _assessment(valid: bool, eligible: bool, reason_code: String,
		encounter_id: int, world_time: int, round_index: int,
		active_counts: Dictionary) -> Dictionary:
	return {"schema_version":SCHEMA_VERSION, "ruleset_id":RULESET_ID,
		"valid":valid, "eligible":eligible, "reason_code":reason_code,
		"encounter_id":encounter_id, "world_time":world_time,
		"round_index":round_index, "active_counts":active_counts.duplicate(true)}


static func _side_profile(side: Dictionary) -> Dictionary:
	var active := _active_members(side)
	var hp_total := 0
	var stress_total := 0
	var resilience_total := 0
	var panic_count := 0
	var active_ids: Array[int] = []
	for member in active:
		active_ids.append(int(member.entity_id))
		hp_total += FixedPointScript.trunc_div(
			int(member.health) * 1000, int(member.max_health))
		stress_total += int(member.stress_milli)
		resilience_total += FixedPointScript.trunc_div(
			int(member.hexaco.C) + (1000 - int(member.hexaco.E)), 2)
		if str(member.mental_mode) == "PANIC":
			panic_count += 1
	var count := maxi(1, active.size())
	var hp_average := FixedPointScript.trunc_div(hp_total, count)
	var stress_average := FixedPointScript.trunc_div(stress_total, count)
	var resilience_average := FixedPointScript.trunc_div(resilience_total, count)
	var cohesion := clampi(1000 - FixedPointScript.trunc_div(stress_average, 2) \
		+ FixedPointScript.trunc_div(resilience_average, 4), 0, 1000)
	var readiness := clampi(FixedPointScript.trunc_div(
		hp_average * 2 + cohesion, 3), 0, 1000)
	var stance := _stance(str(side.command_id), active.size(), panic_count,
		hp_average, stress_average)
	var guard: int = int({"PRESS":0, "HOLD":250, "WITHDRAW":150,
		"CEASE":300}.get(stance, 0))
	var attack_scale: int = int({"PRESS":1000, "HOLD":700, "WITHDRAW":0,
		"CEASE":0}.get(stance, 0))
	return {"side_id":str(side.side_id), "command_id":str(side.command_id),
		"focus_target_id":int(side.target_id), "target_side_id":"",
		"active_count":active.size(), "active_ids":active_ids,
		"panic_count":panic_count, "average_hp_milli":hp_average,
		"average_stress_milli":stress_average, "cohesion_milli":cohesion,
		"readiness_milli":readiness, "stance":stance, "guard_milli":int(guard),
		"attack_scale_milli":int(attack_scale),
		"total_projected_damage_milli":0}


static func _stance(command_id: String, active_count: int, panic_count: int,
		average_hp_milli: int, average_stress_milli: int) -> String:
	match command_id:
		"RETREAT": return "WITHDRAW"
		"STOP_ATTACK": return "CEASE"
		"HOLD_POSITION": return "HOLD"
		"ATTACK_TARGET": return "PRESS"
	if panic_count * 2 > active_count \
			or (average_hp_milli < 250 and average_stress_milli >= 650):
		return "WITHDRAW"
	return "PRESS"


static func _impact(actor: Dictionary, target: Dictionary, source_side_id: String,
		target_side_id: String, attack_scale_milli: int,
		target_guard_milli: int) -> Dictionary:
	var raw_damage := maxi(1, int(actor.power) - int(target.armor_flat))
	var hit_chance := clampi(500 + int(actor.accuracy_milli) \
		- int(target.evasion_milli), 50, 950)
	var projected := FixedPointScript.trunc_div(
		raw_damage * hit_chance * ROUND_TIME, int(actor.attack_time))
	projected = FixedPointScript.trunc_div(projected * attack_scale_milli, 1000)
	projected = FixedPointScript.trunc_div(projected * (1000 - target_guard_milli), 1000)
	return {"source_side_id":source_side_id, "target_side_id":target_side_id,
		"actor_id":int(actor.entity_id), "target_id":int(target.entity_id),
		"raw_damage":raw_damage, "hit_chance_milli":hit_chance,
		"attack_time":int(actor.attack_time), "attack_scale_milli":attack_scale_milli,
		"target_guard_milli":target_guard_milli,
		"projected_damage_milli":projected,
		"projected_damage_floor":FixedPointScript.trunc_div(projected, 1000),
		"reason_code":"expected_damage_without_rng"}


static func _sorted_sides(side_rows: Array) -> Array:
	var result: Array = side_rows.duplicate(true)
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		return str(a.side_id) < str(b.side_id))
	return result


static func _active_members(side: Dictionary) -> Array:
	var result: Array = []
	for member in side.get("member_rows", []):
		if str(member.get("life_state", "")) == "ACTIVE":
			result.append(member.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.entity_id) < int(b.entity_id))
	return result


static func _side_by_id(side_rows: Array, side_id: String) -> Dictionary:
	for side in side_rows:
		if str(side.get("side_id", "")) == side_id:
			return side
	return {}


static func _member_by_id(side: Dictionary, entity_id: int) -> Dictionary:
	for member in side.get("member_rows", []):
		if int(member.get("entity_id", -1)) == entity_id:
			return member
	return {}


static func _select_target_id(side: Dictionary) -> int:
	var active := _active_members(side)
	active.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_hp := FixedPointScript.trunc_div(int(a.health) * 1000, int(a.max_health))
		var b_hp := FixedPointScript.trunc_div(int(b.health) * 1000, int(b.max_health))
		if a_hp != b_hp:
			return a_hp < b_hp
		if int(a.armor_flat) != int(b.armor_flat):
			return int(a.armor_flat) < int(b.armor_flat)
		return int(a.entity_id) < int(b.entity_id))
	return int(active[0].entity_id) if not active.is_empty() else -1


static func _other_side_id(side_ids: Array, side_id: String) -> String:
	for value in side_ids:
		if str(value) != side_id:
			return str(value)
	return ""


static func _stable_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in range(value.length()):
		var code: int = value.unicode_at(index)
		var ascii_letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var ascii_digit := code >= 48 and code <= 57
		if not ascii_letter and not ascii_digit and code not in [45, 46, 95]:
			return false
	return true
