extends "res://tests/test_case.gd"

const Model = preload("res://sim/party_offscreen_combat_model.gd")


func test_transition_boundary_rejects_every_detailed_or_unsupported_case() -> bool:
	var base := _input()
	var contact_input: Dictionary = base.duplicate(true)
	contact_input.encounter_phase = "CONTACT"
	check_eq(Model.assess(contact_input).reason_code, "encounter_not_engaged",
		"only an already engaged remote encounter can enter abstract cadence")
	for row in [
		["protagonist_participates", "protagonist_participates"],
		["observed_by_player", "player_observes_encounter"],
		["within_detailed_radius", "inside_detailed_radius"],
		["pending_player_choice", "pending_player_choice"],
	]:
		var candidate: Dictionary = base.duplicate(true)
		candidate[str(row[0])] = true
		var assessment: Dictionary = Model.assess(candidate)
		check(bool(assessment.valid) and not bool(assessment.eligible),
			"%s remains a valid but detailed-only input" % str(row[0]))
		check_eq(str(assessment.reason_code), str(row[1]),
			"%s boundary reason" % str(row[0]))
	var status_input: Dictionary = base.duplicate(true)
	status_input.side_rows[0].member_rows[0].status_ids = ["BLEEDING"]
	check_eq(Model.assess(status_input).reason_code, "unsupported_status",
		"persistent status keeps the encounter detailed until P4 supports cadence")
	var terminal_input: Dictionary = base.duplicate(true)
	for member in terminal_input.side_rows[1].member_rows:
		member.life_state = "DEAD"
		member.health = 0
	check_eq(Model.assess(terminal_input).reason_code, "encounter_terminal",
		"a terminal encounter cannot start another abstract round")
	var malformed: Dictionary = base.duplicate(true)
	malformed.erase("round_index")
	var invalid: Dictionary = Model.assess(malformed)
	check(not bool(invalid.valid) and not bool(invalid.eligible),
		"malformed input is distinguished from an ineligible valid encounter")
	check_eq(str(invalid.reason_code), "invalid_offscreen_input_keys",
		"strict top-level DTO keys")
	return finish()


func test_forecast_is_pure_canonical_and_order_independent() -> bool:
	var source := _input()
	var before: Dictionary = source.duplicate(true)
	var first: Dictionary = Model.forecast_round(source)
	var second: Dictionary = Model.forecast_round(source)
	check(bool(first.accepted), "eligible input forecasts one round")
	check_eq(first, second, "repeated forecast is deterministic")
	check_eq(source, before, "forecast never mutates caller input")
	var shuffled: Dictionary = source.duplicate(true)
	shuffled.side_rows.reverse()
	for side in shuffled.side_rows:
		side.member_rows.reverse()
	check_eq(Model.forecast_round(shuffled), first,
		"side and member input order cannot change the canonical result")
	var keys: Array = first.keys(); keys.sort()
	check_eq(keys, ["accepted", "assessment", "encounter_id", "impact_rows",
		"reason_code", "round_index", "ruleset_id", "schema_version",
		"side_rows", "trace_rows", "world_time"], "exact forecast DTO keys")
	var assessment_keys: Array = first.assessment.keys(); assessment_keys.sort()
	check_eq(assessment_keys, ["active_counts", "eligible", "encounter_id",
		"reason_code", "round_index", "ruleset_id", "schema_version", "valid",
		"world_time"], "exact boundary assessment keys")
	var side_keys: Array = first.side_rows[0].keys(); side_keys.sort()
	check_eq(side_keys, ["active_count", "active_ids", "average_hp_milli",
		"average_stress_milli", "cohesion_milli", "command_id", "focus_target_id",
		"guard_milli", "panic_count", "readiness_milli", "side_id", "stance",
		"target_side_id", "total_projected_damage_milli"], "exact side summary keys")
	var impact_keys: Array = first.impact_rows[0].keys(); impact_keys.sort()
	check_eq(impact_keys, ["actor_id", "attack_scale_milli", "attack_time",
		"hit_chance_milli", "projected_damage_floor", "projected_damage_milli",
		"raw_damage", "reason_code", "source_side_id", "target_guard_milli",
		"target_id", "target_side_id"], "exact proposed impact keys")
	var trace_keys: Array = first.trace_rows[0].keys(); trace_keys.sort()
	check_eq(trace_keys, ["actor_id", "code", "side_id"], "exact reason trace keys")
	return finish()


func test_press_round_targets_weakest_member_and_uses_integer_expected_damage() -> bool:
	var forecast: Dictionary = Model.forecast_round(_input())
	var a_impacts: Array = forecast.impact_rows.filter(func(row):
		return str(row.source_side_id) == "A")
	check_eq(a_impacts.size(), 2, "each active normal attacker proposes one impact")
	for impact in a_impacts:
		check_eq(int(impact.target_id), 21, "lowest HP ratio target is focused")
	var actor_11: Dictionary = a_impacts.filter(func(row):
		return int(row.actor_id) == 11)[0]
	check_eq([actor_11.raw_damage, actor_11.hit_chance_milli,
		actor_11.projected_damage_milli], [18, 950, 17100],
		"power/armor, bounded hit chance and tempo use integer milli arithmetic")
	var target_before := int(_input().side_rows[1].member_rows[0].health)
	check_eq(target_before, 40, "forecast does not apply proposed damage to input HP")
	var side_a: Dictionary = forecast.side_rows.filter(func(row):
		return str(row.side_id) == "A")[0]
	check_eq(int(side_a.total_projected_damage_milli),
		int(a_impacts[0].projected_damage_milli) + int(a_impacts[1].projected_damage_milli),
		"side summary equals canonical member proposals")
	return finish()


