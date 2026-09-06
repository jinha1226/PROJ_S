class_name PartyRationSystem
extends RefCounted

## Party-wide ration gauge: drains with world time and party size. Pure function of
## world time, active member count and party state; no RNG, no frame time.

const RulesScript = preload("res://sim/party_ration_rules.gd")


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
	state.revision += 1
	return true


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
