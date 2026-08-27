class_name PartyPlaytestSession
extends RefCounted

const SimulatorScript = preload("res://sim/simulator.gd")
const CommandScript = preload("res://sim/sim_command.gd")
const PartyStateScript = preload("res://sim/party_encounter_state.gd")
const MemberScript = preload("res://sim/party_member_state.gd")
const ActionScript = preload("res://sim/party_action_command.gd")
const RequestScript = preload("res://sim/party_turn_request.gd")
const PersonalityRegistryScript = preload("res://sim/personality_definition_registry.gd")
const WorldStateScript = preload("res://sim/world_state.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")

const SESSION_FORMAT_VERSION := 1
const SAVE_PATH := "user://living_world_party_encounter_v1.json"
const DEFAULT_WORLD_SEED := 44
const DEFAULT_PERSONALITY_SEED := 20260828

var sim
var world_seed := DEFAULT_WORLD_SEED
var personality_seed := DEFAULT_PERSONALITY_SEED
var command_journal: Array[Dictionary] = []
var _deployment_plan: Dictionary = {}
var _protagonist_draft = null
var _overrides: Dictionary = {}
var _draft_fingerprint := ""

func _init(p_world_seed: int = DEFAULT_WORLD_SEED, p_personality_seed: int = DEFAULT_PERSONALITY_SEED) -> void:
	reset_party(p_world_seed, p_personality_seed)

func reset_party(p_world_seed: int, p_personality_seed: int) -> bool:
	var candidate = SimulatorScript.create(15, 15, p_world_seed)
	if candidate == null: return false
	var protagonist = candidate.world.add_entity("hero", "주인공", Vector2i(7,7), 120, ["party_member"], "human", "party")
	var narae = candidate.world.add_entity("companion", "나래", Vector2i(6,7), 95, ["party_member"], "human", "party")
	var miru = candidate.world.add_entity("companion", "미루", Vector2i(7,6), 105, ["party_member"], "goblin", "party")
	var enemy = candidate.world.add_entity("melee_enemy", "고블린", Vector2i(11,7), 60, ["party_enemy"], "goblin", "enemy")
	if protagonist == null or narae == null or miru == null or enemy == null: return false
	var state = PartyStateScript.new(); state.protagonist_id = protagonist.id
	state.party_member_ids.append_array([protagonist.id, narae.id, miru.id]); state.enemy_ids.append(enemy.id)
	state.group_anchor = protagonist.position; state.party_detection_radius = 4; state.enemy_detection_radius = 3
	state.member_rows[protagonist.id] = MemberScript.new(protagonist.id, 0, "PROTAGONIST", "DEPLOYED", null)
	state.member_rows[narae.id] = MemberScript.new(narae.id, 1, "COMPANION", "GROUPED", PersonalityRegistryScript.generate(p_personality_seed, 0))
	state.member_rows[miru.id] = MemberScript.new(miru.id, 2, "COMPANION", "GROUPED", PersonalityRegistryScript.generate(p_personality_seed, 1))
	state.enemy_busy_rows[enemy.id] = 0
	narae.position = state.group_anchor; miru.position = state.group_anchor
	candidate.world.party_encounter = state
	if not candidate.world.world_state_error().is_empty(): return false
	sim = candidate; world_seed = p_world_seed; personality_seed = p_personality_seed
	command_journal.clear(); _clear_draft(); _deployment_plan.clear()
	return true

