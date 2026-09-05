class_name CampaignFloorMap
extends RefCounted

# Authored macro geography with deterministic micro variation.  The large
# regions and three route identities stay readable between expeditions while
# thickets, rubble and scenic cells vary with the world seed.
const SCHEMA_VERSION := 1
const RULESET_ID := "campaign-floor-regions-v1"
const FLOOR_ONE_SIZE := Vector2i(160, 160)
const FLOOR_TWO_SIZE := Vector2i(192, 192)
const PORTAL_CLEAR_RADIUS := 8

const _FLOOR_PROFILES := {
	1:{
		"theme_id":"ERODED_BORDER_FOREST",
		"label":"침식된 변경 숲",
		"size":FLOOR_ONE_SIZE,
		"entry":Vector2i(12, 80),
		"anchor_portal":Vector2i(78, 76),
		"transition_portal":Vector2i(146, 28),
		"contact_count":13,
		"enemy_count":39,
		"regions":[
			["BORDER_GATE","변경 관문",4,60,32,42],
			["ERODED_WOODS","침식숲",30,42,54,64],
			["ABANDONED_HAMLET","버려진 촌락",78,58,34,42],
			["FLOODED_ORCHARD","침수 과수원",28,108,54,40],
			["OLD_QUARRY","옛 채굴터",82,108,42,38],
			["RELAY_RUINS","중계 유적",116,12,38,54],
		],
	},
	2:{
		"theme_id":"ASH_WASTE_FOUNDRY",
		"label":"잿빛 황무지와 함몰 주조장",
		"size":FLOOR_TWO_SIZE,
		"entry":Vector2i(14, 96),
		"anchor_portal":Vector2i(96, 102),
		"transition_portal":Vector2i(178, 36),
		"contact_count":15,
		"enemy_count":47,
		"regions":[
			["ASH_GATE","잿빛 관문",4,76,34,42],
			["ASH_PLAIN","잿빛 평원",34,58,62,70],
			["BROKEN_VIADUCT","붕괴 고가로",38,12,72,42],
			["WATCH_POSTS","감시 초소",108,18,42,42],
			["DRAINAGE_TRENCH","폐배수로",36,132,72,48],
			["SLAG_FIELD","슬래그 지대",108,116,54,58],
			["SUNKEN_FOUNDRY","함몰 주조장",146,20,40,76],
		],
	},
}


