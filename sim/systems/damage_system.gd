class_name DamageSystem
extends RefCounted

const COMBAT_RULESET_ID := "deterministic-melee-resolution-v1"
const LIFE_RULESET_ID := "active-downed-dead-v1"
const STATUS_RULESET_ID := "bounded-status-lifecycle-v1"
const ACTOR_INTERVAL := 100
const MAX_WORLD_TIME := 9223372036854775707
const StatusRowScript = preload("res://sim/combat_status_row.gd")
const StatusRegistryScript = preload("res://sim/status_registry.gd")

var world


func _init(p_world) -> void:
	world = p_world


func apply_canonical_active_damage(entity, requested_damage: int, damage_type: String,
		cause_id: int, event_position: Vector2i, processed_step_index: int,
		expected_health_before: int, terminal_immediate: bool = false,
		apply_bleed_status: bool = false) -> Dictionary:
	var resolved_position: Vector2i = entity.position \
		if entity != null and event_position == Vector2i(-1, -1) else event_position
	var cause = world.event_by_id(cause_id) if cause_id > 0 else null
	var lethal: bool = entity != null and requested_damage >= expected_health_before
	var protagonist_target: bool = entity != null and world.party_encounter != null \
		and world.party_encounter.protagonist_id == entity.id
	var status_count: int = world.combatant_states[entity.id].status_rows.size() \
		if entity != null and world.combatant_states.has(entity.id) else 0
	var should_apply_bleed: bool = apply_bleed_status and not terminal_immediate
	var required_events := (3 + status_count) if terminal_immediate \
		else ((2 if lethal else 1) + (1 if should_apply_bleed else 0))
	var bleed_rows: Array = []
	if entity != null and world.combatant_states.has(entity.id):
		for status in world.combatant_states[entity.id].status_rows:
			if status.status_id == "BLEEDING": bleed_rows.append(status)
	if entity == null or not world.combatant_states.has(entity.id) \
			or world.combatant_states[entity.id].life_state != "ACTIVE" \
			or damage_type not in ["physical", "fire", "electric"] \
			or requested_damage <= 0 or expected_health_before <= 0 \
			or entity.health != expected_health_before or processed_step_index <= 0 \
			or processed_step_index != world._active_step_index \
			or cause == null or cause.target_id != entity.id \
			or cause.position != resolved_position or cause.step_index != processed_step_index \
			or cause.world_time != world.world_time \
			or bleed_rows.size() > 1 \
			or (apply_bleed_status and (damage_type != "physical" \
				or cause.type != "action.melee_attack" \
				or cause.data.get("schema_version") not in [1, 3] \
				or cause.data.get("combat_ruleset_id") != COMBAT_RULESET_ID \
				or cause.data.get("outcome") != "HIT" \
				or cause.data.get("bleed_proc_succeeded") != true \
				or int(cause.data.get("final_damage", -1)) != requested_damage)) \
			or terminal_immediate != (lethal and protagonist_target) \
			or (lethal and not terminal_immediate \
				and world.world_time > MAX_WORLD_TIME - 200) \
			or (should_apply_bleed and world.world_time > MAX_WORLD_TIME - 300) \
			or not world.has_event_id_headroom(required_events):
		return {"accepted": false, "event": null, "applied_health_damage": 0}
	var applied_damage := mini(expected_health_before, requested_damage)
	entity.health -= applied_damage
	var damage_event = world.emit_event(
		"combat.%s_damage" % damage_type, -1, entity.id, resolved_position,
		applied_damage, cause_id, {"schema_version": 1,
			"combat_ruleset_id": COMBAT_RULESET_ID,
			"damage_type": damage_type, "requested_damage": requested_damage,
			"applied_health_damage": applied_damage})
	if damage_event == null:
		return {"accepted": false, "event": null,
			"applied_health_damage": applied_damage}
	var transition_event = null
	var death_event = null
	var status_event = null
	if lethal:
		var strict_boundary: int = (world.world_time / ACTOR_INTERVAL + 1) * ACTOR_INTERVAL
		var resolve_at := -1 if terminal_immediate else strict_boundary + ACTOR_INTERVAL
		transition_event = world.emit_event("entity.downed", -1, entity.id,
			resolved_position, 0, damage_event.id, {"schema_version": 1,
				"life_ruleset_id": LIFE_RULESET_ID,
				"previous_life_state": "ACTIVE",
				"downed_resolve_at": str(resolve_at),
				"terminal_immediate": terminal_immediate})
		if transition_event == null:
			return {"accepted": false, "event": damage_event,
				"transition_event": null, "applied_health_damage": applied_damage}
		var combatant = world.combatant_states[entity.id]
		combatant.life_state = "DOWNED"
		combatant.guarded_until = 0; combatant.guard_source_event_id = -1
		combatant.downed_at = world.world_time
		combatant.downed_resolve_at = resolve_at
		combatant.downed_source_event_id = transition_event.id
		combatant.recovery_lock_until = 0; combatant.recovery_source_event_id = -1
		if terminal_immediate:
			for status in combatant.status_rows:
				var expired = world.emit_event("status.expired", -1, entity.id,
					resolved_position, 0, transition_event.id, {"schema_version": 1,
						"status_ruleset_id": STATUS_RULESET_ID,
						"status_id": str(status.status_id), "reason": "OWNER_DIED"})
				if expired == null:
					return {"accepted": false, "event": damage_event,
						"transition_event": transition_event, "death_event": null,
						"applied_health_damage": applied_damage}
			death_event = world.emit_event("entity.died", -1, entity.id,
				resolved_position, 0, transition_event.id, {"schema_version": 1,
					"life_ruleset_id": LIFE_RULESET_ID,
					"previous_life_state": "DOWNED", "reason": "PARTY_DEFEAT",
					"damage_type": damage_type})
			if death_event == null:
				return {"accepted": false, "event": damage_event,
					"transition_event": transition_event, "death_event": null,
					"applied_health_damage": applied_damage}
			combatant.life_state = "DEAD"
			combatant.downed_at = -1; combatant.downed_resolve_at = -1
			combatant.downed_source_event_id = -1
			combatant.status_rows.clear()
			world.party_encounter.safe_phase = "PARTY_DEFEATED"
	if should_apply_bleed:
		var status_definition: Dictionary = StatusRegistryScript.definition("BLEEDING")
		if status_definition.is_empty():
			return {"accepted": false, "event": damage_event,
				"transition_event": transition_event, "death_event": death_event,
				"status_event": null, "applied_health_damage": applied_damage}
		var strict_boundary: int = (world.world_time / ACTOR_INTERVAL + 1) * ACTOR_INTERVAL
		var candidate_expires: int = strict_boundary \
			+ (int(status_definition.tick_count_after_apply_or_refresh) - 1) \
			* int(status_definition.tick_interval)
		var existing = bleed_rows[0] if bleed_rows.size() == 1 else null
		var next_tick_at: int = existing.next_tick_at if existing != null else strict_boundary
		var expires_at: int = maxi(existing.expires_at, candidate_expires) \
			if existing != null else candidate_expires
		var event_type := "status.refreshed" if existing != null else "status.applied"
		status_event = world.emit_event(event_type, -1, entity.id, resolved_position,
			0, damage_event.id, {"schema_version": 1,
				"status_ruleset_id": STATUS_RULESET_ID, "status_id": "BLEEDING",
				"next_tick_at": str(next_tick_at), "expires_at": str(expires_at),
				"tick_damage": int(status_definition.tick_damage)})
		if status_event == null:
			return {"accepted": false, "event": damage_event,
				"transition_event": transition_event, "death_event": death_event,
				"status_event": null, "applied_health_damage": applied_damage}
		if existing == null:
			existing = StatusRowScript.new("BLEEDING")
			existing.applied_at = world.world_time
			existing.next_tick_at = next_tick_at
			world.combatant_states[entity.id].status_rows.append(existing)
		existing.refreshed_at = world.world_time
		existing.expires_at = expires_at
		existing.source_event_id = status_event.id
	return {"accepted": true, "event": damage_event,
		"transition_event": transition_event, "death_event": death_event,
		"status_event": status_event,
		"applied_health_damage": applied_damage}


