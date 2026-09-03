class_name DeterministicDungeonMap
extends RefCounted

# Product dungeons deliberately outgrow the 15x15 camera.  The generator uses
# its own RNG, so building presentation geometry never consumes simulation RNG.
const SCHEMA_VERSION := 1
const RULESET_ID := "sector-rooms-snake-v4-clustered-field-regions"
const PREVIOUS_RULESET_ID := "sector-rooms-snake-v3-96x96-large-chambers"
const LEGACY_RULESET_ID := "sector-rooms-snake-v2-opening-encounter"
const MIN_SIZE := 32
const DEFAULT_WIDTH := 96
const DEFAULT_HEIGHT := 96
const LEGACY_WIDTH := 48
const LEGACY_HEIGHT := 48
const _MATERIAL_IDS := ["shallow_water", "metal", "wood_floor", "rubble"]
const _AUTHORITY_FIELD_PROFILES := {
	"shallow_water":{"region_id":"FLOODED_CISTERN","label":"침수 저수조"},
	"metal":{"region_id":"BROKEN_FORGE","label":"폐쇄된 주조장"},
	"wood_floor":{"region_id":"BURNT_GALLERY","label":"탄 목재 회랑"},
	"rubble":{"region_id":"COLLAPSED_QUARRY","label":"무너진 채굴실"},
}
const _SCENIC_FIELD_PROFILES := {
	"grass":{"region_id":"OVERGROWN_COURT","label":"잠식된 정원"},
	"ice":{"region_id":"FROZEN_CRYPT","label":"얼어붙은 묘실"},
	"fog":{"region_id":"MIST_GALLERY","label":"안개 회랑"},
}


static func generate(width: int, height: int, seed: int) -> Dictionary:
	return _generate_versioned(width,height,seed,false,false)


# Save migration only. This reproduces the 96x96 v3 terrain that scattered
# material cells across every room before field regions became coherent.
static func generate_previous_product(width:int,height:int,seed:int)->Dictionary:
	return _generate_versioned(width,height,seed,false,true)


# Save migration only. The exact deployed v2 topology remains reproducible so
# an existing snapshot can replay against its original room and door geometry.
static func generate_legacy(width:int,height:int,seed:int)->Dictionary:
	return _generate_versioned(width,height,seed,true,true)


