class_name NpcExpeditionSimulator
extends RefCounted

const MAP_WIDTH := 15
const MAP_HEIGHT := 13
const ENTRY := Vector2i(1, 11)
const PREPARE_TURNS := 2
const RECOVERY_PER_TURN := 30
const MAX_LOG_ROWS := 96
const MONSTER_COUNT_MIN := 1
const MONSTER_COUNT_MAX := 3
const MONSTER_ACTION_BUDGET_PER_TURN := 100
const MAX_MONSTER_ACTIONS_PER_RESPONSE := 3
const MONSTER_MOVE_COSTS := [70, 100, 130]
const MONSTER_ATTACK_COSTS := [80, 110, 140]

const SimulatorScript = preload("res://sim/simulator.gd")
const CommandScript = preload("res://sim/sim_command.gd")
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const HexacoScript = preload("res://sim/dungeon_population/hexaco_profile.gd")
const InventoryStateScript = preload("res://sim/inventory_state.gd")
const AmmoPoolStateScript = preload("res://sim/ammo_pool_state.gd")
const WeaponRuntimeStateScript = preload("res://sim/weapon_runtime_state.gd")
const WorldItemOperationsScript = preload("res://sim/world_item_operations.gd")
const ItemRegistryScript = preload("res://sim/item_registry.gd")
const DecisionRegistryScript = preload("res://sim/decision_ruleset_registry.gd")
const EnemyAwarenessScript = preload("res://sim/enemy_awareness_state.gd")
const EnemyPerceptionScript = preload("res://sim/enemy_perception_registry.gd")
const CombatProfileRegistryScript = preload("res://sim/combat_profile_registry.gd")

const PHASE_LABELS := {
	"TOWN_PREPARE": "마을 · 원정 준비",
	"DUNGEON_ENTER": "던전 · 진입",
	"DUNGEON_EXPLORE": "던전 · 탐색",
	"DUNGEON_COMBAT": "던전 · 전투",
	"DUNGEON_LOOT": "던전 · 전리품 회수",
	"DUNGEON_RETURN": "던전 · 귀환",
	"TOWN_RECOVER": "마을 · 치료와 정산",
	"DEAD": "원정 실패 · 사망",
}

const ACTION_LABELS := {
	"PREPARE": "보급을 점검한다",
	"ENTER": "던전에 들어간다",
	"APPROACH": "목표를 향해 탐색한다",
	"ATTACK": "몬스터를 공격한다",
	"FINISH": "쓰러진 몬스터를 마무리한다",
	"USE_ITEM": "회복 물약을 사용한다",
	"LOOT": "전리품을 회수한다",
	"RETURN": "출구로 귀환한다",
	"RECOVER": "마을에서 치료한다",
	"WAIT": "상황을 지켜본다",
}

var seed: int = 1
var turn_index: int = 0
var completed_cycles: int = 0
var phase := "TOWN_PREPARE"
var location := "TOWN"
var prepare_turns_left := PREPARE_TURNS
var loot_banked := 0
var kills := 0
var simulator
var npc_id := -1
var monster_id := -1
var monster_ids: Array[int] = []
var monster_traits: Dictionary = {}
var monster_awareness: Dictionary = {}
var profile
var recent_action_id := ""
var current_action_id := ""
var commitment_until_turn := 0
var action_cooldown_until: Dictionary = {}
var last_decision: Dictionary = {}
var logs: Array[Dictionary] = []
var _dungeon_generation := 0
var _rewarded_monster_ids: Dictionary = {}
var _last_npc_life_state := "ACTIVE"
var _scenario_override: Dictionary = {}


func _init(p_seed: int = 1, p_scenario_override: Dictionary = {}) -> void:
	_scenario_override = p_scenario_override.duplicate(true)
	reset(p_seed)


func reset(p_seed: int = 1) -> Dictionary:
	seed = p_seed
	turn_index = 0
	completed_cycles = 0
	phase = "TOWN_PREPARE"
	location = "TOWN"
	prepare_turns_left = PREPARE_TURNS
	loot_banked = 0
	kills = 0
	recent_action_id = ""
	current_action_id = ""
	commitment_until_turn = 0
	action_cooldown_until.clear()
	last_decision.clear()
	logs.clear()
	_dungeon_generation = 0
	profile = HexacoScript.generated(seed, 1)
	_bootstrap_dungeon()
	var supplied: Dictionary = WorldItemOperationsScript.commit_grant(simulator.world,
		npc_id, "POTION_HEALING", 2, ENTRY, "NPC_INITIAL_SUPPLY")
	if not bool(supplied.get("accepted", false)):
		return {"accepted": false, "reason": str(supplied.get("reason", "item_supply_failed"))}
	_last_npc_life_state = _life_state(npc_id)
	_log("CYCLE", "아린이 마을에서 첫 원정을 준비하기 시작했다.")
	return {"accepted": true, "reason": "ok", "seed": str(seed)}


func step() -> Dictionary:
	if phase == "DEAD":
		return {"accepted": false, "reason": "npc_dead"}
	turn_index += 1
	var event_start: int = simulator.world.events.size()
	var decision := decision_breakdown()
	var selected := str(decision.get("selected_action_id", "WAIT"))
	var downed_wait := selected == "WAIT" and location == "DUNGEON" \
		and _life_state(npc_id) == "DOWNED"
	# An unconscious NPC must not advance the lifecycle clock before nearby
	# enemies receive their response window; otherwise DOWNED always recovers
	# before a pursuer can deliver a finisher.
	var accepted := true if downed_wait else _execute(selected)
	if not accepted and phase != "DEAD":
		# A rejected action must still spend the turn; otherwise a time-gated
		# blocker (recovery lock, transient occupancy) can never clear.
		_log("STALL", "%s 행동이 거부되어 잠시 상황을 지켜본다." % str(ACTION_LABELS.get(selected, selected)))
		_advance_time()
	last_decision = decision.duplicate(true)
	last_decision["resolved_turn"] = str(turn_index)
	last_decision["accepted"] = accepted
	if accepted:
		_commit_decision(selected)
	if accepted and location == "DUNGEON" and phase != "DEAD" \
			and selected != "ENTER":
		_monster_response()
	if downed_wait and _life_state(npc_id) == "DOWNED":
		accepted = _advance_time()
		last_decision["accepted"] = accepted
	_reconcile_monster_deaths(event_start)
	_reconcile_life()
	return {"accepted": accepted, "reason": "ok" if accepted else "action_failed",
		"turn_index": str(turn_index), "action_id": selected,
		"phase": phase, "observation": observation()}


func decision_breakdown() -> Dictionary:
	var candidates: Array[Dictionary] = []
	match phase:
		"TOWN_PREPARE":
			candidates.append(_candidate("PREPARE", true, 1000,
				"다음 원정을 위해 장비와 소모품을 확인한다.", []))
		"DUNGEON_ENTER":
			candidates.append(_candidate("ENTER", true, 1000,
				"준비가 끝났고 원정지가 정해졌다.", []))
		"TOWN_RECOVER":
			candidates.append(_candidate("RECOVER", true, 1000,
				"마을은 안전하며 부상과 전리품을 정리할 수 있다.", []))
		"DEAD":
			candidates.append(_candidate("WAIT", true, 1000,
				"사망해 더는 행동할 수 없다.", []))
		_:
			candidates = _dungeon_candidates()
	var selected := _select_candidate(candidates)
	var switch_evidence: Dictionary = selected.get("switch_evidence", {}).duplicate(true)
	for row in candidates:
		row["selected"] = str(row.action_id) == str(selected.get("action_id", ""))
	return {"turn_index": str(turn_index + 1), "phase": phase,
		"ruleset_id": DecisionRegistryScript.EXPEDITION_RULESET_ID,
		"selected_action_id": str(selected.get("action_id", "WAIT")),
		"selected_label": str(selected.get("label", ACTION_LABELS.WAIT)),
		"selected_reason": str(selected.get("reason", "행동 가능한 선택지를 확인했다.")),
		"switch_evidence": switch_evidence,
		"candidates": candidates.duplicate(true)}


