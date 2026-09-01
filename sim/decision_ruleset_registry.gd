class_name DecisionRulesetRegistry
extends RefCounted

const FixedPointScript = preload("res://sim/fixed_point.gd")

const RULESET_ID := "dungeon-hierarchical-utility-v1"
const EXPEDITION_RULESET_ID := "npc-expedition-utility-v1"
const PARTY_RULESET_ID := "party-companion-utility-v1"
const SCORE_COMBINER_ID := "weighted-sum-v1"
const SCORE_MIN := -1000000
const SCORE_MAX := 1000000
const ACTION_IDS := ["ENGAGE", "PROTECT", "FLEE", "TAKE_COVER", "HOLD", "FREEZE"]
const EXPEDITION_ACTION_IDS := ["APPROACH", "ATTACK", "FINISH", "USE_ITEM", "LOOT", "RETURN"]
const PARTY_ACTION_IDS := ["ENGAGE", "PROTECT", "RETREAT", "HOLD"]
const MODE_IDS := ["NORMAL", "PANIC"]
const PARTY_MODE_IDS := ["NORMAL", "PANIC"]
const PARTY_INPUTS := ["facet.aggression", "facet.altruism", "facet.boldness", "facet.composure",
	"appraisal.attack_drive", "appraisal.perceived_threat", "appraisal.panic_pressure",
	"context.hp_loss", "context.ally_targeted", "context.ally_hp_loss", "context.engaged_enemies",
	"context.outnumbered", "context.claim_alignment", "context.focus_alignment",
	"relation.ally_trust", "relation.protagonist_trust", "affect.stress"]

class CurveDef extends RefCounted:
	var def_version := 1
	var curve_id: String
	var control_points: Array[Vector2i] = []
	func _init(p_id: String, points: Array) -> void:
		curve_id = p_id
		for point in points: control_points.append(Vector2i(int(point[0]), int(point[1])))

class GateDef extends RefCounted:
	var def_version := 1
	var gate_id: String
	var evaluator_id: String
	func _init(p_id: String, p_evaluator: String) -> void:
		gate_id = p_id; evaluator_id = p_evaluator

class ConsiderationDef extends RefCounted:
	var def_version := 1
	var consideration_id: String
	var evaluator_id := "normalized-input-v1"
	var input_id: String
	var curve_id: String
	var signed_weight_milli: int
	func _init(p_id: String, p_input: String, p_curve: String, p_weight: int) -> void:
		consideration_id = p_id; input_id = p_input; curve_id = p_curve; signed_weight_milli = p_weight

class ActionDef extends RefCounted:
	var def_version := 1
	var action_id: String
	var decision_tier: int
	var base_score: int
	var allowed_mode_ids: Array[String] = []
	var tie_break_rank: int
	var commitment_duration: int
	var cooldown_duration: int
	var switch_margin: int
	var candidate_provider_id: String
	var gates: Array = []
	var considerations: Array = []
	var intent_builder_id: String
	var interrupt_policy_id := "commitment-switch-v1"
	func _init(p_id: String, p_modes: Array, p_rank: int, p_base: int,
			p_commit: int, p_cooldown: int, p_margin: int, p_provider: String, p_builder: String) -> void:
		action_id = p_id; decision_tier = 100; base_score = p_base; tie_break_rank = p_rank
		for mode in p_modes: allowed_mode_ids.append(str(mode))
		commitment_duration = p_commit; cooldown_duration = p_cooldown; switch_margin = p_margin
		candidate_provider_id = p_provider; intent_builder_id = p_builder

class MentalModeDef extends RefCounted:
	var def_version := 1
	var mode_id: String
	var candidate_action_ids: Array[String] = []
	var tie_break_rank: int
	var transition_policy_id := "panic-hysteresis-v1"
	func _init(p_id: String, p_actions: Array, p_rank: int) -> void:
		mode_id = p_id; tie_break_rank = p_rank
		for action in p_actions: candidate_action_ids.append(str(action))

static var _curves: Dictionary = {}
static var _actions: Dictionary = {}
static var _modes: Dictionary = {}
static var _expedition_actions: Dictionary = {}
static var _party_actions: Dictionary = {}
static var _party_modes: Dictionary = {}


