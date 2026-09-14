extends RefCounted
const Generator=preload("res://sim/nine_room_generator.gd")
const Terrain=preload("res://sim/terrain_registry.gd")
static func enabled(w)->bool:
	return w!=null and w.party_encounter!=null and not w.party_encounter.nine_room_floor.is_empty()
static func membership(p:Vector2i)->Vector2i:
	if p.x<0 or p.y<0 or p.x>=48 or p.y>=24:return Vector2i(-1,-1)
	return Vector2i(p.x/24+1,p.y/8*3+(p.x%24)/8)
static func same_room(w,a:Vector2i,b:Vector2i)->bool:
	return not enabled(w) or membership(a)==membership(b)
static func current(w,p:Vector2i)->bool:
	if not enabled(w):return true
	var s:Dictionary=w.party_encounter.nine_room_floor
	return membership(p)==Vector2i(int(s.floor_index),int(s.active_room_id))
static func queued(w,id:int)->bool:
	if not enabled(w):return false
	return w.party_encounter.nine_room_floor.pending_pursuit.any(func(row):return int(row.entity_id)==id)
static func actor_active(w,id:int)->bool:
	return not enabled(w) or w.entities.has(id) and current(w,w.entities[id].position) and not queued(w,id)
static func bounds(w)->Rect2i:
	var s:Dictionary=w.party_encounter.nine_room_floor
	return Rect2i((int(s.floor_index)-1)*24+int(s.active_room_id)%3*8,int(s.active_room_id)/3*8,8,8)
static func current_floor(w)->Dictionary:
	return w.party_encounter.nine_room_floor.floors[int(w.party_encounter.nine_room_floor.floor_index)-1]
static func portals(w)->Array:
	return current_floor(w).portals if enabled(w) else []
static func portal(w,key:String)->Dictionary:
	for p in portals(w):
		if p.portal_id==key:return p
	return {}
static func cell(w,p:Dictionary,room:int)->Vector2i:
	var c:Array=p.a_cell if int(p.a)==room else p.b_cell
	var offset:Array=current_floor(w).offset
	return Vector2i(int(c[0])+int(offset[0]),int(c[1])+int(offset[1]))
static func portal_at(w,destination:Vector2i)->Dictionary:
	if not enabled(w):return {}
	var room:int=w.party_encounter.nine_room_floor.active_room_id
	for p in portals(w):
		if room in [int(p.a),int(p.b)] and cell(w,p,room)==destination:return p
	return {}
static func rejected(reason:String)->Dictionary:
	return {"accepted":false,"reason":reason,"time_cost":0}
static func safe(w,p:Vector2i)->bool:
	if not w.in_bounds(p):return false
	var tile=w.tile_at(p);var def:Dictionary=Terrain.definition_view(tile.terrain)
	return bool(def.get("passable",false)) and tile.fire==0 and tile.wetness==0 and str(tile.terrain) not in ["shallow_water","ice","lava"]
static func arrivals(w,p:Dictionary,target:int,ids:Array,reserved:Array=[])->Array:
	var start:=cell(w,p,target);var offset:=Vector2i((int(current_floor(w).floor_index)-1)*24,0)
	var area:=Rect2i(offset+Vector2i(target%3*8,target/3*8),Vector2i(8,8))
	var candidates:Array=[]
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			var c:=Vector2i(x,y)
			if c in reserved:continue
			if distance(c,start)>int(Generator.CONFIG.arrival_radius) or not safe(w,c):continue
			if not w.occupying_entities_at(c).filter(func(e):return e.id not in ids).is_empty():continue
			# Arrival stays just inside, so one tap cannot bounce back.
			if c==start:continue
			candidates.append(c)
	candidates.sort_custom(func(a,b):return distance(a,start)<distance(b,start) if distance(a,start)!=distance(b,start) else a.y*48+a.x<b.y*48+b.x)
	return candidates.slice(0,ids.size()) if candidates.size()>=ids.size() else []
static func party_ids(w)->Array:
	var party=w.party_encounter;var ids:Array=[]
	for id in party.active_party_member_ids:
		if party.member(id).presence not in ["DEFEATED","EXILED"]:ids.append(id)
	ids.sort();ids.erase(party.protagonist_id);ids.push_front(party.protagonist_id)
	return ids
static func assess(w,actor_id:int,key:String,require_adjacent:bool=false)->Dictionary:
	if not enabled(w):return rejected("room_exit_unavailable")
	var s:Dictionary=w.party_encounter.nine_room_floor;var p:=portal(w,key)
	if actor_id!=w.party_encounter.protagonist_id or p.is_empty() or int(s.active_room_id) not in [int(p.a),int(p.b)]:return rejected("room_exit_invalid")
	var exit:=cell(w,p,int(s.active_room_id));var ids:=party_ids(w)
	for id in ids:
		if not w.can_act(id,w.world_time) or preload("res://sim/abilities/monster_ability_runtime.gd").anchored(w,id):return rejected("room_party_cannot_move")
		if not current(w,w.entities[id].position) or distance(w.entities[id].position,exit)>int(Generator.CONFIG.exit_gather_radius):return rejected("room_party_far")
	if require_adjacent and distance(w.entities[actor_id].position,exit)>1:return rejected("room_exit_not_adjacent")
	var target:int=int(p.b) if int(p.a)==int(s.active_room_id) else int(p.a)
	var cells:=arrivals(w,p,target,ids)
	if cells.is_empty():return rejected("room_arrival_full")
	return {"accepted":true,"reason":"ok","portal_id":key,"source_room":int(s.active_room_id),"target_room":target,"exit_cell":exit,"party_ids":ids,"arrivals":cells,"revision":int(s.revision)}
static func distance(a:Vector2i,b:Vector2i)->int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

static func path_distance(w,origin:Vector2i,target:Vector2i,limit:int)->int:
	var todo:Array=[origin];var lengths:Dictionary={origin:0}
	for p in todo:
		if p==target:return int(lengths[p])
		if lengths[p]>=limit:continue
		for d in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]:
			var c:Vector2i=p+d
			if not same_room(w,origin,c) or lengths.has(c) or not w.in_bounds(c) or not Terrain.definition_view(w.tile_at(c).terrain).get("passable",false) or not w.diagonal_step_terrain_allowed(p,c):continue
			lengths[c]=int(lengths[p])+1;todo.append(c)
	return -1
