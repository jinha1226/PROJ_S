class_name PartyEncounterCoordinator
extends RefCounted

const ActionScript = preload("res://sim/party_action_command.gd")
const RequestScript = preload("res://sim/party_turn_request.gd")
const PlanScript = preload("res://sim/party_turn_plan.gd")
const MeleeScript = preload("res://sim/systems/melee_combat_system.gd")
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const MAX_DEPLOYED_PARTY := 3
const PARTY_ACTION_COST := 100
const MAX_INT64 := 9223372036854775807
const MAX_WORLD_TIME := 9223372036854775707
const MAX_SCHEDULE_OCCURRENCES := 1024

var world
var movement
var damage
var pathfinder
var melee
var environment
var exposure
var fail_after_leaf_index: int = -1
var fail_point := ""

func _init(p_world, p_movement, p_damage, p_pathfinder, p_environment = null, p_exposure = null) -> void:
	world = p_world; movement = p_movement; damage = p_damage; pathfinder = p_pathfinder
	environment = p_environment; exposure = p_exposure
	melee = MeleeScript.new(world, damage)

func process_tick(processed_step_index: int, actor_schedule_id: int, due_time: int,
		tick_start_can_act_ids: Dictionary, allow_victory: bool = true) -> bool:
	if processed_step_index <= 0 or world._active_step_index != processed_step_index \
			or actor_schedule_id <= 0 or due_time != world.world_time:
		return false
	if world.party_encounter == null: return true
	if not reconcile_liveness(allow_victory): return false
	var encounter = world.party_encounter
	if encounter.safe_phase == "PARTY_DEFEATED": return true
	if encounter.safe_phase in ["GROUPED", "GROUPED_COMPLETE"]:
		if encounter.safe_phase == "GROUPED": return _exploration_enemy_cadence(
			processed_step_index,actor_schedule_id,due_time,tick_start_can_act_ids)
		return true
	if encounter.safe_phase == "ENGAGED": return _enemy_batch(processed_step_index,
		actor_schedule_id, due_time, tick_start_can_act_ids, allow_victory)
	return true

func reconcile_liveness(allow_victory: bool = true) -> bool:
	if world.party_encounter == null:
		return true
	var state = world.party_encounter
	var presence_changed := false
	for member_id in state.party_member_ids:
		if not world.entities.has(member_id):
			return false
		var member = state.member(member_id)
		if member == null:
			return false
		if world.combatant_states[member_id].life_state == "DEAD" and member.presence != "DEFEATED":
			member.presence = "DEFEATED"
			presence_changed = true
	var protagonist_alive: bool = world.combatant_states[state.protagonist_id].life_state == "ACTIVE"
	if not protagonist_alive:
		if state.safe_phase != "PARTY_DEFEATED":
			state.safe_phase = "PARTY_DEFEATED"
			state.revision += 1
		elif presence_changed:
			state.revision += 1
		return not _fault("reconcile_liveness")
	if allow_victory and state.safe_phase == "ENGAGED" and not _has_alive_enemy():
		if _fault("victory_event"):
			return false
		var victory_cause_id := _last_enemy_death_event_id()
		if victory_cause_id <= 0:
			return false
		var victory = world.emit_event("party.victory", state.protagonist_id, -1,
			world.entities[state.protagonist_id].position, 0, victory_cause_id)
		if victory == null:
			return false
		# This intermediate phase exists only inside the active party-turn
		# transaction. Remaining cadence must still see deployed combat positions.
		state.safe_phase = "REGROUP_READY"
		state.revision += 1
	elif presence_changed:
		state.revision += 1
	return not _fault("reconcile_liveness")


func finalize_automatic_regroup() -> bool:
	# Victory is not a second player decision. The killing party turn owns the
	# regroup chain so a failure anywhere below rolls the whole turn
	# back through Simulator.step_party_turn(). REGROUP_READY remains a readable
	# legacy wire phase, but production progression never publishes it.
	var state = world.party_encounter
	if state == null or state.safe_phase != "REGROUP_READY":
		return true
	var protagonist = world.entities.get(state.protagonist_id)
	if protagonist == null or not world.can_act(protagonist.id, world.world_time):
		return false
	if _fault("automatic_regroup_after_victory"):
		return false
	var victory_id := -1
	for index in range(world.events.size() - 1, -1, -1):
		if world.events[index].type == "party.victory":
			victory_id = world.events[index].id
			break
	if victory_id <= 0:
		return false
	var root = world.emit_event("party.regroup_started", protagonist.id, -1,
		protagonist.position, 0, victory_id)
	if root == null or _fault("automatic_regroup_started_event"):
		return false
	state.group_anchor = protagonist.position
	for member_id in state.active_party_member_ids:
		if member_id == protagonist.id or not world.occupies_tile(member_id):
			continue
		state.member(member_id).presence = "GROUPED"
		world.entities[member_id].position = state.group_anchor
		if world.emit_event("party.member_regrouped", member_id, protagonist.id,
				state.group_anchor, 0, root.id) == null \
				or _fault("automatic_regroup_member_event"):
			return false
	if world.emit_event("party.regroup_completed", protagonist.id, -1,
			state.group_anchor, 0, root.id) == null \
			or _fault("automatic_regroup_completed_event"):
		return false
	state.safe_phase = "GROUPED_COMPLETE"
	state.formation_id = "NONE"
	state.contact_kind = "NONE"
	state.contact_enemy_id = -1
	state.revision += 1
	return true

func _exploration_enemy_cadence(processed_step_index:int,actor_schedule_id:int,
		due_time:int,tick_start_can_act_ids:Dictionary)->bool:
	# Preserve the established contact boundary: actors already in detection range
	# make contact before any patrol movement. Only a still-GROUPED world patrols.
	if not _detect_contact(processed_step_index,actor_schedule_id,due_time,
			tick_start_can_act_ids):
		return false
	var state=world.party_encounter
	if state.safe_phase!="GROUPED":return true
	# The current product slice is explicitly solo. Legacy party SHOWCASE and
	# REGRESSION fixtures retain their established social/contact timing until
	# companion-aware exploration cadence is designed as its own slice.
	if state.party_member_ids.size()!=1:return true
	var enemies:Array=state.enemy_ids.duplicate();enemies.sort()
	var acted_ids:Dictionary={}
	for enemy_id in enemies:
		if not tick_start_can_act_ids.has(enemy_id) \
				or not world.can_act(enemy_id,world.world_time) \
				or int(state.enemy_busy_rows.get(enemy_id,MAX_WORLD_TIME))>world.world_time \
				or not world.is_autonomous_target(enemy_id):
			continue
		var forecast:Dictionary=forecast_exploration_patrol(enemy_id,
			processed_step_index,actor_schedule_id,due_time)
		if not bool(forecast.get("accepted",false)):return false
		var action_event=null
		var action_cost:=PARTY_ACTION_COST
		if str(forecast.action_type)=="MOVE":
			var destination:=Vector2i(int(forecast.destination[0]),
				int(forecast.destination[1]))
			action_cost=int(forecast.time_cost)
			action_event=movement.commit_preflighted_move(enemy_id,destination,
				str(forecast.terrain_id),action_cost)
		else:
			action_event=_commit_hold(enemy_id,PARTY_ACTION_COST)
		if action_event==null or _fault("exploration_enemy_leaf") \
				or world.world_time>MAX_WORLD_TIME-action_cost:
			return false
		state.enemy_busy_rows[enemy_id]=world.world_time+action_cost
		acted_ids[enemy_id]=true
		# HOLD cannot change contact. A MOVE may cross a detection boundary, so
		# contact is derived immediately, while every enemy that already acted in
		# this cadence is excluded from the same-tick ambush opening.
		if str(forecast.action_type)=="MOVE":
			if not _detect_contact(processed_step_index,actor_schedule_id,due_time,
					tick_start_can_act_ids,acted_ids):
				return false
			if state.safe_phase!="GROUPED":return true
	return true