func party_status() -> Dictionary:
	if sim == null or sim.world.party_encounter == null: return {"ok": false, "reason": "session_not_initialized"}
	var state = sim.world.party_encounter; var view_mode: String = {"GROUPED":"EXPLORATION", "GROUPED_COMPLETE":"EXPLORATION",
		"CONTACT":"ENCOUNTER_PREVIEW", "ENGAGED":"COMBAT", "REGROUP_READY":"REGROUP", "PARTY_DEFEATED":"COMBAT"}[state.safe_phase]
	var visible_enemy_ids: Array = []
	if state.safe_phase not in ["GROUPED", "GROUPED_COMPLETE"]:
		for enemy_id in state.enemy_ids:
			if sim.world.entities[enemy_id].is_alive(): visible_enemy_ids.append(enemy_id)
	var protagonist_position: Vector2i = sim.world.entities[state.protagonist_id].position
	return {"ok": true, "safe_phase": state.safe_phase, "view_mode": view_mode, "terminal": state.safe_phase == "PARTY_DEFEATED",
		"contact_kind": state.contact_kind, "formation_id": state.formation_id, "anchor": [state.group_anchor.x,state.group_anchor.y],
		"facing": [state.facing.x,state.facing.y], "step_index": sim.world.step_index, "world_time": sim.world.world_time,
		"protagonist_id": state.protagonist_id, "party_member_ids": state.party_member_ids.duplicate(),
		"visible_enemy_ids": visible_enemy_ids, "protagonist_position": [protagonist_position.x, protagonist_position.y],
		"snapshot_version": sim.world.SNAPSHOT_VERSION, "ruleset_version": sim.world.RULESET_VERSION,
		"session_format_version": SESSION_FORMAT_VERSION}.duplicate(true)

func observe_party_world() -> Dictionary:
	var status := party_status()
	var hide_enemies: bool = str(status.safe_phase) in ["GROUPED", "GROUPED_COMPLETE"]
	var cells: Array = []
	for y in range(sim.world.height):
		for x in range(sim.world.width):
			var position := Vector2i(x,y); var actors: Array = []
			for entity in sim.world.occupying_entities_at(position):
				var member = sim.world.party_member_state(entity.id)
				var is_enemy: bool = entity.id in sim.world.party_encounter.enemy_ids
				if is_enemy and hide_enemies: continue
				actors.append({"entity_id": entity.id, "display_name": entity.display_name, "health": entity.health,
					"is_protagonist": member != null and member.role == "PROTAGONIST", "roster_slot": member.roster_slot if member != null else 99,
					"faction_id": entity.faction_id, "presence": member.presence if member != null else "DEPLOYED",
					"is_enemy": is_enemy, "sprite_frame": 0 if member != null and member.role == "PROTAGONIST" else (4 if member != null else 5)})
			cells.append({"position": [x,y], "terrain_id": sim.world.tile_at(position).terrain, "actors": actors})
	return {"width": sim.world.width, "height": sim.world.height, "cells": cells,
		"phase": party_status(), "grid_mapping": {"origin": [0,0], "cell_count": 225}}.duplicate(true)

func party_cards() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []; var state = sim.world.party_encounter
	var preview: Dictionary = current_turn_preview() if _protagonist_draft != null else {}
	var preview_by_actor: Dictionary = {}
	for actor_row in preview.get("actor_rows", []): preview_by_actor[int(actor_row.actor_id)] = actor_row
	for member_id in state.party_member_ids:
		var member = state.member(member_id); var entity = sim.world.entities[member_id]
		var logical: Vector2i = entity.position if member.presence == "DEPLOYED" else (state.group_anchor if member.presence == "GROUPED" else Vector2i(-1,-1))
		var exposure := {"applicable": false, "sampled_step_index": sim.world.step_index, "sampled_world_time": sim.world.world_time,
			"position": [-1,-1], "fire_score": 0, "water_score": 0, "electric_score": 0, "poison_score": 0, "total_risk": 0}
		if member.presence in ["DEPLOYED", "GROUPED"] and entity.is_alive():
			var evaluated = sim.evaluate_exposure_for_entity(member_id, logical); var wire: Dictionary = evaluated.evaluation.to_dict()
			exposure = {"applicable": true, "sampled_step_index": int(wire.sampled_step_index), "sampled_world_time": int(wire.sampled_world_time),
				"position": wire.position, "fire_score": wire.fire_score, "water_score": wire.water_score, "electric_score": wire.electric_score,
				"poison_score": wire.poison_score, "total_risk": wire.total_risk}
		var expected_action = _action_presentation(preview_by_actor.get(member_id, null))
		var override_state := "PENDING"
		if expected_action != null: override_state = str(expected_action.source)
		elif member.role == "PROTAGONIST": override_state = "DIRECT"
		rows.append({"entity_id": member_id, "roster_slot": member.roster_slot, "role": member.role,
			"display_name": entity.display_name, "health": entity.health, "max_health": entity.max_health, "alive": entity.is_alive(),
			"status_ids": member.status_ids.duplicate(), "presence": member.presence, "logical_position": [logical.x,logical.y],
			"element_exposure": exposure, "stress": member.stress, "override_state": override_state,
			"expected_action": expected_action})
	return rows.duplicate(true)