static func _ensure() -> void:
	if not _actions.is_empty() and not _expedition_actions.is_empty() \
			and not _party_actions.is_empty():
		return
	_actions.clear()
	_expedition_actions.clear()
	_party_actions.clear()
	_party_modes.clear()
	_curves = {
		"linear_up": CurveDef.new("linear_up", [[0, 0], [1000, 1000]]),
		"linear_down": CurveDef.new("linear_down", [[0, 1000], [1000, 0]]),
		"threshold_up": CurveDef.new("threshold_up", [[0, 0], [499, 0], [500, 1000], [1000, 1000]]),
		"threshold_down": CurveDef.new("threshold_down", [[0, 1000], [499, 1000], [500, 0], [1000, 0]]),
	}
	_modes = {
		"NORMAL": MentalModeDef.new("NORMAL", ["ENGAGE", "PROTECT", "FLEE", "TAKE_COVER", "HOLD"], 0),
		"PANIC": MentalModeDef.new("PANIC", ["FLEE", "FREEZE"], 1),
	}
	_add_action("ENGAGE", ["NORMAL"], 0, 100, 200, 100, 100, "threat-v1", "engage-v1", [
		_c("engage.aggression", "facet.aggression", "linear_up", 300),
		_c("engage.boldness", "facet.boldness", "linear_up", 250),
		_c("engage.attack_drive", "appraisal.attack_drive", "linear_up", 500),
		_c("engage.threat", "appraisal.perceived_threat", "linear_up", -400)])
	_add_action("PROTECT", ["NORMAL"], 1, 60, 200, 100, 100, "ally-threatened-v1", "protect-v1", [
		_c("protect.altruism", "facet.altruism", "linear_up", 300),
		_c("protect.trust", "relation.ally_trust", "linear_up", 100),
		_c("protect.targeted", "context.ally_targeted", "linear_up", 150),
		_c("protect.panic", "appraisal.panic_pressure", "linear_up", -300)])
	_add_action("FLEE", ["NORMAL", "PANIC"], 2, 100, 200, 100, 100, "retreat-v1", "flee-v1", [
		_c("flee.threat", "appraisal.perceived_threat", "linear_up", 500),
		_c("flee.hp", "context.hp_loss", "linear_up", 400),
		_c("flee.fear", "affect.fear", "linear_up", 400),
		_c("flee.boldness", "facet.boldness", "linear_up", -300)])
	_add_action("TAKE_COVER", ["NORMAL"], 3, 180, 200, 200, 100, "cover-v1", "cover-v1", [
		_c("cover.threat", "appraisal.perceived_threat", "linear_up", 350),
		_c("cover.composure", "facet.composure", "linear_up", 150)])
	_add_action("HOLD", ["NORMAL"], 4, 200, 100, 0, 50, "self-v1", "hold-v1", [
		_c("hold.composure", "facet.composure", "linear_up", 200),
		_c("hold.threat", "appraisal.perceived_threat", "linear_up", -250)])
	_add_action("FREEZE", ["PANIC"], 5, 100, 0, 0, 0, "self-v1", "freeze-v1", [
		_c("freeze.panic", "appraisal.panic_pressure", "linear_up", 500),
		_c("freeze.composure", "facet.composure", "linear_down", 300)])
	_build_expedition_actions()
	_build_party_actions()


