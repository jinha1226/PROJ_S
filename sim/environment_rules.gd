class_name EnvironmentRules
extends RefCounted

const FIRE_DECAY_PER_ENVIRONMENT_TICK := 5
const WETNESS_DECAY_PER_ENVIRONMENT_TICK := 2
const FIRE_DAMAGE_CAP_PER_ENVIRONMENT_TICK := 20


static func project_existing_fire_tick(fire: int, wetness: int,
		fire_damage_eligible_time: int, environment_time: int) -> Dictionary:
	var checked_fire := clampi(fire, 0, 100)
	var checked_wetness := clampi(wetness, 0, 100)
	var suppression := mini(checked_fire, checked_wetness)
	var fire_after_suppression := checked_fire - suppression
	var wetness_after_suppression := checked_wetness - suppression
	var fire_after_decay := maxi(
		0, fire_after_suppression - FIRE_DECAY_PER_ENVIRONMENT_TICK)
	var known_damage := 0
	if fire_after_decay > 0 and fire_damage_eligible_time >= 0 \
			and environment_time >= fire_damage_eligible_time:
		known_damage = mini(FIRE_DAMAGE_CAP_PER_ENVIRONMENT_TICK, fire_after_decay)
	return {
		"suppression": suppression,
		"fire_after_suppression": fire_after_suppression,
		"wetness_after_suppression": wetness_after_suppression,
		"fire_after_decay": fire_after_decay,
		"known_damage": known_damage,
	}