func observation() -> Dictionary:
	var npc = _npc()
	var monster = _monster()
	var npc_life := _life_state(npc_id)
	var monster_life := _life_state(monster_id)
	var current_decision := decision_breakdown()
	var monster_rows := _monster_observation_rows()
	var target_row := _monster_observation_row(monster_id)
	return {
		"schema_version": 1,
		"seed": str(seed),
		"turn_index": str(turn_index),
		"world_time": str(simulator.world.world_time),
		"completed_cycles": completed_cycles,
		"expedition_number": completed_cycles + 1,
		"phase": phase,
		"phase_label": str(PHASE_LABELS.get(phase, phase)),
		"location": location,
		"goal": _goal_text(),
		"map_size": [MAP_WIDTH, MAP_HEIGHT],
		"terrain_rows": _terrain_rows(),
		"entry": [ENTRY.x, ENTRY.y],
		"npc": {
			"entity_id": str(npc_id), "name": "아린", "species_id": "human",
			"glyph": "@", "position": _position_array(npc.position) if npc != null else [-1, -1],
			"visible": location == "DUNGEON", "hp": npc.health if npc != null else 0,
			"max_hp": npc.max_health if npc != null else 100, "life_state": npc_life,
			"hexaco": profile.to_dict(), "style": profile.style_summary(),
			"weapon": "기본 근접", "potions": _item_quantity("POTION_HEALING"),
			"carried_loot": _item_quantity("MATERIAL_UNSPECIFIED"),
		},
		"monster": target_row if not target_row.is_empty() else {
			"entity_id": str(monster_id), "name": "감염된 고블린", "glyph": "g",
			"position": _position_array(monster.position) if monster != null else [-1, -1],
			"visible": false, "hp": 0, "max_hp": 1, "life_state": monster_life,
			"move_cost": 100, "attack_cost": 100, "awareness_state": "UNAWARE"},
		"monsters": monster_rows,
		"monster_count": monster_ids.size(),
		"active_monster_count": _monster_count_in_state("ACTIVE"),
		"downed_monster_count": _monster_count_in_state("DOWNED"),
		"threat_milli": _perceived_threat_milli(),
		"corpses": _corpse_rows(),
		"ground_items": _ground_rows(),
		"inventory_labels": _inventory_labels(),
		"loot_banked": loot_banked,
		"kills": kills,
		"decision": current_decision,
		"last_decision": last_decision.duplicate(true),
		"recent_events": recent_logs(8),
	}.duplicate(true)


func recent_logs(limit: int = 16) -> Array:
	var start := maxi(0, logs.size() - clampi(limit, 0, MAX_LOG_ROWS))
	return logs.slice(start, logs.size()).duplicate(true)


func _dungeon_candidates() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var npc = _npc()
	if npc == null or _life_state(npc_id) != "ACTIVE":
		rows.append(_candidate("WAIT", true, 1000, "쓰러져 있어 행동할 수 없다.", []))
		return rows
	if not simulator.world.can_act(npc_id, simulator.world.world_time):
		rows.append(_candidate("WAIT", true, 1000,
			"의식을 되찾은 직후라 아직 몸을 가누지 못한다.", []))
		return rows
	_refresh_target()
	var monster = _monster()
	var hp_milli := int(npc.health * 1000 / maxi(1, npc.max_health))
	var injury := 1000 - hp_milli
	var carried := _item_quantity("MATERIAL_UNSPECIFIED")
	var target_life := _life_state(monster_id) if monster != null else "MISSING"
	var target_downed := target_life == "DOWNED"
	var target_distance := _distance(npc.position, monster.position) if monster != null else 99
	var active_count := _monster_count_in_state("ACTIVE")
	var threat := _perceived_threat_milli()
	# This is intentionally an estimate, not a combat roll: decision inspection
	# must be repeatable and must not advance the world's random stream.
	var outlook := _combat_outlook_milli(npc, monster)
	var caution_pressure := int(injury * int(profile.value("C")) / 1000)
	var potion_urgency := clampi(injury + int(threat / 4) + int(caution_pressure / 4), 0, 1000)
	var carried_milli := clampi(carried * 350, 0, 1000)
	# Mere awareness is not a completed expedition's reason to turn around.
	# Threat only creates a retreat need after it crosses a sustained-danger
	# threshold; injury and secured loot can still justify a cautious exit.
	var retreat_need := clampi(maxi(0, threat - 400) + int(injury * 7 / 10)
		+ int(carried_milli * 4 / 10), 0, 1000)
	var retreat_safe_need := int(retreat_need * int(outlook.retreat_viability) / 1000)
	var fear_pressure := int(threat * int(profile.value("E")) / 1000)
	var unresolved_count := _unresolved_monster_ids().size()
	var ground = _ground_ref()
	var mission_complete := 1000 if unresolved_count == 0 and ground.rows.is_empty() else 0
	var mission_incomplete := 1000 if unresolved_count > 0 and carried == 0 else 0
	var fast_pursuer_count := 0
	for id in monster_ids:
		var traits: Dictionary = monster_traits.get(id, {})
		if _life_state(id) == "ACTIVE" and int(traits.get("move_cost", 100)) <= 80 \
				and int(traits.get("attack_cost", 110)) <= 80:
			fast_pursuer_count += 1
	var return_necessary := unresolved_count == 0 or carried > 0 or injury >= 500 \
		or (threat >= 1000 and fast_pursuer_count >= 3) or phase == "DUNGEON_RETURN"
	var inputs := {
		"context.injury": injury,
		"context.threat": threat,
		"context.target_distance": clampi(target_distance * 100, 0, 1000),
		"context.target_downed": 1000 if target_downed else 0,
		"context.potion_urgency": potion_urgency,
		"context.loot_available": 1000 if not ground.rows.is_empty() else 0,
		"context.carried_loot": carried_milli,
		"context.combat_viability": int(outlook.combat_viability),
		"context.retreat_viability": int(outlook.retreat_viability),
		"context.target_finish_window": int(outlook.target_finish_window),
		"context.retreat_need": retreat_need,
		"context.retreat_safe_need": retreat_safe_need,
		"context.fear_pressure": fear_pressure,
		"context.mission_complete": mission_complete,
		"context.mission_incomplete": mission_incomplete,
		"facet.H": int(profile.value("H")), "facet.E": int(profile.value("E")),
		"facet.X": int(profile.value("X")), "facet.A": int(profile.value("A")),
		"facet.C": int(profile.value("C")), "facet.O": int(profile.value("O")),
	}
	rows.append(_utility_candidate("USE_ITEM",
		_item_quantity("POTION_HEALING") > 0 and npc.health < npc.max_health,
		"부상·주변 위협·신중함이 물약 사용 임계를 넘는지 판단한다.", inputs))
	rows.append(_utility_candidate("RETURN", location == "DUNGEON" and return_necessary,
		"부상, 전리품, 적의 수와 속도를 합쳐 철수 위험을 판단한다.", inputs))
	rows.append(_utility_candidate("LOOT", active_count == 0 and monster == null \
		and not ground.rows.is_empty(),
		"움직이는 위협이 사라져 바닥의 전리품을 회수할 수 있다.", inputs))
	rows.append(_utility_candidate("FINISH", target_downed and target_distance <= 1,
		"목표가 쓰러져 있어 마무리하면 처치와 전리품을 확정할 수 있다.", inputs))
	rows.append(_utility_candidate("ATTACK", phase != "DUNGEON_RETURN" \
		and target_life == "ACTIVE" and target_distance <= 1,
		"활동 중인 목표가 공격 범위 안에 있다.", inputs))
	rows.append(_utility_candidate("APPROACH", phase != "DUNGEON_RETURN" \
		and monster != null and target_distance > 1,
		"목표까지의 거리와 주변 위협을 비교하며 접근한다.", inputs))
	return rows