func _detect_contact(processed_step_index: int, actor_schedule_id: int, due_time: int,
		tick_start_can_act_ids: Dictionary,ambush_excluded_ids:Dictionary={}) -> bool:
	var state = world.party_encounter
	var protagonist = world.entities[state.protagonist_id]
	if not world.can_act(protagonist.id, world.world_time):
		return reconcile_liveness()
	state.group_anchor = protagonist.position
	for member_id in state.party_member_ids:
		var member = state.member(member_id)
		if member.presence == "GROUPED": world.entities[member_id].position = state.group_anchor
	var nearest: Variant = _nearest_alive_enemy(state.group_anchor)
	if nearest == null: return true
	var distance := _distance(state.group_anchor, nearest.position)
	var party_detects: bool = distance <= state.party_detection_radius
	var enemy_detects: bool = distance <= state.enemy_detection_radius
	if not party_detects and not enemy_detects: return true
	state.contact_kind = "DETECTED" if party_detects and enemy_detects else ("PARTY_AMBUSH" if party_detects else "ENEMY_AMBUSH")
	state.contact_enemy_id = nearest.id
	state.facing = _cardinal_facing(nearest.position - state.group_anchor)
	var event_type: String = {"DETECTED": "encounter.detected", "PARTY_AMBUSH": "encounter.party_ambush", "ENEMY_AMBUSH": "encounter.enemy_ambush"}[state.contact_kind]
	var contact = world.emit_event(event_type, nearest.id if state.contact_kind == "ENEMY_AMBUSH" else state.protagonist_id,
		state.protagonist_id if state.contact_kind == "ENEMY_AMBUSH" else nearest.id, state.group_anchor, 0, -1,
		{"contact_kind": state.contact_kind, "enemy_id": str(nearest.id),
			"enemy_position": [nearest.position.x, nearest.position.y],
			"facing": [state.facing.x, state.facing.y]})
	if contact == null or _fault("contact_event"): return false
	if state.contact_kind == "ENEMY_AMBUSH":
		var ambushers: Array = []
		for enemy_id in state.enemy_ids:
			if tick_start_can_act_ids.has(enemy_id) \
					and not ambush_excluded_ids.has(enemy_id) \
					and int(state.enemy_busy_rows.get(enemy_id,MAX_WORLD_TIME))<=world.world_time \
					and world.is_autonomous_target(enemy_id):
				ambushers.append(enemy_id)
		ambushers.sort()
		var rows: Array[Dictionary] = []
		for enemy_id in ambushers:
			rows.append({"enemy_id": enemy_id,
				"original_action_order": rows.size(),
				"melee": melee.can_attack(enemy_id, state.protagonist_id)})
		var melee_rows: Array[Dictionary] = []
		for row in rows:
			if bool(row.melee): melee_rows.append(row)
		melee_rows.sort_custom(func(a: Dictionary, b: Dictionary):
			if int(a.enemy_id) != int(b.enemy_id):
				return int(a.enemy_id) < int(b.enemy_id)
			return int(a.original_action_order) < int(b.original_action_order))
		var context := "PARTY_AMBUSH/%d/%d" % [actor_schedule_id, due_time]
		var frozen_intents: Array = []
		for ordinal in range(melee_rows.size()):
			var row: Dictionary = melee_rows[ordinal]
			var assessment: Dictionary = melee.assess_attack(int(row.enemy_id),
				state.protagonist_id, "SUGGESTED", processed_step_index,
				due_time, context, ordinal)
			var frozen = melee.freeze_assessment(assessment,
				protagonist.health, int(row.original_action_order), true)
			if assessment.is_empty() or frozen == null:
				return false
			frozen_intents.append(frozen)
		var projected_results: Array = melee.project_batch(frozen_intents)
		if projected_results.size() != frozen_intents.size():
			return false
		var canonical_batch: bool = not frozen_intents.is_empty()
		var frozen_by_actor: Dictionary = {}
		var resolution_by_ordinal: Dictionary = {}
		if canonical_batch:
			for frozen in frozen_intents:
				frozen_by_actor[int(str(frozen.assessment.attacker_id))] = frozen
			for resolution in projected_results:
				resolution_by_ordinal[int(resolution.action_data.intent_ordinal)] = resolution
		var pending_results: Array[Dictionary] = []
		for row in rows:
			var enemy_id := int(row.enemy_id)
			var opening = null
			if bool(row.melee):
				var frozen = frozen_by_actor.get(enemy_id)
				var ordinal := int(frozen.assessment.intent_ordinal) if frozen != null else -1
				var resolution = resolution_by_ordinal.get(ordinal)
				if not canonical_batch or frozen == null or resolution == null:
					return false
				var assessment: Dictionary = frozen.assessment
				var target_position := Vector2i(int(assessment.target_position[0]),
					int(assessment.target_position[1]))
				opening = world.emit_event("action.melee_attack", enemy_id,
					state.protagonist_id, target_position,
					int(assessment.base_damage), contact.id, resolution.action_data)
				if opening != null:
					pending_results.append({"action": opening, "intent": frozen,
						"resolution": resolution})
			else:
				opening = _commit_hold(enemy_id, 100, contact.id)
			if opening == null or _fault("ambush_leaf"):
				return false
			state.enemy_busy_rows[enemy_id] = world.world_time + 100
		pending_results.sort_custom(func(a: Dictionary, b: Dictionary):
			return int(a.resolution.action_data.intent_ordinal) \
				< int(b.resolution.action_data.intent_ordinal))
		for pending in pending_results:
			var action = pending.action
			var resolution = pending.resolution
			var target = world.entities.get(action.target_id)
			var target_state = world.combatant_states.get(action.target_id)
			if target == null or target_state == null \
					or target.health != resolution.target_health_before \
					or target_state.life_state != resolution.target_life_before:
				return false
			if resolution.outcome == "OVERKILL_SKIP":
				continue
			if resolution.outcome == "MISS":
				if world.emit_event("combat.attack_missed", -1, action.target_id,
						action.position, 0, action.id, {"schema_version": 1,
							"combat_ruleset_id": MeleeScript.COMBAT_RULESET_ID,
							"outcome": "MISS"}) == null:
					return false
			elif resolution.outcome == "HIT":
				var applied: Dictionary = damage.apply_canonical_active_damage(target,
					resolution.final_damage, "physical", action.id, action.position,
					processed_step_index, resolution.target_health_before,
					resolution.terminal_immediate, resolution.bleed_proc_succeeded)
				if not bool(applied.accepted) \
						or int(applied.applied_health_damage) \
						!= resolution.target_health_before - resolution.target_health_after:
					return false
			else:
				return false
			if target.health != resolution.target_health_after \
					or target_state.life_state != resolution.target_life_after:
				return false
	if state.safe_phase != "PARTY_DEFEATED":
		state.safe_phase = "CONTACT"
	state.revision += 1
	if not reconcile_liveness():
		return false
	return true


