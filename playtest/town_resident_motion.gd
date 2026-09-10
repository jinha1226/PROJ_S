extends RefCounted

# Ambient presentation only: no world RNG, journal writes or expedition time.
const DIRECTIONS:=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
const STEP_SECONDS:=0.7
var walkable:Dictionary={}
var actors:Dictionary={}
var worker_id:=-1
var worker_tile:=Vector2i(-1,-1)

func configure(overview:Dictionary)->void:
	var settlement:Dictionary=overview.get("settlement",{})
	var next_walk:Dictionary={}
	for tile in settlement.get("tiles",[]):
		var p:=Vector2i(int(tile.position[0]),int(tile.position[1]))
		if str(tile.get("terrain_id","")) not in ["TREE","WOODS","FOREST"]:next_walk[p]=true
	for building in settlement.get("buildings",[]):
		var p:=Vector2i(int(building.tile_origin[0]),int(building.tile_origin[1]))
		for y in range(int(building.footprint[1])):
			for x in range(int(building.footprint[0])):next_walk.erase(p+Vector2i(x,y))
	if next_walk!=walkable:actors.clear()
	walkable=next_walk
	var work:Dictionary=overview.get("work",{})
	worker_id=int(work.get("worker_id",-1))
	worker_tile=preload("res://sim/base_work_rules.gd").worker_position(work) if not work.is_empty() else Vector2i(-1,-1)
	var ids:Array=[];var player_ids:Array=[]
	for row in overview.get("residents",[]):
		ids.append(int(row.entity_id))
		if bool(row.get("is_player",false)):player_ids.append(int(row.entity_id))
	ids.sort()
	for id in actors.keys():
		if id not in ids or id==worker_id:actors.erase(id)
	var cells:Array=walkable.keys()
	if cells.is_empty():return
	for id in ids:
		if actors.has(id) or id==worker_id:continue
		for offset in range(cells.size()):
			var p:Vector2i=cells[posmod(id*37+offset,cells.size())]
			if _occupied(p,id):continue
			actors[id]={"from":p,"to":p,"progress":1.0,"pause":float(id%7)*0.25,
				"route":[],"serial":0,"facing":Vector2i.DOWN,"pinned":id in player_ids}
			break

func _occupied(p:Vector2i,except_id:int)->bool:
	if p==worker_tile:return true
	for id in actors:
		if id!=except_id and (actors[id].from==p or actors[id].to==p):return true
	return false

func tick(delta:float)->bool:
	var changed:=false
	for id in actors:
		var row:Dictionary=actors[id]
		if bool(row.pinned):continue
		if float(row.progress)<1.0:
			row.progress=minf(1.0,float(row.progress)+delta/STEP_SECONDS);changed=true
			if row.progress>=1.0:row.from=row.to
			continue
		row.pause=maxf(0,float(row.pause)-delta)
		if row.pause>0:continue
		if row.route.is_empty():
			var cells:Array=walkable.keys()
			row.serial+=1
			var goal:Vector2i=cells[posmod(hash("%d:%d"%[id,row.serial]),cells.size())]
			row.route=_route(row.to,goal,id)
			if row.route.is_empty():row.pause=1.0;continue
		var next:Vector2i=row.route[0]
		if _occupied(next,id):row.route=[];row.pause=0.5;continue
		row.route.pop_front();row.from=row.to;row.to=next;row.progress=0.0
		row.facing=next-row.from;changed=true
		if row.route.is_empty():row.pause=1.0+float(posmod(id+int(row.serial),5))*0.4
	return changed

func _route(start:Vector2i,goal:Vector2i,id:int)->Array:
	var queue:Array=[start];var parents:Dictionary={start:start};var cursor:=0
	while cursor<queue.size():
		var p:Vector2i=queue[cursor];cursor+=1
		if p==goal:break
		for direction in DIRECTIONS:
			var next:Vector2i=p+direction
			if not walkable.has(next) or parents.has(next) or _occupied(next,id):continue
			parents[next]=p;queue.append(next)
	if not parents.has(goal):return []
	var path:Array=[];var p:=goal
	while p!=start:path.push_front(p);p=parents[p]
	return path

func position(id:int,fallback:Vector2)->Vector2:
	if not actors.has(id):return fallback
	var row:Dictionary=actors[id]
	return Vector2(row.from).lerp(Vector2(row.to),float(row.progress))

func facing(id:int)->Vector2i:
	return actors[id].facing if actors.has(id) else Vector2i.DOWN
