extends SceneTree
const Art=preload("res://playtest/fantasy_pawn_assets.gd")
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	if not value:failures.append(message)
func _init():
	var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/content/items.json"))
	for item:Dictionary in catalog.definitions:
		if not "ARMOR" in item.get("equip_slots",[]):continue
		var id:=str(item.definition_id)
		check(Art.Equipment.ARMORS.has(id),"Missing body overlay: "+id)
		for species:String in Art.BODIES:
			var spec:=Art.actor_spec({"species_id":species,"equipment_visual":{"armor_definition_id":id}})
			check(spec.armor_definition_id==id,"Lost equipment projection: "+id)
			check(spec.body_texture==Art.BODIES[species],"Base was replaced: "+species)
	for layers:Dictionary in [Art.Equipment.ARMORS,Art.Equipment.HELMETS]:
		for id:String in layers:
			var image:Image=layers[id].get_image()
			check(image.detect_alpha()!=Image.ALPHA_NONE,"Opaque layer: "+id)
			check(image.get_width()<=256 and image.get_height()<=256,"Oversize runtime layer: "+id)
	check(Art.actor_spec({"species_id":"human"}).armor_definition_id=="","Unequipped actor must stay unequipped")
	print("EQUIPMENT MATERIALS: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
