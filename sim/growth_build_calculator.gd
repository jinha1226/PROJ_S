class_name GrowthBuildCalculator
extends RefCounted

const GrowthRegistry = preload("res://sim/growth_build_registry.gd")
const ItemRegistryScript = preload("res://sim/item_registry.gd")
const WeaponRegistryScript = preload("res://sim/weapon_registry.gd")
const ActorStatRulesScript=preload("res://sim/actor_stat_rules.gd")
const SpeciesCatalogScript=preload("res://sim/species_catalog_registry.gd")
const EQUIPMENT_SLOTS := ["MAIN_HAND", "OFF_HAND", "ARMOR", "ACCESSORY_1", "ACCESSORY_2"]


static func calculate(state, equipped_items: Dictionary) -> Dictionary:
	if state == null or not state.has_method("validation_error") \
			or not state.validation_error().is_empty():
		return _rejected("invalid_growth_state")
	var item_error := loadout_error(equipped_items)
	if not item_error.is_empty(): return _rejected(item_error)
	var item_projection := _project_items(equipped_items,state.species_id)
	var item_tags: Array[String] = item_projection.item_tags
	var aggregate: Dictionary = GrowthRegistry.empty_bonuses()
	for key in aggregate: aggregate[key] = int(item_projection.bonuses.get(key, 0))
	var effect_hooks := {"PASSIVE":[], "ON_HIT":[], "ON_HURT":[], "INTERACT":[]}
	var active_effect_ids: Array[String] = []
	var inactive_effect_ids: Array[String] = []
	var side_effect_ids: Array[String] = []
	var species_effect_ids: Array[String] = []
	var mutation_effect_ids: Array[String] = []

	for effect in GrowthRegistry.species_effects(state.species_id, state.species_branch_ranks):
		species_effect_ids.append(str(effect.effect_id))
		_apply_effect(effect, "SPECIES", state.species_id, item_tags, aggregate,
			effect_hooks, active_effect_ids, inactive_effect_ids, side_effect_ids)
	for mutation_id in state.equipped_mutation_ids:
		if mutation_id.is_empty(): continue
		var definition := GrowthRegistry.mutation_definition(mutation_id)
		var effect := GrowthRegistry.normalized_effect(definition.effect)
		mutation_effect_ids.append(str(effect.effect_id))
		_apply_effect(effect, "MUTATION", mutation_id, item_tags, aggregate,
			effect_hooks, active_effect_ids, inactive_effect_ids, side_effect_ids)
	for affix_hook in item_projection.affix_hooks:
		effect_hooks[str(affix_hook.trigger)].append(affix_hook.duplicate(true))
		active_effect_ids.append(str(affix_hook.effect_id))

	var stats := ActorStatRulesScript.for_growth_state(state)
	var weapon: Dictionary = item_projection.weapon.duplicate(true)
	weapon.damage_flat_bonus = int(aggregate.damage_flat)
	weapon.resolved_damage = int(weapon.base_damage) + int(weapon.damage_flat_bonus)
	weapon.accuracy_bonus_milli = int(aggregate.accuracy_milli)
	weapon.resolved_accuracy_milli = int(weapon.base_accuracy_milli) \
		+ int(weapon.accuracy_bonus_milli)
	var defense := {
		"armor_flat":int(aggregate.armor_flat), "parry_milli":int(aggregate.parry_milli),
		"dodge_milli":int(aggregate.dodge_milli),
		"stealth":int(aggregate.stealth),
	}
	var hazard_tolerance_bonuses := {
		"fire":int(aggregate.fire_tolerance), "water":int(aggregate.water_tolerance),
		"electric":int(aggregate.electric_tolerance),
		"poison":int(aggregate.poison_tolerance),
	}
	var maximum_health: int = GrowthRegistry.BASE_MAX_HEALTH \
		+ (state.level() - 1) * GrowthRegistry.HEALTH_PER_LEVEL \
		+ int(aggregate.max_health)
	var build := {
		"ruleset_id":GrowthRegistry.RULESET_ID,
		"save_migration_policy":GrowthRegistry.SAVE_MIGRATION_POLICY,
		"species_id":state.species_id,
		"level":state.level(), "xp_total":state.xp_total,
		"stats":stats, "stat_points_available":state.stat_points_available(),
		"species_points_available":state.species_points_available(),
		"max_health":maximum_health, "weapon":weapon, "defense":defense,
		"hazard_tolerance_bonuses":hazard_tolerance_bonuses,
		"item_tags":item_tags.duplicate(),
		"equipped_item_rows":item_projection.equipped_item_rows.duplicate(true),
		"species_effect_ids":species_effect_ids,
		"equipped_mutation_ids":state.equipped_mutation_ids.duplicate(),
		"mutation_effect_ids":mutation_effect_ids,
		"active_effect_ids":active_effect_ids,
		"inactive_effect_ids":inactive_effect_ids,
		"effect_hooks":effect_hooks.duplicate(true),
		"side_effect_ids":_unique_sorted(side_effect_ids),
	}
	return {"accepted":true, "reason":"", "build":build.duplicate(true)}


