class_name ActorStatRules
extends RefCounted

const SpeciesCatalogScript=preload("res://sim/species_catalog_registry.gd")
const WeaponRegistryScript=preload("res://sim/weapon_registry.gd")
const STAT_IDS:=["STR","DEX","INT"]


static func baseline_stats()->Dictionary:
	var baseline:=int(WeaponRegistryScript.stat_scaling_rules().get("stat_baseline",0))
	return {"STR":baseline,"DEX":baseline,"INT":baseline}


static func for_species(species_id:String,allocations:Dictionary={})->Dictionary:
	var base:=SpeciesCatalogScript.base_stats(species_id)
	if base.is_empty():base=SpeciesCatalogScript.base_stats(
		SpeciesCatalogScript.FALLBACK_SPECIES_ID)
	var result:Dictionary={}
	for stat_id in STAT_IDS:
		result[stat_id]=int(base.get(stat_id,5))+int(allocations.get(stat_id,0))
	return result


static func for_growth_state(state)->Dictionary:
	if state==null:return baseline_stats()
	return for_species(str(state.species_id),state.stat_allocations)


static func for_entity(world,entity_id:int)->Dictionary:
	if world==null or not world.entities.has(entity_id):return baseline_stats()
	var entity=world.entities[entity_id]
	if world.party_encounter!=null and int(world.party_encounter.protagonist_id)==entity_id:
		return for_growth_state(world.party_encounter.protagonist_growth)
	return for_species(str(entity.species_id))


static func requirements_error(stats:Dictionary,requirements:Dictionary)->String:
	for stat_id in STAT_IDS:
		if int(stats.get(stat_id,0))<int(requirements.get(stat_id,0)):
			return "item_requirements_not_met"
	return ""
