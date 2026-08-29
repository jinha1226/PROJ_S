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
const VisualTestMapScript = preload("res://playtest/party_visual_test_map.gd")

const SESSION_FORMAT_VERSION := 3
const PRESENTATION_SCHEMA_VERSION := 1
const SAVE_PATH := "user://living_world_party_encounter_v3.json"
const DEFAULT_WORLD_SEED := 44
const DEFAULT_PERSONALITY_SEED := 20260828
const REGRESSION_SCENARIO_ID := "REGRESSION_V1"
const SHOWCASE_SCENARIO_ID := "SHOWCASE_V1"
const NEW_EXPEDITION_FACET_MIN := 100
const NEW_EXPEDITION_FACET_MAX := 899
const NEW_EXPEDITION_MIN_PROFILE_DISTANCE := 700
const NEW_EXPEDITION_SEED_LIMIT := 2147483646
const EXILE_WORLD_INTERVAL := 100
const EXILE_ENCOUNTER_STEP_DELAY := 5
const ACTIVE_PARTY_LIMIT := 3
const RESCUE_TIME_COST := 100
const RESCUE_AID_MAGNITUDE := 70
const RECRUITMENT_OFFER_TIME_COST := 100
const RECRUITMENT_RULESET_ID := "species-dominant-rescue-recruitment-v1"
const PERSONALITY_ARCHETYPES := [
	{"archetype_id":"BOLD_VANGUARD", "label":"대담한 선봉",
		"center":{"aggression":780,"altruism":420,"boldness":790,"composure":610}},
	{"archetype_id":"CALM_GUARDIAN", "label":"침착한 수호자",
		"center":{"aggression":360,"altruism":760,"boldness":540,"composure":800}},
	{"archetype_id":"QUICK_SCOUT", "label":"기민한 척후",
		"center":{"aggression":620,"altruism":400,"boldness":650,"composure":470}},
	{"archetype_id":"KIND_SUPPORT", "label":"다정한 지원가",
		"center":{"aggression":330,"altruism":820,"boldness":470,"composure":630}},
	{"archetype_id":"CAUTIOUS_SENTINEL", "label":"신중한 파수꾼",
		"center":{"aggression":280,"altruism":570,"boldness":290,"composure":810}},
	{"archetype_id":"FIERY_CHARGER", "label":"불같은 돌격수",
		"center":{"aggression":830,"altruism":350,"boldness":740,"composure":300}},
]

var sim
var world_seed := DEFAULT_WORLD_SEED
var personality_seed := DEFAULT_PERSONALITY_SEED
var scenario_id := REGRESSION_SCENARIO_ID
var command_journal: Array[Dictionary] = []
var _deployment_plan: Dictionary = {}
var _protagonist_draft = null
var _overrides: Dictionary = {}
var _draft_fingerprint := ""
var _exploration_route = null
var _protagonist_placeholder := false

func _combatant_status_ids(entity_id: int) -> Array[String]:
	var result: Array[String] = []
	if sim == null or sim.world == null: return result
	var combatant = sim.world.combatant_states.get(entity_id)
	if combatant == null: return result
	for row in combatant.status_rows: result.append(str(row.status_id))
	result.sort()
	return result

func _init(p_world_seed: int = DEFAULT_WORLD_SEED,
		p_personality_seed: int = DEFAULT_PERSONALITY_SEED,
		p_scenario_id: String = REGRESSION_SCENARIO_ID) -> void:
	reset_party(p_world_seed, p_personality_seed, p_scenario_id)


static func new_expedition_personality_seed(entropy_seed: int,
		avoid_seed: int = -1) -> int:
	# This function is deliberately pure. The UI supplies entropy once at the
	# new-expedition boundary; constructor, save/load, refresh and replay never
	# consult Time or an RNG. Existing explicit seeds remain byte-reproducible.
	var normalized := entropy_seed % NEW_EXPEDITION_SEED_LIMIT
	if normalized < 0: normalized += NEW_EXPEDITION_SEED_LIMIT
	for attempt in range(4096):
		var candidate := 1 + (normalized + attempt * 104729) % NEW_EXPEDITION_SEED_LIMIT
		if candidate == avoid_seed: continue
		if _new_expedition_seed_is_suitable(candidate): return candidate
	# The search space is intentionally generous; retain a deterministic fallback
	# rather than introducing a second nondeterministic draw if rules evolve.
	return 1 + (normalized + 4096 * 104729) % NEW_EXPEDITION_SEED_LIMIT


static func personality_archetype(profile) -> Dictionary:
	if profile == null: return {}
	var best: Dictionary = {}
	var best_distance := 9223372036854775807
	for archetype_value in PERSONALITY_ARCHETYPES:
		var archetype: Dictionary = archetype_value
		var center: Dictionary = archetype.center
		var distance := 0
		for facet_id in PersonalityRegistryScript.FACET_IDS:
			var delta := int(profile.value(facet_id)) - int(center[facet_id])
			distance += delta * delta
		if distance < best_distance:
			best_distance = distance; best = archetype
	return {"archetype_id":str(best.get("archetype_id","")),
		"label":str(best.get("label","")), "distance":best_distance}.duplicate(true)


static func _new_expedition_seed_is_suitable(candidate_seed: int) -> bool:
	var profiles: Array = [PersonalityRegistryScript.generate(candidate_seed,0),
		PersonalityRegistryScript.generate(candidate_seed,1)]
	var archetype_ids: Array[String] = []
	for profile in profiles:
		if profile == null: return false
		for facet_id in PersonalityRegistryScript.FACET_IDS:
			var value := int(profile.value(facet_id))
			if value < NEW_EXPEDITION_FACET_MIN or value > NEW_EXPEDITION_FACET_MAX:
				return false
		archetype_ids.append(str(personality_archetype(profile).get("archetype_id","")))
	if archetype_ids[0] == archetype_ids[1]: return false
	var distance := 0
	for facet_id in PersonalityRegistryScript.FACET_IDS:
		distance += absi(int(profiles[0].value(facet_id))-int(profiles[1].value(facet_id)))
	return distance >= NEW_EXPEDITION_MIN_PROFILE_DISTANCE

func reset_party(p_world_seed: int, p_personality_seed: int,
		p_scenario_id: String = REGRESSION_SCENARIO_ID) -> bool:
	if not VisualTestMapScript.has_scenario(p_scenario_id): return false
	var candidate = SimulatorScript.create(15, 15, p_world_seed)
	if candidate == null: return false
	var showcase := p_scenario_id == SHOWCASE_SCENARIO_ID
	if showcase and not VisualTestMapScript.apply_showcase_terrain(candidate.world): return false
	if showcase and not VisualTestMapScript.apply_showcase_hazards(candidate.world): return false
	var hero_position := VisualTestMapScript.HERO_POSITION if showcase else Vector2i(7,7)
	var narae_position := Vector2i(1,12) if showcase else Vector2i(6,7)
	var miru_position := Vector2i(2,11) if showcase else Vector2i(7,6)
	var enemy_position := VisualTestMapScript.ENEMY_POSITION if showcase else Vector2i(11,7)
	var protagonist = candidate.world.add_entity("hero", "주인공", hero_position, 120, ["party_member"], "human", "party")
	var narae = candidate.world.add_entity("companion", "나래", narae_position, 95, ["party_member"], "human", "party")
	var miru = candidate.world.add_entity("companion", "미루", miru_position, 105, ["party_member"], "goblin", "party")
	var candidate_dwarf = candidate.world.add_entity("companion", "보린", Vector2i(1,13), 110,
		["party_member", "recruitable"], "dwarf", "party") if showcase else null
	var candidate_amphibian = candidate.world.add_entity("companion", "세라", Vector2i(2,13), 90,
		["recruitable", "rescue_npc"], "amphibian", "neutral") if showcase else null
	var enemy = candidate.world.add_entity("melee_enemy", "고블린", enemy_position, 60, ["party_enemy"], "goblin", "enemy")
	if protagonist == null or narae == null or miru == null or enemy == null \
			or (showcase and (candidate_dwarf == null or candidate_amphibian == null)):
		return false
	_configure_party_species_relations(candidate)
	# The rescue story is authoritative event history, but it deliberately does
	# not impersonate combat DOWNED. The world NPC stays ACTIVE and occupies its
	# canonical cell until an accepted offer converts the same entity to GROUPED.
	if showcase and not _bootstrap_rescue_candidate(candidate,
			candidate_amphibian.id):
		return false
	var state = PartyStateScript.new(); state.protagonist_id = protagonist.id
	state.party_member_ids.append_array([protagonist.id, narae.id, miru.id])
	if showcase: state.party_member_ids.append(candidate_dwarf.id)
	state.enemy_ids.append(enemy.id)
	state.active_party_member_ids.clear()
	state.active_party_member_ids.append_array([protagonist.id, narae.id, miru.id])
	state.group_anchor = protagonist.position
	state.party_detection_radius = 3 if showcase else 4; state.enemy_detection_radius = 3
	state.member_rows[protagonist.id] = MemberScript.new(protagonist.id, 0, "PROTAGONIST", "DEPLOYED", null)
	state.member_rows[narae.id] = MemberScript.new(narae.id, 1, "COMPANION", "GROUPED", PersonalityRegistryScript.generate(p_personality_seed, 0))
	state.member_rows[miru.id] = MemberScript.new(miru.id, 2, "COMPANION", "GROUPED", PersonalityRegistryScript.generate(p_personality_seed, 1))
	if showcase:
		state.member_rows[candidate_dwarf.id] = MemberScript.new(candidate_dwarf.id, 3,
			"COMPANION", "RECRUITABLE", PersonalityRegistryScript.generate(p_personality_seed, 2))
	state.enemy_busy_rows[enemy.id] = 0
	narae.position = state.group_anchor; miru.position = state.group_anchor
	candidate.world.party_encounter = state
	if not candidate.world.world_state_error().is_empty(): return false
	sim = candidate; world_seed = p_world_seed; personality_seed = p_personality_seed
	scenario_id = p_scenario_id
	command_journal.clear(); _clear_draft(); _deployment_plan.clear()
	if _exploration_route == null: _exploration_route = ExplorationRouteScript.new(self)
	else: _exploration_route.clear()
	return true


func _configure_party_species_relations(candidate) -> void:
	# The candidate is the observer in a recruitment decision.  Personal aid is
	# deliberately bounded by RelationshipSystem, so these priors remain the
	# dominant baseline even after a dramatic rescue.
	candidate.world.species_relations.set_relation("human", "human", 35, 0, 0)
	candidate.world.species_relations.set_relation("dwarf", "human", 25, 5, 0)
	candidate.world.species_relations.set_relation("amphibian", "human", -30, 25, 45)
	candidate.world.species_relations.set_relation("goblin", "human", -60, 35, 75)


func _bootstrap_rescue_candidate(candidate, target_id: int) -> bool:
	if candidate == null or candidate.world == null \
			or not candidate.world.entities.has(target_id):
		return false
	var target = candidate.world.entities[target_id]
	target.health = maxi(1, int((target.max_health + 4) / 5))
	var rng_before: int = candidate.world.rng.state
	var discovered = candidate.world.emit_event("party.rescue_discovered", -1,
		target_id, target.position, 0, -1,
		{"schema_version":1, "state":"COLLAPSED_STORY", "non_hostile":true,
			"position":[target.position.x,target.position.y], "personality_slot":3})
	return discovered != null and candidate.world.rng.state == rng_before \
		and str(candidate.world.combatant_states[target_id].life_state) == "ACTIVE"

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
		"protagonist_id": state.protagonist_id, "party_member_ids": state.active_party_member_ids.duplicate(),
		"roster_member_ids": state.party_member_ids.duplicate(),
		"rescue_candidate_ids":rescue_candidate_ids(),
		"recruitable_member_ids":_member_ids_with_presence("RECRUITABLE"),
		"exiled_member_ids":_member_ids_with_presence("EXILED"),
		"visible_enemy_ids": visible_enemy_ids, "protagonist_position": [protagonist_position.x, protagonist_position.y],
			"snapshot_version": sim.world.SNAPSHOT_VERSION, "ruleset_version": sim.world.RULESET_VERSION,
			"session_format_version": SESSION_FORMAT_VERSION, "scenario_id": scenario_id}.duplicate(true)


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


