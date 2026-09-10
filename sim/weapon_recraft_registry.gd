class_name WeaponRecraftRegistry
extends RefCounted

const RULESET_ID := "weapon-recraft-v1"
const ItemRegistryScript = preload("res://sim/item_registry.gd")
const WeaponRegistryScript = preload("res://sim/weapon_registry.gd")
const RECIPES := {
	"WEAPON_SHORT_SWORD": {
		"target_definition_id":"WEAPON_SHORT_SWORD_IRON",
		"material_definition_id":"MATERIAL_IRON_INGOT",
		"material_quantity":1,
		"gold_cost":0,
	}
}


static func recipe_for(definition_id:String)->Dictionary:
	return RECIPES.get(definition_id,{}).duplicate(true)


static func source_definition_ids()->Array[String]:
	var result:Array[String]=[]
	for value in RECIPES:result.append(str(value))
	result.sort();return result


static func registry_error()->String:
	for source_id in source_definition_ids():
		var row:Dictionary=RECIPES[source_id]
		if not ItemRegistryScript.has(source_id):return "recraft_source_missing"
		var source=ItemRegistryScript.definition(source_id)
		var target_id:=str(row.target_definition_id)
		var material_id:=str(row.material_definition_id)
		if source==null or source.category!="WEAPON" or not ItemRegistryScript.has(target_id):
			return "recraft_target_invalid"
		var target=ItemRegistryScript.definition(target_id)
		if target==null or target.category!="WEAPON" or str(target.weapon_id).is_empty():
			return "recraft_target_invalid"
		if WeaponRegistryScript.definition(str(source.weapon_id))==null \
				or WeaponRegistryScript.definition(str(target.weapon_id))==null:
			return "recraft_weapon_missing"
		if not ItemRegistryScript.has(material_id) \
				or ItemRegistryScript.definition(material_id).category!="MATERIAL":
			return "recraft_material_invalid"
		if int(row.material_quantity)<1 or int(row.gold_cost)<0:return "recraft_cost_invalid"
	return ""
