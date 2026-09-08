extends RefCounted

const Settlement=preload("res://sim/base_settlement_rules.gd")

static func current(events:Array)->Dictionary:
	var job:Dictionary={}
	for event in events:
		match event.type:
			"base.work_ordered":
				job=event.data.duplicate(true);job["order_id"]=int(event.id);job["progress"]=0
			"base.work_progressed":
				if not job.is_empty() and int(event.cause_id)==int(job.order_id):
					job["progress"]=int(event.magnitude)
			"base.work_completed","base.work_cancelled":job={}
	return job

static func worker_position(job:Dictionary)->Vector2i:
	if job.is_empty():return Vector2i(7,7)
	var route:Array=job.get("route",[[7,7]])
	var point:Array=route[mini(int(job.get("progress",0)),route.size()-1)]
	return Vector2i(int(point[0]),int(point[1]))

static func route_to_site(buildings:Array,origin:Vector2i,footprint:Vector2i)->Array:
	var blocked:Dictionary={}
	for p in Settlement.BLOCKED_TILES:blocked[p]=true
	for row in buildings:
		var r:=Rect2i(int(row.tile_origin[0]),int(row.tile_origin[1]),int(row.footprint[0]),int(row.footprint[1]))
		for y in range(r.position.y,r.end.y):
			for x in range(r.position.x,r.end.x):blocked[Vector2i(x,y)]=true
	var site:=Rect2i(origin,footprint)
	for y in range(site.position.y,site.end.y):
		for x in range(site.position.x,site.end.x):blocked[Vector2i(x,y)]=true
	var start:=Vector2i(7,7);var queue:Array[Vector2i]=[start]
	var previous:Dictionary={start:start};var goal:=Vector2i(-1,-1)
	while not queue.is_empty():
		var p:Vector2i=queue.pop_front()
		if site.grow(1).has_point(p):goal=p;break
		for d in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
			var n:Vector2i=p+d
			if not Rect2i(0,0,Settlement.WIDTH,Settlement.HEIGHT).has_point(n) \
					or blocked.has(n) or previous.has(n):continue
			previous[n]=p;queue.append(n)
	if goal.x<0:return []
	var route:Array=[]
	while goal!=start:
		route.push_front([goal.x,goal.y]);goal=previous[goal]
	route.push_front([start.x,start.y]);return route

static func operation_error(op:Variant)->String:
	if not op is Dictionary:return "invalid_base_work_operation"
	var keys:Array=op.keys();keys.sort()
	match str(op.get("action","")):
		"TICK","CANCEL":
			if keys!=["action"]:return "invalid_base_work_operation"
		"UPGRADE":
			if keys!=["action","type_id"] or op.get("type_id") not in ["STORAGE","LODGE","CLINIC"]:
				return "invalid_base_work_operation"
		"BUILD":
			if keys!=["action","tile_origin","type_id"] or op.get("type_id") not in Settlement.CONSTRUCTIBLE_TYPES \
					or not op.get("tile_origin") is Array or op.tile_origin.size()!=2:return "invalid_base_work_operation"
			for n in op.tile_origin:
				if not (n is int or n is float and n==floor(n)) or n<0 or n>=16:return "invalid_base_work_operation"
		_:return "invalid_base_work_operation"
	return ""