func _candidate(action_id: String, legal: bool, score: int, reason: String,
		terms: Array) -> Dictionary:
	var copied_terms: Array = terms.duplicate(true)
	var disclosed_total := 0
	for term_value in copied_terms:
		if term_value is Dictionary:
			disclosed_total += int(term_value.get("value", 0))
	if disclosed_total != score:
		copied_terms.push_front({"factor": "기본값", "value": score - disclosed_total})
	return {"action_id": action_id, "label": str(ACTION_LABELS.get(action_id, action_id)),
		"legal": legal, "score": score if legal else -1, "reason": reason,
		"terms": copied_terms, "tie_break_rank": 1000, "selected": false}


func _utility_candidate(action_id: String, legal: bool, reason: String,
		inputs: Dictionary) -> Dictionary:
	var definition = DecisionRegistryScript.expedition_action(action_id)
	if definition == null:
		return _candidate(action_id, false, -1, "원정 규칙이 등록되지 않았다.", [])
	var cooldown_until := int(action_cooldown_until.get(action_id, 0))
	var cooldown_blocked := action_id != current_action_id and cooldown_until > turn_index
	var evaluated: Dictionary = DecisionRegistryScript.evaluate(definition, inputs)
	var terms: Array = [{"factor": "기본값", "value": int(evaluated.base_score)}]
	for row_value in evaluated.considerations:
		var row: Dictionary = row_value
		terms.append({"factor": _factor_label(str(row.consideration_id)),
			"value": int(row.contribution), "input_id": str(row.input_id),
			"raw_input": int(row.raw_input), "curve_id": str(row.curve_id)})
	return {"action_id": action_id, "label": str(ACTION_LABELS.get(action_id, action_id)),
		"legal": legal and not cooldown_blocked,
		"score": int(evaluated.score) if legal and not cooldown_blocked else -1,
		"reason": "재사용 대기 중이다." if cooldown_blocked else reason,
		"terms": terms, "tie_break_rank": int(definition.tie_break_rank), "selected": false}


func _select_candidate(candidates: Array[Dictionary]) -> Dictionary:
	var challenger: Dictionary = {}
	for row in candidates:
		if not bool(row.get("legal", false)):
			continue
		if challenger.is_empty() or int(row.score) > int(challenger.score) \
				or (int(row.score) == int(challenger.score) \
				and int(row.tie_break_rank) < int(challenger.tie_break_rank)):
			challenger = row
	if challenger.is_empty():
		return _candidate("WAIT", true, 0, "가능한 행동이 없어 잠시 기다린다.", [])
	var selected: Dictionary = challenger
	var retained := false
	var reason_code := "entered"
	var current_score := -1000000
	var switch_margin := 0
	var current: Dictionary = {}
	for row in candidates:
		if str(row.action_id) == current_action_id:
			current = row
			break
	if not current.is_empty() and bool(current.legal):
		current_score = int(current.score)
		var definition = DecisionRegistryScript.expedition_action(current_action_id)
		switch_margin = int(definition.switch_margin) if definition != null else 0
		if commitment_until_turn > turn_index:
			selected = current
			retained = true
			reason_code = "retained_commitment"
		elif str(challenger.action_id) == current_action_id:
			retained = true
			reason_code = "continued_best"
		elif int(challenger.score) < current_score + switch_margin:
			selected = current
			retained = true
			reason_code = "retained_margin"
		else:
			reason_code = "switched"
	selected = selected.duplicate(true)
	selected["switch_evidence"] = {"previous_action": current_action_id,
		"challenger_action": str(challenger.action_id),
		"selected_action": str(selected.action_id), "current_score": current_score,
		"challenger_score": int(challenger.score), "switch_margin": switch_margin,
		"commitment_until_turn": commitment_until_turn, "retained": retained,
		"reason_code": reason_code}
	return selected


func _commit_decision(action_id: String) -> void:
	var next_definition = DecisionRegistryScript.expedition_action(action_id)
	if next_definition == null:
		current_action_id = ""
		commitment_until_turn = turn_index
		recent_action_id = action_id
		return
	if not current_action_id.is_empty() and current_action_id != action_id:
		var previous_definition = DecisionRegistryScript.expedition_action(current_action_id)
		if previous_definition != null and int(previous_definition.cooldown_duration) > 0:
			action_cooldown_until[current_action_id] = turn_index \
				+ int(previous_definition.cooldown_duration)
	if current_action_id != action_id:
		commitment_until_turn = turn_index + int(next_definition.commitment_duration)
	current_action_id = action_id
	recent_action_id = action_id


func _factor_label(consideration_id: String) -> String:
	var labels := {
		"approach.threat": "주변 위협", "approach.distance": "목표 거리",
		"approach.openness": "탐구성(O)", "approach.extraversion": "적극성(X)",
		"approach.mission_incomplete": "미완료 원정 목표", "approach.emotionality": "불안 민감도(E)",
		"attack.viability": "전투 생존 여유", "attack.finish_window": "목표 마무리 기회",
		"attack.boldness": "대담함(낮은 E)", "attack.hostility": "직선성(낮은 A)",
		"finish.downed": "마무리 기회", "finish.threat": "남은 위협",
		"finish.injury": "부상 부담", "finish.discipline": "신중함(C)",
		"item.urgency": "치료 임계", "item.threat": "주변 위협",
		"item.discipline": "신중함(C)", "loot.available": "회수 가능",
		"loot.threat": "남은 위협", "loot.pragmatism": "실리성(낮은 H)",
		"loot.curiosity": "탐구성(O)", "return.need": "철수 필요도",
		"return.need_and_escape": "실행 가능한 철수", "return.combat_deadly": "전투 불리",
		"return.fear_pressure": "위협 기반 불안(E)", "return.loot": "보유 전리품",
		"return.mission_complete": "원정 목표 완료",
		"return.agreeableness": "충돌 회피(A)", "return.downed": "마무리 기회",
	}
	return str(labels.get(consideration_id, consideration_id))


func _execute(action_id: String) -> bool:
	match action_id:
		"PREPARE": return _prepare()
		"ENTER": return _enter_dungeon()
		"APPROACH": return _approach_monster()
		"ATTACK": return _attack(npc_id, monster_id, "", "NPC")
		"FINISH": return _attack(npc_id, monster_id, "", "NPC")
		"USE_ITEM": return _use_healing_potion()
		"LOOT": return _loot()
		"RETURN": return _return_toward_town()
		"RECOVER": return _recover_in_town()
		"WAIT": return _advance_time()
	return false


func _prepare() -> bool:
	prepare_turns_left = maxi(0, prepare_turns_left - 1)
	_restock_potion_if_needed()
	_log("PREPARE", "장비와 회복 물약을 점검했다. 준비 %d/%d." % [
		PREPARE_TURNS - prepare_turns_left, PREPARE_TURNS])
	if prepare_turns_left == 0:
		phase = "DUNGEON_ENTER"
	return _advance_time()