func available_companion_ids() -> Array:
	var ids: Array = []
	if sim == null or sim.world.party_encounter == null: return ids
	var state = sim.world.party_encounter
	for member_id in state.party_member_ids:
		if member_id != state.protagonist_id and sim.world.entities[member_id].is_alive(): ids.append(member_id)
	return ids.duplicate()

func deployment_draft() -> Dictionary:
	if _deployment_plan.is_empty():
		return {"has_preview": false, "accepted": false, "reason": "deployment_preview_required",
			"message": reason_message("deployment_preview_required"), "preset_id": "NONE", "companion_ids": [], "placements": []}
	return {"has_preview": true, "accepted": bool(_deployment_plan.get("accepted", false)),
		"reason": str(_deployment_plan.get("reason", "invalid_deployment_plan")),
		"message": reason_message(str(_deployment_plan.get("reason", "invalid_deployment_plan"))),
		"preset_id": str(_deployment_plan.get("preset_id", "NONE")),
		"companion_ids": _deployment_plan.get("companion_ids", []).duplicate(true),
		"placements": _deployment_plan.get("placements", []).duplicate(true)}.duplicate(true)

func enemy_targets() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var status := party_status()
	for enemy_id in status.get("visible_enemy_ids", []):
		var entity = sim.world.entities[int(enemy_id)]
		rows.append({"entity_id": entity.id, "display_name": entity.display_name, "health": entity.health,
			"max_health": entity.max_health, "alive": entity.is_alive(), "position": [entity.position.x, entity.position.y]})
	return rows.duplicate(true)

func commit_exploration_direction(direction: Vector2i) -> Dictionary:
	if direction not in [Vector2i.ZERO, Vector2i.UP, Vector2i(1,-1), Vector2i.RIGHT, Vector2i(1,1),
			Vector2i.DOWN, Vector2i(-1,1), Vector2i.LEFT, Vector2i(-1,-1)]:
		return _rejection_dto("invalid_exploration_direction")
	var status := party_status()
	if not bool(status.get("ok", false)): return _rejection_dto(str(status.get("reason", "session_not_initialized")))
	var hero_id := int(status.protagonist_id)
	var command = CommandScript.wait(hero_id) if direction == Vector2i.ZERO else CommandScript.move_to(
		hero_id, Vector2i(int(status.protagonist_position[0]), int(status.protagonist_position[1])) + direction)
	return commit_exploration(command)

func set_actor_action(actor_id: int, action_type: String, destination: Array = [], target_id: int = -1) -> Dictionary:
	if sim == null or sim.world.party_encounter == null: return _rejection_dto("session_not_initialized")
	var action = null
	match action_type:
		"HOLD": action = ActionScript.hold(actor_id)
		"MOVE":
			if destination.size() != 2 or not destination[0] is int or not destination[1] is int:
				return _rejection_dto("invalid_party_destination")
			action = ActionScript.move_to(actor_id, Vector2i(int(destination[0]), int(destination[1])))
		"MELEE": action = ActionScript.melee(actor_id, target_id)
		_: return _rejection_dto("invalid_party_action")
	var state = sim.world.party_encounter
	return begin_turn(action) if actor_id == state.protagonist_id else override_companion(actor_id, action)

func preview_exploration(command) -> Dictionary:
	if party_status().view_mode != "EXPLORATION": return _rejection_dto("exploration_phase_required")
	if command == null or command.actor_id != sim.world.party_encounter.protagonist_id: return _rejection_dto("protagonist_command_required")
	if int(command.type) not in [int(CommandScript.Type.WAIT), int(CommandScript.Type.MOVE)]: return _rejection_dto("invalid_exploration_action")
	var preview = sim.preview(command)
	return {"accepted": preview.accepted, "reason": preview.reason, "message": reason_message(preview.reason),
		"time_cost": preview.time_cost}.duplicate(true)

func commit_exploration(command) -> Dictionary:
	var preview := preview_exploration(command)
	if not preview.accepted: return preview
	var result = sim.step(command)
	if result.accepted: command_journal.append({"kind":"exploration", "command":command.to_dict()})
	_clear_draft()
	return _result_dto(result)