static func loadout_error(equipped_items: Variant) -> String:
	if not equipped_items is Dictionary: return "invalid_growth_loadout_shape"
	for slot in equipped_items:
		if not slot is String or str(slot) not in EQUIPMENT_SLOTS:
			return "invalid_growth_equipment_slot"
	var seen_instances := {}
	var main_definition = null
	for slot in EQUIPMENT_SLOTS:
		if not equipped_items.has(slot) or equipped_items[slot] == null: continue
		var item: Variant = equipped_items[slot]
		if typeof(item) != TYPE_OBJECT or not item.has_method("validation_error") \
				or not item.validation_error().is_empty():
			return "invalid_growth_equipped_item"
		if seen_instances.has(item.instance_id): return "duplicate_growth_equipped_instance"
		seen_instances[item.instance_id] = true
		var definition = ItemRegistryScript.definition(str(item.definition_id))
		if definition == null or slot not in definition.equip_slots:
			return "growth_item_slot_mismatch"
		if slot == "MAIN_HAND": main_definition = definition
		var seen_affix_kinds := {}
		for affix_id in item.affix_ids:
			if not GrowthRegistry.AFFIX_BUILD_PROFILES.has(affix_id):
				return "unknown_growth_affix_profile"
			var kind := str(GrowthRegistry.AFFIX_BUILD_PROFILES[affix_id].kind)
			if seen_affix_kinds.has(kind): return "duplicate_growth_affix_kind"
			seen_affix_kinds[kind] = true
	if main_definition != null and ItemRegistryScript.is_two_handed(main_definition.definition_id) \
			and equipped_items.get("OFF_HAND") != null:
		return "growth_two_handed_offhand_conflict"
	return ""


static func _project_items(equipped_items: Dictionary,species_id:String="human") -> Dictionary:
	var bonuses := GrowthRegistry.empty_bonuses()
	var tags: Array[String] = []
	var rows: Array[Dictionary] = []
	var affix_hooks: Array[Dictionary] = []
	var weapon_definition = WeaponRegistryScript.definition(
		SpeciesCatalogScript.natural_weapon_id(species_id))
	for slot in EQUIPMENT_SLOTS:
		if not equipped_items.has(slot) or equipped_items[slot] == null: continue
		var item = equipped_items[slot]
		var definition = ItemRegistryScript.definition(str(item.definition_id))
		var item_tags := _item_tags(slot, item, definition)
		for tag in item_tags: tags.append(tag)
		for key in definition.bonuses:
			if bonuses.has(key): bonuses[key] = int(bonuses[key]) + int(definition.bonuses[key])
		for affix_id in item.affix_ids:
			var affix := ItemRegistryScript.affix(affix_id)
			for key in affix.bonuses:
				if bonuses.has(key): bonuses[key] = int(bonuses[key]) + int(affix.bonuses[key])
			for hook_id in affix.hook_ids:
				affix_hooks.append(_affix_hook(affix_id, str(hook_id), slot))
			var profile: Dictionary = GrowthRegistry.AFFIX_BUILD_PROFILES[affix_id]
			if not str(profile.hook_id).is_empty():
				affix_hooks.append(_affix_hook(affix_id, str(profile.hook_id), slot))
		if slot == "MAIN_HAND": weapon_definition = WeaponRegistryScript.definition(definition.weapon_id)
		rows.append({"slot":slot, "instance_id":str(item.instance_id),
			"definition_id":str(item.definition_id), "rarity":str(item.rarity),
			"affix_ids":item.affix_ids.duplicate(), "tags":item_tags})
	var weapon := {
		"weapon_id":str(weapon_definition.weapon_id), "attack_form":str(weapon_definition.attack_form),
		"range_min":int(weapon_definition.range_min), "range_max":int(weapon_definition.range_max),
		"attack_time":int(weapon_definition.attack_time),
		"base_damage":int(weapon_definition.base_damage),
		"base_accuracy_milli":int(weapon_definition.accuracy_milli),
		"armor_penetration_flat":int(weapon_definition.armor_penetration_flat),
		"trait_id":str(weapon_definition.trait_id), "two_handed":bool(weapon_definition.two_handed),
	}
	return {"bonuses":bonuses, "item_tags":_unique_sorted(tags),
		"equipped_item_rows":rows, "affix_hooks":affix_hooks, "weapon":weapon}