func run_progress() -> Dictionary:
	var unavailable := {"schema_version":VisualTestMapScript.RUN_MANIFEST_SCHEMA_VERSION,
		"available":false, "scenario_id":scenario_id, "objective_id":"",
		"run_state":"UNAVAILABLE", "entry_position":[], "exit_position":[],
		"encounter_cleared":false,
		"reward":{"reward_id":"", "amount":0, "granted":false},
		"exit":{"feature_id":"", "open":false},
		"complete":false, "terminal":false}
	var manifest: Dictionary = VisualTestMapScript.run_manifest(scenario_id)
	if manifest.is_empty() or sim == null or sim.world == null \
			or sim.world.party_encounter == null:
		return unavailable.duplicate(true)
	var state = sim.world.party_encounter
	var hero = sim.world.entities.get(state.protagonist_id)
	if hero == null:
		return unavailable.duplicate(true)
	var encounter_cleared: bool = state.safe_phase in ["REGROUP_READY", "GROUPED_COMPLETE"]
	var exit_position := Vector2i(int(manifest.exit.position[0]),
		int(manifest.exit.position[1]))
	var complete: bool = state.safe_phase == "GROUPED_COMPLETE" \
		and hero.position == exit_position
	var terminal: bool = complete or state.safe_phase == "PARTY_DEFEATED"
	var run_state := "EXPLORE"
	if state.safe_phase == "PARTY_DEFEATED": run_state = "DEFEATED"
	elif complete: run_state = "COMPLETE"
	elif encounter_cleared: run_state = "EXIT_OPEN"
	elif state.safe_phase in ["CONTACT", "ENGAGED", "REGROUP_READY"]:
		run_state = "ENCOUNTER"
	return {"schema_version":int(manifest.schema_version), "available":true,
		"scenario_id":str(manifest.scenario_id),
		"objective_id":str(manifest.objective_id), "run_state":run_state,
		"entry_position":manifest.entry.position.duplicate(true),
		"exit_position":manifest.exit.position.duplicate(true),
		"encounter_cleared":encounter_cleared,
		"reward":{"reward_id":str(manifest.reward.reward_id),
			"amount":int(manifest.reward.amount) if encounter_cleared else 0,
			"granted":encounter_cleared},
		"exit":{"feature_id":str(manifest.exit.open_feature_id) if encounter_cleared \
			else str(manifest.exit.locked_feature_id), "open":encounter_cleared},
		"complete":complete, "terminal":terminal}.duplicate(true)


func restart_same_run() -> Dictionary:
	var progress := run_progress()
	if not bool(progress.available):
		return _rejection_dto("run_restart_unavailable")
	if str(progress.run_state) not in ["COMPLETE", "DEFEATED"]:
		return _rejection_dto("run_restart_not_ready")
	var frozen_world_seed := world_seed
	var frozen_personality_seed := personality_seed
	var frozen_scenario_id := scenario_id
	if not reset_party(frozen_world_seed, frozen_personality_seed,
			frozen_scenario_id):
		return _rejection_dto("run_restart_failed")
	return _feedback_dto({"accepted":true, "reason":"ok",
		"world_seed":str(world_seed), "personality_seed":str(personality_seed),
		"scenario_id":scenario_id, "run_progress":run_progress()})


func restart_with_personality_seed(p_personality_seed: int) -> Dictionary:
	var progress := run_progress()
	if not bool(progress.available):
		return _rejection_dto("run_restart_unavailable")
	if str(progress.run_state) not in ["COMPLETE", "DEFEATED"]:
		return _rejection_dto("run_restart_not_ready")
	if p_personality_seed == personality_seed:
		return _rejection_dto("personality_seed_unchanged")
	var frozen_world_seed := world_seed
	var frozen_scenario_id := scenario_id
	if not reset_party(frozen_world_seed, p_personality_seed, frozen_scenario_id):
		return _rejection_dto("run_restart_failed")
	return _feedback_dto({"accepted":true, "reason":"ok",
		"world_seed":str(world_seed), "personality_seed":str(personality_seed),
		"scenario_id":scenario_id, "run_progress":run_progress()})


func party_personality_summary() -> Dictionary:
	var rows: Array = []
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return {"schema_version":1,"personality_seed":str(personality_seed),
			"companion_rows":rows}.duplicate(true)
	var state = sim.world.party_encounter
	for member_id_value in state.party_member_ids:
		var member_id := int(member_id_value)
		var member = state.member(member_id)
		if member == null or member.role != "COMPANION" \
				or member.personality_profile == null \
				or not sim.world.entities.has(member_id):
			continue
		var archetype := personality_archetype(member.personality_profile)
		rows.append({"actor_id":member_id,"roster_slot":int(member.roster_slot),
			"display_name":str(sim.world.entities[member_id].display_name),
			"archetype_id":str(archetype.get("archetype_id","")),
			"archetype_label":str(archetype.get("label","")),
			"facet_rows":member.personality_profile.facet_rows.duplicate(true)})
	for candidate_id_value in rescue_candidate_ids():
		var candidate_id := int(candidate_id_value)
		var profile = _rescue_personality_profile(candidate_id)
		if profile == null or not sim.world.entities.has(candidate_id): continue
		var archetype := personality_archetype(profile)
		rows.append({"actor_id":candidate_id,"roster_slot":63,
			"display_name":str(sim.world.entities[candidate_id].display_name),
			"archetype_id":str(archetype.get("archetype_id","")),
			"archetype_label":str(archetype.get("label","")),
			"facet_rows":profile.facet_rows.duplicate(true)})
	rows.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.roster_slot)<int(b.roster_slot) if int(a.roster_slot)!=int(b.roster_slot) \
			else int(a.actor_id)<int(b.actor_id))
	return {"schema_version":1,"personality_seed":str(personality_seed),
		"companion_rows":rows}.duplicate(true)

func observe_party_world() -> Dictionary:
	var status := party_status()
	var progress := run_progress()
	# The SHOWCASE is a visual test: a distant monster is deliberately visible
	# before its detection radius is crossed. REGRESSION keeps the legacy reveal.
	var hide_enemies: bool = scenario_id == REGRESSION_SCENARIO_ID \
		and str(status.safe_phase) in ["GROUPED", "GROUPED_COMPLETE"]
	var hero_position := Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	var visible: Dictionary = VisualTestMapScript.visible_cells(sim.world, hero_position, scenario_id)
	# The controlled actor is always a valid presentation anchor. Keep this
	# explicit so grouped followers can safely fall back to the hero cell even if
	# a future LOS implementation accidentally omits its origin.
	visible[_position_key(hero_position)] = true
	var follower_positions := _grouped_follower_display_positions(visible)
	var followers_by_cell: Dictionary = {}
	for member_id_value in follower_positions:
		var member_id := int(member_id_value)
		var follower_position: Vector2i = follower_positions[member_id]
		var follower_key := _position_key(follower_position)
		if not followers_by_cell.has(follower_key): followers_by_cell[follower_key] = []
		followers_by_cell[follower_key].append(member_id)
	var cells: Array = []
	for y in range(sim.world.height):
		for x in range(sim.world.width):
			var position := Vector2i(x,y)
			var visibility_state := "VISIBLE" if visible.has(_position_key(position)) else "UNSEEN"
			if visibility_state == "UNSEEN":
				cells.append({"position":[x,y], "terrain_id":"unknown", "feature_id":"",
					"visibility_state":"UNSEEN", "fire_intensity":0, "wetness":0,
					"effective_conductivity":0, "actors":[]})
				continue
			var actors: Array = []
			for entity in sim.world.occupying_entities_at(position):
				var is_enemy: bool = entity.id in sim.world.party_encounter.enemy_ids
				if is_enemy and hide_enemies: continue
				actors.append(_actor_observation(entity, position, position, ""))
			for member_id_value in followers_by_cell.get(_position_key(position), []):
				var member_id := int(member_id_value)
				if sim.world.entities.has(member_id):
					actors.append(_actor_observation(sim.world.entities[member_id],
						sim.world.party_encounter.group_anchor, position, "FOLLOWER"))
			actors.sort_custom(func(a: Dictionary, b: Dictionary):
				return int(a.roster_slot) < int(b.roster_slot) \
					if int(a.roster_slot) != int(b.roster_slot) \
					else int(a.entity_id) < int(b.entity_id))
			var tile = sim.world.tile_at(position)
			cells.append({"position":[x,y], "terrain_id":str(tile.terrain),
				"feature_id":_run_feature_id_at(position, progress),
				"visibility_state":"VISIBLE", "fire_intensity":int(tile.fire),
				"wetness":int(tile.wetness),
				"effective_conductivity":int(tile.effective_conductivity()), "actors":actors})
	return {"width": sim.world.width, "height": sim.world.height, "cells": cells,
		"phase": party_status(), "grid_mapping": {"origin": [0,0], "cell_count": 225},
		"visibility":{"mode":"LOS_RADIUS" if scenario_id == SHOWCASE_SCENARIO_ID else "FULL",
			"radius":VisualTestMapScript.SHOWCASE_FOV_RADIUS if scenario_id == SHOWCASE_SCENARIO_ID else 15,
			"memory_supported":false}}.duplicate(true)


func _grouped_follower_display_positions(presentation_visible: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return result
	var state = sim.world.party_encounter
	var anchor: Vector2i = state.group_anchor
	var facing: Vector2i = state.facing
	if facing not in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		facing = Vector2i.RIGHT
	var used := {_position_key(anchor):true}
	# Presentation followers should avoid every authoritative occupant when a
	# distinct visible cell exists. Their logical position and occupancy remain
	# the grouped anchor; this set is only a renderer-placement constraint.
	for entity_id_value in sim.world.entities:
		var entity_id := int(entity_id_value)
		if sim.world.occupies_tile(entity_id):
			used[_position_key(sim.world.entities[entity_id].position)] = true
	var follower_ids: Array = []
	for member_id_value in state.party_member_ids:
		var member_id := int(member_id_value)
		var member = state.member(member_id)
		if member_id != state.protagonist_id and member != null \
				and member.presence == "GROUPED" and sim.world.occupies_tile(member_id):
			follower_ids.append(member_id)
	follower_ids.sort_custom(func(a, b):
		var member_a = state.member(int(a)); var member_b = state.member(int(b))
		return int(member_a.roster_slot) < int(member_b.roster_slot) \
			if int(member_a.roster_slot) != int(member_b.roster_slot) else int(a) < int(b))
	var adjacent_offsets := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]
	for follower_index in range(follower_ids.size()):
		var candidates: Array[Vector2i] = [anchor - facing * (follower_index + 1)]
		for offset in adjacent_offsets:
			var fallback: Vector2i = anchor + offset
			if fallback not in candidates: candidates.append(fallback)
		for candidate in candidates:
			var key := _position_key(candidate)
			if not sim.world.in_bounds(candidate) or used.has(key): continue
			if not presentation_visible.is_empty() and not presentation_visible.has(key): continue
			var terrain := TerrainRegistryScript.definition(str(sim.world.tile_at(candidate).terrain))
			if terrain.is_empty() or not bool(terrain.get("passable", false)): continue
			result[int(follower_ids[follower_index])] = candidate
			used[key] = true
			break
		# Visibility is more important than separation. At tight corners there may
		# be no free visible floor, so overlap the hero presentation instead of
		# silently dropping a party member from the observation DTO.
		if not result.has(int(follower_ids[follower_index])):
			result[int(follower_ids[follower_index])] = anchor
	return result


