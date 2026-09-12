extends RefCounted
## A distance field over the player's KNOWLEDGE, never the authoritative map.
## Packed cell flags eliminate string keys/dictionaries from neighbor expansion.
const Heap=preload("res://game/rebuilt/min_heap.gd")
const Directions=preload("res://sim/systems/movement_system.gd").MOVE_DIRECTIONS_8
const KNOWN:=1
const PASSABLE:=2
const OCCUPIED:=4
const GATEWAY:=8
const SAFE:=16
const VISITED:=32
const EXHAUSTED:=64
var width:=0
var height:=0
var flags:=PackedByteArray()
var move_costs:=PackedInt32Array()
var expanded:=0

func search(snapshot:Dictionary,cells:Dictionary,start:Vector2i,exhausted:Dictionary)->Dictionary:
	width=int(snapshot.get("width",0));height=int(snapshot.get("height",0));expanded=0
	if width<=0 or height<=0 or not _in_bounds(start):return {"found":false,"reason":"auto_explore_no_frontier"}
	var count:=width*height
	flags.resize(count);flags.fill(0);move_costs.resize(count);move_costs.fill(0)
	var visited:Dictionary=snapshot.get("visited",{})
	for key in cells:
		var parts:=str(key).split(":")
		if parts.size()!=2:continue
		var p:=Vector2i(int(parts[0]),int(parts[1]))
		if not _in_bounds(p):continue
		var index:=p.y*width+p.x
		var cell:Dictionary=cells[key]
		var bits:=KNOWN
		if bool(cell.get("passable",false)):bits|=PASSABLE
		if bool(cell.get("occupied",false)):bits|=OCCUPIED
		if bool(cell.get("diagonal_gateway",false)):bits|=GATEWAY
		if bits&PASSABLE and not bits&OCCUPIED and not bool(cell.get("objective_blocked",false)) \
				and int(cell.get("risk",0))<=0:bits|=SAFE
		if visited.has(key):bits|=VISITED
		if exhausted.has(key):bits|=EXHAUSTED
		flags[index]=bits;move_costs[index]=int(cell.get("move_time_cost",0))
	var first:=start.y*width+start.x
	if not flags[first]&KNOWN:return {"found":false,"reason":"auto_explore_no_frontier"}
	var exit_wire:Array=snapshot.get("exit_position",[-1,-1])
	var exit:=Vector2i(int(exit_wire[0]),int(exit_wire[1])) if exit_wire.size()==2 else Vector2i(-1,-1)
	var seek_exit:=exit.x>=0 and exit.y>=0
	# An unpublished/unknown or unsafe exit cannot be reached through this
	# knowledge graph. It must not disable nearest-frontier early termination.
	var exit_open:=seek_exit and bool(snapshot.get("exit_open",false)) and _in_bounds(exit) \
		and bool(flags[exit.y*width+exit.x]&SAFE) and exit!=start
	var steps:=PackedInt32Array();steps.resize(count);steps.fill(2147483647)
	var costs:=PackedInt64Array();costs.resize(count);costs.fill(9223372036854775807)
	var parents:=PackedInt32Array();parents.resize(count);parents.fill(-1)
	var open=Heap.new();open.sort_keys=4;open.push([0,0,first,0])
	steps[first]=0;costs[first]=0
	var frontier:Array=[];var fallback:Array=[];var sequence:=1
	while not open.empty():
		var node:Array=open.pop();var index:int=node[2]
		if node[0]!=steps[index] or node[1]!=costs[index]:continue
		if not exit_open and not frontier.is_empty() and int(node[0])>int(frontier[0]):break
		expanded+=1
		var p:=Vector2i(index%width,index/width)
		if exit_open and p==exit:return _result(index,"EXIT",0,steps,costs,parents,cells)
		var distance:=maxi(absi(p.x-exit.x),absi(p.y-exit.y)) if seek_exit else 0
		var candidate:Array=[int(node[0])+distance,node[0],node[1],index,distance if seek_exit else -1]
		if index!=first and not flags[index]&(VISITED|EXHAUSTED) and _is_frontier(p):
			if frontier.is_empty() or _less(candidate,frontier):frontier=candidate
		elif snapshot.has("visited") and index!=first and not flags[index]&VISITED:
			if fallback.is_empty() or _less(candidate,fallback):fallback=candidate
		for direction in Directions:
			var next:Vector2i=p+direction
			if not can_step(p,next):continue
			var next_index:=next.y*width+next.x
			var next_steps:int=node[0]+1;var next_cost:int=node[1]+move_costs[next_index]
			if next_steps>steps[next_index] or next_steps==steps[next_index] and next_cost>=costs[next_index]:continue
			steps[next_index]=next_steps;costs[next_index]=next_cost;parents[next_index]=index
			open.push([next_steps,next_cost,next_index,sequence]);sequence+=1
	var chosen:Array=frontier if not frontier.is_empty() else fallback
	if chosen.is_empty():return {"found":false,"reason":"auto_explore_no_frontier"}
	return _result(int(chosen[3]),"FRONTIER" if not frontier.is_empty() else "UNVISITED",
		int(chosen[4]),steps,costs,parents,cells)

func can_step(from:Vector2i,to:Vector2i)->bool:
	if not _in_bounds(to) or not flags[to.y*width+to.x]&SAFE:return false
	var delta:=to-from
	if delta.x==0 or delta.y==0:return true
	var flank_count:=0;var gateway:=false
	for flank in [from+Vector2i(delta.x,0),from+Vector2i(0,delta.y)]:
		if not _in_bounds(flank):continue
		var bits:=int(flags[flank.y*width+flank.x])
		if not bits&PASSABLE:continue
		if bits&OCCUPIED:return false
		flank_count+=1;gateway=gateway or bool(bits&GATEWAY)
	return flank_count==2 or flank_count==1 and (gateway \
		or bool(flags[from.y*width+from.x]&GATEWAY) or bool(flags[to.y*width+to.x]&GATEWAY))

func _is_frontier(p:Vector2i)->bool:
	for delta in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
		var next:Vector2i=p+delta
		if _in_bounds(next) and not flags[next.y*width+next.x]&KNOWN:return true
	return false

func _in_bounds(p:Vector2i)->bool:
	return p.x>=0 and p.y>=0 and p.x<width and p.y<height

func _less(a:Array,b:Array)->bool:
	for i in range(4):
		if a[i]!=b[i]:return a[i]<b[i]
	return false

func _result(index:int,kind:String,distance:int,steps:PackedInt32Array,costs:PackedInt64Array,
		parents:PackedInt32Array,cells:Dictionary)->Dictionary:
	var route:Array=[];var cursor:=index
	while cursor>=0:
		route.append(Vector2i(cursor%width,cursor/width));cursor=parents[cursor]
	route.reverse()
	var target:=Vector2i(index%width,index/width)
	return {"found":true,"target":target,"target_kind":kind,"path":route,
		"steps":steps[index],"cost":costs[index],"exit_distance":distance,
		"visibility_state":str(cells["%d:%d"%[target.x,target.y]].get("visibility_state","MEMORY"))}
