extends "res://tests/test_case.gd"

const SlotScript=preload("res://playtest/item_inventory_slot.gd")
const RegistryScript=preload("res://sim/item_registry.gd")
const AssetsScript=preload("res://playtest/fixed_front_topdown_assets.gd")

const EXPECTED_ICON_KINDS:={
	"WEAPON_SHORT_SWORD":"SWORD","WEAPON_THRUSTING_SWORD":"SWORD",
	"WEAPON_HAND_AXE":"AXE","WEAPON_MACE":"MACE","WEAPON_SPEAR":"SPEAR",
	"WEAPON_BOW":"BOW","WEAPON_CROSSBOW":"CROSSBOW","SHIELD_WOOD":"SHIELD",
	"ARMOR_HELMET":"HELMET","ARMOR_HOOD":"HOOD","POTION_HEALING":"POTION",
	"FOOD_RATION":"RATION",
}


func _spec(definition_id:String,slot:String="")->Dictionary:
	var definition=RegistryScript.definition(definition_id)
	var slot_node=SlotScript.new()
	slot_node.configure({"empty":false,"instance_id":"PROBE","definition_id":definition_id,
		"label":str(definition.label),"category":str(definition.category),"quantity":1},
		0,slot,false)
	var spec:Dictionary=slot_node.slot_draw_spec()
	slot_node.free()
	return spec


func test_inventory_cells_draw_unworn_items_instead_of_paper_doll_layers()->bool:
	# The fixed-front equipment atlas holds worn overlay layers: each silhouette is
	# authored at its position on a body canvas. An inventory cell must never
	# consume them, or a sword reads as a hand attachment and a cuirass as a torso.
	for definition_id in RegistryScript.ids():
		var definition=RegistryScript.definition(definition_id)
		var spec:=_spec(definition_id)
		check(not bool(spec.uses_texture) and spec.texture==null,
			"%s cell draws its own icon rather than a worn equipment layer"%definition_id)
		check(not str(spec.icon_kind).is_empty(),
			"%s cell resolves a named icon silhouette"%definition_id)
		if EXPECTED_ICON_KINDS.has(definition_id):
			check_eq(str(spec.icon_kind),str(EXPECTED_ICON_KINDS[definition_id]),
				"%s icon silhouette"%definition_id)
		elif str(definition.category)=="ARMOR" and definition_id!="SHIELD_WOOD":
			check_eq(str(spec.icon_kind),"ARMOR","%s icon silhouette"%definition_id)
	return finish()


func test_equipped_cells_keep_the_same_silhouette_as_backpack_cells()->bool:
	# Equipping must only change the cell's frame and corner marker. Showing the
	# worn art once equipped was the visible half of the same defect.
	for definition_id in ["WEAPON_SHORT_SWORD","WEAPON_BOW","SHIELD_WOOD"]:
		var definition=RegistryScript.definition(definition_id)
		var equip_slots:Array=definition.equip_slots
		if equip_slots.is_empty():continue
		check_eq(str(_spec(definition_id,str(equip_slots[0])).icon_kind),
			str(_spec(definition_id).icon_kind),
			"%s looks identical in the backpack and in its equipment slot"%definition_id)
	return finish()


func test_paper_doll_atlas_stays_available_for_actor_layers()->bool:
	# The fix removes the inventory's use of these layers, not the layers.
	check(AssetsScript.weapon_texture("WEAPON_SHORT_SWORD")!=null \
		and AssetsScript.armor_texture("ARMOR_LEATHER")!=null,
		"actor paper-doll registry still resolves its equipment layers")
	return finish()
