extends RefCounted

const Catalog=preload("res://sim/item_catalog_registry.gd")
const WorldItems=preload("res://sim/world_item_operations.gd")

static func candidates(depth:int)->Array[String]:
	var result:Array[String]=[]
	for id in Catalog.ids_for_family("WEAPON"):
		if str(id).begins_with("WEAPON_DCSS_") and depth>=int(Catalog.definition(id).min_depth):result.append(str(id))
	return result

static func initialise(world,layout:Dictionary,seed:int)->String:
	var floors:Dictionary=layout.get("campaign_floors",{})
	if floors.is_empty():floors={int(layout.get("floor_index",1)):layout}
	var indices:Array=floors.keys();indices.sort()
	for index in indices:
		var floor:Dictionary=floors[index];var pool:=candidates(int(index))
		if pool.is_empty():continue
		var centers:Array=floor.get("room_centers",[])
		var used:Dictionary={}
		for slot in range(mini(4,centers.size())):
			var position:Vector2i=centers[posmod(seed+slot,centers.size())]
			if used.has(position) or not world.in_bounds(position) or world.tile_at(position).terrain=="wall":continue
			used[position]=true
			var digest:PackedByteArray=("dcss-find-v1/%d/%d/%d"%[seed,int(index),slot]).sha256_buffer()
			var item:String=pool[(int(digest[0])*256+int(digest[1]))%pool.size()]
			var result:=WorldItems.commit_spawn_ground(world,item,1,position,-1,-1,"DCSS_FLOOR_FIND")
			if not result.get("accepted",false):return str(result.get("reason","dcss_find_failed"))
	return ""
