class_name PlaytestSession
extends RefCounted

const SimulatorScript = preload("res://sim/simulator.gd")
const CommandScript = preload("res://sim/sim_command.gd")
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const PersonalityRegistry = preload("res://sim/personality_definition_registry.gd")
const EncounterLabStateScript = preload("res://sim/encounter_lab_state.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")

const ARENA_WIDTH := 15
const ARENA_HEIGHT := 15
const DEFAULT_WORLD_SEED := 7
const DEFAULT_PERSONALITY_SEED := 20260827
const SESSION_FORMAT_VERSION := 2
const SAVE_PATH := "user://living_world_personality_lab_v2.json"

var sim
var world_seed: int = DEFAULT_WORLD_SEED
var personality_seed: int = DEFAULT_PERSONALITY_SEED
var command_journal: Array[Dictionary] = []
var selected_lead_id: int = -1
var _status_reason := "reset"
var _last_result = null
var _last_step_event_start: int = 0

func _init(p_world_seed: int = DEFAULT_WORLD_SEED, p_personality_seed: Variant = DEFAULT_PERSONALITY_SEED) -> void:
	reset_lab(p_world_seed, int(p_personality_seed) if p_personality_seed is int else DEFAULT_PERSONALITY_SEED)

func reset_lab(p_world_seed: int, p_personality_seed: int) -> bool:
	var candidate = SimulatorScript.create(ARENA_WIDTH, ARENA_HEIGHT, p_world_seed)
	if candidate == null or not _bootstrap_lab(candidate, p_personality_seed):
		_status_reason = "lab_bootstrap_failed"; return false
	sim = candidate; world_seed = p_world_seed; personality_seed = p_personality_seed
	command_journal = []; _last_result = null; _last_step_event_start = candidate.world.events.size()
	_status_reason = "reset"
	var roster: Array[Dictionary] = lead_roster(); selected_lead_id = int(roster[0].entity_id) if not roster.is_empty() else -1
	return true

func reset(p_seed: int, _legacy_species: Variant = null) -> bool:
	return reset_lab(p_seed, personality_seed)

func lab_status() -> Dictionary:
	if sim == null: return {"ok": false, "reason": "session_not_initialized"}
	return {"ok": true, "reason": _status_reason, "world_seed": world_seed,
		"personality_seed": personality_seed, "width": sim.world.width, "height": sim.world.height,
		"step_index": sim.world.step_index, "world_time": sim.world.world_time,
		"phase": sim.world.encounter_lab.phase, "selected_lead_id": selected_lead_id,
		"command_count": command_journal.size(),
		"ruleset_version": sim.world.RULESET_VERSION,
		"snapshot_version": sim.world.SNAPSHOT_VERSION,
		"session_format_version": SESSION_FORMAT_VERSION}.duplicate(true)

func world_status() -> Dictionary: return lab_status()

func progress_status() -> Dictionary:
	if sim == null: return {"schema_version": 1, "ok": false, "reason": "session_not_initialized"}
	var active_leads := 0
	var alive_threats := 0
	var alive_allies := 0
	for entity_id in _actor_ids("LEAD"):
		var lead_state = sim.world.agent_states[entity_id]
		if sim.world.is_autonomous_target(entity_id) and lead_state.encounter_status == "ACTIVE":
			active_leads += 1
	for entity_id in _actor_ids("MELEE_THREAT"):
		if sim.world.is_autonomous_target(entity_id): alive_threats += 1
	for entity_id in _actor_ids("PASSIVE_ALLY"):
		if sim.world.is_autonomous_target(entity_id): alive_allies += 1
	var resolved_trials := 0
	for trial_slot in range(4):
		var lead_id := _actor_id_for_slot("LEAD", trial_slot)
		var threat_id := _actor_id_for_slot("MELEE_THREAT", trial_slot)
		if lead_id <= 0 or threat_id <= 0: continue
		var lead_active: bool = sim.world.is_autonomous_target(lead_id) \
			and sim.world.agent_states[lead_id].encounter_status == "ACTIVE"
		if not lead_active or not sim.world.is_unresolved_enemy(threat_id): resolved_trials += 1
	var last_advance := {"available": _last_result != null, "accepted": false, "reason": "",
		"processed_ticks": 0, "emitted_event_count": 0, "start_time": sim.world.world_time,
		"end_time": sim.world.world_time, "latest_salient_event": {}}
	if _last_result != null:
		last_advance.accepted = bool(_last_result.accepted)
		last_advance.reason = str(_last_result.reason)
		last_advance.start_time = int(_last_result.start_time)
		last_advance.end_time = int(_last_result.end_time)
		if _last_result.accepted:
			last_advance.processed_ticks = int((_last_result.end_time - _last_result.start_time) / 100)
			var event_start := clampi(_last_step_event_start, 0, sim.world.events.size())
			last_advance.emitted_event_count = sim.world.events.size() - event_start
			last_advance.latest_salient_event = _latest_salient_event(event_start)
	var phase_id := str(sim.world.encounter_lab.phase)
	var display_phase_id := "RESOLVED" if phase_id == "ACTIVE" and resolved_trials >= 4 else phase_id
	return {"schema_version": 1, "ok": true, "tick_index": int(sim.world.world_time / 100),
		"world_time": sim.world.world_time, "step_index": sim.world.step_index,
		"phase_id": phase_id, "display_phase_id": display_phase_id,
		"phase_label": _phase_label(display_phase_id), "total_trials": 4,
		"active_trials": 4 - resolved_trials, "resolved_trials": resolved_trials,
		"active_leads": active_leads, "alive_threats": alive_threats,
		"alive_allies": alive_allies, "last_advance": last_advance}.duplicate(true)

