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
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const AffinityRegistryScript = preload("res://sim/species_hazard_affinity_registry.gd")
const ExplorationRouteScript = preload("res://playtest/party_exploration_route.gd")

const SESSION_FORMAT_VERSION := 2
const PRESENTATION_SCHEMA_VERSION := 1
const SAVE_PATH := "user://living_world_party_encounter_v2.json"
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
var _exploration_route = null

func _combatant_status_ids(entity_id: int) -> Array[String]:
	var result: Array[String] = []
	if sim == null or sim.world == null: return result
	var combatant = sim.world.combatant_states.get(entity_id)
	if combatant == null: return result
	for row in combatant.status_rows: result.append(str(row.status_id))
	result.sort()
	return result

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
	if _exploration_route == null: _exploration_route = ExplorationRouteScript.new(self)
	else: _exploration_route.clear()
	return true

func party_status() -> Dictionary:
	if sim == null or sim.world.party_encounter == null: return {"ok": false, "reason": "session_not_initialized"}
	var state = sim.world.party_encounter; var view_mode: String = {"GROUPED":"EXPLORATION", "GROUPED_COMPLETE":"EXPLORATION",
		"CONTACT":"ENCOUNTER_PREVIEW", "ENGAGED":"COMBAT", "REGROUP_READY":"REGROUP", "PARTY_DEFEATED":"COMBAT"}[state.safe_phase]
	var visible_enemy_ids: Array = []
	if state.safe_phase not in ["GROUPED", "GROUPED_COMPLETE"]:
		for enemy_id in state.enemy_ids:
			if sim.world.is_unresolved_enemy(enemy_id): visible_enemy_ids.append(enemy_id)
	var protagonist_position: Vector2i = sim.world.entities[state.protagonist_id].position
	return {"ok": true, "safe_phase": state.safe_phase, "view_mode": view_mode, "terminal": state.safe_phase == "PARTY_DEFEATED",
		"contact_kind": state.contact_kind, "formation_id": state.formation_id, "anchor": [state.group_anchor.x,state.group_anchor.y],
		"facing": [state.facing.x,state.facing.y], "step_index": sim.world.step_index, "world_time": sim.world.world_time,
		"protagonist_id": state.protagonist_id, "party_member_ids": state.party_member_ids.duplicate(),
		"visible_enemy_ids": visible_enemy_ids, "protagonist_position": [protagonist_position.x, protagonist_position.y],
			"snapshot_version": sim.world.SNAPSHOT_VERSION, "ruleset_version": sim.world.RULESET_VERSION,
			"session_format_version": SESSION_FORMAT_VERSION}.duplicate(true)


func presentation_state() -> Dictionary:
	if sim == null or sim.world.party_encounter == null:
		return {"schema_version": PRESENTATION_SCHEMA_VERSION, "phase_id": "UNINITIALIZED",
			"mode": "UNAVAILABLE", "terminal": false, "combat_style_active": false,
			"banner": {"visible": true, "key": "session_unavailable",
				"title": "세션을 준비할 수 없습니다.", "subtitle": "", "tone": "ERROR"},
			"grid_style": {"style_id": "DEFAULT", "tint_hex": "#ffffff",
				"border_hex": "#617183", "vignette": false}}.duplicate(true)
	var status := party_status()
	var phase_id := str(status.safe_phase)
	var mode := "EXPLORATION"
	var banner := {"visible": true, "key": "exploration", "title": "탐험",
		"subtitle": "파티가 한 무리로 이동합니다.", "tone": "CALM"}
	var grid_style := {"style_id": "EXPLORATION", "tint_hex": "#ffffff",
		"border_hex": "#617183", "vignette": false}
	match phase_id:
		"CONTACT":
			mode = "ENCOUNTER"
			banner = {"visible": true, "key": "encounter_contact", "title": "조우",
				"subtitle": "전투 대형을 선택하세요.", "tone": "WARNING"}
			grid_style = {"style_id": "ENCOUNTER", "tint_hex": "#fff2d6",
				"border_hex": "#e8b95c", "vignette": true}
		"ENGAGED":
			mode = "COMBAT"
			banner = {"visible": true, "key": "combat_active", "title": "전투 중",
				"subtitle": "파티 행동을 계획하고 한꺼번에 확정하세요.", "tone": "COMBAT"}
			grid_style = {"style_id": "COMBAT", "tint_hex": "#ffe4dc",
				"border_hex": "#ff776d", "vignette": true}
		"REGROUP_READY":
			mode = "REGROUP"
			banner = {"visible": true, "key": "combat_victory", "title": "승리",
				"subtitle": "파티가 자동으로 재집결합니다.", "tone": "VICTORY"}
			grid_style = {"style_id": "REGROUP", "tint_hex": "#e5fff0",
				"border_hex": "#62d98b", "vignette": false}
		"GROUPED_COMPLETE":
			mode = "EXPLORATION"
			banner = {"visible": true, "key": "combat_victory_complete", "title": "승리 · 자동 재집결",
				"subtitle": "탐험 재개", "tone": "VICTORY"}
			grid_style = {"style_id": "VICTORY", "tint_hex": "#e5fff0",
				"border_hex": "#62d98b", "vignette": true}
		"PARTY_DEFEATED":
			mode = "DEFEAT"
			banner = {"visible": true, "key": "party_defeated", "title": "패배",
				"subtitle": "주인공이 쓰러져 더 행동할 수 없습니다.", "tone": "DEFEAT"}
			grid_style = {"style_id": "DEFEAT", "tint_hex": "#d5c6cf",
				"border_hex": "#8f5367", "vignette": true}
	return {"schema_version": PRESENTATION_SCHEMA_VERSION, "phase_id": phase_id,
		"mode": mode, "terminal": bool(status.terminal),
		"combat_style_active": phase_id in ["ENGAGED", "PARTY_DEFEATED"],
		"banner": banner, "grid_style": grid_style}.duplicate(true)

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
		if member.presence in ["DEPLOYED", "GROUPED"] and sim.world.is_environment_exposed(member_id):
			var evaluated = sim.evaluate_exposure_for_entity(member_id, logical); var wire: Dictionary = evaluated.evaluation.to_dict()
			exposure = {"applicable": true, "sampled_step_index": int(wire.sampled_step_index), "sampled_world_time": int(wire.sampled_world_time),
				"position": wire.position, "fire_score": wire.fire_score, "water_score": wire.water_score, "electric_score": wire.electric_score,
				"poison_score": wire.poison_score, "total_risk": wire.total_risk}
		var expected_action = _action_presentation(preview_by_actor.get(member_id, null))
		var readiness := "행동 준비" if member.busy_until <= sim.world.world_time else "행동 중"
		var emotion := _emotion_presentation(member, entity)
		var override_state := "PENDING"
		if expected_action != null: override_state = str(expected_action.source)
		elif member.role == "PROTAGONIST": override_state = "DIRECT"
		rows.append({"entity_id": member_id, "roster_slot": member.roster_slot, "role": member.role,
			"display_name": entity.display_name, "health": entity.health, "max_health": entity.max_health, "alive": sim.world.occupies_tile(member_id),
			"status_ids": _combatant_status_ids(member_id), "presence": member.presence, "logical_position": [logical.x,logical.y],
			"element_exposure": exposure, "stress": member.stress, "readiness": readiness,
			"emotion": emotion, "override_state": override_state,
			"expected_action": expected_action})
	return rows.duplicate(true)

func available_companion_ids() -> Array:
	var ids: Array = []
	if sim == null or sim.world.party_encounter == null: return ids
	var state = sim.world.party_encounter
	for member_id in state.party_member_ids:
		if member_id != state.protagonist_id and sim.world.is_autonomous_target(member_id): ids.append(member_id)
	return ids.duplicate()