func apply_canonical_downed_finisher(entity, requested_pressure: int, cause_id: int,
		event_position: Vector2i, processed_step_index: int) -> Dictionary:
	var resolved_position: Vector2i = entity.position \
		if entity != null and event_position == Vector2i(-1, -1) else event_position
	var cause = world.event_by_id(cause_id) if cause_id > 0 else null
	var combatant = world.combatant_states.get(entity.id) if entity != null else null
	var status_count: int = combatant.status_rows.size() if combatant != null else 0
	if entity == null or combatant == null or combatant.life_state != "DOWNED" \
			or entity.health != 0 or requested_pressure <= 0 \
			or processed_step_index <= 0 or processed_step_index != world._active_step_index \
			or cause == null or cause.type != "action.melee_attack" \
			or cause.target_id != entity.id or cause.position != resolved_position \
			or cause.step_index != processed_step_index or cause.world_time != world.world_time \
			or cause.data.get("schema_version") != 1 \
			or cause.data.get("intent_mode") != "FINISHER" \
			or cause.data.get("outcome") != "FINISHER" \
			or not world.has_event_id_headroom(2 + status_count):
		return {"accepted": false, "event": null, "death_event": null}
	var pressure = world.emit_event("combat.downed_damage", -1, entity.id,
		resolved_position, requested_pressure, cause_id, {"schema_version": 1,
			"combat_ruleset_id": COMBAT_RULESET_ID, "damage_type": "physical",
			"requested_damage": requested_pressure, "applied_health_damage": 0,
			"reason": "FINISHER"})
	if pressure == null:
		return {"accepted": false, "event": null, "death_event": null}
	for status in combatant.status_rows:
		var expired = world.emit_event("status.expired", -1, entity.id,
			resolved_position, 0, pressure.id, {"schema_version": 1,
				"status_ruleset_id": STATUS_RULESET_ID,
				"status_id": str(status.status_id), "reason": "OWNER_DIED"})
		if expired == null:
			return {"accepted": false, "event": pressure, "death_event": null}
	var death = world.emit_event("entity.died", -1, entity.id, resolved_position,
		0, pressure.id, {"schema_version": 1, "life_ruleset_id": LIFE_RULESET_ID,
			"previous_life_state": "DOWNED", "reason": "FINISHER",
			"damage_type": "physical"})
	if death == null:
		return {"accepted": false, "event": pressure, "death_event": null}
	combatant.life_state = "DEAD"
	combatant.guarded_until = 0; combatant.guard_source_event_id = -1
	combatant.downed_at = -1; combatant.downed_resolve_at = -1
	combatant.downed_source_event_id = -1
	combatant.recovery_lock_until = 0; combatant.recovery_source_event_id = -1
	combatant.status_rows.clear()
	return {"accepted": true, "event": pressure, "death_event": death}