func snapshot_json() -> String:
	return "" if sim == null else JSON.stringify(sim.snapshot())

func command_journal_json() -> String:
	return JSON.stringify(command_journal)

func journal_json() -> String: return command_journal_json()

func player_state() -> Dictionary:
	if sim == null or selected_lead_id <= 0: return {}
	var entity = sim.world.entities[selected_lead_id]
	return {"id": entity.id, "position": [entity.position.x, entity.position.y], "health": entity.health,
		"max_health": entity.max_health, "hp": entity.health, "max_hp": entity.max_health,
		"alive": sim.world.occupies_tile(entity.id), "species_id": entity.species_id, "display_name": entity.display_name}

func recent_events(limit: int = 20) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if sim == null: return rows
	var start := maxi(0, sim.world.events.size() - maxi(0, limit))
	for event in sim.world.events.slice(start): rows.append(event.to_dict())
	return rows.duplicate(true)

func recent_event_log(limit: int = 24) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if sim == null or limit <= 0: return rows
	var start := maxi(0, sim.world.events.size() - limit)
	for event in sim.world.events.slice(start):
		rows.append({
			"event_id": event.id,
			"world_time": event.world_time,
			"type": event.type,
			"actor_id": event.actor_id,
			"target_id": event.target_id,
			"cause_id": event.cause_id,
			"message": _event_log_message(event),
		})
	return rows.duplicate(true)

func last_result_summary() -> Dictionary:
	if _last_result == null: return {"available": false}
	return {"available": true, "accepted": _last_result.accepted, "reason": _last_result.reason,
		"start_time": _last_result.start_time, "end_time": _last_result.end_time,
		"time_cost": _last_result.time_cost, "timeline": _last_result.timeline.duplicate(true),
		"events": recent_events(), "event_log": recent_event_log()}

func _event_log_message(event) -> String:
	var actor_name := _event_entity_name(event.actor_id)
	var target_name := _event_entity_name(event.target_id)
	match str(event.type):
		"action.wait":
			return "시간이 한 턴 흘렀다."
		"encounter.threat_appeared":
			return "%s %s 앞에 나타났다." % [_subject(actor_name), target_name]
		"perception.threat_noticed":
			return "%s %s 발견했다." % [_subject(actor_name), _object(target_name)]
		"ai.mental_mode_changed":
			return _mental_mode_event_message(event, actor_name)
		"ai.decision_selected":
			return _decision_event_message(event, actor_name, target_name)
		"action.move":
			return "%s (%d,%d)로 움직였다." % [_subject(actor_name), event.position.x, event.position.y]
		"action.melee_attack":
			return "%s %s 공격했다." % [_subject(actor_name), _object(target_name)]
		"action.hold":
			return "%s 자리를 지키며 방어했다." % _subject(actor_name)
		"action.freeze":
			return "%s 두려움에 얼어붙었다." % _subject(actor_name)
		"encounter.actor_escaped":
			return "%s 전투에서 달아났다." % _subject(actor_name)
		"combat.physical_damage":
			return "%s 공격을 맞아 %d의 피해를 입었다." % [_subject(target_name), int(event.magnitude)]
		"entity.died":
			return "%s 쓰러졌다." % _subject(target_name)
		_:
			return "기록되지 않은 사건이 일어났다."

