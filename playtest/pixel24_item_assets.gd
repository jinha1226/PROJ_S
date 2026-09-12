class_name Pixel24ItemAssets
extends RefCounted

const ITEM_TEXTURES=preload("res://playtest/dungeon_0x72_assets.gd").ITEMS


static func texture_for_id(value:String)->Texture2D:
	return preload("res://playtest/dungeon_0x72_assets.gd").item(value.strip_edges())


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
		return texture_for_id("MATERIAL_UNSPECIFIED")
	if kind=="POTION" and ITEM_TEXTURES.has("POTION_UNSPECIFIED"):
		return texture_for_id("POTION_UNSPECIFIED")
	if kind=="ACCESSORY" and ITEM_TEXTURES.has("ACCESSORY_UNSPECIFIED"):
		return texture_for_id("ACCESSORY_UNSPECIFIED")
	return texture_for_id("DROPPED_ITEM")


static func ground_icon_key(cell:Dictionary)->String:
	var direct:=preload("res://playtest/ascii_visual_style.gd").item_presentation_spec(
		cell.get("ground_item_glyph",""))
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
	return "DROPPED_ITEM" if bool(direct.visible) else ""