static func _item_tags(slot: String, item, definition) -> Array[String]:
	var tags: Array[String] = ["CATEGORY_%s" % definition.category, "SLOT_%s" % slot,
		"RARITY_%s" % item.rarity]
	if not item.affix_ids.is_empty(): tags.append("HAS_AFFIX")
	for affix_id in item.affix_ids: tags.append("AFFIX_%s" % affix_id)
	if definition.category == "WEAPON":
		var weapon = WeaponRegistryScript.definition(definition.weapon_id)
		tags.append("WEAPON")
		tags.append("FORM_%s" % weapon.attack_form)
		tags.append("PROFICIENCY_%s" % weapon.proficiency_id)
		tags.append("RANGED" if int(weapon.range_min) > 1 else "MELEE")
		if bool(weapon.two_handed): tags.append("TWO_HANDED")
		if str(weapon.trait_id) != "NONE": tags.append("TRAIT_%s" % weapon.trait_id)
	return _unique_sorted(tags)


static func _apply_effect(effect: Dictionary, source_kind: String, source_id: String,
		item_tags: Array[String], aggregate: Dictionary, effect_hooks: Dictionary,
		active_effect_ids: Array[String], inactive_effect_ids: Array[String],
		side_effect_ids: Array[String]) -> void:
	var active := true
	for required_tag in effect.required_item_tags:
		if required_tag not in item_tags:
			active = false
			break
	if not active:
		inactive_effect_ids.append(str(effect.effect_id))
		return
	active_effect_ids.append(str(effect.effect_id))
	for side_effect_id in effect.side_effect_ids: side_effect_ids.append(str(side_effect_id))
	if str(effect.trigger) == "PASSIVE":
		for key in GrowthRegistry.BONUS_KEYS:
			aggregate[key] = int(aggregate[key]) + int(effect.bonuses[key])
	if not str(effect.hook_id).is_empty():
		effect_hooks[str(effect.trigger)].append({
			"effect_id":str(effect.effect_id), "source_kind":source_kind,
			"source_id":source_id, "hook_id":str(effect.hook_id),
			"bonuses":effect.bonuses.duplicate(true),
			"required_item_tags":effect.required_item_tags.duplicate(),
			"side_effect_ids":effect.side_effect_ids.duplicate(),
		})


static func _affix_hook(affix_id: String, hook_id: String, slot: String) -> Dictionary:
	return {"effect_id":"AFFIX_%s_%s" % [affix_id, hook_id], "source_kind":"AFFIX",
		"source_id":affix_id, "hook_id":hook_id, "trigger":"ON_HURT",
		"bonuses":GrowthRegistry.empty_bonuses(), "required_item_tags":["SLOT_%s" % slot],
		"side_effect_ids":[]}


static func _unique_sorted(values: Array) -> Array[String]:
	var seen := {}
	var result: Array[String] = []
	for value in values:
		var text := str(value)
		if not seen.has(text): seen[text] = true; result.append(text)
	result.sort()
	return result


static func _rejected(reason: String) -> Dictionary:
	return {"accepted":false, "reason":reason, "build":{}}
