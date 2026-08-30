extends "res://tests/test_case.gd"

const WeaponRegistry = preload("res://sim/weapon_registry.gd")
const WeaponRules = preload("res://sim/weapon_attack_rules.gd")
const Loadout = preload("res://sim/weapon_loadout_state.gd")
const Progression = preload("res://sim/protagonist_progression.gd")
const ProgressionRegistry = preload("res://sim/progression_registry.gd")
const MeleeCombatSystem = preload("res://sim/systems/melee_combat_system.gd")


func test_registry_has_only_committed_weapon_families_and_three_attack_forms() -> bool:
	check(not MeleeCombatSystem.COMBAT_RULESET_ID.is_empty(), "existing melee bridge parses")
	check_eq(WeaponRegistry.registry_error(), "", "weapon registry validates")
	check_eq(WeaponRegistry.ids(), ["BOW", "CROSSBOW", "HAND_AXE", "MACE", "SHORT_SWORD",
		"SPEAR", "THRUSTING_SWORD", "UNARMED"], "small committed weapon set")
	var forms := {}
	var proficiencies := {}
	for weapon_id in WeaponRegistry.ids():
		var weapon = WeaponRegistry.definition(weapon_id)
		forms[weapon.attack_form] = true
		proficiencies[weapon.proficiency_id] = true
		check(weapon.ammo_kind in ["NONE", "ARROW", "BOLT"], "no thrown or complex ammunition")
	var form_ids: Array = forms.keys(); form_ids.sort()
	var proficiency_ids: Array = proficiencies.keys(); proficiency_ids.sort()
	check_eq(form_ids, ["IMPACT", "PIERCE", "SLASH"], "exact physical forms")
	check_eq(proficiency_ids, ["AXE", "BLUNT", "RANGED", "SPEAR", "SWORD", "UNARMED"],
		"exact proficiency categories")
	check(int(WeaponRegistry.definition("UNARMED").attack_time)
		< int(WeaponRegistry.definition("SHORT_SWORD").attack_time), "unarmed is intrinsically fast")
	check(WeaponRegistry.definition("CROSSBOW").reload_required \
		and not WeaponRegistry.definition("BOW").reload_required, "only crossbow reloads")
	return finish()


func test_proficiency_only_changes_accuracy_and_damage_never_weapon_speed() -> bool:
	var novice := WeaponRules.build_attack_spec("HAND_AXE", 0, 10, 100, 120, 3)
	var veteran := WeaponRules.build_attack_spec("HAND_AXE", 10, 10, 100, 120, 3)
	check(not novice.is_empty() and not veteran.is_empty(), "attack specs build")
	check(int(veteran.hit_chance_milli) > int(novice.hit_chance_milli), "rank raises accuracy")
	check(int(veteran.normal_final_damage) > int(novice.normal_final_damage), "rank raises damage")
	check_eq(veteran.attack_time, novice.attack_time, "rank cannot change intrinsic attack time")
	check_eq(veteran.attack_time, WeaponRegistry.definition("HAND_AXE").attack_time,
		"attack time comes from weapon")
	return finish()


func test_weapon_identity_exports_reach_cleave_stun_and_deterministic_resolution() -> bool:
	var ally_block := {Vector2i(1, 0): "ALLY"}
	var enemy_block := {Vector2i(1, 0): "ENEMY"}
	check_eq(WeaponRules.targeting_error(Vector2i.ZERO, Vector2i(2, 0), "SPEAR", ally_block), "",
		"spear reaches over ally")
	check_eq(WeaponRules.targeting_error(Vector2i.ZERO, Vector2i(2, 0), "SPEAR", enemy_block),
		"spear_line_blocked", "spear cannot pierce enemy")
	check_eq(WeaponRules.targeting_error(Vector2i.ZERO, Vector2i(3, 0), "SPEAR"),
		"target_out_of_range", "spear caps at two cells")
	var axe_spec := WeaponRules.build_attack_spec("HAND_AXE", 0, 20, 500, 0, 0)
	var mace_spec := WeaponRules.build_attack_spec("MACE", 0, 20, 500, 0, 0)
	check(int(axe_spec.secondary_damage_milli) > 0, "axe exports cleave damage")
	check(int(mace_spec.stun_chance_milli) > 0, "mace exports stun chance")
	var key := WeaponRules.commitment_key(7, 2, 100, "TEST", 0, 1, 2, "MACE", 0)
	var bleed_roll := WeaponRules.lane_roll_milli(key, "BLEED")
	check(bleed_roll >= 0 and bleed_roll < 1000 \
		and bleed_roll == WeaponRules.lane_roll_milli(key, "BLEED"),
		"weapon BLEED lane is defined and deterministic")
	check_eq(WeaponRules.resolve_attack_spec(mace_spec, key),
		WeaponRules.resolve_attack_spec(mace_spec, key), "weapon resolution is deterministic")
	check_eq(WeaponRules.secondary_target_ids(Vector2i(5, 5), [
		{"entity_id":8, "position":Vector2i(6, 5)},
		{"entity_id":3, "position":Vector2i(4, 4)},
		{"entity_id":9, "position":Vector2i(8, 5)}]), [3, 8], "cleave candidates are stable")
	return finish()


