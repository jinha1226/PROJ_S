class_name TopdownTileAssets
extends RefCounted

## Presentation-only tile atlas registry for the flat product camera. Simulation
## terrain, FOV, pathing and pointer mapping stay integer-grid authoritative.

const TILE_SIZE := 128
const FLOOR_TEXTURES := {
	1: preload("res://assets/topdown_fixed_front/terrain/floor1_atlas_16x1_128.png"),
	2: preload("res://assets/topdown_fixed_front/terrain/floor2_atlas_16x1_128.png"),
}

const FLOOR_ONE_TERRAIN := {
	# Indices 4-7 are authored road fragments. Without an autotile connector they
	# form random straight/L-shaped roads, so ordinary walkable ground uses only
	# seamless organic fills.
	"floor":[0,2,3],
	"stone_floor":[0,2,3],
	"wood_floor":[0,3],
	"metal":[2],
	"rubble":[12],
	"shallow_water":[8,9],
	"wall":[10,11],
}

const FLOOR_TWO_TERRAIN := {
	"floor":[0,1],
	"stone_floor":[2,3],
	# The industrial corridor fragments at 4-7 and the isolated rail at 13 need
	# connectivity metadata. Keep passable ground on continuous ash/plate fills.
	"wood_floor":[0,1],
	"metal":[2,3],
	"rubble":[10,11],
	"shallow_water":[8,9],
	"wall":[10,12],
}

const INACTIVE_PORTALS := [
	"anchor_portal_inactive", "run_exit_locked",
	"floor_transition_portal_locked",
]
const ACTIVE_PORTALS := [
	"anchor_portal_active", "run_exit_open", "floor_transition_portal",
]


static func tile_spec(cell:Dictionary,position:Vector2i,floor_index:int)->Dictionary:
	var visibility:=str(cell.get("visibility_state","UNSEEN")).to_upper()
	var hidden:={"visible":false,"texture":null,"region":Rect2(),
		"floor_index":floor_index,"tile_index":-1,"visibility_state":visibility,
		"changes_mapping":false,"changes_fov":false,"draw_image":false}
	if visibility=="UNSEEN":return hidden.duplicate(true)
	var resolved_floor:=2 if floor_index==2 else 1
	var texture:Texture2D=FLOOR_TEXTURES.get(resolved_floor,null)
	if texture==null:return hidden.duplicate(true)
	var feature_id:=str(cell.get("feature_id",""))
	var tile_index:=-1
	if feature_id in INACTIVE_PORTALS:tile_index=14
	elif feature_id in ACTIVE_PORTALS:tile_index=15
	else:
		var terrain_id:=str(cell.get("terrain_id","floor"))
		var table:Dictionary=FLOOR_TWO_TERRAIN if resolved_floor==2 \
			else FLOOR_ONE_TERRAIN
		var choices:Variant=table.get(terrain_id,table.get("floor",[0]))
		if not choices is Array or choices.is_empty():return hidden.duplicate(true)
		tile_index=int(choices[_variant_index(position,resolved_floor,choices.size())])
	return {"visible":true,"texture":texture,
		"region":Rect2(float(tile_index*TILE_SIZE),0.0,TILE_SIZE,TILE_SIZE),
		"floor_index":resolved_floor,"tile_index":tile_index,
		"visibility_state":visibility,"changes_mapping":false,
		"changes_fov":false,"draw_image":true}.duplicate(true)


static func _variant_index(position:Vector2i,floor_index:int,count:int)->int:
	if count<=1:return 0
	var mixed:=position.x*73856093 ^ position.y*19349663 ^ floor_index*83492791
	return posmod(mixed,count)
