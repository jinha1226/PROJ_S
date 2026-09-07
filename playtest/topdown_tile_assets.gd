class_name TopdownTileAssets
extends RefCounted

## Presentation-only tile atlas registry for the flat product camera. Simulation
## terrain, FOV, pathing and pointer mapping stay integer-grid authoritative.

const TILE_SIZE := 256
const FLOOR_TEXTURES := {
	1: preload("res://assets/illustrated_front/terrain.png"),
	2: preload("res://assets/illustrated_front/terrain.png"),
}

const FLOOR_ONE_TERRAIN := {
	# Illustrated atlas: organic moss ground and quiet slate variants.
	"floor":[4,5],
	"stone_floor":[0,1,3],
	"wood_floor":[6],
	"metal":[13],
	"rubble":[12],
	"shallow_water":[8,9],
	"wall":[10,11],
}

const FLOOR_TWO_TERRAIN := {
	"floor":[6,7],
	"stone_floor":[0,3],
	# The second floor uses ash and metal variants from the same illustrated atlas.
	"wood_floor":[6],
	"metal":[13],
	"rubble":[12],
	"shallow_water":[8,9],
	"wall":[10,11],
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
		"is_wall":str(cell.get("terrain_id",""))=="wall",
		"region":Rect2(float((tile_index%4)*TILE_SIZE),float((tile_index/4)*TILE_SIZE),TILE_SIZE,TILE_SIZE),
		"floor_index":resolved_floor,"tile_index":tile_index,
		"visibility_state":visibility,"changes_mapping":false,
		"changes_fov":false,"draw_image":true}.duplicate(true)


static func _variant_index(position:Vector2i,floor_index:int,count:int)->int:
	if count<=1:return 0
	var mixed:=position.x*73856093 ^ position.y*19349663 ^ floor_index*83492791
	return posmod(mixed,count)