func _enter_dungeon() -> bool:
	if completed_cycles > 0:
		_bootstrap_dungeon()
	location = "DUNGEON"
	phase = "DUNGEON_EXPLORE"
	_log("ENTER", "아린이 던전 입구를 통과했다. 감염체의 흔적을 찾는다.")
	return _advance_time()


func _approach_monster() -> bool:
	var npc = _npc()
	var monster = _monster()
	if npc == null or monster == null:
		return false
	var goals := _open_neighbors(monster.position, npc_id)
	var route: Dictionary = simulator.pathfinder.find_path_to_any(npc_id, goals)
	if not bool(route.get("found", false)) or int(route.get("steps", 0)) < 1:
		_log("BLOCKED", "목표로 가는 길을 찾지 못해 출구로 방향을 바꿨다.")
		phase = "DUNGEON_RETURN"
		return true
	var destination: Vector2i = route.path[1]
	var moved: Variant = simulator.step(CommandScript.move_to(npc_id, destination))
	if not moved.accepted:
		return false
	phase = "DUNGEON_COMBAT" if _distance(destination, monster.position) <= 1 \
		else "DUNGEON_EXPLORE"
	_log("MOVE", "아린이 %s로 이동했다. 목표까지 %d칸." % [
		_position_text(destination), _distance(destination, monster.position)])
	return true


func _attack(attacker_id: int, target_id: int, weapon_id: String, side: String,
		advance_time_after: bool = true) -> bool:
	var attacker = simulator.world.entities.get(attacker_id)
	var target = simulator.world.entities.get(target_id)
	if attacker == null or target == null:
		return false
	var processed_step: int = int(simulator.world.step_index) + 1
	var assessment: Dictionary = simulator.melee.assess_attack(attacker_id, target_id,
		"DIRECT", processed_step, simulator.world.world_time,
		"PARTY_TURN/%d" % processed_step, 0, weapon_id)
	if assessment.is_empty():
		return false
	var frozen = simulator.melee.freeze_assessment(assessment, target.health, 0)
	var projected: Array = simulator.melee.project_batch([frozen])
	if projected.size() != 1:
		return false
	var resolution = projected[0]
	var rollback: Variant = simulator.capture_rollback_memento()
	if not rollback is Dictionary or rollback.is_empty():
		return false
	simulator.world.begin_step(processed_step)
	var action = simulator.world.emit_event("action.melee_attack", attacker_id, target_id,
		target.position, int(assessment.base_damage), -1, resolution.action_data)
	if action == null:
		simulator.restore_rollback_memento(rollback)
		return false
	var applied_ok := true
	if resolution.outcome in ["MISS", "PARRIED"]:
		var result_event_type := "combat.attack_parried" if resolution.outcome == "PARRIED" \
			else "combat.attack_missed"
		applied_ok = simulator.world.emit_event(result_event_type, -1, target_id,
			target.position, 0, action.id, {"schema_version": 1,
				"combat_ruleset_id": simulator.melee.COMBAT_RULESET_ID,
				"outcome": str(resolution.outcome)}) != null
	elif resolution.outcome == "FINISHER":
		var finished: Dictionary = simulator.damage.apply_canonical_downed_finisher(target,
			int(frozen.assessment.normal_final_damage), action.id, target.position, processed_step)
		applied_ok = bool(finished.get("accepted", false))
	else:
		var applied: Dictionary = simulator.damage.apply_canonical_active_damage(target,
			int(resolution.final_damage), "physical", action.id, target.position,
			processed_step, int(resolution.target_health_before), false,
			bool(resolution.bleed_proc_succeeded))
		applied_ok = bool(applied.get("accepted", false))
	if not applied_ok:
		simulator.restore_rollback_memento(rollback)
		return false
	if target.health != int(resolution.target_health_after) \
			or _life_state(target_id) != str(resolution.target_life_after):
		simulator.restore_rollback_memento(rollback)
		return false
	simulator.world.finish_step()
	var attacker_name := str(attacker.display_name)
	var target_name := str(target.display_name)
	var result_text := "빗나갔다" if resolution.outcome in ["MISS", "PARRIED"] \
		else ("마무리했다" if resolution.outcome == "FINISHER" \
		else "%d 피해를 입혔다" % int(resolution.final_damage))
	_log("COMBAT", "%s이(가) %s을(를) 공격해 %s." % [attacker_name, target_name, result_text])
	if side == "NPC" and target_id in monster_ids:
		_alert_monsters_from_combat(target_id)
		phase = "DUNGEON_COMBAT"
	return _advance_time() if advance_time_after else true


func _use_healing_potion() -> bool:
	var instance_id := _first_item_instance("POTION_HEALING")
	var npc = _npc()
	if instance_id.is_empty() or npc == null or npc.health >= npc.max_health:
		return false
	var preview: Dictionary = WorldItemOperationsScript.preview_use(
		simulator.world, npc_id, instance_id)
	if not bool(preview.get("accepted", false)):
		return false
	var restored := mini(ItemRegistryScript.HEALING_POTION_RESTORE, npc.max_health - npc.health)
	var processed_step: int = int(simulator.world.step_index) + 1
	var rollback: Variant = simulator.capture_rollback_memento()
	if not rollback is Dictionary or rollback.is_empty():
		return false
	simulator.world.begin_step(processed_step)
	var used: Dictionary = WorldItemOperationsScript.commit_use(simulator.world,
		npc_id, instance_id, npc.position, 0)
	if not bool(used.get("accepted", false)):
		simulator.restore_rollback_memento(rollback)
		return false
	if not _commit_health_restored(npc, restored, int(used.event_id),
			"healing-potion-v1", "POTION"):
		simulator.restore_rollback_memento(rollback)
		return false
	simulator.world.finish_step()
	_log("ITEM", "아린이 회복 물약을 사용해 HP %d를 회복했다." % restored)
	return _advance_time()


func _loot() -> bool:
	var position := _reachable_ground_item_position()
	var npc = _npc()
	var ground = _ground_ref()
	if position == Vector2i(-1, -1) or npc == null:
		return false
	if npc.position != position:
		var route: Dictionary = simulator.pathfinder.find_path(npc_id, position)
		if not bool(route.get("found", false)) or int(route.get("steps", 0)) < 1:
			return false
		var moved: Variant = simulator.step(CommandScript.move_to(npc_id, route.path[1]))
		if not moved.accepted:
			return false
		_log("MOVE", "아린이 전리품이 떨어진 %s로 이동했다." % _position_text(route.path[1]))
		return true
	var instance_id := ""
	for row in ground.rows:
		if row.position == position:
			instance_id = str(row.item.instance_id)
			break
	if instance_id.is_empty():
		return false
	var preview: Dictionary = WorldItemOperationsScript.preview_pickup(
		simulator.world, npc_id, instance_id, npc.position)
	if not bool(preview.get("accepted", false)):
		return false
	var processed_step: int = int(simulator.world.step_index) + 1
	var rollback: Variant = simulator.capture_rollback_memento()
	if not rollback is Dictionary or rollback.is_empty():
		return false
	simulator.world.begin_step(processed_step)
	var picked: Dictionary = WorldItemOperationsScript.commit_pickup(simulator.world,
		npc_id, instance_id, npc.position, 0)
	if not bool(picked.get("accepted", false)):
		simulator.restore_rollback_memento(rollback)
		return false
	simulator.world.finish_step()
	ground = _ground_ref()
	phase = "DUNGEON_LOOT" if not ground.rows.is_empty() else "DUNGEON_RETURN"
	_log("LOOT", "아린이 감염체의 전리품을 회수했다.%s" % (
		" 남은 전리품도 확인한다." if not ground.rows.is_empty() else " 이제 출구로 돌아간다."))
	return _advance_time()