func _actor_observation(entity, logical_position: Vector2i,
		display_position: Vector2i, display_role_override: String) -> Dictionary:
	var member = sim.world.party_member_state(entity.id)
	var is_enemy: bool = entity.id in sim.world.party_encounter.enemy_ids
	var combatant = sim.world.combatant_states.get(entity.id)
	var actor_facing := _actor_facing(entity.id, is_enemy)
	var display_role := display_role_override
	if display_role.is_empty():
		display_role = "ENEMY" if is_enemy else ("PROTAGONIST" \
			if member != null and member.role == "PROTAGONIST" else ("COMPANION" \
			if member != null else "ACTOR"))
	var dto := {"entity_id":entity.id, "display_name":entity.display_name,
		"kind":str(entity.kind), "species_id":str(entity.species_id),
		"health":entity.health, "max_health":entity.max_health,
		"life_state":str(combatant.life_state) if combatant != null else "DEAD",
		"status_ids":_combatant_status_ids(entity.id),
		"guarded":combatant != null and combatant.life_state == "ACTIVE" \
			and sim.world.world_time < combatant.guarded_until,
		"facing":[actor_facing.x, actor_facing.y],
		"logical_position":[logical_position.x, logical_position.y],
		"display_position":[display_position.x, display_position.y],
		"display_role":display_role,
		"is_protagonist":member != null and member.role == "PROTAGONIST",
		"roster_slot":member.roster_slot if member != null else 99,
		"faction_id":entity.faction_id,
		"presence":member.presence if member != null else "DEPLOYED",
		"is_enemy":is_enemy,
		"sprite_frame":0 if member != null and member.role == "PROTAGONIST" \
			else (4 if member != null else 5)}
	if member == null and _rescue_discovery_event_for(entity.id) != null:
		var story_state := rescue_story_state(entity.id)
		dto["display_role"] = "RESCUE_NPC"
		dto["presence"] = "WORLD_NPC"
		dto["story_state"] = story_state
		dto["authoritative_life_state"] = str(combatant.life_state) \
			if combatant != null else "DEAD"
		# DOWNED is a presentation pose only. Combat life remains ACTIVE and all
		# occupancy/hit authority continues to use the canonical world entity.
		dto["life_state"] = "DOWNED" if story_state == "COLLAPSED_STORY" else "ACTIVE"
	return dto

func party_cards() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []; var state = sim.world.party_encounter
	var preview: Dictionary = current_turn_preview() if _protagonist_draft != null else {}
	var preview_by_actor: Dictionary = {}
	for actor_row in preview.get("actor_rows", []): preview_by_actor[int(actor_row.actor_id)] = actor_row
	for member_id in state.active_party_member_ids:
		var member = state.member(member_id); var entity = sim.world.entities[member_id]
		var logical: Vector2i = entity.position if member.presence == "DEPLOYED" else (state.group_anchor if member.presence == "GROUPED" else Vector2i(-1,-1))
		var exposure := {"applicable": false, "sampled_step_index": sim.world.step_index, "sampled_world_time": sim.world.world_time,
			"position": [-1,-1], "fire_score": 0, "water_score": 0, "electric_score": 0, "poison_score": 0, "total_risk": 0}
		if member.presence in ["DEPLOYED", "GROUPED"] and sim.world.is_environment_exposed(member_id):
			var evaluated = sim.evaluate_exposure_for_entity(member_id, logical); var wire: Dictionary = evaluated.evaluation.to_dict()
			exposure = {"applicable": true, "sampled_step_index": int(wire.sampled_step_index), "sampled_world_time": int(wire.sampled_world_time),
				"position": wire.position, "fire_score": wire.fire_score, "water_score": wire.water_score, "electric_score": wire.electric_score,
				"poison_score": wire.poison_score, "total_risk": wire.total_risk}
		var expected_action = null if _protagonist_placeholder \
				and member.role == "PROTAGONIST" \
			else _action_presentation(preview_by_actor.get(member_id, null))
		var readiness := "행동 준비" if member.busy_until <= sim.world.world_time else "행동 중"
		var emotion := _emotion_presentation(member, entity)
		var override_state := "PENDING"
		if expected_action != null: override_state = str(expected_action.source)
		elif member.role == "PROTAGONIST":
			override_state = "PENDING" if _protagonist_placeholder else "DIRECT"
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
	for member_id in state.active_party_member_ids:
		if member_id != state.protagonist_id and sim.world.is_autonomous_target(member_id): ids.append(member_id)
	return ids.duplicate()


func rescue_candidate_ids() -> Array:
	var ids: Array = []
	if sim == null or sim.world == null: return ids
	for event in sim.world.events:
		if event.type != "party.rescue_discovered" or event.target_id <= 0 \
				or event.target_id in ids or not sim.world.entities.has(event.target_id):
			continue
		if rescue_story_state(event.target_id) != "JOINED": ids.append(event.target_id)
	ids.sort()
	return ids.duplicate()


func is_rescue_candidate(entity_id: int) -> bool:
	return entity_id in rescue_candidate_ids()


func rescue_story_state(entity_id: int) -> String:
	var discovery = _rescue_discovery_event_for(entity_id)
	if discovery == null: return ""
	var outcome = _recruitment_outcome_event_for(entity_id)
	if outcome != null:
		return "JOINED" if outcome.type == "party.recruitment_accepted" else "REJECTED"
	if _rescue_event_for(entity_id) != null: return "OFFER_READY"
	return str(discovery.data.get("state", "COLLAPSED_STORY"))


func rescue_assessment(entity_id: int) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized")
	var state = sim.world.party_encounter
	if state.safe_phase not in ["GROUPED", "GROUPED_COMPLETE"] or _run_is_complete():
		return _rejection_dto("party_roster_unsafe_phase")
	var discovery = _rescue_discovery_event_for(entity_id)
	var entity = sim.world.entities.get(entity_id)
	var combatant = sim.world.combatant_states.get(entity_id)
	if discovery == null or entity == null or combatant == null \
			or not entity.tags.has("rescue_npc") \
			or not bool(discovery.data.get("non_hostile", false)):
		return _rejection_dto("rescue_candidate_not_recruitable")
	if rescue_story_state(entity_id) != "COLLAPSED_STORY":
		return _rejection_dto("rescue_already_completed")
	if str(combatant.life_state) != "ACTIVE":
		return _rejection_dto("rescue_candidate_unavailable")
	var hero = sim.world.entities.get(state.protagonist_id)
	if hero == null or maxi(absi(hero.position.x-entity.position.x),
			absi(hero.position.y-entity.position.y)) > 1:
		return _rejection_dto("rescue_candidate_too_far")
	return _feedback_dto({"accepted":true,"reason":"ok","entity_id":entity_id,
		"story_state":"COLLAPSED_STORY","result_state":"OFFER_READY",
		"life_state":"DOWNED","authoritative_life_state":"ACTIVE",
		"time_cost":RESCUE_TIME_COST,"consumes_time":true,
		"message_ko":"한 턴을 들여 상처를 안정화합니다."})


func stabilize_recruit_candidate(entity_id: int) -> Dictionary:
	var assessment := rescue_assessment(entity_id)
	if not bool(assessment.get("accepted", false)): return assessment
	var rollback_value: Variant = sim.snapshot()
	if not rollback_value is Dictionary:
		return _rejection_dto("party_snapshot_unavailable")
	var rollback: Dictionary = rollback_value
	var state = sim.world.party_encounter
	var hero_id: int = int(state.protagonist_id)
	var result = sim.step(CommandScript.wait_for(RESCUE_TIME_COST, hero_id))
	if not result.accepted or not sim.world.entities.has(entity_id) \
			or str(sim.world.combatant_states[entity_id].life_state) != "ACTIVE" \
			or rescue_story_state(entity_id) != "COLLAPSED_STORY":
		_restore_roster_rollback(rollback)
		return _rejection_dto("rescue_stabilization_failed")
	_advance_exile_world()
	var entity = sim.world.entities[entity_id]
	var rescued = sim.world.emit_event("party.npc_stabilized", hero_id, entity_id,
		entity.position, 0, -1, {"schema_version":1,
			"previous_state":"COLLAPSED_STORY", "state":"OFFER_READY",
			"time_cost":RESCUE_TIME_COST})
	if rescued == null or not sim.relationships.record_aid(entity_id, hero_id,
			rescued.id, RESCUE_AID_MAGNITUDE):
		_restore_roster_rollback(rollback)
		return _rejection_dto("rescue_stabilization_failed")
	state = sim.world.party_encounter
	state.revision += 1
	if not sim.world.world_state_error().is_empty():
		_restore_roster_rollback(rollback)
		return _rejection_dto("rescue_stabilization_failed")
	_clear_draft(); _deployment_plan.clear()
	if _exploration_route != null: _exploration_route.clear()
	command_journal.append({"kind":"roster","operation":{
		"action":"STABILIZE","entity_id":str(entity_id)}})
	return _feedback_dto({"accepted":true,"reason":"ok","entity_id":entity_id,
		"life_state":"ACTIVE","story_state":"OFFER_READY",
		"consumes_time":true,"step_index":int(result.processed_step_index),
		"start_time":int(result.start_time),"end_time":int(result.end_time),
		"time_cost":RESCUE_TIME_COST,"event_ids":[rescued.id],
		"recruitment":recruitment_assessment(entity_id)})