static func _build_expedition_actions() -> void:
	_add_expedition_action("APPROACH", 0, 350, 2, 0, 60, [
		_c("approach.mission_incomplete", "context.mission_incomplete", "linear_up", 700),
		_c("approach.threat", "context.threat", "linear_up", -360),
		_c("approach.distance", "context.target_distance", "linear_up", 180),
		_c("approach.openness", "facet.O", "linear_up", 280),
		_c("approach.extraversion", "facet.X", "linear_up", 220),
		_c("approach.emotionality", "facet.E", "linear_up", -250)])
	_add_expedition_action("ATTACK", 1, 340, 1, 0, 70, [
		_c("attack.viability", "context.combat_viability", "linear_up", 650),
		_c("attack.finish_window", "context.target_finish_window", "linear_up", 600),
		_c("attack.boldness", "facet.E", "linear_down", 140),
		_c("attack.hostility", "facet.A", "linear_down", 100)])
	_add_expedition_action("FINISH", 2, 450, 0, 0, 0, [
		_c("finish.downed", "context.target_downed", "threshold_up", 650),
		_c("finish.threat", "context.threat", "linear_up", -240),
		_c("finish.injury", "context.injury", "linear_up", -150),
		_c("finish.discipline", "facet.C", "linear_up", 100)])
	_add_expedition_action("USE_ITEM", 3, 50, 0, 2, 0, [
		_c("item.urgency", "context.potion_urgency", "threshold_up", 1000),
		_c("item.threat", "context.threat", "linear_up", 180),
		_c("item.discipline", "facet.C", "linear_up", 200)])
	_add_expedition_action("LOOT", 4, 300, 1, 0, 40, [
		_c("loot.available", "context.loot_available", "threshold_up", 700),
		_c("loot.threat", "context.threat", "linear_up", -500),
		_c("loot.pragmatism", "facet.H", "linear_down", 150),
		_c("loot.curiosity", "facet.O", "linear_up", 150)])
	_add_expedition_action("RETURN", 5, 100, 2, 0, 80, [
		_c("return.need", "context.retreat_need", "linear_up", 400),
		_c("return.need_and_escape", "context.retreat_safe_need", "linear_up", 200),
		_c("return.combat_deadly", "context.combat_viability", "linear_down", 300),
		_c("return.fear_pressure", "context.fear_pressure", "linear_up", 250),
		_c("return.loot", "context.carried_loot", "linear_up", 450),
		_c("return.mission_complete", "context.mission_complete", "threshold_up", 650),
		_c("return.agreeableness", "facet.A", "linear_up", 80),
		_c("return.downed", "context.target_downed", "threshold_up", -600)])


static func _add_expedition_action(id: String, rank: int, base: int, commitment: int,
		cooldown: int, margin: int, considerations: Array) -> void:
	var action = ActionDef.new(id, ["EXPEDITION"], rank, base, commitment,
		cooldown, margin, "expedition-v1", "expedition-v1")
	action.considerations = considerations
	_expedition_actions[id] = action


static func _build_party_actions() -> void:
	_party_modes = {
		"NORMAL": ["ENGAGE", "PROTECT", "RETREAT", "HOLD"],
		"PANIC": ["RETREAT", "HOLD"],
	}
	_add_party_action("ENGAGE", 0, 300, [
		_c("party_engage.attack_drive", "appraisal.attack_drive", "linear_up", 450),
		_c("party_engage.claim", "context.claim_alignment", "linear_up", 300),
		_c("party_engage.focus", "context.focus_alignment", "linear_up", 200),
		_c("party_engage.threat", "appraisal.perceived_threat", "linear_up", -300),
		_c("party_engage.hp_loss", "context.hp_loss", "linear_up", -250),
		_c("party_engage.aggression", "facet.aggression", "linear_up", 250),
		_c("party_engage.boldness", "facet.boldness", "linear_up", 200),
		_c("party_engage.stress", "affect.stress", "linear_up", -200),
	])
	_add_party_action("PROTECT", 1, 200, [
		_c("party_protect.ally_targeted", "context.ally_targeted", "threshold_up", 500),
		_c("party_protect.ally_hp_loss", "context.ally_hp_loss", "linear_up", 300),
		_c("party_protect.trust", "relation.ally_trust", "linear_up", 300),
		_c("party_protect.altruism", "facet.altruism", "linear_up", 300),
		_c("party_protect.panic", "appraisal.panic_pressure", "linear_up", -300),
		_c("party_protect.hp_loss", "context.hp_loss", "linear_up", -150),
	])
	_add_party_action("RETREAT", 2, 100, [
		_c("party_retreat.threat", "appraisal.perceived_threat", "linear_up", 450),
		_c("party_retreat.hp_loss", "context.hp_loss", "linear_up", 400),
		_c("party_retreat.stress", "affect.stress", "linear_up", 350),
		_c("party_retreat.engaged", "context.engaged_enemies", "linear_up", 250),
		_c("party_retreat.outnumbered", "context.outnumbered", "linear_up", 200),
		_c("party_retreat.boldness", "facet.boldness", "linear_up", -300),
		_c("party_retreat.composure", "facet.composure", "linear_up", -100),
	])
	_add_party_action("HOLD", 3, 250, [
		_c("party_hold.composure", "facet.composure", "linear_up", 150),
		_c("party_hold.threat", "appraisal.perceived_threat", "linear_up", -250),
		_c("party_hold.engaged", "context.engaged_enemies", "linear_up", -300),
	])


