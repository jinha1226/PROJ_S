class_name DuelDecisionUIFake
extends RefCounted

var seed_value := 22002
var tick_index := 0
var step_calls := 0
var restart_calls := 0
var random_calls := 0
var actors: Array = []
var logs: Array = []
var last_resolution: Dictionary = {}


func _init(seed: int = 22002) -> void:
	_reset_state(seed)


func observation() -> Dictionary:
	return {
		"schema_version": 3,
		"seed": str(seed_value),
		"tick_index": str(tick_index),
		"world_time": str(tick_index * 100),
		"map_size": [21, 21],
		"actors": actors.duplicate(true),
		"phase": "COMPLETE" if tick_index >= 3 else "ACTIVE",
		"last_resolution": last_resolution.duplicate(true),
		"recent_events": logs.duplicate(true),
	}


func decision_breakdowns() -> Array:
	return [
		_actor_breakdown("actor_a", "ENGAGE", "actor_b",
			"상대는 위험하지만 아직 몸 상태가 버틸 만해 맞서기로 했습니다.", true),
		_actor_breakdown("actor_b", "FLEE", "actor_a",
			"종족 간 적대감보다 현재 부상과 위험이 더 크게 느껴져 물러납니다.", false),
		_simple_breakdown("actor_c", "APPROACH", "actor_a", "동료 쪽으로 조심스럽게 접근합니다.",
			"approach_pressure"),
		_simple_breakdown("actor_d", "SELF_TREAT", "actor_d", "출혈을 먼저 치료하려 합니다.",
			"treatment_need"),
		_simple_breakdown("actor_e", "HOLD", "-1", "상황을 지켜보며 자리를 지킵니다.",
			"uncertainty"),
	].duplicate(true)


func step() -> Dictionary:
	step_calls += 1
	if tick_index >= 3:
		return {"accepted": false, "reason": "scenario_complete"}
	tick_index += 1
	actors[1].hp = maxi(0, int(actors[1].hp) - 9)
	actors[1].position = [17, 10]
	actors[2].position = [9, 5]
	var first_id := (tick_index - 1) * 5 + 1
	last_resolution = {
		"turn_index": str(tick_index),
		"event_ids": [str(first_id), str(first_id + 1), str(first_id + 2), str(first_id + 3), str(first_id + 4)],
		"action_rows": [
			{"actor_id": "actor_a", "action_id": "ENGAGE", "target_id": "actor_b"},
			{"actor_id": "actor_b", "action_id": "FLEE", "target_id": "actor_a"},
			{"actor_id": "actor_c", "action_id": "APPROACH", "target_id": "actor_a"},
			{"actor_id": "actor_d", "action_id": "SELF_TREAT", "target_id": "actor_d"},
			{"actor_id": "actor_e", "action_id": "HOLD", "target_id": "-1"},
		],
		"relationship_changes": [
			{"message_ko": "고블린이 인간을 더 위험한 상대로 기억합니다. · 경계 +12"},
		],
	}
	logs.append({"event_id": str(first_id), "turn_index": str(tick_index), "type": "ACTION",
		"actor_id": "actor_a", "target_id": "actor_b", "action_id": "ENGAGE", "magnitude": 0})
	logs.append({"event_id": str(first_id + 1), "turn_index": str(tick_index), "type": "ACTION",
		"actor_id": "actor_b", "target_id": "actor_a", "action_id": "FLEE", "magnitude": 0})
	logs.append({"event_id": str(first_id + 2), "turn_index": str(tick_index), "type": "DAMAGE",
		"actor_id": "actor_a", "target_id": "actor_b", "action_id": "ENGAGE", "magnitude": 9})
	logs.append({"event_id": str(first_id + 3), "turn_index": str(tick_index), "type": "MOVE",
		"actor_id": "actor_b", "target_id": "actor_a", "action_id": "FLEE", "magnitude": 5})
	logs.append({"event_id": str(first_id + 4), "turn_index": str(tick_index), "type": "MEMORY",
		"actor_id": "actor_b", "target_id": "actor_a", "action_id": "ENGAGE", "magnitude": 35})
	return {"accepted": true, "tick_index": str(tick_index)}


