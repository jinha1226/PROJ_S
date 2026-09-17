extends RefCounted
const Loader=preload("res://sim/json_content_loader.gd")
const Handcrafted=preload("res://sim/handcrafted_room_templates.gd")
static var CONFIG:Dictionary=Loader.load_document("res://data/content/nine_room_dungeon.json")
const RULESET_ID:="nine-room-dungeon-v1"
const VERSION:=8
const FirstFloor=preload("res://sim/first_floor_stages.gd")
const Catalog=preload("res://sim/stage_catalog.gd")
const SIZE:=8
const DEFAULT_STAGE:={"reinforcements":{"interval_rounds":7,"cap":8,"spawn_edges":["N","E","S","W"]},"objective":{"type":"ELIMINATE","rounds":0,"cell":[-1,-1],"retreat_allowed":true}}
static var generation_count:=0

static func generate(seed:int,floor_index:int=1)->Dictionary:
	if floor_index not in [1,2]:return {}
	generation_count+=1
	var rng:=RandomNumberGenerator.new();rng.seed=seed ^ (floor_index*0x4E494E45)
	var visited:Array=[4,3,5];var edges:Array=[[3,4],[4,5]]
	while visited.size()<9:
		var candidates:Array=[]
		for a in visited:
			if a==4 and edges.filter(func(e):return 4 in e).size()>=3:continue
			for b in neighbors(a):
				if b not in visited:candidates.append([a,b])
		var edge:Array=candidates[rng.randi_range(0,candidates.size()-1)]
		edges.append([mini(edge[0],edge[1]),maxi(edge[0],edge[1])]);visited.append(edge[1])
	var extras:Array=[]
	for a in range(9):
		for b in neighbors(a):
			if a<b and [a,b] not in edges:extras.append([a,b])
	for index in range(mini(int(CONFIG.extra_links),extras.size())):
		var available:Array=extras.filter(func(e):return 4 not in e or edges.filter(func(link):return 4 in link).size()<3)
		if available.is_empty():break
		var chosen:Array=available[rng.randi_range(0,available.size()-1)];edges.append(chosen);extras.erase(chosen)
	edges.sort_custom(func(a,b):return a[0]*9+a[1]<b[0]*9+b[1])
	var distances:Dictionary={4:0};var todo:Array=[4]
	for a in todo:
		for e in edges:
			var b:int=e[1] if e[0]==a else (e[0] if e[1]==a else -1)
			if b>=0 and not distances.has(b):distances[b]=distances[a]+1;todo.append(b)
	var stairs:int=0
	for id in range(9):
		if distances[id]>distances.get(stairs,-1):stairs=id
	var remaining:Array=[]
	for id in range(9):
		if id not in [4,stairs]:remaining.append(id)
	# Fisher-Yates with a dedicated role stream; never consumes combat RNG.
	rng.seed=seed ^ floor_index ^ 0x524F4C45
	for i in range(remaining.size()-1,0,-1):
		var j:int=rng.randi_range(0,i);var temp=remaining[i];remaining[i]=remaining[j];remaining[j]=temp
	var roles:Dictionary={4:"SAFE",stairs:"STAIRS",remaining[0]:"SAFE"}
	for i in range(1,3):roles[remaining[i]]="HAZARD"
	for i in range(3,7):roles[remaining[i]]="COMBAT"
	if floor_index==1:
		edges=FirstFloor.CONTENT.edges.duplicate(true);stairs=1
		for id in range(9):roles[id]=FirstFloor.room(id).role
	var terrain:Array[String]=[];terrain.resize(24*24);terrain.fill("stone_floor")
	var rooms:Array=[];var portals:Array=[];var enemies:Array=[];var supply:Array=[]
	var doors:Array=[];var centers:Array=[]
	for id in range(9):
		var origin:=Vector2i(id%3*8,id/3*8);var exits:Array=[]
		for y in range(8):
			for x in range(8):
				# Only corner obstacles: the full 8x8 is playable, not a 6x6 inset.
				if x in [0,7] and y in [0,7]:terrain[(origin.y+y)*24+origin.x+x]="wall"
		centers.append(origin+Vector2i(3,3))
		var stage:Dictionary=DEFAULT_STAGE.duplicate(true)
		if floor_index==1:
			var authored_stage:Dictionary=FirstFloor.room(id)
			stage={"reinforcements":authored_stage.reinforcements.duplicate(true),"objective":authored_stage.objective.duplicate(true)}
		rooms.append({"room_id":id,"coord":[id%3,id/3],"role":roles[id],"bounds":[origin.x,origin.y,8,8],"exits":exits,"stage":stage})
	for edge in edges:
		var a:int=edge[0];var b:int=edge[1];var delta:=Vector2i(b%3-a%3,b/3-a/3)
		var local_a:=Vector2i(7,3) if delta.x==1 else Vector2i(3,7)
		var local_b:=Vector2i(0,3) if delta.x==1 else Vector2i(3,0)
		var pa:=Vector2i(a%3*8,a/3*8)+local_a;var pb:=Vector2i(b%3*8,b/3*8)+local_b
		var key:="F%d_R%d_R%d"%[floor_index,a,b]
		portals.append({"portal_id":key,"a":a,"b":b,"a_cell":[pa.x,pa.y],"b_cell":[pb.x,pb.y],"direction":[delta.x,delta.y]})
		rooms[a].exits.append(key);rooms[b].exits.append(key);doors.append(pa);doors.append(pb)
	rng.seed=seed ^ floor_index ^ 0x54455252
	var combat_index:=0
	for room in rooms:
		var origin:=Vector2i(room.bounds[0],room.bounds[1])
		if floor_index==1:
			FirstFloor.stamp(terrain,origin,room.room_id)
			var authored:Dictionary=FirstFloor.room(room.room_id)
			room["template_id"]=authored.id;room["template_name"]=authored.name
			room["biome"]=authored.biome;room["hint"]=authored.hint
		if room.role=="COMBAT":
			var template:Dictionary=FirstFloor.room(room.room_id) if floor_index==1 else Handcrafted.stamp(terrain,24,origin,combat_index+floor_index-1)
			combat_index+=1
			room["template_id"]=template.id
			room["template_name"]=template.name
			room["biome"]=template.biome
			if floor_index==1:
				for e in Catalog.wave_enemies(template,0):
					var p:Vector2i=origin+Vector2i(int(e.cell[0]),int(e.cell[1]))
					enemies.append({"position":p,"species_id":str(e.kind),"group_id":"ROOM_%d"%room.room_id,"route_id":"ROOM_%d"%room.room_id})
			else:
				var species:Array=["dcss_orc","dcss_gnoll","goblin"]
				for i in range(mini(species.size(),int(CONFIG.enemies_per_combat_room))):
					var cell:Array=template.enemy_cells[i]
					var p:Vector2i=origin+Vector2i(cell[0],cell[1])
					enemies.append({"position":p,"species_id":species[i],"group_id":"ROOM_%d"%room.room_id,"route_id":"ROOM_%d"%room.room_id})
		elif room.role=="HAZARD":
			if floor_index!=1:
				for p in [Vector2i(4,4),Vector2i(4,5),Vector2i(5,4)]:terrain[(origin.y+p.y)*24+origin.x+p.x]="rubble"
			supply.append(origin+Vector2i(5,5))
	var entry:=Vector2i(11,11);var exit:Vector2i=centers[stairs]
	return {"schema_version":1,"ruleset_id":RULESET_ID,"seed":seed,"floor_index":floor_index,"floor_label":"%d층 · 아홉 구역"%floor_index,"theme_id":"ERODED_BORDER_FOREST" if floor_index==1 else "ASHEN_FOUNDRY","width":24,"height":24,"terrain":terrain,"rooms":rooms,"portals":portals,"edges":edges,"door_positions":doors,"room_centers":centers,"entry_position":entry,"hero_position":entry,"anchor_portal_position":entry,"transition_portal_position":exit,"exit_position":exit,"enemy_roster":enemies,"runtime_enemy_roster":enemies.duplicate(true),"enemy_positions":enemies.map(func(e):return e.position),"supply_positions":supply,"visitor_positions":[Vector2i(12,12)],"landmarks":[],"regions":[],"field_regions":[],"routes":[],"floor_hazards":[],"anchor_portal_clear_radius":3,"planned_contact_count":4,"planned_enemy_count":enemies.size()}