func forecast_exploration_patrol(enemy_id:int,processed_step_index:int,
		actor_schedule_id:int,due_time:int)->Dictionary:
	# Pure, keyed patrol selection. It never advances world.rng and therefore the
	# same seed/snapshot/cadence always yields the same destination.
	var rejected:={"accepted":false,"reason":"enemy_unavailable",
		"enemy_id":enemy_id,"action_type":"HOLD","from_position":[-1,-1],
		"destination":[-1,-1],"terrain_id":"","time_cost":PARTY_ACTION_COST,
		"risk":0}
	if world==null or world.party_encounter==null \
			or world.party_encounter.safe_phase!="GROUPED" \
			or enemy_id not in world.party_encounter.enemy_ids \
			or not world.entities.has(enemy_id) or not world.is_autonomous_target(enemy_id) \
			or processed_step_index<=0 or actor_schedule_id<=0 or due_time!=world.world_time:
		return rejected.duplicate(true)
	var enemy=world.entities[enemy_id]
	rejected.from_position=[enemy.position.x,enemy.position.y]
	var current_risk:=_patrol_exposure_risk(enemy_id,enemy.position)
	if current_risk<0:
		rejected.reason="exposure_unavailable"
		return rejected.duplicate(true)
	var candidates:Array[Dictionary]=[]
	for direction_index in range(movement.MOVE_DIRECTIONS_8.size()):
		var destination:Vector2i=enemy.position+movement.MOVE_DIRECTIONS_8[direction_index]
		if world.party_encounter.patrol_reserved_positions.has(destination):continue
		var traversal=movement.assess_move(enemy_id,destination)
		if not traversal.accepted:continue
		var risk:=_patrol_exposure_risk(enemy_id,destination)
		if risk<0:continue
		var terrain_id:=str(traversal.terrain_id)
		var definition:Dictionary=TerrainRegistryScript.definition(terrain_id)
		if definition.is_empty():continue
		candidates.append({"destination":destination,"terrain_id":terrain_id,
			"time_cost":int(definition.move_time_cost),"risk":risk,
			"tie_rank":_patrol_tie_rank(enemy_id,processed_step_index,
				actor_schedule_id,due_time,destination,direction_index)})
	if candidates.is_empty():
		rejected.accepted=true;rejected.reason="patrol_blocked_guard"
		return rejected.duplicate(true)
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):
		if int(a.risk)!=int(b.risk):return int(a.risk)<int(b.risk)
		if int(a.tie_rank)!=int(b.tie_rank):return int(a.tie_rank)<int(b.tie_rank)
		var ap:Vector2i=a.destination;var bp:Vector2i=b.destination
		return ap.y<bp.y if ap.y!=bp.y else ap.x<bp.x)
	var selected:Dictionary=candidates[0]
	# A healthy tile does not send a monster into unavoidable exposure. An actor
	# already in danger may still step to a strictly safer (but non-zero) tile.
	if int(selected.risk)>0 and int(selected.risk)>=current_risk:
		rejected.accepted=true;rejected.reason="patrol_risk_guard"
		rejected.risk=int(selected.risk)
		return rejected.duplicate(true)
	var destination:Vector2i=selected.destination
	rejected.accepted=true;rejected.reason="patrol_scout"
	rejected.action_type="MOVE"
	rejected.destination=[destination.x,destination.y]
	rejected.terrain_id=str(selected.terrain_id)
	rejected.time_cost=int(selected.time_cost)
	rejected.risk=int(selected.risk)
	return rejected.duplicate(true)


func _patrol_exposure_risk(enemy_id:int,position:Vector2i)->int:
	if exposure==null:return -1
	var evaluated=exposure.evaluate_for_entity(enemy_id,position,false)
	if evaluated==null or not evaluated is Dictionary \
			or evaluated.get("evaluation")==null:
		return -1
	return maxi(0,int(evaluated.evaluation.total_risk))


func _patrol_tie_rank(enemy_id:int,processed_step_index:int,
		actor_schedule_id:int,due_time:int,destination:Vector2i,
		direction_index:int)->int:
	var key:="party-patrol-v1|seed=%d|step=%d|schedule=%d|time=%d|enemy=%d|x=%d|y=%d|direction=%d"%[
		world.seed,processed_step_index,actor_schedule_id,due_time,enemy_id,
		destination.x,destination.y,direction_index]
	var digest:PackedByteArray=key.sha256_buffer()
	return ((int(digest[0])&0x7f)<<24)|(int(digest[1])<<16) \
		|(int(digest[2])<<8)|int(digest[3])

func preview_deployment(preset_id: String, companion_ids: Array) -> Dictionary:
	var rejected := {"accepted": false, "reason": "", "preset_id": preset_id, "companion_ids": [], "placements": [], "base_fingerprint": ""}
	if world.party_encounter == null or world.party_encounter.safe_phase != "CONTACT" or not world.is_settled(): rejected.reason = "deployment_phase_required"; return rejected
	if preset_id not in ["WEDGE", "LINE", "COLUMN"]: rejected.reason = "unknown_formation"; return rejected
	var state = world.party_encounter; var selected: Array[int] = []
	for value in companion_ids:
		var companion_id := int(value) if value is int else -1
		var companion = state.member(companion_id)
		if not value is int or selected.has(companion_id) or companion_id == state.protagonist_id \
				or companion == null or companion.role != "COMPANION" or companion.presence != "GROUPED" \
				or not world.entities.has(companion_id) or not world.can_act(companion_id, world.world_time):
			rejected.reason = "invalid_companion_ids"; return rejected
		selected.append(companion_id)
	selected.sort_custom(func(a, b):
		var am = state.member(a); var bm = state.member(b)
		return am.roster_slot < bm.roster_slot if am.roster_slot != bm.roster_slot else a < b)
	if selected.size() + 1 > MAX_DEPLOYED_PARTY: rejected.reason = "too_many_deployed_party"; return rejected
	rejected.companion_ids = selected.duplicate()
	var placements: Array = [{"entity_id": state.protagonist_id, "roster_slot": 0,
		"position": [state.group_anchor.x, state.group_anchor.y], "placement": "anchor"}]
	var reserved := {_key(state.group_anchor): state.protagonist_id}
	for index in range(selected.size()):
		var target: Vector2i = state.group_anchor + _formation_offset(preset_id, index, state.facing)
		var chosen = target if _deployment_cell_valid(target, reserved, state.group_anchor) else _fallback_cell(state.group_anchor, reserved)
		if chosen == null: rejected.reason = "deployment_space_unavailable"; return rejected
		reserved[_key(chosen)] = selected[index]
		placements.append({"entity_id": selected[index], "roster_slot": state.member(selected[index]).roster_slot,
			"position": [chosen.x, chosen.y], "placement": "preset" if chosen == target else "fallback"})
	if world.step_index == MAX_INT64: rejected.reason = "step_index_overflow"; return rejected
	if world.world_time > MAX_WORLD_TIME - 100: rejected.reason = "time_overflow"; return rejected
	if not world.has_event_id_headroom(selected.size() + 2): rejected.reason = "event_id_overflow"; return rejected
	rejected.accepted = true; rejected.reason = "ok"; rejected.placements = placements
	rejected.base_fingerprint = _fingerprint(); rejected["plan_hash"] = _hash_without(rejected, "plan_hash")
	return rejected.duplicate(true)