func recruitment_assessment(entity_id: int) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized")
	var state = sim.world.party_encounter
	var discovery = _rescue_discovery_event_for(entity_id)
	var entity = sim.world.entities.get(entity_id)
	var combatant = sim.world.combatant_states.get(entity_id)
	if discovery == null or entity == null or combatant == null:
		return _rejection_dto("companion_not_recruitable")
	var prior_outcome = _recruitment_outcome_event_for(entity_id)
	if prior_outcome != null:
		return _feedback_dto({"accepted":false,"reason":"recruitment_already_resolved",
			"entity_id":entity_id,"resolved":true,
			"joined":str(prior_outcome.type)=="party.recruitment_accepted",
			"probability_milli":int(prior_outcome.data.get("probability_milli",0)),
			"probability_percent":int((int(prior_outcome.data.get("probability_milli",0))+5)/10),
			"roll_milli":int(prior_outcome.data.get("roll_milli",-1)),
			"reasons":prior_outcome.data.get("reasons",[]).duplicate(true)})
	var rescue_event = _rescue_event_for(entity_id)
	if rescue_event == null or rescue_story_state(entity_id) != "OFFER_READY":
		return _rejection_dto("recruitment_requires_rescue")
	var relation: Dictionary = sim.relationships.effective_relation(entity_id,
		state.protagonist_id)
	var species_base: Dictionary = relation.get("species_base",{})
	var personal: Dictionary = relation.get("personal",{})
	# Species prior is intentionally the dominant single term. Personal history
	# can soften it, but one rescue never makes inherited hostility disappear.
	var species_term := int(species_base.get("base_trust",0))*5 \
		- int(species_base.get("base_hostility",0))*5 \
		- int(species_base.get("base_fear",0))*3
	var affection_term := int(personal.get("trust_delta",0))*3 \
		- maxi(0,int(personal.get("fear_delta",0)))*2 \
		- int(personal.get("grievance",0))*2
	var memory_term := int(personal.get("gratitude",0))
	var profile = _rescue_personality_profile(entity_id)
	var personality_term := 0
	if profile != null:
		personality_term = clampi(int((profile.value("altruism")-500)/5) \
			+ int((profile.value("composure")-500)/10), -140, 140)
	var hp_percent := int(entity.health*100/maxi(1,entity.max_health))
	var survival_term := clampi((100-hp_percent)*2,0,180)
	var rescue_term := 180
	var has_vacancy: bool = state.active_party_member_ids.size() < ACTIVE_PARTY_LIMIT
	var vacancy_term := 40 if has_vacancy else 0
	var probability := clampi(500+species_term+affection_term+memory_term \
		+personality_term+survival_term+rescue_term+vacancy_term,50,950)
	var reasons: Array[Dictionary] = _recruitment_reason_rows(species_base,
		relation, personality_term, survival_term, rescue_term, vacancy_term)
	var hero = sim.world.entities.get(state.protagonist_id)
	var adjacent: bool = hero != null and maxi(absi(hero.position.x-entity.position.x),
		absi(hero.position.y-entity.position.y)) <= 1
	var legal: bool = has_vacancy and adjacent \
		and str(combatant.life_state)=="ACTIVE" \
		and state.safe_phase in ["GROUPED","GROUPED_COMPLETE"] \
		and not _run_is_complete()
	var reason := "ok"
	if not has_vacancy: reason = "party_full"
	elif not adjacent: reason = "recruitment_candidate_too_far"
	elif str(combatant.life_state)!="ACTIVE": reason = "companion_unavailable"
	elif state.safe_phase not in ["GROUPED","GROUPED_COMPLETE"] or _run_is_complete():
		reason = "party_roster_unsafe_phase"
	var key := "%s|world=%d|personality=%d|candidate=%d|rescue=%d" % [
		RECRUITMENT_RULESET_ID,world_seed,personality_seed,entity_id,int(rescue_event.id)]
	# A blocked offer exposes its probability and reasons, but consumes neither
	# the keyed roll nor a judgment event. Opening a vacancy reveals the stable roll.
	var roll := _stable_roll_milli(key) if legal else -1
	return _feedback_dto({"accepted":legal,"reason":reason,"entity_id":entity_id,
		"resolved":false,"joined":false,"probability_milli":probability,
		"probability_percent":int((probability+5)/10),"roll_milli":roll,
		"would_accept":legal and roll<probability,"ruleset_id":RECRUITMENT_RULESET_ID,
		"key_hash":key.sha256_text() if legal else "","reasons":reasons,
		"terms":{"species_prior":species_term,"affection":affection_term,
			"personal_memory":memory_term,"personality":personality_term,
			"survival_threat":survival_term,"rescued":rescue_term,
			"vacancy":vacancy_term}})


func offer_recruitment(entity_id: int) -> Dictionary:
	var assessment := recruitment_assessment(entity_id)
	if not bool(assessment.get("accepted",false)): return assessment
	var rollback_value: Variant = sim.snapshot()
	if not rollback_value is Dictionary:
		return _rejection_dto("party_snapshot_unavailable")
	var rollback: Dictionary = rollback_value
	var hero_id: int = int(sim.world.party_encounter.protagonist_id)
	var result = sim.step(CommandScript.wait_for(RECRUITMENT_OFFER_TIME_COST,hero_id))
	if not result.accepted: return _rejection_dto(str(result.reason))
	_advance_exile_world()
	var joined := bool(assessment.would_accept)
	var event_type := "party.recruitment_accepted" if joined \
		else "party.recruitment_refused"
	var reason_codes: Array[String] = []
	for row in assessment.reasons: reason_codes.append(str(row.get("code","")))
	var decision = sim.world.emit_event(event_type, entity_id, hero_id,
		sim.world.entities[entity_id].position,
		int(assessment.probability_milli), -1, {"schema_version":1,
			"ruleset_id":RECRUITMENT_RULESET_ID,
			"probability_milli":int(assessment.probability_milli),
			"roll_milli":int(assessment.roll_milli),"accepted":joined,
			"reason_codes":reason_codes,
			"reasons":assessment.reasons.duplicate(true)})
	if decision == null:
		_restore_roster_rollback(rollback)
		return _rejection_dto("recruitment_resolution_failed")
	if joined:
		if not _prepare_rescue_candidate_for_roster(entity_id):
			_restore_roster_rollback(rollback)
			return _rejection_dto("recruitment_resolution_failed")
		var roster_result := _apply_roster_change("RECRUIT",entity_id,false)
		if not bool(roster_result.get("accepted",false)):
			_restore_roster_rollback(rollback)
			return _rejection_dto("recruitment_resolution_failed")
	else:
		sim.world.party_encounter.revision += 1
	if not sim.world.world_state_error().is_empty():
		_restore_roster_rollback(rollback)
		return _rejection_dto("recruitment_resolution_failed")
	_clear_draft(); _deployment_plan.clear()
	if _exploration_route != null: _exploration_route.clear()
	command_journal.append({"kind":"roster","operation":{
		"action":"OFFER_RECRUIT","entity_id":str(entity_id)}})
	return _feedback_dto({"accepted":true,"reason":"ok","resolved":true,
		"entity_id":entity_id,"joined":joined,
		"probability_milli":int(assessment.probability_milli),
		"probability_percent":int(assessment.probability_percent),
		"roll_milli":int(assessment.roll_milli),
		"reasons":assessment.reasons.duplicate(true),"consumes_time":true,
		"step_index":int(result.processed_step_index),
		"start_time":int(result.start_time),"end_time":int(result.end_time),
		"time_cost":RECRUITMENT_OFFER_TIME_COST,"event_ids":[decision.id]})


func _recruitment_reason_rows(species_base: Dictionary, relation: Dictionary,
		personality_term: int, survival_term: int, rescue_term: int,
		vacancy_term: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var base_trust := int(species_base.get("base_trust",0))
	var base_hostility := int(species_base.get("base_hostility",0))
	if base_trust>=15 and base_hostility<30:
		rows.append({"code":"SPECIES_AFFINITY","label":"종족 사이 기본 호감이 있습니다.","tone":"POSITIVE"})
	elif base_trust<=-20 or base_hostility>=45:
		rows.append({"code":"SPECIES_DISTRUST","label":"종족 사이 뿌리 깊은 경계가 있습니다.","tone":"NEGATIVE"})
	else:
		rows.append({"code":"SPECIES_WARY","label":"종족 차이 때문에 아직 조심스럽습니다.","tone":"CAUTION"})
	if rescue_term>0:
		rows.append({"code":"RESCUED","label":"당신이 목숨을 구해 준 일을 기억합니다.","tone":"POSITIVE"})
	if int(relation.get("gratitude",0))>=50 or int(relation.get("trust",0))>=25:
		rows.append({"code":"PERSONAL_AFFECTION","label":"개인적인 감사와 호감이 큽니다.","tone":"POSITIVE"})
	elif int(relation.get("hostility",0))>=45 or int(relation.get("trust",0))<0:
		rows.append({"code":"PERSONAL_WARY","label":"개인적으로도 아직 완전히 믿지 못합니다.","tone":"NEGATIVE"})
	if survival_term>=120:
		rows.append({"code":"SURVIVAL_THREAT","label":"부상이 심해 안전한 동행이 절실합니다.","tone":"POSITIVE"})
	if personality_term>=40:
		rows.append({"code":"OPEN_PERSONALITY","label":"도움을 받아들이는 성향입니다.","tone":"POSITIVE"})
	elif personality_term<=-40:
		rows.append({"code":"GUARDED_PERSONALITY","label":"쉽게 마음을 열지 않는 성향입니다.","tone":"CAUTION"})
	if vacancy_term>0:
		rows.append({"code":"PARTY_VACANCY","label":"파티에 함께할 빈자리가 있습니다.","tone":"POSITIVE"})
	return rows


static func _stable_roll_milli(key: String) -> int:
	var digest: PackedByteArray = key.sha256_buffer()
	var value := ((int(digest[0])&0x7f)<<24)|(int(digest[1])<<16) \
		|(int(digest[2])<<8)|int(digest[3])
	return value%1000


func _rescue_discovery_event_for(entity_id: int):
	if sim == null or sim.world == null: return null
	for event in sim.world.events:
		if event.type == "party.rescue_discovered" and event.target_id == entity_id:
			return event
	return null


func _rescue_event_for(entity_id: int):
	if sim == null or sim.world == null: return null
	for index in range(sim.world.events.size()-1,-1,-1):
		var event = sim.world.events[index]
		if event.type=="party.npc_stabilized" and event.target_id==entity_id:
			return event
	return null


func _rescue_personality_profile(entity_id: int):
	var discovery = _rescue_discovery_event_for(entity_id)
	if discovery == null: return null
	var slot := int(discovery.data.get("personality_slot", 3))
	return PersonalityRegistryScript.generate(personality_seed, slot)


func _prepare_rescue_candidate_for_roster(entity_id: int) -> bool:
	if sim == null or sim.world == null or sim.world.party_encounter == null \
			or _rescue_discovery_event_for(entity_id) == null \
			or not sim.world.entities.has(entity_id):
		return false
	var state = sim.world.party_encounter
	if state.member(entity_id) != null \
			or state.active_party_member_ids.size() >= ACTIVE_PARTY_LIMIT:
		return false
	var profile = _rescue_personality_profile(entity_id)
	if profile == null: return false
	state.party_member_ids.append(entity_id)
	state.party_member_ids.sort()
	state.member_rows[entity_id] = MemberScript.new(entity_id, 0,
		"COMPANION", "RECRUITABLE", profile)
	state.member_rows[entity_id].busy_until = sim.world.world_time
	for roster_index in range(state.party_member_ids.size()):
		state.member_rows[state.party_member_ids[roster_index]].roster_slot = roster_index
	return true


func _recruitment_outcome_event_for(entity_id: int):
	if sim == null or sim.world == null: return null
	for index in range(sim.world.events.size()-1,-1,-1):
		var event = sim.world.events[index]
		if event.type in ["party.recruitment_accepted","party.recruitment_refused"] \
				and event.actor_id==entity_id:
			return event
	return null


func _restore_roster_rollback(snapshot: Dictionary) -> void:
	var restored = SimulatorScript.from_snapshot(snapshot)
	if restored != null: sim = restored


func roster_change_assessment(operation: String, entity_id: int) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized")
	var state = sim.world.party_encounter
	if state.safe_phase not in ["GROUPED", "GROUPED_COMPLETE"] or _run_is_complete():
		return _rejection_dto("party_roster_unsafe_phase")
	var member = state.member(entity_id)
	if member == null or not sim.world.entities.has(entity_id):
		return _rejection_dto("party_member_not_found")
	if operation == "DISMISS":
		if entity_id == state.protagonist_id: return _rejection_dto("protagonist_dismiss_forbidden")
		if entity_id not in state.active_party_member_ids: return _rejection_dto("companion_not_active")
		if member.role != "COMPANION" or sim.world.combatant_states[entity_id].life_state != "ACTIVE":
			return _rejection_dto("companion_unavailable")
	elif operation == "RECRUIT":
		if entity_id in state.active_party_member_ids or entity_id not in state.party_member_ids \
				or member.role != "COMPANION" or member.presence != "RECRUITABLE":
			return _rejection_dto("companion_not_recruitable")
		if state.active_party_member_ids.size() >= ACTIVE_PARTY_LIMIT: return _rejection_dto("party_full")
		if sim.world.combatant_states[entity_id].life_state != "ACTIVE": return _rejection_dto("companion_unavailable")
	else:
		return _rejection_dto("invalid_roster_operation")
	return _feedback_dto({"accepted":true,"reason":"ok","operation":operation,
		"entity_id":entity_id,"active_party_member_ids":state.active_party_member_ids.duplicate(true)})


func recruitable_companions() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if sim == null or sim.world == null or sim.world.party_encounter == null: return rows
	var state = sim.world.party_encounter
	for entity_id in state.party_member_ids:
		if entity_id in state.active_party_member_ids: continue
		var member = state.member(entity_id); var entity = sim.world.entities.get(entity_id)
		if member == null or entity == null or member.presence != "RECRUITABLE": continue
		var archetype := personality_archetype(member.personality_profile)
		var assessment := roster_change_assessment("RECRUIT", entity_id)
		rows.append({"entity_id":entity_id,"roster_slot":int(member.roster_slot),
			"display_name":str(entity.display_name),"presence":str(member.presence),
			"health":int(entity.health),"max_health":int(entity.max_health),
			"life_state":"ACTIVE","authoritative_life_state":"ACTIVE",
			"status_ids":_combatant_status_ids(entity_id),
			"archetype_label":str(archetype.get("label","동료")),
			"rescue_state":"AVAILABLE","can_stabilize":false,"stabilization":{},
			"decision_available":false,"recruitment":{},
			"can_recruit":bool(assessment.get("accepted",false)),
			"reason":str(assessment.get("reason","ok")),
			"message":str(assessment.get("message",""))})
	for entity_id_value in rescue_candidate_ids():
		var entity_id := int(entity_id_value)
		var entity = sim.world.entities[entity_id]
		var story_state := rescue_story_state(entity_id)
		var rescue := rescue_assessment(entity_id) if story_state=="COLLAPSED_STORY" else {}
		var recruitment := recruitment_assessment(entity_id) \
			if story_state in ["OFFER_READY","REJECTED"] else {}
		var profile = _rescue_personality_profile(entity_id)
		var archetype := personality_archetype(profile)
		rows.append({"entity_id":entity_id,"roster_slot":63,
			"display_name":str(entity.display_name),"presence":"WORLD_NPC",
			"health":int(entity.health),"max_health":int(entity.max_health),
			"life_state":"DOWNED" if story_state=="COLLAPSED_STORY" else "ACTIVE",
			"authoritative_life_state":str(sim.world.combatant_states[entity_id].life_state),
			"status_ids":_combatant_status_ids(entity_id),
			"archetype_label":str(archetype.get("label","동료")),
			"rescue_state":story_state,"can_stabilize":bool(rescue.get("accepted",false)),
			"stabilization":rescue.duplicate(true),
			"decision_available":story_state in ["OFFER_READY","REJECTED"],
			"recruitment":recruitment.duplicate(true),
			"can_recruit":bool(recruitment.get("accepted",false)),
			"reason":str(recruitment.get("reason",rescue.get("reason","ok"))),
			"message":str(recruitment.get("message",rescue.get("message","")))})
	rows.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.roster_slot)<int(b.roster_slot) if int(a.roster_slot)!=int(b.roster_slot) \
			else int(a.entity_id)<int(b.entity_id))
	return rows.duplicate(true)