func deployment_draft() -> Dictionary:
	if _deployment_plan.is_empty():
		return _feedback_dto({"has_preview": false, "accepted": false,
			"reason": "deployment_preview_required", "preset_id": "NONE",
			"companion_ids": [], "placements": []}, null, null, {"action_type": "DEPLOY"})
	return _feedback_dto({"has_preview": true, "accepted": bool(_deployment_plan.get("accepted", false)),
		"reason": str(_deployment_plan.get("reason", "invalid_deployment_plan")),
		"preset_id": str(_deployment_plan.get("preset_id", "NONE")),
		"companion_ids": _deployment_plan.get("companion_ids", []).duplicate(true),
		"placements": _deployment_plan.get("placements", []).duplicate(true)}, null, null,
		{"action_type": "DEPLOY"})

func enemy_targets() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var status := party_status()
	for enemy_id in status.get("visible_enemy_ids", []):
		var entity = sim.world.entities[int(enemy_id)]
		rows.append({"entity_id": entity.id, "display_name": entity.display_name, "health": entity.health,
			"max_health": entity.max_health, "alive": sim.world.is_unresolved_enemy(enemy_id), "position": [entity.position.x, entity.position.y]})
	return rows.duplicate(true)

func commit_exploration_direction(direction: Vector2i) -> Dictionary:
	if direction not in [Vector2i.ZERO, Vector2i.UP, Vector2i(1,-1), Vector2i.RIGHT, Vector2i(1,1),
			Vector2i.DOWN, Vector2i(-1,1), Vector2i.LEFT, Vector2i(-1,-1)]:
		return _rejection_dto("invalid_exploration_direction", null, null,
			{"action_type": "MOVE", "direction": [direction.x, direction.y]})
	var status := party_status()
	if not bool(status.get("ok", false)): return _rejection_dto(str(status.get("reason", "session_not_initialized")))
	var hero_id := int(status.protagonist_id)
	var command = CommandScript.wait(hero_id) if direction == Vector2i.ZERO else CommandScript.move_to(
		hero_id, Vector2i(int(status.protagonist_position[0]), int(status.protagonist_position[1])) + direction)
	return commit_exploration(command)

func set_actor_action(actor_id: int, action_type: String, destination: Array = [], target_id: int = -1) -> Dictionary:
	if sim == null or sim.world.party_encounter == null: return _rejection_dto("session_not_initialized")
	var action = _make_action(actor_id, action_type, destination, target_id)
	if action == null:
		return _rejection_dto("invalid_party_destination" if action_type == "MOVE" else "invalid_party_action",
			null, null, {"actor_id": actor_id, "action_type": action_type,
				"destination": destination.duplicate(true), "target_id": target_id})
	var state = sim.world.party_encounter
	return begin_turn(action) if actor_id == state.protagonist_id else override_companion(actor_id, action)


func preview_actor_action(actor_id: int, action_type: String, destination: Array = [],
		target_id: int = -1) -> Dictionary:
	# UI hover/tap preview must not mutate the pending direct action or overrides.
	if sim == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized")
	var action = _make_action(actor_id, action_type, destination, target_id)
	if action == null:
		return _rejection_dto("invalid_party_destination" if action_type == "MOVE" else "invalid_party_action",
			null, null, {"actor_id": actor_id, "action_type": action_type,
				"destination": destination.duplicate(true), "target_id": target_id})
	var state = sim.world.party_encounter
	var direct = action if actor_id == state.protagonist_id else _protagonist_draft
	if direct == null:
		return _rejection_dto("turn_draft_required", action)
	var overrides: Array = []
	var ids: Array = _overrides.keys()
	if actor_id != state.protagonist_id and not ids.has(actor_id): ids.append(actor_id)
	ids.sort()
	for id in ids:
		overrides.append({"actor_id": id,
			"action": action if int(id) == actor_id else _overrides[id]})
	var request = RequestScript.new(direct, overrides)
	var preview: Dictionary = sim.preview_party_turn(request).to_dict().duplicate(true)
	return _feedback_dto(preview, action, request)


func turn_intent_overlays() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if _protagonist_draft == null: return rows
	for card in party_cards():
		if not card.expected_action is Dictionary: continue
		var action: Dictionary = card.expected_action
		rows.append({"actor_id": int(card.entity_id), "actor_name": str(card.display_name),
			"from_position": card.logical_position.duplicate(true), "source": str(action.source),
			"source_label": str(action.source_label), "source_color": str(action.source_color),
			"line_style": _overlay_line_style(str(action.source)),
			"marker_style": _overlay_marker_style(str(action.source)),
			"type": str(action.type), "type_label": str(action.type_label),
			"destination": action.destination.duplicate(true), "target_id": int(action.target_id),
			"target_position": action.target_position.duplicate(true), "reason": str(action.reason),
			"automatic_suggestion": _overlay_suggestion(action.get("automatic_suggestion", null),
				card.logical_position) if str(action.source) == "OVERRIDE" else null})
	return rows.duplicate(true)


func turn_summary_lines() -> Array[String]:
	var lines: Array[String] = []
	for row in turn_intent_overlays():
		var detail := str(row.type_label)
		if row.type == "MOVE": detail += " (%d,%d)" % [int(row.destination[0]), int(row.destination[1])]
		elif row.type == "MELEE": detail += " %s" % _name(int(row.target_id))
		var line := "%s · %s: %s" % [str(row.actor_name), str(row.source_label), detail]
		if row.automatic_suggestion is Dictionary:
			line += " / 원래 제안: %s" % _overlay_action_text(row.automatic_suggestion)
		line += " — %s" % str(row.reason)
		lines.append(line)
	return lines

func _overlay_suggestion(value: Variant, from_position: Array) -> Variant:
	if not value is Dictionary: return null
	var target_position := [-1,-1]
	var target_id := int(value.get("target_id",-1))
	if target_id > 0 and sim.world.entities.has(target_id):
		target_position = [sim.world.entities[target_id].position.x,sim.world.entities[target_id].position.y]
	return {"source":"SUGGESTED","source_label":"원래 자동 제안","source_color":"#75c8ff",
		"line_style":"DASHED_THIN","marker_style":"CIRCLE",
		"type":str(value.get("type","HOLD")),"type_label":str(value.get("type_label","대기")),
		"from_position":from_position.duplicate(true),"destination":value.get("destination",[-1,-1]).duplicate(true),
		"target_id":target_id,"target_name":str(value.get("target_name","")),
		"target_position":target_position}.duplicate(true)

func _overlay_action_text(action: Dictionary) -> String:
	if str(action.type)=="MOVE":return "이동 (%d,%d)"%[int(action.destination[0]),int(action.destination[1])]
	if str(action.type)=="MELEE":return "공격 %s"%str(action.get("target_name","적"))
	return "대기"

func _overlay_line_style(source: String) -> String:
	return {"OVERRIDE":"SOLID_THICK","DIRECT":"SOLID","SUGGESTED":"DASHED_THIN"}.get(source,"SOLID")

func _overlay_marker_style(source: String) -> String:
	return {"OVERRIDE":"SQUARE","DIRECT":"DIAMOND","SUGGESTED":"CIRCLE"}.get(source,"CIRCLE")

