class_name GrowthBuildRegistry
extends RefCounted

const ContentLoaderScript=preload("res://sim/json_content_loader.gd")
const ItemRegistryScript=preload("res://sim/item_registry.gd")
const CONTENT_PATH:="res://data/content/growth_builds.json"
static var _CONTENT:Dictionary=ContentLoaderScript.load_document(CONTENT_PATH)
static var RULESET_ID:String=str(_CONTENT.get("ruleset_id",""))
static var SAVE_MIGRATION_POLICY:String=str(_CONTENT.get("save_migration_policy",""))

const MUTATION_ACQUISITION_POLICY := "FIRST_ELIGIBLE_KILL_GUARANTEED"
const BASE_MAX_HEALTH := 100
const HEALTH_PER_LEVEL := 2
const HEALTH_PER_VITALITY := 4
const STAT_POINT_INTERVAL := 3
const SPECIES_POINT_LEVELS := [7, 17]
const MUTATION_SLOT_COUNT := 3
const MUTATION_SWAP_TIME := 100
const SAFE_MUTATION_SWAP_PHASE := "GROUPED"
const MAX_AFFIXES_BY_RARITY := {"COMMON":0, "UNCOMMON":1, "RARE":2}
const MAX_AFFIXES_PER_KIND := 1
const MAX_XP := 1000000
const PICKER_SPECIES_IDS := ["human", "elf", "dwarf", "orc", "beastkin"]

static var STAT_IDS:Array[String]=ContentLoaderScript.ordered_ids(
	_CONTENT.get("stats",[]),"stat_id")
static var STAT_DEFINITIONS:Dictionary=ContentLoaderScript.index_rows(
	_CONTENT.get("stats",[]),"stat_id")
const EFFECT_TRIGGERS := ["PASSIVE", "ON_HIT", "ON_HURT", "INTERACT"]
const BONUS_KEYS := [
	"max_health", "might", "agility", "vitality", "armor_flat",
	"parry_milli", "dodge_milli", "stealth", "accuracy_milli",
	"damage_flat", "fire_tolerance", "water_tolerance",
	"electric_tolerance", "poison_tolerance",
]

static var SPECIES_DEFINITIONS:Dictionary=ContentLoaderScript.index_rows(
	_CONTENT.get("species",[]),"species_id")
static var MUTATION_DEFINITIONS:Dictionary=ContentLoaderScript.index_rows(
	_CONTENT.get("mutations",[]),"mutation_id")
static var AFFIX_BUILD_PROFILES:Dictionary=ContentLoaderScript.index_rows(
	_CONTENT.get("affix_build_profiles",[]),"affix_id")
static var MONSTER_SPECIES_FAMILIES:Dictionary=ContentLoaderScript.index_rows(
	_CONTENT.get("monster_species_families",[]),"species_id")


static func species_ids() -> Array[String]:
	var result: Array[String] = []
	for species_id in SPECIES_DEFINITIONS: result.append(str(species_id))
	result.sort()
	return result


static func picker_species_ids() -> Array[String]:
	var result: Array[String] = []
	for species_id in PICKER_SPECIES_IDS: result.append(species_id)
	return result


static func species_definition(species_id: String) -> Dictionary:
	return SPECIES_DEFINITIONS[species_id].duplicate(true) if has_species(species_id) else {}


static func has_species(species_id: String) -> bool:
	return SPECIES_DEFINITIONS.has(species_id) \
		and species_definition_error(SPECIES_DEFINITIONS[species_id]).is_empty()


static func branch_ids(species_id: String) -> Array[String]:
	var result: Array[String] = []
	if not SPECIES_DEFINITIONS.has(species_id): return result
	for branch in SPECIES_DEFINITIONS[species_id].branches:
		result.append(str(branch.branch_id))
	return result


