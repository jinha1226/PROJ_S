extends "res://tests/test_case.gd"

const Registry = preload("res://sim/decision_ruleset_registry.gd")
const GOLDEN_DUNGEON := "7e784f4d37888b696a58b360c08d0dfea3b1e2faa974a03760f274f4840785bd"
const GOLDEN_EXPEDITION := "856f22f6209d487d20f183e7227e0481ff74eb92a87f9c6234055bf929e5db8b"


func test_party_ruleset_is_registered_and_valid() -> bool:
	check_eq(Registry.validation_error(), "", "registry validates with party ruleset")
	check_eq(Registry.PARTY_RULESET_ID, "party-companion-utility-v3-emotion", "ruleset id")
	var ids: Array = Registry.party_actions().map(func(action): return action.action_id)
	check_eq(ids, ["ENGAGE", "HOLD", "PROTECT", "RETREAT"], "four party actions sorted")
	check_eq(Registry.party_mode_actions("NORMAL"),
		["ENGAGE", "PROTECT", "RETREAT", "HOLD"], "normal mode")
	check_eq(Registry.party_mode_actions("PANIC"), ["RETREAT", "HOLD"], "panic mode")
	for action in Registry.party_actions():
		check_eq(action.commitment_duration, 0, "%s stores no commitment" % action.action_id)
		check_eq(action.cooldown_duration, 0, "%s stores no cooldown" % action.action_id)
		check(action.gates.is_empty(),
			"%s gates are evaluated by the coordinator, not the registry" % action.action_id)
		for consideration in action.considerations:
			check(consideration.input_id in Registry.party_inputs(),
				"%s uses whitelisted input %s" % [action.action_id, consideration.input_id])
			if consideration.input_id.begins_with("facet."):
				check(absi(consideration.signed_weight_milli) <= 300, "facet weight cap")
			if consideration.input_id.begins_with("relation."):
				check(absi(consideration.signed_weight_milli) <= 500, "relation weight cap")
	return finish()


func test_party_ruleset_does_not_change_existing_rulesets() -> bool:
	var dungeon: Array = Registry.actions().map(func(action): return _action_key(action))
	var expedition: Array = Registry.expedition_actions().map(func(action): return _action_key(action))
	check_eq(dungeon.size(), 6, "dungeon ruleset still has 6 actions")
	check_eq(expedition.size(), 6, "expedition ruleset still has 6 actions")
	check_eq(JSON.stringify(dungeon).sha256_text(), GOLDEN_DUNGEON, "dungeon ruleset unchanged")
	check_eq(JSON.stringify(expedition).sha256_text(), GOLDEN_EXPEDITION,
		"expedition ruleset unchanged")
	return finish()


func test_party_evaluate_is_integer_and_explainable() -> bool:
	var engage = Registry.party_action("ENGAGE")
	var inputs := {}
	for input_id in Registry.party_inputs():
		inputs[input_id] = 500
	var evaluated: Dictionary = Registry.evaluate(engage, inputs)
	check_eq(evaluated.error, "", "all inputs supplied")
	check(evaluated.score is int, "score is int")
	var total: int = int(evaluated.base_score)
	for row in evaluated.considerations:
		total += int(row.contribution)
	check_eq(total, int(evaluated.score), "contributions sum to score")
	var missing: Dictionary = Registry.evaluate(engage, {})
	check(str(missing.error).begins_with("missing_or_invalid_input:"),
		"missing input is reported")
	return finish()


func _action_key(action) -> Dictionary:
	return {"id": action.action_id, "base": action.base_score,
		"rank": action.tie_break_rank, "commit": action.commitment_duration,
		"cooldown": action.cooldown_duration, "margin": action.switch_margin,
		"modes": action.allowed_mode_ids,
		"considerations": action.considerations.map(func(consideration):
			return [consideration.consideration_id, consideration.input_id,
				consideration.curve_id, consideration.signed_weight_milli])}