func preview_deployment(preset_id: String, companion_ids: Array) -> Dictionary:
	_deployment_plan = sim.preview_deployment(preset_id, companion_ids)
	var dto: Dictionary = deployment_draft()
	dto.erase("has_preview")
	return dto.duplicate(true)

func commit_deployment() -> Dictionary:
	if _deployment_plan.is_empty(): return _rejection_dto("deployment_preview_required")
	var request = {"preset_id": _deployment_plan.get("preset_id", ""), "companion_ids": _deployment_plan.get("companion_ids", []).duplicate()}
	var result = sim.deploy_party(_deployment_plan)
	if result.accepted:
		var wire_ids: Array = []; for companion_id in request.companion_ids: wire_ids.append(str(companion_id))
		command_journal.append({"kind":"deployment", "request":{"preset_id":str(request.preset_id), "companion_ids":wire_ids}})
		_deployment_plan.clear()
	return _result_dto(result)

func begin_turn(protagonist_action) -> Dictionary:
	var copied_action = _canonical_action_copy(protagonist_action)
	if copied_action == null: return _rejection_dto("invalid_party_action")
	var previous_action = _protagonist_draft
	var previous_overrides := _overrides.duplicate()
	var previous_fingerprint := _draft_fingerprint
	_protagonist_draft = copied_action; _overrides.clear(); _draft_fingerprint = JSON.stringify(sim.snapshot()).sha256_text()
	var preview := current_turn_preview()
	if not bool(preview.get("accepted", false)):
		_protagonist_draft = previous_action; _overrides = previous_overrides; _draft_fingerprint = previous_fingerprint
	return preview

func override_companion(entity_id: int, action) -> Dictionary:
	if _protagonist_draft == null: return _rejection_dto("turn_draft_required")
	var copied_action = _canonical_action_copy(action)
	if copied_action == null or copied_action.actor_id != entity_id: return _rejection_dto("override_actor_mismatch")
	var had_previous := _overrides.has(entity_id); var previous = _overrides.get(entity_id)
	_overrides[entity_id] = copied_action
	var preview := current_turn_preview()
	if not bool(preview.get("accepted", false)):
		if had_previous: _overrides[entity_id] = previous
		else: _overrides.erase(entity_id)
	return preview

func clear_companion_override(entity_id: int) -> Dictionary:
	if _protagonist_draft == null: return _rejection_dto("turn_draft_required")
	_overrides.erase(entity_id); return current_turn_preview()

func current_turn_preview() -> Dictionary:
	if _protagonist_draft == null: return _rejection_dto("turn_draft_required")
	if _draft_fingerprint != JSON.stringify(sim.snapshot()).sha256_text(): _clear_draft(); return _rejection_dto("stale_turn_draft")
	var rows: Array = []; var ids: Array = _overrides.keys(); ids.sort()
	for id in ids: rows.append({"actor_id":id,"action":_overrides[id]})
	var preview: Dictionary = sim.preview_party_turn(RequestScript.new(_protagonist_draft, rows)).to_dict().duplicate(true)
	preview["message"] = reason_message(str(preview.get("reason", "invalid_party_plan")))
	return preview

func commit_turn() -> Dictionary:
	var preview := current_turn_preview()
	if not bool(preview.get("accepted",false)): return preview
	var plan_data := preview.duplicate(true); plan_data.erase("message")
	var plan = load("res://sim/party_turn_plan.gd").new(plan_data); var result = sim.step_party_turn(plan)
	if result.accepted: command_journal.append({"kind":"party_turn", "request":preview.canonical_request.duplicate(true)})
	if result.accepted: _clear_draft()
	return _result_dto(result)

func regroup() -> Dictionary:
	var result = sim.regroup_party()
	if result.accepted: command_journal.append({"kind":"regroup"})
	return _result_dto(result)

func recent_event_log(limit: int = 24) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []; var start := maxi(0, sim.world.events.size()-clampi(limit,0,100))
	for index in range(start, sim.world.events.size()):
		var event = sim.world.events[index]
		rows.append({"event_id":event.id,"step_index":event.step_index,"world_time":event.world_time,"message":_event_message(event)})
	return rows.duplicate(true)

