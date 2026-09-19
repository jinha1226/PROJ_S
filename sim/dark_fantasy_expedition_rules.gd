extends RefCounted

const State = preload("res://sim/dark_fantasy_expedition_state.gd")
const LIFE_RULESET_ID := "active-downed-dead-v1"

const DAMAGE_STRESS := 4
const DYING_STRESS := 10
const DEATH_STRESS := 20
const CAMP_HEAL_CP := 2
const CAMP_STRESS_CP := 2
const CAMP_INJURY_CP := 2
const CAMP_STRESS_RECOVERY := 20
const INJURY_SPROINED_ANKLE := "SPRAINED_ANKLE"

static func active(world) -> bool:
	return world != null and world.party_encounter != null \
		and world.party_encounter.dark_expedition != null \
		and world.party_encounter.dark_expedition.phase in ["ACTIVE", "CAMP"]

static func start(world, expedition_id: String = "", gold: int = 0) -> Dictionary:
	if world == null or world.party_encounter == null:
		return reject("world_unavailable")
	if world.party_encounter.dark_expedition != null:
		return reject("expedition_already_active")
	var id := expedition_id if not expedition_id.is_empty() else "DFE-%d-%d" % [world.seed, world.step_index]
	var state = State.start(id, gold, world.party_encounter.active_party_member_ids)
	if state == null:
		return reject("expedition_state_invalid")
	world.party_encounter.dark_expedition = state
	world.party_encounter.revision += 1
	return {"accepted": true, "reason": "ok", "expedition_id": id}

static func status(world) -> Dictionary:
	if world == null or world.party_encounter == null or world.party_encounter.dark_expedition == null:
		return {"active": false}
	var state = world.party_encounter.dark_expedition
	var members: Array = []
	for id in world.party_encounter.party_member_ids:
		if not state.member_rows.has(str(id)):
			state.ensure_member(int(id))
		var entity = world.entities.get(int(id)); var row: Dictionary = state.member(int(id))
		members.append({"entity_id": int(id), "health": int(entity.health) if entity != null else 0,
			"max_health": int(entity.max_health) if entity != null else 0,
			"stress": int(row.get("stress", 0)), "death_tokens": int(row.get("death_tokens", 0)),
			"injury_ids": row.get("injury_ids", []).duplicate(),
			"stress_band": stress_band(int(row.get("stress", 0))),
			"life_state": str(world.combatant_states[int(id)].life_state) if world.combatant_states.has(int(id)) else "DEAD"})
	return {"active": true, "expedition_id": state.expedition_id, "phase": state.phase,
		"room_index": state.room_index, "completed_rooms": state.completed_rooms.duplicate(),
		"camp_available": state.camp_available, "camp_cp": state.camp_cp,
		"rescue_supplies": state.rescue_supplies, "earned_gold": state.earned_gold,
		"preserved_gold": state.preserved_gold, "settlement_state": state.settlement_state,
		"members": members}

static func complete_room(world, room_index: int) -> Dictionary:
	if not active(world): return reject("expedition_not_active")
	if not world.party_encounter.dark_expedition.complete_room(room_index):
		return reject("room_progress_invalid")
	return {"accepted": true, "reason": "camp_available" if room_index == 0 else "room_complete",
		"room_index": room_index}

static func enter_camp(world) -> Dictionary:
	if not active(world) or not world.party_encounter.dark_expedition.enter_camp():
		return reject("camp_unavailable")
	return {"accepted": true, "reason": "ok", "camp_cp": world.party_encounter.dark_expedition.camp_cp}

static func leave_camp(world) -> Dictionary:
	if not active(world) or not world.party_encounter.dark_expedition.leave_camp():
		return reject("camp_unavailable")
	return {"accepted": true, "reason": "ok"}

