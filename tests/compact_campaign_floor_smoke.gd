extends SceneTree
const Floors=preload("res://playtest/campaign_floor_map.gd")
const WorldMap=preload("res://playtest/campaign_world_map.gd")
var errors:Array[String]=[]
func check(ok:bool,message:String)->void:
	if not ok:errors.append(message)
func _init()->void:
	for seed in [1,44,256]:
		for floor_id in [1,2]:
			var map:Dictionary=Floors.generate(floor_id,seed)
			check(not map.is_empty(),"generation");if map.is_empty():continue
			check(map.width==80 if floor_id==1 else map.width==96,"compact width")
			var occupied:Dictionary={}
			for row in map.runtime_enemy_roster:
				check(not occupied.has(row.position),"no overlapping spawn")
				occupied[row.position]=true
				check(map.terrain[row.position.y*map.width+row.position.x]!="wall","passable spawn")
			check(map.runtime_enemy_roster.size()==map.planned_enemy_count,"preserved roster")
			var queue:Array=[map.entry_position];var visited:Dictionary={map.entry_position:0};var cursor:=0
			while cursor<queue.size():
				var p:Vector2i=queue[cursor];cursor+=1
				for d in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
					var n:Vector2i=p+d
					if n.x<0 or n.y<0 or n.x>=map.width or n.y>=map.height or visited.has(n):continue
					if map.terrain[n.y*map.width+n.x]=="wall":continue
					visited[n]=int(visited[p])+1;queue.append(n)
			check(visited.has(map.anchor_portal_position) and visited.has(map.transition_portal_position),"reachable portals")
			for row in map.runtime_enemy_roster:check(visited.has(row.position),"reachable enemies")
			for p in map.supply_positions:check(visited.has(p),"reachable supplies")
			if seed==44:print("F",floor_id," size ",map.width,"x",map.height," reachable ",visited.size()," portal distances ",visited.get(map.anchor_portal_position),"/",visited.get(map.transition_portal_position))
		check(not WorldMap.generate(seed).is_empty(),"aggregate topology")
	for error in errors:printerr(error)
	print("Compact floors: %d failures"%errors.size());quit(0 if errors.is_empty() else 1)
