class_name DarknessStressRules
extends RefCounted

## Event-sourced darkness exposure. Exposure is reconstructed from the event
## tail, while stress is applied through the existing party morale system.
const RULESET_ID := "darkness-stress-v1"
const EVENT_EXPOSURE_CHANGED := "darkness.exposure_changed"
const DEEP_DARK_THRESHOLD := 180
const GRACE_TIME := 300
const MAX_EXPOSURE := 2000
const STRESS_PER_100_TIME := 12

const VisionRulesScript = preload("res://sim/vision_rules.gd")

static func state(world, entity_id: int) -> Dictionary:
	var result := {"entity_id": entity_id, "exposure": 0, "deep_dark": false,
		"illumination": 0, "grace_remaining": GRACE_TIME,
		"last_event_id": -1, "sampled_world_time": -1}
	if world == null or not world.entities.has(entity_id): return result
	var latest = _latest_event(world, entity_id)
	if latest != null:
		result.last_event_id = int(latest.id)
		result.exposure = clampi(int(latest.data.get("exposure_after", 0)), 0, MAX_EXPOSURE)
		result.sampled_world_time = int(latest.world_time)
	var lighting := VisionRulesScript.lighting_for_world(world)
	result.illumination = VisionRulesScript.illumination(
		world, world.entities[entity_id].position, lighting)
	result.deep_dark = int(result.illumination) < DEEP_DARK_THRESHOLD
	result.grace_remaining = maxi(0, GRACE_TIME - int(result.exposure))
	return result


static func commit_boundary(world, start_time: int, end_time: int) -> bool:
	if world == null or world.party_encounter == null or end_time <= start_time:
		return true
	var elapsed := end_time - start_time
	var ids: Array[int] = []
	for raw_id in world.party_encounter.active_party_member_ids:
		var entity_id := int(raw_id)
		var member = world.party_encounter.member(entity_id)
		var combatant = world.combatant_states.get(entity_id)
		if member == null or combatant == null or not world.entities.has(entity_id): continue
		if member.presence not in ["DEPLOYED", "GROUPED"] or combatant.life_state == "DEAD": continue
		ids.append(entity_id)
	ids.sort()
	for entity_id in ids:
		var previous := state(world, entity_id)
		var before := int(previous.exposure)
		var illumination := int(previous.illumination)
		var deep_dark := illumination < DEEP_DARK_THRESHOLD
		var after := mini(MAX_EXPOSURE, before + elapsed) if deep_dark else maxi(0, before - elapsed)
		if after == before: continue
		var member = world.party_encounter.member(entity_id)
		var profile := VisionRulesScript.profile_for_entity(world.entities[entity_id])
		var resistance := clampi(int(profile.get("darkness_stress_resistance_milli", 500)), 0, 1000)
		var before_progress := maxi(0, before - GRACE_TIME)
		var after_progress := maxi(0, after - GRACE_TIME)
		var susceptibility := 1000 - resistance
		var before_stress := int(before_progress * STRESS_PER_100_TIME * susceptibility / 100000.0)
		var after_stress := int(after_progress * STRESS_PER_100_TIME * susceptibility / 100000.0)
		var stress_delta := maxi(0, after_stress - before_stress)
		var event: Variant = world.emit_event(EVENT_EXPOSURE_CHANGED, entity_id, -1,
			world.entities[entity_id].position, stress_delta, -1, {
				"schema_version": 1, "ruleset_id": RULESET_ID,
				"exposure_before": before, "exposure_after": after,
				"elapsed": elapsed, "illumination": illumination,
				"deep_dark": deep_dark, "stress_delta": stress_delta,
				"resistance_milli": resistance})
		if event == null: return false
	return true


static func _latest_event(world, entity_id: int):
	for index in range(world.events.size() - 1, -1, -1):
		var event = world.events[index]
		if str(event.type) == EVENT_EXPOSURE_CHANGED and int(event.actor_id) == entity_id:
			return event
	return null
