class_name ItemCatalogRegistry
extends RefCounted

const Loader = preload("res://sim/json_content_loader.gd")
const Items = preload("res://sim/item_registry.gd")
const CONTENT_PATH := "res://data/content/item_catalog.json"
const FAMILIES := ["WEAPON", "ARMOR", "POTION", "FOOD", "MAGIC_STONE", "MATERIAL"]
const EFFECT_KINDS := ["NONE", "HEAL", "NUTRITION"]
static var _CONTENT:Dictionary = Loader.load_document(CONTENT_PATH)
static var _DEFINITIONS:Dictionary = Loader.index_rows(
	_CONTENT.get("definitions", []), "definition_id")


static func has(definition_id:String) -> bool:
	return _DEFINITIONS.has(definition_id) and _row_error(_DEFINITIONS[definition_id]).is_empty()


static func definition(definition_id:String) -> Dictionary:
	return _DEFINITIONS.get(definition_id, {}).duplicate(true) if has(definition_id) else {}


static func ids() -> Array[String]:
	var result:Array[String] = []
	for definition_id in _DEFINITIONS: result.append(str(definition_id))
	result.sort()
	return result


static func ids_for_family(family:String) -> Array[String]:
	var result:Array[String] = []
	for definition_id in ids():
		if str(_DEFINITIONS[definition_id].family) == family: result.append(definition_id)
	return result


static func family(definition_id:String) -> String:
	return str(definition(definition_id).get("family", ""))


static func healing_amount(definition_id:String) -> int:
	var row := definition(definition_id)
	return int(row.get("effect_power", 0)) if row.get("effect_kind", "") == "HEAL" else 0


static func nutrition_milli(definition_id:String) -> int:
	var row := definition(definition_id)
	return int(row.get("effect_power", 0)) * 1000 \
		if row.get("effect_kind", "") == "NUTRITION" else 0


static func buy_price(definition_id:String) -> int:
	return int(definition(definition_id).get("buy_price", 0))


static func sell_price(definition_id:String) -> int:
	return int(definition(definition_id).get("sell_price", 0))


static func available_at_depth(definition_id:String, depth:int) -> bool:
	var row := definition(definition_id)
	return not row.is_empty() and depth >= int(row.min_depth)


static func registry_error() -> String:
	var document_error := Loader.document_error(_CONTENT, "ITEM_CATALOG", [
		"content_schema_version", "content_version", "content_type", "ruleset_id", "definitions"])
	if not document_error.is_empty(): return document_error
	if str(_CONTENT.ruleset_id) != "item-catalog-v1": return "item_catalog_ruleset_mismatch"
	var rows_error := Loader.rows_error(_CONTENT.definitions, "definition_id")
	if not rows_error.is_empty(): return rows_error
	for definition_id in _DEFINITIONS:
		if str(_DEFINITIONS[definition_id].get("definition_id", "")) != definition_id:
			return "item_catalog_key_mismatch"
		var error := _row_error(_DEFINITIONS[definition_id])
		if not error.is_empty(): return error
	return ""


static func content_version() -> String:
	return str(_CONTENT.get("content_version", ""))


static func _row_error(row:Variant) -> String:
	if not row is Dictionary: return "invalid_item_catalog_shape"
	var keys:Array = row.keys(); keys.sort()
	if keys != ["buy_price", "definition_id", "effect_kind", "effect_power", "family",
			"min_depth", "sell_price", "tier"]:
		return "invalid_item_catalog_keys"
	for key in ["definition_id", "family", "effect_kind"]:
		if not row[key] is String: return "invalid_item_catalog_shape"
	for key in ["tier", "min_depth", "buy_price", "sell_price", "effect_power"]:
		if not row[key] is int or int(row[key]) < 0: return "invalid_item_catalog_number"
	if str(row.family) not in FAMILIES or str(row.effect_kind) not in EFFECT_KINDS:
		return "invalid_item_catalog_enum"
	if int(row.tier) > 3 or int(row.min_depth) > 99: return "invalid_item_catalog_number"
	var item = Items.definition(str(row.definition_id))
	if item == null: return "item_catalog_item_missing"
	var expected_category:String = str({
		"WEAPON":"WEAPON", "ARMOR":"ARMOR", "POTION":"CONSUMABLE",
		"FOOD":"CONSUMABLE", "MAGIC_STONE":"MATERIAL", "MATERIAL":"MATERIAL",
	}[str(row.family)])
	if str(item.category) != expected_category: return "item_catalog_category_mismatch"
	if str(row.family) == "POTION" and str(item.use_kind) != "HEALING":
		return "item_catalog_use_kind_mismatch"
	if str(row.family) == "FOOD" and str(item.use_kind) != "EAT":
		return "item_catalog_use_kind_mismatch"
	if str(row.effect_kind) == "HEAL" and (str(row.family) != "POTION" or int(row.effect_power) <= 0):
		return "item_catalog_effect_mismatch"
	if str(row.effect_kind) == "NUTRITION" and (str(row.family) != "FOOD" or int(row.effect_power) <= 0):
		return "item_catalog_effect_mismatch"
	if str(row.effect_kind) == "NONE" and int(row.effect_power) != 0:
		return "item_catalog_effect_mismatch"
	return ""
