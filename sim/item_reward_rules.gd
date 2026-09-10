class_name ItemRewardRules
extends RefCounted

## Shared presentation/usage contract for the first reward slice.  The item
## registry remains the ownership authority; this table only says what a
## registered item is primarily for.
const RULESET_ID := "item-reward-families-v1"
const ItemCatalog = preload("res://sim/item_catalog_registry.gd")
const FAMILIES := ["WEAPON_MATERIAL", "CRAFT_MATERIAL", "CURRENCY", "MONSTER_ABILITY", "BASE_MATERIAL", "SUPPLY", "SPECIAL"]
const LABELS := {
	"WEAPON_MATERIAL":"무기 업그레이드 소재",
	"CRAFT_MATERIAL":"제작 재료",
	"CURRENCY":"돈·환금품",
	"MONSTER_ABILITY":"몬스터 이능",
	"BASE_MATERIAL":"거점 업그레이드 재료",
	"SUPPLY":"보급품",
	"SPECIAL":"특별 발견",
}
const ITEM_FAMILIES := {
	"MATERIAL_IRON_INGOT":"WEAPON_MATERIAL",
	"MAGIC_STONE":"CURRENCY",
	"ESSENCE_FIRE_BOLT":"MONSTER_ABILITY",
	"FOOD_RATION":"SUPPLY",
	"POTION_HEALING":"SUPPLY",
	"POTION_UNSPECIFIED":"SUPPLY",
}
const ITEM_PURPOSES := {
	"MATERIAL_IRON_INGOT":"무기 재제작용",
	"MAGIC_STONE":"환금품·거래용",
	"ESSENCE_FIRE_BOLT":"이능 흡수 전 보관",
	"FOOD_RATION":"원정 보급품",
	"POTION_HEALING":"회복용 보급품",
}


static func family_for_item(definition_id:String)->String:
	if ITEM_FAMILIES.has(definition_id):return str(ITEM_FAMILIES[definition_id])
	match ItemCatalog.family(definition_id):
		"MAGIC_STONE":return "CURRENCY"
		"POTION","FOOD":return "SUPPLY"
		"MATERIAL":
			return "WEAPON_MATERIAL" if definition_id in ["MATERIAL_IRON_INGOT",
				"MAT_WEAPON_TOUGH_WOOD","MAT_WEAPON_STEEL","MAT_WEAPON_HEARTWOOD"] \
				else "CRAFT_MATERIAL"
	return "SPECIAL"


static func purpose_for_item(definition_id:String)->String:
	if ITEM_PURPOSES.has(definition_id):return str(ITEM_PURPOSES[definition_id])
	match ItemCatalog.family(definition_id):
		"MAGIC_STONE":return "환금품·거래용"
		"POTION":return "회복용 보급품"
		"FOOD":return "원정 보급품"
		"MATERIAL":return "제작 재료"
	return ""


static func ability_for_item(definition_id:String)->String:
	return {"ESSENCE_FIRE_BOLT":"FIREBOLT"}.get(definition_id,"")


static func family_label(family:String)->String:
	return str(LABELS.get(family,family))


static func base_resource_family(resource_id:String)->String:
	return "BASE_MATERIAL" if resource_id in ["TIMBER","STONE","HERBS"] else ""
