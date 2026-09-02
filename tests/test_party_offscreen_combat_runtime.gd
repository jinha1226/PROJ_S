extends "res://tests/test_case.gd"

const Model = preload("res://sim/party_offscreen_combat_model.gd")
const State = preload("res://sim/party_offscreen_combat_state.gd")
const Runtime = preload("res://sim/party_offscreen_combat_runtime.gd")


func test_fractional_damage_carries_without_rounding_drift() -> bool:
	var input := _input(1000)
	for side in input.side_rows:
		for member in side.member_rows:
			member.power = 2
			member.armor_flat = 1
			member.accuracy_milli = 500
			member.evasion_milli = 500
			member.attack_time = 100
		# One of two active members withholds its strike. The other contributes
		# exactly 500 milli, so this fixture isolates carry instead of summation.
		side.member_rows[1].mental_mode = "PANIC"
	var created: Dictionary = State.create(input)
	check(bool(created.accepted), "eligible P4-1 input creates authority state")
	var first: Dictionary = Runtime.advance(created.state, 1000, 1)
	check(bool(first.accepted), "first half-HP round commits")
	var after_first = State.from_dict(first.state_rows[0])
	check(after_first != null, "first result restores")
	if after_first != null:
		check_eq(_member(after_first, 11).health, 100,
			"500 milli damage does not round up")
		check_eq(int(after_first.damage_remainders[11]), 500,
			"fractional damage is authoritative carry")
	var second: Dictionary = Runtime.advance(first.state_rows[0], 1100, 1)
	var after_second = State.from_dict(second.state_rows[0])
	check(after_second != null, "second result restores")
	if after_second != null:
		check_eq(_member(after_second, 11).health, 99,
			"two 500 milli rounds become exactly one HP")
		check_eq(int(after_second.damage_remainders[11]), 0,
			"carry is consumed without drift")
	return finish()


func test_lethal_expected_damage_emits_damage_downed_death_and_terminal_events() -> bool:
	var input := _input(2000)
	input.side_rows[1].member_rows = [
		_member_row(21, 8, 8, 2, 1, 500, 500, 100),
	]
	input.side_rows[0].member_rows[0].power = 30
	input.side_rows[0].member_rows[1].power = 30
	var created: Dictionary = State.create(input)
	var advanced: Dictionary = Runtime.advance(created.state, 2000, 1)
	check(bool(advanced.accepted), "lethal round commits")
	var restored = State.from_dict(advanced.state_rows[0]) \
		if bool(advanced.accepted) else null
	check(restored != null, "terminal authority state restores")
	if restored != null:
		check_eq(restored.encounter_phase, "TERMINAL", "side elimination ends cadence")
		check_eq(restored.next_round_at, -1, "terminal encounter has no due round")
		check_eq([_member(restored, 21).health, _member(restored, 21).life_state],
			[0, "DEAD"], "lethal abstract damage has one final authority projection")
		var types: Array = restored.event_rows.map(func(row): return str(row.type))
		check(types.has("offscreen.damage_resolved"), "damage event recorded")
		check(types.has("offscreen.entity_downed"), "downed transition recorded")
		check(types.has("offscreen.entity_died"), "death transition recorded")
		check(types.has("offscreen.encounter_resolved"), "terminal event recorded")
	return finish()


func test_save_load_resume_is_byte_deterministic_and_order_independent() -> bool:
	var first = State.create(_input(3000)).state
	var second_input := _input(3000)
	second_input.encounter_id = 7002
	for side in second_input.side_rows:
		for member in side.member_rows:
			member.entity_id += 100
	var second = State.create(second_input).state
	var prefix: Dictionary = Runtime.advance_batch([second, first], 3100, 3)
	check(bool(prefix.accepted), "canonical batch advances")
	var json := JSON.stringify(prefix.state_rows)
	var loaded: Variant = JSON.parse_string(json)
	check(loaded is Array, "authority snapshot is JSON round-trippable")
	var resumed: Dictionary = Runtime.advance_batch(loaded, 3500, 8)
	var uninterrupted: Dictionary = Runtime.advance_batch(prefix.state_rows, 3500, 8)
	check_eq(resumed, uninterrupted,
		"save/load resume produces byte-identical state and event rows")
	var reversed: Array = prefix.state_rows.duplicate(true)
	reversed.reverse()
	check_eq(Runtime.advance_batch(reversed, 3500, 8), uninterrupted,
		"caller encounter order cannot change the canonical batch")
	return finish()


