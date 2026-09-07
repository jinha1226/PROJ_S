class_name BaseResourceCacheRules
extends RefCounted

const RULESET_ID := "position-bound-supply-cache-v1"
const CACHE_ROWS := [
	{"resource_id":"TIMBER","amount":3},{"resource_id":"STONE","amount":3},
	{"resource_id":"HERBS","amount":2},{"resource_id":"TIMBER","amount":3},
	{"resource_id":"STONE","amount":3},{"resource_id":"HERBS","amount":2},
	{"resource_id":"TIMBER","amount":3},{"resource_id":"STONE","amount":3},
	{"resource_id":"HERBS","amount":2},
]


static func caches(world,layout:Dictionary,world_seed:int,
		expedition_index:int)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if world==null or layout.is_empty() or expedition_index<1:return result
	var blocked:Dictionary={}
	for key in ["entry_position","exit_position","transition_portal_position",
			"anchor_portal_position"]:
		var value:Variant=layout.get(key)
		if value is Vector2i:blocked[value]=true
	for value in layout.get("door_positions",[]):
		if value is Vector2i:blocked[value]=true
	# Authored supply points are immutable floor-local topology. Nearby offsets
	# provide multiple distinct caches without scanning/sorting the aggregate map.
	var origins:Array=layout.get("supply_positions",[]).duplicate()
	for center in layout.get("room_centers",[]):
		if center not in origins:origins.append(center)
	var floor_bounds:=_floor_bounds(layout,world)
	var offsets:Array[Vector2i]=[Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,
		Vector2i.LEFT,Vector2i.UP,Vector2i(1,1),Vector2i(-1,1),
		Vector2i(1,-1),Vector2i(-1,-1)]
	var candidates:Array[Vector2i]=[]
	for origin_value in origins:
		if not origin_value is Vector2i:continue
		var origin:Vector2i=origin_value
		for offset in offsets:
			var position:=origin+offset
			if not floor_bounds.has_point(position) or blocked.has(position) \
					or position in candidates or str(world.tile_at(position).terrain)=="wall":
				continue
			var separated:=true
			for existing in candidates:
				if maxi(absi(existing.x-position.x),absi(existing.y-position.y))<=2:
					separated=false;break
			if not separated:continue
			candidates.append(position)
			break
	for slot in range(CACHE_ROWS.size()):
		if candidates.is_empty():break
		var selected_index:=posmod(world_seed+expedition_index*7+slot*11,
			candidates.size())
		var position:Vector2i=candidates.pop_at(selected_index)
		var row:Dictionary=CACHE_ROWS[slot]
		result.append({"cache_id":"EXP%d_F%d_%s_%d"%[expedition_index,
			int(layout.get("floor_index",1)),row.resource_id,slot+1],
			"resource_id":str(row.resource_id),"amount":int(row.amount),
			"position":[position.x,position.y]})
	return result


static func _floor_bounds(layout:Dictionary,world)->Rect2i:
	var raw:Variant=layout.get("floor_bounds",[])
	if raw is Array and raw.size()==4:
		return Rect2i(int(raw[0]),int(raw[1]),int(raw[2]),int(raw[3]))
	return Rect2i(0,0,world.width,world.height)
