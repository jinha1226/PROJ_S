class_name ExposureSystem
extends RefCounted

const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const AffinityRegistryScript = preload("res://sim/species_hazard_affinity_registry.gd")
const ExposureSampleScript = preload("res://sim/exposure_sample.gd")
const ExposureEvaluationScript = preload("res://sim/exposure_evaluation.gd")
const DestinationAssessmentScript = preload("res://sim/destination_assessment.gd")
const EnvironmentRulesScript = preload("res://sim/environment_rules.gd")
const TimingScript = preload("res://sim/action_timing_table.gd")

var world
var movement_system


func _init(p_world, p_movement_system) -> void:
	world = p_world
	movement_system = p_movement_system


func sample(position: Vector2i):
	if not world.in_bounds(position) or not world.is_settled():
		return null
	var tile = world.tile_at(position)
	var terrain: Dictionary = TerrainRegistryScript.definition(tile.terrain)
	if terrain.is_empty():
		return null
	var next_environment_time := -1
	for entry in world.scheduled_entries:
		if entry["kind"] == "system.environment_tick":
			next_environment_time = int(entry["due_time"])
			break
	if next_environment_time < 0:
		return null
	var projection: Dictionary = EnvironmentRulesScript.project_existing_fire_tick(
		tile.fire, tile.wetness, tile.fire_damage_eligible_time, next_environment_time)
	var sources: Array[int] = []
	for source_id in [tile.fire_source_event_id, tile.wetness_source_event_id]:
		if source_id != -1 and not sources.has(source_id):
			sources.append(source_id)
	sources.sort()
	return ExposureSampleScript.new({
		"position": position, "sampled_step_index": world.step_index,
		"sampled_world_time": world.world_time,
		"after_event_id": world.events.back().id if not world.events.is_empty() else -1,
		"next_environment_time": next_environment_time,
		"terrain_id": tile.terrain, "passable": terrain["passable"],
		"move_time_cost": terrain["move_time_cost"],
		"fire_intensity": tile.fire,
		"fire_damage_eligible_time": tile.fire_damage_eligible_time,
		"known_fire_damage_at_next_tick": projection["known_damage"],
		"terrain_water_exposure": terrain["terrain_water_exposure"],
		"wetness": tile.wetness,
		"water_exposure": maxi(int(terrain["terrain_water_exposure"]), tile.wetness),
		"conductivity": tile.effective_conductivity(),
		"electric_risk": 0, "electric_certainty": "NONE", "poison_intensity": 0,
		"fire_source_event_id": tile.fire_source_event_id,
		"wetness_source_event_id": tile.wetness_source_event_id,
		"source_event_ids": sources,
	})


func evaluate_for_entity(entity_id: int, position: Vector2i):
	if not world.entities.has(entity_id) or not world.entities[entity_id].is_alive():
		return null
	var sampled = sample(position)
	if sampled == null:
		return null
	var affinity = AffinityRegistryScript.affinity_for(world.entities[entity_id].species_id)
	var evaluation = ExposureEvaluationScript.evaluate(sampled, affinity)
	return {"sample": sampled, "affinity": affinity, "evaluation": evaluation}


func assess_destination(entity_id: int, position: Vector2i):
	if not world.entities.has(entity_id) or not world.entities[entity_id].is_alive():
		return null
	var traversal = movement_system.assess_move(entity_id, position)
	var evaluated = evaluate_for_entity(entity_id, position)
	if evaluated == null:
		return DestinationAssessmentScript.new({"traversal": traversal})
	var cost := 0
	var tier := ""
	var sampled = evaluated["sample"]
	if sampled.passable and sampled.move_time_cost > 0:
		cost = sampled.move_time_cost
		tier = TimingScript.speed_tier_for(cost)
	return DestinationAssessmentScript.new({
		"traversal": traversal, "sample": evaluated["sample"],
		"affinity": evaluated["affinity"], "evaluation": evaluated["evaluation"],
		"move_time_cost": cost, "speed_tier": tier,
	})