func preview_exploration(command) -> Dictionary:
	if party_status().view_mode != "EXPLORATION": return _rejection_dto("exploration_phase_required")
	if command == null or command.actor_id != sim.world.party_encounter.protagonist_id:
		return _rejection_dto("protagonist_command_required")
	var context := _exploration_context(command)
	if int(command.type) not in [int(CommandScript.Type.WAIT), int(CommandScript.Type.MOVE)]:
		return _rejection_dto("invalid_exploration_action", null, null, context)
	var preview = sim.preview(command)
	return _feedback_dto({"accepted": preview.accepted, "reason": preview.reason,
		"time_cost": preview.time_cost}, null, null, context)


func preview_exploration_route(goal: Variant) -> Dictionary:
	return _exploration_route.preview(goal)


func exploration_route_draft() -> Dictionary:
	return _exploration_route.draft()


func exploration_route_state() -> Dictionary:
	return _exploration_route.state()


func start_exploration_route(goal: Variant, plan_hash: String) -> Dictionary:
	return _exploration_route.start(goal, plan_hash)


func continue_exploration_route() -> Dictionary:
	return _exploration_route.continue_route()


func cancel_exploration_route() -> Dictionary:
	return _exploration_route.cancel()


func commit_exploration(command) -> Dictionary:
	_exploration_route.cancel_for_direct_command()
	return _commit_exploration_one(command, false)


func _commit_exploration_one(command, preserve_route: bool) -> Dictionary:
	var preview := preview_exploration(command)
	if not preview.accepted: return preview
	var result = sim.step(command)
	if result.accepted: command_journal.append({"kind":"exploration", "command":command.to_dict()})
	_clear_draft()
	if not preserve_route: _exploration_route.cancel_for_direct_command()
	return _result_dto(result, null, null, _exploration_context(command))

func preview_deployment(preset_id: String, companion_ids: Array) -> Dictionary:
	_deployment_plan = sim.preview_deployment(preset_id, companion_ids)
	var dto: Dictionary = deployment_draft()
	dto.erase("has_preview")
	return dto.duplicate(true)

func commit_deployment() -> Dictionary:
	_exploration_route.cancel_for_direct_command()
	if _deployment_plan.is_empty(): return _rejection_dto("deployment_preview_required")
	var request = {"preset_id": _deployment_plan.get("preset_id", ""), "companion_ids": _deployment_plan.get("companion_ids", []).duplicate()}
	var result = sim.deploy_party(_deployment_plan)
	if result.accepted:
		var wire_ids: Array = []; for companion_id in request.companion_ids: wire_ids.append(str(companion_id))
		command_journal.append({"kind":"deployment", "request":{"preset_id":str(request.preset_id), "companion_ids":wire_ids}})
		_deployment_plan.clear()
	return _result_dto(result)

func begin_turn(protagonist_action) -> Dictionary:
	_exploration_route.cancel_for_direct_command()
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
	if _protagonist_draft == null:
		return _rejection_dto("turn_draft_required", action, null, {"actor_id": entity_id})
	var copied_action = _canonical_action_copy(action)
	if copied_action == null or copied_action.actor_id != entity_id:
		return _rejection_dto("override_actor_mismatch", copied_action, null, {"actor_id": entity_id})
	var had_previous := _overrides.has(entity_id); var previous = _overrides.get(entity_id)
	_overrides[entity_id] = copied_action
	var candidate_request = _pending_turn_request()
	var preview := current_turn_preview()
	if not bool(preview.get("accepted", false)):
		preview = _feedback_dto(preview, copied_action, candidate_request)
		if had_previous: _overrides[entity_id] = previous
		else: _overrides.erase(entity_id)
	return preview

func clear_companion_override(entity_id: int) -> Dictionary:
	if _protagonist_draft == null:
		return _rejection_dto("turn_draft_required", null, null,
			{"actor_id": entity_id, "action_type": "CLEAR_OVERRIDE"})
	_overrides.erase(entity_id); return current_turn_preview()

func current_turn_preview() -> Dictionary:
	if _protagonist_draft == null: return _rejection_dto("turn_draft_required")
	if _draft_fingerprint != JSON.stringify(sim.snapshot()).sha256_text(): _clear_draft(); return _rejection_dto("stale_turn_draft")
	var request = _pending_turn_request()
	var preview: Dictionary = sim.preview_party_turn(request).to_dict().duplicate(true)
	return _feedback_dto(preview, _protagonist_draft, request)

func commit_turn() -> Dictionary:
	_exploration_route.cancel_for_direct_command()
	var preview := current_turn_preview()
	if not bool(preview.get("accepted",false)): return preview
	var request = RequestScript.from_dict(preview.canonical_request)
	var plan_data := preview.duplicate(true)
	for facade_key in ["message", "reason_code", "reason_details", "visual_effect_schema_version",
			"visual_effects"]:
		plan_data.erase(facade_key)
	var plan = load("res://sim/party_turn_plan.gd").new(plan_data); var result = sim.step_party_turn(plan)
	if result.accepted: command_journal.append({"kind":"party_turn", "request":preview.canonical_request.duplicate(true)})
	if result.accepted: _clear_draft()
	return _result_dto(result, null, request)


func inspect_tile(position_value: Variant, viewer_id: int = -1) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized", null, null,
			{"action_type":"INSPECT_TILE"})
	var parsed := _inspection_position(position_value)
	if not bool(parsed.get("ok", false)):
		return _rejection_dto("invalid_tile_position", null, null,
			{"action_type":"INSPECT_TILE"})
	var position: Vector2i = parsed.position
	if not sim.world.in_bounds(position):
		return _rejection_dto("inspect_tile_out_of_bounds", null, null,
			{"action_type":"INSPECT_TILE", "position":[position.x,position.y]})
	var resolved_viewer := viewer_id
	if resolved_viewer == -1:
		resolved_viewer = int(sim.world.party_encounter.protagonist_id)
	if not sim.world.entities.has(resolved_viewer):
		return _rejection_dto("inspect_viewer_not_found", null, null,
			{"action_type":"INSPECT_TILE", "position":[position.x,position.y],
				"viewer_id":resolved_viewer})
	var viewer = sim.world.entities[resolved_viewer]
	if not sim.world.can_act(resolved_viewer, sim.world.world_time):
		return _rejection_dto("inspect_viewer_dead", null, null,
			{"action_type":"INSPECT_TILE", "position":[position.x,position.y],
				"viewer_id":resolved_viewer})
	var assessment = sim.assess_destination(resolved_viewer, position)
	if assessment == null or assessment.sample == null \
			or assessment.affinity == null or assessment.evaluation == null:
		return _rejection_dto("tile_inspection_unavailable", null, null,
			{"action_type":"INSPECT_TILE", "position":[position.x,position.y],
				"viewer_id":resolved_viewer})
	var sample: Dictionary = assessment.sample.to_dict()
	var affinity: Dictionary = assessment.affinity.to_dict()
	var evaluation: Dictionary = assessment.evaluation.to_dict()
	var definition: Dictionary = TerrainRegistryScript.definition(str(sample.terrain_id))
	var occupants: Array = []
	for entity in sim.world.occupying_entities_at(position):
		var member = sim.world.party_member_state(entity.id)
		occupants.append({"entity_id":entity.id,"display_name":str(entity.display_name),
			"health":entity.health,"max_health":entity.max_health,"alive":sim.world.occupies_tile(entity.id),
			"kind":str(entity.kind),"species_id":str(entity.species_id),
			"faction_id":str(entity.faction_id),"tags":entity.tags.duplicate(),
			"role":str(member.role) if member != null else "",
			"presence":str(member.presence) if member != null else "",
			"roster_slot":int(member.roster_slot) if member != null else -1})
	var dto := {"schema_version":PRESENTATION_SCHEMA_VERSION,"accepted":true,"reason":"ok",
		"position":[position.x,position.y],"terrain_id":str(sample.terrain_id),
		"terrain_label":_terrain_label(str(sample.terrain_id)),
		"presentation_key":str(definition.get("presentation_key", "")),
		"passable":bool(sample.passable),"move_time_cost":int(sample.move_time_cost),
		"speed_tier":str(assessment.speed_tier),"occupants":occupants,
		"traversal":assessment.traversal.to_dict() if assessment.traversal != null else null,
		"sample":sample,"provenance":{"sampled_step_index":int(sample.sampled_step_index),
			"sampled_world_time":int(sample.sampled_world_time),
			"after_event_id":int(sample.after_event_id),
			"next_environment_time":int(sample.next_environment_time),
			"source_event_ids":_int_array(sample.source_event_ids),
			"fire_source_event_id":int(sample.fire_source_event_id),
			"wetness_source_event_id":int(sample.wetness_source_event_id)},
		"viewer":{"entity_id":resolved_viewer,"display_name":str(viewer.display_name),
			"species_id":str(viewer.species_id)},"affinity":affinity,
		"risk":{"species_id":str(evaluation.species_id),
			"fire":int(evaluation.fire_score),"water":int(evaluation.water_score),
			"electric":int(evaluation.electric_score),"poison":int(evaluation.poison_score),
			"total":int(evaluation.total_risk)}}
	return _feedback_dto(dto, null, null, {"action_type":"INSPECT_TILE",
		"position":[position.x,position.y],"viewer_id":resolved_viewer})


