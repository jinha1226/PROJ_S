extends SceneTree
const Art=preload("res://playtest/fantasy_pawn_assets.gd")
const Ground=preload("res://playtest/pixel24_item_assets.gd")
const Equipped=preload("res://playtest/fixed_front_topdown_assets.gd")
var failures:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init():
	for id in ["WEAPON_CROSSBOW","WEAPON_CROSSBOW_STEEL_HEARTWOOD","WEAPON_MACE","WEAPON_MACE_STEEL","WEAPON_SPEAR","WEAPON_SPEAR_STEEL","WEAPON_DCSS_CLUB"]:
		var texture=Art.item(id)
		check(texture!=null and texture.get_size()==Vector2(128,128),id+" has a runtime sprite")
		check(Equipped.weapon_texture(id)==texture,id+" equip and inventory agree")
		check(Ground.ground_icon_key({"ground_items":[{"definition_id":id,"category":"WEAPON"}]})==id,id+" never falls back to a sack")
	check(Art.item("WEAPON_CROSSBOW")!=Art.item("WEAPON_BOW"),"crossbow is not a bow placeholder")
	for i in range(9):
		var texture=Art.item("MYSTERY_POTION_%d"%i)
		check(texture!=null and texture.get_size()==Vector2(128,128),"mystery potion uses new family")
	print("FANTASY ITEM EXPANSION: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