func resolve_turn() -> Dictionary:
	return step()


func reset(seed: int) -> Dictionary:
	_reset_state(seed)
	return {"accepted": true}


func restart_same_scenario() -> Dictionary:
	restart_calls += 1
	_reset_state(seed_value)
	return {"accepted": true}


func new_random_scenario(seed: int) -> Dictionary:
	random_calls += 1
	_reset_state(seed)
	return {"accepted": true}


func recent_logs(limit: int = 24) -> Array:
	return logs.slice(maxi(0, logs.size() - limit)).duplicate(true)


func snapshot() -> Dictionary:
	return observation()


func save_json() -> String:
	return JSON.stringify(observation())


func load_json(_encoded: String) -> Dictionary:
	return {"accepted": true}


func _reset_state(seed: int) -> void:
	seed_value = seed
	tick_index = 0
	logs.clear()
	last_resolution.clear()
	actors = [
		{
			"id": "actor_a", "name": "라온", "species_id": "human", "position": [4, 10],
			"hp": 82, "max_hp": 100, "alive": true,
			"presence": "ACTIVE", "glyph": "A",
			"dot": [{"label_ko": "출혈", "remaining": 3}], "armed": true,
			"weapon": "장검", "power": 67, "supplies": 1,
			"memory": {"kind": "HARMED", "modifier": -35},
			"memories": [{"target_id": "actor_b", "kind": "HARMED", "modifier": -35}],
			"relations": [{"target_id": "actor_b", "species_prior": -40,
				"memory_kind": "HARMED", "memory_modifier": -35, "effective": -75}],
			"hexaco": {"H": 620, "E": 410, "X": 720, "A": 280, "C": 690, "O": 540},
		},
		{
			"id": "actor_b", "name": "모그", "species_id": "goblin", "position": [16, 10],
			"hp": 46, "max_hp": 90, "alive": true, "dot": [], "armed": true,
			"presence": "ACTIVE", "glyph": "B",
			"weapon": "굽은 단검", "power": 49, "supplies": 0,
			"memory": {"kind": "HELPED", "modifier": 15},
			"hexaco": {"H": 210, "E": 760, "X": 350, "A": 330, "C": 430, "O": 610},
		},
		{
			"id": "actor_c", "name": "세라", "species_id": "human", "position": [10, 4],
			"hp": 91, "max_hp": 100, "alive": true, "presence": "ACTIVE", "glyph": "C",
			"dot": [], "armed": true, "weapon": "창", "power": 58, "supplies": 0,
			"memories": [], "relations": [{"target_id": "actor_a", "species_prior": 10,
				"memory_kind": "NONE", "memory_modifier": 0, "effective": 10}],
			"hexaco": {"H": 560, "E": 480, "X": 650, "A": 570, "C": 720, "O": 450},
		},
		{
			"id": "actor_d", "name": "두린", "species_id": "dwarf", "position": [10, 16],
			"hp": 55, "max_hp": 100, "alive": true, "presence": "ACTIVE", "glyph": "D",
			"dot": [{"label_ko": "출혈", "remaining": 2}], "armed": true,
			"weapon": "도끼", "power": 62, "supplies": 1, "memories": [], "relations": [],
			"hexaco": {"H": 640, "E": 680, "X": 390, "A": 610, "C": 780, "O": 310},
		},
		{
			"id": "actor_e", "name": "키리", "species_id": "beastkin", "position": [13, 13],
			"hp": 73, "max_hp": 80, "alive": true, "presence": "ACTIVE", "glyph": "E",
			"dot": [], "armed": false, "weapon": "NONE", "power": 44, "supplies": 0,
			"memories": [], "relations": [],
			"hexaco": {"H": 460, "E": 350, "X": 520, "A": 700, "C": 410, "O": 760},
		},
	]