func inspect_party_member(entity_id: int) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized", null, null,
			{"action_type":"INSPECT_MEMBER","actor_id":entity_id})
	var state = sim.world.party_encounter
	var member = state.member(entity_id)
	if member == null or not sim.world.entities.has(entity_id):
		return _rejection_dto("party_member_not_found", null, null,
			{"action_type":"INSPECT_MEMBER","actor_id":entity_id})
	var entity = sim.world.entities[entity_id]
	var logical: Vector2i = entity.position if member.presence == "DEPLOYED" else (
		state.group_anchor if member.presence == "GROUPED" else Vector2i(-1,-1))
	var full_exposure := {"applicable":false,"position":[logical.x,logical.y],
		"sample":null,"affinity":null,"risk":null}
	var compact_exposure := {"applicable":false,"sampled_step_index":sim.world.step_index,
		"sampled_world_time":sim.world.world_time,"position":[-1,-1],"fire_score":0,
		"water_score":0,"electric_score":0,"poison_score":0,"total_risk":0}
	if member.presence in ["DEPLOYED","GROUPED"] and sim.world.is_environment_exposed(entity_id):
		var evaluated = sim.evaluate_exposure_for_entity(entity_id, logical)
		if evaluated != null:
			var sample_wire: Dictionary = evaluated.sample.to_dict()
			var affinity_wire: Dictionary = evaluated.affinity.to_dict()
			var risk_wire: Dictionary = evaluated.evaluation.to_dict()
			full_exposure = {"applicable":true,"position":[logical.x,logical.y],
				"sample":sample_wire,"affinity":affinity_wire,
				"risk":{"species_id":str(risk_wire.species_id),
					"fire":int(risk_wire.fire_score),"water":int(risk_wire.water_score),
					"electric":int(risk_wire.electric_score),"poison":int(risk_wire.poison_score),
					"total":int(risk_wire.total_risk)}}
			compact_exposure = {"applicable":true,"sampled_step_index":int(risk_wire.sampled_step_index),
				"sampled_world_time":int(risk_wire.sampled_world_time),"position":risk_wire.position,
				"fire_score":int(risk_wire.fire_score),"water_score":int(risk_wire.water_score),
				"electric_score":int(risk_wire.electric_score),"poison_score":int(risk_wire.poison_score),
				"total_risk":int(risk_wire.total_risk)}
	var expected_action: Variant = _pure_expected_action(entity_id)
	var readiness := "행동 준비" if member.busy_until <= sim.world.world_time else "행동 중"
	var emotion := _emotion_presentation(member, entity)
	var personality_profile = null
	var personality_facets: Array = []
	if member.personality_profile != null:
		personality_profile = member.personality_profile.to_dict()
		for row in member.personality_profile.facet_rows:
			var labels: Array = PersonalityRegistryScript.LABELS.get(str(row.facet_id), ["낮음","높음"])
			personality_facets.append({"facet_id":str(row.facet_id),"value":int(row.base_value),
				"low_label":str(labels[0]),"high_label":str(labels[1])})
	var relation_rows: Array = []
	var relation_ids: Array = state.party_member_ids.duplicate()
	relation_ids.sort_custom(func(a,b):
		var member_a=state.member(int(a));var member_b=state.member(int(b))
		return int(member_a.roster_slot)<int(member_b.roster_slot) \
			if int(member_a.roster_slot)!=int(member_b.roster_slot) else int(a)<int(b))
	for subject_id_value in relation_ids:
		var subject_id := int(subject_id_value)
		if subject_id == entity_id or not sim.world.entities.has(subject_id): continue
		var relation: Dictionary = sim.relationships.effective_relation(entity_id,subject_id)
		relation_rows.append({"subject_id":subject_id,
			"subject_name":str(sim.world.entities[subject_id].display_name),
			"subject_species_id":str(sim.world.entities[subject_id].species_id),
			"trust":int(relation.get("trust",0)),"fear":int(relation.get("fear",0)),
			"hostility":int(relation.get("hostility",0)),
			"gratitude":int(relation.get("gratitude",0)),
			"grievance":int(relation.get("grievance",0)),
			"disposition":str(relation.get("disposition","NEUTRAL")),
			"species_base":relation.get("species_base",{}).duplicate(true),
			"personal":relation.get("personal",{}).duplicate(true)})
	var override_state := "PENDING"
	if expected_action is Dictionary: override_state = str(expected_action.source)
	elif member.role == "PROTAGONIST": override_state = "DIRECT"
	var dto := {"schema_version":PRESENTATION_SCHEMA_VERSION,"accepted":true,"reason":"ok",
		"entity_id":entity_id,"roster_slot":int(member.roster_slot),"role":str(member.role),
		"display_name":str(entity.display_name),"health":int(entity.health),
		"max_health":int(entity.max_health),"alive":sim.world.occupies_tile(entity_id),
		"kind":str(entity.kind),"tags":entity.tags.duplicate(),"species_id":str(entity.species_id),
		"faction_id":str(entity.faction_id),"status_ids":_combatant_status_ids(entity_id),
		"presence":str(member.presence),"logical_position":[logical.x,logical.y],
		"busy_until":int(member.busy_until),
		"remaining_time":maxi(0,int(member.busy_until)-int(sim.world.world_time)),
		"stress":int(member.stress),"readiness":readiness,"emotion":emotion,
		"override_state":override_state,"expected_action":expected_action,
		"element_exposure":compact_exposure,"current_exposure":full_exposure,
		"personality_profile":personality_profile,"personality_available":personality_profile != null,
		"personality_facets":personality_facets,
		"personality_note":"주인공은 생성형 성격 프로필을 사용하지 않습니다." \
			if personality_profile == null else "결정론적 성격 프로필",
		"species_affinity":AffinityRegistryScript.affinity_for(entity.species_id).to_dict(),
		"relation_rows":relation_rows}
	return _feedback_dto(dto, null, null,
		{"action_type":"INSPECT_MEMBER","actor_id":entity_id})


