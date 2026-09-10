class_name ItemRewardRules
extends RefCounted

## Shared presentation/usage contract for the first reward slice.  The item
## registry remains the ownership authority; this table only says what a
## registered item is primarily for.
const RULESET_ID := "item-reward-families-v1"
const FAMILIES := ["WEAPON_MATERIAL", "CURRENCY", "MONSTER_ABILITY", "BASE_MATERIAL", "SUPPLY", "SPECIAL"]
const LABELS := {
	"WEAPON_MATERIAL":"무기 업그레이드 소재",
	"CURRENCY":"돈·환금품",
	"MONSTER_ABILITY":"몬스터 이능",
	"BASE_MATERIAL":"거점 업그레이드 재료",
	"SUPPLY":"보급품",
	"SPECIAL":"특별 발견",
}
const ITEM_FAMILIES := {
	"MATERIAL_IRON_INGOT":"WEAPON_MATERIAL",
	"MAGIC_STONE":"CURRENCY",
	"FOOD_RATION":"SUPPLY",
	"POTION_HEALING":"SUPPLY",
	"POTION_UNSPECIFIED":"SUPPLY",
}
const ITEM_PURPOSES := {
	"MATERIAL_IRON_INGOT":"무기 재제작용",
	"MAGIC_STONE":"환금품·거래용",
	"FOOD_RATION":"원정 보급품",
	"POTION_HEALING":"회복용 보급품",
}


static func family_for_item(definition_id:String)->String:
	return str(ITEM_FAMILIES.get(definition_id,"SPECIAL"))


static func purpose_for_item(definition_id:String)->String:
	return str(ITEM_PURPOSES.get(definition_id,""))


static func family_label(family:String)->String:
	return str(LABELS.get(family,family))


static func base_resource_family(resource_id:String)->String:
	return "BASE_MATERIAL" if resource_id in ["TIMBER","STONE","HERBS"] else ""
