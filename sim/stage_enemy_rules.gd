extends RefCounted
const Rooms=preload("res://sim/room_transition_rules.gd")
static var DATA:Dictionary=preload("res://sim/json_content_loader.gd").load_document("res://data/content/stage_enemy_roles.json")
static func profile(w,id:int)->Dictionary:
	if not Rooms.enabled(w) or id not in w.party_encounter.enemy_ids:return {}
	return DATA.get(w.entities[id].species_id,{"label":"전사","move":2,"min":1,"max":1,"pattern":"SINGLE"})
static func line(w,origin:Vector2i,target:Vector2i)->bool:
	return Rooms.same_room(w,origin,target) and preload("res://sim/combat_kernel.gd").sees(origin,target,w.combat_solid,maxi(1,ceili(Vector2(target-origin).length())))
static func aimable(w,origin:Vector2i,target:Vector2i,p:Dictionary)->bool:
	var d:=Rooms.distance(origin,target)
	return d>=int(p.min) and d<=int(p.max) and line(w,origin,target)
static func cells(w,id:int,origin:Vector2i,target:Vector2i)->Array[Vector2i]:
	var p:=profile(w,id);var result:Array[Vector2i]=[]
	if p.is_empty() or not aimable(w,origin,target,p):return result
	var candidates:Array[Vector2i]=[target]
	if p.pattern=="CROSS":
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:candidates.append(target+d)
	elif p.pattern=="SWEEP":
		var direction:=Vector2i(signi(target.x-origin.x),signi(target.y-origin.y))
		var ring:Array[Vector2i]=[Vector2i.UP,Vector2i(1,-1),Vector2i.RIGHT,Vector2i(1,1),Vector2i.DOWN,Vector2i(-1,1),Vector2i.LEFT,Vector2i(-1,-1)]
		var index:=ring.find(direction)
		candidates=[origin+ring[(index+7)%8],target,origin+ring[(index+1)%8]]
	for cell in candidates:
		if Rooms.current(w,cell) and cell!=origin and Rooms.Terrain.definition_view(w.tile_at(cell).terrain).get("passable",false) and line(w,origin,cell):result.append(cell)
	return result
static func forecast(coordinator,id:int,target,base:Dictionary)->Dictionary:
	var w=coordinator.world;var p:=profile(w,id)
	if p.is_empty():return {}
	var origin:Vector2i=w.entities[id].position
	base.reason="stage_reposition"
	if aimable(w,origin,target.position,p):
		base.action_type="MELEE";base.reason="stage_"+str(p.pattern).to_lower();return base
	# Find firing positions as well as melee positions, including backing away
	# from a target inside an archer's minimum range. Bounded to this 8x8 room.
	var goals:Array=[];var bounds:=Rooms.bounds(w)
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var cell:=Vector2i(x,y)
			if aimable(w,cell,target.position,p):goals.append(cell)
	var route:Dictionary=coordinator.pathfinder.find_path_to_any(id,goals,{},12)
	if route.get("found",false) and route.path.size()>1:
		var next:Vector2i=route.path[1];var assessment=coordinator.movement.assess_move(id,next)
		if assessment.accepted:
			base.action_type="MOVE";base.destination=[next.x,next.y];base.terrain_id=assessment.terrain_id
	return base