static func neighbors(id:int)->Array:
	var result:Array=[]
	for d in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
		var c:Vector2i=Vector2i(id%3,id/3)+d
		if c.x in range(3) and c.y in range(3):result.append(c.y*3+c.x)
	return result

static func world_layout(seed:int,selected_floor:int=1)->Dictionary:
	var aggregate:Dictionary={"schema_version":1,"ruleset_id":RULESET_ID,"seed":seed,"width":48,"height":24,"terrain":[],"campaign_floors":{},"campaign_floor_indices":[1,2],"hazards":[]}
	aggregate.terrain.resize(48*24);aggregate.terrain.fill("wall")
	for floor in [1,2]:
		var generated:=generate(seed,floor);var offset:=Vector2i((floor-1)*24,0)
		for y in range(24):
			for x in range(24):aggregate.terrain[y*48+offset.x+x]=generated.terrain[y*24+x]
		# Existing immutable two-floor selection contract.
		var translated:Dictionary=preload("res://playtest/campaign_world_map.gd")._translated_floor(compatible(generated),offset)
		translated["nine_rooms"]=generated.rooms.duplicate(true);translated["nine_portals"]=generated.portals.duplicate(true)
		translated["nine_offset"]=[offset.x,offset.y]
		if floor==1:translated["visitor_positions"]=[FirstFloor.npc_position()]
		aggregate.campaign_floors[floor]=translated
	return preload("res://playtest/campaign_world_map.gd").select_floor(aggregate,selected_floor)

static func compatible(g:Dictionary)->Dictionary:
	var copy:Dictionary=g.duplicate(true);copy.rooms=[]
	for r in g.rooms:copy.rooms.append(Rect2i(r.bounds[0],r.bounds[1],8,8))
	return copy
