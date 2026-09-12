class_name Pixel24BuildingAssets
extends RefCounted
## Same-family facility symbols; the pack has no complete town buildings.
const ICONS={"STORAGE":"crate","LODGE":"knight_m_idle_anim_f0","CLINIC":"flask_red",
	"MARKET":"chest_full_open_anim_f0","ARMORY":"weapon_regular_sword","GATE":"doors_leaf_closed"}
static func texture(type_id:String,_level:int)->Texture2D:
	var id:=type_id.strip_edges().to_upper()
	return preload("res://playtest/dungeon_0x72_assets.gd").texture(str(ICONS[id])) if ICONS.has(id) else null
static func expected_size(_type_id:String)->Vector2i:
	return Vector2i(16,16)