func _mental_mode_event_message(event, actor_name: String) -> String:
	var from_mode := str(event.data.get("from_mode", ""))
	var to_mode := str(event.data.get("to_mode", ""))
	if from_mode == "NORMAL" and to_mode == "PANIC":
		return "%s 위협에 겁을 먹고 평정심을 잃었다." % _subject(actor_name)
	if from_mode == "PANIC" and to_mode == "NORMAL":
		return "%s 마음을 추스르고 평정을 되찾았다." % _subject(actor_name)
	return "%s 마음가짐이 달라졌다." % _topic(actor_name)

func _decision_event_message(event, actor_name: String, target_name: String) -> String:
	var reaction_id := str(event.data.get("reaction_id", ""))
	var retained := bool(event.data.get("retained", false))
	var switch_evidence: Dictionary = event.data.get("switch_evidence", {}) \
		if event.data.get("switch_evidence", {}) is Dictionary else {}
	var previous_reaction := str(switch_evidence.get("previous_reaction", "NONE"))
	var returned_from_danger: bool = previous_reaction in ["FLEE", "TAKE_COVER", "FREEZE"]
	match reaction_id:
		"ENGAGE":
			var opponent := target_name if event.target_id > 0 else "적"
			if retained:
				return "%s 계속 %s에게 맞서기로 했다." % [_subject(actor_name), opponent]
			if returned_from_danger:
				return "%s 용기를 내어 다시 %s에게 맞서기로 했다." % [_subject(actor_name), opponent]
			return "%s %s에게 맞서기로 했다." % [_subject(actor_name), opponent]
		"PROTECT":
			var ally := _object(target_name) if event.target_id > 0 else "동료를"
			if retained:
				return "%s 계속 %s 지키기로 했다." % [_subject(actor_name), ally]
			if returned_from_danger:
				return "%s 용기를 내어 %s 지키러 나섰다." % [_subject(actor_name), ally]
			return "%s %s 지키러 나섰다." % [_subject(actor_name), ally]
		"FLEE":
			return "%s %s위험을 피해 물러나기로 했다." % [
				_subject(actor_name), "계속 " if retained else ""]
		"TAKE_COVER":
			return "%s %s몸을 숨길 곳을 찾기로 했다." % [
				_subject(actor_name), "계속 " if retained else ""]
		"HOLD":
			return "%s %s자리를 지키며 버티기로 했다." % [
				_subject(actor_name), "계속 " if retained else ""]
		"FREEZE":
			return "%s %s두려움에 사로잡혀 움직이지 못했다." % [
				_subject(actor_name), "여전히 " if retained else ""]
		_:
			return "%s 상황을 지켜보기로 했다." % _subject(actor_name)

func _subject(value: String) -> String:
	return value + ("이" if _has_final_consonant(value) else "가")

func _object(value: String) -> String:
	return value + ("을" if _has_final_consonant(value) else "를")

func _topic(value: String) -> String:
	return value + ("은" if _has_final_consonant(value) else "는")

func _has_final_consonant(value: String) -> bool:
	for index in range(value.length() - 1, -1, -1):
		var code := value.unicode_at(index)
		if code in [9, 10, 13, 32]: continue
		if code >= 0xAC00 and code <= 0xD7A3:
			return (code - 0xAC00) % 28 != 0
		if code >= 48 and code <= 57:
			return str(code - 48) in ["0", "1", "3", "6", "7", "8"]
		return false
	return false

func _event_entity_name(entity_id: int) -> String:
	if entity_id <= 0: return "-"
	if sim != null and sim.world.entities.has(entity_id):
		var state = sim.world.agent_states.get(entity_id)
		if state != null and state.trial_slot >= 0:
			var role_label := str({"LEAD": "주인공", "PASSIVE_ALLY": "동료",
				"MELEE_THREAT": "고블린"}.get(state.controller_kind, ""))
			if not role_label.is_empty(): return "%s %d" % [role_label, state.trial_slot + 1]
		return str(sim.world.entities[entity_id].display_name)
	return "#%d" % entity_id