static func _generate_versioned(width:int,height:int,seed:int,
		legacy_small_rooms:bool,legacy_material_scatter:bool)->Dictionary:
	if width < MIN_SIZE or height < MIN_SIZE:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x4D41505F53454544
	var terrain: Array[String] = []
	terrain.resize(width * height)
	terrain.fill("wall")
	# Product worlds use sixteen broad sectors instead of scaling room count with
	# area. The legacy branch retains the deployed 48x48 4x4 partition exactly.
	var columns := clampi(width / 12, 3, 5) if legacy_small_rooms \
		else (4 if width>=64 else 3)
	var rows := clampi(height / 12, 3, 5) if legacy_small_rooms \
		else (4 if height>=64 else 3)
	var sector_width := width / columns
	var sector_height := height / rows
	var rooms: Array[Rect2i] = []
	var centers: Array[Vector2i] = []
	for row_index in range(rows):
		var column_order: Array[int] = []
		for column_index in range(columns):
			column_order.append(column_index)
		if row_index % 2 == 1:
			column_order.reverse()
		for column_index in column_order:
			var sector_left := column_index * sector_width
			var sector_top := row_index * sector_height
			var available_width := mini(sector_width, width - sector_left)
			var available_height := mini(sector_height, height - sector_top)
			var max_room_width:=maxi(5,mini(8 if legacy_small_rooms else 15,
				available_width-(3 if legacy_small_rooms else 4)))
			var max_room_height:=maxi(5,mini(8 if legacy_small_rooms else 15,
				available_height-(3 if legacy_small_rooms else 4)))
			var min_room_width:=5 if legacy_small_rooms else mini(9,max_room_width)
			var min_room_height:=5 if legacy_small_rooms else mini(9,max_room_height)
			var room_width := rng.randi_range(min_room_width,max_room_width)
			var room_height := rng.randi_range(min_room_height,max_room_height)
			var min_x := sector_left + 1
			var max_x := mini(width - room_width - 2,
				sector_left + available_width - room_width - 1)
			var min_y := sector_top + 1
			var max_y := mini(height - room_height - 2,
				sector_top + available_height - room_height - 1)
			var room_x := rng.randi_range(min_x, maxi(min_x, max_x))
			var room_y := rng.randi_range(min_y, maxi(min_y, max_y))
			var room := Rect2i(room_x, room_y, room_width, room_height)
			rooms.append(room)
			centers.append(Vector2i(room.position.x + room.size.x / 2,
				room.position.y + room.size.y / 2))
			_carve_room(terrain, width, room)
	var door_positions: Array[Vector2i] = []
	for index in range(1, centers.size()):
		var from := centers[index - 1]
		var to := centers[index]
		var horizontal_first := rng.randi_range(0, 1) == 0
		if horizontal_first:
			_carve_horizontal(terrain, width, from.x, to.x, from.y)
			_carve_vertical(terrain, width, from.y, to.y, to.x)
		else:
			_carve_vertical(terrain, width, from.y, to.y, from.x)
			_carve_horizontal(terrain, width, from.x, to.x, to.y)
		# Doors are open, passable features.  Keeping them out of terrain authority
		# lets later door rules evolve without changing the generated topology.
		if index % 2 == 1:
			var door := _room_edge_for_corridor(rooms[index - 1], from, to,
				horizontal_first)
			if _inside_border(door, width, height) and door not in door_positions:
				door_positions.append(door)
	var entry := centers[0]
	var exit := centers[centers.size() - 1]
	# The first product encounter is part of the opening readability contract:
	# its source stays authoritative map population, but it begins inside the
	# six-cell LOS window instead of a distant middle-sector room. Prefer five
	# cells of Chebyshev separation (falling back to four or six for tighter room
	# geometry), which avoids immediate detection at radius three.
	var distant_enemy:=centers[mini(centers.size()-2,maxi(2,centers.size()/2))]
	var enemy := _opening_enemy_position(terrain,width,height,entry,exit,
		door_positions,distant_enemy)
	var enemy_roster:Array[Dictionary]=[{"position":enemy,"species_id":"goblin"}]
	if not legacy_small_rooms:
		enemy_roster.append_array(_distributed_enemy_roster(terrain,width,height,
			seed,rooms,entry,exit,door_positions,enemy,10+posmod(seed,3)))
	var enemy_positions:Array[Vector2i]=[]
	var protected := {entry:true, exit:true}
	for enemy_row in enemy_roster:
		var roster_position:Vector2i=enemy_row.position
		enemy_positions.append(roster_position);protected[roster_position]=true
	for door in door_positions:
		protected[door] = true
	var material_positions := {}
	for material_id in _MATERIAL_IDS:
		material_positions[material_id] = []
	var field_regions:Array[Dictionary]=[]
	var presentation_material_positions:={"grass":[],"ice":[],"fog":[]}
	var material_count := clampi(width*height/96,32,96)
	if legacy_material_scatter:
		var material_candidates: Array[Vector2i] = []
		for room_index in range(1, rooms.size() - 1):
			var room: Rect2i = rooms[room_index]
			for y in range(room.position.y + 1, room.end.y - 1):
				for x in range(room.position.x + 1, room.end.x - 1):
					var position := Vector2i(x, y)
					if not protected.has(position):
						material_candidates.append(position)
		_shuffle(material_candidates, rng)
		material_count=mini(material_candidates.size(),maxi(20,width*height/42)) \
			if legacy_small_rooms else mini(material_candidates.size(),material_count)
		for index in range(material_count):
			var position := material_candidates[index]
			var material_id: String = _MATERIAL_IDS[index % _MATERIAL_IDS.size()]
			terrain[_index(position, width)] = material_id
			material_positions[material_id].append(position)
	else:
		field_regions=_place_clustered_field_regions(terrain,width,rooms,protected,
			seed,material_count,material_positions,presentation_material_positions)
	var hazards: Array[Dictionary] = []
	var metal_cells: Array = material_positions["metal"]
	var wood_cells: Array = material_positions["wood_floor"]
	if not metal_cells.is_empty():
		hazards.append({"kind":"WETNESS", "position":metal_cells[0], "magnitude":75})
	if not wood_cells.is_empty():
		hazards.append({"kind":"FIRE", "position":wood_cells[0], "magnitude":55})
	var result:Dictionary={
		"schema_version":SCHEMA_VERSION,
		"ruleset_id":LEGACY_RULESET_ID if legacy_small_rooms else (
			PREVIOUS_RULESET_ID if legacy_material_scatter else RULESET_ID),
		"seed":seed,
		"width":width,
		"height":height,
		"terrain":terrain,
		"rooms":rooms,
		"room_centers":centers,
		"entry_position":entry,
		"hero_position":entry,
		"exit_position":exit,
		"enemy_positions":enemy_positions,
		"door_positions":door_positions,
		"hazards":hazards,
		"material_positions":material_positions,
		"field_regions":field_regions,
		"presentation_material_positions":presentation_material_positions,
	}
	if not legacy_small_rooms:result["enemy_roster"]=enemy_roster
	return result.duplicate(true)


