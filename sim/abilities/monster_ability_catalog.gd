extends RefCounted
## Acquisition metadata. Per-definition effect_status must match runtime support.
const Loader=preload("res://sim/json_content_loader.gd")
static var DATA:Dictionary=Loader.load_document("res://data/content/monster_abilities.json")
static func for_item(id:String)->Dictionary:
	for row in DATA.get("definitions",[]):
		if str(row.essence_id)==id:return row.duplicate(true)
	return {}