static func camp_action(world, action: String, target_id: int) -> Dictionary:
	if not active(world) or world.party_encounter.dark_expedition.phase != "CAMP":
		return reject("camp_unavailable")
	var state = world.party_encounter.dark_expedition
	if not world.entities.has(target_id) or target_id not in world.party_encounter.party_member_ids:
		return reject("camp_target_invalid")
	var row: Dictionary = state.member(target_id); var entity = world.entities[target_id]
	var cost := CAMP_HEAL_CP if action == "HEAL" else CAMP_STRESS_CP if action == "CALM" else CAMP_INJURY_CP if action == "TREAT_INJURY" else -1
	if cost < 0: return reject("camp_action_invalid")
	if state.camp_cp < cost: return reject("camp_cp_insufficient")
	if action == "HEAL":
		var combatant=world.combatant_states.get(target_id)
		if entity.health >= entity.max_health or combatant == null or combatant.life_state == "DEAD":return reject("camp_heal_not_needed")
		if not combatant.status_rows.is_empty():return reject("camp_heal_statuses_pending")
		var amount := mini(int(entity.max_health)-int(entity.health), maxi(1, ceili(float(entity.max_health) * 0.25)))
		var source=world.emit_event("dark_expedition.camp_action",world.party_encounter.protagonist_id,
			target_id,entity.position,cost,-1,{"schema_version":1,
			"ruleset_id":"dark-fantasy-expedition-v1","action":"HEAL",
			"target_id":str(target_id)})
		if source==null:return reject("camp_heal_failed")
		var recovered_from_dying:bool=combatant.life_state=="DOWNED"
		var recovery_health:=0
		if recovered_from_dying:
			recovery_health=maxi(1,int((int(entity.max_health)+9)/10))
			var recovery=world.emit_event("entity.recovered",-1,target_id,entity.position,
				recovery_health,source.id,{"schema_version":1,
				"life_ruleset_id":LIFE_RULESET_ID,"recovered_health":recovery_health,
				"recovery_lock_until":str(world.world_time+100)})
			if recovery==null:return reject("camp_heal_failed")
			entity.health=recovery_health;combatant.life_state="ACTIVE"
			combatant.downed_at=-1;combatant.downed_resolve_at=-1;combatant.downed_source_event_id=-1
			combatant.guarded_until=0;combatant.guard_source_event_id=-1
			combatant.recovery_lock_until=world.world_time+100;combatant.recovery_source_event_id=int(recovery.id)
		var healed:=amount-recovery_health if recovered_from_dying else amount
		if healed>0:
			entity.health+=healed
			var health_event=world.emit_event("health.restored",target_id,target_id,entity.position,healed,
				source.id,{"schema_version":1,"ruleset_id":"dark-fantasy-expedition-v1",
				"kind":"DARK_CAMP","health_after":int(entity.health)})
			if health_event==null:return reject("camp_heal_failed")
	elif action == "CALM":
		if int(row.get("stress", 0)) <= 0:return reject("camp_calm_not_needed")
		row["stress"] = maxi(0, int(row.get("stress", 0)) - CAMP_STRESS_RECOVERY)
	else:
		if INJURY_SPROINED_ANKLE not in row.get("injury_ids",[]):return reject("camp_injury_not_needed")
		row.get("injury_ids",[]).erase(INJURY_SPROINED_ANKLE)
	state.camp_cp -= cost
	return {"accepted": true, "reason": "ok", "action": action, "target_id": target_id,
		"camp_cp": state.camp_cp}

static func use_rescue(world, target_id: int, amount: int = 1) -> Dictionary:
	if not active(world):return reject("expedition_not_active")
	var state = world.party_encounter.dark_expedition
	if state.rescue_supplies < amount or amount != 1:return reject("rescue_supply_unavailable")
	if not world.entities.has(target_id) or target_id not in world.party_encounter.party_member_ids:return reject("rescue_target_invalid")
	var combatant=world.combatant_states.get(target_id);var entity=world.entities[target_id]
	if combatant == null or combatant.life_state != "DOWNED":return reject("rescue_target_not_dying")
	entity.health=1;combatant.life_state="ACTIVE";state.rescue_supplies-=1
	return {"accepted":true,"reason":"ok","target_id":target_id,"rescue_supplies":state.rescue_supplies}