func save_session_json() -> String:
	return JSON.stringify({"session_format_version":SESSION_FORMAT_VERSION,"world_seed":str(world_seed),"personality_seed":str(personality_seed),
		"snapshot":sim.snapshot(),"journal":command_journal.duplicate(true)})

func load_session_json(encoded: String) -> Dictionary:
	var decoded = JSON.parse_string(encoded)
	if not decoded is Dictionary:
		return _rejection_dto("invalid_party_session")
	var top_keys: Array = decoded.keys(); top_keys.sort()
	if top_keys != ["journal", "personality_seed", "session_format_version", "snapshot", "world_seed"] \
			or not _integer(decoded.get("session_format_version")) \
			or int(decoded.session_format_version) != SESSION_FORMAT_VERSION \
			or not decoded.get("snapshot") is Dictionary \
			or not Int64CodecScript.is_canonical(decoded.get("world_seed")) \
			or not Int64CodecScript.is_canonical(decoded.get("personality_seed")) \
			or not decoded.get("journal") is Array or decoded.journal.size() > 10000:
		return _rejection_dto("invalid_party_session_wire")
	var journal_error := _journal_wire_error(decoded.journal)
	if not journal_error.is_empty(): return _rejection_dto(journal_error)
	var restored = SimulatorScript.from_snapshot(decoded.snapshot)
	if restored == null or restored.world.party_encounter == null:
		var restore_reason := WorldStateScript.snapshot_restore_error(decoded.snapshot)
		return _rejection_dto(restore_reason if not restore_reason.is_empty() else "invalid_party_snapshot")
	var parsed_world_seed := Int64CodecScript.parse(decoded.world_seed,"world seed")
	var parsed_personality_seed := Int64CodecScript.parse(decoded.personality_seed,"personality seed")
	var replay = load("res://playtest/party_playtest_session.gd").new(parsed_world_seed, parsed_personality_seed)
	for row in decoded.journal:
		var replay_result:Dictionary={"accepted":false}
		match str(row.kind):
			"exploration":
				var command=CommandScript.from_dict(row.command)
				replay_result=replay.commit_exploration(command)
			"deployment":
				var request:Dictionary=row.request; var companion_ids: Array = []
				for value in request.companion_ids: companion_ids.append(Int64CodecScript.parse(value, "deployment companion"))
				replay.preview_deployment(str(request.preset_id), companion_ids); replay_result=replay.commit_deployment()
			"party_turn":
				var request:Dictionary=row.request; var direct=ActionScript.from_dict(request.protagonist_action)
				replay.begin_turn(direct)
				for override in request.overrides:
					var action=ActionScript.from_dict(override.action)
					replay.override_companion(Int64CodecScript.parse(override.actor_id,"override actor"),action)
				replay_result=replay.commit_turn()
			"regroup": replay_result=replay.regroup()
		if not bool(replay_result.get("accepted",false)):return _rejection_dto("party_journal_replay_failed")
	if replay.sim.snapshot()!=restored.snapshot():return _rejection_dto("party_journal_snapshot_mismatch")
	sim = restored; world_seed = parsed_world_seed; personality_seed = parsed_personality_seed
	command_journal.clear()
	for row in decoded.journal: command_journal.append(row.duplicate(true))
	_deployment_plan.clear(); _clear_draft()
	return {"accepted":true,"reason":"ok", "message":reason_message("ok")}

func _journal_wire_error(journal: Array) -> String:
	for row in journal:
		if not row is Dictionary: return "invalid_party_journal"
		var keys: Array = row.keys(); keys.sort()
		match str(row.get("kind", "")):
			"exploration":
				if keys != ["command", "kind"] or not row.get("command") is Dictionary: return "invalid_exploration_journal"
				var command_keys: Array = row.command.keys(); command_keys.sort()
				if command_keys != ["actor_id", "position", "power", "type", "wait_duration_time_units"] \
						or not CommandScript.command_wire_error(row.command).is_empty() \
						or int(row.command.type) not in [int(CommandScript.Type.WAIT), int(CommandScript.Type.MOVE)]:
					return "invalid_exploration_journal"
			"deployment":
				if keys != ["kind", "request"] or not row.get("request") is Dictionary: return "invalid_deployment_journal"
				var request_keys: Array = row.request.keys(); request_keys.sort()
				if request_keys != ["companion_ids", "preset_id"] or row.request.get("preset_id") not in ["WEDGE", "LINE", "COLUMN"] \
						or not row.request.get("companion_ids") is Array or row.request.companion_ids.size() > 2:
					return "invalid_deployment_journal"
				var previous_id := 0
				for value in row.request.companion_ids:
					if not Int64CodecScript.is_canonical(value): return "invalid_deployment_journal"
					var parsed := Int64CodecScript.parse(value, "deployment companion")
					if parsed <= previous_id: return "invalid_deployment_journal"
					previous_id = parsed
			"party_turn":
				if keys != ["kind", "request"]: return "invalid_party_turn_journal"
				var request_error := RequestScript.wire_error(row.get("request"))
				if not request_error.is_empty(): return request_error
			"regroup":
				if keys != ["kind"]: return "invalid_regroup_journal"
			_: return "unknown_party_journal_kind"
	return ""