func deployment_commit_error(plan: Variant) -> String:
	var plan_error := _deployment_plan_error(plan)
	if not plan_error.is_empty():
		return plan_error
	if not bool(plan.accepted):
		return str(plan.reason)
	if str(plan.base_fingerprint) != _fingerprint():
		return "stale_deployment_plan"
	var authoritative: Dictionary = preview_deployment(str(plan.preset_id), plan.companion_ids.duplicate())
	if not bool(authoritative.get("accepted", false)):
		return "stale_deployment_plan"
	if plan != authoritative:
		return "deployment_plan_mismatch"
	return ""


func commit_prevalidated_deployment(plan: Dictionary, processed_step_index: int):
	if processed_step_index <= 0 or world._active_step_index != processed_step_index:
		return {"reason": "invalid_processed_step_index"}
	var authoritative: Dictionary = plan
	var event_start: int = world.events.size(); var state = world.party_encounter
	var contact_cause_id := _contact_event_id()
	if contact_cause_id <= 0:
		return {"reason": "contact_event_missing"}
	var selected: Dictionary = {}; var deployment_index := 0
	for row in authoritative.placements:
		var id := int(row.entity_id); selected[id] = true; var member = state.member(id)
		member.presence = "DEPLOYED"; world.entities[id].position = Vector2i(int(row.position[0]), int(row.position[1]))
		if id != state.protagonist_id:
			var preset_position: Vector2i = state.group_anchor + _formation_offset(
				str(authoritative.preset_id), deployment_index, state.facing)
			var deployment_data := {"formation_id": str(authoritative.preset_id),
				"formation_index": deployment_index, "placement": str(row.placement),
				"preset_position": [preset_position.x, preset_position.y],
				"roster_slot": member.roster_slot}
			if world.emit_event("party.member_deployed", id, -1, world.entities[id].position,
					0, contact_cause_id, deployment_data) == null:
				return {"reason": "event_emission_failed"}
			deployment_index += 1
		if id != state.protagonist_id and _fault("deployment_member_event"):
			return {"reason": "injected_deployment_failure"}
	for id in state.active_party_member_ids:
		if id != state.protagonist_id and not selected.has(id) and world.occupies_tile(id): state.member(id).presence = "DORMANT"
	if state.contact_kind == "PARTY_AMBUSH":
		for enemy_id in state.enemy_ids: state.enemy_busy_rows[enemy_id] = world.world_time + 100
	var companion_wires: Array = []
	for companion_id in authoritative.companion_ids: companion_wires.append(str(companion_id))
	var completed = world.emit_event("party.deployment_completed", state.protagonist_id, -1,
		state.group_anchor, 0, contact_cause_id, {"formation_id": str(authoritative.preset_id),
			"companion_ids": companion_wires})
	if completed == null or _fault("deployment_completed_event"):
		return {"reason": "event_emission_failed"}
	state.formation_id = str(authoritative.preset_id); state.safe_phase = "ENGAGED"; state.revision += 1
	return _result(true, "ok", world.events_since(event_start), 0, processed_step_index)

func preview_party_turn(request, processed_step_index: int,
		attack_start_world_time: int) -> PartyTurnPlan:
	if processed_step_index <= 0 or attack_start_world_time != world.world_time:
		return PlanScript.new({"accepted": false, "reason": "invalid_processed_step_context",
			"actor_rows": [], "base_fingerprint": _fingerprint()})
	var rejection := _turn_rejection(request)
	if not rejection.is_empty(): return PlanScript.new({"accepted": false, "reason": rejection, "actor_rows": [], "base_fingerprint": _fingerprint()})
	var state = world.party_encounter; var rows: Array = []
	var direct = request.protagonist_action; rows.append(_action_row(direct, "DIRECT", state.member(direct.actor_id).roster_slot))
	var overrides: Dictionary = {}; for row in request.overrides: overrides[int(row.actor_id)] = row.action
	for member_id in state.party_member_ids:
		if member_id == state.protagonist_id: continue
		var member = state.member(member_id)
		if member.presence != "DEPLOYED" or not world.can_act(member_id, world.world_time) or member.busy_until > world.world_time: continue
		var suggested = _suggest(member_id, direct)
		var action = overrides.get(member_id, suggested)
		var source := "OVERRIDE" if overrides.has(member_id) else "SUGGESTED"
		var row = _action_row(action, source, member.roster_slot); row["suggestion"] = suggested.to_dict(); row["overridden"] = overrides.has(member_id) and action.to_dict() != suggested.to_dict(); rows.append(row)
	var conflict_error := _resolve_move_conflicts(rows)
	if not conflict_error.is_empty(): return PlanScript.new({"accepted": false, "reason": conflict_error, "actor_rows": [], "base_fingerprint": _fingerprint()})
	var batch_context: String = "PARTY_TURN/%d" % processed_step_index
	var melee_rows: Array[Dictionary] = []
	for row_index in range(rows.size()):
		var row: Dictionary = rows[row_index]
		if str(row.action.type) == "MELEE":
			melee_rows.append({"row_index": row_index, "actor_id": int(row.action.actor_id),
				"target_id": int(row.action.target_id)})
		else:
			row.combat_assessment = null; rows[row_index] = row
	melee_rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.target_id) != int(b.target_id): return int(a.target_id) < int(b.target_id)
		if int(a.actor_id) != int(b.actor_id): return int(a.actor_id) < int(b.actor_id)
		return int(a.row_index) < int(b.row_index))
	for melee_ordinal in range(melee_rows.size()):
		var row_index := int(melee_rows[melee_ordinal].row_index)
		var row: Dictionary = rows[row_index]
		var assessment: Dictionary = melee.assess_attack(int(row.action.actor_id), int(row.action.target_id),
			str(row.source), processed_step_index, attack_start_world_time, batch_context, melee_ordinal)
		if assessment.is_empty(): return PlanScript.new({"accepted":false,"reason":"combat_assessment_failed","actor_rows":[],"base_fingerprint":_fingerprint()})
		row.combat_assessment = assessment; rows[row_index] = row
	var max_cost := 0
	for row in rows: max_cost = maxi(max_cost, int(row.time_cost))
	if world.world_time > MAX_WORLD_TIME - max_cost: return PlanScript.new({"accepted":false,"reason":"time_overflow","actor_rows":[],"base_fingerprint":_fingerprint()})
	var schedule_plan := _schedule_preflight(world.world_time + max_cost)
	if not str(schedule_plan.reason).is_empty(): return PlanScript.new({"accepted":false,"reason":str(schedule_plan.reason),"actor_rows":[],"base_fingerprint":_fingerprint()})
	# Include action/damage/death/override rows and the worst-case victory plus
	# zero-time regroup chain (root, every living companion, completion).
	var conservative_events: int = rows.size() * 4 + state.party_member_ids.size() + 4
	conservative_events += schedule_plan.occurrences.size() * (world.tiles.size() * 4 + world.entities.size() * 6 + 4)
	if not world.has_event_id_headroom(conservative_events): return PlanScript.new({"accepted":false,"reason":"event_id_overflow","actor_rows":[],"base_fingerprint":_fingerprint()})
	var timeline: Array = []
	for occurrence in schedule_plan.occurrences:
		timeline.append({"kind": str(occurrence.kind), "at_time": str(occurrence.due_time), "schedule_id": str(occurrence.schedule_id)})
	var data := {"accepted": true, "reason": "ok", "canonical_request": request.to_dict(), "base_step": str(world.step_index),
		"base_time": str(world.world_time), "base_revision": str(state.revision), "base_fingerprint": _fingerprint(),
		"actor_rows": rows, "total_time_cost": max_cost, "timeline": timeline}
	data["plan_hash"] = PlanScript.canonical_hash(data)
	return PlanScript.new(data)

