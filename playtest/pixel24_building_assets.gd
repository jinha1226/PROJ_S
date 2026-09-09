class_name Pixel24BuildingAssets
extends RefCounted

const TEXTURES:={
	"STORAGE":[preload("res://assets/pixel24_v3/runtime/buildings/storage_camp.png"),preload("res://assets/pixel24_v3/runtime/buildings/storage_timber.png"),preload("res://assets/pixel24_v3/runtime/buildings/storage_stone.png")],
	"LODGE":[preload("res://assets/pixel24_v3/runtime/buildings/lodge_camp.png"),preload("res://assets/pixel24_v3/runtime/buildings/lodge_timber.png"),preload("res://assets/pixel24_v3/runtime/buildings/lodge_stone.png")],
	"CLINIC":[preload("res://assets/pixel24_v3/runtime/buildings/clinic_camp.png"),preload("res://assets/pixel24_v3/runtime/buildings/clinic_timber.png"),preload("res://assets/pixel24_v3/runtime/buildings/clinic_stone.png")],
	"MARKET":[preload("res://assets/pixel24_v3/runtime/buildings/market_camp.png"),preload("res://assets/pixel24_v3/runtime/buildings/market_timber.png"),preload("res://assets/pixel24_v3/runtime/buildings/market_stone.png")],
	"ARMORY":[preload("res://assets/pixel24_v3/runtime/buildings/armory_camp.png"),preload("res://assets/pixel24_v3/runtime/buildings/armory_timber.png"),preload("res://assets/pixel24_v3/runtime/buildings/armory_stone.png")],
	"GATE":[preload("res://assets/pixel24_v3/runtime/buildings/gate_camp.png"),preload("res://assets/pixel24_v3/runtime/buildings/gate_timber.png"),preload("res://assets/pixel24_v3/runtime/buildings/gate_stone.png")],
}


static func texture(type_id:String,level:int)->Texture2D:
	var id:=type_id.strip_edges().to_upper()
	if not TEXTURES.has(id):return null
	return TEXTURES[id][clampi(level,1,3)-1]


static func expected_size(type_id:String)->Vector2i:
	return Vector2i(72,72) if type_id.strip_edges().to_upper() in ["STORAGE","CLINIC","GATE"] else Vector2i(72,48)