func exile_story_records() -> Array:
	if sim==null or sim.world==null or sim.world.party_encounter==null:return []
	return sim.world.party_encounter.exile_records.duplicate(true)


func _exile_record_for_member(entity_id:int):
	for record in sim.world.party_encounter.exile_records:
		if int(str(record.former_member_id))==entity_id:return record.duplicate(true)
	return null


func dismiss_companion(entity_id: int) -> Dictionary:
	return _apply_roster_change("DISMISS", entity_id)


func recruit_companion(entity_id: int) -> Dictionary:
	if _rescue_discovery_event_for(entity_id)!=null:
		return _rejection_dto("recruitment_already_resolved") \
			if _recruitment_outcome_event_for(entity_id)!=null \
			else _rejection_dto("recruitment_offer_required")
	return _apply_roster_change("RECRUIT", entity_id)


func _apply_roster_change(operation: String, entity_id: int,
		append_journal: bool = true) -> Dictionary:
	var assessment := roster_change_assessment(operation, entity_id)
	if not bool(assessment.get("accepted",false)): return assessment
	var rollback: Dictionary = sim.snapshot()
	var state = sim.world.party_encounter
	var exile_condition: Dictionary = _exile_condition(entity_id) if operation=="DISMISS" else {}
	if operation=="DISMISS" and not bool(exile_condition.get("valid",false)):
		return _rejection_dto("party_roster_change_failed")
	if operation == "DISMISS":
		state.active_party_member_ids.erase(entity_id)
		state.member(entity_id).presence = "EXILED"
		# Exile is permanent and removes the tombstone from every future lifecycle
		# target. Status history remains in the immutable event stream, while the
		# no-longer-observable entity keeps no live status row.
		sim.world.combatant_states[entity_id].status_rows.clear()
	else:
		state.active_party_member_ids.append(entity_id); state.active_party_member_ids.sort()
		state.member(entity_id).presence = "GROUPED"
		sim.world.entities[entity_id].position = state.group_anchor
	var event_type := "party.companion_dismissed" if operation == "DISMISS" \
		else "party.companion_recruited"
	var event_data:={"operation":operation}
	if operation=="DISMISS":
		event_data["condition_band"]=str(exile_condition.condition_band)
		event_data["resentment_delta"]=int(exile_condition.resentment_delta)
	var event = sim.world.emit_event(event_type, state.protagonist_id, entity_id,
		state.group_anchor, 0, -1, event_data)
	if event!=null and operation=="DISMISS":
		if not sim.relationships.record_harm(entity_id,state.protagonist_id,event.id,
				int(exile_condition.resentment_delta)):
			event=null
		else:
			state.exile_records.append(_new_exile_record(entity_id,event.id,exile_condition))
	state.revision += 1
	var roster_world_error:String=sim.world.world_state_error()
	if event == null or not roster_world_error.is_empty():
		var restored = SimulatorScript.from_snapshot(rollback)
		if restored != null: sim = restored
		return _rejection_dto("party_roster_change_failed")
	_clear_draft(); _deployment_plan.clear()
	if _exploration_route != null: _exploration_route.clear()
	if append_journal:
		command_journal.append({"kind":"roster","operation":{
			"action":operation,"entity_id":str(entity_id)}})
	return _feedback_dto({"accepted":true,"reason":"ok","operation":operation,
		"entity_id":entity_id,"active_party_member_ids":state.active_party_member_ids.duplicate(true),
		"recruitable_member_ids":_member_ids_with_presence("RECRUITABLE"),
		"exiled_member_ids":_member_ids_with_presence("EXILED")})


func _exile_condition(entity_id:int)->Dictionary:
	if sim.world.step_index>9223372036854775807-EXILE_ENCOUNTER_STEP_DELAY:return {"valid":false}
	var entity=sim.world.entities[entity_id];var member=sim.world.party_encounter.member(entity_id)
	var status_effects:Array=[]
	for status in sim.world.combatant_states[entity_id].status_rows:
		var remaining:=clampi(int((status.expires_at-status.next_tick_at)/EXILE_WORLD_INTERVAL)+1,1,16)
		status_effects.append({"status_id":str(status.status_id),"remaining_ticks":remaining,
			"tick_damage":3 if str(status.status_id)=="BLEEDING" else 2})
	status_effects.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.status_id)<str(b.status_id))
	var harmful_status:=not status_effects.is_empty()
	var hp_percent:=int(entity.health*100/maxi(1,entity.max_health));var band:="STRAINED"
	if hp_percent>=70 and member.stress<350 and not harmful_status:band="HEALTHY"
	elif hp_percent<=30 or member.stress>=750 or harmful_status:band="ENDANGERED"
	var relation:Dictionary=sim.relationships.effective_relation(entity_id,
		sim.world.party_encounter.protagonist_id)
	var composure:=int(member.personality_profile.value("composure"))
	var vulnerability:=(100-hp_percent)+int(member.stress/10)+(45 if harmful_status else 0)
	var resentment_delta:=clampi(15+int(vulnerability/2)+int(relation.get("grievance",0)/4)-int(composure/50),10,100)
	var fear_delta:=clampi(int((100-hp_percent)/2)+int(member.stress/20)+(20 if harmful_status else 0),5,100)
	return {"valid":true,"condition_band":band,"resentment_delta":resentment_delta,
		"fear_delta":fear_delta,"hp_percent":hp_percent,"stress":int(member.stress),
		"harmful_status":harmful_status,"status_effects":status_effects}


func _new_exile_record(entity_id:int,dismissal_event_id:int,condition:Dictionary)->Dictionary:
	var entity=sim.world.entities[entity_id];var member=sim.world.party_encounter.member(entity_id)
	var archetype:=personality_archetype(member.personality_profile)
	var profile_wire:Dictionary=member.personality_profile.to_dict()
	var relation:Dictionary=sim.relationships.effective_relation(entity_id,
		sim.world.party_encounter.protagonist_id)
	return {"schema_version":1,"former_member_id":str(entity_id),
		"display_name":str(entity.display_name),"species_id":str(entity.species_id),
		"personality_summary":{"archetype_id":str(archetype.get("archetype_id","")),
			"archetype_label":str(archetype.get("label","")),
			"profile_hash":JSON.stringify(profile_wire).sha256_text(),
			"aggression":int(member.personality_profile.value("aggression")),
			"altruism":int(member.personality_profile.value("altruism")),
			"boldness":int(member.personality_profile.value("boldness")),
			"composure":int(member.personality_profile.value("composure"))},
		"dismissed_world_time":str(sim.world.world_time),
		"dismissed_step_index":str(sim.world.step_index),"dismissal_event_id":str(dismissal_event_id),
		"condition_snapshot":{"condition_band":str(condition.condition_band),"hp":int(entity.health),
			"hp_percent":int(condition.hp_percent),"stress":int(condition.stress),
			"harmful_status":bool(condition.harmful_status)},
		"emotion_modifiers":{"resentment_delta":int(condition.resentment_delta),
			"fear_delta":int(condition.fear_delta)},
		"relationship_snapshot":{"trust":int(relation.get("trust",0)),"fear":int(relation.get("fear",0)),
			"hostility":int(relation.get("hostility",0)),"gratitude":int(relation.get("gratitude",0)),
			"grievance":int(relation.get("grievance",0))},
		"current_hp":int(entity.health),"max_hp":int(entity.max_health),
		"alive":sim.world.combatant_states[entity_id].life_state == "ACTIVE",
		"initial_status_effects":condition.status_effects.duplicate(true),
		"status_effects":condition.status_effects.duplicate(true),"location_id":"OFFSCREEN_WILDERNESS",
		"initial_safety":{"HEALTHY":400,"STRAINED":250,"ENDANGERED":100}[str(condition.condition_band)],
		"safety":{"HEALTHY":400,"STRAINED":250,"ENDANGERED":100}[str(condition.condition_band)],
		"current_behavior":"SEEK_SAFETY","last_world_time":str(sim.world.world_time),
		"last_world_step":str(sim.world.step_index),
		"encounter_eligible_after_step":str(sim.world.step_index+EXILE_ENCOUNTER_STEP_DELAY)}