func _turn_rejection(request) -> String:
	if world.party_encounter == null or world.party_encounter.safe_phase != "ENGAGED" or not world.is_settled(): return "party_turn_phase_required"
	if request == null or not request is PartyTurnRequest or request.protagonist_action == null: return "invalid_party_request"
	var request_wire: Variant = request.to_dict()
	var wire_error := RequestScript.wire_error(request_wire)
	if not wire_error.is_empty(): return wire_error
	var state = world.party_encounter; var direct = request.protagonist_action
	if direct.actor_id != state.protagonist_id: return "protagonist_action_required"
	var error := _action_error(direct); if not error.is_empty(): return error
	var seen: Dictionary = {}; var previous := 0
	for row in request.overrides:
		if not row is Dictionary or not row.has_all(["actor_id", "action"]): return "invalid_override_shape"
		var id := int(row.actor_id)
		if id <= previous or seen.has(id) or id == state.protagonist_id: return "duplicate_or_unsorted_override"
		if not state.member_rows.has(id) or state.member(id).presence != "DEPLOYED": return "override_actor_not_deployed"
		if row.action == null or row.action.actor_id != id: return "override_actor_mismatch"
		error = _action_error(row.action); if not error.is_empty(): return error
		seen[id] = true; previous = id
	return ""

func _action_error(action) -> String:
	if action == null or action.type not in ActionScript.TYPES or not world.entities.has(action.actor_id): return "invalid_party_action"
	var state = world.party_encounter; var member = state.member(action.actor_id)
	if member == null or member.presence != "DEPLOYED" or not world.can_act(action.actor_id, world.world_time): return "party_actor_unavailable"
	if member.busy_until > world.world_time: return "party_actor_busy"
	if action.type == "MOVE":
		var assessment = movement.assess_move(action.actor_id, action.destination); return "" if assessment.accepted else assessment.reason
	if action.type == "MELEE":
		if action.target_id not in state.enemy_ids or not world.entities.has(action.target_id) \
				or not world.is_explicit_melee_target(action.target_id) or not melee.can_attack(action.actor_id, action.target_id):
			return "melee_not_legal"
	return ""

func _suggest(actor_id: int, protagonist_action):
	var actor = world.entities[actor_id]
	var member = world.party_encounter.member(actor_id)
	var aggression: int = member.personality_profile.value("aggression") if member.personality_profile != null else 500
	var boldness: int = member.personality_profile.value("boldness") if member.personality_profile != null else 500
	var composure: int = member.personality_profile.value("composure") if member.personality_profile != null else 500
	var relation: Dictionary = _relation_values(actor_id)
	var enemies: Array = []
	for enemy_id in world.party_encounter.enemy_ids:
		if world.is_autonomous_target(enemy_id): enemies.append(world.entities[enemy_id])
	enemies.sort_custom(func(a,b): return a.id < b.id)
	if enemies.is_empty(): return ActionScript.hold(actor_id)
	var focus_id := _direct_focus_enemy_id(protagonist_action, enemies)
	var drive: int = aggression * 2 + boldness
	var hold_score: int = 1100 + int((999 - boldness) / 4) - int(aggression / 5)
	var candidates: Array = []
	for enemy in enemies:
		var support_score := _target_support_score(enemy.id, focus_id, relation)
		if melee.can_attack(actor_id, enemy.id):
			candidates.append({"kind":"MELEE", "target_id":enemy.id, "destination":actor.position,
				"approach":actor.position, "score":700 + drive + support_score - _hazard_penalty(actor_id, actor.position, composure),
				"total_cost":0, "steps":0})
			continue
		var approach_cells: Array[Vector2i] = []
		for direction in movement.MOVE_DIRECTIONS_8:
			var approach: Vector2i = enemy.position + direction
			if world.in_bounds(approach): approach_cells.append(approach)
		approach_cells.sort_custom(func(a:Vector2i,b:Vector2i): return a.y < b.y if a.y != b.y else a.x < b.x)
		var path: Dictionary = pathfinder.find_path_to_any(actor_id, approach_cells)
		if not bool(path.get("found", false)) or int(path.get("steps", 0)) < 1 or path.path.size() < 2: continue
		var first_step: Vector2i = path.path[1]; var approach: Vector2i = path.goal
		if not movement.assess_move(actor_id, first_step).accepted: continue
		candidates.append({"kind":"MOVE", "target_id":enemy.id, "destination":first_step,
			"approach":approach, "score":400 + drive + support_score - int(path.total_cost) \
				- int(path.steps) * 20 - _hazard_penalty(actor_id, first_step, composure),
			"total_cost":int(path.total_cost), "steps":int(path.steps)})
	if candidates.is_empty(): return ActionScript.hold(actor_id)
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):
		if int(a.score) != int(b.score): return int(a.score) > int(b.score)
		if int(a.total_cost) != int(b.total_cost): return int(a.total_cost) < int(b.total_cost)
		if int(a.steps) != int(b.steps): return int(a.steps) < int(b.steps)
		if int(a.target_id) != int(b.target_id): return int(a.target_id) < int(b.target_id)
		var aa:Vector2i=a.approach; var ba:Vector2i=b.approach
		if aa.y != ba.y: return aa.y < ba.y
		if aa.x != ba.x: return aa.x < ba.x
		var ad:Vector2i=a.destination; var bd:Vector2i=b.destination
		return ad.y < bd.y if ad.y != bd.y else ad.x < bd.x)
	var selected: Dictionary = candidates[0]
	if int(selected.score) < hold_score: return ActionScript.hold(actor_id)
	return ActionScript.melee(actor_id, int(selected.target_id)) if selected.kind == "MELEE" \
		else ActionScript.move_to(actor_id, selected.destination)

