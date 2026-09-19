extends RefCounted
## Connected, undirected 3x3 graph. Each node owns its persistent 8x8 room.
const SIDE := 3
const KINDS := ["battle", "battle", "battle", "camp", "camp", "loot", "loot"]

static func generate(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rooms: Array = []
	for id in range(9):
		rooms.append({"id":id, "kind":"entry", "name":"폐허 입구", "links":[],
			"tiles":[], "enemies":[], "started":false, "cleared":false,
			"used":false, "feature":Vector2i(4,4)})
	# Randomized spanning tree ensures no isolated rooms; extra edges add loops.
	var reached: Array = [0]
	while reached.size() < 9:
		var frontier: Array = []
		for source in reached:
			for target in neighbors(source):
				if target not in reached: frontier.append([source,target])
		var edge: Array = frontier[rng.randi_range(0,frontier.size()-1)]
		connect_rooms(rooms,edge[0],edge[1]); reached.append(edge[1])
	for source in range(9):
		for target in neighbors(source):
			if target > source and target not in rooms[source].links and rng.randf() < 0.4:
				connect_rooms(rooms,source,target)
	var kinds: Array = KINDS.duplicate()
	for i in range(kinds.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var value = kinds[i]; kinds[i] = kinds[j]; kinds[j] = value
	var names := {"entry":"폐허 입구", "battle":"망령의 방", "camp":"회복의 샘", "loot":"잊힌 보물", "boss":"수문장의 방"}
	for id in range(9):
		var row: Dictionary = rooms[id]
		row.kind = "entry" if id == 0 else "boss" if id == 8 else kinds[id-1]
		row.name = names[row.kind]
		row.cleared = id == 0
		row.links.sort()
		var wet_room := rng.randf() < 0.5
		for y in range(8):
			for x in range(8):
				var terrain := "stone"
				if y == 3: terrain = "wood"
				if x == 5: terrain = "water" if wet_room else "metal"
				if Vector2i(x,y) in [Vector2i(3,2),Vector2i(3,5)]: terrain = "wall"
				if row.kind in ["camp","loot"] and x >= 3 and x <= 5 and y >= 3 and y <= 5:
					terrain = "water" if row.kind == "camp" else "wood"
				row.tiles.append({"terrain":terrain,"fire":0,"wet":70 if terrain == "water" else 0})
	return rooms

static func neighbors(id: int) -> Array:
	var result: Array = []
	if id % 3 > 0: result.append(id-1)
	if id % 3 < 2: result.append(id+1)
	if id >= 3: result.append(id-3)
	if id < 6: result.append(id+3)
	return result

static func connect_rooms(rooms: Array, a: int, b: int) -> void:
	rooms[a].links.append(b); rooms[b].links.append(a)