func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))

func _canonical_action_copy(action: Variant):
	if action == null or not action is PartyActionCommand:
		return null
	return ActionScript.from_dict(action.to_dict())

func _clear_draft() -> void: _protagonist_draft = null; _overrides.clear(); _draft_fingerprint = ""

func _result_dto(result) -> Dictionary:
	var ids: Array = []; for event in result.events: ids.append(event.id)
	return {"accepted":result.accepted,"reason":result.reason,"message":reason_message(result.reason),"consumes_time":result.consumes_time,"step_index":result.processed_step_index,
		"start_time":result.start_time,"end_time":result.end_time,"time_cost":result.time_cost,"event_ids":ids}.duplicate(true)

func _rejection_dto(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "message": reason_message(reason)}

func _action_presentation(row: Variant) -> Variant:
	if not row is Dictionary or not row.get("action") is Dictionary:
		return null
	var action: Dictionary = row.action
	var source := str(row.get("source", "SUGGESTED"))
	var source_label: String = {"DIRECT":"직접", "OVERRIDE":"지정", "SUGGESTED":"자동"}.get(source, "자동")
	var source_color: String = {"DIRECT":"#ffd467", "OVERRIDE":"#ff9f68", "SUGGESTED":"#75c8ff"}.get(source, "#75c8ff")
	var action_type := str(action.get("type", "HOLD"))
	var target_id := Int64CodecScript.parse(action.get("target_id", "-1"), "presentation target")
	var destination: Array = action.get("destination", [-1,-1]).duplicate(true)
	var action_text := "대기"
	var target_name := ""
	if action_type == "MOVE": action_text = "이동 (%d,%d)" % [int(destination[0]), int(destination[1])]
	elif action_type == "MELEE":
		target_name = _name(target_id)
		action_text = "%s 공격" % target_name
	return {"source": source, "source_label": source_label, "source_color": source_color,
		"type": action_type, "type_label": {"HOLD":"대기", "MOVE":"이동", "MELEE":"공격"}.get(action_type, "대기"),
		"destination": destination, "target_id": target_id, "target_name": target_name,
		"text": "%s · %s" % [source_label, action_text], "overridden": bool(row.get("overridden", false)),
		"resolution_note": str(row.get("resolution_note", ""))}.duplicate(true)

