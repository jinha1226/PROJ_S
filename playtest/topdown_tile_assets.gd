class_name TopdownTileAssets
extends RefCounted
## Presentation-only mapping for the generated orthographic 64px tile set.
const TILE_SIZE:=64
const FAMILY:="GENERATED_TOPDOWN_64_V1"
const TERRAIN_TEXTURES={
	"stone_floor":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/stone_floor.png"),
	"cracked_stone":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/cracked_stone.png"),
	"mossy_stone":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/mossy_stone.png"),
	"dirt":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/dirt.png"),
	"grass":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/grass.png"),
	"rubble":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/rubble.png"),
	"shallow_water":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/shallow_water.png"),
	"deep_water":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/deep_water.png"),
	"wall_cap":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/wall_cap.png"),
	"pillar":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/pillar.png"),
	"low_cover":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/low_cover.png"),
	"crate":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/crate.png"),
	"iron_plate":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/iron_plate.png"),
	"spikes":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/spikes.png"),
	"exit_rune":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/exit_rune.png"),
	"lava":preload("res://assets/generated/topdown_tactical64_v1/runtime/tiles/lava.png"),
}
const WALL_TEXTURES={
	"wall_stone":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/wall_stone.png"),
	"wall_stone_moss":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/wall_stone_moss.png"),
	"wall_brick":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/wall_brick.png"),
	"wall_stone_ruined":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/wall_stone_ruined.png"),
	"wall_timber":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/wall_timber.png"),
	"wall_timber_reinforced":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/wall_timber_reinforced.png"),
	"wall_iron":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/wall_iron.png"),
	"wall_natural_rock":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/wall_natural_rock.png"),
	"door_stone_horizontal_closed":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/door_stone_horizontal_closed.png"),
	"door_stone_horizontal_open":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/door_stone_horizontal_open.png"),
	"door_stone_vertical_closed":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/door_stone_vertical_closed.png"),
	"door_stone_vertical_open":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/door_stone_vertical_open.png"),
	"door_timber_horizontal_closed":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/door_timber_horizontal_closed.png"),
	"door_timber_horizontal_open":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/door_timber_horizontal_open.png"),
	"door_timber_vertical_closed":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/door_timber_vertical_closed.png"),
	"door_timber_vertical_open":preload("res://assets/generated/topdown_walls_doors64_v1/runtime/tiles/door_timber_vertical_open.png"),
}
const FLOOR_FEATURES={"floor_transition_portal":"exit_rune","run_exit_open":"exit_rune",
	"run_exit_locked":"exit_rune","anchor_portal_active":"exit_rune",
	"anchor_portal_inactive":"exit_rune","open_door":"exit_rune","pillar":"pillar",
	"low_cover":"low_cover","crate":"crate"}

static func tile_spec(cell:Dictionary,position:Vector2i,floor_index:int,
		neighbors:Dictionary={})->Dictionary:
	var visibility:=str(cell.get("visibility_state","UNSEEN")).to_upper()
	if visibility=="UNSEEN":return _hidden(floor_index,visibility)
	var terrain:=str(cell.get("terrain_id","floor"))
	var key:=_texture_key(cell,position,floor_index,neighbors)
	var texture:Texture2D=WALL_TEXTURES.get(key,TERRAIN_TEXTURES.get(key,null))
	if texture==null:key="stone_floor";texture=TERRAIN_TEXTURES[key]
	return {"visible":true,"texture":texture,"region":Rect2(0,0,TILE_SIZE,TILE_SIZE),
		"is_wall":terrain=="wall","is_door":terrain in ["door_closed","door_open"],
		"asset_family":FAMILY,"sprite_key":key,"floor_index":floor_index,
		"tile_index":-1,"tint":Color.WHITE,"visibility_state":visibility,
		"changes_mapping":false,"changes_fov":false,"draw_image":true}

static func _texture_key(cell:Dictionary,position:Vector2i,floor_index:int,
		neighbors:Dictionary)->String:
	var terrain:=str(cell.get("terrain_id","floor"))
	if terrain=="wall":
		var choices:=["wall_stone","wall_stone_moss","wall_stone_ruined"] \
			if floor_index<=1 else ["wall_brick","wall_iron","wall_natural_rock"]
		return choices[_variant_index(position,floor_index,choices.size())]
	if terrain in ["door_closed","door_open"]:
		var material:="stone" if floor_index<=1 else "timber"
		var orientation:="horizontal" if _known_floor(neighbors,"N") \
			or _known_floor(neighbors,"S") else "vertical"
		return "door_%s_%s_%s"%[material,orientation,
			"closed" if terrain=="door_closed" else "open"]
	var feature:=str(cell.get("feature_id",""))
	if FLOOR_FEATURES.has(feature):return FLOOR_FEATURES[feature]
	var presentation:=str(cell.get("presentation_material_id",""))
	if TERRAIN_TEXTURES.has(presentation):return presentation
	match terrain:
		"floor","stone_floor":
			var floors:=["stone_floor","cracked_stone","mossy_stone"]
			return floors[_variant_index(position,floor_index,floors.size())]
		"wood_floor":return "dirt"
		"metal","rubber_floor":return "iron_plate"
		"rubble","shallow_water","deep_water","lava","spikes","dirt","grass", \
		"pillar","low_cover","crate":return terrain
	return "stone_floor"

static func _known_floor(neighbors:Dictionary,side:String)->bool:
	var row:Dictionary=neighbors.get(side,{})
	return str(row.get("visibility_state","UNSEEN")) in ["VISIBLE","MEMORY"] \
		and str(row.get("terrain_id","wall"))!="wall"

static func _hidden(floor_index:int,visibility:String)->Dictionary:
	return {"visible":false,"texture":null,"region":Rect2(),"floor_index":floor_index,
		"tile_index":-1,"visibility_state":visibility,"changes_mapping":false,
		"changes_fov":false,"draw_image":false}

static func _variant_index(position:Vector2i,floor_index:int,count:int)->int:
	if count<=1:return 0
	return posmod(position.x*73856093 ^ position.y*19349663 \
		^ floor_index*83492791,count)
