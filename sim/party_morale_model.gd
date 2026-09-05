class_name PartyMoraleModel
extends RefCounted

const FixedPointScript = preload("res://sim/fixed_point.gd")
const RelationshipSystemScript = preload("res://sim/systems/relationship_system.gd")

const RULESET_ID := "party-morale-contagion-v2-hexaco"
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
						var appraisal := death_shock_appraisal(world, member_id,
							target_id)
						direct[member_id] = int(direct[member_id]) \
							+ int(appraisal.stress_delta)
						triggers[member_id].append_array(appraisal.trigger_codes)
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
			var resilience := morale_resilience(world.party_encounter.member(
				member_id).personality_profile)
			var base := FixedPointScript.trunc_div(int(direct[source_id]), 4)
			contagion += FixedPointScript.trunc_div(base * (1500 - resilience), 1000)
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


static func death_shock_appraisal(world, observer_id: int,
		deceased_id: int) -> Dictionary:
	# Death is not a uniform party-wide debuff. Emotionality controls the initial
	# sensitivity, the directed relationship controls attachment, and proximity
	# distinguishes witnessing the death from hearing about it through the party.
	# The result stays a pure projection so the authoritative morale transaction
	# can still roll back the complete combat step.
	var fallback := {"stress_delta":300, "emotionality_delta":70,
		"bond_delta":0, "witness_delta":0,
		"trust":0, "gratitude":0,
		"trigger_codes":["ALLY_DIED"]}
	if world == null or world.party_encounter == null \
			or not world.entities.has(observer_id) \
			or not world.entities.has(deceased_id):
		return fallback.duplicate(true)
	var member = world.party_encounter.member(observer_id)
	var emotionality := 500
	if member != null and member.personality_profile != null:
		var sampled := int(member.personality_profile.value("E"))
		if sampled >= 0: emotionality = clampi(sampled, 0, 1000)
	var relation: Dictionary = RelationshipSystemScript.new(world).effective_relation(
		observer_id, deceased_id)
	var trust := clampi(int(relation.get("trust", 0)), -100, 100)
	var gratitude := clampi(int(relation.get("gratitude", 0)), 0, 100)
	var emotionality_delta := FixedPointScript.trunc_div(emotionality * 140, 1000)
	var positive_bond := maxi(0, trust) + FixedPointScript.trunc_div(gratitude, 2)
	var estrangement_relief := FixedPointScript.trunc_div(maxi(0, -trust) * 2, 5)
	var bond_delta := positive_bond - estrangement_relief
	var witnessed := _distance(world.entities[observer_id].position,
		world.entities[deceased_id].position) <= CONTAGION_RANGE
	var witness_delta := 40 if witnessed else 0
	var stress_delta := clampi(210 + emotionality_delta + bond_delta \
		+ witness_delta, 120, 440)
	var trigger_codes: Array[String] = ["ALLY_DIED"]
	if witnessed: trigger_codes.append("ALLY_DIED_WITNESSED")
	if trust >= 15 or gratitude >= 20: trigger_codes.append("ALLY_DIED_BONDED")
	if emotionality >= 650: trigger_codes.append("ALLY_DIED_EMOTIONALITY")
	trigger_codes.sort()
	return {"stress_delta":stress_delta,
		"emotionality_delta":emotionality_delta,"bond_delta":bond_delta,
		"witness_delta":witness_delta,"trust":trust,"gratitude":gratitude,
		"trigger_codes":trigger_codes}.duplicate(true)


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


static func morale_resilience(profile) -> int:
	if profile == null:
		return 500
	var emotionality := int(profile.value("E"))
	var conscientiousness := int(profile.value("C"))
	if emotionality < 0 or conscientiousness < 0:
		return 500
	return clampi(FixedPointScript.trunc_div(
		conscientiousness + 1000 - emotionality, 2), 0, 1000)


static func _near_active_enemy(world, member_id: int) -> bool:
	for enemy_id in world.party_encounter.enemy_ids:
		if world.entities.has(enemy_id) and world.is_autonomous_target(enemy_id) \
				and _distance(world.entities[member_id].position,
					world.entities[enemy_id].position) <= RECOVERY_THREAT_RANGE:
			return true
	return false


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