static func _place_clustered_field_regions(terrain:Array[String],width:int,
		rooms:Array[Rect2i],protected:Dictionary,seed:int,material_count:int,
		material_positions:Dictionary,presentation_positions:Dictionary)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var available_rooms:Array[int]=[]
	for room_index in range(1,rooms.size()-1):available_rooms.append(room_index)
	_shuffle_ints(available_rooms,seed ^ 0x4649454C445F5634)
	var room_cursor:=0
	for material_index in range(_MATERIAL_IDS.size()):
		if room_cursor>=available_rooms.size():break
		var material_id:String=_MATERIAL_IDS[material_index]
		var room_index:int=available_rooms[room_cursor];room_cursor+=1
		var room:Rect2i=rooms[room_index]
		var candidates:=_room_floor_candidates(terrain,width,room,protected)
		_sort_field_candidates(candidates,room,seed,material_index+101)
		var requested:=material_count/_MATERIAL_IDS.size() \
			+(1 if material_index<material_count%_MATERIAL_IDS.size() else 0)
		var placed:=mini(requested,candidates.size())
		for index in range(placed):
			var position:Vector2i=candidates[index]
			terrain[_index(position,width)]=material_id
			material_positions[material_id].append(position)
		var profile:Dictionary=_AUTHORITY_FIELD_PROFILES[material_id]
		result.append(_field_region_row(profile,room_index,room,material_id,
			material_id,placed))
	var scenic_ids:Array[String]=["grass","ice","fog"]
	for scenic_index in range(scenic_ids.size()):
		if room_cursor>=available_rooms.size():break
		var material_id:String=scenic_ids[scenic_index]
		var room_index:int=available_rooms[room_cursor];room_cursor+=1
		var room:Rect2i=rooms[room_index]
		var candidates:=_room_floor_candidates(terrain,width,room,protected)
		_sort_field_candidates(candidates,room,seed,scenic_index+211)
		var requested:=clampi(candidates.size()*3/5,18,42)
		var placed:=mini(requested,candidates.size())
		for index in range(placed):
			presentation_positions[material_id].append(candidates[index])
		var profile:Dictionary=_SCENIC_FIELD_PROFILES[material_id]
		result.append(_field_region_row(profile,room_index,room,"stone_floor",
			material_id,placed))
	result.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.room_index)<int(b.room_index))
	return result


static func _room_floor_candidates(terrain:Array[String],width:int,room:Rect2i,
		protected:Dictionary)->Array[Vector2i]:
	var result:Array[Vector2i]=[]
	for y in range(room.position.y+1,room.end.y-1):
		for x in range(room.position.x+1,room.end.x-1):
			var position:=Vector2i(x,y)
			if not protected.has(position) \
					and terrain[_index(position,width)]=="stone_floor":
				result.append(position)
	return result