func _advance_exile_world()->void:
	var state=sim.world.party_encounter
	for index in range(state.exile_records.size()):
		var record:Dictionary=state.exile_records[index]
		if not bool(record.alive):continue
		var next_tick:=int(str(record.last_world_time))+EXILE_WORLD_INTERVAL
		var processed:=false
		while next_tick<=sim.world.world_time and bool(record.alive):
			processed=true
			var hp_before:=int(record.current_hp);var behavior:="SEEK_SAFETY"
			var status_rows:Array=record.status_effects.duplicate(true);var remaining:Array=[];var expired:Array=[]
			if not status_rows.is_empty():
				behavior="SELF_TREAT" if int(record.personality_summary.composure)>=450 \
					or int(record.safety)>=400 else "SEEK_SAFETY"
				for status in status_rows:
					record.current_hp=maxi(0,int(record.current_hp)-int(status.tick_damage))
					var duration_cost:=2 if behavior=="SELF_TREAT" else 1
					status.remaining_ticks=int(status.remaining_ticks)-duration_cost
					if int(status.remaining_ticks)>0 and int(record.current_hp)>0:remaining.append(status)
					else:expired.append(str(status.status_id))
				record.status_effects=remaining
			else:
				behavior="RECOVER"
				var recovery:=3 if int(record.safety)>=500 else 1
				record.current_hp=mini(int(record.max_hp),int(record.current_hp)+recovery)
			record.safety=mini(1000,int(record.safety)+150)
			record.alive=int(record.current_hp)>0
			record.current_behavior=behavior if bool(record.alive) else "DEAD"
			var tick=sim.world.emit_event("party.exile_world_tick",-1,
				int(str(record.former_member_id)),Vector2i(-1,-1),maxi(0,hp_before-int(record.current_hp)),
				int(str(record.dismissal_event_id)),{"behavior":str(record.current_behavior),
					"alive":bool(record.alive),"expired_status_ids":expired,
					"hp_after":int(record.current_hp),"hp_before":hp_before,
					"safety_after":int(record.safety),
					"scheduled_world_time":str(next_tick),
					"status_effects_after":record.status_effects.duplicate(true)})
			if tick==null:return
			if not bool(record.alive):
				record.status_effects=[]
				if sim.world.emit_event("party.exile_died",-1,int(str(record.former_member_id)),
						Vector2i(-1,-1),0,tick.id,{"reason":"OFFSCREEN_CONDITION"})==null:return
			next_tick+=EXILE_WORLD_INTERVAL
		if processed:
			record.last_world_time=str(sim.world.world_time);record.last_world_step=str(sim.world.step_index)
			state.exile_records[index]=record;state.revision+=1


func exile_encounter_evaluation(entity_id:int)->Dictionary:
	var record=_exile_record_for_member(entity_id)
	if record==null:return {"eligible":false,"reason":"exile_record_not_found"}
	if not bool(record.alive):return {"eligible":false,"reason":"exile_actor_dead","action":"NONE"}
	if sim.world.step_index<int(str(record.encounter_eligible_after_step)):
		return {"eligible":false,"reason":"exile_encounter_too_early","action":"NONE"}
	var hostility:=clampi(int(record.relationship_snapshot.hostility) \
		+int(record.emotion_modifiers.resentment_delta/5),0,100)
	var fear:=clampi(int(record.relationship_snapshot.fear)+int(record.emotion_modifiers.fear_delta),0,100)
	var action:="HOSTILE" if hostility>=60 and fear<85 else ("AVOID" if fear>=60 else "DIALOGUE")
	return {"eligible":true,"reason":"ok","action":action,"hostility":hostility,"fear":fear,
		"former_member_id":entity_id,"identity":{"display_name":record.display_name,
			"species_id":record.species_id,"personality_summary":record.personality_summary.duplicate(true)}}.duplicate(true)


func _member_ids_with_presence(presence: String) -> Array:
	var ids: Array = []
	if sim == null or sim.world == null or sim.world.party_encounter == null: return ids
	var state = sim.world.party_encounter
	for entity_id in state.party_member_ids:
		if state.member(entity_id).presence == presence: ids.append(entity_id)
	return ids

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
	if _run_is_complete(): return _rejection_dto("run_complete")
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
	if _run_is_complete(): return _rejection_dto("run_complete")
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
		var role := str(card.role)
		var resolution_note := str(action.get("resolution_note", ""))
		rows.append({"actor_id": int(card.entity_id), "actor_name": str(card.display_name),
			"role":role, "roster_slot":int(card.roster_slot),
			"from_position": card.logical_position.duplicate(true), "source": str(action.source),
			"source_label": str(action.source_label), "source_color": str(action.source_color),
			"line_style": _overlay_line_style(str(action.source)),
			"marker_style": _overlay_marker_style(str(action.source)),
			"type": str(action.type), "type_label": str(action.type_label),
			"destination": action.destination.duplicate(true), "target_id": int(action.target_id),
			"target_position": action.target_position.duplicate(true), "reason": str(action.reason),
			"resolution_note":resolution_note,
			"speech_headline":_companion_speech_headline(str(action.type),
				str(action.source), resolution_note) if role == "COMPANION" else "",
			"speech_reason_summary":_companion_speech_reason_summary(str(action.type),
				str(action.source), resolution_note) if role == "COMPANION" else "",
			"automatic_suggestion": _overlay_suggestion(action.get("automatic_suggestion", null),
				card.logical_position) if str(action.source) == "OVERRIDE" else null})
	return rows.duplicate(true)


func companion_speech_bubbles() -> Array[Dictionary]:
	# This is a detached presentation projection of the current preview. It never
	# participates in save/load, replay, RNG, or authoritative simulation state.
	var bubbles: Array[Dictionary] = []
	for intent in turn_intent_overlays():
		if str(intent.get("role", "")) != "COMPANION": continue
		bubbles.append({"schema_version":1,
			"actor_id":int(intent.actor_id), "actor_name":str(intent.actor_name),
			"roster_slot":int(intent.roster_slot), "role":"COMPANION",
			"from_position":intent.from_position.duplicate(true),
			"source":str(intent.source), "action_type":str(intent.type),
			"headline":str(intent.speech_headline), "reason":str(intent.reason),
			"reason_summary":str(intent.speech_reason_summary),
			"resolution_note":str(intent.resolution_note)})
	bubbles.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.roster_slot) < int(b.roster_slot) \
			if int(a.roster_slot) != int(b.roster_slot) \
			else int(a.actor_id) < int(b.actor_id))
	return bubbles.duplicate(true)


func _companion_speech_headline(action_type: String, source: String,
		resolution_note: String) -> String:
	if action_type == "MELEE": return "공격할게."
	if action_type == "MOVE": return "이동할게."
	if source == "OVERRIDE" or resolution_note == "destination_conflict_suggested_hold":
		return "대기할게."
	return "엄호할게."


func _companion_speech_reason_summary(action_type: String, source: String,
		resolution_note: String) -> String:
	if source == "OVERRIDE": return "지시를 따라서"
	if resolution_note == "destination_conflict_suggested_hold": return "길이 겹쳐서"
	if action_type == "MELEE": return "적이 가까워서"
	if action_type == "MOVE": return "길이 열려서"
	return "자리를 지키려고"


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
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _command_targets_locked_exit(command):
		return _rejection_dto("exit_locked", null, null,
			_exploration_context(command))
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
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _position_is_locked_exit(goal):
		return _rejection_dto("exit_locked", null, null,
			{"action_type":"ROUTE", "destination":_position_wire_value(goal)})
	return _exploration_route.preview(goal)


func exploration_companion_follow_plan(route_value: Dictionary = {}) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return {"schema_version":1, "accepted":false,
			"reason":"session_not_initialized", "path":[], "companion_rows":[]}
	var route: Dictionary = route_value.duplicate(true) if not route_value.is_empty() \
		else _exploration_route.state()
	var path: Variant = route.get("path", [])
	if not bool(route.get("accepted", false)) or not path is Array or path.size() < 2:
		return {"schema_version":1, "accepted":false,
			"reason":str(route.get("reason", "route_preview_required")),
			"path":[], "companion_rows":[]}.duplicate(true)
	var state = sim.world.party_encounter
	var rows: Array = []
	var completed_steps := clampi(int(route.get("completed_steps", 0)), 0, path.size() - 1)
	var next_index := mini(path.size() - 1, completed_steps + 1)
	for member_id in state.party_member_ids:
		if member_id == state.protagonist_id: continue
		var member = state.member(member_id)
		if member == null or member.presence != "GROUPED" \
				or not sim.world.is_environment_exposed(member_id): continue
		var maxima := {"fire":0, "water":0, "electric":0, "poison":0, "total":0}
		for step in route.get("steps", []):
			if not step is Dictionary: continue
			for risk in step.get("member_risk_ceilings", []):
				if not risk is Dictionary or int(risk.get("entity_id", -1)) != member_id:
					continue
				for component in maxima.keys():
					maxima[component] = maxi(int(maxima[component]), int(risk.get(component, 0)))
		var entity = sim.world.entities[member_id]
		rows.append({"entity_id":member_id, "display_name":str(entity.display_name),
			"roster_slot":int(member.roster_slot), "species_id":str(entity.species_id),
			"source":"SUGGESTED", "mode":"FOLLOW_ROUTE",
			"from_position":path[completed_steps].duplicate(true),
			"next_position":path[next_index].duplicate(true),
			"goal":path[-1].duplicate(true), "path":path.duplicate(true),
			"component_maxima":maxima.duplicate(true),
			"max_total_risk":int(maxima.total)})
	rows.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.roster_slot) < int(b.roster_slot) if int(a.roster_slot) != int(b.roster_slot) \
			else int(a.entity_id) < int(b.entity_id))
	return {"schema_version":1, "accepted":true, "reason":"ok",
		"path":path.duplicate(true), "completed_steps":completed_steps,
		"next_position":path[next_index].duplicate(true),
		"companion_rows":rows}.duplicate(true)


func exploration_route_draft() -> Dictionary:
	return _exploration_route.draft()


func exploration_route_state() -> Dictionary:
	return _exploration_route.state()


func start_exploration_route(goal: Variant, plan_hash: String) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _position_is_locked_exit(goal):
		return _rejection_dto("exit_locked", null, null,
			{"action_type":"ROUTE", "destination":_position_wire_value(goal)})
	var result: Dictionary = _exploration_route.start(goal, plan_hash)
	if _run_is_complete(): _clear_run_completion_transients()
	return result


func continue_exploration_route() -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	var result: Dictionary = _exploration_route.continue_route()
	if _run_is_complete(): _clear_run_completion_transients()
	return result


func cancel_exploration_route() -> Dictionary:
	return _exploration_route.cancel()


func commit_exploration(command) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _command_targets_locked_exit(command):
		return _rejection_dto("exit_locked", null, null,
			_exploration_context(command))
	_exploration_route.cancel_for_direct_command()
	var result: Dictionary = _commit_exploration_one(command, false)
	if _run_is_complete(): _clear_run_completion_transients()
	return result


func _commit_exploration_one(command, preserve_route: bool) -> Dictionary:
	var preview := preview_exploration(command)
	if not preview.accepted: return preview
	var result = sim.step(command)
	if result.accepted:
		_advance_exile_world()
		command_journal.append({"kind":"exploration", "command":command.to_dict()})
	_clear_draft()
	if not preserve_route: _exploration_route.cancel_for_direct_command()
	return _result_dto(result, null, null, _exploration_context(command))