func _phase_label(phase_id: String) -> String:
	return str({"ARMED": "조우 대기", "ACTIVE": "전투 진행", "RESOLVED": "결과 확정",
		"COMPLETE": "실험 종료"}.get(phase_id, phase_id))

func _latest_salient_event(start_index: int) -> Dictionary:
	var selected = null
	var selected_priority := -1
	for event_index in range(start_index, sim.world.events.size()):
		var event = sim.world.events[event_index]
		var priority := _salient_event_priority(event)
		if priority >= selected_priority:
			selected = event
			selected_priority = priority
	if selected == null: return {}
	return {"event_id": selected.id, "world_time": selected.world_time, "type": selected.type,
		"message": _event_log_message(selected)}

func _salient_event_priority(event) -> int:
	var event_type := str(event.type)
	if event_type == "ai.decision_selected":
		return int({"PROTECT": 85, "FREEZE": 85, "ENGAGE": 84, "FLEE": 84,
			"TAKE_COVER": 83, "HOLD": 82}.get(str(event.data.get("reaction_id", "")), 81))
	return int({"entity.died": 100, "encounter.actor_escaped": 95,
		"combat.physical_damage": 90, "ai.mental_mode_changed": 86,
		"action.melee_attack": 80, "encounter.threat_appeared": 75, "action.freeze": 68,
		"action.move": 60, "perception.threat_noticed": 55,
		"action.hold": 10, "action.wait": 0}.get(event_type, 20))

func _reaction_log_label(reaction_id: String) -> String:
	return str({"ENGAGE": "교전", "PROTECT": "보호", "FLEE": "후퇴", "TAKE_COVER": "엄폐",
		"HOLD": "대기", "FREEZE": "얼어붙기"}.get(reaction_id, reaction_id))

func observe_lab() -> Dictionary:
	if sim == null: return {}
	var cells: Array[Dictionary] = []
	for y in range(ARENA_HEIGHT):
		for x in range(ARENA_WIDTH):
			var position := Vector2i(x, y); var tile = sim.world.tile_at(position)
			var entities: Array[Dictionary] = []
			var ids: Array = sim.world.entities.keys(); ids.sort()
			for id in ids:
				var entity = sim.world.entities[id]; var state = sim.world.agent_states.get(id)
				if entity.position != position or not sim.world.occupies_tile(entity.id) or (state != null and state.encounter_status != "ACTIVE"): continue
				if state != null and state.controller_kind == "MELEE_THREAT" and sim.world.encounter_lab.phase == "ARMED": continue
				entities.append({"entity_id": id, "display_name": entity.display_name, "controller_kind": "" if state == null else state.controller_kind,
					"trial_slot": -1 if state == null else state.trial_slot, "glyph": _glyph(state), "health": entity.health,
					"current_reaction": "" if state == null else state.current_reaction})
			cells.append({"position": [x, y], "terrain_id": tile.terrain,
				"passable": bool(TerrainRegistryScript.definition(tile.terrain).passable), "entities": entities})
	return {"schema_version": 1, "sampled_step_index": sim.world.step_index,
		"sampled_world_time": sim.world.world_time, "phase": sim.world.encounter_lab.phase,
		"width": ARENA_WIDTH, "height": ARENA_HEIGHT, "cells": cells,
		"slots": _slot_summaries()}.duplicate(true)

func observe_window(_center: Vector2i = Vector2i(7, 7), _radius: int = 7) -> Dictionary: return observe_lab()
func view_visible_cells(_radius: int = 7) -> Array[Dictionary]: return observe_lab().get("cells", [])

func lead_roster() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if sim == null: return rows
	for id in _actor_ids("LEAD"):
		var entity = sim.world.entities[id]; var state = sim.world.agent_states[id]
		rows.append({"entity_id": id, "trial_slot": state.trial_slot, "name": entity.display_name,
			"position": [entity.position.x, entity.position.y], "health": entity.health, "max_health": entity.max_health,
			"alive": sim.world.occupies_tile(entity.id), "encounter_status": state.encounter_status,
			"personality": state.personality_profile.facet_rows.duplicate(true), "fear": state.fear, "anger": state.anger,
			"mental_mode": state.mental_mode, "reaction": state.current_reaction, "activity": state.current_activity})
	return rows.duplicate(true)

