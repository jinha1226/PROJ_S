class_name StatusLifecycleSystem
extends RefCounted

const LIFE_RULESET_ID := "active-downed-dead-v1"
const STATUS_RULESET_ID := "bounded-status-lifecycle-v1"
const COMBAT_RULESET_ID := "deterministic-melee-resolution-v1"
const RECOVERY_LOCK_DURATION := 100
const STATUS_INTERVAL := 100
const BLEED_TICK_DAMAGE := 3
const MAX_WORLD_TIME := 9223372036854775707

var world
var damage


func _init(p_world, p_damage) -> void:
	world = p_world
	damage = p_damage


func freeze_tick_start_can_act_ids(at_time: int) -> Variant:
	if world == null or at_time != world.world_time:
		return null
	var eligible: Dictionary = {}
	var entity_ids: Array = world.entities.keys()
	entity_ids.sort()
	for entity_id_value in entity_ids:
		var entity_id := int(entity_id_value)
		if world.can_act(entity_id, at_time):
			eligible[entity_id] = true
	return eligible


func process_actor_occurrence(processed_step_index: int,
		tick_start_can_act_ids: Dictionary) -> bool:
	if world == null or processed_step_index <= 0 \
			or world._active_step_index != processed_step_index:
		return false
	for entity_id_value in tick_start_can_act_ids:
		var entity_id := int(entity_id_value)
		if tick_start_can_act_ids[entity_id_value] != true \
				or not world.entities.has(entity_id):
			return false
	if not _process_due_statuses(processed_step_index):
		return false
	return _process_due_recoveries(processed_step_index)


func _process_due_statuses(processed_step_index: int) -> bool:
	var due_rows: Array[Dictionary] = []
	var required_events := 0
	var entity_ids: Array = world.combatant_states.keys()
	entity_ids.sort()
	for entity_id_value in entity_ids:
		var entity_id := int(entity_id_value)
		var entity = world.entities.get(entity_id)
		var combatant = world.combatant_states[entity_id]
		var ordered_statuses: Array = combatant.status_rows.duplicate()
		ordered_statuses.sort_custom(func(a, b): return a.status_id < b.status_id)
		for status in ordered_statuses:
			if status.status_id != "BLEEDING" or entity == null \
					or status.next_tick_at < world.world_time:
				return false
			if status.next_tick_at > world.world_time:
				continue
			if status.next_tick_at > status.expires_at \
					or combatant.life_state not in ["ACTIVE", "DOWNED"] \
					or status.next_tick_at > MAX_WORLD_TIME - STATUS_INTERVAL:
				return false
			var source = world.event_by_id(status.source_event_id)
			if source == null or source.type not in ["status.applied", "status.refreshed"] \
					or source.target_id != entity_id:
				return false
			var downed_owner: bool = combatant.life_state == "DOWNED"
			var lethal: bool = not downed_owner and entity.health <= BLEED_TICK_DAMAGE
			var protagonist_terminal: bool = lethal and world.party_encounter != null \
					and world.party_encounter.protagonist_id == entity_id
			# DOWNED bleedout and immediate protagonist death each add the C1
			# corpse-materialization child after entity.died.
			var damage_events: int = (3 + combatant.status_rows.size()) if downed_owner \
				else ((4 + combatant.status_rows.size()) \
					if protagonist_terminal else (2 if lethal else 1))
			var natural_expiry: bool = not downed_owner \
					and world.world_time >= status.expires_at and not protagonist_terminal
			required_events += 1 + damage_events + (1 if natural_expiry else 0)
			due_rows.append({"entity_id": entity_id, "status": status,
				"downed": downed_owner, "terminal": protagonist_terminal,
				"natural": natural_expiry})
	if due_rows.is_empty():
		return true
	if not world.has_event_id_headroom(required_events):
		return false
	for due in due_rows:
		var entity_id := int(due.entity_id)
		var entity = world.entities.get(entity_id)
		var combatant = world.combatant_states.get(entity_id)
		var status = due.status
		if entity == null or combatant == null \
				or combatant.life_state not in ["ACTIVE", "DOWNED"] \
				or status not in combatant.status_rows \
				or status.next_tick_at != world.world_time:
			return false
		var tick = world.emit_event("status.tick", -1, entity_id, entity.position,
			BLEED_TICK_DAMAGE, status.source_event_id, {"schema_version": 1,
				"status_ruleset_id": STATUS_RULESET_ID, "status_id": "BLEEDING",
				"scheduled_tick_at": str(world.world_time),
				"tick_damage": BLEED_TICK_DAMAGE})
		if tick == null:
			return false
		if bool(due.downed):
			var bleedout: Dictionary = damage.apply_canonical_downed_bleedout(entity,
				BLEED_TICK_DAMAGE, tick.id, entity.position, processed_step_index)
			if not bool(bleedout.accepted):
				return false
			continue
		var health_before: int = entity.health
		var applied: Dictionary = damage.apply_canonical_active_damage(entity,
			BLEED_TICK_DAMAGE, "physical", tick.id, entity.position,
			processed_step_index, health_before, bool(due.terminal), false)
		if not bool(applied.accepted):
			return false
		if combatant.life_state == "DEAD":
			continue
		status.next_tick_at += STATUS_INTERVAL
		if bool(due.natural):
			var expired = world.emit_event("status.expired", -1, entity_id,
				entity.position, 0, tick.id, {"schema_version": 1,
					"status_ruleset_id": STATUS_RULESET_ID,
					"status_id": "BLEEDING", "reason": "NATURAL"})
			if expired == null:
				return false
			combatant.status_rows.erase(status)
	return true