static func generate(floor_index:int, seed:int)->Dictionary:
	if not _FLOOR_PROFILES.has(floor_index): return {}
	var profile:Dictionary=_FLOOR_PROFILES[floor_index]
	var size:Vector2i=profile.size
	var terrain:Array[String]=[]
	terrain.resize(size.x*size.y);terrain.fill("stone_floor")
	_carve_border(terrain,size)
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed ^ (0x464C4F4F525F5631+floor_index*104729)
	if floor_index==1:
		_place_forest_thickets(terrain,size,rng)
	else:
		_place_waste_ridges(terrain,size,rng)
	var routes:Array[Dictionary]=_route_definitions(floor_index,profile)
	for route in routes:
		_carve_polyline(terrain,size,route.points,3)
	var entry:Vector2i=profile.entry
	var anchor:Vector2i=profile.anchor_portal
	var transition:Vector2i=profile.transition_portal
	for position in [entry,anchor,transition]:_carve_disc(terrain,size,position,4,"stone_floor")
	var material_positions:={"shallow_water":[],"metal":[],"wood_floor":[],"rubble":[]}
	var presentation_positions:={"grass":[],"ice":[],"fog":[]}
	if floor_index==1:
		_paint_rect_material(terrain,size,Rect2i(34,116,42,24),"shallow_water",
			seed+11,3,material_positions.shallow_water)
		_paint_rect_material(terrain,size,Rect2i(88,116,30,22),"rubble",
			seed+17,2,material_positions.rubble)
		_paint_scenic(terrain,size,Rect2i(28,38,86,74),"grass",seed+23,
			presentation_positions.grass)
	else:
		_paint_rect_material(terrain,size,Rect2i(48,140,52,26),"shallow_water",
			seed+31,4,material_positions.shallow_water)
		_paint_rect_material(terrain,size,Rect2i(112,124,42,38),"rubble",
			seed+37,2,material_positions.rubble)
		_paint_rect_material(terrain,size,Rect2i(150,28,28,58),"metal",
			seed+41,2,material_positions.metal)
		_paint_scenic(terrain,size,Rect2i(42,62,90,60),"fog",seed+43,
			presentation_positions.fog)
	# Objectives and authored contacts always win over decorative painting.
	for route in routes:_carve_polyline(terrain,size,route.points,2)
	for position in [entry,anchor,transition]:_carve_disc(terrain,size,position,3,"stone_floor")
	var encounter_groups:=_encounter_groups(floor_index,profile,routes,terrain,size,seed)
	# Every authored group is materialized once, but the runtime activates only
	# the nearby group. Keeping the complete floor roster in the deterministic
	# map manifest makes save replay independent from the order in which routes
	# are explored.
	var runtime_roster:Array[Dictionary]=_runtime_enemy_roster(
		encounter_groups,terrain,size)
	var region_rows:Array[Dictionary]=[]
	var rooms:Array[Rect2i]=[];var room_centers:Array[Vector2i]=[]
	for value in profile.regions:
		var bounds:=Rect2i(int(value[2]),int(value[3]),int(value[4]),int(value[5]))
		rooms.append(bounds);room_centers.append(bounds.get_center())
		region_rows.append({"region_id":str(value[0]),"label":str(value[1]),
			"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]})
	var supply_positions:=_supply_positions(floor_index)
	for position in supply_positions:_carve_disc(terrain,size,position,1,"stone_floor")
	return {
		"schema_version":SCHEMA_VERSION,"ruleset_id":RULESET_ID,
		"floor_index":floor_index,"theme_id":str(profile.theme_id),
		"floor_label":str(profile.label),"seed":seed,"width":size.x,"height":size.y,
		"terrain":terrain,"rooms":rooms,"room_centers":room_centers,
		"regions":region_rows,"routes":routes,
		"entry_position":entry,"hero_position":entry,
		"anchor_portal_position":anchor,
		"anchor_portal_clear_radius":PORTAL_CLEAR_RADIUS,
		"transition_portal_position":transition,"exit_position":transition,
		"door_positions":[],"hazards":_hazards(floor_index,material_positions),
		"material_positions":material_positions,
		"presentation_material_positions":presentation_positions,
		"field_regions":region_rows,"encounter_groups":encounter_groups,
		"planned_contact_count":int(profile.contact_count),
		"planned_enemy_count":int(profile.enemy_count),
		"runtime_enemy_roster":runtime_roster,
		"enemy_roster":runtime_roster.duplicate(true),
		"enemy_positions":runtime_roster.map(func(row):return row.position),
		"supply_positions":supply_positions,
	}.duplicate(true)


static func floor_size(floor_index:int)->Vector2i:
	return _FLOOR_PROFILES[floor_index].size if _FLOOR_PROFILES.has(floor_index) \
		else Vector2i.ZERO


static func _route_definitions(floor_index:int,profile:Dictionary)->Array[Dictionary]:
	var entry:Vector2i=profile.entry;var exit:Vector2i=profile.transition_portal
	if floor_index==1:
		return [
			{"route_id":"NORTH_RIDGE","label":"폐관문·정찰 능선",
				"risk":"AMBUSH","points":[entry,Vector2i(34,58),Vector2i(70,30),
				Vector2i(112,30),exit]},
			{"route_id":"CENTRAL_WOODS","label":"침식숲·폐촌",
				"risk":"BALANCED","points":[entry,Vector2i(44,80),Vector2i(78,76),
				Vector2i(108,64),exit]},
			{"route_id":"SOUTH_MARSH","label":"습지·채굴터",
				"risk":"HAZARD_LOOT","points":[entry,Vector2i(38,126),Vector2i(88,132),
				Vector2i(124,104),exit]},
		]
	return [
		{"route_id":"NORTH_VIADUCT","label":"붕괴 고가로·감시 초소",
			"risk":"COVERED","points":[entry,Vector2i(42,70),Vector2i(64,30),
			Vector2i(120,34),exit]},
		{"route_id":"CENTRAL_ASH","label":"잿빛 평원·폐철도",
			"risk":"EXPOSED","points":[entry,Vector2i(54,94),Vector2i(96,102),
			Vector2i(136,80),exit]},
		{"route_id":"SOUTH_DRAIN","label":"폐배수로·슬래그 지대",
			"risk":"HAZARD_LOOT","points":[entry,Vector2i(48,150),Vector2i(112,154),
			Vector2i(152,126),exit]},
	]


static func _encounter_groups(floor_index:int,profile:Dictionary,routes:Array[Dictionary],
		terrain:Array[String],size:Vector2i,seed:int)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var count:int=int(profile.contact_count);var remaining:int=int(profile.enemy_count)
	for index in range(count):
		var route:Dictionary=routes[index%routes.size()]
		var points:Array=route.points
		var segment:=1+posmod(index/routes.size(),points.size()-1)
		var anchor_guard:=index==count-2
		var transition_guard:=index==count-1
		# Keep the first combat group outside the entrance/tutorial pocket.  The
		# player can inspect gear and resolve the wounded-traveller beat without
		# background time costs pulling enemies into combat immediately.
		var position:Vector2i
		if index==0:position=profile.entry+Vector2i(28,0)
		elif anchor_guard:position=profile.anchor_portal+Vector2i(3,0)
		elif transition_guard:position=profile.transition_portal+Vector2i(-3,2)
		else:
			position=points[mini(segment,points.size()-1)]
			var offset_rank:=posmod(seed+index*17,7)-3
			position+=Vector2i(offset_rank,(index%3)-1)
		position.x=clampi(position.x,2,size.x-3);position.y=clampi(position.y,2,size.y-3)
		_carve_disc(terrain,size,position,2,"stone_floor")
		var groups_left:=count-index
		var group_size:=clampi(int(ceil(float(remaining)/float(groups_left))),2,5)
		remaining-=group_size
		var species_ids:Array[String]=[]
		for member_index in range(group_size):
			species_ids.append("kobold" if (index+member_index+floor_index)%4==0 else "goblin")
		result.append({"group_id":"F%d_G%02d"%[floor_index,index+1],
			"route_id":str(route.route_id),"position":[position.x,position.y],
			"species_ids":species_ids,"optional":false,
			"anchor_guard":anchor_guard,"transition_guard":transition_guard})
	return result


static func _supply_positions(floor_index:int)->Array[Vector2i]:
	var result:Array[Vector2i]=[]
	result.assign([Vector2i(38,88),Vector2i(68,120),Vector2i(98,70),
		Vector2i(116,122),Vector2i(136,46)] if floor_index==1 else [
		Vector2i(44,104),Vector2i(72,38),Vector2i(88,154),Vector2i(122,92),
		Vector2i(142,142),Vector2i(164,62)])
	return result


static func _runtime_enemy_roster(groups:Array[Dictionary],terrain:Array[String],
		size:Vector2i)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var occupied:Dictionary={}
	var offsets:Array[Vector2i]=[
		Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i(1,1),
		Vector2i.LEFT,Vector2i.UP,Vector2i(-1,-1),Vector2i(1,-1),
		Vector2i(-1,1),Vector2i(2,0),Vector2i(0,2),Vector2i(-2,0),
		Vector2i(0,-2),Vector2i(2,1),Vector2i(1,2),Vector2i(-2,1)]
	for group_value in groups:
		var group:Dictionary=group_value
		var center:=Vector2i(int(group.position[0]),int(group.position[1]))
		for species_id_value in group.species_ids:
			var spawn:=Vector2i(-1,-1)
			for offset in offsets:
				var candidate:=center+offset
				if candidate.x<1 or candidate.y<1 or candidate.x>=size.x-1 \
						or candidate.y>=size.y-1 or occupied.has(candidate):
					continue
				if terrain[candidate.y*size.x+candidate.x]=="wall":continue
				spawn=candidate;break
			if spawn==Vector2i(-1,-1):return []
			occupied[spawn]=true
			_carve_disc(terrain,size,spawn,1,"stone_floor")
			result.append({"position":spawn,"species_id":str(species_id_value),
				"group_id":str(group.group_id),"route_id":str(group.route_id)})
	return result


static func _hazards(floor_index:int,materials:Dictionary)->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	var water:Array=materials.get("shallow_water",[])
	var metal:Array=materials.get("metal",[])
	if not water.is_empty():rows.append({"kind":"WETNESS","position":water[0],
		"magnitude":55 if floor_index==1 else 70})
	if floor_index==2 and not metal.is_empty():rows.append({"kind":"WETNESS",
		"position":metal[0],"magnitude":65})
	return rows


static func _carve_border(terrain:Array[String],size:Vector2i)->void:
	for x in range(size.x):
		terrain[x]="wall";terrain[(size.y-1)*size.x+x]="wall"
	for y in range(size.y):
		terrain[y*size.x]="wall";terrain[y*size.x+size.x-1]="wall"


static func _place_forest_thickets(terrain:Array[String],size:Vector2i,
		rng:RandomNumberGenerator)->void:
	for _index_value in range(115):
		var center:=Vector2i(rng.randi_range(10,size.x-11),rng.randi_range(8,size.y-9))
		var radius:=Vector2i(rng.randi_range(3,8),rng.randi_range(3,7))
		_paint_ellipse(terrain,size,center,radius,"wall")


static func _place_waste_ridges(terrain:Array[String],size:Vector2i,
		rng:RandomNumberGenerator)->void:
	for _index_value in range(72):
		var center:=Vector2i(rng.randi_range(12,size.x-13),rng.randi_range(10,size.y-11))
		var radius:=Vector2i(rng.randi_range(3,10),rng.randi_range(2,5))
		_paint_ellipse(terrain,size,center,radius,"wall")


static func _paint_ellipse(terrain:Array[String],size:Vector2i,center:Vector2i,
		radius:Vector2i,terrain_id:String)->void:
	for y in range(center.y-radius.y,center.y+radius.y+1):
		for x in range(center.x-radius.x,center.x+radius.x+1):
			if x<=0 or y<=0 or x>=size.x-1 or y>=size.y-1:continue
			var dx:=x-center.x;var dy:=y-center.y
			if dx*dx*radius.y*radius.y+dy*dy*radius.x*radius.x \
					<=radius.x*radius.x*radius.y*radius.y:
				terrain[y*size.x+x]=terrain_id


static func _carve_polyline(terrain:Array[String],size:Vector2i,points:Array,
		radius:int)->void:
	for index in range(1,points.size()):
		var from:Vector2i=points[index-1];var to:Vector2i=points[index]
		var steps:=maxi(absi(to.x-from.x),absi(to.y-from.y))
		for step in range(steps+1):
			var t:=float(step)/float(maxi(1,steps))
			_carve_disc(terrain,size,Vector2i(roundi(lerpf(from.x,to.x,t)),
				roundi(lerpf(from.y,to.y,t))),radius,"stone_floor")


static func _carve_disc(terrain:Array[String],size:Vector2i,center:Vector2i,
		radius:int,terrain_id:String)->void:
	for y in range(center.y-radius,center.y+radius+1):
		for x in range(center.x-radius,center.x+radius+1):
			if x<=0 or y<=0 or x>=size.x-1 or y>=size.y-1:continue
			if absi(x-center.x)+absi(y-center.y)<=radius+1:
				terrain[y*size.x+x]=terrain_id


static func _paint_rect_material(terrain:Array[String],size:Vector2i,bounds:Rect2i,
		terrain_id:String,salt:int,modulus:int,out:Array)->void:
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var position:=Vector2i(x,y)
			if x<=0 or y<=0 or x>=size.x-1 or y>=size.y-1 \
					or terrain[y*size.x+x]=="wall":continue
			if posmod(x*31+y*17+salt,modulus)==0:
				terrain[y*size.x+x]=terrain_id;out.append(position)


static func _paint_scenic(terrain:Array[String],size:Vector2i,bounds:Rect2i,
		_material_id:String,salt:int,out:Array)->void:
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			if x<=0 or y<=0 or x>=size.x-1 or y>=size.y-1 \
					or terrain[y*size.x+x]=="wall":continue
			if posmod(x*19+y*29+salt,5)==0:out.append(Vector2i(x,y))
