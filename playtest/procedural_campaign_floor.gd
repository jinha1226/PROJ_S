extends RefCounted
## Original implementation of partitioned rooms, connecting tree and loop links.
## Generator v1 is pinned in living-expedition event version 5 for save replay.
const SIZE:=64
const DIRS:=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
static func generate(seed:int,rules_version:int=5)->Dictionary:
	var rng:=RandomNumberGenerator.new();rng.seed=seed ^ 0x50434731
	var leaves:Array[Rect2i]=[Rect2i(2,2,SIZE-4,SIZE-4)]
	while leaves.size()<14:
		var pick:=-1;var area:=0
		for i in range(leaves.size()):
			var r:Rect2i=leaves[i]
			if maxi(r.size.x,r.size.y)>=22 and r.get_area()>area:pick=i;area=r.get_area()
		if pick<0:break
		var r:Rect2i=leaves[pick];leaves.remove_at(pick)
		var horizontal:bool=r.size.x>r.size.y if abs(r.size.x-r.size.y)>8 else rng.randf()<0.5
		if r.size.x<22:horizontal=false
		if r.size.y<22:horizontal=true
		var extent:int=r.size.x if horizontal else r.size.y
		var cut:int=rng.randi_range(maxi(10,int(extent*0.38)),mini(extent-10,int(extent*0.62)))
		if horizontal:
			leaves.append(Rect2i(r.position,Vector2i(cut,r.size.y)))
			leaves.append(Rect2i(r.position+Vector2i(cut,0),Vector2i(r.size.x-cut,r.size.y)))
		else:
			leaves.append(Rect2i(r.position,Vector2i(r.size.x,cut)))
			leaves.append(Rect2i(r.position+Vector2i(0,cut),Vector2i(r.size.x,r.size.y-cut)))
	var terrain:Array[String]=[];terrain.resize(SIZE*SIZE);terrain.fill("wall")
	var rooms:Array[Rect2i]=[];var centers:Array[Vector2i]=[]
	for leaf in leaves:
		var extent:=Vector2i(rng.randi_range(5,mini(13,leaf.size.x-3)),rng.randi_range(5,mini(13,leaf.size.y-3)))
		var pos:=leaf.position+Vector2i(rng.randi_range(1,leaf.size.x-extent.x-1),rng.randi_range(1,leaf.size.y-extent.y-1))
		var room:=Rect2i(pos,extent);rooms.append(room);centers.append(room.get_center())
		for y in range(pos.y,pos.y+extent.y):
			for x in range(pos.x,pos.x+extent.x):terrain[y*SIZE+x]="stone_floor"
	var edges:Array=[];var joined:Dictionary={0:true}
	while joined.size()<rooms.size():
		var best:=INF;var pair:=Vector2i(-1,-1)
		for a in joined:
			for b in range(rooms.size()):
				if joined.has(b):continue
				var cost:float=centers[a].distance_squared_to(centers[b])
				if cost<best:best=cost;pair=Vector2i(a,b)
		edges.append(pair);joined[pair.y]=true
	var extras:Array=[]
	for a in range(rooms.size()):
		for b in range(a+1,rooms.size()):
			if Vector2i(a,b) not in edges and Vector2i(b,a) not in edges:extras.append(Vector2i(a,b))
	for n in range(mini(3,extras.size())):
		var i:=rng.randi_range(0,extras.size()-1);edges.append(extras[i]);extras.remove_at(i)
	var routes:Array=[]
	for pair in edges:
		var a:Vector2i=centers[pair.x];var b:Vector2i=centers[pair.y]
		var bend:=Vector2i(b.x,a.y) if rng.randf()<0.5 else Vector2i(a.x,b.y)
		_carve(terrain,a,bend);_carve(terrain,bend,b)
		routes.append({"route_id":"LINK_%d"%routes.size(),"label":"통로","points":[a,bend,b]})
	var entrance_index:=rng.randi_range(0,centers.size()-1)
	var entry:Vector2i=centers[entrance_index];var distance:=distances(terrain,entry)
	var exit:Vector2i=entry
	for center in centers:
		if int(distance[center])>int(distance[exit]):exit=center
	var anchor:Vector2i=centers[(entrance_index+1)%centers.size()]
	if anchor==exit:anchor=centers[(entrance_index+2)%centers.size()]
	var roster:Array=[];var groups:Array=[];var supplies:Array[Vector2i]=[];var regions:Array=[]
	var used:Dictionary={entry:true,exit:true,anchor:true}
	for i in range(rooms.size()):
		var room:Rect2i=rooms[i];var c:Vector2i=centers[i]
		regions.append({"region_id":"ROOM_%d"%i,"label":"석실","bounds":[room.position.x,room.position.y,room.size.x,room.size.y]})
		if i==entrance_index:continue
		var candidates:Array[Vector2i]=[]
		for y in range(room.position.y,room.end.y):
			for x in range(room.position.x,room.end.x):
				var p:=Vector2i(x,y)
				if not used.has(p) and int(distance[p])>=12 and p.distance_to(entry)>8:candidates.append(p)
		var species:Array[String]=[];var id:="F1_G%02d"%i
		for k in range(mini(rng.randi_range(1,3),candidates.size())):
			var ix:=rng.randi_range(0,candidates.size()-1);var p:Vector2i=candidates[ix];candidates.remove_at(ix);used[p]=true
			var kind:String=preload("res://sim/dcss_enemy_registry.gd").spawn_species(1,seed,i,k)
			if rules_version>=7 and k==0:kind=["fire_lizard","frost_spider","water_slime","electric_eel"][(groups.size()+posmod(seed,4))%4]
			species.append(kind);roster.append({"position":p,"species_id":kind,"group_id":id,"route_id":"LINK_0"})
		if not species.is_empty():groups.append({"group_id":id,"route_id":"LINK_0","position":[c.x,c.y],"species_ids":species,"optional":true,"anchor_guard":false,"transition_guard":c==exit})
		if not used.has(c) and supplies.size()<5:supplies.append(c);used[c]=true
	return {"schema_version":1,"ruleset_id":"procedural-rooms-v1","procedural_generation":true,
		"floor_index":1,"floor_label":"잊힌 지하 회랑","theme_id":"PROCEDURAL_STONE_DUNGEON",
		"seed":seed,"width":SIZE,"height":SIZE,"terrain":terrain,"rooms":rooms,"room_centers":centers,
		"regions":regions,"field_regions":regions,"routes":routes,"room_links":edges,
		"entry_position":entry,"hero_position":entry,"exit_position":exit,"transition_portal_position":exit,
		"anchor_portal_position":anchor,"anchor_portal_clear_radius":2,"door_positions":[],"hazards":[],
		"material_positions":{"shallow_water":[],"metal":[],"wood_floor":[],"rubble":[]},
		"presentation_material_positions":{"grass":[],"ice":[],"fog":[]},"supply_positions":supplies,
		"encounter_groups":groups,"planned_contact_count":groups.size(),"planned_enemy_count":roster.size(),
		"runtime_enemy_roster":roster,"enemy_roster":roster.duplicate(true),"enemy_positions":roster.map(func(row):return row.position)}
static func _carve(terrain:Array[String],a:Vector2i,b:Vector2i)->void:
	var p:=a
	while true:
		terrain[p.y*SIZE+p.x]="stone_floor"
		if p==b:break
		if p.x!=b.x:p.x+=signi(b.x-p.x)
		else:p.y+=signi(b.y-p.y)
static func distances(terrain:Array[String],start:Vector2i)->Dictionary:
	var queue:Array[Vector2i]=[start];var seen:Dictionary={start:0};var cursor:=0
	while cursor<queue.size():
		var p:Vector2i=queue[cursor];cursor+=1
		for d in DIRS:
			var n:Vector2i=p+d
			if n.x<0 or n.y<0 or n.x>=SIZE or n.y>=SIZE or seen.has(n) or terrain[n.y*SIZE+n.x]=="wall":continue
			seen[n]=int(seen[p])+1;queue.append(n)
	return seen