func reason_message(reason: String) -> String:
	return {
		"ok":"준비되었습니다.", "deployment_preview_required":"먼저 대형을 선택하세요.",
		"deployment_phase_required":"지금은 배치할 수 없습니다.", "unknown_formation":"알 수 없는 대형입니다.",
		"invalid_companion_ids":"동료 선택이 올바르지 않습니다.", "deployment_space_unavailable":"동료가 설 자리가 부족합니다.",
		"stale_deployment_plan":"세계가 바뀌었습니다. 대형을 다시 선택하세요.", "deployment_plan_mismatch":"변조된 배치 계획은 확정할 수 없습니다.",
		"turn_draft_required":"주인공 행동을 먼저 지정하세요.", "stale_turn_draft":"세계가 바뀌어 행동을 다시 지정해야 합니다.",
		"party_turn_phase_required":"지금은 파티 턴을 확정할 수 없습니다.", "protagonist_action_required":"주인공 행동이 필요합니다.",
		"party_actor_unavailable":"선택한 파티원은 행동할 수 없습니다.", "party_actor_busy":"선택한 파티원은 아직 준비되지 않았습니다.",
		"melee_not_legal":"인접한 살아 있는 적만 공격할 수 있습니다.", "move_not_adjacent":"한 칸 이내로만 이동할 수 있습니다.",
		"move_destination_occupied":"그 칸은 이미 점유되어 있습니다.", "move_terrain_blocked":"그 지형으로 이동할 수 없습니다.",
		"destination_conflict":"두 직접 지시가 같은 칸을 요구합니다.", "party_plan_mismatch":"변조된 파티 계획은 확정할 수 없습니다.",
		"stale_party_plan":"세계가 바뀌어 턴을 다시 계획해야 합니다.", "regroup_not_ready":"아직 재집결할 수 없습니다.",
		"protagonist_dead":"주인공이 쓰러져 재집결할 수 없습니다.", "exploration_phase_required":"지금은 탐험 이동을 할 수 없습니다.",
		"protagonist_command_required":"주인공만 탐험 이동을 지시할 수 있습니다.", "invalid_exploration_direction":"올바른 방향을 선택하세요.",
		"invalid_exploration_action":"탐험에서는 이동하거나 대기할 수 있습니다.",
		"invalid_party_action":"지원하지 않는 행동입니다.", "invalid_party_destination":"이동 위치가 올바르지 않습니다.",
		"override_actor_mismatch":"선택한 동료와 지시 대상이 다릅니다.", "party_turn_failed":"파티 턴이 취소되어 이전 상태로 돌아갔습니다.",
		"actor_tick_failed":"세계 처리에 실패해 이전 상태로 돌아갔습니다.", "party_journal_replay_failed":"저장 기록을 재생할 수 없습니다.",
		"party_journal_snapshot_mismatch":"저장 기록과 스냅샷이 일치하지 않습니다.", "invalid_party_session":"저장 데이터 형식이 올바르지 않습니다.",
		"invalid_party_session_wire":"저장 데이터가 정규 형식이 아닙니다.", "session_not_initialized":"세션이 준비되지 않았습니다."
	}.get(reason, "행동을 처리할 수 없습니다: %s" % reason)

func _event_message(event) -> String:
	var actor := _name(event.actor_id); var target := _name(event.target_id)
	match event.type:
		"encounter.detected": return "고블린과 파티가 서로를 발견했다."
		"encounter.party_ambush": return "파티가 고블린보다 먼저 기척을 알아챘다."
		"encounter.enemy_ambush": return "고블린이 숨어 있던 곳에서 파티를 덮쳤다."
		"party.member_deployed": return "%s 대형에 자리를 잡았다." % _subject(actor)
		"party.deployment_completed": return "파티가 전투 대형을 갖췄다."
		"action.move": return "%s (%d,%d)로 움직였다." % [_subject(actor),event.position.x,event.position.y]
		"action.melee_attack": return "%s %s 공격했다." % [_subject(actor),_object(target)]
		"combat.physical_damage": return "%s %d의 피해를 입었다." % [_subject(target),event.magnitude]
		"party.override_committed": return "%s 지시한 행동으로 계획을 바꿨다." % _topic(actor)
		"party.victory": return "마지막 적이 쓰러졌다. 파티를 재집결할 수 있다."
		"party.regroup_started": return "주인공이 동료들을 불러 모았다."
		"party.member_regrouped": return "%s 주인공 곁으로 돌아왔다." % _subject(actor)
		"party.regroup_completed": return "파티가 다시 한 무리로 길을 나설 준비를 마쳤다."
		"action.hold": return "%s 자리를 지켰다." % _subject(actor)
		"entity.died": return "%s 쓰러졌다." % _subject(target)
	return "세계에 변화가 일어났다."

func _name(entity_id: int) -> String: return str(sim.world.entities[entity_id].display_name) if entity_id > 0 and sim.world.entities.has(entity_id) else "대상"
func _subject(value:String)->String: return value + ("이" if _has_final(value) else "가")
func _object(value:String)->String: return value + ("을" if _has_final(value) else "를")
func _topic(value:String)->String: return value + ("은" if _has_final(value) else "는")
func _has_final(value:String)->bool:
	if value.is_empty(): return false
	var code := value.unicode_at(value.length()-1); return code >= 0xAC00 and code <= 0xD7A3 and (code-0xAC00)%28 != 0
