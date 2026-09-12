class_name TopdownTileAssets
extends RefCounted

## Presentation-only tile atlas registry for the flat product camera. Simulation
## terrain, FOV, pathing and pointer mapping stay integer-grid authoritative.

const TILE_SIZE := 16
const FLOOR_TEXTURES := {
	1: preload("res://assets/kenney/tiny-dungeon/tilemap_packed.png"),
	2: preload("res://assets/kenney/tiny-dungeon/tilemap_packed.png"),
}

const FLOOR_ONE_TERRAIN := {
	# Native Kenney sand/slate variants, 12 columns in the packed atlas.
	"floor":[48,49,50],
	"stone_floor":[48,50],
	"wood_floor":[51],
	"metal":[41],
	"rubble":[42],
	"shallow_water":[48],
	"wall":[40],
}

const FLOOR_TWO_TERRAIN := {
	"floor":[48,49,50],
	"stone_floor":[48,50],
	"wood_floor":[51],
	"metal":[41],
	"rubble":[42],
	"shallow_water":[48],
	"wall":[58],
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
	if feature_id in INACTIVE_PORTALS:tile_index=48
	elif feature_id in ACTIVE_PORTALS:tile_index=48
	else:
		var terrain_id:=str(cell.get("terrain_id","floor"))
		var table:Dictionary=FLOOR_TWO_TERRAIN if resolved_floor==2 \
			else FLOOR_ONE_TERRAIN
		var choices:Variant=table.get(terrain_id,table.get("floor",[0]))
		if not choices is Array or choices.is_empty():return hidden.duplicate(true)
		tile_index=int(choices[_variant_index(position,resolved_floor,choices.size())])
	return {"visible":true,"texture":texture,
		"is_wall":str(cell.get("terrain_id",""))=="wall",
		"asset_family":"KENNEY_TINY_DUNGEON",
		"tint":Color(0.32,0.65,0.86) if str(cell.get("terrain_id",""))=="shallow_water" else Color.WHITE,
		"region":Rect2(float((tile_index%12)*TILE_SIZE),float((tile_index/12)*TILE_SIZE),TILE_SIZE,TILE_SIZE),
		"floor_index":resolved_floor,"tile_index":tile_index,
		"visibility_state":visibility,"changes_mapping":false,
		"changes_fov":false,"draw_image":true}.duplicate(true)


static func _variant_index(position:Vector2i,floor_index:int,count:int)->int:
	if count<=1:return 0
	var mixed:=position.x*73856093 ^ position.y*19349663 ^ floor_index*83492791
	return posmod(mixed,count)