func _direct_focus_enemy_id(action, enemies: Array) -> int:
	if action != null and action.type == "MELEE": return action.target_id
	var focus_position: Vector2i = world.entities[world.party_encounter.protagonist_id].position
	if action != null and action.type == "MOVE": focus_position = action.destination
	var ranked: Array = enemies.duplicate()
	ranked.sort_custom(func(a,b):
		var ad:=_distance(focus_position,a.position); var bd:=_distance(focus_position,b.position)
		return ad < bd if ad != bd else a.id < b.id)
	return -1 if ranked.is_empty() else int(ranked[0].id)

func _target_support_score(enemy_id: int, focus_id: int, relation: Dictionary) -> int:
	if enemy_id != focus_id: return 0
	var relation_drive: int = int(relation.trust) * 4 + int(relation.gratitude) * 3 - int(relation.grievance) * 4
	return relation_drive * 2

func _hazard_penalty(actor_id: int, position: Vector2i, composure: int) -> int:
	if exposure == null: return 0
	var evaluated = exposure.evaluate_for_entity(actor_id, position)
	if evaluated == null or not evaluated is Dictionary or evaluated.get("evaluation") == null: return 0
	var risk: int = maxi(0, int(evaluated.evaluation.total_risk))
	return int(risk * (1500 - clampi(composure, 0, 999)) / 30)

func _action_row(action, source: String, roster_slot: int) -> Dictionary:
	var cost := PARTY_ACTION_COST
	if action.type == "MOVE": cost = int(TerrainRegistryScript.definition(world.tile_at(action.destination).terrain).move_time_cost)
	return {"actor_id": action.actor_id, "roster_slot": roster_slot, "source": source, "action": action.to_dict(), "time_cost": cost,
		"resolution_note": "", "suggestion": null, "overridden": false, "combat_assessment": null}

func _resolve_move_conflicts(rows: Array) -> String:
	var by_destination: Dictionary = {}
	for row in rows:
		if row.action.type != "MOVE": continue
		var key := "%s:%s" % [row.action.destination[0], row.action.destination[1]]
		if not by_destination.has(key): by_destination[key] = []
		by_destination[key].append(row)
	var destination_keys: Array = by_destination.keys(); destination_keys.sort()
	for key in destination_keys:
		var contenders: Array = by_destination[key]
		if contenders.size() < 2: continue
		contenders.sort_custom(func(a,b):
			var rank := {"DIRECT": 0, "OVERRIDE": 1, "SUGGESTED": 2}
			if rank[a.source] != rank[b.source]: return rank[a.source] < rank[b.source]
			return a.roster_slot < b.roster_slot if a.roster_slot != b.roster_slot else a.actor_id < b.actor_id)
		for index in range(1, contenders.size()):
			if contenders[index].source != "SUGGESTED": return "destination_conflict"
			contenders[index].action = ActionScript.hold(int(contenders[index].actor_id)).to_dict(); contenders[index].time_cost = 100; contenders[index].resolution_note = "destination_conflict_suggested_hold"
	return ""

func _enemy_batch(processed_step_index: int, actor_schedule_id: int, due_time: int,
		tick_start_can_act_ids: Dictionary, allow_victory: bool = true) -> bool:
	if processed_step_index <= 0 or world._active_step_index != processed_step_index \
			or actor_schedule_id <= 0 or due_time != world.world_time:
		return false
	var state = world.party_encounter; var enemies: Array = state.enemy_ids.duplicate(); enemies.sort()
	var rows: Array[Dictionary] = []
	for enemy_id in enemies:
		if not tick_start_can_act_ids.has(enemy_id) \
				or not world.can_act(enemy_id, world.world_time) \
				or int(state.enemy_busy_rows[enemy_id]) > world.world_time: continue
		var forecast := forecast_enemy_action(enemy_id)
		if not bool(forecast.get("accepted", false)): continue
		rows.append({"enemy_id": enemy_id, "target_id": int(forecast.target_id),
			"original_action_order": rows.size(), "action_type": str(forecast.action_type),
			"destination": forecast.destination.duplicate(true),
			"terrain_id": str(forecast.terrain_id), "time_cost": int(forecast.time_cost),
			"melee": str(forecast.action_type) == "MELEE"})
	var melee_rows: Array[Dictionary] = []
	for row in rows:
		if bool(row.melee): melee_rows.append(row)
	melee_rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.target_id) != int(b.target_id): return int(a.target_id) < int(b.target_id)
		if int(a.enemy_id) != int(b.enemy_id): return int(a.enemy_id) < int(b.enemy_id)
		return int(a.original_action_order) < int(b.original_action_order))
	var context := "PARTY_ENEMY/%d/%d" % [actor_schedule_id, due_time]
	var frozen_intents: Array = []
	for ordinal in range(melee_rows.size()):
		var row: Dictionary = melee_rows[ordinal]
		var target = world.entities.get(int(row.target_id))
		var assessment: Dictionary = melee.assess_attack(int(row.enemy_id), int(row.target_id),
			"SUGGESTED", processed_step_index, due_time, context, ordinal)
		var frozen = melee.freeze_assessment(assessment,
			target.health if target != null else -1, int(row.original_action_order),
			int(row.target_id) == state.protagonist_id)
		if assessment.is_empty() or frozen == null: return false
		frozen_intents.append(frozen)
	var projected_results: Array = melee.project_batch(frozen_intents)
	if projected_results.size() != frozen_intents.size():
		return false
	var canonical_batch: bool = not frozen_intents.is_empty()
	var frozen_by_actor: Dictionary = {}
	var resolution_by_actor: Dictionary = {}
	if canonical_batch:
		for frozen in frozen_intents:
			frozen_by_actor[int(str(frozen.assessment.attacker_id))] = frozen
		for resolution in projected_results:
			resolution_by_actor[int(str(resolution.action_data.get("intent_ordinal", -1)))] = resolution
	var pending_results: Array[Dictionary] = []
	for row in rows:
		var enemy_id := int(row.enemy_id)
		var action_cost := 100
		var action_event = null
		if bool(row.melee):
			var frozen = frozen_by_actor.get(enemy_id)
			var ordinal := int(frozen.assessment.intent_ordinal) if frozen != null else -1
			var resolution = resolution_by_actor.get(ordinal)
			if not canonical_batch or frozen == null or resolution == null:
				return false
			var assessment: Dictionary = frozen.assessment
			var frozen_position := Vector2i(int(assessment.target_position[0]),
				int(assessment.target_position[1]))
			action_event = world.emit_event("action.melee_attack", enemy_id,
				int(row.target_id), frozen_position, int(assessment.base_damage), -1,
				resolution.action_data)
			if action_event != null:
				pending_results.append({"action": action_event, "intent": frozen,
					"resolution": resolution})
		elif str(row.action_type) == "MOVE":
			var destination := Vector2i(int(row.destination[0]), int(row.destination[1]))
			action_cost = int(row.time_cost)
			action_event = movement.commit_preflighted_move(enemy_id, destination,
				str(row.terrain_id), action_cost)
		else:
			action_event = _commit_hold(enemy_id, 100)
		if action_event == null or _fault("enemy_leaf"):
			return false
		if world.world_time > MAX_WORLD_TIME - action_cost:
			return false
		state.enemy_busy_rows[enemy_id] = world.world_time + action_cost
	pending_results.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.resolution.action_data.intent_ordinal) \
			< int(b.resolution.action_data.intent_ordinal))
	for pending in pending_results:
		var action = pending.action
		var resolution = pending.resolution
		var target = world.entities.get(action.target_id)
		var target_state = world.combatant_states.get(action.target_id)
		if target == null or target_state == null \
				or target.health != resolution.target_health_before \
				or target_state.life_state != resolution.target_life_before:
			return false
		if resolution.outcome == "OVERKILL_SKIP":
			continue
		if resolution.outcome == "MISS":
			if world.emit_event("combat.attack_missed", -1, action.target_id,
					action.position, 0, action.id, {"schema_version": 1,
						"combat_ruleset_id": MeleeScript.COMBAT_RULESET_ID,
						"outcome": "MISS"}) == null:
				return false
		elif resolution.outcome == "HIT":
			var applied: Dictionary = damage.apply_canonical_active_damage(target,
				resolution.final_damage, "physical", action.id, action.position,
				processed_step_index, resolution.target_health_before,
				resolution.terminal_immediate, resolution.bleed_proc_succeeded)
			if not bool(applied.accepted) \
					or int(applied.applied_health_damage) \
					!= resolution.target_health_before - resolution.target_health_after:
				return false
		else:
			return false
		if target.health != resolution.target_health_after \
				or target_state.life_state != resolution.target_life_after:
			return false
	return reconcile_liveness(allow_victory)


