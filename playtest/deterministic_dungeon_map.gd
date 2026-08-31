class_name DeterministicDungeonMap
extends RefCounted

# Product dungeons deliberately outgrow the 15x15 camera.  The generator uses
# its own RNG, so building presentation geometry never consumes simulation RNG.
const SCHEMA_VERSION := 1
const RULESET_ID := "sector-rooms-snake-v3-96x96-large-chambers"
const LEGACY_RULESET_ID := "sector-rooms-snake-v2-opening-encounter"
const MIN_SIZE := 32
const DEFAULT_WIDTH := 96
const DEFAULT_HEIGHT := 96
const LEGACY_WIDTH := 48
const LEGACY_HEIGHT := 48
const _MATERIAL_IDS := ["shallow_water", "metal", "wood_floor", "rubble"]


static func generate(width: int, height: int, seed: int) -> Dictionary:
	return _generate_versioned(width,height,seed,false)


# Save migration only. The exact deployed v2 topology remains reproducible so
# an existing snapshot can replay against its original room and door geometry.
static func generate_legacy(width:int,height:int,seed:int)->Dictionary:
	return _generate_versioned(width,height,seed,true)


static func _generate_versioned(width:int,height:int,seed:int,
		legacy_small_rooms:bool)->Dictionary:
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
	var material_candidates: Array[Vector2i] = []
	for room_index in range(1, rooms.size() - 1):
		var room: Rect2i = rooms[room_index]
		for y in range(room.position.y + 1, room.end.y - 1):
			for x in range(room.position.x + 1, room.end.x - 1):
				var position := Vector2i(x, y)
				if not protected.has(position):
					material_candidates.append(position)
	_shuffle(material_candidates, rng)
	var material_count := mini(material_candidates.size(),maxi(20,width*height/42)) \
		if legacy_small_rooms else mini(material_candidates.size(),
			clampi(width*height/96,32,96))
	for index in range(material_count):
		var position := material_candidates[index]
		var material_id: String = _MATERIAL_IDS[index % _MATERIAL_IDS.size()]
		terrain[_index(position, width)] = material_id
		material_positions[material_id].append(position)
	var hazards: Array[Dictionary] = []
	var metal_cells: Array = material_positions["metal"]
	var wood_cells: Array = material_positions["wood_floor"]
	if not metal_cells.is_empty():
		hazards.append({"kind":"WETNESS", "position":metal_cells[0], "magnitude":75})
	if not wood_cells.is_empty():
		hazards.append({"kind":"FIRE", "position":wood_cells[0], "magnitude":55})
	var result:Dictionary={
		"schema_version":SCHEMA_VERSION,
		"ruleset_id":LEGACY_RULESET_ID if legacy_small_rooms else RULESET_ID,
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
	}
	if not legacy_small_rooms:result["enemy_roster"]=enemy_roster
	return result.duplicate(true)


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