static func species_effects(species_id: String, branch_ranks: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not has_species(species_id): return result
	var definition: Dictionary = SPECIES_DEFINITIONS[species_id]
	result.append(normalized_effect(definition.fixed_trait))
	for branch in definition.branches:
		var rank := int(branch_ranks.get(str(branch.branch_id), 0))
		for rank_index in range(mini(rank, branch.ranks.size())):
			result.append(normalized_effect(branch.ranks[rank_index]))
	return result


static func mutation_ids() -> Array[String]:
	var result: Array[String] = []
	for mutation_id in MUTATION_DEFINITIONS: result.append(str(mutation_id))
	result.sort()
	return result


static func mutation_for_family(monster_family_id: String) -> String:
	for mutation_id in mutation_ids():
		if str(MUTATION_DEFINITIONS[mutation_id].monster_family_id) == monster_family_id:
			return mutation_id
	return ""


static func monster_family_for_species(species_id: String) -> String:
	var row:Variant=MONSTER_SPECIES_FAMILIES.get(species_id)
	return str(row.get("monster_family_id","")) if row is Dictionary else ""


static func mutation_definition(mutation_id: String) -> Dictionary:
	return MUTATION_DEFINITIONS[mutation_id].duplicate(true) \
		if MUTATION_DEFINITIONS.has(mutation_id) else {}


static func level_for_xp(xp_total: int) -> int:
	var level := 1
	while level < 100 and xp_total >= xp_floor_for_level(level + 1): level += 1
	return level


static func xp_floor_for_level(level: int) -> int:
	if level <= 1: return 0
	return 25 * (level - 1) * (level + 2)


static func stat_points_for_level(level: int) -> int:
	return clampi(level, 1, 100) / STAT_POINT_INTERVAL


static func species_points_for_level(level: int) -> int:
	var result := 0
	for threshold in SPECIES_POINT_LEVELS:
		if level >= int(threshold): result += 1
	return result


static func empty_bonuses() -> Dictionary:
	var result := {}
	for key in BONUS_KEYS: result[key] = 0
	return result


static func normalized_effect(effect: Dictionary) -> Dictionary:
	var result: Dictionary = effect.duplicate(true)
	var bonuses := empty_bonuses()
	for key in BONUS_KEYS: bonuses[key] = int(effect.get("bonuses", {}).get(key, 0))
	result.bonuses = bonuses
	result.required_item_tags = _string_array(effect.get("required_item_tags", []))
	result.side_effect_ids = _string_array(effect.get("side_effect_ids", []))
	return result


static func content_version()->String:
	return str(_CONTENT.get("content_version",""))


static func registry_error() -> String:
	var document_error:=ContentLoaderScript.document_error(_CONTENT,"GROWTH_BUILDS",[
		"content_schema_version","content_version","content_type","ruleset_id",
		"save_migration_policy","stats","species","mutations",
		"affix_build_profiles","monster_species_families"])
	if not document_error.is_empty():return document_error
	if int(_CONTENT.get("content_schema_version",0))!=1:return "growth_content_schema_mismatch"
	if RULESET_ID!="playable-species-growth-v2":return "growth_ruleset_mismatch"
	if SAVE_MIGRATION_POLICY!="HARD_CUT":return "growth_migration_policy_mismatch"
	for pair in [["stats","stat_id"],["species","species_id"],
			["mutations","mutation_id"],["affix_build_profiles","affix_id"],
			["monster_species_families","species_id"]]:
		var rows_error:=ContentLoaderScript.rows_error(_CONTENT[str(pair[0])],str(pair[1]))
		if not rows_error.is_empty():return rows_error
	var stat_definition_ids: Array = STAT_DEFINITIONS.keys(); stat_definition_ids.sort()
	var expected_stat_ids: Array = STAT_IDS.duplicate(); expected_stat_ids.sort()
	if STAT_IDS != ["MIGHT","AGILITY","VITALITY"] \
			or stat_definition_ids != expected_stat_ids:
		return "invalid_growth_stat_definitions"
	for stat_id in STAT_IDS:
		var stat_row:Dictionary=STAT_DEFINITIONS[stat_id]
		var stat_keys:Array=stat_row.keys();stat_keys.sort()
		if stat_keys!=["label","stat_id"] \
				or str(stat_row.get("stat_id", "")) != stat_id \
				or str(stat_row.get("label", "")).is_empty():
			return "invalid_growth_stat_definition"
	if species_ids() != ["beastkin", "dwarf", "elf", "human", "orc"]:
		return "invalid_growth_species_set"
	if picker_species_ids()!=PICKER_SPECIES_IDS:return "invalid_growth_species_picker_order"
	for species_id in SPECIES_DEFINITIONS:
		if str(SPECIES_DEFINITIONS[species_id].get("species_id", "")) != species_id:
			return "growth_species_key_mismatch"
		var error := species_definition_error(SPECIES_DEFINITIONS[species_id])
		if not error.is_empty(): return error
	var seen_families := {}
	for mutation_id in MUTATION_DEFINITIONS:
		var row: Variant = MUTATION_DEFINITIONS[mutation_id]
		if not row is Dictionary or str(row.get("mutation_id", "")) != mutation_id:
			return "growth_mutation_key_mismatch"
		var keys: Array = row.keys(); keys.sort()
		if keys != ["effect", "label", "monster_family_id", "mutation_id"]:
			return "invalid_growth_mutation_keys"
		if str(row.label).is_empty() or str(row.monster_family_id).is_empty():
			return "invalid_growth_mutation_identity"
		if seen_families.has(row.monster_family_id): return "duplicate_growth_mutation_family"
		seen_families[row.monster_family_id] = true
		var mutation_effect_error := effect_error(row.effect)
		if not mutation_effect_error.is_empty(): return mutation_effect_error
	for affix_id in AFFIX_BUILD_PROFILES:
		var profile: Dictionary = AFFIX_BUILD_PROFILES[affix_id]
		var profile_keys:Array=profile.keys();profile_keys.sort()
		if profile_keys!=["affix_id","hook_id","kind"] \
				or str(profile.get("affix_id", "")) != affix_id \
				or str(profile.get("kind", "")) not in ["NUMERIC", "REACTIVE"] \
				or not profile.get("hook_id") is String \
				or not ItemRegistryScript.has_affix(affix_id):
			return "invalid_growth_affix_profile"
	for species_id in MONSTER_SPECIES_FAMILIES:
		var family_row:Dictionary=MONSTER_SPECIES_FAMILIES[species_id]
		var family_keys:Array=family_row.keys();family_keys.sort()
		if family_keys!=["monster_family_id","species_id"] \
				or str(family_row.species_id)!=species_id \
				or mutation_for_family(str(family_row.monster_family_id)).is_empty():
			return "invalid_growth_monster_family"
	return ""


static func species_definition_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_growth_species_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["branches", "fixed_trait", "label", "species_id", "weapon_familiarity"]:
		return "invalid_growth_species_keys"
	if str(row.species_id).is_empty() or str(row.label).is_empty() \
			or not row.branches is Array or row.branches.size() != 2:
		return "invalid_growth_species_shape"
	var fixed_error := effect_error(row.fixed_trait)
	if not fixed_error.is_empty(): return fixed_error
	if not row.weapon_familiarity is Dictionary:return "invalid_weapon_familiarity_shape"
	var familiarity_keys:Array=row.weapon_familiarity.keys();familiarity_keys.sort()
	if familiarity_keys!=["mode","weapon_tags"] \
			or str(row.weapon_familiarity.get("mode","")) not in ["ADAPTIVE","FIXED"] \
			or not row.weapon_familiarity.get("weapon_tags") is Array:
		return "invalid_weapon_familiarity_shape"
	if str(row.species_id)=="human" and str(row.weapon_familiarity.mode)!="ADAPTIVE":
		return "invalid_human_weapon_familiarity"
	if str(row.species_id)!="human" and str(row.weapon_familiarity.mode)!="FIXED":
		return "invalid_fixed_weapon_familiarity"
	var previous_tag:=""
	for tag in row.weapon_familiarity.weapon_tags:
		if not tag is String or str(tag).is_empty() \
				or (not previous_tag.is_empty() and str(tag)<=previous_tag):
			return "noncanonical_weapon_familiarity_tags"
		previous_tag=str(tag)
	var seen_branches := {}
	for branch in row.branches:
		if not branch is Dictionary: return "invalid_growth_species_branch_shape"
		var branch_keys: Array = branch.keys(); branch_keys.sort()
		if branch_keys != ["branch_id", "label", "ranks"]:
			return "invalid_growth_species_branch_keys"
		if str(branch.branch_id).is_empty() or str(branch.label).is_empty() \
				or seen_branches.has(branch.branch_id) or not branch.ranks is Array \
				or branch.ranks.size() != 2:
			return "invalid_growth_species_branch_shape"
		seen_branches[branch.branch_id] = true
		for effect in branch.ranks:
			var rank_error := effect_error(effect)
			if not rank_error.is_empty(): return rank_error
	return ""


static func effect_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_growth_effect_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["bonuses", "effect_id", "hook_id", "label", "required_item_tags",
			"side_effect_ids", "trigger"]:
		return "invalid_growth_effect_keys"
	if str(row.effect_id).is_empty() or str(row.label).is_empty() \
			or str(row.trigger) not in EFFECT_TRIGGERS or not row.bonuses is Dictionary \
			or not row.required_item_tags is Array or not row.side_effect_ids is Array:
		return "invalid_growth_effect_shape"
	for key in row.bonuses:
		if key not in BONUS_KEYS or not _integer(row.bonuses[key]) \
				or absi(int(row.bonuses[key])) > 10000:
			return "invalid_growth_effect_bonus"
	if str(row.trigger) != "PASSIVE" and str(row.hook_id).is_empty():
		return "missing_growth_effect_hook"
	for values in [row.required_item_tags, row.side_effect_ids]:
		var previous := ""
		for value in values:
			if not value is String or str(value).is_empty() or (not previous.is_empty() \
					and str(value) <= previous):
				return "noncanonical_growth_effect_values"
			previous = str(value)
	return ""


static func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values: result.append(str(value))
	return result


static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))