func preview_deployment(preset_id: String, companion_ids: Array) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	_deployment_plan = sim.preview_deployment(preset_id, companion_ids)
	var dto: Dictionary = deployment_draft()
	dto.erase("has_preview")
	return dto.duplicate(true)

func commit_deployment() -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	_exploration_route.cancel_for_direct_command()
	if _deployment_plan.is_empty(): return _rejection_dto("deployment_preview_required")
	var request = {"preset_id": _deployment_plan.get("preset_id", ""), "companion_ids": _deployment_plan.get("companion_ids", []).duplicate()}
	var result = sim.deploy_party(_deployment_plan)
	if result.accepted:
		_advance_exile_world()
		var wire_ids: Array = []; for companion_id in request.companion_ids: wire_ids.append(str(companion_id))
		command_journal.append({"kind":"deployment", "request":{"preset_id":str(request.preset_id), "companion_ids":wire_ids}})
		_deployment_plan.clear()
	return _result_dto(result)

func begin_turn(protagonist_action) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	_exploration_route.cancel_for_direct_command()
	var copied_action = _canonical_action_copy(protagonist_action)
	if copied_action == null: return _rejection_dto("invalid_party_action")
	var previous_action = _protagonist_draft
	var previous_overrides := _overrides.duplicate()
	var previous_fingerprint := _draft_fingerprint
	var previous_placeholder := _protagonist_placeholder
	_protagonist_draft = copied_action; _overrides.clear()
	_protagonist_placeholder = false
	_draft_fingerprint = JSON.stringify(sim.snapshot()).sha256_text()
	var preview := current_turn_preview()
	if not bool(preview.get("accepted", false)):
		_protagonist_draft = previous_action; _overrides = previous_overrides
		_draft_fingerprint = previous_fingerprint
		_protagonist_placeholder = previous_placeholder
	return preview


func prepare_auto_combat_plan() -> Dictionary:
	if _run_is_complete(): return _auto_planning_empty("run_complete")
	_exploration_route.cancel_for_direct_command()
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _auto_planning_empty("session_not_initialized")
	var state = sim.world.party_encounter
	if state.safe_phase != "ENGAGED" or not sim.world.is_settled():
		return _auto_planning_empty("party_turn_phase_required")
	if _protagonist_draft != null:
		if _draft_fingerprint == JSON.stringify(sim.snapshot()).sha256_text():
			return auto_combat_planning_state()
		_clear_draft()
	_protagonist_draft = ActionScript.hold(state.protagonist_id)
	_overrides.clear()
	_protagonist_placeholder = true
	_draft_fingerprint = JSON.stringify(sim.snapshot()).sha256_text()
	return auto_combat_planning_state()


func auto_combat_planning_state() -> Dictionary:
	if _run_is_complete(): return _auto_planning_empty("run_complete")
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _auto_planning_empty("session_not_initialized")
	if _protagonist_draft == null:
		return _auto_planning_empty("turn_draft_required")
	var preview: Dictionary = current_turn_preview()
	if _protagonist_draft == null:
		return _auto_planning_empty(str(preview.get("reason", "stale_turn_draft")))
	var accepted := bool(preview.get("accepted", false))
	var override_ids: Array = _overrides.keys(); override_ids.sort()
	return {"schema_version":1, "active":true, "accepted":accepted,
		"reason":str(preview.get("reason", "ok")),
		"placeholder":_protagonist_placeholder,
		"protagonist_action_selected":not _protagonist_placeholder,
		"commit_ready":accepted and not _protagonist_placeholder,
		"plan_hash":str(preview.get("plan_hash", "")),
		"overridden_companion_ids":override_ids.duplicate(),
		"preview":preview.duplicate(true)}.duplicate(true)


func replace_auto_combat_protagonist_action(protagonist_action) -> Dictionary:
	if _run_is_complete(): return _auto_planning_empty("run_complete")
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _auto_planning_empty("session_not_initialized")
	var state = sim.world.party_encounter
	if state.safe_phase != "ENGAGED" or not sim.world.is_settled():
		return _auto_planning_empty("party_turn_phase_required")
	var copied_action = _canonical_action_copy(protagonist_action)
	if copied_action == null or copied_action.actor_id != state.protagonist_id:
		return _auto_planning_empty("protagonist_action_required")
	var previous_action = _protagonist_draft
	var previous_overrides := _overrides.duplicate()
	var previous_fingerprint := _draft_fingerprint
	var previous_placeholder := _protagonist_placeholder
	_protagonist_draft = copied_action
	_protagonist_placeholder = false
	_draft_fingerprint = JSON.stringify(sim.snapshot()).sha256_text()
	var preview := current_turn_preview()
	if not bool(preview.get("accepted", false)):
		_protagonist_draft = previous_action; _overrides = previous_overrides
		_draft_fingerprint = previous_fingerprint
		_protagonist_placeholder = previous_placeholder
		var rejected := auto_combat_planning_state()
		rejected["accepted"] = false
		rejected["reason"] = str(preview.get("reason", "invalid_party_action"))
		rejected["rejected_preview"] = preview.duplicate(true)
		return rejected.duplicate(true)
	return auto_combat_planning_state()


func _auto_planning_empty(reason: String) -> Dictionary:
	return {"schema_version":1, "active":false, "accepted":false,
		"reason":reason, "placeholder":false,
		"protagonist_action_selected":false, "commit_ready":false,
		"plan_hash":"", "overridden_companion_ids":[], "preview":{}}.duplicate(true)

func override_companion(entity_id: int, action) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
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
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _protagonist_draft == null:
		return _rejection_dto("turn_draft_required", null, null,
			{"actor_id": entity_id, "action_type": "CLEAR_OVERRIDE"})
	_overrides.erase(entity_id); return current_turn_preview()

func current_turn_preview() -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _protagonist_draft == null: return _rejection_dto("turn_draft_required")
	if _draft_fingerprint != JSON.stringify(sim.snapshot()).sha256_text(): _clear_draft(); return _rejection_dto("stale_turn_draft")
	var request = _pending_turn_request()
	var preview: Dictionary = sim.preview_party_turn(request).to_dict().duplicate(true)
	return _feedback_dto(preview, _protagonist_draft, request)

func commit_turn() -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	_exploration_route.cancel_for_direct_command()
	if _protagonist_placeholder:
		return _rejection_dto("protagonist_action_required")
	var preview := current_turn_preview()
	if not bool(preview.get("accepted",false)): return preview
	var request = RequestScript.from_dict(preview.canonical_request)
	var plan_data := preview.duplicate(true)
	for facade_key in ["message", "reason_code", "reason_details", "visual_effect_schema_version",
			"visual_effects"]:
		plan_data.erase(facade_key)
	var plan = load("res://sim/party_turn_plan.gd").new(plan_data); var result = sim.step_party_turn(plan)
	if result.accepted:
		_advance_exile_world()
		command_journal.append({"kind":"party_turn", "request":preview.canonical_request.duplicate(true)})
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
	if member == null and _rescue_discovery_event_for(entity_id) != null:
		return _inspect_rescue_candidate(entity_id)
	if member == null or not sim.world.entities.has(entity_id):
		return _rejection_dto("party_member_not_found", null, null,
			{"action_type":"INSPECT_MEMBER","actor_id":entity_id})
	var entity = sim.world.entities[entity_id]
	var combatant = sim.world.combatant_states.get(entity_id)
	var life_state := str(combatant.life_state) if combatant != null else "DEAD"
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
	var personality_archetype_dto: Dictionary = {}
	if member.personality_profile != null:
		personality_profile = member.personality_profile.to_dict()
		personality_archetype_dto = personality_archetype(member.personality_profile)
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
		"life_state":life_state,
		"presence":str(member.presence),"active_party_member":entity_id in state.active_party_member_ids,
		"recruitable_member":member.presence == "RECRUITABLE",
		"exiled_member":member.presence == "EXILED",
		"logical_position":[logical.x,logical.y],
		"busy_until":int(member.busy_until),
		"remaining_time":maxi(0,int(member.busy_until)-int(sim.world.world_time)),
		"stress":int(member.stress),"readiness":readiness,"emotion":emotion,
		"override_state":override_state,"expected_action":expected_action,
		"element_exposure":compact_exposure,"current_exposure":full_exposure,
		"personality_profile":personality_profile,"personality_available":personality_profile != null,
		"personality_facets":personality_facets,"personality_archetype":personality_archetype_dto,
		"personality_note":"주인공은 생성형 성격 프로필을 사용하지 않습니다." \
			if personality_profile == null else "%s · 결정론적 성격 프로필" \
				% str(personality_archetype_dto.get("label","분류되지 않은 성향")),
		"species_affinity":AffinityRegistryScript.affinity_for(entity.species_id).to_dict(),
		"relation_rows":relation_rows,"exile_record":_exile_record_for_member(entity_id),
		"rescue_assessment":rescue_assessment(entity_id) \
			if member.presence=="RECRUITABLE" and life_state=="DOWNED" else {},
		"recruitment_assessment":recruitment_assessment(entity_id) \
			if member.presence=="RECRUITABLE" and _rescue_event_for(entity_id)!=null else {}}
	return _feedback_dto(dto, null, null,
		{"action_type":"INSPECT_MEMBER","actor_id":entity_id})


func _inspect_rescue_candidate(entity_id: int) -> Dictionary:
	if not sim.world.entities.has(entity_id):
		return _rejection_dto("party_member_not_found")
	var entity = sim.world.entities[entity_id]
	var story_state := rescue_story_state(entity_id)
	var profile = _rescue_personality_profile(entity_id)
	var facets: Array = []
	if profile != null:
		for row in profile.facet_rows:
			var labels: Array = PersonalityRegistryScript.LABELS.get(str(row.facet_id),
				["낮음","높음"])
			facets.append({"facet_id":str(row.facet_id),"value":int(row.base_value),
				"low_label":str(labels[0]),"high_label":str(labels[1])})
	var relation_rows: Array = []
	var hero_id := int(sim.world.party_encounter.protagonist_id)
	var relation: Dictionary = sim.relationships.effective_relation(entity_id,hero_id)
	if sim.world.entities.has(hero_id):
		relation_rows.append({"subject_id":hero_id,
			"subject_name":str(sim.world.entities[hero_id].display_name),
			"subject_species_id":str(sim.world.entities[hero_id].species_id),
			"trust":int(relation.get("trust",0)),"fear":int(relation.get("fear",0)),
			"hostility":int(relation.get("hostility",0)),
			"gratitude":int(relation.get("gratitude",0)),
			"grievance":int(relation.get("grievance",0)),
			"disposition":str(relation.get("disposition","NEUTRAL")),
			"species_base":relation.get("species_base",{}).duplicate(true),
			"personal":relation.get("personal",{}).duplicate(true)})
	var position: Vector2i = entity.position
	var archetype := personality_archetype(profile)
	var collapsed := story_state == "COLLAPSED_STORY"
	var dto := {"schema_version":PRESENTATION_SCHEMA_VERSION,"accepted":true,"reason":"ok",
		"entity_id":entity_id,"roster_slot":63,"role":"COMPANION",
		"display_name":str(entity.display_name),"health":int(entity.health),
		"max_health":int(entity.max_health),"alive":true,"kind":str(entity.kind),
		"tags":entity.tags.duplicate(),"species_id":str(entity.species_id),
		"faction_id":str(entity.faction_id),"status_ids":_combatant_status_ids(entity_id),
		"life_state":"DOWNED" if collapsed else "ACTIVE",
		"authoritative_life_state":str(sim.world.combatant_states[entity_id].life_state),
		"rescue_story_state":story_state,"presence":"WORLD_NPC",
		"active_party_member":false,"recruitable_member":true,"exiled_member":false,
		"logical_position":[position.x,position.y],"busy_until":int(sim.world.world_time),
		"remaining_time":0,"stress":0,
		"readiness":"도움 필요" if collapsed else "대화 가능",
		"emotion":{"icon":"!" if collapsed else "●",
			"label":"쓰러짐" if collapsed else "안정됨",
			"reason":"심한 상처로 움직이지 못합니다." if collapsed \
				else "상처를 안정화해 대화할 수 있습니다.","health_percent":
				int(entity.health*100/maxi(1,entity.max_health))},
		"override_state":"PENDING","expected_action":null,
		"element_exposure":{"applicable":false},"current_exposure":{"applicable":false},
		"personality_profile":profile.to_dict() if profile != null else null,
		"personality_available":profile != null,"personality_facets":facets,
		"personality_archetype":archetype,
		"personality_note":"%s · 결정론적 성격 프로필"%str(archetype.get("label","동료")),
		"species_affinity":AffinityRegistryScript.affinity_for(entity.species_id).to_dict(),
		"relation_rows":relation_rows,"exile_record":null,
		"rescue_assessment":rescue_assessment(entity_id) if collapsed else {},
		"recruitment_assessment":recruitment_assessment(entity_id) \
			if story_state in ["OFFER_READY","REJECTED"] else {}}
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
	var rows: Array[Dictionary] = []
	var start := maxi(0, sim.world.events.size()-clampi(limit,0,100))
	for index in range(start, sim.world.events.size()):
		var event = sim.world.events[index]
		rows.append({"event_id":event.id,"step_index":event.step_index,
			"world_time":event.world_time,"message":_event_message(event)})
	return rows.duplicate(true)

