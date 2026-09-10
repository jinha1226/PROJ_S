class_name SpeciesDropRegistry
extends RefCounted

const CONTENT_PATH := "res://data/content/species_drop_tables.json"
const RULESET_ID := "species-drops-v3"
const PREVIOUS_RULESET_ID := "species-drops-v2"
const LEGACY_RULESET_ID := "species-drops-v1"
const ContentLoaderScript = preload("res://sim/json_content_loader.gd")
const ItemRegistryScript = preload("res://sim/item_registry.gd")
const ItemRewardRulesScript = preload("res://sim/item_reward_rules.gd")
const ActiveSkillRegistryScript = preload("res://sim/abilities/active_skill_registry.gd")
const REWARD_FAMILIES := ["CURRENCY", "MONSTER_ABILITY"]

static var _CONTENT: Dictionary = ContentLoaderScript.load_document(CONTENT_PATH)
static var _TABLES: Dictionary = ContentLoaderScript.index_rows(
	_CONTENT.get("tables", []), "species_id")


static func has_table(species_id: String) -> bool:
	return _TABLES.has(species_id) and _table_error(_TABLES[species_id]).is_empty()


static func species_ids() -> Array[String]:
	var result: Array[String] = []
	for species_id in _TABLES: result.append(str(species_id))
	result.sort()
	return result


static func rolls_for(world_seed: int, death_event_id: int, species_id: String,
		ruleset_id:String=RULESET_ID) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if death_event_id < 1 or ruleset_id not in [RULESET_ID,PREVIOUS_RULESET_ID,LEGACY_RULESET_ID] \
			or not registry_error().is_empty() or not has_table(species_id):
		return result
	for row in _TABLES[species_id].rolls:
		var key := "%s|seed=%d|death=%d|species=%s|roll=%s" % [
			ruleset_id, world_seed, death_event_id, species_id, str(row.roll_id)]
		if _keyed_u31(key, "CHANCE") % 1000 >= int(row.chance_per_1000):
			continue
		var span := int(row.max_quantity) - int(row.min_quantity) + 1
		var quantity := int(row.min_quantity) + _keyed_u31(key, "QUANTITY") % span
		result.append({"roll_id": str(row.roll_id),
			"definition_id": str(row.definition_id), "quantity": quantity})
	return result.duplicate(true)


static func rewards_for(world_seed:int,death_event_id:int,species_id:String,
		source_depth:int=1,floor_generation:int=0,source_id:String="")->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if death_event_id<1 or not registry_error().is_empty() or not has_table(species_id):return result
	for row in _TABLES[species_id].get("reward_rows",[]):
		if source_depth<int(row.min_depth) or source_depth>int(row.max_depth):continue
		if not source_id.is_empty() and str(row.source_id)!=source_id:continue
		var key:="%s|seed=%d|death=%d|species=%s|reward=%s"%[
			RULESET_ID,world_seed,death_event_id,species_id,str(row.reward_id)]
		if _keyed_u31(key,"CHANCE")%1000>=int(row.chance_per_1000):continue
		result.append({"reward_id":str(row.reward_id),
			"reward_family":str(row.reward_family),"definition_id":str(row.definition_id),
			"ability_id":str(row.ability_id),"amount":int(row.amount),
			"source_id":str(row.source_id),"min_depth":int(row.min_depth),
			"max_depth":int(row.max_depth),"floor_generation":floor_generation})
	return result.duplicate(true)


static func registry_error() -> String:
	var document_error := ContentLoaderScript.document_error(_CONTENT, "SPECIES_DROP_TABLES", [
		"content_schema_version", "content_version", "content_type", "ruleset_id", "tables"])
	if not document_error.is_empty(): return document_error
	if str(_CONTENT.get("ruleset_id", "")) != RULESET_ID: return "species_drop_ruleset_mismatch"
	var rows_error := ContentLoaderScript.rows_error(_CONTENT.get("tables", []), "species_id")
	if not rows_error.is_empty(): return rows_error
	var previous_species := ""
	var roll_ids: Dictionary = {}
	for table in _CONTENT.tables:
		var species_id := str(table.get("species_id", ""))
		if not previous_species.is_empty() and species_id <= previous_species:
			return "duplicate_or_unsorted_species_drop_table"
		previous_species = species_id
		var error := _table_error(table, roll_ids)
		if not error.is_empty(): return error
	return ""