func forecast_enemy_action(enemy_id: int) -> Dictionary:
	# This is the single pure selector used by both the mobile forecast and the
	# canonical enemy batch. The UI describes it as a current-state forecast:
	# player movement can legitimately change the next scheduled evaluation.
	var rejected := {"accepted":false, "reason":"enemy_unavailable",
		"enemy_id":enemy_id, "target_id":-1, "action_type":"HOLD",
		"from_position":[-1,-1], "destination":[-1,-1],
		"terrain_id":"", "time_cost":PARTY_ACTION_COST}
	if world == null or world.party_encounter == null \
			or enemy_id not in world.party_encounter.enemy_ids \
			or not world.entities.has(enemy_id) \
			or not world.is_autonomous_target(enemy_id):
		return rejected.duplicate(true)
	var enemy = world.entities[enemy_id]
	rejected.from_position = [enemy.position.x, enemy.position.y]
	var target = _nearest_deployed_party(enemy.position)
	if target == null:
		rejected.reason = "enemy_target_unavailable"
		return rejected.duplicate(true)
	rejected.accepted = true
	rejected.target_id = target.id
	if melee.can_attack(enemy_id, target.id):
		rejected.reason = "target_adjacent"
		rejected.action_type = "MELEE"
		return rejected.duplicate(true)
	var direction := Vector2i(signi(target.position.x-enemy.position.x),
		signi(target.position.y-enemy.position.y))
	var destination: Vector2i = enemy.position + direction
	var assessment = movement.assess_move(enemy_id, destination)
	if assessment.accepted:
		var terrain_id := str(assessment.terrain_id)
		rejected.reason = "approach_nearest_target"
		rejected.action_type = "MOVE"
		rejected.destination = [destination.x, destination.y]
		rejected.terrain_id = terrain_id
		rejected.time_cost = int(TerrainRegistryScript.definition(terrain_id).move_time_cost)
	else:
		rejected.reason = "approach_blocked_guard"
	return rejected.duplicate(true)

func _nearest_alive_enemy(position: Vector2i):
	var candidates: Array = []
	for id in world.party_encounter.enemy_ids:
		if world.is_unresolved_enemy(id): candidates.append(world.entities[id])
	candidates.sort_custom(func(a,b): var ad = _distance(position,a.position); var bd = _distance(position,b.position); return ad < bd if ad != bd else a.id < b.id)
	return null if candidates.is_empty() else candidates[0]

func _nearest_deployed_party(position: Vector2i):
	var candidates: Array = []
	for id in world.party_encounter.party_member_ids:
		if world.party_encounter.member(id).presence == "DEPLOYED" and world.is_autonomous_target(id): candidates.append(world.entities[id])
	candidates.sort_custom(func(a,b): var ad = _distance(position,a.position); var bd = _distance(position,b.position); return ad < bd if ad != bd else a.id < b.id)
	return null if candidates.is_empty() else candidates[0]

func _deployment_cell_valid(position: Vector2i, reserved: Dictionary, anchor: Vector2i) -> bool:
	if not world.in_bounds(position) or reserved.has(_key(position)): return false
	var definition = TerrainRegistryScript.definition(world.tile_at(position).terrain)
	if definition.is_empty() or not bool(definition.passable) or world.blocking_entity_at(position) != null:return false
	var delta:=position-anchor
	if absi(delta.x)==1 and absi(delta.y)==1:
		for flank in [anchor+Vector2i(delta.x,0),anchor+Vector2i(0,delta.y)]:
			if not world.in_bounds(flank) or reserved.has(_key(flank)) \
					or world.blocking_entity_at(flank)!=null \
					or not bool(TerrainRegistryScript.definition(world.tile_at(flank).terrain).get("passable",false)):
				return false
	return true


func _commit_hold(actor_id: int, magnitude: int, cause_id: int = -1):
	if not world.entities.has(actor_id) or not world.combatant_states.has(actor_id) \
			or world.world_time > MAX_WORLD_TIME - 200:
		return null
	var hold = world.emit_event("action.hold", actor_id, -1,
		world.entities[actor_id].position, magnitude, cause_id)
	if hold == null: return null
	var combatant = world.combatant_states[actor_id]
	var candidate_until: int = hold.world_time + 200
	if candidate_until > combatant.guarded_until:
		combatant.guarded_until = candidate_until
		combatant.guard_source_event_id = hold.id
	return hold