func save_session_json() -> String:
	return JSON.stringify({"session_format_version":SESSION_FORMAT_VERSION,
		"scenario_id":scenario_id,"world_seed":str(world_seed),
		"personality_seed":str(personality_seed),"snapshot":sim.snapshot(),
		"journal":command_journal.duplicate(true)})

func load_session_json(encoded: String) -> Dictionary:
	var decoded = JSON.parse_string(encoded)
	if not decoded is Dictionary:
		return _rejection_dto("invalid_party_session")
	var top_keys: Array = decoded.keys(); top_keys.sort()
	if top_keys != ["journal", "personality_seed", "scenario_id", "session_format_version", "snapshot", "world_seed"] \
			or not _integer(decoded.get("session_format_version")) \
			or int(decoded.session_format_version) != SESSION_FORMAT_VERSION \
			or not decoded.get("scenario_id") is String \
			or not VisualTestMapScript.has_scenario(str(decoded.scenario_id)) \
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
	var parsed_scenario_id := str(decoded.scenario_id)
	var replay = load("res://playtest/party_playtest_session.gd").new(
		parsed_world_seed, parsed_personality_seed, parsed_scenario_id)
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
			"roster":
				var operation: Dictionary = row.operation
				var entity_id := Int64CodecScript.parse(operation.entity_id,"roster member")
				match str(operation.action):
					"DISMISS": replay_result = replay.dismiss_companion(entity_id)
					"RECRUIT": replay_result = replay.recruit_companion(entity_id)
					"STABILIZE": replay_result = replay.stabilize_recruit_candidate(entity_id)
					"OFFER_RECRUIT": replay_result = replay.offer_recruitment(entity_id)
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
	scenario_id = parsed_scenario_id
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
			"roster":
				if keys != ["kind", "operation"] or not row.get("operation") is Dictionary:
					return "invalid_roster_journal"
				var operation_keys: Array = row.operation.keys(); operation_keys.sort()
				if operation_keys != ["action", "entity_id"] \
						or row.operation.get("action") not in ["DISMISS", "RECRUIT",
							"STABILIZE", "OFFER_RECRUIT"] \
						or not Int64CodecScript.is_canonical(row.operation.get("entity_id")) \
						or Int64CodecScript.parse(row.operation.entity_id,"roster member") <= 0:
					return "invalid_roster_journal"
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

func _clear_draft() -> void:
	_protagonist_draft = null; _overrides.clear(); _draft_fingerprint = ""
	_protagonist_placeholder = false


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


func _run_feature_id_at(position: Vector2i, progress: Dictionary) -> String:
	if bool(progress.get("available", false)):
		var exit_position: Variant = progress.get("exit_position", [])
		if exit_position is Array and exit_position.size() == 2 \
				and position == Vector2i(int(exit_position[0]), int(exit_position[1])):
			return str(progress.get("exit", {}).get("feature_id", ""))
		var entry_position: Variant = progress.get("entry_position", [])
		if entry_position is Array and entry_position.size() == 2 \
				and position == Vector2i(int(entry_position[0]), int(entry_position[1])):
			return "run_entry"
	return VisualTestMapScript.feature_id_at(scenario_id, position)


func _run_is_complete() -> bool:
	var progress := run_progress()
	return bool(progress.get("available", false)) and bool(progress.get("complete", false))


func _position_is_locked_exit(value: Variant) -> bool:
	var progress := run_progress()
	if not bool(progress.get("available", false)) \
			or bool(progress.get("exit", {}).get("open", false)):
		return false
	var parsed := _inspection_position(value)
	var exit_position: Variant = progress.get("exit_position", [])
	return bool(parsed.get("ok", false)) and exit_position is Array \
		and exit_position.size() == 2 and parsed.position == Vector2i(
			int(exit_position[0]), int(exit_position[1]))


func _command_targets_locked_exit(command: Variant) -> bool:
	return command != null and command is SimCommand \
		and int(command.type) == int(CommandScript.Type.MOVE) \
		and _position_is_locked_exit(command.position)


func _position_wire_value(value: Variant) -> Array:
	var parsed := _inspection_position(value)
	return [parsed.position.x, parsed.position.y] if bool(parsed.get("ok", false)) else []


func _clear_run_completion_transients() -> void:
	_deployment_plan.clear()
	_clear_draft()
	if _exploration_route != null: _exploration_route.clear()


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
	if reason in ["exit_locked", "run_complete", "run_restart_unavailable",
			"run_restart_not_ready", "run_restart_failed"]:
		return "RUN"
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
			"exit_locked":"적을 쓰러뜨리면 출구가 열립니다.",
			"run_complete":"이미 원정을 완료했습니다. 같은 원정을 다시 시작할 수 있습니다.",
			"run_restart_unavailable":"이 시나리오는 다시 시작할 원정이 없습니다.",
			"run_restart_not_ready":"원정을 완료하거나 실패한 뒤 다시 시작할 수 있습니다.",
			"run_restart_failed":"같은 원정을 다시 준비하지 못했습니다.",
			"personality_seed_unchanged":"새 성격을 만들려면 다른 성격 시드가 필요합니다.",
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
		"party_roster_unsafe_phase":"지금은 파티 편성을 바꿀 수 없습니다.",
		"protagonist_dismiss_forbidden":"주인공은 추방할 수 없습니다.",
		"companion_not_active":"현재 파티에 없는 동료입니다.",
		"companion_not_recruitable":"영입 후보가 아니거나 이미 떠난 인물입니다.",
		"companion_unavailable":"현재 영입하거나 추방할 수 없는 동료입니다.",
		"party_full":"파티가 가득 찼습니다.",
		"rescue_candidate_not_recruitable":"도울 수 있는 비적대 영입 후보가 아닙니다.",
		"rescue_candidate_unavailable":"이 인물은 현재 구조할 수 없는 상태입니다.",
		"rescue_candidate_too_far":"쓰러진 인물 옆으로 이동해야 안정화할 수 있습니다.",
		"rescue_already_completed":"이미 상처를 안정화했습니다.",
		"rescue_stabilization_failed":"안정화가 취소되어 이전 상태로 돌아갔습니다.",
		"recruitment_requires_rescue":"먼저 쓰러진 인물을 도와 안정화해야 합니다.",
		"recruitment_candidate_too_far":"영입을 제안하려면 그 인물 곁에 있어야 합니다.",
		"recruitment_offer_required":"구조한 인물에게는 수락 가능성을 확인한 뒤 영입을 제안하세요.",
		"recruitment_already_resolved":"이 영입 제안의 답은 이미 정해졌습니다.",
		"recruitment_resolution_failed":"영입 제안이 취소되어 이전 상태로 돌아갔습니다.",
		"invalid_roster_operation":"지원하지 않는 편성 변경입니다.",
		"party_roster_change_failed":"편성 변경이 취소되어 이전 상태로 돌아갔습니다.",
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
		"party.rescue_discovered": return "%s 심하게 다친 채 쓰러져 있다." % _subject(target)
		"party.npc_stabilized": return "%s %s 상처를 안정화해 목숨을 구했다." % [_subject(actor),_possessive(target)]
		"party.recruitment_accepted":
			return "%s 영입 제안을 받아들였다. (수락 %d%% · 판정 %d)" % [
				_subject(actor),int((event.data.get("probability_milli",0)+5)/10),
				int(event.data.get("roll_milli",-1))]
		"party.recruitment_refused":
			return "%s 영입 제안을 거절했다. (수락 %d%% · 판정 %d)" % [
				_subject(actor),int((event.data.get("probability_milli",0)+5)/10),
				int(event.data.get("roll_milli",-1))]
		"relationship.aid_recorded": return "%s 구조받은 일을 고마운 기억으로 남겼다." % _subject(actor)
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
		"party.companion_dismissed":
			if str(event.data.get("condition_band",""))=="ENDANGERED":
				return "%s 부상당한 채 버려져 깊은 원한을 품었다."%_subject(target)
			if str(event.data.get("condition_band",""))=="STRAINED":
				return "%s 힘겨운 상태에서 추방되어 원한을 품었다."%_subject(target)
			return "%s 파티에서 영구히 추방되어 원망을 품었다."%_subject(target)
		"party.companion_recruited": return "%s 파티에 새로 합류했다." % _subject(target)
		"party.exile_world_tick":
			if str(event.data.get("behavior",""))=="SELF_TREAT":return "%s 홀로 상처를 돌보며 버텼다."%_subject(target)
			if str(event.data.get("behavior",""))=="RECOVER":return "%s 안전한 곳에서 몸을 추슬렀다."%_subject(target)
			return "%s 살아남기 위해 안전한 곳을 찾았다."%_subject(target)
		"party.exile_died": return "%s 홀로 버티지 못하고 숨졌다."%_subject(target)
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
func _position_key(position:Vector2i)->String:return "%d:%d"%[position.x,position.y]
func _actor_facing(entity_id:int,is_enemy:bool)->Vector2i:
	var state=sim.world.party_encounter
	var facing:Vector2i=state.facing if state!=null else Vector2i.RIGHT
	return -facing if is_enemy else facing
func _subject(value:String)->String: return value + ("이" if _has_final(value) else "가")
func _object(value:String)->String: return value + ("을" if _has_final(value) else "를")
func _topic(value:String)->String: return value + ("은" if _has_final(value) else "는")
func _possessive(value:String)->String: return value + ("의")
func _has_final(value:String)->bool:
	if value.is_empty(): return false
	var code := value.unicode_at(value.length()-1); return code >= 0xAC00 and code <= 0xD7A3 and (code-0xAC00)%28 != 0
