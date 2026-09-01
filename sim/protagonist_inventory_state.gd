class_name ProtagonistInventoryState
extends "res://sim/inventory_state.gd"

# Compatibility wrapper. `InventoryState` is the general 12-slot authority; this
# file only keeps the protagonist bootstrap helpers alive until session bootstrap
# owns them, so existing preloads of the old path keep resolving.


static func with_legacy_short_sword(instance_id:String="LEGACY_SHORT_SWORD"):
	return with_legacy_weapon("SHORT_SWORD",instance_id)


static func with_legacy_weapon(weapon_id:String,instance_id:String="LEGACY_MAIN_HAND"):
	var definition_id:=RegistryScript.weapon_definition_id(weapon_id)
	if definition_id.is_empty():return null
	var item=ItemScript.new(instance_id,definition_id)
	return load("res://sim/protagonist_inventory_state.gd").new([item],
		{"MAIN_HAND":instance_id})