func inspect_reaction(entity_id: int) -> Dictionary:
	if sim == null or not sim.world.agent_states.has(entity_id): return {}
	var state = sim.world.agent_states[entity_id]; var entity = sim.world.entities[entity_id]
	if state.controller_kind != "LEAD": return {}
	var appraisal: Dictionary = sim.actor_coordinator.threat_appraisal(entity_id)
	var all_candidates: Array[Dictionary] = []
	for action_id in sim.actor_coordinator.DecisionRegistry.ACTION_IDS:
		var candidate: Dictionary
		if sim.actor_coordinator.DecisionRegistry.mode(state.mental_mode).candidate_action_ids.has(action_id):
			var found := false
			for row in sim.actor_coordinator.evaluate_candidates(entity_id):
				if row.reaction_id == action_id: candidate = row; found = true; break
			if not found: continue
		else:
			candidate = {"reaction_id": action_id, "legal": false, "rejection_reason": "MODE_GATE",
				"score": 0, "base_score": 0, "gates": [{"gate_id": "mode", "veto": true, "reason": "MODE_GATE"}],
				"considerations": []}
		all_candidates.append(_candidate_dto(candidate))
	var threat_relation: Dictionary = sim.relationships.effective_relation(entity_id, state.active_threat_id) if state.active_threat_id > 0 else {}
	var ally_id := -1
	for candidate_id in sim.world.agent_states:
		var candidate_state = sim.world.agent_states[candidate_id]
		if candidate_state.trial_slot == state.trial_slot and candidate_state.controller_kind == "PASSIVE_ALLY":
			ally_id = candidate_id; break
	var ally_relation: Dictionary = sim.relationships.effective_relation(entity_id, ally_id) if ally_id > 0 else {}
	var recent: Array[Dictionary] = []
	for event in sim.world.events:
		if event.actor_id == entity_id or event.target_id == entity_id or event.id == state.threat_notice_event_id:
			recent.append(event.to_dict())
	while recent.size() > 12: recent.pop_front()
	var last_trace: Dictionary = {}
	if state.last_decision_event_id > 0:
		var event = sim.world.event_by_id(state.last_decision_event_id)
		if event != null: last_trace = event.data.duplicate(true)
	return {"schema_version": 1, "identity": {"entity_id": entity.id, "name": entity.display_name,
			"trial_slot": state.trial_slot, "position": [entity.position.x, entity.position.y],
			"health": entity.health, "max_health": entity.max_health, "encounter_status": state.encounter_status},
		"personality": {"facet_rows": state.personality_profile.facet_rows.duplicate(true),
			"labels": _personality_labels(state.personality_profile)},
		"emotion": {"fear": state.fear, "anger": state.anger, "mental_mode": state.mental_mode,
			"emotion_updated_time": state.emotion_updated_time, "mental_mode_since": state.mental_mode_since},
		"appraisal": appraisal.duplicate(true), "threat_relation": threat_relation.duplicate(true),
		"ally_relation": ally_relation.duplicate(true),
		"candidates": all_candidates, "selected_reaction": state.current_reaction,
		"current_activity": state.current_activity, "target_entity_id": state.intent_target_entity_id,
		"target_position": [state.intent_target_position.x, state.intent_target_position.y],
		"busy_until": state.busy_until, "commitment_until": state.commitment_until,
		"action_history_rows": state.action_history_rows.duplicate(true),
		"last_decision_event_id": state.last_decision_event_id, "last_trace": last_trace,
		"recent_events": recent}.duplicate(true)

func inspect_entity(entity_id: int) -> Dictionary: return inspect_reaction(entity_id)

func select_lead(entity_id: int) -> bool:
	if sim == null or not sim.world.agent_states.has(entity_id) or sim.world.agent_states[entity_id].controller_kind != "LEAD": return false
	selected_lead_id = entity_id; return true