static func settle(world, kind: String) -> Dictionary:
	if world == null or world.party_encounter == null or world.party_encounter.dark_expedition == null:
		return reject("expedition_not_found")
	var state = world.party_encounter.dark_expedition
	if kind in ["SAFE_RETREAT", "EMERGENCY_RETREAT"]:
		var viable: bool = world.party_encounter.active_party_member_ids.any(func(id):
			return world.combatant_states.has(int(id)) and world.combatant_states[int(id)].life_state == "ACTIVE")
		if not viable:return reject("all_party_disabled")
	if not state.settle(kind):return reject("settlement_already_done")
	return {"accepted":true,"reason":"ok","kind":kind,"preserved_gold":state.preserved_gold}

static func commit_event_batch(world, event_rows: Array) -> bool:
	# The expedition owns its 0..100 stress scale while active. Existing morale
	# batches call this once per resolved command/scheduled tick, so event IDs make
	# the projection replay-safe without adding a second event bus.
	if world == null or world.party_encounter == null \
			or world.party_encounter.dark_expedition == null:
		return true
	var state = world.party_encounter.dark_expedition
	if state.phase not in ["ACTIVE", "CAMP"]: return true
	var batch_downs: Dictionary = {}
	var batch_deaths: Dictionary = {}
	for event in event_rows:
		var event_type := str(event.get("type", "") if event is Dictionary else event.type)
		var target_id := int(event.get("target_id", -1) if event is Dictionary else event.target_id)
		if event_type == "entity.downed" and target_id in world.party_encounter.party_member_ids:
			batch_downs[target_id] = true
		elif event_type == "entity.died" and target_id in world.party_encounter.party_member_ids:
			batch_deaths[target_id] = true
	for event in event_rows:
		var event_id := int(event.get("id", -1) if event is Dictionary else event.id)
		if event_id <= 0 or str(event_id) in state.processed_event_ids: continue
		var event_type := str(event.get("type", "") if event is Dictionary else event.type)
		var target_id := int(event.get("target_id", -1) if event is Dictionary else event.target_id)
		var magnitude := int(event.get("magnitude", 0) if event is Dictionary else event.magnitude)
		if target_id in world.party_encounter.party_member_ids:
			if event_type in ["combat.physical_damage", "combat.fire_damage", "combat.electric_damage"] \
					and magnitude > 0:
				var row: Dictionary = state.member(target_id)
				row["stress"] = mini(100, int(row.get("stress", 0)) + DAMAGE_STRESS)
			elif event_type == "combat.downed_damage" and magnitude > 0:
				var token_row: Dictionary = state.member(target_id)
				token_row["death_tokens"] = mini(3, int(token_row.get("death_tokens", 0)) + 1)
			elif event_type == "entity.downed":
				var injured: Dictionary = state.member(target_id)
				var injuries: Array = injured.get("injury_ids", [])
				if INJURY_SPROINED_ANKLE not in injuries: injuries.append(INJURY_SPROINED_ANKLE)
				injured["injury_ids"] = injuries
				if not batch_deaths.has(target_id):
					for member_id_value in world.party_encounter.party_member_ids:
						var member_id := int(member_id_value)
						if member_id == target_id or not _stress_eligible(world, member_id): continue
						var ally: Dictionary = state.member(member_id)
						ally["stress"] = mini(100, int(ally.get("stress", 0)) + DYING_STRESS)
			elif event_type == "entity.died":
				for member_id_value in world.party_encounter.party_member_ids:
						var member_id := int(member_id_value)
						if member_id == target_id or not _stress_eligible(world, member_id): continue
						var ally: Dictionary = state.member(member_id)
						ally["stress"] = mini(100, int(ally.get("stress", 0)) + DEATH_STRESS)
		state.processed_event_ids.append(str(event_id))
	world.party_encounter.revision += 1 if not event_rows.is_empty() else 0
	return true

static func _stress_eligible(world, entity_id: int) -> bool:
	if not world.entities.has(entity_id) or not world.combatant_states.has(entity_id): return false
	var member = world.party_encounter.member(entity_id)
	return member != null and member.presence in ["DEPLOYED", "GROUPED"] \
		and world.combatant_states[entity_id].life_state != "DEAD"

static func stress_band(value: int) -> String:
	if value >= 100: return "CRISIS"
	if value >= 80: return "HIGH"
	if value >= 50: return "TENSE"
	return "CALM"

static func reject(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}