func _fallback_cell(anchor: Vector2i, reserved: Dictionary):
	var candidates: Array = []
	for radius in [1,2]:
		for y in range(anchor.y-radius, anchor.y+radius+1):
			for x in range(anchor.x-radius, anchor.x+radius+1):
				var p := Vector2i(x,y)
				if _distance(anchor,p) == radius and _deployment_cell_valid(p,reserved,anchor): candidates.append(p)
		if not candidates.is_empty(): break
	candidates.sort_custom(func(a,b): var am = absi(a.x-anchor.x)+absi(a.y-anchor.y); var bm=absi(b.x-anchor.x)+absi(b.y-anchor.y); return am < bm if am != bm else (a.y < b.y if a.y != b.y else a.x < b.x))
	return null if candidates.is_empty() else candidates[0]

func _formation_offset(preset: String, index: int, facing: Vector2i) -> Vector2i:
	var back := -facing; var right := Vector2i(-facing.y, facing.x); var left := -right
	if preset == "WEDGE": return back + (left if index == 0 else right)
	if preset == "LINE": return left if index == 0 else right
	return back * (index + 1)

func _cardinal_facing(delta: Vector2i) -> Vector2i:
	if absi(delta.y) >= absi(delta.x): return Vector2i(0, signi(delta.y))
	return Vector2i(signi(delta.x), 0)

func _distance(a: Vector2i, b: Vector2i) -> int: return maxi(absi(a.x-b.x), absi(a.y-b.y))
func _key(p: Vector2i) -> String: return "%d:%d" % [p.x,p.y]
func _fingerprint() -> String: return JSON.stringify(world.snapshot()).sha256_text()
func _hash_without(data: Dictionary, key: String) -> String: var copy = data.duplicate(true); copy.erase(key); return JSON.stringify(copy).sha256_text()
func _normalize_schedules() -> void:
	var due: int = world.world_time - (world.world_time % 100) + 100
	for entry in world.scheduled_entries: entry.due_time = due

func _contact_event_id() -> int:
	for index in range(world.events.size() - 1, -1, -1):
		if world.events[index].type in ["encounter.detected", "encounter.party_ambush", "encounter.enemy_ambush"]:
			return world.events[index].id
	return -1

func _deployment_plan_error(plan: Variant) -> String:
	if not plan is Dictionary:
		return "invalid_deployment_plan"
	var keys: Array = plan.keys(); keys.sort()
	var accepted: bool = plan.get("accepted") is bool and bool(plan.accepted)
	var expected_keys := ["accepted", "base_fingerprint", "companion_ids", "placements", "preset_id", "reason"]
	if accepted:
		expected_keys.append("plan_hash")
		expected_keys.sort()
	if keys != expected_keys:
		return "invalid_deployment_plan_keys"
	if not plan.get("accepted") is bool or not plan.get("reason") is String \
			or not plan.get("preset_id") is String or not plan.get("base_fingerprint") is String \
			or not plan.get("companion_ids") is Array or not plan.get("placements") is Array:
		return "invalid_deployment_plan_shape"
	if accepted and (not plan.get("plan_hash") is String or str(plan.plan_hash).length() != 64 \
			or str(plan.base_fingerprint).length() != 64 or str(plan.reason) != "ok"):
		return "invalid_deployment_plan_hash"
	var seen_ids: Dictionary = {}
	for value in plan.companion_ids:
		if not value is int or int(value) <= 0 or seen_ids.has(int(value)):
			return "invalid_companion_ids"
		seen_ids[int(value)] = true
	for placement in plan.placements:
		if not placement is Dictionary:
			return "invalid_deployment_placement"
		var placement_keys: Array = placement.keys(); placement_keys.sort()
		if placement_keys != ["entity_id", "placement", "position", "roster_slot"] \
				or not placement.entity_id is int or int(placement.entity_id) <= 0 \
				or not placement.roster_slot is int or int(placement.roster_slot) < 0 \
				or placement.placement not in ["anchor", "preset", "fallback"] \
				or not placement.position is Array or placement.position.size() != 2 \
				or not placement.position[0] is int or not placement.position[1] is int:
			return "invalid_deployment_placement"
	return ""

func _schedule_preflight(end_time: int) -> Dictionary:
	var occurrences: Array = []
	for raw_entry in world.scheduled_entries:
		var entry: Dictionary = raw_entry.duplicate(true)
		while int(entry.due_time) <= end_time:
			occurrences.append(entry.duplicate(true))
			if occurrences.size() > MAX_SCHEDULE_OCCURRENCES:
				return {"reason": "schedule_budget_exceeded", "occurrences": []}
			if str(entry.kind) == "system.actor_tick" and int(entry.due_time) > MAX_WORLD_TIME - 10000:
				return {"reason": "time_overflow", "occurrences": []}
			var interval := int(entry.repeat_interval)
			if interval <= 0:
				break
			if int(entry.due_time) > MAX_WORLD_TIME - interval:
				return {"reason": "time_overflow", "occurrences": []}
			entry.due_time = int(entry.due_time) + interval
	occurrences.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.due_time) != int(b.due_time): return int(a.due_time) < int(b.due_time)
		if int(a.priority) != int(b.priority): return int(a.priority) < int(b.priority)
		return int(a.schedule_id) < int(b.schedule_id))
	return {"reason": "", "occurrences": occurrences}

func _has_alive_enemy() -> bool:
	if world.party_encounter == null:
		return false
	for enemy_id in world.party_encounter.enemy_ids:
		if world.entities.has(enemy_id) and world.is_unresolved_enemy(enemy_id):
			return true
	return false

func _last_enemy_death_event_id() -> int:
	if world.party_encounter == null: return -1
	for index in range(world.events.size() - 1, -1, -1):
		var event = world.events[index]
		if event.type == "entity.died" and event.target_id in world.party_encounter.enemy_ids:
			return event.id
	return -1

func _fault(point: String) -> bool:
	return not fail_point.is_empty() and fail_point == point

func _relation_values(observer_id:int)->Dictionary:
	var protagonist_id:int=world.party_encounter.protagonist_id
	var observer=world.entities[observer_id];var protagonist=world.entities[protagonist_id]
	var base:Dictionary=world.species_relations.get_relation(observer.species_id,protagonist.species_id)
	var personal=world.personal_relations.get("%d:%d"%[observer_id,protagonist_id])
	return {"trust":clampi(int(base.base_trust)+(int(personal.personal_trust_delta) if personal!=null else 0),-100,100),
		"gratitude":int(personal.gratitude) if personal!=null else 0,"grievance":int(personal.grievance) if personal!=null else 0}
func _result(accepted: bool, reason: String, events: Array, cost: int,
		processed_step_index: int):
	return load("res://sim/sim_step_result.gd").new(accepted, accepted and cost > 0, reason, events,
		{"processed_step_index": processed_step_index if accepted else -1,
		"start_time": world.world_time-cost, "end_time": world.world_time, "time_cost": cost,
		"timeline": [], "root_event_id": events[0].id if not events.is_empty() else -1})