func combat_log(turn_limit: int = 8, row_limit: int = 80) -> Dictionary:
	var checked_turn_limit := clampi(turn_limit,0,64)
	var checked_row_limit := clampi(row_limit,0,500)
	var selected_steps: Array = []
	if checked_turn_limit > 0 and checked_row_limit > 0:
		for index in range(sim.world.events.size()-1,-1,-1):
			var step_index := int(sim.world.events[index].step_index)
			if not selected_steps.has(step_index):
				selected_steps.append(step_index)
				if selected_steps.size() >= checked_turn_limit: break
	selected_steps.sort()
	var selected_events: Array = []
	for event in sim.world.events:
		if selected_steps.has(int(event.step_index)): selected_events.append(event)
	if selected_events.size() > checked_row_limit:
		selected_events = selected_events.slice(selected_events.size()-checked_row_limit)
	var groups_by_step: Dictionary = {}
	var ordered_steps: Array = []
	for event in selected_events:
		var step_index := int(event.step_index)
		if not groups_by_step.has(step_index):
			groups_by_step[step_index]={"step_index":step_index,"start_time":int(event.world_time),
				"end_time":int(event.world_time),"rows":[]}
			ordered_steps.append(step_index)
		var group: Dictionary = groups_by_step[step_index]
		group.end_time = int(event.world_time)
		group.rows.append(_combat_event_row(event))
		groups_by_step[step_index]=group
	var groups: Array = []
	for step_index in ordered_steps: groups.append(groups_by_step[step_index])
	return {"schema_version":PRESENTATION_SCHEMA_VERSION,"turn_limit":checked_turn_limit,
		"row_limit":checked_row_limit,"group_count":groups.size(),
		"row_count":selected_events.size(),"groups":groups}.duplicate(true)


func recent_event_log(limit: int = 24) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []; var start := maxi(0, sim.world.events.size()-clampi(limit,0,100))
	for index in range(start, sim.world.events.size()):
		var event = sim.world.events[index]
		rows.append({"event_id":event.id,"step_index":event.step_index,
			"world_time":event.world_time,"message":_event_message(event)})
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
		if not bool(replay_result.get("accepted",false)):return _rejection_dto("party_journal_replay_failed")
	if replay.sim.snapshot()!=restored.snapshot():return _rejection_dto("party_journal_snapshot_mismatch")
	sim = restored; world_seed = parsed_world_seed; personality_seed = parsed_personality_seed
	command_journal.clear()
	for row in decoded.journal: command_journal.append(row.duplicate(true))
	_deployment_plan.clear(); _clear_draft(); _exploration_route.clear()
	return _feedback_dto({"accepted":true,"reason":"ok"})

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
			_: return "unknown_party_journal_kind"
	return ""

func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))

func _canonical_action_copy(action: Variant):
	if action == null or not action is PartyActionCommand:
		return null
	return ActionScript.from_dict(action.to_dict())

func _make_action(actor_id: int, action_type: String, destination: Array, target_id: int):
	match action_type:
		"HOLD": return ActionScript.hold(actor_id)
		"MOVE":
			if destination.size() != 2 or not destination[0] is int or not destination[1] is int:
				return null
			return ActionScript.move_to(actor_id, Vector2i(int(destination[0]), int(destination[1])))
		"MELEE": return ActionScript.melee(actor_id, target_id)
	return null

func _clear_draft() -> void: _protagonist_draft = null; _overrides.clear(); _draft_fingerprint = ""


func _pending_turn_request():
	var rows: Array = []
	var ids: Array = _overrides.keys()
	ids.sort()
	for id in ids:
		rows.append({"actor_id":id,"action":_overrides[id]})
	return RequestScript.new(_protagonist_draft, rows)

func _result_dto(result, action: Variant = null, request: Variant = null,
		context: Dictionary = {}) -> Dictionary:
	var ids: Array = []
	for event in result.events:
		ids.append(event.id)
	var dto := {"accepted":result.accepted,"reason":result.reason,
		"consumes_time":result.consumes_time,"step_index":result.processed_step_index,
		"start_time":result.start_time,"end_time":result.end_time,"time_cost":result.time_cost,
		"event_ids":ids,"visual_effects":_visual_effects_from_result(result)}
	return _feedback_dto(dto, action, request, context)


func _rejection_dto(reason: String, action: Variant = null, request: Variant = null,
		context: Dictionary = {}) -> Dictionary:
	return _feedback_dto({"accepted": false, "reason": reason}, action, request, context)


func _feedback_dto(value: Dictionary, action: Variant = null, request: Variant = null,
		context: Dictionary = {}) -> Dictionary:
	var dto := value.duplicate(true)
	var reason := str(dto.get("reason", "invalid_party_action"))
	var details := _reason_details(reason, action, request, context)
	dto["reason"] = reason
	dto["reason_code"] = reason
	dto["reason_details"] = details
	dto["message"] = reason_message(reason, details)
	dto["visual_effect_schema_version"] = PRESENTATION_SCHEMA_VERSION
	if not dto.get("visual_effects") is Array:
		dto["visual_effects"] = []
	return dto.duplicate(true)


func _exploration_context(command) -> Dictionary:
	if command == null:
		return {}
	var action_type := "MOVE" if int(command.type) == int(CommandScript.Type.MOVE) else "HOLD"
	return {"actor_id": int(command.actor_id), "action_type": action_type,
		"destination": [command.position.x, command.position.y] if action_type == "MOVE" else [-1,-1]}


func _inspection_position(value: Variant) -> Dictionary:
	if value is Vector2i:
		return {"ok":true,"position":value}
	if value is Array and value.size() == 2 and value[0] is int and value[1] is int:
		return {"ok":true,"position":Vector2i(int(value[0]),int(value[1]))}
	return {"ok":false,"position":Vector2i(-1,-1)}


func _int_array(values: Array) -> Array:
	var result: Array = []
	for value in values: result.append(int(value))
	return result


func _terrain_label(terrain_id: String) -> String:
	return {"floor":"바닥","stone_floor":"돌바닥","wood_floor":"나무바닥",
		"metal":"금속 바닥","rubble":"잔해","shallow_water":"얕은 물",
		"wall":"벽"}.get(terrain_id,terrain_id)


func _pure_expected_action(entity_id: int) -> Variant:
	if _protagonist_draft == null \
			or _draft_fingerprint != JSON.stringify(sim.snapshot()).sha256_text():
		return null
	var preview: Dictionary = sim.preview_party_turn(_pending_turn_request()).to_dict().duplicate(true)
	for row in preview.get("actor_rows", []):
		if int(row.get("actor_id",-1)) == entity_id:
			return _action_presentation(row)
	return null


func _combat_event_row(event) -> Dictionary:
	var event_type := str(event.type)
	var damage_type := str(event.data.get("damage_type", ""))
	var cause_type := ""
	if int(event.cause_id) > 0:
		var cause = sim.world.event_by_id(int(event.cause_id))
		if cause != null: cause_type = str(cause.type)
	return {"event_id":int(event.id),"type":event_type,
		"step_index":int(event.step_index),"world_time":int(event.world_time),
		"actor_id":int(event.actor_id),"actor_name":_event_entity_name(int(event.actor_id)),
		"target_id":int(event.target_id),"target_name":_event_entity_name(int(event.target_id)),
		"instigator_id":int(event.instigator_id),
		"instigator_name":_event_entity_name(int(event.instigator_id)),
		"position":[event.position.x,event.position.y],"magnitude":int(event.magnitude),
		"damage_type":damage_type,"cause_id":int(event.cause_id),"cause_type":cause_type,
		"category":_event_category(event_type),"tone":_event_tone(event_type),
		"data":event.data.duplicate(true),"message":_event_message(event)}


func _event_entity_name(entity_id: int) -> String:
	return str(sim.world.entities[entity_id].display_name) \
		if entity_id > 0 and sim.world.entities.has(entity_id) else ""