static func _add_party_action(id: String, rank: int, base: int, considerations: Array) -> void:
	var modes := ["NORMAL"] if id in ["ENGAGE", "PROTECT"] else ["NORMAL", "PANIC"]
	var action = ActionDef.new(id, modes, rank, base, 0, 0, 0, "party-v1", "party-v1")
	action.considerations = considerations
	_party_actions[id] = action


static func _c(id: String, input: String, curve: String, weight: int):
	return ConsiderationDef.new(id, input, curve, weight)


static func _add_action(id: String, modes: Array, rank: int, base: int, commitment: int,
		cooldown: int, margin: int, provider: String, builder: String, considerations: Array) -> void:
	var action = ActionDef.new(id, modes, rank, base, commitment, cooldown, margin, provider, builder)
	action.gates = [GateDef.new("alive-ready", "alive-ready-v1"), GateDef.new("mode", "mode-v1"),
		GateDef.new("target", "target-valid-v1"), GateDef.new("cooldown", "cooldown-v1")]
	action.considerations = considerations
	_actions[id] = action


static func action(action_id: String): _ensure(); return _copy_action(_actions.get(action_id))
static func mode(mode_id: String): _ensure(); return _copy_mode(_modes.get(mode_id))
static func curve(curve_id: String): _ensure(); return _copy_curve(_curves.get(curve_id))
static func actions() -> Array:
	_ensure(); var ids: Array = _actions.keys(); ids.sort(); return ids.map(func(id): return _copy_action(_actions[id]))
static func modes() -> Array: _ensure(); return [_copy_mode(_modes.NORMAL), _copy_mode(_modes.PANIC)]
static func expedition_action(action_id: String):
	_ensure(); return _copy_action(_expedition_actions.get(action_id))
static func expedition_actions() -> Array:
	_ensure(); var ids: Array = _expedition_actions.keys(); ids.sort()
	return ids.map(func(id): return _copy_action(_expedition_actions[id]))
static func party_action(action_id: String):
	_ensure(); return _copy_action(_party_actions.get(action_id))
static func party_actions() -> Array:
	_ensure(); var ids: Array = _party_actions.keys(); ids.sort()
	return ids.map(func(id): return _copy_action(_party_actions[id]))
static func party_mode_actions(mode_id: String) -> Array[String]:
	_ensure()
	var result: Array[String] = []
	for action_id in _party_modes.get(mode_id, []):
		result.append(str(action_id))
	return result
static func party_inputs() -> Array[String]:
	var result: Array[String] = []
	for input_id in PARTY_INPUTS:
		result.append(input_id)
	return result

static func _copy_curve(source):
	if source == null: return null
	var points: Array = []
	for p in source.control_points: points.append([p.x, p.y])
	return CurveDef.new(source.curve_id, points)

static func _copy_mode(source):
	if source == null: return null
	return MentalModeDef.new(source.mode_id, source.candidate_action_ids, source.tie_break_rank)

static func _copy_action(source):
	if source == null: return null
	var copy = ActionDef.new(source.action_id, source.allowed_mode_ids, source.tie_break_rank, source.base_score,
		source.commitment_duration, source.cooldown_duration, source.switch_margin, source.candidate_provider_id, source.intent_builder_id)
	copy.decision_tier = source.decision_tier; copy.interrupt_policy_id = source.interrupt_policy_id
	for gate in source.gates: copy.gates.append(GateDef.new(gate.gate_id, gate.evaluator_id))
	for c in source.considerations: copy.considerations.append(ConsiderationDef.new(c.consideration_id, c.input_id, c.curve_id, c.signed_weight_milli))
	return copy


static func evaluate_curve(curve_id: String, raw_input: int) -> int:
	_ensure()
	var definition = _curves.get(curve_id)
	if definition == null: return -1
	var x := clampi(raw_input, 0, 1000)
	for index in range(definition.control_points.size() - 1):
		var a: Vector2i = definition.control_points[index]
		var b: Vector2i = definition.control_points[index + 1]
		if x >= a.x and x <= b.x:
			return FixedPointScript.interpolate(x, a.x, a.y, b.x, b.y)
	return -1


