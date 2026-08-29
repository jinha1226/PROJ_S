class_name MeleeCombatSystem
extends RefCounted

const COMBAT_RULESET_ID := "deterministic-melee-resolution-v1"
const ProfileRegistryScript = preload("res://sim/combat_profile_registry.gd")
const FrozenIntentScript = preload("res://sim/frozen_attack_intent.gd")
const ResolutionScript = preload("res://sim/attack_resolution.gd")
const ProgressionRegistryScript=preload("res://sim/progression_registry.gd")

var world
var damage

func _init(p_world, p_damage) -> void: world = p_world; damage = p_damage

static func commitment_key(world_seed: int, processed_step_index: int, attack_start_world_time: int,
		batch_context: String, intent_ordinal: int, attacker_id: int, target_id: int) -> String:
	return "%s|seed=%d|step=%d|time=%d|batch=%s|ordinal=%d|attacker=%d|target=%d" % [
		COMBAT_RULESET_ID, world_seed, processed_step_index, attack_start_world_time,
		batch_context, intent_ordinal, attacker_id, target_id]

static func commitment_hash(key: String) -> String: return key.sha256_text()

static func lane_hash(key: String, lane: String) -> String:
	return (key + "|lane=" + lane).sha256_text() if lane in ["HIT", "BLEED"] else ""

static func lane_roll_milli(key: String, lane: String) -> int:
	if lane not in ["HIT", "BLEED"]: return -1
	var digest: PackedByteArray = (key + "|lane=" + lane).sha256_buffer()
	var u31 := ((int(digest[0]) & 0x7f) << 24) | (int(digest[1]) << 16) \
		| (int(digest[2]) << 8) | int(digest[3])
	return u31 % 1000

func assess_attack(attacker_id: int, target_id: int, source: String,
		processed_step_index: int, attack_start_world_time: int, batch_context: String,
		intent_ordinal: int) -> Dictionary:
	if source not in ["DIRECT", "SUGGESTED", "OVERRIDE"] or intent_ordinal < 0 \
			or processed_step_index <= 0 or attack_start_world_time < 0 \
			or not can_attack(attacker_id, target_id): return {}
	var attacker = world.entities[attacker_id]; var target = world.entities[target_id]
	var attacker_state = world.combatant_states[attacker_id]
	var target_state = world.combatant_states[target_id]
	var attacker_profile := ProfileRegistryScript.profile(attacker_state.combat_profile_id)
	var target_profile := ProfileRegistryScript.profile(target_state.combat_profile_id)
	if attacker_profile.is_empty() or target_profile.is_empty(): return {}
	var hit_chance := clampi(500 + int(attacker_profile.accuracy_milli) - int(target_profile.evasion_milli), 50, 950)
	var bleed_chance := clampi(int(attacker_profile.bleed_proc_milli) - int(target_profile.bleed_resist_milli), 0, 1000)
	var skill_rank:=0
	if world.party_encounter!=null and attacker_id==world.party_encounter.protagonist_id \
			and world.party_encounter.protagonist_progression!=null:
		skill_rank=world.party_encounter.protagonist_progression.rank("MELEE")
	var base_damage := int(attacker_profile.power) \
		+ProgressionRegistryScript.melee_power_bonus(skill_rank)
	var armor_reduction := mini(int(target_profile.armor_flat), maxi(0, base_damage - 1))
	var after_armor := base_damage - armor_reduction
	var guarded: bool = target_state.life_state == "ACTIVE" and attack_start_world_time < target_state.guarded_until
	var guard_reduction := int(after_armor * 250 / 1000) if guarded else 0
	var normal_final_damage := maxi(1, after_armor - guard_reduction)
	var key := commitment_key(world.seed, processed_step_index, attack_start_world_time,
		batch_context, intent_ordinal, attacker_id, target_id)
	return {"schema_version":1, "attacker_id":str(attacker_id), "target_id":str(target_id),
		"attacker_position":[attacker.position.x, attacker.position.y],
		"target_position":[target.position.x, target.position.y],
		"attacker_life_state":"ACTIVE", "target_life_state":target_state.life_state,
		"attacker_profile_id":attacker_state.combat_profile_id, "target_profile_id":target_state.combat_profile_id,
		"target_evasion_milli":int(target_profile.evasion_milli), "target_armor_flat":int(target_profile.armor_flat),
		"frozen_guarded_until":str(target_state.guarded_until), "guard_source_event_id":str(target_state.guard_source_event_id),
		"source":source, "processed_step_index":str(processed_step_index),
		"attack_start_world_time":str(attack_start_world_time), "batch_context":batch_context,
		"intent_ordinal":intent_ordinal, "intent_mode":"FINISHER" if target_state.life_state == "DOWNED" else "STRIKE",
		"hit_chance_milli":hit_chance, "bleed_chance_milli":bleed_chance,
		"base_damage":base_damage, "armor_reduction":armor_reduction, "guarded":guarded,
		"guard_reduction":guard_reduction, "normal_final_damage":normal_final_damage,
		"commitment_hash":commitment_hash(key)}