func _event_category(event_type: String) -> String:
	if event_type == "entity.died": return "DEATH"
	if event_type.begins_with("combat."): return "DAMAGE"
	if event_type.begins_with("action.") or event_type == "party.override_committed": return "ACTION"
	if event_type.begins_with("encounter.") or event_type == "party.deployment_completed" \
			or event_type == "party.member_deployed": return "ENCOUNTER"
	if event_type.begins_with("party.victory") or event_type.begins_with("party.regroup") \
			or event_type == "party.member_regrouped": return "OUTCOME"
	if event_type.begins_with("environment."): return "ENVIRONMENT"
	return "WORLD"


func _event_tone(event_type: String) -> String:
	if event_type == "entity.died": return "DEFEAT"
	if event_type.begins_with("combat."): return "DANGER"
	if event_type == "party.victory" or event_type.begins_with("party.regroup") \
			or event_type == "party.member_regrouped": return "VICTORY"
	if event_type.begins_with("encounter."): return "WARNING"
	if event_type.begins_with("action."): return "ACTION"
	return "INFO"


func _reason_details(reason: String, action: Variant, request: Variant,
		context: Dictionary) -> Dictionary:
	if reason == "ok":
		return {}
	var details := context.duplicate(true)
	details["category"] = _reason_category(reason)
	if action is PartyActionCommand:
		details["actor_id"] = int(action.actor_id)
		details["action_type"] = str(action.type)
		details["destination"] = [action.destination.x, action.destination.y]
		details["target_id"] = int(action.target_id)
	var actor_id := int(details.get("actor_id", -1))
	if sim != null and sim.world != null and actor_id > 0:
		if sim.world.entities.has(actor_id):
			var entity = sim.world.entities[actor_id]
			details["actor_name"] = str(entity.display_name)
			details["alive"] = bool(sim.world.occupies_tile(entity.id))
			details["from_position"] = [entity.position.x, entity.position.y]
		var state = sim.world.party_encounter
		var member = state.member(actor_id) if state != null else null
		if member != null:
			details["presence"] = str(member.presence)
			details["busy_until"] = int(member.busy_until)
			details["remaining_time"] = maxi(0, int(member.busy_until) - int(sim.world.world_time))
			details["is_deployed"] = str(member.presence) == "DEPLOYED"
	var destination: Variant = details.get("destination", null)
	if str(details.get("action_type", "")) == "MOVE" and destination is Array \
			and destination.size() == 2 and actor_id > 0 and sim != null \
			and sim.world != null and sim.world.entities.has(actor_id):
		var assessment = sim.assess_move(actor_id, Vector2i(int(destination[0]), int(destination[1])))
		var assessment_dto: Dictionary = assessment.to_dict()
		details["movement_assessment"] = assessment_dto
		details["terrain_id"] = str(assessment_dto.terrain_id)
		details["blocking_entity_ids"] = assessment_dto.blocking_entity_ids.duplicate()
		var blocker_names: Array[String] = []
		for blocker_id in assessment_dto.blocking_entity_ids:
			blocker_names.append(_name(int(blocker_id)))
		details["blocking_entity_names"] = blocker_names
		details["sampled_world_time"] = int(assessment_dto.sampled_world_time)
	if reason == "destination_conflict":
		var conflict := _destination_conflict_details(request)
		for key in conflict:
			details[key] = conflict[key]
	return details.duplicate(true)


func _destination_conflict_details(request: Variant) -> Dictionary:
	if request == null or not request is PartyTurnRequest:
		return {}
	var direct_actions: Array = []
	if request.protagonist_action != null:
		direct_actions.append(request.protagonist_action)
	for row in request.overrides:
		if row is Dictionary and row.get("action") != null:
			direct_actions.append(row.action)
	var grouped: Dictionary = {}
	for action in direct_actions:
		if action == null or str(action.type) != "MOVE":
			continue
		var key := "%d:%d" % [action.destination.x, action.destination.y]
		if not grouped.has(key):
			grouped[key] = []
		grouped[key].append(action)
	var keys: Array = grouped.keys()
	keys.sort()
	for key in keys:
		var contenders: Array = grouped[key]
		if contenders.size() < 2:
			continue
		var ids: Array[int] = []
		var names: Array[String] = []
		for contender in contenders:
			ids.append(int(contender.actor_id))
		ids.sort()
		for id in ids:
			names.append(_name(id))
		var position := str(key).split(":")
		return {"conflict_destination": [int(position[0]), int(position[1])],
			"conflicting_actor_ids": ids, "conflicting_actor_names": names}
	return {}


func _reason_category(reason: String) -> String:
	if reason.begins_with("route_") or reason == "invalid_route_goal":
		return "ROUTE"
	if reason.begins_with("inspect_") or reason.ends_with("_inspection_unavailable") \
			or reason in ["invalid_tile_position","party_member_not_found"]:
		return "INSPECTION"
	if reason.begins_with("move_") or reason == "destination_conflict":
		return "MOVEMENT"
	if reason in ["turn_draft_required", "party_actor_busy", "party_actor_unavailable",
			"override_actor_not_deployed", "override_actor_mismatch", "melee_not_legal"]:
		return "PARTY_ACTION"
	if "deployment" in reason or reason in ["unknown_formation", "invalid_companion_ids",
			"too_many_deployed_party"]:
		return "DEPLOYMENT"
	if "overflow" in reason or reason == "schedule_budget_exceeded":
		return "CAPACITY"
	if "session" in reason or "journal" in reason or "snapshot" in reason:
		return "SESSION"
	return "REQUEST"


func _visual_effects_from_result(result) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if result == null or not bool(result.accepted):
		return rows
	var order := 0
	for event in result.events:
		var event_type := str(event.type)
		if event_type == "action.melee_attack":
			rows.append(_visual_effect_row(event, "SLASH", "slash", order,
				"physical", int(event.magnitude), ""))
			order += 1
		elif event_type.begins_with("combat.") and event_type.ends_with("_damage"):
			var damage_type := str(event.data.get("damage_type", "physical"))
			rows.append(_visual_effect_row(event, "HIT_FLASH", "hit_flash", order,
				damage_type, int(event.magnitude), ""))
			order += 1
			rows.append(_visual_effect_row(event, "FLOATING_AMOUNT", "floating_amount", order,
				damage_type, int(event.magnitude), "-%d" % int(event.magnitude)))
			order += 1
		elif event_type == "entity.died":
			var death_type := str(event.data.get("damage_type", "physical"))
			rows.append(_visual_effect_row(event, "DEATH", "death", order,
				death_type, 0, ""))
			order += 1
	return rows.duplicate(true)


func _visual_effect_row(event, kind: String, suffix: String, order: int,
		damage_type: String, magnitude: int, text: String) -> Dictionary:
	return {"effect_id":"%d:%s" % [int(event.id),suffix], "event_id":int(event.id),
		"order":order, "kind":kind, "source_event_type":str(event.type),
		"step_index":int(event.step_index), "world_time":int(event.world_time),
		"actor_id":int(event.actor_id), "target_id":int(event.target_id),
		"instigator_id":int(event.instigator_id), "cause_id":int(event.cause_id),
		"world_position":[event.position.x,event.position.y], "damage_type":damage_type,
		"magnitude":magnitude, "text":text}.duplicate(true)