func test_global_round_budget_bounds_large_catch_up_work() -> bool:
	var states: Array = []
	for encounter_offset in range(40):
		var input := _input(4000)
		input.encounter_id = 8000 + encounter_offset
		for side in input.side_rows:
			side.command_id = "STOP_ATTACK"
			for member in side.member_rows:
				member.entity_id += encounter_offset * 100
		states.append(State.create(input).state)
	var before: Array = []
	for state in states:
		before.append(state.to_dict())
	var advanced: Dictionary = Runtime.advance_batch(states, 1000000,
		Runtime.MAX_ROUNDS_PER_ADVANCE)
	check(bool(advanced.accepted), "large overdue batch is accepted")
	check_eq(int(advanced.rounds_processed), Runtime.MAX_ROUNDS_PER_ADVANCE,
		"one player advance never exceeds the global round budget")
	check(bool(advanced.budget_exhausted), "remaining work is explicitly deferred")
	var total_rounds := 0
	for state_row in advanced.state_rows:
		var restored = State.from_dict(state_row)
		total_rounds += restored.round_index
	check_eq(total_rounds, Runtime.MAX_ROUNDS_PER_ADVANCE,
		"budget is global rather than multiplied by encounter count")
	var after_original: Array = []
	for state in states:
		after_original.append(state.to_dict())
	check_eq(after_original, before, "runtime never mutates caller authority on commit")
	return finish()


func test_invalid_or_ineligible_state_is_atomic_and_never_spins() -> bool:
	var state = State.create(_input(5000)).state
	var saved: Dictionary = state.to_dict()
	var invalid: Dictionary = saved.duplicate(true)
	invalid.next_round_at = "oops"
	var rejected: Dictionary = Runtime.advance(invalid, 5000, 1)
	check(not bool(rejected.accepted), "malformed authority is rejected")
	check_eq(state.to_dict(), saved, "malformed sibling input cannot mutate live state")
	state.observed_by_player = true
	var paused_before: Dictionary = state.to_dict()
	var paused: Dictionary = Runtime.advance(state, 1000000, 8)
	check(bool(paused.accepted), "detailed-boundary state pauses without failure")
	check_eq(int(paused.rounds_processed), 0, "ineligible due state does no work")
	check_eq(str(paused.paused_rows[0].reason_code), "player_observes_encounter",
		"pause preserves the P4-1 transition reason")
	check_eq(paused.state_rows[0], paused_before,
		"pause does not advance time, HP, events or remainder")
	return finish()


func _input(world_time: int) -> Dictionary:
	return {
		"schema_version":Model.SCHEMA_VERSION,
		"encounter_id":7001,
		"encounter_phase":"ENGAGED",
		"world_time":world_time,
		"round_index":0,
		"protagonist_participates":false,
		"observed_by_player":false,
		"within_detailed_radius":false,
		"pending_player_choice":false,
		"side_rows":[
			{"side_id":"A", "command_id":"FOLLOW", "target_id":-1,
				"member_rows":[
					_member_row(11, 100, 100, 20, 2, 600, 100, 100),
					_member_row(12, 100, 100, 14, 1, 550, 120, 100),
				]},
			{"side_id":"B", "command_id":"FOLLOW", "target_id":-1,
				"member_rows":[
					_member_row(21, 100, 100, 16, 2, 550, 100, 100),
					_member_row(22, 100, 100, 13, 1, 590, 145, 120),
				]},
		],
	}


func _member_row(entity_id: int, health: int, max_health: int, power: int,
		armor_flat: int, accuracy_milli: int, evasion_milli: int,
		attack_time: int) -> Dictionary:
	return {"entity_id":entity_id, "health":health, "max_health":max_health,
		"life_state":"ACTIVE", "power":power, "armor_flat":armor_flat,
		"accuracy_milli":accuracy_milli, "evasion_milli":evasion_milli,
		"attack_time":attack_time, "stress_milli":200,
		"mental_mode":"NORMAL", "status_ids":[],
		"hexaco":{"H":500,"E":500,"X":500,"A":500,"C":500,"O":500}}


func _member(state, entity_id: int) -> Dictionary:
	for side in state.side_rows:
		for member in side.member_rows:
			if int(member.entity_id) == entity_id:
				return member
	return {}