func _return_toward_town() -> bool:
	phase = "DUNGEON_RETURN"
	var npc = _npc()
	if npc == null:
		return false
	if npc.position == ENTRY:
		_arrive_town()
		return _advance_time()
	var route: Dictionary = simulator.pathfinder.find_path(npc_id, ENTRY)
	if not bool(route.get("found", false)) or int(route.get("steps", 0)) < 1:
		return false
	var moved: Variant = simulator.step(CommandScript.move_to(npc_id, route.path[1]))
	if not moved.accepted:
		return false
	_log("MOVE", "아린이 출구 쪽 %s로 이동했다. 남은 거리 %d칸." % [
		_position_text(route.path[1]), _distance(route.path[1], ENTRY)])
	if route.path[1] == ENTRY:
		_arrive_town()
	return true


func _arrive_town() -> void:
	location = "TOWN"
	phase = "TOWN_RECOVER"
	var deposited := _deposit_loot()
	_log("RETURN", "아린이 마을로 귀환했다.%s" % (
		" 전리품 %d개를 창고에 맡겼다." % deposited if deposited > 0 else ""))


func _recover_in_town() -> bool:
	var npc = _npc()
	if npc == null:
		return false
	var restored: int = mini(RECOVERY_PER_TURN, int(npc.max_health) - int(npc.health))
	if restored > 0:
		var processed_step: int = int(simulator.world.step_index) + 1
		var rollback: Variant = simulator.capture_rollback_memento()
		if not rollback is Dictionary or rollback.is_empty():
			return false
		simulator.world.begin_step(processed_step)
		if not _commit_health_restored(npc, restored, -1, "npc-town-recovery-v1", "TOWN"):
			simulator.restore_rollback_memento(rollback)
			return false
		simulator.world.finish_step()
	_log("RECOVER", "마을에서 치료를 받았다. HP +%d." % restored)
	var advanced := _advance_time()
	if npc.health >= npc.max_health:
		completed_cycles += 1
		phase = "TOWN_PREPARE"
		prepare_turns_left = PREPARE_TURNS
		_log("CYCLE", "%d번째 원정을 마쳤다. 다음 원정을 준비한다." % completed_cycles)
	return advanced


func _commit_health_restored(entity, amount: int, cause_id: int, ruleset_id: String,
		kind: String) -> bool:
	# Healing never writes entity.health silently: the world replays HP from the
	# event ledger after a DOWNED->recovered transition, so every restoration is
	# a canonical health.restored leaf that discloses the resulting HP.
	if entity == null or amount <= 0 or int(entity.health) + amount > int(entity.max_health):
		return false
	var health_after: int = int(entity.health) + amount
	var event = simulator.world.emit_event("health.restored", entity.id, entity.id,
		entity.position, amount, cause_id, {"schema_version": 1, "ruleset_id": ruleset_id,
			"kind": kind, "health_after": health_after})
	if event == null:
		return false
	entity.health = health_after
	return true


func _monster_response() -> void:
	var npc = _npc()
	if npc == null or location != "DUNGEON" or _life_state(npc_id) == "DEAD":
		return
	var ordered_ids: Array[int] = monster_ids.duplicate()
	ordered_ids.sort()
	for id in ordered_ids:
		if _life_state(id) != "ACTIVE" or _life_state(npc_id) == "DEAD":
			continue
		_update_monster_awareness(id)
		var awareness = monster_awareness.get(id)
		if awareness == null or str(awareness.awareness_state) == "UNAWARE":
			continue
		var traits: Dictionary = monster_traits.get(id, {})
		traits["action_budget"] = mini(int(traits.get("action_budget", 0)) \
			+ MONSTER_ACTION_BUDGET_PER_TURN, 400)
		var actions := 0
		while actions < MAX_MONSTER_ACTIONS_PER_RESPONSE \
				and _life_state(id) == "ACTIVE" and _life_state(npc_id) != "DEAD":
			var monster = simulator.world.entities.get(id)
			if monster == null:
				break
			var distance := _distance(npc.position, monster.position)
			if distance <= 1:
				var attack_cost := int(traits.get("attack_cost", 100))
				if int(traits.action_budget) < attack_cost:
					break
				traits.action_budget = int(traits.action_budget) - attack_cost
				if not _attack(id, npc_id, "", "MONSTER", false):
					break
				actions += 1
				continue
			var move_cost := int(traits.get("move_cost", 100))
			if int(traits.action_budget) < move_cost:
				break
			var goals := _open_neighbors(npc.position, id)
			var route: Dictionary = simulator.pathfinder.find_path_to_any(id, goals)
			if not bool(route.get("found", false)) or int(route.get("steps", 0)) <= 0:
				break
			var moved: Variant = simulator.step(CommandScript.move_to(id, route.path[1]))
			if not moved.accepted:
				break
			traits.action_budget = int(traits.action_budget) - move_cost
			actions += 1
			_log("ENEMY", "%s이(가) %s로 다가왔다. 이동 속도 %s." % [
				str(monster.display_name), _position_text(route.path[1]), _speed_label(move_cost)])
		monster_traits[id] = traits


func _advance_time() -> bool:
	var result = simulator.step(CommandScript.wait_for(100, -1))
	return result != null and bool(result.accepted)


func _reconcile_life() -> void:
	var npc_life := _life_state(npc_id)
	if npc_life == "DEAD":
		phase = "DEAD"
		location = "DUNGEON"
		if _last_npc_life_state != "DEAD":
			_log("DEATH", "아린은 이번 원정에서 돌아오지 못했다.")
	elif npc_life == "DOWNED":
		phase = "DUNGEON_COMBAT"
		if _last_npc_life_state != "DOWNED":
			_log("DOWNED", "아린이 쓰러졌다. 자력 행동이 불가능하다.")
	elif _last_npc_life_state == "DOWNED":
		phase = "DUNGEON_COMBAT"
		_log("RECOVERED", "아린이 간신히 의식을 되찾았다.")
	_last_npc_life_state = npc_life


func _reconcile_monster_deaths(event_start: int) -> void:
	var newly_dead: Dictionary = {}
	for event in simulator.world.events_since(event_start):
		if event.type == "entity.died" and int(event.target_id) in monster_ids:
			newly_dead[int(event.target_id)] = true
	# The canonical event is authoritative. The state scan is a defensive diff
	# for a death that happened in a nested time-advance path before this wrapper
	# regained control.
	for id in monster_ids:
		if _life_state(id) == "DEAD" and not _rewarded_monster_ids.has(id):
			newly_dead[id] = true
	var dead_ids: Array = newly_dead.keys()
	dead_ids.sort()
	for id_value in dead_ids:
		var id := int(id_value)
		if _rewarded_monster_ids.has(id):
			continue
		var monster = simulator.world.entities.get(id)
		if monster == null:
			continue
		_rewarded_monster_ids[id] = true
		kills += 1
		_spawn_loot(id, monster.position)
		_log("KILL", "%s 처치를 확인했다. 누적 처치 %d." % [_monster_name(id), kills])
	_refresh_target()
	if _unresolved_monster_ids().is_empty() and location == "DUNGEON":
		phase = "DUNGEON_LOOT" if not _ground_ref().rows.is_empty() else "DUNGEON_RETURN"
	elif phase == "DUNGEON_LOOT":
		phase = "DUNGEON_COMBAT"