static func _table_error(row: Variant, global_roll_ids_value: Variant = null) -> String:
	var global_roll_ids: Dictionary = global_roll_ids_value \
		if global_roll_ids_value is Dictionary else {}
	if not row is Dictionary: return "invalid_species_drop_table_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["reward_rows", "rolls", "species_id"] or not row.get("species_id") is String \
			or str(row.species_id).is_empty() or not row.get("rolls") is Array \
			or not row.get("reward_rows") is Array or row.rolls.size() > 16 \
			or row.reward_rows.size()>16:
		return "invalid_species_drop_table_shape"
	var previous_roll := ""
	for roll in row.rolls:
		if not roll is Dictionary: return "invalid_species_drop_roll_shape"
		var roll_keys: Array = roll.keys(); roll_keys.sort()
		if roll_keys != ["chance_per_1000", "definition_id", "max_quantity",
				"min_quantity", "roll_id"] \
				or not roll.definition_id is String \
				or not roll.chance_per_1000 is int or not roll.min_quantity is int \
				or not roll.max_quantity is int:
			return "invalid_species_drop_roll_shape"
		var roll_id := str(roll.roll_id)
		if not previous_roll.is_empty() and roll_id <= previous_roll:
			return "duplicate_or_unsorted_species_drop_roll"
		if global_roll_ids.has(roll_id): return "duplicate_species_drop_roll_id"
		global_roll_ids[roll_id] = true
		previous_roll = roll_id
		var definition = ItemRegistryScript.definition(str(roll.definition_id))
		if definition == null or str(definition.category) not in ["MATERIAL", "CONSUMABLE"]:
			return "invalid_species_drop_definition"
		if int(roll.chance_per_1000) < 0 or int(roll.chance_per_1000) > 1000 \
				or int(roll.min_quantity) < 1 \
				or int(roll.max_quantity) < int(roll.min_quantity) \
				or int(roll.max_quantity) > int(definition.stack_limit):
			return "invalid_species_drop_range"
	var previous_reward:=""
	for reward in row.reward_rows:
		if not reward is Dictionary:return "invalid_species_reward_shape"
		var reward_keys:Array=reward.keys();reward_keys.sort()
		if reward_keys!=["ability_id","amount","chance_per_1000","definition_id",
				"max_depth","min_depth","reward_family","reward_id","source_id"] \
				or not reward.reward_id is String \
				or str(reward.reward_id).is_empty() or not reward.reward_family is String \
				or str(reward.reward_family) not in REWARD_FAMILIES \
				or not reward.definition_id is String or not reward.ability_id is String \
				or not reward.source_id is String or str(reward.source_id).is_empty() \
				or not reward.chance_per_1000 is int or not reward.amount is int \
				or not reward.min_depth is int or not reward.max_depth is int:
			return "invalid_species_reward_shape"
		if not previous_reward.is_empty() and str(reward.reward_id)<=previous_reward:
			return "duplicate_or_unsorted_species_reward"
		previous_reward=str(reward.reward_id)
		if int(reward.chance_per_1000)<0 or int(reward.chance_per_1000)>1000 \
				or int(reward.amount)<1 or int(reward.amount)>1000 \
				or int(reward.min_depth)<1 or int(reward.max_depth)<int(reward.min_depth) \
				or int(reward.max_depth)>15:
			return "invalid_species_reward_range"
		if str(reward.reward_family)=="CURRENCY":
			if not str(reward.definition_id).is_empty() or not str(reward.ability_id).is_empty():
				return "invalid_species_currency_reward"
		elif str(reward.reward_family)=="MONSTER_ABILITY":
			if not ItemRegistryScript.has(str(reward.definition_id)) \
				or ItemRewardRulesScript.family_for_item(str(reward.definition_id))!="MONSTER_ABILITY" \
				or ItemRewardRulesScript.ability_for_item(str(reward.definition_id))!=str(reward.ability_id) \
				or not ActiveSkillRegistryScript.SKILLS.has(str(reward.ability_id)) \
				or int(reward.amount)!=1:
				return "invalid_species_ability_reward"
	return ""


static func _keyed_u31(key: String, channel: String) -> int:
	var digest: PackedByteArray = (key + "|channel=" + channel).sha256_buffer()
	return ((int(digest[0]) & 0x7f) << 24) | (int(digest[1]) << 16) \
		| (int(digest[2]) << 8) | int(digest[3])
