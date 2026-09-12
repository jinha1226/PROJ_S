extends RefCounted

# Scene-free combat/movement base. Hosts own actors, equipment, injuries and
# event persistence. Both the campaign and rebuilt harness use this engine.
const Heap=preload("res://game/rebuilt/min_heap.gd")
const Geometry=preload("res://sim/combat_kernel.gd")
const ENGINE_ID:="turn-engine-v2"

static func physical(raw:int,accuracy:int,evasion:int,armor:int,penetration:int=0,
		minimum_hit:int=50,maximum_hit:int=950)->Dictionary:
	var protection:=maxi(0,armor-penetration)
	var absorbed:=mini(protection,maxi(0,raw-1))
	return {"hit_chance":clampi(accuracy-evasion,minimum_hit,maximum_hit),
		"armor_reduction":absorbed,"damage":maxi(1,raw-absorbed)}

static func damage_outcome(hit_roll:int,hit_chance:int,block_roll:int=-1,block_chance:int=0)->String:
	if hit_roll>=hit_chance:return "MISS"
	if block_roll>=0 and block_roll<block_chance:return "PARRIED"
	return "HIT"

# Integer-indexed A*, including deterministic straight-line ties. The host's
# can_step callback supplies terrain/occupancy/body-specific traversal rules.
static func path(width:int,height:int,start:Vector2i,goals:Array,can_step:Callable,
		step_cost:Callable,minimum_cost:int=100,maximum_steps:int=-1)->Dictionary:
	var count:=width*height
	var costs:=PackedInt64Array();costs.resize(count);costs.fill(9223372036854775807)
	var steps:=PackedInt32Array();steps.resize(count);steps.fill(2147483647)
	var drifts:=PackedInt64Array();drifts.resize(count);drifts.fill(9223372036854775807)
	var parents:=PackedInt32Array();parents.resize(count);parents.fill(-1)
	var targets:Dictionary={}
	for goal in goals:targets[goal.y*width+goal.x]=true
	var first:=start.y*width+start.x
	var open=Heap.new();open.sort_keys=6
	costs[first]=0;steps[first]=0;drifts[first]=0
	open.push([estimate(start,goals)*minimum_cost,0,0,0,first,0])
	var sequence:=1
	var expanded:=0
	while not open.empty():
		var node:Array=open.pop();var cell:int=node[4]
		if node[1]!=costs[cell] or node[2]!=steps[cell] or node[3]!=drifts[cell]:continue
		expanded+=1
		var origin:=Vector2i(cell%width,cell/width)
		if targets.has(cell):
			var route:Array[Vector2i]=[];var cursor:=cell
			while cursor>=0:
				route.append(Vector2i(cursor%width,cursor/width));cursor=parents[cursor]
			route.reverse()
			return {"found":true,"reason":"ok","path":route,"total_cost":costs[cell],
				"steps":steps[cell],"goal":origin,"expanded":expanded,"engine":ENGINE_ID}
		for direction in Geometry.DIRECTIONS:
			if maximum_steps>=0 and steps[cell]>=maximum_steps:break
			var point:Vector2i=origin+direction
			if point.x<0 or point.y<0 or point.x>=width or point.y>=height or not can_step.call(origin,point):continue
			var next:=point.y*width+point.x
			var cost:int=costs[cell]+int(step_cost.call(point))
			var step:int=steps[cell]+1
			var drift:int=drifts[cell]
			if goals.size()==1:
				var line:Vector2i=goals[0]-start;var offset:=point-start
				drift+=absi(line.x*offset.y-line.y*offset.x)
			if cost>costs[next] or cost==costs[next] and (step>steps[next] or step==steps[next] and drift>=drifts[next]):continue
			costs[next]=cost;steps[next]=step;drifts[next]=drift;parents[next]=cell
			open.push([cost+estimate(point,goals)*minimum_cost,cost,step,drift,next,sequence]);sequence+=1
	return {"found":false,"reason":"path_unreachable","path":[],"total_cost":-1,"steps":0,"expanded":expanded,"engine":ENGINE_ID}

static func estimate(point:Vector2i,goals:Array)->int:
	var distance:=2147483647
	for goal in goals:distance=mini(distance,maxi(absi(goal.x-point.x),absi(goal.y-point.y)))
	return distance

# Hazard-aware search keeps a separate state per cell AND step count so a
# safer detour cannot eliminate a shorter route needed by the step budget.
static func risk_path(width:int,height:int,start:Vector2i,goals:Array,
		can_step:Callable,step_cost:Callable,risk:Callable,limit:int)->Dictionary:
	var stride:=limit+1
	var first:=start.y*width+start.x
	var targets:Dictionary={}
	for goal in goals:targets[goal.y*width+goal.x]=true
	var open=Heap.new();open.sort_keys=7
	var initial:Array=[0,0,0,0,0,first,0,first*stride]
	open.push(initial)
	var best:Dictionary={first*stride:initial.slice(0,5)}
	var parents:Dictionary={first*stride:-1}
	var sequence:=1;var expanded:=0
	while not open.empty():
		var node:Array=open.pop();var cell:int=node[5];var state:int=node[7]
		if best.get(state,[])!=node.slice(0,5):continue
		expanded+=1
		var origin:=Vector2i(cell%width,cell/width)
		if targets.has(cell):
			var route:Array[Vector2i]=[];var cursor:=state
			while cursor>=0:
				var route_cell:int=cursor/stride
				route.append(Vector2i(route_cell%width,route_cell/width));cursor=parents[cursor]
			route.reverse()
			return {"found":true,"reason":"ok","path":route,"total_cost":node[3],"steps":node[2],
				"max_total_risk":node[0],"total_risk":node[1],"expanded":expanded,"engine":ENGINE_ID}
		if int(node[2])>=limit:continue
		for direction in Geometry.DIRECTIONS:
			var point:Vector2i=origin+direction
			if point.x<0 or point.y<0 or point.x>=width or point.y>=height or not can_step.call(origin,point):continue
			var next:=point.y*width+point.x
			var step:int=node[2]+1;var next_state:=next*stride+step
			var exposure:int=risk.call(point);var drift:int=node[4]
			if goals.size()==1:
				var line:Vector2i=goals[0]-start;var offset:=point-start
				drift+=absi(line.x*offset.y-line.y*offset.x)
			var candidate:Array=[maxi(int(node[0]),exposure),int(node[1])+exposure,step,
				int(node[3])+int(step_cost.call(point)),drift,next,sequence,next_state]
			sequence+=1
			if best.has(next_state):
				var old:Array=best[next_state]
				var improves:=false
				for i in range(5):
					if candidate[i]!=old[i]:improves=candidate[i]<old[i];break
				if not improves:continue
			best[next_state]=candidate.slice(0,5);parents[next_state]=state;open.push(candidate)
	return {"found":false,"reason":"path_unreachable","path":[],"total_cost":-1,"steps":0,"engine":ENGINE_ID}