static func _sort_field_candidates(candidates:Array[Vector2i],room:Rect2i,
		seed:int,salt:int)->void:
	var center:=Vector2i(room.position.x+room.size.x/2,
		room.position.y+room.size.y/2)
	candidates.sort_custom(func(a:Vector2i,b:Vector2i):
		var a_distance:=absi(a.x-center.x)+absi(a.y-center.y)
		var b_distance:=absi(b.x-center.x)+absi(b.y-center.y)
		if a_distance!=b_distance:return a_distance<b_distance
		var a_rank:=_field_cell_rank(seed,salt,a)
		var b_rank:=_field_cell_rank(seed,salt,b)
		return a_rank<b_rank if a_rank!=b_rank else (
			a.y<b.y if a.y!=b.y else a.x<b.x))


static func _field_cell_rank(seed:int,salt:int,position:Vector2i)->int:
	var digest:PackedByteArray=("field-region-v1|%d|%d|%d|%d"%[
		seed,salt,position.x,position.y]).sha256_buffer()
	return ((int(digest[0])&0x7f)<<24)|(int(digest[1])<<16) \
		|(int(digest[2])<<8)|int(digest[3])


static func _field_region_row(profile:Dictionary,room_index:int,room:Rect2i,
		authority_material_id:String,presentation_material_id:String,
		cell_count:int)->Dictionary:
	return {"schema_version":1,"region_id":str(profile.region_id),
		"label":str(profile.label),"room_index":room_index,
		"bounds":[room.position.x,room.position.y,room.size.x,room.size.y],
		"authority_material_id":authority_material_id,
		"presentation_material_id":presentation_material_id,
		"cell_count":cell_count}.duplicate(true)


static func _shuffle_ints(values:Array[int],seed:int)->void:
	var rng:=RandomNumberGenerator.new();rng.seed=seed
	for index in range(values.size()-1,0,-1):
		var swap_index:=rng.randi_range(0,index)
		var value:=values[index];values[index]=values[swap_index]
		values[swap_index]=value


static func _distributed_enemy_roster(terrain:Array[String],width:int,height:int,
		seed:int,rooms:Array[Rect2i],entry:Vector2i,exit:Vector2i,
		door_positions:Array[Vector2i],opening_enemy:Vector2i,
		total_count:int)->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	var occupied:Dictionary={entry:true,exit:true,opening_enemy:true}
	for door in door_positions:occupied[door]=true
	var needed:=maxi(0,total_count-1)
	for slot in range(needed):
		# Walk distinct non-entry sectors before wrapping. A stable seed offset
		# changes which rooms receive the two optional monsters without consuming
		# simulation RNG.
		var room_index:=1+posmod(slot+posmod(seed,rooms.size()-2),rooms.size()-2)
		var room:Rect2i=rooms[room_index]
		var candidates:Array[Vector2i]=[]
		for y in range(room.position.y+1,room.end.y-1):
			for x in range(room.position.x+1,room.end.x-1):
				var candidate:=Vector2i(x,y)
				if occupied.has(candidate) or terrain[_index(candidate,width)]=="wall":continue
				candidates.append(candidate)
		candidates.sort_custom(func(a:Vector2i,b:Vector2i):
			var ar:=_spawn_tie_rank(seed,slot,a);var br:=_spawn_tie_rank(seed,slot,b)
			return ar<br if ar!=br else (a.y<b.y if a.y!=b.y else a.x<b.x))
		if candidates.is_empty():continue
		var selected:Vector2i=candidates[0];occupied[selected]=true
		rows.append({"position":selected,
			"species_id":"kobold" if (slot+1)%3==0 else "goblin"})
	return rows