func _refresh_target() -> void:
	var npc = _npc()
	if npc == null:
		monster_id = -1
		return
	var candidates: Array[Dictionary] = []
	for id in monster_ids:
		var life := _life_state(id)
		if life not in ["ACTIVE", "DOWNED"]:
			continue
		var monster = simulator.world.entities.get(id)
		if monster == null:
			continue
		var distance := _distance(npc.position, monster.position)
		var priority := 0 if life == "DOWNED" and distance <= 1 \
			else (1 if life == "ACTIVE" else 2)
		var reachable := true
		if life == "ACTIVE" and distance > 1:
			var route: Dictionary = simulator.pathfinder.find_path_to_any(npc_id,
				_open_neighbors(monster.position, npc_id))
			reachable = bool(route.get("found", false))
		candidates.append({"id": id, "priority": priority, "distance": distance,
			"reachable": reachable})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		if bool(a.reachable) != bool(b.reachable): return bool(a.reachable)
		if int(a.priority) != int(b.priority): return int(a.priority) < int(b.priority)
		if int(a.distance) != int(b.distance): return int(a.distance) < int(b.distance)
		return int(a.id) < int(b.id))
	monster_id = -1 if candidates.is_empty() else int(candidates[0].id)


func _unresolved_monster_ids() -> Array[int]:
	var result: Array[int] = []
	for id in monster_ids:
		if _life_state(id) in ["ACTIVE", "DOWNED"]:
			result.append(id)
	return result


func _monster_count_in_state(life_state: String) -> int:
	var count := 0
	for id in monster_ids:
		if _life_state(id) == life_state:
			count += 1
	return count


func _combat_outlook_milli(npc, target) -> Dictionary:
	# Integer, bounded outlook used only for utility inputs.  It deliberately
	# uses profile damage and action budgets rather than assess_attack(), whose
	# frozen combat roll belongs to execution rather than deliberation.
	var total_active_hp := 0
	for id in monster_ids:
		if _life_state(id) != "ACTIVE":
			continue
		var monster = simulator.world.entities.get(id)
		if monster != null:
			total_active_hp += maxi(0, int(monster.health))
	var npc_attack_damage := _estimated_normal_damage(npc_id, monster_id)
	var monster_attack_damage := _estimated_normal_damage(monster_id, npc_id)
	var combat_actions := maxi(1, int((total_active_hp + npc_attack_damage - 1) / npc_attack_damage))
	var combat_damage := _expected_enemy_damage(combat_actions, monster_attack_damage)
	var route: Dictionary = simulator.pathfinder.find_path(npc_id, ENTRY)
	var retreat_turns := int(route.get("steps", _distance(npc.position, ENTRY)))
	var retreat_damage := _expected_enemy_damage(retreat_turns, monster_attack_damage)
	var combat_viability := clampi(int((int(npc.health) - combat_damage) * 1000
		/ maxi(1, int(npc.max_health))), 0, 1000)
	var retreat_viability := clampi(int((int(npc.health) - retreat_damage) * 1000
		/ maxi(1, int(npc.max_health))), 0, 1000)
	var finish_window := 0
	if target != null:
		if _life_state(monster_id) == "DOWNED":
			finish_window = 1000
		else:
			finish_window = clampi(1000 - int(int(target.health) * 1000
				/ maxi(1, int(target.max_health))), 0, 1000)
	return {"combat_viability": combat_viability, "retreat_viability": retreat_viability,
		"target_finish_window": finish_window, "combat_actions": combat_actions,
		"combat_damage": combat_damage, "retreat_damage": retreat_damage,
		"retreat_turns": retreat_turns}


func _estimated_normal_damage(attacker_id: int, target_id: int) -> int:
	var attacker_state = simulator.world.combatant_states.get(attacker_id)
	var target_state = simulator.world.combatant_states.get(target_id)
	if attacker_state == null or target_state == null:
		return 1
	var attacker_profile: Dictionary = CombatProfileRegistryScript.profile(
		str(attacker_state.combat_profile_id))
	var target_profile: Dictionary = CombatProfileRegistryScript.profile(
		str(target_state.combat_profile_id))
	# Matches the shared unguarded, non-weapon base-damage rule. Hit/miss,
	# parry, and bleed stay execution concerns so inspection cannot consume RNG.
	var power := maxi(1, int(attacker_profile.get("power", 1)))
	var armor := clampi(int(target_profile.get("armor_flat", 0)), 0, power - 1)
	return maxi(1, power - armor)


func _expected_enemy_damage(npc_turns: int, damage_per_hit: int) -> int:
	var npc = _npc()
	if npc == null or npc_turns <= 0:
		return 0
	var total := 0
	for id in monster_ids:
		if _life_state(id) != "ACTIVE":
			continue
		var monster = simulator.world.entities.get(id)
		if monster == null:
			continue
		var traits: Dictionary = monster_traits.get(id, {})
		var move_cost := maxi(1, int(traits.get("move_cost", 100)))
		var attack_cost := maxi(1, int(traits.get("attack_cost", 110)))
		var distance := _distance(npc.position, monster.position)
		# A pursuer first spends budget closing distance; remaining response
		# windows can turn into attacks. Existing budget matters for adjacency.
		var close_turns := 0 if distance <= 1 else int(((distance - 1) * move_cost + 99) / 100)
		var attack_turns := maxi(0, npc_turns - close_turns)
		var budget := int(traits.get("action_budget", 0)) + attack_turns * MONSTER_ACTION_BUDGET_PER_TURN
		var attacks := int(budget / attack_cost)
		total += attacks * damage_per_hit
	return total


func _perceived_threat_milli() -> int:
	var npc = _npc()
	if npc == null or location != "DUNGEON":
		return 0
	var threat := 0
	for id in monster_ids:
		var life := _life_state(id)
		if life not in ["ACTIVE", "DOWNED"]:
			continue
		var monster = simulator.world.entities.get(id)
		if monster == null:
			continue
		var distance := _distance(npc.position, monster.position)
		var awareness = monster_awareness.get(id)
		var mutually_engaged := awareness != null \
			and str(awareness.awareness_state) in ["ALERT", "HUNTING", "SEARCHING"]
		var visible := distance <= 8 and EnemyPerceptionScript.has_line_of_sight(
			simulator.world, npc.position, monster.position)
		if not visible and not mutually_engaged:
			continue
		if life == "DOWNED":
			threat += 40
			continue
		var traits: Dictionary = monster_traits.get(id, {})
		var speed_pressure := maxi(0, 140 - int(traits.get("move_cost", 100))) * 2 \
			+ maxi(0, 150 - int(traits.get("attack_cost", 110))) * 2
		var proximity_pressure := maxi(0, 7 - mini(distance, 7)) * 20
		threat += 220 + speed_pressure + proximity_pressure
	return clampi(threat, 0, 1000)


func _update_monster_awareness(id: int) -> void:
	var npc = _npc()
	var monster = simulator.world.entities.get(id)
	var awareness = monster_awareness.get(id)
	if npc == null or monster == null or awareness == null:
		return
	var profile_row: Dictionary = EnemyPerceptionScript.profile(str(monster.species_id))
	var sight_range := int(profile_row.get("sight_range", 6))
	var distance := _distance(monster.position, npc.position)
	var sees := distance <= sight_range and EnemyPerceptionScript.has_line_of_sight(
		simulator.world, monster.position, npc.position)
	var previous := str(awareness.awareness_state)
	if distance <= 1:
		awareness.suspicion = 1000
		awareness.awareness_state = "HUNTING"
	elif sees:
		awareness.suspicion = clampi(int(awareness.suspicion) \
			+ EnemyPerceptionScript.suspicion_gain(str(monster.species_id), distance), 0, 1000)
		if previous in ["ALERT", "HUNTING", "SEARCHING"]:
			awareness.awareness_state = "HUNTING"
		elif int(awareness.suspicion) >= EnemyPerceptionScript.ALERT_THRESHOLD:
			awareness.awareness_state = "ALERT"
		else:
			awareness.awareness_state = "SUSPICIOUS"
	else:
		awareness.suspicion = maxi(0, int(awareness.suspicion) \
			- EnemyPerceptionScript.SUSPICION_DECAY)
		if previous in ["HUNTING", "ALERT"]:
			awareness.awareness_state = "SEARCHING"
		elif previous == "SUSPICIOUS" and int(awareness.suspicion) == 0:
			awareness.awareness_state = "UNAWARE"
	if sees or distance <= 1:
		awareness.last_known_target_position = npc.position
		awareness.last_seen_step = simulator.world.step_index
		awareness.last_seen_time = simulator.world.world_time
	if previous != str(awareness.awareness_state):
		_log("AWARENESS", "%s 인지: %s → %s." % [_monster_name(id), previous,
			str(awareness.awareness_state)])


