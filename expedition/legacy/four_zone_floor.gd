extends RefCounted
## Fixed decision graph, seeded room interiors. Geometry RNG is presentation-local.
const SIZE:=48
const RULESET_ID:="four-zone-mobile-v1"
static func generate(depth:int,seed:int)->Dictionary:
	if depth not in [1,2]:return {}
	var rng:=RandomNumberGenerator.new();rng.seed=seed ^ (depth*104729)
	var terrain:Array[String]=[];terrain.resize(SIZE*SIZE);terrain.fill("wall")
	var rooms:Array[Rect2i]=[Rect2i(2,18,12,13),Rect2i(15,3,16,16),Rect2i(15,29,16,16),Rect2i(34,16,12,17)]
	var entry:=Vector2i(5,24);var exit:=Vector2i(42,24);var anchor:=Vector2i(23,24)
	var centers:Array[Vector2i]=[];var regions:Array[Dictionary]=[]
	var labels:=["입구 야영지","바위 회랑","침수 저장고","심부 관문"]
	var region_ids:=["ENTRY_CAMP","STONE_HUNT","FLOODED_HUNT","DEEP_GATE"]
	for i in range(rooms.size()):
		var room:=rooms[i];centers.append(room.get_center())
		for y in range(room.position.y,room.end.y):
			for x in range(room.position.x,room.end.x):terrain[y*SIZE+x]="stone_floor"
		if i>0:
			for n in range(10):
				var p:=Vector2i(rng.randi_range(room.position.x+2,room.end.x-3),rng.randi_range(room.position.y+2,room.end.y-3))
				terrain[p.y*SIZE+p.x]="rubble" if i!=2 else "shallow_water"
		regions.append({"region_id":region_ids[i],"label":labels[i],"bounds":[room.position.x,room.position.y,room.size.x,room.size.y]})
	var routes:Array[Dictionary]=[
		{"route_id":"UPPER","label":"바위 회랑","points":[entry,Vector2i(10,24),Vector2i(10,11),Vector2i(40,11),exit]},
		{"route_id":"LOWER","label":"침수 저장고","points":[entry,Vector2i(10,24),Vector2i(10,37),Vector2i(40,37),exit]},
		{"route_id":"CROSS","label":"사냥터 연결로","points":[Vector2i(23,11),anchor,Vector2i(23,37)]}]
	for route in routes:
		for i in range(1,route.points.size()):
			var p:Vector2i=route.points[i-1];var end:Vector2i=route.points[i]
			while p!=end:
				clear(terrain,p,1)
				p+=Vector2i(signi(end.x-p.x),signi(end.y-p.y))
			clear(terrain,end,1)
	var supplies:Array[Vector2i]=[Vector2i(8,27),Vector2i(27,7),Vector2i(27,41),Vector2i(42,29)]
	var groups:Array[Dictionary]=[];var roster:Array[Dictionary]=[]
	var positions:Array[Vector2i]=[Vector2i(13,11),Vector2i(25,13),Vector2i(19,35),Vector2i(27,38),Vector2i(36,24)]
	for i in range(positions.size()):
		var p:=positions[i];clear(terrain,p,2)
		var species:Array[String]=[]
		var count:=1 if i==0 else (2 if depth==1 else 3)
		for j in range(count):
			var id:=preload("res://expedition/legacy/dcss_enemy_registry.gd").spawn_species(depth,seed,i,j)
			species.append(id)
			roster.append({"position":p+Vector2i(j,0),"species_id":id,"group_id":"F%d_G%02d"%[depth,i+1],"route_id":"UPPER" if i<2 else "LOWER" if i<4 else "DEEP"})
		groups.append({"group_id":"F%d_G%02d"%[depth,i+1],"route_id":"UPPER" if i<2 else "LOWER" if i<4 else "DEEP","position":[p.x,p.y],"species_ids":species,"optional":i in [1,2,3],"anchor_guard":false,"transition_guard":i==4})
	var camp:=Vector2i(8,24);var relic:=Vector2i(23,24)
	var visitors:Array[Vector2i]=[Vector2i(9,25),Vector2i(19,8),Vector2i(20,40)]
	for p in supplies+visitors+[entry,exit,anchor]:clear(terrain,p,1)
	var tactical_obstacles:=preload("res://expedition/legacy/tactical_terrain_layout.gd").apply(
		terrain,SIZE,rooms,routes,supplies+visitors+positions+[entry,exit,anchor,camp,relic],seed)
	var materials:={"shallow_water":[],"metal":[],"wood_floor":[],"rubble":[]}
	for y in range(SIZE):
		for x in range(SIZE):
			var material:String=terrain[y*SIZE+x]
			if materials.has(material):materials[material].append(Vector2i(x,y))
	return {"schema_version":1,"ruleset_id":RULESET_ID,"floor_index":depth,"theme_id":"FOUR_ZONE_DUNGEON","floor_label":"갈림길 미궁" if depth==1 else "심부 갈림길",
		"seed":seed,"width":SIZE,"height":SIZE,"terrain":terrain,"rooms":rooms,"room_centers":centers,"regions":regions,"field_regions":regions.duplicate(true),"routes":routes,
		"entry_position":entry,"hero_position":entry,"anchor_portal_position":anchor,"anchor_portal_clear_radius":2,"transition_portal_position":exit,"exit_position":exit,
		"door_positions":[],"hazards":[],"tactical_obstacles":tactical_obstacles,"material_positions":materials,"presentation_material_positions":{"grass":[],"ice":[],"fog":[]},
		"encounter_groups":groups,"planned_contact_count":groups.size(),"planned_enemy_count":roster.size(),"runtime_enemy_roster":roster,"enemy_roster":roster.duplicate(true),"enemy_positions":roster.map(func(row):return row.position),"supply_positions":supplies,
		"landmarks":[{"kind":"CAMP","label":"도움이 필요한 모험가","position":camp},{"kind":"RELIC","label":"갈림길 중계석","position":relic}],"visitor_positions":visitors}

static func clear(terrain:Array[String],center:Vector2i,radius:int)->void:
	for y in range(center.y-radius,center.y+radius+1):
		for x in range(center.x-radius,center.x+radius+1):
			if x>0 and y>0 and x<SIZE-1 and y<SIZE-1:terrain[y*SIZE+x]="stone_floor"
