extends "res://tests/test_case.gd"

const DefenseRules = preload("res://sim/combat_defense_rules.gd")


func test_snapshot_keeps_armor_dodge_and_parry_as_distinct_defenses() -> bool:
	var snapshot := DefenseRules.build_snapshot(150, 2, {
		"armor_flat": 3,
		"dodge_milli": 50,
		"parry_milli": 100,
		# Non-defense item projection fields are forward-compatible and ignored.
		"stealth": 20,
		"affix_hook_ids": ["TEST_HOOK"],
	})
	check_eq(DefenseRules.snapshot_error(snapshot), "", "snapshot validates")
	check_eq([
		snapshot.base_armor_flat,
		snapshot.equipment_armor_flat,
		snapshot.effective_armor_flat,
		snapshot.base_evasion_milli,
		snapshot.dodge_milli,
		snapshot.effective_evasion_milli,
		snapshot.parry_milli,
	], [2, 3, 5, 150, 50, 200, 100], "three defenses remain inspectable")
	return finish()


func test_dodge_changes_only_the_existing_hit_formula() -> bool:
	var plain := DefenseRules.build_snapshot(100, 2)
	var nimble := DefenseRules.build_snapshot(100, 2, {"dodge_milli": 75})
	var plain_hit := DefenseRules.hit_chance_milli(200, 40, 30, plain)
	var nimble_hit := DefenseRules.hit_chance_milli(200, 40, 30, nimble)
	check_eq([plain_hit, nimble_hit, plain_hit - nimble_hit], [670, 595, 75],
		"dodge subtracts one-for-one from hit chance")
	check_eq(DefenseRules.hit_chance_milli(100000, 0, 0, plain), 950,
		"hit chance keeps canonical upper cap")
	check_eq(DefenseRules.hit_chance_milli(-100000, 0, 0, plain), 50,
		"hit chance keeps canonical lower cap")
	return finish()


func test_armor_and_penetration_are_flat_and_never_reduce_a_hit_below_one() -> bool:
	var armored := DefenseRules.build_snapshot(100, 2, {"armor_flat": 3})
	check_eq(DefenseRules.armor_reduction(12, 1, armored), 4,
		"penetration removes flat armor one-for-one")
	check_eq(DefenseRules.resolve_landed_hit(12, 1, 999, armored), {
		"outcome": "DAMAGED",
		"parry_chance_milli": 0,
		"parry_roll_milli": 999,
		"armor_reduction": 4,
		"final_damage": 8,
	}, "landed hit uses effective armor")
	check_eq(DefenseRules.armor_reduction(3, 0,
		DefenseRules.build_snapshot(0, 999)), 2, "armor retains minimum one damage")
	return finish()


func test_parry_is_a_separate_deterministic_post_hit_gate() -> bool:
	var shielded := DefenseRules.build_snapshot(100, 2, {"parry_milli": 100})
	check(DefenseRules.parry_succeeds(99, shielded), "roll below parry chance succeeds")
	check(not DefenseRules.parry_succeeds(100, shielded), "equal roll fails exact threshold")
	check_eq(DefenseRules.resolve_landed_hit(20, 0, 99, shielded), {
		"outcome": "PARRIED",
		"parry_chance_milli": 100,
		"parry_roll_milli": 99,
		"armor_reduction": 0,
		"final_damage": 0,
	}, "parry has one readable zero-damage outcome")
	return finish()


func test_invalid_inputs_fail_closed_without_state_or_rng() -> bool:
	check_eq(DefenseRules.build_snapshot(-1, 0), {}, "negative base evasion rejected")
	check_eq(DefenseRules.build_snapshot(0, 0, {"parry_milli": 1001}), {},
		"out of range parry rejected")
	var valid := DefenseRules.build_snapshot(0, 0)
	var tampered := valid.duplicate(true)
	tampered.effective_armor_flat = 9
	check_eq(DefenseRules.snapshot_error(tampered), "invalid_defense_snapshot_projection",
		"derived fields are tamper evident")
	check_eq(DefenseRules.resolve_landed_hit(-1, 0, 0, valid), {},
		"invalid landed hit rejected")
	return finish()
