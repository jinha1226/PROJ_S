class_name TopdownTileAssets
extends RefCounted
## Appearance only: terrain/FOV/pathing remain authoritative in the simulation.
const PackAssets=preload("res://playtest/dungeon_0x72_assets.gd")
const TILE_SIZE:=16
const FLOOR_TEXTURES={1:PackAssets.ATLAS,2:PackAssets.ATLAS}
const TERRAIN={"floor":["floor_1","floor_2","floor_3","floor_5"],
	"stone_floor":["floor_1","floor_2"],"wood_floor":["floor_7"],
	"metal":["floor_spikes_anim_f0"],"rubble":["floor_4","floor_8"],
	"shallow_water":["floor_1"],"wall":["wall_mid"]}
static func tile_spec(cell:Dictionary,position:Vector2i,floor_index:int)->Dictionary:
	var visibility:=str(cell.get("visibility_state","UNSEEN")).to_upper()
	if visibility=="UNSEEN":return {"visible":false,"texture":null,"region":Rect2(),
		"floor_index":floor_index,"tile_index":-1,"visibility_state":visibility,
		"changes_mapping":false,"changes_fov":false,"draw_image":false}
	var terrain:=str(cell.get("terrain_id","floor"))
	var choices:Array=TERRAIN.get(terrain,TERRAIN.floor)
	var key:String=choices[_variant_index(position,floor_index,choices.size())]
	var region:Rect2=PackAssets.RECTS[key]
	return {"visible":true,"texture":PackAssets.ATLAS,"region":region,"is_wall":terrain=="wall",
		"asset_family":"0X72_DUNGEON_II","floor_index":floor_index,
		"tile_index":int(region.position.y/16)*32+int(region.position.x/16),
		"tint":Color(0.4,0.85,1.0) if terrain=="shallow_water" else Color.WHITE,
		"visibility_state":visibility,"changes_mapping":false,"changes_fov":false,"draw_image":true}
static func _variant_index(position:Vector2i,floor_index:int,count:int)->int:
	if count<=1:return 0
	return posmod(position.x*73856093 ^ position.y*19349663 ^ floor_index*83492791,count)