func test_numeric_ammo_and_crossbow_reload_are_minimal_and_exact() -> bool:
	var bow = Loadout.new("BOW", 2, 0)
	check(bow.consume_attack().accepted and int(bow.ammo_pools.ARROW) == 1, "bow consumes one arrow")
	check(bow.consume_attack().accepted and int(bow.ammo_pools.ARROW) == 0, "bow repeats without reload")
	check_eq(bow.consume_attack().reason, "ammo_empty", "empty bow rejects")
	var crossbow = Loadout.new("CROSSBOW", 0, 2)
	check_eq(crossbow.attack_error(), "reload_required", "crossbow starts unloaded")
	var reload_result := crossbow.reload()
	check(reload_result.accepted and int(reload_result.reload_time) > 0, "reload is explicit action data")
	check(crossbow.consume_attack().accepted and int(crossbow.ammo_pools.BOLT) == 1 \
		and not crossbow.crossbow_loaded, "crossbow fires one bolt then unloads")
	var saved := crossbow.to_dict()
	check_eq(Loadout.wire_error(saved), "", "loadout wire validates")
	check_eq(Loadout.from_dict(saved).to_dict(), saved, "loadout round trips")
	return finish()


func test_six_proficiencies_save_focus_award_and_read_legacy() -> bool:
	var progression = Progression.new()
	check_eq(ProgressionRegistry.training_modes_error(progression.training_modes), "", "default modes validate")
	var training_ids: Array = progression.skill_training.keys(); training_ids.sort()
	check_eq(training_ids,
		["AXE", "BLUNT", "RANGED", "SPEAR", "SWORD", "UNARMED"], "six training pools")
	check(progression.set_training_mode("RANGED", "FOCUS"), "RANGED changes independently")
	check_eq(progression.training_modes.RANGED, "FOCUS", "selected mode is authoritative")
	check(progression.award_victory(4), "victory awards once")
	check_eq([progression.xp_total, progression.skill_training.RANGED], [100, 37],
		"3:1 focused victory distribution with fixed-order remainder")
	var saved := progression.to_dict()
	check_eq(Progression.wire_error(saved), "", "new progression wire validates")
	check_eq(Progression.from_dict(saved).to_dict(), saved, "new progression round trips")
	var legacy := {"schema_version":1, "xp_total":100,
		"training_focus":[{"skill_id":"MELEE","weight":50},{"skill_id":"GUARD","weight":30},
			{"skill_id":"EXPLORATION","weight":20}],
		"skill_training":[{"skill_id":"MELEE","training_total":50},
			{"skill_id":"GUARD","training_total":30},{"skill_id":"EXPLORATION","training_total":20}],
		"processed_victory_event_ids":["4"]}
	check_eq(Progression.wire_error(legacy), "", "legacy wire remains readable")
	var migrated = Progression.from_dict(legacy)
	check_eq([migrated.schema_version, migrated.xp_total, migrated.skill_training.SWORD], [3, 100, 50],
		"legacy melee becomes sword familiarity")
	return finish()


func test_independent_modes_allocate_raw_weights_and_migrate_schema_two() -> bool:
	var progression = Progression.new()
	check(progression.set_training_mode("SWORD", "FOCUS"), "SWORD focuses independently")
	check(progression.set_training_mode("AXE", "OFF"), "AXE switches off independently")
	check_eq(ProgressionRegistry.PROFICIENCY_IDS.map(
		func(skill_id): return progression.training_modes[skill_id]),
		["FOCUS", "OFF", "NORMAL", "NORMAL", "NORMAL", "NORMAL"],
		"mode authority preserves every independent row")
	check(progression.award_victory(7), "mode-weighted victory awards")
	check_eq(ProgressionRegistry.PROFICIENCY_IDS.map(
		func(skill_id): return progression.skill_training[skill_id]),
		[43, 0, 15, 14, 14, 14],
		"3/1/0 quotient and remainder use fixed proficiency order")
	var schema_two := {"schema_version":2, "xp_total":100,
		"training_focus":[{"skill_id":"SWORD","weight":10},{"skill_id":"AXE","weight":10},
			{"skill_id":"BLUNT","weight":10},{"skill_id":"SPEAR","weight":10},
			{"skill_id":"RANGED","weight":50},{"skill_id":"UNARMED","weight":10}],
		"skill_training":[{"skill_id":"SWORD","training_total":10},
			{"skill_id":"AXE","training_total":10},{"skill_id":"BLUNT","training_total":10},
			{"skill_id":"SPEAR","training_total":10},{"skill_id":"RANGED","training_total":50},
			{"skill_id":"UNARMED","training_total":10}],
		"processed_victory_event_ids":["7"]}
	check_eq(Progression.wire_error(schema_two), "", "schema two wire remains readable")
	var migrated = Progression.from_dict(schema_two)
	check_eq([migrated.schema_version, migrated.training_modes.RANGED,
		migrated.training_modes.SWORD, migrated.skill_training.RANGED],
		[3, "FOCUS", "NORMAL", 50], "schema two preset migrates without inventing XP")
	return finish()