func apply_canonical_downed_bleedout(entity, requested_pressure: int, cause_id: int,
		event_position: Vector2i, processed_step_index: int) -> Dictionary:
	var resolved_position: Vector2i = entity.position \
		if entity != null and event_position == Vector2i(-1, -1) else event_position
	var cause = world.event_by_id(cause_id) if cause_id > 0 else null
	var combatant = world.combatant_states.get(entity.id) if entity != null else null
	var status_count: int = combatant.status_rows.size() if combatant != null else 0
	if entity == null or combatant == null or combatant.life_state != "DOWNED" \
			or entity.health != 0 or requested_pressure <= 0 \
			or processed_step_index <= 0 or processed_step_index != world._active_step_index \
			or cause == null or cause.type != "status.tick" \
			or cause.target_id != entity.id or cause.position != resolved_position \
			or cause.magnitude != requested_pressure \
			or cause.step_index != processed_step_index or cause.world_time != world.world_time \
			or cause.data.get("schema_version") != 1 \
			or cause.data.get("status_ruleset_id") != STATUS_RULESET_ID \
			or cause.data.get("status_id") != "BLEEDING" \
			or cause.data.get("tick_damage") != requested_pressure \
			or status_count != 1 or combatant.status_rows[0].status_id != "BLEEDING" \
			or not world.has_event_id_headroom(2 + status_count):
		return {"accepted": false, "event": null, "death_event": null}
	var pressure = world.emit_event("combat.downed_damage", -1, entity.id,
		resolved_position, requested_pressure, cause_id, {"schema_version": 1,
			"combat_ruleset_id": COMBAT_RULESET_ID, "damage_type": "physical",
			"requested_damage": requested_pressure, "applied_health_damage": 0,
			"reason": "BLEEDOUT"})
	if pressure == null:
		return {"accepted": false, "event": null, "death_event": null}
	for status in combatant.status_rows:
		var expired = world.emit_event("status.expired", -1, entity.id,
			resolved_position, 0, pressure.id, {"schema_version": 1,
				"status_ruleset_id": STATUS_RULESET_ID,
				"status_id": str(status.status_id), "reason": "OWNER_DIED"})
		if expired == null:
			return {"accepted": false, "event": pressure, "death_event": null}
	var death = world.emit_event("entity.died", -1, entity.id, resolved_position,
		0, pressure.id, {"schema_version": 1, "life_ruleset_id": LIFE_RULESET_ID,
			"previous_life_state": "DOWNED", "reason": "BLEEDOUT",
			"damage_type": "physical"})
	if death == null:
		return {"accepted": false, "event": pressure, "death_event": null}
	combatant.life_state = "DEAD"
	combatant.guarded_until = 0; combatant.guard_source_event_id = -1
	combatant.downed_at = -1; combatant.downed_resolve_at = -1
	combatant.downed_source_event_id = -1
	combatant.recovery_lock_until = 0; combatant.recovery_source_event_id = -1
	combatant.status_rows.clear()
	return {"accepted": true, "event": pressure, "death_event": death}