static func _spawn_tie_rank(seed:int,slot:int,position:Vector2i)->int:
	var digest:PackedByteArray=("dungeon-enemy-v1|%d|%d|%d|%d"%[
		seed,slot,position.x,position.y]).sha256_buffer()
	return ((int(digest[0])&0x7f)<<24)|(int(digest[1])<<16) \
		|(int(digest[2])<<8)|int(digest[3])


static func apply_terrain(world, layout: Dictionary) -> bool:
	if world == null or layout.is_empty() \
			or world.width != int(layout.get("width", 0)) \
			or world.height != int(layout.get("height", 0)):
		return false
	var terrain: Array = layout.get("terrain", [])
	if terrain.size() != world.width * world.height:
		return false
	for y in range(world.height):
		for x in range(world.width):
			if not world.bootstrap_set_terrain(Vector2i(x, y),
					str(terrain[y * world.width + x])):
				return false
	return true


static func apply_hazards(world, layout: Dictionary) -> bool:
	if world == null or layout.is_empty():
		return false
	for row_value in layout.get("hazards", []):
		var row: Dictionary = row_value
		var position: Vector2i = row.get("position", Vector2i(-1, -1))
		var magnitude := int(row.get("magnitude", 0))
		match str(row.get("kind", "")):
			"WETNESS":
				if world.bootstrap_set_wetness(position, magnitude) == null:
					return false
			"FIRE":
				if world.bootstrap_set_fire(position, magnitude) == null:
					return false
			_:
				return false
	return true


static func terrain_at(layout: Dictionary, position: Vector2i) -> String:
	var width := int(layout.get("width", 0))
	var height := int(layout.get("height", 0))
	if position.x < 0 or position.y < 0 or position.x >= width or position.y >= height:
		return ""
	var terrain: Array = layout.get("terrain", [])
	if terrain.size() != width * height:
		return ""
	return str(terrain[_index(position, width)])


static func presentation_material_at(layout:Dictionary,position:Vector2i)->String:
	if terrain_at(layout,position) in ["","wall"]:return ""
	var rows:Variant=layout.get("presentation_material_positions",{})
	if not rows is Dictionary:return ""
	for material_id in ["grass","ice","fog"]:
		var positions:Variant=rows.get(material_id,[])
		if positions is Array and position in positions:return material_id
	return ""


static func field_region_at(layout:Dictionary,position:Vector2i)->Dictionary:
	var rows:Variant=layout.get("field_regions",[])
	if not rows is Array:return {}
	for value in rows:
		if not value is Dictionary:continue
		var bounds:Variant=value.get("bounds",[])
		if bounds is Array and bounds.size()==4 and Rect2i(int(bounds[0]),
				int(bounds[1]),int(bounds[2]),int(bounds[3])).has_point(position):
			return (value as Dictionary).duplicate(true)
	return {}