func _action_presentation(row: Variant) -> Variant:
	if not row is Dictionary or not row.get("action") is Dictionary:
		return null
	var action: Dictionary = row.action
	var source := str(row.get("source", "SUGGESTED"))
	var source_label: String = {"DIRECT":"직접 예정", "OVERRIDE":"개별 덮어쓰기", "SUGGESTED":"자동 제안"}.get(source, "자동 제안")
	var source_color: String = {"DIRECT":"#ffd467", "OVERRIDE":"#ff9f68", "SUGGESTED":"#75c8ff"}.get(source, "#75c8ff")
	var action_type := str(action.get("type", "HOLD"))
	var target_id := Int64CodecScript.parse(action.get("target_id", "-1"), "presentation target")
	var destination: Array = action.get("destination", [-1,-1]).duplicate(true)
	var action_text := "대기"
	var target_name := ""
	var actor_id := int(row.get("actor_id", -1))
	var target_position := [-1, -1]
	var reason := "상황을 지켜봅니다."
	if action_type == "MOVE": action_text = "이동 (%d,%d)" % [int(destination[0]), int(destination[1])]
	elif action_type == "MELEE":
		target_name = _name(target_id)
		action_text = "%s 공격" % target_name
		target_position = [sim.world.entities[target_id].position.x, sim.world.entities[target_id].position.y] \
			if sim.world.entities.has(target_id) else [-1, -1]
	if action_type == "MOVE":
		reason = "목표에 접근할 길을 골랐습니다." if source == "SUGGESTED" else "선택한 칸으로 이동합니다."
	elif action_type == "MELEE":
		reason = "인접한 적을 공격할 수 있습니다."
	elif source == "SUGGESTED":
		reason = "위험과 거리를 보고 자리를 지킵니다."
	if source == "OVERRIDE": reason = "자동 제안 대신 개별 지시를 따릅니다."
	var resolution_note := str(row.get("resolution_note", ""))
	if resolution_note == "destination_conflict_suggested_hold":
		reason = "이동 경로가 충돌해 이번 턴에는 자리를 지킵니다."
	var automatic_suggestion = null
	if row.get("suggestion") is Dictionary:
		var suggested: Dictionary = row.suggestion
		var suggested_type := str(suggested.get("type", "HOLD"))
		var suggested_destination: Array = suggested.get("destination", [-1, -1]).duplicate(true)
		var suggested_target := Int64CodecScript.parse(suggested.get("target_id", "-1"), "suggestion target")
		automatic_suggestion = {"type": suggested_type,
			"type_label": {"HOLD":"대기", "MOVE":"이동", "MELEE":"공격"}.get(suggested_type, "대기"),
			"destination": suggested_destination, "target_id": suggested_target,
			"target_name": _name(suggested_target) if suggested_target > 0 else ""}
	if source != "OVERRIDE": automatic_suggestion = null
	return {"source": source, "source_label": source_label, "source_color": source_color,
		"type": action_type, "type_label": {"HOLD":"대기", "MOVE":"이동", "MELEE":"공격"}.get(action_type, "대기"),
		"actor_id": actor_id, "destination": destination, "target_id": target_id,
		"target_name": target_name, "target_position": target_position, "reason": reason,
		"text": "%s · %s" % [source_label, action_text], "overridden": bool(row.get("overridden", false)),
		"automatic_suggestion": automatic_suggestion,
		"resolution_note": resolution_note}.duplicate(true)

func _emotion_presentation(member, entity) -> Dictionary:
	var health_percent: int = int(entity.health * 100 / maxi(1, entity.max_health))
	var boldness := 500
	var composure := 500
	if member.personality_profile != null:
		boldness = member.personality_profile.value("boldness")
		composure = member.personality_profile.value("composure")
	var label := "침착"; var icon := "●"; var reason := "건강과 긴장이 안정적입니다."
	if health_percent <= 30 or member.stress >= 750:
		if boldness >= 600 and composure >= 450:
			label = "용기를 냄"; icon = "◆"; reason = "생존 위협 속에서 대담한 본성이 드러납니다."
		else:
			label = "겁먹음"; icon = "!"; reason = "낮은 체력과 높은 긴장으로 생존 본능이 앞섭니다."
	elif member.stress >= 350 or health_percent <= 60:
		label = "긴장"; icon = "▲"; reason = "위험이 커져 경계하고 있습니다."
	return {"icon":icon, "label":label, "reason":reason,
		"health_percent":health_percent}.duplicate(true)