func apply_damage(entity, amount: int, damage_type: String, cause_id: int,
		event_position: Vector2i, processed_step_index: int) -> int:
	if entity == null or not world.combatant_states.has(entity.id) \
			or world.combatant_states[entity.id].life_state != "ACTIVE" or amount <= 0 \
			or processed_step_index <= 0 or processed_step_index != world._active_step_index:
		return 0
	var damage := mini(entity.health, maxi(1, amount))
	entity.health -= damage
	var resolved_position: Vector2i = entity.position if event_position == Vector2i(-1, -1) else event_position
	var damage_event = world.emit_event(
		"combat.%s_damage" % damage_type, -1, entity.id, resolved_position,
		damage, cause_id, {"damage_type": damage_type}
	)
	if entity.health == 0:
		var death_event = world.emit_event(
			"entity.died", -1, entity.id, resolved_position, 0, damage_event.id,
			{"damage_type": damage_type}
		)
		if death_event != null:
			var combatant = world.combatant_states.get(entity.id)
			combatant.life_state = "DEAD"
			combatant.guarded_until = 0; combatant.guard_source_event_id = -1
			combatant.downed_at = -1; combatant.downed_resolve_at = -1; combatant.downed_source_event_id = -1
			combatant.recovery_lock_until = 0; combatant.recovery_source_event_id = -1
			combatant.status_rows.clear()
	return damage
