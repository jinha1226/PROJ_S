class_name Pixel24ItemAssets
extends RefCounted

const ITEM_TEXTURES:={
	"POTION_HEALING":preload("res://assets/pixel24_v3/runtime/items/potion_healing.png"),
	"FOOD_RATION":preload("res://assets/pixel24_v3/runtime/items/food_ration.png"),
	"SCROLL_UNSPECIFIED":preload("res://assets/pixel24_v3/runtime/items/scroll_unspecified.png"),
	"ACCESSORY_BRASS_CHARM":preload("res://assets/pixel24_v3/runtime/items/accessory_brass_charm.png"),
	"GOBLIN_EAR":preload("res://assets/pixel24_v3/runtime/items/goblin_ear.png"),
	"MATERIAL_UNSPECIFIED":preload("res://assets/pixel24_v3/runtime/items/material_unspecified.png"),
	"MAGIC_STONE":preload("res://assets/pixel24_v3/runtime/items/material_unspecified.png"),
	"POTION_UNSPECIFIED":preload("res://assets/pixel24_v3/runtime/items/potion_unspecified.png"),
	"ACCESSORY_UNSPECIFIED":preload("res://assets/pixel24_v3/runtime/items/accessory_unspecified.png"),
}
const RESOURCE_TEXTURES:={
	"TIMBER":preload("res://assets/pixel24_v3/runtime/items/resource_timber.png"),
	"STONE":preload("res://assets/pixel24_v3/runtime/items/resource_stone.png"),
	"HERBS":preload("res://assets/pixel24_v3/runtime/items/resource_herbs.png"),
}
const PRESENTATION_TEXTURES:={
	"DROPPED_ITEM":preload("res://assets/pixel24_v3/runtime/items/dropped_item_marker.png"),
	"LOOT_SACK":preload("res://assets/pixel24_v3/runtime/items/loot_sack.png"),
	"TOWN_GOLD":preload("res://assets/pixel24_v3/runtime/items/town_gold.png"),
}


static func texture_for_id(value:String)->Texture2D:
	var id:=value.strip_edges().to_upper()
	if ITEM_TEXTURES.has(id):return ITEM_TEXTURES[id]
	if RESOURCE_TEXTURES.has(id):return RESOURCE_TEXTURES[id]
	if PRESENTATION_TEXTURES.has(id):return PRESENTATION_TEXTURES[id]
	return null


static func texture_for_row(row:Dictionary)->Texture2D:
	for key in ["definition_id","resource_id","item_definition_id"]:
		if row.has(key):
			var texture:=texture_for_id(str(row[key]))
			if texture!=null:return texture
	return null


static func ground_texture(row:Dictionary,presentation_kind:String)->Texture2D:
	var texture:=texture_for_row(row)
	if texture!=null:return texture
	var kind:=presentation_kind.strip_edges().to_upper()
	if kind=="MATERIAL" and ITEM_TEXTURES.has("MATERIAL_UNSPECIFIED"):
		return ITEM_TEXTURES["MATERIAL_UNSPECIFIED"]
	if kind=="POTION" and ITEM_TEXTURES.has("POTION_UNSPECIFIED"):
		return ITEM_TEXTURES["POTION_UNSPECIFIED"]
	if kind=="ACCESSORY" and ITEM_TEXTURES.has("ACCESSORY_UNSPECIFIED"):
		return ITEM_TEXTURES["ACCESSORY_UNSPECIFIED"]
	return PRESENTATION_TEXTURES["DROPPED_ITEM"]


static func ground_icon_key(cell:Dictionary)->String:
	var direct:=preload("res://playtest/ascii_visual_style.gd").item_presentation_spec(
		cell.get("ground_item_glyph",""))
	if bool(direct.visible):return "DROPPED_ITEM"
	var values:Variant=cell.get("ground_items",[])
	if not values is Array:return ""
	for value in values:
		var spec:=preload("res://playtest/ascii_visual_style.gd").item_presentation_spec(value)
		if not bool(spec.visible):continue
		if value is Dictionary:
			for key in ["definition_id","resource_id","item_definition_id"]:
				var id:=str(value.get(key,"")).to_upper()
				if texture_for_id(id)!=null:return id
		match str(spec.kind):
			"MATERIAL":return "MATERIAL_UNSPECIFIED"
			"POTION":return "POTION_UNSPECIFIED"
			"ACCESSORY":return "ACCESSORY_UNSPECIFIED"
		return "DROPPED_ITEM"
	return ""