func _alert_monsters_from_combat(target_id: int) -> void:
	var npc = _npc()
	if npc == null:
		return
	for id in monster_ids:
		if _life_state(id) != "ACTIVE":
			continue
		var monster = simulator.world.entities.get(id)
		if monster == null or (id != target_id and _distance(monster.position, npc.position) > 5):
			continue
		var awareness = monster_awareness.get(id)
		if awareness != null:
			awareness.awareness_state = "HUNTING"
			awareness.suspicion = 1000
			awareness.last_known_target_position = npc.position


func _monster_observation_rows() -> Array:
	var rows: Array = []
	for id in monster_ids:
		var row := _monster_observation_row(id)
		if not row.is_empty():
			rows.append(row)
	return rows


func _monster_observation_row(id: int) -> Dictionary:
	var monster = simulator.world.entities.get(id) if simulator != null else null
	if monster == null:
		return {}
	var traits: Dictionary = monster_traits.get(id, {})
	var awareness = monster_awareness.get(id)
	var life := _life_state(id)
	return {"entity_id": str(id), "name": str(monster.display_name), "glyph": "g",
		"position": _position_array(monster.position),
		"visible": location == "DUNGEON" and life != "DEAD",
		"hp": monster.health, "max_hp": monster.max_health, "life_state": life,
		"move_cost": int(traits.get("move_cost", 100)),
		"attack_cost": int(traits.get("attack_cost", 110)),
		"move_speed": _speed_label(int(traits.get("move_cost", 100))),
		"attack_speed": _speed_label(int(traits.get("attack_cost", 110))),
		"action_budget": int(traits.get("action_budget", 0)),
		"awareness_state": str(awareness.awareness_state) if awareness != null else "UNAWARE"}


func _monster_name(id: int) -> String:
	var monster = simulator.world.entities.get(id) if simulator != null else null
	return str(monster.display_name) if monster != null else "감염된 고블린"


func _allowed_speed_cost(value: Variant, allowed: Array, fallback: int) -> int:
	var parsed := int(value)
	return parsed if parsed in allowed else fallback


func _speed_label(cost: int) -> String:
	return "빠름" if cost < 100 else ("보통" if cost <= 110 else "느림")


func _bootstrap_dungeon() -> void:
	var carried_bundle := _carried_item_bundle()
	_dungeon_generation += 1
	simulator = SimulatorScript.new(MAP_WIDTH, MAP_HEIGHT, seed + _dungeon_generation * 1009)
	monster_ids.clear()
	monster_traits.clear()
	monster_awareness.clear()
	_rewarded_monster_ids.clear()
	current_action_id = ""
	commitment_until_turn = turn_index
	action_cooldown_until.clear()
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var position := Vector2i(x, y)
			if _is_wall(position):
				simulator.world.bootstrap_set_terrain(position, "wall")
	var npc = simulator.world.add_entity("hero", "아린", ENTRY, 100,
		["autonomous_npc", "expedition_observer"], "human", "town")
	npc_id = npc.id if npc != null else -1
	_restore_carried_item_bundle(carried_bundle)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + _dungeon_generation * 7919
	var spawn_groups := [
		[Vector2i(11, 7), Vector2i(12, 7), Vector2i(11, 8)],
		[Vector2i(10, 9), Vector2i(11, 9), Vector2i(10, 10)],
		[Vector2i(10, 3), Vector2i(11, 3), Vector2i(10, 4)],
	]
	var monster_count := clampi(int(_scenario_override.get("monster_count",
		rng.randi_range(MONSTER_COUNT_MIN, MONSTER_COUNT_MAX))),
		MONSTER_COUNT_MIN, MONSTER_COUNT_MAX)
	var spawn_group: Array = spawn_groups[(completed_cycles + absi(seed)) % spawn_groups.size()]
	for index in range(monster_count):
		var monster_position: Vector2i = spawn_group[index]
		var health := clampi(int(_scenario_override.get("monster_health",
			rng.randi_range(40, 60))), 30, 80)
		var monster = simulator.world.add_entity("melee_enemy", "감염된 고블린 %d" % (index + 1),
			monster_position, health, ["monster", "infected"], "goblin", "infected",
			"GOBLIN_MELEE_V1")
		if monster == null:
			continue
		monster_ids.append(monster.id)
		var move_cost := _allowed_speed_cost(_scenario_override.get("monster_move_cost",
			MONSTER_MOVE_COSTS[rng.randi_range(0, MONSTER_MOVE_COSTS.size() - 1)]),
			MONSTER_MOVE_COSTS, 100)
		var attack_cost := _allowed_speed_cost(_scenario_override.get("monster_attack_cost",
			MONSTER_ATTACK_COSTS[rng.randi_range(0, MONSTER_ATTACK_COSTS.size() - 1)]),
			MONSTER_ATTACK_COSTS, 110)
		monster_traits[monster.id] = {"move_cost": move_cost,
			"attack_cost": attack_cost, "action_budget": 0}
		monster_awareness[monster.id] = EnemyAwarenessScript.new(monster.id, monster_position)
	monster_ids.sort()
	monster_id = monster_ids[0] if not monster_ids.is_empty() else -1
	if npc != null and completed_cycles == 0:
		npc.health = npc.max_health
	_last_npc_life_state = _life_state(npc_id)


func _is_wall(position: Vector2i) -> bool:
	if position.x == 0 or position.y == 0 or position.x == MAP_WIDTH - 1 \
			or position.y == MAP_HEIGHT - 1:
		return true
	return position in [Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3),
		Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 6),
		Vector2i(9, 6), Vector2i(10, 6), Vector2i(11, 6),
		Vector2i(2, 9), Vector2i(3, 9), Vector2i(4, 9)]


func _spawn_loot(dead_monster_id: int, position: Vector2i) -> void:
	var death_event_id := -1
	for event in simulator.world.events:
		if event.type == "entity.died" and int(event.target_id) == dead_monster_id:
			death_event_id = int(event.id)
			break
	var spawned: Dictionary = WorldItemOperationsScript.commit_spawn_ground(simulator.world,
		"MATERIAL_UNSPECIFIED", 1, position, dead_monster_id, death_event_id,
		"NPC_EXPEDITION_REWARD")
	if bool(spawned.get("accepted", false)):
		_log("DROP", "%s이(가) 쓰러진 자리에 전리품이 남았다." % _monster_name(dead_monster_id))


func _deposit_loot() -> int:
	var deposited := 0
	var instance_ids: Array[String] = []
	var inventory = _inventory_ref()
	if inventory == null:
		return 0
	for item in inventory.backpack:
		if item.definition_id == "MATERIAL_UNSPECIFIED":
			instance_ids.append(str(item.instance_id))
			deposited += int(item.quantity)
	for instance_id in instance_ids:
		var discarded: Dictionary = WorldItemOperationsScript.commit_discard(simulator.world,
			npc_id, instance_id, _npc().position, 0)
		if not bool(discarded.get("accepted", false)):
			deposited -= int(inventory.item(instance_id).quantity)
	loot_banked += deposited
	return deposited


