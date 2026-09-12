extends RefCounted

const Kernel=preload("res://sim/combat_kernel.gd")
var expanded:=0
var fields:Dictionary={}

func next_step(world,start:int,goal:int)->int:
	if not fields.has(goal):
		# A target-centred distance field shared by every pursuing actor. Dynamic
		# occupancy is resolved only for the immediate step, avoiding crowd dead ends.
		var distance:=PackedInt32Array();distance.resize(world.terrain.size());distance.fill(-1)
		var queue:=PackedInt32Array([goal]);distance[goal]=0
		var head:=0
		while head<queue.size():
			var cell:=queue[head];head+=1
			if distance[cell]>=14:continue
			for direction in Kernel.DIRECTIONS:
				var p:Vector2i=world.position(cell)+direction
				if not world.in_bounds(p):continue
				var next:int=world.index(p)
				if distance[next]>=0 or world.blocked(next) or not world.open_edge(cell,next):continue
				distance[next]=distance[cell]+1;queue.append(next)
		if fields.size()>=8:fields.erase(fields.keys()[0])
		fields[goal]=distance
	var field:PackedInt32Array=fields[goal]
	if field[start]<0:return -1
	var best:=-1
	var best_distance:=field[start]
	for direction in Kernel.DIRECTIONS:
		var p:Vector2i=world.position(start)+direction
		if not world.in_bounds(p):continue
		var next:int=world.index(p)
		if field[next]<0 or field[next]>=best_distance or world.occupancy[next]>=0 or not world.open_edge(start,next):continue
		best=next;best_distance=field[next]
	return best

func route(world,start:int,goal:int,known_only:bool=true)->PackedInt32Array:
	expanded=0
	if goal<0 or goal>=world.terrain.size() or world.blocked(goal):return PackedInt32Array()
	if known_only and world.memory[goal]==0:return PackedInt32Array()
	var result:Dictionary=preload("res://sim/turn_engine.gd").path(world.WIDTH,world.HEIGHT,
		world.position(start),[world.position(goal)],
		func(from:Vector2i,to:Vector2i)->bool:
			var cell:int=world.index(to)
			return not world.blocked(cell) and world.open_edge(world.index(from),cell) \
				and (not known_only or world.memory[cell]!=0) and (world.occupancy[cell]<0 or cell==goal),
		func(point:Vector2i)->int:return world.move_cost(world.index(point)))
	expanded=int(result.expanded)
	var path:=PackedInt32Array()
	if result.found:
		for point in result.path.slice(1):path.append(world.index(point))
	return path
