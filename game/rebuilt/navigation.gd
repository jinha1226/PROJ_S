extends RefCounted

const Heap=preload("res://game/rebuilt/min_heap.gd")
const Kernel=preload("res://sim/combat_kernel.gd")
var costs:=PackedInt32Array()
var parents:=PackedInt32Array()
var heap=Heap.new()
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
	var count:int=world.terrain.size()
	costs.resize(count);costs.fill(2147483647)
	parents.resize(count);parents.fill(-1);heap.clear()
	costs[start]=0;heap.push([0,start,start,0])
	while not heap.empty():
		var row:Array=heap.pop()
		var cell:int=row[2]
		if int(row[3])!=costs[cell]:continue
		expanded+=1
		if cell==goal:
			var path:=PackedInt32Array()
			while cell!=start:path.append(cell);cell=parents[cell]
			path.reverse();return path
		var origin:Vector2i=world.position(cell)
		for direction in Kernel.DIRECTIONS:
			var point:Vector2i=origin+direction
			if not world.in_bounds(point):continue
			var next:int=world.index(point)
			if world.blocked(next) or not world.open_edge(cell,next):continue
			if known_only and world.memory[next]==0:continue
			if world.occupancy[next]>=0 and next!=goal:continue
			var score:int=costs[cell]+world.move_cost(next)
			if score>=costs[next]:continue
			costs[next]=score;parents[next]=cell
			var delta:Vector2i=world.position(goal)-point
			var estimate:int=score+maxi(absi(delta.x),absi(delta.y))*100
			heap.push([estimate,next,next,score])
	return PackedInt32Array()