func freeze_assessment(assessment: Dictionary, target_health_at_batch_start: int,
		original_action_order: int, protagonist_terminal_if_lethal: bool = false):
	if target_health_at_batch_start < 0 or original_action_order < 0:
		return null
	return FrozenIntentScript.new(
		assessment, target_health_at_batch_start, original_action_order, world.seed,
		protagonist_terminal_if_lethal)

func resolve_frozen_intent(intent):
	if intent == null or not intent.assessment is Dictionary:
		return null
	var assessment: Dictionary = intent.assessment
	var attacker_id := int(str(assessment.get("attacker_id", "-1")))
	var target_id := int(str(assessment.get("target_id", "-1")))
	var processed_step_index := int(str(assessment.get("processed_step_index", "-1")))
	var attack_start_world_time := int(str(assessment.get("attack_start_world_time", "-1")))
	var batch_context := str(assessment.get("batch_context", ""))
	var intent_ordinal := int(assessment.get("intent_ordinal", -1))
	if attacker_id <= 0 or target_id <= 0 or processed_step_index <= 0 \
			or attack_start_world_time < 0 or batch_context.is_empty() or intent_ordinal < 0:
		return null
	var key := commitment_key(intent.world_seed, processed_step_index, attack_start_world_time,
		batch_context, intent_ordinal, attacker_id, target_id)
	if str(assessment.get("commitment_hash", "")) != commitment_hash(key):
		return null
	var hit_roll := lane_roll_milli(key, "HIT")
	var bleed_roll := lane_roll_milli(key, "BLEED")
	var finisher: bool = str(assessment.get("target_life_state", "")) == "DOWNED" \
		and str(assessment.get("intent_mode", "")) == "FINISHER"
	var outcome := "FINISHER" if finisher \
		else ("MISS" if hit_roll >= int(assessment.get("hit_chance_milli", -1)) else "HIT")
	var bleed_proc_succeeded := not finisher and outcome == "HIT" \
		and bleed_roll < int(assessment.get("bleed_chance_milli", -1))
	var final_damage := int(assessment.get("normal_final_damage", 0)) \
		if outcome == "HIT" else 0
	var action_data := {
		"schema_version": 1,
		"combat_ruleset_id": COMBAT_RULESET_ID,
		"attacker_profile_id": str(assessment.get("attacker_profile_id", "")),
		"target_profile_id": str(assessment.get("target_profile_id", "")),
		"batch_context": batch_context,
		"intent_ordinal": intent_ordinal,
		"intent_mode": str(assessment.get("intent_mode", "")),
		"target_life_at_batch_start": str(assessment.get("target_life_state", "")),
		"outcome": outcome,
		"processed_step_index": str(processed_step_index),
		"attack_start_world_time": str(attack_start_world_time),
		"commitment_hash": commitment_hash(key),
		"hit_chance_milli": 1000 if finisher \
			else int(assessment.get("hit_chance_milli", -1)),
		"hit_roll_milli": hit_roll,
		"bleed_chance_milli": 0 if finisher \
			else int(assessment.get("bleed_chance_milli", -1)),
		"bleed_roll_milli": bleed_roll,
		"bleed_proc_succeeded": bleed_proc_succeeded,
		"base_damage": int(assessment.get("base_damage", 0)),
		"target_evasion_milli": int(assessment.get("target_evasion_milli", -1)),
		"armor_flat": int(assessment.get("target_armor_flat", -1)),
		"armor_reduction": int(assessment.get("armor_reduction", -1)),
		"frozen_guarded_until": str(assessment.get("frozen_guarded_until", "-1")),
		"guard_source_event_id": str(assessment.get("guard_source_event_id", "-1")),
		"guarded": bool(assessment.get("guarded", false)),
		"guard_reduction": int(assessment.get("guard_reduction", -1)),
		"final_damage": final_damage,
	}
	return ResolutionScript.new({
		"outcome": outcome,
		"hit_roll_milli": hit_roll,
		"bleed_roll_milli": bleed_roll,
		"bleed_proc_succeeded": bleed_proc_succeeded,
		"final_damage": final_damage,
		"action_data": action_data,
	})

