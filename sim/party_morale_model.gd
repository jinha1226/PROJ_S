class_name PartyMoraleModel
extends RefCounted

const FixedPointScript = preload("res://sim/fixed_point.gd")

const RULESET_ID := "party-morale-contagion-v1"
const PANIC_ENTER := 850
const PANIC_EXIT := 650
const CONTAGION_RANGE := 4
const RECOVERY_THREAT_RANGE := 3
const RECOVERY_DELTA := -40
const MAX_CONTAGION := 180


static func evaluate(world, event_rows: Array, previous_modes: Dictionary = {}) -> Dictionary:
	var members := _eligible_members(world)
	var direct := {}
	var triggers := {}
	for member_id in members:
		direct[member_id] = 0
		triggers[member_id] = []
	var events: Array = event_rows.duplicate()
	events.sort_custom(func(a, b):
		var a_id := int(a.get("id", 0) if a is Dictionary else a.id)
		var b_id := int(b.get("id", 0) if b is Dictionary else b.id)
		return a_id < b_id)
	for event in events:
		var event_type := str(event.get("type", "") if event is Dictionary else event.type)
		var actor_id := int(event.get("actor_id", -1) if event is Dictionary else event.actor_id)
		var target_id := int(event.get("target_id", -1) if event is Dictionary else event.target_id)
		var magnitude := maxi(0, int(event.get("magnitude", 0) \
			if event is Dictionary else event.magnitude))
		if event_type in ["combat.physical_damage", "combat.downed_damage"] \
				and direct.has(target_id):
			direct[target_id] = int(direct[target_id]) + mini(220, magnitude * 4)
			triggers[target_id].append("SELF_DAMAGE")
		elif event_type == "party.override_committed" and direct.has(actor_id):
			direct[actor_id] = int(direct[actor_id]) + magnitude
			triggers[actor_id].append("OVERRIDE_STRESS")
		elif event_type == "entity.downed" and target_id in members:
			for member_id in members:
				if member_id == target_id:
					direct[member_id] = int(direct[member_id]) + 160
					triggers[member_id].append("SELF_DOWNED")
				else:
					direct[member_id] = int(direct[member_id]) + 120
					triggers[member_id].append("ALLY_DOWNED")
		elif event_type == "entity.died":
			if target_id in world.party_encounter.party_member_ids:
				for member_id in members:
					if member_id != target_id:
						direct[member_id] = int(direct[member_id]) + 300
						triggers[member_id].append("ALLY_DIED")
			elif target_id in world.party_encounter.enemy_ids:
				for member_id in members:
					direct[member_id] = int(direct[member_id]) - 100
					triggers[member_id].append("ENEMY_DIED")
	var rows: Array[Dictionary] = []
	for member_id in members:
		var member = world.party_encounter.member(member_id)
		var stress_before := clampi(int(member.stress), 0, 1000)
		var contagion := 0
		for source_id in members:
			if source_id == member_id or int(direct[source_id]) <= 0 \
					or _distance(world.entities[member_id].position,
						world.entities[source_id].position) > CONTAGION_RANGE:
				continue
			var composure := _composure(world, member_id)
			var base := FixedPointScript.trunc_div(int(direct[source_id]), 4)
			contagion += FixedPointScript.trunc_div(base * (1500 - composure), 1000)
		contagion = clampi(contagion, 0, MAX_CONTAGION)
		if contagion > 0:
			triggers[member_id].append("ALLY_FEAR_CONTAGION")
		var recovery := RECOVERY_DELTA if int(direct[member_id]) <= 0 \
			and contagion == 0 and not _near_active_enemy(world, member_id) else 0
		if recovery < 0:
			triggers[member_id].append("SAFE_RECOVERY")
		var stress_after := clampi(stress_before + int(direct[member_id]) \
			+ contagion + recovery, 0, 1000)
		var mode_before := str(previous_modes.get(member_id, member.mental_mode))
		if mode_before not in ["NORMAL", "PANIC"]:
			mode_before = "NORMAL"
		var mode_after := next_mode(mode_before, stress_after)
		var trigger_codes: Array = triggers[member_id].duplicate()
		trigger_codes.sort()
		rows.append({"entity_id":member_id, "stress_before":stress_before,
			"direct_delta":int(direct[member_id]), "contagion_delta":contagion,
			"recovery_delta":recovery, "stress_after":stress_after,
			"mode_before":mode_before, "mode_after":mode_after,
			"trigger_codes":trigger_codes})
	return {"schema_version":1, "ruleset_id":RULESET_ID,
		"member_rows":rows}.duplicate(true)


static func next_mode(previous_mode: String, stress: int) -> String:
	if previous_mode == "PANIC":
		return "NORMAL" if stress <= PANIC_EXIT else "PANIC"
	return "PANIC" if stress >= PANIC_ENTER else "NORMAL"


static func _eligible_members(world) -> Array[int]:
	var result: Array[int] = []
	if world == null or world.party_encounter == null:
		return result
	for member_id_value in world.party_encounter.active_party_member_ids:
		var member_id := int(member_id_value)
		var member = world.party_encounter.member(member_id)
		var combatant = world.combatant_states.get(member_id)
		if member != null and member.presence in ["DEPLOYED", "GROUPED"] \
				and combatant != null and combatant.life_state != "DEAD" \
				and world.entities.has(member_id):
			result.append(member_id)
	result.sort_custom(func(a: int, b: int):
		var a_slot := int(world.party_encounter.member(a).roster_slot)
		var b_slot := int(world.party_encounter.member(b).roster_slot)
		return a_slot < b_slot if a_slot != b_slot else a < b)
	return result


static func _composure(world, member_id: int) -> int:
	var profile = world.party_encounter.member(member_id).personality_profile
	if profile == null:
		return 500
	var value := int(profile.value("composure"))
	return clampi(value, 0, 1000) if value >= 0 else 500


static func _near_active_enemy(world, member_id: int) -> bool:
	for enemy_id in world.party_encounter.enemy_ids:
		if world.entities.has(enemy_id) and world.is_autonomous_target(enemy_id) \
				and _distance(world.entities[member_id].position,
					world.entities[enemy_id].position) <= RECOVERY_THREAT_RANGE:
			return true
	return false


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
