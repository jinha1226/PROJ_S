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
		"schema_version": 1,
		"seed": str(seed_value),
		"tick_index": str(tick_index),
		"world_time": str(tick_index * 100),
		"map_size": [15, 15],
		"distance": 4,
		"actors": actors.duplicate(true),
		"phase": "COMPLETE" if tick_index >= 3 else "ACTIVE",
		"last_resolution": last_resolution.duplicate(true),
		"recent_events": logs.duplicate(true),
	}


func decision_breakdowns() -> Array:
	return [
		_actor_breakdown("actor_a", "ENGAGE", "상대는 위험하지만 아직 몸 상태가 버틸 만해 맞서기로 했습니다.", true),
		_actor_breakdown("actor_b", "FLEE", "종족 간 적대감보다 현재 부상과 위험이 더 크게 느껴져 물러납니다.", false),
	].duplicate(true)


func step() -> Dictionary:
	step_calls += 1
	if tick_index >= 3:
		return {"accepted": false, "reason": "scenario_complete"}
	tick_index += 1
	actors[1].hp = maxi(0, int(actors[1].hp) - 9)
	actors[1].position = [10, 7]
	var first_id := (tick_index - 1) * 5 + 1
	last_resolution = {
		"turn_index": str(tick_index),
		"event_ids": [str(first_id), str(first_id + 1), str(first_id + 2), str(first_id + 3), str(first_id + 4)],
		"action_rows": [
			{"actor_id": "actor_a", "action_id": "ENGAGE"},
			{"actor_id": "actor_b", "action_id": "FLEE"},
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
			"id": "actor_a", "name": "라온", "species_id": "human", "position": [5, 7],
			"hp": 82, "max_hp": 100, "alive": true,
			"dot": [{"label_ko": "출혈", "remaining": 3}], "armed": true,
			"weapon": "장검", "power": 67, "supplies": 1,
			"memory": {"kind": "HARMED", "modifier": -35},
			"hexaco": {"H": 620, "E": 410, "X": 720, "A": 280, "C": 690, "O": 540},
		},
		{
			"id": "actor_b", "name": "모그", "species_id": "goblin", "position": [9, 7],
			"hp": 46, "max_hp": 90, "alive": true, "dot": [], "armed": true,
			"weapon": "굽은 단검", "power": 49, "supplies": 0,
			"memory": {"kind": "HELPED", "modifier": 15},
			"hexaco": {"H": 210, "E": 760, "X": 350, "A": 330, "C": 430, "O": 610},
		},
	]


func _actor_breakdown(actor_id: String, selected_action: String, reason: String,
		engage_selected: bool) -> Dictionary:
	var engage_total := 438 if actor_id == "actor_a" else 260
	var flee_total := 290 if actor_id == "actor_a" else 515
	return {
		"actor_id": actor_id,
		"selected_action_id": selected_action,
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
				"action_id": "ENGAGE", "atomic_verb": "MELEE", "legal": true,
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
				"action_id": "FLEE", "atomic_verb": "MOVE", "legal": true,
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
				"action_id": "REST", "atomic_verb": "WAIT", "legal": false,
				"rejection_reason": "적이 가까워 안전하게 쉴 수 없습니다.", "base": 40,
				"hexaco_terms": [], "state_terms": [], "relation_terms": [], "context_terms": [],
				"jitter": 0, "total": -999, "selected": false,
			},
		],
	}