func advance_ticks(count: int = 1) -> Dictionary:
	if count not in [1, 10]: return {"ok": false, "reason": "unsupported_tick_count"}
	if sim == null: return {"ok": false, "reason": "session_not_initialized"}
	# WAIT is a lab clock command, not an action owned by one lead. Keeping the
	# canonical observer sentinel also lets the surviving chambers continue when
	# the first lead dies or escapes.
	var command = CommandScript.wait_for(count * 100, -1)
	var event_start: int = sim.world.events.size()
	var result = sim.step(command); _last_result = result; _last_step_event_start = event_start
	_status_reason = result.reason
	if result.accepted: command_journal.append(command.to_dict().duplicate(true))
	return {"ok": result.accepted, "reason": result.reason, "processed_step_index": result.processed_step_index,
		"start_time": result.start_time, "end_time": result.end_time, "timeline": result.timeline.duplicate(true),
		"phase": sim.world.encounter_lab.phase}.duplicate(true)

func advance_minutes(minutes: int) -> Dictionary:
	return advance_ticks(1 if minutes == 1 else 10) if minutes in [1, 10] else {"ok": false, "reason": "unsupported_tick_count"}

func save_slot() -> Dictionary:
	if sim == null: return {"ok": false, "reason": "session_not_initialized"}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null: return {"ok": false, "reason": "save_open_failed"}
	file.store_string(save_session_json())
	return {"ok": true, "reason": "ok", "path": SAVE_PATH}

func load_slot() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH): return {"ok": false, "reason": "save_missing"}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null: return {"ok": false, "reason": "load_open_failed"}
	return load_session_json(file.get_as_text())

func save_session_json() -> String:
	if sim == null: return ""
	return JSON.stringify({"session_format_version": SESSION_FORMAT_VERSION, "world_seed": str(world_seed),
		"personality_seed": str(personality_seed), "snapshot": sim.snapshot(),
		"command_journal": command_journal.duplicate(true)})

