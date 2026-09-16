class_name TopdownTileAssets
extends RefCounted
## Generated fantasy art, source-derived connected walls, legacy terrain fallback.
const Legacy=preload("res://playtest/legacy_generated_tile_assets.gd")
const TILE_SIZE:=64
const FAMILY:="FANTASY_PAWNS_TERRAIN_V1"
const MATERIALS={"stone_floor":"stone_floor_a","cracked_stone":"cracked_floor",
	"mossy_stone":"moss_floor","wood_floor":"wood_floor","rubble":"rubble",
	"shallow_water":"water","deep_water":"water","pillar":"wall_end"}
const FLOOR_FEATURES={"floor_transition_portal":"stairs_down","run_exit_open":"stairs_up",
	"run_exit_locked":"stairs_up","anchor_portal_active":"stairs_up",
	"anchor_portal_inactive":"stairs_up","open_door":"door_open","pillar":"wall_end"}

static func tile_spec(cell:Dictionary,position:Vector2i,floor_index:int,
		neighbors:Dictionary={})->Dictionary:
	var visibility:=str(cell.get("visibility_state","UNSEEN")).to_upper()
	if visibility=="UNSEEN":return Legacy._hidden(floor_index,visibility)
	var terrain:=str(cell.get("terrain_id","floor"))
	var key:=""
	if terrain=="wall":
		var mask:=0
		for side in ["N","E","S","W"]:
			if Legacy._known_floor(neighbors,side):mask|={"N":1,"E":2,"S":4,"W":8}[side]
		key="wall_%02d"%mask
	elif terrain in ["door_closed","door_open"]:
		key=terrain
		if not Legacy._known_floor(neighbors,"N") and not Legacy._known_floor(neighbors,"S"):
			key+="_vertical"
	else:
		var feature:=str(cell.get("feature_id",""))
		var material:=str(cell.get("presentation_material_id",""))
		if FLOOR_FEATURES.has(feature):key=FLOOR_FEATURES[feature]
		elif visibility=="VISIBLE" and terrain in ["floor","stone_floor","wood_floor","metal","rubble"] and str(cell.get("surface_id","NONE"))!="ICE" and int(cell.get("wetness",0))>0:key="water"
		elif MATERIALS.has(material):key=MATERIALS[material]
		elif terrain in ["floor","stone_floor"]:
			var variant:=Legacy._variant_index(position,floor_index,12)
			key="cracked_floor" if variant==0 else "moss_floor" if variant==1 \
				else "stone_floor_b" if variant%3==0 else "stone_floor_a"
		elif MATERIALS.has(terrain):key=MATERIALS[terrain]
	if key.is_empty():return Legacy.tile_spec(cell,position,floor_index,neighbors)
	var texture:Texture2D=WALL_TEXTURES.get(key,TERRAIN_TEXTURES.get(key))
	return {"visible":true,"texture":texture,"region":Rect2(0,0,64,64),
		"is_wall":terrain=="wall","is_door":terrain in ["door_closed","door_open"],
		"asset_family":FAMILY,"sprite_key":key,"floor_index":floor_index,
		"tile_index":-1,"tint":Color(0.65,0.76,0.9) if terrain=="deep_water" else Color.WHITE,
		"visibility_state":visibility,"changes_mapping":false,"changes_fov":false,"draw_image":true}
const TERRAIN_TEXTURES={
	"cracked_floor":preload("res://assets/fantasy_pawns_v1/tiles/cracked_floor.png"),
	"door_closed":preload("res://assets/fantasy_pawns_v1/tiles/door_closed.png"),
	"door_closed_vertical":preload("res://assets/fantasy_pawns_v1/tiles/door_closed_vertical.png"),
	"door_open":preload("res://assets/fantasy_pawns_v1/tiles/door_open.png"),
	"door_open_vertical":preload("res://assets/fantasy_pawns_v1/tiles/door_open_vertical.png"),
	"moss_floor":preload("res://assets/fantasy_pawns_v1/tiles/moss_floor.png"),
	"pit":preload("res://assets/fantasy_pawns_v1/tiles/pit.png"),
	"rubble":preload("res://assets/fantasy_pawns_v1/tiles/rubble.png"),
	"stairs_down":preload("res://assets/fantasy_pawns_v1/tiles/stairs_down.png"),
	"stairs_up":preload("res://assets/fantasy_pawns_v1/tiles/stairs_up.png"),
	"stone_floor_a":preload("res://assets/fantasy_pawns_v1/tiles/stone_floor_a.png"),
	"stone_floor_b":preload("res://assets/fantasy_pawns_v1/tiles/stone_floor_b.png"),
	"wall_corner_nw":preload("res://assets/fantasy_pawns_v1/tiles/wall_corner_nw.png"),
	"wall_end":preload("res://assets/fantasy_pawns_v1/tiles/wall_end.png"),
	"wall_north":preload("res://assets/fantasy_pawns_v1/tiles/wall_north.png"),
	"wall_solid":preload("res://assets/fantasy_pawns_v1/tiles/wall_solid.png"),
	"water":preload("res://assets/fantasy_pawns_v1/tiles/water.png"),
	"wood_floor":preload("res://assets/fantasy_pawns_v1/tiles/wood_floor.png"),
}
const WALL_TEXTURES={
	"wall_00":preload("res://assets/fantasy_pawns_v1/walls/wall_00.png"),
	"wall_01":preload("res://assets/fantasy_pawns_v1/walls/wall_01.png"),
	"wall_02":preload("res://assets/fantasy_pawns_v1/walls/wall_02.png"),
	"wall_03":preload("res://assets/fantasy_pawns_v1/walls/wall_03.png"),
	"wall_04":preload("res://assets/fantasy_pawns_v1/walls/wall_04.png"),
	"wall_05":preload("res://assets/fantasy_pawns_v1/walls/wall_05.png"),
	"wall_06":preload("res://assets/fantasy_pawns_v1/walls/wall_06.png"),
	"wall_07":preload("res://assets/fantasy_pawns_v1/walls/wall_07.png"),
	"wall_08":preload("res://assets/fantasy_pawns_v1/walls/wall_08.png"),
	"wall_09":preload("res://assets/fantasy_pawns_v1/walls/wall_09.png"),
	"wall_10":preload("res://assets/fantasy_pawns_v1/walls/wall_10.png"),
	"wall_11":preload("res://assets/fantasy_pawns_v1/walls/wall_11.png"),
	"wall_12":preload("res://assets/fantasy_pawns_v1/walls/wall_12.png"),
	"wall_13":preload("res://assets/fantasy_pawns_v1/walls/wall_13.png"),
	"wall_14":preload("res://assets/fantasy_pawns_v1/walls/wall_14.png"),
	"wall_15":preload("res://assets/fantasy_pawns_v1/walls/wall_15.png"),
}
