class_name ContentDatabase
extends RefCounted

const ProgressionRegistryScript=preload("res://sim/progression_registry.gd")
const WeaponRegistryScript=preload("res://sim/weapon_registry.gd")
const ItemRegistryScript=preload("res://sim/item_registry.gd")
const GrowthBuildRegistryScript=preload("res://sim/growth_build_registry.gd")
const SpeciesCatalogRegistryScript=preload("res://sim/species_catalog_registry.gd")
const BodyTemplateRegistryScript=preload("res://sim/body_template_registry.gd")


static func validation_error()->String:
	# Validate dependency leaves first so a broken permanent-id reference reports
	# its owning database instead of surfacing later during world bootstrap.
	for registry in [ProgressionRegistryScript,WeaponRegistryScript,
			ItemRegistryScript,SpeciesCatalogRegistryScript,GrowthBuildRegistryScript,
			BodyTemplateRegistryScript]:
		var error:String=registry.registry_error()
		if not error.is_empty():return error
	return ""


static func content_versions()->Dictionary:
	return {
		"proficiencies":ProgressionRegistryScript.content_version(),
		"weapons":WeaponRegistryScript.content_version(),
		"items":ItemRegistryScript.content_version(),
		"species_catalog":SpeciesCatalogRegistryScript.content_version(),
		"growth_builds":GrowthBuildRegistryScript.content_version(),
	}.duplicate(true)
