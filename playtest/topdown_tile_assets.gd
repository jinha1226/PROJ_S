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
static func tile_spec(cell:Dictionary,position:Vector2i,floor_index:int,neighbors:Dictionary={})->Dictionary:
	var visibility:=str(cell.get("visibility_state","UNSEEN")).to_upper()
	if visibility=="UNSEEN":return {"visible":false,"texture":null,"region":Rect2(),
		"floor_index":floor_index,"tile_index":-1,"visibility_state":visibility,
		"changes_mapping":false,"changes_fov":false,"draw_image":false}
	var terrain:=str(cell.get("terrain_id","floor"))
	var choices:Array=TERRAIN.get(terrain,TERRAIN.floor)
	var key:String=choices[_variant_index(position,floor_index,choices.size())]
	if terrain=="wall":key=_wall_key(neighbors)
	var region:Rect2=PackAssets.RECTS[key]
	return {"visible":true,"texture":PackAssets.ATLAS,"region":region,"is_wall":terrain=="wall",
		"asset_family":"0X72_DUNGEON_II","sprite_key":key,"floor_index":floor_index,
		"tile_index":int(region.position.y/16)*32+int(region.position.x/16),
		"tint":Color(0.4,0.85,1.0) if terrain=="shallow_water" else Color.WHITE,
		"visibility_state":visibility,"changes_mapping":false,"changes_fov":false,"draw_image":true}

static func _known_floor(neighbors:Dictionary,side:String)->bool:
	var row:Dictionary=neighbors.get(side,{})
	# Never consult hidden terrain to choose a silhouette.
	return str(row.get("visibility_state","UNSEEN")) in ["VISIBLE","MEMORY"] \
		and str(row.get("terrain_id","wall"))!="wall"

static func _wall_key(neighbors:Dictionary)->String:
	var n:=_known_floor(neighbors,"N");var e:=_known_floor(neighbors,"E")
	var s:=_known_floor(neighbors,"S");var w:=_known_floor(neighbors,"W")
	# Original side strips stay at their native 16px cell position, not stretched
	# into a full-width front face. Front/back faces remain horizontal.
	if s:
		if e and not w:return "wall_left"
		if w and not e:return "wall_right"
		return "wall_mid"
	if n:
		if e and not w:return "wall_top_left"
		if w and not e:return "wall_top_right"
		return "wall_top_mid"
	if e:return "wall_outer_mid_left"
	if w:return "wall_outer_mid_right"
	# Room corners can touch known floor diagonally without a cardinal opening.
	if _known_floor(neighbors,"SE"):return "wall_outer_top_left"
	if _known_floor(neighbors,"SW"):return "wall_outer_top_right"
	if _known_floor(neighbors,"NE"):return "wall_outer_front_left"
	if _known_floor(neighbors,"NW"):return "wall_outer_front_right"
	return "wall_mid"
static func _variant_index(position:Vector2i,floor_index:int,count:int)->int:
	if count<=1:return 0
	return posmod(position.x*73856093 ^ position.y*19349663 ^ floor_index*83492791,count)