func _restock_potion_if_needed() -> void:
	if _item_quantity("POTION_HEALING") > 0:
		return
	var npc = _npc()
	if npc == null:
		return
	var added: Dictionary = WorldItemOperationsScript.commit_grant(simulator.world,
		npc_id, "POTION_HEALING", 2, npc.position, "NPC_TOWN_RESTOCK")
	if bool(added.get("accepted", false)):
		_log("SUPPLY", "마을에서 회복 물약 2개를 보충했다.")


func _carried_item_bundle() -> Dictionary:
	# A new expedition currently owns a fresh dungeon world. Carry only this NPC's
	# canonical rows and allocator frontier across that boundary; ground items and
	# monster inventories belong to the completed dungeon and stay behind.
	if simulator == null or simulator.world == null or npc_id < 1:
		return {}
	var inventory = simulator.world._inventory_ref(npc_id)
	var ammo_pool = simulator.world._ammo_pool_ref(npc_id)
	if inventory == null or ammo_pool == null:
		return {}
	var owned_ids: Dictionary = {}
	for item in inventory.backpack:
		owned_ids[str(item.instance_id)] = true
	var runtime_rows: Array = []
	var runtime_ids: Array = simulator.world.item_state.weapon_runtime_rows.keys()
	runtime_ids.sort()
	for instance_id in runtime_ids:
		if owned_ids.has(str(instance_id)):
			runtime_rows.append(
				simulator.world.item_state.weapon_runtime_rows[instance_id].to_dict())
	return {"inventory": inventory.to_dict(), "ammo_pool": ammo_pool.to_dict(),
		"runtime_rows": runtime_rows,
		"next_item_instance_id": int(simulator.world.item_state.next_item_instance_id),
		"revision": int(simulator.world.item_state.revision)}


func _restore_carried_item_bundle(bundle: Dictionary) -> void:
	if bundle.is_empty() or simulator == null or simulator.world == null or npc_id < 1:
		return
	var inventory = InventoryStateScript.from_dict(bundle.get("inventory", {}))
	var ammo_pool = AmmoPoolStateScript.from_dict(bundle.get("ammo_pool", {}))
	if inventory == null or ammo_pool == null:
		return
	var state = simulator.world.item_state
	state.inventory_rows[npc_id] = inventory
	state.ammo_pool_rows[npc_id] = ammo_pool
	for row in bundle.get("runtime_rows", []):
		var runtime = WeaponRuntimeStateScript.from_dict(row)
		if runtime != null:
			state.weapon_runtime_rows[str(runtime.instance_id)] = runtime
	state.next_item_instance_id = maxi(state.next_item_instance_id,
		int(bundle.get("next_item_instance_id", state.next_item_instance_id)))
	state.revision = maxi(state.revision, int(bundle.get("revision", state.revision)))


func _inventory_ref():
	return simulator.world._inventory_ref(npc_id) \
		if simulator != null and simulator.world != null else null


func _ground_ref():
	return simulator.world.item_state.ground_items \
		if simulator != null and simulator.world != null \
			and simulator.world.item_state != null else null


func _npc():
	return simulator.world.entities.get(npc_id) if simulator != null else null


func _monster():
	return simulator.world.entities.get(monster_id) if simulator != null else null


func _life_state(entity_id: int) -> String:
	var state = simulator.world.combatant_states.get(entity_id) if simulator != null else null
	return str(state.life_state) if state != null else "MISSING"


func _item_quantity(definition_id: String) -> int:
	var total := 0
	var inventory = _inventory_ref()
	if inventory == null:
		return total
	for item in inventory.backpack:
		if item.definition_id == definition_id:
			total += int(item.quantity)
	return total


func _first_item_instance(definition_id: String) -> String:
	var inventory = _inventory_ref()
	if inventory == null:
		return ""
	for item in inventory.backpack:
		if item.definition_id == definition_id:
			return str(item.instance_id)
	return ""


func _reachable_ground_item_position() -> Vector2i:
	# A drop under a downed (still tile-blocking) body cannot be walked onto;
	# the NPC has to finish the body first, so such loot is not a candidate.
	var ground = _ground_ref()
	if ground == null:
		return Vector2i(-1, -1)
	for row in ground.rows:
		var position: Vector2i = row.position
		if simulator.world.blocking_entity_at(position, npc_id) == null:
			return position
	return Vector2i(-1, -1)


func _open_neighbors(center: Vector2i, moving_id: int) -> Array:
	var goals: Array = []
	for direction in simulator.movement.MOVE_DIRECTIONS_8:
		var candidate: Vector2i = center + direction
		if not simulator.world.in_bounds(candidate):
			continue
		var terrain: Dictionary = TerrainRegistryScript.definition(
			str(simulator.world.tile_at(candidate).terrain))
		if bool(terrain.get("passable", false)) \
				and simulator.world.blocking_entity_at(candidate, moving_id) == null:
			goals.append(candidate)
	return goals


func _terrain_rows() -> Array[String]:
	var rows: Array[String] = []
	for y in range(MAP_HEIGHT):
		var row := ""
		for x in range(MAP_WIDTH):
			row += "#" if str(simulator.world.tile_at(Vector2i(x, y)).terrain) == "wall" else "."
		rows.append(row)
	return rows


func _corpse_rows() -> Array:
	var rows: Array = []
	for entity_id in simulator.world.entities:
		if int(entity_id) == npc_id:
			continue
		if _life_state(int(entity_id)) == "DEAD":
			var entity = simulator.world.entities[entity_id]
			rows.append({"position": _position_array(entity.position), "glyph": "%"})
	return rows


func _ground_rows() -> Array:
	var rows: Array = []
	var ground = _ground_ref()
	if ground == null:
		return rows
	for row in ground.rows:
		rows.append({"position": _position_array(row.position), "glyph": "*",
			"label": "전리품"})
	return rows


func _inventory_labels() -> Array[String]:
	var labels: Array[String] = []
	var inventory = _inventory_ref()
	if inventory == null:
		return labels
	for item in inventory.backpack:
		var definition = ItemRegistryScript.definition(item.definition_id)
		if definition != null:
			labels.append("%s%s" % [definition.label,
				" ×%d" % item.quantity if item.quantity > 1 else ""])
	return labels


func _goal_text() -> String:
	match phase:
		"TOWN_PREPARE": return "장비와 물약을 확인하고 출발 준비를 마친다."
		"DUNGEON_ENTER": return "선택한 던전에 진입한다."
		"DUNGEON_EXPLORE": return "감염체의 흔적을 따라 안전한 경로를 찾는다."
		"DUNGEON_COMBAT": return "체력을 보존하며 감염체를 제압한다."
		"DUNGEON_LOOT": return "쓰러진 감염체의 전리품을 회수한다."
		"DUNGEON_RETURN": return "확보한 물건을 들고 입구로 돌아간다."
		"TOWN_RECOVER": return "상처를 치료하고 전리품을 창고에 맡긴다."
		"DEAD": return "원정이 종료되었다."
	return "다음 행동을 판단한다."


func _log(kind: String, message: String) -> void:
	logs.append({"turn": str(turn_index), "kind": kind, "message": message})
	if logs.size() > MAX_LOG_ROWS:
		logs.pop_front()


static func _distance(first: Vector2i, second: Vector2i) -> int:
	return maxi(absi(first.x - second.x), absi(first.y - second.y))


static func _position_array(position: Vector2i) -> Array[int]:
	return [position.x, position.y]


static func _position_text(position: Vector2i) -> String:
	return "(%d,%d)" % [position.x, position.y]
