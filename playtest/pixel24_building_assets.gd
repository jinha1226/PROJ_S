class_name Pixel24BuildingAssets
extends RefCounted
## Tiny Dungeon has no town buildings. Use same-family facility symbols until
## a compatible Kenney town set is installed; do not mix former illustrations.
const ICONS={"STORAGE":90,"LODGE":88,"CLINIC":113,"MARKET":89,"ARMORY":104,"GATE":45}
static func texture(type_id:String,_level:int)->Texture2D:
	var id:=type_id.strip_edges().to_upper()
	return preload("res://playtest/kenney_dungeon_assets.gd").texture(int(ICONS[id])) if ICONS.has(id) else null
static func expected_size(_type_id:String)->Vector2i:
	return Vector2i(16,16)
