class_name WeaponAttackRules
extends RefCounted

const RULESET_ID := "deterministic-weapon-attack-v1"
const RegistryScript = preload("res://sim/weapon_registry.gd")
const ProgressionRegistryScript = preload("res://sim/progression_registry.gd")
const ROLL_LANES := ["HIT", "BLEED", "STUN"]


static func build_attack_spec(weapon_id: String, proficiency_rank: int,
		attacker_power: int, attacker_accuracy_milli: int,
		target_evasion_milli: int, target_armor_flat: int) -> Dictionary:
	var weapon = RegistryScript.definition(weapon_id)
	if weapon == null or proficiency_rank < 0 or proficiency_rank > ProgressionRegistryScript.MAX_RANK \
			or attacker_power < 0 or target_armor_flat < 0:
		return {}
	var proficiency_accuracy: int = ProgressionRegistryScript.proficiency_accuracy_bonus_milli(proficiency_rank)
	var proficiency_damage: int = ProgressionRegistryScript.proficiency_damage_bonus(proficiency_rank)
	var hit_chance: int = clampi(500 + attacker_accuracy_milli + weapon.accuracy_milli \
		- target_evasion_milli + proficiency_accuracy, 50, 950)
	var raw_damage: int = attacker_power + weapon.base_damage + proficiency_damage
	var effective_armor: int = maxi(0, target_armor_flat - weapon.armor_penetration_flat)
	var armor_reduction: int = mini(effective_armor, maxi(0, raw_damage - 1))
	var final_damage: int = maxi(1, raw_damage - armor_reduction)
	return {"schema_version":1, "ruleset_id":RULESET_ID,
		"weapon_id":weapon.weapon_id, "weapon_label":weapon.label,
		"proficiency_id":weapon.proficiency_id, "proficiency_rank":proficiency_rank,
		"attack_form":weapon.attack_form, "trait_id":weapon.trait_id,
		"range_min":weapon.range_min, "range_max":weapon.range_max,
		"attack_time":weapon.attack_time, "reload_time":weapon.reload_time,
		"ammo_kind":weapon.ammo_kind, "ammo_cost":weapon.ammo_cost,
		"reload_required":weapon.reload_required,
		"attacker_power":attacker_power, "weapon_damage":weapon.base_damage,
		"proficiency_damage":proficiency_damage, "raw_damage":raw_damage,
		"proficiency_accuracy_milli":proficiency_accuracy,
		"hit_chance_milli":hit_chance, "target_evasion_milli":target_evasion_milli,
		"target_armor_flat":target_armor_flat,
		"armor_penetration_flat":weapon.armor_penetration_flat,
		"armor_reduction":armor_reduction, "normal_final_damage":final_damage,
		"secondary_damage_milli":weapon.secondary_damage_milli,
		"stun_chance_milli":weapon.stun_chance_milli}.duplicate(true)


static func commitment_key(world_seed: int, processed_step_index: int,
		attack_start_world_time: int, batch_context: String, intent_ordinal: int,
		attacker_id: int, target_id: int, weapon_id: String, proficiency_rank: int) -> String:
	return "%s|seed=%d|step=%d|time=%d|batch=%s|ordinal=%d|attacker=%d|target=%d|weapon=%s|rank=%d" % [
		RULESET_ID, world_seed, processed_step_index, attack_start_world_time,
		batch_context, intent_ordinal, attacker_id, target_id, weapon_id, proficiency_rank]


static func lane_roll_milli(key: String, lane: String) -> int:
	if lane not in ROLL_LANES: return -1
	var digest: PackedByteArray = (key + "|lane=" + lane).sha256_buffer()
	var u31 := ((int(digest[0]) & 0x7f) << 24) | (int(digest[1]) << 16) \
		| (int(digest[2]) << 8) | int(digest[3])
	return u31 % 1000


static func resolve_attack_spec(spec: Dictionary, commitment: String) -> Dictionary:
	if spec.is_empty() or str(spec.get("ruleset_id", "")) != RULESET_ID \
			or commitment.is_empty():
		return {}
	var hit_roll: int = lane_roll_milli(commitment, "HIT")
	var stun_roll: int = lane_roll_milli(commitment, "STUN")
	var hit: bool = hit_roll < int(spec.hit_chance_milli)
	var damage: int = int(spec.normal_final_damage) if hit else 0
	var secondary_damage: int = int(damage * int(spec.secondary_damage_milli) / 1000) if hit else 0
	var stunned: bool = hit and int(spec.stun_chance_milli) > 0 \
		and stun_roll < int(spec.stun_chance_milli)
	return {"outcome":"HIT" if hit else "MISS", "hit_roll_milli":hit_roll,
		"stun_roll_milli":stun_roll, "final_damage":damage,
		"secondary_damage":secondary_damage, "stun_succeeded":stunned,
		"attack_time":int(spec.attack_time), "weapon_id":str(spec.weapon_id),
		"attack_form":str(spec.attack_form), "trait_id":str(spec.trait_id),
		"commitment_hash":commitment.sha256_text()}.duplicate(true)


static func targeting_error(attacker_position: Vector2i, target_position: Vector2i,
		weapon_id: String, occupants: Dictionary = {}) -> String:
	var weapon = RegistryScript.definition(weapon_id)
	if weapon == null: return "unknown_weapon"
	if attacker_position == target_position: return "self_target_forbidden"
	var delta := target_position - attacker_position
	var distance: int = maxi(absi(delta.x), absi(delta.y))
	if distance < weapon.range_min or distance > weapon.range_max: return "target_out_of_range"
	if weapon.trait_id == "SPEAR_REACH" and distance == 2:
		if not (delta.x == 0 or delta.y == 0 or absi(delta.x) == absi(delta.y)):
			return "spear_target_not_in_line"
		var middle := attacker_position + Vector2i(signi(delta.x), signi(delta.y))
		var middle_kind: String = str(occupants.get(middle, ""))
		# An ally may brace aside for the thrust. An enemy or solid obstruction may not.
		if not middle_kind.is_empty() and middle_kind != "ALLY": return "spear_line_blocked"
	elif weapon.proficiency_id == "RANGED":
		for cell in _line_cells(attacker_position, target_position):
			if occupants.has(cell): return "ranged_line_blocked"
	return ""


static func secondary_target_ids(primary_position: Vector2i, candidate_rows: Array) -> Array[int]:
	var result: Array[int] = []
	for row in candidate_rows:
		if not row is Dictionary or not row.has_all(["entity_id", "position"]): continue
		var position: Vector2i = row.position
		if position != primary_position \
				and maxi(absi(position.x - primary_position.x), absi(position.y - primary_position.y)) == 1:
			result.append(int(row.entity_id))
	result.sort()
	return result


static func _line_cells(from_position: Vector2i, to_position: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x0 := from_position.x
	var y0 := from_position.y
	var x1 := to_position.x
	var y1 := to_position.y
	var dx: int = absi(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -absi(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var error: int = dx + dy
	while true:
		if x0 == x1 and y0 == y1: break
		var twice: int = 2 * error
		if twice >= dy:
			error += dy
			x0 += sx
		if twice <= dx:
			error += dx
			y0 += sy
		if x0 == x1 and y0 == y1: break
		result.append(Vector2i(x0, y0))
	return result