func load_session_json(encoded: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(encoded) != OK or not (parser.data is Dictionary): return {"ok": false, "reason": "invalid_session_json"}
	var data: Dictionary = parser.data
	if data.get("session_format_version") != SESSION_FORMAT_VERSION: return {"ok": false, "reason": "unsupported_session_version"}
	if not Int64CodecScript.is_canonical(data.get("world_seed")) or not Int64CodecScript.is_canonical(data.get("personality_seed")) \
			or not (data.get("snapshot") is Dictionary) or not (data.get("command_journal") is Array):
		return {"ok": false, "reason": "invalid_session_wire"}
	var restored = SimulatorScript.from_snapshot(data.snapshot)
	if restored == null or restored.world.width != ARENA_WIDTH or restored.world.height != ARENA_HEIGHT or restored.world.encounter_lab == null:
		return {"ok": false, "reason": "snapshot_restore_failed"}
	var checked_world_seed: int = Int64CodecScript.parse(data.world_seed, "world seed")
	var checked_personality_seed: int = Int64CodecScript.parse(data.personality_seed, "personality seed")
	if restored.world.seed != checked_world_seed or restored.world.encounter_lab.personality_seed != checked_personality_seed:
		return {"ok": false, "reason": "session_metadata_mismatch"}
	var replay = SimulatorScript.create(ARENA_WIDTH, ARENA_HEIGHT, checked_world_seed)
	if replay == null or not _bootstrap_lab(replay, checked_personality_seed): return {"ok": false, "reason": "journal_bootstrap_failed"}
	var canonical_journal: Array[Dictionary] = []
	for command_row in data.command_journal:
		var command = CommandScript.from_dict(command_row) if command_row is Dictionary else null
		if command == null or command.type != CommandScript.Type.WAIT or not replay.step(command).accepted:
			return {"ok": false, "reason": "journal_replay_rejected"}
		canonical_journal.append(command.to_dict().duplicate(true))
	if replay.snapshot() != restored.snapshot(): return {"ok": false, "reason": "journal_snapshot_mismatch"}
	sim = restored; world_seed = checked_world_seed; personality_seed = checked_personality_seed
	command_journal.clear()
	for command_row in canonical_journal: command_journal.append(command_row.duplicate(true))
	_status_reason = "loaded"; _last_result = null; _last_step_event_start = restored.world.events.size()
	var roster: Array[Dictionary] = lead_roster(); selected_lead_id = int(roster[0].entity_id) if not roster.is_empty() else -1
	return {"ok": true, "reason": "ok"}

func _bootstrap_lab(candidate, p_personality_seed: int) -> bool:
	for x in range(ARENA_WIDTH):
		for y in range(ARENA_HEIGHT):
			if x in [0, 7, 14] or y in [0, 7, 14]:
				if not candidate.world.bootstrap_set_terrain(Vector2i(x, y), "wall"): return false
	for slot in range(4):
		if not candidate.world.bootstrap_set_terrain(_semantic(slot, "pillar"), "wall"): return false
	candidate.world.encounter_lab = EncounterLabStateScript.new(p_personality_seed)
	candidate.world.species_relations.set_relation("human", "human", 45, 0, 0)
	candidate.world.species_relations.set_relation("human", "goblin", -25, 45, 55)
	candidate.world.species_relations.set_relation("goblin", "human", -30, 15, 70)
	for slot in range(4):
		var lead = candidate.world.add_lab_actor("LEAD", slot, _semantic(slot, "lead"), "Lead %d" % (slot + 1), "human", 100)
		var ally = candidate.world.add_lab_actor("PASSIVE_ALLY", slot, _semantic(slot, "ally"), "Ally %d" % (slot + 1), "human", 100)
		var threat = candidate.world.add_lab_actor("MELEE_THREAT", slot, _semantic(slot, "threat"), "Threat %d" % (slot + 1), "goblin", 90)
		if lead == null or ally == null or threat == null: return false
		candidate.world.agent_states[lead.id].personality_profile = PersonalityRegistry.generate(p_personality_seed, slot)
		candidate.world.agent_states[threat.id].intent_target_entity_id = ally.id
	return candidate.world.world_state_error().is_empty()

func _origin(slot: int) -> Vector2i: return Vector2i(1 if slot % 2 == 0 else 8, 1 if slot < 2 else 8)
func _semantic(slot: int, name: String) -> Vector2i:
	var local: Vector2i = {"threat": Vector2i(3,1), "pillar": Vector2i(2,2), "cover": Vector2i(1,3),
		"intercept": Vector2i(3,3), "lead": Vector2i(2,4), "ally": Vector2i(3,4), "retreat": Vector2i(1,5)}[name]
	return _origin(slot) + local

func _actor_ids(kind: String) -> Array:
	var ids: Array = []
	if sim == null: return ids
	for id in sim.world.agent_states:
		if sim.world.agent_states[id].controller_kind == kind: ids.append(id)
	ids.sort_custom(func(a, b): return sim.world.agent_states[a].trial_slot < sim.world.agent_states[b].trial_slot)
	return ids

func _actor_id_for_slot(kind: String, trial_slot: int) -> int:
	for entity_id in _actor_ids(kind):
		if sim.world.agent_states[entity_id].trial_slot == trial_slot: return entity_id
	return -1

func _glyph(state) -> String:
	if state == null: return ""
	if state.controller_kind == "LEAD": return str(state.trial_slot + 1)
	if state.controller_kind == "PASSIVE_ALLY": return "a"
	return "M"

func _slot_summaries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in lead_roster():
		rows.append({"trial_slot": row.trial_slot, "entity_id": row.entity_id, "fear": row.fear,
			"mental_mode": row.mental_mode, "reaction": row.reaction, "dominant_facets": _dominant(row.personality)})
	return rows

func _dominant(rows: Array) -> Array[String]:
	var sorted: Array = rows.duplicate(true); sorted.sort_custom(func(a: Dictionary, b: Dictionary):
		var ad: int = absi(int(a.base_value) - 500); var bd: int = absi(int(b.base_value) - 500)
		return ad > bd if ad != bd else str(a.facet_id) < str(b.facet_id))
	var result: Array[String] = []
	for row in sorted.slice(0, mini(2, sorted.size())): result.append(str(row.facet_id))
	return result

func _personality_labels(profile) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for facet in PersonalityRegistry.definitions():
		var value: int = profile.value(facet.facet_id)
		rows.append({"facet_id": facet.facet_id, "base_value": value,
			"label": facet.high_label if value >= facet.neutral_value else facet.low_label})
	return rows

func _candidate_dto(candidate: Dictionary) -> Dictionary:
	var target = candidate.get("target_position", Vector2i(-1, -1))
	return {"reaction_id": candidate.reaction_id, "legal": bool(candidate.legal),
		"rejection_reason": str(candidate.rejection_reason), "score": int(candidate.score),
		"base_score": int(candidate.base_score), "gates": candidate.gates.duplicate(true),
		"considerations": candidate.considerations.duplicate(true),
		"target_position": [target.x, target.y] if target is Vector2i else [-1, -1]}