static func reachable(layout: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	if terrain_at(layout, from) == "wall" or terrain_at(layout, to) == "wall":
		return false
	var frontier: Array[Vector2i] = [from]
	var seen := {from:true}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == to:
			return true
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var candidate: Vector2i = current + direction
			if seen.has(candidate) or terrain_at(layout, candidate) in ["", "wall"]:
				continue
			seen[candidate] = true
			frontier.append(candidate)
	return false


# Pure opening-event anchors. They depend only on the immutable generated layout
# and the world seed, never on simulation RNG consumption or presentation time.
static func opening_event_anchors(layout: Dictionary, world_seed: int) -> Dictionary:
	var entry: Variant = layout.get("entry_position")
	var exit: Variant = layout.get("exit_position")
	if not entry is Vector2i or not exit is Vector2i: return {}
	var route: Array[Vector2i] = _shortest_cardinal_path(layout, entry, exit)
	if route.size() < 4: return {}
	var denominator := route.size() - 1
	var band_start := maxi(1, int(ceil(float(denominator) * 0.35)))
	var band_end := mini(denominator - 1, int(floor(float(denominator) * 0.50)))
	if band_start > band_end: return {}
	var protected: Dictionary = {entry:true, exit:true}
	for position in layout.get("enemy_positions", []): protected[position] = true
	for position in layout.get("door_positions", []): protected[position] = true
	for hazard in layout.get("hazards", []):
		if hazard is Dictionary and hazard.get("position") is Vector2i:
			protected[hazard.position] = true
	var target_index := clampi(int(round(float(denominator) * 0.42)),
		band_start, band_end)
	var goal_index := -1
	for radius in range(0, band_end - band_start + 1):
		for candidate_index in [target_index - radius, target_index + radius]:
			if candidate_index < band_start or candidate_index > band_end: continue
			var candidate: Vector2i = route[candidate_index]
			if not protected.has(candidate):
				goal_index = candidate_index
				break
		if goal_index >= 0: break
	if goal_index < 0: return {}
	var band: Array[Vector2i] = []
	for index in range(band_start, band_end + 1): band.append(route[index])
	# The traveller is not inexplicably collapsed on the threshold. Place them a
	# short, readable 6-10 route steps inside, preferring a side alcove. A fixed
	# step band keeps this an opening beat even on a very long generated route.
	var spawn_band_end := mini(band_start - 2, 10)
	if spawn_band_end < 3: return {}
	var spawn_band_start := mini(spawn_band_end, 6)
	var spawn_target_index := clampi(8, spawn_band_start, spawn_band_end)
	var spawn_route_index := -1
	for radius in range(0, spawn_band_end - spawn_band_start + 1):
		for candidate_index in [spawn_target_index - radius,
				spawn_target_index + radius]:
			if candidate_index < spawn_band_start \
					or candidate_index > spawn_band_end: continue
			if not protected.has(route[candidate_index]):
				spawn_route_index = candidate_index; break
		if spawn_route_index >= 0: break
	if spawn_route_index < 0: return {}
	var route_anchor: Vector2i = route[spawn_route_index]
	var route_cells: Dictionary = {}
	for position in route: route_cells[position] = true
	var spawn_candidates: Array[Vector2i] = []
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var candidate: Vector2i = route_anchor + direction
		if terrain_at(layout, candidate) in ["", "wall"] \
				or protected.has(candidate) or route_cells.has(candidate): continue
		spawn_candidates.append(candidate)
	if spawn_candidates.is_empty(): spawn_candidates.append(route_anchor)
	spawn_candidates.sort_custom(func(a: Vector2i, b: Vector2i):
		var ar := _opening_anchor_rank(world_seed, a)
		var br := _opening_anchor_rank(world_seed, b)
		return ar < br if ar != br else (a.y < b.y if a.y != b.y else a.x < b.x))
	return {"spawn_position":spawn_candidates[0],
		"spawn_route_index":spawn_route_index,
		"convergence_band":band,
		"convergence_goal":route[goal_index],
		"entry_exit_path":route,
		"band_start_index":band_start,
		"band_end_index":band_end,
		"goal_index":goal_index}.duplicate(true)


static func _shortest_cardinal_path(layout: Dictionary, start: Vector2i,
		goal: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if terrain_at(layout, start) in ["", "wall"] \
			or terrain_at(layout, goal) in ["", "wall"]:
		return empty
	var frontier: Array[Vector2i] = [start]
	var seen := {start:true}
	var previous: Dictionary = {}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == goal:
			var path: Array[Vector2i] = [goal]
			var cursor := goal
			while cursor != start:
				cursor = previous[cursor]
				path.push_front(cursor)
			return path
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var candidate: Vector2i = current + direction
			if seen.has(candidate) or terrain_at(layout, candidate) in ["", "wall"]: continue
			seen[candidate] = true
			previous[candidate] = current
			frontier.append(candidate)
	return empty


static func _opening_anchor_rank(world_seed: int, position: Vector2i) -> int:
	var digest: PackedByteArray = ("opening-anchor-v1|%d|%d|%d" % [
		world_seed, position.x, position.y]).sha256_buffer()
	return ((int(digest[0]) & 0x7f) << 24) | (int(digest[1]) << 16) \
		| (int(digest[2]) << 8) | int(digest[3])


static func _opening_enemy_position(terrain:Array[String],width:int,height:int,
		entry:Vector2i,exit:Vector2i,door_positions:Array[Vector2i],
		distant_fallback:Vector2i)->Vector2i:
	var candidates:Array[Vector2i]=[]
	for y in range(maxi(1,entry.y-6),mini(height-1,entry.y+7)):
		for x in range(maxi(1,entry.x-6),mini(width-1,entry.x+7)):
			var candidate:=Vector2i(x,y)
			if candidate==entry or candidate==exit or candidate in door_positions \
					or terrain[_index(candidate,width)]=="wall":continue
			var distance:=maxi(absi(candidate.x-entry.x),absi(candidate.y-entry.y))
			if distance!=5 or not _terrain_line_of_sight(
					terrain,width,entry,candidate):continue
			candidates.append(candidate)
	if candidates.is_empty():
		# Generated sector rooms always provide an opening candidate, but retain a
		# deterministic passable fallback if future topology rules become tighter.
		for fallback_distance in [4,6]:
			for y in range(maxi(1,entry.y-6),mini(height-1,entry.y+7)):
				for x in range(maxi(1,entry.x-6),mini(width-1,entry.x+7)):
					var candidate:=Vector2i(x,y)
					if candidate==entry or candidate==exit or candidate in door_positions \
							or terrain[_index(candidate,width)]=="wall":continue
					if maxi(absi(candidate.x-entry.x),absi(candidate.y-entry.y)) \
							==fallback_distance and _terrain_line_of_sight(
								terrain,width,entry,candidate):candidates.append(candidate)
			if not candidates.is_empty():break
	if candidates.is_empty():return distant_fallback
	candidates.sort_custom(func(a:Vector2i,b:Vector2i):
		var a_axis:=mini(absi(a.x-entry.x),absi(a.y-entry.y))
		var b_axis:=mini(absi(b.x-entry.x),absi(b.y-entry.y))
		# Prefer a cardinal sight line, then stable reading order.
		return a_axis<b_axis if a_axis!=b_axis else (a.y<b.y if a.y!=b.y else a.x<b.x))
	return candidates[0]

static func _terrain_line_of_sight(terrain:Array[String],width:int,
		origin:Vector2i,target:Vector2i)->bool:
	var x0:=origin.x;var y0:=origin.y;var x1:=target.x;var y1:=target.y
	var dx:=absi(x1-x0);var sx:=1 if x0<x1 else -1
	var dy:=-absi(y1-y0);var sy:=1 if y0<y1 else -1
	var error:=dx+dy
	while x0!=x1 or y0!=y1:
		var doubled:=2*error
		if doubled>=dy:error+=dy;x0+=sx
		if doubled<=dx:error+=dx;y0+=sy
		if Vector2i(x0,y0)==target:return true
		if terrain[y0*width+x0]=="wall":return false
	return true


static func _carve_room(terrain: Array[String], width: int, room: Rect2i) -> void:
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			terrain[y * width + x] = "stone_floor"


static func _carve_horizontal(terrain: Array[String], width: int,
		x0: int, x1: int, y: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		terrain[y * width + x] = "stone_floor"


static func _carve_vertical(terrain: Array[String], width: int,
		y0: int, y1: int, x: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		terrain[y * width + x] = "stone_floor"


static func _room_edge_for_corridor(room: Rect2i, from: Vector2i, to: Vector2i,
		horizontal_first: bool) -> Vector2i:
	if horizontal_first and from.x != to.x:
		return Vector2i(room.end.x - 1 if to.x > from.x else room.position.x,
			from.y)
	if from.y != to.y:
		return Vector2i(from.x,
			room.end.y - 1 if to.y > from.y else room.position.y)
	return from


static func _shuffle(values: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := values[index]
		values[index] = values[swap_index]
		values[swap_index] = value


static func _inside_border(position: Vector2i, width: int, height: int) -> bool:
	return position.x > 0 and position.y > 0 \
		and position.x < width - 1 and position.y < height - 1


static func _index(position: Vector2i, width: int) -> int:
	return position.y * width + position.x