func reason_message(reason: String, details: Dictionary = {}) -> String:
	if reason == "party_actor_busy":
		var remaining := int(details.get("remaining_time", 0))
		return "선택한 파티원은 아직 행동 중입니다. (%d 시간 남음)" % remaining \
			if remaining > 0 else "선택한 파티원은 아직 행동 중입니다."
	if reason == "party_actor_unavailable":
		if not bool(details.get("alive", true)) or str(details.get("presence", "")) == "DEFEATED":
			return "선택한 파티원은 쓰러져 행동할 수 없습니다."
		return "선택한 파티원은 지금 행동할 수 없습니다."
	var mapped: Dictionary = {
		"ok":"준비되었습니다.", "deployment_preview_required":"먼저 대형을 선택하세요.",
		"deployment_phase_required":"지금은 배치할 수 없습니다.", "unknown_formation":"알 수 없는 대형입니다.",
		"invalid_companion_ids":"동료 선택이 올바르지 않습니다.", "too_many_deployed_party":"한 전투에 배치할 수 있는 파티원 수를 넘었습니다.",
		"deployment_space_unavailable":"동료가 설 수 있는 빈 칸이 부족합니다.",
		"stale_deployment_plan":"세계가 바뀌었습니다. 대형을 다시 선택하세요.",
		"deployment_plan_mismatch":"변경되거나 손상된 배치 계획은 확정할 수 없습니다.",
		"turn_draft_required":"동료를 지시하려면 먼저 주인공 행동을 선택하세요.",
		"stale_turn_draft":"세계가 바뀌어 행동을 다시 지정해야 합니다.",
		"party_turn_phase_required":"지금은 파티 턴을 확정할 수 없습니다.",
		"protagonist_action_required":"주인공 행동이 필요합니다.",
		"override_actor_not_deployed":"이번 전투에 배치되지 않은 예비 동료입니다.",
		"override_actor_mismatch":"선택한 동료와 지시 대상이 다릅니다.",
		"duplicate_or_unsorted_override":"동료별 지시는 한 번씩만 지정할 수 있습니다.",
		"melee_not_legal":"인접한 살아 있는 적만 공격할 수 있습니다.",
		"move_requires_actor":"이동할 파티원을 먼저 선택하세요.",
		"actor_not_found":"선택한 파티원을 찾을 수 없습니다.",
		"actor_dead":"쓰러진 파티원은 이동할 수 없습니다.",
		"move_not_adjacent":"인접한 8방향 한 칸으로만 이동할 수 있습니다.",
		"move_out_of_bounds":"지도 밖으로 이동할 수 없습니다.",
		"move_destination_occupied":"다른 인물이 그 칸을 점유하고 있습니다.",
		"move_terrain_blocked":"벽 또는 통과할 수 없는 지형입니다.",
		"move_diagonal_flank_blocked":"벽 모서리를 가로질러 대각선으로 이동할 수 없습니다.",
		"move_diagonal_flank_occupied":"다른 인물이 막은 모서리를 가로질러 대각선으로 이동할 수 없습니다.",
		"destination_conflict":"두 개 이상의 직접 이동 지시가 같은 칸을 요구합니다.",
		"party_plan_mismatch":"변경되거나 손상된 파티 계획은 확정할 수 없습니다.",
		"stale_party_plan":"세계가 바뀌어 턴을 다시 계획해야 합니다.",
		"regroup_not_ready":"아직 재집결할 수 없습니다.",
		"protagonist_dead":"주인공이 쓰러져 재집결할 수 없습니다.",
		"exploration_phase_required":"지금은 탐험 이동을 할 수 없습니다.",
		"protagonist_command_required":"주인공만 탐험 이동을 지시할 수 있습니다.",
		"invalid_exploration_direction":"올바른 방향을 선택하세요.",
		"invalid_exploration_action":"탐험에서는 이동하거나 대기할 수 있습니다.",
		"invalid_route_goal":"목적지 좌표가 올바르지 않습니다.",
		"route_preview_required":"먼저 먼 목적지의 경로를 확인하세요.",
		"route_not_active":"진행 중인 장거리 이동이 없습니다.",
		"route_already_active":"이미 장거리 이동을 진행하고 있습니다.",
		"route_plan_mismatch":"변경되거나 손상된 경로 계획은 시작할 수 없습니다.",
		"route_stale":"세계가 바뀌어 장거리 이동을 멈췄습니다. 경로를 다시 확인하세요.",
		"route_exploration_phase_required":"전투나 조우 중에는 장거리 이동을 할 수 없습니다.",
		"route_goal_out_of_bounds":"지도 밖을 장거리 목적지로 선택할 수 없습니다.",
		"route_actor_dead":"주인공이 쓰러져 장거리 이동을 계속할 수 없습니다.",
		"route_already_at_goal":"이미 선택한 목적지에 있습니다.",
		"route_unavailable":"목적지까지 안전하게 이어지는 경로가 없습니다.",
		"route_destination_unavailable":"경로의 다음 칸을 확인할 수 없어 이동을 멈췄습니다.",
		"route_path_changed":"지형이나 장애물이 바뀌어 장거리 이동을 멈췄습니다.",
		"route_position_changed":"현재 위치가 계획과 달라 장거리 이동을 멈췄습니다.",
		"route_party_changed":"이동 중인 파티 구성이 바뀌어 장거리 이동을 멈췄습니다.",
		"route_hazard_increased":"미리 본 경로보다 위험이 커져 이동을 멈췄습니다.",
		"route_step_rejected":"다음 한 칸을 이동할 수 없어 장거리 이동을 멈췄습니다.",
		"route_contact":"적과 조우해 장거리 이동을 즉시 멈췄습니다.",
		"route_party_defeated":"파티가 쓰러져 장거리 이동을 즉시 멈췄습니다.",
		"route_completed":"목적지에 도착했습니다.",
		"route_cancelled":"장거리 이동을 취소했습니다.",
		"invalid_tile_position":"확인할 타일 좌표가 올바르지 않습니다.",
		"inspect_tile_out_of_bounds":"지도 밖의 타일은 확인할 수 없습니다.",
		"inspect_viewer_not_found":"타일 위험을 판단할 인물을 찾을 수 없습니다.",
		"inspect_viewer_dead":"쓰러진 인물의 기준으로 타일 위험을 판단할 수 없습니다.",
		"tile_inspection_unavailable":"현재 타일 정보를 확인할 수 없습니다.",
		"party_member_not_found":"선택한 파티원의 상세 정보를 찾을 수 없습니다.",
		"invalid_party_action":"지원하지 않는 행동입니다.",
		"invalid_party_destination":"이동 위치가 올바르지 않습니다.",
		"melee_target_required":"공격할 적을 선택하세요.",
		"move_destination_required":"이동할 칸을 선택하세요.",
		"party_target_forbidden":"이 행동에는 공격 대상을 지정할 수 없습니다.",
		"party_destination_forbidden":"이 행동에는 이동 칸을 지정할 수 없습니다.",
		"party_turn_failed":"파티 턴이 취소되어 이전 상태로 돌아갔습니다.",
		"actor_tick_failed":"세계 처리에 실패해 이전 상태로 돌아갔습니다.",
		"party_schedule_mismatch":"세계 처리 순서가 바뀌어 파티 턴을 취소했습니다.",
		"party_turn_semantic_failure":"파티 턴을 안전하게 완료하지 못해 이전 상태로 돌아갔습니다.",
		"party_snapshot_unavailable":"안전한 복원 지점을 만들 수 없어 행동을 취소했습니다.",
		"schedule_budget_exceeded":"한 번에 처리할 세계 변화가 너무 많습니다. 더 짧은 행동을 선택하세요.",
		"step_index_overflow":"더 이상 턴 기록을 추가할 수 없습니다.",
		"time_overflow":"더 이상 세계 시간을 진행할 수 없습니다.",
		"event_id_overflow":"더 이상 사건 기록을 추가할 수 없습니다.",
		"party_journal_replay_failed":"저장 기록을 재생할 수 없습니다.",
		"party_journal_snapshot_mismatch":"저장 기록과 스냅샷이 일치하지 않습니다.",
		"invalid_party_session":"저장 데이터 형식이 올바르지 않습니다.",
		"invalid_party_session_wire":"저장 데이터가 정규 형식이 아닙니다.",
		"session_not_initialized":"세션이 준비되지 않았습니다."
	}
	if mapped.has(reason):
		return str(mapped[reason])
	if reason.begins_with("invalid_") or reason.begins_with("noncanonical_") \
			or reason.begins_with("duplicate_or_unsorted_") or reason.begins_with("unknown_"):
		return "요청 또는 저장 데이터 형식이 올바르지 않습니다."
	if reason.ends_with("_failed") or reason.ends_with("_failure"):
		return "처리에 실패해 이전 상태로 안전하게 돌아갔습니다."
	return "요청을 처리할 수 없습니다. 상태를 확인하고 다시 시도하세요."

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
		"party.override_committed": return "%s 지시한 행동으로 계획을 바꿨다." % _topic(actor)
		"party.victory": return "마지막 적이 쓰러졌다. 파티가 즉시 한곳으로 모이기 시작했다."
		"party.regroup_started": return "주인공이 동료들을 불러 모았다."
		"party.member_regrouped": return "%s 주인공 곁으로 돌아왔다." % _subject(actor)
		"party.regroup_completed": return "전투가 끝났다. 파티가 자동으로 재집결해 다시 한 무리로 탐험을 시작한다."
		"action.hold": return "%s 자리를 지켰다." % _subject(actor)
		"entity.died":
			if int(event.instigator_id) > 0:
				return "%s 공격으로 %s 쓰러졌다." % [
					_possessive(_name(event.instigator_id)),_subject(target)]
			return "환경 영향으로 %s 쓰러졌다." % _subject(target)
	if str(event.type).begins_with("combat.") and str(event.type).ends_with("_damage"):
		if int(event.instigator_id) > 0:
			return "%s 공격으로 %s %d 피해를 입었다." % [
				_possessive(_name(event.instigator_id)),_subject(target),int(event.magnitude)]
		var hazard_label: String = {"fire":"불길","electric":"감전","water":"물",
			"poison":"독","physical":"환경 충격"}.get(str(event.data.get("damage_type","")),"환경 영향")
		return "%s 때문에 %s %d 피해를 입었다." % [hazard_label,_subject(target),int(event.magnitude)]
	return "세계에 변화가 일어났다."

func _name(entity_id: int) -> String: return str(sim.world.entities[entity_id].display_name) if entity_id > 0 and sim.world.entities.has(entity_id) else "대상"
func _subject(value:String)->String: return value + ("이" if _has_final(value) else "가")
func _object(value:String)->String: return value + ("을" if _has_final(value) else "를")
func _topic(value:String)->String: return value + ("은" if _has_final(value) else "는")
func _possessive(value:String)->String: return value + ("의")
func _has_final(value:String)->bool:
	if value.is_empty(): return false
	var code := value.unicode_at(value.length()-1); return code >= 0xAC00 and code <= 0xD7A3 and (code-0xAC00)%28 != 0