func _actor_breakdown(actor_id: String, selected_action: String, target_id: String, reason: String,
		engage_selected: bool) -> Dictionary:
	var engage_total := 438 if actor_id == "actor_a" else 260
	var flee_total := 290 if actor_id == "actor_a" else 515
	return {
		"actor_id": actor_id,
		"selected_action_id": selected_action,
		"selected_target_id": target_id,
		"selected_reason_ko": reason,
		"selection_mode": "NEW" if tick_index == 0 else "RETAINED",
		"continued": tick_index > 0,
		"intent_turn_count": tick_index + 1,
		"decision_episode_id": "1",
		"current_intent_id": "" if tick_index == 0 else selected_action,
		"switch_reason_code": "NEW" if tick_index == 0 else "COMMITMENT",
		"switch_reason_ko": "새 판단을 시작했다." if tick_index == 0 else "아직 행동을 유지할 때다.",
		"retention_bonus": 30, "switch_margin": 20, "current_score": 0,
		"challenger_action_id": selected_action, "challenger_score": 0,
		"candidates": [
			{
				"action_id": "ENGAGE", "target_id": "actor_b" if actor_id == "actor_a" else "actor_a",
				"atomic_verb": "MELEE", "legal": true,
				"rejection_reason": "", "base": 100,
				"hexaco_terms": [{"input_id": "X", "contribution": 120}, {"input_id": "A", "contribution": -55}],
				"state_terms": [{"input_id": "health", "contribution": 80}],
				"relation_terms": [
					{"bucket": "SPECIES_PRIOR", "input_id": "species_prior", "contribution": -75},
					{"bucket": "PERSONAL_MEMORY", "input_id": "personal_memory", "contribution": 10},
				],
				"context_terms": [{"input_id": "threat", "contribution": 255}],
				"jitter": 3, "total": engage_total, "selected": engage_selected,
			},
			{
				"action_id": "FLEE", "target_id": "actor_a", "atomic_verb": "MOVE", "legal": true,
				"rejection_reason": "", "base": 80,
				"hexaco_terms": [{"input_id": "E", "contribution": 140}],
				"state_terms": [{"input_id": "injury", "contribution": 120}],
				"relation_terms": [
					{"bucket": "SPECIES_PRIOR", "input_id": "species_prior", "contribution": 35},
					{"bucket": "PERSONAL_MEMORY", "input_id": "personal_memory", "contribution": 20},
				],
				"context_terms": [{"input_id": "danger", "contribution": 115}],
				"jitter": 5, "total": flee_total, "selected": not engage_selected,
			},
			{
				"action_id": "REST", "target_id": "-1", "atomic_verb": "WAIT", "legal": false,
				"rejection_reason": "적이 가까워 안전하게 쉴 수 없습니다.", "base": 40,
				"hexaco_terms": [], "state_terms": [], "relation_terms": [], "context_terms": [],
				"jitter": 0, "total": -999, "selected": false,
			},
		],
	}


func _simple_breakdown(actor_id: String, action_id: String, target_id: String,
		reason: String, input_id: String) -> Dictionary:
	return {
		"actor_id": actor_id, "selected_action_id": action_id,
		"selected_target_id": target_id, "selected_reason_ko": reason,
		"selection_mode": "NEW" if tick_index == 0 else "RETAINED",
		"continued": tick_index > 0, "intent_turn_count": tick_index + 1,
		"decision_episode_id": "1", "current_intent_id": "" if tick_index == 0 else action_id,
		"switch_reason_code": "NEW" if tick_index == 0 else "COMMITMENT",
		"switch_reason_ko": "새 판단을 시작했다." if tick_index == 0 else "아직 행동을 유지할 때다.",
		"retention_bonus": 20, "switch_margin": 20, "current_score": 0,
		"challenger_action_id": action_id, "challenger_score": 0,
		"candidates": [{"action_id": action_id, "target_id": target_id,
			"atomic_verb": "USE_ITEM" if action_id == "SELF_TREAT" else "WAIT" if action_id == "HOLD" else "MOVE",
			"legal": true, "rejection_reason": "", "base": 80,
			"hexaco_terms": [], "state_terms": [{"input_id": input_id, "contribution": 120}],
			"relation_terms": [], "context_terms": [], "jitter": 2, "total": 202,
			"selected": true}],
	}
