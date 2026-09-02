extends "res://tests/test_case.gd"

const Loader=preload("res://sim/json_content_loader.gd")
const Growth=preload("res://sim/growth_build_registry.gd")
const Items=preload("res://sim/item_registry.gd")
const Weapons=preload("res://sim/weapon_registry.gd")
const Progression=preload("res://sim/progression_registry.gd")
const ContentDatabase=preload("res://sim/content_database.gd")

const DOCUMENTS := {
	"GROWTH_BUILDS":"res://data/content/growth_builds.json",
	"ITEMS":"res://data/content/items.json",
	"WEAPONS":"res://data/content/weapons.json",
	"PROFICIENCIES":"res://data/content/proficiencies.json",
}


func test_content_documents_are_readable_versioned_and_detached()->bool:
	for content_type in DOCUMENTS:
		var first:Dictionary=Loader.load_document(DOCUMENTS[content_type])
		var second:Dictionary=Loader.load_document(DOCUMENTS[content_type])
		check(not first.is_empty() and first==second,
			"%s JSON loads deterministically"%content_type)
		check_eq(first.get("content_schema_version"),1,
			"%s uses the supported content schema"%content_type)
		check(not str(first.get("content_version","")).is_empty(),
			"%s publishes an authoring version"%content_type)
		first["content_version"]="tampered"
		check(str(second.get("content_version",""))!="tampered",
			"%s loads detached data"%content_type)
	check_eq([Growth.registry_error(),Items.registry_error(),Weapons.registry_error(),
		Progression.registry_error()],["","","",""],
		"all JSON-backed registries pass strict validation")
	check_eq(ContentDatabase.validation_error(),"",
		"the session-level content database passes integrated validation")
	return finish()


func test_content_ids_cross_reference_without_runtime_names()->bool:
	for definition_id in Items.ids():
		var item=Items.definition(definition_id)
		if item!=null and item.category=="WEAPON":
			check(Weapons.has(item.weapon_id),
				"item %s references a permanent weapon id"%definition_id)
	for weapon_id in Weapons.ids():
		var weapon=Weapons.definition(weapon_id)
		check(weapon!=null and weapon.proficiency_id in Progression.PROFICIENCY_IDS,
			"weapon %s references a permanent proficiency id"%weapon_id)
	for affix_id in Growth.AFFIX_BUILD_PROFILES:
		check(Items.has_affix(affix_id),
			"growth affix profile %s references the item database"%affix_id)
	for species_id in Growth.MONSTER_SPECIES_FAMILIES:
		check(not Growth.mutation_for_family(
			Growth.monster_family_for_species(species_id)).is_empty(),
			"monster species %s references a mutation family"%species_id)
	return finish()


func test_loader_rejects_wrong_schema_keys_and_duplicate_ids()->bool:
	var valid:Dictionary=Loader.load_document(DOCUMENTS.PROFICIENCIES)
	var expected_keys:Array=valid.keys();expected_keys.sort()
	check_eq(Loader.document_error(valid,"PROFICIENCIES",expected_keys),"",
		"valid document envelope is accepted")
	var wrong_schema:Dictionary=valid.duplicate(true);wrong_schema.content_schema_version=2
	check_eq(Loader.document_error(wrong_schema,"PROFICIENCIES",expected_keys),
		"content_schema_unsupported","future content schema fails closed")
	var unknown_key:Dictionary=valid.duplicate(true);unknown_key["extra"]={}
	check_eq(Loader.document_error(unknown_key,"PROFICIENCIES",expected_keys),
		"content_document_keys_invalid","unknown top-level content field fails closed")
	var duplicate_rows:Array=valid.definitions.duplicate(true)
	duplicate_rows.append(valid.definitions[0].duplicate(true))
	check_eq(Loader.rows_error(duplicate_rows,"proficiency_id"),
		"content_row_identity_duplicate","duplicate permanent ids fail closed")
	return finish()


func test_registry_views_match_the_json_authority()->bool:
	var item_document:Dictionary=Loader.load_document(DOCUMENTS.ITEMS)
	var item_rows:Dictionary=Loader.index_rows(item_document.definitions,"definition_id")
	for definition_id in Items.ids():
		check_eq(Items.definition_dict(definition_id),item_rows[definition_id],
			"item registry view matches JSON for %s"%definition_id)
	var weapon_document:Dictionary=Loader.load_document(DOCUMENTS.WEAPONS)
	var weapon_rows:Dictionary=Loader.index_rows(weapon_document.definitions,"weapon_id")
	for weapon_id in Weapons.ids():
		check_eq(Weapons.definition_dict(weapon_id),weapon_rows[weapon_id],
			"weapon registry view matches JSON for %s"%weapon_id)
	var growth_document:Dictionary=Loader.load_document(DOCUMENTS.GROWTH_BUILDS)
	var species_rows:Dictionary=Loader.index_rows(growth_document.species,"species_id")
	for species_id in Growth.species_ids():
		check_eq(Growth.species_definition(species_id),species_rows[species_id],
			"species registry view matches JSON for %s"%species_id)
	check_eq([Growth.content_version(),Items.content_version(),Weapons.content_version(),
		Progression.content_version()],["growth-builds-2026-09-02-species-v2","items-2026-09-01",
		"weapons-2026-09-01","proficiencies-2026-09-01"],
		"content versions are visible to diagnostics")
	check_eq(ContentDatabase.content_versions(),{
		"proficiencies":"proficiencies-2026-09-01",
		"weapons":"weapons-2026-09-01",
		"items":"items-2026-09-01",
		"growth_builds":"growth-builds-2026-09-02-species-v2",
	},"integrated content versions are available for diagnostics")
	return finish()
