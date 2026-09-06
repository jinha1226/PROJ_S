class_name PartyRationSystem
extends RefCounted

## Party-wide ration gauge: drains with world time and party size. Pure function of
## world time, active member count and party state; no RNG, no frame time.

const RulesScript = preload("res://sim/party_ration_rules.gd")
const WorldItemOperationsScript = preload("res://sim/world_item_operations.gd")


static func band(world) -> String:
	if world == null or world.party_encounter == null: return "FED"
	return RulesScript.band(int(world.party_encounter.ration_milli))


static func active_member_count(world) -> int:
	var count := 0
	for member_id in world.party_encounter.active_party_member_ids:
		var combatant = world.combatant_states.get(int(member_id))
		if combatant != null and str(combatant.life_state) == "ACTIVE": count += 1
	return maxi(1, count)


static func process_tick(world, damage, processed_step_index: int) -> bool:
	if world == null or world.party_encounter == null: return true
	var state = world.party_encounter
	if state.expedition_cycle == null or str(state.expedition_cycle.phase) != "DUNGEON":
		# Town never drains; keep the clock current so departure starts fresh.
		state.ration_processed_at = int(world.world_time)
		return true
	var rules := RulesScript.rules()
	var interval := int(rules.drain_interval)
	var elapsed := int(world.world_time) - int(state.ration_processed_at)
	var intervals := elapsed / interval
	if intervals <= 0: return true
	var before_band := RulesScript.band(int(state.ration_milli))
	var drain := intervals * RulesScript.drain_per_interval_milli(active_member_count(world))
	state.ration_milli = maxi(0, int(state.ration_milli) - drain)
	state.ration_processed_at = int(state.ration_processed_at) + intervals * interval
	var after_band := RulesScript.band(int(state.ration_milli))
	if after_band != before_band:
		if not _emit_band_change(world, before_band, after_band): return false
	if after_band != "FED":
		var had_food := not _first_food_instance_id(world).is_empty()
		if not auto_eat(world): return false
		if not had_food and after_band != before_band and not _emit_missing(world): return false
	state.revision += 1
	return true


static func _first_food_instance_id(world) -> String:
	var inventory = world.inventory_of(int(world.party_encounter.protagonist_id))
	if inventory == null: return ""
	var food_id := str(RulesScript.rules().food_definition_id)
	var ids: Array = []
	for item in inventory.backpack:
		if str(item.definition_id) == food_id and int(item.quantity) > 0:
			ids.append(str(item.instance_id))
	ids.sort()
	return "" if ids.is_empty() else str(ids[0])


static func auto_eat(world) -> bool:
	# Only the protagonist's bag feeds the party, and one ration is the most a
	# single tick may consume: the gauge climbs back in food_nutrition steps.
	var state = world.party_encounter
	if RulesScript.band(int(state.ration_milli)) == "FED": return true
	var instance_id := _first_food_instance_id(world)
	if instance_id.is_empty(): return true
	if not world.has_event_id_headroom(2): return false
	var used: Dictionary = WorldItemOperationsScript.commit_use_without_event(world,
		int(state.protagonist_id), instance_id)
	if not bool(used.get("accepted", false)): return true
	var before_band := RulesScript.band(int(state.ration_milli))
	state.ration_milli = mini(RulesScript.ration_max_milli(),
		int(state.ration_milli) + RulesScript.food_nutrition_milli())
	var event = world.emit_event("party.ration_eaten", int(state.protagonist_id), -1,
		_hero_position(world), 0, -1, {"schema_version": 1,
			"ruleset_id": RulesScript.RULESET_ID, "definition_id": str(used.get("definition_id", "")),
			"instance_id": instance_id, "ration_milli": int(state.ration_milli)})
	if event == null: return false
	var after_band := RulesScript.band(int(state.ration_milli))
	if after_band != before_band and not _emit_band_change(world, before_band, after_band):
		return false
	return true


static func _emit_missing(world) -> bool:
	if not world.has_event_id_headroom(1): return false
	var state = world.party_encounter
	return world.emit_event("party.ration_missing", int(state.protagonist_id), -1,
		_hero_position(world), 0, -1, {"schema_version": 1,
			"ruleset_id": RulesScript.RULESET_ID, "ration_milli": int(state.ration_milli)}) != null


static func _hero_position(world) -> Vector2i:
	var hero = world.entities.get(int(world.party_encounter.protagonist_id))
	return hero.position if hero != null else Vector2i(-1, -1)


static func _emit_band_change(world, before_band: String, after_band: String) -> bool:
	if not world.has_event_id_headroom(1): return false
	var state = world.party_encounter
	var event = world.emit_event("party.ration_changed", int(state.protagonist_id), -1,
		_hero_position(world), 0, -1, {"schema_version": 1,
			"ruleset_id": RulesScript.RULESET_ID, "before": before_band, "after": after_band,
			"ration_milli": int(state.ration_milli)})
	return event != null
