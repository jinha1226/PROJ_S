class_name SpeciesHazardAffinityRegistry
extends RefCounted

const RULESET_ID := "hazard-affinity-v1"
const HazardAffinityScript = preload("res://sim/hazard_affinity.gd")

const _PROFILES := {
	"default": {"species_id": "default", "fire_tolerance": 0, "water_tolerance": 0,
		"electric_tolerance": 0, "poison_tolerance": 0},
	"human": {"species_id": "human", "fire_tolerance": 20, "water_tolerance": 25,
		"electric_tolerance": 10, "poison_tolerance": 10},
	"goblin": {"species_id": "goblin", "fire_tolerance": -10, "water_tolerance": -10,
		"electric_tolerance": -10, "poison_tolerance": 10},
	"elf": {"species_id": "elf", "fire_tolerance": 20, "water_tolerance": 25,
		"electric_tolerance": 10, "poison_tolerance": 10},
	"orc": {"species_id": "orc", "fire_tolerance": 20, "water_tolerance": 25,
		"electric_tolerance": 10, "poison_tolerance": 10},
	"beastkin": {"species_id": "beastkin", "fire_tolerance": 20, "water_tolerance": 25,
		"electric_tolerance": 10, "poison_tolerance": 10},
	"dwarf": {"species_id": "dwarf", "fire_tolerance": 40, "water_tolerance": -25,
		"electric_tolerance": 20, "poison_tolerance": 20},
}


static func affinity_for(species_id: String):
	var resolved_id := species_id if not species_id.is_empty() and _PROFILES.has(species_id) else "default"
	return HazardAffinityScript.new(_PROFILES[resolved_id].duplicate(true))


static func all_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _PROFILES.keys()
	ids.sort()
	for species_id in ids:
		result.append(_PROFILES[species_id].duplicate(true))
	return result