func test_exception_commands_and_panic_change_stance_without_individual_orders() -> bool:
	var retreat_input := _input()
	retreat_input.side_rows[0].command_id = "RETREAT"
	var retreat: Dictionary = Model.forecast_round(retreat_input)
	check_eq(_side(retreat, "A").stance, "WITHDRAW", "RETREAT withdraws the side")
	check(_impacts(retreat, "A").is_empty(), "RETREAT proposes no attacks")
	var stop_input := _input()
	stop_input.side_rows[0].command_id = "STOP_ATTACK"
	var stopped: Dictionary = Model.forecast_round(stop_input)
	check_eq(_side(stopped, "A").stance, "CEASE", "STOP_ATTACK ceases attacks")
	check(_impacts(stopped, "A").is_empty(), "STOP_ATTACK proposes no attacks")
	var hold_input := _input()
	hold_input.side_rows[0].command_id = "HOLD_POSITION"
	var held: Dictionary = Model.forecast_round(hold_input)
	check_eq([_side(held, "A").stance, _side(held, "A").guard_milli],
		["HOLD", 250], "HOLD_POSITION trades pressure for guard")
	check(not _impacts(held, "A").is_empty(), "held force may answer adjacent pressure")
	var panic_input := _input()
	for member in panic_input.side_rows[0].member_rows:
		member.mental_mode = "PANIC"
	var panic: Dictionary = Model.forecast_round(panic_input)
	check_eq(_side(panic, "A").stance, "WITHDRAW",
		"a panicked majority autonomously withdraws under FOLLOW")
	var focus_input := _input()
	focus_input.side_rows[0].command_id = "ATTACK_TARGET"
	focus_input.side_rows[0].target_id = 22
	var focus: Dictionary = Model.forecast_round(focus_input)
	for impact in _impacts(focus, "A"):
		check_eq(int(impact.target_id), 22, "shared attack target reaches every attacker")
	return finish()


func test_hexaco_resilience_changes_readiness_without_probability_rolls() -> bool:
	var fragile_input := _input()
	for member in fragile_input.side_rows[0].member_rows:
		member.hexaco.E = 1000
		member.hexaco.C = 0
	var resilient_input: Dictionary = fragile_input.duplicate(true)
	for member in resilient_input.side_rows[0].member_rows:
		member.hexaco.E = 0
		member.hexaco.C = 1000
	var fragile: Dictionary = Model.forecast_round(fragile_input)
	var resilient: Dictionary = Model.forecast_round(resilient_input)
	check(int(_side(resilient, "A").cohesion_milli) \
		> int(_side(fragile, "A").cohesion_milli),
		"continuous E/C resilience changes aggregate cohesion")
	check_eq(_impacts(resilient, "A"), _impacts(fragile, "A"),
		"HEXACO does not become a hidden hit probability roll")
	return finish()


func _input() -> Dictionary:
	return {
		"schema_version": 1,
		"encounter_id": 7001,
		"encounter_phase": "ENGAGED",
		"world_time": 1200,
		"round_index": 0,
		"protagonist_participates": false,
		"observed_by_player": false,
		"within_detailed_radius": false,
		"pending_player_choice": false,
		"side_rows": [
			{"side_id":"A", "command_id":"FOLLOW", "target_id":-1,
				"member_rows":[
					_member(11, 100, 100, 20, 2, 600, 100, 100, 200),
					_member(12, 70, 100, 14, 1, 550, 120, 100, 300),
				]},
			{"side_id":"B", "command_id":"FOLLOW", "target_id":-1,
				"member_rows":[
					_member(21, 40, 80, 16, 2, 550, 100, 100, 250),
					_member(22, 80, 80, 13, 1, 590, 145, 120, 150),
				]},
		],
	}


func _member(entity_id: int, health: int, max_health: int, power: int,
		armor_flat: int, accuracy_milli: int, evasion_milli: int,
		attack_time: int, stress_milli: int) -> Dictionary:
	return {"entity_id":entity_id, "health":health, "max_health":max_health,
		"life_state":"ACTIVE", "power":power, "armor_flat":armor_flat,
		"accuracy_milli":accuracy_milli, "evasion_milli":evasion_milli,
		"attack_time":attack_time, "stress_milli":stress_milli,
		"mental_mode":"NORMAL", "status_ids":[],
		"hexaco":{"H":500,"E":500,"X":500,"A":500,"C":500,"O":500}}


func _side(forecast: Dictionary, side_id: String) -> Dictionary:
	for row in forecast.get("side_rows", []):
		if str(row.get("side_id", "")) == side_id:
			return row
	return {}


func _impacts(forecast: Dictionary, side_id: String) -> Array:
	return forecast.get("impact_rows", []).filter(func(row):
		return str(row.get("source_side_id", "")) == side_id)
