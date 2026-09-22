extends RefCounted
## Fixed fight room as a §7 layout so the real floor/session code runs unchanged.
const Builder = preload("res://expedition/encounter_builder.gd")
const DEFAULT_SPEC := {"size":20,"room":[5,5,9,9],"door":[9,4],"pillars":[[8,8],[10,10]],"party_entry":[9,3],"light":90,"members":[]}

static func layout(spec: Dictionary, theme: Dictionary) -> Dictionary:
	var size: int = spec.size
	var terrain: Array = []; terrain.resize(size*size); terrain.fill("wall")
	var rect := Rect2i(spec.room[0],spec.room[1],spec.room[2],spec.room[3])
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x): terrain[y*size+x] = "stone"
	var door := Vector2i(spec.door[0],spec.door[1]); var entry := Vector2i(spec.party_entry[0],spec.party_entry[1])
	var p := entry
	while p != door:
		terrain[p.y*size+p.x] = "stone"; p += Vector2i(signi(door.x-p.x),signi(door.y-p.y))
	terrain[door.y*size+door.x] = "stone"
	var obstacles: Dictionary = {}
	for pillar in spec.pillars:
		var q := Vector2i(pillar[0],pillar[1]); terrain[q.y*size+q.x] = "wall"; obstacles[q] = true
	var members: Array = []
	for row in spec.members:
		var member: Dictionary = Builder.member(Builder.species(row.species_id),row.role)
		if row.has("pos"): member.pos = Vector2i(row.pos[0],row.pos[1])
		members.append(member)
	var floor_cells: Array = []
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			if not obstacles.has(Vector2i(x,y)): floor_cells.append(Vector2i(x,y))
	var unplaced: Array = members.filter(func(m): return not m.has("pos"))
	if not unplaced.is_empty():
		var rng := RandomNumberGenerator.new(); rng.seed = 1
		assert(Builder.place(unplaced,floor_cells,[door],Vector2i(-1,-1),[],obstacles,rng),"arena placement failed")
	var room := {"id":0,"rect":rect,"kind":"fight","template_id":"","rows":[],"parsed":{},"doors":[door],"tier":spec.get("tier","deep"),"spine":true}
	return {"size":size,"seed":0,"theme_id":theme.get("id",""),"depth":int(theme.depth),"terrain":terrain,"rooms":[room],"edges":[],
		"entry":entry,"relic":Vector2i(-1,-1),"features":{},
		"encounters":[{"room":0,"tier":room.tier,"mandatory":true,"budget":0,"members":members}],
		"stats":{"regenerations":0,"relic_distance":0,"max_distance":0}}