static func evaluate(action_def, inputs: Dictionary) -> Dictionary:
	var score: int = action_def.base_score
	var rows: Array[Dictionary] = []
	for consideration in action_def.considerations:
		if not inputs.has(consideration.input_id) or not (inputs[consideration.input_id] is int):
			return {"error": "missing_or_invalid_input:%s" % consideration.input_id,
				"base_score": action_def.base_score, "score": SCORE_MIN, "considerations": []}
		var raw := clampi(int(inputs.get(consideration.input_id, 0)), 0, 1000)
		var output := evaluate_curve(consideration.curve_id, raw)
		var contribution := FixedPointScript.weighted_contribution(output, consideration.signed_weight_milli)
		score = clampi(score + contribution, SCORE_MIN, SCORE_MAX)
		rows.append({"consideration_id": consideration.consideration_id, "input_id": consideration.input_id,
			"raw_input": raw, "normalized_input": raw, "curve_id": consideration.curve_id,
			"curve_output": output, "signed_weight_milli": consideration.signed_weight_milli,
			"contribution": contribution, "veto": false, "reason": "", "evidence_ids": []})
	return {"error": "", "base_score": action_def.base_score, "score": score, "considerations": rows}


static func validation_error() -> String:
	_ensure()
	var curve_ids: Array = _curves.keys(); curve_ids.sort()
	var expected_curve_ids := ["linear_down", "linear_up", "threshold_down", "threshold_up"]
	if curve_ids != expected_curve_ids: return "unknown_or_missing_curve"
	var action_keys: Array = _actions.keys(); action_keys.sort()
	var expected_action_keys: Array = ACTION_IDS.duplicate(); expected_action_keys.sort()
	if action_keys != expected_action_keys: return "unknown_or_missing_action"
	var mode_keys: Array = _modes.keys(); mode_keys.sort()
	var expected_mode_keys: Array = MODE_IDS.duplicate(); expected_mode_keys.sort()
	if mode_keys != expected_mode_keys: return "unknown_or_missing_mode"
	for curve_id in curve_ids:
		var d = _curves[curve_id]
		if d.def_version != 1 or d.curve_id != curve_id or not _stable_id(curve_id): return "invalid_curve_identity"
		if d.control_points.size() < 2 or d.control_points.size() > 8: return "invalid_curve_point_count"
		if d.control_points[0].x != 0 or d.control_points[-1].x != 1000: return "invalid_curve_endpoints"
		for i in range(d.control_points.size()):
			var p: Vector2i = d.control_points[i]
			if p.y < 0 or p.y > 1000 or (i > 0 and p.x <= d.control_points[i - 1].x): return "invalid_curve_points"
	var ranks: Dictionary = {}
	var mode_ranks: Dictionary = {}
	var global_gate_ids: Dictionary = {}
	var global_consideration_ids: Dictionary = {}
	var allowed_inputs := ["facet.aggression", "facet.altruism", "facet.boldness", "facet.composure",
		"appraisal.attack_drive", "appraisal.perceived_threat", "appraisal.panic_pressure",
		"context.hp_loss", "context.ally_targeted", "relation.ally_trust", "affect.fear"]
	var providers := ["threat-v1", "ally-threatened-v1", "retreat-v1", "cover-v1", "self-v1"]
	var builders := ["engage-v1", "protect-v1", "flee-v1", "cover-v1", "hold-v1", "freeze-v1"]
	for action_id in ACTION_IDS:
		var a = _actions.get(action_id)
		if a == null: return "missing_action"
		if a.def_version != 1 or a.action_id != action_id or a.decision_tier < 0 or a.decision_tier > 1000:
			return "invalid_action_identity"
		if ranks.has(a.tie_break_rank): return "duplicate_action_tie_break_rank"
		ranks[a.tie_break_rank] = true
		if a.tie_break_rank < 0 or not _stable_id(a.action_id.to_lower()): return "invalid_action_rank_or_id"
		if a.base_score < -10000 or a.base_score > 10000 or a.considerations.size() > 12 \
				or a.commitment_duration < 0 or a.commitment_duration > 10000 or a.cooldown_duration < 0 \
				or a.cooldown_duration > 10000 or a.switch_margin < 0 or a.switch_margin > 10000:
			return "invalid_action_range"
		if a.candidate_provider_id not in providers or a.intent_builder_id not in builders \
				or a.interrupt_policy_id != "commitment-switch-v1": return "unknown_action_strategy"
		var allowed_modes_seen := {}
		if a.allowed_mode_ids.is_empty(): return "missing_allowed_mode"
		for allowed_mode_id in a.allowed_mode_ids:
			if allowed_mode_id not in MODE_IDS or allowed_modes_seen.has(allowed_mode_id): return "invalid_allowed_mode"
			allowed_modes_seen[allowed_mode_id] = true
			if not _modes[allowed_mode_id].candidate_action_ids.has(action_id): return "allowed_mode_reverse_reference_missing"
		var gate_ids := {}; var consideration_ids := {}
		if a.gates.size() != 4: return "invalid_gate_count"
		for gate in a.gates:
			var scoped_gate_id := "%s.%s" % [action_id.to_lower(), gate.gate_id]
			if gate.def_version != 1 or not _stable_id(gate.gate_id) or not _stable_id(gate.evaluator_id) \
					or gate_ids.has(gate.gate_id) or global_gate_ids.has(scoped_gate_id) \
					or gate.evaluator_id not in ["alive-ready-v1", "mode-v1", "target-valid-v1", "cooldown-v1"]:
				return "invalid_or_duplicate_gate"
			gate_ids[gate.gate_id] = true
			global_gate_ids[scoped_gate_id] = true
		for c in a.considerations:
			if c.def_version != 1 or not _stable_id(c.consideration_id) or not _stable_id(c.evaluator_id) \
					or not _stable_id(c.input_id) or not _stable_id(c.curve_id) \
					or consideration_ids.has(c.consideration_id) or global_consideration_ids.has(c.consideration_id) \
					or c.evaluator_id != "normalized-input-v1" \
					or c.input_id not in allowed_inputs or not _curves.has(c.curve_id) or absi(c.signed_weight_milli) > 2000:
				return "invalid_or_duplicate_consideration"
			consideration_ids[c.consideration_id] = true
			global_consideration_ids[c.consideration_id] = true
			if c.input_id.begins_with("facet.") and absi(c.signed_weight_milli) > 300: return "personality_weight_too_large"
			if c.input_id.begins_with("relation.") and absi(c.signed_weight_milli) > 500: return "relation_weight_too_large"
	for mode_id in MODE_IDS:
		var m = _modes.get(mode_id)
		if m == null: return "missing_mode"
		if m.def_version != 1 or m.mode_id != mode_id or not _stable_id(mode_id.to_lower()) \
				or m.transition_policy_id != "panic-hysteresis-v1" or m.tie_break_rank < 0 \
				or mode_ranks.has(m.tie_break_rank): return "invalid_or_duplicate_mode"
		mode_ranks[m.tie_break_rank] = true
		var candidates_seen := {}
		for action_id in m.candidate_action_ids:
			if candidates_seen.has(action_id) or not _actions.has(action_id) or not _actions[action_id].allowed_mode_ids.has(mode_id): return "invalid_mode_action_cross_reference"
			candidates_seen[action_id] = true
	if not _modes.NORMAL.candidate_action_ids.has("HOLD") or not _modes.PANIC.candidate_action_ids.has("FREEZE"):
		return "missing_mode_fallback"
	var expedition_keys: Array = _expedition_actions.keys(); expedition_keys.sort()
	var expected_expedition_keys: Array = EXPEDITION_ACTION_IDS.duplicate(); expected_expedition_keys.sort()
	if expedition_keys != expected_expedition_keys: return "unknown_or_missing_expedition_action"
	var expedition_ranks: Dictionary = {}
	var expedition_inputs := ["context.injury", "context.threat", "context.target_distance",
		"context.target_downed", "context.potion_urgency", "context.loot_available",
		"context.carried_loot", "context.combat_viability", "context.retreat_viability",
		"context.target_finish_window", "context.retreat_need", "context.retreat_safe_need",
		"context.fear_pressure", "context.mission_complete", "context.mission_incomplete",
		"facet.H", "facet.E", "facet.X", "facet.A", "facet.C", "facet.O"]
	for action_id in EXPEDITION_ACTION_IDS:
		var expedition = _expedition_actions.get(action_id)
		if expedition == null or expedition.action_id != action_id \
				or expedition.allowed_mode_ids != ["EXPEDITION"] \
				or expedition_ranks.has(expedition.tie_break_rank) \
				or expedition.base_score < -10000 or expedition.base_score > 10000 \
				or expedition.commitment_duration < 0 or expedition.commitment_duration > 4 \
				or expedition.cooldown_duration < 0 or expedition.cooldown_duration > 4 \
				or expedition.switch_margin < 0 or expedition.switch_margin > 1000 \
				or not expedition.gates.is_empty() or expedition.considerations.is_empty() \
				or expedition.considerations.size() > 12:
			return "invalid_expedition_action"
		expedition_ranks[expedition.tie_break_rank] = true
		var consideration_ids: Dictionary = {}
		for consideration in expedition.considerations:
			if consideration_ids.has(consideration.consideration_id) \
					or consideration.input_id not in expedition_inputs \
					or not _curves.has(consideration.curve_id) \
					or absi(consideration.signed_weight_milli) > 2000:
				return "invalid_expedition_consideration"
			consideration_ids[consideration.consideration_id] = true
	var party_keys: Array = _party_actions.keys(); party_keys.sort()
	var expected_party_keys: Array = PARTY_ACTION_IDS.duplicate(); expected_party_keys.sort()
	if party_keys != expected_party_keys:
		return "invalid_party_action"
	var party_mode_keys: Array = _party_modes.keys(); party_mode_keys.sort()
	var expected_party_mode_keys: Array = PARTY_MODE_IDS.duplicate(); expected_party_mode_keys.sort()
	if party_mode_keys != expected_party_mode_keys:
		return "invalid_party_mode"
	var party_ranks: Dictionary = {}
	var party_consideration_ids: Dictionary = {}
	for action_id in PARTY_ACTION_IDS:
		var party_action_def = _party_actions.get(action_id)
		if party_action_def == null or party_action_def.action_id != action_id \
				or party_action_def.allowed_mode_ids.is_empty() \
				or party_ranks.has(party_action_def.tie_break_rank) \
				or party_action_def.base_score < -10000 or party_action_def.base_score > 10000 \
				or party_action_def.commitment_duration != 0 \
				or party_action_def.cooldown_duration != 0 \
				or party_action_def.switch_margin != 0 \
				or party_action_def.candidate_provider_id != "party-v1" \
				or party_action_def.intent_builder_id != "party-v1" \
				or not party_action_def.gates.is_empty() \
				or party_action_def.considerations.is_empty() \
				or party_action_def.considerations.size() > 12:
			return "invalid_party_action"
		party_ranks[party_action_def.tie_break_rank] = true
		var action_modes: Dictionary = {}
		for mode_id in party_action_def.allowed_mode_ids:
			if mode_id not in PARTY_MODE_IDS or action_modes.has(mode_id) \
					or action_id not in _party_modes.get(mode_id, []):
				return "invalid_party_mode"
			action_modes[mode_id] = true
		var action_consideration_ids: Dictionary = {}
		for consideration in party_action_def.considerations:
			if consideration.def_version != 1 \
					or not str(consideration.consideration_id).begins_with("party_") \
					or not _stable_id(consideration.consideration_id) \
					or action_consideration_ids.has(consideration.consideration_id) \
					or party_consideration_ids.has(consideration.consideration_id) \
					or consideration.input_id not in PARTY_INPUTS \
					or not _curves.has(consideration.curve_id) \
					or absi(consideration.signed_weight_milli) > 2000 \
					or (consideration.input_id.begins_with("facet.") \
						and absi(consideration.signed_weight_milli) > 300) \
					or (consideration.input_id.begins_with("relation.") \
						and absi(consideration.signed_weight_milli) > 500):
				return "invalid_party_consideration"
			action_consideration_ids[consideration.consideration_id] = true
			party_consideration_ids[consideration.consideration_id] = true
	for mode_id in PARTY_MODE_IDS:
		var seen_party_actions: Dictionary = {}
		var mode_action_ids: Array = _party_modes.get(mode_id, [])
		if mode_action_ids.is_empty():
			return "invalid_party_mode"
		for action_id in mode_action_ids:
			if seen_party_actions.has(action_id) or not _party_actions.has(action_id) \
					or mode_id not in _party_actions[action_id].allowed_mode_ids:
				return "invalid_party_mode"
			seen_party_actions[action_id] = true
	if "HOLD" not in _party_modes.get("NORMAL", []) \
			or "HOLD" not in _party_modes.get("PANIC", []):
		return "invalid_party_mode"
	return ""


static func _stable_id(value: String) -> bool:
	if value.is_empty() or value.to_utf8_buffer().size() > 64: return false
	for code in value.to_ascii_buffer():
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code in [46, 95, 45]): return false
	return true
