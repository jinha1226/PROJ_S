class_name MeleeCombatSystem
extends RefCounted

const COMBAT_RULESET_ID := "deterministic-melee-resolution-v1"
const ProfileRegistryScript = preload("res://sim/combat_profile_registry.gd")
const FrozenIntentScript = preload("res://sim/frozen_attack_intent.gd")
const ResolutionScript = preload("res://sim/attack_resolution.gd")
const ProgressionRegistryScript=preload("res://sim/progression_registry.gd")
const WeaponRegistryScript=preload("res://sim/weapon_registry.gd")
const WeaponAttackRulesScript=preload("res://sim/weapon_attack_rules.gd")
const ActorStatRulesScript=preload("res://sim/actor_stat_rules.gd")
const DefenseRulesScript=preload("res://sim/combat_defense_rules.gd")

var world
var damage

func _init(p_world, p_damage) -> void: world = p_world; damage = p_damage

static func commitment_key(world_seed: int, processed_step_index: int, attack_start_world_time: int,
		batch_context: String, intent_ordinal: int, attacker_id: int, target_id: int,
		defense_fragment: String = "") -> String:
	var base := "%s|seed=%d|step=%d|time=%d|batch=%s|ordinal=%d|attacker=%d|target=%d" % [
		COMBAT_RULESET_ID, world_seed, processed_step_index, attack_start_world_time,
		batch_context, intent_ordinal, attacker_id, target_id]
	return base if defense_fragment.is_empty() else base + "|" + defense_fragment

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
		intent_ordinal: int, weapon_id: String = "", occupants: Dictionary = {}) -> Dictionary:
	if source not in ["DIRECT", "SUGGESTED", "OVERRIDE"] or intent_ordinal < 0 \
			or processed_step_index <= 0 or attack_start_world_time < 0 \
			or (weapon_id.is_empty() and not can_attack(attacker_id, target_id)) \
			or (not weapon_id.is_empty() and not can_attack_with_weapon(attacker_id,
				target_id, weapon_id, occupants)):
		return {}
	var attacker = world.entities[attacker_id]; var target = world.entities[target_id]
	var attacker_state = world.combatant_states[attacker_id]
	var target_state = world.combatant_states[target_id]
	var attacker_profile := ProfileRegistryScript.profile(attacker_state.combat_profile_id)
	var target_profile := ProfileRegistryScript.profile(target_state.combat_profile_id)
	if attacker_profile.is_empty() or target_profile.is_empty(): return {}
	# Equipment defense applies only while the protagonist is still an active
	# combatant. Downed targets retain the established v1 finisher lane, so its
	# death/lifecycle history remains byte-for-byte compatible.
	var defense_snapshot:=_protagonist_defense_snapshot(target_id,target_profile) \
		if target_state.life_state == "ACTIVE" else {}
	var equipment_defense:=not defense_snapshot.is_empty()
	var target_evasion:=int(defense_snapshot.effective_evasion_milli) if equipment_defense \
		else int(target_profile.evasion_milli)
	var target_armor:=int(defense_snapshot.effective_armor_flat) if equipment_defense \
		else int(target_profile.armor_flat)
	var weapon_spec: Dictionary = {}
	var proficiency_rank := 0
	if not weapon_id.is_empty():
		var weapon = WeaponRegistryScript.definition(weapon_id)
		if weapon == null: return {}
		proficiency_rank = _weapon_proficiency_rank(attacker_id, weapon.proficiency_id)
		weapon_spec = WeaponAttackRulesScript.build_attack_spec(weapon_id, proficiency_rank,
			int(attacker_profile.power), int(attacker_profile.accuracy_milli),
			target_evasion, target_armor,ActorStatRulesScript.for_entity(world,attacker_id))
		if weapon_spec.is_empty(): return {}
	var hit_chance := int(weapon_spec.hit_chance_milli) if not weapon_spec.is_empty() \
		else clampi(500 + int(attacker_profile.accuracy_milli) - target_evasion, 50, 950)
	var bleed_chance := clampi(int(attacker_profile.bleed_proc_milli) - int(target_profile.bleed_resist_milli), 0, 1000)
	var base_damage := int(weapon_spec.raw_damage) if not weapon_spec.is_empty() \
		else int(attacker_profile.power)
	var armor_reduction := int(weapon_spec.armor_reduction) if not weapon_spec.is_empty() \
		else mini(target_armor, maxi(0, base_damage - 1))
	var after_armor := base_damage - armor_reduction
	var guarded: bool = target_state.life_state == "ACTIVE" and attack_start_world_time < target_state.guarded_until
	var guard_rank:=0
	if world.party_encounter!=null and target_id==world.party_encounter.protagonist_id \
			and world.party_encounter.protagonist_progression!=null:
		guard_rank=world.party_encounter.protagonist_progression.rank("GUARD")
	var guard_rate_milli:=ProgressionRegistryScript.guard_reduction_milli(guard_rank)
	var guard_reduction := int(after_armor * guard_rate_milli / 1000) if guarded else 0
	var normal_final_damage := maxi(1, after_armor - guard_reduction)
	var defense_fragment:=DefenseRulesScript.commitment_fragment(defense_snapshot) if equipment_defense else ""
	var key := WeaponAttackRulesScript.commitment_key(world.seed, processed_step_index,
		attack_start_world_time, batch_context, intent_ordinal, attacker_id, target_id,
		weapon_id, proficiency_rank) if not weapon_spec.is_empty() else commitment_key(world.seed,
		processed_step_index, attack_start_world_time, batch_context, intent_ordinal,
		attacker_id, target_id, defense_fragment)
	var result := {"schema_version":3 if equipment_defense else (2 if not weapon_spec.is_empty() else 1),
		"attacker_id":str(attacker_id), "target_id":str(target_id),
		"attacker_position":[attacker.position.x, attacker.position.y],
		"target_position":[target.position.x, target.position.y],
		"attacker_life_state":"ACTIVE", "target_life_state":target_state.life_state,
		"attacker_profile_id":attacker_state.combat_profile_id, "target_profile_id":target_state.combat_profile_id,
		"target_evasion_milli":target_evasion, "target_armor_flat":target_armor,
		"frozen_guarded_until":str(target_state.guarded_until), "guard_source_event_id":str(target_state.guard_source_event_id),
		"source":source, "processed_step_index":str(processed_step_index),
		"attack_start_world_time":str(attack_start_world_time), "batch_context":batch_context,
		"intent_ordinal":intent_ordinal, "intent_mode":"FINISHER" if target_state.life_state == "DOWNED" else "STRIKE",
		"hit_chance_milli":hit_chance, "bleed_chance_milli":bleed_chance,
		"base_damage":base_damage, "armor_reduction":armor_reduction, "guarded":guarded,
		"guard_reduction":guard_reduction, "normal_final_damage":normal_final_damage,
		"commitment_hash":commitment_hash(key)}
	if equipment_defense:
		result["defense_ruleset_id"]=DefenseRulesScript.RULESET_ID
		result["target_base_evasion_milli"]=int(defense_snapshot.base_evasion_milli)
		result["target_base_armor_flat"]=int(defense_snapshot.base_armor_flat)
		result["equipment_dodge_milli"]=int(defense_snapshot.dodge_milli)
		result["equipment_armor_flat"]=int(defense_snapshot.equipment_armor_flat)
		result["equipment_parry_milli"]=int(defense_snapshot.parry_milli)
	if not weapon_spec.is_empty():
		for key_name in ["weapon_id", "proficiency_id", "proficiency_rank", "attack_form",
				"trait_id", "range_min", "range_max", "attack_time", "weapon_damage", "proficiency_damage",
				"proficiency_accuracy_milli", "armor_penetration_flat",
				"secondary_damage_milli", "stun_chance_milli"]:
			result[key_name] = weapon_spec[key_name]
	return result

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
	var schema_version:=int(assessment.get("schema_version",1))
	var weapon_schema := schema_version == 2
	var equipment_defense:=schema_version==3
	var defense_snapshot:=_defense_snapshot_from_assessment(assessment) if equipment_defense else {}
	if equipment_defense and defense_snapshot.is_empty():return null
	var key := WeaponAttackRulesScript.commitment_key(intent.world_seed, processed_step_index,
		attack_start_world_time, batch_context, intent_ordinal, attacker_id, target_id,
		str(assessment.get("weapon_id", "")), int(assessment.get("proficiency_rank", 0))) \
		if weapon_schema else commitment_key(intent.world_seed, processed_step_index,
		attack_start_world_time, batch_context, intent_ordinal, attacker_id, target_id,
		DefenseRulesScript.commitment_fragment(defense_snapshot) if equipment_defense else "")
	if str(assessment.get("commitment_hash", "")) != commitment_hash(key):
		return null
	var hit_roll := WeaponAttackRulesScript.lane_roll_milli(key, "HIT") if weapon_schema \
		else lane_roll_milli(key, "HIT")
	var bleed_roll := WeaponAttackRulesScript.lane_roll_milli(key, "BLEED") if weapon_schema \
		else lane_roll_milli(key, "BLEED")
	var parry_roll:=DefenseRulesScript.parry_roll_milli(key) if equipment_defense else -1
	var finisher: bool = str(assessment.get("target_life_state", "")) == "DOWNED" \
		and str(assessment.get("intent_mode", "")) == "FINISHER"
	var outcome := "FINISHER" if finisher else ("MISS" \
		if hit_roll >= int(assessment.get("hit_chance_milli", -1)) else ("PARRIED" \
		if equipment_defense and DefenseRulesScript.parry_succeeds(parry_roll,defense_snapshot) else "HIT"))
	var bleed_proc_succeeded := not finisher and outcome == "HIT" \
		and bleed_roll < int(assessment.get("bleed_chance_milli", -1))
	var final_damage := int(assessment.get("normal_final_damage", 0)) \
		if outcome == "HIT" else 0
	var action_data := {
		"schema_version": 3 if equipment_defense else 1,
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
	if weapon_schema:
		# Record the weapon used so replay validates this attack against it rather
		# than the loadout equipped at validation time, which may have changed.
		action_data["weapon_id"] = str(assessment.get("weapon_id", ""))
	if equipment_defense:
		action_data["defense_ruleset_id"]=DefenseRulesScript.RULESET_ID
		action_data["target_base_evasion_milli"]=int(defense_snapshot.base_evasion_milli)
		action_data["target_base_armor_flat"]=int(defense_snapshot.base_armor_flat)
		action_data["equipment_dodge_milli"]=int(defense_snapshot.dodge_milli)
		action_data["equipment_armor_flat"]=int(defense_snapshot.equipment_armor_flat)
		action_data["equipment_parry_milli"]=int(defense_snapshot.parry_milli)
		action_data["parry_roll_milli"]=parry_roll
		action_data["parry_succeeded"]=outcome=="PARRIED"
	return ResolutionScript.new({
		"outcome": outcome,
		"hit_roll_milli": hit_roll,
		"bleed_roll_milli": bleed_roll,
		"parry_roll_milli":parry_roll,
		"parry_succeeded":outcome=="PARRIED",
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
		elif resolution.outcome not in ["MISS","PARRIED"]:
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


# Weapon-aware seam for the new play session. This intentionally returns a
# detached assessment instead of changing the shipped melee event schema in
# place. The coordinator can freeze this DTO in its next version without
# inventing any combat formula in UI code.
func build_weapon_assessment(attacker_id: int, target_id: int, weapon_id: String,
		source: String, processed_step_index: int, attack_start_world_time: int,
		batch_context: String, intent_ordinal: int, occupants: Dictionary = {}) -> Dictionary:
	if source not in ["DIRECT", "SUGGESTED", "OVERRIDE"] or intent_ordinal < 0 \
			or processed_step_index <= 0 or attack_start_world_time < 0 \
			or not can_attack_with_weapon(attacker_id, target_id, weapon_id, occupants):
		return {}
	var attacker_state = world.combatant_states.get(attacker_id)
	var target_state = world.combatant_states.get(target_id)
	if attacker_state == null or target_state == null: return {}
	var attacker_profile := ProfileRegistryScript.profile(attacker_state.combat_profile_id)
	var target_profile := ProfileRegistryScript.profile(target_state.combat_profile_id)
	var weapon = WeaponRegistryScript.definition(weapon_id)
	if attacker_profile.is_empty() or target_profile.is_empty() or weapon == null: return {}
	var proficiency_rank := _weapon_proficiency_rank(attacker_id, weapon.proficiency_id)
	var spec := WeaponAttackRulesScript.build_attack_spec(weapon_id, proficiency_rank,
		int(attacker_profile.power), int(attacker_profile.accuracy_milli),
		int(target_profile.evasion_milli), int(target_profile.armor_flat),
		ActorStatRulesScript.for_entity(world,attacker_id))
	if spec.is_empty(): return {}
	var key := WeaponAttackRulesScript.commitment_key(world.seed, processed_step_index,
		attack_start_world_time, batch_context, intent_ordinal, attacker_id, target_id,
		weapon_id, proficiency_rank)
	return {"schema_version":1, "attacker_id":str(attacker_id), "target_id":str(target_id),
		"attacker_position":[world.entities[attacker_id].position.x, world.entities[attacker_id].position.y],
		"target_position":[world.entities[target_id].position.x, world.entities[target_id].position.y],
		"source":source, "processed_step_index":str(processed_step_index),
		"attack_start_world_time":str(attack_start_world_time), "batch_context":batch_context,
		"intent_ordinal":intent_ordinal, "attack_spec":spec,
		"commitment_hash":key.sha256_text()}.duplicate(true)


func resolve_weapon_assessment(assessment: Dictionary) -> Dictionary:
	if assessment.is_empty() or not assessment.get("attack_spec") is Dictionary: return {}
	var spec: Dictionary = assessment.attack_spec
	var attacker_id := int(str(assessment.get("attacker_id", "-1")))
	var target_id := int(str(assessment.get("target_id", "-1")))
	var processed_step_index := int(str(assessment.get("processed_step_index", "-1")))
	var attack_start_world_time := int(str(assessment.get("attack_start_world_time", "-1")))
	var batch_context := str(assessment.get("batch_context", ""))
	var intent_ordinal := int(assessment.get("intent_ordinal", -1))
	var key := WeaponAttackRulesScript.commitment_key(world.seed, processed_step_index,
		attack_start_world_time, batch_context, intent_ordinal, attacker_id, target_id,
		str(spec.get("weapon_id", "")), int(spec.get("proficiency_rank", -1)))
	if str(assessment.get("commitment_hash", "")) != key.sha256_text(): return {}
	return WeaponAttackRulesScript.resolve_attack_spec(spec, key)


func can_attack_with_weapon(attacker_id: int, target_id: int, weapon_id: String,
		occupants: Dictionary = {}) -> bool:
	if not world.entities.has(attacker_id) or not world.entities.has(target_id) \
			or not WeaponRegistryScript.has(weapon_id):
		return false
	if not world.can_act(attacker_id, world.world_time) \
			or not world.is_explicit_melee_target(target_id):
		return false
	return WeaponAttackRulesScript.targeting_error(world.entities[attacker_id].position,
		world.entities[target_id].position, weapon_id, occupants).is_empty()


func _weapon_proficiency_rank(attacker_id: int, proficiency_id: String) -> int:
	if world.party_encounter != null and attacker_id == world.party_encounter.protagonist_id \
			and world.party_encounter.protagonist_progression != null:
		return world.party_encounter.protagonist_progression.rank(proficiency_id)
	return 0


func _protagonist_defense_snapshot(target_id:int,target_profile:Dictionary)->Dictionary:
	if world.party_encounter==null or target_id!=world.party_encounter.protagonist_id:return {}
	var dto:Dictionary=world.equipment_modifiers(world.party_encounter.protagonist_id)
	if dto.is_empty():return {}
	var totals:Variant=dto.get("totals",{})
	return DefenseRulesScript.build_snapshot(int(target_profile.evasion_milli),
		int(target_profile.armor_flat),totals if totals is Dictionary else {})


func _defense_snapshot_from_assessment(assessment:Dictionary)->Dictionary:
	if str(assessment.get("defense_ruleset_id",""))!=DefenseRulesScript.RULESET_ID:return {}
	return DefenseRulesScript.build_snapshot(int(assessment.get("target_base_evasion_milli",-1)),
		int(assessment.get("target_base_armor_flat",-1)),{"armor_flat":
		int(assessment.get("equipment_armor_flat",-1)),"dodge_milli":
		int(assessment.get("equipment_dodge_milli",-1)),"parry_milli":
		int(assessment.get("equipment_parry_milli",-1))})