func _process_due_recoveries(_processed_step_index: int) -> bool:
	var due_ids: Array[int] = []
	var combatant_ids: Array = world.combatant_states.keys()
	combatant_ids.sort()
	for entity_id_value in combatant_ids:
		var entity_id := int(entity_id_value)
		var combatant = world.combatant_states[entity_id]
		if combatant.life_state != "DOWNED" or combatant.downed_resolve_at < 0 \
				or world.world_time < combatant.downed_resolve_at:
			continue
		if world.party_encounter != null \
				and entity_id == world.party_encounter.protagonist_id:
			return false
		if not combatant.status_rows.is_empty():
			continue
		var entity = world.entities.get(entity_id)
		var downed_source = world.event_by_id(combatant.downed_source_event_id)
		if entity == null or entity.max_health <= 0 \
				or downed_source == null or downed_source.type != "entity.downed" \
				or downed_source.target_id != entity_id:
			return false
		due_ids.append(entity_id)
	if due_ids.is_empty():
		return true
	if world.world_time > MAX_WORLD_TIME - RECOVERY_LOCK_DURATION \
			or not world.has_event_id_headroom(due_ids.size()):
		return false
	for entity_id in due_ids:
		var entity = world.entities[entity_id]
		var combatant = world.combatant_states[entity_id]
		var recovered_health: int = maxi(1, int((entity.max_health + 9) / 10))
		var recovery_lock_until: int = world.world_time + RECOVERY_LOCK_DURATION
		var recovered = world.emit_event("entity.recovered", -1, entity_id,
			entity.position, recovered_health, combatant.downed_source_event_id,
			{"schema_version": 1, "life_ruleset_id": LIFE_RULESET_ID,
				"recovered_health": recovered_health,
				"recovery_lock_until": str(recovery_lock_until)})
		if recovered == null:
			return false
		entity.health = recovered_health
		combatant.life_state = "ACTIVE"
		combatant.guarded_until = 0
		combatant.guard_source_event_id = -1
		combatant.downed_at = -1
		combatant.downed_resolve_at = -1
		combatant.downed_source_event_id = -1
		combatant.recovery_lock_until = recovery_lock_until
		combatant.recovery_source_event_id = recovered.id
	return true