func project_batch(frozen_intents: Array) -> Array:
	var ordered: Array = frozen_intents.duplicate()
	ordered.sort_custom(func(a, b):
		var a_target := int(str(a.assessment.target_id))
		var b_target := int(str(b.assessment.target_id))
		if a_target != b_target: return a_target < b_target
		var a_actor := int(str(a.assessment.attacker_id))
		var b_actor := int(str(b.assessment.attacker_id))
		if a_actor != b_actor: return a_actor < b_actor
		return a.original_action_order < b.original_action_order)
	var shadow: Dictionary = {}
	var projected: Array = []
	for ordinal in range(ordered.size()):
		var intent = ordered[ordinal]
		var assessment: Dictionary = intent.assessment
		if int(assessment.get("intent_ordinal", -1)) != ordinal:
			return []
		var target_id := int(str(assessment.target_id))
		if not shadow.has(target_id):
			shadow[target_id] = {"health": intent.target_health_at_batch_start,
				"life": str(assessment.target_life_state)}
		var current: Dictionary = shadow[target_id]
		var resolution = resolve_frozen_intent(intent)
		if resolution == null:
			return []
		var health_before := int(current.health)
		var life_before := str(current.life)
		var health_after := health_before
		var life_after := life_before
		var frozen_life := str(assessment.target_life_state)
		if life_before == "DEAD" or (life_before == "DOWNED" and frozen_life == "ACTIVE"):
			resolution.outcome = "OVERKILL_SKIP"
			resolution.final_damage = 0
			resolution.bleed_proc_succeeded = false
			resolution.action_data.outcome = "OVERKILL_SKIP"
			resolution.action_data.final_damage = 0
			resolution.action_data.bleed_proc_succeeded = false
		elif life_before == "DOWNED":
			if frozen_life != "DOWNED" or resolution.outcome != "FINISHER":
				return []
			life_after = "DEAD"
		elif life_before == "ACTIVE":
			if frozen_life != "ACTIVE":
				return []
			if resolution.outcome == "HIT":
				health_after = maxi(0, health_before - resolution.final_damage)
				if health_after == 0:
					if intent.protagonist_terminal_if_lethal:
						life_after = "DEAD"
						resolution.terminal_immediate = true
					else:
						life_after = "DOWNED"
			elif resolution.outcome != "MISS":
				return []
		else:
			return []
		resolution.target_health_before = health_before
		resolution.target_life_before = life_before
		resolution.target_health_after = health_after
		resolution.target_life_after = life_after
		shadow[target_id] = {"health": health_after, "life": life_after}
		projected.append(resolution)
	return projected

func can_attack(attacker_id: int, target_id: int) -> bool:
	if not world.entities.has(attacker_id) or not world.entities.has(target_id): return false
	var attacker = world.entities[attacker_id]; var target = world.entities[target_id]
	return world.can_act(attacker_id, world.world_time) and world.is_explicit_melee_target(target_id) \
		and maxi(absi(attacker.position.x - target.position.x), absi(attacker.position.y - target.position.y)) == 1
